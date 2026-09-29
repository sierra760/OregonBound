"""Pin original List of Legends DITL, root font, menu, and renderer evidence."""
from pathlib import Path
import json
import struct
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from extract_a5 import decode_initial_data
from macresources import parse_file
ROOT = Path(__file__).resolve().parents[1]


def test_legends_dialog_keeps_title_actions_and_full_page_art():
    items = json.loads((ROOT/'assets/dialogs/ditl_9010.json').read_text())['items']
    assert items[0]['bounds'] == dict(top=0,left=0,bottom=304,right=494)
    assert items[1]['data'] == 'Load Game' and items[2]['data'] == 'Travel the Trail'
    assert items[1]['bounds'] == dict(top=270,left=30,bottom=290,right=150)
    assert items[2]['bounds'] == dict(top=270,left=343,bottom=290,right=463)
    assert items[3]['bounds'] == dict(top=112,left=30,bottom=262,right=464)
    assert items[5]['bounds'] == dict(top=26,left=146,bottom=71,right=359)


def test_root_font_and_renderer_geometry_are_not_system_table_defaults():
    data=decode_initial_data((ROOT/'assets/code_segments/CODE_21_A5Init.bin').read_bytes())
    assert struct.unpack_from('>5h',data,len(data)-0x2a84)==(6322,1,1,14,0)
    font=json.loads((ROOT/'assets/fonts/nfnt_16131.json').read_text())['header']
    assert (font['ascent'],font['descent'],font['leading'],font['wid_max'])==(12,3,0,16)
    code=(ROOT/'assets/code_segments/CODE_4_Attract.bin').read_bytes()
    assert code[0x666:0x66c].hex()=='223c00000bb8' # score /3000
    assert code[0x6a0:0x6a6].hex()=='90bc00000096' # class x=right-150
    assert code[0x6ec:0x6f0].hex()=='48780258' # Legends600ticks
    assert code[0x7d2:0x7d6].hex()=='48781c20' # Title7200ticks


def test_original_game_menu_has_no_hall_of_fame_command():
    resources=list(parse_file((ROOT/'raw/oregon_trail.rsrc').read_bytes()))
    game=bytes(next(r for r in resources if r.type==b'MENU' and r.id==1003))
    management=bytes(next(r for r in resources if r.type==b'MENU' and r.id==1004))
    assert b'Introduction' in game and b'Sound On' in game
    assert b'Legend' not in game and b'Hall' not in game
    assert b'Clear List of Legends' in management
