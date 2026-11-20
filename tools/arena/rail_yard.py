"""Rail Yard: a large arena (up to 16 players). A brick station hall with a mezzanine and a
walkable roof on the north side, four tracks with trains you can run through, island
platforms under canopies, a covered footbridge over everything, and a goods yard with a
shed, a signal box and a water tower on the south side.

Floors: street and yard 0 m, platforms and concourse 1 m, mezzanine and footbridge
6.5 m, station roof 13 m, signal box 4 m, water tower deck 10 m.
"""
import math
from arena_builder import Map, palette

PAL = "res://game/maps/palettes/rail_yard.tres"

COLORS = {
    "ground": (0.55, 0.52, 0.47), "street": (0.42, 0.42, 0.43), "pavement": (0.68, 0.67, 0.64),
    "ballast": (0.48, 0.45, 0.41), "rail": (0.36, 0.34, 0.33), "sleeper": (0.32, 0.25, 0.2),
    "platform": (0.78, 0.76, 0.72), "platform_edge": (0.96, 0.8, 0.18), "tactile": (0.9, 0.86, 0.7),
    "brick": (0.62, 0.3, 0.22), "brick_dark": (0.45, 0.22, 0.17), "stone_trim": (0.86, 0.82, 0.72),
    "tile": (0.82, 0.8, 0.74), "tile_dark": (0.42, 0.4, 0.38), "floorboard": (0.64, 0.47, 0.3),
    "plaster": (0.9, 0.86, 0.76), "glass": (0.64, 0.8, 0.86), "glass_rail": (0.62, 0.78, 0.84),
    "iron": (0.17, 0.33, 0.27), "iron_dark": (0.13, 0.2, 0.18), "canopy": (0.75, 0.78, 0.76),
    "roof": (0.33, 0.36, 0.4), "steel": (0.5, 0.53, 0.56), "steel_dark": (0.3, 0.32, 0.35),
    "train": (0.78, 0.2, 0.17), "train_stripe": (0.96, 0.93, 0.86), "train_roof": (0.55, 0.57, 0.6),
    "train_floor": (0.36, 0.38, 0.42), "train_seat": (0.2, 0.33, 0.6), "window_dark": (0.15, 0.2, 0.26),
    "loco": (0.16, 0.36, 0.58), "loco_yellow": (0.95, 0.75, 0.12), "wagon": (0.45, 0.3, 0.22),
    "wagon_grey": (0.52, 0.54, 0.52), "tank": (0.2, 0.2, 0.22), "coal": (0.12, 0.12, 0.13),
    "shed_wall": (0.56, 0.62, 0.6), "shed_roof": (0.48, 0.5, 0.52), "crate": (0.7, 0.55, 0.34),
    "crate_dark": (0.55, 0.42, 0.26), "pallet": (0.6, 0.5, 0.36), "concrete": (0.66, 0.66, 0.64),
    "bench": (0.42, 0.28, 0.18), "kiosk": (0.2, 0.45, 0.36), "awning": (0.86, 0.3, 0.24),
    "lamp": (1.0, 0.95, 0.8), "signal_red": (1.0, 0.2, 0.15), "signal_green": (0.3, 1.0, 0.45),
    "clock": (0.97, 0.95, 0.88), "sign": (0.12, 0.2, 0.36), "tunnel": (0.06, 0.06, 0.07),
    "backdrop": (0.6, 0.55, 0.52), "backdrop_dark": (0.48, 0.44, 0.43), "water_tank": (0.38, 0.42, 0.36),
    "timber": (0.42, 0.32, 0.22), "fence": (0.3, 0.32, 0.3), "plant": (0.34, 0.56, 0.3),
    # details
    "hazard": (0.95, 0.76, 0.12), "grille": (0.2, 0.22, 0.24), "stain": (0.4, 0.38, 0.35), "paint": (0.93, 0.92, 0.88),
    "poster_red": (0.72, 0.22, 0.18), "poster_blue": (0.2, 0.38, 0.6), "poster_cream": (0.92, 0.86, 0.68),
}
GLOW = {"lamp": 1.4, "signal_red": 2.5, "signal_green": 2.5, "clock": 0.4}
BREAKABLE = {
    "glass": 25, "glass_rail": 40, "plaster": 120, "floorboard": 220, "canopy": 140,
    "shed_wall": 110, "shed_roof": 140,
}

# Patterns the surface shader draws on a kind (MapScenery.SURFACES): no blocks needed.
SURFACE = {
    "brick": "bricks", "brick_dark": "bricks", "stone_trim": "blocks_small", "ground": "dirt", "street": "tarmac",
    "pavement": "pavers", "platform": "pavers", "ballast": "gravel", "coal": "gravel", "tile": "checker",
    "floorboard": "planks", "timber": "planks", "bench": "planks", "crate": "planks", "crate_dark": "planks",
    "pallet": "planks", "wagon": "planks_upright", "water_tank": "planks_upright", "kiosk": "planks_upright",
    "shed_wall": "corrugated", "shed_roof": "corrugated", "canopy": "panels_plain", "train": "panels_plain",
    "loco": "panels_plain", "loco_yellow": "panels_plain", "wagon_grey": "plates", "tank": "plates",
    "train_floor": "plates", "roof": "tarmac", "concrete": "slabs", "backdrop": "windows", "backdrop_dark": "windows",
    "hazard": "hazard", "grille": "slats",
}

TRACKS = [-9.5, 0.5, 5.5, 15.5]          # track centre lines (z)
ISLANDS = [(-7, -2), (8, 13)]            # island platforms (z from, to)


def build(path):
    m = Map("RailYard", PAL,
            {"sky": {"sky_top_color": (0.3, 0.5, 0.82), "sky_horizon_color": (0.86, 0.84, 0.8),
                     "ground_bottom_color": (0.5, 0.47, 0.42), "ground_horizon_color": (0.8, 0.78, 0.74)},
             "lines": ["ambient_light_source = 2", "ambient_light_color = Color(0.78, 0.8, 0.88, 1)",
                       "ambient_light_energy = 0.7", "tonemap_mode = 2", "tonemap_white = 2.6",
                       "ssao_enabled = true", "glow_enabled = true"]},
            (48, 215, (1.0, 0.93, 0.82), 1.05),
            {"face_shade": "Vector3(0.93, 0.84, 0.66)", "kill_height": "-8.0",
             "bounds": "Rect2(-52, -46, 104, 92)", "swing_point": "Vector3(0, 9.6, 0)"})
    ground(m)
    tracks(m)
    platforms(m)
    station(m)
    footbridge(m)
    trains(m)
    gantries(m)
    yard(m)
    perimeter(m)
    details(m)
    spawns(m)
    pickups(m)
    m.write(path)
    palette(path.replace("game/maps/", "game/maps/palettes/").replace(".tscn", ".tres"), COLORS, GLOW, BREAKABLE, surface=SURFACE)


def ground(m):
    g = m.group("Ground")
    m.box(g, "Yard", "ground", (-60, -1, -50), (60, 0, 50))
    m.box(g, "Far", "ground", (-200, -1.2, -200), (200, -0.15, 200), tint=(0.92, 0.92, 0.9))
    m.box(g, "Street", "street", (-50, 0, -46), (50, 0.02, -40), solid=False)
    m.box(g, "Pavement", "pavement", (-50, 0, -40), (50, 0.12, -36.4))


def tracks(m):
    f = m.folder("Tracks")
    m.box(f, "Ballast", "ballast", (-50, 0, -12), (50, 0.1, 18))
    for i, z in enumerate(TRACKS):
        g = m.group("Track%d" % (i + 1), f)
        for side in (-0.72, 0.72):
            m.box(g, "Rail", "rail", (-50, 0.1, z + side - 0.06), (50, 0.26, z + side + 0.06), solid=False)
        x = -49.0
        while x < 50:
            m.box(g, "Sleeper", "sleeper", (x - 0.13, 0.1, z - 1.25), (x + 0.13, 0.16, z + 1.25), solid=False)
            x += 1.5


def platforms(m):
    f = m.folder("Platforms")
    # Platform 1 runs along the station front; the islands sit between the tracks.
    plats = [("Platform1", -16, -12, 44, "1")] + [("Platform%d" % (i + 2), z0, z1, 38, str(i + 2)) for i, (z0, z1) in enumerate(ISLANDS)]
    for name, z0, z1, half, label in plats:
        g = m.group(name, f)
        m.box(g, "Deck", "platform", (-half, 0, z0), (half, 1.0, z1))
        for zz in (z0, z1):
            if name == "Platform1" and zz == z0:
                continue
            inner = zz + (0.45 if zz == z0 else -0.45)
            m.box(g, "Edge", "platform_edge", (-half, 1.0, min(zz, inner) if zz == z0 else inner), (half, 1.02, inner if zz == z0 else zz), solid=False)
            t = inner + (0.25 if zz == z0 else -0.25)
            m.box(g, "Tactile", "tactile", (-half, 1.0, min(inner, t)), (half, 1.015, max(inner, t)), solid=False)
        for sx in (-1, 1):   # ramps down to the track bed at both ends
            a = (sx * half, 1.0, (z0 + z1) / 2)
            b = (sx * (half + 4.5), 0.1, (z0 + z1) / 2)
            m.slab(g, "EndRamp", "platform", a, b, z1 - z0, thick=0.6)
        # Benches and lamp posts along the middle.
        mid = (z0 + z1) / 2
        for x in range(-30, 31, 12):
            if abs(x) < 4 or (name != "Platform1" and abs(x) in (6, 18)) or (name == "Platform1" and abs(x) == 30):
                continue
            m.box(g, "Bench", "bench", (x - 1.2, 1.0, mid - 0.3), (x + 1.2, 1.45, mid + 0.3))
            m.box(g, "BenchBack", "bench", (x - 1.2, 1.45, mid - 0.06), (x + 1.2, 1.95, mid + 0.06), solid=False)
        for x in range(-36, 37, 12):
            if name == "Platform1":
                break
            if abs(x) <= 12:
                continue
            m.cyl(g, "LampPost", "iron", (x, 1.0, mid), 0.18, 3.2, sides=8, solid=False)
            m.box(g, "Lamp", "lamp", (x - 0.25, 4.0, mid - 0.25), (x + 0.25, 4.3, mid + 0.25), solid=False)
        # A name board at each end, clear of the canopy columns (platform 1's hang off the gantries).
        for x in ((-20, 20) if name == "Platform1" else (-20.5, 18.5 if name == "Platform2" else 16.5)):
            name_board(m, g, "PLATFORM " + label, x, 4.2, mid, name != "Platform1")
    # Canopies over the islands, kept clear of the footbridge stairs.
    for i, (z0, z1) in enumerate(ISLANDS):
        g = m.group("Canopy%d" % (i + 1), f)
        mid = (z0 + z1) / 2
        spans = [(-34, -3), (13, 34)] if i == 0 else [(-34, -13), (3, 34)]
        for (x0, x1) in spans:
            m.box(g, "Roof", "canopy", (x0, 5.5, z0 - 0.2), (x1, 5.8, z1 + 0.2))
            m.box(g, "Fascia", "iron", (x0, 5.2, z0 - 0.3), (x1, 5.8, z0 - 0.2), solid=False)
            m.box(g, "Fascia", "iron", (x0, 5.2, z1 + 0.2), (x1, 5.8, z1 + 0.3), solid=False)
            x = x0 + 1.5
            while x <= x1 - 1.4:
                m.box(g, "Column", "iron", (x - 0.15, 1.0, mid - 0.15), (x + 0.15, 5.5, mid + 0.15))
                m.box(g, "Bracket", "iron", (x - 0.1, 5.0, z0), (x + 0.1, 5.5, z1), solid=False)
                x += 8


