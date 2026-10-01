#!/usr/bin/env python3
"""Extract WST# (guidebook text) resources from Oregon Trail resource fork to JSON.

Format: a big-endian 16-bit slot count followed by aligned 16-bit byte lengths
and Mac Roman payloads. Empty slots retain their indices; the final payload
needs no trailing alignment byte. Evidence: CD 1.2 CODE4:0b36-0bd0.

Output: assets/guidebook/wst_{id}.json
  {"id": int, "name": str, "entry_count": int, "entries": [{"index": int, "text": str}]}
"""

import json
import os
import struct
import macresources

RSRC_PATH = "raw/oregon_trail.rsrc"
OUT_DIR = "assets/guidebook"


def parse_wst_resource(data: bytes, res_id: int, res_name: str) -> dict:
    """Read length-prefixed strings without dropping empty slots or text bytes."""
    if len(data) < 2:
        raise ValueError(f"WST# {res_id}: truncated entry count")
    declared_count = struct.unpack_from(">H", data)[0]
    entries = []
    position = 2
    for index in range(declared_count):
        position += position % 2
        if position + 2 > len(data):
            raise ValueError(f"WST# {res_id}: truncated length for entry {index}")
        length = struct.unpack_from(">H", data, position)[0]
        position += 2
        if position + length > len(data):
            raise ValueError(f"WST# {res_id}: truncated text for entry {index}")
        text = data[position:position + length].decode("mac_roman")
        entries.append({"index": index, "text": text})
        position += length
    return {"id": res_id, "name": res_name, "entry_count": len(entries), "entries": entries}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    with open(RSRC_PATH, "rb") as f:
        raw = f.read()

    resources = list(macresources.parse_file(raw))
    wst_resources = [r for r in resources if r.type == b"WST#"]
    wst_resources.sort(key=lambda r: r.id)

    print(f"Found {len(wst_resources)} WST# resources")

    for r in wst_resources:
        result = parse_wst_resource(bytes(r.data), r.id, r.name)
        out_path = os.path.join(OUT_DIR, f"wst_{r.id}.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print(
            f"  WST# {r.id:5d} ({r.name:12s}): "
            f"{result['entry_count']:2d} entries → {out_path}"
        )

    produced = len([f for f in os.listdir(OUT_DIR) if f.endswith(".json")])
    print(f"\nExtracted {produced} WST# JSON files to {OUT_DIR}/")
    if produced != len(wst_resources):
        print(f"ERROR: expected {len(wst_resources)}, produced {produced}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
