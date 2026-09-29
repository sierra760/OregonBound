from __future__ import annotations

import os
import struct
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

from .models import DecodeDiagnostic, DecodeImage, DecodeStatus, ResourceInfo


PICT_HEADER_LENGTH = 10
PICT_V2_HEADER_LENGTH = 24
PACK_BITS_RECT = 0x0098


def _scan_to_cliprgn(data: bytearray) -> int | None:
    opcode_sizes: dict[int, int] = {
        0x00: 0,
        0x11: 1,
        0x03: 2,
        0x04: 1,
        0x05: 2,
        0x06: 4,
        0x07: 4,
        0x08: 2,
        0x09: 8,
        0x0A: 8,
        0x0B: 4,
        0x0C: 4,
        0x0D: 2,
        0x0E: 4,
        0x0F: 4,
        0x10: 8,
        0x12: 2,
        0x13: 4,
        0x15: 2,
        0x16: 2,
        0x17: 2,
    }
    offset = 10
    limit = min(offset + 256, len(data) - 1)
    while offset < limit:
        opcode = data[offset]
        if opcode == 0x01:
            return offset + 1
        size = opcode_sizes.get(opcode)
        if size is None:
            return None
        offset += 1 + size
    return None


def normalize_pict(data: bytes) -> tuple[bytes, list[DecodeDiagnostic]]:
    if len(data) < PICT_HEADER_LENGTH:
        raise ValueError(f"PICT header requires {PICT_HEADER_LENGTH} bytes; got {len(data)}")

    diagnostics: list[DecodeDiagnostic] = []
    working = bytearray(data)
    top, left, bottom, right = struct.unpack_from(">hhhh", working, 2)
    if top >= 0 and left >= 0:
        return data, diagnostics

    dt = max(0, -top)
    dl = max(0, -left)
    struct.pack_into(">hhhh", working, 2, top + dt, left + dl, bottom + dt, right + dl)
    clip_offset = _scan_to_cliprgn(working)
    if clip_offset is not None and clip_offset + 10 <= len(working):
        rgn_size = struct.unpack_from(">H", working, clip_offset)[0]
        if rgn_size >= 10:
            rect_offset = clip_offset + 2
            ct, cl, cb, cr = struct.unpack_from(">hhhh", working, rect_offset)
            struct.pack_into(">hhhh", working, rect_offset, ct + dt, cl + dl, cb + dt, cr + dl)
    diagnostics.append(DecodeDiagnostic("info", "pict.normalized_frame", "Shifted negative PICT frame to origin"))
    return bytes(working), diagnostics


def _unpack_packbits_row(data: bytes, offset: int, byte_count: int, row_bytes: int) -> tuple[bytes, int]:
    end = offset + byte_count
    row = bytearray()
    cursor = offset
    while cursor < end and len(row) < row_bytes:
        control = data[cursor]
        cursor += 1
        if control <= 127:
            count = control + 1
            row.extend(data[cursor : cursor + count])
            cursor += count
        elif control >= 129:
            count = 257 - control
            if cursor < end:
                row.extend(bytes([data[cursor]]) * count)
            cursor += 1
        else:
            continue
    if len(row) < row_bytes:
        row.extend(bytes(row_bytes - len(row)))
    return bytes(row[:row_bytes]), end


def _decode_packbits_rect(
    data: bytes,
    opcode_offset: int,
    pict_frame: tuple[int, int, int, int],
) -> Image.Image | None:
    cursor = opcode_offset + 2
    if cursor + 46 > len(data):
        return None

    row_bytes_raw = struct.unpack_from(">H", data, cursor)[0]
    row_bytes = row_bytes_raw & 0x3FFF
    top, left, bottom, right = struct.unpack_from(">hhhh", data, cursor + 2)
    pixel_size = struct.unpack_from(">H", data, cursor + 28)[0]
    cmp_count = struct.unpack_from(">H", data, cursor + 30)[0]
    cmp_size = struct.unpack_from(">H", data, cursor + 32)[0]
    cursor += 46

    width = right - left
    height = bottom - top
    if row_bytes <= 0 or width <= 0 or height <= 0:
        return None
    if pixel_size != 8 or cmp_count != 1 or cmp_size != 8:
        return None
    if cursor + 8 > len(data):
        return None

    _seed, _flags, color_table_size = struct.unpack_from(">IHH", data, cursor)
    cursor += 8
    if color_table_size > 255 or cursor + (color_table_size + 1) * 8 > len(data):
        return None

    palette = bytearray(bytes([255, 255, 255]) * 256)
    for _ in range(color_table_size + 1):
        value, red, green, blue = struct.unpack_from(">HHHH", data, cursor)
        cursor += 8
        if value < 256:
            palette[value * 3 : value * 3 + 3] = bytes((red >> 8, green >> 8, blue >> 8))

    if cursor + 18 > len(data):
        return None
    src_top, src_left, src_bottom, src_right = struct.unpack_from(">hhhh", data, cursor)
    cursor += 8
    dst_top, dst_left, dst_bottom, dst_right = struct.unpack_from(">hhhh", data, cursor)
    cursor += 8
    mode = struct.unpack_from(">H", data, cursor)[0]
    cursor += 2

    src_width = src_right - src_left
    src_height = src_bottom - src_top
    if src_width <= 0 or src_height <= 0:
        return None
    if (top, left, bottom, right) != pict_frame:
        return None
    if mode != 0:
        return None
    if (src_top, src_left, src_bottom, src_right) != (top, left, bottom, right):
        return None
    if (dst_top, dst_left, dst_bottom, dst_right) != (top, left, bottom, right):
        return None

    rows = []
    for _ in range(src_height):
        if row_bytes > 250:
            if cursor + 2 > len(data):
                return None
            byte_count = struct.unpack_from(">H", data, cursor)[0]
            cursor += 2
        else:
            if cursor >= len(data):
                return None
            byte_count = data[cursor]
            cursor += 1
        row, cursor = _unpack_packbits_row(data, cursor, byte_count, row_bytes)
        rows.append(row[src_left : src_left + src_width])

    image = Image.new("P", (src_width, src_height))
    image.putpalette(bytes(palette))
    image.putdata(b"".join(rows))
    return image.convert("RGBA")


