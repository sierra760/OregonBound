"""Verify CODE14 visibility/index anchors independently of the Swift projection."""
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]


class JournalVisibilityBinaryTests(unittest.TestCase):
    def setUp(self):
        self.code = (ROOT / 'assets/code_segments/CODE_14_Message.bin').read_bytes()

    def test_bold_event_jump_table_is_not_a_severity_guess(self):
        bold = [opcode for opcode in range(23,60)
                if 0x1702 + struct.unpack_from('>h',self.code,0x1704+2*(opcode-23))[0] == 0x174e]
        self.assertEqual(bold,[23,24,26,27,29,34,35,37,38,39,40,41,42,53,54,55,56,57,58,59])

    def test_visibility_exception_opcodes_are_original_immediates(self):
        # Every entry below is a moveq of an opcode compared in1904's predicate.
        for at,value in {0x1910:120,0x1926:120,0x196e:65,0x1978:25,0x1982:20,
                         0x198c:36,0x1996:43,0x19a0:105,0x1a18:71,
                         0x1a22:72,0x1a2c:80,0x1a88:118}.items():
            self.assertEqual(self.code[at:at+2],bytes([0x72,value]))
        # Crossing action literal130, then mask31 of record byte2.
        self.assertEqual(self.code[0x19dc:0x19e2],bytes.fromhex('0c8000000082'))
        self.assertEqual(self.code[0x19ea:0x19ee],bytes.fromhex('721fc280'))

    def test_rebuild_checkpoints_every_eight_physical_records(self):
        # recordCount &7; byteOffset=currentPointer-base; store word offset;
        # then store the separately maintained cumulative text-line word.
        self.assertEqual(self.code[0x0a52:0x0a56],bytes.fromhex('7207c280'))
        self.assertEqual(self.code[0x0a58:0x0a60],bytes.fromhex('202efee090ade264'))
        self.assertEqual(self.code[0x0a6c:0x0a70],bytes.fromhex('31801800'))
        self.assertEqual(self.code[0x0a7c:0x0a82],bytes.fromhex('31ade27c0800'))
        # Physical record count advances even after a hidden record (d94–dd6).
        self.assertEqual(self.code[0x0dd6:0x0dd8],bytes.fromhex('5254'))


if __name__ == '__main__':
    unittest.main()
