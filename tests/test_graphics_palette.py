from pathlib import Path
import struct
import unittest

from scripts.graphics_extract.palette import (
    PIXMAP_OFFSET_CICN,
    PIXMAP_OFFSET_IMAG,
    build_palette_bytes,
    parse_color_table,
    parse_pixmap,
)
from scripts.graphics_extract.resource_reader import read_resources


class PaletteTests(unittest.TestCase):
    def test_parse_pixmap_extracts_bounds_and_pixel_size(self):
        data = bytearray(50)
        struct.pack_into(">Hhhhh", data, 4, 0x8004, 1, 2, 11, 22)
        struct.pack_into(">H", data, 32, 8)

        pixmap = parse_pixmap(bytes(data), 0)

        self.assertTrue(pixmap["is_pixmap"])
        self.assertEqual(pixmap["row_bytes"], 4)
        self.assertEqual(pixmap["bounds"], (1, 2, 11, 22))
        self.assertEqual(pixmap["width"], 20)
        self.assertEqual(pixmap["height"], 10)
        self.assertEqual(pixmap["pixel_size"], 8)

    def test_parse_color_table_returns_8_bit_rgb_entries(self):
        data = (
            struct.pack(">IHH", 0, 0x8000, 1)
            + struct.pack(">HHHH", 0, 0xFFFF, 0x0000, 0x8000)
            + struct.pack(">HHHH", 1, 0x0000, 0x4000, 0xFFFF)
        )

        colors = parse_color_table(data, 0)

        self.assertEqual(colors, [(255, 0, 128), (0, 64, 255)])
        self.assertEqual(build_palette_bytes(colors)[:6], bytes([255, 0, 128, 0, 64, 255]))
        self.assertEqual(len(build_palette_bytes(colors)), 768)

    def test_parse_color_table_rejects_truncated_header(self):
        with self.assertRaisesRegex(ValueError, "Color table header"):
            parse_color_table(b"\x00\x00\x00", 0)

    def test_parse_color_table_rejects_truncated_entries(self):
        data = (
            struct.pack(">IHH", 0, 0x8000, 1)
            + struct.pack(">HHHH", 0, 0xFFFF, 0x0000, 0x8000)
        )

        with self.assertRaisesRegex(ValueError, "Color table entries"):
            parse_color_table(data, 0)

    def test_parse_oregon_color_imag_19000_requires_imag_offset(self):
        records = read_resources(Path("raw/oregon_color.rsrc"))
        imag_19000 = next(
            record for record in records if record.type_code == b"Imag" and record.info.resource_id == 19000
        )

        pixmap_at_cicn_offset = parse_pixmap(imag_19000.data, PIXMAP_OFFSET_CICN)
        pixmap_at_imag_offset = parse_pixmap(imag_19000.data, PIXMAP_OFFSET_IMAG)

        self.assertNotEqual(pixmap_at_cicn_offset["bounds"], (0, 0, 304, 494))
        self.assertEqual(pixmap_at_imag_offset["row_bytes"], 494)
        self.assertEqual(pixmap_at_imag_offset["bounds"], (0, 0, 304, 494))
        self.assertEqual(pixmap_at_imag_offset["width"], 494)
        self.assertEqual(pixmap_at_imag_offset["height"], 304)
        self.assertEqual(pixmap_at_imag_offset["pixel_size"], 8)


if __name__ == "__main__":
    unittest.main()
