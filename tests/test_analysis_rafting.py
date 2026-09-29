from pathlib import Path
import sys
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
from analysis_rafting import (Party, ScriptedRandom, collide, maximum_rocks, frame_progress,
                              should_spawn, choose_lane, steer, hits_raft, rock_frame, settlement, barlow_payment)


@pytest.mark.parametrize('rain,maximum', [(0,3),(400,3),(549,3),(699,3),(700,2),(849,2),(850,1),(65535,1)])
def test_rain_caps_simultaneous_rocks(rain, maximum):
    assert maximum_rocks(rain) == maximum


def test_color_progress_ends_on_old_zero_after_670_running_frames():
    remaining = 1340
    for _ in range(670):
        remaining, done, objects = frame_progress(remaining, 5, 4)
        assert not done and objects
    assert remaining == 0
    assert frame_progress(remaining, 5, 4) == (-1, True, False)
    assert frame_progress(1340, 0, 4) == (1339, True, False)
    assert frame_progress(2, 5, 2) == (1, False, True)


def test_spawn_always_draws_even_when_full_or_near_end():
    rng = ScriptedRandom([0,7,7,7,7])
    assert should_spawn(151,0,0,3,rng)
    assert not should_spawn(150,0,0,3,rng)
    assert not should_spawn(151,3,0,3,rng)
    assert not should_spawn(151,0,1,3,rng)
    assert should_spawn(151,1,0,3,rng)
    assert len(rng.trace) == 5 and all(site == 0x05cc for site,_,_ in rng.trace)


def test_lane_retry_is_not_independent_uniform_screen_position():
    rng = ScriptedRandom([0,1,2,3]) # lane23,16,9 all within14, then2 accepted
    assert choose_lane(-999,rng) == (2,193)
    assert [bound for _,bound,_ in rng.trace] == [8]*4
    assert choose_lane(0, ScriptedRandom([3,5,6])) == (-19,151)


def test_mouse_dead_zone_step_clamp_and_direction_frame():
    assert steer(159,63,222) == (159,0,3) # edge inclusive; pointer inside raft does not move it
    assert steer(159,63,223) == (163,1,4)
    assert steer(159,63,158) == (155,-1,2)
    assert steer(349,63,500) == (350,0,3)
    assert steer(11,63,0) == (10,0,3)


def test_collision_uses_directional_bands_not_circle_or_normalized_lane():
    assert hits_raft(220,150,159,0)
    assert not hits_raft(260,150,159,0)
    assert not hits_raft(220,300,159,0)
    # Rock's right edge175 touches straight band's left175 at y210; empty intersection.
    assert not hits_raft(189,111,159,0)
    assert hits_raft(189,112,159,0)


def test_collision_rng_order_zero_items_odd_oxen_and_leader_last():
    party = Party([3,10,0,1,0,0,20],[True,True,False],[False]*3)
    rng = ScriptedRandom([49,10,50,0,20,39,40,39,40])
    result = collide(party,rng)
    assert result.losses == [2,10,0,0,0,0,20]
    assert result.drowned == [1] and result.party.alive == [True,False,False]
    assert result.party.inventory == [1,0,0,1,0,0,0]
    assert [site for site,_,_ in rng.trace] == [0x1960,0x1982,0x1960,0x1960,0x1982,0x185a,0x185a,0x18c2,0x1918]
    assert party.inventory[0] == 3 and party.alive[1] # local snapshot copied


def test_second_collision_uses_reduced_inventory_and_skips_already_drowned():
    party = Party([1,0,0,0,0,0,2],[True,False],[False,True])
    rng = ScriptedRandom([0,2,0,0])
    result = collide(party,rng)
    assert result.party.inventory == [0]*7 and not any(result.party.alive)
    assert result.drowned == [0] and result.pause_steps == 100
    assert [site for site,_,_ in rng.trace] == [0x1960,0x1982,0x185a,0x1918]
    initial = Party([3,10,0,0,0,0,100],[True,True],[False,False])
    total = settlement(initial, result.party, 130)
    assert total == {'losses':[3,10,0,0,0,0,100],'drowned':[0,1],'badness':105,'survivors':0,'date_delta':0,'miles_delta':0}


def test_no_artificial_ten_collision_failure_when_draws_spare_lone_survivor():
    party = Party([0]*7,[True],[False])
    for _ in range(11):
        party = collide(party, ScriptedRandom([40])).party
    assert party.alive == [True]


