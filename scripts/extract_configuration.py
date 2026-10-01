"""Decode recovered preference fields in Macintosh 1.1/CD 1.2 CONF1000."""
from __future__ import annotations


def parse_configuration_defaults(data: bytes) -> dict:
    if len(data) != 1108:
        raise ValueError('Unsupported CONF1000 payload length')
    if not 1 <= data[0x126] <= 10:
        raise ValueError('Invalid CONF1000 password length')
    speed, hunt = data[0x135:0x137]
    if speed not in (2, 4, 8) or hunt not in range(1, 7):
        raise ValueError('Invalid CONF1000 timing defaults')

    def string(offset):
        return bytes(data[offset + 1:offset + 1 + data[offset]]).decode('mac_roman')

    return dict(hint=string(0x26), password=string(0x126), speed=speed, huntTime=hunt)
