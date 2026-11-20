"""Empyrean Tower, the second half of tools/arena/empyrean.py: what stands in the rooms
(each tier's fantasy side and its sci-fi side), the ring gates and the rune altar, the
debris field, the sensor masts, holograms, drones, grapple anchors, spawn points and
weapons. See empyrean.py for the plan and the conventions (P, rot, sectors)."""
import math
import random
from arena_builder import xform, fmt, vec, color, norm, cross, IDENTITY, yaw_cols
from cirrus import FLIP, LIE_X, LIE_Z
import empyrean as E
from empyrean import P, rot, ri, ro, rc, chord, TIER, L1, L2, L3, RS, ACCENT, ACCENT_RGB, NAMES, TOP

GATE_Y = 1.87          # a ring gate's middle above the floor it stands on
FRONTS = {}            # gate name -> the path of its "Front" marker (for the bots' links)


def spot(m, parent, name, r, deg, y, face=None):
    """A group at P(r, deg, y), turned so its own -z looks at the shaft (or, with `face`,
    so its +z looks along that angle)."""
    return m.group(name, parent, at=P(r, deg, y), yaw=math.radians(deg if face is None else face))


# ---------------------------------------------------------------------------
# Props. Each is built in its own group's frame: +z away from the shaft, y = 0 the floor.

def console(m, g, x=0.0, z=0.0, acc="conduit", holo="holo", wide=1.8):
    """A control console: alloy body, a lit screen sloping toward -z, a hologram over it."""
    m.bev(g, "Console", "alloy_dark", (x - wide / 2, 0, z - 0.45), (x + wide / 2, 0.95, z + 0.45), bevel=0.12)
    m.block(g, "Screen", "screen", (x, 1.05, z - 0.1), (wide - 0.3, 0.06, 0.7), cols=((1, 0, 0), (0, 0.94, 0.34), (0, -0.34, 0.94)), solid=False)
    m.box(g, "ConsoleTrim", acc, (x - wide / 2 + 0.1, 0.3, z - 0.49), (x + wide / 2 - 0.1, 0.4, z - 0.45), solid=False)
    if holo:
        m.box(g, "Readout", holo, (x - wide * 0.35, 1.5, z - 0.02), (x + wide * 0.35, 2.3, z + 0.02), solid=False)


def holo_book(m, g, x, y, z, kind="holo_gold"):
    """An open book of light: two pages in a shallow V."""
    for side in (-1, 1):
        m.block(g, "HoloPage", kind, (x + side * 0.33, y, z), (0.62, 0.03, 0.8), cols=((0.94, side * 0.34, 0), (-side * 0.34, 0.94, 0), (0, 0, 1)), solid=False)
    m.box(g, "HoloSpine", kind, (x - 0.03, y - 0.14, z - 0.4), (x + 0.03, y - 0.08, z + 0.4), solid=False)


def shelf(m, g, x0, x1, z, high, seed, deep=0.9):
    """A tall bookshelf along x, its books on both faces."""
    rng = random.Random(seed)
    m.box(g, "Shelf", "wood", (x0, 0, z - deep / 2), (x1, high, z + deep / 2))
    m.box(g, "ShelfCap", "brass", (x0 - 0.1, high, z - deep / 2 - 0.1), (x1 + 0.1, high + 0.18, z + deep / 2 + 0.1), solid=False)
    rows = int(high / 1.5)
    for r in range(rows):
        y = 0.35 + r * 1.5
        for face in (-1, 1):
            kind = ("books_red", "books_blue", "books_green")[rng.randrange(3)]
            zz = z + face * (deep / 2 + 0.03)
            m.box(g, "Books", kind, (x0 + 0.15, y, min(zz, zz - face * 0.05)), (x1 - 0.15, y + 1.0, max(zz, zz - face * 0.05)), solid=False)


def server(m, g, x0, x1, z, high, acc, seed, deep=0.9):
    """A data-archive stack: dark alloy, seams, rows of status lights, a conduit up its end."""
    rng = random.Random(seed)
    m.box(g, "ServerStack", "alloy_dark", (x0, 0, z - deep / 2), (x1, high, z + deep / 2))
    m.box(g, "ServerCap", "alloy", (x0 - 0.1, high, z - deep / 2 - 0.1), (x1 + 0.1, high + 0.18, z + deep / 2 + 0.1), solid=False)
    rows = int(high / 1.5)
    for r in range(rows):
        y = 0.6 + r * 1.5
        for face in (-1, 1):
            zz = z + face * (deep / 2 + 0.03)
            lit = acc if rng.random() < 0.7 else "screen"
            m.box(g, "StatusLights", lit, (x0 + 0.25, y, min(zz, zz - face * 0.04)), (x1 - 0.25, y + 0.12, max(zz, zz - face * 0.04)), solid=False)
            m.box(g, "Vent", "alloy", (x0 + 0.25, y + 0.3, min(zz, zz - face * 0.03)), (x1 - 0.25, y + 0.75, max(zz, zz - face * 0.03)), solid=False)
    m.box(g, "ServerConduit", "conduit", (x1, 0.2, z - 0.08), (x1 + 0.08, high - 0.2, z + 0.08), solid=False)


def tank(m, g, x, z, high=4.2, wide=2.0, fluid="fluid", acc="accent_green", plant=None):
    """A glass cylinder between alloy caps: a bio-tank of glowing fluid, or a pod with a plant in it."""
    m.cyl(g, "TankBase", "alloy_dark", (x, 0, z), wide + 0.5, 0.6, sides=12)
    m.cyl(g, "TankGlass", "glass_clear", (x, 0.6, z), wide, high - 1.2, sides=12, unbreakable=True)
    m.cyl(g, "TankCap", "alloy", (x, high - 0.6, z), wide + 0.5, 0.6, sides=12)
    m.block(g, "TankLight", acc, (x, 0.66, z), (wide + 0.56, 0.12, wide + 0.56), shape="tube", sides=12, inner=wide + 0.3, solid=False)
    if plant:
        m.cyl(g, "PodStem", "vine", (x, 0.6, z), 0.22, high * 0.4, sides=6, solid=False)
        m.block(g, "PodBloom", plant, (x, 0.6 + high * 0.4 + 0.45, z), (wide * 0.7, 0.9, wide * 0.7), shape="dome", sides=8, solid=False)
        m.block(g, "PodLeaf", "leaf", (x, 0.6 + high * 0.4, z), (wide * 0.8, 0.5, wide * 0.8), cols=FLIP, shape="dome", sides=8, solid=False)
    else:
        m.cyl(g, "TankFluid", fluid, (x, 0.62, z), wide - 0.25, high - 1.6, sides=12, solid=False)


def vat(m, g, x, z, wide=2.6, high=1.6, fluid="fluid"):
    """A bubbling vat: a brass-bound stone tub."""
    m.cyl(g, "Vat", "stone_dark", (x, 0, z), wide, high, sides=12)
    m.block(g, "VatBand", "brass", (x, high - 0.25, z), (wide + 0.16, 0.3, wide + 0.16), shape="tube", sides=12, inner=wide - 0.1, solid=False)
    m.cyl(g, "VatBrew", fluid, (x, high - 0.02, z), wide - 0.4, 0.08, sides=12, solid=False)
    for k in range(3):
        a = k * 2.1 + x
        m.block(g, "Bubble", fluid, (x + math.cos(a) * wide * 0.22, high + 0.14 + 0.1 * k, z + math.sin(a) * wide * 0.22), (0.3 + 0.1 * k, 0.2, 0.3 + 0.1 * k), shape="dome", sides=6, solid=False)


def robot_arm(m, g, x, z, y, reach=1.6, acc="accent_green"):
    """A robotic arm hanging over a bench: base, two links, a lit tool."""
    m.cyl(g, "ArmBase", "alloy_dark", (x, y, z), 0.6, 0.3, sides=8)
    a, b, c = (x, y + 0.3, z), (x + reach * 0.5, y + 1.5, z), (x + reach, y + 0.9, z + 0.3)
    m.rod(g, "ArmLink", "alloy", a, b, thick=0.22, wide=0.22)
    m.rod(g, "ArmLink", "alloy", b, c, thick=0.18, wide=0.18)
    m.block(g, "ArmJoint", "brass", b, (0.36, 0.36, 0.36), shape="bevel", bevel=0.08, solid=False)
    m.block(g, "ArmTool", acc, (c[0], c[1] - 0.15, c[2]), (0.16, 0.3, 0.16), solid=False)


def bench(m, g, x0, x1, z, kind="wood"):
    m.bev(g, "Bench", kind, (x0, 0, z - 0.6), (x1, 1.0, z + 0.6), bevel=0.08)
    m.box(g, "BenchTop", "alloy", (x0 - 0.05, 1.0, z - 0.65), (x1 + 0.05, 1.08, z + 0.65), solid=False)


def alembic(m, g, x, y, z):
    """Glassware: a bulb on a brass stand with a neck."""
    m.cyl(g, "AlembicStand", "brass", (x, y, z), 0.3, 0.25, sides=6, solid=False)
    m.block(g, "AlembicBulb", "glass_clear", (x, y + 0.45, z), (0.5, 0.4, 0.5), shape="dome", sides=8, solid=False)
    m.block(g, "AlembicBrew", "fluid", (x, y + 0.33, z), (0.36, 0.16, 0.36), shape="dome", sides=8, solid=False)
    m.rod(g, "AlembicNeck", "glass_clear", (x, y + 0.6, z), (x + 0.4, y + 0.95, z), thick=0.07, wide=0.07)


