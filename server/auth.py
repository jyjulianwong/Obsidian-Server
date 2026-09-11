import os
import time
from functools import lru_cache

import boto3
from authlib.jose import JsonWebKey, jwt

_ISSUER = os.environ.get("OBSIDIAN_ISSUER", "")
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
