"""Empyrean Tower, the fourth part of tools/arena/empyrean.py: the magic. The last pass,
to make the tower feel magical and a little surreal. Looks and sound only: nothing here
is solid, adds a route or changes how the map plays.

 - Living magic (MapMagic boxes: all movement is on the graphics card): a river of
   liquid magic climbing the shaft against gravity (a MapMagicStream), rune rings
   turning round it, and each tier's own: caged lightning and rising sparks (Engine),
   flocks of books and loose pages (Library), rising droplets and bubbles (Labs), small
   see-through spirits (Menagerie), floating candles and turning chalk circles
   (Summoning Chamber), constellations and little worlds (Observatory). Motes of light
   everywhere, thinnest in the corridors and outside.
 - The tower's technology harnessing it: at every tier an intake draws a thread off
   the river and pipes it, glowing, along the vault to a tank on the wall.
 - Three impossible things outside, all of them phantoms (pale, see-through, plainly
   not there, so flying through one is no surprise): a broken arch whose stones hang
   apart, a stair of floating treads winding off into nothing, and the tower's own top
   mirrored upside down under its root.
 - A MapMagicField, which makes the motes, books, pages, spirits, candles and the
   runes in the stone answer to players within 4 m in plain sight. A quiet sound of its
   own in every tier (MapAmbientSound).

See empyrean.py for the plan and the conventions."""
import math
import random
from arena_builder import xform, fmt, vec, color, IDENTITY, yaw_cols, norm, cross
from cirrus import FLIP, LIE_X, LIE_Z
import empyrean as E
from empyrean import P, rot, ri, ro, rc, chord, TIER, L1, L2, L3, RS, ACCENT, ACCENT_RGB, TOP, LANE, FEAT, DOOR_N, DOOR_W

MOTES, SPARKS, PAGES, BOOKS, DROPLETS, BUBBLES, FISH, JELLIES, MOTHS, CANDLES, STARS, ARCS = range(12)
REACTS = (MOTES, PAGES, BOOKS, FISH, JELLIES, MOTHS, CANDLES)
PIECE = {MOTES: 0.09, SPARKS: 0.06, PAGES: 0.2, BOOKS: 0.3, DROPLETS: 0.09, BUBBLES: 0.14, FISH: 0.5, JELLIES: 0.5,
         MOTHS: 0.16, CANDLES: 1.0, STARS: 0.2, ARCS: 0.06}
POWER = {MOTES: 1.5, SPARKS: 1.8, DROPLETS: 1.5, BUBBLES: 1.0, FISH: 1.35, JELLIES: 1.2, MOTHS: 1.4, CANDLES: 2.4, STARS: 1.8, ARCS: 2.2}
WARM = (1.0, 0.8, 0.45)
PALE = (0.9, 0.95, 1.0)
_n = [0]


def magic(m, parent, name, kind, at, size, count, col, col_b=None, deg=0.0, piece=None, power=None, far=None):
    """A MapMagic box centred on `at`, turned square to the radius at `deg` (x along the wall, z outward)."""
    _n[0] += 1
    props = [("transform", xform(rot(deg), at)), ("kind", str(kind)), ("size", vec(size)), ("count", str(int(count))),
             ("piece", fmt(piece or PIECE[kind])), ("color", color(col)), ("color_b", color(col_b or col)),
             ("power", fmt(power or POWER.get(kind, 1.4))), ("variation", str(_n[0]))]
    if kind not in REACTS:
        props.append(("reacts", "false"))
    if far is not None:
        props.append(("draw_range", fmt(far)))       # (the default is 90 m; the things meant to be seen from far off say more)
    return m.node(name, parent, "magic", props)


def stream(m, parent, name, path, cols, width, speed=2.2, power=1.2, taper=(4.0, 4.0)):
    flat = ", ".join(fmt(v) for p in path for v in p)
    cc = ", ".join(fmt(v) for c in cols for v in (tuple(c) + (1,))[:4])
    return m.node(name, parent, "stream", [("path", "PackedVector3Array(%s)" % flat), ("width", fmt(width)), ("colors", "PackedColorArray(%s)" % cc),
                                           ("speed", fmt(speed)), ("power", fmt(power)), ("taper", "Vector2(%s, %s)" % (fmt(taper[0]), fmt(taper[1])))])


# ---------------------------------------------------------------------------
# The river up the shaft

