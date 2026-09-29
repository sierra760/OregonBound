#!/usr/bin/env python3
"""Extract MECC Imag resources from Oregon Color resource fork to PNG files.

Imag resource layout:
  [0-5]   6-byte MECC header: h1 (frame_count BE u16), h2 (flags), h3 (data hint)
  [6-55]  50-byte QuickDraw PixMap: bounds, rowBytes (stride), pixelSize, etc.
  [56+]   Optional inline CTable when h2 bit indicates it (ctFlags==0x8000)
  [pixel_start+]  Frames back-to-back; each frame:
    [+0..+1]  compression width  (little-endian u16)
    [+2..+3]  compression height (little-endian u16)
    [+4]      unknown byte (always 0x01)
    [+5+]     row opcodes decoded by FUN_00000002

Row-opcode format (reverse-engineered from CODE_20 FUN_00000002):
  opcode byte → case = bits[7:6], sub = bits[5:3], low = bits[2:0]

  case 3 (11xxxxxx):
    sub=0  literal row: copy `width` bytes from stream
    sub=1  solid fill:  fill row with 1 byte from stream
    sub=2  copy row by 1-byte signed delta from current row index
    sub=3  copy row by 2-byte signed delta (big-endian)
    sub=4  copy same row from previous frame (no stream bytes)
    sub=5  compressed row: low=7 → FUN_00000aba (multi-byte pattern repeat, 8-bit out);
                           low=1..6 → A5+0x132 MECC_RLE (single-byte run-length,
                                      comp_w bytes written directly as 8-bit indices)
    sub=6  palette setup for ivar5 indirection table (no row increment)
             low=0: inline palette data
             low=1: reference prior row's palette (1-byte back-delta)
             low=2: reference prior row's palette (2-byte form)

  case 2 (10xxxxxx):
    Decompress or read packed bits → expand to 8-bit via bit-depth = sub → remap via ivar5
    low=7 → FUN_00000aba to temp buf; low=0 → direct from stream; low=1..6 → MECC_RLE

  cases 0, 1 (00/01xxxxxx):
    Complex multi-plane operations using FUN_00000896 (look-up table based).
    Partially decoded where possible; otherwise the frame is skipped with a warning.

A5+0x132  MECC_RLE decompressor (used for low=1..6 in ALL cases):
  ctrl < 0x80: run of (ctrl+1) copies of next single byte.
  ctrl >= 0x80: literal copy of (ctrl-0x7f) bytes.
  This is "inverted PackBits" (PackBits has ctrl<0x80=literal, ctrl>0x80=run).

FUN_00000aba decompressor (CODE_20 FUN_00000aba, used for low=7 only):
  Type A (ctrl < 0x80): [ctrl, pattern_len, pattern_bytes…]
    Emit (ctrl+1) repetitions of the pattern_len-byte pattern.
  Type B (ctrl >= 0x80): [ctrl, literal_bytes…]
    Emit (ctrl − 0x7f) literal bytes verbatim.
  Returns bytes_consumed (uVar4 in original).

Inter-frame postamble:
  Each frame is followed by a per-frame postamble whose content is not needed
  for rendering.  The postamble always ends with the 8-byte sentinel
  0xFF 0xFF 0xFF 0xFF 0x00 0x00 0x00 0x00 immediately before the next frame.

Palette:
  Inline CTable when present (ctFlags==0x8000 at offset 60).
  Otherwise falls back to the 256-entry CTable found inside imag_19000,
  and if that is absent, to standalone clut resource 1008.
"""

import struct
import sys
from pathlib import Path

import macresources
from PIL import Image


HEADER_SIZE   = 6    # MECC 6-byte resource header
PIXMAP_SIZE   = 50   # QuickDraw PixMap struct
PIXMAP_OFFSET = HEADER_SIZE
DATA_OFFSET   = HEADER_SIZE + PIXMAP_SIZE   # = 56


