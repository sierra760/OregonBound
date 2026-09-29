"""Deterministic CODE16 daily movement/weather oracle with injected RNG draws.

This is not a complete game-day simulator. See docs/ORIGINAL_DAILY_TRAVEL.md.
"""
from __future__ import annotations

from analysis_health import original_tables, signed_div


def signed_word(value: int) -> int:
    value &= 65535
    return value - 65536 if value & 32768 else value


def process_counters(*, flags: int, rest: int, delay: int) -> dict:
    """CODE16:0x1f30–0x1f90; a counter reaching zero keeps its flag today."""
    started_resting = bool(flags & 4)
    for mask, value in ((8, delay), (4, rest)):
        if flags & mask:
            if value:
                value = (value - 1) & 255
            else:
                flags &= ~mask
        if mask == 8:
            delay = value
        else:
            rest = value
    return dict(flags=flags, rest=rest, delay=delay, started_resting=started_resting)


def movement(*, flags=2, pace=0, destination=0, minimum_oxen=8,
             active_conditions_last_wagon=0, snow=0, remaining=102,
             cumulative=0, last_miles=0) -> dict:
    """CODE16:0x249a–0x259a, after weather and health; no arrival callbacks.

    minimum_oxen is taken before the per-wagon illness/death callbacks.
    active_conditions_last_wagon counts illness before today's recoveries.
    """
    if not 0 <= minimum_oxen <= 40 or not 0 <= active_conditions_last_wagon <= 5:
        raise ValueError('Outside original normal wagon inventory/condition domain')
    if not 0 <= pace <= 2 or not -1 <= destination <= 16:
        raise ValueError('Invalid pace or destination')
    if not flags & 2 or flags & 12:
        return dict(miles=0, remaining=remaining, cumulative=cumulative,
                    last_miles=last_miles, arrived=False, flags=flags, terms=None)
    terrain = 20 if destination < 5 else 12
    oxen = min(minimum_oxen, 8)
    # MOVE.W sets N before BGE at0x24e6: preserve low-word signed test.
    snow_factor = max(0, signed_word(4000 - (snow & 65535)))
    numerator = terrain * oxen * (pace + 2) * (10-active_conditions_last_wagon) * snow_factor
    base = signed_word(signed_div(numerator, 640000))
    near_threshold = signed_div(base * 11, 10)
    miles = remaining if remaining < near_threshold else base
    new_remaining = (remaining - miles) & 255
    arrived = new_remaining == 0
    return dict(miles=miles, remaining=new_remaining,
                cumulative=(cumulative+miles) & 65535, last_miles=miles & 255,
                arrived=arrived, flags=flags & ~2 if arrived else flags,
                terms=dict(terrain=terrain, oxen=oxen, pace=pace+2,
                           illness=10-active_conditions_last_wagon,
                           snow=snow_factor, numerator=numerator,
                           base_miles=base, near_threshold=near_threshold))


def weather_step(*, weather=0, temperature=2, region=0, month=3,
                 rain=0, snow=0, rain_increment=0, snow_increment=0,
                 draws=()) -> dict:
    """CODE16:0x1f94–0x21a4 with ordered, bounded random results supplied.

    Weather values128...137 request one-day event override. Counters are raw
    unsigned words; increments not selected by a branch remain unchanged.
    """
    if not 0 <= region < 6 or not 1 <= month <= 12:
        raise ValueError('Invalid climate table index')
    sequence = iter(draws)
    calls = []

    def rng(bound):
        try:
            value = next(sequence)
        except StopIteration as exc:
            raise ValueError(f'Missing RNG({bound}) result') from exc
        if not 0 <= value < bound:
            raise ValueError(f'RNG({bound}) result outside ordinary wrapper range')
        calls.append({'bound': bound, 'result': value})
        return value

    tables = original_tables()
    if weather & 128:
        weather &= 127
        if weather == 7:
            rain_increment = 100
        elif weather == 8:
            snow_increment = 800
        elif weather == 9:
            rain_increment = 50
    elif weather >= 7 or rng(2) != 0:
        weather = rng(3)
        temperature = signed_div(tables['temperature_base'][region][month-1] + rng(41), 20)
        if rng(1000) < tables['precipitation_threshold'][region][month-1]:
            heavy = rng(10) < 3
            if temperature < 2:
                weather, snow_increment = (6, 640) if heavy else (5, 160)
            else:
                weather, rain_increment = (4, 80) if heavy else (3, 20)
        else:
            rain_increment = snow_increment = 0
    rain = (signed_div((rain & 65535)*9, 10) + (rain_increment & 65535)) & 65535
    snow = (signed_div((snow & 65535)*97, 100) + (snow_increment & 65535)) & 65535
    if snow > 0 and (temperature >= 3 or weather == 4):
        rain = (rain + 50) & 65535
        if snow < 500:
            snow = 0
    return dict(weather=weather, temperature=temperature, rain=rain, snow=snow,
                rain_increment=rain_increment, snow_increment=snow_increment,
                rng_calls=calls)
