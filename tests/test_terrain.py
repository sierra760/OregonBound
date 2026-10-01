"""Synthetic hunting terrain resource cases."""
import struct
import pytest
from scripts import extract_terrain


def test_entry_sides_and_absolute_obstacles():
    data = struct.pack('>hhh8h', 2, 0, 2, -3, 5, 9, 20, 10, 21, 30, 45)
    assert extract_terrain.parse_terrain_resource(data, 17) == {
        'resource_id': 17, 'left_entry_allowed': True, 'right_entry_allowed': False,
        'obstacles': [{'top': -3, 'left': 5, 'bottom': 9, 'right': 20},
                      {'top': 10, 'left': 21, 'bottom': 30, 'right': 45}],
    }


def test_empty_terrain_and_right_entry():
    parsed = extract_terrain.parse_terrain_resource(struct.pack('>hhh', 0, -1, 0), 18)
    assert parsed['left_entry_allowed'] is False
    assert parsed['right_entry_allowed'] is True
    assert parsed['obstacles'] == []


@pytest.mark.parametrize('data', [b'', bytes(5), struct.pack('>hhh', 1, 1, -1),
    struct.pack('>hhh', 1, 1, 1), struct.pack('>hhh', 1, 1, 0) + bytes(2),
    struct.pack('>7h', 1, 1, 1, 4, 2, 4, 7), struct.pack('>7h', 1, 1, 1, 1, 9, 8, 2)])
def test_invalid_terrain_is_rejected(data):
    with pytest.raises(ValueError):
        extract_terrain.parse_terrain_resource(data, 19)
