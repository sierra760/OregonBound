from pathlib import Path
import json
import struct
import tempfile
import unittest

import macresources
from PIL import Image

from scripts.extract_fonts import extract_fonts, glyph_for_code, parse_fond, parse_nfnt, render_text


def synthetic_font() -> bytes:
    # A uses columns0..2; B is absent; missing glyph occupies columns3..4.
    # owTLoc=12 words relative to byte16 => byte40, not resource byte24.
    header = struct.pack('>HHHHhhHHHHHhH', 0x9000, 65, 66, 4, -1, -1, 4, 3, 12, 2, 1, 0, 1)
    bitmap = b'\xb0\x00\xe8\x00\xb0\x00'
    locations = struct.pack('>4H', 0, 3, 3, 5)
    widths = struct.pack('>4H', 0x0204, 0xffff, 0x0003, 0xffff)
    return header + bitmap + locations + widths


class FontTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.resources = list(macresources.parse_file(Path('raw/oregon_trail.rsrc').read_bytes()))
        cls.font_data = {r.id: bytes(r) for r in cls.resources if r.type == b'NFNT'}

    def test_documented_offsets_and_msb_bitmap_boundaries(self):
        font, atlas = parse_nfnt(synthetic_font(), 1)
        self.assertEqual(font['table_offsets'], {'bitmap': 26, 'locations': 32, 'widths': 40, 'parsed_end': 48})
        self.assertEqual(font['glyphs'][0]['atlas_rect'], [0, 0, 3, 3])
        self.assertEqual(font['glyphs'][1]['atlas_rect'], [3, 0, 0, 3])
        self.assertEqual(font['glyphs'][2]['atlas_rect'], [3, 0, 2, 3])
        self.assertEqual([bool(atlas.getpixel((x, 0))) for x in range(5)], [True, False, True, True, False])

    def test_advance_and_signed_bearing_are_independent_of_bitmap_width(self):
        font, _ = parse_nfnt(synthetic_font(), 1)
        a = glyph_for_code(font, 65)
        missing = glyph_for_code(font, 66)
        self.assertEqual((a['advance'], a['bearing_x'], a['bearing_y']), (4, 1, -2))
        self.assertEqual((missing['advance'], missing['bearing_x']), (3, -1))

    def test_missing_codes_use_original_missing_glyph(self):
        font, atlas = parse_nfnt(synthetic_font(), 1)
        missing = font['glyphs'][2]
        for code in (64, 66, 67, -1, 256, None):
            self.assertIs(glyph_for_code(font, code), missing)
        image, advance = render_text(font, atlas, 'AB🦬')
        self.assertEqual(advance, 10)
        self.assertEqual(image.mode, '1')
        self.assertEqual(set(image.convert("L").tobytes()), {0, 255})

    def test_blank_space_retains_advance_without_missing_fallback(self):
        font, atlas = parse_nfnt(self.font_data[23522], 23522)
        space = glyph_for_code(font, 32)
        self.assertFalse(space['missing'])
        self.assertEqual(space['atlas_rect'][2], 0)
        self.assertEqual(space['advance'], 3)
        image, advance = render_text(font, atlas, '   ')
        self.assertEqual(advance, 9)
        self.assertEqual(image.size, (9, 12))
        self.assertEqual(set(image.convert("L").tobytes()), {255})

    def test_original_plain12_A_matches_hand_checked_resource_bits(self):
        font, atlas = parse_nfnt(self.font_data[23522], 23522)
        glyph = glyph_for_code(font, 65)
        self.assertEqual(glyph['atlas_rect'], [140, 0, 8, 12])
        self.assertEqual(glyph['advance'], 8)
        x, y, width, height = glyph['atlas_rect']
        rows = [''.join('#' if atlas.getpixel((x + column, row)) else '.' for column in range(width)) for row in range(height)]
        self.assertEqual(rows, [
            '........', '...#....', '...#....', '..#.#...', '..#.#...', '.#...#..',
            '.#####..', '#.....#.', '##...###', '........', '........', '........',
        ])

    def test_fond_maps_size_style_and_resource_without_id_arithmetic(self):
        resource = next(r for r in self.resources if r.type == b'FOND')
        family = parse_fond(bytes(resource), resource.id, str(resource.name))
        self.assertEqual(family['name'], 'WTTimes')
        self.assertEqual(family['family_id'], 6322)
        self.assertEqual([(a['size'], a['style'], a['resource_id']) for a in family['associations']],
                         [(12, 0, 23522), (12, 1, 17847), (14, 0, 22669), (14, 1, 16131)])
        self.assertEqual(family['associations'][1]['style_names'], ['bold'])
        self.assertEqual(family['width_table_offset'], 0)
        self.assertEqual(family['kerning_table_offset'], 0)

    def test_all_atlas_bits_round_trip_to_original_bitmap_bytes(self):
        for resource_id, data in self.font_data.items():
            with self.subTest(resource_id=resource_id):
                font, atlas = parse_nfnt(data, resource_id)
                self.assertEqual(atlas.tobytes(), data[26:font['table_offsets']['locations']])
                self.assertEqual(font['table_offsets']['parsed_end'], len(data))
                self.assertEqual(len(font['glyphs']), 257)
                for glyph in font['glyphs']:
                    x, _, width, _ = glyph['atlas_rect']
                    self.assertLessEqual(x + width, atlas.width)
                self.assertEqual(font['image_height_table'] is not None, resource_id in (17847, 16131))

    def test_exported_png_and_json_retain_original_bits_and_metrics(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = extract_fonts(Path('raw/oregon_trail.rsrc'), root)
            self.assertEqual(len(manifest['fonts']), 4)
            for entry in manifest['fonts']:
                font = json.loads((root / entry['metrics_file']).read_text())
                atlas = Image.open(root / entry['atlas_file'])
                data = self.font_data[entry['resource_id']]
                self.assertEqual(atlas.tobytes(), data[26:font['table_offsets']['locations']])
                self.assertEqual((root / f"nfnt_{entry['resource_id']}.bin").read_bytes(), data)
                self.assertEqual(len(font['family_associations']), 1)

    def test_truncated_or_invalid_tables_are_rejected(self):
        for data in (synthetic_font()[:25], synthetic_font()[:-1]):
            with self.assertRaises(ValueError):
                parse_nfnt(data, 1)
        data = bytearray(synthetic_font())
        struct.pack_into('>H', data, 34, 17)
        with self.assertRaisesRegex(ValueError, 'boundaries'):
            parse_nfnt(bytes(data), 1)

    def test_plain_system_strike_can_end_after_missing_glyph_metric(self):
        font, _ = parse_nfnt(synthetic_font()[:-2], 1)
        self.assertEqual(font['offset_width_table'], [0x0204, 0xffff, 0x0003])
        self.assertEqual(font['table_offsets']['parsed_end'], 46)
        self.assertEqual(font['glyphs'][-1]['advance'], 3)
        for raw in (synthetic_font()[:-3], synthetic_font()[:-4]):
            with self.assertRaises(ValueError):
                parse_nfnt(raw, 1)


if __name__ == '__main__':
    unittest.main()
