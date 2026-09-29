"""Source frame indices and independently established screenshot root origin."""
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]

def test_original_frame_draw_calls_are_top_left_bottom_right_not_top_right_bottom_left():
    code=(ROOT/'assets/code_segments/CODE_5_Display.bin').read_bytes()
    assert code[0x3670:0x3682].hex()=='2f002f0072072f012f002f2dd3144eba1cc8'
    assert code[0x3692:0x36a6].hex()=='70002f002f002f0072012f012f2dd3144eba1ca4'
    assert code[0x36b8:0x36d0].hex()=='70002f004878013b72072f0170022f002f2dd3144eba1c7a'
    assert code[0x36e2:0x36f8].hex()=='70002f002f00487801f972032f012f2dd3144eba1c52'
    #5348 adapts (handle,frame,x,y,mode) into destinationRect then519a.
    assert code[0x5352:0x5366].hex()=='3d6e0012fffa3d6e0016fff8426efffc426efffe'
    assert code[0x5372:0x5380].hex()=='302e000e48c02f002f0b4ebafe1c'

def test_vertical_assets_are_exact_horizontal_mirrors():
    base=ROOT/'assets/graphics/oregon_color/images/Imag'
    left=np.array(Image.open(base/'imag_10128_01.png').convert('RGBA'))
    right=np.array(Image.open(base/'imag_10128_03.png').convert('RGBA'))
    assert left.shape == right.shape == (322,7,4)
    assert np.array_equal(left,right[:,::-1,:])

def test_all_four_source_strips_align_at_original_root_384_218():
    reference=np.array(Image.open(ROOT/'docs/reference/original-registration.png').convert('RGB'),dtype=np.int16).sum(2)
    base=ROOT/'assets/graphics/oregon_color/images/Imag'
    for frame,x,y,width,height in [(0,7,0,498,7),(1,0,0,7,322),(2,7,315,498,7),(3,505,0,7,322)]:
        source=np.array(Image.open(base/f'imag_10128_{frame:02}.png').convert('RGB'),dtype=np.int16).sum(2)
        actual=reference[218+y:218+y+height,384+x:384+x+width]
        assert source.shape == actual.shape == (height,width)
        for threshold in [255,300,384]:
            assert np.array_equal(source<threshold,actual<threshold)
