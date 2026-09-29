from pathlib import Path
import struct
from capstone import Cs, CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000

ROOT = Path(__file__).resolve().parents[1]

def code(segment):
    return next((ROOT/'assets/code_segments').glob(f'CODE_{segment}_*')).read_bytes()

def ops(segment,start,end):
    md = Cs(CS_ARCH_M68K,CS_MODE_BIG_ENDIAN | CS_MODE_M68K_000)
    return {i.address:(i.mnemonic,i.op_str) for i in md.disasm(code(segment)[start:end],start)}

def test_focus_callback_rejects_other_windows_and_duplicate_activation_states():
    initial = ops(1,0x1958,0x1960)
    assert initial[0x195c] == ('clr.b','-$2044(a5)')
    focus = ops(1,0x19e0,0x1aaa)
    assert focus[0x19ec] == ('cmpa.l','-$26dc(a5), a4')
    assert focus[0x19f0] == ('bne.w','$1aa4')
    assert focus[0x1a02] == ('tst.b','-$2044(a5)')
    assert focus[0x1a06] == ('beq.b','$1a5a')
    assert focus[0x1a08] == ('clr.b','-$2044(a5)')
    assert focus[0x1a62] == ('move.b','-$2044(a5), d0')
    assert focus[0x1a66] == ('bne.b','$1aa4')
    assert focus[0x1a68] == ('move.b','#$1, -$2044(a5)')
    assert focus[0x1a0c] == ('tst.w','-$278c(a5)')
    assert focus[0x1a14] == ('moveq','#$6, d0')
    assert focus[0x1a18] == ('dc.w','$a939') # enable Exit
    assert focus[0x1a1c] == ('moveq','#$1, d0')
    assert focus[0x1a20] == ('dc.w','$a93a') # disable Load
    assert focus[0x1a74] == ('dc.w','$a93a')
    assert focus[0x1a7c] == ('dc.w','$a93a')

def test_window_activation_and_application_resume_have_distinct_event_sources():
    activation = ops(1,0x1c86,0x1ca4)
    assert activation[0x1c8c] == ('moveq','#$1, d1')
    assert activation[0x1c9a] == ('move.l','-$12(a6), -(a7)') # event message window
    assert activation[0x1c9e] == ('jsr','$19e0(pc)')
    resume = ops(1,0x1cce,0x1cf6)
    assert resume[0x1cce] == ('moveq','#$18, d0')
    assert resume[0x1cd6] == ('moveq','#$1, d0')
    assert resume[0x1cda] == ('bne.b','$1d0c')
    assert resume[0x1cde] == ('and.l','-$12(a6), d0')
    assert resume[0x1cee] == ('dc.w','$a924') # FrontWindow
    assert resume[0x1cf0] == ('jsr','$19e0(pc)')

def test_game_and_management_menu_headers_follow_real_focus_edges():
    focus = ops(1,0x1a34,0x1aa4)
    assert focus[0x1a42] == ('pea.l','$3eb.w')
    assert focus[0x1a46] == ('jsr','$922(a5)')
    assert focus[0x1a4a] == ('pea.l','$3ec.w')
    assert focus[0x1a4e] == ('jsr','$922(a5)')
    assert focus[0x1a8c] == ('pea.l','$3eb.w')
    assert focus[0x1a90] == ('jsr','$91a(a5)')
    assert focus[0x1a94] == ('pea.l','$3ec.w')
    assert focus[0x1a98] == ('jsr','$91a(a5)')

def test_about_heap_and_purge_space_are_not_host_physical_memory():
    about = ops(2,0x9d2,0xa60)
    assert about[0x9de] == ('move.l','$130.w, d0')
    assert about[0x9e2] == ('sub.l','$2aa.w, d0')
    assert about[0xa14] == ('jsr','$3a2(a5)')
    assert struct.unpack_from('>4H',code(0),0x3a2-0x12) == (0x4ef4,0x3f3c,1,0xa9f0)
    purge = ops(1,0x4ef4,0x4f08)
    assert purge[0x4ef4] == ('dc.w','$a162')
    assert purge[0x4efa] == ('move.l','a0, (a1)')
    assert purge[0x4f00] == ('move.l','d0, (a1)')
    size = ops(2,0x3c2,0x3ea)
    assert size[0x3c6] == ('move.l','#$400, d1')
    assert size[0x3cc] == ('jsr','$262(a5)')
    assert size[0x3e4] == ('moveq','#$4b, d0')
