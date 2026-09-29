"""Binary/resource regressions for original CODE7 later-fort stores."""
from pathlib import Path
import json
import struct
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from extract_a5 import decode_initial_data
from macresources import parse_file
ROOT = Path(__file__).resolve().parents[1]


def test_original_price_tables_and_box_costs():
    resources = list(parse_file((ROOT/'raw/oregon_trail.rsrc').read_bytes()))
    data = decode_initial_data(bytes(next(r for r in resources if r.type == b'CODE' and r.id == 21))[4:])
    prices = struct.unpack_from('>7H', data, len(data)-0x2876)
    regional = data[len(data)-0x2888:len(data)-0x2888+18]
    assert prices == (2000,1000,200,1000,1000,1000,20)
    assert tuple(regional) == (100,100,100,125,125,150,150,150,175,175,175,200,200,225,250,250,250,250)
    assert prices[2]*regional[3]//100 == 250  # Kearney box20
    assert prices[6]*regional[8]//100 == 35  # Bridger food1


def test_later_store_is_same_full_cart_with_cancel_have():
    items = json.loads((ROOT/'assets/dialogs/ditl_9030.json').read_text())['items']
    assert len(items) == 29
    assert items[0]['bounds'] == {'top':0,'left':0,'bottom':304,'right':494}
    assert items[15]['data'] == 'Help' and items[24]['data'] == 'Cancel'
    assert items[15]['bounds'] == items[24]['bounds']
    assert [i['bounds']['top'] for i in items[16:23]] == [137,155,173,191,209,227,245]
    labels = json.loads((ROOT/'assets/strings/str_3016.json').read_text())['strings']
    assert labels[2:] == ['Max','Have']


def test_purchase_checks_money_before_capacity_and_has_no_rng():
    code = (ROOT/'assets/code_segments/CODE_7_Buy.bin').read_bytes()
    assert code[0x416:0x41a].hex() == '4a866c10'  # tst.l d6;bge042a
    assert code[0x482:0x486].hex() == 'b4806c2e'  # cmp.l d0,d2;bge04b4
    assert bytes.fromhex('4ead00a2') not in code
