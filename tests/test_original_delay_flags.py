from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def test_counter_requires_flag_before_read_and_decrement():
    code=(ROOT/'assets/code_segments/CODE_16_Model.bin').read_bytes()
    assert code[0x1f30:0x1f40] == bytes.fromhex('206dd8fa7000102800057208c2806720')
    assert code[0x1f4c:0x1f60] == bytes.fromhex('206dd8fa022800f700056008206dd8fa53280006')

def test_delay_request_only_sets_flag_for_strictly_larger_counter():
    code=(ROOT/'assets/code_segments/CODE_16_Model.bin').read_bytes()
    assert code[0x2f8e:0x2fb0] == bytes.fromhex('206dd8fa70001028000648c7be806f12206dd8fa11470006206dd8fa002800080005')

def test_loader_clears_flags_without_clearing_counter():
    code=(ROOT/'assets/code_segments/CODE_6_Main3.bin').read_bytes()
    assert code[0x2f0:0x2fa] == bytes.fromhex('206dd2924228002d4247')
