"""Neon Arcade: a small arena (1v1 and small free-for-alls). One big room of arcade
cabinets with an L-shaped mezzanine (north and west walls) behind glass railings, a
party room under it, a change booth in the middle to climb, steel trusses under the
roof to hook, open skylights up to the roof, and a glass shop front onto the street.

Heights: floor 0 m, stage 0.6 m, booth roof 3 m, mezzanine 4.5 m, trusses 7.4-8 m,
roof 9.6 m.
"""
import math
from arena_builder import Map, palette

PAL = "res://game/maps/palettes/neon_arcade.tres"

COLORS = {
    "carpet": (0.2, 0.14, 0.32), "carpet_spots": (0.36, 0.2, 0.5), "tile": (0.22, 0.22, 0.26),
    "wall": (0.16, 0.15, 0.22), "wall_panel": (0.26, 0.22, 0.36), "wall_outer": (0.5, 0.48, 0.55),
    "mezz_floor": (0.3, 0.2, 0.42), "partition": (0.44, 0.3, 0.58), "glass": (0.55, 0.75, 0.86),
    "glass_rail": (0.5, 0.76, 0.86), "door": (0.4, 0.6, 0.7), "steel": (0.42, 0.44, 0.5),
    "truss": (0.3, 0.31, 0.36), "cab_red": (0.7, 0.16, 0.22), "cab_blue": (0.16, 0.3, 0.72),
    "cab_black": (0.1, 0.1, 0.13), "cab_yellow": (0.9, 0.7, 0.14), "screen": (0.3, 0.85, 1.0),
    "screen_pink": (1.0, 0.35, 0.75), "marquee": (1.0, 0.9, 0.55), "neon_pink": (1.0, 0.25, 0.7),
    "neon_cyan": (0.2, 0.95, 1.0), "neon_yellow": (1.0, 0.86, 0.2), "neon_green": (0.35, 1.0, 0.45),
    "counter": (0.85, 0.35, 0.55), "shelf": (0.36, 0.3, 0.44), "prize": (0.95, 0.6, 0.2),
    "prize_blue": (0.35, 0.6, 0.95), "stage": (0.12, 0.12, 0.16), "dance_pad": (0.9, 0.3, 0.9),
    "hockey": (0.9, 0.92, 0.96), "claw_glass": (0.6, 0.85, 0.95), "roof": (0.4, 0.4, 0.43),
    "parapet": (0.55, 0.52, 0.58), "ac_unit": (0.7, 0.72, 0.74), "sidewalk": (0.6, 0.6, 0.6),
    "street": (0.3, 0.3, 0.32), "backdrop": (0.36, 0.34, 0.44), "backdrop_dark": (0.26, 0.25, 0.34),
    "window_lit": (1.0, 0.85, 0.55), "lamp": (1.0, 0.95, 0.85), "table": (0.85, 0.85, 0.9),
    "sofa": (0.2, 0.7, 0.75), "kerb": (0.72, 0.72, 0.7), "shutter": (0.46, 0.48, 0.52), "tyre": (0.08, 0.08, 0.09),
    "beacon": (1.0, 0.2, 0.15),
}
# The pattern each colour is drawn with (MapScenery.SURFACES).
SURFACE = {
    "carpet": "confetti", "wall": "panels", "wall_outer": "bricks", "mezz_floor": "checker", "partition": "panels_plain",
    "roof": "tarmac", "sidewalk": "pavers", "street": "tarmac", "backdrop": "windows_lit", "backdrop_dark": "windows_lit",
    "stage": "planks", "ac_unit": "slats", "shutter": "slats", "shelf": "planks",
}
GLOW = {"screen": 1.6, "screen_pink": 1.6, "marquee": 1.4, "neon_pink": 3.0, "neon_cyan": 3.0,
        "neon_yellow": 3.0, "neon_green": 3.0, "lamp": 1.5, "window_lit": 0.8, "dance_pad": 1.2, "beacon": 2.5}
BREAKABLE = {"glass": 25, "glass_rail": 40, "partition": 100, "mezz_floor": 200, "roof": 300}

X0, X1, Z0, Z1 = -18, 18, -14, 14     # inside faces of the outer walls
MZ, MX = -9, -13                      # mezzanine edges: north part z < MZ, west part x < MX
MY = 4.5                              # mezzanine floor height


def build(path):
    m = Map("NeonArcade", PAL,
            {"sky": {"sky_top_color": (0.14, 0.16, 0.36), "sky_horizon_color": (0.62, 0.42, 0.6),
                     "ground_bottom_color": (0.12, 0.1, 0.16), "ground_horizon_color": (0.5, 0.36, 0.5)},
             "lines": ["ambient_light_source = 2", "ambient_light_color = Color(0.78, 0.74, 0.95, 1)",
                       "ambient_light_energy = 1.05", "tonemap_mode = 2", "tonemap_white = 2.4",
                       "ssao_enabled = true", "glow_enabled = true", "glow_intensity = 1.1"]},
            (32, 250, (1.0, 0.72, 0.6), 0.9),
            {"face_shade": "Vector3(0.93, 0.84, 0.66)", "kill_height": "-6.0",
             "bounds": "Rect2(-23, -19, 46, 42)", "swing_point": "Vector3(0, 7.4, 0)"})
    shell(m)
    mezzanine(m)
    floor_games(m)
    party_room(m)
    street(m)
    roof(m)
    details(m)
    spawns(m)
    pickups(m)
    m.write(path)
    palette(path.replace("game/maps/", "game/maps/palettes/").replace(".tscn", ".tres"), COLORS, GLOW, BREAKABLE,
            roughness=0.7, surface=SURFACE)


