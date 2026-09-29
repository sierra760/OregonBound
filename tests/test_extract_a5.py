import struct
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from extract_a5 import decode_initial_data, extract_tables


def test_original_global_tables():
    blob = (ROOT / "assets/code_segments/CODE_21_A5Init.bin").read_bytes()
    memory = decode_initial_data(blob)
    assert len(memory) == 13560
    tables = extract_tables(memory)
    assert tables["profession_score_half_multipliers"] == [2, 4, 4, 2, 6, 3, 5, 7]
    assert tables["supply_capacity"] == [40, 50, 1980, 3, 3, 3, 2000]
    assert tables["hunt_time_seconds"] == [20, 30, 45, 60, 90, 120]
    assert tables["profession_starting_cash_cents"] == [160000, 80000, 80000, 120000, 40000, 120000, 80000, 40000]
    assert tables["supply_base_pack_price_cents"] == [2000, 1000, 200, 1000, 1000, 1000, 20]
    assert tables["location_price_percent"] == [100, 100, 100, 125, 125, 150, 150, 150, 175, 175, 175, 200, 200, 225, 250, 250, 250, 250]


def test_copy_and_add_records():
    blob = struct.pack(">IIHH", 16, 0, 2, 0) + bytes.fromhex("04 0000 deadbeef 22 0002 0001")
    assert decode_initial_data(blob, header_offset=0) == bytes.fromhex("deadbef0") + bytes(12)


def test_truncated_and_out_of_bounds_data_are_rejected():
    with pytest.raises(ValueError):
        decode_initial_data(b"short")
    blob = struct.pack(">IIHH", 4, 0, 1, 0) + bytes.fromhex("04 0002 deadbeef")
    with pytest.raises(ValueError):
        decode_initial_data(blob, header_offset=0)
