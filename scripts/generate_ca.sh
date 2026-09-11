#!/usr/bin/env bash
# One-time setup: creates the Obsidian device CA. Run locally, never in CI —
# ca.key must never touch AWS or leave this machine (back it up offline).
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p ca
cd ca

if [[ -f ca.key ]]; then
  echo "ca/ca.key already exists — refusing to overwrite." >&2
  echo "Deleting it and regenerating invalidates every certificate issued to every device." >&2
  exit 1
fi

openssl genrsa -out ca.key 4096
openssl req -x509 -new -key ca.key -sha256 -days 3650 -out ca.crt \
  -subj "/CN=Obsidian Device CA"

chmod 600 ca.key

echo
echo "Created:"
echo "  ca/ca.key — sensitive. Back this up offline; never commit it or upload it to AWS."
echo "  ca/ca.crt — public. Uploaded to the S3 truststore by 'terraform apply' (var.ca_cert_path)."
