"""Synthetic fixtures for the column-compressed one-bit Imag variant."""
import struct
from scripts.graphics_extract.imag import decode_imag
from scripts.graphics_extract.models import DecodeStatus, ResourceInfo
import pytest


COMMANDS = bytes([2, 0x80, 0, 0xFE, 0xFF, 0xBE, 0, 0x80])
EXPECTED = bytes([0] + [255] * 8 + [255] * 8 + [0] + [0] * 8 + [255] + [0] * 9)


def frame(commands=COMMANDS, width=9, height=4, stride=2):
    header = struct.pack('>IHhhhh', 0, stride, 3, 5, 3 + height, 5 + width)
    return struct.pack('>I', 18 + len(commands)) + header + commands


def decode(*frames, count=None):
    payload = struct.pack('>H', len(frames) if count is None else count) + b''.join(frames)
    info = ResourceInfo('synthetic', 'Imag', 123, 'Columns', len(payload))
    return decode_imag(info, payload, bytes(768), 'synthetic')


def test_column_commands_and_crop():
    records = decode(frame())
    assert len(records) == 1
    result = records[0]
    assert result.status == DecodeStatus.OK
    assert (result.width, result.height, result.mode) == (9, 4, 'L')
    assert result.image.tobytes() == EXPECTED
    assert result.palette is None
    assert result.byte_ranges['pixels'] == [20, 28]
    assert (result.frame_index, result.frame_count) == (0, 1)


def test_declared_boundaries_skip_padding_and_allow_zero_control():
    records = decode(frame(COMMANDS + b'\x00'), frame(b'\x00' + COMMANDS))
    assert len(records) == 2
    assert all(r.status == DecodeStatus.OK for r in records)
    assert [r.image.tobytes() for r in records] == [EXPECTED, EXPECTED]
    assert [r.byte_ranges['pixels'] for r in records] == [[20, 28], [47, 56]]
    assert [r.frame_index for r in records] == [0, 1]


@pytest.mark.parametrize('commands', [b'', b'\x02\x80', b'\xbe\x00', b'\xfc', b'\x05' + bytes(5), b'\xbb\x00\x80', b'\x00'])
def test_malformed_commands_fail(commands):
    result = decode(frame(commands))[0]
    assert result.status == DecodeStatus.FAILED
    assert result.image is None


def test_does_not_read_commands_from_next_frame():
    assert decode(frame(b'\x02\x80'), frame())[0].status == DecodeStatus.FAILED


@pytest.mark.parametrize('width,height,stride', [(17, 4, 2), (0, 4, 2), (9, 0, 2), (9, 4, 0), (32760, 32760, 4096)])
def test_invalid_dimensions_fail(width, height, stride):
    # Zero-origin bounds avoid signed-short overflow in the large fixture.
    header = struct.pack('>IHhhhh', 0, stride, 0, 0, height, width)
    result = decode(struct.pack('>I', 26) + header + COMMANDS)[0]
    assert result.status == DecodeStatus.FAILED


def test_partial_resource_reports_shortfall():
    records = decode(frame(), count=2)
    assert len(records) == 1
    assert records[0].status == DecodeStatus.PARTIAL
    assert records[0].image.tobytes() == EXPECTED
    assert 'imag.decoded_frame_shortfall' in [d.code for d in records[0].diagnostics]


@pytest.mark.parametrize('length', [0, 17, 27, 0xffffffff])
def test_invalid_declared_frame_length(length):
    payload = struct.pack('>I', length) + frame()[4:]
    assert decode(payload)[0].status == DecodeStatus.FAILED
