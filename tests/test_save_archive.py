import unittest
from pathlib import Path
from scripts.analysis_save_archive import recover_layout


class OriginalSaveLayoutTests(unittest.TestCase):
    def test_header_and_copy_lengths_are_read_from_original_instructions(self):
        layout = recover_layout()
        self.assertEqual(layout, dict(magic=0x4d454343, version=2, label_offset=6,
            header_word_offset=38, world_offset=40, world_size=4126,
            journal_state_offset=4166, journal_state_size=34,
            journal_offset=4200, journal_size=10240, file_size=14440,
            creator=0x4f52474e, file_type=0x4f524443))
        self.assertEqual(layout['world_offset'] + layout['world_size'], layout['journal_state_offset'])
        self.assertEqual(layout['journal_state_offset'] + layout['journal_state_size'], layout['journal_offset'])
        self.assertEqual(layout['world_size'], 606 + 32 * 110)

    def test_mutated_copy_instruction_is_not_silently_accepted(self):
        code = bytearray(Path('assets/code_segments/CODE_6_Main3.bin').read_bytes())
        code[0x01d6] ^= 1
        with self.assertRaisesRegex(ValueError, '01d6'):
            recover_layout(code)

    def test_original_read_and_write_block_sizes_and_position_modes_agree(self):
        code = Path('assets/code_segments/CODE_6_Main3.bin').read_bytes()
        self.assertEqual(code[0x05ae:0x05bc], code[0x0652:0x0660])
        self.assertEqual(code[0x05fa:0x0608], code[0x0696:0x06a4])
        self.assertEqual(code[0x05ae:0x05bc].hex(), '2d7c00001068ffd43d7c0001ffdc')
        self.assertEqual(code[0x05fa:0x0608].hex(), '2d7c00002800ffd43d7c0003ffdc')