def name_board(m, g, text, x, y, z, posts):
    """A sign board across a platform, lettered on both sides, on two slim posts of its
    own (or bracketed off the gantry post beside it). It does not hang from the canopy:
    that breaks."""
    m.strip(g, "NameBoard", "sign", (x - 2.45, y - 0.45, z - 0.05), (x + 2.45, y + 0.45, z + 0.05))
    m.strip(g, "NameBoardEdge", "paint", (x - 2.5, y - 0.5, z - 0.03), (x + 2.5, y + 0.5, z + 0.03))
    for sx in (-1.8, 1.8):
        if posts:
            m.strip(g, "NameBoardPost", "iron_dark", (x + sx * 1.39 - 0.05, 1.0, z - 0.06), (x + sx * 1.39 + 0.05, y + 0.58, z + 0.06))
        else:
            m.strip(g, "NameBoardArm", "iron_dark", (x + sx * 0.1 - 0.04, y + 0.2, z + 0.05), (x + sx * 0.1 + 0.04, y + 0.28, z + 0.5))
    m.sign(text, (x, y, z + 0.07), yaw=0, size=72, col=(1, 1, 1, 1), one_sided=True)
    m.sign(text, (x, y, z - 0.07), yaw=math.pi, size=72, col=(1, 1, 1, 1), one_sided=True)


def station(m):
    f = m.folder("Station")
    X0, X1, Z0, Z1 = -30, 30, -36, -16
    g = m.group("Hall", f)
    # (The floor stops at the walls' inside faces: in a doorway the wall's own sill is the floor.)
    m.box(g, "Concourse", "tile", (X0 + 0.4, 0, Z0 + 0.4), (X1 - 0.4, 1.0, Z1))
    for x in range(-28, 29, 4):   # darker tile bands
        m.box(g, "Band", "tile_dark", (x - 0.2, 1.0, Z0 + 0.5), (x + 0.2, 1.02, Z1 - 0.5), solid=False)
    # Front steps down to the street.
    m.stairs(g, "FrontSteps", (0, 0.12, -39.6), (0, 1.0, -36.4), 10, kind="stone_trim", rise=0.22, base=0)
    for sx in (-1, 1):
        m.box(g, "StepCheek", "brick_dark", (sx * 5 - 0.4, 0.12, -40), (sx * 5 + 0.4, 1.3, -36.4))
    # Outer walls (thick brick, they never break).
    T = 0.8
    m.wall(g, "NorthWall", "brick", (X0, Z0), (X1, Z0), 0, 13.6, T,
           holes=[(25, 35, 1.0, 5.5), (10, 14, 1.0, 4.0), (46, 50, 1.0, 4.0),
                  (4, 8, 8.0, 11.0), (18, 22, 8.0, 11.0), (38, 42, 8.0, 11.0), (52, 56, 8.0, 11.0)])
    for x0 in (4, 18, 38, 52):   # upper windows, glazed
        m.box(g, "Window", "glass", (X0 + x0, 8.0, Z0 - 0.05), (X0 + x0 + 4, 11.0, Z0 + 0.05))
    for x in (X0, X1):
        m.wall(g, "EndWall", "brick", (x, Z0), (x, Z1), 0, 13.6, T, holes=[(6, 10, 8.0, 11.0), (14, 18, 1.0, 4.2)])
        m.box(g, "EndWindow", "glass", (x - 0.05, 8.0, Z0 + 6), (x + 0.05, 11.0, Z0 + 10))
    # The platform side: a brick band with a clock over an open arcade of iron columns.
    m.wall(g, "FrontBand", "brick", (X0, Z1), (X1, Z1), 7.5, 13.6, 0.8, holes=[(27.5, 32.5, 7.5, 10.2)])
    m.box(g, "Cornice", "stone_trim", (X0 - 0.3, 13.6, Z1 - 0.6), (X1 + 0.3, 14.0, Z1 + 0.6))
    m.box(g, "Cornice", "stone_trim", (X0 - 0.3, 13.6, Z0 - 0.6), (X1 + 0.3, 14.0, Z0 + 0.6))
    m.cyl(g, "Clock", "clock", (0, 11.8, Z1 + 0.42), 2.6, 0.12, sides=24, solid=False, cols=((1, 0, 0), (0, 0, -1), (0, 1, 0)))
    for x in (-23, -17, -11, -5, 5, 11, 17, 23):
        m.box(g, "ArcadeColumn", "iron", (x - 0.25, 1.0, Z1 - 0.25), (x + 0.25, 7.5, Z1 + 0.25))
    for x0, x1 in ((-30, -26), (26, 30)):
        m.box(g, "Pier", "brick", (x0, 1.0, Z1 - 0.4), (x1, 7.5, Z1 + 0.4))
    m.sign("CENTRAL", (-14, 10.6, Z1 + 0.5), size=150, col=(0.97, 0.94, 0.86, 1), one_sided=True)
    m.sign("STATION", (14, 10.6, Z1 + 0.5), size=150, col=(0.97, 0.94, 0.86, 1), one_sided=True)
    for sx in (-1, 1):   # steps down from the end doors
        m.slab(g, "EndDoorRamp", "stone_trim", (sx * 30.4, 1.0, -20), (sx * 34.4, 0, -20), 4, thick=0.5)
    m.sign("CENTRAL STATION", (0, 6.6, Z0 - 0.5), yaw=math.pi, size=110, col=(0.97, 0.94, 0.86, 1), one_sided=True)

    # Mezzanine: z -36..-24 at 6.5 m, offices at both ends, a gallery in the middle.
    mz = m.group("Mezzanine", f)
    MZ = -24
    for (x0, x1) in ((X0, -14), (-14, 14), (14, X1)):
        m.box(mz, "Floor", "floorboard", (x0, 6.2, Z0), (x1, 6.5, MZ))
    m.box(mz, "Beam", "iron_dark", (X0, 5.7, MZ - 0.3), (X1, 6.2, MZ))
    for x in (-21, -7, 7, 21):
        m.box(mz, "Post", "iron", (x - 0.25, 1.0, MZ - 0.5), (x + 0.25, 5.7, MZ))
    # Glass railing along the edge, open where the stairs and the footbridge meet it.
    m.rail(mz, "Railing", "glass_rail", (X0, MZ - 0.06), (X1, MZ - 0.06), 6.5, 1.1, 0.12,
           holes=[(13.44, 16.0), (28, 32), (44.0, 46.56)])
    m.box(mz, "Handrail", "iron", (X0, 7.6, MZ - 0.02), (X1, 7.7, MZ + 0.14), solid=False)
    # Stairs up from the concourse (south of the mezzanine edge, with a landing at the top).
    for sx in (-1, 1):
        m.stairs(mz, "Stairs", (sx * 26, 1.0, -22.6), (sx * 16.5, 6.5, -22.6), 2.6, kind="stone_trim", side="iron", base=1.0)
        m.box(mz, "Landing", "floorboard", (min(sx * 16.5, sx * 14), 6.2, MZ - 0.01), (max(sx * 16.5, sx * 14), 6.5, -21.3), unbreakable=True)
        m.box(mz, "LandingPost", "iron", (sx * 15.25 - 0.2, 1.0, -21.7), (sx * 15.25 + 0.2, 6.2, -21.3))
    # Office partitions (plaster, they break) with doors.
    for x in (-14, 14):
        m.wall(mz, "Partition", "plaster", (x, Z0), (x, MZ - 0.12), 6.5, 13.0, 0.25, holes=[(7.0, 8.6, 6.5, 8.8)])
    for sx in (-1, 1):   # cubicle screens
        m.wall(mz, "Screen", "plaster", (sx * 26, -29.3), (sx * 17, -29.3), 6.5, 8.1, 0.12, holes=[(4, 5.5, 6.5, 8.1)])
    for (cx, cz) in ((-24, -31), (-18, -31), (24, -31), (18, -31), (-24, -27.5), (22, -27.5)):
        m.box(mz, "Desk", "timber", (cx - 1.0, 6.5, cz - 0.5), (cx + 1.0, 7.3, cz + 0.5))
    for cx in (-26.5, 26.5):
        m.box(mz, "Cabinet", "steel", (cx - 1.5, 6.5, Z0 + 0.4), (cx + 1.5, 8.3, Z0 + 1.0))
    # The gallery: benches and a café counter.
    m.box(mz, "Counter", "kiosk", (-6, 6.5, -31.5), (6, 7.6, -30.5))
    for x in (-9, 9):
        m.box(mz, "GalleryBench", "bench", (x - 1.5, 6.5, -29.5), (x + 1.5, 6.95, -28.9))
    # Stair to the roof, along the north wall, under a hatch.
    m.stairs(mz, "RoofStairs", (-8, 6.5, -34.4), (3.3, 13.6, -34.4), 2.4, kind="steel_dark", side="iron", base=6.5,
             cheeks=(False, True))
    m.rail(mz, "StairGuard", "iron", (-8, -33.1), (3.3, -33.1), 6.5, 1.1, 0.1)

    # Roof at 13 m, with a hatch over the roof stair and a skylight (glass, breakable) over the hall.
    r = m.group("Roof", f)
    # (The roof stops at the end walls' inside faces: the walls' tops are at the same height.)
    m.box(r, "RoofWest", "roof", (X0 + 0.4, 13.0, Z0), (-10, 13.6, Z1))
    m.box(r, "RoofEast", "roof", (10, 13.0, Z0), (X1 - 0.4, 13.6, Z1))
    m.box(r, "RoofMidNorth", "roof", (-10, 13.0, Z0), (-2.0, 13.6, -24))
    m.box(r, "RoofMidNorth", "roof", (-2.0, 13.0, -33.1), (10, 13.6, -24))
    m.box(r, "RoofHatchEnd", "roof", (3.3, 13.0, Z0), (10, 13.6, -33.1))
    m.box(r, "RoofMidSouth", "roof", (-10, 13.0, -18.5), (10, 13.6, Z1))
    for x0 in range(-10, 10, 4):
        m.box(r, "Skylight", "glass", (x0, 13.3, -24), (x0 + 4, 13.5, -18.5))
    for x0 in range(-10, 11, 4):
        m.box(r, "SkylightBar", "iron", (max(x0 - 0.1, -10), 13.0, -24), (min(x0 + 0.1, 10), 13.6, -18.5))
    m.rail(r, "HatchGuard", "iron", (-2.0, -33.0), (3.3, -33.0), 13.6, 1.0, 0.1)
    m.rail(r, "HatchGuard", "iron", (-2.05, Z0 + 0.4), (-2.05, -33.0), 13.6, 1.0, 0.1)
    for (x0, z0) in ((-26, -32), (18, -30)):
        m.box(r, "Vent", "steel", (x0, 13.6, z0), (x0 + 3, 15.2, z0 + 2.5))
    m.box(r, "ClockTower", "brick", (-3, 14.0, -18.5), (3, 18.5, -16.4))
    m.box(r, "ClockTowerCap", "stone_trim", (-3.4, 18.5, -18.9), (3.4, 19.0, -16.0))

    # Concourse furniture: ticket office (plaster walls), kiosks, benches.
    t = m.group("TicketOffice", f)
    m.wall(t, "Wall", "plaster", (-7, -33), (7, -33), 1.0, 4.4, 0.25, holes=[(9, 11, 1.0, 3.2)])
    m.wall(t, "Front", "plaster", (-7, -28.5), (7, -28.5), 1.0, 4.4, 0.25, holes=[(1, 5, 2.2, 3.4), (9, 13, 2.2, 3.4)])
    for x in (-7, 7):
        m.wall(t, "Side", "plaster", (x, -33), (x, -28.5), 1.0, 4.4, 0.25)
    m.box(t, "Roof", "floorboard", (-7.2, 4.4, -33.2), (7.2, 4.7, -28.3))
    m.box(t, "Counter", "timber", (-6.9, 1.0, -28.4), (6.9, 2.1, -27.9))
    m.sign("TICKETS", (0, 3.9, -28.3), size=64, col=(1, 0.86, 0.4, 1), one_sided=True)
    k = m.group("Kiosks", f)
    for cx in (-21, 21):
        m.box(k, "Kiosk", "kiosk", (cx - 2, 1.0, -31), (cx + 2, 3.4, -28))
        m.box(k, "Awning", "awning", (cx - 2.3, 3.4, -28.6), (cx + 2.3, 3.6, -27.4))
    for x in (-12, 12):
        m.box(k, "Bench", "bench", (x - 1.5, 1.0, -20.3), (x + 1.5, 1.45, -19.7))
    m.box(k, "Departures", "sign", (-4, 3.0, -23.4), (4, 5.2, -23.0), solid=False)
    m.sign("DEPARTURES", (0, 4.6, -22.9), size=48, col=(1, 0.86, 0.3, 1), one_sided=True)


