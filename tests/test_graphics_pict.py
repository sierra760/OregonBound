import struct
import unittest
from pathlib import Path

from scripts.graphics_extract.resource_reader import read_resources
from scripts.graphics_extract.models import DecodeStatus, ResourceInfo
from scripts.graphics_extract.pict import _convert_indexed_packbits_pict, convert_pict


def make_resource(raw_length: int) -> ResourceInfo:
    return ResourceInfo("oregon_color", "PICT", 1, "", raw_length)


class PictDecoderTests(unittest.TestCase):
    def test_convert_pict_rejects_truncated_header(self):
        record = convert_pict(make_resource(4), b"abcd")

        self.assertEqual(record.status, DecodeStatus.FAILED)
        self.assertIsNone(record.width)
        self.assertIsNone(record.height)
        self.assertIsNone(record.mode)
        self.assertEqual(record.diagnostics[0].code, "pict.decode_failed")
        self.assertIn("PICT header requires 10 bytes", record.diagnostics[0].message)

    def test_convert_pict_rejects_inverted_frame_dimensions(self):
        data = struct.pack(">Hhhhh", 0, 0, 10, 5, 1)

        record = convert_pict(make_resource(len(data)), data)

        self.assertEqual(record.status, DecodeStatus.FAILED)
        self.assertIsNone(record.width)
        self.assertIsNone(record.height)
        self.assertIsNone(record.mode)
        self.assertEqual(record.diagnostics[0].code, "pict.invalid_dimensions")
        self.assertIn("Invalid PICT dimensions", record.diagnostics[0].message)

    def test_real_oregon_color_pict_decodes_indexed_packbits_bitmap(self):
        record = next(
            record
            for record in read_resources(Path("raw/oregon_color.rsrc"))
            if record.type_code == b"PICT" and record.info.resource_id == 10256
        )

        decoded = convert_pict(record.info, record.data)

        self.assertEqual(decoded.status, DecodeStatus.OK)
        self.assertIsNotNone(decoded.image)
        colors = decoded.image.convert("RGBA").getcolors(maxcolors=10_000_000)
        self.assertIsNotNone(colors)
        self.assertGreater(len(colors), 1)

    def test_indexed_packbits_fast_path_rejects_destination_rect_offsets(self):
        record = next(
            record
            for record in read_resources(Path("raw/oregon_color.rsrc"))
            if record.type_code == b"PICT" and record.info.resource_id == 10256
        )
        data = bytearray(record.data)
        packbits_opcode = data.index(b"\x00\x98")
        pixmap_offset = packbits_opcode + 2
        color_table_size = struct.unpack_from(">H", data, pixmap_offset + 46 + 6)[0]
        rect_offset = pixmap_offset + 46 + 8 + (color_table_size + 1) * 8
        dst_top_offset = rect_offset + 8
        struct.pack_into(">h", data, dst_top_offset, 1)

        self.assertIsNone(_convert_indexed_packbits_pict(bytes(data)))

    def test_indexed_packbits_fast_path_rejects_bitmap_smaller_than_pict_frame(self):
        record = next(
            record
            for record in read_resources(Path("raw/oregon_color.rsrc"))
            if record.type_code == b"PICT" and record.info.resource_id == 10256
        )
        data = bytearray(record.data)
        packbits_opcode = data.index(b"\x00\x98")
        pixmap_offset = packbits_opcode + 2
        struct.pack_into(">hhhh", data, pixmap_offset + 2, 0, 0, 1, 1)
        color_table_size = struct.unpack_from(">H", data, pixmap_offset + 46 + 6)[0]
        rect_offset = pixmap_offset + 46 + 8 + (color_table_size + 1) * 8
        struct.pack_into(">hhhhhhhh", data, rect_offset, 0, 0, 1, 1, 0, 0, 1, 1)

        self.assertIsNone(_convert_indexed_packbits_pict(bytes(data)))


if __name__ == "__main__":
    unittest.main()
