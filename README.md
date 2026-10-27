# terraform-aws-privatelink-consumer

Consumer side of AWS PrivateLink for the Tamr API. Run this **in your own AWS account** to reach
the Tamr API privately, without traffic crossing the public internet.

It creates an interface VPC endpoint against Tamr's endpoint service, a security group scoping
which of your subnets may use it, and a Route 53 private hosted zone that shadows your Tamr tenant
domain inside your VPC only.

## Usage

```hcl
module "tamr_api_privatelink" {
  source = "git::https://github.com/Datatamer/terraform-aws-privatelink-consumer.git?ref=v1.0.0"

  vpc_id                = "vpc-0123456789abcdef0"
  subnet_ids            = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  endpoint_service_name = "com.amazonaws.vpce.us-east-1.vpce-svc-0123456789abcdef0"
  allowed_cidrs         = ["10.0.0.0/16"]
  api_domain            = "tamr.cloud"
}
```

Use the endpoint service name and tenant domain Tamr gives you for your region, for example
`tamr.cloud`, or `eu.tamr.cloud`, `uk.tamr.cloud` or `ap.tamr.cloud` outside the US. Your AWS
region must match the region of that endpoint service.

## Onboarding sequence

1. Send Tamr the ARN of the IAM role that will apply this module, or your AWS account ID if you
   can't name a role. Tamr sends back the endpoint service name and the **AZ IDs** the service is
   available in.
2. Apply this module. The endpoint starts in `pendingAcceptance`.
3. Wait for Tamr to accept the connection. Someone at Tamr does this by hand. After that the
   endpoint is `available`, which the module's `vpc_endpoint_state` output shows.
4. Test with `enable_test_client = true` (see below), or from an instance in `allowed_cidrs`:
   ```bash
   dig +short your-tenant.tamr.cloud     # expect endpoint ENI private IPs
   curl -v https://your-tenant.tamr.cloud/
   ```

## What this does to DNS

Inside this VPC, the private hosted zone takes over all of `api_domain`: every name under it, at
any depth, resolves to the endpoint. Resolution outside the VPC is untouched.

An endpoint reaches a single Tamr region. If your tenants are in more than one region, give each
region its own VPC and endpoint.

If you already manage a hosted zone for that domain in this VPC, set
`create_private_hosted_zone = false` and add an alias record yourself, pointing at the
`endpoint_dns_name` output.

## Testing without an instance

`enable_test_client = true` creates a Lambda inside your VPC that makes the request for you,
named `<name>-test-client` (`tamr-api-test-client` with the default `name`):

```hcl
module "tamr_api_privatelink" {
  ...
  enable_test_client = true
  test_client_host   = "your-tenant.tamr.cloud"   # must be one label under api_domain
  test_client_path   = "/api/v1alpha/record/list"
}
```

To control where it logs, for example to set a retention period, pass a log group you own in
`test_client_log_group_name`. Otherwise Lambda creates its default
`/aws/lambda/<name>-test-client` group the first time it runs.

```bash
aws lambda invoke --function-name tamr-api-test-client \
  --payload '{"path": "/api/v1alpha/record/list"}' \
  --cli-binary-format raw-in-base64-out /dev/stdout
```

The response lists each request's status, headers and body, so the result doesn't depend on logs.

| Result in `requests` | Meaning |
|---|---|
| `"status": 403` | **Working end to end.** TLS terminated with the right cert, Tamr routed the request, and the API rejected an unauthenticated request |
| `"status": 404` | Reached Tamr but no route matched — check `test_client_host` is your real tenant hostname |
| `"error": "TimeoutError"` | Connection not accepted yet, or no inbound rule on the endpoint security group |
| `"error": "SSLCertVerificationError"` | The hostname requested is not what the private hosted zone resolves, or `create_private_hosted_zone` is false |

### Several requests on one connection

`count` sends the request that many times over one connection, `interval_seconds` apart. Each entry
in `requests` says whether it reused the connection. For example, to check that a connection
survives five minutes idle:

```bash
aws lambda invoke --function-name tamr-api-test-client \
  --payload '{"count": 2, "interval_seconds": 300}' \
  --cli-binary-format raw-in-base64-out --cli-read-timeout 0 /dev/stdout
```

The whole run must fit in `test_client_timeout`, 900 seconds by default. The AWS CLI stops waiting
after 60 seconds unless you pass `--cli-read-timeout 0`.

The same script runs on your own machine, so you can compare with the public route:

```bash
python3 lambda/api_test_client/index.py https://your-tenant.tamr.cloud/ --count 2 --interval 300
```

## Notes

- **AZ IDs, not names.** AZ names are per-account aliases, so compare your subnets' AZ IDs with
  the ones Tamr sends. A subnet in an AZ the service does not serve fails at apply with
  *"endpoint service does not support the Availability Zone (AZ) for the subnet"*; drop that subnet
  from `subnet_ids`.
- **Your source IP is not visible to Tamr.** Traffic is translated at the endpoint and again at
  Tamr's load balancer. Authorization is entirely at the application layer — your API
  credentials, not your network address.
- **Idle connections.** AWS drops a TCP connection through an endpoint after 350 seconds with no
  traffic, but Tamr keeps connections alive from its side.
- **Cost.** You pay AWS for endpoint hours and data processed, per the standard PrivateLink
  pricing. Tamr does not charge for the connection.

## Development