RIVER_FOOT, RIVER_HEAD, river_at = E.RIVER_FOOT, E.RIVER_HEAD, E.river_at
RIVER_WIDE, THREAD_WIDE = 1.0, 0.26
# How far the river's (a thread's) middle has to stay from anything in the shaft: half
# its width, its swell (a third more) and its sway, and a hand's breadth of air.
RIVER_CLEAR = RIVER_WIDE * 0.5 * 1.35 + 0.18 + 0.15
THREAD_CLEAR = THREAD_WIDE * 0.5 * 1.35 + 0.08 + 0.1


def _box_gap(p, centre, axes, half):
    """How far point p is from a box (its middle, its three unit axes, its half sizes)."""
    d = [p[k] - centre[k] for k in range(3)]
    out = 0.0
    for axis, h in zip(axes, half):
        along = sum(d[k] * axis[k] for k in range(3))
        over = max(abs(along) - h, 0.0)
        out += over * over
    return math.sqrt(out)


def shaft_gap(p):
    """How far point p is from the nearest thing in the shaft that liquid magic must not
    run through: a bridge (its deck, rails, lamp posts and the banners under it) or a
    floating stone. (name, metres)."""
    best = ("nothing", 99.0)
    for y, deg, _i in E.bridges():
        th = math.radians(deg)
        along = (math.sin(th), 0.0, math.cos(th))
        across = (math.cos(th), 0.0, -math.sin(th))
        up = (0.0, 1.0, 0.0)
        parts = [("bridge at %.1f m" % y, (0, y + 0.2, 0), (RS + 0.3, 0.7, 1.82))]                 # deck and rails
        for side in (-1, 1):
            c = (across[0] * 1.72 * side, y - 1.8, across[2] * 1.72 * side)
            parts.append(("banner under the bridge at %.1f m" % y, c, (1.0, 1.3, 0.09)))
            for end in (-1, 1):
                c = (along[0] * (RS - 0.4) * end + across[0] * 1.7 * side, y + 1.9, along[2] * (RS - 0.4) * end + across[2] * 1.7 * side)
                parts.append(("lamp post on the bridge at %.1f m" % y, c, (0.2, 1.0, 0.2)))
        for name, c, half in parts:
            gap = _box_gap(p, c, (along, up, across), half)
            if gap < best[1]:
                best = (name, gap)
    for at in E.STONES:
        gap = max(math.dist(p, (at[0], at[1] - 1.6, at[2])) - 1.45, 0.0)
        if gap < best[1]:
            best = ("floating stone at %.1f m" % at[1], gap)
    return best


def check_clear(name, path, need):
    """Stops the build if a stream's path runs closer than `need` to something in the shaft."""
    worst = ("nothing", 99.0, None)
    for k in range(len(path) - 1):
        for u in (0.0, 0.25, 0.5, 0.75):
            p = tuple(a + (b - a) * u for a, b in zip(path[k], path[k + 1]))
            what, gap = shaft_gap(p)
            if gap < worst[1]:
                worst = (what, gap, p)
    if worst[1] < need:
        raise SystemExit("%s runs %.2f m from the %s (it needs %.2f m) at %s" % (name, worst[1], worst[0], need, worst[2]))
    return worst


def tier_colour(y):
    """The colour of the tier at height y, blending into the next one over its top third."""
    f = min(max(y / TIER, 0.0), 5.999)
    i = int(f)
    u = min(max((f - i - 0.7) / 0.3, 0.0), 1.0)
    a, b = ACCENT_RGB[i], ACCENT_RGB[min(i + 1, 5)]
    return tuple(p + (q - p) * u for p, q in zip(a, b))


