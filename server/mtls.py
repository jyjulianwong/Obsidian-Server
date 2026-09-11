import os
import re
from fastapi import Request

_CN_PATTERN = re.compile(r"CN=([^,]+)")

# Local dev only: lets `uvicorn main:app --reload` simulate a verified device
# without a real mTLS handshake. Never set OBSIDIAN_DEV_MODE in Lambda.
_DEV_MODE = os.environ.get("OBSIDIAN_DEV_MODE") == "1"


def _parse_cn(subject_dn: str) -> str | None:
    match = _CN_PATTERN.search(subject_dn)
    return match.group(1) if match else None


def get_verified_device_id(request: Request) -> str | None:
    """Returns the CN of the mTLS client certificate API Gateway already
    verified against the truststore, or None if no certificate was presented.

    API Gateway (HTTP API, mTLS-enabled custom domain) adds the verified
    client certificate to requestContext.authentication.clientCert in the
    Lambda proxy integration event — it never reaches app code as a raw cert.
    Mangum forwards that raw event via request.scope["aws.event"].
    """
    if _DEV_MODE:
        dev_device_id = request.headers.get("x-dev-device-id")
        if dev_device_id:
            return dev_device_id

    event = request.scope.get("aws.event")
    if not event:
        return None

    client_cert = (
        event.get("requestContext", {})
        .get("authentication", {})
        .get("clientCert")
    )
    if not client_cert:
        return None

    return _parse_cn(client_cert.get("subjectDN", ""))
