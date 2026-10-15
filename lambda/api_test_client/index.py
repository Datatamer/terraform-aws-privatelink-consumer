"""Requests the Tamr API through the PrivateLink endpoint and returns the result."""

import json
import os
import ssl
import urllib.error
import urllib.parse
import urllib.request

API_URL = os.environ["API_URL"]
METHOD = os.environ.get("METHOD", "GET")
VERIFY_TLS = os.environ.get("VERIFY_TLS", "true").lower() == "true"


def handler(event, context):
    url = event.get("url")
    if url is None:
        url = API_URL
        path = event.get("path")
        if path:
            url = urllib.parse.urljoin(API_URL, path)

    body = event.get("body")
    data = None
    headers = {}
    if body is not None:
        data = (body if isinstance(body, str) else json.dumps(body)).encode()
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(
        url,
        data=data,
        method=event.get("method", METHOD),
        headers=headers,
    )

    context_kwargs = {}
    if not VERIFY_TLS:
        unverified = ssl.create_default_context()
        unverified.check_hostname = False
        unverified.verify_mode = ssl.CERT_NONE
        context_kwargs["context"] = unverified

    try:
        with urllib.request.urlopen(request, timeout=15, **context_kwargs) as response:
            result = {
                "url": url,
                "status": response.status,
                "headers": dict(response.headers),
                "body": response.read().decode(errors="replace"),
            }
    except urllib.error.HTTPError as err:
        result = {
            "url": url,
            "status": err.code,
            "headers": dict(err.headers),
            "body": err.read().decode(errors="replace"),
        }
    except Exception as err:  # noqa: BLE001 - surface anything else verbatim
        result = {
            "url": url,
            "error": type(err).__name__,
            "detail": str(err),
        }

    print(json.dumps(result, default=str))
    return result
