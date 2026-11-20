"""Lost Temple: a large outdoor arena (up to 16 players) in a jungle clearing ringed by
cliffs. A stepped pyramid in the middle (grand stairs north and south, a crypt tunnel
through its base, a shrine on top), a ruined palace with a breakable plank upper floor
(north-west), an aqueduct and a broken tower (north-east), treehouses joined by rope
bridges (south-west), a ruined courtyard with a hut (south-east), an excavation
scaffold (west) and a stone gate (east).

Heights: ground 0 m, pyramid tiers 3, 6 and 9 m (shrine roof 14.3 m), palace upper
floor 4.3 m, aqueduct 7 m, broken tower 14 m, treehouses 6 m, scaffold 4.5 and 9 m.
"""
import math
from arena_builder import Map, palette

PAL = "res://game/maps/palettes/lost_temple.tres"

COLORS = {
    "grass": (0.36, 0.52, 0.24), "grass_dark": (0.28, 0.43, 0.2), "dirt": (0.5, 0.4, 0.28),
    "paving": (0.66, 0.62, 0.52), "temple": (0.7, 0.64, 0.5), "temple_dark": (0.55, 0.5, 0.4),
    "temple_light": (0.8, 0.75, 0.62), "carving": (0.62, 0.52, 0.36), "gold": (0.95, 0.74, 0.25),
    "stone": (0.6, 0.58, 0.54), "stone_dark": (0.45, 0.44, 0.42), "moss": (0.3, 0.5, 0.22),
    "rock": (0.5, 0.47, 0.43), "rock_dark": (0.38, 0.36, 0.34), "plank": (0.6, 0.44, 0.27),
    "wood_wall": (0.52, 0.38, 0.24), "timber": (0.4, 0.29, 0.19), "rope": (0.72, 0.62, 0.42),
    "thatch": (0.78, 0.66, 0.38), "trunk": (0.42, 0.32, 0.22), "leaves": (0.24, 0.5, 0.22),
    "leaves_light": (0.36, 0.6, 0.26), "leaves_dark": (0.17, 0.38, 0.17), "vine": (0.2, 0.44, 0.18),
    "water": (0.25, 0.52, 0.6), "torch": (1.0, 0.62, 0.22), "crystal": (0.35, 0.9, 0.85),
    "cloth_red": (0.7, 0.18, 0.14), "cloth_blue": (0.18, 0.32, 0.6), "pot": (0.68, 0.4, 0.26),
    "flower": (0.96, 0.92, 0.8), "flower_pink": (0.92, 0.45, 0.62), "foam": (0.88, 0.95, 0.95),
}
# The pattern each colour is drawn with (MapScenery.SURFACES).
SURFACE = {
    "grass": "grass", "grass_dark": "grass", "moss": "grass", "dirt": "dirt", "paving": "blocks_small",
    "temple": "blocks", "temple_dark": "blocks", "temple_light": "blocks", "stone": "blocks_small",
    "stone_dark": "blocks_small", "rock": "strata", "rock_dark": "strata", "plank": "planks",
    "wood_wall": "planks_upright", "thatch": "thatch", "trunk": "bark", "leaves": "clumps",
    "leaves_light": "clumps", "leaves_dark": "clumps", "water": "water",
}
GLOW = {"torch": 2.0, "crystal": 1.6, "gold": 0.3}
BREAKABLE = {"plank": 200, "wood_wall": 120, "thatch": 80, "cloth_red": 40}


def build(path):
    m = Map("LostTemple", PAL,
            {"sky": {"sky_top_color": (0.26, 0.52, 0.8), "sky_horizon_color": (0.8, 0.88, 0.86),
                     "ground_bottom_color": (0.3, 0.38, 0.24), "ground_horizon_color": (0.7, 0.78, 0.68)},
             "lines": ["ambient_light_source = 2", "ambient_light_color = Color(0.74, 0.84, 0.8, 1)",
                       "ambient_light_energy = 0.65", "tonemap_mode = 2", "tonemap_white = 2.6",
                       "ssao_enabled = true", "glow_enabled = true"]},
            (55, 140, (1.0, 0.92, 0.78), 1.1),
            {"face_shade": "Vector3(0.93, 0.84, 0.66)", "kill_height": "-8.0",
             "bounds": "Rect2(-50, -50, 100, 100)", "swing_point": "Vector3(0, 14.3, 0)"})
    ground(m)
    pyramid(m)
    palace(m)
    aqueduct(m)
    treehouses(m)
    courtyard(m)
    middle(m)
    cliffs(m)
    details(m)
    spawns(m)
    pickups(m)
    m.write(path)
    palette(path.replace("game/maps/", "game/maps/palettes/").replace(".tscn", ".tres"), COLORS, GLOW, BREAKABLE, surface=SURFACE)


def ground(m):
    g = m.group("Ground")
    m.box(g, "Grass", "grass", (-62, -1, -62), (62, 0, 62))
    m.box(g, "Far", "grass_dark", (-220, -1.2, -220), (220, -0.2, 220))
    m.box(g, "Plaza", "paving", (-22, 0, -22), (22, 0.03, 22), solid=False)
    for (x0, z0, x1, z1) in ((-2.5, -40, 2.5, -22), (-2.5, 22, 2.5, 46), (-46, -2, -22, 2), (22, -2, 46, 2)):
        m.box(g, "Path", "dirt", (x0, 0, z0), (x1, 0.025, z1), solid=False)


def vine(m, g, axis, face, out, u, top, h, wide=1.2, over=0.5):
    """A curtain of vine hanging `h` down a wall from its top edge at height `top`, with
    thinner strands either side and a few pale leaves. It stands further out than any
    trim or band on the wall, and laps `over` the top (0: it only hangs from the edge)."""
    m.on_wall(g, "Vine", "vine", axis, face, out, u - wide / 2, u + wide / 2, top - h, top + 0.03, 0.16)
    if over:
        m.on_wall(g, "Vine", "vine", axis, face, -out, u - wide / 2 + 0.1, u + wide / 2 - 0.1, top, top + 0.03, over)
    m.on_wall(g, "Vine", "vine", axis, face, out, u - wide / 2 - 0.34, u - wide / 2 - 0.16, top - h * 0.62, top + 0.03, 0.13)
    m.on_wall(g, "Vine", "vine", axis, face, out, u + wide / 2 + 0.12, u + wide / 2 + 0.27, top - h * 0.45, top + 0.03, 0.19)
    for k, (du, dy) in enumerate(((-0.3, 0.3), (0.25, 0.55), (-0.1, 0.8), (0.4, 0.12))):
        y = top - h * dy
        m.on_wall(g, "VineLeaf", "leaves_light", axis, face, out, u + du * wide - 0.11, u + du * wide + 0.11, y - 0.09, y + 0.09, 0.07, lift=0.16)


