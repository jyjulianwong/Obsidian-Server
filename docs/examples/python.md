# Python

<span class="obsidian-pill">requests</span>
<span class="obsidian-pill">FastAPI</span>
<span class="obsidian-pill">PyJWT</span>

## Verifying a token (FastAPI)

Use this in a backend API that should only serve requests carrying a valid
Obsidian-issued token — for example, "one of my own devices is allowed to
hit this endpoint."

The verification is entirely local: `PyJWKClient` fetches Obsidian's public
signing key once and caches it, re-fetching only if it encounters a `kid`
it hasn't seen before. There is no network call to Obsidian on the request
path.

```bash
pip install "pyjwt[crypto]"
```

```python title="fastapi_verify_token.py"
--8<-- "examples/fastapi_verify_token.py"
```

Wire it into a route as a dependency:

```python
from fastapi_verify_token import require_device

@app.get("/reports")
def reports(device_id: str = Depends(require_device)):
    ...
```

`require_device` returns the authenticated `device_id` (the JWT's `sub`
claim) on success, or raises `HTTPException(401)` if the token is missing,
expired, or fails signature/issuer verification.

!!! warning "Fetch JWKS from the JWKS domain, not the issuer"
    `OBSIDIAN_JWKS_URL` must point at the separate, no-mTLS JWKS domain
    (`jwks.jyjwong.com`), never at a path under `OBSIDIAN_ISSUER`. The
    issuer's domain requires a client certificate on *every* route — a
    resource server with no device cert of its own gets a TLS-level
    connection reset trying to fetch JWKS from there.

Not using FastAPI? The same two-domain split — JWKS from the public
domain, `iss` checked against the mTLS domain — works with any language's
standard JWT library.

## Getting a token (server-to-server or CLI)

Use this when the caller itself *is* one of your provisioned devices — a
cron job, a CLI tool, or one service calling another — and can present its
own client certificate directly. There's no browser involved, so no
certificate-picker UX to worry about.

```bash
pip install requests
```

```python title="python_client_get_token.py"
--8<-- "examples/python_client_get_token.py"
```

Point `DEVICE_CERT` at the key/cert pair written by
[`scripts/provision_device.py`](https://github.com/jyjulianwong/Obsidian-Server/blob/main/scripts/provision_device.py)
for this device, then call `get_access_token()` before hitting your other
API.
