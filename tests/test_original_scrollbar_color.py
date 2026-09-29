from pathlib import Path
import struct
import json
from PIL import Image
from capstone import Cs, CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000

ROOT=Path(__file__).resolve().parents[1]
FOLDER=ROOT/'assets/system_controls'


def instructions(start,end):
    b=(FOLDER/'system7_cdef_1_unpacked.bin').read_bytes()
    md=Cs(CS_ARCH_M68K,CS_MODE_BIG_ENDIAN|CS_MODE_M68K_000)
    return {i.address:(i.mnemonic,i.op_str) for i in md.disasm(b[start:end],start)}


def test_fallback_color_table_is_actual_system_resource():
    b=(FOLDER/'system7_cdef_1_unpacked.bin').read_bytes()
    c=(FOLDER/'system7_control_colors.bin').read_bytes()
    assert struct.unpack_from('>h',c,6)[0]==14
    for index in range(15):
        entry,r,g,blue=struct.unpack_from('>4H',c,8+index*8)
        assert entry==index
        assert (r,g,blue)==struct.unpack_from('>3H',b,0xcd2+6*index)
    game=(FOLDER/'game_control_colors.bin').read_bytes()
    assert struct.unpack_from('>h',game,6)[0]==3
    assert struct.unpack_from('>4H',game,16)==(1,0xff00,0xf66d,0x8997)


def test_track_pattern_and_disable_source_branches():
    assert (FOLDER/'system7_scrollbar_pattern17.bin').read_bytes()==bytes.fromhex('8822882288228822')
    track=instructions(0x6e8,0x734)
    assert track[0x6fc]==('move.w','#$1c, d0') #28 gray foreground
    assert track[0x700]==('move.w','#$16, d1') #22 gray background
    assert track[0x72c]==('move.w','#$11, -(a7)') #PAT17
    disabled=instructions(0x242,0x258)
    assert disabled[0x24a]==('moveq','#$20, d1') #32 disabled track fill
    arrows=instructions(0x4d2,0x50e)
    assert arrows[0x4d8]==('move.w','#$20, d1')
    assert arrows[0x4de]==('move.w','#$21, d1')
    assert arrows[0x4fc]==('addq.w','#$8, d0') #outline only disabled masks


def test_thumb_bevel_and_original_nonunity_interpolation():
    calc=instructions(0x826,0x860)
    assert calc[0x836]==('mulu.w','#$1111, d2')
    assert calc[0x84a]==('mulu.w','d2, d1')
    assert calc[0x84c]==('swap','d1')
    thumb=instructions(0x34e,0x3f4)
    assert thumb[0x34e]==('move.l','#$20003, -(a7)') #dv2,dh3
    assert thumb[0x362]==('move.w','#$22, d0') #34 light bevel
    assert thumb[0x36e]==('move.w','#$25, d0') #37 dark bevel
    assert thumb[0x39a]==('move.w','#$24, -$50(a6)') #36 grip foreground
    assert thumb[0x3a0]==('move.w','#$22, -$4e(a6)') #34 grip background
    assert thumb[0x3c2]==('move.w','#$23, d0') #35 first grip line
    colors=json.loads((FOLDER/'system7_scrollbar_color.json').read_text())
    assert colors['color_rgb16']['37']==[13108,13108,26215]


def test_exported_parts_disabled_gray_and_mask_geometry():
    atlas=Image.open(FOLDER/'system7_scrollbar_arrows_system.png').convert('RGBA')
    assert atlas.size==(96,16)
    assert atlas.getpixel((32+1,1))==(238,238,238,255) #disabled background, no bevel
    assert atlas.getpixel((32+7,3))==(119,119,119,255) #original outline mask
    assert atlas.getpixel((16+7,4))==(0,0,0,255) #pressed fill
    assert atlas.getpixel((7,4))==(163,163,215,255) #normal fill
    thumb=Image.open(FOLDER/'system7_scrollbar_thumb_rgb.png').convert('RGBA')
    assert thumb.size==(14,16)
    assert thumb.getpixel((0,0))==(85,85,85,255)
    assert thumb.getpixel((0,1))==(204,204,255,255)
    assert thumb.getpixel((13,15))==(51,51,102,255)
    assert thumb.getpixel((4,3))==(163,163,215,255)
    assert thumb.getpixel((4,4))==(204,204,255,255)
    assert thumb.getpixel((4,5))==(102,102,153,255)
    track=Image.open(FOLDER/'system7_scrollbar_track_rgb.png').convert('RGBA')
    assert track.getpixel((0,0))==(119,119,119,255)
    assert track.getpixel((1,0))==(221,221,221,255)
