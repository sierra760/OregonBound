"""Original binary evidence and calendar boundaries, independent of Swift UI."""
from datetime import date, timedelta
from pathlib import Path
import sys
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from analysis_climate_calendar import climate_operand_hits, month_lengths, next_date
from analysis_daily_travel import weather_step

ROOT = Path(__file__).resolve().parents[1]


def test_climate_direct_operands_are_only_initialization_and_two_reads():
    assert climate_operand_hits() == {
        'CODE_16_Model.bin': [0x636, 0x26c8, 0x28d0],
        'CODE_18_River.bin': [0x1e], 'CODE_5_Display.bin': [0x3bf4]}
    # The other two022c words are BGT.W displacements, not memory operands.
    for file, start in [('CODE_18_River.bin',0x1c),('CODE_5_Display.bin',0x3bf2)]:
        assert (ROOT/'assets/code_segments'/file).read_bytes()[start:start+4].hex() == '6e00022c'
    code = (ROOT/'assets/code_segments/CODE_16_Model.bin').read_bytes()
    assert code[0x634:0x638].hex() == '4228022c'  # clr.b022c(a0)
    assert code[0x26c6:0x26ca].hex() == '1228022c'  # move.b022c(a0),d1
    assert code[0x28ce:0x28d2].hex() == '1028022c'  # move.b022c(a0),d0


def test_six_climate_rows_really_affect_weather_so_do_not_guess_mapping():
    # Identical March draws: row0 threshold78 is dry at100, row5 threshold108
    # rains. Thus a guessed westward transition changes the RNG call count too.
    east = weather_step(region=0, month=3, draws=[1,0,20,100])
    west = weather_step(region=5, month=3, draws=[1,0,20,100,9])
    assert east['weather'] == 0 and west['weather'] == 3
    assert len(east['rng_calls']) == 4 and len(west['rng_calls']) == 5


def test_month_lengths_come_from_a5_initializer():
    assert month_lengths() == (31,28,31,30,31,30,31,31,30,31,30,31)


@pytest.mark.parametrize('before,after', [
    ((1848,1,31),(1848,2,1)),
    ((1848,2,28),(1848,2,29)),
    ((1848,2,29),(1848,3,1)),
    ((1849,2,28),(1849,3,1)),
    ((1848,4,30),(1848,5,1)),
    ((1848,12,31),(1849,1,1)),
    ((1900,2,28),(1900,2,29)),
    ((1900,2,29),(1900,3,1)),
    ((65535,12,31),(0,1,1)),
])
def test_original_calendar_rollovers(before, after):
    assert next_date(*before) == after


def test_normal_journey_dates_match_gregorian_across_leap_and_year_rollover():
    current = date(1848,3,1)
    for _ in range(730):
        result = next_date(current.year, current.month, current.day)
        current += timedelta(days=1)
        assert result == (current.year,current.month,current.day)


def test_day_routine_has_no_rng_or_climate_operand():
    code = (ROOT/'assets/code_segments/CODE_16_Model.bin').read_bytes()[0x1e9e:0x1f24]
    assert bytes.fromhex('4ead00a2') not in code
    assert bytes.fromhex('022c') not in code
