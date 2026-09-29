"""Boundary cases selected from original CODE16 branches, not UI approximations."""
from pathlib import Path
import sys
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from analysis_daily_travel import movement, process_counters, weather_step


def test_travel_terrain_pace_oxen_and_conditions():
    assert movement()['miles'] == 20
    assert movement(pace=1)['miles'] == 30
    assert movement(pace=2)['miles'] == 40
    assert movement(destination=4)['miles'] == 20
    assert movement(destination=5)['miles'] == 12
    assert movement(minimum_oxen=4)['miles'] == 10
    assert movement(minimum_oxen=40)['miles'] == 20
    assert movement(active_conditions_last_wagon=1)['miles'] == 18
    assert movement(active_conditions_last_wagon=5)['miles'] == 10


def test_snow_factor_and_final_integer_truncation():
    assert movement(snow=2000)['miles'] == 10
    assert movement(snow=3999)['miles'] == 0
    assert movement(snow=4000)['miles'] == 0
    assert movement(snow=4001)['miles'] == 0
    assert movement(destination=5, minimum_oxen=3, pace=1)['miles'] == 6


def test_near_arrival_uses_strict_eleven_tenths_rule():
    assert movement(remaining=21)['miles'] == 21
    boundary = movement(remaining=22)
    assert boundary['miles'] == 20 and boundary['remaining'] == 2
    result = movement(remaining=21, cumulative=65530)
    assert result['cumulative'] == 15 and result['flags'] == 0 and result['arrived']


@pytest.mark.parametrize('flags', [0, 4, 6, 8, 10, 14])
def test_rest_delay_and_not_traveling_preserve_last_miles(flags):
    result = movement(flags=flags, last_miles=17)
    assert result['miles'] == 0 and result['last_miles'] == 17


def test_counter_zero_clears_next_day_and_retains_rest_entry_flag():
    state = process_counters(flags=14, rest=1, delay=1)
    assert state == dict(flags=14, rest=0, delay=0, started_resting=True)
    state = process_counters(flags=state['flags'], rest=0, delay=0)
    assert state == dict(flags=2, rest=0, delay=0, started_resting=True)


def test_weather_persistence_reuses_both_previous_increments():
    result = weather_step(weather=3, rain=100, snow=1000,
                          rain_increment=20, snow_increment=160, draws=[0])
    assert (result['rain'], result['snow']) == (110, 1130)
    assert result['rng_calls'] == [dict(bound=2, result=0)]


def test_fresh_dry_weather_resets_both_increments_and_temperature():
    # March row0 base33: (33+40)/20 =3; precip threshold78, equality is dry.
    result = weather_step(rain_increment=80, snow_increment=640, draws=[1, 2, 40, 78])
    assert (result['weather'], result['temperature']) == (2, 3)
    assert (result['rain_increment'], result['snow_increment']) == (0, 0)
    assert [c['bound'] for c in result['rng_calls']] == [2, 3, 41, 1000]


def test_rain_snow_split_and_heavy_draw_boundary():
    snow = weather_step(month=3, draws=[1, 0, 0, 0, 2], rain_increment=20)
    assert (snow['weather'], snow['temperature'], snow['snow_increment']) == (6, 1, 640)
    assert snow['rain_increment'] == 20  # opposite increment is not reset
    rain = weather_step(month=3, draws=[1, 0, 7, 0, 3], snow_increment=160)
    assert (rain['weather'], rain['temperature'], rain['rain_increment']) == (3, 2, 20)
    assert rain['snow_increment'] == 160


def test_event_override_has_no_draw_and_next_severe_day_skips_coinflip():
    result = weather_step(weather=0x88, snow_increment=160)
    assert result['weather'] == 8 and result['snow_increment'] == 800
    assert result['rng_calls'] == []
    next_day = weather_step(weather=8, draws=[0, 0, 999])
    assert [c['bound'] for c in next_day['rng_calls']] == [3, 41, 1000]


def test_melt_branch_adds_rain_but_only_clears_small_snow():
    below = weather_step(weather=0x80, temperature=3, snow=515)
    assert (below['rain'], below['snow']) == (50, 0)  # floor515*.97 =499
    at = weather_step(weather=0x80, temperature=3, snow=516)
    assert (at['rain'], at['snow']) == (50, 500)
    cold_rain = weather_step(weather=0x84, temperature=1, snow=100)
    assert cold_rain['snow'] == 0 and cold_rain['rain'] == 50


def test_missing_or_invalid_draw_is_rejected():
    with pytest.raises(ValueError, match='Missing RNG'):
        weather_step()
    with pytest.raises(ValueError, match='range'):
        weather_step(draws=[2])


def test_original_movement_instruction_constants_and_strict_branch():
    code = (Path(__file__).resolve().parents[1] / 'assets/code_segments/CODE_16_Model.bin').read_bytes()
    # MOVE.L #640000,D1; JSR signed division helper A5+0x262.
    assert code[0x2542:0x254c].hex() == '223c0009c4004ead0262'
    # CMP.L D0,D1; BGE skips the assignment of remaining miles.
    assert code[0x2576:0x257a].hex() == 'b2806c0c'
    # Snow decay divisor100 followed by the same helper.
    assert code[0x213e:0x2144].hex() == '72644ead0262'
