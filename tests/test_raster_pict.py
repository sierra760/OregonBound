"""Synthetic native raster PICT coverage without platform conversion."""
import struct
import pytest
from scripts.graphics_extract import pict


def mono_picture():
    frame = struct.pack('>hhhh', 3, 5, 4, 7)
    bounds = struct.pack('>hhhh', 3, 0, 4, 64)
    region = struct.pack('>H', 10) + frame
    return (bytes(2) + frame + bytes([0x11, 1, 1]) + region + bytes([0x99])
            + struct.pack('>H', 8) + bounds + frame * 2 + bytes(2) + region
            + bytes([4, 0, 4, 250, 0, 255]))


def test_monochrome_crops_padded_rows_relative_to_bounds():
    image = pict._convert_monochrome_packbits_pict(mono_picture())
    assert image.size == (2, 1)
    assert list(image.getdata()) == [(0, 0, 0, 255), (255, 255, 255, 255)]


def indexed_picture():
    frame = struct.pack('>hhhh', 0, 0, 1, 3)
    pixmap = bytearray(46)
    struct.pack_into('>H', pixmap, 0, 0x8008)
    pixmap[2:10] = frame
    struct.pack_into('>HHH', pixmap, 28, 8, 1, 8)
    palette = struct.pack('>IHH8H', 0, 0, 1, 0, 0, 0, 0, 1, 65535, 65535, 65535)
    stream = (bytes(2) + frame + bytes.fromhex('001102ff0c00') + bytes(24)
              + bytes.fromhex('000000a00082001e0098') + pixmap + palette + frame * 2 + bytes(2)
              + bytes([9, 7, 0, 1, 0, 0, 0, 0, 0, 0]) + bytes.fromhex('00a0008300ff'))
    return stream


def test_v2_comments_and_default_highlight_are_skipped():
    image = pict._convert_indexed_packbits_pict(indexed_picture())
    assert image is not None
    assert list(image.getdata()) == [(0, 0, 0, 255), (255, 255, 255, 255), (0, 0, 0, 255)]


@pytest.mark.parametrize('data,count,stride', [(b'\x00', 1, 1), (b'\xff', 1, 2),
    (b'\x01\x11\x22', 2, 2), (b'\xfe\x11', 2, 2), (b'\x00\x11', 3, 1)])
def test_packbits_rejects_incomplete_or_overflowing_row(data, count, stride):
    with pytest.raises(ValueError):
        pict._unpack_packbits_row(data, 0, count, stride)


@pytest.mark.parametrize('kind', ['missing_end', 'trailing_draw', 'narrow_clip', 'short_stride', 'oversized'])
def test_indexed_rejects_incomplete_or_unsupported_rendering(kind):
    data = indexed_picture()
    if kind == 'missing_end': data = data[:-2]
    elif kind == 'trailing_draw': data = data[:-2] + struct.pack('>5H', 0x30, 0, 0, 1, 3) + data[-2:]
    elif kind == 'narrow_clip': data = data[:40] + struct.pack('>6H', 1, 10, 0, 0, 1, 2) + data[40:]
    elif kind == 'oversized':
        data = bytearray(data)
        struct.pack_into('>H', data, 50, 0xa000)
        for offset in (2, 52, 120, 128):struct.pack_into('>hhhh', data, offset, 0, 0, 4097, 8192)
    else:
        data = bytearray(data)
        for offset in (2, 52, 120, 128):struct.pack_into('>hhhh', data, offset, 0, 0, 1, 9)
    assert pict._convert_indexed_packbits_pict(data) is None


def test_indexed_nonzero_origin_crops_relative_to_bitmap():
    data = bytearray(indexed_picture())
    for offset in (2, 52, 120, 128):struct.pack_into('>hhhh', data, offset, 3, 5, 4, 8)
    image = pict._convert_indexed_packbits_pict(data)
    assert image.tobytes() == bytes([0,0,0,255,255,255,255,255,0,0,0,255])
