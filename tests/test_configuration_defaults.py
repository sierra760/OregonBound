"""Synthetic CONF defaults; no authored game text in fixtures."""
import pytest
from scripts.extract_configuration import parse_configuration_defaults


def fixture():
    data = bytearray(1108)
    data[0x26:0x2a] = bytes([3, 65, 0x8e, 66])
    data[0x126:0x12a] = bytes([3, 75, 101, 121])
    data[0x135:0x137] = bytes([8, 6])
    return data


def test_defaults():
    assert parse_configuration_defaults(fixture()) == dict(hint='AéB', password='Key', speed=8, huntTime=6)


@pytest.mark.parametrize('kind', ['short', 'long', 'password', 'empty', 'speed', 'hunt'])
def test_invalid(kind):
    data = fixture()
    if kind == 'short': data.pop()
    elif kind == 'long': data.append(0)
    else:
        offset, value = {'password': (0x126, 11), 'empty': (0x126, 0), 'speed': (0x135, 3), 'hunt': (0x136, 7)}[kind]
        data[offset] = value
    with pytest.raises(ValueError):
        parse_configuration_defaults(data)
