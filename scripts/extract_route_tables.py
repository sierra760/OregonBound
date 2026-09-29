"""Extract route distances and landmark scene selection from original A5 data.

Instruction evidence and the boundary between travel and rafting are recorded in
docs/ORIGINAL_ROUTES.md. CODE resource paths have their four-byte header removed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct

import macresources
from extract_a5 import decode_initial_data

ROOT = Path(__file__).resolve().parents[1]
IDS = ('independence', 'kansas', 'big-blue', 'kearney', 'chimney', 'laramie',
       'rock', 'south-pass', 'bridger', 'green', 'soda', 'hall', 'snake',
       'boise', 'blue-mountains', 'walla', 'dalles')


def strings(data: bytes) -> list[str]:
    count = int.from_bytes(data[:2], 'big')
    result, pos = [], 2
    for _ in range(count):
        if pos >= len(data) or pos + 1 + data[pos] > len(data):
            raise ValueError('Truncated STR# table')
        size = data[pos]
        result.append(data[pos + 1:pos + 1 + size].decode('macroman'))
        pos += size + 1
    return result


def next_leg(current_index: int, route_flags: int, distances: list[list[int]]) -> tuple[int, int]:
    """CODE16:0x0d08–0x0da0, called at a stopped landmark, no obstruction.

    +0x238 is signed and starts at -1. The destination becomes currentIndex+1;
    mask1 at destination7 or mask2 at destination14 selects alternate length
    and skips that destination. Original stores the low byte of the word.
    """
    if not -1 <= current_index <= 15:
        raise ValueError('Not a departure landmark')
    destination = current_index + 1
    alternate = (destination == 7 and route_flags & 1) or (destination == 14 and route_flags & 2)
    miles = distances[destination][int(bool(alternate))] & 255
    return destination + int(bool(alternate)), miles


def extract(root: Path = ROOT) -> dict:
    source = root / 'assets/code_segments/CODE_21_A5Init.bin'
    memory = decode_initial_data(source.read_bytes())
    distances = [list(struct.unpack_from('>2H', memory, len(memory) - 0x2800 + 4*i))
                 for i in range(18)]
    # Includes the preceding word because Independence's signed index is -1.
    scenes = list(struct.unpack_from('>17H', memory, len(memory) - 0x27b8))
    main_resources = list(macresources.parse_file((root / 'raw/oregon_trail.rsrc').read_bytes()))
    names = strings(bytes(next(r.data for r in main_resources if r.type == b'STR#' and r.id == 3002)))
    nodes = []
    for index, (key, name, scene) in enumerate(zip(IDS, names, scenes)):
        nodes.append({'id': key, 'original_index': index - 1, 'name': name,
                      'name_str_index': index + 1, 'scene_code': scene,
                      'scene': {'resource_id': 15300 + scene // 2,
                                'monochrome_resource_id': 5300 + scene // 2,
                                'frame': scene % 2},
                      'scene_a5_offset': -0x27b8 + index * 2})
    edges = []
    for current in range(-1, 16):
        choices = (0, 1) if current == 6 else (0, 2) if current == 13 else (0,)
        for flags in choices:
            destination, miles = next_leg(current, flags, distances)
            alternate = bool(flags)
            edges.append({'source': IDS[current+1],
                          'destination': IDS[destination+1] if destination < 16 else 'overland-end',
                          'destination_index': destination, 'miles': miles,
                          'route_flag_mask': 1 if current == 6 else 2 if current == 13 else 0,
                          'route_flag_set': alternate,
                          'distance_table_index': current+1,
                          'distance_a5_offset': -0x2800 + (current+1)*4 + 2*int(alternate),
                          'mode': 'barlow-road' if current == 15 else 'trail'})
    return {'schema_version': 1,
            'evidence': {'initializer_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                         'distance_table_a5_offset': -0x2800,
                         'scene_table_a5_offset': -0x27b6,
                         'scene_code': 'CODE6:0x1558–0x15b4',
                         'route_code': 'CODE16:0x0d08–0x0da0',
                         'landmark_names': 'STR#3002[1...17]'},
            'raw_distance_pairs': distances, 'landmarks': nodes, 'edges': edges,
            'terminal': {'id': 'overland-end', 'original_index': 16, 'scene': None,
                         'evidence': 'CODE16:0x25b6–0x25ec invokes ending at index16'},
            'rafting': {'source': 'dalles', 'miles': None, 'name': names[18],
                        'route_flag_mask': 4, 'mode': 'minigame',
                        'evidence': 'CODE1:0x36dc–0x370e dispatches command10 and returns'},
            'limits': ['No ending image is inferred from the adjacent A5 word or artwork.',
                       'Fixed leg distances do not describe daily movement or rafting progress.',
                       'Climate regions, map polylines, talk tables, and guide-topic names are not extracted.']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, default=ROOT / 'assets/metadata/original_routes.json')
    args = parser.parse_args()
    result = extract(args.root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