def footbridge(m):
    """A covered footbridge from the mezzanine over all four tracks, with stairs down to
    the two island platforms and to the yard."""
    g = m.group("Footbridge")
    Z0, Z1 = -24, 20
    m.box(g, "Deck", "steel_dark", (-2, 6.1, Z0), (2, 6.5, Z1), unbreakable=True)
    # Side panels, open where the stairs arrive (platform 2 stair on the east, platform 3 on the west).
    m.wall(g, "EastSide", "iron", (2.05, -16), (2.05, Z1), 6.5, 7.6, 0.1, holes=[(10.3, 12.7, 6.5, 7.6)])
    m.wall(g, "WestSide", "iron", (-2.05, -16), (-2.05, Z1), 6.5, 7.6, 0.1, holes=[(25.3, 27.7, 6.5, 7.6)])
    m.box(g, "Roof", "canopy", (-2.4, 9.5, -16), (2.4, 9.8, Z1))
    z = -14.0
    while z <= Z1:
        for sx in (-1, 1):
            m.box(g, "RoofPost", "iron", (sx * 2.1 - 0.1, 6.5, z - 0.1), (sx * 2.1 + 0.1, 9.5, z + 0.1), solid=False)
        z += 4
    for (z0, z1) in ((-13.6, -12.4), (-4.9, -4.1), (10.1, 10.9), (19.0, 20.0)):
        for sx in (-1, 1):
            m.box(g, "Leg", "iron", (sx * 1.6 - 0.25, 0 if z0 > 18 else 1.0, z0), (sx * 1.6 + 0.25, 6.1, z1))
    # Stairs: platform 2 (east side), platform 3 (west side), down to the yard (south end).
    m.stairs(g, "StairsPlatform2", (12.2, 1.0, -4.5), (2.0, 6.5, -4.5), 2.4, kind="steel_dark", side="iron", base=1.0)
    m.stairs(g, "StairsPlatform3", (-12.2, 1.0, 10.5), (-2.0, 6.5, 10.5), 2.4, kind="steel_dark", side="iron", base=1.0)
    m.stairs(g, "StairsYard", (0, 0, 31.2), (0, 6.5, Z1), 4.0, kind="steel_dark", side="iron", base=0)
    m.sign("PLATFORMS 2 - 3", (0, 9.0, -15.9), size=56, col=(1, 1, 1, 1), one_sided=True)


def carriage(m, parent, name, x0, x1, z, doors=(0.2, 0.5, 0.8), tail=False):
    """A passenger carriage you can walk through: floor at 1 m (platform height), doors on
    both sides, open window bands, gangway doors at both ends."""
    g = m.group(name, parent)
    W = 1.5
    L = x1 - x0
    m.box(g, "Under", "steel_dark", (x0 + 1, 0.3, z - 1.1), (x1 - 1, 0.7, z + 1.1))
    for bx in (x0 + 3, x1 - 3):
        m.box(g, "Bogie", "steel_dark", (bx - 1.4, 0.1, z - 1.0), (bx + 1.4, 0.6, z + 1.0), solid=False)
    m.box(g, "Floor", "train_floor", (x0, 0.7, z - W), (x1, 1.0, z + W))
    holes = [(L * f - 0.8, L * f + 0.8, 1.0, 3.3) for f in doors]
    win = []
    u = 1.0
    while u < L - 1.0:
        if all(abs(u + 0.9 - L * f) > 1.9 for f in doors):
            win.append((u, u + 1.8, 2.0, 3.2))
        u += 2.4
    for side in (-1, 1):
        zz = z + side * (W - 0.08)
        m.wall(g, "Side", "train", (x0, zz), (x1, zz), 1.0, 4.0, 0.16, holes=sorted(holes + win))
        u = -0.04   # the stripe stops just short of each door, and wraps the ends a little
        for (h0, h1, _, _) in sorted(holes) + [(L + 0.06, L + 0.06, 0, 0)]:
            m.box(g, "Stripe", "train_stripe", (x0 + u + 0.02, 1.6, zz - 0.1), (x0 + h0 - 0.02, 1.75, zz + 0.1), solid=False)
            u = h1
        for fd in doors:   # door plates over the gap to the platform edge
            dx = x0 + L * fd
            za, zb = sorted((z + side * W, z + side * (W + 1.0)))
            m.box(g, "DoorPlate", "steel", (dx - 0.8, 0.85, za), (dx + 0.8, 1.0, zb))
    for xx in (x0 + 0.08, x1 - 0.08):
        m.wall(g, "End", "train", (xx, z - W), (xx, z + W), 1.0, 4.0, 0.16, holes=[(1.0, 2.0, 1.0, 3.2)])
    m.box(g, "Roof", "train_roof", (x0, 4.0, z - W - 0.05), (x1, 4.3, z + W + 0.05))
    # Details: door frames, a dark rail above and below the windows, roof ribs and vents.
    for side in (-1, 1):
        face = z + side * W
        starts = [x0] + [x0 + L * fd + 0.9 for fd in doors]
        ends = [x0 + L * fd - 0.9 for fd in doors] + [x1]
        for a, b in zip(starts, ends):
            for y in (1.9, 3.2):
                m.on_wall(g, "WindowRail", "window_dark", "x", face, side, a, b, y, y + 0.1, 0.025)
        for fd in doors:
            dx = x0 + L * fd
            for ex in (dx - 0.9, dx + 0.8):
                m.on_wall(g, "DoorFrame", "steel_dark", "x", face, side, ex, ex + 0.1, 1.0, 3.3, 0.03)
            m.on_wall(g, "DoorHead", "steel_dark", "x", face, side, dx - 0.9, dx + 0.9, 3.3, 3.42, 0.03)
    x = x0 + 1.5
    while x < x1 - 1:
        m.strip(g, "RoofRib", "steel", (x - 0.05, 4.3, z - W - 0.05), (x + 0.05, 4.34, z + W + 0.05))
        x += 3
    for side in (-1, 1):
        za, zb = sorted((z + side * 0.3, z + side * 0.6))
        m.strip(g, "RoofVent", "steel", (x0 + 2.5, 4.3, za), (x1 - 2.5, 4.4, zb))
    if tail:   # red lamps on the last carriage's end
        for dz in (-1.2, 0.95):
            m.on_wall(g, "TailLamp", "signal_red", "z", x0, -1, z + dz, z + dz + 0.25, 1.3, 1.55, 0.04)
    for u in range(4, int(L) - 3, 4):
        if all(abs(u - L * f) > 1.8 for f in doors):
            m.box(g, "Seat", "train_seat", (x0 + u - 0.8, 1.0, z - W + 0.2), (x0 + u + 0.8, 1.55, z - W + 0.7))
            m.box(g, "Seat", "train_seat", (x0 + u - 0.8, 1.0, z + W - 0.7), (x0 + u + 0.8, 1.55, z + W - 0.2))
    return g


