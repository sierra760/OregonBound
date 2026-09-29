"""CODE16 instruction-selected regressions; scripted bounded draws expose order."""
from pathlib import Path
import sys
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from analysis_trail_events import World, Wagon, ScriptedRandom, dispatch, known_action, delay_at_least, select_member


def probe(name, world, draw, slot):
    world.events.append((name, slot))


def test_outer_independent_checks_order_not_single_choice():
    w = World(temperature=0, month=6, destination=12, rain=0, snow=3001)
    w.wagons[0].inventory[6] = 0
    rng = ScriptedRandom([0]*12 + [1])
    result = dispatch(w, rng, probe)
    assert [e[0] for e in result.events] == [
        'snowbound', 'illness', 'food_aid', 'wild_fruit', 'severe_weather',
        'fog_hail', 'broken_part', 'lost_trail', 'rough_impassable', 'fire',
        'supplies_found', 'dry_ground']
    assert [x[0] for x in rng.trace] == [0x312c, 0x3160, 0x319e, 0x3200,
        0x3216, 0x322c, 0x326c, 0x32a0, 0x32c8, 0x32de, 0x32ec, 0x3320, 0x3358]
    assert w.events == []  # copied input


def test_no_wagons_no_draws():
    rng = ScriptedRandom([])
    assert dispatch(World(wagon_count=0), rng, probe).events == []
    assert rng.trace == []


@pytest.mark.parametrize('destination,roll,selected', [(11, 3, True), (11, 4, False),
                                                       (12, 6, True), (12, 7, False)])
def test_breakage_rate_boundary(destination, roll, selected):
    draws = [99, 99, roll] + ([1] if selected else []) + [99]
    if destination > 11:
        draws += [99]
    draws += [99, 99]
    result = dispatch(World(destination=destination), ScriptedRandom(draws), probe)
    assert result.events == ([('sick_ox', None)] if selected else [])


def test_hot_check_and_severe_weather_short_circuit_rng():
    rng = ScriptedRandom([4, 99, 99, 99, 99, 99, 99])
    result = dispatch(World(temperature=4, weather=4), rng, known_action)
    assert [e['id'] for e in result.events] == [8]
    assert result.weather == 0x87 and result.delay == 1
    assert 0x3200 not in [x[0] for x in rng.trace]
    assert rng.trace[0] == (0x30d6, 100, 4)  # strict <4


def test_helper_draws_and_writes_interleave_with_outer_checks():
    rng = ScriptedRandom([9, 99, 99, 99, 0, 4, 1, 99, 99])
    result = dispatch(World(snow=3001), rng, known_action)
    assert [e['id'] for e in result.events] == [12, 2]
    assert result.delay == 10  # snow10 and lost5 take max, not sum
    assert [x[0] for x in rng.trace] == [0x354a, 0x312c, 0x3216, 0x322c,
                                        0x32a0, 0x3064, 0x3078, 0x32de, 0x3320]


def test_equal_delay_does_not_set_flag():
    w = World(delay=3, flags=2)
    delay_at_least(w, 3)
    assert w.flags == 2
    delay_at_least(w, 4)
    assert w.delay == 4 and w.flags == 10


@pytest.mark.parametrize('choice,event,pending', [(39,9,7), (40,11,20), (59,11,20), (60,10,10)])
def test_dry_ground_thresholds_assign_pending(choice, event, pending):
    w = World()
    w.wagons[0].pending = 7
    known_action('dry_ground', w, ScriptedRandom([choice]))
    assert w.events[0]['id'] == event and w.wagons[0].pending == pending


def test_snow_blocks_water_but_not_grass_events():
    w = World(snow=1)
    known_action('dry_ground', w, ScriptedRandom([40]))
    assert w.events == []
    known_action('dry_ground', w, ScriptedRandom([0]))
    assert w.events[0]['id'] == 9


def test_fog_hail_route_and_temperature_checks():
    w = World(destination=12, temperature=4)
    known_action('fog_hail', w, ScriptedRandom([1]))
    assert w.delay == 1 and w.events[0]['id'] == 0
    w = World(destination=11, temperature=5)
    rng = ScriptedRandom([])
    known_action('fog_hail', w, rng)
    assert w.weather == 0x89 and w.delay == 0 and rng.trace == []


def test_raw_oxen_loss_parity_and_single_wagon_no_rng_consumption():
    w = World()
    rng = ScriptedRandom([])
    known_action('sick_ox', w, rng)
    known_action('sick_ox', w, rng)
    assert w.wagons[0].inventory[0] == 10
    assert [e['id'] for e in w.events] == [23, 24]
    assert rng.trace == [(0x2d12, 1, 0)]*2


def test_farmer_draw_and_wandering_no_inventory_loss():
    w = World(wagons=[None, Wagon(profession=4)])
    rng = ScriptedRandom([1, 2])
    known_action('sick_ox', w, rng)
    known_action('wandered_ox', w, rng)
    assert w.wagons[1].inventory[0] == 12 and w.delay == 3
    assert [(e['id'], e['slot']) for e in w.events] == [(22,1), (21,1)]


def test_part_repair_draws_before_profession_checks_and_no_delay():
    w = World()
    rng = ScriptedRandom([0, 1, 1, 0])
    known_action('broken_part', w, rng)
    assert [x[0] for x in rng.trace] == [0x2d12, 0x2b68, 0x2b76, 0x2bb2, 0x2bea]
    assert w.events[0]['id'] == 33 and w.wagons[0].inventory[3] == 0
    assert w.delay == 0 and w.flags == 2
    known_action('broken_part', w, ScriptedRandom([0, 0, 0, 0]))
    assert w.events[-1]['id'] == 34 and w.flags == 0 and w.wagons[0].status == 2


