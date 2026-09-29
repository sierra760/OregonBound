from pathlib import Path
import struct,json,hashlib
import macresources
from macresources.greggybits import unpack
from PIL import Image
from capstone import Cs, CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000

ROOT=Path(__file__).resolve().parents[1]

def code(segment):return next((ROOT/'assets/code_segments').glob(f'CODE_{segment}_*')).read_bytes()
def ops(data,start,end):
    m=Cs(CS_ARCH_M68K,CS_MODE_BIG_ENDIAN|CS_MODE_M68K_000)
    return {i.address:(i.mnemonic,i.op_str) for i in m.disasm(data[start:end],start)}

def test_password_calls_are_note_and_stop_with_same_alert_and_nil_filter():
    c0=code(0)
    assert struct.unpack_from('>4H',c0,0x82-0x12)==(0x56e,0x3f3c,1,0xa9f0)
    assert struct.unpack_from('>4H',c0,0x92-0x12)==(0x670,0x3f3c,1,0xa9f0)
    wrong=ops(code(15),0,0x26);empty=ops(code(15),0x3d4,0x3fa)
    assert wrong[0x10]==('moveq','#$1, d0')
    assert wrong[0x1a]==('jsr','$82(a5)')
    assert empty[0x3e4]==('moveq','#$2, d0')
    assert empty[0x3ee]==('jsr','$92(a5)')
    c=code(1)
    note=ops(c,0x56e,0x58c);stop=ops(c,0x670,0x68e)
    assert note[0x57c]==('move.w','#$7d3, -(a7)')
    assert note[0x580]==('moveq','#$0, d0')
    assert note[0x584]==('dc.w','$a987')
    assert stop[0x67e]==('move.w','#$7d3, -(a7)')
    assert stop[0x682]==('moveq','#$0, d0')
    assert stop[0x686]==('dc.w','$a986')

def test_original_alert_resource_no_extra_font_color_or_icon_override():
    r={(x.type,x.id):bytes(x) for x in macresources.parse_file((ROOT/'raw/oregon_trail.rsrc').read_bytes())}
    assert r[b'ALRT',2003]==bytes.fromhex('00000000007d012c07d34444')
    ditl=json.loads((ROOT/'assets/dialogs/ditl_2003.json').read_text())
    assert ditl['items'][0]['bounds']==dict(top=100,left=120,bottom=120,right=180)
    assert ditl['items'][1]['data']=='^0.'
    assert all((kind,2003) not in r for kind in [b'actb',b'ictb',b'dctb'])
    assert all((b'ICON',rid) not in r for rid in [0,1,2])
    for rid in [2040,2041,2044,2047,2050]:assert struct.unpack_from('>h',r[b'DLOG',rid],8)[0]==1

def test_original_selection_precedes_nested_alert_and_outer_loop_resumes():
    c=code(15)
    enable=ops(c,0x674,0x6a8);change=ops(c,0xb4,0xe6)
    assert enable[0x678]==('moveq','#$5, d0')
    assert enable[0x680]==('move.w','#$7d0, -(a7)')
    assert enable[0x684]==('dc.w','$a97e')
    assert enable[0x686]==('jsr','$0(pc)')
    assert enable[0x6a4]==('bne.w','$5e6')
    assert change[0xb6]==('moveq','#$6, d0')
    assert change[0xbe]==('move.w','#$3e8, -(a7)')
    assert change[0xc2]==('dc.w','$a97e')
    assert change[0xc4]==('jsr','$0(pc)')
    assert change[0xe2]==('bne.w','$52')

def test_system_icon_pixels_are_original_decoded_resources():
    p=ROOT/'assets/system_controls'
    m=json.loads((p/'system7_alert_icons.json').read_text())
    for icon in m['icons']:
        rid=icon['resource_id'];raw=(p/f'system7_alert_icon_{rid}.bin').read_bytes()
        bits=unpack(raw) if icon['attributes']&1 else raw
        assert len(bits)==128
        assert hashlib.sha256(bits).hexdigest()==icon['unpacked_sha256']
        img=Image.open(p/icon['file']).convert('RGBA')
        for y in range(32):
            for x in range(32):
                ink=bits[y*4+x//8]&(0x80>>(x%8))
                assert img.getpixel((x,y))==((0,0,0,255) if ink else (255,255,255,255))

def test_modal_structure_is_eight_pixels_outside_content():
    p=ROOT/'assets/system_controls'
    b=(p/'system7_wdef_0_unpacked.bin').read_bytes()
    assert b==unpack((p/'system7_wdef_0.bin').read_bytes())
    o=ops(b,0x710,0x75c)
    assert o[0x72a]==('move.l','$a06.w, -(a7)') #InsetRect -1,-1
    assert o[0x73e]==('cmpi.w','#$1, d5')
    assert o[0x746]==('move.l','#$fff9fff9, -(a7)') #another -7,-7
    assert o[0x74c]==('dc.w','$a8a9')
    assert struct.unpack_from('>8h',b,0xea6)==(26,24,26,23,30,32,32,28)
