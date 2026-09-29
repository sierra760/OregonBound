"""Exact System7 CDEF0 call sites and authored Time Options control rectangles."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]

def test_system7_radio_raster_call_parameters():
    code = (ROOT/'raw/system7/cdef_0_unpacked.bin').read_bytes()
    assert hashlib.sha256(code).hexdigest() == 'b647566a3fe540ae1e2477e6c3ced3d3a33cfffc131fcd8fbfa22c5774cc0dde'
    assert code[0x482:0x490].hex() == '90540440000ce24092403f410004'
    assert code[0x4b0:0x4c2].hex() == '322c000254413f4100020641000c3f410006'
    assert code[0x4e4:0x4ec].hex() == '2f3c00020002a89b' # pressed PenSize2,2
    assert code[0x4f8:0x500].hex() == 'a8b7a89ee24d6440' # FrameOval,PenNormal,selected bit
    assert code[0x532:0x540].hex() == '2f0f2f3c00030003a8a92f0fa8b8' # inset3,PaintOval
    assert code[0x252:0x25a].hex() == '322c000206410012' # left+18 label baseline x

def test_authored_radio_bounds_labels_and_color_requests():
    items=json.loads((ROOT/'assets/dialogs/ditl_2047.json').read_text())['items']
    assert [(x['data'],x['bounds']) for x in items if x['type']=='radio'] == [
        ('Fast',dict(top=90,left=70,bottom=105,right=145)),
        ('Medium',dict(top=70,left=70,bottom=85,right=145)),
        ('Slow',dict(top=50,left=70,bottom=65,right=145))]
    # Requested control frame0/text2 RGB are black. These aren't device indices.
    import struct
    for name in ['system7_control_colors.bin','game_control_colors.bin']:
        data=(ROOT/'assets/system_controls'/name).read_bytes()
        colors={v:(r,g,b) for v,r,g,b in struct.iter_unpack('>4H',data[8:])}
        assert colors[0] == (0,0,0) and colors[2] == (0,0,0)

def test_live_original_capture_matches_integer_radio_masks():
    # Original1024x768 capture, unchanged. JPEG threshold only classifies ink;
    # no edited/cropped reference asset is generated or used as implementation.
    from math import isqrt
    from PIL import Image
    source=ROOT/'docs/reference/original-time-options-2026-09-19.jpg'
    image=Image.open(source).convert('RGB')
    def circle(size,inset=0):
        result=set()
        for y in range(size):
            k=isqrt(size*size-(1-size+2*y)**2)
            result.update((x+inset,y+inset) for x in range((size-k)//2,(size+k+1)//2))
        return result
    ring=circle(12)-circle(10,1)
    for origin_y,selected in [(355,False),(375,True),(395,False)]:
        ink={(x,y) for y in range(12) for x in range(12)
             if sum(image.getpixel((479+x,origin_y+y)))<384}
        assert ink == ring | (circle(6,3) if selected else set())
