"""The authored legends and presentation resource anchors, from supplied forks."""
from pathlib import Path
import struct
import macresources

ROOT = Path(__file__).resolve().parents[1]


def test_authored_single_wagon_legends_match_production():
    resources = list(macresources.parse_file((ROOT / 'raw/oregon_trail.rsrc').read_bytes()))
    data = bytes(next(r.data for r in resources if r.type == b'CONF' and r.id == 1000))
    assert struct.unpack_from('>3H', data, 0x1c8) == (10, 10, 26)
    source = (ROOT / 'OregonBound/OregonBound/Engine/OriginalEndingPresentation.swift').read_text()
    scores = []
    for index in range(10):
        pos = 0x1ce + index * 32
        name = data[pos + 1:pos + 1 + data[pos]].decode('macroman')
        assert f'"{name}"' in source
        scores.append(struct.unpack_from('>i', data, pos + 28)[0])
    assert ', '.join(map(str, scores)) in source


def test_original_ending_resources_and_strict_ranking_branch():
    ending = (ROOT / 'assets/code_segments/CODE_10_Ending.bin').read_bytes()
    # Full arrival screen9090 and death image19150, then qualifying/nonqualifying scores.
    assert ending[0x142:0x14a].hex() == '48784a9248782382'
    assert ending[0x8e:0x96].hex() == '48784ace487823be'
    assert ending[0x162a:0x1630].hex() == '203c010d238c'
    assert ending[0x163a:0x1640].hex() == '203c010d23aa'
    code = (ROOT / 'assets/code_segments/CODE_3_Main2.bin').read_bytes()
    assert code[0x1bf6:0x1bfc].hex() == 'bcb0081c6f04'
