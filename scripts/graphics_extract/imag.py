from __future__ import annotations

import struct

from PIL import Image

from .models import DecodeDiagnostic, DecodeImage, DecodeStatus, PaletteInfo, ResourceInfo
from .imag_codec import (
    DATA_OFFSET,
    build_palette_from_clut,
    build_palette_from_ctable,
    decode_frame,
    decode_bitmap_columns,
    expand_bitmap,
    detect_inline_ctable,
    parse_pixmap,
)


def _crop_backing_store_to_bounds(
    pixels: bytes, width: int, height: int, row_bytes: int,
) -> bytes:
    store_size = row_bytes * height
    store = (pixels + bytes(store_size))[:store_size]
    return b"".join(store[row * row_bytes:row * row_bytes + width] for row in range(height))


def _status_for_diagnostics(diagnostics: list[DecodeDiagnostic]) -> DecodeStatus:
    if any(diagnostic.severity in {"warning", "error"} for diagnostic in diagnostics):
        return DecodeStatus.PARTIAL
    return DecodeStatus.OK


def decode_imag(
    resource: ResourceInfo,
    data: bytes,
    fallback_palette: bytes,
    fallback_source: str,
) -> list[DecodeImage]:
    """Decode the length-prefixed frames used by the original Display loader.

    CODE 5:0x5b8c skips the resource's two-byte count; 0x5ba2 advances by
    each frame's big-endian long length. CODE 5:0x5d3c–0x5d62 skips that
    length and copies a fresh 50-byte PixMap. The apparent eight-byte
    "sentinel" is really pmTable=-1 followed by pmReserved=0 in that PixMap.
    Compression dimensions describe only the linear backing-store layout.
    CD bitmap frames instead carry a 14-byte BitMap and column commands.
    """
    records: list[DecodeImage] = []
    pending: list[DecodeDiagnostic] = []
    frame_count = 0
    try:
        frame_count = struct.unpack_from(">H", data)[0]
        if frame_count == 0:
            raise ValueError("Imag declares no frames")
        frame_start = 2
        palette = fallback_palette
        palette_info = PaletteInfo(source=fallback_source, entry_count=256)
        inherited_palette = False
        for frame_index in range(frame_count):
            if frame_start + 18 > len(data):
                pending.append(DecodeDiagnostic(
                    "error", "imag.truncated_frame_header",
                    f"Frame {frame_index} has no complete length and bitmap header at {frame_start}",
                ))
                break
            frame_length = struct.unpack_from(">I", data, frame_start)[0]
            if frame_length < 18 or frame_start + frame_length > len(data):
                pending.append(DecodeDiagnostic(
                    "error", "imag.invalid_frame_length",
                    f"Frame {frame_index} length {frame_length} at {frame_start} exceeds its resource or header",
                ))
                break
            frame_end = frame_start + frame_length
            row_flags = struct.unpack_from(">H", data, frame_start + 8)[0]
            if not row_flags & 0x8000:
                row_bytes = row_flags & 0x3fff
                top, left, bottom, right = struct.unpack_from(">hhhh", data, frame_start + 10)
                width, height = right - left, bottom - top
                if (width <= 0 or height <= 0 or width > row_bytes * 8
                        or width * height > 64 * 1024 * 1024):
                    raise ValueError(f"Invalid bitmap dimensions in frame {frame_index}")
                pixel_start = frame_start + 18
                packed, end_offset = decode_bitmap_columns(data[:frame_end], pixel_start, row_bytes, height)
                image = Image.frombytes("L", (width, height), expand_bitmap(packed, width, height, row_bytes))
                records.append(DecodeImage(
                    resource=resource, status=DecodeStatus.OK, image_path=None,
                    width=width, height=height, mode="L", frame_index=frame_index,
                    frame_count=frame_count, byte_ranges={"pixels": [pixel_start, end_offset]}, image=image,
                ))
                frame_start = frame_end
                continue
            if frame_length < 54:
                raise ValueError(f"Truncated PixMap in frame {frame_index}")
            pixmap = parse_pixmap(data, frame_start + 4)
            width, height, row_bytes = (int(pixmap[key]) for key in ("width", "height", "row_bytes"))
            if (not pixmap["is_pixmap"] or pixmap["pixel_size"] != 8
                    or width <= 0 or height <= 0 or row_bytes < width):
                raise ValueError(f"Invalid 8-bit PixMap in frame {frame_index}: {pixmap}")
            pixel_start = frame_start + 54
            frame_diagnostics: list[DecodeDiagnostic] = []
            # CODE 5:0x5d8c–0x5d94: pmTable==0 means an inline color table.
            # Nonzero pointers inherit the last inline palette (0x5b8e–0x5bb2).
            table_pointer = struct.unpack_from(">I", data, frame_start + 46)[0]
            if table_pointer == 0:
                if pixel_start + 8 > frame_end:
                    raise ValueError(f"Truncated color table in frame {frame_index}")
                count = struct.unpack_from(">H", data, pixel_start + 6)[0] + 1
                table_size = 8 + count * 8
                if count > 256 or pixel_start + table_size > frame_end:
                    raise ValueError(f"Invalid color table size in frame {frame_index}")
                palette = build_palette_from_ctable(data, pixel_start)
                palette_info = PaletteInfo(source="inline_ctable", entry_count=count)
                inherited_palette = True
                pixel_start += table_size
            elif not inherited_palette:
                frame_diagnostics.append(DecodeDiagnostic(
                    "warning", "imag.palette_fallback", f"Using {fallback_source} palette",
                ))
            if pixel_start + 5 > frame_end:
                pending.append(DecodeDiagnostic(
                    "error", "imag.truncated_frame_header", f"Frame {frame_index} has no compression header",
                ))
                break
            comp_width, comp_height = struct.unpack_from("<HH", data, pixel_start)
            if comp_width * comp_height != row_bytes * height:
                frame_diagnostics.append(DecodeDiagnostic(
                    "error", "imag.backing_size_mismatch",
                    f"Compression layout {comp_width}x{comp_height} does not match PixMap backing store {row_bytes}x{height}",
                ))
            frame_pixels, end_offset = decode_frame(data[:frame_end], pixel_start, width, height, None, align_end=False)
            if end_offset > frame_end:
                frame_diagnostics.append(DecodeDiagnostic(
                    "warning", "imag.frame_boundary_overread",
                    f"Frame ended at {end_offset}, past declared boundary {frame_end}",
                ))
            image = Image.frombytes("P", (width, height),
                _crop_backing_store_to_bounds(frame_pixels, width, height, row_bytes))
            image.putpalette(palette)
            records.append(DecodeImage(
                resource=resource, status=_status_for_diagnostics(frame_diagnostics),
                image_path=None, width=width, height=height, mode="P",
                frame_index=frame_index, frame_count=frame_count, palette=palette_info,
                byte_ranges={"pixels": [pixel_start, min(end_offset, frame_end)]},
                diagnostics=frame_diagnostics, image=image,
            ))
            frame_start = frame_end
    except Exception as exc:
        pending.append(DecodeDiagnostic("error", "imag.decode_failed", str(exc)))
    if len(records) < frame_count:
        pending.append(DecodeDiagnostic(
            "warning", "imag.decoded_frame_shortfall",
            f"Decoded {len(records)} frames for declared count {frame_count}",
        ))
    if not records:
        return [DecodeImage(
            resource=resource, status=DecodeStatus.FAILED, image_path=None,
            width=None, height=None, mode=None,
            diagnostics=pending + [DecodeDiagnostic("error", "imag.no_frames", "No frames decoded")],
        )]
    for record in records:
        record.diagnostics.extend(pending)
        record.status = _status_for_diagnostics(record.diagnostics)
    return records


def fallback_palette_from_resources(resources: list[object]) -> tuple[bytes, str]:
    imag_19000 = next(
        (bytes(record) for record in resources if record.type == b"Imag" and record.id == 19000),
        None,
    )
    if imag_19000 is not None:
        has_ctable, _ct_byte_size = detect_inline_ctable(imag_19000)
        if has_ctable:
            return build_palette_from_ctable(imag_19000, DATA_OFFSET), "imag_19000_inline_ctable"
    clut_1008 = next(
        (bytes(record) for record in resources if record.type == b"clut" and record.id == 1008),
        None,
    )
    if clut_1008 is not None:
        return build_palette_from_clut(clut_1008), "clut_1008"
    return bytes(256 * 3), "zero_palette"
