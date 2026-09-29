"""Self-contained MECC Imag row codec.

Row operations follow the original CODE 20 machine instructions. Frame
container traversal and per-frame PixMap layout live in imag.py.
"""

import struct


HEADER_SIZE   = 6    # MECC 6-byte resource header
PIXMAP_SIZE   = 50   # QuickDraw PixMap struct
PIXMAP_OFFSET = HEADER_SIZE
DATA_OFFSET   = HEADER_SIZE + PIXMAP_SIZE   # = 56


# ---------------------------------------------------------------------------
# PixMap / CTable helpers (unchanged from previous version)
# ---------------------------------------------------------------------------

def parse_pixmap(data: bytes, offset: int = PIXMAP_OFFSET) -> dict:
    """Parse a QuickDraw PixMap (first-frame offset by default)."""
    off = offset
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

def mecc_rle(data: bytes, start: int, target: int, pattern_len: int = 1) -> tuple[bytes, int]:
    """MECC RLE decompressor (A5+0x132 function pointer).

    ctrl < 0x80  → run of (ctrl+1) copies of the next pattern_len bytes.
    ctrl >= 0x80 → literal copy of (ctrl-0x7f) bytes.

    This is "inverted PackBits": ctrl<0x80 = run (not literal). The low
    opcode bits are the pattern width consumed by the original A5+0x132 helper.

    Returns (decoded_bytes, bytes_consumed_from_data_starting_at_start).
    """
    result = bytearray()
    i = start
    end = len(data)
    pattern_len = max(1, pattern_len)
    while len(result) < target and i < end:
        ctrl = data[i]
        if ctrl < 0x80:
            # Run of (ctrl+1) copies of the next fixed-width pattern.
            reps = ctrl + 1
            pattern = data[i + 1 : i + 1 + pattern_len]
            for _ in range(reps):
                result.extend(pattern)
            i += 1 + pattern_len
        else:
            # Literal copy of (ctrl-0x7f) bytes
            n = ctrl - 0x7f
            result.extend(data[i + 1 : i + 1 + n])
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
                result.extend(pattern)
            # Advance past pattern_len byte + pattern bytes
            i += 1 + pattern_len
        else:
            # Type B: literal copy
            n = ctrl - 0x7f          # number of bytes to emit
            result.extend(data[i + 1 : i + 1 + n])
            i += ctrl - 0x7e         # = 1 (ctrl) + n (data) bytes consumed

    return bytes(result), i - start


# ---------------------------------------------------------------------------
# Bit-depth expansion (table-driven LSB-first, as used by MECC's decoder)
# ---------------------------------------------------------------------------

_BIT_MASKS = [0x00, 0x01, 0x03, 0x07, 0x0F, 0x1F, 0x3F, 0x7F]
_BIT_STRIDES = [0, 1, 1, 3, 1, 5, 3, 7]
_BIT_GROUPS = [0, 8, 4, 8, 2, 8, 4, 8]
_BIT_BYTE_OFFSETS = {
    1: (0, 0, 0, 0, 0, 0, 0, 0),
    2: (0, 0, 0, 0),
    3: (0, 0, 0, 1, 1, 1, 2, 2),
    4: (0, 0),
    5: (0, 0, 1, 1, 2, 3, 3, 4),
    6: (0, 0, 1, 2),
    7: (0, 0, 1, 2, 3, 4, 5, 6),
}
_BIT_SHIFTS = {
    1: (0, 1, 2, 3, 4, 5, 6, 7),
    2: (0, 2, 4, 6),
    3: (0, 3, 6, 1, 4, 7, 2, 5),
    4: (0, 4),
    5: (0, 5, 2, 7, 4, 1, 6, 3),
    6: (0, 6, 4, 2),
    7: (0, 7, 6, 5, 4, 3, 2, 1),
}


def expand_bits(data: bytes, depth: int, target_pixels: int) -> bytes:
    """Expand N-bit-per-pixel packed data to 8-bit unsigned indices.

    This mirrors the original A5+0x12a helper: bit fields are read from
    little-endian 16-bit windows using depth-specific offset/shift tables.
    Always returns exactly target_pixels bytes (zero-padded if data is short).
    """
    if depth == 8:
        result = bytearray(data[:target_pixels])
        if len(result) < target_pixels:
            result.extend(b'\x00' * (target_pixels - len(result)))
        return bytes(result)
    if depth < 1 or depth > 8:
        return bytes(target_pixels)
    result = bytearray()
    mask = _BIT_MASKS[depth]
    stride = _BIT_STRIDES[depth]
    group = _BIT_GROUPS[depth]
    offsets = _BIT_BYTE_OFFSETS[depth]
    shifts = _BIT_SHIFTS[depth]
    base = 0
    index = 0
    while len(result) < target_pixels:
        byte_index = base + offsets[index]
        lo = data[byte_index] if byte_index < len(data) else 0
        hi_index = byte_index + 1
        hi = data[hi_index] if hi_index < len(data) else 0
        value = ((hi << 8) | lo) >> shifts[index]
        result.append(value & mask)
        index += 1
        if index == group:
            index = 0
            base += stride
    result.extend(b'\x00' * (target_pixels - len(result)))
    return bytes(result)