def chandelier(m, g, x, z, top, drop, acc, wide=3.0):
    """Something to hook in a tall room: a brass ring of crystal lamps on a chain, an alloy
    hub with a conduit in the middle. The hub and the ring's rim are solid."""
    y = top - drop
    m.cyl(g, "Chain", "alloy_dark", (x, y + 0.5, z), 0.16, drop - 0.5, sides=6, solid=False)
    m.cyl(g, "Hub", "alloy", (x, y - 0.2, z), 1.1, 0.8, sides=10)
    m.block(g, "HubLight", "conduit", (x, y - 0.3, z), (1.16, 0.14, 1.16), shape="tube", sides=10, inner=0.9, solid=False)
    m.block(g, "LampRing", "brass", (x, y, z), (wide, 0.22, wide), shape="tube", sides=16, inner=wide - 0.5, solid=False)
    for k in range(6):
        a = math.radians(k * 60.0)
        px, pz = x + math.sin(a) * (wide * 0.5 - 0.12), z + math.cos(a) * (wide * 0.5 - 0.12)
        m.block(g, "Lamp", acc, (px, y + 0.3, pz), (0.34, 0.5, 0.34), shape="cone", sides=6, solid=False)
        m.bev(g, "LampSeat", "brass", (px - 0.3, y - 0.2, pz - 0.3), (px + 0.3, y + 0.12, pz + 0.3), bevel=0.08)
        if k % 2 == 0:
            m.rod(g, "Spoke", "brass", (x, y, z), (px, y, pz), thick=0.08, wide=0.12)


def rune_circle(m, g, x, y, z, wide, acc, plate="alloy_floor"):
    """A rune circle etched into a metal deck plate: rings of light on alloy, glyph marks between."""
    m.cyl(g, "DeckPlate", plate, (x, y, z), wide + 0.6, 0.06, sides=24, solid=False)
    m.block(g, "RuneRing", acc, (x, y + 0.085, z), (wide, 0.05, wide), shape="tube", sides=32, inner=wide - 0.3, solid=False)
    m.block(g, "RuneRingInner", "glow", (x, y + 0.085, z), (wide * 0.6, 0.05, wide * 0.6), shape="tube", sides=6, inner=wide * 0.6 - 0.24, solid=False)
    for k in range(8):
        a = math.radians(k * 45.0 + 22.5)
        px, pz = x + math.sin(a) * wide * 0.4, z + math.cos(a) * wide * 0.4
        m.block(g, "Glyph", acc if k % 2 else "glow", (px, y + 0.085, pz), (0.5, 0.05, 0.14), cols=yaw_cols(a), solid=False)


def pylon(m, g, x, z, high, acc, arcane):
    """An arcane pylon (stone, a crystal at its tip) or an emitter pylon (alloy, a lit head)."""
    if arcane:
        m.cone(g, "Pylon", "stone_dark", (x, 0, z), 1.3, high, top=0.5, sides=6)
        m.cone(g, "PylonCrystal", acc, (x, high + 0.1, z), 0.6, 1.3, sides=6, solid=False)
        m.block(g, "PylonBand", "brass", (x, high * 0.5, z), (1.1, 0.2, 1.1), shape="tube", sides=6, inner=0.7, solid=False)
    else:
        m.cyl(g, "Emitter", "alloy", (x, 0, z), 0.8, high, sides=8)
        m.bev(g, "EmitterHead", "alloy_dark", (x - 0.6, high, z - 0.6), (x + 0.6, high + 0.7, z + 0.6), bevel=0.2)
        m.block(g, "EmitterLight", acc, (x, high + 0.35, z), (1.26, 0.2, 1.26), shape="tube", sides=8, inner=1.1, solid=False)
        m.box(g, "EmitterCable", "conduit", (x - 0.05, 0.2, z - 0.48), (x + 0.05, high - 0.2, z - 0.4), solid=False)


def floating_stone(m, g, at, size, acc, seed):
    rng = random.Random(seed)
    m.block(g, "FloatingStone", "rock" if seed % 2 else "stone_dark", at, (size, size * 0.6, size), shape="bevel", bevel=size * 0.2, cols=rot(rng.uniform(0, 90)))
    m.block(g, "StoneRune", acc, (at[0], at[1] + size * 0.3 + 0.04, at[2]), (size * 0.5, 0.06, size * 0.5), shape="tube", sides=6, inner=size * 0.5 - 0.16, solid=False)


def cage(m, g, x, z, top, drop, wide=2.4):
    """An empty creature cage hung from the ceiling: its floor and roof are solid (land on it, hook it)."""
    y = top - drop
    m.cyl(g, "CageChain", "alloy_dark", (x, y + 3.0, z), 0.16, drop - 3.0, sides=6, solid=False)
    m.cyl(g, "CageFloor", "brass", (x, y, z), wide, 0.25, sides=10)
    m.cone(g, "CageRoof", "brass", (x, y + 2.7, z), wide, 0.5, top=0.4, sides=10)
    for k in range(10):
        a = math.radians(k * 36.0)
        px, pz = x + math.sin(a) * (wide * 0.5 - 0.08), z + math.cos(a) * (wide * 0.5 - 0.08)
        if k % 5:
            m.cyl(g, "CageBar", "alloy_dark", (px, y + 0.25, pz), 0.09, 2.45, sides=4, solid=False)


def planter(m, g, x, z, wide, kinds=("leaf", "leaf_alien"), seed=0, tall=1.0):
    rng = random.Random(seed)
    m.cyl(g, "Planter", "stone", (x, 0, z), wide, 0.7, sides=10)
    m.cyl(g, "PlanterSoil", "soil", (x, 0.7, z), wide - 0.3, 0.05, sides=10, solid=False)
    for k in range(3):
        a = rng.uniform(0, 6.28)
        d = rng.uniform(0, wide * 0.25)
        s = rng.uniform(0.7, 1.2) * wide * 0.5 * tall
        m.block(g, "Plant", kinds[k % len(kinds)], (x + math.sin(a) * d, 0.75 + s * 0.45, z + math.cos(a) * d), (s, s * 0.9, s), shape="dome", sides=7, solid=False)
    m.cyl(g, "Stalk", "vine", (x, 0.7, z), 0.16, 1.2 * tall + 0.6, sides=5, solid=False)
    m.block(g, "Bloom", ("accent_teal", "accent_violet", "accent_gold")[seed % 3], (x, 1.3 + 1.2 * tall + 0.25, z), (0.5, 0.5, 0.5), shape="dome", sides=6, solid=False)


def machine(m, g, x0, x1, z0, z1, high, acc, pipes=True):
    """Heavy machinery: an alloy block with brass bands, a lit slot and a pipe over the top."""
    m.bev(g, "Machine", "alloy", (x0, 0, z0), (x1, high, z1), bevel=0.25)
    m.box(g, "MachineBand", "brass", (x0 - 0.04, high * 0.62, z0 - 0.04), (x1 + 0.04, high * 0.62 + 0.25, z1 + 0.04), solid=False)
    m.box(g, "MachineSlot", acc, (x0 + 0.4, high * 0.3, z0 - 0.03), (x1 - 0.4, high * 0.3 + 0.2, z0), solid=False)
    if pipes:
        m.lying_cyl(g, "MachinePipe", "alloy_dark", ((x0 + x1) / 2, high + 0.35, (z0 + z1) / 2), 0.6, x1 - x0 + 1.2, axis="x", sides=8)


# ---------------------------------------------------------------------------
# Ring gates and the altar

def gate(m, name, at, face, pair, acc, two_sided=True, link_to=None):
    """A ring gate standing on the floor at `at` (x, y, z), facing angle `face` (its front
    looks that way). The ring is alloy and brass with rune marks; its frame is solid
    (stand on it, hook it) except along the bottom, where you walk through."""
    g = m.group(name, "Gates", at=at, yaw=math.radians(face))
    m.cyl(g, "Plinth", "alloy_dark", (0, 0, 0), 5.2, 0.2, sides=24)
    m.block(g, "PlinthRune", acc, (0, 0.22, 0), (4.6, 0.05, 4.6), shape="tube", sides=24, inner=4.2, solid=False)
    m.block(g, "Ring", "alloy", (0, GATE_Y, 0), (4.7, 0.5, 4.7), cols=LIE_Z, shape="tube", sides=32, inner=3.3, solid=False)
    m.block(g, "RingLip", "brass", (0, GATE_Y, 0), (3.5, 0.62, 3.5), cols=LIE_Z, shape="tube", sides=32, inner=3.2, solid=False)
    m.block(g, "RingBand", "brass", (0, GATE_Y, 0), (4.9, 0.3, 4.9), cols=LIE_Z, shape="tube", sides=32, inner=4.6, solid=False)
    for k in range(12):
        a = math.radians(k * 30.0)
        px, py = math.sin(a) * 2.0, GATE_Y + math.cos(a) * 2.0
        cols = ((math.cos(a), -math.sin(a), 0), (math.sin(a), math.cos(a), 0), (0, 0, 1))
        if 4 <= k <= 8:
            continue       # the bottom arc: open, the plinth is the threshold
        m.block(g, "Frame", "alloy", (px, py, 0), (1.15, 0.72, 0.5), cols=cols, drawn=False)
        m.block(g, "RuneMark", acc if k % 2 else "glow", (math.sin(a) * 2.02, GATE_Y + math.cos(a) * 2.02, 0), (0.5, 0.1, 0.56), cols=cols, solid=False)
    for side in (-1, 1):       # feet: stone on one side, an alloy housing with a conduit on the other
        m.bev(g, "Foot", "stone_dark" if side < 0 else "alloy_dark", (side * 2.0 - 0.55, 0.2, -0.6), (side * 2.0 + 0.55, 1.5, 0.6), bevel=0.18)
        m.box(g, "FootLight", "glow" if side < 0 else "conduit", (side * 2.0 - 0.3, 0.5, 0.6), (side * 2.0 + 0.3, 0.62, 0.64), solid=False)
    props = [("transform", xform(IDENTITY, (0, GATE_Y, 0))), ("pair", str(pair))]
    if not two_sided:
        props.append(("two_sided", "false"))
    m.node("Gate", g, "gate", props)
    FRONTS[name] = m.node("Front", g, None, [("transform", xform(IDENTITY, (0, 0.2, 2.4)))], type_="Marker3D")
    if link_to:
        m.node("Through", g, "link", [("transform", xform(IDENTITY, (0, 0.2, 2.4))), ("how", "5"), ("hook", 'NodePath("../Gate")'),
                                      ("landing", 'NodePath("../../%s/Front")' % link_to)], type_="Marker3D")
    return g


