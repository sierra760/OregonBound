"""Extract original overland/river animation data, not a visual approximation.

Binary evidence and implementation boundaries: docs/ORIGINAL_TRAVEL_ANIMATION.md.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct

import macresources
from extract_a5 import decode_initial_data
from analysis_animation import decode_frame_bounds
from extract_ditl import parse_ditl_resource

ROOT = Path(__file__).resolve().parents[1]
OPCODES = {
    0: ("nop", 2), 1: ("wait", 4), 2: ("move_by", 8),
    3: ("move_to", 8), 4: ("frame", 4), 5: ("next_frame", 2),
    6: ("previous_frame", 2), 7: ("repeat", 8), 8: ("hide", 2),
    9: ("show", 2), 10: ("set_signal", 4), 11: ("wait_signal", 4),
    12: ("transfer_mode", 4), 13: ("call_scene", 4), 254: ("custom", 4),
    255: ("delete", 2),
}


def decode_scripts(data: bytes) -> list[dict]:
    """Scpt container traversal CODE5:0x071c–0x074a; VM CODE5:0x0c62."""
    if len(data) < 2:
        raise ValueError("Missing script count")
    count = struct.unpack_from(">H", data)[0]
    cursor = 2
    scripts = []
    for index in range(count):
        if cursor + 4 > len(data):
            raise ValueError("Truncated script header")
        length = struct.unpack_from(">I", data, cursor)[0]
        end = cursor + length
        if length < 6 or end > len(data):
            raise ValueError("Invalid script length")
        pc = cursor + 4
        instructions = []
        while pc < end:
            if pc + 2 > end:
                raise ValueError("Truncated script instruction")
            size, opcode = data[pc:pc + 2]
            if opcode not in OPCODES or size != OPCODES[opcode][1] or pc + size > end:
                raise ValueError("Unsupported or truncated script instruction")
            args = list(struct.unpack_from(f">{(size-2)//2}h", data, pc + 2))
            instructions.append({"offset": pc - cursor - 4, "size": size,
                                 "opcode": opcode, "operation": OPCODES[opcode][0], "arguments": args})
            pc += size
        offsets = {instruction["offset"] for instruction in instructions}
        for instruction in instructions:
            if instruction["opcode"] == 7 and instruction["arguments"][2] not in offsets:
                raise ValueError("Repeat destination is not an instruction boundary")
        scripts.append({"index": index, "resource_offset": cursor, "length": length,
                        "instructions": instructions})
        cursor = end
    if cursor != len(data):
        raise ValueError("Trailing bytes after final script")
    return scripts


def palette_sources(destination: int, month: int, weather: int, snow: int) -> dict[int, int]:
    """CODE1:0x3fc4–0x414e. Called only in the 8-bit palette animation path."""
    if not 0 <= weather <= 9:
        raise ValueError("Weather category is outside the recovered switch")
    sky = 230 if weather <= 1 else 232 if weather <= 3 else 231
    if destination == 4:
        first, last = 99, -1
    elif destination < 5:
        first, last = 4, 9
    elif destination < 13:
        first, last = 4, 5
    elif destination == 13:
        first, last = 4, 10
    else:
        first, last = 3, 10
    grass = 227 if snow != 0 else 226 if first <= month <= last else 228
    return {229: grass, 233: sky}


def clipped_copy(frame: int, x: int, y: int, width: int, height: int,
                 clip: tuple[int, int, int, int] = (9, 64, 86, 326)) -> dict | None:
    """Express QuickDraw's unscaled clipped srcCopy as source/destination rects."""
    top, left, bottom, right = clip
    dl, dt, dr, db = max(x, left), max(y, top), min(x + width, right), min(y + height, bottom)
    if dr <= dl or db <= dt:
        return None
    return {"resource_id": 15100, "frame": frame,
            "source_rect_tlbr": [dt-y, dl-x, db-y, dr-x],
            "destination_rect_tlbr": [dt, dl, db, dr], "transfer_mode": 0}


