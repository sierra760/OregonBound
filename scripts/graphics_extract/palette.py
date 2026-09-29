from __future__ import annotations

import struct

PIXMAP_OFFSET_CICN = 0
PIXMAP_OFFSET_IMAG = 6


def parse_pixmap(data: bytes, offset: int = 0) -> dict[str, object]:
    """Parse a QuickDraw PixMap.

    Callers must pass the correct resource-specific offset. cicn PixMaps start
    at PIXMAP_OFFSET_CICN; Oregon Color Imag resources include a 6-byte header
    before the PixMap and should use PIXMAP_OFFSET_IMAG.
    """
    row_bytes_raw = struct.unpack_from(">H", data, offset + 4)[0]
    row_bytes = row_bytes_raw & 0x3FFF
    top, left, bottom, right = struct.unpack_from(">hhhh", data, offset + 6)
    pixel_size = struct.unpack_from(">H", data, offset + 32)[0]
    return {
        "row_bytes": row_bytes,
        "is_pixmap": bool(row_bytes_raw & 0x8000),
        "bounds": (top, left, bottom, right),
        "width": right - left,
        "height": bottom - top,
        "pixel_size": pixel_size,
    }


def parse_color_table(data: bytes, offset: int = 0) -> list[tuple[int, int, int]]:
    header_length = 8
    if len(data) < offset + header_length:
        raise ValueError(
            f"Color table header at offset {offset} requires {header_length} bytes; "
            f"only {max(0, len(data) - offset)} available"
        )

    _seed, _flags, ct_size = struct.unpack_from(">IHH", data, offset)
    expected_length = header_length + (ct_size + 1) * 8
    if len(data) < offset + expected_length:
        raise ValueError(
            f"Color table entries at offset {offset} declare {ct_size + 1} entries "
            f"({expected_length} bytes total); only {max(0, len(data) - offset)} available"
        )

    colors: list[tuple[int, int, int]] = []
    for index in range(ct_size + 1):
        _value, red, green, blue = struct.unpack_from(">HHHH", data, offset + 8 + index * 8)
        colors.append((red >> 8, green >> 8, blue >> 8))
    return colors


def build_palette_bytes(colors: list[tuple[int, int, int]]) -> bytes:
    palette = bytearray(256 * 3)
    for index, (red, green, blue) in enumerate(colors[:256]):
        palette[index * 3] = red
        palette[index * 3 + 1] = green
        palette[index * 3 + 2] = blue
    return bytes(palette)
