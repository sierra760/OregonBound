from pathlib import Path
import importlib
import struct
import unittest

import macresources

from scripts.graphics_extract.imag import decode_imag, fallback_palette_from_resources
from scripts.graphics_extract.imag_codec import (
    decode_frame,
    expand_bits,
    expand_bits_signed,
    fun_000018e4,
    mecc_rle,
)
from scripts.graphics_extract.models import DecodeStatus, ResourceInfo


def make_resource(raw_length: int) -> ResourceInfo:
    return ResourceInfo("test", "Imag", 1, "", raw_length)


def make_frame(
    pixel_data: bytes, width: int = 1, height: int = 1,
    row_bytes: int | None = None, inline_palette: bool = True,
) -> bytes:
    # CODE 5:0x5ba2 and 0x5d3c–0x5d62: length32 + PixMap50 + payload.
    row_bytes = width if row_bytes is None else row_bytes
    pixmap = bytearray(50)
    struct.pack_into(">H", pixmap, 4, 0x8000 | row_bytes)
    struct.pack_into(">hhhh", pixmap, 6, 0, 0, height, width)
    struct.pack_into(">H", pixmap, 32, 8)
    ctable = bytearray()
    if inline_palette:
        ctable.extend(struct.pack(">IHH", 0, 0x8000, 255))
        for index in range(256):
            component = index * 257
            ctable.extend(struct.pack(">HHHH", index, component, component, component))
    else:
        struct.pack_into(">I", pixmap, 42, 0xffffffff)
    payload = bytes(pixmap) + bytes(ctable) + pixel_data
    return struct.pack(">I", len(payload) + 4) + payload


def make_inline_ctable_imag(
    frame_count: int, pixel_data: bytes, width: int = 1, height: int = 1,
    row_bytes: int | None = None,
) -> bytes:
    return struct.pack(">H", frame_count) + make_frame(pixel_data, width, height, row_bytes)


def diagnostic_codes(records):
    return [diag.code for record in records for diag in record.diagnostics]