def altar(m, f):
    """The rune altar in the Summoning Chamber: a rune-circle dais, a stone and brass
    pedestal with an alloy console top and holographic readouts. Hold interact here for
    2 s to start the Portal Surge."""
    y0 = TIER * 4
    g = spot(m, f, "Altar", RS + 6.0, 75.0, y0)
    m.cyl(g, "Dais", "alloy_floor", (0, 0, 0), 7.0, 0.22, sides=24)
    rune_circle(m, g, 0, 0.2, 0, 6.2, "accent_violet")
    m.bev(g, "Pedestal", "stone", (-0.75, 0.22, -0.75), (0.75, 0.9, 0.75), bevel=0.15)
    m.box(g, "PedestalBand", "brass", (-0.8, 0.6, -0.8), (0.8, 0.75, 0.8), solid=False)
    m.bev(g, "ConsoleTop", "alloy_dark", (-0.9, 0.9, -0.9), (0.9, 1.3, 0.9), bevel=0.2)
    m.block(g, "ConsoleRune", "accent_violet", (0, 1.31, 0), (1.3, 0.04, 1.3), shape="tube", sides=6, inner=1.0, solid=False)
    for k in range(4):
        a = math.radians(k * 90.0 + 45.0)
        px, pz = math.sin(a) * 1.05, math.cos(a) * 1.05
        m.block(g, "Readout", "holo" if k % 2 else "holo_gold", (px, 2.0, pz), (0.8, 0.5, 0.03), cols=yaw_cols(a), solid=False)
        m.cyl(g, "ReadoutEmitter", "brass", (px * 0.8, 1.3, pz * 0.8), 0.14, 0.12, sides=6, solid=False)
    m.node("MapTerminal", g, "terminal", [("transform", xform(IDENTITY, (0, 0.22, 0))), ("channel_time", "2.0"), ("range", "2.0"),
                                          ("light", "Color(0.75, 0.5, 1, 1)"), ("event", 'NodePath("../../../PortalSurge")')])
    return g


# ---------------------------------------------------------------------------
# The six tiers' rooms. A feature room is sectors 0-9 (0 to 150 degrees), its middle at 75.

def hall_lights(m, f, i):
    """What every tier shares: its accent in the feature room (a band of light round the
    back wall, lamps on the balcony fronts), chandeliers to hook."""
    y0 = TIER * i
    acc = ACCENT[i]
    g = m.group("Lights", f)
    for k in range(E.FEAT):
        deg = (k + 0.5) * 15.0
        r = ri(y0 + L3 - 1.0)
        m.pb(g, "AccentBand", acc, r - 0.12, r, deg, chord(r, 24) * 0.9, y0 + L3 - 1.5, y0 + L3 - 1.1, solid=False)
        m.pb(g, "BalconyLamp", acc, rc(i) - 0.2, rc(i) - 0.12, deg, chord(rc(i), 24) * 0.5, y0 + L1 - 0.4, y0 + L1 - 0.2, solid=False)
    for k in range(E.FEAT, 24):          # the corridor's light: a strip under each storey along the outer lane
        deg = (k + 0.5) * 15.0
        for y in (y0 + L1 - 0.56, y0 + L2 - 0.56, y0 + L3 - 0.56):
            m.pb(g, "CorridorLight", acc if k % 2 else "glow", rc(i) + 1.1, rc(i) + 1.5, deg, chord(rc(i), 24) * 0.7, y, y + 0.06, solid=False)
    for n, deg in enumerate((38.0, 75.0, 112.0)):
        at = P((RS + rc(i)) * 0.5 + (1.5 if n == 1 else 0.0), deg, 0)
        chandelier(m, g, at[0], at[2], y0 + L3 - 0.5, 4.5 + (n % 2) * 2.5, acc)
    for n in range(8):                   # the upper hall: lamps on the colonnade
        deg = n * 45.0 + 20.0
        m.pb(g, "HallLamp", acc if n % 2 else "glow", RS + 3.5, RS + 6.0, deg, 0.5, y0 + TIER - 0.72, y0 + TIER - 0.6, solid=False)


def engine(m, f):
    """Arcane Engine: the crystal core is a fusion reactor. Fantasy: rune conduits in the
    stone floor, brass, the crystal. Sci-fi: coolant pipes, consoles, heavy machinery."""
    y0, acc, i = 0.0, "accent_cyan", 0
    g = m.group("Reactor", f)
    for k in range(12):          # rune conduits in the floor, from the basin to the wall
        deg = k * 30.0 + 15.0
        m.pb(g, "RuneConduit", acc if k % 2 else "glow", 4.4, ri(0) - 0.6, deg, 0.22, 0.0, 0.03, solid=False)
    for k in range(4):           # consoles round the basin, facing it
        s = spot(m, g, "Console", 6.3, k * 90.0 + 30.0, 0.0)
        console(m, s, acc=acc)
    for n, deg in enumerate((22.0, 50.0, 96.0, 118.0)):        # heavy machinery along the feature room
        s = spot(m, g, "Machine", RS + 6.5 + (n % 2) * 3.5, deg, 0.0)
        machine(m, s, -2.2, 2.2, -1.4, 1.4, 3.2 + (n % 2) * 1.2, acc)
        m.cyl(s, "Coolant", "alloy", (3.2, 0, 0.4), 1.5, 5.0 + n, sides=10)
        m.block(s, "CoolantBand", "brass", (3.2, 2.2, 0.4), (1.66, 0.3, 1.66), shape="tube", sides=10, inner=1.4, solid=False)
        m.block(s, "CoolantGlow", acc, (3.2, 4.2, 0.4), (1.6, 0.16, 1.6), shape="tube", sides=10, inner=1.4, solid=False)
    # Coolant pipes sweeping round the room under the first balcony, and up to the core.
    for y, r in ((4.6, rc(i) - 1.0), (5.2, rc(i) - 2.0)):
        for k in range(0, E.FEAT):
            m.pipe(g, "CoolantPipe", "alloy_dark" if y < 5 else "brass", P(r, k * 15.0 + 1.0, y0 + y), P(r, k * 15.0 + 14.0, y0 + y), diameter=0.5)
    for deg in (25.0, 125.0):
        m.bar(g, "FeedPipe", "alloy", P(rc(i) - 1.0, deg, 4.6), P(RS - 2.5, deg, 8.6), thick=0.5, wide=0.5)
        m.bar(g, "FeedArm", "stone_dark", P(RS - 2.6, deg, 8.6), P(RS - 2.6, deg, 0.0), thick=0.6, wide=0.6)
    for n, deg in enumerate((60.0, 90.0)):       # brass-bound stone plinths with crystals: the arcane side
        s = spot(m, g, "CrystalPlinth", RS + 3.2, deg, 0.0)
        m.bev(s, "Plinth", "stone", (-0.9, 0, -0.9), (0.9, 1.2, 0.9), bevel=0.2)
        m.cone(s, "PlinthCrystal", "crystal", (0, 1.2, 0), 1.0, 2.2, sides=6)
        m.block(s, "PlinthBand", "brass", (0, 1.0, 0), (2.0, 0.2, 2.0), shape="tube", sides=4, inner=1.7, solid=False)
    hall_lights(m, f, i)


def library(m, f):
    """Grand Library: towering shelves that alternate with data-archive stacks, reading
    consoles with holographic books, books of light drifting in slow orbits."""
    i = 1
    y0, acc = TIER * i, "accent_gold"
    g = m.group("Stacks", f)
    for n, deg in enumerate((23.0, 39.0, 55.0, 95.0, 111.0, 127.0)):      # radial rows, 11 m tall
        s = m.group("Row", g, at=P(0, 0, y0), yaw=math.radians(deg - 90.0))   # (its x runs out from the shaft)
        x0, x1 = RS + 3.2, rc(i) - 1.6
        mid = (x0 + x1) * 0.5
        if n % 2 == 0:
            shelf(m, s, x0, mid - 0.6, 0, 11.0, n)
            server(m, s, mid + 0.6, x1, 0, 11.0, acc, n)
        else:
            server(m, s, x0, mid - 0.6, 0, 11.0, acc, n)
            shelf(m, s, mid + 0.6, x1, 0, 11.0, n)
        m.bar(s, "Ladder", "brass", (mid - 2.5, 0, 0.75), (mid - 1.6, 10.8, 0.5), thick=0.12, wide=0.7, solid=False)
        m.box(s, "LadderRail", "brass", (x0, 10.6, 0.46), (x1, 10.72, 0.56), solid=False)
    for n, deg in enumerate((31.0, 47.0, 75.0, 103.0, 119.0)):            # reading consoles, a book of light over each
        s = spot(m, g, "Reading", RS + 4.6 + (n % 2) * 4.0, deg, y0)
        console(m, s, acc=acc, holo=None)
        holo_book(m, s, 0, 1.9, 0)
    for n, (r, deg, y) in enumerate(((RS + 5.0, 66.0, 9.0), (RS + 7.5, 84.0, 13.0), (RS + 3.6, 75.0, 15.5))):
        at = P(r, deg, y0 + y)                    # books drifting in slow orbits (scenery)
        sp = m.node("BookOrbit", g, "spinner", [("transform", xform(IDENTITY, at)), ("speed", fmt(7.0 - n * 4.0))])
        for k in range(5):
            a = math.radians(k * 72.0)
            px, pz = math.sin(a) * (2.0 + n * 0.5), math.cos(a) * (2.0 + n * 0.5)
            if k % 2:
                holo_book(m, sp, px, 0.3 * k - 0.6, pz)
            else:
                m.block(sp, "Book", ("books_red", "books_blue", "books_green")[k % 3], (px, 0.3 * k - 0.6, pz), (0.6, 0.14, 0.8), cols=yaw_cols(a), solid=False)
    for lvl in (L1, L2):          # shelves and stacks along the reading balconies' back wall
        for k in ((1, 3, 5, 7, 8) if lvl == L1 else (0, 2, 7, 9)):
            s = spot(m, g, "BalconyStack", ri(y0 + lvl + 3.0) - 0.75, k * 15.0 + 7.5, y0 + lvl)
            (shelf if k % 2 else server)(m, s, -2.0, 2.0, 0, 4.4, *(() if k % 2 else (acc,)), k)
    hall_lights(m, f, i)


