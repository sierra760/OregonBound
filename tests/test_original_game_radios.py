"""Pin supplied game resources and CODE anchors, independently of Swift geometry.

Run staged copy with OREGON_SOURCE_ROOT pointing at the repository.
CODE offsets address the extracted segments after their four-byte headers.
"""
from pathlib import Path
import os
import struct
import macresources

ROOT = Path(os.environ.get('OREGON_SOURCE_ROOT', Path(__file__).resolve().parents[1]))


def resources():
    return {(r.type, r.id): bytes(r) for r in macresources.parse_file(
        (ROOT / 'raw/oregon_trail.rsrc').read_bytes())}


def items(data):
    cursor = 2
    result = []
    for _ in range(struct.unpack_from('>H', data)[0] + 1):
        rect = struct.unpack_from('>4h', data, cursor + 4)
        kind, length = data[cursor + 12:cursor + 14]
        payload = data[cursor + 14:cursor + 14 + length]
        result.append((rect, kind, payload))
        cursor += 14 + length + (length & 1)
    assert cursor == len(data)
    return result


def code(segment):
    return next((ROOT / 'assets/code_segments').glob(f'CODE_{segment}_*.bin')).read_bytes()


def anchor(segment, offset, expected):
    expected = bytes.fromhex(expected)
    assert code(segment)[offset:offset + len(expected)] == expected


def test_raw_registration_radio_group_and_controls():
    rs = resources()
    parent = items(rs[b'DITL', 9020])
    assert parent[6] == ((116, 26, 299, 227), 128, b'')
    assert parent[7] == ((116, 31, 294, 223), 0, b'')
    names = [b'Banker', b'Blacksmith', b'Carpenter', b'Doctor', b'Farmer',
             b'Merchant', b'Saddlemaker', b'Teacher']
    assert items(rs[b'DITL', 9022]) == [
        ((15 + 20*i, 15, 35 + 20*i, 130), 6, name)
        for i, name in enumerate(names)]
    # CODE19 embeds resource9022 on item8 using the generic group handler.
    anchor(19, 0x870, '2f3c010d233e486d081270082f002f2e00084ead0832')


def test_raw_trade_radio_group_preserves_overlapping_authored_rectangles():
    rs = resources()
    assert items(rs[b'DITL', 6120])[3] == ((24, 112, 160, 256), 0, b'')
    labels = [b'ox(en)', b'set(s) of clothing', b'bullets', b'wagon wheel(s)',
              b'wagon axle(s)', b'wagon tongue(s)', b'pounds of food', b'$ (dollars cash)']
    assert items(rs[b'DITL', 6121]) == [
        ((17*i, 0, 17*i + 18, 134), 6, label)
        for i, label in enumerate(labels)]
    anchor(3, 0x4b9e, '2f3c010a17e9486d081270042f002f0c4ead0832426df4f4')


def test_first_selection_and_zero_based_model_writes():
    # Generic group chooses DITL item1, not the reversed display-list head.
    anchor(5, 0x467a, '70012f002f0c4eba058e264020532f28001470013f00a963')
    anchor(19, 0x90a, '422dd879')  # clear occupation byte A5-2787
    anchor(19, 0x9da, '206e000c3028000248c053801b40d879')  # item-1 -> byte
    anchor(3, 0x4c28, '206e000c3028000248c053803b40f4f4')  # item-1 -> word A5-b0c


def test_radio_paper_comes_from_game_window_color_table():
    data = resources()[b'wctb', 1000]
    assert struct.unpack_from('>H', data, 6)[0] == 4
    colors = {entry: (r, g, b) for entry, r, g, b in struct.iter_unpack('>4H', data[8:])}
    assert colors == {0: (0xff00, 0xf66d, 0x8997), 1: (0, 0, 0),
                      2: (0, 0, 0), 3: (0, 0, 0), 4: (65535, 65535, 65535)}
    # GetNewCWindow1000 associates this wctb with the game window.
    anchor(9, 0x272, '598f3f3c03e82f2dd92470ff2f00aa46')
    cdef = (ROOT / 'raw/system7/cdef_0_unpacked.bin').read_bytes()
    for offset, expected in [
        (0x7e, '42a74227206e000e20502f280004486f0006aa42'),  # GetAuxWin(owner)
        (0x15c, '4a066706486effd46016'),  # radio variant chooses window background
        (0x468, '4a2effea6706486effd4aa15'),  # RGBBackColor before marker erase
    ]:
        data = bytes.fromhex(expected)
        assert cdef[offset:offset + len(data)] == data


def test_registration_frame_installs_gray_pattern_and_restores_pen():
    # CODE19 passes qd.gray (A5-019a) and callback A5+07ea to item7.
    anchor(19, 0x85c, '486dfe66486d07ea70072f002f2e00084ead0832')
    # The CODE0 jump entry resolves A5+07ea to CODE5:4026.
    assert struct.unpack_from('>4H', code(0), 0x7ea - 0x12) == (0x4026, 0x3f3c, 5, 0xa9f0)
    # GetPenState; PenNormal; PenPat(item+14); FrameRect; SetPenState.
    anchor(5, 0x408c, '486effeea898a89e2053206800142f08a89d486effe6a8a1486effeea899')