def trains(m):
    f = m.folder("Trains")
    # Track 1: a passenger train you can run through between platforms 1 and 2.
    zA = TRACKS[0]
    for i, (x0, x1) in enumerate(((-38, -20), (-19, -1), (2, 20))):
        carriage(m, f, "Carriage%d" % (i + 1), x0, x1, zA, tail=(i == 0))
    loco(m, f, "Engine", 21, 37, zA, "loco", face=1)
    for (x0, x1) in ((-20, -19), (-1, 2)):
        m.box(f, "Gangway", "steel", (x0, 0.85, zA - 0.5), (x1, 1.0, zA + 0.5))
    # Track 2: a freight engine and box wagons at the east end.
    zB = TRACKS[1]
    loco(m, f, "FreightEngine", 6, 20, zB, "loco_yellow", face=-1)
    for i, x0 in enumerate((21, 34)):
        g = m.group("BoxWagon%d" % (i + 1), f)
        m.box(g, "Under", "steel_dark", (x0 + 0.5, 0.3, zB - 1.1), (x0 + 11.5, 0.8, zB + 1.1))
        m.box(g, "Body", "wagon", (x0, 0.8, zB - 1.5), (x0 + 12, 4.0, zB + 1.5))
        m.box(g, "Roof", "wagon_grey", (x0 - 0.1, 4.0, zB - 1.6), (x0 + 12.1, 4.25, zB + 1.6))
        m.box(g, "Door", "wagon_grey", (x0 + 4.5, 1.0, zB - 1.56), (x0 + 7.5, 3.8, zB + 1.56), solid=False)
        for side in (-1, 1):   # ribs along the body and the rail the door slides on
            for dx in (0.1, 1.5, 3.0, 8.9, 10.4, 11.8):
                m.on_wall(g, "Rib", "steel_dark", "x", zB + side * 1.5, side, x0 + dx, x0 + dx + 0.1, 0.8, 4.0, 0.04)
            m.on_wall(g, "DoorRail", "steel_dark", "x", zB + side * 1.5, side, x0 + 3.2, x0 + 8.9, 3.82, 3.94, 0.09)
    # Track 3: tank wagons at the west end.
    zC = TRACKS[2]
    for i, x0 in enumerate((-44, -31)):
        g = m.group("TankWagon%d" % (i + 1), f)
        m.box(g, "Frame", "steel_dark", (x0, 0.3, zC - 1.2), (x0 + 12, 1.0, zC + 1.2))
        m.lying_cyl(g, "Tank", "tank", (x0 + 6, 2.5, zC), 2.9, 11.0, axis="x", sides=16)
        m.cyl(g, "Dome", "tank", (x0 + 6, 3.8, zC), 1.2, 0.6, sides=12)
        m.box(g, "Walkway", "steel", (x0 + 1, 3.9, zC - 0.6), (x0 + 11, 4.0, zC + 0.6))
        for dx in (1.5, 4.5, 7.5, 10.5):   # hoops round the tank, and a ladder up its side
            m.pipe(g, "Hoop", "steel_dark", (x0 + dx - 0.07, 2.5, zC), (x0 + dx + 0.07, 2.5, zC), 3.02, sides=16, inner=2.9)
        for lx in (x0 + 5.6, x0 + 6.35):
            m.strip(g, "LadderRail", "steel", (lx, 1.0, zC + 1.47), (lx + 0.05, 3.95, zC + 1.52))
        for k in range(7):
            m.strip(g, "LadderRung", "steel", (x0 + 5.65, 1.3 + k * 0.4, zC + 1.48), (x0 + 6.35, 1.34 + k * 0.4, zC + 1.51))
    # Track 4: open coal wagons under the gantries.
    zD = TRACKS[3]
    for i, x0 in enumerate((-36, -24, 4, 16, 28)):
        g = m.group("CoalWagon%d" % (i + 1), f)
        m.box(g, "Under", "steel_dark", (x0 + 0.5, 0.3, zD - 1.1), (x0 + 10.5, 0.9, zD + 1.1))
        m.box(g, "Floor", "wagon_grey", (x0, 0.9, zD - 1.5), (x0 + 11, 1.4, zD + 1.5))
        for zz in (zD - 1.42, zD + 1.42):
            m.box(g, "Side", "wagon_grey", (x0, 1.4, zz - 0.08), (x0 + 11, 3.2, zz + 0.08))
        for xx in (x0 + 0.08, x0 + 10.92):
            m.box(g, "End", "wagon_grey", (xx - 0.08, 1.4, zD - 1.5), (xx + 0.08, 3.2, zD + 1.5))
        m.box(g, "Coal", "coal", (x0 + 0.3, 1.4, zD - 1.3), (x0 + 10.7, 2.6, zD + 1.3))
        for (a, b, h, za, zb) in ((1.2, 4.4, 0.16, -0.9, 0.7), (5.0, 8.0, 0.24, -0.6, 0.95), (8.3, 10.2, 0.2, -0.8, 0.5)):
            m.strip(g, "CoalHeap", "coal", (x0 + a, 2.6, zD + za), (x0 + b, 2.6 + h, zD + zb), tint=(1.25, 1.25, 1.3))
        for side in (-1, 1):
            for dx in (0.9, 3.9, 6.9, 9.9):
                m.on_wall(g, "Rib", "steel_dark", "x", zD + side * 1.5, side, x0 + dx, x0 + dx + 0.12, 1.4, 3.2, 0.04)
    # Buffer stops at the east ends of tracks 3 and 4.
    for z in (zC, zD):
        g = m.group("Buffer", f)
        m.box(g, "Stop", "steel_dark", (46, 0.1, z - 1.4), (47.5, 1.6, z + 1.4))
        m.box(g, "Beam", "loco_yellow", (45.6, 0.8, z - 1.5), (46, 1.3, z + 1.5))


def loco(m, parent, name, x0, x1, z, kind, face=1):
    """An engine: a cab at the front end (`face` +1 = east, -1 = west) and a long bonnet."""
    g = m.group(name, parent)
    m.box(g, "Under", "steel_dark", (x0 + 0.5, 0.3, z - 1.2), (x1 - 0.5, 1.0, z + 1.2))
    m.box(g, "Deck", "steel", (x0, 1.0, z - 1.5), (x1, 1.3, z + 1.5))
    cab = (x1 - 4.5, x1 - 0.5) if face > 0 else (x0 + 0.5, x0 + 4.5)
    hood = (x0 + 0.5, cab[0]) if face > 0 else (cab[1], x1 - 0.5)
    m.box(g, "Hood", kind, (hood[0], 1.3, z - 1.1), (hood[1], 3.6, z + 1.1))
    m.box(g, "Cab", kind, (cab[0], 1.3, z - 1.45), (cab[1], 4.3, z + 1.45))
    m.box(g, "CabRoof", "train_roof", (cab[0] - 0.1, 4.3, z - 1.5), (cab[1] + 0.1, 4.5, z + 1.5))
    wx = cab[1] if face > 0 else cab[0]
    m.box(g, "Windscreen", "window_dark", (wx - 0.06, 3.0, z - 1.2), (wx + 0.06, 4.0, z + 1.2), solid=False)
    for zz in (z - 1.47, z + 1.47):
        m.box(g, "CabWindow", "window_dark", (cab[0] + 0.6, 3.0, zz - 0.03), (cab[1] - 0.6, 3.9, zz + 0.03), solid=False)
    m.box(g, "Stripe", "loco_yellow" if kind != "loco_yellow" else "steel_dark", (x0, 1.3, z - 1.52), (x1, 1.55, z + 1.52), solid=False)
    # The cab's front: a striped panel under the windscreen with a headlamp either side.
    m.on_wall(g, "FrontPanel", "hazard", "z", wx, face, z - 1.3, z + 1.3, 1.5, 2.6, 0.07)
    for dz in (-1.05, 0.7):
        m.on_wall(g, "Headlamp", "lamp", "z", wx, face, z + dz, z + dz + 0.35, 2.65, 2.9, 0.1)
    # Grilles and a handrail along the bonnet, an exhaust on top, buffers at both ends.
    for side in (-1, 1):
        for (a, b) in ((hood[0] + 0.7, hood[0] + 3.4), (hood[1] - 3.4, hood[1] - 0.7)):
            m.on_wall(g, "Grille", "grille", "x", z + side * 1.1, side, a, b, 2.0, 3.2, 0.03)
        m.on_wall(g, "Handrail", "steel", "x", z + side * 1.1, side, hood[0] + 0.3, hood[1] - 0.3, 1.84, 1.9, 0.09)
    ex = (hood[0] + hood[1]) / 2 - face * 2.0
    m.pipe(g, "Exhaust", "steel_dark", (ex, 3.6, z), (ex, 4.1, z), 0.5)
    m.pipe(g, "ExhaustCap", "steel", (ex, 4.1, z), (ex, 4.18, z), 0.62)
    for (end, way) in ((x0, -1), (x1, 1)):
        for dz in (-0.85, 0.85):
            m.pipe(g, "Buffer", "steel_dark", (end, 1.15, z + dz), (end + way * 0.24, 1.15, z + dz), 0.24)
            m.pipe(g, "BufferHead", "steel", (end + way * 0.24, 1.15, z + dz), (end + way * 0.3, 1.15, z + dz), 0.44)


def gantries(m):
    """Overhead line gantries across the tracks: iron beams to grapple and walk along."""
    f = m.folder("Gantries")
    for x in (-36, -20, 20, 36):
        g = m.group("Gantry", f)
        m.box(g, "PostNorth", "iron", (x - 0.25, 1.0, -13.5), (x + 0.25, 8.2, -13.0))
        m.box(g, "PostSouth", "iron", (x - 0.25, 0, 18.6), (x + 0.25, 8.2, 19.1))
        m.box(g, "Beam", "iron", (x - 0.3, 7.6, -13.5), (x + 0.3, 8.2, 19.1))
        for z in TRACKS:
            m.box(g, "Dropper", "iron_dark", (x - 0.04, 6.2, z - 0.04), (x + 0.04, 7.6, z + 0.04), solid=False)
    w = m.group("Wires", f)
    for z in TRACKS:
        m.box(w, "Wire", "iron_dark", (-50, 6.15, z - 0.03), (50, 6.21, z + 0.03), solid=False)
        m.box(w, "Catenary", "iron_dark", (-50, 7.3, z - 0.03), (50, 7.36, z + 0.03), solid=False)
    # Signals on platform 1 and the yard side.
    for (x, z, col) in ((-44, -13, "signal_red"), (44, -13, "signal_green"), (-46, 18.8, "signal_green"), (46, 18.8, "signal_red")):
        g = m.group("Signal", f)
        base = 1.0 if z < 0 else 0.0
        m.box(g, "Post", "steel_dark", (x - 0.15, base, z - 0.15), (x + 0.15, base + 5.0, z + 0.15))
        m.box(g, "Head", "steel_dark", (x - 0.35, base + 5.0, z - 0.3), (x + 0.35, base + 6.4, z + 0.3))
        m.box(g, "Light", col, (x - 0.2, base + 5.8, z - 0.32), (x + 0.2, base + 6.2, z + 0.32), solid=False)


def crates(m, parent, name, x, z, layout):
    """A stack of 1.2 m crates: layout is a list of (dx, dz, height in crates)."""
    g = m.group(name, parent, at=(x, 0, z))
    for i, (dx, dz, h) in enumerate(layout):
        for k in range(h):
            kind = "crate" if (i + k) % 2 == 0 else "crate_dark"
            m.box(g, "Crate", kind, (dx - 0.6, k * 1.2, dz - 0.6), (dx + 0.6, (k + 1) * 1.2, dz + 0.6))
    return g