def extract(root: Path = ROOT) -> dict:
    color = {(r.type, r.id): bytes(r) for r in macresources.parse_file((root / "raw/oregon_color.rsrc").read_bytes())}
    main = {(r.type, r.id): bytes(r) for r in macresources.parse_file((root / "raw/oregon_trail.rsrc").read_bytes())}
    memory = decode_initial_data((root / "assets/code_segments/CODE_21_A5Init.bin").read_bytes())
    scenes = list(struct.unpack_from(">18h", memory, len(memory) - 0x27b8))
    frames = decode_frame_bounds(color[b"Imag", 15100])
    programs = decode_scripts(main[b"Scpt", 5310])
    condition_items = parse_ditl_resource(main[b"DITL", 5600], 5600)["items"]
    def condition_rect(index):
        bounds = condition_items[index]["bounds"]
        return [bounds[key] for key in ("top", "left", "bottom", "right")]
    colors = {index: list(struct.unpack_from(">4H", color[b"clut", 1008], 8 + index*8)[1:]) for index in range(226, 234)}
    return {
        "schema_version": 1,
        "travel": {
            "resource_id": 15100, "tick_interval": 3, "clip_rect_tlbr": [9,64,86,326],
            "background": {"frame":0,"x":64,"y":9},
            "upper_strip": {"frame":1,"initial_x":-460,"y":32,"width":786,"height":14,
                            "dx":1,"period_expression":"3 - pace", "wrap_when_x_at_least":64,"wrap_x":-460},
            "lower_strip": {"frame":2,"initial_x":-460,"y":81,"width":786,"height":6,
                            "dx_expression":"pace + 1","period":1,"wrap_when_x_at_least":64,"wrap_x":-460},
            "wagon": {"first":3,"last":6,"x":256,"y":54,"width":67,"height":25,"period_expression":"3 - pace"},
            "landmark_requested_frame_by_destination_minus1_to16": [code + 7 for code in scenes],
            "landmark_effective_frame_by_destination_minus1_to16": [21] + [code + 7 for code in scenes[1:]],
            "landmark_selector_range": [8,21],
            "landmark_initial_x": "254 - frameWidth - 3 * remainingMiles",
            "landmark_y": "46 + trunc((35 - frameHeight) / 2)",
            "landmark_initial_hidden_x": -746,
            "draw_order_back_to_front": ["background","upper_strip","lower_strip","landmark","wagon"],
            "frames": frames,
            "palette_rgb16": colors,
            "palette_live_indices": [229,233],
        },
        "river": {
            "resource_id":15310,"script_resource_id":5310,"tick_interval":3,
            "clip_rect_tlbr":[9,64,164,326],
            "masked_frames":[7,9,12],
            "variant_by_method_raw": {1:2,2:0,3:1},
            "success_creation_script_indices":"[variant + 7, 1, 2, 0]",
            "failure_creation_script_indices":"[3, 4, 5, 6, variant + 10, 2, 0]",
            "draw_order":"reverse creation order",
            "frames":decode_frame_bounds(color[b"Imag",15310]),"programs":programs,
        },
        "thermometer": {
            "resource_id":15600,"frame":10,"art_rect_tlbr":condition_rect(2),
            "fill_rect_tlbr":condition_rect(3),"fill_top_expression":"87 - 6 * temperatureCategory",
            "rgb16":list(struct.unpack_from(">3H",memory,len(memory)-0xe4a)),
            "evidence":"CODE3:0x2d66–0x2de4; DITL5600 items3/4",
        },
        "limits":["Landmark movement is adaptive and must not be replaced by a fixed velocity.",
                  "River frame7/9/12 masks require the original color-mask algorithm; opacity is insufficient.",
                  "Terminal destination16 takes the ending path, not an ordinary landmark view."]
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = json.dumps(extract(args.root), indent=2) + "\n"
    if args.output:
        args.output.write_text(result)
    else:
        print(result, end="")

class LandmarkMotion:
    """CODE1:42d4 callback + CODE5:09d0/0a76, ordinary valid game inputs.

    Origin and destination are intentionally separate. Immediate moves preserve
    fixed-point accumulators; the callback advances them unconditionally.
    """
    def __init__(self, width, height, remaining, *, blocked=False):
        self.width=width; self.height=height
        self.x=254-width-3*remaining if not blocked else -746
        self.y=46+(35-height)//2
        self.left=self.x; self.top=self.y
        self.fixed_x=self.fixed_y=self.vx=self.vy=0
        self.last_miles=-1; self.previous_x=0
        self.calls=0; self.total_ticks=0; self.previous_tick=0
        self.average=5; self.duration=0; self.delta=0

    @staticmethod
    def signed32(value):
        return (value+2**31)%2**32-2**31

    @staticmethod
    def divide(a,b):
        return abs(a)//abs(b)*(1 if (a<0)==(b<0) else -1)

    def move(self, duration, dx, dy=0):
        if duration:
            self.fixed_x=self.x<<16; self.fixed_y=self.y<<16
            self.vx=self.divide(dx<<16,duration)
            self.vy=self.divide(dy<<16,duration)
        else:
            self.x+=dx; self.left+=dx; self.y+=dy; self.top+=dy

    def callback(self, tick, remaining, last_movement, *, pace=0, day_delay=4, end_tick=None, new_size=None):
        self.calls+=1
        if self.total_ticks==0:
            self.total_ticks=5; self.average=5
        else:
            self.total_ticks+=min(tick-self.previous_tick,15)
            self.average=self.divide(self.total_ticks,self.calls)
        self.previous_tick=tick if end_tick is None else end_tick
        duration=self.divide(day_delay*60,self.average)
        if self.last_miles<remaining:
            if new_size:
                self.width,self.height=new_size
                self.left=self.x;self.top=self.y # SelectFrame rebuilds destrect.
            x=254-(3*remaining+self.width);y=46+(35-self.height)//2
            self.move(0,x-self.x,y-self.y)
            self.previous_x=-999
        if self.last_miles!=remaining:
            desired=254-(3*(remaining-last_movement//2)+self.width)
            delta=desired-self.x
            if delta<=0:delta=3*(20+10*pace)
            if delta>175:duration=0
            delta=min(delta,70)
            self.last_miles=remaining;self.duration=duration;self.delta=delta
            self.move(duration,delta)
        self.fixed_x=self.signed32(self.fixed_x+self.vx)
        self.fixed_y=self.signed32(self.fixed_y+self.vy)
        x=self.signed32(self.fixed_x+0x8000)>>16
        y=self.signed32(self.fixed_y+0x8000)>>16
        self.left+=x-self.x;self.top+=y-self.y;self.x=x;self.y=y
        if self.x<self.previous_x:
            self.x=self.previous_x+5;self.left=self.previous_x
        if self.x>254-self.width:
            self.x=254-self.width;self.left=self.x
        self.previous_x=self.x
        return self.x,self.left,self.y,self.top
