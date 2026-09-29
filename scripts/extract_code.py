#!/usr/bin/env python3
"""Extract all 22 CODE segments as raw 68k binaries with parsed segment headers.

CODE 0 (Jump Table):
  16-byte header: above_a5 size (4), below_a5 size (4), jt_size (4), jt_offset (4)
  Saved as full raw resource data (header + jump table body).

CODE 1-21:
  4-byte header: near_model_offset (2, big-endian unsigned short),
                 far_model_entry_count (2, big-endian unsigned short)
  Saved as code bytes AFTER stripping the 4-byte header.

Output:
  assets/code_segments/CODE_{id}_{name}.bin  — one per segment
  assets/code_segments/code_metadata.json    — array of segment objects
"""

import json
import os
import struct
import sys
import macresources

RSRC_PATH = "raw/oregon_trail.rsrc"
OUT_DIR = "assets/code_segments"

# Fallback names for segments whose resource-fork name is empty.
# CODE 0 has no name in the fork; all others have names matching the task plan.
FALLBACK_NAMES = {
    0: "JumpTable",
}


def clean_name(name: str) -> str:
    """Strip leading % from resource names (e.g. %A5Init → A5Init)."""
    return name.lstrip("%")


def parse_code0_header(data: bytes) -> dict:
    """Parse the 16-byte CODE 0 jump table header."""
    if len(data) < 16:
        raise ValueError(f"CODE 0 too short: {len(data)} bytes")
    above_a5, below_a5, jt_size, jt_offset = struct.unpack(">IIII", data[:16])
    return {
        "above_a5_size": above_a5,
        "below_a5_size": below_a5,
        "jump_table_size": jt_size,
        "jump_table_offset": jt_offset,
    }


def parse_code_header(data: bytes, res_id: int) -> dict:
    """Parse the 4-byte header for CODE 1-21."""
    if len(data) < 4:
        raise ValueError(f"CODE {res_id} too short: {len(data)} bytes")
    near_model_offset, far_model_entry_count = struct.unpack(">HH", data[:4])
    return {
        "near_model_offset": near_model_offset,
        "far_model_entry_count": far_model_entry_count,
    }


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)

    with open(RSRC_PATH, "rb") as f:
        raw = f.read()

    resources = list(macresources.parse_file(raw))
    code_resources = [r for r in resources if r.type == b"CODE"]
    code_resources.sort(key=lambda r: r.id)

    print(f"Found {len(code_resources)} CODE resources")

    metadata = []
    errors = []

    for r in code_resources:
        res_id = r.id
        if r.name is None:
            raw_name = ""
        elif isinstance(r.name, bytes):
            raw_name = r.name.decode("mac_roman", errors="replace")
        else:
            raw_name = r.name
        name = clean_name(raw_name) if raw_name else FALLBACK_NAMES.get(res_id, f"Seg{res_id}")
        data = bytes(r.data)
        raw_size = len(data)

        try:
            if res_id == 0:
                # CODE 0: full raw data (header + jump table body)
                header_values = parse_code0_header(data)
                code_bytes = data  # save everything including header
                code_size = raw_size
                header_type = "jump_table_16b"
            else:
                # CODE 1-21: strip 4-byte header, save remaining as code
                header_values = parse_code_header(data, res_id)
                code_bytes = data[4:]
                code_size = len(code_bytes)
                header_type = "near_far_4b"

            filename = f"CODE_{res_id}_{name}.bin"
            out_path = os.path.join(OUT_DIR, filename)
            with open(out_path, "wb") as f:
                f.write(code_bytes)

            seg_meta = {
                "id": res_id,
                "name": name,
                "raw_size": raw_size,
                "code_size": code_size,
                "header_type": header_type,
                "header_values": header_values,
                "output_path": out_path,
            }
            metadata.append(seg_meta)
            print(
                f"  CODE {res_id:3d} ({name:15s}): raw={raw_size:6d} B  code={code_size:6d} B → {filename}"
            )

        except Exception as exc:
            errors.append(f"CODE {res_id}: {exc}")
            print(f"  ERROR CODE {res_id}: {exc}", file=sys.stderr)

    # Write metadata JSON
    meta_path = os.path.join(OUT_DIR, "code_metadata.json")
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2)
    print(f"\nWrote metadata for {len(metadata)} segments → {meta_path}")

    # Verify
    bin_files = [f for f in os.listdir(OUT_DIR) if f.endswith(".bin")]
    print(f"Total .bin files in {OUT_DIR}: {len(bin_files)}")

    if errors:
        print(f"\n{len(errors)} errors:")
        for e in errors:
            print(f"  {e}")
        return 1

    if len(metadata) != 22:
        print(f"ERROR: expected 22 segments, got {len(metadata)}")
        return 1

    # Confirm no zero-size code
    zero_size = [m for m in metadata if m["code_size"] == 0]
    if zero_size:
        print(f"ERROR: {len(zero_size)} segments have code_size=0")
        return 1

    print("\nAll 22 CODE segments extracted successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
