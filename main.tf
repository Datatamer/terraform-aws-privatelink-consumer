resource "aws_security_group" "endpoint" {
  name_prefix = "${var.name}-vpce-"
  description = "Clients permitted to reach the Tamr API PrivateLink endpoint"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-vpce"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.endpoint.id
  description       = "HTTPS from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.endpoint.id
  description                  = "HTTPS from ${each.value}"
  referenced_security_group_id = each.value
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_endpoint" "this" {
  vpc_id              = var.vpc_id
  service_name        = var.endpoint_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = false

  tags = merge(var.tags, {
    Name = var.name
  })

  lifecycle {
    precondition {
      condition     = length(var.allowed_cidrs) + length(var.allowed_security_group_ids) > 0
      error_message = "Set allowed_cidrs or allowed_security_group_ids, or nothing can reach the endpoint."
    }
  }
}

locals {
  regional_dns_entry = one([
    for e in aws_vpc_endpoint.this.dns_entry : e
    if length(split("-", split(".", e.dns_name)[0])) == 3
  ])
}

resource "aws_route53_zone" "this" {
  count = var.create_private_hosted_zone ? 1 : 0

  name    = var.api_domain
  comment = "Tamr API via PrivateLink"

  vpc {
    vpc_id = var.vpc_id
  }

  tags = merge(var.tags, {
    Name = var.name
  })
}

resource "aws_route53_record" "wildcard" {
  count = var.create_private_hosted_zone ? 1 : 0

  zone_id = aws_route53_zone.this[0].zone_id
  name    = "*.${var.api_domain}"
  type    = "A"

  alias {
    name                   = local.regional_dns_entry.dns_name
    zone_id                = local.regional_dns_entry.hosted_zone_id
    evaluate_target_health = false
  }
}
