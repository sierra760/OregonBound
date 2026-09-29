from pathlib import Path
import struct
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from analysis_travel_animation import extract, decode_scripts, palette_sources, clipped_copy


@pytest.fixture(scope="module")
def metadata():
    return extract(ROOT)


def test_original_travel_frame_dimensions_and_scene_table(metadata):
    travel = metadata["travel"]
    assert len(travel["frames"]) == 22
    assert [f["source_rect_tlbr"] for f in travel["frames"][:4]] == [
        [0,0,77,262], [0,0,14,786], [0,0,6,786], [0,0,25,67]]
    assert travel["landmark_requested_frame_by_destination_minus1_to16"] == [7,20,20,8,9,10,11,12,13,20,14,15,20,16,17,18,19,21]


def test_clip_preserves_original_strip_sampling():
    upper = clipped_copy(1,-460,32,786,14)
    assert upper["source_rect_tlbr"] == [0,524,14,786]
    assert upper["destination_rect_tlbr"] == [32,64,46,326]
    lower = clipped_copy(2,-460,81,786,6)
    assert lower["source_rect_tlbr"] == [0,524,5,786]
    assert lower["destination_rect_tlbr"] == [81,64,86,326]
    assert clipped_copy(20,-746,46,46,35) is None


def test_palette_weather_and_snow_sources(metadata):
    assert [palette_sources(0,4,w,0)[233] for w in range(10)] == [230,230,232,232,231,231,231,231,231,231]
    assert palette_sources(0,4,0,1)[229] == 227
    assert metadata["travel"]["palette_rgb16"][227] == [62913,63568,60947]
    with pytest.raises(ValueError):
        palette_sources(0,4,10,0)


@pytest.mark.parametrize("destination,green_months", [
    (-1,range(4,10)), (3,range(4,10)), (4,[]), (5,range(4,6)),
    (12,range(4,6)), (13,range(4,11)), (14,range(3,11)), (15,range(3,11)),
])
def test_original_season_boundaries(destination,green_months):
    actual = [m for m in range(1,13) if palette_sources(destination,m,0,0)[229] == 226]
    assert actual == list(green_months)


def test_original_river_programs_decode_all_instruction_boundaries(metadata):
    river = metadata["river"]
    assert len(river["frames"]) == 18
    programs = river["programs"]
    assert len(programs) == 13
    assert programs[0]["resource_offset"] == 2
    assert programs[-1]["resource_offset"] + programs[-1]["length"] == 738
    assert [(op["operation"],op["arguments"]) for op in programs[0]["instructions"]] == [
        ("frame",[0]),("move_to",[0,64,9]),("show",[]),("wait_signal",[6]),("delete",[])]
    for index,frame,x,y in [(7,7,206,84),(8,9,162,66),(9,12,170,72)]:
        instructions=programs[index]["instructions"]
        assert instructions[0]["arguments"] == [frame]
        assert instructions[1]["arguments"] == [0,x,y]
    repeats = [op for op in programs[9]["instructions"] if op["opcode"] == 7]
    assert [op["arguments"] for op in repeats] == [[3,-2,40],[3,-2,58]]


def test_river_decoder_rejects_truncation_and_invalid_branch():
    with pytest.raises(ValueError):
        decode_scripts(bytes.fromhex("0001000000180404"))
    with pytest.raises(ValueError):
        decode_scripts(struct.pack(">HI",1,12) + bytes.fromhex("08070001fffe0001"))


def test_original_timing_and_temperature_formula_instructions(metadata):
    main=(ROOT/"assets/code_segments/CODE_1_Main.bin").read_bytes()
    assert main[0x3e8e:0x3e94] == bytes.fromhex("56802b40f5aa") # deadline = TickCount+3
    temperature=(ROOT/"assets/code_segments/CODE_3_Main2.bin").read_bytes()
    assert temperature[0x2d80:0x2d88] == bytes.fromhex("72054ead02623e00") # height/5
    assert metadata["thermometer"]["rgb16"] == [65280,0,1792]
    assert metadata["thermometer"]["fill_rect_tlbr"] == [57,69,87,71]


def test_adaptive_motion_fixed_point_and_measured_tick_duration():
    from analysis_travel_animation import LandmarkMotion
    motion=LandmarkMotion(46,35,40)
    assert motion.callback(100,40,20)==(89,89,46,46)
    assert (motion.duration,motion.delta,motion.average)==(48,30,5)
    assert motion.callback(103,40,20)==(89,89,46,46)
    assert motion.average==4
    assert motion.callback(106,20,20)==(90,90,46,46)
    assert (motion.duration,motion.delta,motion.average)==(80,70,3)
    motion.callback(1000,20,20)
    assert motion.total_ticks==26 and motion.average==6


def test_immediate_jump_keeps_old_fixed_state_and_origin_destination_difference():
    from analysis_travel_animation import LandmarkMotion
    motion=LandmarkMotion(46,35,100)
    motion.callback(0,100,20)
    motion.callback(3,100,20)
    # More than175 desired pixels forces duration0; the immediate70-pixel jump
    # is then overwritten by the unconditionally advanced old fixed accumulator.
    motion.callback(6,30,20)
    assert motion.duration==0 and motion.delta==70
    assert (motion.x,motion.left)==(-90,-90)
    # Force a backwards fixed-point result as occurs after arrival/reset state.
    motion.previous_x=100
    assert motion.callback(9,30,20)[:2]==(105,100)
    assert motion.callback(12,30,20)[:2]==(110,105)


def test_reposition_on_remaining_increase_and_fixed_point_arrival_clamp():
    from analysis_travel_animation import LandmarkMotion
    motion=LandmarkMotion(46,35,1)
    assert motion.callback(0,1,20)[:2]==(206,206)
    for tick in range(3,15,3):motion.callback(tick,1,20)
    assert motion.x==208 # Stops on visual edge even with remaining1.
    motion.callback(15,90,20,new_size=(62,32))
    assert (motion.width,motion.height,motion.x,motion.y)==(62,32,-78,47)


def test_landmark_original_byte_anchors_and_zero_duration_keeps_accumulators():
    code=(ROOT/'assets/code_segments/CODE_1_Main.bin').read_bytes()
    display=(ROOT/'assets/code_segments/CODE_5_Display.bin').read_bytes()
    assert code[0x44a0:0x44a6].hex()=='2f0b4ead0702'
    assert code[0x44c4:0x44d4].hex()=='202df4f65a8037400008376df4f8000c'
    assert display[0xa32:0xa3e].hex()=='df6b0008df6b000cdf6b0010'
