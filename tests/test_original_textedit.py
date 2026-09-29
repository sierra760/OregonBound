import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def code(segment): return next((ROOT/'assets/code_segments').glob(f'CODE_{segment}_*')).read_bytes()

def test_registration_resets_limit_then_enables_117_pixel_gate():
    assert code(19)[0x99c:0x9ac] == bytes.fromhex('4ead07aa3b7c0001d46e3b7c0075d46c')
    assert code(5)[0x3122:0x3126] == bytes.fromhex('426dd46a')
    assert code(5)[0x262e:0x2634] == bytes.fromhex('3b7c000ad46a')

def test_keyboard_paste_has_width_gate_menu_paste_does_not():
    assert code(5)[0x25c8:0x25cc] == bytes.fromhex('4ebafd1e')
    assert code(5)[0x19e2:0x19ec] == bytes.fromhex('b0816d082f2dd474a9db')
    assert code(5)[0x19f6:0x1a0c] == bytes.fromhex('48787fff70002f002f2dd4704eba1138 2f2dd474a9d7'.replace(' ',''))

def test_commit_gate_remains_fifteen_and_uses_no_trim():
    assert code(19)[0xa34:0xa40] == bytes.fromhex('70001013720fb2806d000148')
    assert code(5)[0x2648:0x264a] == bytes.fromhex('7e08')

def test_registration_uses_inherited_wttimes_bold14():
    assert code(5)[0x183e:0x1848] == bytes.fromhex('43edd57c20d920d930d9')
    assert code(5)[0x2da6:0x2db4] == bytes.fromhex('43e9001841e8001822d822d832d8')
    font=json.loads((ROOT/'assets/fonts/nfnt_16131.json').read_text())
    association=font['family_associations'][0]
    assert (association['family_id'],association['size'],association['style'])==(6322,14,1)
    assert font['glyphs'][ord('W')]['advance']==16
    assert font['glyphs'][ord('i')]['advance']==5