def test_blacksmith_stops_repair_draws_early():
    w = World(wagons=[Wagon(profession=1)], wagon_count=2)
    rng = ScriptedRandom([2, 1])
    known_action('broken_part', w, rng)
    assert w.events[0]['id'] == 32 and w.wagons[0].inventory[5] == 1
    assert len(rng.trace) == 3


def test_found_supplies_report_precap_and_never_oxen_or_food():
    w = World()
    w.wagons[0].inventory[1] = 50
    known_action('supplies_found', w, ScriptedRandom([1,2, 1,39, 0, 0, 0]))
    assert w.wagons[0].inventory == [12,50,159,1,1,1,1000]
    assert w.events[0]['quantities'] == [0,3,59,0,0,0,0]


def test_fire_includes_food_excludes_oxen_and_logs_only_nonzero_loss():
    w = World()
    known_action('fire', w, ScriptedRandom([50,50,50,50,50, 49,1000]))
    assert w.wagons[0].inventory == [12,10,100,1,1,1,0]
    assert w.events[0]['id'] == 65
    w.events.clear()
    known_action('fire', w, ScriptedRandom([99]*5+[0]))  # zero food ->bound1, no sample
    assert w.events == []


def test_fruit_cap_and_aid_word_wrap():
    w = World()
    w.wagons[0].inventory[6] = 1990
    known_action('wild_fruit', w, ScriptedRandom([]), 0)
    known_action('wild_fruit', w, ScriptedRandom([]), 0)
    assert w.wagons[0].inventory[6] == 2000 and len(w.events) == 1
    w.wagons[0].inventory[6] = 65530
    known_action('food_aid', w, ScriptedRandom([]), 0)
    assert w.wagons[0].inventory[6] == 24


def test_unimplemented_action_fails_instead_of_claiming_complete_simulation():
    with pytest.raises(NotImplementedError):
        dispatch(World(), ScriptedRandom([0]), known_action)


def test_binary_branch_anchors_and_capacity_table():
    # Instruction offsets exclude four-byte resource CODE header.
    root = Path(__file__).resolve().parents[1]
    code = (root/'assets/code_segments/CODE_16_Model.bin').read_bytes()
    assert code[0x30b6:0x30be] == bytes.fromhex('0c8000000bb86f04')
    assert code[0x358a:0x3590] == bytes.fromhex('117c0088022d')
    assert code[0x35b8:0x35be] == bytes.fromhex('117c0087022d')
    assert code[0x2c36:0x2c3c] == bytes.fromhex('022800fd0005')
    from extract_a5 import decode_initial_data
    import struct
    memory = decode_initial_data((root/'assets/code_segments/CODE_21_A5Init.bin').read_bytes())
    assert struct.unpack_from('>7H', memory, len(memory)-0x2896) == (40,50,1980,3,3,3,2000)


def test_member_selection_skips_dead_with_original_draw_bounds():
    wagon = Wagon(conditions=[255, 9, 255, 255, 255])
    rng = ScriptedRandom([0, 1])
    assert select_member(wagon, rng) == 2
    assert rng.trace == [(0x2c8c,4,0), (0x2c8c,4,1)]
    wagon.survivors = 1
    assert select_member(wagon, ScriptedRandom([])) == 0


def test_member_retry_boundary_falls_back_even_on_valid_thousandth_draw():
    wagon = Wagon(conditions=[255, 9, 255, 255, 255])
    rng = ScriptedRandom([0]*999+[1])
    assert select_member(wagon, rng) == 0 and len(rng.trace) == 1000
    rng = ScriptedRandom([0]*1001)
    assert select_member(wagon, rng) == 0 and len(rng.trace) == 1001


def test_injury_overwrites_condition_but_keeps_longer_timer():
    w = World()
    w.wagons[0].timers[1] = 40
    known_action('snakebite', w, ScriptedRandom([0,2]))
    assert w.wagons[0].conditions[1] == 2 and w.wagons[0].timers[1] == 40
    known_action('broken_limb', w, ScriptedRandom([0,1,4]))
    assert w.wagons[0].conditions[1] == 1 and w.wagons[0].timers[1] == 40
    assert [e['id'] for e in w.events] == [29,27]


def test_lost_person_only_delays_never_removes_member():
    w = World()
    known_action('lost_person', w, ScriptedRandom([2,4]))
    assert w.delay == 5 and w.wagons[0].survivors == 5
    assert w.wagons[0].conditions == [255]*5
    assert w.events[0]['member'] == 3


def test_literal_thief_raw_oxen_conversion_can_discard_selected_loss():
    w = World()
    known_action('thief', w, ScriptedRandom([0,1]))
    assert w.wagons[0].inventory[0] == 12 and not w.events
    known_action('thief', w, ScriptedRandom([0,3]))
    assert w.wagons[0].inventory[0] == 10 and w.events[0]['quantities'][0] == 2


def test_literal_thief_cash_branch_is_not_clamped():
    w = World()
    w.wagons[0].inventory[6] = 0
    w.wagons[0].cash = 10000
    rng = ScriptedRandom([3,9999])
    known_action('thief', w, rng)
    assert w.wagons[0].cash == -990000
    assert rng.trace[-1] == (0x374e,10000,9999)
    # Negative balance does not trigger more cash theft.
    known_action('thief', w, ScriptedRandom([3]))
    assert len(w.events) == 1
