import struct
import unittest
from pathlib import Path

from scripts.graphics_extract.cicn import decode_cicn
from scripts.graphics_extract.models import DecodeStatus, ResourceInfo
from scripts.graphics_extract.resource_reader import read_resources


def make_two_pixel_cicn() -> bytes:
    pixmap = bytearray(50)
    struct.pack_into(">Hhhhh", pixmap, 4, 0x8002, 0, 0, 1, 2)
    struct.pack_into(">H", pixmap, 32, 8)

    mask_bitmap = bytearray(14)
    struct.pack_into(">Hhhhh", mask_bitmap, 4, 1, 0, 0, 1, 2)

    bw_bitmap = bytearray(14)
    struct.pack_into(">Hhhhh", bw_bitmap, 4, 1, 0, 0, 1, 2)

    handle = b"\x00\x00\x00\x00"
    mask_data = b"\xC0"
    bw_data = b"\x00"
    color_table = (
        struct.pack(">IHH", 0, 0x8000, 1)
        + struct.pack(">HHHH", 0, 0xFFFF, 0x0000, 0x0000)
        + struct.pack(">HHHH", 1, 0x0000, 0xFFFF, 0x0000)
    )
    pixel_data = bytes([0, 1])
    return bytes(pixmap + mask_bitmap + bw_bitmap) + handle + mask_data + bw_data + color_table + pixel_data


def make_sparse_four_bit_cicn() -> bytes:
    pixmap = bytearray(50)
    struct.pack_into(">Hhhhh", pixmap, 4, 0x8001, 0, 0, 1, 1)
    struct.pack_into(">H", pixmap, 32, 4)

    mask_bitmap = bytearray(14)
    struct.pack_into(">Hhhhh", mask_bitmap, 4, 1, 0, 0, 1, 1)

    bw_bitmap = bytearray(14)
    struct.pack_into(">Hhhhh", bw_bitmap, 4, 1, 0, 0, 1, 1)

    handle = b"\x00\x00\x00\x00"
    mask_data = b"\x80"
    bw_data = b"\x00"
    color_table = (
        struct.pack(">IHH", 0, 0x8000, 1)
        + struct.pack(">HHHH", 0, 0x0000, 0x0000, 0x0000)
        + struct.pack(">HHHH", 15, 0x0000, 0x0000, 0xFFFF)
    )
    pixel_data = bytes([0xF0])
    return bytes(pixmap + mask_bitmap + bw_bitmap) + handle + mask_data + bw_data + color_table + pixel_data


class CicnDecoderTests(unittest.TestCase):
    def test_decode_cicn_returns_rgba_image_record(self):
        resource = ResourceInfo("oregon_color", "cicn", 5000, "", len(make_two_pixel_cicn()))

        records = decode_cicn(resource, make_two_pixel_cicn())

        self.assertEqual(len(records), 1)
        record = records[0]
        self.assertEqual(record.status, DecodeStatus.OK)
        self.assertEqual(record.width, 2)
        self.assertEqual(record.height, 1)
        self.assertEqual(record.mode, "RGBA")
        self.assertEqual(record.image.tobytes(), bytes([255, 0, 0, 255, 0, 255, 0, 255]))
        self.assertEqual(record.palette.entry_count, 2)

    def test_decode_cicn_uses_sparse_color_spec_values(self):
        resource = ResourceInfo("oregon_color", "cicn", 5001, "", len(make_sparse_four_bit_cicn()))

        records = decode_cicn(resource, make_sparse_four_bit_cicn())

        self.assertEqual(len(records), 1)
        record = records[0]
        self.assertEqual(record.status, DecodeStatus.OK)
        self.assertEqual(record.width, 1)
        self.assertEqual(record.height, 1)
        self.assertEqual(record.image.tobytes(), bytes([0, 0, 255, 255]))
        self.assertEqual(record.palette.entry_count, 2)

    def test_decode_real_oregon_color_cicn_resources(self):
        resources = read_resources(Path("raw/oregon_color.rsrc"))
        cicn_resources = [record for record in resources if record.type_code == b"cicn"]

        self.assertEqual(len(cicn_resources), 24)
        for record in cicn_resources:
            with self.subTest(resource_id=record.info.resource_id):
                decoded = decode_cicn(record.info, record.data)

                self.assertEqual(len(decoded), 1)
                self.assertNotEqual(decoded[0].status, DecodeStatus.FAILED)
                self.assertEqual(decoded[0].width, 32)
                self.assertEqual(decoded[0].height, 32)


if __name__ == "__main__":
    unittest.main()
