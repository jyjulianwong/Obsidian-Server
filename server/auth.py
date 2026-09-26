import os
import time
from functools import lru_cache

import boto3
from authlib.jose import JsonWebKey, jwt

_ISSUER = os.environ.get("OBSIDIAN_ISSUER", "")
_JWKS_URI = os.environ.get("OBSIDIAN_JWKS_URI", "")
_SIGNING_KEY_PARAM = os.environ["OBSIDIAN_SIGNING_KEY_SSM_PARAM"]
_TOKEN_TTL_SECONDS = int(os.environ.get("OBSIDIAN_TOKEN_TTL_SECONDS", "3600"))


@lru_cache(maxsize=1)
def _signing_key() -> JsonWebKey:
    # Cached per warm Lambda execution environment — one SSM read per cold start.
    ssm = boto3.client("ssm")
    param = ssm.get_parameter(Name=_SIGNING_KEY_PARAM, WithDecryption=True)
    pem = param["Parameter"]["Value"].encode("utf-8")
    key = JsonWebKey.import_key(pem, {"kty": "RSA"})
    return key


def issue_token(device_id: str) -> dict:
    key = _signing_key()
    now = int(time.time())
    header = {"alg": "RS256", "kid": key.thumbprint()}
    payload = {
        "iss": _ISSUER,
        "sub": device_id,
        "iat": now,
        "exp": now + _TOKEN_TTL_SECONDS,
    }
    token = jwt.encode(header, payload, key)
    return {
        "access_token": token.decode("utf-8"),
        "token_type": "bearer",
        "expires_in": _TOKEN_TTL_SECONDS,
    }


def jwks() -> dict:
    key = _signing_key()
    public_jwk = key.as_dict(is_private=False)
    public_jwk["kid"] = key.thumbprint()
    public_jwk["use"] = "sig"
    public_jwk["alg"] = "RS256"
    return {"keys": [public_jwk]}


def openid_configuration() -> dict:
    # Obsidian isn't a full OIDC provider — there's no authorization endpoint,
    # user login, or id_token; a device authenticates itself with an mTLS
    # client cert and gets an access token directly. This document is really
    # OAuth 2.0 Authorization Server Metadata (RFC 8414) published at the
    # conventional OIDC discovery path, since that's where most tooling looks
    # first. jwks_uri deliberately points at the separate public JWKS domain
    # (see OBSIDIAN_JWKS_URI) rather than a path under the issuer, which
    # requires a client certificate on every route.
    return {
        "issuer": _ISSUER,
        "token_endpoint": f"{_ISSUER}/auth/token",
        "jwks_uri": _JWKS_URI,
        "token_endpoint_auth_methods_supported": ["tls_client_auth"],
        "grant_types_supported": ["client_credentials"],
        "response_types_supported": [],
    }