def shell(m):
    g = m.group("Shell")
    m.box(g, "Floor", "carpet", (X0 - 0.8, -0.5, Z0 - 0.8), (X1 + 0.8, 0, Z1 + 0.8))
    H = 9.1   # the walls stop under the roof slab (through it, their tops and sides would lie in its faces)
    m.box(g, "NorthWall", "wall", (X0 - 0.8, 0, Z0 - 0.8), (X1 + 0.8, H, Z0))
    m.box(g, "WestWall", "wall", (X0 - 0.8, 0, Z0), (X0, H, Z1))
    m.box(g, "EastWall", "wall", (X1, 0, Z0), (X1 + 0.8, H, Z1))
    m.box(g, "FireDoor", "steel", (X1 - 0.06, 0, Z0 + 1.5), (X1, 2.4, Z0 + 3.1), solid=False)
    m.box(g, "ExitSign", "neon_green", (X1 - 0.08, 2.6, Z0 + 1.9), (X1 - 0.02, 2.9, Z0 + 2.7), solid=False)
    # Shop front: glass panes (they break, and then the street is yours) and glass doors.
    m.wall(g, "Front", "wall_outer", (X0 - 0.8, Z1 + 0.4), (X1 + 0.8, Z1 + 0.4), 0, H, 0.8,
           holes=[(4.8, 14.8, 0.8, 4.0), (17.3, 20.3, 0, 3.0), (22.8, 32.8, 0.8, 4.0)])
    for x0 in (-14, -9, 4, 9):
        m.box(g, "Window", "glass", (x0, 0.8, Z1 + 0.34), (x0 + 5, 4.0, Z1 + 0.46))
    m.box(g, "Doors", "door", (-1.5, 0, Z1 + 0.34), (1.5, 3.0, Z1 + 0.46))
    # Wall panels and neon strips.
    for z in range(-12, 13, 4):
        m.box(g, "Panel", "wall_panel", (X0, 0.4, z - 1.6), (X0 + 0.05, 3.6, z + 1.6), solid=False)
    m.box(g, "NeonStrip", "neon_pink", (X0, 8.2, Z0), (X0 + 0.08, 8.35, Z1), solid=False)
    m.box(g, "NeonStrip", "neon_cyan", (X1 - 0.08, 8.2, Z0), (X1, 8.35, Z1), solid=False)
    m.box(g, "NeonStrip", "neon_cyan", (X0 + 0.08, 8.2, Z0), (X1 - 0.08, 8.35, Z0 + 0.08), solid=False)
    m.box(g, "NeonStrip", "neon_pink", (X0 + 0.08, 8.2, Z1 - 0.08), (X1 - 0.08, 8.35, Z1), solid=False)
    # Trusses under the roof (hook them, or stand on them).
    t = m.group("Trusses")
    for x in (-12, -6, 0, 6, 12):
        m.box(t, "Truss", "truss", (x - 0.2, 7.4, Z0), (x + 0.2, 8.0, Z1))
        m.box(t, "Light", "lamp", (x - 0.15, 7.25, -6), (x + 0.15, 7.4, 6), solid=False)
    m.box(t, "Spine", "truss", (X0, 7.6, -0.2), (X1, 8.0, 0.2))


def mezzanine(m):
    g = m.group("Mezzanine")
    m.box(g, "FloorNorth", "mezz_floor", (X0, MY - 0.3, Z0), (X1, MY, MZ))
    m.box(g, "FloorWest", "mezz_floor", (X0, MY - 0.3, MZ), (MX, MY, Z1))
    m.box(g, "EdgeBeam", "steel", (MX, MY - 0.7, MZ - 0.4), (X1, MY - 0.3, MZ))
    m.box(g, "EdgeBeam", "steel", (MX, MY - 0.7, MZ), (MX + 0.4, MY - 0.3, Z1))
    for x in (-7, -1, 6, 12, 17.6):
        m.box(g, "Column", "steel", (x - 0.2, 0, MZ - 0.4), (x + 0.2, MY - 0.7, MZ))
    for z in (-3, 3, 13.6):
        m.box(g, "Column", "steel", (MX, 0, z - 0.2), (MX + 0.4, MY - 0.7, z + 0.2))
    m.box(g, "Column", "steel", (MX, 0, MZ - 0.4), (MX + 0.4, MY - 0.7, MZ))
    # Glass railings, open where the stairs arrive.
    m.rail(g, "Railing", "glass_rail", (MX, MZ - 0.06), (X1, MZ - 0.06), MY, 1.1, 0.12, holes=[(25.0, 27.4)])
    m.rail(g, "Railing", "glass_rail", (MX + 0.06, MZ), (MX + 0.06, Z1), MY, 1.1, 0.12, holes=[(17.0, 19.4)])
    m.box(g, "Handrail", "neon_cyan", (MX, MY + 1.1, MZ - 0.1), (X1, MY + 1.18, MZ - 0.02), solid=False)
    m.box(g, "Handrail", "neon_pink", (MX + 0.02, MY + 1.1, MZ), (MX + 0.1, MY + 1.18, Z1), solid=False)
    m.stairs(g, "StairsEast", (13.2, 0, -1), (13.2, MY, MZ), 2.4, kind="steel", side="truss", base=0)
    m.stairs(g, "StairsWest", (-5, 0, 9.2), (MX, MY, 9.2), 2.4, kind="steel", side="truss", base=0, cheek_stop=0.14)
    # Up top: sofas, a VR booth and a row of cabinets.
    m.box(g, "Sofa", "sofa", (-17.6, MY, -4), (-16.4, MY + 0.8, 1))
    m.box(g, "Sofa", "sofa", (-6, MY, -13.6), (-1, MY + 0.8, -12.4))
    for x in (2, 3.4, 4.8, 6.2, 7.6):
        cabinet(m, g, x, -13.2, 0, "cab_blue" if x % 2 else "cab_red", MY)
    m.box(g, "VRBooth", "partition", (-17.6, MY, 5), (-14.6, MY + 2.6, 5.15))
    m.box(g, "VRMat", "neon_green", (-17.4, MY, 5.4), (-14.8, MY + 0.02, 7.6), solid=False)
    m.sign("LEVEL 2", (16, MY + 2.4, MZ - 0.15), yaw=0, size=48, col=(0.4, 1.0, 1.0, 1))


def cabinet(m, parent, x, z, yaw, kind, y=0.0):
    """An arcade cabinet facing the way `yaw` turns its front (0 = facing south, +z)."""
    g = m.group("Cabinet", parent, at=(x, y, z), yaw=yaw)
    m.box(g, "Body", kind, (-0.55, 0, -0.45), (0.55, 2.1, 0.45))
    m.box(g, "Screen", "screen" if kind != "cab_red" else "screen_pink", (-0.42, 1.2, 0.45), (0.42, 1.75, 0.5), solid=False)
    m.box(g, "Marquee", "marquee", (-0.5, 1.85, 0.45), (0.5, 2.05, 0.52), solid=False)
    m.box(g, "Panel", "cab_black", (-0.5, 0.95, 0.45), (0.5, 1.1, 0.75), solid=False)
    m.strip(g, "CoinDoor", "steel", (-0.2, 0.3, 0.45), (0.2, 0.7, 0.48))
    m.strip(g, "Stick", "prize", (-0.3, 1.1, 0.55), (-0.22, 1.25, 0.63))
    m.strip(g, "Buttons", "prize_blue", (0.05, 1.1, 0.54), (0.35, 1.13, 0.68))
    for s in (-1, 1):
        a, b = sorted((s * 0.55, s * 0.575))
        m.strip(g, "Stripe", "hockey", (a, 1.45, -0.35), (b, 1.6, 0.35))
    return g


