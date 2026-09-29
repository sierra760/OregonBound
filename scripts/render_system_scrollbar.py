"""Assemble System 7 CDEF1's vertical color parts at requested RGB values.

This is pre-device-CLUT RGB rendering. Real indexed Color2Index can quantize
these colors or make CDEF1 choose its monochrome branch. See the evidence doc.
"""
from pathlib import Path
import argparse
import json
import struct
from PIL import Image, ImageDraw


def base_colors(code):
    return [struct.unpack_from('>HHH', code, 0xcd2 + i*6) for i in range(15)]


def color(code, index, overrides=None):
    bases = base_colors(code)
    bases = {i: v for i, v in enumerate(bases)} | (overrides or {})
    if index < 16:
        return bases[index]
    first, second, weight = struct.unpack_from('>HHH', code, 0xd2c + (index-16)*6)
    # CDEF1:0826–085a: unsigned multiply high word of ABS(delta), then restore sign.
    # Division is65536, NOT65535: weight15 can leave a one-unit residual.
    return tuple(a + (1 if b >= a else -1) * ((abs(b-a) * weight * 0x1111) >> 16)
                 for a,b in zip(bases[first],bases[second]))


def pixels(folder, resource_id):
    b=(folder / f'system7_scrollbar_pixs_{resource_id}.bin').read_bytes()
    stride,top,left,bottom,right,depth=struct.unpack_from('>HhhhhH',b)
    assert depth == 1
    stride &= 0x3fff
    return [[bool(b[12+y*stride+x//8] & (0x80>>(x%8))) for x in range(right-left)]
            for y in range(bottom-top)]


def render(folder, output):
    code=(folder/'system7_cdef_1_unpacked.bin').read_bytes()
    rgb16={i: color(code,i) for i in list(range(15))+list(range(16,38))}
    rgba={i: tuple(c>>8 for c in rgb)+(255,) for i,rgb in rgb16.items()}
    # Runtime control entry1 can be the game's paper color. It affects the arrow
    # top/left bevel only; all missing color entries fall back through CDEF1:0a0e.
    paper=(0xff00,0xf66d,0x8997)
    game_rgba={**rgba,1:tuple(c>>8 for c in paper)+(255,)}
    output.mkdir(parents=True,exist_ok=True)
    variants=[]
    for palette_name,palette in [('system',rgba),('game_paper',game_rgba)]:
        atlas=Image.new('RGBA',(96,16))
        for direction,ids in [('up',(-10206,-10205)),('down',(-10204,-10203))]:
            for state in ['normal','pressed','disabled']:
                disabled=state=='disabled'; pressed=state=='pressed'
                img=Image.new('RGBA',(16,16),palette[32 if disabled else 33])
                for resource_id,ink in [(ids[0],28 if disabled else 0 if pressed else 37),
                                        (ids[1],None if disabled else 0 if pressed else 35)]:
                    if ink is None: continue
                    for y,row in enumerate(pixels(folder,resource_id)):
                        for x,bit in enumerate(row):
                            if bit: img.putpixel((x,y),palette[ink])
                draw=ImageDraw.Draw(img)
                if not disabled:
                    # CDEF1:0536–0566: inset(1,1), B20 then B50, restore rect.
                    draw.line([(1,14),(1,1),(14,1)],fill=palette[1])
                    draw.line([(1,14),(14,14),(14,1)],fill=palette[28])
                draw.rectangle((0,0,15,15),outline=palette[0])
                index=(0 if direction=='up' else 3)+['normal','pressed','disabled'].index(state)
                atlas.paste(img,(index*16,0))
                if palette_name=='system':variants.append({'name':f'{direction}_{state}','rect':[index*16,0,16,16]})
        atlas.save(output/f'system7_scrollbar_arrows_{palette_name}.png')
    thumb=Image.new('RGBA',(14,16),rgba[18]);d=ImageDraw.Draw(thumb)
    # CDEF1:0318–0392. Source thumb Rect(0,0,16,14), rightward top pixel
    # is outside this14px part and covered by final control FrameRect anyway.
    d.line([(0,0),(13,0)],fill=rgba[29])
    d.line([(0,15),(0,1),(13,1)],fill=rgba[34])
    d.line([(0,15),(13,15),(13,1)],fill=rgba[37])
    # CDEF1:0394–03be; packed InsetRect argument has dv2,dh3.
    # Final source/destination are both6x10, with no scaling.
    grip=pixels(folder,-10208)
    for y,row in enumerate(grip):
        for x,bit in enumerate(row): thumb.putpixel((4+x,3+y),rgba[36 if bit else 34])
    d.line([(4,3),(9,3)],fill=rgba[35]) # CDEF1:03c2–03f2.
    thumb.save(output/'system7_scrollbar_thumb_rgb.png')
    pattern=bytes.fromhex('8822882288228822')
    track=Image.new('RGBA',(8,8))
    for y in range(8):
        for x in range(8): track.putpixel((x,y),rgba[28 if pattern[y]&(0x80>>x) else 22])
    track.save(output/'system7_scrollbar_track_rgb.png')
    Image.new('RGBA',(1,1),rgba[32]).save(output/'system7_scrollbar_disabled_rgb.png')
    # Representative local pattern phase0; actual QuickDraw pattern is aligned
    # to port coordinates, so consumers retain the original control origin.
    examples=Image.new('RGBA',(48,104))
    arrows=Image.open(output/'system7_scrollbar_arrows_system.png')
    for index,value in enumerate([None,0,50]):
        bar=Image.new('RGBA',(16,104),rgba[32])
        if value is not None:
            for y in range(16,88):
                for x in range(1,15):bar.putpixel((x,y),track.getpixel((x%8,y%8)))
            top=16+(56*value//100)
            bar.paste(thumb,(1,top))
        arrow_index=2 if value is None else 0
        bar.paste(arrows.crop((arrow_index*16,0,arrow_index*16+16,16)),(0,0))
        bar.paste(arrows.crop(((arrow_index+3)*16,0,(arrow_index+4)*16,16)),(0,88))
        ImageDraw.Draw(bar).rectangle((0,0,15,103),outline=rgba[0])
        examples.paste(bar,(index*16,0))
    examples.save(output/'system7_scrollbar_examples_rgb.png')
    manifest={'schema_version':1,'source':'system7_scrollbar.json','rendering':'requested RGB, before device Color2Index/CLUT',
              'color_rgb16':rgb16,'color_rgba8':rgba,'arrow_variants':variants,
              'system_arrow_atlas':'system7_scrollbar_arrows_system.png',
              'game_paper_arrow_atlas':'system7_scrollbar_arrows_game_paper.png',
              'game_paper_override':{'1':paper},
              'thumb':{'file':'system7_scrollbar_thumb_rgb.png','width':14,'height':16},
              'track':{'file':'system7_scrollbar_track_rgb.png','width':8,'height':8,
                       'pattern_hex':pattern.hex(),'foreground_color':28,'background_color':22},
              'disabled_fill':{'file':'system7_scrollbar_disabled_rgb.png','color':32,'rgba':rgba[32]},
              'limitations':['No live GDevice CLUT quantization','No RGB2Index distinguishability fallback',
                             'Game-paper variant is an explicit entry1 override, not proof of live AuxCtl table']}
    (output/'system7_scrollbar_color.json').write_text(json.dumps(manifest,indent=2)+'\n')
    return manifest

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,default=Path('assets/system_controls'))
    p.add_argument('--output',type=Path,default=Path('assets/system_controls'))
    args=p.parse_args();render(args.source,args.output)