def _convert_indexed_packbits_pict(data: bytes) -> Image.Image | None:
    if len(data) < PICT_HEADER_LENGTH:
        return None
    pict_frame = struct.unpack_from(">hhhh", data, 2)
    offset = PICT_HEADER_LENGTH
    while offset + 2 <= len(data):
        opcode_offset = offset
        opcode = struct.unpack_from(">H", data, offset)[0]
        offset += 2
        if opcode == PACK_BITS_RECT:
            return _decode_packbits_rect(data, opcode_offset, pict_frame)
        if opcode == 0x0011:
            offset += 2
        elif opcode == 0x0C00:
            offset += PICT_V2_HEADER_LENGTH
        elif opcode == 0x0001:
            if offset + 2 > len(data):
                return None
            region_size = struct.unpack_from(">H", data, offset)[0]
            if region_size < 2:
                return None
            offset += region_size
        elif opcode == 0x00FF:
            return None
        else:
            return None
    return None


def convert_pict(resource: ResourceInfo, data: bytes, temp_dir: Path | None = None) -> DecodeImage:
    diagnostics: list[DecodeDiagnostic] = []
    width = None
    height = None
    tmp_name = None
    png_name = None
    try:
        normalized, diagnostics = normalize_pict(data)
        top, left, bottom, right = struct.unpack_from(">hhhh", normalized, 2)
        width = right - left
        height = bottom - top
        if width <= 0 or height <= 0:
            diagnostics.append(
                DecodeDiagnostic("error", "pict.invalid_dimensions", f"Invalid PICT dimensions: {width}x{height}")
            )
            return DecodeImage(resource, DecodeStatus.FAILED, None, None, None, None, diagnostics=diagnostics)

        image = _convert_indexed_packbits_pict(normalized)
        if image is not None:
            return DecodeImage(
                resource=resource,
                status=DecodeStatus.PARTIAL if any(d.severity == "warning" for d in diagnostics) else DecodeStatus.OK,
                image_path=None,
                width=image.width,
                height=image.height,
                mode="RGBA",
                frame_index=0,
                frame_count=1,
                byte_ranges={"pict": [0, len(data)]},
                diagnostics=diagnostics,
                image=image,
            )

        pict_file_bytes = b"\x00" * 512 + normalized
        with tempfile.NamedTemporaryFile(suffix=".pict", delete=False, dir=temp_dir) as tmp:
            tmp_name = tmp.name
            tmp.write(pict_file_bytes)
        png_name = tmp_name + ".png"
        result = subprocess.run(
            ["sips", "-s", "format", "png", tmp_name, "--out", png_name],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            diagnostics.append(
                DecodeDiagnostic("error", "pict.sips_failed", result.stderr.strip() or result.stdout.strip())
            )
            return DecodeImage(resource, DecodeStatus.FAILED, None, width, height, None, diagnostics=diagnostics)

        image = Image.open(png_name).convert("RGBA")
        image.load()
        return DecodeImage(
            resource=resource,
            status=DecodeStatus.PARTIAL if any(d.severity == "warning" for d in diagnostics) else DecodeStatus.OK,
            image_path=None,
            width=image.width,
            height=image.height,
            mode="RGBA",
            frame_index=0,
            frame_count=1,
            byte_ranges={"pict": [0, len(data)]},
            diagnostics=diagnostics,
            image=image,
        )
    except Exception as exc:
        diagnostics.append(DecodeDiagnostic("error", "pict.decode_failed", str(exc)))
        return DecodeImage(resource, DecodeStatus.FAILED, None, width, height, None, diagnostics=diagnostics)
    finally:
        for path in (tmp_name, png_name):
            if path:
                try:
                    os.unlink(path)
                except OSError:
                    pass
