"""Original CDEF0 and CODE5 parameters; complete Time Options button ink oracle."""
from pathlib import Path
from math import isqrt
import json
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]

def test_original_color_roles_integer_center_and_round_rect_calls():
    code=(ROOT/'raw/system7/cdef_0_unpacked.bin').read_bytes()
    assert code[0x166:0x17e].hex()=='20531028001153000c0000fd640470026002700161a8aa15'
    assert code[0x2ae:0x2ca].hex()=='303c000160104a2effc667063f3c0031a889303c00026100fe5eaa14'
    assert code[0x302:0x30a].hex()=='70006100fe1eaa14'
    assert code[0x3da:0x3ee].hex()=='4a0666123828000c98680008e24c300448443800'
    assert code[0x25c:0x26c].hex()=='322c0006926c00029240e241d26c0002'
    assert code[0x18c:0x192].hex()=='2f0c2f04a8b2' # EraseRoundRect
    assert code[0x316:0x31c].hex()=='2f0c2f04a8b0' # FrameRoundRect

def test_original_default_ring_outset_four_pen_three_oval_sixteen():
    code=(ROOT/'assets/code_segments/CODE_5_Display.bin').read_bytes()
    assert code[0x3232:0x3252].hex()=='70033f003f00a89b486effe670fc3f003f00a8a9486effe670103f003f00a8b0'

def round_rect(x,y,width,height,diameter):
    """Independent quadratic formula for square corner ovals, not Swift loop."""
    result=set();top=diameter//2;bottom=height-diameter+top
    for row in range(height):
        n=row if row<top else diameter-(height-row) if row>=bottom else top-1
        k=isqrt(diameter*diameter-(1-diameter+2*n)**2)
        left=(diameter-k)//2;right=width-diameter+(diameter+k+1)//2
        result.update((x+col,y+row) for col in range(left,right))
    return result

def test_complete_original_cancel_and_default_ok_ink_matches_recovered_recipe():
    reference=Image.open(ROOT/'docs/reference/original-time-options-2026-09-19.jpg').convert('RGB')
    metrics=json.loads((ROOT/'assets/fonts/nfnt_5478.json').read_text())
    glyphs={g['code']:g for g in metrics['glyphs'] if g.get('code') is not None}
    atlas=Image.open(ROOT/'assets/fonts/nfnt_5478.png').convert('RGBA')
    for title,origin_x,default in [('Cancel',423,False),('OK',513,True)]:
        # Local padded88×28 control. Original content starts at407,303.
        expected=round_rect(4,4,80,20,10)-round_rect(5,5,78,18,8)
        if default: expected |= round_rect(0,0,88,28,16)-round_rect(3,3,82,22,10)
        width=sum(glyphs[b]['advance'] for b in title.encode('mac_roman'))
        cursor=4+(80-width)//2
        for byte in title.encode('mac_roman'):
            g=glyphs[byte];left,top,w,h=g['atlas_rect']
            for y in range(h):
                for x in range(w):
                    if atlas.getpixel((left+x,top+y))[0]>127:
                        expected.add((cursor+g['bearing_x']+x,6+y))
            cursor+=g['advance']
        actual={(x,y) for y in range(28) for x in range(88)
                if sum(reference.getpixel((origin_x+x,474+y)))<384}
        assert actual == expected
