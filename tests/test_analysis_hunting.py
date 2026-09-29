from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from analysis_hunting import (read_tables, extract, initial_weights, choose_population,
    choose_species, spawn_attempt, spawn_origin, can_turn, deplete_population,
    earned_food, carried_food, Projectile, HitObject, impact_target,
    accepts_shot, timed_out, scenery_plan)


class Rolls:
    def __init__(self, values): self.values=iter(values); self.bounds=[]
    def __call__(self,bound):
        self.bounds.append(bound)
        value=next(self.values)
        assert 0 <= value < bound
        return value


def test_original_binary_tables_and_hunt_time_settings():
    t=read_tables()
    assert t['food_base']==[250,35,1,1,175,90,20]
    assert t['food_random_span']==[270,25,2,1,180,30,10]
    assert t['speed']==[3,8,9,7,6,4,10]
    assert t['frame_period']==[3,2,2,2,2,2,2]
    assert t['hunt_seconds_by_setting']==[0,20,30,45,60,90,120]
    assert [last-death for last,death in zip(t['last_frame'],t['death_frame_count'])]==[3,2,2,2,2,3,2]


def test_resources_and_original_buttons():
    result=extract()
    assert [i['data'] for i in result['dialog']['items'][:2]]==['Move','Stop Hunting']
    assert result['frames'][19160][3]['source_rect_tlbr']==[0,0,5,5]
    assert result['frames'][19161][0]['source_rect_tlbr']==[0,0,38,58]


@pytest.mark.parametrize('destination,month,expected',[
    (2,3,[15,25,40,40,0,0,0]),(3,4,[15,25,40,40,0,0,7]),
    (4,4,[15,25,40,40,8,0,20]),(6,4,[15,25,40,40,15,5,20]),
    (10,4,[8,10,40,40,15,5,20]),(12,4,[8,10,40,40,8,5,7]),
    (13,10,[8,10,40,40,8,10,0]),(14,11,[8,10,40,40,15,0,0]),
    (15,10,[8,25,40,40,15,10,0]),
])
def test_population_location_and_season_boundaries(destination,month,expected):
    assert initial_weights(destination,month,False)==expected
    repeated=initial_weights(destination,month,True)
    assert repeated[2:4]==[20,20]
    assert repeated[:2]+repeated[4:]==expected[:2]+expected[4:]


def test_population_pruning_rejections_and_random_order():
    rng=Rolls([0,2,6,0])
    assert choose_population(2,3,False,rng)==[0,25,0,40,0,0,0]
    assert rng.bounds==[2,7,7,7] # Rejected selections still consume RNG.
    rng=Rolls([0,1])
    assert choose_population(2,3,True,rng)==[0,0,20,20,0,0,0]
    assert rng.bounds==[7,7]


def test_weighted_selection_is_reverse_order():
    weights=[15,25,0,40,0,0,0]
    assert [choose_species(weights,r) for r in [0,39,40,64,65,79]]==[3,3,1,1,0,0]
    with pytest.raises(ValueError): choose_species(weights,80)


def test_spawn_gate_last_three_seconds_and_capacity():
    for repeated,bound in [(False,50),(True,150)]:
        rng=Rolls([7]); assert spawn_attempt(repeated_area=repeated,now_tick=10,end_tick=191,living=1,kills_in_scene=3,random=rng)
        assert rng.bounds==[bound]
    for changes in [dict(end_tick=190),dict(living=2),dict(kills_in_scene=4)]:
        args=dict(repeated_area=False,now_tick=10,end_tick=191,living=1,kills_in_scene=3)
        args.update(changes); rng=Rolls([7]); assert not spawn_attempt(**args,random=rng)
        assert rng.bounds==[50]


def test_spawn_origins_and_turnaround_boundaries():
    rng=Rolls([0,127])
    assert spawn_origin(58,38,True,rng)==(-49,59)
    assert spawn_origin(58,38,False,rng)==(503,186)
    assert rng.bounds==[128,128]
    assert can_turn(9,503,0) and can_turn(9,503,1)
    assert not can_turn(8,503,0) and not can_turn(9,504,0) and not can_turn(9,503,2)


def test_projectile_travels_then_resolves_one_update_later():
    p=Projectile(96,68) # Chebyshev160/20=8 updates; no instant hit at click.
    assert p.remaining==8
    for i in range(1,9):
        assert not p.step()
        assert (p.x,p.y)==(256-20*i,228-20*i)
    assert not p.resolved
    assert p.step() and p.resolved
    assert not p.step()
    close=Projectile(250,227)
    assert (close.x,close.y,close.remaining)==(250,227,0)
    assert close.step()


def test_projectile_signed_fractional_rounding():
    p=Projectile(201,187) # duration2: delta(-55,-41), ties round toward positive.
    assert not p.step(); assert (p.x,p.y)==(229,208)
    assert not p.step(); assert (p.x,p.y)==(201,187)
    assert p.step()


def test_hit_rect_order_occlusion_and_half_open_edges():
    animal=HitObject(-8,(50,50,100,100))
    tree=HitObject(2,(50,50,100,100))
    corpse=HitObject(3,(50,50,100,100))
    assert impact_target(50,50,[corpse,tree,animal])==1
    assert impact_target(50,50,[animal,tree])==0
    assert impact_target(100,99,[animal]) is None
    assert impact_target(99,100,[animal]) is None
    assert impact_target(99,99,[animal])==0


