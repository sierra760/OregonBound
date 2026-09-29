"""Instruction-derived deterministic health fragment from CODE 16:0x21a8–0x2482.

This is an analysis oracle, not a whole-day simulation. Inputs are AFTER weather
and state-counter processing; random events have already run. An illness/death
side effect is returned as a flag and is deliberately not simulated here.
"""
from pathlib import Path
import json
import struct

if __package__:
    from .extract_a5 import decode_initial_data
else:
    from extract_a5 import decode_initial_data


def signed_div(numerator: int, denominator: int) -> int:
    return (abs(numerator) // abs(denominator)) * (-1 if (numerator < 0) != (denominator < 0) else 1)


def daily_health(*, badness=0, auxiliary=0, pending=0, survivors=5,
                 food=100, clothing=10, rations=0, pace=0, flags=0,
                 temperature=2, weather=0, members=None) -> dict:
    """Members are (status, remaining_days), ordered by original party slot."""
    if not (1 <= survivors <= 5 and 0 <= rations <= 2 and 0 <= pace <= 2):
        raise ValueError("Requires a living original-size party and valid ration/pace indices")
    if members is None:
        members = [(255, 0)] * survivors
    if food < 0 or clothing < 0 or not 0 <= temperature <= 5 or not 0 <= weather <= 9:
        raise ValueError("Invalid original-domain supplies or weather")
    if any(not 0 <= v <= 255 for v in (badness, auxiliary, pending, flags)):
        raise ValueError("Health and flags must be raw unsigned bytes")
    updated_members = []
    recovered = []
    illnesses = 0
    for index, (status, days) in enumerate(members):
        if status not in (255, 9):
            illnesses += 1
            days = (days - 1) & 255
            if days == 0:
                status = 255
                recovered.append(index)
        updated_members.append((status, days))
    temperature_penalty = 2 - temperature if temperature < 3 else temperature - 3
    clothing_penalty = max(0, 5 - 2 * temperature - clothing // survivors)
    ration_penalty = 2 * rations if food > 0 else 16
    pace_weather = (0 if flags & 12 else 2 * (pace + 1)) + (weather >= 3) + (weather >= 5)
    new_aux = (signed_div(auxiliary - 1, 2) + (clothing_penalty > 0 or food <= 0)) & 255
    terms = {
        'retained_badness': min(badness, 139) * 9 // 10,
        'temperature': temperature_penalty, 'clothing': clothing_penalty,
        'rations': ration_penalty, 'pace_weather': pace_weather,
        'auxiliary': new_aux, 'illnesses': illnesses, 'pending': pending,
    }
    raw = sum(terms.values()) & 255
    return {'badness': min(raw, 139), 'stored_before_threshold': raw,
            'auxiliary': new_aux, 'pending': 0,
            'food': max(0, food - survivors * (3 - rations)),
            'members': updated_members, 'recovered': recovered,
            'threshold_exceeded': raw > 139, 'terms': terms}


def original_tables() -> dict:
    memory = decode_initial_data(Path('assets/code_segments/CODE_21_A5Init.bin').read_bytes())
    result = {}
    for name, offset, format_code in [('temperature_base', -0x1d10, 'b'),
                                      ('precipitation_threshold', -0x1cc8, 'h')]:
        values = struct.unpack_from('>72' + format_code, memory, len(memory) + offset)
        result[name] = [list(values[i:i + 12]) for i in range(0, 72, 12)]
    return result


if __name__ == '__main__':
    print(json.dumps({'tables': original_tables(), 'steady_filling_mild_day': daily_health()}, indent=2))
