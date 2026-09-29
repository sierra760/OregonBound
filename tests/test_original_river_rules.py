"""Primary-binary anchors for the river rules' surprising boundary behavior."""
from pathlib import Path
import sys
import pytest
from capstone import Cs, CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import macresources


def instructions(segment, start, stop):
    resource = next(bytes(r) for r in macresources.parse_file((ROOT/'raw/oregon_trail.rsrc').read_bytes())
                    if r.type == b'CODE' and r.id == segment)
    md = Cs(CS_ARCH_M68K, CS_MODE_BIG_ENDIAN | CS_MODE_M68K_000)
    return {i.address: (i.mnemonic, i.op_str) for i in md.disasm(resource[4+start:4+stop], start)}


def test_arrival_reads_unsigned_rain_and_stores_byte_dimensions_without_rng():
    code = instructions(16, 0x26ee, 0x2788)
    assert code[0x270c] == ('move.w', '#$258, d7')  # 600ft Kansas
    assert code[0x2714] == ('move.w', '#$dc, d7')   # 220ft BigBlue
    assert code[0x271a] == ('moveq', '#$28, d6')   # Green40 half-feet
    assert code[0x2724] == ('move.w', '#$3e8, d7') # Snake1000ft
    assert code[0x2730] == ('moveq', '#$0, d1')
    assert code[0x2732] == ('move.w', '$230(a0), d1')
    assert code[0x273a] == ('moveq', '#$19, d1')  # /25
    assert code[0x274a] == ('move.b', 'd1, $22a(a0)')
    assert code[0x275e] == ('add.l', 'd1, d1')
    assert code[0x2760] == ('add.l', 'd2, d1')    # rain*3
    assert code[0x2766] == ('moveq', '#$14, d1')  # /20
    assert code[0x2774] == ('moveq', '#$a, d1')   # /10
    assert code[0x277e] == ('move.b', 'd0, $22b(a0)')
    assert not any(op == '$a2(a5)' for _, op in code.values())


def test_current_switch_really_handles_index9_not_snake11():
    code = instructions(18, 0x1176, 0x11c0)
    assert code[0x1182] == ('subq.b', '#$1, d0')
    assert code[0x1186] == ('subq.b', '#$7, d0')
    assert code[0x118a] == ('subq.b', '#$1, d0') # cumulative9, NOT11
    assert code[0x118e] == ('bra.b', '$11a6')   # unmatched preserves callerD7
    assert code[0x11a6] == ('ext.l', 'd7')
    assert code[0x11b2] == ('add.l', 'd7, d0')
    assert code[0x11b4] == ('moveq', '#$64, d1')
    loss = instructions(18, 0x0256, 0x0268)
    assert loss[0x025e] == ('move.b', '$22a(a0), d0')
    assert loss[0x0262] == ('move.w', 'd0, d7')


def test_empty_supplies_skip_random_and_loss_includes_zero_and_entire_quantity():
    code = instructions(18, 0x15f4, 0x1638)
    assert code[0x15fe] == ('tst.w', '$46(a3, d0.l)')
    assert code[0x1602] == ('beq.b', '$163a')
    assert code[0x1608] == ('jsr', '$a2(a5)')
    assert code[0x1622] == ('addq.l', '#$1, d0')
    assert code[0x1626] == ('jsr', '$a2(a5)')


def test_result_rolls_losses_then_180_timer_and_defers_application_until_close():
    code = instructions(3, 0x225a, 0x22a4)
    assert code[0x228e] == ('jsr', '$c92(a5)') # CODE18:0256
    assert code[0x2292] == ('pea.l', '$b4.w')  #180
    assert code[0x2296] == ('jsr', '$a2(a5)')
    close = instructions(3, 0x23ba, 0x23cc)
    assert close[0x23c0] == ('bne.b', '$23cc')
    assert close[0x23c2] == ('jsr', '$cca(a5)') # CODE18:11c0 applies once
    assert close[0x23c6] == ('move.b', '#$1, -$1956(a5)')


@pytest.mark.parametrize('site', [0x03b8,0x03e0,0x042a,0x0468,0x048e,0x04d0,0x04f6,0x0516,
                                0x0292,0x14ce,0x1564,0x15a4,0x1608,0x1626])
def test_reported_river_draw_sites_really_call_original_bounded_random(site):
    assert instructions(18, site, site+4)[site] == ('jsr', '$a2(a5)')