def shaft_magic(m):
    g = m.group("Magic", "Shaft", grouped=False)
    # The river: out of the core crystal's tip, round and round the shaft, up into a pool
    # that hangs upside down under the Observatory's platform.
    path = []
    y = RIVER_FOOT
    while y < RIVER_HEAD:
        path.append(river_at(y))
        y += 0.35
    path.append(river_at(RIVER_HEAD))
    stops = [tier_colour(RIVER_FOOT + (RIVER_HEAD - RIVER_FOOT) * k / 23.0) for k in range(24)]
    worst = check_clear("the river", path, RIVER_CLEAR)
    print("  the river's closest pass: %.2f m from the %s" % (worst[1], worst[0]))
    stream(m, g, "River", path, stops, RIVER_WIDE, speed=2.4, power=1.7, taper=(3.0, 2.0))
    top = river_at(RIVER_HEAD)
    pool = m.group("Pool", g)
    m.cyl(pool, "PoolLight", "accent_silver", (0, RIVER_HEAD + 0.42, 0), 7.2, 0.05, sides=24, solid=False)
    m.block(pool, "PoolRim", "brass", (0, RIVER_HEAD + 0.4, 0), (7.6, 0.14, 7.6), shape="tube", sides=24, inner=7.2, solid=False)
    m.block(pool, "PoolCollar", "alloy", (0, RIVER_HEAD + 0.3, 0), (8.2, 0.2, 8.2), shape="tube", sides=24, inner=7.7, solid=False)
    magic(m, g, "PoolRain", DROPLETS, (0, RIVER_HEAD - 3.5, 0), (6.0, 7.0, 6.0), 36, ACCENT_RGB[5], PALE)
    magic(m, g, "Spring", SPARKS, (0, RIVER_FOOT + 3.0, 0), (3.0, 8.0, 3.0), 40, ACCENT_RGB[0], PALE)
    # Droplets that have left it, still rising, and motes the whole height of the shaft.
    for i in range(5):
        ym = TIER * i + 16.0
        magic(m, g, "Spray", DROPLETS, (0, ym + 3.0, 0), (7.5, 24.0, 7.5), 34, tier_colour(ym), PALE)
        magic(m, g, "ShaftMotes", MOTES, (0, ym, 0), (14.0, 28.0, 14.0), 80, tier_colour(ym), WARM)
    # Rune rings: a great ring of runes turning slowly round the river in the middle of each tier.
    for i in range(1, 5):
        y = TIER * i + 9.5
        sp = m.node("RuneRing", g, "spinner", [("transform", xform(IDENTITY, (0, y, 0))), ("speed", fmt(5.0 if i % 2 else -4.0))])
        m.block(sp, "Ring", "brass", (0, 0, 0), (13.2, 0.14, 13.2), shape="tube", sides=32, inner=12.9, solid=False)
        m.block(sp, "RingLight", ACCENT[i], (0, 0, 0), (12.9, 0.06, 12.9), shape="tube", sides=32, inner=12.7, solid=False)
        for k in range(12):
            deg = k * 30.0
            m.block(sp, "Rune", ACCENT[i] if k % 2 else "glow", P(6.5, deg, 0.0), (0.16, 0.7, 0.1), cols=rot(deg), solid=False)
            m.block(sp, "RuneArm", ACCENT[i] if k % 2 else "glow", P(6.5, deg + 1.6 * (1 if k % 3 else -1), 0.12), (0.12, 0.34, 0.1),
                    cols=tuple(tuple(c) for c in _tilt(deg, 0.7 if k % 3 else -0.7)), solid=False)


def _tilt(deg, lean):
    """rot(deg) leaned sideways along the wall by `lean` radians (a rune's slanted stroke)."""
    X, Y, Z = rot(deg)
    c, s = math.cos(lean), math.sin(lean)
    X2 = tuple(x * c + y * s for x, y in zip(X, Y))
    Y2 = tuple(-x * s + y * c for x, y in zip(X, Y))
    return X2, Y2, Z


# ---------------------------------------------------------------------------
# Technology harnessing it: an intake, a pipe along the vault, a tank on the wall

MANA_DEG = 60.0