def floor_games(m):
    f = m.folder("Games")
    # Two rows of back-to-back cabinets, with a gap in the middle for the booth.
    r = m.group("Rows", f)
    kinds = ["cab_red", "cab_blue", "cab_black", "cab_yellow"]
    i = 0
    for zc in (-4, 5):
        for (xa, xb) in ((-10, -3), (3, 8)):
            x = xa + 0.55
            while x <= xb - 0.5:
                cabinet(m, r, x, zc - 0.45, math.pi, kinds[i % 4])
                cabinet(m, r, x, zc + 0.45, 0, kinds[(i + 1) % 4])
                x += 1.15
                i += 1
            m.box(r, "RowSign", "neon_yellow" if zc < 0 else "neon_pink", (xa, 2.15, zc - 0.05), (xb - 0.5, 2.35, zc + 0.05), solid=False)
    # Change booth in the middle: climb onto its roof.
    b = m.group("ChangeBooth", f)
    m.box(b, "Booth", "counter", (-2, 0, -1.5), (2, 2.7, 1.5))
    m.box(b, "Roof", "steel", (-2.2, 2.7, -1.7), (2.2, 3.0, 1.7))
    m.box(b, "Window", "screen", (-1.4, 1.2, 1.5), (1.4, 2.2, 1.55), solid=False)
    m.box(b, "Window", "screen", (-1.4, 1.2, -1.55), (1.4, 2.2, -1.5), solid=False)
    for s in (-1, 1):
        m.on_wall(b, "Neon", "neon_green", "z", s * 2.2, s, -1.75, 1.75, 2.9, 3.04, 0.05)
        m.on_wall(b, "Neon", "neon_green", "x", s * 1.7, s, -2.2, 2.2, 2.9, 3.04, 0.05)
    m.sign("TOKENS", (0, 2.45, 1.56), size=40, col=(1, 1, 1, 1), parent=b)
    # Prize counter in the south-east corner (vault the counter to get in).
    p = m.group("PrizeCounter", f)
    m.box(p, "Front", "counter", (11, 0, 4), (11.6, 1.1, 12))
    m.box(p, "Side", "counter", (11, 0, 4), (17.2, 1.1, 4.6))
    m.box(p, "Side", "counter", (11, 0, 11.4), (17.2, 1.1, 12))
    m.box(p, "Top", "neon_pink", (10.95, 1.1, 3.95), (11.65, 1.16, 12.05), solid=False)
    m.box(p, "Shelves", "shelf", (17.2, 0, 4), (18, 3.6, 12))
    for (z, h, k) in ((5, 2.6, "prize"), (6.4, 3.0, "prize_blue"), (7.8, 2.2, "prize"), (9.2, 2.8, "prize_blue"), (10.6, 2.4, "prize")):
        m.box(p, "Prize", k, (16.8, h, z - 0.5), (17.2, h + 0.6, z + 0.5), solid=False)
    m.sign("PRIZES", (17.9, 4.3, 8), yaw=-math.pi / 2, size=72, col=(1, 0.85, 0.3, 1))
    # Stage with dance machines (south), a ramp up the front.
    s = m.group("Stage", f)
    m.box(s, "Stage", "stage", (-3, 0, 10), (5, 0.6, Z1 - 0.2))
    m.slab(s, "Ramp", "stage", (1, 0.6, 10), (1, 0, 8.2), 6, thick=0.3)
    for x in (-1, 3):
        m.box(s, "Pad", "dance_pad", (x - 0.8, 0.6, 11.4), (x + 0.8, 0.62, 13.0), solid=False)
        m.box(s, "Screen", "cab_black", (x - 0.9, 0.6, 13.2), (x + 0.9, 2.8, 13.7))
        m.box(s, "Glow", "screen_pink", (x - 0.7, 1.6, 13.15), (x + 0.7, 2.5, 13.2), solid=False)
    # Air hockey tables.
    h = m.group("AirHockey", f)
    for (x0, z0) in ((6.5, 8), (-10.5, 0)):
        m.box(h, "Table", "hockey", (x0, 0, z0), (x0 + 3, 0.9, z0 + 2))
        for (lo, hi) in (((x0 - 0.05, z0 - 0.05), (x0 + 3.05, z0 + 0.08)), ((x0 - 0.05, z0 + 1.92), (x0 + 3.05, z0 + 2.05)),
                         ((x0 - 0.05, z0 + 0.08), (x0 + 0.08, z0 + 1.92)), ((x0 + 2.92, z0 + 0.08), (x0 + 3.05, z0 + 1.92))):
            m.box(h, "Rim", "neon_cyan", (lo[0], 0.85, lo[1]), (hi[0], 0.96, hi[1]), solid=False)
        # The table itself: a centre line, a goal at each end, a puck and two mallets.
        m.strip(h, "CentreLine", "cab_red", (x0 + 1.48, 0.9, z0 + 0.08), (x0 + 1.52, 0.92, z0 + 1.92))
        for gx in (x0 + 0.08, x0 + 2.86):
            m.strip(h, "Goal", "cab_black", (gx, 0.9, z0 + 0.7), (gx + 0.06, 0.93, z0 + 1.3))
        m.pipe(h, "Puck", "cab_red", (x0 + 1.9, 0.9, z0 + 0.8), (x0 + 1.9, 0.94, z0 + 0.8), 0.16, sides=10)
        for (px, kind) in ((x0 + 0.6, "cab_blue"), (x0 + 2.45, "cab_yellow")):
            m.pipe(h, "Mallet", kind, (px, 0.9, z0 + 1.05), (px, 0.98, z0 + 1.05), 0.26, sides=10)
            m.pipe(h, "MalletKnob", kind, (px, 0.98, z0 + 1.05), (px, 1.08, z0 + 1.05), 0.1, sides=8)
    # Under the west mezzanine: pinball machines against the wall.
    pb = m.group("Pinball", f)
    for z in (-7, -5, -1, 1, 5, 7, 11):
        m.box(pb, "Pinball", "cab_blue" if z % 4 else "cab_red", (X0, 0, z - 0.4), (X0 + 1.2, 1.0, z + 0.4))
        m.box(pb, "Backbox", "cab_black", (X0, 1.0, z - 0.4), (X0 + 0.3, 2.0, z + 0.4))
        m.box(pb, "Lights", "screen", (X0 + 0.3, 1.2, z - 0.32), (X0 + 0.32, 1.9, z + 0.32), solid=False)
    # Under the north mezzanine, west of the party room: claw machines.
    c = m.group("ClawMachines", f)
    for x in (-11, -8, -5):
        m.box(c, "Base", "cab_yellow", (x - 0.7, 0, -13.4), (x + 0.7, 1.0, -12.0))
        m.box(c, "Case", "claw_glass", (x - 0.7, 1.0, -13.4), (x + 0.7, 2.4, -12.0))
        m.box(c, "Top", "neon_pink", (x - 0.72, 2.4, -13.42), (x + 0.72, 2.6, -11.98), solid=False)
    # Under the north mezzanine, east: a lounge behind a partition, with vending machines.
    m.wall(c, "LoungeWall", "partition", (12.4, MZ - 0.6), (X1, MZ - 0.6), 0, MY - 0.7, 0.25, holes=[(3.6, 5.2, 0, 2.6)])
    m.wall(c, "LoungeWall", "partition", (12.4, Z0), (12.4, MZ - 0.6), 0, MY - 0.7, 0.25)
    for x in (14, 15.4):
        m.box(c, "Vending", "cab_red" if x == 14 else "cab_blue", (x - 0.6, 0, -13.9), (x + 0.6, 2.2, -13.0))
        m.box(c, "VendingLight", "lamp", (x - 0.45, 0.9, -13.0), (x + 0.45, 2.0, -12.96), solid=False)


