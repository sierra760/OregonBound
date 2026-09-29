"""Binary-backed CODE6 save-layout extraction; no native Journey mapping."""
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]


def recover_layout(code: bytes | None = None):
    if code is None:
        code = (ROOT / 'assets/code_segments/CODE_6_Main3.bin').read_bytes()
    def word(offset):
        return struct.unpack_from('>H', code, offset)[0]
    def long(offset):
        return struct.unpack_from('>I', code, offset)[0]
    anchors = {
        0x019c: '20bc', 0x01a6: '317c', 0x01b4: '4868',
        0x01c0: '316dd872', 0x01ce: '43e9', 0x01d2: '303c',
        0x01d6: '22d851c8fffc32d8', 0x01e2: '41e8',
        0x01ea: '700720d951c8fffc30d9',
        0x0652: '2d7c', 0x0696: '2d7c',
        0x0446: '2f3c', 0x044c: '2f3c',
    }
    for offset, expected in anchors.items():
        raw = bytes.fromhex(expected)
        if code[offset:offset + len(raw)] != raw:
            raise ValueError(f'Original instruction changed at CODE6:{offset:04x}')
    first = long(0x0654)
    journal = long(0x0698)
    world = word(0x01d0)
    world_size = (word(0x01d4) + 1) * 4 + 2
    state = word(0x01e4)
    return dict(magic=long(0x019e), version=word(0x01a8), label_offset=word(0x01b6),
                header_word_offset=word(0x01c4), world_offset=world, world_size=world_size,
                journal_state_offset=state, journal_state_size=(code[0x01eb] + 1) * 4 + 2,
                journal_offset=first, journal_size=journal, file_size=first + journal,
                creator=long(0x0448), file_type=long(0x044e))
