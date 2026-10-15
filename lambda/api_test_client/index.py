"""Requests the Tamr API through the PrivateLink endpoint and returns the result.

Runs as: python3 index.py URL [--count N] [--interval SECONDS] [--insecure]
"""

import argparse
import http.client
import json
import os
import select
import ssl
import time
import urllib.parse

TIMEOUT = 15


def tls_context(verify_tls):
    context = ssl.create_default_context()
    if not verify_tls:
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
    return context


def send(url, count=1, interval_seconds=0, method="GET", body=None, verify_tls=True):
    parsed = urllib.parse.urlsplit(url)
    path = parsed.path or "/"
    if parsed.query:
        path += "?" + parsed.query
    data, headers = None, {}
    if body is not None:
        data = (body if isinstance(body, str) else json.dumps(body)).encode()
        headers["Content-Type"] = "application/json"

    conn = http.client.HTTPSConnection(
        parsed.hostname, parsed.port or 443, timeout=TIMEOUT, context=tls_context(verify_tls)
    )
    requests = []
    first_port = None
    try:
        for i in range(count):
            if i > 0:
                time.sleep(interval_seconds)
                # Raise instead of opening a new connection if the old one is gone.
                conn.auto_open = 0
            try:
                if conn.sock is not None and select.select([conn.sock], [], [], 0)[0]:
                    if conn.sock.recv(1) == b"":
                        raise http.client.RemoteDisconnected("server closed the connection")
                conn.request(method, path, body=data, headers=headers)
                port = conn.sock.getsockname()[1]
                response = conn.getresponse()
                requests.append({
                    "status": response.status,
                    "reused_connection": first_port is not None and port == first_port,
                    "headers": dict(response.getheaders()),
                    "body": response.read().decode(errors="replace"),
                })
                first_port = first_port or port
            except Exception as err:  # noqa: BLE001 - surface anything else verbatim
                requests.append({"error": type(err).__name__, "detail": str(err)})
                break
    finally:
        conn.close()
    return {"url": url, "requests": requests}


def handler(event, context):
    api_url = os.environ.get("API_URL", "")
    url = event.get("url")
    if url is None:
        url = api_url
        if event.get("path"):
            url = urllib.parse.urljoin(api_url, event["path"])

    result = send(
        url,
        count=int(event.get("count", 1)),
        interval_seconds=float(event.get("interval_seconds", 0)),
        method=event.get("method", os.environ.get("METHOD", "GET")),
        body=event.get("body"),
        verify_tls=os.environ.get("VERIFY_TLS", "true").lower() == "true",
    )
    print(json.dumps(result, default=str))
    return result


def main():
    parser = argparse.ArgumentParser(description="Send requests to a URL over one connection.")
    parser.add_argument("url")
    parser.add_argument("--count", type=int, default=1, help="requests to send on one connection")
    parser.add_argument("--interval", type=float, default=0, metavar="SECONDS", help="pause between requests")
    parser.add_argument("--method", default="GET")
    parser.add_argument("--insecure", action="store_true", help="skip TLS certificate verification")
    args = parser.parse_args()
    result = send(args.url, args.count, args.interval, args.method, verify_tls=not args.insecure)
    print(json.dumps(result, indent=2, default=str))


if __name__ == "__main__":
    main()
