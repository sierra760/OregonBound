"""Resource-backed anchors for the native popup's recovered constants."""
import hashlib,json,struct
from pathlib import Path
import macresources
ROOT=Path(__file__).resolve().parents[1]

def test_menu52_is_six_plain_enabled_choices():
    r=next(x for x in macresources.parse_file((ROOT/'raw/oregon_trail.rsrc').read_bytes()) if x.type==b'MENU' and x.id==52)
    b=bytes(r)
    assert struct.unpack_from('>hhhhHI',b)==(52,0,0,0,0,0xffffffff)
    pos=14;title=b[pos+1:pos+1+b[pos]].decode('mac_roman');pos+=1+b[pos]
    assert title=='Hunt Time:'
    items=[]
    while b[pos]:
        n=b[pos];items.append(b[pos+1:pos+1+n].decode('mac_roman'))
        assert b[pos+1+n:pos+5+n]==bytes(4)
        pos+=5+n
    assert items==['20 seconds','30 seconds','45 seconds','60 seconds','90 seconds','2 minutes']

def test_chicago_strike_proves_label_menu_size_and_checkmark():
    f=json.loads((ROOT/'assets/fonts/nfnt_5478.json').read_text())
    g={x['code']:x for x in f['glyphs'] if x['code'] is not None}
    width=lambda s:sum(g[c]['advance'] for c in s.encode('mac_roman'))
    assert width('Hunt Time:')==68
    h=f['header'];assert h['ascent']==12
    assert h['ascent']+h['descent']+h['leading']==16
    assert max(width(s) for s in ['20 seconds','30 seconds','45 seconds','60 seconds','90 seconds','2 minutes'])+g[32]['advance']+h['wid_max']-2+8==97
    assert g[18]['atlas_rect']==[18,0,9,15]
    assert g[18]['advance']==11

def test_menu_definitions_preserve_instruction_anchors():
    directory=ROOT/'assets/system_controls'
    m=json.loads((directory/'system7_menu_definitions.json').read_text())
    for entry in m['resources']:
        data=(directory/f"system7_{entry['type'].lower()}_0_unpacked.bin").read_bytes()
        assert len(data)==entry['unpacked_length']
        assert hashlib.sha256(data).hexdigest()==entry['unpacked_sha256']
    mdef=(directory/'system7_mdef_0_unpacked.bin').read_bytes()
    assert mdef[0x040a:0x040c]==bytes.fromhex('5552') # subq.w #2,(a2): adjusted widMax.
    assert mdef[0x0508:0x050a]==bytes.fromhex('5047') # addq.w #8,d7: menu width padding.
    mbdf=(directory/'system7_mbdf_0_unpacked.bin').read_bytes()
    assert mbdf[0x09f2:0x09fa]==bytes.fromhex('2f3c00020002a89b') # PenSize2,2 shadow.