# ---------------------------------------------------------------------------
# PixMap / CTable helpers (unchanged from previous version)
# ---------------------------------------------------------------------------

def parse_pixmap(data: bytes) -> dict:
    """Parse QuickDraw PixMap at PIXMAP_OFFSET."""
    off = PIXMAP_OFFSET
    row_bytes_raw = struct.unpack_from(">H", data, off + 4)[0]
    is_pixmap = bool(row_bytes_raw & 0x8000)
    row_bytes  = row_bytes_raw & 0x3FFF
    top, left, bottom, right = struct.unpack_from(">hhhh", data, off + 6)
    pixel_size = struct.unpack_from(">H", data, off + 32)[0]
    return {
        "row_bytes":  row_bytes,
        "is_pixmap":  is_pixmap,
        "bounds":     (top, left, bottom, right),
        "width":      right - left,
        "height":     bottom - top,
        "pixel_size": pixel_size,
    }


def detect_inline_ctable(data: bytes) -> tuple[bool, int]:
    """Return (has_ctable, ct_byte_size) for the CTable at DATA_OFFSET."""
    if len(data) < DATA_OFFSET + 8:
        return False, 0
    ct_flags     = struct.unpack_from(">H", data, DATA_OFFSET + 4)[0]
    ct_size_field= struct.unpack_from(">H", data, DATA_OFFSET + 6)[0]
    n = ct_size_field + 1
    ct_byte_size = 8 + n * 8
    if ct_flags == 0x8000 and n <= 256 and len(data) >= DATA_OFFSET + ct_byte_size:
        return True, ct_byte_size
    return False, 0


def build_palette_from_ctable(data: bytes, offset: int) -> bytes:
    """Build 256-entry RGB palette bytes from Mac CTable at `offset`."""
    _seed, _flags, ct_size = struct.unpack_from(">IHH", data, offset)
    n = ct_size + 1
    pal = bytearray(256 * 3)
    for i in range(min(n, 256)):
        _, r, g, b = struct.unpack_from(">HHHH", data, offset + 8 + i * 8)
        pal[i * 3]     = r >> 8
        pal[i * 3 + 1] = g >> 8
        pal[i * 3 + 2] = b >> 8
    return bytes(pal)


def build_palette_from_clut(clut_data: bytes) -> bytes:
    """Build 256-entry RGB palette bytes from standalone 'clut' resource."""
    _seed, _flags, ct_size = struct.unpack_from(">IHH", clut_data, 0)
    n = ct_size + 1
    pal = bytearray(256 * 3)
    for i in range(min(n, 256)):
        _, r, g, b = struct.unpack_from(">HHHH", clut_data, 8 + i * 8)
        pal[i * 3]     = r >> 8
        pal[i * 3 + 1] = g >> 8
        pal[i * 3 + 2] = b >> 8
    return bytes(pal)


# ---------------------------------------------------------------------------
# MECC_RLE  — A5+0x132 (used for low=1..6 paths in all cases)
# ---------------------------------------------------------------------------

def mecc_rle(data: bytes, start: int, target: int) -> tuple[bytes, int]:
    """MECC RLE decompressor (A5+0x132 function pointer).

    ctrl < 0x80  → run of (ctrl+1) copies of the SINGLE next byte.
    ctrl >= 0x80 → literal copy of (ctrl-0x7f) bytes.

    This is "inverted PackBits": ctrl<0x80 = run (not literal).

    Returns (decoded_bytes, bytes_consumed_from_data_starting_at_start).
    """
    result = bytearray()
    i = start
    end = len(data)
    while len(result) < target and i < end:
        ctrl = data[i]
        if ctrl < 0x80:
            # Run of (ctrl+1) copies of next single byte
            reps = ctrl + 1
            if i + 1 < end:
                val = data[i + 1]
                take = min(reps, target - len(result))
                result.extend(bytes([val]) * take)
            i += 2   # always consume ctrl+val regardless of take
        else:
            # Literal copy of (ctrl-0x7f) bytes
            n = ctrl - 0x7f
            take = min(n, target - len(result))
            result.extend(data[i + 1 : i + 1 + take])
            i += 1 + n   # always consume ctrl + all n bytes
    return bytes(result), i - start


