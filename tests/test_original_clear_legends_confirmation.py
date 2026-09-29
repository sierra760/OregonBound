"""Pin the exact direct StopAlert call; older recovery called it NoteAlert."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]

def test_original_confirmation_is_stop_alert_without_the_password_audio_wrapper():
    code = (ROOT / 'assets/code_segments/CODE_15_Management.bin').read_bytes()
    assert code[0x8b0:0x8be].hex() == '2f2efff84ead005a2f2efff4205f'
    assert code[0x8c0:0x8cc].hex() == '558f3f3c07fd70002f00a986'
    assert code[0x8d6:0x8e0].hex() == '7202b280588f660000e4'
    # Direct ALRT loading/centering call, not CODE1's alert/audio wrapper.
    assert bytes.fromhex('4ead005a') in code[0x878:0x8cc]

def test_authored_confirmation_items():
    items = json.loads((ROOT / 'assets/dialogs/ditl_2045.json').read_text())['items']
    assert [item['data'] for item in items[:2]] == ['No', 'Yes']
    assert items[0]['bounds'] == dict(top=65, left=57, bottom=85, right=117)
    assert items[1]['bounds'] == dict(top=65, left=153, bottom=85, right=213)
    assert items[3]['bounds'] == dict(top=13, left=65, bottom=54, right=265)
    assert (ROOT / 'assets/system_controls/system7_alert_icon_0.png').is_file()