def party_room(m):
    """Under the north mezzanine: a party room with breakable walls."""
    g = m.group("PartyRoom")
    m.wall(g, "Front", "partition", (-2, MZ - 0.6), (11.6, MZ - 0.6), 0, MY - 0.7, 0.25, holes=[(6, 7.8, 0, 2.6), (1, 4.5, 1.1, 2.6)])
    m.wall(g, "Side", "partition", (-2, Z0), (-2, MZ - 0.6), 0, MY - 0.7, 0.25)
    m.wall(g, "Side", "partition", (11.6, Z0), (11.6, MZ - 0.6), 0, MY - 0.7, 0.25)
    m.box(g, "Table", "table", (0, 0, -12.6), (3.4, 0.8, -11.2))
    m.box(g, "Sofa", "sofa", (8, 0, -13.8), (11.2, 0.7, -12.8))
    m.box(g, "Balloons", "neon_pink", (1.2, 2.6, -12.2), (1.6, 3.2, -11.8), solid=False)
    m.sign("PARTY ROOM", (4.8, 3.3, MZ - 0.45), size=44, col=(1, 0.5, 0.85, 1))


BUILDINGS = []   # (x, width, height) of each building across the street, for the details


def street(m):
    """Outside the shop front: a pavement (only reachable once the glass breaks) and a street."""
    g = m.group("Street")
    m.box(g, "Pavement", "sidewalk", (-23, -0.5, Z1 + 0.8), (23, 0, 21))
    m.box(g, "Kerb", "kerb", (-23, 0, 20.7), (23, 0.15, 21))
    m.box(g, "Road", "street", (-80, -0.7, 21), (80, -0.15, 44))
    m.box(g, "Far", "street", (-160, -0.9, -160), (160, -0.6, 160), tint=(0.7, 0.7, 0.7))
    for x in (-23.4, 23.4):
        m.box(g, "Fence", "steel", (x - 0.1, 0, Z1 + 0.8), (x + 0.1, 1.2, 21))
    m.box(g, "Barrier", "steel", (-23, 0, 22.8), (23, 12, 23.2), drawn=False)
    for x in (-16, -6, 6, 16):
        m.box(g, "Bollard", "steel", (x - 0.2, 0, 19.8), (x + 0.2, 1.0, 20.2))
    m.box(g, "Bench", "steel", (10, 0, 17.5), (12.5, 0.5, 18.1))
    m.box(g, "Awning", "neon_pink", (X0 - 0.8, 4.4, Z1 + 0.8), (X1 + 0.8, 4.6, Z1 + 2.4))
    b = m.group("Backdrop")
    x = -60
    i = 0
    for (w, h) in ((14, 18), (10, 24), (16, 14), (12, 28), (18, 20), (11, 16), (15, 22), (12, 18), (14, 26)):
        kind = "backdrop" if i % 2 == 0 else "backdrop_dark"
        m.box(b, "Building", kind, (x, -0.15, 30), (x + w, h, 44))
        BUILDINGS.append((x, w, h))
        x += w + 1
        i += 1
    for (x0, x1) in ((-60, -20), (20, 60)):
        m.box(b, "Neighbour", "backdrop_dark", (x0 if x0 < 0 else 19.6, -0.15, -40), (-19.6 if x0 < 0 else x1, 14, Z1 + 0.8))
    m.box(b, "Behind", "backdrop_dark", (-30, -0.15, -50), (30, 16, -15.6))   # the neighbours' colour: they overlap


def roof(m):
    g = m.group("Roof")
    T, B = 9.6, 9.1
    RX0, RX1, RZ0, RZ1 = X0 - 0.8, X1 + 0.8, Z0 - 0.8, Z1 + 0.8
    # Two open skylights over the middle of the room (fly up through them).
    m.box(g, "Roof", "roof", (RX0, B, RZ0), (RX1, T, -6))
    m.box(g, "Roof", "roof", (RX0, B, -3), (RX1, T, 3))
    m.box(g, "Roof", "roof", (RX0, B, 6), (RX1, T, RZ1))
    for (z0, z1) in ((-6, -3), (3, 6)):
        m.box(g, "Roof", "roof", (RX0, B, z0), (-8, T, z1))
        m.box(g, "Roof", "roof", (8, B, z0), (RX1, T, z1))
        for (a, b) in (((-8, z0), (8, z0)), ((-8, z1), (8, z1))):
            m.box(g, "Curb", "parapet", (a[0], T, a[1] - 0.1), (b[0], T + 0.4, b[1] + 0.1))
    m.box(g, "Parapet", "parapet", (RX0, T, RZ0), (RX1, T + 1.0, RZ0 + 0.3))
    m.box(g, "Parapet", "parapet", (RX0, T, RZ1 - 0.3), (RX1, T + 1.0, RZ1))
    m.box(g, "Parapet", "parapet", (RX0, T, RZ0), (RX0 + 0.3, T + 1.0, RZ1))
    m.box(g, "Parapet", "parapet", (RX1 - 0.3, T, RZ0), (RX1, T + 1.0, RZ1))
    for (x, z) in ((-14, -11), (-9, -11), (13, -10), (-14, 10)):
        m.box(g, "ACUnit", "ac_unit", (x - 1.2, T, z - 1), (x + 1.2, T + 1.6, z + 1))
    m.box(g, "Vent", "steel", (14, T, 8), (15, T + 2.4, 9))
    # The big sign along the front edge of the roof.
    m.box(g, "SignFrame", "truss", (-10, T + 1.0, RZ1 - 0.6), (10, T + 1.2, RZ1 - 0.4))
    m.box(g, "SignBoard", "cab_black", (-10, T + 1.2, RZ1 - 0.6), (10, T + 4.4, RZ1 - 0.4))
    m.box(g, "SignNeon", "neon_cyan", (-10.1, T + 4.4, RZ1 - 0.65), (10.1, T + 4.55, RZ1 - 0.35), solid=False)
    m.sign("NEON ARCADE", (0, T + 2.8, RZ1 - 0.34), size=220, col=(1.0, 0.4, 0.85, 1), pixel=0.012)



