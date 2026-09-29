"""Independent source anchors for CODE14 supply/trade/decision expansion."""
import json
from pathlib import Path
import struct
import unittest
from scripts.extract_a5 import decode_initial_data

ROOT = Path(__file__).resolve().parents[1]


class SaveJournalExpansionBinaryTests(unittest.TestCase):
    def setUp(self):
        self.code = (ROOT / 'assets/code_segments/CODE_14_Message.bin').read_bytes()

    def test_decision_action_dispatch_subtractions_and_targets(self):
        # Recover action selectors from the actual chain, not from text templates.
        subtracts = [0x2bb2, 0x2bb6, 0x2bba, 0x2bc0, 0x2bc6, 0x2bcc,
                     0x2bd2, 0x2bd8, 0x2bde, 0x2be4, 0x2bea, 0x2bf0, 0x2bf6]
        actions = []
        total = 0
        for at in subtracts:
            op = struct.unpack_from('>H', self.code, at)[0]
            if op == 0x0400:  # subi.b #immediate,d0
                total += struct.unpack_from('>H', self.code, at+2)[0]
                branch = at+4
            else:  # subq.b #1/#7,d0
                self.assertEqual(op & 0xf1ff, 0x5100)
                total += (op >> 9) & 7 or 8
                branch = at+2
            self.assertEqual(self.code[branch], 0x67)  # beq
            displacement = self.code[branch+1]
            if displacement == 0:
                displacement = struct.unpack_from('>h', self.code, branch+2)[0]
            elif displacement >= 128:
                displacement -= 256
            actions.append((total, branch+2+displacement))
        self.assertEqual(actions, [(1,0x2c02),(2,0x2c1c),(3,0x2cc2),(4,0x2cdc),
            (5,0x2d42),(6,0x2d8a),(7,0x2dbe),(8,0x2dfa),(9,0x2e52),
            (10,0x2da4),(17,0x2e84),(66,0x2c36),(130,0x2c80)])

    def test_trade_quantity_loads_and_crossing_method_bits(self):
        # move.l 4(a3),-(sp); move.l 8(a3),-(sp).
        self.assertEqual(self.code[0x29fa:0x29fe], bytes.fromhex('2f2b0004'))
        self.assertEqual(self.code[0x2a38:0x2a3c], bytes.fromhex('2f2b0008'))
        # Crossing reads byte2, shifts5, masks7, addsSTR item11.
        self.assertEqual(self.code[0x2c9a:0x2caa], bytes.fromhex('10280002ea887207c280700bd2803f01'))
        for rid in (1505,1525):
            resource = json.loads((ROOT / f'assets/strings/str_{rid}.json').read_text())
            self.assertEqual(resource['count'],11)
            self.assertEqual(len(resource['strings']),11)

    def test_original_pascal_substitution_tokens(self):
        initial = next((ROOT / 'assets/code_segments').glob('CODE_21*')).read_bytes()
        memory = decode_initial_data(initial)
        expected = {0x1e18:'^0',0x1e14:'^3',0x1e10:'^2',0x1e0c:'^4',
                    0x1e08:'^5',0x1e04:'^0',0x1e00:'^5',0x1df4:'^6',0x1df0:'^5'}
        for displacement, token in expected.items():
            pos = len(memory)-displacement
            self.assertEqual(memory[pos],2)
            self.assertEqual(memory[pos+1:pos+3].decode('mac_roman'),token)


if __name__ == '__main__':
    unittest.main()