def yard(m):
    f = m.folder("Yard")
    # Goods shed: corrugated walls and roof (both break), loading office on a mezzanine.
    s = m.group("GoodsShed", f)
    SX0, SX1, SZ0, SZ1 = -44, -14, 24, 40
    m.box(s, "Floor", "concrete", (SX0, 0, SZ0), (SX1, 0.12, SZ1))
    m.wall(s, "NorthWall", "shed_wall", (SX0, SZ0), (SX1, SZ0), 0.12, 8.0, 0.3, holes=[(5, 10, 0.12, 5.0), (19, 24, 0.12, 5.0)])
    m.wall(s, "SouthWall", "shed_wall", (SX0, SZ1), (SX1, SZ1), 0.12, 8.0, 0.3, holes=[(13, 17, 1.5, 3.5)])
    m.wall(s, "WestWall", "shed_wall", (SX0, SZ0), (SX0, SZ1), 0.12, 8.0, 0.3, holes=[(4, 12, 4.8, 6.6)])
    m.wall(s, "EastWall", "shed_wall", (SX1, SZ0), (SX1, SZ1), 0.12, 8.0, 0.3, holes=[(5, 10, 0.12, 4.5)])
    for x0 in range(SX0, SX1, 6):
        m.box(s, "RoofPanel", "shed_roof", (x0, 8.0, SZ0 - 0.3), (x0 + 6, 8.3, SZ1 + 0.3))
    for x in range(SX0 + 6, SX1, 6):
        m.box(s, "Truss", "steel_dark", (x - 0.15, 7.2, SZ0), (x + 0.15, 8.0, SZ1))
        m.box(s, "Column", "steel_dark", (x - 0.2, 0.12, SZ0 + 0.15), (x + 0.2, 7.2, SZ0 + 0.55))
        m.box(s, "Column", "steel_dark", (x - 0.2, 0.12, SZ1 - 0.55), (x + 0.2, 7.2, SZ1 - 0.15))
    m.box(s, "OfficeFloor", "floorboard", (SX0, 3.7, 35), (-26, 4.0, SZ1))
    m.box(s, "OfficeBeam", "steel_dark", (SX0, 3.3, 34.7), (-26, 3.7, 35.1))
    for x in (-38, -32, -26.3):
        m.box(s, "OfficePost", "steel_dark", (x - 0.2, 0.12, 34.7), (x + 0.2, 3.3, 35.1))
    m.rail(s, "OfficeRail", "steel", (SX0, 35.05), (-26, 35.05), 4.0, 1.1, 0.1, holes=[(13.8, 16.0)])
    m.stairs(s, "OfficeStairs", (-29.1, 0.12, 27), (-29.1, 4.0, 35), 2.2, kind="steel_dark", side="steel", base=0.12)
    crates(m, s, "ShedCrates", -36, 29, [(0, 0, 2), (1.2, 0, 3), (2.4, 0, 1), (0, 1.2, 1), (1.2, 1.2, 2)])
    crates(m, s, "ShedCrates", -22, 30, [(0, 0, 1), (0, 1.2, 2), (1.2, 1.2, 1)])
    m.box(s, "Forklift", "loco_yellow", (-21, 0.12, 34), (-19, 2.2, 36.5))
    m.sign("GOODS", (-29, 6.4, SZ0 - 0.2), yaw=math.pi, size=120, col=(0.98, 0.9, 0.7, 1), one_sided=True)

    # Signal box: a brick ground floor and a glazed lookout room at 4 m, stairs on the east side.
    b = m.group("SignalBox", f)
    BX0, BX1, BZ0, BZ1 = 24, 32, 22, 28
    m.box(b, "Base", "brick", (BX0, 0, BZ0), (BX1, 3.7, BZ0 + 0.5))
    m.box(b, "Base", "brick", (BX0, 0, BZ1 - 0.5), (BX1, 3.7, BZ1))
    m.wall(b, "BaseWest", "brick", (BX0 + 0.25, BZ0 + 0.5), (BX0 + 0.25, BZ1 - 0.5), 0, 3.7, 0.5, holes=[(2, 3.4, 0, 2.6)])
    m.wall(b, "BaseEast", "brick", (BX1 - 0.25, BZ0 + 0.5), (BX1 - 0.25, BZ1 - 0.5), 0, 3.7, 0.5)
    m.box(b, "Floor", "floorboard", (BX0, 3.7, BZ0), (BX1, 4.0, BZ1), unbreakable=True)
    m.box(b, "Lookout", "timber", (BX0, 4.0, BZ0), (BX1, 5.0, BZ0 + 0.2))
    m.box(b, "Lookout", "timber", (BX0, 4.0, BZ1 - 0.2), (BX1, 5.0, BZ1))
    m.box(b, "LookoutWest", "timber", (BX0, 4.0, BZ0 + 0.2), (BX0 + 0.2, 5.0, BZ1 - 0.2))
    m.wall(b, "LookoutEast", "timber", (BX1 - 0.1, BZ0 + 0.2), (BX1 - 0.1, BZ1 - 0.2), 4.0, 5.0, 0.2, holes=[(0.6, 2.2, 4.0, 5.0)])
    m.box(b, "DoorFrame", "timber", (BX1 - 0.2, 6.6, BZ0 + 0.8), (BX1, 7.2, BZ0 + 2.4))
    m.box(b, "Glass", "glass", (BX0, 5.0, BZ0), (BX1, 7.2, BZ0 + 0.1))
    m.box(b, "Glass", "glass", (BX0, 5.0, BZ1 - 0.1), (BX1, 7.2, BZ1))
    m.box(b, "GlassWest", "glass", (BX0, 5.0, BZ0 + 0.1), (BX0 + 0.1, 7.2, BZ1 - 0.1))
    m.box(b, "Roof", "roof", (BX0 - 0.6, 7.2, BZ0 - 0.6), (BX1 + 0.6, 7.6, BZ1 + 0.6))
    m.box(b, "Levers", "signal_red", (BX0 + 1, 4.0, BZ0 + 2.6), (BX1 - 2.5, 4.9, BZ0 + 3.4))
    m.stairs(b, "Stairs", (33.4, 0, 32.4), (33.4, 4.0, 24.6), 2.2, kind="timber", side="timber", base=0)
    m.box(b, "Landing", "timber", (BX1, 3.7, BZ0), (34.6, 4.0, 24.6))
    m.box(b, "LandingPost", "timber", (34.2, 0, BZ0 + 0.1), (34.5, 3.7, BZ0 + 0.4))
    m.sign("SIGNAL BOX", (28, 4.5, BZ1 + 0.07), size=56, col=(1, 1, 1, 1), one_sided=True)

    # Water tower: four legs and a tank over a deck at 10 m (grapple up, or rocket-boot).
    w = m.group("WaterTower", f)
    cx, cz = 38, 35
    for dx in (-2.6, 2.6):
        for dz in (-2.6, 2.6):
            m.box(w, "Leg", "timber", (cx + dx - 0.3, 0, cz + dz - 0.3), (cx + dx + 0.3, 9.7, cz + dz + 0.3))
    m.box(w, "Brace", "timber", (cx - 2.6, 4.6, cz - 2.7), (cx + 2.6, 4.9, cz - 2.5), solid=False)
    m.box(w, "Brace", "timber", (cx - 2.6, 4.6, cz + 2.5), (cx + 2.6, 4.9, cz + 2.7), solid=False)
    m.box(w, "Deck", "timber", (cx - 4, 9.7, cz - 4), (cx + 4, 10.0, cz + 4))
    m.cyl(w, "Tank", "water_tank", (cx, 10.0, cz), 5.4, 4.6, sides=20)
    m.cyl(w, "Cap", "roof", (cx, 14.6, cz), 5.8, 0.4, sides=20)
    m.rail(w, "Rail", "timber", (cx - 4, cz - 3.95), (cx + 4, cz - 3.95), 10.0, 1.0, 0.1)
    m.rail(w, "Rail", "timber", (cx - 4, cz + 3.95), (cx + 4, cz + 3.95), 10.0, 1.0, 0.1)

    # Crates, pallets and a sleeper pile for cover across the yard.
    crates(m, f, "Crates", 8, 25, [(0, 0, 2), (1.2, 0, 1), (0, 1.2, 1)])
    crates(m, f, "Crates", -8, 24, [(0, 0, 1), (1.2, 0, 2), (2.4, 0, 1)])
    crates(m, f, "Crates", 14, 36, [(0, 0, 3), (1.2, 0, 2), (0, 1.2, 2), (1.2, 1.2, 1)])
    crates(m, f, "Crates", -7, 35, [(0, 0, 2), (0, 1.2, 1)])
    crates(m, f, "Crates", 44, 24, [(0, 0, 1), (0, 1.2, 2)])
    p = m.group("SleeperPile", f)
    for k in range(4):
        m.box(p, "Sleepers", "sleeper", (20, k * 0.3, 39 - k * 0.2), (27, (k + 1) * 0.3, 41 - k * 0.2))
    for (x, z) in ((-10, 29), (4, 39), (19, 30)):
        g = m.group("Pallet", f, at=(x, 0, z))
        m.box(g, "Pallet", "pallet", (-0.6, 0, -0.5), (0.6, 0.15, 0.5))
        m.box(g, "Sacks", "crate_dark", (-0.5, 0.15, -0.4), (0.5, 0.9, 0.4))


def perimeter(m):
    f = m.folder("Perimeter")
    g = m.group("Walls", f)
    for x in (-50, 50):
        # Track portals: dark tunnel mouths in the side walls.
        m.wall(g, "SideWall", "brick_dark", (x, -46), (x, 46), 0, 6.0, 1.0, holes=[(34, 64, 0, 6.0)])
        m.box(g, "Tunnel", "tunnel", (x - 0.4 if x < 0 else x + 0.4, 0, -12), (x - 1.0 if x < 0 else x + 1.0, 5.2, 18))
        m.box(g, "Arch", "stone_trim", (x - 0.6, 5.2, -12), (x + 0.6, 6.4, 18))
    m.box(g, "SouthWall", "brick_dark", (-50, 0, 45.5), (50, 6.0, 46.5))
    m.box(g, "NorthWall", "brick_dark", (-50, 0, -46.5), (50, 3.0, -45.5))
    # Town backdrop beyond the walls (out of reach).
    b = m.group("Backdrop", f)
    x = -60
    i = 0
    for (w, h) in ((14, 16), (10, 22), (18, 14), (12, 26), (16, 18), (11, 12), (20, 20), (13, 24), (9, 15)):
        kind = "backdrop" if i % 2 == 0 else "backdrop_dark"
        m.box(b, "Building", kind, (x, 0, -66), (x + w, h, -52))
        x += w + 1
        i += 1
    for (z0, z1, h) in ((-40, -16, 18), (22, 44, 14)):
        for sx in (-1, 1):
            m.box(b, "Building", "backdrop_dark", (sx * 58 - 6, 0, z0), (sx * 58 + 6, h, z1))
    for x in range(-56, 57, 14):
        m.box(b, "Warehouse", "backdrop", (x, 0, 54), (x + 12, 10, 66))


def spawns(m):
    pts = [
        # concourse
        ((-24, 1.0, -26), (0, -10)), ((24, 1.0, -26), (0, -10)), ((-10, 1.0, -34), (0, 0)), ((10, 1.0, -34), (0, 0)),
        # mezzanine and roof
        ((-22, 6.5, -34), (0, -10)), ((22, 6.5, -34), (0, -10)), ((-6, 6.5, -26.5), (0, 0)), ((24, 13.6, -20), (0, 0)),
        # platforms
        ((-33, 1.0, -14), (0, 0)), ((33, 1.0, -14), (0, 0)), ((-24, 1.0, -3.2), (0, 10)), ((28, 1.0, -3.2), (0, 10)),
        ((-28, 1.0, 10.5), (0, -10)), ((24, 1.0, 10.5), (0, -10)),
        # yard, shed, signal box
        ((-34, 0.12, 37.5), (0, 0)), ((-18, 0.12, 27), (0, 0)), ((-40, 4.0, 38), (0, 0)), ((30.6, 4.0, 26.6), (0, 0)),
        ((8, 0, 32), (0, 0)), ((40, 0, 28), (0, 0)), ((-4, 0, 42), (0, 0)), ((30, 0, 40), (0, 0)),
    ]
    for p, t in pts:
        m.spawn(p, t)


def pickups(m):
    for (p, w) in [
        ((0, 1.0, -26.5), "shotgun"), ((0, 6.5, -30), "lever_action"), ((-27, 6.5, -27.5), "revolver"),
        ((0, 13.6, -28), "railgun"), ((-9, 1.0, -14), "rifle"), ((0, 1.0, -4.5), "rifle"),
        ((0, 1.0, 10.5), "lmg"), ((-10, 4.3, TRACKS[0]), "sword"), ((28, 4.0, 24.6 - 1.4), "lever_action"),
        ((-33, 0.12, 32.5), "grenade_launcher"), ((-35, 4.0, 37.5), "hammer"), ((38, 10.0, 31.6), "rocket_launcher"),
        ((10, 0, 41), "burst_rifle"), ((0, 6.5, 6), "spear"), ((-42, 0.1, 0.5), "machine_pistol"),
    ]:
        m.weapon(p, w)