# ---------------------------------------------------------------------------
# FUN_00000aba  — MECC custom decompressor (used for low=7 paths only)
# ---------------------------------------------------------------------------

def fun_00000aba(data: bytes, start: int, target: int) -> tuple[bytes, int]:
    """MECC custom decompressor (CODE_20 FUN_00000aba).

    Type A (ctrl < 0x80):
      [ctrl][pattern_len][pattern_bytes x pattern_len]
      → emit (ctrl+1) repetitions of the pattern.

    Type B (ctrl >= 0x80):
      [ctrl][literal_bytes x (ctrl-0x7f)]
      → emit literal bytes verbatim.

    Returns (decoded_bytes, bytes_consumed_from_data_starting_at_start).
    """
    result = bytearray()
    i = start
    end = len(data)
    while len(result) < target and i < end:
        ctrl = data[i]
        if ctrl < 0x80:
            # Type A: repeat pattern
            i += 1
            if i >= end:
                break
            pattern_len = data[i]
            pattern = data[i + 1 : i + 1 + pattern_len]
            reps = ctrl + 1
            for _ in range(reps):
                take = min(pattern_len, target - len(result))
                result.extend(pattern[:take])
                if len(result) >= target:
                    break
            # Advance past pattern_len byte + pattern bytes
            i += 1 + pattern_len
        else:
            # Type B: literal copy
            n = ctrl - 0x7f          # number of bytes to emit
            take = min(n, target - len(result))
            result.extend(data[i + 1 : i + 1 + take])
            i += ctrl - 0x7e         # = 1 (ctrl) + n (data) bytes consumed

    return bytes(result), i - start


# ---------------------------------------------------------------------------
# Bit-depth expansion (MSB-first, standard QuickDraw packing)
# ---------------------------------------------------------------------------

def expand_bits(data: bytes, depth: int, target_pixels: int) -> bytes:
    """Expand N-bit-per-pixel packed data (MSB first) to 8-bit unsigned indices.

    Always returns exactly target_pixels bytes (zero-padded if data is short).
    """
    if depth == 8:
        result = bytearray(data[:target_pixels])
        if len(result) < target_pixels:
            result.extend(b'\x00' * (target_pixels - len(result)))
        return bytes(result)
    if depth not in (1, 2, 4):
        return bytes(target_pixels)
    result = bytearray()
    mask = (1 << depth) - 1
    for byte_val in data:
        for shift in range(8 - depth, -1, -depth):
            result.append((byte_val >> shift) & mask)
            if len(result) >= target_pixels:
                return bytes(result)
    result.extend(b'\x00' * (target_pixels - len(result)))
    return bytes(result)


def expand_bits_signed(data: bytes, depth: int, target_pixels: int) -> list[int]:
    """Expand N-bit-per-pixel (MSB first) with sign-extension — for FUN_00000896.

    Matches FUN_00000896 for standard QuickDraw depths 1/2/4/8.
    Each depth-bit value is sign-extended to a Python int.
    Returns a list of `target_pixels` signed ints.
    """
    # For depth 8, bytes are already signed
    raw = expand_bits(data, depth, target_pixels)
    if depth >= 8:
        return [b if b < 128 else b - 256 for b in raw]
    sign_bit = 1 << (depth - 1)
    fill     = 0xFF << depth & 0xFF   # used to sign-extend
    result = []
    for b in raw:
        if b & sign_bit:
            result.append(b | (fill << 0) | 0xFFFFFF00 & -1)
            # Simpler: just subtract 2^depth
            result[-1] = b - (1 << depth)
        else:
            result.append(b)
        if len(result) >= target_pixels:
            break
    while len(result) < target_pixels:
        result.append(0)
    return result