def mana_line(m, g, i):
    y0, acc = TIER * i, ACCENT[i]
    ceil = y0 + L3 - 0.5
    lip = P(RS + 0.9, MANA_DEG, ceil - 1.5)
    # The thread drawn off the river.
    path = None
    for below in (3.4, 4.6, 5.8, 7.0, 8.4, 2.4):          # leave the river at the first height that gives a clear run to the intake
        src = river_at(ceil - below)
        trial = []
        for k in range(13):
            u = k / 12.0
            p = tuple(a + (b - a) * u for a, b in zip(src, lip))
            trial.append((p[0], p[1] + 0.7 * math.sin(math.pi * u), p[2]))
        if min(shaft_gap(tuple(a + (b - a) * u for a, b in zip(trial[k], trial[k + 1])))[1] for k in range(12) for u in (0.0, 0.33, 0.66)) >= THREAD_CLEAR:
            path = trial
            break
    if path is None:
        raise SystemExit("no clear run for the thread off the river at tier %d" % i)
    check_clear("the thread at tier %d" % i, path, THREAD_CLEAR)
    stream(m, g, "Thread", path, [ACCENT_RGB[i]], THREAD_WIDE, speed=3.2, power=1.3, taper=(0.8, 0.5))
    # The intake, hung from the vault at the shaft's rim.
    m.block(g, "IntakeFunnel", "alloy", (lip[0], lip[1] + 0.1, lip[2]), (1.3, 0.9, 1.3), cols=rot(MANA_DEG), shape="cone", sides=8, top=0.5, solid=False)
    m.block(g, "IntakeBand", "brass", (lip[0], lip[1] - 0.3, lip[2]), (1.4, 0.14, 1.4), shape="tube", sides=8, inner=1.2, solid=False)
    m.pb(g, "IntakeHousing", "alloy_dark", RS + 0.4, RS + 1.6, MANA_DEG, 1.0, ceil - 1.05, ceil - 0.4, shape="bevel", bevel=0.12, solid=False)
    m.pb(g, "IntakeLight", acc, RS + 0.38, RS + 0.4, MANA_DEG, 0.5, ceil - 0.85, ceil - 0.7, solid=False)
    # The pipe: glass with the liquid glowing in it, along the vault and down the back wall.
    side = MANA_DEG + 1.8
    rw = ri(ceil) - 0.35
    m.pb(g, "Pipe", "glass_clear", RS + 1.6, rw, side, 0.36, ceil - 1.02, ceil - 0.66, solid=False, unbreakable=True)
    m.pb(g, "PipeMana", acc, RS + 1.6, rw, side, 0.16, ceil - 0.92, ceil - 0.76, solid=False)
    for r in (RS + 3.0, (RS + rw) * 0.5, rw - 1.6):
        m.pb(g, "PipeBracket", "alloy_dark", r - 0.12, r + 0.12, side, 0.56, ceil - 1.1, ceil - 0.5, solid=False)
    tank_y = y0 + L1 + 3.3
    drop = (ceil - 0.8) - (tank_y + 0.9)
    ym = tank_y + 0.9 + drop * 0.5
    m.block(g, "PipeDown", "glass_clear", P(ri(ym) - 0.32, side, ym), (0.36, drop, 0.36), cols=E.lean(side), solid=False, unbreakable=True)
    m.block(g, "PipeDownMana", acc, P(ri(ym) - 0.32, side, ym), (0.16, drop, 0.16), cols=E.lean(side), solid=False)
    # The tank, high on the wall over the balcony.
    at = P(ri(tank_y) - 0.85, side, tank_y)
    m.block(g, "Tank", "glass_clear", at, (1.3, 1.8, 1.3), shape="cyl", sides=10, solid=False, unbreakable=True)
    m.block(g, "TankMana", acc, (at[0], at[1] - 0.25, at[2]), (1.0, 1.2, 1.0), shape="cyl", sides=10, solid=False)
    for dy in (-1.0, 1.0):
        m.block(g, "TankCap", "alloy", (at[0], at[1] + dy, at[2]), (1.5, 0.22, 1.5), shape="cyl", sides=10, solid=False)
    m.block(g, "TankBand", "brass", at, (1.42, 0.12, 1.42), shape="tube", sides=10, inner=1.28, solid=False)
    m.pb(g, "TankBracket", "alloy_dark", ri(tank_y) - 0.9, ri(tank_y) + 0.1, side, 0.5, tank_y - 1.25, tank_y - 1.05, solid=False)
    magic(m, g, "TankBubbles", BUBBLES, (at[0], at[1] - 0.2, at[2]), (0.7, 1.1, 0.7), 5, PALE, ACCENT_RGB[i], piece=0.07)


# ---------------------------------------------------------------------------
# Every tier: motes in the feature room, the corridor, the upper hall and the balconies

def room_spots(i, depth=None):
    """Three boxes that fill the feature room: (where its middle is at floor level, angle, size across, size deep)."""
    Rc = rc(i)
    mid = (RS + Rc) * 0.5 + 0.4
    deep = depth or (Rc - RS - 1.6)
    return [(mid, deg, mid * math.radians(46.0), deep) for deg in (26.0, 75.0, 124.0)]


def tier_motes(m, g, i):
    y0, acc = TIER * i, ACCENT_RGB[i]
    for n, (r, deg, wide, deep) in enumerate(room_spots(i)):
        magic(m, g, "RoomMotes", MOTES, P(r, deg, y0 + 6.5), (wide, 11.0, deep), 34, acc, WARM, deg=deg)
    Rc = rc(i)
    for lvl, base in enumerate((0.0, L1, L2)):          # the corridor: a few, every third sector
        for k in (1, 4, 7, 10, 13):
            deg = (FEAT + k + 0.5) * 15.0
            magic(m, g, "CorridorMotes", MOTES, P(Rc + LANE * 0.5, deg, y0 + base + 1.9), (3.6, 2.2, 2.2), 6, acc, WARM, deg=deg)
        for k in (2, 6, 11):                            # ...and the rooms
            deg = (FEAT + k + 0.5) * 15.0
            magic(m, g, "NookMotes", MOTES, P((RS + Rc) * 0.5, deg, y0 + base + 2.2), (3.6, 2.6, Rc - RS - 2.0), 8, acc, WARM, deg=deg)
    yh = y0 + L3
    for deg in (30.0, 100.0, 190.0, 320.0):             # the upper hall
        r = (RS + ri(yh)) * 0.5 + 0.8
        magic(m, g, "HallMotes", MOTES, P(r, deg, yh + 3.8), (9.0, 5.5, ri(yh) - RS - 3.0), 18, acc, WARM, deg=deg)


