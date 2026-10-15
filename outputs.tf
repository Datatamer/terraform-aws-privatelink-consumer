output "vpc_endpoint_id" {
  description = "ID of the interface endpoint, for Tamr to accept"
  value       = aws_vpc_endpoint.this.id
}

output "vpc_endpoint_state" {
  description = "pendingAcceptance until Tamr accepts the connection, then available"
  value       = aws_vpc_endpoint.this.state
}

output "endpoint_dns_name" {
  description = "Regional DNS name of the endpoint"
  value       = local.regional_dns_entry.dns_name
}

output "endpoint_dns_entries" {
  description = "All DNS entries (regional plus per-AZ), for debugging resolution"
  value       = aws_vpc_endpoint.this.dns_entry
}

output "security_group_id" {
  description = "Security group on the endpoint ENIs. Reference this from a client's egress rules."
  value       = aws_security_group.endpoint.id
}

output "hosted_zone_id" {
  description = "ID of the private hosted zone, if this module created it"
  value       = var.create_private_hosted_zone ? aws_route53_zone.this[0].zone_id : null
}

output "test_client_function_name" {
  description = "Name of the test client Lambda, for aws lambda invoke"
  value       = var.enable_test_client ? aws_lambda_function.test_client[0].function_name : null
}

output "test_client_security_group_id" {
  description = "Security group on the test client, already permitted inbound on the endpoint"
  value       = var.enable_test_client ? aws_security_group.test_client[0].id : null
}

output "test_client_url" {
  description = "URL the test client requests by default"
  value       = var.enable_test_client ? local.test_client_url : null
}
