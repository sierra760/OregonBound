#!/usr/bin/env python3
"""Extract WST# (guidebook text) resources from Oregon Trail resource fork to JSON.

Format (MECC-proprietary):
  2-byte big-endian entry count (always 3, though final resource may have fewer real entries)
  Followed by entries, each delimited by 0x01 byte:
    0x01 marker | 1-byte metadata/style byte | Mac Roman text bytes
  Entries are separated by 0x01; the data begins with 0x01 before the first entry.
  Text trailing null bytes are stripped.

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
    """Parse a WST# resource using 0x01-delimited entry format.

    Each entry is: 0x01 separator + 1-byte metadata/style + text (to next 0x01 or EOF).
    The style byte is not interpreted—it appears to be a display/font code.
    """
    if len(data) < 2:
        return {"id": res_id, "name": res_name, "entry_count": 0, "entries": []}

    declared_count = struct.unpack(">H", data[:2])[0]

    # Split the payload (after 2-byte count) by the 0x01 entry delimiter
    parts = data[2:].split(b"\x01")
    # Part 0 is always empty because data starts with 0x01
    # Parts 1..N each begin with a 1-byte metadata field followed by entry text
    entries = []
    for idx, part in enumerate(parts):
        if not part:
            continue  # skip empty (Part 0, or padding nulls)
        # First byte is metadata/style; remainder is text
        text_bytes = part[1:].rstrip(b"\x00")
        text = text_bytes.decode("mac_roman", errors="replace")
        if text:  # skip truly empty entries (e.g. null-padded tail in last resource)
            entries.append({"index": len(entries), "text": text})

    if len(entries) != declared_count:
        print(
            f"  NOTE: WST# {res_id} declared count={declared_count}, "
            f"extracted {len(entries)} entries"
        )

    return {
        "id": res_id,
        "name": res_name,
        "entry_count": len(entries),
        "entries": entries,
    }


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
