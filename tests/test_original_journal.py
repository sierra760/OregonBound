from pathlib import Path
import json
import re
import struct
import macresources
from capstone import Cs, CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000

ROOT=Path(__file__).resolve().parents[1]


def code(segment):
    return next((ROOT/'assets/code_segments').glob(f'CODE_{segment}_*')).read_bytes()


def ops(segment,start,end):
    md=Cs(CS_ARCH_M68K,CS_MODE_BIG_ENDIAN|CS_MODE_M68K_000)
    return {i.address:(i.mnemonic,i.op_str) for i in md.disasm(code(segment)[start:end],start)}


def test_punctuation_is_literal_A_through_y_and_append_has_byte_capacity():
    i=ops(14,0x1890,0x18bc)
    assert i[0x189a]==('moveq','#$41, d0')
    assert i[0x189e]==('bhi.b','$18bc')
    assert i[0x18aa]==('moveq','#$7a, d0')
    assert i[0x18ae]==('bls.b','$18bc')
    assert i[0x18b0]==('moveq','#$2e, d0')
    assert i[0x18b6]==('jsr','$1bfa(pc)')
    assert ops(14,0x1c04,0x1c10)[0x1c08]==('cmpi.l','#$ff, d0')


def test_supply_join_inserts_and_after_last_comma_without_replacing_it():
    i=ops(14,0x26a8,0x26d4)
    assert i[0x26aa]==('jsr','$1d38(pc)')
    assert i[0x26bc]==('move.w','#$5dc, -(a7)')
    assert i[0x26c0]==('moveq','#$5, d0')
    assert i[0x26ce]==('move.b','d7, -(a7)')
    assert i[0x26d0]==('jsr','$102(a5)')
    assert struct.unpack_from('>4H',code(0),0x102-0x12)==(0xe0e,0x3f3c,1,0xa9f0)
    insertion=ops(1,0xe16,0xe2e)
    assert insertion[0xe24]==('moveq','#$0, d0') # zero replaced characters
    assert insertion[0xe2a]==('jsr','$1e(pc)')
    find=ops(14,0x1d56,0x1d6c)
    assert find[0x1d5a]==('moveq','#$2c, d1')
    assert find[0x1d66]==('moveq','#$20, d1')


def test_hunt_gate_uses_exact_weather_distance_and_signed_ammo_in_order():
    i=ops(6,0x1c1e,0x1c5a)
    assert i[0x1c24]==('move.b','$22d(a0), d0')
    assert i[0x1c28]==('moveq','#$7, d1')
    assert i[0x1c2c]==('bgt.b','$1c3a')
    assert i[0x1c56]==('jsr','$96e(pc)')
    assert ops(6,0x970,0x982)[0x976]==('move.b','$239(a0), d0')
    ammo=ops(6,0x9ca,0x9e2)
    assert ammo[0x9ca]==('move.w','$4a(a3), d0')
    assert ammo[0x9ce]==('ext.l','d0')
    assert ammo[0x9d0]==('bgt.b','$9e2')


def test_river_begin_does_not_clear_rest_and_vbl_admits_it_under_modal_flag():
    i=ops(16,0x150c,0x1516)
    assert i[0x150c]==('ori.b','#$8, $1(a3)')
    assert i[0x1512]==('bra.w','$17ac')
    rest=ops(16,0x1e2e,0x1e42)
    assert rest[0x1e38]==('moveq','#$4, d1')
    assert rest[0x1e3c]==('beq.b','$1e48')
    assert rest[0x1e3e]==('jsr','$1a9a(pc)')


def test_embedded_journal_tables_are_literal_original_resources():
    text=(ROOT/'OregonBound/OregonBound/Engine/OriginalJournalRules.swift').read_text()
    expected={}
    for r in macresources.parse_file((ROOT/'raw/oregon_trail.rsrc').read_bytes()):
        if r.type!=b'STR#':continue
        data=bytes(r.data);pos=2;strings=[]
        for _ in range(int.from_bytes(data[:2],'big')):
            n=data[pos];pos+=1;strings.append(data[pos:pos+n].decode('macroman'));pos+=n
        expected[r.id]=strings
    found=set()
    for resource,body in re.findall(r'^        (\d+): \[\n(.*?)^        \],',text,re.M|re.S):
        actual=[json.loads(line.strip().rstrip(',')) for line in body.splitlines()]
        assert actual==expected[int(resource)]
        found.add(int(resource))
    assert found=={1500,1501,1502,1503,1507,1522,1523,3009,3010,3011}


def test_raft_member_index_is_packed_into_drowning_count_and_zero_is_singular():
    caller=ops(16,0x14de,0x14f6)
    assert caller[0x14e0]==('moveq','#$35, d0')
    assert caller[0x14e4]==('ext.l','d7')
    assert caller[0x14e6]==('move.l','d7, -(a7)')
    death=ops(16,0x1b3c,0x1b58)
    assert death[0x1b40]==('ext.l','d6')
    assert death[0x1b50]==('jsr','$294a(pc)')
    packing=ops(16,0x296a,0x2984)
    assert packing[0x2978]==('move.b','$13(a6), d1')
    assert packing[0x297c]==('lsl.l','#$5, d1')
    assert packing[0x2980]==('move.b','d1, -$1(a6)')
    display=ops(14,0x1e96,0x1ee2)
    assert display[0x1e98]==('move.b','$1(a3), d0')
    assert display[0x1e9c]==('lsr.l','#$5, d0')
    assert display[0x1ec0]==('moveq','#$1, d0')
    assert display[0x1ec6]==('bge.b','$1ed6') # one >= count selects singular
