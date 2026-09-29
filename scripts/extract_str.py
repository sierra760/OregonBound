#!/usr/bin/env python3
"""Extract all STR# (string list) resources from Oregon Trail resource fork to JSON.

Format per Inside Macintosh:
  2-byte big-endian count
  count × Pascal strings: 1-byte length + Mac Roman bytes

Output: assets/strings/str_{id}.json
  {"id": int, "count": int, "strings": ["...", ...]}
"""

import json
import os
import struct
import macresources

RSRC_PATH = "raw/oregon_trail.rsrc"
OUT_DIR = "assets/strings"


def parse_str_resource(data: bytes, res_id: int) -> dict:
    """Parse a STR# resource and return a dict."""
    if len(data) < 2:
        return {"id": res_id, "count": 0, "strings": []}

    count = struct.unpack(">H", data[:2])[0]
    strings = []
    pos = 2
    for i in range(count):
        if pos >= len(data):
            print(f"  WARNING: ran out of data at string {i} of {count} in STR# {res_id}")
            break
        slen = data[pos]
        pos += 1
        raw = data[pos : pos + slen]
        text = raw.decode("mac_roman", errors="replace")
        strings.append(text)
        pos += slen

    if len(strings) != count:
        print(f"  WARNING: STR# {res_id} expected {count} strings, got {len(strings)}")

    return {"id": res_id, "count": count, "strings": strings}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    with open(RSRC_PATH, "rb") as f:
        raw = f.read()

    resources = list(macresources.parse_file(raw))
    str_resources = [r for r in resources if r.type == b"STR#"]
    str_resources.sort(key=lambda r: r.id)

    print(f"Found {len(str_resources)} STR# resources")

    for r in str_resources:
        result = parse_str_resource(bytes(r.data), r.id)
        out_path = os.path.join(OUT_DIR, f"str_{r.id}.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print(f"  STR# {r.id:5d}: {result['count']:3d} strings → {out_path}")

    # Verify
    produced = len([f for f in os.listdir(OUT_DIR) if f.endswith(".json")])
    print(f"\nExtracted {produced} STR# JSON files to {OUT_DIR}/")
    if produced != len(str_resources):
        print(f"ERROR: expected {len(str_resources)}, produced {produced}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
