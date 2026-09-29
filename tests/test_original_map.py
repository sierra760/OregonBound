"""Original map route paint tables and binary register-flow anchors."""
import json
from pathlib import Path
import struct
from scripts.extract_a5 import decode_initial_data

ROOT = Path(__file__).resolve().parents[1]


def test_original_steps_match_each_hvof_route():
    memory = decode_initial_data((ROOT / 'assets/code_segments/CODE_21_A5Init.bin').read_bytes())
    words = struct.unpack_from('>34h', memory, len(memory) - 0x2848)
    assert words == (4,0,12,0,7,0,22,0,6,0,15,0,6,0,8,3,4,0,7,8,4,0,14,0,8,0,11,0,8,12,7,0,10,7)
    expected = [sum(words[0:14:2]), words[15] + words[19], sum(words[14:20:2]),
                sum(words[20:28:2]), words[29], words[28] + words[30], words[33], words[32]]
    for index, count in enumerate(expected):
        path = json.loads((ROOT / f'assets/map_viewports/hvof_{128 + index}.json').read_text())
        assert path['point_count'] == count


def test_map_caller_supplies_path_index_to_skipped_leg_return_register():
    code = (ROOT / 'assets/code_segments/CODE_6_Main3.bin').read_bytes()
    #208c saves D6;2094 puts path argument in D6, then calls1e5e.
    assert code[0x2094:0x2098] == bytes.fromhex('3c2e000a')
    #2126 saves D6/D7 but initializes only D7; skipped branch2196 returns D6.
    assert code[0x2126:0x212e] == bytes.fromhex('48e703003e2f000e')
    assert code[0x2196:0x2198] == bytes.fromhex('6664')
    assert code[0x21fc:0x2204] == bytes.fromhex('30064cdf00c04e75')