def pyramid(m):
    f = m.folder("Pyramid")
    g = m.group("Tiers", f)
    # Tier 1 (0-3 m) is built round a crypt: a tunnel east-west and a chamber in the middle.
    m.box(g, "Tier1North", "temple", (-15, 0, -15), (15, 3, -4))
    m.box(g, "Tier1South", "temple", (-15, 0, 4), (15, 3, 15))
    for sz in ((-4, -1.5), (1.5, 4)):
        m.box(g, "Tier1Side", "temple", (-15, 0, sz[0]), (-4, 3, sz[1]))
        m.box(g, "Tier1Side", "temple", (4, 0, sz[0]), (15, 3, sz[1]))
    # The crypt's ceiling is the tier's own stone on top (one colour to walk on), lined dark below.
    for (x0, z0, x1, z1) in ((-15, -1.5, -4, 1.5), (4, -1.5, 15, 1.5), (-4, -4, 4, 4)):
        m.box(g, "CryptCeiling", "temple", (x0, 2.8, z0), (x1, 3, z1))
        m.strip(g, "CryptLining", "temple_dark", (max(x0, -14.95), 2.76, z0), (min(x1, 14.95), 2.8, z1))
    m.box(g, "Tier2", "temple", (-10.5, 3, -10.5), (10.5, 6, 10.5))
    m.box(g, "Tier3", "temple", (-6, 6, -6), (6, 9, 6))
    # A pale rim round the top of each tier (round it, not across it: the top is one colour).
    for (half, y) in ((15, 3), (10.5, 6), (6, 9)):
        for s in (-1, 1):
            m.on_wall(g, "Trim", "temple_light", "x", s * half, s, -half - 0.1, half + 0.1, y - 0.35, y, 0.1)
            m.on_wall(g, "Trim", "temple_light", "z", s * half, s, -half, half, y - 0.35, y, 0.1)
    # Carved bands on the faces (broken where the crypt tunnel opens), and vines over the edges.
    for (half, y0) in ((15, 1.0), (10.5, 4.0), (6, 7.0)):
        for s in (-1, 1):
            m.on_wall(g, "Band", "carving", "x", s * half, s, -half - 0.05, half + 0.05, y0, y0 + 0.6, 0.05)
            for (a, b) in ((-half, -1.5), (1.5, half)) if half == 15 else ((-half, half),):
                m.on_wall(g, "Band", "carving", "z", s * half, s, a, b, y0, y0 + 0.6, 0.05)
    for (axis, out, u, half, top, h) in (("x", -1, -12, 15, 3, 2.6), ("x", -1, 9, 15, 3, 2.2), ("z", 1, 8, 15, 3, 2.8),
                                         ("z", -1, -9, 15, 3, 2.4), ("x", 1, -7, 10.5, 6, 2.8), ("z", 1, -4, 10.5, 6, 2.5)):
        vine(m, g, axis, out * half, out, u, top, h)
    # Crypt: torches and a crystal on a plinth.
    c = m.group("Crypt", f)
    m.box(c, "Plinth", "temple_dark", (-0.8, 0, -0.8), (0.8, 0.9, 0.8))
    m.box(c, "Crystal", "crystal", (-0.3, 0.9, -0.3), (0.3, 1.9, 0.3), solid=False)
    for (x, z) in ((-3.9, -3), (3.9, -3), (-3.9, 3), (3.9, 3)):
        m.box(c, "Torch", "torch", (x - 0.1, 1.6, z - 0.15), (x + 0.1, 2.0, z + 0.15), solid=False)
    for x in (-15.05, 15.05):
        m.box(c, "Lintel", "carving", (x - 0.1, 2.3, -2.0), (x + 0.1, 2.8, 2.0), solid=False)
    # Grand stairs, north and south, from the plaza to the shrine at 9 m.
    for sz in (-1, 1):
        m.stairs(f, "GrandStairs", (0, 0, sz * 24), (0, 9, sz * 6), 5, kind="temple_light", side="temple_dark",
                 rise=0.3, base=0, fill=True)
        for sx in (-1, 1):
            m.box(f, "Lion", "temple_dark", (sx * 4.6 - 0.8, 0, sz * 25 - 1.2), (sx * 4.6 + 0.8, 1.6, sz * 25 + 1.2))
            m.box(f, "LionHead", "temple_dark", (sx * 4.6 - 0.6, 1.6, sz * 24.2 - 0.6), (sx * 4.6 + 0.6, 2.6, sz * 24.2 + 0.6))
            m.box(f, "Brazier", "stone_dark", (sx * 3.2 - 0.4, 9, sz * 6.6 - 0.4), (sx * 3.2 + 0.4, 9.9, sz * 6.6 + 0.4))
            m.box(f, "Flame", "torch", (sx * 3.2 - 0.25, 9.9, sz * 6.6 - 0.25), (sx * 3.2 + 0.25, 10.3, sz * 6.6 + 0.25), solid=False)
    # Shrine on top: pillars at the corners, walls east and west with doors, a stepped roof.
    s = m.group("Shrine", f)
    for x in (-5, 5):
        for z in (-5, 5):
            m.box(s, "Pillar", "temple_light", (x - 0.6, 9, z - 0.6), (x + 0.6, 13.5, z + 0.6))
    for x in (-5, 5):
        m.wall(s, "Wall", "temple", (x, -4.4), (x, 4.4), 9, 13.5, 0.8, holes=[(3.4, 5.4, 9, 12)])
    m.box(s, "Roof", "temple_dark", (-6.5, 13.5, -6.5), (6.5, 14.3, 6.5))
    m.box(s, "RoofCap", "temple", (-3.5, 14.3, -3.5), (3.5, 15.3, 3.5))
    m.box(s, "RoofGold", "gold", (-1, 15.3, -1), (1, 16.3, 1))
    m.box(s, "Altar", "temple_dark", (-1.2, 9, -0.7), (1.2, 10.1, 0.7))
    m.box(s, "AltarGold", "gold", (-0.4, 10.1, -0.3), (0.4, 10.5, 0.3), solid=False)
    m.box(s, "Banner", "cloth_red", (-4.55, 10.5, -3.6), (-4.5, 13.0, -2.4), solid=False)
    m.box(s, "Banner", "cloth_red", (4.5, 10.5, 2.4), (4.55, 13.0, 3.6), solid=False)


def palace(m):
    """North-west: a two-storey ruin. Plank upper floor and wooden partitions break."""
    g = m.group("Palace")
    X0, X1, Z0, Z1 = -42, -22, -42, -26
    m.box(g, "Floor", "paving", (X0, 0, Z0), (X1, 0.03, Z1), solid=False)
    m.wall(g, "NorthWall", "stone", (X0, Z0), (X1, Z0), 0, 8, 0.8, holes=[(3, 5, 5.2, 7.0), (9, 11, 5.2, 7.0), (14, 16, 5.2, 7.0)])
    m.wall(g, "SouthWall", "stone", (X0, Z1), (X1, Z1), 0, 6.5, 0.8, holes=[(8, 11, 0, 3.2), (3, 5, 5.0, 6.5), (14, 17, 1.2, 2.8)])
    m.wall(g, "WestWall", "stone", (X0, Z0), (X0, Z1), 0, 8, 0.8, holes=[(6, 9, 0, 3.2), (11, 13, 5.2, 7.0)])
    m.wall(g, "EastWall", "stone", (X1, Z0), (X1, Z1), 0, 5.5, 0.8, holes=[(5, 8, 0, 3.2), (11, 13, 1.2, 2.8)])
    m.box(g, "EastRuin", "stone", (X1 - 0.4, 5.5, Z0), (X1 + 0.4, 7.2, Z0 + 4))
    m.box(g, "SouthRuin", "stone", (X0, 6.5, Z1 - 0.4), (X0 + 7, 8, Z1 + 0.4))
    # Upper floor at 4.3 m: west half full depth, east half stops short of the stairs.
    m.box(g, "UpperWest", "plank", (X0, 4.0, Z0), (-31, 4.3, Z1))
    m.box(g, "UpperEast", "plank", (-31, 4.0, Z0), (X1, 4.3, -28.6))
    m.box(g, "Beam", "timber", (-31.1, 3.6, -29.0), (X1, 4.0, -28.6))
    for (x, z) in ((-31, -34), (-26.5, -35), (-36, -30.5)):
        m.box(g, "Post", "timber", (x - 0.25, 0, z - 0.25), (x + 0.25, 4.0, z + 0.25))
    m.stairs(g, "Stairs", (-23, 0, -27.6), (-31, 4.3, -27.6), 1.8, kind="stone_dark", side="stone", base=0)
    m.rail(g, "StairRail", "timber", (-30.9, -28.65), (X1, -28.65), 4.3, 1.0, 0.12)
    # Partitions: ground floor (north-south) and upper floor (east-west).
    m.wall(g, "Partition", "wood_wall", (-36, Z0), (-36, Z1), 0, 4.0, 0.25, holes=[(9, 10.6, 0, 2.6)])
    m.wall(g, "Partition", "wood_wall", (X0, -34), (-31, -34), 4.3, 8, 0.25, holes=[(4.5, 6.1, 4.3, 6.8)])
    # Part of the roof survives over the west rooms; broken beams over the rest.
    m.box(g, "Roof", "stone_dark", (X0, 8, Z0), (-33, 8.6, Z1))
    for x in (-30, -26):
        m.box(g, "RoofBeam", "timber", (x - 0.2, 7.55, Z0), (x + 0.2, 7.95, Z1 + 0.4))
    m.box(g, "FallenBeam", "timber", (-29, 0, -40), (-24, 0.5, -39.4))
    m.box(g, "Rubble", "stone_dark", (-25, 0, -32), (-23.2, 1.0, -30))
    m.box(g, "Rubble", "stone", (-24.5, 1.0, -31.6), (-23.4, 1.6, -30.6))
    m.box(g, "Throne", "gold", (-40.5, 4.3, -37), (-39.5, 6.0, -35.8))
    m.box(g, "ThroneSeat", "cloth_blue", (-40.6, 4.3, -37.1), (-39.0, 5.0, -35.7))
    for z in (-40, -32, -28.5):
        m.box(g, "Torch", "torch", (X0 + 0.42, 2.4, z - 0.15), (X0 + 0.55, 2.8, z + 0.15), solid=False)
    m.box(g, "Vines", "vine", (X1 + 0.42, 1.0, -41), (X1 + 0.46, 5.5, -39), solid=False)


def aqueduct(m):
    """North-east: an aqueduct at 7 m from a ramp at its west end to a broken tower."""
    g = m.group("Aqueduct")
    Z0, Z1 = -35, -30
    m.slab(g, "Ramp", "stone", (8, 0, -32.5), (20, 7, -32.5), 3.2, thick=0.6)
    m.box(g, "RampWall", "stone_dark", (8, 0, -34.3), (20, 0.8, -34.1), solid=False)
    m.box(g, "Deck", "stone", (20, 6, Z0), (44, 7, Z1))
    for zz in (Z0, Z1 - 0.4):
        m.box(g, "Lip", "stone_dark", (20, 7, zz), (40, 7.5, zz + 0.4))
    m.box(g, "Water", "water", (20, 7, Z0 + 0.4), (40, 7.04, Z1 - 0.4), solid=False)
    for x in (22, 28, 34):
        m.box(g, "Pier", "stone", (x - 0.7, 0, Z0 + 0.4), (x + 0.7, 6, Z1 - 0.4))
        m.box(g, "Arch", "stone_dark", (x + 0.7, 5.2, Z0 + 0.6), (x + 5.3, 6, Z1 - 0.6), solid=False)
    m.box(g, "Moss", "moss", (24, 7.5, Z0), (30, 7.55, Z0 + 0.4), solid=False)
    t = m.group("BrokenTower")
    m.box(t, "Tower", "stone", (40, 0, -37), (46, 13.4, -28))
    m.box(t, "Top", "stone_dark", (39.6, 13.4, -37.4), (46.4, 14, -27.6))
    m.box(t, "Battlement", "stone", (39.6, 14, -37.4), (41, 15, -36))
    m.box(t, "Battlement", "stone", (45, 14, -29), (46.4, 15, -27.6))
    m.box(t, "Battlement", "stone", (45, 14, -37.4), (46.4, 15.4, -35))
    m.box(t, "Window", "rock_dark", (39.95, 9, -33.5), (40.05, 11, -32), solid=False)
    m.box(t, "Vines", "vine", (39.94, 4, -30), (39.98, 13.4, -28.6), solid=False)


