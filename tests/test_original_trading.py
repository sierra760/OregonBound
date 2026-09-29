"""Original CODE3 trading rules, with injected bounded random results."""
from pathlib import Path
import sys
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from analysis_trading import (Wagon, Request, Offer, make_request, counteroffer,
                              present, resolve, payment_quantity, CAPACITY, UNIT_CENTS)
from analysis_trail_events import ScriptedRandom


def test_request_capacity_uses_raw_oxen_and_allows_cash():
    w = Wagon([38, 50, 1980, 3, 3, 3, 2000], 0)
    assert make_request(w, 0, 1) == Request(0, 1)
    with pytest.raises(ValueError, match='grass'): make_request(w, 0, 2)
    with pytest.raises(ValueError, match='space'): make_request(w, 3, 1)
    assert make_request(w, 7, 5000) == Request(7, 500000)


@pytest.mark.parametrize('q', [0, -1])
def test_nonpositive_request_rejected(q):
    with pytest.raises(ValueError, match='quantity'): make_request(Wagon(), 3, q)


@pytest.mark.parametrize('roll,found', [(333, False), (334, True)])
def test_single_wagon_availability_strict_boundary(roll, found):
    rng = ScriptedRandom([roll] + ([7, 20] if found else []) + [6, 2])
    result = present(Wagon(), Request(3, 1), rng)
    assert (result.offer is not None) == found
    assert result.portrait == 2
    assert [t[:2] for t in rng.trace][-2:] == [(0x4712, 9)] * 2


def test_requested_type_rerolls_without_price_draw():
    rng = ScriptedRandom([3, 3, 7, 20])
    offer = counteroffer(Wagon(), Request(3, 1), rng)
    assert offer == Offer(Request(3, 1), 7, 1000)
    assert [t[:2] for t in rng.trace] == [(0x3f7c, 8)] * 3 + [(0x4096, 41)]


@pytest.mark.parametrize('roll,qty', [(0, 40), (20, 50), (40, 60)])
def test_food_counterpayment_percentage_inclusive(roll, qty):
    assert counteroffer(Wagon(), Request(3, 1), ScriptedRandom([6, roll])).quantity == qty


def test_bullets_are_ten_cents_each_and_minimum_one():
    assert payment_quantity(Request(2, 20), 7, 100) == 2
    assert payment_quantity(Request(6, 1), 3, 80) == 1


def test_float32_ratio_is_preserved_before_truncation():
    assert payment_quantity(Request(1, 15), 3, 90) == 13  # .9f below .9
    assert payment_quantity(Request(3, 1), 0, 100) == 1  # .5 ->0 ->minimum1
    assert payment_quantity(Request(3, 1), 6, 90) == 44  # 50 * .9f is <45
    assert payment_quantity(Request(3, 1), 7, 99) == 9


def test_last_ox_rejected_but_other_exact_available_quantity_allowed():
    w = Wagon([2, 1, 0, 0, 0, 0, 0], 0)
    rng = ScriptedRandom([0, 20, 1, 20])
    assert counteroffer(w, Request(3, 1), rng) == Offer(Request(3, 1), 1, 1)


def test_odd_raw_oxen_floor_affordability_keeps_at_least_one_whole():
    w = Wagon([3, 1, 0, 0, 0, 0, 0], 0)
    assert counteroffer(w, Request(3, 1), ScriptedRandom([0, 20, 1, 20])).item == 1


def test_rejected_candidate_can_be_retried_with_new_price():
    w = Wagon([0, 0, 0, 0, 0, 0, 50], 0)
    assert counteroffer(w, Request(3, 1), ScriptedRandom([6, 40, 6, 0])).quantity == 40


def test_all_seven_rejected_types_stop_search_no_gift():
    rng = ScriptedRandom([i for t in [0, 1, 2, 4, 5, 6, 7] for i in [t, 20]])
    assert counteroffer(Wagon([0]*7, 0), Request(3, 1), rng) is None
    assert len(rng.trace) == 14


def test_receive_cash_and_pay_oxen_raw_conversions():
    w = Wagon([6, 0, 0, 0, 0, 0, 0], 0)
    offer = counteroffer(w, Request(7, 4000), ScriptedRandom([0, 20]))
    assert offer.quantity == 2
    result = resolve(w, offer, True)
    assert result.status == 'accepted' and result.wagon.stock[0] == 2
    assert result.wagon.cash == 4000 and w.stock[0] == 6


def test_acquire_replacement_without_day_or_repair_side_effect():
    w = Wagon([2, 0, 0, 0, 0, 0, 0], 1000)
    offer = counteroffer(w, make_request(w, 3, 1), ScriptedRandom([7, 20]))
    result = resolve(w, offer, True)
    assert result.wagon.stock[3] == 1 and result.wagon.cash == 0
    assert result.journal_opcode == 0x4f and result.days == 0


def test_refusal_and_no_offer_have_no_resource_journal_or_day_cost():
    w = Wagon()
    for offer in [None, Offer(Request(3, 1), 7, 1000)]:
        result = resolve(w, offer, False)
        assert result.wagon == w and result.days == 0 and result.journal_opcode is None


def test_acceptance_rechecks_capacity_before_payment():
    w = Wagon([2, 0, 0, 3, 0, 0, 0], 0)
    offer = Offer(Request(3, 1), 7, 1000)
    assert resolve(w, offer, True).journal_opcode == 0x4e
    w.stock[3] = 0
    result = resolve(w, offer, True)
    assert result.journal_opcode == 0x4c and result.wagon == w


def test_tables_and_branch_bytes_match_original():
    from extract_a5 import decode_initial_data
    from macresources import parse_file
    root = Path(__file__).resolve().parents[1]
    resources = list(parse_file((root/'raw/oregon_trail.rsrc').read_bytes()))
    code21 = bytes(next(r for r in resources if r.type == b'CODE' and r.id == 21))
    import struct
    data = decode_initial_data(code21[4:])
    assert tuple(CAPACITY) == struct.unpack_from('>7H', data, len(data)-0x2896)
    base = list(struct.unpack_from('>7H', data, len(data)-0x2876))
    base[2] //= 20
    assert tuple(UNIT_CENTS) == tuple(base + [100])
    code3 = (root/'assets/code_segments/CODE_3_Main2.bin').read_bytes()
    assert code3[0x43b2:0x43b6].hex() == '383c014d'
    assert code3[0x43de:0x43e0].hex() == '6d0a'
    assert code3[0x4256:0x425e].hex() == '7c0860027c087a00'
