#!/usr/bin/env python3
"""Extract HVof (map viewport scroll offsets) and ORGN (version string) resources.

HVof format: pairs of signed bytes (dx, dy) — map viewport scroll offsets for each
trail map section. Resource names identify the trail region.
Output: assets/map_viewports/hvof_{id}.json
  {"id": int, "name": str, "point_count": int, "points": [{"dx": int, "dy": int}]}

ORGN format: plain Mac Roman text — version/copyright string.
Output: assets/metadata/orgn.json
  {"id": int, "text": str, "source_file": str}
"""

import json
import os
import struct
import macresources

RSRC_PATH = "raw/oregon_trail.rsrc"
HVOF_OUT_DIR = "assets/map_viewports"
ORGN_OUT_DIR = "assets/metadata"


def parse_hvof_resource(data: bytes, res_id: int, res_name: str) -> dict:
    """Parse HVof resource as an array of signed byte pairs (dx, dy)."""
    byte_count = len(data)
    pair_count = byte_count // 2
    if byte_count % 2 != 0:
        print(f"  WARNING: HVof {res_id} has odd byte count {byte_count}; ignoring last byte")

    pairs = struct.unpack(">" + "bb" * pair_count, data[: pair_count * 2])
    points = [{"dx": pairs[i * 2], "dy": pairs[i * 2 + 1]} for i in range(pair_count)]

    return {
        "id": res_id,
        "name": res_name,
        "point_count": pair_count,
        "points": points,
    }


def parse_orgn_resource(data: bytes, res_id: int, source_file: str) -> dict:
    """Parse ORGN resource as plain Mac Roman text."""
    text = data.decode("mac_roman", errors="replace").strip()
    return {"id": res_id, "text": text, "source_file": source_file}


def main():
    os.makedirs(HVOF_OUT_DIR, exist_ok=True)
    os.makedirs(ORGN_OUT_DIR, exist_ok=True)

    with open(RSRC_PATH, "rb") as f:
        raw = f.read()

    resources = list(macresources.parse_file(raw))

    # --- HVof extraction ---
    hvof_resources = [r for r in resources if r.type == b"HVof"]
    hvof_resources.sort(key=lambda r: r.id)

    print(f"Found {len(hvof_resources)} HVof resources")
    for r in hvof_resources:
        result = parse_hvof_resource(bytes(r.data), r.id, r.name)
        out_path = os.path.join(HVOF_OUT_DIR, f"hvof_{r.id}.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print(
            f"  HVof {r.id:3d} ({r.name:30s}): "
            f"{result['point_count']:3d} points → {out_path}"
        )

    hvof_produced = len([f for f in os.listdir(HVOF_OUT_DIR) if f.endswith(".json")])
    print(f"\nExtracted {hvof_produced} HVof JSON files to {HVOF_OUT_DIR}/")
    if hvof_produced != len(hvof_resources):
        print(f"ERROR: expected {len(hvof_resources)}, produced {hvof_produced}")
        return 1

    # --- ORGN extraction ---
    orgn_resources = [r for r in resources if r.type == b"ORGN"]
    print(f"\nFound {len(orgn_resources)} ORGN resource(s)")

    if not orgn_resources:
        print("WARNING: No ORGN resource found")
        return 1

    r = orgn_resources[0]
    result = parse_orgn_resource(bytes(r.data), r.id, RSRC_PATH)
    out_path = os.path.join(ORGN_OUT_DIR, f"orgn.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f"  ORGN {r.id}: {repr(result['text'])} → {out_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
