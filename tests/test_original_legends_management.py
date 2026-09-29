"""Original management editor resources and deferred deletion instruction anchors."""
from pathlib import Path
import json
import struct
from macresources import parse_file
ROOT=Path(__file__).resolve().parents[1]


def test_editor_buttons_and_confirmation_mean_restore_not_clear_all():
    items=json.loads((ROOT/'assets/dialogs/ditl_2042.json').read_text())['items']
    assert [items[i]['data'] for i in [0,1,5]]==['Remove','Done','Original']
    assert items[3]['bounds']==dict(top=30,left=20,bottom=192,right=280)
    alert=json.loads((ROOT/'assets/dialogs/ditl_2045.json').read_text())['items']
    assert [alert[i]['data'] for i in [0,1]]==['No','Yes']
    assert alert[3]['data']=='Are you sure you want to delete the current list?'
    resources=list(parse_file((ROOT/'raw/oregon_trail.rsrc').read_bytes()))
    assert bytes(next(r for r in resources if r.type==b'ALRT' and r.id==2045)).hex()=='00000000005e010e07fd4444'


def test_editor_is_single_table_and_restore_does_not_discard_pending_removals():
    code=(ROOT/'assets/code_segments/CODE_15_Management.bin').read_bytes()
    assert code[0x6dc:0x6e0].hex()=='42464244' # pending D6=0; table selectorD4=0
    assert code[0x830:0x838].hex()=='48c42f044ead0582' # Done chooses table
    assert code[0x84e:0x852].hex()=='4ead0592' # Done deletes queued name+score
    assert bytes.fromhex('434f4e46') in code[0x8e0:0x99e] # Original reads CONF1000
    assert code[0x99a:0x99e].hex()=='4ead0562' # Original persists immediately
    assert bytes.fromhex('4246') not in code[0x878:0x9c2] # no clear.w D6 on restore


def test_authored_single_and_train_tables_are_separate_config_blocks():
    resources=list(parse_file((ROOT/'raw/oregon_trail.rsrc').read_bytes()))
    conf=bytes(next(r for r in resources if r.type==b'CONF' and r.id==1000))
    assert struct.unpack_from('>3H',conf,0x1c8)==(10,10,26)
    assert len(conf)>=0x1c8+2*0x146
    # Reset selects CONF+1c8 +selector*146; selector is0 in this editor.
    code=(ROOT/'assets/code_segments/CODE_15_Management.bin').read_bytes()
    assert code[0x91c:0x920].hex()=='c0fc0146'
