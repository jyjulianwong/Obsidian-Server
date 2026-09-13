# Obsidian

A personal, central auth service that silently authenticates your own pre-authorized devices (laptops, phones, servers) using **mutual TLS (mTLS)** and issues short-lived JWT access tokens for your other projects' APIs to trust. No password, no per-device login script — the device's installed certificate proves its identity during the TLS handshake itself.

📖 **[Docs site](https://jyjulianwong.github.io/Obsidian-Server/)** — what Obsidian is, how the token flow works, and copy-paste API examples in Python and JavaScript. This README covers deploying Obsidian itself.

## Who is this for?

I run several small personal projects, each with its own UI and API. I didn't want to bolt a separate login system onto each one, and I didn't want a shared password floating between them either. Obsidian is the one place that knows which of my devices are allowed to act on my behalf; every other project just verifies the token Obsidian issued and gets on with its own job.

## Architecture

```
Device (installed client cert)
  │  TLS handshake — API Gateway requests + verifies the client cert
  │  against the S3 truststore before any HTTP request is processed
  ▼
auth.jyjwong.com (API Gateway custom domain, mTLS-enabled)
  │  Mangum translates the API Gateway event to ASGI
  ▼
Lambda — FastAPI app (server/)
  ├─ reads verified cert CN from the request (device_id)
  ├─ checks device_id in DynamoDB devices table (active/revoked)
  └─ signs + returns a JWT (RS256) using a key from SSM Parameter Store
  ▼
Device stores the token, calls your other projects' APIs with
  Authorization: Bearer <token>
  ▼
Your other projects verify the JWT locally via Obsidian's JWKS endpoint,
  served on a SEPARATE public domain with no mTLS (jwks.jyjwong.com) —
  API Gateway can't exempt one route from a domain's mTLS requirement,
  and resource servers verifying tokens don't have a device certificate.
  No call back to Obsidian per request either way.
```

| Piece | Role |
|---|---|
| Private CA (`ca/ca.key` / `ca/ca.crt`) | Your own root of trust — signs every device certificate |
| Device certs (`devices/<id>/`) | One keypair + signed cert per authorized device |
| S3 truststore bucket | Holds `ca.crt`; referenced by the API Gateway custom domain |
| API Gateway custom domain (`auth.jyjwong.com`) | Terminates TLS, verifies client certs against the truststore; serves `/auth/token` |
| API Gateway public domain (`jwks.jyjwong.com`) | Same Lambda, no truststore; serves only `GET /.well-known/jwks.json` for resource servers without a device cert |
| Lambda (Mangum + FastAPI + authlib) | Runs the auth service; issues JWTs, serves JWKS |
| JWT signing keypair | Separate from the CA — Terraform-generated, stored in SSM |
| DynamoDB devices table | `device_id → active/revoked` — your app-level kill switch |
| Cloudflare domains | DNS only (grey cloud), point both custom domains at API Gateway |

## Repository layout

```
.
├── server/              # FastAPI + Mangum auth service (deployed to Lambda)
├── terraform/
│   ├── bootstrap/       # One-time state infrastructure (run manually once)
│   └── *.tf             # Main infrastructure (deployed via CI/CD after first apply)
├── scripts/
│   ├── generate_ca.sh          # One-time: create the device CA
│   ├── provision_device.py     # Issue + register a new device certificate
│   ├── revoke_device.py        # Mark a device inactive
│   ├── generate_mtls_bundle.sh # Bundle a device's key+cert into a .p12 for OS/browser import
│   ├── package_lambda.sh       # Build the real (dependency-inclusive) Lambda zip
│   └── run_local_server.sh     # Run the FastAPI app locally
├── examples/            # Copy-paste snippets for your OTHER projects
│   ├── fastapi_verify_token.py     # Python/FastAPI: verify a Bearer token
│   ├── python_client_get_token.py  # Python: server-to-server / CLI token fetch
│   └── browser_get_token.js        # JS: browser token fetch + caveats
└── .github/workflows/   # CI/CD
```

---

## Prerequisites

- **AWS CLI**, configured (`aws configure`) with credentials for the account you're deploying into.
- **Terraform** ≥ 1.6.
- **OpenSSL** (for the CA and device certs).
- **uv** (Python package manager — `pip install uv`).
- A **domain managed in Cloudflare** you're willing to carve a subdomain out of (e.g. `auth.jyjwong.com`). DNS only — Cloudflare is not involved in the TLS handshake at all here.

---

## Initial setup

Everything below is a **one-time** setup. After it's done, pushes to `main` redeploy automatically via GitHub Actions.

### 1. Find your AWS account ID

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo $ACCOUNT_ID
```

### 2. Bootstrap Terraform state infrastructure

```bash
cd terraform/bootstrap
terraform init
terraform apply -var="aws_account_id=$ACCOUNT_ID"
# Creates: ${ACCOUNT_ID}-jyjulianwong-obsidian-terraform-state (S3)
#          jyjulianwong-obsidian-terraform-lock (DynamoDB)
cd ../..
```

### 3. Generate the device CA (on local machine only)

```bash
./scripts/generate_ca.sh
```

This creates `ca/ca.key` (sensitive — never commit it, back it up offline) and `ca/ca.crt` (public — this one **is** committed, Terraform uploads it as the mTLS truststore).

### 4. Terraform: Phase 1 — create the ACM certificates only

Both custom domains need a validated ACM certificate before they can exist, and DNS validation for a Cloudflare-hosted domain can't be automated by Terraform (Cloudflare isn't the AWS-integrated DNS provider). So this is done in two phases.

```bash
cd terraform
terraform init \
  -backend-config="bucket=${ACCOUNT_ID}-jyjulianwong-obsidian-terraform-state" \
  -backend-config="dynamodb_table=jyjulianwong-obsidian-terraform-lock"

terraform apply \
  -target=aws_acm_certificate.auth_domain \
  -target=aws_acm_certificate.jwks_domain \
  -var="aws_account_id=$ACCOUNT_ID" \
  -var="domain_name=auth.jyjwong.com" \
  -var="jwks_domain_name=jwks.jyjwong.com"

terraform output acm_certificate_validation_records
```

### 5. Add the ACM validation records to Cloudflare

In the Cloudflare dashboard for your domain → **DNS**, add both CNAME records printed above (one per domain):

| Type | Name | Content | Proxy status |
|---|---|---|---|
| CNAME | (from `resource_record_name`) | (from `resource_record_value`) | **DNS only** (grey cloud) |

Wait a few minutes for DNS propagation and ACM validation (usually well under 10 minutes).

### 6. Terraform: Phase 2 — apply the entire plan

```bash
terraform apply \
  -var="aws_account_id=$ACCOUNT_ID" \
  -var="domain_name=auth.jyjwong.com" \
  -var="jwks_domain_name=jwks.jyjwong.com" \
  -var="allowed_origins=https://app.jyjwong.com,http://localhost:3000"
```

This creates the truststore bucket, the JWT signing key (in SSM), the devices table, the Lambda function (placeholder code — see step 8), the mTLS-enabled API Gateway custom domain, and the separate public (no-mTLS) API Gateway domain that serves just the JWKS route.

```bash
terraform output apigatewayv2_domain_target
terraform output apigatewayv2_jwks_domain_target
```

### 7. Point Cloudflare at API Gateway — human action

In Cloudflare **DNS**, add two more records — one per custom domain:

| Type | Name | Content | Proxy status |
|---|---|---|---|
| CNAME | `auth` (or your chosen subdomain) | (from `apigatewayv2_domain_target`) | **DNS only** (grey cloud) |
| CNAME | `jwks` (or your chosen subdomain) | (from `apigatewayv2_jwks_domain_target`) | **DNS only** (grey cloud) |

**Important:** both must stay grey-cloud (DNS only). A proxied (orange-cloud) record terminates TLS at Cloudflare's edge — for `auth.jyjwong.com` that breaks client-certificate verification (the client cert would never reach API Gateway); for `jwks.jyjwong.com` it's not strictly required for security, but keep it consistent so ACM's TLS cert on the origin stays the one actually presented.

### 8. Deploy the real Lambda code (manually for the first time only)

Terraform's own zip has no dependencies bundled (just enough to create the function). Build and push the real one once, before CI/CD exists to do it for you:

```bash
cd ..   # repo root
./scripts/package_lambda.sh
aws lambda update-function-code \
  --function-name "$(terraform -chdir=terraform output -raw lambda_function_name)" \
  --zip-file fileb://server/build/lambda.zip
```

### 9. Provision your first device

```bash
DEVICE_ID="obsidian-my-laptop"
./scripts/provision_device.py $DEVICE_ID \
  --table-name "$(terraform -chdir=terraform output -raw devices_table_name)"
```

(The script carries its own inline dependency metadata — `uv` installs `boto3` into an ephemeral venv on first run, no setup needed.)

This writes `devices/my-laptop/my-laptop.key` + `.crt` and registers `my-laptop` as active in DynamoDB.

#### Installing a device certificate

Bundle the key + cert (+ CA, so the OS can build the chain) into a `.p12` first:

```bash
DEVICE_ID="obsidian-my-laptop"
./scripts/generate_mtls_bundle.sh $DEVICE_ID
```

This prompts twice for an export password (type the same thing both times) and writes `devices/my-laptop/my-laptop.p12`. It always passes `-legacy` to `openssl pkcs12`: OpenSSL 3.x (`openssl version` — Homebrew's is) defaults to AES-256/SHA-256 for `.p12` files, which macOS Keychain's importer can't parse — it fails with **"OSStatus -26276"** regardless of whether the password is right. `-legacy` falls back to 3DES/RC2, which Keychain understands.

Before importing anywhere, verify the password actually took (the script prints this command with a placeholder — fill in the real password):

```bash
openssl pkcs12 -legacy -in devices/$DEVICE_ID/$DEVICE_ID.p12 -noout -passin pass:YOUR_PASSWORD
```

No output is success. A "Mac verify error" here means the two prompts in step 1 didn't match — rerun the script.

- **macOS:** Double-click the `.p12` in Finder — Keychain Access imports it and prompts for the export password you just set. Or, run:
  ```bash
  security import devices/$DEVICE_ID/$DEVICE_ID.p12 -k ~/Library/Keychains/login.keychain-db -P 'YOUR_PASSWORD' -T /usr/bin/security
  ```
  To remove it later (e.g. after revoking the device), delete the identity — the cert + private key `security import` created — from Keychain:
  ```bash
  security delete-identity -c "$DEVICE_ID" -t ~/Library/Keychains/login.keychain-db
  ```
  `-c` matches on the certificate's own Subject Common Name (`CN=<device_id>`, the identity `provision_device.py` issued) — not the `"Obsidian: <device_id>"` friendly name `generate_mtls_bundle.sh` sets on the `.p12`. Keychain only surfaces that friendly name for the private-key row; the certificate row (and everything `security` searches by `-c`) always uses the embedded CN. If the name isn't unique (e.g. the same device was provisioned twice), this refuses and asks for a SHA-256 hash instead — get one with `security find-certificate -c "$DEVICE_ID" -Z ~/Library/Keychains/login.keychain-db`, then pass it as `-Z <hash>` instead of `-c`. This only removes the certificate from Keychain — it doesn't revoke the device itself; see [Revocation](#revocation) for that.
- **Windows:** Double-click the `.p12` → Certificate Import Wizard → Store it under "Personal".
- **iOS:** AirDropping/emailing the raw `.p12` installs it as a bare "Identity Certificate" in Settings → VPN & Device Management, indistinguishable from other profiles. Wrap it in a proper configuration profile first:
  ```bash
  ./scripts/generate_ios_profile.sh $DEVICE_ID
  ```
  This writes `devices/$DEVICE_ID/$DEVICE_ID.mobileconfig` with a `PayloadDisplayName`/`PayloadDescription` set (`"Obsidian: $DEVICE_ID"`). AirDrop or email that `.mobileconfig` instead — Settings will still prompt for the export password, but the installed profile is now clearly labeled. It'll show as "Not Signed" (we don't sign profiles) — that's expected for a self-generated one.
- **Android:** AirDrop or email the `.p12` to the device, then open it — Settings will offer to install it (enter the export password).
- **Linux (NSS-based browsers, e.g. Chrome):** `chrome://settings/certificates` → **Your certificates** → **Import** → Select the `.p12`.

Optional, for a fully silent flow on a device you manage: some browsers support pre-selecting the client certificate for a given origin via enterprise policy (e.g. Chrome's `AutoSelectCertificateForUrls`), so the OS-level cert picker never appears. The exact mechanism is OS/browser-version specific — search for that policy name plus your OS if you want it; it's a convenience, not a requirement (a picker you dismiss once per browser profile is otherwise the norm).

### 10. Test it

```bash
DEVICE_ID="obsidian-my-laptop"
curl --cert devices/$DEVICE_ID/$DEVICE_ID.crt \
     --key devices/$DEVICE_ID/$DEVICE_ID.key \
     -X POST https://auth.jyjwong.com/auth/token
```

You should get back `{"access_token": "...", "token_type": "bearer", "expires_in": 3600}`.

### 11. Add GitHub Actions secrets

In your GitHub repository → **Settings → Secrets and variables → Actions**, add:

| Secret name | Value |
|---|---|
| `AWS_ACCOUNT_ID` | Your 12-digit AWS account ID |
| `AWS_ACCESS_KEY_ID` | `terraform output github_actions_access_key_id` |
| `AWS_SECRET_ACCESS_KEY` | `terraform output -raw github_actions_secret_access_key` |
| `OBSIDIAN_DOMAIN_NAME` | e.g. `auth.jyjwong.com` |
| `OBSIDIAN_JWKS_DOMAIN_NAME` | e.g. `jwks.jyjwong.com` |
| `OBSIDIAN_ALLOWED_ORIGINS` | e.g. `https://app.jyjwong.com,http://localhost:3000` |

From here on, every push to `main` touching `server/`, `terraform/`, or `ca/ca.crt` runs `terraform apply` and redeploys the Lambda automatically.

---

## Integrating Obsidian into your other projects

Files in `examples/` are meant to be copied into your other projects, not run from here.

### A backend API that should trust Obsidian tokens

Copy `examples/fastapi_verify_token.py` into the project, set `OBSIDIAN_ISSUER` and `OBSIDIAN_JWKS_URL`, and use it as a FastAPI dependency:

```python
from fastapi_verify_token import require_device

@app.get("/reports")
def reports(device_id: str = Depends(require_device)):
    ...
```

It verifies the JWT's RS256 signature against Obsidian's JWKS locally — no network round-trip to Obsidian per request. **Fetch the JWKS from `OBSIDIAN_JWKS_URL` (the `jwks.jyjwong.com` domain — `terraform output jwks_url`), not from a path under `OBSIDIAN_ISSUER`.** The issuer's domain (`auth.jyjwong.com`) requires a client certificate for every route, including `/.well-known/jwks.json` — a resource server with no device cert of its own will get a TLS-level connection reset trying to fetch JWKS from there. `OBSIDIAN_ISSUER` is still needed separately, to check the JWT's `iss` claim. (Not using FastAPI? The same split — JWKS from the public domain, `iss` checked against the mTLS domain — works with any language's standard JWT library.)

### A UI that should get a token silently

Copy `examples/browser_get_token.js` into the frontend, set `OBSIDIAN_ISSUER`, and call `getAccessToken()` before hitting your API. Read the caveat at the top of that file about the browser's client-certificate picker dialog — it's a one-time-per-profile prompt, not a per-request one.

### A server-to-server or CLI caller

Copy `examples/python_client_get_token.py`, point `DEVICE_CERT` at a provisioned device's key/cert pair. No browser involved, so no cert-picker UX to worry about.

---

## Revocation

- **Preferred, instant:**
  ```bash
  DEVICE_ID="obsidian-my-laptop"
  ./scripts/revoke_device.py $DEVICE_ID \
    --table-name "$(terraform -chdir=terraform output -raw devices_table_name)"
  ```
  `/auth/token` refuses the device on its very next request; already-issued tokens still expire naturally within `token_ttl_seconds` (default 1 hour).
- **Certificate expiry:** device certs default to a 36500-day (~100 year) validity (see `scripts/provision_device.py --days`) — there's no CRL/OCSP, so expiry isn't a meaningful safety net at that length and the DynamoDB `active`/`revoked` check above is the only real revocation path. Pass a shorter `--days` at provisioning time if you want certs to lapse on their own.
- **Rotating the CA itself** (only if the CA key is compromised — not needed for revoking one device): regenerate `ca/ca.crt`, `terraform apply` to re-upload it and bump `truststore_version`, then re-issue every device's certificate against the new CA.

---

## Local development

```bash
export OBSIDIAN_SIGNING_KEY_SSM_PARAM="/jyjulianwong-obsidian/jwt_signing_key"
export OBSIDIAN_DEVICES_TABLE_NAME="$(terraform -chdir=terraform output -raw devices_table_name)"
./scripts/run_local_server.sh
```

This still talks to the real SSM parameter and DynamoDB table (needs your AWS credentials active), but skips the mTLS handshake — `OBSIDIAN_DEV_MODE=1` lets you simulate a verified device via a header:

```bash
curl -X POST http://localhost:8000/auth/token -H "X-Dev-Device-Id: my-laptop"
```

---

## Docs site

The [docs site](https://jyjulianwong.github.io/Obsidian-Server/) (`docs/`, built with [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/)) covers what Obsidian is and how to integrate it, as opposed to this README's focus on deploying Obsidian itself. Preview it locally:

```bash
pip install -r docs/requirements.txt
mkdocs serve
```

Then open <http://127.0.0.1:8000>. Pages live under `docs/`; the Python and JavaScript example pages pull their code blocks directly from `examples/` via `pymdownx.snippets`, so they can't drift out of sync.

---

## CI/CD

`.github/workflows/deploy-terraform.yml`:
- **On PR** (touching `terraform/`, `server/`, or `ca/ca.crt`): runs `terraform plan` and posts the output as a PR comment.
- **On merge to `main`**: bumps a calendar version and tags it (`version_bump`), then — checked out at that tag — runs `terraform apply` and builds + deploys the real Lambda package (`deploy`).

`.github/workflows/deploy-docs.yml`:
- **On PR** (touching `docs/`, `examples/`, `mkdocs.yml`, or `README.md`): builds the [docs site](https://jyjulianwong.github.io/Obsidian-Server/) with `mkdocs build --strict` to catch broken links/snippets before merge.
- **On merge to `main`**: builds and deploys the site to GitHub Pages via `actions/deploy-pages`.
- **One-time setup:** in the repo's **Settings → Pages**, set **Source** to **GitHub Actions**.

### Versioning

Every deploy to `main` is stamped with a calendar version (`YYYY.MM.DD.MINOR`, e.g. `2026.09.11.0`) via `scripts/bump_calver.py`: it bumps `version` in `server/pyproject.toml`, commits, and tags (`v2026.09.11.0`). The `deploy` job then builds and ships that exact tagged commit, not whatever `main` happens to be at the moment the job runs — so a green Actions run always corresponds to one, findable, reproducible commit. The bump commit pushes using the workflow's own `GITHUB_TOKEN`, which GitHub deliberately excludes from retriggering `on: push` — so this doesn't loop.

### Pre-commit hooks

Install once per clone:

```bash
cd server && uv sync --group dev && cd ..
uv run --project server pre-commit install
```

`.pre-commit-config.yaml` runs on every commit:
- `uv-lock` / `uv-sort` — keep `server/uv.lock` and `server/pyproject.toml`'s dependency list in sync and sorted.
- `ruff` / `ruff-format` — lint and format all Python in the repo, using the rules in `server/pyproject.toml`.
- `terraform_fmt` — keeps everything under `terraform/` canonically formatted.

---

## Useful AWS CLI commands

```bash
# Tail Lambda logs
aws logs tail /aws/lambda/jyjulianwong-obsidian-auth --follow --region eu-west-2

# Check Lambda function status
aws lambda get-function \
  --function-name jyjulianwong-obsidian-auth \
  --region eu-west-2 \
  --query "Configuration.{State:State,LastUpdateStatus:LastUpdateStatus}"

# List all registered devices and their status
aws dynamodb scan \
  --table-name "$(terraform -chdir=terraform output -raw devices_table_name)" \
  --query "Items[].{device_id:device_id.S,status:status.S}"

# Read the JWT signing key (rarely needed — mostly for disaster recovery)
aws ssm get-parameter \
  --name "/jyjulianwong-obsidian/jwt_signing_key" \
  --with-decryption \
  --query "Parameter.Value" --output text
```

---

## Cost estimates

| Item | Approx. cost |
|---|---|
| Cloudflare domain | ~$10/year |
| ACM certificate | Free |
| API Gateway custom domain resource | No charge |
| API Gateway requests | ~$1/million (negligible at this volume) |
| S3 truststore storage | Fractions of a cent |
| Lambda + DynamoDB (pay-per-request) | Fractions of a cent at this volume |
| **Total** | **~$1/month**, essentially just the domain |
