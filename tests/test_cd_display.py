import struct
import pytest
from PIL import Image
from scripts.graphics_extract.cd_display import CD16Palette, initialized_bytes
from scripts.graphics_extract.models import DecodeImage, DecodeStatus, ResourceInfo, DecodeDiagnostic


def initializer(stream, size=0x2400, header=32):
    data = bytearray(header)
    data[:8] = bytes.fromhex('48e77ff849fa') + struct.pack('>h', header - 6)
    data += struct.pack('>IHHII', size, 1, 0, 16, 16 + len(stream)) + stream
    return bytes(data)


def clut():
    return struct.pack('>IHH', 0, 0x8000, 15) + b''.join(
        struct.pack('>HHHH', 0x8000, i * 0x1100, (15-i) * 0x1100, 0) for i in range(16))


def context():
    indices = bytes(i % 16 for i in range(256))
    stream = b'\x00\x81\x00\x80\xee' + indices + b'\x00\x00'
    return CD16Palette.from_sources(b'\x00\x20\x00\x01' + initializer(stream), clut())


@pytest.mark.parametrize('number', [b'\x02', b'\x80\x02', b'\xc0\x00\x02', b'\xe0\0\0\0\x02'])
def test_initializer_number_widths(number):
    assert initialized_bytes(initializer(b'\x00' + number + b'\x00ab\x00\x00', size=8)) == b'ab' + bytes(6)


def test_initializer_repetitions_use_distinct_literals_and_repeat_skip():
    stream = b'\x00\xf0\x02\x03\x01abcdef\x00\x00'
    assert initialized_bytes(initializer(stream, size=10)) == b'\0ab\0cd\0ef\0'
    assert initialized_bytes(initializer(b'\x11ab\x00\x00', size=5)) == b'\0\0ab\0'


@pytest.mark.parametrize('stream', [b'', b'\x00', b'\x00\x02\x00a', b'\x00\x02\x08ab\0\0',
    b'\x00\xf0\x02\x00\x00ab\0\0', b'\x00\xf0\x02\x7f\x00ab\0\0',
    b'\x00' + b'\xf0'*10, b'\0\0garbage'])
def test_initializer_rejects_invalid_stream(stream):
    with pytest.raises(ValueError):
        initialized_bytes(initializer(stream, size=8))


def test_context_uses_authored_indices_and_preserves_odd_width_geometry():
    palette = context()
    image = Image.frombytes('P', (3, 2), bytes([0, 17, 255, 34, 3, 132]))
    record = DecodeImage(ResourceInfo('synthetic', 'Ima4', 7, '', 99), DecodeStatus.PARTIAL,
        None, 3, 2, 'P', palette=None, byte_ranges={'pixels': [2, 99]}, image=image,
        bounds=[4, 5, 6, 8], diagnostics=[DecodeDiagnostic('warning', 'imag.palette_fallback', 'unused')])
    output = palette.convert(record)
    assert output.image.tobytes() == bytes([0, 1, 15, 2, 3, 4])
    assert output.image.getpalette()[:48] == [v for i in range(16) for v in (i*17, (15-i)*17, 0)]
    assert output.status == DecodeStatus.OK and output.diagnostics == []
    assert output.bounds == [4, 5, 6, 8] and output.byte_ranges == {'pixels': [2, 99]}
    assert output.resource.raw_length == 99 and output.palette.entry_count == 16


@pytest.mark.parametrize('kind', ['size', 'version', 'flags', 'header', 'start', 'end', 'map', 'palette'])
def test_context_rejects_invalid_sources(kind):
    data = bytearray(initializer(b'\x00\x81\x00\x80\xee' + bytes(i%16 for i in range(256)) + b'\0\0'))
    colors = clut()
    if kind == 'size': struct.pack_into('>I', data, 32, 0xffffffff)
    elif kind == 'version': data[37] = 2
    elif kind == 'flags': data[39] = 1
    elif kind == 'header': data[4] = 0
    elif kind == 'start': struct.pack_into('>I', data, 40, 15)
    elif kind == 'end': struct.pack_into('>I', data, 44, 0xffffffff)
    elif kind == 'map': data[53] = 16
    else: colors = colors[:-1]
    with pytest.raises(ValueError): CD16Palette.from_sources(b'\x00\x20\x00\x01' + bytes(data), colors)


def test_extractor_converts_only_alternate_artwork(tmp_path):
    import macresources
    from scripts import extract_graphics
    pixmap = bytearray(50)
    struct.pack_into('>Hhhhh', pixmap, 4, 0x8004, 4, 5, 6, 8)
    struct.pack_into('>H', pixmap, 32, 8)
    struct.pack_into('>I', pixmap, 42, 0xffffffff)
    stream = struct.pack('<HHB', 4, 2, 1) + bytes([0xc0,0,17,255,7,0xc0,34,3,132,7])
    payload = struct.pack('>HI', 1, 54+len(stream)) + pixmap + stream
    source = tmp_path / 'input'
    source.write_bytes(macresources.make_file([
        macresources.Resource(type=t, id=7, name='Synthetic', data=payload) for t in [b'Imag', b'Ima4']]))
    manifest = extract_graphics.extract(source, tmp_path / 'out', strict=True, expected_counts={}, cd16_palette=context())
    frames = {r.resource.resource_type: r for r in manifest.images}
    assert Image.open(tmp_path / 'out' / frames['Ima4'].image_path).tobytes() == bytes([0,1,15,2,3,4])
    assert Image.open(tmp_path / 'out' / frames['Imag'].image_path).tobytes() == bytes([0,17,255,34,3,132])
    assert frames['Ima4'].bounds == frames['Imag'].bounds == [4,5,6,8]
    assert frames['Ima4'].palette.source == 'cd_16_color'


def test_nested_repeat_number_preserves_original_register_exchange():
    # CODE23:00d2–00d8: the nested second number changes d3 before EXG.
    stream = b'\x00\xf0\x02\xf0\x03\x04\x00abcdefghijkl\x00\x00'
    assert initialized_bytes(initializer(stream, size=12)) == b'abcdefghijkl'