@pytest.mark.parametrize('top,frame', [(39,10),(63,10),(64,8),(75,7),(99,5),(300,5)])
def test_rock_frame_bands(top,frame):
    assert rock_frame(top) == frame


def test_barlow_exact_cash_boundary():
    assert barlow_payment(499) is None
    assert barlow_payment(500) == 0
    assert barlow_payment(-100) is None


def test_original_collision_threshold_and_countdown_instruction_anchors():
    import macresources
    from capstone import Cs, CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000
    raw = next(bytes(r) for r in macresources.parse_file((Path(__file__).resolve().parents[1]/'raw/oregon_trail.rsrc').read_bytes())
               if r.type == b'CODE' and r.id == 17)[4:]
    md = Cs(CS_ARCH_M68K, CS_MODE_BIG_ENDIAN | CS_MODE_M68K_000)
    def ops(lo, hi):
        return {i.address:(i.mnemonic,i.op_str) for i in md.disasm(raw[lo:hi],lo)}
    assert ops(0x03dc,0x03e2)[0x03dc] == ('move.w','#$53c, -$1a20(a5)')
    step = ops(0x0594,0x05c8)
    assert step[0x0598] == ('subq.w','#$1, -$1a20(a5)')
    assert step[0x059c] == ('tst.w','d0') # OLD count, not decremented field
    assert step[0x05b8] == ('subq.w','#$1, -$1a20(a5)')
    assert step[0x05c2] == ('addq.l','#$3, d0')
    loss = ops(0x13cc,0x13ea)
    assert loss[0x13cc] == ('move.w','#$64, -$197e(a5)') #100 pause, not death limit
    assert loss[0x13d2] == ('moveq','#$32, d0') #50% supplies
    assert loss[0x13da] == ('moveq','#$28, d0') #40% oxen
    assert loss[0x13e2] == ('moveq','#$28, d0') #40% people


def test_embedded_extended_constants_match_single_trajectory_and_map_results():
    from fractions import Fraction
    from analysis_rafting import single, rock_motion, marker_target
    raw = next((Path(__file__).resolve().parents[1]/'assets/code_segments').glob('CODE_17*')).read_bytes()
    def extended(offset):
        word = int.from_bytes(raw[offset:offset+2],'big')
        significand = int.from_bytes(raw[offset+2:offset+10],'big')
        power = (word&32767)-16383-63
        return Fraction(significand)*Fraction(2)**power*(-1 if word&32768 else 1)
    # All legal rock lanes, all138 active callbacks before retirement.
    for lane in [23-7*i for i in range(8)]:
        exact_slope = single(lane*extended(0xfe0))
        assert exact_slope == single(lane*0.0178)
        acc = 0.0
        for _ in range(138):
            exact = single(Fraction(acc)+Fraction(exact_slope)*2)
            dx = -2 if exact_slope < 0 and exact < -2 else 2 if exact_slope > 0 and exact > 2 else 0
            assert rock_motion(lane,acc) == (dx,single(Fraction(exact)-dx))
            acc = single(Fraction(exact)-dx)
    # Map uses extended constants, single target storage, then FTINTX $0016.
    segments = [(19,464,0,0xbba,1),(46,466,19,0xb88,1),(115,466,46,0xbb0,1),
                (154,475,115,0xba6,-1),(192,462,154,0xb9c,-1),(221,457,192,0xb92,-1),
                (269,446,221,0xb88,1)]
    for progress in range(269):
        _,base,origin,offset,sign = next(s for s in segments if progress < s[0])
        exact = single(base+(progress-origin)*extended(offset)*sign)
        assert marker_target(progress) == exact
    assert int(marker_target(116)-475) == 0  # −0.333... truncates, rather than floors.


def test_initial_lane_global_and_callback_before_move_binary_anchors():
    from extract_a5 import decode_initial_data
    directory = Path(__file__).resolve().parents[1]/'assets/code_segments'
    memory = decode_initial_data(next(directory.glob('CODE_21*')).read_bytes())
    assert int.from_bytes(memory[-0x1982:-0x1980],'big',signed=True) == -999
    raw = next(directory.glob('CODE_5*')).read_bytes()
    assert raw[0xe0:0xe2] == bytes.fromhex('4e90')  # callback jsr(a0)
    assert raw[0x144:0x148] == bytes.fromhex('4eba088a')  # move helper at09d0
