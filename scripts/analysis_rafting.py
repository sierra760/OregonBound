"""Instruction-derived rafting fragments, not a complete game/QuickDraw emulator.

CODE17 offsets exclude its four-byte CODE header. Caller supplies bounded RNG;
its order is exposed in ScriptedRandom.trace. See docs/ORIGINAL_RAFTING.md.
"""
from dataclasses import dataclass, field
from copy import deepcopy


def trunc_div(n, d):
    return (-1 if n < 0 else 1) * (abs(n) // d)


def signed_word(n):
    return (n + 32768) % 65536 - 32768


@dataclass
class ScriptedRandom:
    values: list[int]
    trace: list[tuple[int, int, int]] = field(default_factory=list)

    def __call__(self, bound, site):
        value = self.values.pop(0)
        assert 0 <= value < bound
        self.trace.append((site, bound, value))
        return value


@dataclass
class Party:
    inventory: list[int] = field(default_factory=lambda: [0]*7)
    alive: list[bool] = field(default_factory=lambda: [True]*5)
    drowned: list[bool] = field(default_factory=lambda: [False]*5)


@dataclass
class Collision:
    party: Party
    losses: list[int]
    drowned: list[int]
    pause_steps: int = 100


def collide(party, draw):
    """CODE17:13cc–1478: supplies50%, raw oxen pairs40%, people40%."""
    result = deepcopy(party)
    assert len(result.inventory) == 7 and 1 <= len(result.alive) <= 5
    losses = [0]*7
    for item in range(1, 7):
        quantity = result.inventory[item]
        if quantity and draw(100, 0x1960) < 50:
            losses[item] = draw(quantity+1, 0x1982)
    pairs_lost = sum(draw(100, 0x185a) < 40 for _ in range((result.inventory[0]+1)//2))
    losses[0] = min(result.inventory[0], pairs_lost*2)
    drowned = []
    survivors = sum(result.alive)
    for member in range(1, len(result.alive)):
        if result.alive[member] and draw(100, 0x18c2) < 40:
            drowned.append(member)
            survivors -= 1
    if survivors == 1 and result.alive[0] and draw(100, 0x1918) < 40:
        drowned.append(0)
    for member in drowned:
        result.alive[member] = False
        result.drowned[member] = True
    result.inventory = [max(0, quantity-loss) for quantity, loss in zip(result.inventory, losses)]
    return Collision(result, losses, drowned)


def maximum_rocks(rain):
    """CODE17:046e–04b8; rain is world unsigned word+230."""
    assert 0 <= rain <= 65535
    return min(3, max(1, 4-trunc_div(rain-400, 150)))


def frame_progress(remaining, survivors, pixel_depth):
    """CODE17:0594–05ba. Return (stored signedword, finishes, runs_objects).

    Tests OLD count for zero. Color depth>2 then subtracts an extra1.
    Pause/deadline handling occurs outside this deterministic fragment.
    """
    old = remaining
    remaining = signed_word(remaining-1)
    if old == 0 or survivors == 0:
        return remaining, True, False
    if pixel_depth > 2:
        remaining = signed_word(remaining-1)
    return remaining, False, True


def should_spawn(remaining, active, cooldown, maximum, draw):
    """CODE17:05c8–060e draws R40 unconditionally each running frame."""
    roll = draw(40, 0x05cc)
    return (roll == 7 or active == 0) and cooldown == 0 and remaining > 150 and active < maximum


def choose_lane(previous, draw):
    """CODE17:0e80–0ecc. Reject new signed lane when |delta|<15.

    Sentinel−999 is replaced by the FIRST draw, which necessarily retries.
    Return (acceptedLane, firstPixelX). No invented retry cap.
    """
    while True:
        lane = 23 - 7*draw(8, 0x0e8c)
        if previous == -999:
            previous = lane
        if lane-previous <= -15 or lane-previous >= 15:
            return lane, 189+2*lane


def steer(left, width, mouse_x):
    """CODE17:0554–058a,0c78–0d0a. Return left,direction,frame index."""
    direction = 1 if mouse_x > left+width else -1 if mouse_x < left else 0
    left += direction*4
    if left > 350:
        left, direction = 350, 0
    if left < 10:
        left, direction = 10, 0
    return left, direction, direction+3


def intersects(a, b):
    """QuickDraw rectangle tuples(top,left,bottom,right), positive intersection."""
    return max(a[0], b[0]) < min(a[2], b[2]) and max(a[1], b[1]) < min(a[3], b[3])


def hits_raft(rock_top, rock_left, raft_left, direction):
    """CODE17:0fea–1364: two rock rects against four direction-specific bands."""
    assert direction in [-1, 0, 1]
    rocks = [(rock_top+5, rock_left+21, rock_top+21, rock_left+49),
             (rock_top+21, rock_left+1, rock_top+31, rock_left+64)]
    if rock_top+31 < 210 or rock_top+5 > 254 or raft_left > rock_left+64 or raft_left+60 < rock_left+1:
        return False
    edges = {
        -1: [(21,41), (12,40), (8,48), (6,58)],
         0: [(16,36), (17,45), (11,50), (5,57)],
         1: [(26,46), (23,49), (13,53), (5,57)],
    }[direction]
    bands = [(210,217), (218,222), (222,240), (240,253)]
    return any(intersects((top,raft_left+left,bottom,raft_left+right), rock)
               for (top,bottom),(left,right) in zip(bands,edges) for rock in rocks)


def rock_frame(top):
    """CODE17:166a–16a6. Rock enlarges from Imag19200 frame10 toward5."""
    return 10 if top < 64 else max(5, 10-trunc_div(top-39, 12))


def settlement(initial, local, badness):
    """CODE3:1ec2–1f18, CODE16:1442–1508 (command61).

    No date, food-needs, cash, or mileage side effect in this message handler.
    Raft deaths use1af0, which caps badness105; ordinary river deaths differ.
    """
    losses = [max(0, before-after) for before, after in zip(initial.inventory, local.inventory)]
    deaths = [i for i in range(len(initial.alive)) if initial.alive[i] and local.drowned[i]]
    return {'losses': losses, 'drowned': deaths,
            'badness': min(badness,105) if deaths else badness,
            'survivors': sum(initial.alive)-len(deaths), 'date_delta': 0, 'miles_delta': 0}


def barlow_payment(cash):
    """CODE1:374e–3790. None means original insufficient-cash dialog."""
    return cash-500 if cash >= 500 else None


def single(value):
    import struct
    return struct.unpack('>f', struct.pack('>f', float(value)))[0]


def rock_motion(lane, accumulator):
    """CODE17:148a–1636: extended add, single store; strict threshold ±2."""
    slope = single(lane*0.0178)
    accumulator = single(accumulator + slope*2)
    dx = -2 if slope < 0 and accumulator < -2 else 2 if slope > 0 and accumulator > 2 else 0
    return dx, single(accumulator-dx)


def marker_target(progress):
    """CODE17:07c0–0b7e single target. Caller truncates (target-currentX)."""
    if progress < 19: value = 464+progress*0.166666667
    elif progress < 46: value = 466
    elif progress < 115: value = 466+(progress-46)*0.144927537
    elif progress < 154: value = 475-(progress-115)*0.333333334
    elif progress < 192: value = 462-(progress-154)*0.105263158
    elif progress < 221: value = 457-(progress-192)*0.379310345
    else: value = 446
    return single(value)
