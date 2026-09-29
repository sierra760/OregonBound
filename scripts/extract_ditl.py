#!/usr/bin/env python3
"""Extract all DITL (dialog item list) resources from Oregon Trail resource fork to JSON.

Format per Inside Macintosh:
  2-byte big-endian (item_count - 1)
  For each item:
    4-byte placeholder (reserved, skip)
    8-byte bounding Rect: top, left, bottom, right (2-byte big-endian signed each)
    1-byte item type (lower 7 bits used; bit 7 = disabled flag)
    1-byte data length
    data bytes (padded to even length)

Item type values (lower 7 bits):
  0  = userItem
  4  = button
  5  = checkbox
  6  = radio
  7  = control (resource ID in data)
  8  = staticText
  16 = editText
  32 = icon (resource ID in data)
  64 = picture (resource ID in data)

Output: assets/dialogs/ditl_{id}.json
  {"id": int, "item_count": int, "items": [
    {"type": str, "disabled": bool, "bounds": {"top": int, "left": int, "bottom": int, "right": int}, "data": ...},
    ...
  ]}
"""

import json
import os
import struct
import macresources

RSRC_PATH = "raw/oregon_trail.rsrc"
OUT_DIR = "assets/dialogs"

TYPE_NAMES = {
    0: "userItem",
    4: "button",
    5: "checkbox",
    6: "radio",
    7: "control",
    8: "staticText",
    16: "editText",
    32: "icon",
    64: "picture",
}

# Item types whose data field is a 2-byte resource ID
RESOURCE_ID_TYPES = {7, 32, 64}


def decode_item_data(item_type: int, raw: bytes) -> object:
    """Decode item-specific data based on type."""
    if item_type in RESOURCE_ID_TYPES:
        if len(raw) >= 2:
            return struct.unpack(">H", raw[:2])[0]
        return None
    # Text-bearing types (button, checkbox, radio, staticText) or unknown
    if raw:
        return raw.decode("mac_roman", errors="replace")
    return ""


def parse_ditl_resource(data: bytes, res_id: int) -> dict:
    """Parse a DITL resource and return a dict."""
    if len(data) < 2:
        return {"id": res_id, "item_count": 0, "items": []}

    cnt_minus_1 = struct.unpack(">H", data[:2])[0]
    item_count = cnt_minus_1 + 1
    items = []
    pos = 2

    for i in range(item_count):
        if pos + 14 > len(data):
            print(f"  WARNING: ran out of data at item {i} of {item_count} in DITL {res_id}")
            break

        # 4-byte placeholder
        pos += 4

        # 8-byte bounding rect
        top, left, bottom, right = struct.unpack(">hhhh", data[pos : pos + 8])
        pos += 8

        # 1-byte type (bit 7 = disabled flag, lower 7 bits = type code)
        type_byte = data[pos]
        pos += 1
        disabled = bool(type_byte & 0x80)
        item_type_code = type_byte & 0x7F
        type_name = TYPE_NAMES.get(item_type_code, f"unknown_{item_type_code}")

        # 1-byte data length (always present, padded to even on disk)
        data_len = data[pos]
        pos += 1
        padded_len = data_len + (data_len % 2)  # round up to even
        raw_item_data = data[pos : pos + data_len]
        pos += padded_len

        decoded = decode_item_data(item_type_code, raw_item_data)

        items.append(
            {
                "type": type_name,
                "disabled": disabled,
                "bounds": {"top": top, "left": left, "bottom": bottom, "right": right},
                "data": decoded,
            }
        )

    return {"id": res_id, "item_count": item_count, "items": items}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    with open(RSRC_PATH, "rb") as f:
        raw = f.read()

    resources = list(macresources.parse_file(raw))
    ditl_resources = [r for r in resources if r.type == b"DITL"]
    ditl_resources.sort(key=lambda r: r.id)

    print(f"Found {len(ditl_resources)} DITL resources")

    for r in ditl_resources:
        result = parse_ditl_resource(bytes(r.data), r.id)
        out_path = os.path.join(OUT_DIR, f"ditl_{r.id}.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print(f"  DITL {r.id:5d}: {result['item_count']:3d} items → {out_path}")

    # Verify
    produced = len([f for f in os.listdir(OUT_DIR) if f.endswith(".json")])
    print(f"\nExtracted {produced} DITL JSON files to {OUT_DIR}/")
    if produced != len(ditl_resources):
        print(f"ERROR: expected {len(ditl_resources)}, produced {produced}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
