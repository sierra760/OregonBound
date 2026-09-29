"""Original death panes and inherited score font; offsets exclude CODE headers."""
from pathlib import Path
import json
import struct
import macresources
from extract_a5 import decode_initial_data
from extract_ditl import parse_ditl_resource
ROOT = Path(__file__).resolve().parents[1]


def extract(root=ROOT):
    resources = list(macresources.parse_file((root/'raw/oregon_trail.rsrc').read_bytes()))
    def resource(kind, identifier):
        return bytes(next(r.data for r in resources if r.type == kind and r.id == identifier))
    a5 = decode_initial_data((root/'assets/code_segments/CODE_21_A5Init.bin').read_bytes())
    def words(displacement, count):
        return list(struct.unpack_from('>'+str(count)+'h', a5, len(a5)+displacement))
    string = resource(b'STR#',2050)
    caption = string[3:3+string[2]].decode('mac_roman')
    c3=(root/'assets/code_segments/CODE_3_Main2.bin').read_bytes()
    c10=(root/'assets/code_segments/CODE_10_Ending.bin').read_bytes()
    return dict(caption=caption, image=19150, sound=9001,
                callback_events=[0xcf4+x for x in struct.unpack_from('>6h',c3,0xcf6)],
                loss_callback_events=[0x24+x for x in struct.unpack_from('>6h',c10,0x26)],
                rectangles={str(i):words(-0x2d5c+i*8,4) for i in [4,5,13]},
                root_font=words(-0x2a84,5), plain_font=words(-0x2a8e,5),
                dialogs={str(i):parse_ditl_resource(resource(b'DITL',i),i) for i in [5300,5400,9150]})


if __name__=='__main__': print(json.dumps(extract(),indent=2,ensure_ascii=False))
