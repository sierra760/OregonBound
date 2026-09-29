#!/usr/bin/env python3
"""Extract cicn (color icon) resources from Oregon Color resource fork to PNG files.

cicn binary layout (Mac Inside Macintosh, Volume V, chapter 7):
  - PixMap record (50 bytes, incl. 4-byte baseAddr placeholder at offset 0)
  - Mask BitMap record (14 bytes: baseAddr 4, rowBytes 2, bounds 8)
  - B&W icon BitMap record (14 bytes)
  - iconData Handle placeholder (4 bytes, always nil)
  - Mask bitmap data  (mask_rowBytes * height bytes)
  - B&W icon bitmap data (bw_rowBytes * height bytes)
  - ColorTable (seed 4, flags 2, ctSize 2, then (ctSize+1) x 8-byte ColorSpec entries)
  - Pixel data (row_bytes * height bytes, indexed color, MSB-first packed)
"""

import struct
import sys
from pathlib import Path
import macresources
from PIL import Image


def _extract_bits(byte_val: int, col: int, pixel_size: int) -> int:
    """Extract a pixel value from a byte given column index and bit depth."""
    if pixel_size == 1:
        shift = 7 - (col % 8)
        return (byte_val >> shift) & 0x01
    elif pixel_size == 2:
        shift = 6 - (col % 4) * 2
        return (byte_val >> shift) & 0x03
    elif pixel_size == 4:
        shift = 4 - (col % 2) * 4
        return (byte_val >> shift) & 0x0F
    elif pixel_size == 8:
        return byte_val & 0xFF
    else:
        raise ValueError(f"Unsupported pixel_size: {pixel_size}")


def parse_cicn(data: bytes) -> Image.Image:
    """Parse a cicn resource binary and return a Pillow RGBA image."""
    # --- PixMap record (50 bytes) ---
    # offset 0: baseAddr placeholder (4 bytes, unused)
    row_bytes = struct.unpack_from('>H', data, 4)[0] & 0x7FFF  # strip high bit
    bounds = struct.unpack_from('>hhhh', data, 6)              # top, left, bottom, right
    # offsets 14–29: version, packType, packSize, hRes, vRes (all not needed for decode)
    pixel_size = struct.unpack_from('>H', data, 32)[0]         # bits per pixel

    top, left, bottom, right = bounds
    width = right - left
    height = bottom - top
    offset = 50  # end of PixMap

    # --- Mask BitMap (14 bytes) ---
    mask_row_bytes = struct.unpack_from('>H', data, offset + 4)[0]
    mask_bounds = struct.unpack_from('>hhhh', data, offset + 6)
    mask_h = mask_bounds[2] - mask_bounds[0]
    offset += 14

    # --- B&W icon BitMap (14 bytes) ---
    bw_row_bytes = struct.unpack_from('>H', data, offset + 4)[0]
    bw_bounds = struct.unpack_from('>hhhh', data, offset + 6)
    bw_h = bw_bounds[2] - bw_bounds[0]
    offset += 14

    # --- iconData Handle placeholder (4 bytes) ---
    offset += 4

    # --- Mask bitmap data ---
    mask_data = data[offset: offset + mask_row_bytes * mask_h]
    offset += mask_row_bytes * mask_h

    # --- B&W icon data (skip, not used for color rendering) ---
    offset += bw_row_bytes * bw_h

    # --- ColorTable ---
    _ct_seed, _ct_flags, ct_size = struct.unpack_from('>IHH', data, offset)
    offset += 8
    ct_entries = ct_size + 1

    # Build palette: pixel_value -> (R, G, B) with 8-bit channels
    palette: dict[int, tuple[int, int, int]] = {}
    for _ in range(ct_entries):
        val, r16, g16, b16 = struct.unpack_from('>HHHH', data, offset)
        offset += 8
        palette[val] = (r16 >> 8, g16 >> 8, b16 >> 8)

    # --- Pixel data ---
    pixel_data = data[offset: offset + row_bytes * height]

    # Decode indexed pixel values to (R, G, B) tuples
    pixels_rgb: list[tuple[int, int, int]] = []
    pixels_per_byte = 8 // pixel_size
    for row in range(height):
        row_start = row * row_bytes
        for col in range(width):
            byte_idx = col // pixels_per_byte
            pixel_val = _extract_bits(pixel_data[row_start + byte_idx], col, pixel_size)
            color = palette.get(pixel_val, (0, 0, 0))
            pixels_rgb.append(color)

    # Decode mask bitmap (1-bit, MSB-first; 1 = opaque, 0 = transparent)
    mask_pixels: list[int] = []
    for row in range(height):
        row_start = row * mask_row_bytes
        for col in range(width):
            byte_idx = col // 8
            bit = (mask_data[row_start + byte_idx] >> (7 - (col % 8))) & 1
            mask_pixels.append(255 if bit else 0)

    # Compose RGBA image
    img = Image.new('RGBA', (width, height))
    img.putdata([(*rgb, a) for rgb, a in zip(pixels_rgb, mask_pixels)])
    return img


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    rsrc_path = root / 'raw' / 'oregon_color.rsrc'
    out_dir = root / 'assets' / 'images' / 'cicn'
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f'Reading {rsrc_path}')
    with open(rsrc_path, 'rb') as f:
        raw = f.read()

    resources = macresources.parse_file(raw)
    cicn_list = sorted(
        [r for r in resources if r.type == b'cicn'],
        key=lambda r: r.id,
    )

    print(f'Found {len(cicn_list)} cicn resources')
    errors = 0
    for r in cicn_list:
        out_path = out_dir / f'cicn_{r.id}.png'
        try:
            img = parse_cicn(bytes(r))
            img.save(out_path)
            print(f'  cicn_{r.id}.png  {img.size[0]}x{img.size[1]}  '
                  f'{img.size[0] * img.size[1]} px')
        except Exception as exc:
            print(f'  cicn_{r.id}: ERROR: {exc}', file=sys.stderr)
            errors += 1

    print(f'Done: {len(cicn_list) - errors}/{len(cicn_list)} written to {out_dir}')
    if errors:
        sys.exit(1)


if __name__ == '__main__':
    main()