def tree(m, parent, name, x, z, height=18, canopy=11):
    g = m.group(name, parent, at=(x, 0, z))
    m.cyl(g, "Trunk", "trunk", (0, 0, 0), 2.2, height, sides=10)
    m.cyl(g, "Roots", "trunk", (0, 0, 0), 3.4, 0.8, sides=10)
    m.cyl(g, "Canopy", "leaves", (0, height - 5, 0), canopy, 3.6, sides=12)
    m.cyl(g, "CanopyTop", "leaves_light", (0, height - 1.4, 0), canopy * 0.65, 2.4, sides=10)
    m.cyl(g, "CanopyLow", "leaves_dark", (0, height - 6.2, 0), canopy * 0.8, 1.2, sides=12, solid=False)
    # Drawn only: roots spreading at the foot, boughs under the canopy, vines hanging from
    # it (they stop above head height over the treehouse decks) and clumps of leaf round it.
    seed = x * 0.37 + z * 0.61
    for k in range(5):
        a = seed + k * 1.2566
        m.rod(g, "Root", "trunk", (math.cos(a) * 0.9, 1.5, math.sin(a) * 0.9), (math.cos(a) * 2.5, 0.05, math.sin(a) * 2.5), thick=0.45)
    for k in range(3):
        a = seed * 1.7 + k * 2.2
        m.rod(g, "Bough", "trunk", (math.cos(a) * 0.8, height - 9.5, math.sin(a) * 0.8),
              (math.cos(a) * canopy * 0.36, height - 5.4, math.sin(a) * canopy * 0.36), thick=0.4)
    for k in range(6):
        a = seed * 2.3 + k * 1.05 + rnd(k, seed) * 0.5
        r = canopy * (0.2 + 0.17 * rnd(k, seed + 3))
        drop = 2.2 + 1.7 * rnd(k, seed + 7)
        vx, vz = math.cos(a) * r, math.sin(a) * r
        m.strip(g, "HangingVine", "vine", (vx - 0.05, height - 6.2 - drop, vz - 0.05), (vx + 0.05, height - 6.1, vz + 0.05))
        m.strip(g, "VineLeaf", "leaves_light", (vx - 0.16, height - 6.42 - drop, vz - 0.16), (vx + 0.16, height - 6.1 - drop, vz + 0.16))
    for k in range(7):
        a = seed * 3.1 + k * 0.8976
        r = canopy * 0.5 - 0.55
        w = 0.9 + 0.5 * rnd(k, seed + 11)
        cx, cz = math.cos(a) * r, math.sin(a) * r
        y0 = height - 4.7 + 1.1 * rnd(k, seed + 13)
        m.strip(g, "LeafClump", ("leaves_light", "leaves_dark", "leaves")[k % 3], (cx - w, y0, cz - w), (cx + w, y0 + 1.2 + 0.6 * rnd(k, seed + 17), cz + w))
    return g


def rnd(i, k=0.0):
    """A number from 0 to 1 that is always the same for the same i and k."""
    v = math.sin(i * 12.9898 + k * 78.233 + 1.3) * 43758.5453
    return v - math.floor(v)


def treehouses(m):
    """South-west: three big trees with plank platforms at 6 m and rope bridges between them."""
    f = m.folder("Treehouses")
    trees = {"A": (-34, 27), "B": (-34, 40), "C": (-22, 38)}
    for k, (x, z) in trees.items():
        tree(m, f, "Tree" + k, x, z)
    p = m.group("Platforms", f)
    plats = {"A": (-37.5, -30.5, 23.5, 30.5), "B": (-37.5, -30.5, 36.5, 43.5), "C": (-25.5, -18.5, 34.5, 41.5)}
    for k, (x0, x1, z0, z1) in plats.items():
        m.box(p, "Deck" + k, "plank", (x0, 5.7, z0), (x1, 6.0, z1))
        for (bx, bz) in ((x0 + 0.3, z0 + 0.3), (x1 - 0.3, z0 + 0.3), (x0 + 0.3, z1 - 0.3), (x1 - 0.3, z1 - 0.3)):
            m.box(p, "Strut", "timber", (bx - 0.15, 0, bz - 0.15), (bx + 0.15, 5.7, bz + 0.15))
    # Rope rails, open where bridges and the ramp arrive.
    rails = [
        ("A", (-37.5, 23.5), (-30.5, 23.5), [(2.3, 4.7)]), ("A", (-37.5, 30.5), (-30.5, 30.5), [(2.4, 4.6)]),
        ("A", (-37.5, 23.5), (-37.5, 30.5), []), ("A", (-30.5, 23.5), (-30.5, 30.5), []),
        ("B", (-37.5, 36.5), (-30.5, 36.5), [(2.4, 4.6)]), ("B", (-37.5, 43.5), (-30.5, 43.5), []),
        ("B", (-37.5, 36.5), (-37.5, 43.5), []), ("B", (-30.5, 36.5), (-30.5, 43.5), [(1.4, 3.6)]),
        ("C", (-25.5, 34.5), (-18.5, 34.5), [(2.3, 4.7)]), ("C", (-25.5, 41.5), (-18.5, 41.5), []),
        ("C", (-18.5, 34.5), (-18.5, 41.5), []), ("C", (-25.5, 34.5), (-25.5, 41.5), [(3.4, 5.6)]),
    ]
    for k, a, b, holes in rails:
        m.rail(p, "Rope" + k, "rope", a, b, 6.0, 0.9, 0.08, holes=holes)
    # Rope bridges: A-B (north-south) and B-C (east-west).
    b = m.group("Bridges", f)
    m.box(b, "BridgeAB", "plank", (-35.2, 5.75, 30.5), (-32.8, 5.95, 36.5))
    m.box(b, "BridgeBC", "plank", (-30.5, 5.75, 37.8), (-25.5, 5.95, 40.2))
    for x in (-35.3, -32.8):
        m.box(b, "Rope", "rope", (x, 6.6, 30.5), (x + 0.1, 6.7, 36.5), solid=False)
    for zz in (37.7, 40.2):
        m.box(b, "Rope", "rope", (-30.5, 6.6, zz), (-25.5, 6.7, zz + 0.1), solid=False)
    # A ramp from the ground up to platform A.
    m.slab(f, "Ramp", "plank", (-34, 0, 14), (-34, 6.0, 23.5), 2.2, thick=0.3, unbreakable=True)
    m.box(f, "RampPost", "timber", (-35.2, 0, 21.0), (-34.9, 5.0, 21.3))
    m.box(f, "RampPost", "timber", (-33.1, 0, 21.0), (-32.8, 5.0, 21.3))
    m.slab(f, "RampC", "plank", (-22, 0, 24), (-22, 6.0, 34.5), 2.2, thick=0.3, unbreakable=True)
    # A storage hut on the ground (wooden walls and a thatch roof, both break).
    h = m.group("StoreHut", f)
    m.wall(h, "Wall", "wood_wall", (-46, 28), (-40, 28), 0, 3.2, 0.25, holes=[(2.2, 3.8, 1.2, 2.2)])
    m.wall(h, "Wall", "wood_wall", (-46, 33), (-40, 33), 0, 3.2, 0.25, holes=[(1.5, 3.0, 1.2, 2.2)])
    m.wall(h, "Wall", "wood_wall", (-46, 28), (-46, 33), 0, 3.2, 0.25)
    m.wall(h, "Wall", "wood_wall", (-40, 28), (-40, 33), 0, 3.2, 0.25, holes=[(1.8, 3.4, 0, 2.4)])
    m.box(h, "Roof", "thatch", (-46.6, 3.2, 27.4), (-39.4, 3.5, 33.6))
    m.box(h, "Pots", "pot", (-45.4, 0, 31.6), (-44.4, 0.9, 32.6))


