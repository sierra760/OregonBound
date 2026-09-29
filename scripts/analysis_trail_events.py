"""CODE16:309a event-dispatch oracle; see docs/ORIGINAL_TRAIL_EVENTS.md.

Inputs use original raw units. Inject a bounded RNG and an action callback;
callbacks execute synchronously so their draws/writes affect later checks.
The default action implementation fails on deliberately unimplemented helpers.
"""
from dataclasses import dataclass, field
from copy import deepcopy


@dataclass
class Wagon:
    inventory: list[int] = field(default_factory=lambda: [12, 10, 100, 1, 1, 1, 1000])
    badness: int = 0
    pending: int = 0
    status: int = 0
    cash: int = 160000
    profession: int = 0
    survivors: int = 5              # player+4; original slots = len(conditions)
    conditions: list[int] = field(default_factory=lambda: [255]*5)
    timers: list[int] = field(default_factory=lambda: [0]*5)


@dataclass
class World:
    wagons: list[Wagon | None] = field(default_factory=lambda: [Wagon()])
    wagon_count: int = 1           # world+8, distinct from active-slot count +240
    temperature: int = 2          # +22e
    weather: int = 0              # +22d: retain event override bit128
    month: int = 4                # +2: one-based
    destination: int = 0         # signed byte +238
    rain: int = 1                 # unsigned word +230
    snow: int = 0                 # unsigned word +232
    delay: int = 0                # byte +6
    flags: int = 2                # byte +5
    events: list = field(default_factory=list)


class ScriptedRandom:
    """Supply bounded results, not raw QuickDraw samples. Trace includes calls
    with bound1, but these consume no result, matching CODE1:073e."""
    def __init__(self, values):
        self.values = iter(values)
        self.trace = []

    def __call__(self, bound, site):
        value = 0 if bound <= 1 else next(self.values)
        if not 0 <= value < max(1, bound):
            raise ValueError((hex(site), bound, value))
        self.trace.append((site, bound, value))
        return value


def dispatch(original, draw, action):
    """Copy inputs; run exact outer checks, with explicit helper implementation.

    action(name, mutable_world, draw, slot_or_None) MUST consume the helper's
    draws and apply writes. A recording callback is only an outer-flow probe.
    No rest/flags gate here: the caller gates entry at CODE16:1ae6.
    """
    w = deepcopy(original)
    if w.wagon_count == 0:       # 309e–30a8
        return w
    def call(name, slot=None):
        action(name, w, draw, slot)
    if w.snow > 3000:
        call('snowbound')       # 30be ->3546
    if w.temperature >= 3 and draw(100, 0x30d6) < 4:
        call('snakebite')
    for slot in range(len(w.wagons)):
        wagon = w.wagons[slot]
        if wagon is None:      # active entry255
            continue
        if draw(100, 0x312c) < wagon.badness // 15 + 1:
            call('illness', slot)
        if wagon.inventory[6] == 0 and draw(100, 0x3160) < 5:
            call('food_aid', slot)
        if 5 <= w.month <= 9 and draw(100, 0x319e) < 4:
            call('wild_fruit', slot)
    if w.weather in (4, 6) or (w.temperature <= 1 and draw(100, 0x3200) < 15):
        call('severe_weather')
    if draw(100, 0x3216) < 6:
        call('fog_hail')
    if draw(100, 0x322c) < (7 if w.destination > 11 else 4):
        call(('broken_part', 'sick_ox', 'broken_limb')[draw(3, 0x326c)])
    if draw(100, 0x32a0) < 2:
        call('lost_trail')
    if w.destination > 11 and draw(100, 0x32c8) < 5:
        call('rough_impassable')
    if draw(100, 0x32de) == 0:
        call(('fire', 'wandered_ox', 'lost_person')[draw(3, 0x32ec)])
    choice = draw(100, 0x3320)
    if choice <= 1:
        call(('supplies_found', 'thief')[choice])
    if w.rain == 0 and draw(2, 0x3358) != 0:
        call('dry_ground')
    return w


def delay_at_least(w, days):
    """2f88: max, never sum; equal/lower days do not even set flags."""
    if days > w.delay:
        w.delay = days & 255
        w.flags |= 8


def select_wagon(w, draw):
    """2cbc compacts slot indices, preserving holes in active list."""
    slots = [i for i, wagon in enumerate(w.wagons) if wagon is not None]
    return slots[draw(len(slots), 0x2d12)] if slots else None


def select_member(wagon, draw):
    """2c64: leader excluded until survivor<=1, or bounded retry fallback.

    Healthy result on draw1000 still falls back to leader; dead result on that
    draw retries once more because 2caa uses BGE, while 2cb0 uses BGT.
    """
    if wagon.survivors <= 1:
        return 0
    retries = 1000
    while True:
        member = draw(len(wagon.conditions)-1, 0x2c8c)+1
        retries -= 1
        if wagon.conditions[member] != 9 or retries < 0:
            return member if retries > 0 else 0