def expand_bits_signed(data: bytes, depth: int, target_pixels: int) -> list[int]:
    """Expand N-bit-per-pixel with sign-extension, for FUN_00000896.

    Each depth-bit value is sign-extended to a Python int. The original
    function uses the same field tables as A5+0x12a, then stores signed chars.
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
) -> tuple[bytes, int]:
    """Delta-index decoder (FUN_000009cc).

    Row_buf contains sign-extended depth-bit values from FUN_00000896.
    Applies a running modular-delta to a palette index, then maps via ivar5.

    Matches the pseudocode logic in CODE_20 FUN_000009cc exactly.
    """
    if ivar5_n <= 0:
        return bytes(comp_w), 0

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

    return bytes(output), uvar3


def fun_000018e4(row_buf: bytes, comp_w: int, ivar5: bytes, depth: int) -> tuple[bytes, int]:
    """Case-1 index decoder (A5+0x13a, target 0x18e4 in CODE_1).

    Unlike FUN_000009cc, this helper works on unsigned symbols and only treats
    the positive all-ones value for the current depth as an accumulator sentinel.
    It returns both output pixels and the number of source symbols consumed.
    """
    if not ivar5:
        return bytes(comp_w), 0

    special = _BIT_MASKS[depth] if 0 <= depth < len(_BIT_MASKS) else 0xFF
    output = bytearray(comp_w)
    consumed = 0
    for pixel in range(comp_w):
        acc = 0
        while True:
            if consumed >= len(row_buf):
                return bytes(output), consumed
            value = row_buf[consumed]
            consumed += 1
            if value != special:
                break
            acc = (acc + value) & 0xFF
        index = (acc + value) & 0xFF
        if index < len(ivar5):
            output[pixel] = ivar5[index]
    return bytes(output), consumed


# ---------------------------------------------------------------------------
# Frame decoder  — FUN_00000002
# ---------------------------------------------------------------------------

def decode_frame(
    data: bytes,
    start: int,
    disp_width: int,
    disp_height: int,
    prev_frame: bytes | None,
    *,
    align_end: bool = True,
) -> tuple[bytes, int]:
    """Decode one MECC Imag frame from row-opcode stream (FUN_00000002).

    Args:
        data:        raw resource bytes (from pixel_start onward)
        start:       byte offset within `data` where this frame begins
        disp_width:  display width from PixMap bounds
        disp_height: display height from PixMap bounds
        prev_frame:  retained for API compatibility; original row references
                     are entirely within this frame, never across frames.
        align_end:   reproduce CODE 20:0x872–0x888's return-pointer alignment.
                     The container uses declared lengths instead (CODE 5:0x5ba2),
                     so its decoder requests the actual consumed position.

    Returns:
        (pixel_bytes, end_offset)
        pixel_bytes is the raw decoded frame buffer in the frame header's
        compression layout.
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
                # CODE 20:0x568–0x578 multiplies an unsigned absolute row
                # number by comp_w and adds the output buffer base.
                ref_row = data[ptr]
                ptr += 1
                if 0 <= ref_row < row:
                    src = output[ref_row * comp_w : (ref_row + 1) * comp_w]
                else:
                    src = bytes(comp_w)
                output[row_off : row_off + comp_w] = src
                row += 1

            elif sub == 3:
                # CODE 20:0x5b0–0x5ce reads low byte then high byte;
                # this is an absolute row index, not a relative displacement.
                ref_row = struct.unpack_from('<H', data, ptr)[0]
                ptr += 2
                if 0 <= ref_row < row:
                    src = output[ref_row * comp_w : (ref_row + 1) * comp_w]
                else:
                    src = bytes(comp_w)
                output[row_off : row_off + comp_w] = src
                row += 1

            elif sub == 4:
                # CODE 20:0x604–0x618 computes (row - 1) * comp_w
                # from this frame's output base. It repeats the preceding row.
                if row:
                    output[row_off : row_off + comp_w] = \
                        output[row_off - comp_w : row_off]
                row += 1

            elif sub == 5:
                # Compressed row: low=7 → FUN_00000aba (multi-byte pattern repeat);
                #                 low=1..6 → A5+0x132 MECC_RLE (fixed-width pattern run).
                # A5+0x132 writes comp_w bytes directly to the output row as
                # 8-bit palette indices (no bit expansion, no ivar5 remap at this level).
                if low == 7:
                    # FUN_00000aba decompresses to 8-bit palette indices directly
                    decoded, consumed = fun_00000aba(data, ptr, comp_w)
                    output[row_off : row_off + comp_w] = decoded[:comp_w]
                    ptr += consumed
                else:
                    # MECC_RLE: A5+0x132 writes comp_w bytes as 8-bit indices
                    decoded, consumed = mecc_rle(data, ptr, comp_w, pattern_len=low)
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
                row_buf = expand_bits(data[ptr:], depth, pixel_count)
                ptr += target_bytes
            else:
                # A5+0x132 MECC_RLE decompresses to packed N-bit data,
                # then FUN_00000896 expands to 8-bit row_buf
                decoded, consumed = mecc_rle(data, ptr, target_bytes, pattern_len=low)
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
        # case 0 — FUN_00000896 (signed bit expand) + FUN_000009cc (delta→ivar5)
        #
        #   Opcode layout: [opcode][pixel_count_lo][pixel_count_hi][compressed…]
        #   pixel_count is a LE 16-bit word giving the number of bit-depth pixels
        #   to expand via FUN_00000896 before passing to FUN_000009cc.
        #
        #   sub = bit-depth (1/2/4/8; 0 → 8)
        #   low = compression variant:
        #     7 = FUN_00000aba to temp buf, then FUN_00000896
        #     0 = direct packed bits (no FUN_00000aba), advance by bit-stream bytes
        #     other = A5+0x132 fixed-width pattern RLE, then FUN_00000896
        # ------------------------------------------------------------------
        elif case == 0:
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
                row_buf_signed = expand_bits_signed(decoded, depth, pixel_count + 1)
            elif low == 0:
                # No FUN_00000aba; bit-packed data starts at ptr+2
                # ptr advances by target_bytes + 2 (the pixel_count word)
                row_buf_signed = expand_bits_signed(
                    data[ptr + 2 :], depth, pixel_count + 1
                )
                ptr += 2 + target_bytes
            else:
                # A5+0x132 MECC_RLE decompresses to packed N-bit data,
                # then FUN_00000896 expands to signed values for FUN_000009cc
                decoded, consumed = mecc_rle(data, ptr + 2, target_bytes, pattern_len=low)
                ptr += 2 + consumed
                row_buf_signed = expand_bits_signed(decoded, depth, pixel_count + 1)

            # FUN_000009cc: running delta → ivar5 mapping → output row
            row_pixels, _consumed_symbols = fun_000009cc(
                row_buf_signed, comp_w, bytes(ivar5), ivar5_n, depth
            )
            output[row_off : row_off + comp_w] = row_pixels
            row += 1

        # ------------------------------------------------------------------
        # case 1 — A5+0x12a (unsigned bit expand) + A5+0x13a (index→ivar5)
        # ------------------------------------------------------------------
        elif case == 1:
            if ptr + 1 >= len(data):
                break
            pixel_count = data[ptr + 1] * 0x100 + data[ptr]
            depth = sub if sub != 0 else 8
            target_bytes = (pixel_count * depth + 7) // 8

            if low == 7:
                decoded, consumed = fun_00000aba(data, ptr + 2, target_bytes)
                ptr += 2 + consumed
                row_buf = expand_bits(decoded, depth, pixel_count + 1)
            elif low == 0:
                row_buf = expand_bits(data[ptr + 2 :], depth, pixel_count + 1)
                ptr += 2 + target_bytes
            else:
                decoded, consumed = mecc_rle(data, ptr + 2, target_bytes, pattern_len=low)
                ptr += 2 + consumed
                row_buf = expand_bits(decoded, depth, pixel_count + 1)

            row_pixels, _consumed_symbols = fun_000018e4(
                row_buf, comp_w, bytes(ivar5), depth
            )
            output[row_off : row_off + comp_w] = row_pixels
            row += 1

        else:
            decode_ok = False
            break

    if row != comp_h:
        raise ValueError(f"Incomplete Imag frame: decoded {row} of {comp_h} compression rows")

    # Word-align the end pointer (FUN_00000002 final alignment bump)
    if align_end and (ptr - start) & 1:
        ptr += 1

    return bytes(output), ptr


# ---------------------------------------------------------------------------
# Frame sentinel utilities — find the 0xff×4 + 0x00×4 inter-frame marker
# ---------------------------------------------------------------------------

_FRAME_SENTINEL = bytes([0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00])


def find_all_sentinels(pixel_data: bytes) -> list[int]:
    """Find the historical marker pattern, for legacy analysis callers only.

    This is NOT a frame-boundary parser: the pattern is a PixMap's pmTable
    and pmReserved fields, and can also occur inside literal pixel data.
    Production frame traversal must use the container's declared lengths.
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