class ImagDecoderTests(unittest.TestCase):
    def test_expand_bits_supports_non_power_of_two_depths(self):
        self.assertEqual(expand_bits(bytes([0b101_011_00]), 3, 2), bytes([0b100, 0b101]))

    def test_expand_bits_signed_supports_non_power_of_two_depths(self):
        self.assertEqual(expand_bits_signed(bytes([0b101_011_00]), 3, 2), [-4, -3])

    def test_expand_bits_matches_original_lsb_first_tables(self):
        self.assertEqual(expand_bits(bytes([0b1110_0100]), 2, 4), bytes([0, 1, 2, 3]))

    def test_mecc_rle_repeats_fixed_width_patterns(self):
        decoded, consumed = mecc_rle(bytes([0x01, 0xAA, 0xBB]), 0, 4, pattern_len=2)

        self.assertEqual(decoded, bytes([0xAA, 0xBB, 0xAA, 0xBB]))
        self.assertEqual(consumed, 3)

    def test_mecc_rle_preserves_current_item_overshoot_for_bit_lookahead(self):
        decoded, consumed = mecc_rle(bytes([0x81, 0xAA, 0xBB]), 0, 1)

        self.assertEqual(decoded, bytes([0xAA, 0xBB]))
        self.assertEqual(consumed, 3)

    def test_case1_index_decoder_uses_unsigned_positive_sentinel(self):
        decoded, consumed = fun_000018e4(
            bytes([1, 3, 2]),
            comp_w=2,
            ivar5=bytes([10, 11, 12, 13, 14, 15]),
            depth=2,
        )

        self.assertEqual(decoded, bytes([11, 15]))
        self.assertEqual(consumed, 3)

    def test_case1_index_decoder_consumes_lookahead_after_trailing_sentinel(self):
        decoded, consumed = fun_000018e4(
            bytes([3, 2]),
            comp_w=1,
            ivar5=bytes([10, 11, 12, 13, 14, 15]),
            depth=2,
        )

        self.assertEqual(decoded, bytes([15]))
        self.assertEqual(consumed, 2)

    def test_import_from_repo_root_without_pythonpath(self):
        module = importlib.import_module("scripts.graphics_extract.imag")

        self.assertIs(module.decode_imag, decode_imag)

    def test_truncated_frame_header_returns_non_ok_diagnostic(self):
        data = make_inline_ctable_imag(frame_count=1, pixel_data=b"\x00")

        records = decode_imag(make_resource(len(data)), data, bytes(256 * 3), "test")

        self.assertGreaterEqual(len(records), 1)
        self.assertNotEqual(records[0].status, DecodeStatus.OK)
        self.assertIn("imag.truncated_frame_header", diagnostic_codes(records))

    def test_declared_frame_shortfall_marks_decoded_records_partial(self):
        data = make_inline_ctable_imag(2, b"\x01\x00\x01\x00\x01\xc8\x07")
        records = decode_imag(make_resource(len(data)), data, bytes(768), "test")
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0].status, DecodeStatus.PARTIAL)
        self.assertIn("imag.decoded_frame_shortfall", diagnostic_codes(records))

    def test_length_prefixed_frames_use_each_pixmap_and_inherit_palette(self):
        # First compression layout 6x1 represents a 3x2 PixMap; second 4x1
        # represents a 2x2 PixMap. Each has its own width/height/rowBytes.
        first = make_frame(struct.pack("<HHB", 6, 1, 1) + b"\xc0abcdef", 3, 2)
        second = make_frame(struct.pack("<HHB", 4, 1, 1) + b"\xc0wxyz", 2, 2, inline_palette=False)
        data = b"\x00\x02" + first + second
        records = decode_imag(make_resource(len(data)), data, bytes(768), "test")
        self.assertEqual([r.status for r in records], [DecodeStatus.OK, DecodeStatus.OK])
        self.assertEqual([(r.width, r.height) for r in records], [(3, 2), (2, 2)])
        self.assertEqual(records[1].image.tobytes(), b"wxyz")
        self.assertEqual(records[1].image.getpalette(), records[0].image.getpalette())

    def test_sentinel_bytes_in_literal_pixels_are_not_frame_boundaries(self):
        pixels = b"\xff\xff\xff\xff\x00\x00\x00\x00"
        data = make_inline_ctable_imag(1, struct.pack("<HHB", 8, 1, 1) + b"\xc0" + pixels, 8, 1)
        records = decode_imag(make_resource(len(data)), data, bytes(768), "test")
        self.assertEqual(records[0].status, DecodeStatus.OK)
        self.assertEqual(records[0].image.tobytes(), pixels)

    def test_compression_layout_must_match_frame_backing_store(self):
        data = make_inline_ctable_imag(1, b"\x02\x00\x02\x00\x01\xc0\x01\x02\xc0\x03\x04", 4, 4)
        records = decode_imag(make_resource(len(data)), data, bytes(768), "test")
        self.assertIn("imag.backing_size_mismatch", diagnostic_codes(records))
        self.assertEqual(records[0].status, DecodeStatus.PARTIAL)

    def test_opcode_e0_repeats_preceding_row_in_same_frame(self):
        # CODE 20:0x604 subtracts one from the current row, then multiplies
        # by compression width and adds this frame's output base at 0x614.
        frame = struct.pack("<HHB", 2, 3, 1) + b"\xc0\x12\x34\xe0\xe0"
        pixels, _ = decode_frame(frame, 0, 2, 3, b"\x99" * 6)
        self.assertEqual(pixels, b"\x12\x34" * 3)

    def test_opcode_d0_uses_unsigned_absolute_row_number(self):
        # CODE 20:0x568 zero-extends the byte; 0x574 adds the output base.
        rows = b"".join(b"\xc8" + bytes([i]) for i in range(130))
        frame = struct.pack("<HHB", 1, 132, 1) + rows + b"\xd0\x80\xd0\x00"
        pixels, _ = decode_frame(frame, 0, 1, 132, None)
        self.assertEqual(pixels, bytes(range(130)) + b"\x80\x00")

    def test_opcode_d8_uses_little_endian_absolute_row_number(self):
        # CODE 20:0x5b2 reads low byte, 0x5b6 high byte, 0x5ba shifts high.
        rows = b"".join(b"\xc8" + bytes([i % 251]) for i in range(259))
        frame = struct.pack("<HHB", 1, 260, 1) + rows + b"\xd8\x00\x01"
        pixels, _ = decode_frame(frame, 0, 1, 260, None)
        self.assertEqual(pixels[-1], 256 % 251)

    def test_full_backing_store_crops_row_bytes_to_pixmap_bounds(self):
        frame = b"\x04\x00\x02\x00\x01\xc0\x01\x02\x03\x09\xc0\x04\x05\x06\x09"
        data = make_inline_ctable_imag(
            frame_count=1,
            pixel_data=frame,
            width=3,
            height=2,
            row_bytes=4,
        )

        records = decode_imag(make_resource(len(data)), data, bytes(256 * 3), "test")

        self.assertEqual(records[0].width, 3)
        self.assertEqual(records[0].height, 2)
        self.assertEqual(list(records[0].image.tobytes()), [1, 2, 3, 4, 5, 6])

    def test_decode_imag_19000_from_oregon_color_resource(self):
        resources = list(macresources.parse_file(Path("raw/oregon_color.rsrc").read_bytes()))
        resource = next(record for record in resources if record.type == b"Imag" and record.id == 19000)
        data = bytes(resource)
        fallback_palette, fallback_source = fallback_palette_from_resources(resources)
        info = ResourceInfo("oregon_color", "Imag", resource.id, "", len(data))

        records = decode_imag(info, data, fallback_palette, fallback_source)

        self.assertGreaterEqual(len(records), 1)
        self.assertNotEqual(records[0].status, DecodeStatus.FAILED)
        self.assertGreater(records[0].width, 0)
        self.assertGreater(records[0].height, 0)
        self.assertIsNotNone(records[0].image)

    def test_imag_19000_overlay_frames_use_natural_bounds(self):
        resources = list(macresources.parse_file(Path("raw/oregon_color.rsrc").read_bytes()))
        resource = next(record for record in resources if record.type == b"Imag" and record.id == 19000)
        data = bytes(resource)
        fallback_palette, fallback_source = fallback_palette_from_resources(resources)
        info = ResourceInfo("oregon_color", "Imag", resource.id, "", len(data))

        records = decode_imag(info, data, fallback_palette, fallback_source)

        self.assertEqual((records[0].width, records[0].height), (494, 304))
        self.assertEqual((records[1].width, records[1].height), (46, 32))

    def test_case1_decoding_stays_within_declared_frame_for_real_resource(self):
        resources = list(macresources.parse_file(Path("raw/oregon_color.rsrc").read_bytes()))
        resource = next(record for record in resources if record.type == b"Imag" and record.id == 15300)
        data = bytes(resource)
        fallback_palette, fallback_source = fallback_palette_from_resources(resources)
        info = ResourceInfo("oregon_color", "Imag", resource.id, "", len(data))

        records = decode_imag(info, data, fallback_palette, fallback_source)

        self.assertNotIn("imag.frame_boundary_overread", diagnostic_codes([records[0]]))

    def test_real_frames_match_their_own_pixmaps(self):
        resources = list(macresources.parse_file(Path("raw/oregon_color.rsrc").read_bytes()))
        fallback, source = fallback_palette_from_resources(resources)
        expected = {15100: [(262, 77), (786, 14), (786, 6), (67, 25)],
                    15310: [(262, 155), (110, 73), (108, 70), (53, 24)],
                    19200: [(88, 306), (11, 11), (63, 52), (63, 52)]}
        for resource_id, sizes in expected.items():
            resource = next(r for r in resources if r.type == b"Imag" and r.id == resource_id)
            data = bytes(resource)
            records = decode_imag(make_resource(len(data)), data, fallback, source)
            with self.subTest(resource_id=resource_id):
                self.assertEqual([(r.width, r.height) for r in records[:4]], sizes)
                self.assertNotIn("imag.frame_boundary_overread", diagnostic_codes(records))
                self.assertNotIn("imag.backing_size_mismatch", diagnostic_codes(records))
                self.assertEqual(len(records), int.from_bytes(data[:2], "big"))
        # Resource 15310 begins C8 08 E0 E0 E0 E0: five equal compressed
        # rows fill all 262*155 backing bytes with index 08, not one strip.
        resource = next(r for r in resources if r.type == b"Imag" and r.id == 15310)
        data = bytes(resource)
        records = decode_imag(make_resource(len(data)), data, fallback, source)
        self.assertEqual(records[0].image.tobytes(), b"\x08" * (262 * 155))

    def test_all_original_frames_consume_exact_declared_payloads(self):
        resources = list(macresources.parse_file(Path("raw/oregon_color.rsrc").read_bytes()))
        fallback, source = fallback_palette_from_resources(resources)
        for resource in resources:
            if resource.type != b"Imag":
                continue
            data = bytes(resource)
            records = decode_imag(make_resource(len(data)), data, fallback, source)
            self.assertEqual(len(records), int.from_bytes(data[:2], "big"))
            frame_start = 2
            for record in records:
                with self.subTest(resource=resource.id, frame=record.frame_index):
                    frame_end = frame_start + struct.unpack_from(">I", data, frame_start)[0]
                    self.assertEqual(record.byte_ranges["pixels"][1], frame_end)
                    self.assertNotIn("imag.backing_size_mismatch", diagnostic_codes([record]))
                    self.assertNotIn("imag.frame_boundary_overread", diagnostic_codes([record]))
                    frame_start = frame_end

    def test_missing_compressed_rows_cannot_report_success(self):
        frame = struct.pack("<HHB", 1, 2, 1) + b"\xc8\x07"
        data = make_inline_ctable_imag(1, frame, 1, 2)
        records = decode_imag(make_resource(len(data)), data, bytes(768), "test")
        self.assertEqual(records[0].status, DecodeStatus.FAILED)
        self.assertIn("imag.decode_failed", diagnostic_codes(records))

    def test_invalid_declared_length_is_reported(self):
        data = bytearray(make_inline_ctable_imag(1, b"\x01\x00\x01\x00\x01\xc8\x07"))
        struct.pack_into(">I", data, 2, len(data) + 100)
        records = decode_imag(make_resource(len(data)), bytes(data), bytes(768), "test")
        self.assertEqual(records[0].status, DecodeStatus.FAILED)
        self.assertIn("imag.invalid_frame_length", diagnostic_codes(records))


if __name__ == "__main__":
    unittest.main()