def fun_000009cc(
    row_buf: list[int],
    comp_w: int,
    ivar5: bytes,
    ivar5_n: int,
    depth: int,
) -> bytes:
    """Delta-index decoder (FUN_000009cc).

    Row_buf contains sign-extended depth-bit values from FUN_00000896.
    Applies a running modular-delta to a palette index, then maps via ivar5.

    Matches the pseudocode logic in CODE_20 FUN_000009cc exactly.
    """
    if ivar5_n <= 0:
        return bytes(comp_w)

    output  = bytearray(comp_w)
    cvar2   = 1 << (depth - 1)     # e.g., 2 for depth=2
    mask    = cvar2 - 1             # e.g., 1 for depth=2  (= uVar1 initial)
    # 'special' values in row_buf that cause accumulation:
    # uVar1 == cVar6 OR -cVar2 == cVar6
    mask_s  = mask if mask < 128 else mask - 256   # sign-extended mask
    neg2    = -cvar2                               # e.g., -2 for depth=2

    uvar5 = 0    # running palette-index (unsigned 8-bit)
    uvar3 = 0    # index into row_buf

    for local_6 in range(comp_w):
        if uvar3 >= len(row_buf):
            break

        cvar6 = row_buf[uvar3]      # already signed

        # Accumulate special values
        while True:
            uvar3 += 1
            if (mask_s != cvar6) and (neg2 != cvar6):
                break                                   # not special → exit
            # accumulate: uVar5 = (byte)(cVar6 + (char)uVar5)
            uvar5_s = uvar5 if uvar5 < 128 else uvar5 - 256  # signed view
            uvar5   = (uvar5_s + cvar6) & 0xFF
            if uvar3 >= len(row_buf):
                break
            cvar6 = row_buf[uvar3]

        # Apply accumulated delta: cVar6 += (char)uVar5
        uvar5_s = uvar5 if uvar5 < 128 else uvar5 - 256
        cvar6  += uvar5_s

        # Modular wrap into [0, ivar5_n-1]
        if cvar6 < 0:
            cvar6 += ivar5_n
        if cvar6 > ivar5_n - 1:
            cvar6 -= ivar5_n

        uvar5 = cvar6 & 0xFF

        idx = cvar6
        if 0 <= idx < len(ivar5):
            output[local_6] = ivar5[idx]

    return bytes(output)


# ---------------------------------------------------------------------------
# Frame decoder  — FUN_00000002
# ---------------------------------------------------------------------------

