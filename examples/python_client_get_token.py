"""For server-to-server or CLI callers (no browser cert picker involved —
the client cert is passed explicitly, so this just works non-interactively).

Install: pip install requests
"""

import requests

OBSIDIAN_ISSUER = "https://auth.jyjwong.com"  # set to your Obsidian deployment
DEVICE_CERT = ("devices/my-server/my-server.crt", "devices/my-server/my-server.key")


def get_access_token() -> str:
    response = requests.post(f"{OBSIDIAN_ISSUER}/auth/token", cert=DEVICE_CERT)
    response.raise_for_status()
    return response.json()["access_token"]


def call_protected_api():
    token = get_access_token()
    response = requests.get(
        "https://api.jyjwong.com/reports",
        headers={"Authorization": f"Bearer {token}"},
    )
    response.raise_for_status()
    return response.json()
