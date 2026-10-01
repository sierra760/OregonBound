"""Synthetic format cases; no external game files are required."""
import struct

import pytest

from scripts.extract_wst import parse_wst_resource


def guide_table(entries):
    result = bytearray(struct.pack('>H', len(entries)))
    for entry in entries:
        if len(result) % 2:
            result.append(0)
        result.extend(struct.pack('>H', len(entry)))
        result.extend(entry)
    return bytes(result)


@pytest.mark.parametrize('entries', [
    [b'abc', b'XY', b'z'],
    [b'a' * 255, b'b' * 256, b'c' * 512],
    [b'one\x01two\x00', b'', b'last'],
    [b'', b'abc', b''],
    [],
])
def test_guide_uses_lengths_and_preserves_slots(entries):
    parsed = parse_wst_resource(guide_table(entries), 12, 'Synthetic')
    assert parsed['entry_count'] == len(entries)
    assert parsed['entries'] == [
        {'index': index, 'text': entry.decode('mac_roman')}
        for index, entry in enumerate(entries)
    ]


@pytest.mark.parametrize('payload', [
    b'', b'\x00', b'\x00\x01', b'\x00\x01\x00',
    b'\x00\x01\x00\x03ab',
    b'\x00\x02\x00\x01a\x00\x00',
])
def test_guide_rejects_truncated_count_length_or_text(payload):
    with pytest.raises(ValueError):
        parse_wst_resource(payload, 12, 'Synthetic')

from scripts.extract_snd import parse_snd_format1


def sound(command=0x8051):
    # Format 1, no synth entries, one command, header at byte 14.
    return (struct.pack('>HHHHHI', 1, 0, 1, command, 0, 14)
            + struct.pack('>IIIIIBB', 0, 3, 22050 << 16, 0, 3, 0, 60)
            + bytes([0, 128, 255]))


@pytest.mark.parametrize('command', [0x8050, 0x8051])
def test_sound_accepts_both_offset_command_forms(command):
    assert parse_snd_format1(sound(command)) == (22050, 8, bytes([0, 128, 255]))


@pytest.mark.parametrize('command', [0x0050, 0x0051])
def test_sound_rejects_pointer_commands(command):
    with pytest.raises(ValueError):
        parse_snd_format1(sound(command))


@pytest.mark.parametrize('payload', [
    b'\x00\x01\x00\x02\x00\x00',
    struct.pack('>HHH', 1, 0, 1),
    struct.pack('>HHHHHI', 1, 0, 1, 0x8051, 0, 0xFFFFFFFF),
])
def test_sound_rejects_truncated_tables_and_bad_offsets(payload):
    with pytest.raises(ValueError):
        parse_snd_format1(payload)
