"""Decode the original text-only PICT v1 instructions without a system font substitution.

Fail on unsupported opcodes instead of accepting the blank PNGs produced by sips.
Coordinates are original text baselines relative to the picture frame.
"""
from pathlib import Path
import json
import struct
import macresources


def decode(data: bytes, resource_id: int) -> dict:
    size, top, left, bottom, right = struct.unpack_from('>Hhhhh', data)
    if size != len(data) or data[10:12] != b'\x11\x01':
        raise ValueError('Expected a complete PICT v1 resource')
    at = 12
    font, face, point_size = 0, 0, 12
    x = y = 0
    runs = []
    ended = False
    while at < len(data):
        opcode = data[at]
        at += 1
        if opcode == 0xff:
            ended = True
            break
        if opcode == 0: continue
        if opcode == 1:
            region_size = struct.unpack_from('>H', data, at)[0]
            if region_size != 10: raise ValueError('Nonrectangular clip is unsupported')
            at += region_size
        elif opcode == 3:
            font = struct.unpack_from('>H', data, at)[0]; at += 2
        elif opcode == 4:
            face = data[at]; at += 1
        elif opcode == 0x0d:
            point_size = struct.unpack_from('>H', data, at)[0]; at += 2
        elif opcode in (0x28, 0x29, 0x2a, 0x2b):
            if opcode == 0x28:
                y, x = struct.unpack_from('>hh', data, at); at += 4
            else:
                if opcode in (0x29, 0x2b): x += data[at]; at += 1
                if opcode in (0x2a, 0x2b): y += data[at]; at += 1
            length = data[at]; at += 1
            text = data[at:at + length].decode('mac_roman'); at += length
            runs.append(dict(x=x-left, baseline=y-top, font=font, face=face, size=point_size, text=text))
        else:
            raise ValueError(f'Unsupported PICT opcode {opcode:#x} at {at-1:#x}')
    if not ended or at != len(data): raise ValueError('PICT boundary mismatch')
    return dict(id=resource_id, width=right-left, height=bottom-top, runs=runs)


if __name__ == '__main__':
    root = Path(__file__).resolve().parent.parent
    out = root/'assets'/'pictures'
    out.mkdir(exist_ok=True)
    for resource in macresources.parse_file((root/'raw'/'oregon_trail.rsrc').read_bytes()):
        if resource.type == b'PICT' and resource.id in (2050, 2051, 2052, 2070):
            value = decode(bytes(resource.data), resource.id)
            (out/f'pict_{resource.id}.json').write_text(json.dumps(value, indent=2, ensure_ascii=False)+'\n')
