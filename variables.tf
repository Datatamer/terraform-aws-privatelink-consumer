variable "name" {
  description = "Name prefix for every resource this module creates"
  type        = string
  default     = "tamr-api"
}

variable "vpc_id" {
  description = "Consumer VPC ID to place the endpoint in"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the endpoint ENIs, at most one per AZ"
  type        = list(string)
}

variable "endpoint_service_name" {
  description = "Tamr-provided endpoint service name, e.g. com.amazonaws.vpce.us-east-1.vpce-svc-0123456789abcdef0"
  type        = string
}

variable "allowed_cidrs" {
  description = "CIDRs within the consumer VPC permitted to reach the endpoint on 443"
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "Security group IDs permitted to reach the endpoint on 443"
  type        = list(string)
  default     = []
}

variable "api_domain" {
  description = "Tamr tenant domain to shadow inside this VPC, e.g. tamr.cloud or eu.tamr.cloud"
  type        = string
}

variable "create_private_hosted_zone" {
  description = "Create a Route 53 private hosted zone for api_domain. Set false if you already manage that zone in this VPC and will add the record yourself."
  type        = bool
  default     = true
}

###############################################################################
# Optional test client
###############################################################################

variable "enable_test_client" {
  description = "Create a Lambda in the VPC that requests the API through the endpoint, for testing the connection"
  type        = bool
  default     = false
}

variable "test_client_log_group_name" {
  description = "Existing CloudWatch log group the test client writes to. When null, Lambda creates its default /aws/lambda/<name>-test-client group on first invocation, outside Terraform."
  type        = string
  default     = null
}

variable "test_client_host" {
  description = "Tenant hostname the test client requests, one label under api_domain, e.g. your-tenant.tamr.cloud. Required when enable_test_client is true."
  type        = string
  default     = null
}

variable "test_client_path" {
  description = "URL path the test client requests"
  type        = string
  default     = "/"
}

variable "test_client_method" {
  description = "HTTP method the test client uses"
  type        = string
  default     = "GET"
}

variable "test_client_verify_tls" {
  description = "Whether the test client verifies the API certificate"
  type        = bool
  default     = true
}

variable "test_client_timeout" {
  description = "Seconds the test client may run"
  type        = number
  default     = 900

  validation {
    condition     = var.test_client_timeout >= 1 && var.test_client_timeout <= 900
    error_message = "test_client_timeout must be between 1 and 900 seconds."
  }
}

variable "test_client_security_group_ids" {
  description = "Additional security groups to attach to the test client, for example one that allows reaching CloudWatch Logs"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource that supports them"
  type        = map(string)
  default     = {}
}