# ---------------------------------------------------------------------------
# Details. Everything below is drawn only, never solid, so nothing here changes where you
# can stand, what stops a shot or how a bot finds its way. Pieces on a wall stand at most
# 0.3 m off it; what stands further out is small, overhead or beyond the street barrier.
# On glass, a partition, the mezzanine floor or the roof (they break), a piece is either a
# thin "skin" lying flat on one panel (it then breaks with it) or keeps clear of it, so it
# never holds it up (see MapDestruction).

def details(m):
    room_details(m)
    games_details(m)
    mezzanine_details(m)
    front_details(m)
    street_details(m)
    roof_details(m)


def collar(m, g, name, kind, lo, hi, out=0.03):
    """A band right round a post from corner `lo` to `hi`: a box `out` bigger on every side."""
    m.strip(g, name, kind, (lo[0] - out, lo[1], lo[2] - out), (hi[0] + out, hi[1], hi[2] + out))


def poster(m, g, axis, face, out, u, y, w, h, kind, neon):
    """A framed poster on a wall: a dark board, a block of colour and a pale square on it,
    a neon frame. Each layer stands a little further out than the one under it."""
    m.on_wall(g, "Poster", "cab_black", axis, face, out, u - w / 2, u + w / 2, y, y + h, 0.04)
    m.on_wall(g, "PosterArt", kind, axis, face, out, u - w / 2 + 0.25, u + w / 2 - 0.25, y + 0.25, y + h - 0.25, 0.02, lift=0.04)
    m.on_wall(g, "PosterStar", "hockey", axis, face, out, u - 0.22, u + 0.22, y + h / 2 - 0.22, y + h / 2 + 0.22, 0.02, lift=0.06)
    for (a, b, c, d) in ((u - w / 2, u + w / 2, y, y + 0.07), (u - w / 2, u + w / 2, y + h - 0.07, y + h),
                         (u - w / 2, u - w / 2 + 0.07, y + 0.07, y + h - 0.07), (u + w / 2 - 0.07, u + w / 2, y + 0.07, y + h - 0.07)):
        m.on_wall(g, "PosterNeon", neon, axis, face, out, a, b, c, d, 0.03, lift=0.04)


def room_details(m):
    g = m.group("Details", "Shell")
    # Panels on the east wall like the west wall's, and posters high on every wall.
    for z in (-7, -3, 1):
        m.on_wall(g, "Panel", "wall_panel", "z", X1, -1, z - 1.6, z + 1.6, 0.4, 3.6, 0.05)
    art = (("cab_red", "neon_cyan"), ("cab_yellow", "neon_pink"), ("cab_blue", "neon_yellow"), ("sofa", "neon_pink"),
           ("counter", "neon_cyan"), ("prize", "neon_green"))
    for k, (z, y) in enumerate(((-6, 5.0), (0, 5.0), (8, 5.4))):
        poster(m, g, "z", X1, -1, z, y, 2.6, 2.0, *art[k])
    for k, z in enumerate((-6.5, 3, 10.5)):
        poster(m, g, "z", X0, 1, z, 5.9, 2.4, 1.9, *art[k + 3])
    for k, x in enumerate((-12, -8.5, 12)):
        poster(m, g, "x", Z0, 1, x, 6.0, 2.2, 1.8, *art[(k * 2 + 1) % 6])
    for k, x in enumerate((-10, 10)):
        poster(m, g, "x", Z1, -1, x, 5.0, 2.6, 2.0, *art[k * 3])
    # The high-score board over the doors.
    m.on_wall(g, "ScoreBoard", "cab_black", "x", Z1, -1, -3.4, 3.4, 4.7, 7.7, 0.05)
    m.sign("HIGH SCORES", (0, 7.2, Z1 - 0.07), yaw=math.pi, size=52, col=(1, 0.86, 0.3, 1), one_sided=True)
    for k in range(5):
        y = 6.45 - k * 0.36
        m.on_wall(g, "ScoreName", ("screen", "screen_pink")[k % 2], "x", Z1, -1, 0.4, 2.7 - 0.3 * (k % 3), y, y + 0.14, 0.02, lift=0.05)
        m.on_wall(g, "ScoreNumber", "marquee", "x", Z1, -1, -2.8, -0.8 + 0.25 * (k % 2), y, y + 0.14, 0.02, lift=0.05)
    # Air ducts under the roof (clear of it: the roof breaks), with vents.
    for z in (-11.2, 11.2):
        m.strip(g, "Duct", "ac_unit", (X0 + 0.3, 8.5, z - 0.35), (X1 - 0.3, 8.95, z + 0.35))
        for x in range(-15, 16, 6):
            m.strip(g, "DuctVent", "cab_black", (x - 0.4, 8.46, z - 0.2), (x + 0.4, 8.5, z + 0.2))
    # Spotlights under the trusses, a mirror ball over the stage, neon rings on the columns.
    t = m.group("Lights", "Trusses")
    for (x, z, kind) in ((0, 9, "neon_pink"), (6, 9, "neon_cyan"), (-6, 8, "neon_yellow"), (-12, -7.5, "neon_cyan"),
                         (12, -7.5, "neon_pink"), (6, -8, "neon_yellow"), (-6, -8, "neon_green"), (12, 8.5, "neon_green")):
        m.strip(t, "SpotCan", "cab_black", (x - 0.14, 7.08, z - 0.14), (x + 0.14, 7.4, z + 0.14))
        m.strip(t, "SpotLens", kind, (x - 0.1, 7.04, z - 0.1), (x + 0.1, 7.08, z + 0.1))
    m.pipe(t, "MirrorBallRod", "steel", (0, 7.0, 11.4), (0, 7.4, 11.4), 0.05)
    m.cyl(t, "MirrorBall", "hockey", (0, 6.3, 11.4), 0.8, 0.7, sides=10, solid=False)
    m.cyl(t, "MirrorBallBand", "screen", (0, 6.55, 11.4), 0.86, 0.2, sides=10, solid=False)
    collar(m, g, "ColumnRing", "neon_cyan", (-7.2, 2.2, MZ - 0.4), (-6.8, 2.3, MZ))
    for z in (-3, 3):
        collar(m, g, "ColumnRing", "neon_pink", (MX, 2.2, z - 0.2), (MX + 0.4, 2.3, z + 0.2))


