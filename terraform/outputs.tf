output "acm_certificate_validation_records" {
  description = "DNS records to add manually in Cloudflare (DNS only, grey cloud) before completing the apply — see README"
  value = concat(
    [
      for o in aws_acm_certificate.auth_domain.domain_validation_options : {
        name  = o.resource_record_name
        type  = o.resource_record_type
        value = o.resource_record_value
      }
    ],
    [
      for o in aws_acm_certificate.jwks_domain.domain_validation_options : {
        name  = o.resource_record_name
        type  = o.resource_record_type
        value = o.resource_record_value
      }
    ]
  )
}

output "apigatewayv2_domain_target" {
  description = "Regional API Gateway domain — point your Cloudflare CNAME for var.domain_name at this (DNS only, grey cloud)"
  value       = aws_apigatewayv2_domain_name.auth.domain_name_configuration[0].target_domain_name
}

output "apigatewayv2_jwks_domain_target" {
  description = "Regional API Gateway domain — point your Cloudflare CNAME for var.jwks_domain_name at this (DNS only, grey cloud)"
  value       = aws_apigatewayv2_domain_name.jwks.domain_name_configuration[0].target_domain_name
}

output "truststore_bucket_name" {
  description = "S3 bucket holding the mTLS truststore (ca.crt) — re-upload here and bump truststore_version to rotate the CA"
  value       = aws_s3_bucket.truststore.bucket
}

output "devices_table_name" {
  description = "DynamoDB table for device authorization — used by scripts/provision_device.py and scripts/revoke_device.py"
  value       = aws_dynamodb_table.devices.name
}

output "lambda_function_name" {
  description = "Lambda function name for CI/CD update commands and manual invokes"
  value       = aws_lambda_function.auth.function_name
}

output "issuer_url" {
  description = "The 'iss' claim in issued JWTs, and the base URL for /auth/token and /.well-known/jwks.json"
  value       = local.issuer
}

output "jwks_url" {
  description = "Public (non-mTLS) JWKS endpoint downstream services use to verify Obsidian-issued tokens — distinct from issuer_url, since the issuer's domain requires a client certificate"
  value       = "https://${var.jwks_domain_name}/.well-known/jwks.json"
}

output "github_actions_access_key_id" {
  description = "AWS access key ID for GitHub Actions — store as GitHub secret AWS_ACCESS_KEY_ID"
  value       = aws_iam_access_key.github_actions.id
}

output "github_actions_secret_access_key" {
  description = "AWS secret access key for GitHub Actions — store as GitHub secret AWS_SECRET_ACCESS_KEY"
  value       = aws_iam_access_key.github_actions.secret
  sensitive   = true
}
