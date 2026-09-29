"""Action/day scheduler anchors against supplied CODE and CONF resources."""
from pathlib import Path
import sys
from capstone import Cs, CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
import macresources


def resource(kind, ident):
    return next(bytes(r) for r in macresources.parse_file((ROOT/'raw/oregon_trail.rsrc').read_bytes())
                if r.type == kind and r.id == ident)


def instructions(segment, start, stop):
    md = Cs(CS_ARCH_M68K, CS_MODE_BIG_ENDIAN | CS_MODE_M68K_000)
    return {i.address: (i.mnemonic, i.op_str)
            for i in md.disasm(resource(b'CODE', segment)[start+4:stop+4], start)}


def test_rest_transmits_requested_count_unchanged_and_does_not_advance_day():
    ui = instructions(1, 0x2ef4, 0x2f0a)
    assert ui[0x2ef8] == ('move.b', '#$3, -$a(a6)')
    assert ui[0x2f04] == ('move.b', '$b(a6), -$8(a6)')
    command = instructions(16, 0x0c74, 0x0c90)
    assert command[0x0c7c] == ('move.b', '$2(a0), $7(a1)')
    assert command[0x0c86] == ('ori.b', '#$4, $5(a0)')
    assert not any(m == 'jsr' for m, _ in command.values())


def test_continue_and_timeout_never_clear_rest_counter_or_rest_flag():
    pause = instructions(16, 0x0cd2, 0x0ce0)
    assert pause[0x0cd6] == ('andi.b', '#$fd, $5(a0)')
    resume = instructions(16, 0x0da6, 0x0db8)
    assert resume[0x0daa] == ('ori.b', '#$2, $5(a0)')
    assert resume[0x0db0] == ('clr.b', '-$1bf0(a5)')


def test_hunt_starts_without_day_and_completion_increments_rest_byte():
    start = instructions(16, 0x0e3c, 0x0e4e)
    assert start[0x0e3c] == ('ori.b', '#$10, (a3)')
    assert start[0x0e44] == ('andi.b', '#$fd, $5(a0)')
    end = instructions(16, 0x0e8a, 0x0ea0)
    assert end[0x0e8e] == ('addq.b', '#$1, $7(a0)')
    assert end[0x0e96] == ('ori.b', '#$4, $5(a0)')


def test_rest_cleanup_date_and_event_order_are_literal_n_plus_one():
    day = instructions(16, 0x1ad2, 0x1aee)
    assert day[0x1ad2] == ('jsr', '$1e9e(pc)') # date first
    assert day[0x1ae0] == ('moveq', '#$c, d1')
    assert day[0x1ae4] == ('bne.b', '$1aea')   # pre-counter rest/delay skips events
    assert day[0x1ae6] == ('jsr', '$309a(pc)')
    assert day[0x1aea] == ('jsr', '$1f24(pc)')
    counter = instructions(16, 0x1f74, 0x1f94)
    assert counter[0x1f7e] == ('bne.b', '$1f8c')
    assert counter[0x1f84] == ('andi.b', '#$fb, $5(a0)') # clear only if already0
    assert counter[0x1f90] == ('subq.b', '#$1, $7(a0)')  # retainflag when1becomes0
    arrival = instructions(16, 0x263a, 0x2642)
    assert arrival[0x263c] == ('move.b', '-$1(a6), d0')
    assert arrival[0x2640] == ('bne.b', '$265c')


def test_timer_default_config_copy_and_speed_values():
    # CODE8 copies CONF+26 to A5-2a7a; speed is the byte at A5-296b.
    assert resource(b'CONF',1000)[0x26 + 0x2a7a - 0x296b] == 4
    copy = instructions(8, 0x1090, 0x10a8)
    assert copy[0x1094] == ('lea.l', '-$2a7a(a5), a1')
    assert copy[0x1098] == ('lea.l', '$26(a0), a0')
    setup = instructions(16, 0x0564, 0x0572)
    assert setup[0x056c] == ('move.b', '-$296b(a5), $243(a0)')
    timer = instructions(16, 0x1da2, 0x1db0)
    assert timer[0x1daa] == ('move.w', '#$4b, $a(a3)')
    speeds = instructions(15, 0x1af2, 0x1b08)
    assert speeds[0x1af2] == ('move.b', '#$8, -$296b(a5)')
    assert speeds[0x1afa] == ('move.b', '#$4, -$296b(a5)')
    assert speeds[0x1b02] == ('move.b', '#$2, -$296b(a5)')


def test_wagon_label_priority_crossing_rest_stopped_delay_moving():
    code = instructions(3, 0x2a8c, 0x2ae2)
    assert code[0x2a90] == ('moveq', '#$b, d5')
    assert code[0x2aa4] == ('moveq', '#$4, d5')
    assert code[0x2ab8] == ('moveq', '#$a, d5')
    assert code[0x2acc] == ('moveq', '#$5, d5')
    assert code[0x2ae0] == ('moveq', '#$9, d5')