def labs(m, f):
    """Alchemy Labs: bubbling vats, alembics and distillation columns; bio-tanks of
    glowing fluid, robotic arms over the benches, a tangle of alloy pipes. Dense cover."""
    i = 2
    y0, acc = TIER * i, "accent_green"
    g = m.group("Apparatus", f)
    spots = [(RS + 3.4, 20.0), (RS + 8.0, 32.0), (RS + 4.0, 50.0), (RS + 8.6, 64.0), (RS + 8.6, 88.0), (RS + 4.0, 100.0), (RS + 8.0, 118.0), (RS + 3.4, 132.0)]
    for n, (r, deg) in enumerate(spots):
        s = spot(m, g, "Station", r, deg, y0)
        if n % 4 == 0:
            vat(m, s, 0, 0)
            m.cyl(s, "Column", "brass", (2.0, 0, 0.3), 0.9, 6.0, sides=8)             # a distillation column
            for b in range(3):
                m.block(s, "ColumnRing", "stone_dark", (2.0, 1.4 + b * 1.8, 0.3), (1.2, 0.3, 1.2), shape="tube", sides=8, inner=0.8, solid=False)
            m.block(s, "ColumnCap", "glass_clear", (2.0, 6.3, 0.3), (0.9, 0.6, 0.9), shape="dome", sides=8, solid=False)
        elif n % 4 == 1:
            tank(m, s, -1.3, 0, acc=acc)
            tank(m, s, 1.3, 0.2, high=5.0, acc=acc)
        elif n % 4 == 2:
            bench(m, s, -2.4, 2.4, 0)
            robot_arm(m, s, -1.2, -0.2, 1.08, acc=acc)
            alembic(m, s, 0.9, 1.08, 0.1)
            alembic(m, s, 1.7, 1.08, -0.2)
        else:
            vat(m, s, -1.2, 0, wide=2.0, high=1.3)
            bench(m, s, 0.6, 3.6, 0, kind="alloy_dark")
            robot_arm(m, s, 2.8, 0.1, 1.08, reach=-1.5, acc=acc)
            alembic(m, s, 1.2, 1.08, 0.2)
    # The pipe tangle overhead: alloy mains you can hook and stand on, thin brass feeds between them.
    for n, (r, y) in enumerate(((RS + 2.6, 9.0), (RS + 6.2, 11.5), (RS + 9.8, 8.0))):
        for k in range(1, 9):
            a0, a1 = k * 15.0 + 2.0, k * 15.0 + 16.0
            m.bar(g, "PipeMain", "alloy" if n % 2 else "alloy_dark", P(r, a0, y0 + y), P(r, a1, y0 + y), thick=0.7, wide=0.7)
        for deg in (30.0, 62.0, 88.0, 120.0):
            m.pipe(g, "PipeDrop", "brass", P(r, deg + n * 4.0, y0 + y), P(r + 1.2, deg + n * 4.0, y0 + 2.0), diameter=0.22)
            m.block(g, "Valve", acc, P(r, deg + n * 4.0, y0 + y - 0.5), (0.5, 0.2, 0.5), shape="cyl", sides=8, solid=False)
    for lvl in (L1, L2):          # tanks and benches on the balconies
        for k in ((1, 4, 6, 8) if lvl == L1 else (1, 8)):
            s = spot(m, g, "BalconyBench", ri(y0 + lvl + 3.0) - 1.0, k * 15.0 + 7.5, y0 + lvl)
            if k % 2:
                tank(m, s, 0, 0, high=3.6, wide=1.6, acc=acc)
            else:
                bench(m, s, -1.8, 1.8, 0)
                alembic(m, s, -0.8, 1.08, 0)
                robot_arm(m, s, 0.6, 0, 1.08, reach=1.0, acc=acc)
    hall_lights(m, f, i)


def menagerie(m, f):
    """Menagerie: alien plants, hanging vines and empty cages hung at every height;
    xenobotany pods of glass and alloy, grow-light rigs overhead."""
    i = 3
    y0, acc = TIER * i, "accent_teal"
    g = m.group("Garden", f)
    rng = random.Random(33)
    for n, (r, deg) in enumerate(((RS + 3.5, 22.0), (RS + 7.6, 40.0), (RS + 3.8, 58.0), (RS + 7.2, 92.0), (RS + 3.8, 108.0), (RS + 7.4, 128.0))):
        s = spot(m, g, "Bed", r, deg, y0)
        if n % 2 == 0:
            planter(m, s, 0, 0, 3.4, seed=n, tall=1.6)
        else:
            tank(m, s, -1.2, 0, high=4.6, wide=1.9, acc=acc, plant="leaf_alien")     # a containment pod
            tank(m, s, 1.3, 0.3, high=3.6, wide=1.7, acc=acc, plant="accent_violet")
            console(m, s, x=0.0, z=-1.6, acc=acc, wide=1.4)
    for n, (r, deg, drop) in enumerate(((RS + 2.6, 30.0, 5.0), (RS + 6.0, 50.0, 9.5), (RS + 3.0, 70.0, 13.0), (RS + 6.5, 84.0, 6.5),
                                        (RS + 2.8, 100.0, 10.5), (RS + 6.0, 118.0, 4.0), (RS + 4.5, 138.0, 8.0))):
        at = P(r, deg, 0)
        cage(m, g, at[0], at[2], y0 + L3 - 0.5, drop)
    # Grow-light rigs: alloy trusses across the room (hook them, run along them), strips of light under them.
    for n, deg in enumerate((34.0, 62.0, 90.0, 122.0)):
        y = y0 + 14.5 + (n % 2) * 2.0
        a, b = P(RS + 0.6, deg, y), P(rc(i) + 0.4, deg, y)
        m.bar(g, "GrowRig", "alloy_dark", a, b, thick=0.5, wide=1.4)
        m.bar(g, "GrowLight", acc if n % 2 else "accent_violet", (a[0], a[1] - 0.3, a[2]), (b[0], b[1] - 0.3, b[2]), thick=0.1, wide=0.9, solid=False)
        m.cyl(g, "RigHanger", "brass", P((RS + rc(i)) * 0.5, deg, y + 0.25), 0.2, L3 - 0.75 - (y - y0), sides=6, solid=False)
    for k in range(18):          # vines hanging from the balconies and the ceiling
        deg = rng.uniform(4.0, 146.0)
        r = rng.choice([rc(i) - 0.3, rng.uniform(RS + 1.0, rc(i) - 1.0)])
        top = y0 + (L1 if abs(r - (rc(i) - 0.3)) < 0.01 and k % 2 else L3) - 0.5
        L = rng.uniform(2.0, 5.5)
        m.cyl(g, "Vine", "vine" if k % 3 else "leaf_alien", P(r, deg, top - L), 0.18, L, sides=5, solid=False)
        m.block(g, "VineLeaf", "leaf", P(r, deg, top - L + 0.1), (0.7, 0.5, 0.7), cols=FLIP, shape="dome", sides=6, solid=False)
    for lvl in (L1, L2):
        for k in ((0, 2, 4, 6, 9) if lvl == L1 else (0, 2, 7, 9)):
            s = spot(m, g, "BalconyBed", ri(y0 + lvl + 3.0) - 1.1, k * 15.0 + 7.5, y0 + lvl)
            if k % 4 == 0:
                tank(m, s, 0, 0, high=3.4, wide=1.6, acc=acc, plant="leaf_alien")
            else:
                planter(m, s, 0, 0, 2.2, seed=k)
    hall_lights(m, f, i)


