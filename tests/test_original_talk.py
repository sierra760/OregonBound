"""Binary-backed constraints for the static single-wagon Talk pane."""
from pathlib import Path
import json
import struct
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from extract_a5 import decode_initial_data
from macresources import parse_file
ROOT = Path(__file__).resolve().parents[1]


def test_talk_cursor_starts_at_one_and_increment_precedes_display():
    resources = list(parse_file((ROOT/'raw/oregon_trail.rsrc').read_bytes()))
    data = decode_initial_data(bytes(next(r for r in resources if r.type == b'CODE' and r.id == 21))[4:])
    assert struct.unpack_from('>h', data, len(data)-0xc66) == (1,)
    code = (ROOT/'assets/code_segments/CODE_3_Main2.bin').read_bytes()
    assert code[0x3918:0x391c].hex() == '526df39a'  # addq.w #1,A5-c66
    assert code[0x3928:0x392e].hex() == '3b7c0001f39a'  # wrap to1
    assert bytes.fromhex('4e ad 00 a2') not in code[0x37c6:0x3942]  # no bounded RNG call
    assert code[0x381a:0x3820].hex() == 'd0bc00000c1d'  # add3101 to signed destination


def test_all_eighteen_tables_have_three_valid_portrait_quote_pairs():
    for resource in range(3100, 3118):
        strings = json.loads((ROOT/f'assets/strings/str_{resource}.json').read_text())['strings']
        assert len(strings) == 6
        for index in range(3):
            assert strings[index*2] in list('012345678')
            assert len(strings[index*2+1]) > 20
    independence = json.loads((ROOT/'assets/strings/str_3100.json').read_text())['strings']
    assert independence[2] == '2'
    assert 'Missouri Republican' in independence[3]  # first click displays pair2


def test_ditl_and_art_use_original_dimensions_without_buttons():
    items = json.loads((ROOT/'assets/dialogs/ditl_6080.json').read_text())['items']
    assert [i['type'] for i in items] == ['userItem', 'userItem', 'staticText']
    assert items[2]['bounds'] == {'top':15,'left':146,'bottom':185,'right':250}
    manifest = json.loads((ROOT/'assets/graphics/oregon_color/manifests/graphics_manifest.json').read_text())
    frames = [i for i in manifest['images'] if i['resource']['id'] == 16080]
    assert [(i['width'],i['height']) for i in frames] == [(154,199)]*9 + [(108,199)]
