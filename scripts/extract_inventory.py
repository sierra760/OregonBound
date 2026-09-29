#!/usr/bin/env python3
"""
extract_inventory.py

Parses Oregon Trail and Oregon Color resource forks and produces
assets/resource_inventory.json with a record for every resource found.

Each record contains:
  - type: 4-char resource type code
  - id: integer resource ID
  - name: resource name string (empty string if unnamed)
  - data_length: byte count of the resource data
  - source_file: "oregon_trail" or "oregon_color"
  - output_path: placeholder path (populated by later extraction tasks)
"""

import json
import pathlib
import sys

import macresources

WORKTREE_ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW_DIR = WORKTREE_ROOT / "raw"
ASSETS_DIR = WORKTREE_ROOT / "assets"

SOURCE_FILES = {
    "oregon_trail": RAW_DIR / "oregon_trail.rsrc",
    "oregon_color": RAW_DIR / "oregon_color.rsrc",
}

# Expected counts for sanity check
EXPECTED_COUNTS = {
    "oregon_trail": 406,
    "oregon_color": 62,
}


def parse_rsrc(path: pathlib.Path, source_name: str) -> list[dict]:
    """Parse a .rsrc file and return a list of resource records."""
    raw = path.read_bytes()
    resources = list(macresources.parse_file(raw))
    records = []
    for res in resources:
        # macresources resource attributes
        rtype = res.type.decode("mac_roman") if isinstance(res.type, bytes) else str(res.type)
        rid = res.id
        rname = res.name or ""
        if isinstance(rname, bytes):
            rname = rname.decode("mac_roman", errors="replace")
        data_len = len(res)
        records.append({
            "type": rtype,
            "id": rid,
            "name": rname,
            "data_length": data_len,
            "source_file": source_name,
            "output_path": "",
        })
    return records


def main():
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)

    inventory = []
    counts = {}

    for source_name, path in SOURCE_FILES.items():
        if not path.exists():
            print(f"ERROR: {path} not found", file=sys.stderr)
            sys.exit(1)
        records = parse_rsrc(path, source_name)
        counts[source_name] = len(records)
        print(f"  {source_name}: {len(records)} resources parsed")
        inventory.extend(records)

    # Sanity check counts
    all_ok = True
    for source_name, expected in EXPECTED_COUNTS.items():
        actual = counts.get(source_name, 0)
        status = "OK" if actual == expected else f"MISMATCH (expected {expected})"
        print(f"  {source_name} count: {actual} — {status}")
        if actual != expected:
            all_ok = False

    out_path = ASSETS_DIR / "resource_inventory.json"
    out_path.write_text(json.dumps(inventory, indent=2, ensure_ascii=False))
    print(f"\nWrote {len(inventory)} records to {out_path}")

    # Print type breakdown
    from collections import Counter
    type_counts = Counter(r["type"] for r in inventory)
    print("\nResource type breakdown (all sources):")
    for rtype, count in sorted(type_counts.items(), key=lambda x: -x[1]):
        print(f"  {rtype!r:10s}: {count}")

    if not all_ok:
        print("\nWARNING: Resource counts do not match expected values.", file=sys.stderr)
        # Don't exit 1 — counts may differ from plan estimates; inventory is still valid.

    return 0


if __name__ == "__main__":
    sys.exit(main())