def test_food_ranges_and_depletion():
    tables=read_tables()
    assert [earned_food(i,tables,lambda n:0) for i in range(7)]==[250,35,1,1,175,90,20]
    assert [earned_food(i,tables,lambda n:n-1) for i in range(7)]==[519,59,2,1,354,119,29]
    assert deplete_population([3,0,20,40,0,0,0],0,False)[0]==2
    assert deplete_population([2,0,20,40,0,0,0],0,False)[0]==0
    assert deplete_population([2,0,20,40,0,0,0],0,True)[0]==1
    assert deplete_population([2,0,20,40,0,0,0],2,False)[2]==20
    assert carried_food(500,1,0,2000)==100
    assert carried_food(500,2,0,2000)==200
    assert carried_food(500,2,1995,2000)==5


def test_bullet_limit_and_timeout_wait_for_inflight_shot():
    assert accepts_shot(100,19,False)
    assert not accepts_shot(100,20,False)
    assert not accepts_shot(4,4,False)
    assert not accepts_shot(100,0,True)
    assert not timed_out(100,100,False)
    assert not timed_out(101,100,True)
    assert timed_out(101,100,False)


def test_machine_bytes_pin_core_instruction_evidence():
    code=(ROOT/'assets/code_segments/CODE_13_Hunt.bin').read_bytes()
    assert code[0xec6:0xec8]==bytes.fromhex('5680') # addq.l3 deadline
    assert code[0x1742:0x1748]==bytes.fromhex('72144ead0262') # projectile divide20
    assert code[0x1992:0x1998]==bytes.fromhex('3b7c0014db24') # carried bullets20


def test_scenery_argument_order_and_unused_group_still_consumes_count_roll():
    frames=extract()['frames'][19160]
    sizes=[(f['source_rect_tlbr'][3],f['source_rect_tlbr'][2]) for f in frames]
    rng=Rolls([0,0,0,0,0,0,0,0])
    plan=scenery_plan(6,4,False,False,rng,sizes)
    assert plan==[{'frame':4,'kind':2,'x':9,'y':59},{'frame':9,'kind':2,'x':9,'y':59}]
    assert rng.bounds==[3,2,431,136,3,3,444,75]
    rng=Rolls([0,0,0,0,0,0,0,0,0,0,0,0,0,0])
    assert len(scenery_plan(4,4,False,True,rng,sizes))==4
    assert rng.bounds[-1]==1 # group2 count is called even though no trees are created.


def test_production_swift_tables_and_geometry_match_binary():
    import re
    swift=(ROOT/'OregonBound/OregonBound/Engine/OriginalHuntSession.swift').read_text()
    mapping={'food_random_span':'foodSpan','food_base':'foodBase','frame_period':'period',
             'speed':'speed','death_frame_count':'deathCount','last_frame':'lastFrame',
             'hunt_seconds_by_setting':'seconds'}
    for name,expected in read_tables().items():
        found=re.search(r'static let '+mapping[name]+r' = \[([^\]]+)\]',swift)
        assert [int(x) for x in found.group(1).split(',')]==expected
    original=extract()['frames']
    for name,expected in [('scenerySizes',original[19160]),('animalSizes',[original[i][0] for i in range(19161,19168)])]:
        found=re.search(r'static let '+name+r' = \[([^\]]+)\]',swift)
        sizes=[tuple(map(int,pair)) for pair in re.findall(r'\((\d+),(\d+)\)',found.group(1))]
        assert sizes==[(r['source_rect_tlbr'][3],r['source_rect_tlbr'][2]) for r in expected]


def test_original_color_flag_and_default_configuration():
    import macresources
    import struct
    from extract_a5 import decode_initial_data
    resources = list(macresources.parse_file((ROOT/'raw/oregon_trail.rsrc').read_bytes()))
    conf = bytes(next(r.data for r in resources if r.type == b'CONF' and r.id == 1000))
    # CODE8:1090 copies CONF+26 to A5-2a7a; CODE16:594 copies -296a to world+247.
    setting = conf[0x26+0x2a7a-0x296a]
    assert setting == 3
    assert read_tables()['hunt_seconds_by_setting'][setting] == 45
    memory = decode_initial_data((ROOT/'assets/code_segments/CODE_21_A5Init.bin').read_bytes())
    assert struct.unpack_from('>h',memory,len(memory)-0x2392)[0] == 0
    code = (ROOT/'assets/code_segments/CODE_5_Display.bin').read_bytes()
    assert code[0x1712:0x1718].hex() == '1b6dd912d490' # color-resource-open flag copied
    assert code[0x1816:0x1822].hex() == '4a2dd490670270011b40d48a' # color && depth!=1
    code = (ROOT/'assets/code_segments/CODE_6_Main3.bin').read_bytes()
    assert code[0xa78:0xa7c].hex() == '48780258' # outcome panel600 ticks


def test_original_preparation_and_cursor_source(tmp_path):
    import macresources
    import re
    resources = list(macresources.parse_file((ROOT/'raw/oregon_trail.rsrc').read_bytes()))
    cursor = bytes(next(r.data for r in resources if r.type == b'CURS' and r.id == 128))
    from extract_runtime import extract_runtime
    extract_runtime(ROOT/'raw/oregon_trail.rsrc', tmp_path)
    assert (tmp_path/'runtime/curs_128.bin').read_bytes() == cursor
    assert cursor[-4:] == bytes.fromhex('00070007')
    assert sum(byte.bit_count() for byte in cursor[32:64]) == 132
    assert not any(data & ~mask for data,mask in zip(cursor[:32],cursor[32:64]))
    code = (ROOT/'assets/code_segments/CODE_13_Hunt.bin').read_bytes()
    assert code[0x480:0x486].hex() == '701e2f002f0b'