def known_action(name, w, draw, slot=None):
    """Verified nonhealth subset. Unimplemented callbacks raise, never no-op."""
    def emit(event, **details):
        w.events.append(dict(id=event, slot=slot, **details))
    def pending(value):
        for wagon in w.wagons:
            if wagon is not None:
                wagon.pending = value   # assignment, not accumulation
    if name == 'snowbound':             #3546
        delay_at_least(w, draw(10, 0x354a)+1)
        emit(12)
    elif name == 'severe_weather':      #3566
        if w.temperature <= 1:
            delay_at_least(w, 1)
            emit(7)
            w.weather = 0x88
        elif w.temperature >= 4:
            delay_at_least(w, 1)
            emit(8)
            w.weather = 0x87
    elif name == 'fog_hail':            #2edc
        if w.destination > 11 and w.temperature < 5:
            if draw(2, 0x2f02):
                delay_at_least(w, 1)
                emit(0)
        elif w.destination <= 11 and w.temperature == 5:
            emit(1)
            w.weather = 0x89
    elif name == 'lost_trail':          #3060
        delay_at_least(w, draw(5, 0x3064)+1)
        emit(2 if draw(2, 0x3078) else 3)
    elif name == 'rough_impassable':    #336c
        if draw(2, 0x3374):
            pending(10)
            emit(4)
        else:
            delay_at_least(w, draw(10, 0x33de)+1)
            emit(5)
    elif name == 'dry_ground':          #3814
        choice = draw(100, 0x381c)
        if choice < 40:
            emit(9)
        elif w.snow == 0:
            pending(20 if choice < 60 else 10)
            emit(11 if choice < 60 else 10)
    elif name in ('food_aid', 'wild_fruit'):
        wagon = w.wagons[slot]
        if name == 'food_aid':          #2f58
            wagon.inventory[6] = (wagon.inventory[6]+30) & 65535
            emit(20)
        elif wagon.inventory[6] < 2000: #38ba; A5-288a
            wagon.inventory[6] = min(2000, wagon.inventory[6]+20)
            emit(25)
    elif name in ('snakebite', 'broken_limb', 'lost_person'):
        slot = select_wagon(w, draw)
        if slot is None:
            return
        wagon = w.wagons[slot]
        member = select_member(wagon, draw)
        if name == 'lost_person':       #3002
            delay_at_least(w, draw(5, 0x3030)+1)
            emit(28, member=member)
        else:
            if name == 'snakebite':     #34c6
                condition, duration, event = 2, draw(3, 0x3500)+9, 29
            else:                      #2aae
                condition = draw(2, 0x2ade)
                duration, event = draw(5, 0x2af2)+28, 26+condition
            wagon.conditions[member] = condition
            wagon.timers[member] = max(wagon.timers[member], duration)
            emit(event, member=member)
    elif name == 'thief':               #35c2, including literal cash anomaly
        slot = select_wagon(w, draw)
        if slot is None:
            return
        wagon = w.wagons[slot]
        choice = draw(4, 0x3608)
        item = 6 if choice == 3 else choice
        quantity = wagon.inventory[item]
        if quantity > 0:
            loss = 1+draw(min(quantity, 100), 0x3648 if quantity > 100 else 0x366e)
            if item == 0:
                loss = (quantity+loss+1)//2 - (quantity+1)//2
                loss -= loss % 2
            if loss > 0:
                wagon.inventory[item] -= loss
                changes = [0]*7
                changes[item] = loss
                emit(64, quantities=changes)
        elif wagon.cash > 100:
            loss = (1+draw(100 if wagon.cash > 10000 else wagon.cash,
                           0x3726 if wagon.cash > 10000 else 0x374e))*100
            raw = (wagon.cash-loss) & 0xffffffff
            wagon.cash = raw-0x100000000 if raw >= 0x80000000 else raw
            emit(64, cash=loss)
    elif name in ('supplies_found', 'fire'):
        slot = select_wagon(w, draw)
        if slot is None:
            return
        wagon = w.wagons[slot]
        changes = [0]*7
        if name == 'supplies_found':    #29a6; capacities at A5-2896
            capacity = (40, 50, 1980, 3, 3, 3, 2000)
            for item in range(1, 6):
                if draw(2, 0x29e0):
                    changes[item] = (draw(40, 0x29f8)+20 if item == 2
                                     else draw(3, 0x2a12)+1)
                    wagon.inventory[item] = min(capacity[item],
                                                 wagon.inventory[item]+changes[item])
            emit(63, quantities=changes)  # reports pre-cap gains, even all zero
        else:                          #3796 ->1d2a with chance50
            for item in range(1, 7):
                if draw(100, 0x1d44) < 50:
                    changes[item] = draw(wagon.inventory[item]+1, 0x1d62)
                    wagon.inventory[item] -= changes[item]
            if any(changes):
                emit(65, quantities=changes)
    elif name in ('sick_ox', 'broken_part', 'wandered_ox'):
        slot = select_wagon(w, draw)
        if slot is None:
            return
        wagon = w.wagons[slot]
        professions = {x.profession for x in w.wagons if x is not None}
        if name == 'sick_ox':           #33fe
            if wagon.inventory[0] <= 0:
                return
            if 4 in professions and draw(2, 0x3444):
                emit(22)
            else:
                wagon.inventory[0] -= 1
                emit(23 if wagon.inventory[0] % 2 else 24)
        elif name == 'wandered_ox':     #2fb4: no inventory loss
            delay_at_least(w, draw(3, 0x2fd6)+1)
            emit(21)
        else:                          #2b3e
            part = 3+draw(3, 0x2b68)
            if draw(2, 0x2b76) and 1 in professions:
                event = 32 if w.wagon_count > 1 else 30
            elif draw(2, 0x2bb2) and 2 in professions:
                event = 31 if w.wagon_count > 1 else 30
            elif draw(2, 0x2bea):
                event = 30
            elif wagon.inventory[part] > 0:
                wagon.inventory[part] -= 1
                event = 33
            else:
                wagon.status |= 2 << (part-3)
                w.flags &= ~2
                event = 34
            emit(event, part=part)
    else:
        raise NotImplementedError(f'{name}: supply verified callback before full-day simulation')