def courtyard(m):
    """South-east: low broken walls (vault over them), standing and fallen columns, a dais, a hut."""
    g = m.group("Courtyard")
    m.box(g, "Floor", "paving", (21.7, 0, 21.7), (42.3, 0.03, 42.3), solid=False)
    for (a, b) in (((22, 22), (30, 22)), ((34, 22), (42, 22)), ((22, 42), (28, 42)), ((32, 42), (42, 42)),
                   ((22, 22), (22, 30)), ((22, 36), (22, 42)), ((42, 22), (42, 28)), ((42, 38), (42, 42))):
        m.wall(g, "LowWall", "stone", a, b, 0, 1.1, 0.7)
    for (x, z, h) in ((27, 27, 2.0), (37, 26, 5.0), (27, 37, 6.5), (37, 38.5, 3.5)):
        m.cyl(g, "Column", "temple_light", (x, 0, z), 1.6, h, sides=12)
        m.cyl(g, "ColumnTop", "temple_dark", (x, h, z), 1.9, 0.3, sides=12)
    m.lying_cyl(g, "FallenColumn", "temple_light", (31, 0.8, 24.6), 1.6, 6.5, axis="x", sides=12)
    # A raised dais with ramps north and south.
    m.box(g, "Dais", "temple", (29, 0, 29), (35, 1.2, 35))
    m.slab(g, "DaisRamp", "temple_light", (32, 1.2, 29), (32, 0, 26.2), 3, thick=0.4)
    m.slab(g, "DaisRamp", "temple_light", (32, 1.2, 35), (32, 0, 37.8), 3, thick=0.4)
    m.box(g, "Statue", "temple_dark", (31.2, 1.2, 31.2), (32.8, 3.6, 32.8))
    m.box(g, "StatueHead", "gold", (31.5, 3.6, 31.5), (32.5, 4.4, 32.5))
    # Hut: wooden walls and a thatch roof.
    h = m.group("Hut", g)
    m.wall(h, "Wall", "wood_wall", (36, 29), (42, 29), 0, 3.2, 0.25, holes=[(2.2, 3.8, 0, 2.4)])
    m.wall(h, "Wall", "wood_wall", (36, 34.5), (42, 34.5), 0, 3.2, 0.25, holes=[(3.6, 5.0, 1.2, 2.2)])
    m.wall(h, "Wall", "wood_wall", (36, 29), (36, 34.5), 0, 3.2, 0.25, holes=[(1.5, 3.1, 0, 2.4)])
    m.wall(h, "Wall", "wood_wall", (42, 29), (42, 34.5), 0, 3.2, 0.25)
    m.box(h, "Roof", "thatch", (35.4, 3.2, 28.4), (42.6, 3.5, 35.1))
    m.box(h, "Table", "timber", (39, 0, 31.2), (41, 0.8, 32.4))


BUSHES = ((14, -24, 1.4), (-8, 20, 1.2), (18, 12, 1.3), (-20, -16, 1.2), (8, -20, 1.0), (28, 16, 1.4),
          (-28, 12, 1.3), (16, 44, 1.6), (-14, -44, 1.6), (44, 12, 1.5), (-44, -14, 1.5))   # (x, z, half its width)
BOULDERS = ((20, -44, 3, 2.2), (-44, 18, 2.6, 1.8), (44, -18, 2.4, 2.6), (-20, 44, 3, 1.6))   # (x, z, width, height)


def middle(m):
    f = m.folder("Grounds")
    # Obelisks east and west of the pyramid (wall-run them, hook their tops).
    for x in (-24, 24):
        for z in (-8, 8):
            g = m.group("Obelisk", f, at=(x, 0, z))
            m.box(g, "Base", "temple_dark", (-1.3, 0, -1.3), (1.3, 0.8, 1.3))
            m.box(g, "Shaft", "temple_light", (-0.8, 0.8, -0.8), (0.8, 11, 0.8))
            m.box(g, "Tip", "gold", (-0.5, 11, -0.5), (0.5, 12, 0.5))
            m.box(g, "Glyphs", "carving", (-0.85, 4, -0.5), (0.85, 8, 0.5), solid=False)
    # East: a stone gate (stand on the lintel).
    g = m.group("EastGate", f)
    for z in (-4.5, 4.5):
        m.box(g, "Post", "temple", (33, 0, z - 1), (35, 8, z + 1))
    m.box(g, "Lintel", "temple_dark", (32.6, 8, -5.6), (35.4, 9.4, 5.6))
    m.box(g, "Carving", "gold", (32.55, 8.3, -1), (32.6, 9.1, 1), solid=False)
    m.box(g, "Rubble", "stone", (37, 0, 6.5), (39, 0.9, 8.5))
    # West: an excavation scaffold (plank decks at 4.5 and 9 m, both break) with a ramp.
    s = m.group("Scaffold", f)
    for x in (-38, -32):
        for z in (-3, 3):
            m.box(s, "Pole", "timber", (x - 0.15, 0, z - 0.15), (x + 0.15, 9.8, z + 0.15))
    m.box(s, "DeckLow", "plank", (-38.2, 4.2, -3.2), (-31.8, 4.5, 3.2))
    m.box(s, "DeckHigh", "plank", (-38.2, 8.7, -3.2), (-31.8, 9.0, 3.2))
    m.slab(s, "Ramp", "plank", (-25.5, 0, -2), (-31.8, 4.5, -2), 2, thick=0.3, unbreakable=True)
    m.rail(s, "Rail", "timber", (-38.2, 3.1), (-31.8, 3.1), 9.0, 1.0, 0.1)
    m.rail(s, "Rail", "timber", (-38.2, -3.1), (-31.8, -3.1), 9.0, 1.0, 0.1)
    m.box(s, "Tarp", "cloth_blue", (-38.35, 9.8, -3.35), (-31.65, 9.9, 3.35), solid=False)
    m.box(s, "Crate", "plank", (-37, 4.5, 1), (-35.8, 5.7, 2.2))
    m.box(s, "Dig", "dirt", (-30, 0, 4), (-26, 0.6, 9))
    # Hedge walls north and south.
    h = m.group("Hedges", f)
    for (x0, x1, z) in ((-16, -2.5, -38), (2.5, 16, -38), (-16, -6, 38), (6, 16, 38)):
        m.box(h, "Hedge", "leaves_dark", (x0, 0, z - 0.8), (x1, 2.6, z + 0.8))
    # Fallen logs, bushes and boulders for cover.
    c = m.group("Cover", f)
    m.lying_cyl(c, "Log", "trunk", (-10, 0.7, -29), 1.4, 9, axis="x", sides=10)
    m.lying_cyl(c, "Log", "trunk", (12, 0.7, 29), 1.4, 8, axis="x", sides=10)
    m.lying_cyl(c, "Log", "trunk", (-17, 0.6, 14), 1.2, 6, axis="z", sides=10)
    for (x, z, s_) in BUSHES:
        m.box(c, "Bush", "leaves", (x - s_, 0, z - s_), (x + s_, s_ * 1.0, z + s_))
    for (x, z, w, h) in BOULDERS:
        m.box(c, "Boulder", "rock", (x - w / 2, 0, z - w / 2), (x + w / 2, h, z + w / 2))
    # Extra trees round the edges.
    for (x, z) in ((14, -43), (-44, -6), (44, 44), (44, 22), (-10, 44), (-44, -46 + 2)):
        tree(m, f, "Tree", x, z, height=16, canopy=9)


CLIFFS = []   # (side, start, width, height, depth, kind) of each cliff, for the details


def cliffs(m):
    """A ring of cliffs round the clearing (you leave the map past them)."""
    g = m.group("Cliffs")
    heights = [14, 18, 12, 20, 16, 13, 19, 15, 17, 12, 18, 14]
    i = 0
    for side in ("n", "s", "e", "w"):
        u = -58
        while u < 58:
            w = 10 + (i * 7) % 6
            h = heights[i % len(heights)]
            depth = 6 + (i * 3) % 4
            kind = "rock" if i % 2 == 0 else "rock_dark"
            if side == "n":
                lo, hi = (u, 0, -48 - depth), (u + w, h, -48)
            elif side == "s":
                lo, hi = (u, 0, 48), (u + w, h, 48 + depth)
            elif side == "e":
                lo, hi = (48, 0, u), (48 + depth, h, u + w)
            else:
                lo, hi = (-48 - depth, 0, u), (-48, h, u + w)
            m.box(g, "Cliff", kind, lo, hi)
            m.box(g, "CliffMoss", "moss", (lo[0] - 0.1, h, lo[2] - 0.1), (hi[0] + 0.1, h + 0.3, hi[2] + 0.1), solid=False)
            CLIFFS.append((side, u, w, h, depth, kind))
            u += w
            i += 1
    # A waterfall down the north cliff, over the lip of the rock it comes off.
    (_, u, w, h, depth, _) = [c for c in CLIFFS if c[0] == "n" and c[1] <= -4 < c[1] + c[2]][0]
    x0, x1 = max(u + 0.6, -6.2), min(u + w - 0.6, -1.8)
    m.strip(g, "Waterfall", "water", (x0, 0.05, -48), (x1, h + 0.34, -47.8))
    m.strip(g, "WaterfallTop", "water", (x0, h + 0.3, -48 - depth), (x1, h + 0.34, -48))
    m.strip(g, "Pool", "water", (-8, 0, -48), (0, 0.05, -45))
    m.strip(g, "Foam", "foam", (x0 - 0.2, 0.05, -47.8), (x1 + 0.2, 0.3, -47.3))
    m.strip(g, "Foam", "foam", (x0 + 0.5, 0.05, -47.3), (x1 - 0.4, 0.14, -46.8))



# ---------------------------------------------------------------------------
# Details. Everything below is drawn only, never solid, so nothing here changes where you
# can stand, what stops a shot or how a bot finds its way. Pieces on a wall stand at most
# 0.35 m off it; what stands further out is small, overhead or beyond the cliffs. On a
# wall, floor or roof that breaks, a piece is either a thin "skin" lying flat on one panel
# (it then breaks with it) or keeps clear of it, so it never holds it up (see MapDestruction).

def details(m):
    pyramid_details(m)
    ground_details(m)
    palace_details(m)
    aqueduct_details(m)
    treehouse_details(m)
    courtyard_details(m)
    grounds_details(m)
    cliff_details(m)


