"""Original resource and CODE14 proof anchors for the fixed journal pane."""
import json
from pathlib import Path
import struct
import unittest
from scripts.extract_a5 import decode_initial_data

ROOT = Path(__file__).resolve().parents[1]


class OriginalJournalLayoutBinaryTests(unittest.TestCase):
    def test_resource_geometry_and_font_strikes(self):
        dialog=json.loads((ROOT/'assets/dialogs/ditl_5500.json').read_text())
        self.assertEqual(dialog['items'][0]['bounds'],dict(top=0,left=0,bottom=102,right=247))
        self.assertEqual(dialog['items'][1]['bounds'],dict(top=-1,left=247,bottom=103,right=263))
        a5=decode_initial_data((ROOT/'assets/code_segments/CODE_21_A5Init.bin').read_bytes())
        self.assertEqual(struct.unpack_from('>4h',a5,len(a5)-0x2d5c+6*8),(211,64,313,326))
        self.assertEqual(struct.unpack_from('>5h',a5,len(a5)-0x2a84),(6322,1,1,14,0))
        manifest=json.loads((ROOT/'assets/fonts/manifest.json').read_text())
        associations=manifest['families'][0]['associations']
        self.assertEqual([(x['style'],x['resource_id']) for x in associations if x['size']==12],[(0,23522),(1,17847)])
        for resource in [23522,17847]:
            strike=json.loads((ROOT/f'assets/fonts/nfnt_{resource}.json').read_text())
            self.assertEqual([strike['header'][k] for k in ['ascent','descent','leading']],[9,3,0])
            cr=next(g for g in strike['glyphs'] if g.get('code')==13)
            self.assertEqual(cr['advance'],0)
            self.assertEqual(cr['atlas_rect'][2],0)

    def test_truncation_appends_ellipsis_without_advancing_drawing_boundary(self):
        code=(ROOT/'assets/code_segments/CODE_14_Message.bin').read_bytes()
        # subq.b3,D7; store D7 as Pascal length; append C9 via helper1bfa.
        self.assertEqual(code[0x31a4:0x31b6],bytes.fromhex('570717470008487800c9486b00084ebaea46'))
        self.assertEqual(code[0x31c4:0x31c8],bytes.fromhex('11870000')) # move.b D7,(a0,d0.w)
        # The append helper saves/restores D7/A3, so final boundary is not length+1.
        self.assertEqual(code[0x1bfa:0x1bfe],bytes.fromhex('48e70110'))
        self.assertEqual(code[0x1c1e:0x1c22],bytes.fromhex('4cdf0880'))

    def test_original_insets_and_continuation_constants(self):
        code=(ROOT/'assets/code_segments/CODE_14_Message.bin').read_bytes()
        self.assertEqual(code[0x0048:0x004a],bytes.fromhex('700c')) # Item1 TextSize12.
        self.assertEqual(code[0x0be2:0x0be4],bytes.fromhex('5680')) # addq.l3 baseline.
        self.assertEqual(code[0x0c7c:0x0c7e],bytes.fromhex('720c')) # moveq12 continuation x.
        self.assertEqual(code[0x30ee:0x30f0],bytes.fromhex('5d85')) # subq.l6 width.
        self.assertEqual(code[0x31da:0x31dc],bytes.fromhex('700f')) # subtract15 next threshold.


if __name__=='__main__': unittest.main()