def summoning(m, f):
    """Summoning Chamber: rune circles and arcane pylons, floating stones; a teleporter
    lab whose circles are set in deck plates, ringed by emitter pylons, cables and consoles."""
    i = 4
    y0, acc = TIER * i, "accent_violet"
    g = m.group("Circles", f)
    altar(m, f)
    for n, (r, deg) in enumerate(((RS + 5.0, 28.0), (RS + 4.6, 118.0))):      # two lesser circles
        s = spot(m, g, "Circle", r, deg, y0)
        rune_circle(m, s, 0, 0.0, 0, 5.0, acc)
        for k in range(4):
            a = math.radians(k * 90.0 + 45.0)
            pylon(m, s, math.sin(a) * 3.3, math.cos(a) * 3.3, 3.4 + (k % 2) * 1.2, acc, arcane=(k + n) % 2 == 0)
    for n, deg in enumerate((44.0, 58.0, 92.0, 106.0)):      # pylons round the altar: stone and alloy by turns
        s = spot(m, g, "AltarPylon", RS + 6.0 + (4.6 if n in (1, 2) else 1.0), deg, y0)
        pylon(m, s, 0, 0, 5.0, acc, arcane=n % 2 == 0)
    for deg in (50.0, 100.0):                                # consoles a little way off, their backs to the wall
        s = spot(m, g, "TeleportConsole", rc(i) + 1.6, deg, y0, face=deg + 180.0)
        console(m, s, acc=acc)
    for n, deg in enumerate((36.0, 64.0, 86.0, 114.0)):      # power cables across the deck to the altar (drawn only)
        a, b = P(rc(i) + 1.0, deg, y0 + 0.04), P(RS + 6.0 + 3.6, 75.0 + (deg - 75.0) * 0.3, y0 + 0.04)
        m.rod(g, "Cable", "conduit" if n % 2 else "alloy_dark", a, b, thick=0.06, wide=0.22)
    for n, (r, deg, y) in enumerate(((RS + 2.0, 40.0, 7.0), (RS + 9.0, 60.0, 11.0), (RS + 3.0, 95.0, 13.5), (RS + 8.5, 110.0, 8.0),
                                     (RS + 5.5, 20.0, 12.0), (RS + 5.5, 132.0, 6.0), (RS + 1.6, 75.0, 10.0))):
        floating_stone(m, g, P(r, deg, y0 + y), 2.2 + (n % 3) * 0.5, acc, n)
    for lvl in (L1, L2):
        for k in ((1, 3, 6, 8) if lvl == L1 else (1, 8)):
            s = spot(m, g, "BalconyPylon", ri(y0 + lvl + 3.0) - 1.0, k * 15.0 + 7.5, y0 + lvl)
            pylon(m, s, 0, 0, 3.0, acc, arcane=k % 2 == 1)
            console(m, s, x=1.8, z=0.0, acc=acc, wide=1.2) if k % 2 == 0 else None
    hall_lights(m, f, i)


def observatory(m, f):
    """Observatory: brass instruments and star maps; the great telescope is a space
    telescope on a motorized mount, with sensor dishes round it and a hologram of the
    planet turning over the middle of the room."""
    i = 5
    y0, acc = TIER * i, "accent_silver"
    g = m.group("Instruments", f)
    # The telescope on the shaft's platform: a motorized mount of alloy, a brass-banded barrel.
    m.cyl(g, "MountBase", "alloy_dark", (0, y0, 0), 5.0, 0.8, sides=16)
    m.block(g, "MountLight", acc, (0, y0 + 0.82, 0), (5.1, 0.1, 5.1), shape="tube", sides=16, inner=4.7, solid=False)
    m.cyl(g, "MountPost", "alloy", (0, y0 + 0.8, 0), 2.0, 3.2, sides=12)
    for side in (-1, 1):
        m.bev(g, "MountFork", "alloy", (side * 1.7 - 0.35, y0 + 3.6, -1.0), (side * 1.7 + 0.35, y0 + 7.2, 1.0), bevel=0.15)
        m.block(g, "MountMotor", "brass", (side * 2.15, y0 + 6.2, 0), (0.6, 1.2, 1.2), shape="bevel", bevel=0.2)
    axis = norm((0.0, 0.62, -0.78))        # the barrel points up and toward the north
    X = (1.0, 0.0, 0.0)
    cols = (X, axis, cross(X, axis))
    c = (0, y0 + 6.4, 0)
    along = lambda d: tuple(p + a * d for p, a in zip(c, axis))
    m.block(g, "Barrel", "stone", along(1.5), (2.6, 11.0, 2.6), cols=cols, shape="cyl", sides=16)
    for d in (-3.2, 0.5, 4.2, 6.6):
        m.block(g, "BarrelBand", "brass", along(d), (2.9, 0.4, 2.9), cols=cols, shape="tube", sides=16, inner=2.5, solid=False)
    m.block(g, "Lens", "glass_clear", along(7.05), (2.3, 0.2, 2.3), cols=cols, shape="cyl", sides=16, solid=False)
    m.block(g, "Eyepiece", "alloy_dark", along(-4.6), (1.2, 1.6, 1.2), cols=cols, shape="cyl", sides=10)
    m.block(g, "SensorPack", "alloy_dark", tuple(p + 1.7 * q for p, q in zip(along(2.0), cross(X, axis))), (1.2, 3.0, 0.8), cols=cols, shape="bevel", bevel=0.15)
    m.block(g, "SensorLight", acc, tuple(p + 2.12 * q for p, q in zip(along(2.0), cross(X, axis))), (0.8, 2.4, 0.06), cols=cols, solid=False)
    # The planet, as a hologram: two half shells turning slowly over the telescope.
    sp = m.node("PlanetHologram", g, "spinner", [("transform", xform(IDENTITY, (0, y0 + 19.0, 0))), ("speed", "4.0")])
    m.block(sp, "PlanetNorth", "planet_holo", (0, 2.4, 0), (9.6, 4.8, 9.6), shape="dome", sides=16, solid=False)
    m.block(sp, "PlanetSouth", "planet_holo", (0, -2.4, 0), (9.6, 4.8, 9.6), cols=FLIP, shape="dome", sides=16, solid=False)
    m.block(sp, "PlanetBand", "holo_gold", (0, 0.6, 0), (9.9, 0.5, 9.9), shape="tube", sides=24, inner=9.5, solid=False)
    m.block(sp, "PlanetStorm", "holo", (3.3, -1.2, 2.8), (2.2, 1.0, 2.2), shape="dome", sides=8, solid=False)
    m.block(g, "OrbitLine", "holo", (0, y0 + 19.0, 0), (13.0, 0.06, 13.0), shape="tube", sides=32, inner=12.7, solid=False)
    m.block(g, "HoloBeam", "holo", (0, y0 + 14.0, 3.6), (0.5, 3.0, 0.5), shape="cone", sides=6, cols=FLIP, solid=False)
    # Round the room: brass instruments (armillaries on stone plinths) by turns with sensor dishes and consoles.
    for n in range(8):
        deg = n * 45.0 + 22.5
        if n in (5, 6):
            continue        # (where the ramps from the Summoning Chamber come up)
        s = spot(m, g, "Instrument", RS + 5.2, deg, y0)
        if n % 2 == 0:
            m.bev(s, "Plinth", "stone", (-0.8, 0, -0.8), (0.8, 1.1, 0.8), bevel=0.2)
            for k, tilt in enumerate(((1, 0, 0), (0.7, 0, 0.7), (0, 0, 1))):
                Y = norm((tilt[0], 0.45, tilt[2]))
                Xa = norm(cross(Y, (0.1, 1.0, 0.2)))
                m.block(s, "Armillary", "brass", (0, 2.4, 0), (2.4 - k * 0.3, 0.12, 2.4 - k * 0.3), cols=(Xa, Y, cross(Xa, Y)), shape="tube", sides=20, inner=2.2 - k * 0.3, solid=False)
            m.block(s, "ArmillaryStar", "glow", (0, 2.4, 0), (0.5, 0.5, 0.5), shape="dome", sides=8, solid=False)
            m.cyl(s, "ArmillaryStem", "brass", (0, 1.1, 0), 0.16, 1.2, sides=6, solid=False)
        else:
            console(m, s, acc=acc, holo=None)
            # a star map: a disc of light with stars on it
            m.block(s, "StarMap", "holo", (0, 2.2, 0), (2.4, 0.04, 2.4), cols=((1, 0, 0), (0, 0.5, -0.87), (0, 0.87, 0.5)), shape="cyl", sides=20, solid=False)
            for k in range(6):
                a = k * 1.1 + n
                m.block(s, "Star", "glow" if k % 2 else "screen", (math.sin(a) * (0.3 + 0.14 * k), 2.2 + math.cos(a) * (0.3 + 0.14 * k) * 0.87, 0.06 - math.cos(a) * (0.3 + 0.14 * k) * 0.5),
                        (0.12, 0.12, 0.12), solid=False)
    for n, deg in enumerate((15.0, 50.0, 100.0, 135.0, 170.0)):       # the sensor-dish array on the gallery
        s = spot(m, g, "Dish", ri(y0 + 12.0) - 1.3, deg, y0 + 9.0)
        m.cyl(s, "DishPost", "alloy", (0, 0, 0), 0.4, 1.8, sides=8)
        Y = norm((0.0, 0.6, -0.8))
        m.block(s, "DishBowl", "alloy" if n % 2 else "brass", (0, 2.3, -0.2), (2.4, 0.7, 2.4), cols=((1, 0, 0), tuple(-v for v in Y), cross((1, 0, 0), tuple(-v for v in Y))),
                shape="dome", sides=12, inner=2.2, solid=False)
        m.block(s, "DishFeed", acc, (0, 2.6, -0.6), (0.2, 0.2, 0.2), solid=False)
    for n in range(6):       # a great star chart on the ceiling: rings and points of light
        m.block(g, "CeilingRing", "glow" if n % 2 else "holo", (0, TOP - 0.1, 0), (8.0 + n * 5.0, 0.08, 8.0 + n * 5.0), shape="tube", sides=48, inner=7.8 + n * 5.0, solid=False)
    rng = random.Random(55)
    for n in range(40):
        at = P(rng.uniform(4.0, 18.5), rng.uniform(0, 360), TOP - 0.12)
        m.block(g, "CeilingStar", "screen" if n % 3 else "glow", at, (0.3, 0.1, 0.3), shape="cyl", sides=6, solid=False)
    for n, deg in enumerate((38.0, 112.0, 250.0, 290.0)):
        at = P(RS + 5.0, deg, 0)
        chandelier(m, g, at[0], at[2], TOP - 0.3, 9.0 + (n % 2) * 4.0, acc, wide=3.4)
    for n, (r, deg, y) in enumerate(((RS + 3.0, 200.0, 14.0), (RS + 7.0, 240.0, 19.0), (RS + 4.0, 305.0, 16.0), (RS + 6.5, 80.0, 21.0), (RS + 2.0, 20.0, 17.0))):
        floating_stone(m, g, P(r, deg, y0 + y), 2.4, acc, n + 20)


