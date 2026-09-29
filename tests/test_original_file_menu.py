import json
import struct
import sys
from pathlib import Path
import macresources
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
from extract_a5 import decode_initial_data


def resources(): return list(macresources.parse_file((ROOT/'raw/oregon_trail.rsrc').read_bytes()))

def test_menu_initial_mask_and_about_frame():
    menu = next(r for r in resources() if r.type == b'MENU' and r.id == 1001)
    assert struct.unpack_from('>I', menu.data, 10)[0] == 0x83
    dialog = next(r for r in resources() if r.type == b'DLOG' and r.id == 2001)
    top,left,bottom,right = struct.unpack_from('>hhhh', dialog.data)
    assert (right-left,bottom-top) == (400,200)


def test_literal_license_and_credits():
    resource = next(r for r in resources() if r.type == b'MECC' and r.id == 4)
    b = bytes(resource.data)
    lines = [bytes(v^0xeb for v in b[p+1:p+1+b[p]]).decode('mac_roman') for p in (0,32,64,96)]
    assert len(lines) == 4
    assert lines[0] == 'Licensed to:'
    assert lines[2:] == ['', '']
    names = json.loads((ROOT/'assets/strings/str_2003.json').read_text())['strings']
    assert len(names)==13 and names[5]=='Charolyn Kapplinger'


def test_export_constants_and_buffer_threshold():
    a = decode_initial_data((ROOT/'assets/code_segments/CODE_21_A5Init.bin').read_bytes())
    def pascal(offset):
        p=len(a)+offset;return a[p+1:p+1+a[p]]
    assert pascal(-0x2b16)==b'Export log to:'
    assert pascal(-0x2b06)==b'Trail Log'
    assert pascal(-0x2aee)==b'\r'
    assert pascal(-0x1e4a)==b'\xa5 ' and pascal(-0x1e42)==b' \xa5'
    code=(ROOT/'assets/code_segments/CODE_11_Export.bin').read_bytes()
    assert code[0x238:0x23e]==bytes.fromhex('0c9f00007d00')
    assert code[0x246:0x24a]==bytes.fromhex('32280070')
    assert code[0x8e:0x94]==bytes.fromhex('317cffff0048')


def test_exit_items_have_yes_no_without_cancel():
    dialog=json.loads((ROOT/'assets/dialogs/ditl_5230.json').read_text())['items']
    assert [i['data'] for i in dialog]==['Do you want to save this game before ^0?','Yes','No']
    assert [(i['bounds']['left'],i['bounds']['top']) for i in dialog[1:]]==[(28,85),(175,85)]
