import os

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from mangum import Mangum

import auth
import devices
from mtls import get_verified_device_id

app = FastAPI(title="Obsidian Auth Service")

_allowed_origins = [
    origin.strip()
    for origin in os.environ.get("OBSIDIAN_ALLOWED_ORIGINS", "").split(",")
    if origin.strip()
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
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


handler = Mangum(app, lifespan="off")
