"""Original ending export operations, with anchors in the supplied executable."""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def test_ending_suffix_resources():
    strings = json.loads((ROOT / 'assets/strings/str_3004.json').read_text())['strings']
    assert strings[24:] == ['You made it to the Willamette Valley.',
                           ' person arrived in ^0 health.', ' people arrived in ^0 health.']
    assert strings[3] == 'Your Score = '

def test_original_append_flags_and_order():
    code = (ROOT / 'assets/code_segments/CODE_10_Ending.bin').read_bytes()
    assert code[0x16e:0x182] == bytes.fromhex('70012f002f2dd54872192f0148780bbc4ead0ad2')
    assert code[0xc34:0xc62] == bytes.fromhex(
        '70012f002f0b2f2dd5484ead0ada'
        '70002f00486efbd22f2dd5484ead0ada'
        '70012f00486efcd22f2dd5484ead0ada')

def test_exit_removes_journal_whose_teardown_exports_it():
    main = (ROOT / 'assets/code_segments/CODE_1_Main.bin').read_bytes()
    pane = (ROOT / 'assets/code_segments/CODE_6_Main3.bin').read_bytes()
    journal = (ROOT / 'assets/code_segments/CODE_14_Message.bin').read_bytes()
    assert main[0x994:0x998] == bytes.fromhex('4ead0962')
    assert pane[0x14fe:0x1506] == bytes.fromhex('486d0b4a4ead0772')
    assert journal[0x3b4:0x3c4] == bytes.fromhex('4aad d548 670a 2f2dd548 4ead0aca 588f'.replace(' ', ''))