def outside_motes(m):
    g = m.group("Motes", "Exterior", grouped=False)
    for i in range(E.TIERS):
        y = TIER * i
        if i == 3:
            continue
        for deg, wide in ((75.0, 9.0), (DOOR_N, 6.0), (DOOR_W, 6.0)):
            magic(m, g, "BalconyMotes", MOTES, P(ro(y) + 2.6, deg, y + 1.9), (wide, 3.0, 4.0), 9, ACCENT_RGB[i], WARM, deg=deg)
    for deg in (20.0, 75.0, 130.0, 190.0, 320.0):
        magic(m, g, "RingMotes", MOTES, P(E.RING_R - 3.5, deg, E.RING_Y + 2.0), (9.0, 3.2, 5.0), 10, ACCENT_RGB[3], WARM, deg=deg)
    magic(m, g, "CrownMotes", MOTES, (0, TOP + 44.0, 0), (14.0, 14.0, 14.0), 50, ACCENT_RGB[5], ACCENT_RGB[4], far=220.0)


# ---------------------------------------------------------------------------
# Each tier's own magic

def jar(m, g, top, drop, wide, tall, col):
    """Lightning caged in a glass jar hanging on a chain from `top`."""
    x, y, z = top[0], top[1] - drop, top[2]
    m.cyl(g, "JarChain", "alloy_dark", (x, y + tall * 0.5, z), 0.07, drop - tall * 0.5, sides=4, solid=False)
    m.block(g, "Jar", "glass_clear", (x, y, z), (wide, tall, wide), shape="cyl", sides=8, solid=False, unbreakable=True)
    for dy, kind in ((tall * 0.5 + 0.07, "brass"), (-tall * 0.5 - 0.07, "alloy_dark")):
        m.block(g, "JarCap", kind, (x, y + dy, z), (wide + 0.12, 0.14, wide + 0.12), shape="cyl", sides=8, solid=False)
    m.block(g, "JarPole", "alloy", (x, y, z), (0.06, tall, 0.06), solid=False)
    magic(m, g, "Lightning", ARCS, (x, y, z), (wide * 0.7, tall * 0.94, wide * 0.7), 3, col, PALE, piece=0.05 + wide * 0.03)


def engine_magic(m, g):
    acc = ACCENT_RGB[0]
    Rc = rc(0)
    # Lightning in jars: small ones under the balcony's edge, great ones from the vault round the shaft.
    for k in (2, 5, 8):
        jar(m, g, P(Rc - 0.9, k * 15.0 + 7.5, L1 - 0.5), 2.2, 0.7, 1.0, acc)
    for deg in (20.0, 52.0, 98.0, 130.0):
        jar(m, g, P(RS + 2.6, deg, L3 - 0.5), 6.0 + (deg % 3), 1.5, 2.4, acc)
    # Sparks rising round the core, and off the top of each piston.
    magic(m, g, "CoreSparks", SPARKS, (0, 6.0, 0), (9.0, 12.0, 9.0), 90, acc, PALE)
    for deg in (30.0, 46.0, 104.0, 124.0):
        at = P(ri(0) - 2.6, deg, 0)
        magic(m, g, "PistonSparks", SPARKS, (at[0], 7.6, at[2]), (1.4, 3.6, 1.4), 12, acc, WARM)


def library_magic(m, g):
    y0, acc = TIER, ACCENT_RGB[1]
    for n, (r, deg, wide, deep) in enumerate(room_spots(1)):
        magic(m, g, "BookFlock", BOOKS, P(r, deg, y0 + 10.5), (wide, 5.0, deep), 13, (0.55, 0.16, 0.18), (0.16, 0.26, 0.5), deg=deg)
        magic(m, g, "Pages", PAGES, P(r, deg, y0 + 8.0), (wide, 14.0, deep), 22, acc, deg=deg)
    yh = y0 + L3      # a few books have got out into the upper hall
    magic(m, g, "BookFlock", BOOKS, P((RS + ri(yh)) * 0.5, 60.0, yh + 6.0), (10.0, 3.0, 7.0), 8, (0.2, 0.42, 0.3), (0.55, 0.16, 0.18), deg=60.0)