def collar(m, g, name, kind, lo, hi, out=0.08):
    """A band right round a post or block from corner `lo` to `hi`: a box `out` bigger than
    it on every side. Keep its top below the post's top (or the two would share a plane)."""
    m.strip(g, name, kind, (lo[0] - out, lo[1], lo[2] - out), (hi[0] + out, hi[1], hi[2] + out))


def pyramid_details(m):
    g = m.group("Details", "Pyramid")
    for (half, y0) in ((15, 0), (10.5, 3), (6, 6)):
        for s in (-1, 1):
            # A dark course round the foot of each tier, and pale studs along its carved band
            # (neither crosses the stairs or the crypt's doors).
            m.on_wall(g, "Skirt", "temple_dark", "x", s * half, s, -half - 0.12, half + 0.12, y0, y0 + 0.4, 0.12)
            for (a, b) in ((-half, -1.5), (1.5, half)) if half == 15 else ((-half, half),):
                m.on_wall(g, "Skirt", "temple_dark", "z", s * half, s, a, b, y0, y0 + 0.4, 0.12)
            u = -half + 0.75
            while u < half:
                if abs(u) > 3.1:
                    m.on_wall(g, "Stud", "temple_light", "x", s * half, s, u - 0.25, u + 0.25, y0 + 1.16, y0 + 1.44, 0.04, lift=0.05)
                if abs(u) > 2.0 or half < 15:
                    m.on_wall(g, "Stud", "temple_light", "z", s * half, s, u - 0.25, u + 0.25, y0 + 1.16, y0 + 1.44, 0.04, lift=0.05)
                u += 1.5
    # Carved tablets on the bottom tier, each with a gold eye.
    for s in (-1, 1):
        for u in (-11, -6.5, 6.5, 11):
            for axis in ("x", "z"):
                m.on_wall(g, "Tablet", "carving", axis, s * 15, s, u - 0.7, u + 0.7, 1.8, 2.5, 0.06)
                m.on_wall(g, "TabletFace", "temple_dark", axis, s * 15, s, u - 0.5, u + 0.5, 1.95, 2.35, 0.03, lift=0.06)
                m.on_wall(g, "TabletEye", "gold", axis, s * 15, s, u - 0.12, u + 0.12, 2.05, 2.25, 0.03, lift=0.09)
    # The lions at the foot of the stairs: a plinth and gold eyes.
    for sz in (-1, 1):
        for sx in (-1, 1):
            cx = sx * 4.6
            for e in (-0.25, 0.25):
                m.on_wall(g, "LionEye", "gold", "x", sz * 24.8, sz, cx + e - 0.1, cx + e + 0.1, 2.15, 2.3, 0.04)
            collar(m, g, "LionPlinth", "temple", (cx - 0.8, 0, sz * 25 - 1.2), (cx + 0.8, 0.3, sz * 25 + 1.2), 0.15)
    # The crypt: a stick under each torch, glowing inlays along the tunnel, a band on the plinth.
    c = m.group("CryptDetails", "Pyramid")
    for (x, z) in ((-3.9, -3), (3.9, -3), (-3.9, 3), (3.9, 3)):
        m.strip(c, "Sconce", "timber", (x - 0.05, 1.15, z - 0.05), (x + 0.05, 1.6, z + 0.05))
    for sz in (-1, 1):
        for x in (-13, -10, -7, 7, 10, 13):
            m.on_wall(c, "InlayFrame", "carving", "x", sz * 1.5, -sz, x - 0.5, x + 0.5, 1.2, 1.92, 0.02)
            m.on_wall(c, "Inlay", "crystal", "x", sz * 1.5, -sz, x - 0.2, x + 0.2, 1.5, 1.62, 0.03, lift=0.02)
    collar(m, c, "PlinthBand", "temple_light", (-0.8, 0.55, -0.8), (0.8, 0.75, 0.8), 0.06)
    # The shrine: a foot, a head and a gold band on each pillar, carved door frames, a lip
    # round the roof, a gold band round its cap, a cloth over the altar.
    s = m.group("ShrineDetails", "Pyramid")
    for x in (-5, 5):
        for z in (-5, 5):
            collar(m, s, "PillarFoot", "temple_dark", (x - 0.6, 9, z - 0.6), (x + 0.6, 9.4, z + 0.6), 0.12)
            collar(m, s, "PillarHead", "temple_dark", (x - 0.6, 13.05, z - 0.6), (x + 0.6, 13.45, z + 0.6), 0.12)
            collar(m, s, "PillarBand", "gold", (x - 0.6, 11.15, z - 0.6), (x + 0.6, 11.35, z + 0.6), 0.04)
    for sx in (-1, 1):
        for (face, out) in ((sx * 5.4, sx), (sx * 4.6, -sx)):
            m.on_wall(s, "DoorHead", "carving", "z", face, out, -1.4, 1.4, 12.0, 12.45, 0.07)
            for (a, b) in ((-1.4, -1.0), (1.0, 1.4)):
                m.on_wall(s, "DoorJamb", "carving", "z", face, out, a, b, 9, 12.0, 0.07)
        m.on_wall(s, "RoofLip", "temple_light", "x", sx * 6.5, sx, -6.6, 6.6, 13.95, 14.25, 0.1)
        m.on_wall(s, "RoofLip", "temple_light", "z", sx * 6.5, sx, -6.5, 6.5, 13.95, 14.25, 0.1)
        m.on_wall(s, "AltarCloth", "cloth_red", "x", sx * 0.7, sx, -0.5, 0.5, 9.45, 10.13, 0.06)
    collar(m, s, "CapBand", "gold", (-3.5, 14.75, -3.5), (3.5, 14.95, 3.5), 0.05)
    m.strip(s, "AltarCloth", "cloth_red", (-0.5, 10.1, -0.76), (0.5, 10.13, 0.76))


KEEP_OUT = [(-22.6, -22.6, 22.6, 22.6), (-43, -43, -21, -25), (7, -35, 21, -30), (39.5, -37.5, 46.5, -27.5),
            (21.3, 21.3, 42.7, 42.7), (-47, 27, -39, 34), (-3, -41, 3, -22), (-3, 22, 3, 47), (-47, -2.6, -22, 2.6),
            (22, -2.6, 47, 2.6), (-8.6, -48.5, 0.6, -44.4), (-35.6, 13.5, -32.4, 24), (-23.6, 23.5, -20.4, 35),
            (-16.6, -39, 16.6, -37), (-16.6, 37, 16.6, 39), (-30.5, 3.5, -25.5, 9.5)]   # where no grass grows


def ground_details(m):
    g = m.group("Scatter", "Ground")
    # Moss in the plaza's paving (2 cm proud of it), clear of the pyramid and its stairs.
    for i in range(70):
        x, z = -21 + 42 * rnd(i, 1), -21 + 42 * rnd(i, 2)
        a, b = 0.5 + 1.0 * rnd(i, 3), 0.4 + 0.8 * rnd(i, 4)
        outside = abs(x) - a > 15.3 or abs(z) - b > 15.3
        on_stairs = abs(x) - a < 3.3 and abs(z) > abs(x)
        if outside and not on_stairs and abs(x) + a < 21.8 and abs(z) + b < 21.8:
            m.strip(g, "Moss", "moss", (x - a, 0.03, z - b), (x + a, 0.05, z + b))
    # Tufts of grass, flowers and pebbles across the clearing: the same every time it is built.
    placed = []
    for i in range(460):
        x, z = -47 + 94 * rnd(i, 5), -47 + 94 * rnd(i, 6)
        if any(a - 0.3 < x < c + 0.3 and b - 0.3 < z < d + 0.3 for (a, b, c, d) in KEEP_OUT):
            continue
        if any(abs(x - px) < 0.7 and abs(z - pz) < 0.7 for (px, pz) in placed):
            continue   # never two in one spot
        placed.append((x, z))
        w, h = 0.1 + 0.12 * rnd(i, 7), 0.14 + 0.2 * rnd(i, 8)
        if i % 7 < 4:
            m.strip(g, "Tuft", ("leaves", "leaves_light", "grass_dark", "leaves_dark")[i % 7], (x - w, 0, z - w), (x + w, h, z + w))
        elif i % 7 < 6:
            m.strip(g, "Tuft", "leaves", (x - 0.07, 0, z - 0.07), (x + 0.07, 0.21, z + 0.07))
            m.strip(g, "Flower", ("flower", "flower_pink", "gold")[i % 3], (x - 0.1, 0.21, z - 0.1), (x + 0.1, 0.33, z + 0.1))
        else:
            m.strip(g, "Pebble", "rock", (x - w * 1.3, 0, z - w), (x + w * 1.3, h * 0.6, z + w), tint=(1.1, 1.1, 1.1) if i % 2 else (0.85, 0.85, 0.85))
    # Ferns along the foot of the cliffs.
    for i in range(52):
        u = -46 + 92 * rnd(i, 9)
        w = 0.35 + 0.22 * rnd(i, 10)
        h = 0.3 + 0.3 * rnd(i, 11)
        x, z = ((u, -47.4), (u, 47.4), (-47.4, u), (47.4, u))[i % 4]
        if i % 4 == 0 and -9.5 < u < 1.5:
            continue   # the pool
        m.strip(g, "Fern", "leaves_dark" if i % 2 else "leaves", (x - w, 0, z - w), (x + w, h, z + w))
        m.strip(g, "FernTop", "leaves_light", (x - w * 0.5, h, z - w * 0.5), (x + w * 0.5, h + 0.16, z + w * 0.5))


