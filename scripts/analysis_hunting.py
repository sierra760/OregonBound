"""Binary-backed hunting oracle. CODE13 offsets exclude the four-byte CODE header.

Random(n) is injected so tests preserve the original RNG call order without
inventing seeds. This is a mechanics oracle, not a complete hunt UI/controller.
"""
from __future__ import annotations

from dataclasses import dataclass
import argparse
import json
from pathlib import Path
import struct
from typing import Callable

import macresources
from extract_a5 import decode_initial_data
from analysis_animation import decode_frame_bounds
from extract_ditl import parse_ditl_resource

ROOT = Path(__file__).resolve().parents[1]
Random = Callable[[int], int]
TABLES = {
    'food_random_span': (-0x2534, 7), 'food_base': (-0x2526, 7),
    'frame_period': (-0x2518, 7), 'speed': (-0x250a, 7),
    'death_frame_count': (-0x24fc, 7), 'last_frame': (-0x24ee, 7),
    'hunt_seconds_by_setting': (-0x22b4, 7),
}


def read_tables(root: Path = ROOT) -> dict[str, list[int]]:
    memory = decode_initial_data((root / 'assets/code_segments/CODE_21_A5Init.bin').read_bytes())
    return {name: list(struct.unpack_from(f'>{count}h', memory, len(memory) + offset))
            for name, (offset, count) in TABLES.items()}


def initial_weights(destination: int, month: int, repeated_area: bool) -> list[int]:
    """CODE13:01bc–0320, before random removal down to two species."""
    small = 20 if repeated_area else 40
    weights = [15 if destination < 7 else 8,
               10 if 10 <= destination <= 14 else 25, small, small, 0, 0, 0]
    if 2 < destination < 13:
        weights[6] = 7 if destination in (3, 12) else 20
    if destination == 4 or 10 < destination < 14:
        weights[4] = 8
    elif destination > 4:
        weights[4] = 15
    if 3 < month < 11:
        if destination > 12:
            weights[5] = 10
        elif destination > 5:
            weights[5] = 5
    return weights


def choose_population(destination: int, month: int, repeated_area: bool, random: Random) -> list[int]:
    """CODE13:0320–038e. Rejection sampling matters to the RNG sequence."""
    weights = initial_weights(destination, month, repeated_area)
    if not repeated_area:
        weights[random(2) + 2] = 0
    while sum(weight != 0 for weight in weights) > 2:
        species = random(7)
        if weights[species] != 0:
            weights[species] = 0
    return weights


def choose_species(weights: list[int], roll: int) -> int:
    """CODE13:1292–12d6 traverses species6 down to0, not forward."""
    if len(weights) != 7 or not 0 <= roll < sum(weights):
        raise ValueError('Invalid population/roll')
    for species in range(6, -1, -1):
        if weights[species] > roll:
            return species
        roll -= weights[species]
    raise AssertionError('Unreachable weighted selection')


def spawn_attempt(*, repeated_area: bool, now_tick: int, end_tick: int,
                  living: int, kills_in_scene: int, random: Random) -> bool:
    """CODE13:0ee0–0f24 then1266. RNG occurs even when capacity prevents creation."""
    if random(150 if repeated_area else 50) != 7:
        return False
    # next deadline = now+3; subtracting -177 at0f18 means now+180 < end.
    return now_tick + 180 < end_tick and living < 2 and kills_in_scene < 4


def spawn_origin(width: int, height: int, from_left: bool, random: Random) -> tuple[int, int]:
    """CODE13:1346/13aa/13fa: full-window top-left coordinates."""
    return (9 - width if from_left else 503, 59 + random(166 - height))


def can_turn(left: int, right: int, roll100: int) -> bool:
    """CODE13:155a–1588. Roll is consumed before the bounds checks."""
    return roll100 < 2 and left >= 9 and right <= 503


def deplete_population(weights: list[int], species: int, repeated_area: bool) -> list[int]:
    """CODE13:1880–18d8; small animals2/3 do not deplete."""
    result = weights.copy()
    if species not in (2, 3):
        result[species] -= result[species] // 2
        if not repeated_area and result[species] == 1:
            result[species] = 0
    return result


def earned_food(species: int, tables: dict[str, list[int]], random: Random) -> int:
    """CODE13:18dc–190a, invokes Random(1), whose original wrapper returns0 without advancing RNG."""
    return tables['food_base'][species] + random(tables['food_random_span'][species])