def rooms(m, folders):
    """The rooms on the corridor side of every tier (sectors 10-23): furniture that is both
    cover and character, a little of each half in every room."""
    for i in range(5):
        y0 = TIER * i
        acc = ACCENT[i]
        g = m.group("Rooms", folders[i])
        for lvl, base in enumerate((0.0, L1, L2)):
            for n, k in enumerate((1, 3, 6, 10, 12)):
                deg = (E.FEAT + k) * 15.0 + 7.5
                s = spot(m, g, "Nook", RS + 4.2, deg, y0 + base)
                pick = (i + lvl + n) % 4
                if pick == 0:
                    shelf(m, s, -1.8, 1.8, 0, 3.6, i * 10 + n)
                    console(m, s, x=0, z=-1.6, acc=acc, wide=1.3, holo=None)
                elif pick == 1:
                    server(m, s, -1.8, 1.8, 0, 3.6, acc, i * 10 + n)
                    m.bev(s, "Chest", "wood", (-0.7, 0, -1.9), (0.7, 0.8, -1.1), bevel=0.1)
                    m.box(s, "ChestBand", "brass", (-0.74, 0.45, -1.94), (0.74, 0.58, -1.06), solid=False)
                elif pick == 2:
                    machine(m, s, -1.6, 1.6, -0.8, 0.8, 2.6, acc, pipes=False)
                    pylon(m, s, 2.6, 0.3, 2.8, acc, arcane=True)
                else:
                    tank(m, s, -1.0, 0, high=3.4, wide=1.6, acc=acc)
                    m.bev(s, "Desk", "wood", (0.4, 0, -0.5), (2.6, 0.95, 0.5), bevel=0.08)
                    holo_book(m, s, 1.5, 1.6, 0)
            # the upper hall: benches of each half between the pillars
        for n, deg in enumerate((20.0, 60.0, 100.0, 140.0)):
            s = spot(m, g, "HallPiece", (RS + ri(y0 + L3)) * 0.5 + 1.0, deg, y0 + L3)
            if n % 2 == 0:
                machine(m, s, -2.0, 2.0, -1.0, 1.0, 2.8, acc)
            else:
                m.bev(s, "Statue", "stone", (-1.0, 0, -1.0), (1.0, 1.4, 1.0), bevel=0.2)
                m.cone(s, "StatueCrystal", "crystal", (0, 1.4, 0), 1.2, 2.8, sides=6)
                m.block(s, "StatueHalo", acc, (0, 3.2, 0), (2.2, 0.08, 2.2), shape="tube", sides=16, inner=2.0, solid=False)


# ---------------------------------------------------------------------------
# Outside: the debris field, the sensor masts, drones, anchors

ORBITS = ((62.0, 28.0, 1.6, 20.0), (74.0, 103.0, -1.2, 140.0), (60.0, 164.0, 1.0, 260.0))    # (radius, height, degrees a second, home angle)
GATE_ISLES = (("GateLibraryFar", 78.0, 75.0, 46.0, 2, "accent_gold"), ("GateMenagerieFar", 80.0, 165.0, 112.0, 4, "accent_teal"))


def chunk(m, g, wide, seed, deck="stone_floor", deep=None):
    """A chunk of broken masonry with a flat top (y = 0) to stand on, rock hanging under it.
    Built in the frame of the group it is given."""
    rng = random.Random(seed)
    deep = deep or wide * 0.7
    m.cyl(g, "Top", deck, (0, -0.8, 0), wide, 0.8, sides=rng.choice([7, 8, 9]))
    m.cone(g, "Under", "rock", (0, -0.8, 0), wide * 0.96, deep, top=wide * 0.12, sides=rng.choice([6, 7, 8]), flip=True, yaw=rng.uniform(0, 50))
    for k in range(2):
        a = rng.uniform(0, 6.28)
        m.cone(g, "Spur", "rock_dark", (math.sin(a) * wide * 0.22, -0.9, math.cos(a) * wide * 0.22), wide * 0.5, deep * rng.uniform(0.7, 1.2), sides=5, flip=True, yaw=rng.uniform(0, 60))
    # what is left of the building it came from: a stretch of wall, a column stump, an alloy rib
    a = rng.uniform(0, 6.28)
    h = rng.uniform(1.8, 3.2)
    m.block(g, "WallStump", "stone", (math.sin(a) * wide * 0.3, h * 0.5, math.cos(a) * wide * 0.3), (wide * 0.5, h, 0.8), cols=yaw_cols(a))
    b = a + rng.uniform(1.8, 3.6)
    m.cyl(g, "ColumnStump", "stone_dark", (math.sin(b) * wide * 0.3, 0, math.cos(b) * wide * 0.3), 1.0, rng.uniform(1.0, 2.6), sides=8)
    c = b + 1.4
    m.bar(g, "BentRib", "alloy", (math.sin(c) * wide * 0.36, 0, math.cos(c) * wide * 0.36), (math.sin(c) * wide * 0.5, rng.uniform(2.5, 4.5), math.cos(c) * wide * 0.5), thick=0.4, wide=0.7)
    m.block(g, "RibLight", "conduit", (math.sin(c) * wide * 0.36, 0.05, math.cos(c) * wide * 0.36), (0.9, 0.08, 0.9), shape="cyl", sides=6, solid=False)