def opening(m, g, axis, line, half, u0, u1, y0, y1, door=False, faces=(-1, 1)):
    """Timber over a window or door in a stone wall and stone under a window, on both faces."""
    for out in faces:
        face = line + out * half
        m.on_wall(g, "Lintel", "timber", axis, face, out, u0 - 0.35, u1 + 0.35, y1, y1 + 0.35, 0.1)
        if not door:
            m.on_wall(g, "Sill", "stone_dark", axis, face, out, u0 - 0.2, u1 + 0.2, y0 - 0.22, y0, 0.12)


def palace_details(m):
    g = m.group("Details", "Palace")
    X0, X1, Z0, Z1 = -42, -22, -42, -26
    for (a, b) in ((-39, -37), (-33, -31), (-28, -26)):
        opening(m, g, "x", Z0, 0.4, a, b, 5.2, 7.0)
    opening(m, g, "x", Z1, 0.4, -34, -31, 0, 3.2, door=True)
    opening(m, g, "x", Z1, 0.4, -39, -37, 5.0, 6.5)
    opening(m, g, "x", Z1, 0.4, -28, -25, 1.2, 2.8, faces=(1,))    # the stairs run along its inside
    opening(m, g, "z", X0, 0.4, -36, -33, 0, 3.2, door=True)
    opening(m, g, "z", X0, 0.4, -31, -29, 5.2, 7.0)
    opening(m, g, "z", X1, 0.4, -37, -34, 0, 3.2, door=True)
    opening(m, g, "z", X1, 0.4, -31, -29, 1.2, 2.8)
    # The throne room upstairs: a carpet with gold edges (thin, on the plank floor: it breaks
    # with it) and banners behind the throne.
    m.strip(g, "Carpet", "cloth_red", (-38.9, 4.3, -36.8), (-31.2, 4.33, -36.0))
    for (a, b) in ((-36.9, -36.8), (-36.0, -35.9)):
        m.strip(g, "CarpetEdge", "gold", (-38.9, 4.3, a), (-31.2, 4.33, b))
    for (a, b) in ((-37.7, -37.0), (-35.8, -35.1)):
        m.on_wall(g, "Banner", "cloth_blue", "z", X0 + 0.4, 1, a, b, 5.3, 7.4, 0.04)
        m.on_wall(g, "BannerHem", "gold", "z", X0 + 0.4, 1, a, b, 5.3, 5.45, 0.02, lift=0.04)
    for z in (-40, -32, -28.5):
        m.on_wall(g, "Sconce", "timber", "z", X0 + 0.4, 1, z - 0.05, z + 0.05, 1.95, 2.4, 0.12)
    # Vines over the broken walls and off the roof's edge, moss on the roof, pots in a corner.
    vine(m, g, "x", Z1 + 0.4, 1, -40.5, 8.0, 3.6)
    vine(m, g, "x", Z1 + 0.4, 1, -24.2, 6.5, 2.4)
    vine(m, g, "z", X1 + 0.4, 1, -32.6, 5.5, 2.2)
    vine(m, g, "z", -33, 1, -37.5, 8.6, 1.8, over=0.4)
    for (x0, z0, x1, z1) in ((-41.5, -41, -38.8, -38.6), (-37.2, -33.5, -34.2, -30.9), (-40.8, -29.2, -38.9, -26.8)):
        m.strip(g, "RoofMoss", "moss", (x0, 8.6, z0), (x1, 8.63, z1))
    for (x, z, d, h) in ((-41.0, -41.0, 0.5, 0.6), (-40.4, -41.1, 0.36, 0.45), (-41.1, -40.4, 0.36, 0.4)):
        m.pipe(g, "Pot", "pot", (x, 0, z), (x, h, z), d)
        m.pipe(g, "PotRim", "pot", (x, h, z), (x, h + 0.05, z), d * 0.7, tint=(0.8, 0.8, 0.8))
    for k, (x, z) in enumerate(((-25.4, -29.6), (-23.0, -32.3), (-25.5, -31.2), (-24.2, -29.5), (-26.0, -30.4))):
        s_ = 0.12 + 0.05 * (k % 3)
        m.strip(g, "RubbleStone", "stone" if k % 2 else "stone_dark", (x - s_, 0, z - s_), (x + s_, s_ * 1.4, z + s_))


def aqueduct_details(m):
    g = m.group("Details", "Aqueduct")
    Z0, Z1 = -35, -30
    for x in (22, 28, 34):
        collar(m, g, "PierFoot", "stone_dark", (x - 0.7, 0, Z0 + 0.4), (x + 0.7, 0.5, Z1 - 0.4), 0.15)
        collar(m, g, "PierHead", "stone_dark", (x - 0.7, 4.75, Z0 + 0.4), (x + 0.7, 5.1, Z1 - 0.4), 0.12)
        for (face, out) in ((Z1, 1), (Z0, -1)):
            m.on_wall(g, "Keystone", "stone_dark", "x", face, out, x + 2.7, x + 3.3, 6.0, 6.6, 0.12)
    for (face, out) in ((Z1, 1), (Z0, -1)):
        m.on_wall(g, "Course", "stone_dark", "x", face, out, 20, 40, 6.6, 6.85, 0.1)
    vine(m, g, "x", Z1, 1, 23.6, 7.5, 3.2, over=0.4)
    vine(m, g, "x", Z1, 1, 31.5, 7.5, 2.4, over=0.4)
    vine(m, g, "x", Z1, 1, 37.8, 7.5, 3.8, over=0.4)
    vine(m, g, "x", Z0, -1, 33.0, 7.5, 2.6, over=0.4)
    # The broken tower: two courses of darker stone, arrow slits, a flag on its highest corner.
    t = m.group("Details", "BrokenTower")
    for y in (4.5, 8.4):
        collar(m, t, "Course", "stone_dark", (40, y, -37), (46, y + 0.3, -28), 0.1)
    for (y0, y1) in ((2.6, 4.2), (9.6, 11.2)):
        m.on_wall(t, "Slit", "rock_dark", "x", -28, 1, 42.75, 43.25, y0, y1, 0.05)
    m.pipe(t, "FlagPole", "timber", (45.7, 15.4, -36.2), (45.7, 19.2, -36.2), 0.14)
    m.strip(t, "Flag", "cloth_blue", (43.7, 17.9, -36.22), (45.63, 19.0, -36.18))
    m.strip(t, "FlagBand", "gold", (43.67, 18.3, -36.245), (45.66, 18.5, -36.155))


def hut_details(m, g, x0, x1, z0, z1, openings):
    """A timber frame round each door and window of a wooden hut, and a ridge pole and darker
    rows on its thatch. Every piece is thin and lies on one wall or roof panel, so it breaks
    with it. openings: (axis, the wall's line, from, to, bottom, top)."""
    for (axis, line, u0, u1, y0, y1) in openings:
        low = y0 - 0.12 if y0 > 0 else 0
        for out in (-1, 1):
            face = line + out * 0.125
            m.on_wall(g, "Frame", "timber", axis, face, out, u0, u1, y1, y1 + 0.12, 0.05)
            m.on_wall(g, "Frame", "timber", axis, face, out, u0 - 0.12, u0, low, y1 + 0.12, 0.05)
            m.on_wall(g, "Frame", "timber", axis, face, out, u1, u1 + 0.12, low, y1 + 0.12, 0.05)
            if y0 > 0:
                m.on_wall(g, "Frame", "timber", axis, face, out, u0, u1, low, y0, 0.05)
    zc = (z0 + z1) / 2
    m.strip(g, "Ridge", "timber", (x0 - 0.6, 3.5, zc - 0.1), (x1 + 0.6, 3.62, zc + 0.1))
    z = z0 - 0.1
    while z + 0.5 < z1 + 0.6:
        if abs(z + 0.25 - zc) > 0.5:
            m.strip(g, "ThatchRow", "thatch", (x0 - 0.6, 3.5, z), (x1 + 0.6, 3.56, z + 0.5), tint=(0.84, 0.82, 0.78))
        z += 1.1