def decode_frame(
    data: bytes,
    start: int,
    disp_width: int,
    disp_height: int,
    prev_frame: bytes | None,
) -> tuple[bytes, int]:
    """Decode one MECC Imag frame from row-opcode stream (FUN_00000002).

    Args:
        data:        raw resource bytes (from pixel_start onward)
        start:       byte offset within `data` where this frame begins
        disp_width:  display width from PixMap bounds
        disp_height: display height from PixMap bounds
        prev_frame:  pixel bytes of the previous frame (for sub=4 delta rows),
                     or None for the first frame.

    Returns:
        (pixel_bytes, end_offset)
        pixel_bytes is disp_width × disp_height 8-bit palette indices.
        end_offset is the byte offset within `data` just past this frame
        (word-aligned, pointing to the next frame header or end of resource).
    """
    if start + 5 > len(data):
        return bytes(disp_width * disp_height), start

    # 5-byte per-frame subheader (little-endian)
    comp_w = struct.unpack_from('<H', data, start)[0]
    comp_h = struct.unpack_from('<H', data, start + 2)[0]
    # data[start + 4] = unknown byte (always 0x01 in practice)

    if comp_w == 0 or comp_h == 0:
        # Degenerate frame
        return bytes(disp_width * disp_height), start + 5

    ptr = start + 5
    output = bytearray(comp_w * comp_h)

    # ivar5: small palette indirection table updated by sub=6 opcodes.
    # Maps compressed bit-indices → actual game palette indices.
    ivar5   = bytearray(256)
    ivar5_n = 0   # valid entry count (A5-0x38a in original; used for modular wrap)

    # Per-row palette pointer cache for sub=6/low=1,2 back-references.
    # Maps row_index → (ptr_to_count_byte, n) in `data`.
    row_pal_cache: dict[int, tuple[int, int]] = {}

    row = 0
    decode_ok = True

    while row < comp_h:
        if ptr >= len(data):
            break

        opcode_ptr = ptr          # pbVar18
        opcode = data[ptr]
        ptr += 1                  # pbVar17 = pbVar18 + 1

        case = opcode >> 6
        sub  = (opcode & 0x38) >> 3
        low  = opcode & 7
        row_off = row * comp_w

        # ------------------------------------------------------------------
        # case 3 (bits 7:6 == 11)  — the most common path
        # ------------------------------------------------------------------
        if case == 3:

            if sub == 0:
                # Literal: copy comp_w bytes verbatim
                output[row_off : row_off + comp_w] = data[ptr : ptr + comp_w]
                ptr += comp_w
                row += 1

            elif sub == 1:
                # Solid fill: fill row with one colour index
                fill = data[ptr]
                ptr += 1   # pbVar17 = pbVar18 + 2
                output[row_off : row_off + comp_w] = bytes([fill]) * comp_w
                row += 1

            elif sub == 2:
                # Copy row — 1-byte signed delta (rows back from current)
                delta = struct.unpack_from('b', data, ptr)[0]
                ptr += 1   # pbVar17 = pbVar18 + 2
                ref_row = row + delta
                if 0 <= ref_row < row:
                    src = output[ref_row * comp_w : (ref_row + 1) * comp_w]
                else:
                    src = bytes(comp_w)
                output[row_off : row_off + comp_w] = src
                row += 1

            elif sub == 3:
                # Copy row — 2-byte big-endian signed word delta
                delta = struct.unpack_from('>h', data, ptr)[0]
                ptr += 2   # pbVar17 = pbVar18 + 3
                ref_row = row + delta
                if 0 <= ref_row < row:
                    src = output[ref_row * comp_w : (ref_row + 1) * comp_w]
                else:
                    src = bytes(comp_w)
                output[row_off : row_off + comp_w] = src
                row += 1

            elif sub == 4:
                # Copy same row from previous frame (delta across time, no stream bytes).
                # If no previous frame exists, leave the row as zeros.
                if prev_frame is not None and len(prev_frame) >= row_off + comp_w:
                    output[row_off : row_off + comp_w] = \
                        prev_frame[row_off : row_off + comp_w]
                row += 1

            elif sub == 5:
                # Compressed row: low=7 → FUN_00000aba (multi-byte pattern repeat);
                #                 low=1..6 → A5+0x132 MECC_RLE (single-byte run-length).
                # A5+0x132 writes comp_w bytes directly to the output row as
                # 8-bit palette indices (no bit expansion, no ivar5 remap at this level).
                if low == 7:
                    # FUN_00000aba decompresses to 8-bit palette indices directly
                    decoded, consumed = fun_00000aba(data, ptr, comp_w)
                    output[row_off : row_off + comp_w] = decoded[:comp_w]
                    ptr += consumed
                else:
                    # MECC_RLE: A5+0x132 writes comp_w bytes as 8-bit indices
                    decoded, consumed = mecc_rle(data, ptr, comp_w)
                    output[row_off : row_off + comp_w] = decoded[:comp_w]
                    ptr += consumed
                row += 1

            elif sub == 6:
                # Palette setup for ivar5 — does NOT increment row counter
                if low == 0:
                    # Inline palette: [count_byte][palette_bytes x count]
                    n = data[ptr]
                    pal_data = data[ptr + 1 : ptr + 1 + n]
                    ivar5[:n] = pal_data
                    ivar5_n = n
                    row_pal_cache[row] = (ptr, n)
                    ptr += n + 1
                elif low == 1:
                    # Reference a previously stored palette by 1-byte back-delta
                    back = data[ptr]
                    ptr += 1   # pbVar17 = pbVar18 + 2
                    ref = row - back
                    if ref in row_pal_cache:
                        rp, rn = row_pal_cache[ref]
                        ivar5[:rn] = data[rp + 1 : rp + 1 + rn]
                        ivar5_n = rn
                elif low == 2:
                    # n byte + 1-byte back-delta
                    n    = data[ptr]
                    back = data[ptr + 1]
                    ptr += 2   # pbVar17 = pbVar18 + 3
                    ref = row - back
                    if ref in row_pal_cache:
                        rp, _ = row_pal_cache[ref]
                        ivar5[:n] = data[rp + 1 : rp + 1 + n]
                        ivar5_n = n
                # No row increment for sub=6

            else:
                # Unknown sub — give up decoding this frame
                decode_ok = False
                break

        # ------------------------------------------------------------------
        # case 2 (bits 7:6 == 10)
        #   sub = bit-depth, low = compression variant
        #   Output: direct ivar5 lookup (no running delta, unlike cases 0/1).
        #   Final step in pseudocode: output[i] = ivar5[(short)(ushort)row_buf[i]]
        # ------------------------------------------------------------------
        elif case == 2:
            depth        = sub if sub != 0 else 8
            pixel_count  = comp_w    # case 2 produces exactly comp_w pixels
            target_bytes = (pixel_count * depth + 7) // 8

            if low == 7:
                # FUN_00000aba to expand_buf, then FUN_00000896 to row_buf
                decoded, consumed = fun_00000aba(data, ptr, target_bytes)
                ptr += consumed
                row_buf = expand_bits(decoded, depth, pixel_count)
            elif low == 0:
                # Direct bit-packed data; advances ptr by the bit stream size
                # (determined by A5+0x25a which returns uVar7*depth bits — we
                # estimate it as pixel_count * depth bits)
                row_buf = expand_bits(data[ptr : ptr + target_bytes], depth, pixel_count)
                ptr += target_bytes
            else:
                # A5+0x132 MECC_RLE decompresses to packed N-bit data,
                # then FUN_00000896 expands to 8-bit row_buf
                decoded, consumed = mecc_rle(data, ptr, target_bytes)
                ptr += consumed
                row_buf = expand_bits(decoded, depth, pixel_count)

            # Direct ivar5 map (no running delta for case 2)
            mapped = bytearray(comp_w)
            for i in range(min(comp_w, len(row_buf))):
                idx = row_buf[i]
                if idx < len(ivar5):
                    mapped[i] = ivar5[idx]
            output[row_off : row_off + comp_w] = mapped
            row += 1

        # ------------------------------------------------------------------
        # cases 0 and 1 — FUN_00000896 (bit expand) + FUN_000009cc (delta→ivar5)
        #
        #   Opcode layout: [opcode][pixel_count_lo][pixel_count_hi][compressed…]
        #   pixel_count is a LE 16-bit word giving the number of bit-depth pixels
        #   to expand via FUN_00000896 before passing to FUN_000009cc.
        #
        #   sub = bit-depth (1/2/4/8; 0 → 8)
        #   low = compression variant:
        #     7 = FUN_00000aba to temp buf, then FUN_00000896
        #     0 = direct packed bits (no FUN_00000aba), advance by bit-stream bytes
        #     other = FUN_00000aba+expand combined via A5+0x132 (approximated)
        # ------------------------------------------------------------------
        elif case in (0, 1):
            # Read LE pixel count word at ptr (= pbVar17 = opcode+1)
            if ptr + 1 >= len(data):
                break
            pixel_count = data[ptr + 1] * 0x100 + data[ptr]   # LE: lo at ptr, hi at ptr+1
            depth       = sub if sub != 0 else 8
            target_bytes = (pixel_count * depth + 7) // 8

            if low == 7:
                # FUN_00000aba decompresses to expand_buf, then FUN_00000896 expands
                decoded, consumed = fun_00000aba(data, ptr + 2, target_bytes)
                ptr += 2 + consumed
                row_buf_signed = expand_bits_signed(decoded, depth, pixel_count)
            elif low == 0:
                # No FUN_00000aba; bit-packed data starts at ptr+2
                # ptr advances by target_bytes + 2 (the pixel_count word)
                row_buf_signed = expand_bits_signed(
                    data[ptr + 2 : ptr + 2 + target_bytes], depth, pixel_count
                )
                ptr += 2 + target_bytes
            else:
                # A5+0x132 MECC_RLE decompresses to packed N-bit data,
                # then FUN_00000896 expands to signed values for FUN_000009cc
                decoded, consumed = mecc_rle(data, ptr + 2, target_bytes)
                ptr += 2 + consumed
                row_buf_signed = expand_bits_signed(decoded, depth, pixel_count)

            # FUN_000009cc: running delta → ivar5 mapping → output row
            row_pixels = fun_000009cc(
                row_buf_signed, comp_w, bytes(ivar5), ivar5_n, depth
            )
            output[row_off : row_off + comp_w] = row_pixels
            row += 1

        else:
            decode_ok = False
            break

    # Word-align the end pointer (FUN_00000002 final alignment bump)
    if ptr & 1:
        ptr += 1

    # Reshape compression dimensions → display dimensions if they differ
    pixels = bytes(output)
    if comp_w != disp_width or comp_h != disp_height:
        comp_total = comp_w * comp_h
        disp_total = disp_width * disp_height
        if comp_total == disp_total:
            # Same pixel count, different layout; use flat buffer as-is
            pass
        else:
            # Pad or trim to display size
            pixels = (pixels + bytes(disp_total))[:disp_total]

    return pixels, ptr


