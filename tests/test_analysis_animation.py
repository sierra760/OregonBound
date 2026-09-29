from pathlib import Path
import struct
import sys

import macresources
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from analysis_animation import decode_title_tracks, decode_frame_bounds, decode_setup_block, TrackState


@pytest.fixture
def tracks():
    return decode_title_tracks((ROOT / "assets/code_segments/CODE_4_Attract.bin").read_bytes())


def test_original_initializer_arguments(tracks):
    assert len(tracks) == 11
    assert [(t.first, t.last, t.x, t.y) for t in tracks] == [
        (1,9,222,113), (10,12,79,152), (13,15,19,128), (16,17,141,158),
        (18,19,109,158), (20,29,368,161), (30,37,438,166), (38,40,456,194),
        (41,42,296,186), (43,44,326,275), (45,46,212,205),
    ]
    assert [t.period for t in tracks] == [15,5,90,25,30,1,1,4,16,1,1]
    assert [t.pause_base for t in tracks] == [0,40,30,80,40,80,100,140,160,40,40]
    assert [t.random_span for t in tracks] == [0,30,40,80,80,300,300,300,300,100,60]
    assert [t.repeats for t in tracks] == [1,3,1,1,1,1,1,1,1,3,3]
    assert [t.call_offset for t in tracks] == [0x9c2,0x9e6,0xa0a,0xa2c,0xa50,0xa84,0xaa6,0xaca,0xaee,0xbaa,0xbce]


def test_depth_branch_is_not_shared_color_metadata():
    tracks = decode_title_tracks((ROOT / "assets/code_segments/CODE_4_Attract.bin").read_bytes(), 1)
    assert [t.y for t in tracks[5:9]] == [162,164,196,188]
    assert [t.period for t in tracks[5:9]] == [3,2,20,15]
    assert all(t.motion == "loop" for t in tracks[5:9])


def test_original_pixmap_bounds_cover_each_track(tracks):
    resource = next(bytes(r) for r in macresources.parse_file((ROOT / "raw/oregon_color.rsrc").read_bytes()) if r.type == b"Imag" and r.id == 19000)
    frames = decode_frame_bounds(resource)
    assert len(frames) == 47
    assert frames[0]["source_rect_tlbr"] == [0,0,304,494]
    for track in tracks:
        bounds = [f["source_rect_tlbr"] for f in frames[track.first:track.last+1]]
        assert len({tuple(rect) for rect in bounds}) == 1
        assert bounds[0][:2] == [0,0]
    assert frames[-1]["source_rect_tlbr"] == [0,0,44,44]


def test_loop_repeats_then_pauses(tracks):
    track = tracks[1]
    state = TrackState.initial(track)
    observed = [state.step(track) for _ in range(41)]
    assert observed[::5] == [11,12,10,11,12,10,11,12,10]
    assert state.delay == 40
    assert state.rate == 0
    assert state.remaining == 3
    for _ in range(40):
        assert state.step(track) == 10
    assert state.step(track) == 11


def test_pingpong_reverses_without_duplicate_endpoints(tracks):
    track = tracks[9]
    state = TrackState.initial(track, random_value=2)
    assert [state.step(track, random_value=7) for _ in range(8)] == [43,43,44,43,44,43,44,43]
    assert state.delay == 47
    assert state.remaining == 3
    assert state.direction == -1


def test_reject_unrecognized_binary_and_bad_frame_lengths():
    with pytest.raises(ValueError):
        decode_setup_block(bytes.fromhex("4e71"), 0, 2)
    with pytest.raises(ValueError):
        decode_frame_bounds(struct.pack(">HI", 1, 1000) + bytes(50))
