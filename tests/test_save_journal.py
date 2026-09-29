import unittest
from pathlib import Path
from scripts.analysis_save_journal import fixed_sizes, records


class OriginalSaveJournalTests(unittest.TestCase):
    def test_all_fixed_opcode_ranges_are_derived_from_binary_bounds_and_steps(self):
        sizes = fixed_sizes()
        for low, high, size in [(0,62,2),(63,69,16),(70,84,12),(85,95,4),(105,111,4),(120,120,6)]:
            self.assertEqual([sizes[n] for n in range(low,high+1)], [size]*(high-low+1))
        for value in [96,104,112,117,118,119,121,255]:
            self.assertNotIn(value, sizes)

    def test_variable_message_alignment_and_date_marker(self):
        data = bytes([120,0,7,56,4,6,118,0,3,72,101,121,2,4,9,0xff,119,0,2,72,105,0xab])
        parsed = records(data)
        self.assertEqual([r['length'] for r in parsed], [6,10,6])
        self.assertEqual(parsed[0]['date'], dict(year=1848,month=4,day=6))
        self.assertEqual(b''.join(bytes.fromhex(r['hex']) for r in parsed), data)

    def test_original_name_limit_and_copy_geometry_instructions(self):
        code = Path('assets/code_segments/CODE_19_Startup.bin').read_bytes()
        self.assertEqual(code[0xa38:0xa40].hex(), '720fb2806d000148')
        self.assertEqual(code[0xaa4:0xaac].hex(), '2006e980487408f6')

    def test_unknown_opcode_and_missing_alignment_byte_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Unsupported'):
            records(bytes([96,0]))
        with self.assertRaisesRegex(ValueError, 'Truncated'):
            records(bytes([119,0,0]))
