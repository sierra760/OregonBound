from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from analysis_death_presentation import extract
from analysis_audio import direct_calls


def code(name):return (ROOT/'assets/code_segments'/name).read_bytes()


def test_original_resources_and_callback_events():
    data=extract()
    assert data['caption']=='Burying and mourning the dead…'
    assert data['callback_events']==[0xd02,0xd96,0xdb4,0xdb4,0xda6,0xd62]
    assert data['loss_callback_events']==[0x32,0xb6,0xd6,0xd6,0xc6,0xd6]
    assert data['rectangles']['4']==[9,64,164,326]
    assert data['rectangles']['5']==[167,64,208,326]
    assert data['dialogs']['5300']['items'][0]['bounds']==dict(top=0,left=0,bottom=155,right=262)
    assert data['dialogs']['5400']['items'][0]['bounds']==dict(top=12,left=3,bottom=29,right=259)


def test_two_stage_timer_and_no_catchup_instruction_anchors():
    c3=code('CODE_3_Main2.bin');display=code('CODE_5_Display.bin')
    assert c3[0xd48:0xd50].hex()=='703c2f002f0b4ead'
    assert c3[0xd70:0xd80].hex()=='2f0b4ead07824878021c2f0b4ead077a'
    # Observed TickCount gate, single increment, reset counter before callback.
    assert display[0x2276:0x227e].hex()=='202dd3da b09f640a'.replace(' ','')
    assert display[0x229e:0x22a2].hex()=='52932013'
    assert display[0x22a8:0x22ac].hex()=='70002680'


def test_sound_queued_by_memorial_not_party_loss_callback():
    calls=direct_calls()
    assert next(c for c in calls if c['segment']=='CODE_3_Main2.bin' and c['offset']==0xd12)['operation']=='enqueue'
    assert not any(c['segment']=='CODE_10_Ending.bin' and c['offset']<0xde for c in calls)


def test_score_and_caption_inherit_original_bold_face():
    data=extract()
    assert data['root_font']==[6322,1,1,14,0]
    assert data['plain_font']==[6322,0,1,12,0]
    c10=code('CODE_10_Ending.bin');display=code('CODE_5_Display.bin')
    assert c10[0x1578:0x1582].hex()=='43edd57c20d920d930d9'
    assert display[0x2da6:0x2db4].hex()=='43e9001841e8001822d822d832d8'
    assert c10[0x3c0:0x3c6].hex()=='700c3f00a88a'