def treehouse_details(m):
    g = m.group("Details", "Treehouses")
    # Joists under each deck: thin, flat against it, so they break with it.
    for (x0, x1, z0, z1) in ((-37.5, -30.5, 23.5, 30.5), (-37.5, -30.5, 36.5, 43.5), (-25.5, -18.5, 34.5, 41.5)):
        for dx in (1.0, 2.6, 4.4, 6.0):
            m.strip(g, "Joist", "timber", (x0 + dx - 0.1, 5.58, z0 + 0.05), (x0 + dx + 0.1, 5.7, z1 - 0.05))
    # A lantern on an arm off each trunk, above head height.
    for (tx, tz, dx, dz) in ((-34, 27, 1, 0), (-34, 40, 0, -1), (-22, 38, -1, 0)):
        m.rod(g, "LanternArm", "timber", (tx + dx * 0.95, 8.75, tz + dz * 0.95), (tx + dx * 1.8, 8.75, tz + dz * 1.8), thick=0.08)
        lx, lz = tx + dx * 1.65, tz + dz * 1.65
        m.strip(g, "LanternRope", "rope", (lx - 0.02, 8.52, lz - 0.02), (lx + 0.02, 8.72, lz + 0.02))
        m.strip(g, "Lantern", "torch", (lx - 0.15, 8.1, lz - 0.15), (lx + 0.15, 8.46, lz + 0.15))
        m.strip(g, "LanternCap", "timber", (lx - 0.19, 8.46, lz - 0.19), (lx + 0.19, 8.52, lz + 0.19))
    # Ties from the bridges' hand ropes down to their planks (beside them, not on them).
    for x in (-35.27, -32.77):
        for k in range(6):
            m.strip(g, "RopeTie", "rope", (x, 5.75, 31.0 + k), (x + 0.04, 6.6, 31.04 + k))
    for z in (37.73, 40.23):
        for k in range(5):
            m.strip(g, "RopeTie", "rope", (-30.0 + k, 5.75, z), (-29.96 + k, 6.6, z + 0.04))
    hut_details(m, m.group("Details", "Treehouses/StoreHut"), -46, -40, 28, 33,
                (("x", 28, -43.8, -42.2, 1.2, 2.2), ("x", 33, -44.5, -43.0, 1.2, 2.2), ("z", -40, 29.8, 31.4, 0, 2.4)))


def courtyard_details(m):
    g = m.group("Details", "Courtyard")
    for (x, z, h) in ((27, 27, 2.0), (37, 26, 5.0), (27, 37, 6.5), (37, 38.5, 3.5)):
        m.pipe(g, "ColumnFoot", "temple_dark", (x, 0, z), (x, 0.4, z), 2.0, sides=12)
        if h > 3:
            m.pipe(g, "ColumnRing", "temple_dark", (x, h * 0.5, z), (x, h * 0.5 + 0.22, z), 1.72, sides=12)
    for x in (28.6, 31.0, 33.4):
        m.pipe(g, "ColumnRing", "temple_dark", (x - 0.12, 0.8, 24.6), (x + 0.12, 0.8, 24.6), 1.72, sides=12)
    # The dais: a pale band under its edge (not across the ramps), and the statue on it.
    for s in (-1, 1):
        m.on_wall(g, "DaisBand", "temple_light", "z", 32 + s * 3, s, 29, 35, 0.85, 1.15, 0.08)
        for (a, b) in ((28.92, 30.5), (33.5, 35.08)):
            m.on_wall(g, "DaisBand", "temple_light", "x", 32 + s * 3, s, a, b, 0.85, 1.15, 0.08)
        for (a, b) in ((31.68, 31.88), (32.12, 32.32)):
            m.on_wall(g, "StatueEye", "crystal", "x", 32 + s * 0.5, s, a, b, 4.0, 4.14, 0.04)
    collar(m, g, "StatueFoot", "temple_light", (31.2, 1.2, 31.2), (32.8, 1.55, 32.8), 0.2)
    collar(m, g, "StatueCollar", "gold", (31.2, 3.3, 31.2), (32.8, 3.5, 32.8), 0.05)
    for (x0, z0, x1, z1) in ((24.0, 32.5, 25.6, 33.6), (33.2, 39.2, 35.0, 40.4), (38.4, 23.2, 40.2, 24.3), (29.6, 23.0, 30.8, 23.9)):
        m.strip(g, "Moss", "moss", (x0, 0.03, z0), (x1, 0.05, z1))
    h = m.group("Details", "Courtyard/Hut")
    hut_details(m, h, 36, 42, 29, 34.5,
                (("x", 29, 38.2, 39.8, 0, 2.4), ("x", 34.5, 39.6, 41.0, 1.2, 2.2), ("z", 36, 30.5, 32.1, 0, 2.4)))
    m.pipe(h, "Bowl", "pot", (39.5, 0.8, 31.8), (39.5, 0.98, 31.8), 0.42)
    m.pipe(h, "Jug", "pot", (40.4, 0.8, 31.6), (40.4, 1.25, 31.6), 0.26)


