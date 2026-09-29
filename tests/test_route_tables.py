"""Original route evidence: protect branch direction and actual resource frames."""
import json
from pathlib import Path
import sys

import macresources
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from extract_route_tables import ROOT, extract, next_leg


@pytest.fixture(scope='module')
def routes():
    return extract()


def test_original_branch_lengths_and_destinations(routes):
    pairs = routes['raw_distance_pairs']
    # CODE16:0x0d54 selects alternate BEFORE incrementing index again.
    assert next_leg(6, 0, pairs) == (7, 57)  # South Pass -> Bridger
    assert next_leg(6, 1, pairs) == (8, 125)  # South Pass -> Green
    assert next_leg(7, 0, pairs) == (8, 162)
    assert next_leg(13, 0, pairs) == (14, 55)
    assert next_leg(13, 2, pairs) == (15, 125)
    assert next_leg(14, 2, pairs) == (15, 120)
    assert next_leg(6, 2, pairs) == (7, 57)  # unrelated flag must not skip


def test_initial_and_final_fixed_lengths(routes):
    assert next_leg(-1, 0, routes['raw_distance_pairs']) == (0, 102)
    assert next_leg(15, 0, routes['raw_distance_pairs']) == (16, 100)
    with pytest.raises(ValueError):
        next_leg(16, 0, routes['raw_distance_pairs'])
    assert routes['rafting']['miles'] is None
    assert routes['terminal']['scene'] is None
    assert routes['landmarks'][-1]['name'] == 'The Dalles'
    assert routes['rafting']['name'] == 'raft down the Columbia River'


def test_every_landmark_scene_exists_in_both_original_forks(routes):
    for filename, field in [('oregon_trail', 'monochrome_resource_id'),
                            ('oregon_color', 'resource_id')]:
        resources = {r.id: bytes(r.data) for r in macresources.parse_file(
            (ROOT / f'raw/{filename}.rsrc').read_bytes()) if r.type == b'Imag'}
        for node in routes['landmarks']:
            scene = node['scene']
            assert scene[field] in resources, node['id']
            assert scene['frame'] < int.from_bytes(resources[scene[field]][:2], 'big')


def test_scene_mapping_distinguishes_forts_and_shares_river_frame(routes):
    nodes = {n['id']: n for n in routes['landmarks']}
    assert nodes['independence']['scene_code'] == 0
    assert nodes['bridger']['scene'] == {'resource_id': 15303,
                                      'monochrome_resource_id': 5303, 'frame': 0}
    assert nodes['hall']['scene']['resource_id'] == 15304
    assert nodes['hall']['scene']['frame'] == 0
    assert nodes['dalles']['scene']['resource_id'] == 15306
    assert nodes['dalles']['scene']['frame'] == 0
    for key in ['kansas', 'big-blue', 'green', 'snake']:
        assert nodes[key]['scene']['resource_id'] == 15306
        assert nodes[key]['scene']['frame'] == 1


def test_code_evidence_for_table_addressing_and_scene_divisor():
    model = (ROOT / 'assets/code_segments/CODE_16_Model.bin').read_bytes()
    display = (ROOT / 'assets/code_segments/CODE_6_Main3.bin').read_bytes()
    # LEA -0x2800(A5), A0; byte offset3 is alternate word's low byte.
    assert model[0xd60:0xd64].hex() == '41edd800'
    assert model[0xd68:0xd6e].hex() == '137000030239'
    # Scene is signed index*2 from A5-0x27b6, then remainder/division by2.
    assert display[0x1566:0x156a].hex() == '41edd84a'
    assert display[0x1572:0x1578].hex() == '72024ead0272'
    assert display[0x157e:0x1584].hex() == '72024ead0262'


def test_committed_export_matches_current_original_bytes(routes):
    assert json.loads((ROOT / 'assets/metadata/original_routes.json').read_text()) == routes
