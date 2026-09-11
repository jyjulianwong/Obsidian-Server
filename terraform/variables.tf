variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-2"
}

variable "aws_account_id" {
  description = "AWS account ID to deploy into — Terraform will refuse to apply if the active credentials resolve to a different account"
  type        = string
}

variable "project" {
  description = "Short project identifier used to namespace resource names"
  type        = string
  default     = "jyjulianwong-obsidian"
}

variable "domain_name" {
  description = "Fully-qualified custom domain for the auth service. Must be a domain you control in Cloudflare."
  type        = string
  default     = "auth.jyjwong.com"
}

variable "allowed_origins" {
  description = "Comma-separated origins allowed to call the auth service via CORS (your other projects' UIs), e.g. https://app.jyjwong.com,http://localhost:3000"
  type        = string
  default     = ""
}

variable "token_ttl_seconds" {
  description = "Lifetime of issued access tokens, in seconds"
  type        = number
  default     = 3600
}

variable "ca_cert_path" {
  description = "Path to the Obsidian device CA's public certificate (ca.crt), uploaded to S3 as the mTLS truststore. Generate it with scripts/generate_ca.sh."
  type        = string
  default     = "../ca/ca.crt"
}