def debris(m):
    f = m.folder("Debris")
    rng = random.Random(2026)
    taken = []       # (r, deg, y, clear radius)
    spawn_isles = []

    def free(r, deg, y, need):
        if abs(y - E.RING_Y) < 14.0 and r < 72.0 and abs((deg - E.PAD_DEG + 180) % 360 - 180) < 40:
            return False     # the pad and the starship
        for orb_r, orb_y, _s, _d in ORBITS:
            if abs(y - orb_y) < 16.0 and abs(r - orb_r) < 17.0:
                return False     # an orbiting chunk's path
        for lift_deg, lift_r in ((E.LIFT_C, E.C_R), (E.LIFT_D, E.D_R)):
            if abs((deg - lift_deg + 180) % 360 - 180) < 12 and r < lift_r + 14.0:
                return False
        a = P(r, deg, y)
        return all(math.dist(a, P(*t[:3])) > need + t[3] for t in taken)

    # The two islands the far ring gates stand on (they never move).
    for name, r, deg, y, pair, acc in GATE_ISLES:
        g = m.group(name.replace("Gate", "Isle"), f, at=P(r, deg, y), yaw=math.radians(deg))
        chunk(m, g, 15.0, pair * 7, deck="alloy_floor" if pair == 4 else "stone_floor")
        taken.append((r, deg, y, 10.0))
        m.hook(g, "Anchor", (0, 9.0, 0))
        m.cyl(g, "AnchorMast", "alloy_dark", (4.6, 0, -3.0), 0.4, 7.0, sides=8)
        m.block(g, "AnchorLamp", acc, (4.6, 7.2, -3.0), (0.8, 0.5, 0.8), shape="bevel", bevel=0.15, solid=False)
        at = P(r, deg, y)
        gate(m, name, (at[0], at[1], at[2]), deg + 90.0, pair, acc)
    # Three big still islands people spawn on, each a grapple swing from somewhere solid:
    # two off the docking ring, one off the apron at the tower's foot. The bots' way back
    # from each is a MapJumpLink (they all carry the grapple here: MapRoot.bots_grapple).
    ways = m.folder("Ways", f)
    for n, (r, deg, y, land_r, land_y) in enumerate(((59.0, 30.0, 95.0, E.RING_R - 3.5, E.RING_Y), (59.0, 338.0, 94.0, E.RING_R - 3.5, E.RING_Y),
                                                     (56.0, 135.0, 3.0, E.R_FOOT + 1.6, 0.0))):
        g = m.group("SpawnIsle%d" % (n + 1), f, at=P(r, deg, y), yaw=math.radians(deg))
        chunk(m, g, 13.0, 50 + n, deck="stone_floor" if n % 2 else "alloy_floor")
        taken.append((r, deg, y, 9.0))
        spawn_isles.append((r, deg, y))
        m.hook(g, "Anchor", (0, 8.0, 0))
        # (the way back: stand at the island's near edge, hook the mast by the landing, come down on it)
        mast = P(land_r + 2.6, deg, land_y)
        m.cyl(ways, "WayMast", "alloy_dark", mast, 0.4, 7.5, sides=8)
        m.block(ways, "WayLamp", "glow", (mast[0], mast[1] + 7.7, mast[2]), (0.8, 0.5, 0.8), shape="bevel", bevel=0.15, solid=False)
        m.hook(ways, "Hook%d" % (n + 1), (mast[0], mast[1] + 8.4, mast[2]))
        m.node("Land%d" % (n + 1), ways, None, [("transform", xform(IDENTITY, P(land_r, deg, land_y)))], type_="Marker3D")
        m.node("Back%d" % (n + 1), ways, "link", [("transform", xform(IDENTITY, P(r - 5.2, deg, y))), ("how", "0"),
                                                  ("hook", 'NodePath("../Hook%d")' % (n + 1)), ("landing", 'NodePath("../Land%d")' % (n + 1))], type_="Marker3D")
    # The wrecked shuttle, on a chunk of its own.
    r, deg, y = 70.0, 322.0, 66.0
    g = m.group("WreckedShuttle", f, at=P(r, deg, y), yaw=math.radians(deg + 40.0))
    chunk(m, g, 14.0, 91, deck="alloy_floor")
    taken.append((r, deg, y, 10.0))
    tilt = ((0.97, 0.26, 0), (-0.26, 0.97, 0), (0, 0, 1))
    m.block(g, "ShuttleHull", "ship", (0.5, 1.9, 0.5), (3.4, 2.6, 8.0), cols=tilt, shape="bevel", bevel=0.7)
    m.block(g, "ShuttleNose", "ship", (0.5, 1.9, -4.8), (2.6, 3.0, 2.6), cols=((0.97, 0.26, 0), (0, 0, -1), (0.26, -0.97, 0)), shape="cone", sides=8, top=0.8)
    m.slab(g, "ShuttleWing", "ship", (1.6, 2.3, 1.5), (6.2, 3.6, 2.6), 3.4, thick=0.35)
    m.block(g, "ShuttleEngine", "alloy_dark", (0.2, 1.7, 4.9), (1.8, 1.6, 1.8), cols=((1, 0, 0), (0, 0, 1), (0, -1, 0)), shape="cyl", sides=10)
    m.block(g, "ShuttleScorch", "alloy_dark", (-1.6, 0.03, 0.5), (3.0, 0.06, 6.0), solid=False)
    m.block(g, "ShuttleSpark", "conduit", (2.1, 2.4, -1.0), (0.2, 0.2, 1.6), cols=tilt, solid=False)
    m.hook(g, "Anchor", (0, 8.0, 0))
    # The broken satellite.
    r, deg, y = 58.0, 110.0, 138.0
    g = m.group("BrokenSatellite", f, at=P(r, deg, y), yaw=math.radians(35.0))
    taken.append((r, deg, y, 9.0))
    tip = ((0.9, 0.0, 0.44), (0.0, 1.0, 0.0), (-0.44, 0.0, 0.9))
    m.lying_cyl(g, "Bus", "alloy", (0, 0, 0), 3.0, 6.0, axis="x", sides=10)
    m.block(g, "BusBand", "brass", (1.4, 0, 0), (3.2, 0.5, 3.2), cols=LIE_X, shape="tube", sides=10, inner=2.9, solid=False)
    m.box(g, "PanelWhole", "alloy_dark", (-1.0, -0.15, 1.6), (1.0, 0.15, 9.5))
    m.box(g, "PanelCells", "conduit", (-0.8, 0.15, 2.0), (0.8, 0.19, 9.2), solid=False)
    m.block(g, "PanelSnapped", "alloy_dark", (0.4, 0.6, -4.2), (2.0, 0.3, 4.6), cols=tip)
    m.block(g, "Dish", "ship", (-3.6, 0, 0), (3.6, 1.1, 3.6), cols=((0, 1, 0), (-1, 0, 0), (0, 0, 1)), shape="dome", sides=12, inner=3.4)
    m.cyl(g, "Mast", "alloy_dark", (2.0, 1.5, 0), 0.25, 4.5, sides=6)
    m.hook(g, "Anchor", (0, 6.5, 0))
    # Still chunks, hull plates, rune rings and crystal shards, at every height, most within 76 m of the wall.
    n = 0
    tries = 0
    while n < 18 and tries < 4000:
        tries += 1
        y = rng.uniform(-18.0, TOP + 22.0)
        r = ro(max(0.0, min(y, TOP))) + rng.uniform(14.0, 72.0) ** 1.0 * (0.55 if rng.random() < 0.6 else 1.0)
        deg = rng.uniform(0, 360)
        kind = ("chunk", "chunk", "plate", "ring", "shard", "chunk", "plate", "shard")[n % 8]
        size = {"chunk": rng.uniform(6.0, 12.0), "plate": 6.0, "ring": 5.0, "shard": 4.0}[kind]
        if not free(r, deg, y, size * 0.6 + 4.0):
            continue
        taken.append((r, deg, y, size * 0.6))
        n += 1
        g = m.group({"chunk": "Chunk", "plate": "HullPlate", "ring": "RuneRing", "shard": "CrystalShard"}[kind], f, at=P(r, deg, y), yaw=math.radians(rng.uniform(0, 360)))
        if kind == "chunk":
            chunk(m, g, size, n, deck="alloy_floor" if n % 3 == 0 else "stone_floor")
            if n % 2:
                m.hook(g, "Anchor", (0, 7.0, 0))
        elif kind == "plate":
            t = rng.uniform(-0.35, 0.35)
            cols = ((math.cos(t), math.sin(t), 0), (-math.sin(t), math.cos(t), 0), (0, 0, 1))
            m.block(g, "Plate", "ship" if n % 2 else "alloy", (0, 0, 0), (rng.uniform(5.0, 8.0), 0.5, rng.uniform(4.0, 7.0)), cols=cols, shape="bevel", bevel=0.2)
            m.block(g, "PlateRib", "alloy_dark", (0, -0.45, 0), (0.5, 0.5, 5.0), cols=cols)
            m.block(g, "PlateStripe", "conduit" if n % 4 < 2 else "glow", (1.2, 0.27, 0), (0.25, 0.04, 3.4), cols=cols, solid=False)
        elif kind == "ring":
            m.block(g, "Core", "rock", (0, 0, 0), (2.6, 2.2, 2.6), shape="bevel", bevel=0.7)
            for q, (ax, wide, speed) in enumerate((((0.3, 1, 0.1), 7.0, 9.0), ((1, 0.3, 0.4), 9.0, -6.0))):
                Y = norm(ax)
                X = norm(cross(Y, (0.2, 0.3, 1.0)))
                sp = m.node("Turning", g, "spinner", [("transform", xform((X, Y, cross(X, Y)), (0, 0, 0))), ("speed", fmt(speed))])
                m.block(sp, "Ring", "brass", (0, 0, 0), (wide, 0.3, wide), shape="tube", sides=24, inner=wide - 0.7, solid=False)
                for k in range(6):
                    m.block(sp, "RingRune", ("accent_gold", "accent_violet", "accent_cyan")[(n + k) % 3], P(wide * 0.5 - 0.18, k * 60.0), (0.7, 0.34, 0.2), cols=rot(k * 60.0), solid=False)
            m.hook(g, "Anchor", (0, 2.4, 0))
        else:
            acc = ACCENT[n % 6]
            m.cone(g, "Shard", "crystal", (0, 0, 0), 2.4, rng.uniform(4.0, 7.0), sides=6)
            m.cone(g, "ShardFoot", "crystal", (0, 0, 0), 2.4, 2.6, sides=6, flip=True)
            m.block(g, "ShardCollar", "alloy_dark", (0, 0, 0), (2.9, 0.5, 2.9), shape="tube", sides=6, inner=2.2, solid=False)
            m.block(g, "ShardLight", acc, (0, 0.3, 0), (3.0, 0.1, 3.0), shape="tube", sides=6, inner=2.8, solid=False)
    # The three chunks that orbit (MapIslands turned by the OrbitEvent): each carries a power weapon.
    for n, ((r, y, speed, deg), weapon) in enumerate(zip(ORBITS, ("railgun", "rocket_launcher", "anti_materiel"))):
        isle = m.node("Orbiter%d" % (n + 1), f, "island", [("transform", xform(rot(deg), P(r, deg, y))), ("pivot", "Vector3(0, 0, 0)"), ("orbit", fmt(speed))])
        chunk(m, isle, 13.0, 300 + n, deck="alloy_floor" if n % 2 else "stone_floor", deep=8.0)
        m.cyl(isle, "Beacon", "alloy_dark", (-4.0, 0, 2.0), 0.5, 6.0, sides=8)
        m.block(isle, "BeaconLamp", ACCENT[(n * 2 + 1) % 6], (-4.0, 6.3, 2.0), (1.0, 0.6, 1.0), shape="bevel", bevel=0.2, solid=False)
        m.block(isle, "WeaponRune", "glow", (0, 0.04, 0), (3.0, 0.06, 3.0), shape="tube", sides=6, inner=2.6, solid=False)
        m.hook(isle, "Anchor", (0, 8.0, 0))
        m.weapon_in(isle, (0, 0.1, 0), weapon)
    m.node("Orbit", ".", "orbit", [], type_="Node")
    return spawn_isles


def anchors(m):
    """Floating grapple anchors outside the wall, so the next one is always in reach: a
    spiral of them 13 m off the wall, one every 45 degrees, 28 m up for each turn (about
    30 m from one to the next, and 28 m to the one above)."""
    g = m.group("Anchors", "Exterior")
    k = 0
    y = 6.0
    while y < TOP + 30.0:
        deg = (k * 45.0 + 30.0) % 360.0
        r = ro(min(y, TOP)) + 13.0 if y < TOP else 23.0
        if not (abs(y - E.RING_Y) < 12.0 and abs((deg - E.PAD_DEG + 180) % 360 - 180) < 45) and not (abs(y - E.RING_Y) < 3.0):
            at = P(r, deg, y)
            m.hook(g, "SkyAnchor", at)
            # (a small buoy, not a rock: these are hooks to swing from, not islands)
            m.block(g, "AnchorBuoy", "brass" if k % 2 else "alloy_dark", (at[0], at[1] - 0.9, at[2]), (0.7, 0.9, 0.7), shape="bevel", bevel=0.25, cols=rot(deg + 30))
            m.block(g, "AnchorLight", "glow" if k % 2 else "conduit", (at[0], at[1] - 0.9, at[2]), (0.78, 0.2, 0.78), shape="bevel", bevel=0.2, cols=rot(deg + 30), solid=False)
        y += 3.5
        k += 1


