locals {
  test_client_enabled = var.enable_test_client ? 1 : 0
  test_client_url     = var.test_client_host == null ? null : "https://${var.test_client_host}${var.test_client_path}"
}

resource "aws_security_group" "test_client" {
  count = local.test_client_enabled

  name_prefix = "${var.name}-test-client-"
  description = "Test client for the Tamr API PrivateLink endpoint"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-test-client"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "test_client_to_endpoint" {
  count = local.test_client_enabled

  security_group_id            = aws_security_group.test_client[0].id
  description                  = "HTTPS to the endpoint ENIs"
  referenced_security_group_id = aws_security_group.endpoint.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "endpoint_from_test_client" {
  count = local.test_client_enabled

  security_group_id            = aws_security_group.endpoint.id
  description                  = "HTTPS from the test client"
  referenced_security_group_id = aws_security_group.test_client[0].id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

data "aws_iam_policy_document" "test_client_trust" {
  count = local.test_client_enabled

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "test_client" {
  count = local.test_client_enabled

  name_prefix        = "${var.name}-test-"
  assume_role_policy = data.aws_iam_policy_document.test_client_trust[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "test_client_vpc_access" {
  count = local.test_client_enabled

  role       = aws_iam_role.test_client[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_cloudwatch_log_group" "test_client" {
  count = var.enable_test_client && var.test_client_log_group_name != null ? 1 : 0

  name = var.test_client_log_group_name
}

resource "aws_lambda_function" "test_client" {
  count = local.test_client_enabled

  function_name    = "${var.name}-test-client"
  role             = aws_iam_role.test_client[0].arn
  filename         = "${path.module}/lambda/api_test_client.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/api_test_client.zip")
  handler          = "index.handler"
  runtime          = "python3.13"
  timeout          = 30

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = concat([aws_security_group.test_client[0].id], var.test_client_security_group_ids)
  }

  environment {
    variables = {
      API_URL    = local.test_client_url
      METHOD     = var.test_client_method
      VERIFY_TLS = tostring(var.test_client_verify_tls)
    }
  }

  dynamic "logging_config" {
    for_each = data.aws_cloudwatch_log_group.test_client
    content {
      log_format = "Text"
      log_group  = logging_config.value.name
    }
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.test_client_host != null
      error_message = "test_client_host must be set when enable_test_client is true. Use a tenant hostname under api_domain, e.g. your-tenant.tamr.cloud."
    }

    precondition {
      condition     = can(regex("^[^.]+\\.${replace(var.api_domain, ".", "\\.")}$", var.test_client_host))
      error_message = "test_client_host must be one label under api_domain, e.g. your-tenant.${var.api_domain}."
    }
  }

  depends_on = [aws_iam_role_policy_attachment.test_client_vpc_access]
}