# ---------------------------------------------------------------------------
# Details. Everything below is drawn only, never solid, so nothing here changes where you
# can stand, what stops a shot or how a bot finds its way. Pieces on a wall stand at most
# 0.3 m off it; what stands further out is overhead or out of reach. On a wall or floor
# that breaks, a piece is either a thin "skin" lying flat on it (it then breaks with the
# wall) or keeps clear of it, so it never holds the wall up (see MapDestruction).

def details(m):
    station_details(m)
    platform_details(m)
    track_details(m)
    footbridge_details(m)
    yard_details(m)
    perimeter_details(m)


def wall_lamp(m, g, axis, face, out, u, y):
    """A lamp on a wall: a back plate, an arm and a lit box."""
    m.on_wall(g, "LampPlate", "iron_dark", axis, face, out, u - 0.12, u + 0.12, y - 0.1, y + 0.52, 0.05)
    m.on_wall(g, "LampArm", "iron_dark", axis, face, out, u - 0.04, u + 0.04, y + 0.36, y + 0.44, 0.3, lift=0.05)
    m.on_wall(g, "Lamp", "lamp", axis, face, out, u - 0.16, u + 0.16, y - 0.02, y + 0.36, 0.26, lift=0.14)


def window_trim(m, g, axis, face, out, u0, u1, y0, y1):
    """A stone sill and lintel round a window opening."""
    m.on_wall(g, "Sill", "stone_trim", axis, face, out, u0 - 0.3, u1 + 0.3, y0 - 0.3, y0 - 0.03, 0.18)
    m.on_wall(g, "Lintel", "stone_trim", axis, face, out, u0 - 0.3, u1 + 0.3, y1 + 0.03, y1 + 0.45, 0.14)


def glazing_bars(m, g, axis, mid, u0, u1, y0, y1, ups, levels, half=0.05, kind="iron_dark"):
    """Bars on both faces of a pane of glass (`mid` is the middle of the pane, `half` half
    its thickness). They are thin and lie flat on the glass, so they break with it."""
    for out in (-1, 1):
        for u in ups:
            m.on_wall(g, "GlazingBar", kind, axis, mid + out * half, out, u - 0.05, u + 0.05, y0, y1, 0.04)
        for y in levels:
            m.on_wall(g, "GlazingBar", kind, axis, mid + out * half, out, u0, u1, y - 0.05, y + 0.05, 0.04)


def hanging_lamp(m, g, x, y, z, top, size=0.22):
    """A lamp hung on a rod from whatever is at height `top`."""
    m.strip(g, "HangingLamp", "lamp", (x - size, y, z - size), (x + size, y + 0.34, z + size))
    m.strip(g, "LampCap", "iron_dark", (x - size - 0.06, y + 0.34, z - size - 0.06), (x + size + 0.06, y + 0.42, z + size + 0.06))
    m.strip(g, "LampRod", "iron_dark", (x - 0.03, y + 0.42, z - 0.03), (x + 0.03, top, z + 0.03))


def station_details(m):
    X0, X1, Z0, Z1 = -30, 30, -36, -16
    N, S, W, E = Z0 - 0.4, Z1 + 0.4, X0 - 0.4, X1 + 0.4      # the outside faces
    PIL = (0.88, 0.88, 0.88)
    g = m.group("Front", "Station")
    # The street front: a stone plinth, a string course, brick piers, stone round every
    # opening, lamps and drainpipes.
    for (a, b) in ((X0, -5.4), (5.4, X1)):
        m.on_wall(g, "Plinth", "stone_trim", "x", N, -1, a, b, 0.12, 0.96, 0.08)
    for (a, b) in ((X0, -7.0), (7.0, X1)):
        m.on_wall(g, "Course", "stone_trim", "x", N, -1, a, b, 7.0, 7.3, 0.1)
    for x in (-21, -14, -7, 7, 14, 21):
        m.on_wall(g, "Pier", "brick", "x", N, -1, x - 0.4, x + 0.4, 0.96, 13.6, 0.12, tint=PIL)
    for (x0, x1, y0, y1) in ((-26, -22, 8, 11), (-12, -8, 8, 11), (8, 12, 8, 11), (22, 26, 8, 11)):
        window_trim(m, g, "x", N, -1, x0, x1, y0, y1)
        glazing_bars(m, g, "x", Z0, x0, x1, y0, y1, (x0 + 1.33, x0 + 2.67), (9.95,))
    for sx in (-1, 1):
        a, b = sorted((sx * 5.0, sx * 5.5))
        m.on_wall(g, "DoorJamb", "stone_trim", "x", N, -1, a, b, 1.3, 5.5, 0.14)
        m.on_wall(g, "DoorHead", "stone_trim", "x", N, -1, sx * 18 - 2.3, sx * 18 + 2.3, 4.03, 4.4, 0.14)
        wall_lamp(m, g, "x", N, -1, sx * 6.1, 3.6)
        a, b = sorted((sx * 14.7, sx * 15.7))
        m.on_wall(g, "PosterFrame", "iron_dark", "x", N, -1, a - 0.06, b + 0.06, 1.54, 3.06, 0.03)
        m.on_wall(g, "Poster", "poster_red" if sx < 0 else "poster_blue", "x", N, -1, a, b, 1.6, 3.0, 0.05)
        m.on_wall(g, "PosterBand", "poster_cream", "x", N, -1, a + 0.12, b - 0.12, 2.5, 2.8, 0.07)
        m.pipe(g, "Drainpipe", "iron_dark", (sx * 28.6, 0.12, N - 0.1), (sx * 28.6, 13.55, N - 0.1), 0.16)
    m.on_wall(g, "DoorHead", "stone_trim", "x", N, -1, -5.6, 5.6, 5.5, 6.1, 0.18)
    m.on_wall(g, "SignBoard", "sign", "x", N, -1, -5.3, 5.3, 6.14, 7.06, 0.06)
    # The corners are stone, from the ground to the cornice.
    for sx in (-1, 1):
        a, b = sorted((sx * 29.95, sx * 30.45))
        m.strip(g, "Quoin", "stone_trim", (a, 0, N - 0.05), (b, 13.56, Z0 + 0.05))
        m.strip(g, "Quoin", "stone_trim", (a, 1.0, Z1 - 0.05), (b, 13.56, S + 0.05))
    # The two ends: the same plinth, course and piers, a lamp over each door.
    for sx in (-1, 1):
        face = sx * 30.4
        for (a, b) in ((Z0, -22.0), (-18.0, Z1)):
            m.on_wall(g, "Plinth", "stone_trim", "z", face, sx, a, b, 0, 0.96, 0.08)
        m.on_wall(g, "Course", "stone_trim", "z", face, sx, Z0, Z1, 7.0, 7.3, 0.1)
        for z in (-33, -24):
            m.on_wall(g, "Pier", "brick", "z", face, sx, z - 0.4, z + 0.4, 0.96, 13.6, 0.12, tint=PIL)
        window_trim(m, g, "z", face, sx, -30, -26, 8, 11)
        glazing_bars(m, g, "z", sx * 30, -30, -26, 8, 11, (-28.67, -27.33), (9.95,))
        m.on_wall(g, "DoorHead", "stone_trim", "z", face, sx, -22.3, -17.7, 4.23, 4.6, 0.14)
        wall_lamp(m, g, "z", face, sx, -20, 4.9)
    # The platform side: stone bands across the brick, a rim and hands for the clock, and
    # under it the arcade: a foot and a head on every column, brackets, a lamp in each bay.
    for (a, b) in ((X0, -2.5), (2.5, X1)):
        m.on_wall(g, "Band", "stone_trim", "x", S, 1, a, b, 7.5, 7.85, 0.1)
    m.on_wall(g, "Band", "stone_trim", "x", S, 1, X0, X1, 12.95, 13.25, 0.06)
    m.pipe(g, "ClockRim", "iron", (0, 11.86, S), (0, 11.86, S + 0.16), 3.0, sides=24, inner=2.6)
    m.rod(g, "ClockHand", "iron_dark", (0, 11.86, S + 0.11), (0, 12.9, S + 0.11), thick=0.1, wide=0.04)
    m.rod(g, "ClockHand", "iron_dark", (0, 11.86, S + 0.11), (0.62, 11.5, S + 0.11), thick=0.12, wide=0.04)
    a = m.group("Arcade", "Station")
    for x in (-23, -17, -11, -5, 5, 11, 17, 23):
        m.strip(a, "ColumnFoot", "iron_dark", (x - 0.4, 1.0, Z1 - 0.4), (x + 0.4, 1.28, Z1 + 0.4))
        m.strip(a, "ColumnHead", "iron_dark", (x - 0.42, 7.14, Z1 - 0.42), (x + 0.42, 7.5, Z1 + 0.42))
        for sx in (-1, 1):
            m.rod(a, "Bracket", "iron", (x + sx * 0.25, 6.25, Z1), (x + sx * 1.3, 7.46, Z1), thick=0.1, wide=0.14)
    for x in (-20, -14, -8, 8, 14, 20):
        hanging_lamp(m, a, x, 6.5, Z1, 7.5)
    # On the roof: clock faces and louvres on the tower, a flag over it.
    r = m.group("TowerDetails", "Station")
    for (face, out) in ((-16.4, 1), (-18.5, -1)):
        m.pipe(r, "TowerClock", "clock", (0, 16.3, face), (0, 16.3, face + out * 0.08), 2.0, sides=20)
        m.pipe(r, "TowerClockRim", "iron", (0, 16.3, face), (0, 16.3, face + out * 0.13), 2.3, sides=20, inner=2.0)
        m.rod(r, "ClockHand", "iron_dark", (0, 16.3, face + out * 0.1), (0, 17.1, face + out * 0.1), thick=0.08, wide=0.03)
        m.rod(r, "ClockHand", "iron_dark", (0, 16.3, face + out * 0.1), (out * 0.5, 16.0, face + out * 0.1), thick=0.1, wide=0.03)
    for sx in (-1, 1):
        m.on_wall(r, "Louvre", "grille", "z", sx * 3, sx, -18.0, -16.9, 15.2, 17.5, 0.05)
    m.pipe(r, "FlagPole", "iron_dark", (0, 19.0, -17.45), (0, 23.0, -17.45), 0.12)
    m.strip(r, "Flag", "awning", (0.06, 21.7, -17.47), (1.9, 22.8, -17.43))
    m.strip(r, "FlagBand", "paint", (0.04, 22.1, -17.495), (1.93, 22.4, -17.405))

    # Inside. Joists under the mezzanine floor (thin, flat against it: they break with it),
    # lamps hung under it, timetables on the wall, the kiosks' hatches and striped awnings.
    i = m.group("HallDetails", "Station")
    for x in range(-27, 28, 3):
        m.strip(i, "Joist", "iron_dark", (x - 0.1, 6.08, Z0 + 0.4), (x + 0.1, 6.2, -24.3))
    for x in (-24, -12, 12, 24):
        hanging_lamp(m, i, x, 5.1, -30, 6.08, size=0.25)
    IN = Z0 + 0.4
    for sx in (-1, 1):
        a, b = sorted((sx * 21.5, sx * 25.5))
        m.on_wall(i, "TimetableFrame", "timber", "x", IN, 1, a - 0.1, b + 0.1, 1.9, 3.8, 0.04)
        m.on_wall(i, "Timetable", "sign", "x", IN, 1, a, b, 2.0, 3.7, 0.07)
        for k in range(5):
            m.on_wall(i, "TimetableRow", "paint", "x", IN, 1, a + 0.25, b - 0.3 - (k * 7 % 5) * 0.3, 2.25 + k * 0.28, 2.37 + k * 0.28, 0.09)
    m.on_wall(i, "WayOutBoard", "sign", "x", IN, 1, -1.7, 1.7, 5.6, 6.04, 0.05)
    m.sign("WAY OUT", (0, 5.82, IN + 0.07), size=40, col=(1, 0.86, 0.3, 1), one_sided=True)
    for cx in (-21, 21):
        m.on_wall(i, "KioskHatch", "window_dark", "x", -28, 1, cx - 1.5, cx + 1.5, 2.0, 3.1, 0.03)
        m.on_wall(i, "KioskShelf", "timber", "x", -28, 1, cx - 1.6, cx + 1.6, 1.88, 2.0, 0.22)
        for (dx, kind) in ((-1.3, "poster_cream"), (0.55, "poster_red")):
            m.on_wall(i, "KioskPoster", kind, "x", -28, 1, cx + dx, cx + dx + 0.75, 1.15, 1.75, 0.03)
        for k in range(6):
            x = cx - 2.2 + k * 0.8
            m.strip(i, "AwningStripe", "paint", (x, 3.6, -28.6), (x + 0.4, 3.62, -27.4))
            m.on_wall(i, "AwningStripe", "paint", "x", -27.4, 1, x, x + 0.4, 3.4, 3.6, 0.02)
    # The ticket office: a board behind its sign and frames round its windows (skins of the
    # plaster wall), and the departures board's brackets and rows.
    FR = -28.375
    m.on_wall(i, "TicketBoard", "sign", "x", FR, 1, -1.5, 1.5, 3.5, 4.3, 0.04)
    for (a, b) in ((-6, -2), (2, 6)):
        m.on_wall(i, "TicketFrame", "timber", "x", FR, 1, a, b, 3.4, 3.5, 0.05)
        m.on_wall(i, "TicketFrame", "timber", "x", FR, 1, a, b, 2.1, 2.2, 0.05)
        m.on_wall(i, "TicketFrame", "timber", "x", FR, 1, a - 0.1, a, 2.1, 3.5, 0.05)
        m.on_wall(i, "TicketFrame", "timber", "x", FR, 1, b, b + 0.1, 2.1, 3.5, 0.05)
    for sx in (-3, 3):
        m.rod(i, "BoardBracket", "iron_dark", (sx, 5.2, -23.2), (sx, 5.95, -24.02), thick=0.07)
    for k, (a, b) in enumerate(((-3.5, -1.2), (-3.5, -0.4), (-3.5, -1.8), (0.4, 3.5), (1.2, 3.5), (0.4, 2.6))):
        y = 3.3 + (k % 3) * 0.36
        m.on_wall(i, "DepartureRow", "platform_edge", "x", -23.0, 1, a, b, y, y + 0.14, 0.03)
    for x in (-12, 12):
        for e in (-1.5, 1.5):
            m.strip(i, "BenchArm", "iron_dark", (x + e - 0.04, 1.0, -20.34), (x + e + 0.04, 1.72, -19.66))


