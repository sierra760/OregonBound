"""Recover compact journal fixed lengths from CODE14 and inspect used bytes."""
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]


def fixed_sizes(code=None):
    if code is None:
        code = (ROOT / 'assets/code_segments/CODE_14_Message.bin').read_bytes()
    def bound(address):
        if code[address] != 0x72:
            raise ValueError(f'Expected moveq bound at CODE14:{address:04x}')
        return code[address + 1]
    def quick(address):
        opcode = struct.unpack_from('>H', code, address)[0]
        if opcode & 0xf1ff != 0x508b:
            raise ValueError(f'Expected addq.l to A3 at CODE14:{address:04x}')
        return ((opcode >> 9) & 7) or 8
    def immediate(address):
        if code[address:address+2] != b'\xd6\xfc':
            raise ValueError(f'Expected adda.w immediate at CODE14:{address:04x}')
        return struct.unpack_from('>H', code, address + 2)[0]
    ranges = [(0, bound(0x1b0c), quick(0x1b12)),
              (bound(0x1b1c), bound(0x1b26), quick(0x1b2c)),
              (bound(0x1b36), bound(0x1b40), immediate(0x1b46)),
              (bound(0x1b52), bound(0x1b5c), immediate(0x1b62)),
              (bound(0x1b6c), bound(0x1b76), quick(0x1b7c)),
              (bound(0x1b84), bound(0x1b8e), quick(0x1b94))]
    sizes = {opcode: size for low, high, size in ranges for opcode in range(low, high + 1)}
    sizes[bound(0x1af6)] = quick(0x1afc)
    return sizes


def records(data: bytes):
    sizes = fixed_sizes()
    output = []
    pos = 0
    while pos < len(data):
        opcode = data[pos]
        if opcode in sizes:
            end = pos + sizes[opcode]
        elif opcode in (118, 119):
            end = pos + 2
            for _ in range(2 if opcode == 118 else 1):
                if end >= len(data):
                    raise ValueError(f'Truncated Pascal field at {end}')
                end += 1 + data[end]
            end += (end - pos) & 1
        else:
            raise ValueError(f'Unsupported opcode {opcode} at {pos}')
        if end > len(data):
            raise ValueError(f'Truncated record at {pos}')
        record = dict(offset=pos, opcode=opcode, length=end-pos, hex=data[pos:end].hex())
        if opcode == 120:
            record['date'] = dict(year=struct.unpack_from('>H', data, pos+2)[0], month=data[pos+4], day=data[pos+5])
        output.append(record)
        pos = end
    return output