def games_details(m):
    # Change booth: a ledge under each window, a coin on each end.
    b = m.group("Details", "Games/ChangeBooth")
    for sz in (-1, 1):
        m.on_wall(b, "Ledge", "steel", "x", sz * 1.5, sz, -1.5, 1.5, 1.08, 1.16, 0.22)
    for sx in (-1, 1):
        m.pipe(b, "Coin", "cab_yellow", (sx * 2, 1.5, 0), (sx * 2.04, 1.5, 0), 1.1, sides=16)
        m.pipe(b, "CoinInner", "prize", (sx * 2.04, 1.5, 0), (sx * 2.07, 1.5, 0), 0.7, sides=16)
    # Prize counter: a board under every prize, and a low shelf of toys.
    p = m.group("Details", "Games/PrizeCounter")
    for (z, h) in ((5, 2.6), (6.4, 3.0), (7.8, 2.2), (9.2, 2.8), (10.6, 2.4)):
        m.on_wall(p, "ShelfBoard", "counter", "z", 17.2, -1, z - 0.6, z + 0.6, h - 0.06, h, 0.45)
    m.on_wall(p, "ShelfBoard", "counter", "z", 17.2, -1, 4.1, 11.9, 1.3, 1.36, 0.3)
    kinds = ("prize", "prize_blue", "cab_yellow", "sofa", "cab_red", "hockey")
    for k in range(9):
        z = 4.6 + k * 0.84
        s_ = 0.15 + 0.05 * (k % 3)
        m.on_wall(p, "Toy", kinds[(k * 5) % 6], "z", 17.2, -1, z - s_, z + s_, 1.36, 1.36 + s_ * 2.2, 0.25)
    # Stage: lit edges, arrows on the dance pads, speakers under the screens.
    s = m.group("Details", "Games/Stage")
    for (face, out) in ((-3, -1), (5, 1)):
        m.on_wall(s, "EdgeLight", "neon_pink", "z", face, out, 10, 13.8, 0.46, 0.54, 0.03)
    for x in (-1, 3):
        for (dx, dz, kind) in ((0, 0.5, "neon_cyan"), (0, -0.5, "neon_cyan"), (-0.5, 0, "neon_yellow"), (0.5, 0, "neon_yellow")):
            m.strip(s, "Arrow", kind, (x + dx - 0.18, 0.62, 12.2 + dz - 0.18), (x + dx + 0.18, 0.64, 12.2 + dz + 0.18))
        m.on_wall(s, "Speaker", "truss", "x", 13.2, -1, x - 0.7, x + 0.7, 0.75, 1.4, 0.04)
    # Pinball tables: bumpers and flippers on top.
    pb = m.group("Details", "Games/Pinball")
    for z in (-7, -5, -1, 1, 5, 7, 11):
        for (dx, dz, kind) in ((0.55, -0.15, "screen_pink"), (0.75, 0.12, "neon_yellow"), (0.9, -0.08, "screen")):
            m.pipe(pb, "Bumper", kind, (X0 + dx, 1.0, z + dz), (X0 + dx, 1.05, z + dz), 0.12, sides=8)
        for dz in (-0.18, 0.08):
            m.strip(pb, "Flipper", "hockey", (X0 + 1.04, 1.0, z + dz), (X0 + 1.1, 1.03, z + dz + 0.1))
    # Claw machines: controls, a chute, and the claw and prizes showing in the case.
    c = m.group("Details", "Games/ClawMachines")
    for x in (-11, -8, -5):
        m.on_wall(c, "Controls", "cab_black", "x", -12.0, 1, x - 0.5, x + 0.5, 0.78, 0.96, 0.18)
        m.strip(c, "Knob", "cab_red", (x - 0.25, 0.96, -11.93), (x - 0.17, 1.08, -11.85))
        m.on_wall(c, "Chute", "cab_black", "x", -12.0, 1, x + 0.15, x + 0.55, 0.15, 0.5, 0.03)
        for k, kind in enumerate(("prize", "prize_blue", "counter", "cab_yellow")):
            a = x - 0.6 + k * 0.31
            m.on_wall(c, "CasePrize", kind, "x", -12.0, 1, a, a + 0.26, 1.05, 1.3 + 0.08 * ((k + x) % 3), 0.02)
        m.on_wall(c, "Claw", "steel", "x", -12.0, 1, x - 0.04, x + 0.04, 1.95, 2.4, 0.02)
        m.on_wall(c, "Claw", "steel", "x", -12.0, 1, x - 0.2, x + 0.2, 1.85, 1.95, 0.02)
    for x in (14, 15.4):   # the vending machines in the lounge
        m.on_wall(c, "Slot", "cab_black", "x", -13.0, 1, x - 0.4, x + 0.4, 0.25, 0.6, 0.03)
        m.on_wall(c, "CoinPanel", "steel", "x", -13.0, 1, x + 0.48, x + 0.58, 1.0, 1.5, 0.03)
    # Party room: bunting along the back wall, a cake and plates on the table, balloons.
    r = m.group("Details", "PartyRoom")
    kinds = ("prize", "prize_blue", "counter", "sofa", "cab_yellow")
    x, k = -1.6, 0
    while x < 11.2:
        m.on_wall(r, "Bunting", kinds[k % 5], "x", Z0, 1, x, x + 0.3, 3.0 + 0.1 * (k % 2), 3.4, 0.03)
        x += 0.55
        k += 1
    m.on_wall(r, "BuntingLine", "table", "x", Z0, 1, -1.8, 11.4, 3.4, 3.43, 0.02)
    m.pipe(r, "Cake", "counter", (2.4, 0.8, -11.9), (2.4, 1.0, -11.9), 0.5, sides=12)
    m.pipe(r, "CakeTop", "hockey", (2.4, 1.0, -11.9), (2.4, 1.05, -11.9), 0.42, sides=12)
    for dx in (-0.1, 0.0, 0.1):
        m.strip(r, "Candle", "neon_yellow", (2.385 + dx, 1.05, -11.915), (2.415 + dx, 1.17, -11.885))
    for (px, pz) in ((0.6, -12.2), (1.3, -11.6), (3.0, -12.3)):
        m.pipe(r, "Plate", "hockey", (px, 0.8, pz), (px, 0.83, pz), 0.26, sides=10)
        m.pipe(r, "Cup", "prize_blue", (px + 0.22, 0.8, pz + 0.1), (px + 0.22, 0.92, pz + 0.1), 0.08)
    m.strip(r, "BalloonString", "table", (1.39, 0.8, -12.01), (1.41, 2.6, -11.99))
    for (bx, bz, by, base, kind) in ((0.5, -12.4, 2.3, 0.8, "prize_blue"), (2.9, -11.5, 2.5, 0.8, "cab_yellow"),
                                     (9.5, -13.3, 2.4, 0.7, "sofa"), (10.4, -13.4, 2.8, 0.7, "prize")):
        m.strip(r, "Balloon", kind, (bx - 0.2, by, bz - 0.2), (bx + 0.2, by + 0.5, bz + 0.2))
        m.strip(r, "BalloonString", "table", (bx - 0.01, base, bz - 0.01), (bx + 0.01, by, bz + 0.01))
    m.strip(r, "SofaBack", "sofa", (8, 0.7, -13.8), (11.2, 1.25, -13.5), tint=(0.8, 0.8, 0.8))