def masts(m):
    """The antenna and sensor arrays on the eaves, beside the orrery: masts, dishes and
    spires, all solid (hook them, stand on the dishes' brackets)."""
    f = m.folder("SensorArray", "Exterior")
    y = TOP + 2.6
    for n in range(8):
        deg = n * 45.0 + 22.5
        g = m.group("Mast", f, at=P(E.R_TOP + 1.2, deg, y), yaw=math.radians(deg))
        if n % 2 == 0:
            m.cyl(g, "Mast", "alloy", (0, 0, 0), 0.5, 15.0 + (n % 4) * 3.0, sides=8)
            m.cone(g, "MastTip", "brass", (0, 15.0 + (n % 4) * 3.0, 0), 0.5, 2.4, sides=8)
            for k in range(3):
                m.box(g, "Crossbar", "alloy_dark", (-1.4 + k * 0.3, 5.0 + k * 3.4, -0.12), (1.4 - k * 0.3, 5.3 + k * 3.4, 0.12))
            m.block(g, "MastLight", ACCENT[5], (0, 12.0, 0), (0.7, 0.3, 0.7), shape="bevel", bevel=0.1, solid=False)
        else:
            m.cyl(g, "DishPost", "alloy_dark", (0, 0, 0), 0.7, 3.4, sides=8)
            m.box(g, "Bracket", "brass", (-1.6, 3.0, -0.4), (1.6, 3.4, 2.4))
            Y = norm((0.0, 0.55, 0.83))
            m.block(g, "Dish", "alloy", (0, 4.9, 1.4), (5.0, 1.5, 5.0), cols=((1, 0, 0), tuple(-v for v in Y), cross((1, 0, 0), tuple(-v for v in Y))), shape="dome", sides=12, inner=4.7)
            m.bar(g, "Feed", "brass", (0, 4.2, 0.9), (0, 5.9, 3.0), thick=0.14, wide=0.14)
            m.block(g, "FeedLight", "conduit", (0, 6.0, 3.1), (0.3, 0.3, 0.3), solid=False)
        m.block(g, "Footing", "stone_dark", (0, 0.2, 0), (1.6, 0.4, 1.6), shape="bevel", bevel=0.12)
    return f


def drones(m):
    f = m.folder("Drones")
    for n, (y, off, speed) in enumerate(((16.0, 9.0, 7.0), (52.0, 12.0, -5.0), (84.0, 7.0, 6.0), (118.0, 14.0, -8.0), (146.0, 9.0, 5.0), (176.0, 11.0, -6.0),
                                         (200.0, 6.0, 9.0), (-12.0, 16.0, 4.0))):
        r = ro(max(0.0, min(y, TOP))) + off if y < TOP else 10.0 + off
        m.node("Drone", f, "drone", [("transform", xform(IDENTITY, (0, y, 0))), ("radius", fmt(r)), ("speed", fmt(speed)), ("phase", fmt((n * 0.37) % 1.0)),
                                     ("lamp", color(ACCENT_RGB[n % 6]))])
    for n, y in enumerate((40.0, 100.0, 168.0)):        # ...and three in the shaft
        m.node("ShaftDrone", f, "drone", [("transform", xform(IDENTITY, (0, y, 0))), ("radius", "2.6"), ("speed", fmt(11.0 - n * 9.0)), ("bob", "1.6"),
                                          ("phase", fmt(n * 0.3)), ("lamp", color(ACCENT_RGB[(n * 2 + 1) % 6]))])


# ---------------------------------------------------------------------------
# Gates, spawn points, weapons

def gates(m):
    m.folder("Gates")
    g1 = "GateEngine", "GateObservatory"
    g3 = "GateLabs", "GateSummoning"
    # 1: Arcane Engine <-> Observatory. 3: Alchemy Labs <-> Summoning Chamber (bots know these two).
    gate(m, g1[0], P(RS + 9.0, 141.0, 0.0), 51.0, 1, "accent_cyan", link_to=g1[1])
    gate(m, g1[1], P(RS + 7.0, 135.0, TIER * 5), 45.0, 1, "accent_silver", link_to=g1[0])
    gate(m, g3[0], P(RS + 9.4, 10.0, TIER * 2), 100.0, 3, "accent_green", link_to=g3[1])
    gate(m, g3[1], P(RS + 8.8, 144.0, TIER * 4), 54.0, 3, "accent_violet", link_to=g3[0])
    # 2: Grand Library <-> a still island. 4: Menagerie <-> another. Their far ends are built with the debris.
    gate(m, "GateLibrary", P(RS + 8.6, 8.0, TIER * 1), 98.0, 2, "accent_gold")
    gate(m, "GateMenagerie", P(RS + 8.6, 142.0, TIER * 3), 52.0, 4, "accent_teal")
    m.node("PortalSurge", ".", "surge", [("open_time", "2.0"), ("duration", "30.0"), ("close_time", "2.0"), ("cooldown", "60.0"),
                                         ("pulse_kinds", 'PackedStringArray("glow", "conduit")')], type_="Node")


def spawns(m, isles):
    for i in range(5):
        y0 = TIER * i
        if i == 4:        # the Summoning Chamber: nowhere that sees the altar
            spots = [(rc(i) + 1.3, 262.0, L1), (RS + 5.0, 320.0, L2), (RS + 6.0, 252.0, L3), (rc(i) + 1.3, 200.0, 0.0)]
        else:
            spots = [(RS + 6.0, 185.0, 0.0), (RS + 6.0, 321.0, L1), (RS + 6.5, 60.0, L3), (rc(i) + 1.3, 262.0, L2)]
        for r, deg, lvl in spots[:4 if i in (1, 3) else 3]:
            at = P(r, deg, y0 + lvl + 0.1)
            m.spawn(at, P(r + 6.0 if r < 14 else r - 6.0, deg + 20.0, 0)[0::2])
    y0 = TIER * 5
    for r, deg, lvl in ((RS + 7.0, 40.0, 0.0), (RS + 6.0, 188.0, 0.0), (ri(y0 + 9.0) - 1.6, 118.0, 9.0)):
        m.spawn(P(r, deg, y0 + lvl + 0.1), (0, 0))
    for deg in (120.0, 20.0):         # the docking ring
        m.spawn(P(E.RING_R - 4.0, deg, E.RING_Y + 0.1), P(60.0, deg, 0)[0::2])
    for r, deg, y in isles[:3]:       # the larger still islands
        m.spawn(P(r - 1.0, deg, y + 0.1), (0, 0))


def weapons(m):
    T = lambda i: TIER * i
    inside = [
        # Arcane Engine
        (P(RS + 10.0, 75.0, T(0) + 0.1), "shotgun"), (P(rc(0) + 1.3, 250.0, T(0) + L1 + 0.1), "smg"), (P(RS + 4.0, 300.0, T(0) + L3 + 0.1), "revolver"),
        # Grand Library
        (P(RS + 9.0, 75.0, T(1) + 0.1), "rifle"), (P(rc(1) + 2.4, 60.0, T(1) + L1 + 0.1), "burst_rifle"), (P(RS + 4.0, 190.0, T(1) + L3 + 0.1), "crossbow"),
        # Alchemy Labs
        (P(RS + 11.5, 75.0, T(2) + 0.1), "break_action"), (P(rc(2) + 2.4, 20.0, T(2) + L2 + 0.1), "pistol"), (P(RS + 5.0, 352.0, T(2) + L1 + 0.1), "nail_gun"),
        # Menagerie
        (P(RS + 5.6, 75.0, T(3) + 0.1), "lmg"), (P(rc(3) + 2.4, 128.0, T(3) + L2 + 0.1), "lever_action"), (P(RS + 4.0, 230.0, T(3) + L3 + 0.1), "machine_pistol"),
        # Summoning Chamber: nothing on or near the altar
        (P(rc(4) + 1.3, 300.0, T(4) + L1 + 0.1), "battle_rifle"), (P(RS + 8.5, 200.0, T(4) + L3 + 0.1), "laser_rifle"),
        # Observatory: a power weapon on the gallery
        (P(ri(T(5) + 9.0) - 1.6, 75.0, T(5) + 9.1), "sniper"), (P(RS + 5.0, 318.0, T(5) + 0.1), "bolt_action"),
        # Outside: the docking ring, the eaves among the sensor masts
        (P(E.RING_R - 3.0, 55.0, E.RING_Y + 0.1), "crossbow"),
        (P(E.R_TOP + 0.7, 0.0, TOP + 2.7), "grenade_launcher"),
    ]
    for at, weapon in inside:
        m.weapon(at, weapon)


def dress(m, folders):
    engine(m, folders[0])
    library(m, folders[1])
    labs(m, folders[2])
    menagerie(m, folders[3])
    summoning(m, folders[4])
    observatory(m, folders[5])
    rooms(m, folders)
    gates(m)
    isles = debris(m)
    anchors(m)
    masts(m)
    drones(m)
    # The plasma cannon on the starship's back. (No signs anywhere on this map: no floating label text.)
    m.weapon_in("Exterior/DockingRing/Pad/Starship", (0, 5.0, 0.0), "plasma_cannon")
    spawns(m, isles)
    weapons(m)
