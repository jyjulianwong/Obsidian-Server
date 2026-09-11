import os

import boto3

_TABLE_NAME = os.environ.get("OBSIDIAN_DEVICES_TABLE_NAME", "")
_table = boto3.resource("dynamodb").Table(_TABLE_NAME) if _TABLE_NAME else None


def is_device_active(device_id: str) -> bool:
    if _table is None:
        raise RuntimeError("OBSIDIAN_DEVICES_TABLE_NAME is not set")

    response = _table.get_item(Key={"device_id": device_id})
    item = response.get("Item")
    return item is not None and item.get("status") == "active"