def labs_magic(m, g):
    y0, acc = TIER * 2, ACCENT_RGB[2]
    Rc = rc(2)
    for deg in (28.0, 56.0, 122.0):           # out of each cauldron
        at = P(Rc + 2.6, deg, y0)
        magic(m, g, "CauldronDrops", DROPLETS, (at[0], y0 + 3.4, at[2]), (1.1, 3.8, 1.1), 9, acc, PALE)
        magic(m, g, "CauldronBubbles", BUBBLES, (at[0], y0 + 2.6, at[2]), (1.3, 2.2, 1.3), 6, acc, PALE)
    for n, (r, deg, wide, deep) in enumerate(room_spots(2)):
        magic(m, g, "Drops", DROPLETS, P(r, deg, y0 + 8.5), (wide, 15.0, deep), 30, acc, (0.6, 1.0, 0.85), deg=deg)
        magic(m, g, "Bubbles", BUBBLES, P(r, deg, y0 + 7.5), (wide, 13.0, deep), 18, acc, PALE, deg=deg)


def menagerie_magic(m, g):
    y0, acc = TIER * 3, ACCENT_RGB[3]
    spots = room_spots(3)
    for n, (r, deg, wide, deep) in enumerate(spots):
        magic(m, g, "SpiritFish", FISH, P(r, deg, y0 + 7.5 + n * 1.5), (wide, 4.0, deep), 9, acc, ACCENT_RGB[4], deg=deg)
        magic(m, g, "SpiritMoths", MOTHS, P(r, deg, y0 + 3.6), (wide * 0.8, 3.0, deep * 0.8), 8, WARM, acc, deg=deg)
    for n, (r, deg, wide, deep) in enumerate((spots[0], spots[2])):
        magic(m, g, "SpiritJellies", JELLIES, P(r, deg, y0 + 12.5), (wide, 5.0, deep), 5, ACCENT_RGB[4], acc, deg=deg)
    magic(m, g, "SpiritJellies", JELLIES, P((RS + ri(y0 + L3)) * 0.5, 100.0, y0 + L3 + 6.5), (9.0, 4.0, 7.0), 4, acc, ACCENT_RGB[4], deg=100.0)


def summoning_magic(m, g):
    y0, acc = TIER * 4, ACCENT_RGB[4]
    for n, (r, deg, wide, deep) in enumerate(room_spots(4)):
        magic(m, g, "Candles", CANDLES, P(r, deg, y0 + 5.2), (wide, 3.4, deep), 26, (1.0, 0.6, 0.22), deg=deg)
        magic(m, g, "Candles", CANDLES, P(r, deg, y0 + 11.5), (wide, 5.0, deep), 16, (1.0, 0.6, 0.22), deg=deg)
    # Chalk circles drawn in light on the floor, turning.
    for n, (r, deg, wide, speed) in enumerate(((RS + 6.0, 75.0, 8.2, 5.0), (RS + 5.0, 28.0, 5.4, -7.0), (RS + 4.6, 118.0, 5.4, 6.0))):
        sp = m.node("ChalkCircle", g, "spinner", [("transform", xform(IDENTITY, P(r, deg, y0 + 0.035))), ("speed", fmt(speed))])
        m.block(sp, "Circle", "accent_violet", (0, 0, 0), (wide, 0.02, wide), shape="tube", sides=28, inner=wide - 0.14, solid=False)
        m.block(sp, "Circle", "glow", (0, 0, 0), (wide * 0.72, 0.02, wide * 0.72), shape="tube", sides=5, inner=wide * 0.72 - 0.12, solid=False)
        for k in range(10):
            a = k * 36.0
            m.block(sp, "ChalkMark", "glow" if k % 2 else "accent_violet", P(wide * 0.43, a, 0.0), (0.1, 0.02, 0.5), cols=rot(a + (30.0 if k % 2 else -30.0)), solid=False)