def platform_details(m):
    plats = [("Platform1", -16, -12, (-18, -6, 6, 18))] + [("Platform%d" % (i + 2), z0, z1, (-30, 30)) for i, (z0, z1) in enumerate(ISLANDS)]
    for name, z0, z1, benches in plats:
        g = m.group("Details", "Platforms/" + name)
        mid = (z0 + z1) / 2
        for x in benches:
            for e in (-1.2, 1.2):
                m.strip(g, "BenchArm", "iron_dark", (x + e - 0.04, 1.0, mid - 0.34), (x + e + 0.04, 1.75, mid + 0.34))
        # "MIND THE GAP", painted inside the yellow line where the carriage doors are.
        for zz in (z0, z1):
            if name == "Platform1" and zz == z0:
                continue
            for x in (-11, 11):
                m.sign("MIND THE GAP", (x, 1.02, zz + (1.05 if zz == z0 else -1.05)), yaw=0 if zz == z0 else math.pi,
                       size=40, col=(0.96, 0.8, 0.18, 1), outline=False, flat=True)
        if name == "Platform1":
            continue
        for x in (-36, -24, 24, 36):
            m.pipe(g, "LampPostFoot", "iron_dark", (x, 1.0, mid), (x, 1.3, mid), 0.36)
    for i, (z0, z1) in enumerate(ISLANDS):
        g = m.group("Details", "Platforms/Canopy%d" % (i + 1))
        mid = (z0 + z1) / 2
        spans = [(-34, -3), (13, 34)] if i == 0 else [(-34, -13), (3, 34)]
        k = 0
        for (x0, x1) in spans:
            # A pale band along the bottom of each fascia.
            m.on_wall(g, "FasciaBand", "paint", "x", z0 - 0.3, -1, x0, x1, 5.2, 5.34, 0.03)
            m.on_wall(g, "FasciaBand", "paint", "x", z1 + 0.3, 1, x0, x1, 5.2, 5.34, 0.03)
            x = x0 + 1.5
            while x <= x1 - 1.4:
                m.strip(g, "ColumnFoot", "iron_dark", (x - 0.25, 1.0, mid - 0.25), (x + 0.25, 1.35, mid + 0.25))
                m.strip(g, "ColumnHead", "iron_dark", (x - 0.25, 4.82, mid - 0.25), (x + 0.25, 5.0, mid + 0.25))
                zl = mid + (1.6 if k % 2 == 0 else -1.6)   # a lamp under the bracket, on alternate sides
                m.strip(g, "CanopyLamp", "lamp", (x - 0.3, 4.72, zl - 0.12), (x + 0.3, 4.84, zl + 0.12))
                m.strip(g, "CanopyLampRod", "iron_dark", (x - 0.025, 4.84, zl - 0.025), (x + 0.025, 5.0, zl + 0.025))
                x += 8
                k += 1


