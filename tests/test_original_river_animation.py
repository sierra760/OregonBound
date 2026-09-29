"""Verify locally imported river scripts and frame metadata."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import macresources
from analysis_animation import decode_frame_bounds
SWIFT = ROOT / 'OregonBound/OregonBound/Engine/OriginalRiverAnimation.swift'


def test_runtime_river_script_matches_supplied_resource(tmp_path):
    from extract_runtime import extract_runtime
    source = ROOT / 'raw/oregon_trail.rsrc'
    extract_runtime(source, tmp_path)
    expected = next(bytes(r.data) for r in macresources.parse_file(source.read_bytes())
                    if r.type == b'Scpt' and r.id == 5310)
    assert (tmp_path / 'runtime/scpt_5310.bin').read_bytes() == expected


def test_swift_frame_sizes_match_original_pixmap_bounds():
    resource = next(bytes(r) for r in macresources.parse_file((ROOT / 'raw/oregon_color.rsrc').read_bytes())
                    if r.type == b'Imag' and r.id == 15310)
    expected = []
    for frame in decode_frame_bounds(resource):
        top, left, bottom, right = frame['source_rect_tlbr']
        expected.append((right-left,bottom-top))
    literal = SWIFT.read_text().split('static let frameSizes = [',1)[1].split(']',1)[0]
    actual = [tuple(map(int,pair)) for pair in re.findall(r'\((\d+),(\d+)\)',literal)]
    assert actual == expected
