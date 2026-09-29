from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from analysis_audio import AudioQueue,extract
from extract_a5 import decode_initial_data


def test_exact_original_samples_and_fractional_rates():
    sounds={s['id']:s for s in extract()['sounds']}
    assert set(sounds)=={9001,9002,9003,9004,9006,9007}
    assert {i:s['sample_count'] for i,s in sounds.items()}=={9001:10226,9002:3664,9003:967,9004:388,9006:3919,9007:1024}
    assert sounds[9002]['sample_rate_fixed']==729236945
    assert sounds[9001]['sample_rate_fixed']==486157963
    assert sounds[9006]['sample_rate_fixed']==364618472
    assert sounds[9007]['all_silence']
    assert sounds[9002]['commands']==[(0x8051,0,20)]


def test_single_channel_fifo_waits_for_callback_and_idle():
    q=AudioQueue();q.request(9007);q.enqueue(9002);q.request(9003)
    assert q.active==9007 and q.queue==[9002,9003]
    q.pump();assert q.active==9007
    q.completed();assert q.active==9007
    q.pump();assert q.active==9002 and q.queue==[9003]
    assert q.history==[('play',9007),('stop',9007),('play',9002)]


def test_queue_capacity_and_interrupting_shots():
    q=AudioQueue();q.request(9001)
    for i in range(10):q.enqueue(i)
    assert q.queue==list(range(8))
    # Hunt CODE13:169a/16a2: clear then enqueue; starts on subsequent pump.
    q.clear();q.enqueue(9002)
    assert q.active is None and q.queue==[9002]
    q.pump();assert q.active==9002
    q.clear();q.enqueue(9003);q.pump()
    assert q.history[-2:]==[('stop',9002),('play',9003)]


def test_sound_off_stops_clears_and_muted_queue_is_consumed():
    q=AudioQueue();q.request(9001);q.enqueue(9002);q.set_enabled(False)
    assert q.active is None and q.queue==[]
    q.request(9003);assert q.queue==[]
    q.enqueue(9003);q.enqueue(9004)
    q.pump();assert q.active is None and q.queue==[9004]
    q.set_enabled(True);q.pump();assert q.active==9004


def test_binary_call_sites_and_default_sound_on():
    data=extract();calls=data['calls']
    assert next(c for c in calls if c['segment']=='CODE_13_Hunt.bin' and c['offset']==0x16a2)['resource']==9002
    assert next(c for c in calls if c['segment']=='CODE_17_Raft.bin' and c['offset']==0x1394)['resource']==9006
    assert not any(c['segment']=='CODE_4_Attract.bin' for c in calls)
    memory=decode_initial_data((ROOT/'assets/code_segments/CODE_21_A5Init.bin').read_bytes())
    assert memory[len(memory)-0x26fe]==1
    assert memory[len(memory)-0x183a]==0
    code=(ROOT/'assets/code_segments/CODE_1_Main.bin').read_bytes()
    assert code[0x31c0:0x31c8].hex()=='2d7c5061756cfffC'.lower()
    assert code[0x3148:0x314e].hex()=='4a2dd9026736'
