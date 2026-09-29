"""Instruction/resource evidence for original display palettes, not an OS emulator."""
from pathlib import Path
import struct
import sys
import macresources
from capstone import Cs, CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from extract_a5 import decode_initial_data


def code(segment):
    return next((ROOT/'assets/code_segments').glob(f'CODE_{segment}_*')).read_bytes()


def ops(start,end):
    md=Cs(CS_ARCH_M68K,CS_MODE_BIG_ENDIAN|CS_MODE_M68K_000)
    return {i.address:(i.mnemonic,i.op_str) for i in md.disasm(code(5)[start:end],start)}


def colors(resource_id):
    r=next(r for r in macresources.parse_file((ROOT/'raw/oregon_color.rsrc').read_bytes())
           if r.type==b'clut' and r.id==resource_id)
    data=bytes(r.data)
    seed,flags,last=struct.unpack_from('>IHH',data)
    assert flags == 0x8000
    entries=[struct.unpack_from('>4H',data,8+i*8) for i in range(last+1)]
    assert all(e[0]==0x8000 for e in entries)
    return [e[1:] for e in entries]


def test_installs_game_table_with_tolerant_zero_tolerance_and_explicit_when_supported():
    i=ops(0x1e24,0x1eb8)
    assert i[0x1e32]==('moveq','#$a, d7')
    assert i[0x1e36]==('moveq','#$2, d7')
    assert i[0x1e46]==('move.w','#$3ec, -(a7)')
    assert i[0x1e4e]==('moveq','#$10, d6')
    assert i[0x1e60]==('move.w','#$3f0, -(a7)')
    assert i[0x1e6a]==('move.w','$6(a0), d6')
    assert i[0x1e8c]==('move.w','d6, -(a7)')
    assert i[0x1e90]==('move.w','d7, -(a7)')
    assert i[0x1e92]==('moveq','#$0, d0')
    assert i[0x1e94]==('move.w','d0, -(a7)')
    for offset,trap in [(0x1e96,0xaa91),(0x1ea8,0xaa95),(0x1eae,0xaa94)]:
        assert struct.unpack_from('>H',code(5),offset)[0]==trap
    assert len(colors(1004))==16
    assert len(colors(1008))==235


def test_paper_is_exact_installed_color_not_approximate_nearest_candidate():
    a5=decode_initial_data(code(21))
    paper=struct.unpack_from('>3H',a5,len(a5)-0x2b88)
    assert paper==(65280,63085,35223)
    assert tuple(v>>8 for v in paper)==(255,246,137)
    assert [i for i,c in enumerate(colors(1004)) if c==paper]==[6]
    assert [i for i,c in enumerate(colors(1008)) if c==paper]==list(range(82,90))
    cell=lambda c:tuple(v>>12 for v in c)
    assert {c for c in colors(1008) if cell(c)==cell(paper)}=={paper}
    assert ops(0x1fd2,0x1fde)[0x1fd8]==('pea.l','-$2b88(a5)')
    assert code(5)[0x1fdc:0x1fde]==bytes.fromhex('aa15')


def test_raft_fills_have_exact_colors_in_game_palette():
    for color in [(9728,51456,65280),(0,0,65280)]:
        assert color in colors(1008)[:234]


def test_direct_palette_animation_traps_are_bounded():
    actual=[]
    for p in (ROOT/'assets/code_segments').glob('CODE_*'):
        data=p.read_bytes()
        actual += [(int(p.name.split('_')[1]),i) for i in range(0,len(data)-1,2)
                   if data[i:i+2]==bytes.fromhex('aa3f')]
    assert sorted(actual)==[(1,0x4148),(3,0xac),(3,0x10c)]
