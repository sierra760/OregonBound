#!/usr/bin/env python3
"""Extract PICT resources from Oregon Trail and Oregon Color resource forks to PNG files.

Conversion strategy: prepend the mandatory 512-byte zero PICT file header, then
delegate to macOS `sips` for QuickDraw rendering.  sips supports both PICT v1
(text-only) and PICT v2 (bitmap) formats natively.

Some PICTs store a picFrame with negative top/left (e.g., (-1,-1,…)) which causes
sips to fail.  We normalize the picFrame to start at (0,0) and shift the ClipRgn
region rect by the same delta before passing to sips.

Target resources:
  - PICT 10256 from Oregon Color (color version of B&W PICT 256)
  - PICT 2050, 2051, 2052, 2070 from Oregon Trail (introduction/help text panels)
"""

import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
import macresources


# ---------------------------------------------------------------------------
# PICT normalisation
# ---------------------------------------------------------------------------

def _scan_to_cliprgn(data: bytearray) -> int | None:
    """Return the byte offset of the ClipRgn opcode (0x01) data start.

    Scans PICT v1 opcodes starting at offset 10.  Returns the offset of the
    2-byte region size field that immediately follows the 0x01 opcode byte,
    or None if not found within a reasonable scan window.
    """
    OPCODE_SIZES: dict[int, int] = {
        0x00: 0,   # NOP
        0x11: 1,   # Version (1-byte version number follows)
        0x03: 2,   # TxFont (2-byte font ID)
        0x04: 1,   # TxFace (1-byte face)
        0x05: 2,   # TxMode (2-byte mode)
        0x06: 4,   # SpExtra (Fixed = 4 bytes)
        0x07: 4,   # PnSize (Point = 4 bytes)
        0x08: 2,   # PnMode (2 bytes)
        0x09: 8,   # PnPat (8-byte pattern)
        0x0A: 8,   # FillPat (8-byte pattern)
        0x0B: 4,   # OvSize (Point = 4 bytes)
        0x0C: 4,   # Origin (dh, dv each 2 bytes)
        0x0D: 2,   # TxSize (2-byte size)
        0x0E: 4,   # FgColor (long)
        0x0F: 4,   # BkColor (long)
        0x10: 8,   # TxRatio (2 Points = 8 bytes)
        0x12: 2,   # BkPixPat / DefHilite placeholder
        0x13: 4,   # PnLoc (Point)
        0x15: 2,   # PenTheme
        0x16: 2,   # PenMode16
        0x17: 2,   # TxFont16
    }

    offset = 10
    limit = min(offset + 256, len(data) - 1)
    while offset < limit:
        opcode = data[offset]
        if opcode == 0x01:
            return offset + 1          # caller reads region size from here
        size = OPCODE_SIZES.get(opcode)
        if size is None:
            return None                # unknown opcode; stop scanning
        offset += 1 + size
    return None


def normalize_pict(data: bytes) -> bytes:
    """Return PICT data with picFrame normalised so top >= 0 and left >= 0.

    When picFrame has negative coordinates sips fails with Error 13.
    We shift picFrame to (0,0) and apply the same delta to the ClipRgn rect.
    Text-draw coordinates live in the picture's own coordinate space and are
    unaffected by the frame shift.
    """
    d = bytearray(data)
    top, left, bottom, right = struct.unpack_from('>hhhh', d, 2)

    if top >= 0 and left >= 0:
        return data                    # no-op

    dt = max(0, -top)
    dl = max(0, -left)

    # Shift picFrame
    struct.pack_into('>hhhh', d, 2,
                     top + dt, left + dl, bottom + dt, right + dl)

    # Shift ClipRgn rect if found
    clip_offset = _scan_to_cliprgn(d)
    if clip_offset is not None:
        rgn_size = struct.unpack_from('>H', d, clip_offset)[0]
        if rgn_size >= 10:             # sanity: size includes itself + 8-byte rect
            rect_off = clip_offset + 2
            ct, cl, cb, cr = struct.unpack_from('>hhhh', d, rect_off)
            struct.pack_into('>hhhh', d, rect_off,
                             ct + dt, cl + dl, cb + dt, cr + dl)

    return bytes(d)


# ---------------------------------------------------------------------------
# PICT → PNG conversion
# ---------------------------------------------------------------------------

def convert_pict_to_png(pict_resource_data: bytes, out_path: Path) -> bool:
    """Write a PNG from a PICT resource using macOS sips.

    Returns True on success, False on failure.
    """
    normalised = normalize_pict(pict_resource_data)
    # PICT *files* require a 512-byte zero-filled header before the PICT data.
    pict_file_bytes = b'\x00' * 512 + normalised

    with tempfile.NamedTemporaryFile(suffix='.pict', delete=False) as tf:
        tmp_path = tf.name
        tf.write(pict_file_bytes)

    try:
        result = subprocess.run(
            ['sips', '-s', 'format', 'png', tmp_path, '--out', str(out_path)],
            capture_output=True,
            text=True,
        )
        return result.returncode == 0 and out_path.exists() and out_path.stat().st_size > 0
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    root = Path(__file__).resolve().parent.parent
    trail_rsrc = root / 'raw' / 'oregon_trail.rsrc'
    color_rsrc = root / 'raw' / 'oregon_color.rsrc'
    out_dir = root / 'assets' / 'images' / 'pict'
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f'Reading {trail_rsrc}')
    with open(trail_rsrc, 'rb') as f:
        trail_raw = f.read()

    print(f'Reading {color_rsrc}')
    with open(color_rsrc, 'rb') as f:
        color_raw = f.read()

    trail_res = macresources.parse_file(trail_raw)
    color_res = macresources.parse_file(color_raw)

    # (resource_list, pict_id, source_label)
    targets = [
        (color_res,  10256, 'oregon_color'),
        (trail_res,  2050,  'oregon_trail'),
        (trail_res,  2051,  'oregon_trail'),
        (trail_res,  2052,  'oregon_trail'),
        (trail_res,  2070,  'oregon_trail'),
    ]

    success = 0
    for res_list, rid, source in targets:
        r = next(
            (r for r in res_list if r.type == b'PICT' and r.id == rid),
            None,
        )
        if r is None:
            print(f'  pict_{rid}: NOT FOUND in {source}', file=sys.stderr)
            continue

        out_path = out_dir / f'pict_{rid}.png'
        pict_bytes = bytes(r)
        frame = struct.unpack_from('>hhhh', pict_bytes, 2)
        print(f'  Converting pict_{rid} ({len(pict_bytes)} bytes)'
              f' frame={frame} source={source}')

        if convert_pict_to_png(pict_bytes, out_path):
            size_bytes = out_path.stat().st_size
            print(f'    -> pict_{rid}.png  {size_bytes} bytes  OK')
            success += 1
        else:
            print(f'    -> pict_{rid}: sips conversion FAILED', file=sys.stderr)

    print(f'\nDone: {success}/5 PICTs extracted to {out_dir}')
    if success < 5:
        sys.exit(1)


if __name__ == '__main__':
    main()