The test client's Lambda ships prebuilt as `lambda/api_test_client.zip`, so applying the module
needs no build step. After changing `lambda/api_test_client/index.py`, rebuild and commit the zip:

```bash
make lambda/zip
```

`make all` also formats the code and regenerates the inputs and outputs below. It needs `terraform`,
`python3` and [`terraform-docs`](https://terraform-docs.io) v0.24.0. CI runs `make all` on every
pull request and fails if it changes anything.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.2 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0, < 7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0, < 7.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.test_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.test_client_vpc_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_function.test_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_route53_record.wildcard](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_security_group.endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.test_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_endpoint.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_egress_rule.test_client_to_endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.endpoint_from_test_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_cidr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_cloudwatch_log_group.test_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudwatch_log_group) | data source |
| [aws_iam_policy_document.test_client_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_cidrs"></a> [allowed\_cidrs](#input\_allowed\_cidrs) | CIDRs within the consumer VPC permitted to reach the endpoint on 443 | `list(string)` | `[]` | no |
| <a name="input_allowed_security_group_ids"></a> [allowed\_security\_group\_ids](#input\_allowed\_security\_group\_ids) | Security group IDs permitted to reach the endpoint on 443 | `list(string)` | `[]` | no |
| <a name="input_api_domain"></a> [api\_domain](#input\_api\_domain) | Tamr tenant domain to shadow inside this VPC, e.g. tamr.cloud or eu.tamr.cloud | `string` | n/a | yes |
| <a name="input_create_private_hosted_zone"></a> [create\_private\_hosted\_zone](#input\_create\_private\_hosted\_zone) | Create a Route 53 private hosted zone for api\_domain. Set false if you already manage that zone in this VPC and will add the record yourself. | `bool` | `true` | no |
| <a name="input_enable_test_client"></a> [enable\_test\_client](#input\_enable\_test\_client) | Create a Lambda in the VPC that requests the API through the endpoint, for testing the connection | `bool` | `false` | no |
| <a name="input_endpoint_service_name"></a> [endpoint\_service\_name](#input\_endpoint\_service\_name) | Tamr-provided endpoint service name, e.g. com.amazonaws.vpce.us-east-1.vpce-svc-0123456789abcdef0 | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for every resource this module creates | `string` | `"tamr-api"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs for the endpoint ENIs, at most one per AZ | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource that supports them | `map(string)` | `{}` | no |
| <a name="input_test_client_host"></a> [test\_client\_host](#input\_test\_client\_host) | Tenant hostname the test client requests, one label under api\_domain, e.g. your-tenant.tamr.cloud. Required when enable\_test\_client is true. | `string` | `null` | no |
| <a name="input_test_client_log_group_name"></a> [test\_client\_log\_group\_name](#input\_test\_client\_log\_group\_name) | Existing CloudWatch log group the test client writes to. When null, Lambda creates its default /aws/lambda/<name>-test-client group on first invocation, outside Terraform. | `string` | `null` | no |
| <a name="input_test_client_method"></a> [test\_client\_method](#input\_test\_client\_method) | HTTP method the test client uses | `string` | `"GET"` | no |
| <a name="input_test_client_path"></a> [test\_client\_path](#input\_test\_client\_path) | URL path the test client requests | `string` | `"/"` | no |
| <a name="input_test_client_security_group_ids"></a> [test\_client\_security\_group\_ids](#input\_test\_client\_security\_group\_ids) | Additional security groups to attach to the test client, for example one that allows reaching CloudWatch Logs | `list(string)` | `[]` | no |
| <a name="input_test_client_timeout"></a> [test\_client\_timeout](#input\_test\_client\_timeout) | Seconds the test client may run | `number` | `900` | no |
| <a name="input_test_client_verify_tls"></a> [test\_client\_verify\_tls](#input\_test\_client\_verify\_tls) | Whether the test client verifies the API certificate | `bool` | `true` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | Consumer VPC ID to place the endpoint in | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_endpoint_dns_entries"></a> [endpoint\_dns\_entries](#output\_endpoint\_dns\_entries) | All DNS entries (regional plus per-AZ), for debugging resolution |
| <a name="output_endpoint_dns_name"></a> [endpoint\_dns\_name](#output\_endpoint\_dns\_name) | Regional DNS name of the endpoint |
| <a name="output_hosted_zone_id"></a> [hosted\_zone\_id](#output\_hosted\_zone\_id) | ID of the private hosted zone, if this module created it |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group on the endpoint ENIs. Reference this from a client's egress rules. |
| <a name="output_test_client_function_name"></a> [test\_client\_function\_name](#output\_test\_client\_function\_name) | Name of the test client Lambda, for aws lambda invoke |
| <a name="output_test_client_security_group_id"></a> [test\_client\_security\_group\_id](#output\_test\_client\_security\_group\_id) | Security group on the test client, already permitted inbound on the endpoint |
| <a name="output_test_client_url"></a> [test\_client\_url](#output\_test\_client\_url) | URL the test client requests by default |
| <a name="output_vpc_endpoint_id"></a> [vpc\_endpoint\_id](#output\_vpc\_endpoint\_id) | ID of the interface endpoint, for Tamr to accept |
| <a name="output_vpc_endpoint_state"></a> [vpc\_endpoint\_state](#output\_vpc\_endpoint\_state) | pendingAcceptance until Tamr accepts the connection, then available |
<!-- END_TF_DOCS -->