def scenery_plan(destination: int, month: int, snow: bool, display_flag: bool,
                 random: Random, frame_sizes: list[tuple[int,int]]) -> list[dict]:
    """CODE13:193a–1b5e. All scenery is blocking class2; frame count is a separate argument."""
    allowed = destination != 4
    forest = destination > 4
    omit_first = destination < 2 if destination <= 4 else (destination == 5 or 6 < destination < 11 or destination > 13)
    bound = 1 if display_flag else 3
    objects = []
    def add(base, count):
        frame = base + random(count)
        width,height = frame_sizes[frame]
        objects.append({'frame':frame,'kind':2,'x':9+random(494-width),'y':59+random(166-height)})
    if not omit_first:
        count = random(bound) + (1 if allowed else 4)
        for _ in range(count): add(12 if snow else 4,2)
    count = random(bound) + (3 if omit_first else 1)
    offset = 8 if snow or (not forest and not 4 <= month <= 9) else 0
    if allowed:
        for _ in range(count): add((9 if forest else 7)+offset,3 if forest else 1)
    return objects


def carried_food(shot_food: int, surviving_party_members: int, current_food: int, capacity: int) -> int:
    """CODE13:03b4–03ee/0f88–0fa4/04fa–051e; field world+262+110*selected."""
    return min(shot_food, 200 if surviving_party_members > 1 else 100, max(0, capacity-current_food))


def trunc_div(numerator: int, denominator: int) -> int:
    return (abs(numerator) // abs(denominator)) * (-1 if (numerator < 0) != (denominator < 0) else 1)


@dataclass
class Projectile:
    """CODE13:1676–1832 plus CODE5 signed16.16 movement helpers.

    N movement callbacks are followed by one impact callback. A duration0 shot
    arrives immediately at its target but still resolves on the first callback.
    """
    target_x: int
    target_y: int
    x: int = 256
    y: int = 228
    remaining: int = 0
    fixed_x: int = 0
    fixed_y: int = 0
    velocity_x: int = 0
    velocity_y: int = 0
    resolved: bool = False

    def __post_init__(self):
        dx, dy = self.target_x-self.x, self.target_y-self.y
        self.remaining = max(abs(dx), abs(dy)) // 20
        if self.remaining:
            self.fixed_x, self.fixed_y = self.x << 16, self.y << 16
            self.velocity_x = trunc_div(dx << 16, self.remaining)
            self.velocity_y = trunc_div(dy << 16, self.remaining)
        else:
            self.x, self.y = self.target_x, self.target_y

    def step(self) -> bool:
        if self.resolved:
            return False
        if self.remaining:
            self.fixed_x += self.velocity_x
            self.fixed_y += self.velocity_y
            self.x = (self.fixed_x + 0x8000) >> 16
            self.y = (self.fixed_y + 0x8000) >> 16
            self.remaining -= 1
            return False
        self.resolved = True
        return True


@dataclass(frozen=True)
class HitObject:
    kind: int  # species-8 for live animals; species+3 dead; scenery2 blocks.
    rect: tuple[int, int, int, int]  # top,left,bottom,right


def impact_target(x: int, y: int, objects_in_update_order: list[HitObject]) -> int | None:
    """CODE13:1832–187e. Rectangle tests deliberately ignore sprite mask pixels."""
    for index, obj in enumerate(objects_in_update_order):
        if obj.kind >= 0 and obj.kind != 2:
            continue
        top, left, bottom, right = obj.rect
        if left <= x < right and top <= y < bottom:
            return index  # kind2 blocks; caller must not score it as an animal.
    return None


def accepts_shot(ammunition: int, shots: int, projectile_in_flight: bool) -> bool:
    return not projectile_in_flight and shots < min(ammunition, 20)


def timed_out(now_tick: int, end_tick: int, projectile_in_flight: bool) -> bool:
    return now_tick > end_tick and not projectile_in_flight


def extract(root: Path = ROOT) -> dict:
    color = {(r.type, r.id): bytes(r) for r in macresources.parse_file((root/'raw/oregon_color.rsrc').read_bytes())}
    main = {(r.type, r.id): bytes(r) for r in macresources.parse_file((root/'raw/oregon_trail.rsrc').read_bytes())}
    return {'schema_version': 1, 'tables': read_tables(root),
            'table_a5_offsets': {k: v[0] for k,v in TABLES.items()},
            'frames': {rid: decode_frame_bounds(color[b'Imag',rid]) for rid in range(19160,19168)},
            'dialog': parse_ditl_resource(main[b'DITL',9160],9160),
            'tick_interval':3, 'bullet_origin':[256,228], 'max_ammunition':20,
            'max_live_animals':2, 'max_kills_per_scene':4,
            'limits':['Complete UI event dispatch/key routing is not ported.',
                      'Journey hunting day/action scheduling is not traced by this oracle.']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path)
    args = parser.parse_args()
    result = json.dumps(extract(),indent=2)+'\n'
    if args.output: args.output.write_text(result)
    else: print(result,end='')
