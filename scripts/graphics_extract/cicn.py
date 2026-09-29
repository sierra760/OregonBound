from __future__ import annotations

import struct

from PIL import Image

from .models import DecodeDiagnostic, DecodeImage, DecodeStatus, PaletteInfo, ResourceInfo
from .palette import parse_pixmap


def _extract_bits(byte_val: int, col: int, pixel_size: int) -> int:
    if pixel_size == 1:
        return (byte_val >> (7 - (col % 8))) & 0x01
    if pixel_size == 2:
        return (byte_val >> (6 - (col % 4) * 2)) & 0x03
    if pixel_size == 4:
        return (byte_val >> (4 - (col % 2) * 4)) & 0x0F
    if pixel_size == 8:
        return byte_val & 0xFF
    raise ValueError(f"Unsupported pixel_size: {pixel_size}")


def _require_available(data: bytes, offset: int, length: int, label: str) -> None:
    if length < 0:
        raise ValueError(f"{label} length cannot be negative")
    if len(data) < offset + length:
        raise ValueError(
            f"{label} at offset {offset} requires {length} bytes; "
            f"only {max(0, len(data) - offset)} available"
        )


def _parse_color_table_by_value(data: bytes, offset: int) -> tuple[dict[int, tuple[int, int, int]], int]:
    header_length = 8
    _require_available(data, offset, header_length, "cicn color table header")

    _seed, _flags, ct_size = struct.unpack_from(">IHH", data, offset)
    entry_count = ct_size + 1
    table_length = header_length + entry_count * 8
    _require_available(data, offset, table_length, "cicn color table")

    colors: dict[int, tuple[int, int, int]] = {}
    for index in range(entry_count):
        value, red, green, blue = struct.unpack_from(">HHHH", data, offset + header_length + index * 8)
        colors[value] = (red >> 8, green >> 8, blue >> 8)
    return colors, entry_count


def decode_cicn(resource: ResourceInfo, data: bytes) -> list[DecodeImage]:
    diagnostics: list[DecodeDiagnostic] = []
    try:
        _require_available(data, 0, 50, "cicn PixMap")
        pixmap = parse_pixmap(data, 0)
        width = int(pixmap["width"])
        height = int(pixmap["height"])
        row_bytes = int(pixmap["row_bytes"])
        pixel_size = int(pixmap["pixel_size"])

        if width <= 0 or height <= 0:
            raise ValueError(f"Invalid cicn dimensions: {width}x{height}")

        offset = 50
        _require_available(data, offset, 14, "cicn mask bitmap")
        mask_row_bytes = struct.unpack_from(">H", data, offset + 4)[0]
        mask_top, mask_left, mask_bottom, mask_right = struct.unpack_from(">hhhh", data, offset + 6)
        mask_height = mask_bottom - mask_top
        offset += 14

        _require_available(data, offset, 14, "cicn black-and-white bitmap")
        bw_row_bytes = struct.unpack_from(">H", data, offset + 4)[0]
        bw_top, _bw_left, bw_bottom, _bw_right = struct.unpack_from(">hhhh", data, offset + 6)
        bw_height = bw_bottom - bw_top
        offset += 14

        _require_available(data, offset, 4, "cicn icon data handle")
        offset += 4

        mask_data_start = offset
        mask_data_length = mask_row_bytes * mask_height
        _require_available(data, offset, mask_data_length, "cicn mask data")
        mask_data = data[offset : offset + mask_data_length]
        offset += mask_data_length

        bw_data_length = bw_row_bytes * bw_height
        _require_available(data, offset, bw_data_length, "cicn black-and-white data")
        offset += bw_data_length

        color_table_start = offset
        colors_by_value, color_spec_count = _parse_color_table_by_value(data, offset)
        color_table_length = 8 + color_spec_count * 8
        offset += color_table_length

        pixel_data_start = offset
        pixel_data_length = row_bytes * height
        _require_available(data, offset, pixel_data_length, "cicn pixel data")
        pixel_data = data[offset : offset + pixel_data_length]

        pixels_rgb: list[tuple[int, int, int]] = []
        pixels_per_byte = 8 // pixel_size
        for row in range(height):
            row_start = row * row_bytes
            for col in range(width):
                byte_idx = col // pixels_per_byte
                pixel_val = _extract_bits(pixel_data[row_start + byte_idx], col, pixel_size)
                pixels_rgb.append(colors_by_value.get(pixel_val, (0, 0, 0)))

        alpha_values: list[int] = []
        for row in range(height):
            row_start = row * mask_row_bytes
            for col in range(width):
                byte_idx = col // 8
                bit = (mask_data[row_start + byte_idx] >> (7 - (col % 8))) & 1
                alpha_values.append(255 if bit else 0)

        image = Image.new("RGBA", (width, height))
        image.putdata([(*rgb, alpha) for rgb, alpha in zip(pixels_rgb, alpha_values)])

        if mask_left != 0 or mask_right - mask_left != width:
            diagnostics.append(
                DecodeDiagnostic("warning", "cicn.mask_bounds", "Mask bounds differ from PixMap width")
            )

        return [
            DecodeImage(
                resource=resource,
                status=DecodeStatus.PARTIAL if diagnostics else DecodeStatus.OK,
                image_path=None,
                width=width,
                height=height,
                mode="RGBA",
                frame_index=0,
                frame_count=1,
                palette=PaletteInfo(source="cicn_ctable", entry_count=color_spec_count),
                byte_ranges={
                    "mask": [mask_data_start, mask_data_start + len(mask_data)],
                    "color_table": [color_table_start, color_table_start + color_table_length],
                    "pixels": [pixel_data_start, pixel_data_start + len(pixel_data)],
                },
                diagnostics=diagnostics,
                image=image,
            )
        ]
    except Exception as exc:
        return [
            DecodeImage(
                resource=resource,
                status=DecodeStatus.FAILED,
                image_path=None,
                width=None,
                height=None,
                mode=None,
                diagnostics=[DecodeDiagnostic("error", "cicn.decode_failed", str(exc))],
            )
        ]
