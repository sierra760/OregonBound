"""Authored CONF1000 preferences and bounded CODE15/CODE16 timing evidence."""
from pathlib import Path
import macresources

ROOT = Path(__file__).resolve().parents[1]


def configuration_defaults():
    resource = next(r for r in macresources.parse_file((ROOT/'raw/oregon_trail.rsrc').read_bytes())
                    if r.type == b'CONF' and r.id == 1000)
    data = bytes(resource.data)
    def pascal(offset):
        return data[offset+1:offset+1+data[offset]].decode('mac_roman')
    return dict(password=pascal(0x126), hint=pascal(0x26), speed=data[0x135], hunt=data[0x136])


def timing(speed, hunt):
    if speed not in (2, 4, 8) or not 1 <= hunt <= 6:
        raise ValueError('Invalid authored timing selector')
    return dict(timer_threshold=speed, day_ticks=speed*75, animation_ticks=speed*60,
                hunt_ticks=(0, 20, 30, 45, 60, 90, 120)[hunt]*60)
