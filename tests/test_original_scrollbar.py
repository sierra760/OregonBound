from pathlib import Path
import hashlib
import json
import struct
import macresources
from macresources.greggybits import unpack
from capstone import Cs, CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def code(segment):
    return next((ROOT / 'assets/code_segments').glob(f'CODE_{segment}_*')).read_bytes()


def ops(data, start, end):
    md = Cs(CS_ARCH_M68K, CS_MODE_BIG_ENDIAN | CS_MODE_M68K_000)
    return {i.address: (i.mnemonic, i.op_str) for i in md.disasm(data[start:end], start)}


def test_resource_selects_system_scrollbar_not_an_application_cdef():
    resources = {(r.type, r.id): bytes(r) for r in macresources.parse_file((ROOT / 'raw/oregon_trail.rsrc').read_bytes())}
    control = resources[b'CNTL', 5500]
    assert struct.unpack_from('>hhhh', control) == (-1, 247, 103, 263)
    assert struct.unpack_from('>h', control, 16)[0] == 16
    assert {rid for kind, rid in resources if kind == b'CDEF'} == {8, 10, 14}
    assert struct.unpack_from('>4H', code(0), 0xb4a - 0x12) == (2, 0x3f3c, 14, 0xa9f0)
    assert struct.unpack_from('>4H', code(0), 0xb5a - 0x12) == (0x3e6, 0x3f3c, 14, 0xa9f0)


def test_journal_source_confirms_page_overlap_and_strict_append_deadline():
    c = code(14)
    actions = ops(c, 0x456, 0x46c)
    assert actions[0x45e] == ('subq.l', '#$7, d7')
    assert actions[0x46a] == ('addq.l', '#$7, d7')
    assert ops(c, 0x100c, 0x102a)[0x1016] == ('subq.l', '#$8, d0')
    follow = ops(c, 0x1174, 0x11ac)
    assert follow[0x1178] == ('ble.b', '$11ac') # No new records, no timeout-follow.
    assert follow[0x117e] == ('add.l', '#$384, d0')
    assert follow[0x1190] == ('bls.b', '$11ac') # Strict unsigned tick > deadline.
    assert ops(c, 0x11e4, 0x11ec)[0x11e8] == ('move.l', '(a7)+, -$1db4(a5)')


def test_system_cdef_provenance_and_geometry_instructions():
    folder = ROOT / 'assets/system_controls'
    manifest = json.loads((folder / 'system7_scrollbar.json').read_text())
    c = (folder / 'system7_cdef_1_unpacked.bin').read_bytes()
    assert c == unpack((folder / 'system7_cdef_1.bin').read_bytes())
    assert hashlib.sha256(c).hexdigest() == manifest['unpacked_sha256']
    assert len(c) == 3946
    geometry = ops(c, 0x58e, 0x5fe)
    assert [geometry[a] for a in (0x5ac, 0x5ae, 0x5b0)] == [('sub.w', 'd2, d1')] * 3
    assert geometry[0x5de] == ('move.w', 'd1, $4(a1, d0.w)')
    rounding = ops(c, 0x79c, 0x7b4)
    assert rounding[0x7a0] == ('lsr.w', '#$1, d0')
    assert rounding[0x7a6] == ('ble.b', '$7b0') # Half ties downward.
    hits = ops(c, 0x632, 0x64e)
    assert hits[0x63c] == ('bgt.b', '$642') # <= thickness is arrow, including boundary.
    assert hits[0x64a] == ('bgt.b', '$654')


def test_original_art_is_lossless_embedded_monochrome_data():
    folder = ROOT / 'assets/system_controls'
    c = (folder / 'system7_cdef_1_unpacked.bin').read_bytes()
    manifest = json.loads((folder / 'system7_scrollbar.json').read_text())
    atlas = Image.open(folder / manifest['atlas_file']).convert('RGBA')
    assert atlas.size == (160, 16)
    assert len(manifest['monochrome_bitmaps']) == 10
    for record in manifest['monochrome_bitmaps']:
        index = record['index']
        offset = 0xdb2 + struct.unpack_from('>h', c, 0xdb2 + 2 * index)[0]
        assert offset == record['offset']
        assert struct.unpack_from('>Hhhhh', c, offset) == (2, 0, 0, 16, 16)
        for y in range(16):
            word = struct.unpack_from('>H', c, offset + 10 + y * 2)[0]
            for x in range(16):
                expected = (0, 0, 0, 255) if word & (0x8000 >> x) else (255, 255, 255, 255)
                assert atlas.getpixel((index * 16 + x, y)) == expected
