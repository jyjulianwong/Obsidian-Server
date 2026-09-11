#!/usr/bin/env bash
# Runs the auth service locally. Still talks to real AWS (SSM + DynamoDB),
# so `aws configure` / AWS_PROFILE must already point at your account.
# OBSIDIAN_DEV_MODE lets you simulate a verified device via the
# X-Dev-Device-Id header instead of a real mTLS handshake — see server/mtls.py.
set -euo pipefail

cd "$(dirname "$0")/../server"
uv sync

OBSIDIAN_DEV_MODE=1 \
OBSIDIAN_ISSUER="http://localhost:8000" \
OBSIDIAN_SIGNING_KEY_SSM_PARAM="${OBSIDIAN_SIGNING_KEY_SSM_PARAM:?set to terraform output jwt signing key param name, e.g. /jyjulianwong-obsidian/jwt_signing_key}" \
OBSIDIAN_DEVICES_TABLE_NAME="${OBSIDIAN_DEVICES_TABLE_NAME:?set to \$(terraform -chdir=../terraform output -raw devices_table_name)}" \
OBSIDIAN_ALLOWED_ORIGINS="http://localhost:3000" \
uv run uvicorn main:app --reload --port 8000
