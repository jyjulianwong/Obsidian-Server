#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["boto3"]
# ///
"""Revokes a device's access by marking it inactive in the devices table.

This is the app-level kill switch: the certificate itself stays
cryptographically valid until it expires (see README 'Revocation'), but
/auth/token starts refusing the device immediately.

Usage:
    ./scripts/revoke_device.py my-laptop \
        --table-name "$(terraform -chdir=terraform output -raw devices_table_name)"
"""

import argparse

import boto3


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("device_id")
    parser.add_argument("--table-name", required=True)
    parser.add_argument("--region", default="eu-west-2")
    args = parser.parse_args()

    table = boto3.resource("dynamodb", region_name=args.region).Table(args.table_name)
    table.update_item(
        Key={"device_id": args.device_id},
        UpdateExpression="SET #s = :revoked",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":revoked": "revoked"},
    )
    print(f"'{args.device_id}' marked revoked — refused at /auth/token on its next request")


if __name__ == "__main__":
    main()