def observatory_magic(m, g):
    y0, acc = TIER * 5, ACCENT_RGB[5]
    rng = random.Random(909)
    for n in range(9):        # constellations hung in the air
        deg = n * 40.0 + 12.0
        r = 9.5 + (n % 3) * 1.8
        magic(m, g, "Constellation", STARS, P(r, deg, y0 + 9.0 + (n * 5 % 14)), (4.6, 3.4, 1.6), 6 + n % 4, PALE, WARM, deg=deg)
    for n, (r, y, wide, speed) in enumerate(((9.0, 14.0, 1.1, 4.0), (12.0, 19.0, 0.8, -3.0), (7.0, 23.0, 1.4, 2.2), (11.0, 25.5, 0.7, -5.0))):
        sp = m.node("World", g, "spinner", [("transform", xform(yaw_cols(n * 1.7), (0, y0 + y, 0))), ("speed", fmt(speed))])
        at = (r, 0, 0)
        m.block(sp, "WorldTop", ("cloth_teal", "cloth_violet", "cloth_blue", "brass")[n], (at[0], wide * 0.25, at[2]), (wide, wide * 0.5, wide), shape="dome", sides=10, solid=False)
        m.block(sp, "WorldUnder", ("cloth_blue", "cloth_red", "cloth_teal", "stone_dark")[n], (at[0], -wide * 0.25, at[2]), (wide, wide * 0.5, wide), cols=FLIP, shape="dome", sides=10, solid=False)
        if n % 2 == 0:
            Y = norm((0.3, 1.0, 0.15))
            X = norm(cross(Y, (0, 0, 1)))
            m.block(sp, "WorldRing", ACCENT[5 - n], at, (wide * 1.8, 0.04, wide * 1.8), cols=(X, Y, cross(X, Y)), shape="tube", sides=18, inner=wide * 1.4, solid=False)
        m.block(sp, "WorldMoon", "glow", (at[0] + wide * 1.2, wide * 0.3, at[2] + 0.3), (0.16, 0.16, 0.16), shape="bevel", bevel=0.05, solid=False)
    magic(m, g, "StarDust", MOTES, (0, y0 + 15.0, 0), (30.0, 26.0, 30.0), 150, PALE, acc)


# ---------------------------------------------------------------------------
# Three impossible things outside: phantoms of the tower

