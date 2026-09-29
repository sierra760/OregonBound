"""Recover title animation arguments directly from original CODE 4 instructions.

Offsets refer to assets/code_segments binaries (four-byte CODE headers removed).
No disassembler package is needed: the decoder accepts only the immediate
push instructions present in these verified, straight-line initializer blocks.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import struct


@dataclass(frozen=True)
class Track:
    first: int
    last: int
    x: int
    y: int
    pause_base: int
    random_span: int
    period: int
    repeats: int
    motion: str
    call_offset: int


def decode_setup_block(code: bytes, start: int, end: int) -> list[Track]:
    """Decode moveq/move.l/pea/jsr argument sequences, rejecting unknown code."""
    registers: dict[int, int] = {}
    stack: list[int] = []
    tracks = []
    cursor = start
    while cursor < end:
        if cursor + 2 > len(code):
            raise ValueError("Truncated title initializer")
        op = struct.unpack_from(">H", code, cursor)[0]
        if op & 0xF100 == 0x7000:  # MOVEQ #signed8,Dn
            registers[(op >> 9) & 7] = struct.unpack("b", bytes([op & 255]))[0]
            cursor += 2
        elif op & 0xFFF8 == 0x2F00:  # MOVE.L Dn,-(SP)
            if op & 7 not in registers:
                raise ValueError("Uninitialized title argument register")
            stack.append(registers[op & 7])
            cursor += 2
        elif op == 0x4878:  # PEA absolute word, used to push a signed constant
            stack.append(struct.unpack_from(">h", code, cursor + 2)[0])
            cursor += 4
        elif op == 0x4EBA:  # JSR displacement(PC)
            target = cursor + 2 + struct.unpack_from(">h", code, cursor + 2)[0]
            if target not in (0x240, 0x330) or len(stack) != 8:
                raise ValueError("Unexpected title initializer call or argument count")
            tracks.append(Track(*reversed(stack), "loop" if target == 0x240 else "pingpong", cursor))
            stack.clear()
            # Calls clobber registers. Every following sequence initializes its own.
            registers.clear()
            cursor += 4
        else:
            raise ValueError(f"Unsupported title instruction 0x{op:04x} at 0x{cursor:04x}")
    if cursor != end or stack:
        raise ValueError("Incomplete title initializer block")
    return tracks


def decode_title_tracks(code: bytes, color_depth: int = 8) -> list[Track]:
    common = decode_setup_block(code, 0x9A4, 0xA54)
    middle = decode_setup_block(code, 0xA66, 0xAF2) if color_depth >= 3 else decode_setup_block(code, 0xAFA, 0xB86)
    return common + middle + decode_setup_block(code, 0xB8A, 0xBD2)


def decode_frame_bounds(resource: bytes) -> list[dict]:
    """Read original frame container lengths and PixMap source rectangles."""
    if len(resource) < 2:
        raise ValueError("Missing Imag frame count")
    count = struct.unpack_from(">H", resource)[0]
    cursor = 2
    frames = []
    for index in range(count):
        if cursor + 54 > len(resource):
            raise ValueError("Truncated Imag frame header")
        length = struct.unpack_from(">I", resource, cursor)[0]
        if length < 54 or cursor + length > len(resource):
            raise ValueError("Invalid Imag frame length")
        bounds = list(struct.unpack_from(">4h", resource, cursor + 10))
        if bounds[2] <= bounds[0] or bounds[3] <= bounds[1]:
            raise ValueError("Invalid PixMap bounds")
        frames.append({"index": index, "resource_offset": cursor, "length": length, "source_rect_tlbr": bounds})
        cursor += length
    return frames


@dataclass
class TrackState:
    """Original callback state, with Random(span) supplied by the caller.

    step() is called once per engine update, not once per Macintosh tick.
    Source: CODE4:0000,00fa; CODE5:007e. Delays/phase counters are 16-bit.
    """
    frame: int
    delay: int
    remaining: int
    direction: int = 1
    phase: int = 0
    rate: int = 0

    @classmethod
    def initial(cls, track: Track, random_value: int = 0) -> TrackState:
        return cls(track.first, random_value, track.repeats)

    def step(self, track: Track, random_value: int = 0) -> int:
        if self.delay:
            self.delay = ((self.delay - 1 + 32768) % 65536) - 32768
        else:
            self.rate = track.period
            if self.phase == 0:
                candidate = self.frame + (self.direction if track.motion == "pingpong" else 1)
                if candidate > track.last:
                    candidate = track.last - 1 if track.motion == "pingpong" else track.first
                    self.direction = -1 if track.motion == "pingpong" else self.direction
                    self.remaining -= 1
                elif candidate < track.first:
                    candidate = track.first + 1
                    self.direction = 1
                self.frame = candidate
                finished = candidate == track.first and self.remaining == 0
                if track.motion == "pingpong":
                    finished = finished and self.direction == -1
                if finished:
                    self.delay = ((track.pause_base + random_value + 32768) % 65536) - 32768
                    self.remaining = track.repeats
                    self.rate = 0
        if self.rate:
            self.phase += 1
            if self.phase >= self.rate:
                self.phase = 0
        return self.frame


def extract_title_metadata(code: bytes, resource: bytes, color_depth: int = 8) -> dict:
    tracks = decode_title_tracks(code, color_depth)
    frames = decode_frame_bounds(resource)
    return {
        "resource_id": 19000,
        "color_depth": color_depth,
        "scheduler_tick_interval": 2,
        "scheduler_policy": "after update, next deadline = current TickCount + 2; no catch-up",
        "transfer_mode": 0,
        "mask": None,
        "background": {"frame": 0, "x": 9, "y": 9},
        "tracks": [asdict(track) for track in tracks],
        "draw_order_back_to_front": ["background"] + list(reversed(range(len(tracks)))),
        "frames": frames,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--depth", type=int, default=8)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    import macresources
    resource = next(bytes(item) for item in macresources.parse_file((args.root / "raw/oregon_color.rsrc").read_bytes()) if item.type == b"Imag" and item.id == 19000)
    result = extract_title_metadata((args.root / "assets/code_segments/CODE_4_Attract.bin").read_bytes(), resource, args.depth)
    output = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.write_text(output)
    else:
        print(output, end="")
