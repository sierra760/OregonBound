from pathlib import Path
import macresources
import pytest
from scripts.extract_pict_text import decode


def original():
    return next(bytes(r.data) for r in macresources.parse_file(Path('raw/oregon_trail.rsrc').read_bytes())
                if r.type == b'PICT' and r.id == 2070)


def test_occupation_help_preserves_text_font_and_relative_baselines():
    picture = decode(original(), 2070)
    assert (picture['width'], picture['height']) == (476, 245)
    title = picture['runs'][0]
    assert title == dict(x=179, baseline=16, font=6322, face=1, size=14, text='Occupation Help')
    bankers = next(run for run in picture['runs'] if run['text'] == 'Bankers')
    assert bankers['x'] == 4 and bankers['baseline'] == 115 and bankers['face'] == 0
    cash = next(run for run in picture['runs'] if run['text'] == '$ 1,600')
    assert cash['x'] == 101 and cash['baseline'] == 115
    assert picture['runs'][-1]['text'] == 'x 3.5'


def test_unknown_opcode_does_not_silently_produce_blank_art():
    data = bytearray(original()); data[12] = 0x99
    with pytest.raises(ValueError, match='Unsupported PICT opcode'): decode(bytes(data), 2070)


@pytest.mark.parametrize('resource_id', [2050, 2051, 2052])
def test_introduction_pages_preserve_original_text_beyond_header_bounds(resource_id):
    data = next(bytes(r.data) for r in macresources.parse_file(Path('raw/oregon_trail.rsrc').read_bytes())
                if r.type == b'PICT' and r.id == resource_id)
    picture = decode(data, resource_id)
    assert picture['runs'][0]['text'] == 'Introduction'
    assert all(run['font'] == 6322 and run['size'] == 14 for run in picture['runs'])
    assert len(picture['runs']) == {2050: 14, 2051: 14, 2052: 11}[resource_id]
    if resource_id == 2051:
        assert picture['height'] == 233
        assert picture['runs'][-1]['baseline'] == 246
        assert picture['runs'][-1]['text'] == 'much food you’ll eat each day along the trail.'
