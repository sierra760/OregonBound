"""Decode CD hunting terrain entry permissions and animal collision rectangles."""
from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


def parse_terrain_resource(data: bytes, resource_id: int) -> dict:
    if len(data) < 6:
        raise ValueError(f"Truncated TERR {resource_id} header")
    left, right, count = struct.unpack_from('>hhh', data)
    if count < 0 or len(data) != 6 + count * 8:
        raise ValueError(f"Invalid TERR {resource_id} rectangle count or payload length")
    obstacles = []
    for index in range(count):
        top, x1, bottom, x2 = struct.unpack_from('>hhhh', data, 6 + index * 8)
        if bottom <= top or x2 <= x1:
            raise ValueError(f"Invalid TERR {resource_id} rectangle {index}")
        obstacles.append(dict(top=top, left=x1, bottom=bottom, right=x2))
    return dict(resource_id=resource_id, left_entry_allowed=left != 0,
                right_entry_allowed=right != 0, obstacles=obstacles)


def extract(input_path: Path, output_dir: Path) -> int:
    import macresources
    decoded = [parse_terrain_resource(bytes(resource), resource.id)
               for resource in macresources.parse_file(input_path.read_bytes()) if resource.type == b'TERR']
    output_dir.mkdir(parents=True, exist_ok=True)
    for terrain in decoded:
        (output_dir / f"terr_{terrain['resource_id']}.json").write_text(json.dumps(terrain, indent=2) + '\n')
    return len(decoded)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(f"Decoded {extract(args.input, args.output)} terrain resources")