def track_details(m):
    g = m.group("Weeds", "Tracks")
    for i in range(72):   # tufts of weed in the ballast, scattered the same way every time
        z = TRACKS[i % 4] + (-1.08, 1.1, 0.02, -0.34, 0.4, 1.02)[(i * 5 + i // 4) % 6]
        x = -47.3 + ((i * 29 + (i // 7) * 13) % 94) + 0.37 * (i % 3)
        s_ = (0.1, 0.14, 0.18)[i % 3]
        m.strip(g, "Weed", "plant", (x - s_, 0.1, z - s_), (x + s_, 0.1 + s_ * 1.4, z + s_), tint=(1, 1, 1) if i % 2 else (0.82, 0.9, 0.8))
    g = m.group("BufferLamps", "Tracks")
    for z in (TRACKS[2], TRACKS[3]):
        m.strip(g, "BufferLamp", "signal_red", (46.3, 1.6, z - 0.12), (46.54, 1.8, z + 0.12))
        m.on_wall(g, "BufferStripes", "hazard", "z", 45.6, -1, z - 1.5, z + 1.5, 0.8, 1.3, 0.03)


def footbridge_details(m):
    g = m.group("Details", "Footbridge")
    # A cap on each side panel (stopping where the stairs come up), a fascia under the
    # roof's edges, a gusset each side of every roof post and lamps under the roof.
    for (sx, gaps) in ((1, [(-5.7, -3.3)]), (-1, [(9.3, 11.7)])):
        z = -16.0
        for (g0, g1) in gaps + [(20.0, 20.0)]:
            m.strip(g, "PanelCap", "iron_dark", (sx * 2.05 - 0.09, 7.6, z), (sx * 2.05 + 0.09, 7.66, g0))
            z = g1
        a, b = sorted((sx * 2.4, sx * 2.46))
        m.strip(g, "Fascia", "iron", (a, 9.26, -16), (b, 9.5, 20))
        z = -14.0
        while z <= 20:
            for way in (-1, 1):
                if -16 < z + way * 0.6 < 20:
                    m.rod(g, "Gusset", "iron", (sx * 2.1, 8.8, z + way * 0.1), (sx * 2.1, 9.36, z + way * 0.62), thick=0.06)
            z += 4
    for z in (-12, -4, 4, 12):
        m.strip(g, "Lamp", "lamp", (-0.3, 9.4, z - 0.15), (0.3, 9.5, z + 0.15))
    m.strip(g, "SignBoard", "sign", (-2.36, 8.6, -16.0), (2.36, 9.4, -15.94))
    f = m.group("GantryDetails", "Gantries")
    for x in (-36, -20, 20, 36):
        m.rod(f, "Brace", "iron", (x, 6.5, -13.0), (x, 7.6, -11.7), thick=0.12, wide=0.14)
        m.rod(f, "Brace", "iron", (x, 6.5, 18.6), (x, 7.6, 17.3), thick=0.12, wide=0.14)
        for z in TRACKS:
            m.pipe(f, "Insulator", "paint", (x, 6.5, z), (x, 6.85, z), 0.22)


def yard_details(m):
    # Goods shed. Its walls and roof break, so everything on them is a thin skin or stands clear.
    g = m.group("Details", "Yard/GoodsShed")
    SX0, SX1, SZ0, SZ1 = -44, -14, 24, 40
    NF = SZ0 - 0.15
    for (a, b) in ((-33.9, -29.2), (-19.9, -15.2)):   # the doors, slid open along the wall
        m.on_wall(g, "SlidingDoor", "wagon_grey", "x", NF, -1, a, b, 0.2, 5.0, 0.08)
    for door in (-39, -25):   # the track they hang from, a length to each wall panel so it breaks with it
        for (a, b) in ((door - 0.4, door), (door, door + 5), (door + 5, door + 10)):
            m.on_wall(g, "DoorTrack", "steel_dark", "x", NF, -1, a, b, 5.04, 5.16, 0.14)
    for x in (-36.5, -22.5):
        wall_lamp(m, g, "x", NF, -1, x, 5.6)
        m.strip(g, "DoorLine", "hazard", (x - 2.5, 0.12, SZ0 + 0.16), (x + 2.5, 0.14, SZ0 + 0.7))
        m.strip(g, "DoorLine", "hazard", (x - 2.5, 0, SZ0 - 1.0), (x + 2.5, 0.02, SZ0 - 0.16))
    m.strip(g, "DoorLine", "hazard", (SX1 - 0.7, 0.12, 29), (SX1 - 0.16, 0.14, 34))
    for x0 in range(SX0, SX1, 6):   # a vent along the ridge, one length to each roof panel
        m.strip(g, "RidgeVent", "steel_dark", (x0 + 0.4, 8.3, 31.4), (x0 + 5.6, 8.42, 32.6))
    for x in range(SX0 + 6, SX1, 6):
        m.strip(g, "TrussLamp", "lamp", (x - 0.2, 7.06, 31.4), (x + 0.2, 7.2, 32.6))
    # The forklift: wheels, a mast, forks and a cage over the seat.
    f = m.group("ForkliftDetails", "Yard/GoodsShed")
    for x in (-21, -19):
        for z in (34.5, 36.0):
            a, b = sorted((x, x + (-0.12 if x < -20 else 0.12)))
            m.pipe(f, "Wheel", "tank", (a, 0.47, z), (b, 0.47, z), 0.7, sides=10)
    for x in (-20.7, -19.4):
        m.strip(f, "Mast", "steel_dark", (x, 0.12, 36.5), (x + 0.1, 3.3, 36.62))
        m.strip(f, "Fork", "steel", (x - 0.05, 0.16, 36.62), (x + 0.15, 0.24, 37.7))
    m.strip(f, "MastBar", "steel_dark", (-20.7, 3.1, 36.5), (-19.3, 3.3, 36.6))
    m.strip(f, "Seat", "window_dark", (-20.6, 2.2, 34.4), (-19.4, 2.24, 35.6))
    for (x, z) in ((-20.95, 34.05), (-19.05, 34.05), (-20.95, 36.0), (-19.05, 36.0)):
        m.strip(f, "CagePost", "steel_dark", (x - 0.04, 2.2, z - 0.04), (x + 0.04, 3.05, z + 0.04))
    m.strip(f, "CageTop", "steel_dark", (-21.02, 3.05, 34.0), (-18.98, 3.12, 36.06))

    # Signal box: bars on its windows, a name board, a stove pipe, a lamp by the door.
    b = m.group("Details", "Yard/SignalBox")
    BX0, BX1, BZ0, BZ1 = 24, 32, 22, 28
    glazing_bars(m, b, "x", BZ0 + 0.05, BX0, BX1, 5.0, 7.2, (26, 28, 30), (6.1,))
    glazing_bars(m, b, "x", BZ1 - 0.05, BX0, BX1, 5.0, 7.2, (26, 28, 30), (6.1,))
    glazing_bars(m, b, "z", BX0 + 0.05, BZ0 + 0.1, BZ1 - 0.1, 5.0, 7.2, (24, 26), (6.1,))
    m.on_wall(b, "NameBoard", "sign", "x", BZ1, 1, 26.1, 29.9, 4.15, 4.85, 0.05)
    m.pipe(b, "StovePipe", "iron_dark", (30.6, 7.6, 23.4), (30.6, 8.7, 23.4), 0.3)
    m.pipe(b, "StovePipeCap", "iron_dark", (30.6, 8.7, 23.4), (30.6, 8.8, 23.4), 0.5)
    m.on_wall(b, "Gutter", "iron_dark", "x", BZ0 - 0.6, -1, BX0 - 0.6, BX1 + 0.6, 7.22, 7.4, 0.08)
    m.on_wall(b, "Gutter", "iron_dark", "x", BZ1 + 0.6, 1, BX0 - 0.6, BX1 + 0.6, 7.22, 7.4, 0.08)
    wall_lamp(m, b, "z", BX0, -1, 26.6, 2.75)

    # Water tower: hoops round the tank, braces between the legs above head height, a
    # ladder, a spout.
    w = m.group("Details", "Yard/WaterTower")
    cx, cz = 38, 35
    for y in (10.7, 12.3, 13.9):
        m.pipe(w, "Hoop", "iron_dark", (cx, y, cz), (cx, y + 0.14, cz), 5.52, sides=20, inner=5.4)
    for d in (-2.6, 2.6):
        m.rod(w, "CrossBrace", "timber", (cx - 2.6, 5.1, cz + d), (cx + 2.6, 9.5, cz + d), thick=0.16, wide=0.12)
        m.rod(w, "CrossBrace", "timber", (cx + 2.6, 5.1, cz + d), (cx - 2.6, 9.5, cz + d), thick=0.16, wide=0.1)
        m.rod(w, "CrossBrace", "timber", (cx + d, 5.1, cz - 2.6), (cx + d, 9.5, cz + 2.6), thick=0.16, wide=0.12)
        m.rod(w, "CrossBrace", "timber", (cx + d, 5.1, cz + 2.6), (cx + d, 9.5, cz - 2.6), thick=0.16, wide=0.1)
    for lx in (cx - 0.3, cx + 0.25):
        m.strip(w, "LadderRail", "iron_dark", (lx, 10.0, cz - 2.82), (lx + 0.05, 14.9, cz - 2.76))
    for k in range(12):
        m.strip(w, "LadderRung", "iron_dark", (cx - 0.25, 10.3 + k * 0.38, cz - 2.81), (cx + 0.25, 10.34 + k * 0.38, cz - 2.77))
    m.pipe(w, "Spout", "iron_dark", (cx - 2.2, 10.9, cz - 1.9), (cx - 4.6, 9.3, cz - 4.1), 0.32)
    m.pipe(w, "Finial", "iron_dark", (cx, 15.0, cz), (cx, 15.7, cz), 0.5, sides=6)

    # The yard's ground: oil stains and weeds.
    y = m.group("Ground", "Yard")
    for k, (x, z, a, b) in enumerate(((2, 28, 1.6, 1.0), (16, 30, 1.2, 1.5), (-4, 38, 1.8, 0.9), (30, 34, 1.3, 1.1),
                                      (42, 32, 1.0, 1.4), (-9, 43, 1.5, 0.8), (22, 44, 1.2, 0.9), (0, 22.5, 1.4, 0.7))):
        m.strip(y, "Stain", "stain", (x - a, 0, z - b), (x + a, 0.02, z + b))
        m.strip(y, "Stain", "stain", (x - a * 0.5, 0, z - b * 1.5), (x + a * 0.7, 0.02, z + b * 0.4))
    for i in range(34):
        x = -47 + (i * 37 % 95)
        s_ = (0.12, 0.16, 0.2)[i % 3]
        m.strip(y, "Weed", "plant", (x - s_, 0, 45.5 - s_ * 2 - 0.02), (x + s_, s_ * 1.5, 45.5 - 0.02), tint=(1, 1, 1) if i % 2 else (0.82, 0.9, 0.8))


def perimeter_details(m):
    g = m.group("WallDetails", "Perimeter")
    PIL = (0.86, 0.86, 0.86)
    # Brick piers and a stone course on the inside of the yard walls.
    for x in range(-44, 45, 8):
        m.on_wall(g, "Pier", "brick_dark", "x", 45.5, -1, x - 0.45, x + 0.45, 0, 6.0, 0.15, tint=PIL)
        m.on_wall(g, "Pier", "brick_dark", "x", -45.5, 1, x - 0.45, x + 0.45, 0, 3.0, 0.15, tint=PIL)
    m.on_wall(g, "Course", "stone_trim", "x", 45.5, -1, -49.5, 49.5, 5.5, 5.75, 0.08)
    m.on_wall(g, "Course", "stone_trim", "x", -45.5, 1, -49.5, 49.5, 2.6, 2.85, 0.08)
    for sx in (-1, 1):
        face = sx * 49.5
        for z in (-40, -32, -24, -16, 22, 30, 38):
            m.on_wall(g, "Pier", "brick_dark", "z", face, -sx, z - 0.45, z + 0.45, 0, 6.0, 0.15, tint=PIL)
        for (a, b) in ((-45.5, -12.5), (18.5, 45.5)):
            m.on_wall(g, "Course", "stone_trim", "z", face, -sx, a, b, 5.5, 5.75, 0.08)
        # The tunnel mouths: stone down both sides, a keystone, and a signal lamp over each track.
        for (a, b) in ((-12.5, -12.0), (18.0, 18.5)):
            m.on_wall(g, "PortalStone", "stone_trim", "z", face, -sx, a, b, 0, 5.2, 0.1)
        m.on_wall(g, "Keystone", "stone_trim", "z", sx * 49.4, -sx, 2.4, 3.6, 5.1, 6.5, 0.08)
        for k, z in enumerate(TRACKS):
            lit = "signal_green" if (k + (sx > 0)) % 2 == 0 else "signal_red"
            m.on_wall(g, "PortalLampBox", "steel_dark", "z", sx * 49.4, -sx, z - 0.3, z + 0.3, 5.45, 6.15, 0.12)
            m.on_wall(g, "PortalLamp", lit, "z", sx * 49.4, -sx, z - 0.14, z + 0.14, 5.66, 5.94, 0.04, lift=0.12)

    # The street in front of the station: a centre line, a crossing to the steps, lamps on
    # the far pavement.
    s = m.group("Street", "Perimeter")
    x = -47.0
    while x < 47:
        if abs(x + 1.5) > 6:
            m.strip(s, "CentreLine", "paint", (x, 0.02, -43.1), (x + 3, 0.04, -42.9))
        x += 6
    for k in range(7):
        m.strip(s, "Crossing", "paint", (-3.85 + k * 1.1, 0.02, -45.4), (-3.15 + k * 1.1, 0.04, -40.1))
    for x in range(-40, 41, 16):
        m.pipe(s, "StreetLampPost", "iron_dark", (x, 0, -48.2), (x, 6.2, -48.2), 0.2)
        m.strip(s, "StreetLampArm", "iron_dark", (x - 0.06, 6.1, -48.2), (x + 0.06, 6.22, -46.9))
        m.strip(s, "StreetLamp", "lamp", (x - 0.22, 5.9, -47.3), (x + 0.22, 6.1, -46.8))

    # The town beyond: a flat roof on every building with something standing on it, and two
    # factory chimneys.
    b = m.group("Roofs", "Perimeter")
    x = -60
    for i, (w, h) in enumerate(((14, 16), (10, 22), (18, 14), (12, 26), (16, 18), (11, 12), (20, 20), (13, 24), (9, 15))):
        m.strip(b, "Parapet", "backdrop_dark" if i % 2 == 0 else "backdrop", (x - 0.2, h - 0.5, -66.2), (x + w + 0.2, h + 0.5, -51.8), tint=(0.8, 0.8, 0.82))
        if i % 3 == 0:
            m.strip(b, "StairHead", "brick_dark", (x + 2, h + 0.5, -62), (x + 5.5, h + 3.4, -58))
        elif i % 3 == 1:
            m.pipe(b, "RoofTank", "water_tank", (x + w / 2, h + 0.5, -58), (x + w / 2, h + 4.2, -58), 3.6, sides=12)
            m.pipe(b, "RoofTankCap", "roof", (x + w / 2, h + 4.2, -58), (x + w / 2, h + 4.6, -58), 4.0, sides=12)
        else:
            for dx in (2.5, w - 3.5):
                m.strip(b, "Chimney", "brick_dark", (x + dx, h + 0.5, -56.5), (x + dx + 1.2, h + 3.6, -55.3))
        x += w + 1
    for x in range(-56, 57, 14):   # sawtooth roofs on the warehouses
        for k in range(3):
            m.slab(b, "RoofLight", "roof", (x + k * 4, 12.0, 60), (x + k * 4 + 3.8, 10.0, 60), 11.6, thick=0.3, solid=False)
            m.strip(b, "RoofLightGlass", "glass", (x + k * 4 - 0.04, 10.0, 54.4), (x + k * 4 + 0.12, 11.9, 65.6))
    for (x, z, h) in ((70, 52, 34), (-72, 30, 30)):
        m.pipe(b, "Stack", "brick_dark", (x, 0, z), (x, h, z), 4.2, sides=12)
        m.pipe(b, "StackBand", "stone_trim", (x, h - 3, z), (x, h - 2.2, z), 4.5, sides=12)
        m.pipe(b, "StackTop", "stone_trim", (x, h, z), (x, h + 0.8, z), 4.6, sides=12)
