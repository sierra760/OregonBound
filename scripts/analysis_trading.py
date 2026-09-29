"""Single-wagon CODE3:3e0a/4360/4b64 trading oracle.

All stock uses original raw units (two raw oxen = one ox); cash uses cents.
Request/Offer oxen use displayed whole oxen, and cash quantities remain cents.
Inputs must be valid, normal-range game values; the original input-overflow bugs
and multiplayer messaging are deliberately outside this oracle's scope.
"""
from copy import deepcopy
from dataclasses import dataclass, field
import struct

CAPACITY = (40, 50, 1980, 3, 3, 3, 2000)
UNIT_CENTS = (2000, 1000, 10, 1000, 1000, 1000, 20, 100)


@dataclass
class Wagon:
    stock: list[int] = field(default_factory=lambda: [12, 10, 100, 1, 1, 1, 1000])
    cash: int = 160000


@dataclass(frozen=True)
class Request:
    item: int
    quantity: int


@dataclass(frozen=True)
class Offer:
    request: Request
    item: int
    quantity: int


@dataclass(frozen=True)
class Presentation:
    offer: Offer | None
    portrait: int


@dataclass
class Resolution:
    wagon: Wagon
    status: str
    journal_opcode: int | None = None
    days: int = 0


def raw_quantity(item, quantity):
    return quantity * 2 if item == 0 else quantity


def has_space(wagon, request):
    return request.item == 7 or (wagon.stock[request.item] +
        raw_quantity(request.item, request.quantity) <= CAPACITY[request.item])


def make_request(wagon, item, displayed_quantity):
    if item not in range(8) or not isinstance(displayed_quantity, int) or displayed_quantity <= 0:
        raise ValueError('Enter a positive quantity for a valid item.')
    request = Request(item, displayed_quantity * 100 if item == 7 else displayed_quantity)
    if not has_space(wagon, request):
        raise ValueError('Not enough grass.' if item == 0 else 'Not enough wagon space.')
    return request


def f32(value):
    return struct.unpack('>f', struct.pack('>f', value))[0]


def payment_quantity(request, payment_item, percent):
    """SANE stores base and percent factor as single precision, then FTINT.

    FTINT truncates toward zero, independent of rounding mode. Price 7 is dollars
    here; callers convert payment dollars to cents after affordability checks.
    """
    base = f32(UNIT_CENTS[request.item] / UNIT_CENTS[payment_item] * request.quantity)
    if request.item == 7:
        base = f32(base / 100)
    factor = f32(percent / 100)
    return max(1, int(base * factor))


def counteroffer(wagon, request, draw):
    available = [wagon.stock[0] // 2] + wagon.stock[1:] + [wagon.cash // 100]
    untried = set(range(8)) - {request.item}
    while untried:
        item = draw(8, 0x3f7c)
        if item == request.item:
            continue
        quantity = payment_quantity(request, item, 80 + draw(41, 0x4096))
        if quantity < available[item] or (item != 0 and quantity == available[item]):
            return Offer(request, item, quantity * 100 if item == 7 else quantity)
        untried.discard(item)  # Already-rejected candidates remain eligible to draw.
    return None


def present(wagon, request, draw):
    offer = counteroffer(wagon, request, draw) if draw(1000, 0x43d2) > 333 else None
    portrait = draw(9, 0x4712)
    while portrait == 6:
        portrait = draw(9, 0x4712)
    return Presentation(offer, portrait)


def resolve(original, offer, accept):
    wagon = deepcopy(original)
    if offer is None or not accept:
        return Resolution(wagon, 'no-offer' if offer is None else 'refused')
    request = offer.request
    if not has_space(wagon, request):
        return Resolution(wagon, 'no-space', 0x4e)
    payment = raw_quantity(offer.item, offer.quantity)
    available = wagon.cash if offer.item == 7 else wagon.stock[offer.item]
    if payment > available:
        return Resolution(wagon, 'cannot-pay', 0x4c)
    if offer.item == 7:
        wagon.cash -= payment
    else:
        wagon.stock[offer.item] -= payment
    if request.item == 7:
        wagon.cash += request.quantity
    else:
        wagon.stock[request.item] += raw_quantity(request.item, request.quantity)
    return Resolution(wagon, 'accepted', 0x4f)
