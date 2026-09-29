"""Bounded climate-reference audit and CODE16:1e9e calendar oracle.

No destination-to-climate mapping has been recovered. The byte scan is evidence
about direct operands, not a proof excluding every possible indirect write.
"""
from pathlib import Path
from extract_a5 import decode_initial_data

ROOT = Path(__file__).resolve().parents[1]


def month_lengths() -> tuple[int, ...]:
    data = decode_initial_data((ROOT / 'assets/code_segments/CODE_21_A5Init.bin').read_bytes())
    start = len(data) - 0x1c38
    return tuple(data[start:start + 12])


def next_date(year: int, month: int, day: int) -> tuple[int, int, int]:
    """Original valid date transition; year is the unsigned world+0 word.

    The machine routine permits February29 in all years divisible by four,
    including1900. No Gregorian100/400 rule. No RNG or climate-field write.
    """
    lengths = month_lengths()
    if not 0 <= year <= 65535 or not 1 <= month <= 12:
        raise ValueError('Invalid original year/month')
    maximum = lengths[month-1] + (month == 2 and year % 4 == 0)
    if not 1 <= day <= maximum:
        raise ValueError('Invalid original day')
    day += 1
    if day > lengths[month-1]:
        # CODE16:1ed6 tests day29 after checking the ordinary month length.
        if day == 29 and year % 4 == 0:
            return year, month, day
        day = 1
        month += 1
        if month > 12:
            month = 1
            year = (year + 1) & 65535
    return year, month, day


def climate_operand_hits() -> dict[str, list[int]]:
    """Even byte locations containing022c in executable CODE1...20.

    Excludes jump-table CODE0 and compressed initialized data CODE21. Callers
    must inspect instructions containing hits before labeling reads/writes.
    """
    found = {}
    for path in sorted((ROOT / 'assets/code_segments').glob('CODE_*.bin')):
        segment = int(path.name.split('_')[1])
        if not 1 <= segment <= 20:
            continue
        data = path.read_bytes()
        hits = [i for i in range(0, len(data)-1, 2) if data[i:i+2] == b'\x02\x2c']
        if hits:
            found[path.name] = hits
    return found
