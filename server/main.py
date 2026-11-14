import os

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from mangum import Mangum

import auth
import devices
from mtls import get_verified_device_id

app = FastAPI(title="Obsidian")

_allowed_origins = [
    origin.strip()
    for origin in os.environ.get("OBSIDIAN_ALLOWED_ORIGINS", "").split(",")
    if origin.strip()
]

# Every *.jyjwong.com subdomain (and the apex) is a jyjulianwong-owned site
# by convention (Infrastructure-GitHub's terraform/pages_domains.tf is the
# source of truth for which ones exist) and is allowed automatically, so
# onboarding a new GitHub Pages site never requires touching this service's
# config. OBSIDIAN_ALLOWED_ORIGINS stays for anything outside that pattern,
# e.g. http://localhost:3000 for local dev. allow_origins and
# allow_origin_regex are both checked by CORSMiddleware; an origin matching
# either is allowed.
_JYJWONG_ORIGIN_REGEX = r"https://([a-z0-9-]+\.)?jyjwong\.com"

app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
    allow_origin_regex=_JYJWONG_ORIGIN_REGEX,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization"],
)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/auth/token")
def issue_token(request: Request):
    device_id = get_verified_device_id(request)
    if device_id is None:
        # Should be unreachable in prod — API Gateway rejects unauthenticated
        # TLS handshakes before the request ever reaches this Lambda.
        raise HTTPException(status_code=401, detail="No client certificate presented")

    if not devices.is_device_active(device_id):
        raise HTTPException(status_code=403, detail="Device is not authorized")

    return auth.issue_token(device_id)


@app.get("/.well-known/jwks.json")
def jwks():
    return auth.jwks()


@app.get("/.well-known/openid-configuration")
def openid_configuration():
    return auth.openid_configuration()


handler = Mangum(app, lifespan="off")
