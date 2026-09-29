from pathlib import Path
from capstone import Cs, CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000

ROOT = Path(__file__).resolve().parents[1]

def ops(segment, start, end):
    data = next((ROOT/'assets/code_segments').glob(f'CODE_{segment}_*')).read_bytes()
    md = Cs(CS_ARCH_M68K, CS_MODE_BIG_ENDIAN | CS_MODE_M68K_000)
    return {i.address: (i.mnemonic, i.op_str) for i in md.disasm(data[start:end], start)}

def test_about_and_ordinary_dialog_helpers_block_in_modal_dialog():
    about = ops(2, 0x66, 0x8a)
    assert about[0x74] == ('dc.w', '$a991')
    repeat = ops(2, 0x178, 0x186)
    assert repeat[0x182] == ('bne.w', '$6c')
    generic = ops(1, 0x1e4, 0x1ee)
    assert generic[0x1e4] == ('moveq', '#$0, d0') # null filter
    assert generic[0x1ec] == ('dc.w', '$a991')
    intro = ops(12, 0x106, 0x110)
    assert intro[0x106] == ('moveq', '#$0, d0')
    assert intro[0x10e] == ('dc.w', '$a991')
    export = ops(3, 0xe80, 0xe8e)
    assert export[0xe80] == ('moveq', '#$0, d0') # no application dialog hook
    assert export[0xe8c] == ('dc.w', '$a9ea') # Standard File package

def test_generic_timer_counts_one_observed_tick_after_arbitrary_gap():
    timer = ops(5, 0x2272, 0x2288)
    assert timer[0x2274] == ('dc.w', '$a975')
    assert timer[0x2276] == ('move.l', '-$2c26(a5), d0')
    assert timer[0x227c] == ('bcc.b', '$2288')
    assert timer[0x2282] == ('move.l', '(a7)+, -$2c26(a5)')
    assert timer[0x2286] == ('moveq', '#$1, d7')
    assert ops(5, 0x229e, 0x22a8)[0x229e] == ('addq.l', '#$1, (a3)')

def test_hunt_uses_unchanged_absolute_end_and_fresh_three_tick_update_deadline():
    hunt = ops(13, 0xec0, 0xee0)
    assert hunt[0xec2] == ('dc.w', '$a975')
    assert hunt[0xec6] == ('addq.l', '#$3, d0')
    assert hunt[0xec8] == ('move.l', 'd0, -$253c(a5)')
    assert hunt[0xece] == ('cmp.l', '-$23b8(a5), d0')
    assert hunt[0xed2] == ('bls.b', '$ee0')
    assert hunt[0xedc] == ('clr.w', '-$23b4(a5)')
    river = ops(18, 0x818, 0x832)
    assert river[0x81e] == ('cmp.l', '-$187a(a5), d0')
    assert river[0x822] == ('bcs.w', '$984')
    assert river[0x82c] == ('addq.l', '#$3, d0')
    assert river[0x82e] == ('move.l', 'd0, -$187a(a5)')
