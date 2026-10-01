"""CD Display's authored 8-bit-index to 16-color conversion."""
from dataclasses import dataclass, replace
import struct

from .models import DecodeStatus, PaletteInfo
from .palette import parse_color_table, build_palette_bytes


def initialized_bytes(code: bytes) -> bytes:
    """Decode CODE23's version-1 initialized data, without executing its code.

    Only the data stream is expanded; pointer relocations are irrelevant to the
    byte lookup table. Both input and expanded memory are bounded to 1 MiB.
    """
    if not 8 <= len(code) <= 1024 * 1024 or code[:6] != bytes.fromhex('48e77ff849fa'):
        raise ValueError('Unsupported CD initializer')
    header = 6 + struct.unpack_from('>h', code, 6)[0]
    if header < 8 or header + 16 > len(code):
        raise ValueError('Invalid CD initializer header')
    size, version, flags, start, end = struct.unpack_from('>IHHII', code, header)
    if not (0 < size <= 1024 * 1024 and version == 1 and flags == 0
            and 16 <= start < end <= len(code) - header):
        raise ValueError('Invalid CD initializer bounds or version')
    cursor, limit, destination = header + start, header + end, 0
    memory = bytearray(size)
    repeats = 1

    def byte():
        nonlocal cursor
        if cursor >= limit:
            raise ValueError('Truncated CD initializer stream')
        result = code[cursor]
        cursor += 1
        return result

    def number(depth=0):
        nonlocal repeats
        if depth >= 8:
            raise ValueError('Nested CD initializer repetition')
        first = byte()
        if first < 0x80:
            return first
        if first < 0xc0:
            return ((first & 0x3f) << 8) | byte()
        if first < 0xe0:
            return ((first & 0x1f) << 16) | (byte() << 8) | byte()
        if first < 0xf0:
            return (byte() << 24) | (byte() << 16) | (byte() << 8) | byte()
        repeats = number(depth + 1)
        second = number(depth + 1)
        # Match d0/d3 EXG: the recursive second call may itself change d3.
        value, repeats = repeats, second
        return value

    while True:
        repeats = 1
        operation = byte()
        count = (operation & 15) * 2
        if count == 0:
            count = number()
            if count == 0:
                if cursor != limit:
                    raise ValueError('Trailing CD initializer data')
                return bytes(memory)
        skip = (operation & 0xf0) >> 3
        if skip == 0:
            skip = number()
        if (count > size or skip > size or repeats < 1
                or repeats > (size - destination) // (skip + count)
                or repeats > (limit - cursor) // count):
            raise ValueError('CD initializer operation exceeds bounds')
        for _ in range(repeats):
            destination += skip
            memory[destination:destination + count] = code[cursor:cursor + count]
            destination += count
            cursor += count


@dataclass(frozen=True)
class CD16Palette:
    indices: bytes
    palette: bytes

    def __post_init__(self):
        if len(self.indices) != 256 or any(i > 15 for i in self.indices) or len(self.palette) != 768:
            raise ValueError('Invalid CD 16-color conversion')

    @classmethod
    def from_sources(cls, initializer: bytes, color_table: bytes):
        # CODE resources prepend a jump-table offset and entry count to code.
        if len(initializer) < 4 or struct.unpack_from('>H', initializer, 2)[0] != 1:
            raise ValueError('Unsupported CD initializer segment')
        memory = initialized_bytes(initializer[4:])
        if len(memory) < 0x2312:
            raise ValueError('CD initializer does not contain the color-index table')
        if len(color_table) != 136 or struct.unpack_from('>HH', color_table, 4) != (0x8000, 15):
            raise ValueError('Invalid CD 16-color palette')
        start = len(memory) - 0x2312
        return cls(memory[start:start + 256], build_palette_bytes(parse_color_table(color_table)))

    def convert(self, record):
        if record.resource.resource_type != 'Ima4' or record.image is None or record.image.mode != 'P' or 'transparency' in record.image.info:
            raise ValueError('CD 16-color conversion requires an indexed Ima4 frame')
        image = record.image.point(list(self.indices))
        image.putpalette(self.palette)
        diagnostics = [d for d in record.diagnostics if d.code != 'imag.palette_fallback']
        status = record.status
        if status == DecodeStatus.PARTIAL and not any(d.severity in ('warning', 'error') for d in diagnostics):
            status = DecodeStatus.OK
        return replace(record, image=image, status=status, diagnostics=diagnostics,
                       palette=PaletteInfo('cd_16_color', 16, 1004))
