#!/usr/bin/env bash
# Bundles a provisioned device's key + cert (+ CA, so the OS can build the
# trust chain) into a .p12 for import into an OS/browser keychain.
#
# -legacy matters on OpenSSL 3.x (e.g. Homebrew's), which defaults to
# AES-256/SHA-256 for .p12 files — a format macOS Keychain's importer can't
# parse, failing with "OSStatus -26276" regardless of whether the password
# is right. -legacy falls back to 3DES/RC2, which Keychain understands.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <device_id>" >&2
  exit 1
fi

DEVICE_ID="$1"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_DIR="$ROOT_DIR/devices/$DEVICE_ID"
CA_CRT="$ROOT_DIR/ca/ca.crt"

CRT_PATH="$DEVICE_DIR/$DEVICE_ID.crt"
KEY_PATH="$DEVICE_DIR/$DEVICE_ID.key"
P12_PATH="$DEVICE_DIR/$DEVICE_ID.p12"

if [[ ! -f "$CRT_PATH" || ! -f "$KEY_PATH" ]]; then
  echo "Missing $CRT_PATH or $KEY_PATH — run scripts/provision_device.py $DEVICE_ID first." >&2
  exit 1
fi

if [[ ! -f "$CA_CRT" ]]; then
  echo "CA not found at $CA_CRT — run scripts/generate_ca.sh first." >&2
  exit 1
fi

openssl pkcs12 -export -legacy \
  -in "$CRT_PATH" \
  -inkey "$KEY_PATH" \
  -certfile "$CA_CRT" \
  -out "$P12_PATH" \
  -name "Obsidian: $DEVICE_ID"

echo
echo "Created $P12_PATH"
echo "Verify the password before importing it anywhere:"
echo "  openssl pkcs12 -legacy -in $P12_PATH -noout -passin pass:YOUR_PASSWORD"
