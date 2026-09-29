from pathlib import Path
import struct
from capstone import Cs, CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000

ROOT = Path(__file__).resolve().parents[1]


def blob(segment):
    return next((ROOT/'assets/code_segments').glob(f'CODE_{segment}_*')).read_bytes()


def ops(segment,start,end):
    md = Cs(CS_ARCH_M68K,CS_MODE_BIG_ENDIAN|CS_MODE_M68K_000)
    return {i.address:(i.mnemonic,i.op_str) for i in md.disasm(blob(segment)[start:end],start)}


def test_seed_once_reads_macintosh_time_and_writes_quickdraw_global():
    assert ops(9,0x0158,0x0166) == {
        0x0158:('pea.l','-$4(a6)'),0x015c:('jsr','$2da(a5)'),
        0x0160:('move.l','-$4(a6), -$200(a5)')}
    assert struct.unpack_from('>4H',blob(0),0x2da-0x12) == (0x4b4c,0x3f3c,1,0xa9f0)
    assert ops(1,0x4b50,0x4b54)[0x4b50] == ('move.l','$20c.w, (a0)')
    assert ops(9,0x0174,0x017a)[0x0174] == ('pea.l','-$182(a5)')
    assert blob(9)[0x0178:0x017a] == bytes.fromhex('a86e') # InitGraf


def test_only_direct_random_traps_are_in_shared_bounded_wrapper():
    actual=[]
    for p in (ROOT/'assets/code_segments').glob('CODE_*'):
        # Even-aligned raw scan includes embedded data; fixture has only these two.
        raw=p.read_bytes()
        actual += [(p.name,i) for i in range(0,len(raw)-1,2) if raw[i:i+2] == bytes.fromhex('a861')]
    assert sorted(actual) == [('CODE_1_Main.bin',0x0766),('CODE_1_Main.bin',0x0776)]
    for segment,offsets in [(4,[0xc0,0x202,0x29e,0x382]),(13,[0x338,0x360,0xf06]),
                            (17,[0x5cc,0xe8c,0x185a,0x18c2,0x1918,0x1960,0x1982])]:
        for offset in offsets:assert blob(segment)[offset:offset+4] == bytes.fromhex('4ead00a2')


def test_daily_model_is_vbl_task_not_isolated_scene_clock():
    assert struct.unpack_from('>4H',blob(0),0xbca-0x12) == (0,0x3f3c,16,0xa9f0)
    install=ops(9,0xa52,0xa80)
    assert install[0xa52] == ('lea.l','$bca(a5), a0')
    assert install[0xa62] == ('move.w','#$4b, $e(a0)')
    assert blob(9)[0xa7c:0xa7e] == bytes.fromhex('a033') # VInstall
    assert ops(16,8,0x12)[8] == ('movea.l','-$4(a0), a5')
    assert ops(16,8,0x12)[0xe] == ('jsr','$1da2(pc)')


def test_onshore_timer_remains_sixty_between_submit_and_close():
    assert ops(6,0x24d6,0x24e6)[0x24d6] == ('moveq','#$3c, d0')
    assert ops(6,0x24d6,0x24e6)[0x24dc] == ('jsr','$77a(a5)')
    assert ops(6,0x25c6,0x25d4)[0x25ca] == ('move.b','#$1, -$1a1e(a5)')
    assert ops(6,0x24f0,0x24f8)[0x24f4] == ('beq.w','$259e')
    # CODE5 resets elapsed count, leaves period unchanged, then invokes callback.
    timer=ops(5,0x229e,0x22c2)
    assert timer[0x22aa] == ('move.l','d0, (a3)')
    assert timer[0x22be] == ('jsr','(a0)')


def test_raft_packet_uses_live_signed_inventory_before_delayed_application():
    build = ops(3,0x1ec6,0x1ef2)
    assert build[0x1ecc] == ('move.w','$46(a3, d0.l), d0')
    assert build[0x1ed0] == ('ext.l','d0')
    assert build[0x1ed8] == ('lea.l','-$19d6(a5), a0')
    assert build[0x1ee2] == ('sub.l','d1, d0')
    assert build[0x1eee] == ('move.w','d0, (a0, d1.l)')
    apply = ops(16,0x145e,0x148e)
    assert apply[0x1462] == ('ext.l','d1')
    assert apply[0x146a] == ('cmp.l','d0, d1')
    assert apply[0x146c] == ('bge.b','$1484')
    assert apply[0x147e] == ('sub.w','d1, $46(a3, d0.l)')
