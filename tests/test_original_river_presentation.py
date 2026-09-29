"""Original binary anchors for crossing panes, result timers and static text."""
import json
from pathlib import Path
from capstone import Cs, CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000

ROOT = Path(__file__).resolve().parents[1]


def instructions(path, start, end):
    code = (ROOT / path).read_bytes()
    decoder = Cs(CS_ARCH_M68K, CS_MODE_BIG_ENDIAN | CS_MODE_M68K_000)
    return {i.address: (i.mnemonic, i.op_str) for i in decoder.disasm(code[start:end], start)}


def test_result_uses_saved_failure_roll_safe_three_and_queued_zero_timer():
    code = instructions('assets/code_segments/CODE_3_Main2.bin', 0x2292, 0x22c6)
    assert code[0x2292] == ('pea.l', '$b4.w')
    assert code[0x2296] == ('jsr', '$a2(a5)')
    assert code[0x22ac] == ('lea.l', '-$2a8e(a5), a1')  # plain12 failure tuple
    assert code[0x22ba] == ('moveq', '#$3, d0')
    code = instructions('assets/code_segments/CODE_3_Main2.bin', 0x2322, 0x23ae)
    assert code[0x2344] == ('jsr', '$7a2(a5)')  # default ring/key1, cancel0
    assert code[0x2352] == ('move.l', '#$10a18ba, d0')  # rect10,6330
    assert code[0x235c] == ('move.l', '#$10a18b0, d0')  # rect10,6320
    assert code[0x236c] == ('move.l', '#$b4, -$1950(a5)')
    assert code[0x2386] == ('sub.l', '-$1950(a5), d0')
    assert code[0x239a] == ('jsr', '$77a(a5)')  # replacement timer, not settlement
    assert code[0x23a8] == ('addq.l', '#$1, -$1954(a5)')  # sentinel only
    assert code[0x237a] == ('jsr', '$9a2(a5)')  # queued pane replacement


def test_generic_zero_interval_runs_on_same_tick_and_positive_threshold_is_inclusive():
    code = instructions('assets/code_segments/CODE_5_Display.bin', 0x2294, 0x22b8)
    assert code[0x2294] == ('tst.b', 'd7')
    assert code[0x2298] == ('tst.l', '$4(a3)')
    assert code[0x229c] == ('bne.b', '$22c2')
    assert code[0x229e] == ('addq.l', '#$1, (a3)')
    assert code[0x22a6] == ('bcs.b', '$22c2')  # skip count<interval, not <=


def test_caption_and_result_items_use_authored_text_and_textbox_geometry():
    code = instructions('assets/code_segments/CODE_18_River.bin', 0xf04, 0xf40)
    assert code[0xf06] == ('move.w', '#$bcd, -(a7)')  # STR3021
    assert code[0xf0a] == ('moveq', '#$4, d0')
    assert code[0xf28] == ('jsr', '$892(a5)')  # centered static item
    caption = json.loads((ROOT/'assets/dialogs/ditl_5400.json').read_text())['items'][0]
    assert caption['bounds'] == dict(top=12, left=3, bottom=29, right=259)
    failure = json.loads((ROOT/'assets/dialogs/ditl_6330.json').read_text())['items'][0]
    assert failure['data'] == 'Your wagon tipped over while crossing the river.'
    assert failure['bounds'] == dict(top=8, left=10, bottom=25, right=252)
    text = instructions('raw/system7/textedit_lpch_15_unpacked.bin', 0x1a4, 0x1f6)
    assert text[0x1b0] == ('subq.w', '#$2, d0')
    assert text[0x1b4] == ('ble.b', '$218')  # fast path strictly shorter than width-2
    assert text[0x1cc] == ('addq.w', '#$1, $2(a7)')
    assert text[0x1e6] == ('subq.w', '#$1, d0')
    assert text[0x1ee] == ('asr.w', '#$1, d0')


def test_loss_column_uses_original_quantity_formatter_and_slot_order():
    code = instructions('assets/code_segments/CODE_18_River.bin', 0x104c, 0x1156)
    assert code[0x105e] == ('addi.w', '#$32, d4')  # quantity column +50
    assert code[0x1096] == ('addq.l', '#$1, d0')
    assert code[0x1098] == ('moveq', '#$2, d1')  # round raw oxen up to animals
    assert code[0x10aa] == ('jsr', '$b8a(a5)')  # CODE14 quantity formatter
    assert code[0x10c4] == ('tst.b', '-$1860(a5)')  # leader flag replaces member list
    assert code[0x1116] == ('moveq', '#$1, d7')
    assert code[0x114c] == ('addq.w', '#$1, d7')
    assert code[0x1150] == ('moveq', '#$5, d0')