def mezzanine_details(m):
    g = m.group("Details", "Mezzanine")
    # Lights under the mezzanine: thin and flat against its underside, so they break with it.
    for x in range(-15, 17, 4):
        m.strip(g, "UnderLight", "lamp", (x - 0.6, MY - 0.36, -11.7), (x + 0.6, MY - 0.3, -11.3))
    for z in range(-6, 13, 4):
        m.strip(g, "UnderLight", "lamp", (-15.8, MY - 0.36, z - 0.6), (-15.4, MY - 0.3, z + 0.6))
    # Backs and arms on the sofas, a screen on the VR booth's wall (a skin: it breaks with it).
    DARK = (0.8, 0.8, 0.8)
    m.strip(g, "SofaBack", "sofa", (-17.6, MY + 0.8, -4), (-17.25, MY + 1.35, 1), tint=DARK)
    for (a, b) in ((-4, -3.75), (0.75, 1)):
        m.strip(g, "SofaArm", "sofa", (-17.25, MY + 0.8, a), (-16.4, MY + 1.05, b), tint=DARK)
    m.strip(g, "SofaBack", "sofa", (-6, MY + 0.8, -13.6), (-1, MY + 1.35, -13.25), tint=DARK)
    for (a, b) in ((-6, -5.75), (-1.25, -1)):
        m.strip(g, "SofaArm", "sofa", (a, MY + 0.8, -13.25), (b, MY + 1.05, -12.4), tint=DARK)
    m.on_wall(g, "VRScreen", "screen", "x", 5.15, 1, -17.2, -15.0, MY + 1.0, MY + 2.0, 0.03)


def front_details(m):
    f = m.group("FrontDetails", "Shell")
    ZG = Z1 + 0.4    # the middle of the glass
    # Bars on the shop windows (thin, on the glass: they break with it); a stile, handles and
    # a top rail on the doors.
    for x0 in (-14, -9, 4, 9):
        for out in (-1, 1):
            for dx in (1.67, 3.33):
                m.on_wall(f, "Mullion", "steel", "x", ZG + out * 0.06, out, x0 + dx - 0.04, x0 + dx + 0.04, 0.8, 4.0, 0.03)
    for out in (-1, 1):
        m.on_wall(f, "DoorStile", "steel", "x", ZG + out * 0.06, out, -0.04, 0.04, 0, 2.85, 0.03)
        m.on_wall(f, "DoorRail", "steel", "x", ZG + out * 0.06, out, -1.5, 1.5, 2.85, 3.0, 0.03)
        for sx in (-1, 1):
            a, b = sorted((sx * 0.14, sx * 0.22))
            m.on_wall(f, "DoorHandle", "steel", "x", ZG + out * 0.06, out, a, b, 1.0, 1.5, 0.08)
    # An OPEN sign hung in one window, inside the glass.
    m.strip(f, "OpenBoard", "cab_black", (-7.6, 2.7, Z1 + 0.1), (-5.4, 3.5, Z1 + 0.16))
    m.strip(f, "OpenBoardEdge", "neon_green", (-7.66, 2.64, Z1 + 0.115), (-5.34, 3.56, Z1 + 0.145))
    for x in (-7.4, -5.6):
        m.strip(f, "OpenBoardString", "steel", (x - 0.01, 3.56, Z1 + 0.12), (x + 0.01, 4.0, Z1 + 0.14))
    m.sign("OPEN", (-6.5, 3.1, Z1 + 0.18), yaw=0, size=60, col=(0.5, 1.0, 0.6, 1), one_sided=True)
    m.sign("OPEN", (-6.5, 3.1, Z1 + 0.08), yaw=math.pi, size=60, col=(0.5, 1.0, 0.6, 1), one_sided=True)


def car(m, g, x, z, kind):
    """A parked car, its nose toward +x. The road is at -0.15."""
    m.strip(g, "CarBody", kind, (x - 2.1, 0.15, z - 0.9), (x + 2.1, 0.85, z + 0.9))
    m.strip(g, "CarCabin", "door", (x - 1.2, 0.85, z - 0.8), (x + 1.0, 1.4, z + 0.8))
    m.strip(g, "CarRoof", kind, (x - 1.25, 1.4, z - 0.84), (x + 1.05, 1.48, z + 0.84))
    for wx in (-1.3, 1.3):
        m.pipe(g, "Wheel", "tyre", (x + wx, 0.2, z - 0.94), (x + wx, 0.2, z + 0.94), 0.7, sides=10)
    for dz in (-0.7, 0.45):
        m.strip(g, "Headlamp", "lamp", (x + 2.1, 0.5, z + dz), (x + 2.13, 0.68, z + dz + 0.25))
        m.strip(g, "TailLamp", "beacon", (x - 2.13, 0.5, z + dz), (x - 2.1, 0.68, z + dz + 0.25))


