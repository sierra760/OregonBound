"""Source anchors for application-owned management TextEdit filters."""
import json
from pathlib import Path
import unittest
from capstone import Cs, CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000

ROOT = Path(__file__).resolve().parents[1]

def code(segment):
    return next((ROOT / 'assets/code_segments').glob(f'CODE_{segment}_*')).read_bytes()

def ops(segment, start, end):
    md = Cs(CS_ARCH_M68K, CS_MODE_BIG_ENDIAN | CS_MODE_M68K_000)
    md.skipdata = True
    return {i.address: (i.mnemonic, i.op_str) for i in md.disasm(code(segment)[start:end], start)}

class ManagementTextEditBinaryTests(unittest.TestCase):
    def test_password_whitelist_precedes_dead_escape_remap_and_cap_tests_arrows(self):
        p = ops(15, 0x220, 0x2f0)
        for address, operation in {
            0x224: ('moveq', '#$21, d0'), 0x22e: ('moveq', '#$7e, d0'),
            0x238: ('moveq', '#$8, d0'), 0x242: ('moveq', '#$9, d0'),
            0x24c: ('moveq', '#$1c, d0'), 0x258: ('moveq', '#$1f, d0'),
            0x250: ('bgt.w', '$2e0'), 0x25c: ('blt.w', '$2e0'),
            0x264: ('moveq', '#$1b, d0'), 0x26e: ('moveq', '#$7f, d0'),
            0x286: ('moveq', '#$8, d0'), 0x28a: ('bne.b', '$294'),
            0x2c2: ('moveq', '#$a, d1'), 0x2c6: ('ble.b', '$2d0'),
        }.items(): self.assertEqual(p[address], operation)
        self.assertEqual(code(15)[0x2d4:0x2d6], bytes.fromhex('a9c8'))

    def test_return_rewrites_event_and_hint_only_rewrites_probe(self):
        p = ops(15, 0x1a0, 0x1ce)
        self.assertEqual(p[0x1c0], ('moveq', '#$9, d0'))
        self.assertEqual(p[0x1c2], ('move.l', 'd0, $2(a3)'))
        p = ops(15, 0x316, 0x3c4)
        self.assertEqual(p[0x32a], ('moveq', '#$8, d7'))
        self.assertEqual(p[0x370], ('addq.l', '#$8, a0'))
        self.assertEqual(p[0x378], ('move.l', '(a1)+, (a0)+'))
        self.assertEqual(p[0x37a], ('ext.w', 'd7'))
        self.assertEqual(code(15)[0x382:0x384], bytes.fromhex('a9dc'))
        self.assertEqual(p[0x38a], ('move.w', '$5e(a0), d0'))
        self.assertEqual(p[0x390], ('moveq', '#$3, d1'))
        self.assertEqual(p[0x394], ('blt.b', '$39c'))

    def test_mask_keeps_hidden_key_and_return_only_keydown(self):
        p = ops(15, 0x1382, 0x13e4)
        self.assertEqual(code(15)[0x13a8:0x13aa], bytes.fromhex('a9d1'))
        self.assertEqual(p[0x13b4], ('moveq', '#$a5, d0'))
        self.assertEqual(p[0x13b6], ('move.l', 'd0, $2(a3)'))
        self.assertEqual(p[0x13d8], ('ext.w', 'd7'))
        self.assertEqual(code(15)[0x13e0:0x13e2], bytes.fromhex('a9dc'))
        q = ops(1, 0x37e, 0x400)
        self.assertEqual(q[0x382], ('moveq', '#$3, d1'))
        self.assertEqual(q[0x386], ('bne.b', '$3ea'))

    def test_hint_and_password_resource_rectangles(self):
        resources = {rid: json.loads((ROOT/f'assets/dialogs/ditl_{rid}.json').read_text())['items'] for rid in [2041,2044]}
        hint = resources[2044][7]
        self.assertEqual(hint['type'], 'editText')
        self.assertEqual(hint['bounds'], dict(top=100,left=140,bottom=148,right=275))
        self.assertEqual(resources[2041][4]['bounds'], dict(top=35,left=128,bottom=52,right=260))
        self.assertEqual(resources[2044][5]['type'], 'editText')
        self.assertEqual(resources[2044][6]['type'], 'editText')

if __name__ == '__main__': unittest.main()