def phantoms(m):
    f = m.folder("Phantoms", "Exterior")
    rng = random.Random(1717)
    # 1. A broken arch, its stones hanging apart in the air: off the Library's side.
    g = m.group("BrokenArch", f, at=P(52.0, 322.0, 66.0), yaw=math.radians(322.0 + 20.0))
    span, rise = 7.0, 9.4
    for side in (-1, 1):          # the piers: round drums, drifted apart and a little askew
        y = 0.0
        for k in range(4):
            tall = 2.6 - k * 0.2
            y += rng.uniform(0.25, 0.7)
            t = rng.uniform(-0.12, 0.12)
            cols = ((math.cos(t), math.sin(t), 0), (-math.sin(t), math.cos(t), 0), (0, 0, 1))
            m.block(g, "PierDrum", "phantom", (side * (span + rng.uniform(-0.35, 0.35)), y + tall * 0.5, rng.uniform(-0.3, 0.3)), (2.0, tall, 2.0),
                    cols=cols, shape="cyl", sides=10, solid=False)
            y += tall
        m.block(g, "PierCap", "phantom_light", (side * span, y + 0.9, 0), (2.8, 0.5, 2.8), shape="cyl", sides=10, solid=False)
    for k in range(13):           # the arch's stones, each a long wedge of the curve, none touching the next
        a = math.radians(7.0 + k * 13.8)
        far = 1.0 + 0.1 * math.sin(k * 2.1) + rng.uniform(0.0, 0.08)        # each drifted a little out of line
        x, y = -math.cos(a) * span * far, rise + 2.4 + math.sin(a) * span * 0.9 * far
        t = a - math.pi * 0.5 + rng.uniform(-0.16, 0.16)
        cols = ((math.cos(t), -math.sin(t), 0), (math.sin(t), math.cos(t), 0), (0, 0, 1))
        m.block(g, "ArchStone", "phantom", (x, y, rng.uniform(-0.35, 0.35)), (1.25, 1.5, 1.9), cols=cols, shape="bevel", bevel=0.3, solid=False)
    m.block(g, "Keystone", "phantom_light", (0, rise + 2.4 + span * 0.9 + 1.7, 0), (1.3, 2.4, 2.0), shape="cone", sides=4, top=0.9, cols=FLIP, solid=False)
    magic(m, g, "ArchMotes", MOTES, (0, 8.0, 0), (16.0, 16.0, 5.0), 40, (0.72, 0.8, 1.0), ACCENT_RGB[1], far=220.0)
    # 2. A stair of floating treads winding off the tower into nothing: by the Summoning Chamber.
    y0 = TIER * 4 + 6.0
    hub = P(ro(y0) + 9.5, 338.0, y0)
    g = m.group("StairToNowhere", f, at=hub)
    steps = 46
    for k in range(steps):
        a = math.radians(158.0 + k * 19.0)
        r = 8.4 - k * 0.035 + (k / steps) ** 3 * 9.0          # it winds round its own middle, then swings out and away
        fade = 1.0 - (k / (steps - 1.0)) ** 2 * 0.7
        m.block(g, "Tread", "phantom_light", (math.sin(a) * r, k * 0.46, math.cos(a) * r), (1.1 * fade, 0.18, 2.9 * fade),
                cols=yaw_cols(a), shape="bevel", bevel=0.06, solid=False)
        if k % 2 == 0 and k < steps - 6:        # a baluster at the outer end of every other tread, a rail's ghost along their tops
            m.block(g, "Baluster", "phantom", (math.sin(a) * (r + 1.3 * fade), k * 0.46 + 0.6, math.cos(a) * (r + 1.3 * fade)), (0.14, 1.1, 0.14), solid=False)
    m.block(g, "Newel", "phantom", (0, 9.0, 0), (0.6, 20.0, 0.6), shape="cyl", sides=8, solid=False)
    magic(m, g, "StairMotes", MOTES, (0, 10.0, 0), (20.0, 22.0, 20.0), 50, (0.72, 0.8, 1.0), ACCENT_RGB[4], far=220.0)
    # 3. The tower's own top, mirrored upside down under the root.
    g = m.group("Reflection", f, at=(0, -E.ROOT_DEPTH - 3.5, 0))
    m.cone(g, "MirrorWall", "phantom", (0, 0, 0), 15.0, 9.0, top=13.6, sides=16, flip=True, solid=False)
    m.block(g, "MirrorEaves", "phantom_light", (0, -9.3, 0), (17.0, 0.7, 17.0), shape="tube", sides=16, inner=14.0, solid=False)
    m.cone(g, "MirrorRoof", "phantom_roof", (0, -9.6, 0), 14.4, 12.5, top=1.0, sides=16, flip=True, solid=False)
    for k in range(8):
        deg = k * 45.0 + 11.25
        m.rod(g, "MirrorRib", "phantom_light", P(7.2, deg, -9.7), P(0.7, deg, -21.9), thick=0.16, wide=0.3)
    m.cone(g, "MirrorCrystal", "phantom_light", (0, -24.6, 0), 1.9, 3.4, sides=6, flip=True, solid=False)
    m.cone(g, "MirrorCrystalFoot", "phantom_light", (0, -24.6, 0), 1.9, 1.8, sides=6, solid=False)
    sp = m.node("MirrorOrrery", g, "spinner", [("transform", xform(((0.96, 0.28, 0), (-0.28, 0.96, 0), (0, 0, 1)), (0, -24.6, 0))), ("speed", "-7")])
    m.block(sp, "MirrorRing", "phantom_light", (0, 0, 0), (7.0, 0.12, 7.0), shape="tube", sides=24, inner=6.6, solid=False)
    magic(m, g, "MirrorMotes", MOTES, (0, -12.0, 0), (16.0, 22.0, 16.0), 60, (0.72, 0.8, 1.0), ACCENT_RGB[4], far=220.0)


# ---------------------------------------------------------------------------

SOUNDS = ("magic_engine", "magic_library", "magic_labs", "magic_menagerie", "magic_summoning", "magic_observatory")


def enchant(m, folders):
    shaft_magic(m)
    for i in range(5):
        g = m.group("Magic", folders[i], grouped=False)
        tier_motes(m, g, i)
        mana_line(m, m.group("ManaLine", g), i)
        (engine_magic, library_magic, labs_magic, menagerie_magic, summoning_magic)[i](m, g)
        m.node("Ambience", g, "ambient", [("transform", xform(IDENTITY, P((RS + rc(i)) * 0.5, 75.0, TIER * i + 6.0))), ("sound", '"%s"' % SOUNDS[i]),
                                          ("reach", "30.0"), ("near", "7.0")])
    g = m.group("Magic", folders[5], grouped=False)
    observatory_magic(m, g)
    m.node("Ambience", g, "ambient", [("transform", xform(IDENTITY, (0, TIER * 5 + 9.0, 0))), ("sound", '"%s"' % SOUNDS[5]), ("reach", "34.0"), ("near", "9.0")])
    outside_motes(m)
    phantoms(m)
    m.node("MagicField", ".", "field", [], type_="Node")
