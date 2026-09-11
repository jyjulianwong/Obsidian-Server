#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["boto3"]
# ///
"""Provisions a new device: issues a client certificate signed by the
Obsidian device CA and registers the device as active in DynamoDB.

Usage:
    ./scripts/provision_device.py my-laptop \
        --table-name "$(terraform -chdir=terraform output -raw devices_table_name)"

uv reads the inline metadata above and installs boto3 into an ephemeral
venv automatically — no need to activate server/'s venv or install anything
by hand first.
"""

import argparse
import datetime
import subprocess
import sys
from pathlib import Path

import boto3

ROOT = Path(__file__).resolve().parent.parent
CA_DIR = ROOT / "ca"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("device_id", help="Unique device identifier — becomes the certificate's CN")
    parser.add_argument("--days", type=int, default=90, help="Certificate validity in days (default: 90)")
    parser.add_argument("--table-name", required=True, help="DynamoDB devices table name")
    parser.add_argument("--region", default="eu-west-2")
    args = parser.parse_args()

    ca_key = CA_DIR / "ca.key"
    ca_crt = CA_DIR / "ca.crt"
    if not ca_key.exists() or not ca_crt.exists():
        sys.exit(f"CA not found in {CA_DIR} — run scripts/generate_ca.sh first")

    out_dir = ROOT / "devices" / args.device_id
    out_dir.mkdir(parents=True, exist_ok=True)
    key_path = out_dir / f"{args.device_id}.key"
    csr_path = out_dir / f"{args.device_id}.csr"
    crt_path = out_dir / f"{args.device_id}.crt"

    subprocess.run(["openssl", "genrsa", "-out", str(key_path), "2048"], check=True)
    subprocess.run(
        [
            "openssl", "req", "-new",
            "-key", str(key_path),
            "-out", str(csr_path),
            "-subj", f"/CN={args.device_id}",
        ],
        check=True,
    )
    subprocess.run(
        [
            "openssl", "x509", "-req",
            "-in", str(csr_path),
            "-CA", str(ca_crt),
            "-CAkey", str(ca_key),
            "-CAcreateserial",
            "-out", str(crt_path),
            "-days", str(args.days),
            "-sha256",
        ],
        check=True,
    )

    table = boto3.resource("dynamodb", region_name=args.region).Table(args.table_name)
    table.put_item(
        Item={
            "device_id": args.device_id,
            "status": "active",
            "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        }
    )

    print(f"Registered '{args.device_id}' as active in {args.table_name}")
    print()
    print("Install on the device:")
    print(f"  key:  {key_path}")
    print(f"  cert: {crt_path}")
    print()
    print("See README 'Installing a device certificate' for OS-specific import steps.")


if __name__ == "__main__":
    main()
