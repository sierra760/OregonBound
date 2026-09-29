"""Original single-channel sound queue and exact snd resource metadata.

Offsets are CODE payload offsets after the four-byte segment header.
The note-sequence branch exists in CODE1 but has no enabling write/resources in
this release. This oracle implements only reachable sampled-sound scheduling.
"""
from __future__ import annotations
from dataclasses import dataclass, field
from pathlib import Path
import argparse
import json
import struct
import macresources

ROOT = Path(__file__).resolve().parents[1]
SOUND_JUMPS = {0x1ca: 'clear', 0x1d2: 'request', 0x1da: 'enqueue', 0x1e2: 'wait'}


def decode_sound(data: bytes) -> dict:
    fmt, synth_count = struct.unpack_from('>HH', data)
    if fmt != 1: raise ValueError('Expected original format1')
    offset = 4+synth_count*6
    count, = struct.unpack_from('>H',data,offset)
    commands = [struct.unpack_from('>HHI',data,offset+2+8*i) for i in range(count)]
    header = next(value for command,_,value in commands if command == 0x8051)
    pointer,length,rate,loop_start,loop_end,encoding,base = struct.unpack_from('>IIIIIBB',data,header)
    if pointer != 0 or encoding != 0: raise ValueError('Expected inline unsigned8 PCM')
    pcm = data[header+22:header+22+length]
    if len(pcm) != length: raise ValueError('Truncated sound')
    return dict(format=fmt, commands=commands, sample_count=length, sample_rate_fixed=rate,
                sample_rate=rate/65536, duration_seconds=length*65536/rate,
                loop_start=loop_start,loop_end=loop_end,base_frequency=base,
                pcm_offset=header+22,pcm=pcm)


def direct_calls(root: Path = ROOT) -> list[dict]:
    """Exact jsr d16(a5) byte signatures; independent of inline jump-table decoding."""
    calls=[]
    for path in sorted((root/'assets/code_segments').glob('CODE_*_*.bin')):
        data=path.read_bytes()
        for displacement,name in SOUND_JUMPS.items():
            signature=b'\x4e\xad'+struct.pack('>H',displacement)
            offset=data.find(signature)
            while offset != -1:
                if offset%2 == 0:
                    resource = struct.unpack_from('>h',data,offset-2)[0] if data[offset-4:offset-2]==b'\x48\x78' else None
                    calls.append(dict(segment=path.name,offset=offset,operation=name,resource=resource))
                offset=data.find(signature,offset+1)
    return sorted(calls,key=lambda row:(row['segment'],row['offset']))


@dataclass
class AudioQueue:
    """CODE1:313c/318a/31e4; completion callback and idle pumping stay separate."""
    enabled: bool = True
    channel_available: bool = True
    active: int|None = None
    callback_complete: bool = False
    queue: list[int] = field(default_factory=list)
    history: list[tuple[str,int]] = field(default_factory=list)

    def request(self, resource: int) -> None:
        if not self.enabled or not self.channel_available: return
        if self.active is None:
            self.active=resource;self.callback_complete=False
            self.history.append(('play',resource))
        else: self.enqueue(resource)

    def enqueue(self, resource: int) -> None:
        # Deliberately does not test SoundOn (318a); pump consumes muted entries.
        if len(self.queue)<8:self.queue.append(resource)

    def completed(self) -> None:
        if self.active is not None:self.callback_complete=True

    def pump(self) -> None:
        if not self.channel_available:return
        if self.active is not None and not self.callback_complete:return
        if self.callback_complete:self.stop()
        if self.queue:
            resource=self.queue[0]
            self.request(resource)
            self.queue.pop(0)

    def stop(self) -> None:
        if self.active is not None:self.history.append(('stop',self.active))
        self.active=None;self.callback_complete=False

    def clear(self) -> None:
        self.stop();self.queue.clear()

    def set_enabled(self, value: bool) -> None:
        self.enabled=value
        if not value:self.clear()


def extract(root: Path = ROOT) -> dict:
    resources=list(macresources.parse_file((root/'raw/oregon_trail.rsrc').read_bytes()))
    sounds=[]
    for resource in resources:
        if resource.type != b'snd ':continue
        sound=decode_sound(bytes(resource.data));pcm=sound.pop('pcm')
        sounds.append(dict(id=resource.id,name=resource.name,**sound,all_silence=all(v==128 for v in pcm)))
    return dict(sounds=sorted(sounds,key=lambda row:row['id']),calls=direct_calls(root))


if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path)
    args=parser.parse_args();text=json.dumps(extract(),indent=2)+'\n'
    if args.output:args.output.write_text(text)
    else:print(text,end='')