# ---------------------------------------------------------------------------
# Frame sentinel utilities — find the 0xff×4 + 0x00×4 inter-frame marker
# ---------------------------------------------------------------------------

_FRAME_SENTINEL = bytes([0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00])


def find_all_sentinels(pixel_data: bytes) -> list[int]:
    """Return the start offsets of all 8-byte inter-frame sentinel markers.

    Scans the entire pixel_data buffer.  False positives (the pattern
    accidentally appearing inside image data) are theoretically possible but
    extremely rare in practice because opcode 0xFF causes an immediate
    decode_ok=False, so it cannot appear as an opcode byte.
    """
    positions: list[int] = []
    pos = 0
    sentinel_len = len(_FRAME_SENTINEL)
    while True:
        idx = pixel_data.find(_FRAME_SENTINEL, pos)
        if idx < 0:
            break
        positions.append(idx)
        pos = idx + 1          # allow overlapping (shouldn't happen, but safe)
    return positions


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    root      = Path(__file__).resolve().parent.parent
    rsrc_path = root / "raw" / "oregon_color.rsrc"
    out_dir   = root / "assets" / "images" / "imag"

    # Wipe stale output before regenerating
    if out_dir.exists():
        for f in out_dir.glob("*.png"):
            f.unlink()
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Reading {rsrc_path}")
    with open(rsrc_path, "rb") as f:
        raw = f.read()

    all_resources = list(macresources.parse_file(raw))

    # -----------------------------------------------------------------------
    # Build fallback game palette.
    # imag_19000's inline CTable has all 256 entries; prefer it over clut1008
    # which only has 235 entries (indices 235-255 would be black otherwise).
    # -----------------------------------------------------------------------
    fallback_palette = bytes(256 * 3)
    imag_19000_data  = next(
        (bytes(r) for r in all_resources if r.type == b"Imag" and r.id == 19000),
        None,
    )
    if imag_19000_data is not None:
        has_ct, _ = detect_inline_ctable(imag_19000_data)
        if has_ct:
            fallback_palette = build_palette_from_ctable(imag_19000_data, DATA_OFFSET)
            print("Fallback palette: imag_19000 inline CTable (256 entries)")

    if fallback_palette == bytes(256 * 3):
        clut_resources = {r.id: bytes(r) for r in all_resources if r.type == b"clut"}
        if 1008 in clut_resources:
            fallback_palette = build_palette_from_clut(clut_resources[1008])
            print("Fallback palette: clut1008 (235 entries — indices 235-255 black)")
        else:
            print("WARNING: no palette source found; output will be all black",
                  file=sys.stderr)

    imag_list = sorted(
        [r for r in all_resources if r.type == b"Imag"],
        key=lambda r: r.id,
    )
    print(f"Found {len(imag_list)} Imag resources\n")

    total_saved = 0
    errors      = 0

    for r in imag_list:
        data = bytes(r)
        rid  = r.id

        # 6-byte MECC header (big-endian words)
        h1, h2, h3 = struct.unpack_from(">HHH", data, 0)   # noqa: F841
        frame_count = max(h1, 1)

        # PixMap
        pm         = parse_pixmap(data)
        disp_w     = pm["width"]
        disp_h     = pm["height"]
        row_bytes  = pm["row_bytes"]

        if not pm["is_pixmap"] or row_bytes <= 0 or disp_h <= 0 or disp_w <= 0:
            print(
                f"  imag_{rid}: SKIP — invalid PixMap "
                f"(rb={row_bytes}, w={disp_w}, h={disp_h})",
                file=sys.stderr,
            )
            errors += 1
            continue

        # Inline CTable detection
        has_ctable, ct_byte_size = detect_inline_ctable(data)
        if has_ctable:
            palette      = build_palette_from_ctable(data, DATA_OFFSET)
            pixel_start  = DATA_OFFSET + ct_byte_size
        else:
            palette      = fallback_palette
            pixel_start  = DATA_OFFSET

        pixel_data = data[pixel_start:]

        # Pre-locate all inter-frame sentinels so frame boundaries are correct
        # even when decode_frame terminates early (unknown opcodes, case=0/1
        # rows, etc.).  Frame i starts immediately after sentinel[i-1].
        sentinel_pos = find_all_sentinels(pixel_data)
        # frame_starts[0] = 0 (always); frame_starts[i] = sentinel[i-1] + 8
        _slen = len(_FRAME_SENTINEL)
        frame_starts = [0] + [s + _slen for s in sentinel_pos]

        frames: list[bytes] = []
        prev: bytes | None  = None

        for _fi in range(frame_count):
            if _fi >= len(frame_starts):
                break
            frame_start = frame_starts[_fi]
            if frame_start >= len(pixel_data):
                break
            pixels, _ = decode_frame(
                pixel_data, frame_start, disp_w, disp_h, prev
            )
            frames.append(pixels)
            prev = pixels

        if not frames:
            print(
                f"  imag_{rid}: ERROR — no frames decoded "
                f"(w={disp_w}, h={disp_h}, data={len(pixel_data)})",
                file=sys.stderr,
            )
            errors += 1
            continue

        # Save each frame as a paletted PNG
        for i, frame_pixels in enumerate(frames):
            suffix  = f"_{i:02d}" if len(frames) > 1 else ""
            out_path = out_dir / f"imag_{rid}{suffix}.png"
            img = Image.new("P", (disp_w, disp_h))
            img.putpalette(palette)
            img.putdata(frame_pixels)
            img.save(out_path)
            total_saved += 1

        pal_note   = "CTable" if has_ctable else "fallback-pal"
        frame_note = f" ({len(frames)}/{frame_count} frames)" if frame_count > 1 else ""
        print(f"  imag_{rid}  {disp_w}×{disp_h}  {pal_note}{frame_note}")

    print(f"\nDone: {total_saved} PNG files written to {out_dir}  ({errors} errors)")


if __name__ == "__main__":
    main()