def street_details(m):
    g = m.group("Details", "Street")
    # The road: a centre line, a crossing at the doors; a far pavement with lamps and parked cars.
    x = -78.0
    while x < 76:
        m.strip(g, "CentreLine", "kerb", (x, -0.15, 24.4), (x + 3, -0.13, 24.6))
        x += 7
    for k in range(5):
        m.strip(g, "Crossing", "kerb", (-2.5 + k * 1.1, -0.15, 21.3), (-1.9 + k * 1.1, -0.13, 23.9))
    m.strip(g, "FarPavement", "sidewalk", (-80, -0.15, 28.4), (80, 0.0, 30))
    m.strip(g, "FarKerb", "kerb", (-80, -0.15, 28.2), (80, 0.03, 28.4))
    for x in (-48, -32, -16, 0, 16, 32, 48):
        m.pipe(g, "StreetLampPost", "steel", (x, 0, 28.9), (x, 6.5, 28.9), 0.18)
        m.strip(g, "StreetLampArm", "steel", (x - 0.05, 6.4, 27.6), (x + 0.05, 6.5, 28.9))
        m.strip(g, "StreetLamp", "lamp", (x - 0.25, 6.2, 27.4), (x + 0.25, 6.4, 27.9))
    for (x, kind) in ((-30, "cab_red"), (-9, "cab_blue"), (14, "cab_yellow"), (38, "hockey")):
        car(m, g, x, 27.1, kind)
    m.pipe(g, "Manhole", "steel", (-11, 0, 17.5), (-11, 0.02, 17.5), 0.9, sides=12)
    # The shops next door: shutters down, a sign and an awning over each.
    for sx in (-1, 1):
        for k, (a, b, kind, neon) in enumerate(((20.3, 22.9, "cab_blue", "neon_cyan"), (24.6, 29.4, "cab_yellow", "neon_pink"),
                                                (31.0, 36.0, "cab_red", "neon_yellow"))):
            u0, u1 = sorted((sx * a, sx * b))
            m.on_wall(g, "Shutter", "shutter", "x", Z1 + 0.8, 1, u0, u1, 0, 2.8, 0.05)
            m.on_wall(g, "ShopSign", "cab_black", "x", Z1 + 0.8, 1, u0 - 0.2, u1 + 0.2, 3.0, 3.7, 0.12)
            m.on_wall(g, "ShopNeon", neon, "x", Z1 + 0.8, 1, u0 + 0.2, u1 - 0.2, 3.28, 3.42, 0.03, lift=0.12)
            m.strip(g, "ShopAwning", kind, (u0 - 0.2, 3.8, Z1 + 0.8), (u1 + 0.2, 3.95, Z1 + 1.9))
    # Across the street: neon signs on three buildings, tanks, stair heads and masts on the roofs.
    b = m.group("Details", "Backdrop")
    for i, (x, w, h) in enumerate(BUILDINGS):
        name = {1: ("HOTEL", "neon_cyan", (0.4, 1.0, 1.0, 1)), 4: ("BOWLING", "neon_pink", (1.0, 0.45, 0.85, 1)),
                6: ("DINER", "neon_yellow", (1.0, 0.9, 0.35, 1))}.get(i)
        if name:
            wide = min(w - 2, 12)
            a, c = x + w / 2 - wide / 2, x + w / 2 + wide / 2
            m.on_wall(b, "Billboard", "cab_black", "x", 30, -1, a, c, h - 5.4, h - 2.2, 0.15)
            m.on_wall(b, "BillboardNeon", name[1], "x", 30, -1, a, c, h - 5.6, h - 5.4, 0.2)
            m.on_wall(b, "BillboardNeon", name[1], "x", 30, -1, a, c, h - 2.2, h - 2.0, 0.2)
            m.sign(name[0], (x + w / 2, h - 3.8, 29.82), yaw=math.pi, size=int(wide * 0.8 / len(name[0]) / 0.61 / 0.012),
                   col=name[2], pixel=0.012, one_sided=True)
        if i % 3 == 0:
            m.cyl(b, "RoofTank", "ac_unit", (x + w / 2, h, 34), 3.2, 3.4, sides=10, solid=False)
            m.cyl(b, "RoofTankCap", "truss", (x + w / 2, h + 3.4, 34), 3.6, 0.3, sides=10, solid=False)
        elif i % 3 == 1:
            m.strip(b, "StairHead", "backdrop" if i % 2 else "backdrop_dark", (x + 2, h, 32), (x + 5.5, h + 3, 36), tint=(0.8, 0.8, 0.85))
        if h >= 24:
            m.pipe(b, "Mast", "steel", (x + w - 2.5, h, 33), (x + w - 2.5, h + 7, 33), 0.2)
            m.strip(b, "Beacon", "beacon", (x + w - 2.7, h + 7, 32.8), (x + w - 2.3, h + 7.4, 33.2))
    for (x, z, top) in ((30, -5, 14), (-32, 6, 14), (12, -26, 16)):
        m.cyl(b, "RoofTank", "ac_unit", (x, top, z), 4, 4, sides=10, solid=False)
        m.cyl(b, "RoofTankCap", "truss", (x, top + 4, z), 4.4, 0.3, sides=10, solid=False)
    m.pipe(b, "Mast", "steel", (-8, 16, -24), (-8, 24, -24), 0.2)
    m.strip(b, "Beacon", "beacon", (-8.2, 24, -24.2), (-7.8, 24.4, -23.8))


def roof_details(m):
    g = m.group("Details", "Roof")
    T, RZ1 = 9.6, Z1 + 0.8
    # A fan on each air-conditioning unit and a grille on its side, a cap on the vent.
    for (x, z) in ((-14, -11), (-9, -11), (13, -10), (-14, 10)):
        m.pipe(g, "Fan", "cab_black", (x, T + 1.6, z), (x, T + 1.64, z), 1.5, sides=12)
        m.pipe(g, "FanHub", "steel", (x, T + 1.64, z), (x, T + 1.7, z), 0.4, sides=8)
        m.on_wall(g, "Grille", "truss", "x", z + 1, 1, x - 0.9, x + 0.9, T + 0.3, T + 1.2, 0.04)
    m.strip(g, "VentCap", "steel", (13.85, T + 2.4, 7.85), (15.15, T + 2.55, 9.15))
    # Neon down the sides and along the bottom of the big sign.
    m.on_wall(g, "SignNeon", "neon_pink", "x", RZ1 - 0.4, 1, -10, 10, T + 1.2, T + 1.32, 0.03)
    for (a, c) in ((-10, -9.88), (9.88, 10)):
        m.on_wall(g, "SignNeon", "neon_pink", "x", RZ1 - 0.4, 1, a, c, T + 1.32, T + 4.4, 0.03)


def spawns(m):
    pts = [
        ((-8, 0, -7), (0, 0)), ((7, 0, -7), (0, 0)), ((-11.5, 0, 2.5), (0, 0)), ((0, 0, 7.4), (0, 0)),
        ((14.5, 0, 1.2), (0, 0)), ((-15.5, 0, -12), (0, 0)), ((8, 0, -11.5), (0, 0)),
        ((-15.5, MY, 0), (0, 0)), ((10, MY, -11.5), (0, 0)), ((-8, MY, -11.5), (0, 0)),
        ((16.5, 0, -6), (0, 0)), ((-15.6, 0, 6), (0, 0)),
    ]
    for p, t in pts:
        m.spawn(p, t)


def pickups(m):
    for (p, w) in [
        ((0, 3.0, 0), "shotgun"), ((0, 9.6, 10), "bolt_action"), ((-16, MY, 12), "rifle"), ((0, MY, -11.2), "rifle"),
        ((2, 0, -10.6), "revolver"), ((1, 0.6, 11.0), "hammer"), ((15, 0, 8), "brass_knuckles"), ((8, 0, 18), "burst_rifle"),
        ((-14.5, 0, -3), "machine_pistol"), ((9, 0, -6.6), "spear"), ((-15, 0, -8), "akimbo"),
    ]:
        m.weapon(p, w)
