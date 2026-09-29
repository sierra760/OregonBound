import json
import sys
from pathlib import Path
import pytest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
from analysis_preferences import configuration_defaults, timing


def test_authored_defaults_are_configuration_not_world_values():
    assert configuration_defaults() == dict(password='boom', hint='See the Oregon Trail User’s Guide.', speed=4, hunt=3)
    code = (ROOT/'assets/code_segments/CODE_16_Model.bin').read_bytes()
    assert code[0x570:0x572] == b'\x02\x43'
    assert code[0x598:0x59a] == b'\x02\x47'


@pytest.mark.parametrize('speed', [2,4,8])
@pytest.mark.parametrize('hunt,seconds', enumerate([20,30,45,60,90,120], 1))
def test_all_timing_combinations(speed, hunt, seconds):
    assert timing(speed,hunt) == dict(timer_threshold=speed, day_ticks=speed*75,
                                    animation_ticks=speed*60, hunt_ticks=seconds*60)


def test_time_dialog_item_order_and_geometry():
    items = json.loads((ROOT/'assets/dialogs/ditl_2047.json').read_text())['items']
    assert [i['data'] for i in items] == ['OK','Cancel','Fast','Medium','Slow','Simulation Speed','Time Options']
    assert [items[i]['bounds']['top'] for i in (2,3,4)] == [90,70,50]


def test_menu_dispatch_targets():
    code = (ROOT/'assets/code_segments/CODE_15_Management.bin').read_bytes()
    assert code[0x113a:0x113e] == bytes.fromhex('487807f8') # About2040
    assert code[0x117a:0x117e] == bytes.fromhex('487807fb') # Network2043
    intro = (ROOT/'assets/code_segments/CODE_12_Game.bin').read_bytes()
    assert intro[0xbe:0xc2] == bytes.fromhex('48780802') # DLOG2050
    assert intro[0x1c0:0x1c6] == bytes.fromhex('d0bc00000801') # picture2049+page