def grounds_details(m):
    # Obelisks: glyphs on the other two faces, gold marks on all four, a collar and a gold band.
    for x in (-24, 24):
        for z in (-8, 8):
            g = m.group("ObeliskDetails", "Grounds", at=(x, 0, z))
            m.strip(g, "Glyphs", "carving", (-0.5, 4, -0.85), (0.5, 8, 0.85))
            collar(m, g, "Collar", "temple_dark", (-0.8, 0.8, -0.8), (0.8, 1.15, 0.8), 0.1)
            collar(m, g, "GoldBand", "gold", (-0.8, 10.3, -0.8), (0.8, 10.5, 0.8), 0.04)
            for k in range(5):
                y = 4.35 + k * 0.72
                w = (0.2, 0.12, 0.26, 0.16, 0.22)[k]
                for s in (-1, 1):
                    m.on_wall(g, "Glyph", "gold", "z", s * 0.85, s, -w, w, y, y + 0.3, 0.035)
                    m.on_wall(g, "Glyph", "gold", "x", s * 0.85, s, -w, w, y, y + 0.3, 0.035)
    # The east gate: the gold carving on its far side too, bands and torches on the posts, a vine.
    g = m.group("GateDetails", "Grounds")
    m.strip(g, "Carving", "gold", (35.4, 8.3, -1), (35.45, 9.1, 1))
    for z in (-4.5, 4.5):
        for y in (1.0, 6.4):
            collar(m, g, "PostBand", "carving", (33, y, z - 1), (35, y + 0.5, z + 1), 0.06)
        for (face, out) in ((33, -1), (35, 1)):
            m.on_wall(g, "TorchArm", "timber", "z", face, out, z - 0.05, z + 0.05, 2.9, 3.3, 0.14)
            m.on_wall(g, "Torch", "torch", "z", face, out, z - 0.14, z + 0.14, 3.3, 3.7, 0.22)
    vine(m, g, "z", 32.6, -1, 3.4, 9.4, 1.35)
    vine(m, g, "z", 35.4, 1, -3.0, 9.4, 1.2)
    # The scaffold: braces under both decks (stopping short of them: the decks break), a
    # lantern, flaps on the tarp; a shovel, a bucket and marker stakes at the dig.
    s = m.group("ScaffoldDetails", "Grounds")
    for z in (-3, 3):
        for (x, way) in ((-38, 1), (-32, -1)):
            for top in (4.1, 8.6):
                m.rod(s, "Brace", "timber", (x + way * 0.1, top - 0.95, z), (x + way * 0.95, top - 0.07, z), thick=0.1)
                zw = -1 if z > 0 else 1
                m.rod(s, "Brace", "timber", (x, top - 0.95, z + zw * 0.1), (x, top - 0.07, z + zw * 0.95), thick=0.1)
    m.rod(s, "LanternArm", "timber", (-31.9, 7.5, 3), (-31.2, 7.5, 3), thick=0.07)
    m.strip(s, "LanternRope", "rope", (-31.32, 7.26, 2.98), (-31.28, 7.47, 3.02))
    m.strip(s, "Lantern", "torch", (-31.45, 6.9, 2.85), (-31.15, 7.26, 3.15))
    m.strip(s, "TarpFlap", "cloth_blue", (-38.35, 9.25, -3.35), (-38.31, 9.8, 3.35))
    m.strip(s, "TarpFlap", "cloth_blue", (-38.35, 9.45, 3.31), (-34.5, 9.8, 3.35))
    m.rod(s, "Shovel", "timber", (-28.3, 0.55, 5.6), (-27.9, 1.7, 5.9), thick=0.05)
    m.strip(s, "ShovelBlade", "stone_dark", (-28.45, 0.6, 5.5), (-28.2, 0.92, 5.56))
    m.pipe(s, "Bucket", "pot", (-27.0, 0.6, 7.8), (-27.0, 0.95, 7.8), 0.4)
    for (x, z) in ((-30.3, 3.7), (-25.7, 3.7), (-30.3, 9.3), (-25.7, 9.3)):
        m.strip(s, "Stake", "timber", (x - 0.04, 0, z - 0.04), (x + 0.04, 0.9, z + 0.04))
        m.strip(s, "StakeFlag", "cloth_red", (x + 0.04, 0.66, z - 0.01), (x + 0.3, 0.86, z + 0.01))
    for k, (x, z) in enumerate(((-29.2, 4.6), (-26.6, 5.2), (-28.6, 8.3), (-27.4, 6.6))):
        s_ = 0.1 + 0.04 * k
        m.strip(s, "Spoil", "rock", (x - s_, 0.6, z - s_), (x + s_, 0.6 + s_ * 1.2, z + s_))
    # Flowers in the hedges.
    h = m.group("HedgeFlowers", "Grounds")
    for j, (x0, x1, z) in enumerate(((-16, -2.5, -38), (2.5, 16, -38), (-16, -6, 38), (6, 16, 38))):
        placed = []
        for i in range(18):
            u = x0 + 0.3 + (x1 - x0 - 0.6) * rnd(i, 20 + j)
            if any(abs(u - pu) < 0.3 for pu in placed):
                continue
            placed.append(u)
            kind = ("flower", "flower_pink")[i % 2]
            if i % 3 == 0:
                v = z - 0.6 + 1.2 * rnd(i, 30 + j)
                m.strip(h, "Flower", kind, (u - 0.08, 2.6, v - 0.08), (u + 0.08, 2.67, v + 0.08))
            else:
                out = 1 if (i // 2) % 2 else -1
                y = 0.5 + 1.8 * rnd(i, 40 + j)
                m.on_wall(h, "Flower", kind, "x", z + out * 0.8, out, u - 0.08, u + 0.08, y - 0.08, y + 0.08, 0.06)
    # Bushes: a paler crown and a few berries. Boulders: moss on top, a stone or two beside.
    c = m.group("CoverDetails", "Grounds")
    for i, (x, z, s_) in enumerate(BUSHES):
        m.strip(c, "BushTop", "leaves_light", (x - s_ * 0.55, s_, z - s_ * 0.55), (x + s_ * 0.55, s_ + 0.22, z + s_ * 0.55))
        if i % 2 == 0:
            for k in range(5):
                u, y = (rnd(k, 50 + i) - 0.5) * s_ * 1.6, s_ * (0.25 + 0.6 * rnd(k, 60 + i))
                out = 1 if k % 2 else -1
                if k < 3:
                    m.on_wall(c, "Berry", "flower_pink", "x", z + out * s_, out, x + u - 0.06, x + u + 0.06, y - 0.06, y + 0.06, 0.05)
                else:
                    m.on_wall(c, "Berry", "flower_pink", "z", x + out * s_, out, z + u - 0.06, z + u + 0.06, y - 0.06, y + 0.06, 0.05)
    for (x, z, w, h_) in BOULDERS:
        m.strip(c, "BoulderMoss", "moss", (x - w / 2 + 0.15, h_, z - w / 2 + 0.2), (x + w / 2 - 0.4, h_ + 0.04, z + w / 2 - 0.15))
        m.strip(c, "BoulderStone", "rock_dark", (x + w / 2, 0, z - 0.3), (x + w / 2 + 0.4, 0.35, z + 0.2))
        m.strip(c, "BoulderStone", "rock", (x - 0.2, 0, z + w / 2), (x + 0.3, 0.25, z + w / 2 + 0.35), tint=(1.1, 1.1, 1.1))
    # The cut ends of the fallen logs.
    for (x, y, z, d, way) in ((-14.5, 0.7, -29, 1.4, -1), (-5.5, 0.7, -29, 1.4, 1), (8, 0.7, 29, 1.4, -1), (16, 0.7, 29, 1.4, 1)):
        m.pipe(c, "LogEnd", "plank", (x, y, z), (x + way * 0.03, y, z), d - 0.3, sides=10)
    for (z, way) in ((11, -1), (17, 1)):
        m.pipe(c, "LogEnd", "plank", (-17, 0.6, z), (-17, 0.6, z + way * 0.03), 0.9, sides=10)


def cliff_details(m):
    g = m.group("Details", "Cliffs")
    t = m.group("TopTrees", "Cliffs")
    for i, (side, u, w, h, depth, kind) in enumerate(CLIFFS):
        other = "rock_dark" if kind == "rock" else "rock"

        def on_face(name, k, a, b, y0, y1, d):
            """A piece on the cliff's face, from a to b along it (measured from its start)."""
            if side == "n" and u + a < -1.2 and u + b > -6.8:
                return   # the waterfall
            axis, face, out = {"n": ("x", -48, 1), "s": ("x", 48, -1), "e": ("z", 48, -1), "w": ("z", -48, 1)}[side]
            m.on_wall(g, name, k, axis, face, out, u + a, u + b, y0, y1, d)

        # Ledges of the other rock across the face (above head height), a vine from the top.
        for j in range(3):
            a = 0.4 + (w - 4.4) * rnd(i, 50 + j)
            y = 4.5 + (h - 7) * rnd(i, 60 + j)
            on_face("Ledge", other, a, a + 2.2 + 1.6 * rnd(i, 70 + j), y, y + 0.5 + 0.4 * rnd(i, 80 + j), 0.22 + 0.06 * j)
        if i % 3 != 2:
            a = 1 + (w - 2.2) * rnd(i, 90)
            drop = 3 + 4 * rnd(i, 91)
            on_face("CliffVine", "vine", a - 0.35, a + 0.35, h - drop, h + 0.2, 0.14)
            on_face("CliffVine", "vine", a + 0.5, a + 0.68, h - drop * 0.6, h + 0.2, 0.17)
        # Jungle on top, back from the edge where nobody can go.
        along, back = u + w * (0.3 + 0.4 * rnd(i, 95)), 48 + depth * 0.62
        x, z = {"n": (along, -back), "s": (along, back), "e": (back, along), "w": (-back, along)}[side]
        tall, wide = 6 + 3 * rnd(i, 96), 6 + 2.5 * rnd(i, 97)
        m.cyl(t, "Trunk", "trunk", (x, h, z), 1.0, tall, sides=8, solid=False)
        m.cyl(t, "Canopy", "leaves" if i % 2 else "leaves_dark", (x, h + tall - 1.5, z), wide, 2.6, sides=10, solid=False)
        m.cyl(t, "CanopyTop", "leaves_light", (x, h + tall + 1.1, z), wide * 0.6, 1.5, sides=8, solid=False)
        front = 48.5 + 0.8 * rnd(i, 94)
        along = u + 1.2 + (w - 2.4) * rnd(i, 93)
        x, z = {"n": (along, -front), "s": (along, front), "e": (front, along), "w": (-front, along)}[side]
        m.strip(t, "Bush", "leaves", (x - 0.8, h + 0.3, z - 0.7), (x + 0.8, h + 1.0, z + 0.7))
    # The pool under the waterfall: rocks round it, lily pads on it, reeds along its edge.
    p = m.group("Pool", "Cliffs")
    for (x, z, s_) in ((-8.2, -45.2, 0.3), (-0.1, -45.4, 0.26), (-4.6, -44.85, 0.22), (-7.9, -46.9, 0.34), (0.1, -47.2, 0.3)):
        m.strip(p, "PoolRock", "rock", (x - s_, 0, z - s_), (x + s_, s_ * 1.1, z + s_))
    for (x, z) in ((-6.4, -45.8), (-2.2, -46.3), (-1.2, -45.5)):
        m.strip(p, "LilyPad", "leaves_light", (x - 0.22, 0.05, z - 0.22), (x + 0.22, 0.07, z + 0.22))
    for k in range(8):
        x = -7.4 + k * 0.9 + 0.3 * rnd(k, 92)
        m.strip(p, "Reed", "leaves", (x - 0.04, 0, -45.0), (x + 0.04, 0.5 + 0.4 * rnd(k, 89), -44.92))
    # Far off, flat-topped hills above the tree line, so the cliffs are not the horizon.
    f = m.group("FarHills", "Cliffs")
    for i in range(9):
        a = i * 0.698 + 0.3
        r = 240 + 40 * rnd(i, 99)
        x, z = math.cos(a) * r, math.sin(a) * r
        h = 48 + 30 * rnd(i, 98)
        m.cyl(f, "Hill", "leaves_dark", (x, -1, z), 120, h * 0.45, sides=10, solid=False, tint=(0.82, 0.95, 1.0))
        m.cyl(f, "HillRock", "rock", (x + 6, -1 + h * 0.45, z - 4), 64, h * 0.47, sides=9, solid=False, tint=(0.95, 1.0, 1.08))
        m.cyl(f, "HillTop", "leaves", (x + 6, -1 + h * 0.92, z - 4), 70, h * 0.08, sides=9, solid=False, tint=(0.85, 0.95, 1.0))


def spawns(m):
    pts = [
        ((-18, 0, -18), (0, 0)), ((18, 0, -18), (0, 0)), ((-18, 0, 18), (0, 0)), ((18, 0, 18), (0, 0)),
        ((0, 9, -3.5), (0, -20)), ((-2.5, 0, -2.6), (10, 0)),
        ((-26, 0, -38), (0, 0)), ((-39, 0, -30), (0, 0)), ((-38, 4.3, -38), (0, 0)),
        ((30, 7, -32.5), (0, 0)), ((-34, 6, 24.6), (0, 0)), ((-19.5, 6, 35.5), (0, 0)),
        ((25, 0, 25), (0, 0)), ((39, 0, 25), (0, 0)), ((25, 0, 40), (0, 0)),
        ((-24, 0, 10), (0, 0)), ((40, 0, 0), (0, 0)), ((8, 0, -43), (0, 0)), ((-10, 0, 41), (0, 0)),
        ((44, 0, -44), (0, 0)), ((-30, 0, -14), (0, 0)), ((30, 0, 12), (0, 0)),
    ]
    for p, t in pts:
        m.spawn(p, t)


def pickups(m):
    for (p, w) in [
        ((0, 0, 2.8), "shotgun"), ((5.4, 14.3, 5.4), "bolt_action"), ((37, 7, -32.5), "rifle"), ((43, 14, -32.5), "railgun"),
        ((-29, 0, -36), "smg"), ((-40, 4.3, -30), "break_action"), ((-36.5, 6, 42.5), "axe"), ((-24.6, 6, 38.6), "bat"),
        ((33.5, 1.2, 30.2), "grenade_launcher"), ((-35, 9, 0), "lever_action"), ((38.5, 0, 33), "brass_knuckles"),
        ((38, 0, -2), "lmg"), ((-12, 0, -20), "revolver"), ((10, 0, 20), "sword"), ((-10, 0, -40), "bolt_action"),
    ]:
        m.weapon(p, w)
