import struct

from scripts.graphics_extract.models import DecodeStatus, ResourceInfo
from scripts.graphics_extract.pict import convert_pict, _convert_indexed_packbits_pict, normalize_pict


def picture(duplicate=True):
    frame = struct.pack('>hhhh', 0, 0, 1, 3)
    header = struct.pack('>iiiiii', -1, 0, 0, 3 << 16, 1 << 16, 0)
    pixmap = bytearray(46)
    struct.pack_into('>H', pixmap, 0, 0x8008)
    pixmap[2:10] = frame
    struct.pack_into('>HHH', pixmap, 28, 8, 1, 8)
    palette = struct.pack('>IHHHHHHHHHH', 0, 0, 1, 0, 0, 0, 0, 1, 65535, 65535, 65535)
    return (b'\0\0' + frame + bytes.fromhex('001102ff0c00')
            + (header[:16] if duplicate else b'') + header
            + bytes.fromhex('001e0001000a') + frame + bytes.fromhex('0098')
            + pixmap + palette + frame * 2 + b'\0\0'
            + bytes([9, 7, 0, 1, 0, 0, 0, 0, 0, 0]) + b'\0\xff')


def test_duplicate_legacy_header_decodes_complete_picture():
    data = picture()
    decoded = convert_pict(ResourceInfo('synthetic', 'PICT', 1, '', len(data)), data)
    assert decoded.status == DecodeStatus.OK
    assert decoded.image.tobytes() == bytes([0, 0, 0, 255, 255, 255, 255, 255, 0, 0, 0, 255])
    assert [d.code for d in decoded.diagnostics] == ['pict.duplicate_legacy_header']
    assert decoded.byte_ranges == {'pict': [0, len(data)]}


def test_standard_legacy_header_remains_valid():
    assert _convert_indexed_packbits_pict(picture(False)) is not None


def decoded(data):
    return _convert_indexed_packbits_pict(normalize_pict(data)[0])


def test_duplicate_repair_does_not_hide_invalid_picture():
    for offset in (20, 48, 52):
        data = bytearray(picture())
        data[offset] ^= 1
        assert decoded(bytes(data)) is None
    assert decoded(picture()[:55]) is None
    assert decoded(picture()[:-2]) is None
    assert decoded(picture()[:-2] + b'\0\x30' + b'\0'*8 + b'\0\xff') is None


def test_repaired_picture_requires_native_success_without_platform_fallback():
    from unittest.mock import patch

    cases = [picture()[:-2], picture() + b'\0\0',
             picture()[:-2] + b'\0\x30' + b'\0'*8 + b'\0\xff']
    for data in cases:
        with patch('scripts.graphics_extract.pict.subprocess.run',
                   side_effect=AssertionError('platform fallback must not run')) as fallback:
            result = convert_pict(ResourceInfo('synthetic', 'PICT', 1, '', len(data)), data)
        assert result.status == DecodeStatus.FAILED
        assert result.image is None
        fallback.assert_not_called()
        assert result.diagnostics[-1].code == 'pict.unsupported_encoding'
