terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
}

locals {
  global_prefix = "${var.aws_account_id}-${var.project}" # S3 buckets (globally scoped)
  scoped_prefix = var.project                            # all other resources (account-scoped)
  issuer        = "https://${var.domain_name}"
}

# ---------------------------------------------------------------------------
# ACM — certificate for the custom domain (DNS validation via Cloudflare)
#
# Cloudflare, not Route53, hosts DNS here, so Terraform cannot create the
# validation record itself. Apply this in two phases — see README.
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "auth_domain" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "auth_domain" {
  certificate_arn         = aws_acm_certificate.auth_domain.arn
  validation_record_fqdns = [for o in aws_acm_certificate.auth_domain.domain_validation_options : o.resource_record_name]
}

# ACM certificate for the public JWKS domain — same DNS-validation dance,
# separate domain so it doesn't inherit the auth domain's mTLS truststore.

resource "aws_acm_certificate" "jwks_domain" {
  domain_name       = var.jwks_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "jwks_domain" {
  certificate_arn         = aws_acm_certificate.jwks_domain.arn
  validation_record_fqdns = [for o in aws_acm_certificate.jwks_domain.domain_validation_options : o.resource_record_name]
}

# ---------------------------------------------------------------------------
# S3 — mTLS truststore (holds the Obsidian device CA's public certificate)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "truststore" {
  bucket = "${local.global_prefix}-truststore"
}

resource "aws_s3_bucket_versioning" "truststore" {
  bucket = aws_s3_bucket.truststore.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "truststore" {
  bucket                  = aws_s3_bucket.truststore.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "ca_cert" {
  bucket = aws_s3_bucket.truststore.id
  key    = "ca.crt"
  source = var.ca_cert_path
  etag   = filemd5(var.ca_cert_path)
}

# ---------------------------------------------------------------------------
# JWT signing key — separate from the CA, signs the access tokens this
# service issues. Not a root of trust, so Terraform-managed is acceptable.
# ---------------------------------------------------------------------------

resource "tls_private_key" "jwt_signing" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_ssm_parameter" "jwt_signing_key" {
  name        = "/${local.scoped_prefix}/jwt_signing_key"
  type        = "SecureString"
  value       = tls_private_key.jwt_signing.private_key_pem
  description = "RSA private key used to sign Obsidian access tokens (RS256)"
}

# ---------------------------------------------------------------------------
# DynamoDB — devices table (device_id -> active/revoked)
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "devices" {
  name         = "${local.scoped_prefix}-devices"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "device_id"

  attribute {
    name = "device_id"
    type = "S"
  }
}

# ---------------------------------------------------------------------------
# IAM — Lambda execution role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.scoped_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid    = "ReadDevicesTable"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
    ]
    resources = [aws_dynamodb_table.devices.arn]
  }

  statement {
    sid    = "ReadSigningKeyParam"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
    ]
    resources = [aws_ssm_parameter.jwt_signing_key.arn]
  }

  statement {
    sid    = "DecryptSigningKeyParam"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name   = "${local.scoped_prefix}-lambda-permissions"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# ---------------------------------------------------------------------------
# Lambda — auth service (FastAPI + Mangum, zip package)
#
# This zip only contains the app's own .py files, no dependencies — enough
# for the first `terraform apply` to succeed. CI/CD packages the real
# dependency-inclusive zip (scripts/package_lambda.sh) and pushes it via
# `aws lambda update-function-code`, so `ignore_changes` here stops Terraform
# reverting that on the next apply.
# ---------------------------------------------------------------------------

data "archive_file" "server_src" {
  type        = "zip"
  source_dir  = "../server"
  output_path = "${path.module}/.placeholder-lambda.zip"
  excludes    = ["pyproject.toml", "uv.lock", "build", "__pycache__"]
}

resource "aws_lambda_function" "auth" {
  function_name    = "${local.scoped_prefix}-auth"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "main.handler"
  filename         = data.archive_file.server_src.output_path
  source_code_hash = data.archive_file.server_src.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      OBSIDIAN_ISSUER                = local.issuer
      OBSIDIAN_SIGNING_KEY_SSM_PARAM = aws_ssm_parameter.jwt_signing_key.name
      OBSIDIAN_DEVICES_TABLE_NAME    = aws_dynamodb_table.devices.name
      OBSIDIAN_ALLOWED_ORIGINS       = var.allowed_origins
      OBSIDIAN_TOKEN_TTL_SECONDS     = tostring(var.token_ttl_seconds)
    }
  }

  lifecycle {
    # CI/CD updates the code with real dependencies bundled in; Terraform
    # should not revert it to the dependency-less placeholder on next apply.
    ignore_changes = [filename, source_code_hash]
  }
}

resource "aws_cloudwatch_log_group" "auth" {
  name              = "/aws/lambda/${aws_lambda_function.auth.function_name}"
  retention_in_days = 30
}

# ---------------------------------------------------------------------------
# API Gateway — HTTP API, mTLS custom domain
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "auth" {
  name          = "${local.scoped_prefix}-auth-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.auth.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.auth.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.auth.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.auth.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.auth.execution_arn}/*/*"
}

resource "aws_apigatewayv2_domain_name" "auth" {
  domain_name = var.domain_name

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.auth_domain.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  mutual_tls_authentication {
    truststore_uri     = "s3://${aws_s3_bucket.truststore.bucket}/${aws_s3_object.ca_cert.key}"
    truststore_version = aws_s3_object.ca_cert.version_id
  }
}

resource "aws_apigatewayv2_api_mapping" "auth" {
  api_id      = aws_apigatewayv2_api.auth.id
  domain_name = aws_apigatewayv2_domain_name.auth.id
  stage       = aws_apigatewayv2_stage.default.id
}

# ---------------------------------------------------------------------------
# API Gateway — public JWKS domain, no mTLS
#
# mutual_tls_authentication on aws_apigatewayv2_domain_name.auth applies to
# every route under that domain, not just /auth/token — API Gateway has no
# way to exempt a single path from a domain's mTLS requirement. Resource
# servers (e.g. another project's backend) need to fetch
# /.well-known/jwks.json without a device certificate, so it gets its own
# API + custom domain that never attaches a truststore. Same Lambda, just a
# route restricted to GET /.well-known/jwks.json — /auth/token is never
# wired into this API, so it isn't reachable here even without mTLS.
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "jwks" {
  name          = "${local.scoped_prefix}-jwks-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "jwks_lambda" {
  api_id                 = aws_apigatewayv2_api.jwks.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.auth.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "jwks" {
  api_id    = aws_apigatewayv2_api.jwks.id
  route_key = "GET /.well-known/jwks.json"
  target    = "integrations/${aws_apigatewayv2_integration.jwks_lambda.id}"
}

resource "aws_apigatewayv2_stage" "jwks" {
  api_id      = aws_apigatewayv2_api.jwks.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "jwks_apigateway" {
  statement_id  = "AllowJwksAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.jwks.execution_arn}/*/*"
}

resource "aws_apigatewayv2_domain_name" "jwks" {
  domain_name = var.jwks_domain_name

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.jwks_domain.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "jwks" {
  api_id      = aws_apigatewayv2_api.jwks.id
  domain_name = aws_apigatewayv2_domain_name.jwks.id
  stage       = aws_apigatewayv2_stage.jwks.id
}

# ---------------------------------------------------------------------------
# IAM — GitHub Actions user (Terraform apply + Lambda code deploy)
# ---------------------------------------------------------------------------

resource "aws_iam_user" "github_actions" {
  name = "${local.scoped_prefix}-github-actions-user"
}

data "aws_iam_policy_document" "github_actions" {
  statement {
    sid    = "LambdaCodeUpdate"
    effect = "Allow"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:GetFunction",
    ]
    resources = [aws_lambda_function.auth.arn]
  }

  statement {
    sid    = "TerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${local.global_prefix}-terraform-state",
      "arn:aws:s3:::${local.global_prefix}-terraform-state/*",
    ]
  }

  statement {
    sid    = "TerraformLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = ["arn:aws:dynamodb:${var.aws_region}:*:table/${local.scoped_prefix}-terraform-lock"]
  }

  # Regional Terraform apply permissions
  statement {
    sid    = "TerraformApplyRegional"
    effect = "Allow"
    actions = [
      "s3:*",
      "lambda:*",
      "dynamodb:*",
      "apigateway:*",
      "acm:*",
      "ssm:*",
      "kms:Describe*",
      "kms:List*",
      "logs:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # IAM and ACM are global services and do not populate aws:RequestedRegion,
  # so they must be in their own statement without that condition.
  statement {
    sid    = "TerraformApplyIAM"
    effect = "Allow"
    actions = [
      "iam:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "github_actions" {
  name   = "${local.scoped_prefix}-github-actions-user-policy"
  user   = aws_iam_user.github_actions.name
  policy = data.aws_iam_policy_document.github_actions.json
}

resource "aws_iam_access_key" "github_actions" {
  user = aws_iam_user.github_actions.name
}
