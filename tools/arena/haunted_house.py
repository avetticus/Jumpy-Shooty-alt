"""Haunted House: a very small two-storey house at midnight, all inside, for close-quarters
fights (up to 16 players). Nothing in it keeps still.

The plan (x east, z south, metres; walls on the lines x = -15, -5, 5, 15 and z = -11, -1, 11):

  ground floor (0 m)                          upper floor (4 m)
  +-----------+-----------+-----------+       +-----------+-----------+-----------+
  |  Kitchen  | Back Hall |  Library  |       | Bathroom  |Upper Hall |   Study   |
  |           | (servants'|           |       |           | (stair    |           |
  |           |  stair)   |           |       |           |  hole)    |           |
  +-----------+-----------+-----------+  z=-1 +-----------+--gallery--+-----------+
  |  Dining   |  Foyer    |  Parlour  |       | Bedroom   |  (round   |  Nursery  |
  |  Room     |  (grand   |           |       | (hole in  |  the void)|           |
  |           |   stair)  |           |       |  the floor)           |           |
  +-----------+-----------+-----------+  z=11 +-----------+-----------+-----------+

The Foyer is open from the ground to the roof (7.7 m), with a gallery all round it at 4 m
that the grand stair climbs to; the servants' stair in the Back Hall is the other way up,
and the hole in the Bedroom's floor drops into the Dining Room.

What moves (game/arena/haunt_event.gd, haunt_prop.gd, map_ghost.gd): the furniture floats
and bobs; every 27.5 s the house shifts (a 3 s warning, then 2.5 s in which the shifting
furniture glides to where the next of four layouts has it); nine doorways come and go
(each pair of them keeps its rooms joined: every room can be reached in every layout);
seven ghosts (faceless shades) fly their rounds through the walls; the candles flicker.

Built by `python3 tools/arena/build_arena_maps.py haunted_house` (then
tools/arena/migrate_breakable.gd ticks the boarded-up doorway). The scene is an ordinary
map scene from then on; running this again overwrites hand edits.
"""
import math
import random
from arena_builder import Map, yaw_cols, xform, fmt, vec, color, norm, cross, IDENTITY

PAL = "res://game/maps/palettes/haunted_house.tres"

# -- the plan ----------------------------------------------------------------------
XW, XE, ZN, ZS = -15.0, 15.0, -11.0, 11.0   # outer wall lines
XI = 5.0                                     # the inner wall lines x = -5 and 5
ZI = -1.0                                    # and z = -1
OT = 0.4                                     # outer walls (0.2 room side, 0.2 outside)
IT = 0.3                                     # inner walls (0.15 each side)
G, CG, U, CU = 0.0, 3.7, 4.0, 7.7           # ground floor, its ceiling, upper floor, its ceiling
DOOR_H = 2.5
TRIM_TUCK = 0.1   # how far into a doorway's architrave the wall's trims run
LAYOUTS = 4

# Grand stair: from (0, 0, STAIR_FOOT) north to the gallery's north strip at STAIR_TOP.
STAIR_FOOT, STAIR_TOP, STAIR_W = 8.5, 1.0, 3.0
# Servants' stair: along the Back Hall's north wall, west to east.
SS_X0, SS_X1, SS_Z0, SS_Z1 = -4.2, 3.3, -10.8, -8.8
SS_HOLE_X0 = -2.0
# The hole in the Bedroom's floor.
HOLE = (-11.6, 6.6, -9.4, 8.8)   # x0, z0, x1, z1

COLORS = {
    # walls
    "wp_foyer": (0.2, 0.3, 0.25), "wp_dining": (0.44, 0.12, 0.13), "wp_parlour": (0.56, 0.45, 0.23),
    "kitchen_wall": (0.74, 0.72, 0.64), "wp_library": (0.15, 0.19, 0.31), "wp_hall": (0.38, 0.27, 0.2),
    "wp_bedroom": (0.38, 0.28, 0.43), "wp_nursery": (0.62, 0.5, 0.53), "bath_wall": (0.52, 0.68, 0.66),
    "wp_study": (0.3, 0.34, 0.2), "ceiling": (0.6, 0.58, 0.54), "siding": (0.24, 0.23, 0.27),
    "plaster": (0.5, 0.48, 0.44),
    # floors
    "floor_oak": (0.38, 0.25, 0.15), "floor_dark": (0.25, 0.17, 0.11), "floor_marble": (0.72, 0.71, 0.69),
    "floor_tile": (0.66, 0.68, 0.64), "floor_stone": (0.42, 0.4, 0.38),
    # trim and wood
    "wainscot": (0.27, 0.17, 0.1), "chair_rail": (0.2, 0.12, 0.07), "skirting": (0.16, 0.1, 0.06),
    "moulding": (0.68, 0.66, 0.6), "wood_dark": (0.2, 0.12, 0.07), "wood": (0.4, 0.26, 0.15),
    "wood_light": (0.56, 0.41, 0.26), "mahogany": (0.36, 0.13, 0.08), "board": (0.42, 0.33, 0.22),
    "stair": (0.3, 0.19, 0.11), "banister": (0.18, 0.11, 0.06), "frame": (0.55, 0.42, 0.18),
    # cloth
    "fabric_red": (0.46, 0.08, 0.1), "fabric_green": (0.16, 0.29, 0.19), "fabric_purple": (0.3, 0.15, 0.36),
    "fabric_cream": (0.74, 0.69, 0.58), "linen": (0.82, 0.8, 0.74), "curtain": (0.32, 0.06, 0.1),
    "rug_red": (0.42, 0.1, 0.1), "rug_blue": (0.15, 0.18, 0.36), "rug_border": (0.62, 0.46, 0.2),
    "runner": (0.38, 0.08, 0.12),
    # metal, stone, glass
    "brass": (0.78, 0.6, 0.26), "iron": (0.15, 0.15, 0.16), "steel": (0.52, 0.54, 0.57),
    "porcelain": (0.9, 0.9, 0.86), "stone": (0.5, 0.48, 0.46), "brick": (0.46, 0.26, 0.2),
    "soot": (0.06, 0.05, 0.05), "rubble": (0.27, 0.24, 0.21), "marble_white": (0.84, 0.83, 0.8),
    "glass_window": (0.42, 0.52, 0.7, 0.28), "mirror": (0.5, 0.56, 0.66), "cobweb": (0.86, 0.88, 0.92, 0.3),
    # little things
    "book_red": (0.5, 0.12, 0.1), "book_green": (0.15, 0.32, 0.18), "book_blue": (0.14, 0.2, 0.42),
    "book_brown": (0.42, 0.28, 0.14), "book_black": (0.08, 0.08, 0.09), "paper": (0.84, 0.79, 0.64),
    "canvas": (0.13, 0.11, 0.09), "face": (0.62, 0.52, 0.42), "toy_red": (0.72, 0.16, 0.14),
    "toy_blue": (0.2, 0.36, 0.7), "toy_yellow": (0.86, 0.7, 0.2), "black": (0.03, 0.03, 0.04),
    "bone": (0.8, 0.77, 0.66), "pot": (0.36, 0.3, 0.26), "greenery": (0.16, 0.24, 0.12),
    # lights
    "candle": (0.92, 0.88, 0.76), "flame": (1.0, 0.68, 0.28), "ember": (1.0, 0.34, 0.1),
    "lamp": (1.0, 0.8, 0.5), "glow_green": (0.45, 1.0, 0.6), "eye_glow": (1.0, 0.22, 0.14),
    "ghost_light": (0.5, 0.95, 1.0), "moon": (0.86, 0.9, 1.0),
    # outside
    "foundation": (0.34, 0.33, 0.32), "grass_dead": (0.2, 0.22, 0.15), "dirt": (0.18, 0.15, 0.12),
    "tree": (0.09, 0.08, 0.08), "gravestone": (0.42, 0.43, 0.45), "fence": (0.07, 0.07, 0.08),
    "hill": (0.05, 0.06, 0.09), "mist": (0.55, 0.6, 0.75, 0.14),
}
SURFACE = {
    "wp_foyer": "wallpaper", "wp_dining": "wallpaper", "wp_parlour": "wallpaper", "wp_library": "wallpaper",
    "wp_hall": "wallpaper", "wp_bedroom": "wallpaper", "wp_nursery": "wallpaper", "wp_study": "wallpaper",
    "ceiling": "wallpaper", "plaster": "wallpaper", "kitchen_wall": "bricks", "bath_wall": "tiles",
    "siding": "planks", "floor_oak": "planks", "floor_dark": "planks", "floor_marble": "checker",
    "floor_tile": "checker", "floor_stone": "blocks_small", "wainscot": "planks_upright", "stair": "planks",
    "board": "planks", "wood_light": "planks", "stone": "blocks_small", "brick": "bricks",
    "foundation": "blocks", "grass_dead": "grass", "dirt": "dirt", "tree": "bark", "gravestone": "blocks_small",
    "hill": "grass",
}
GLOW = {"flame": 3.0, "ember": 2.6, "lamp": 2.2, "glow_green": 1.6, "eye_glow": 3.0, "ghost_light": 2.2,
        "moon": 2.8, "candle": 0.25, "mirror": 0.12, "brass": 0.08}
BREAKABLE = {"board": 120}
MATERIAL = {
    "floor_oak": "wood", "floor_dark": "wood", "stair": "wood", "wainscot": "wood", "wood": "wood",
    "wood_dark": "wood", "wood_light": "wood", "mahogany": "wood", "board": "wood", "banister": "wood",
    "floor_marble": "concrete", "floor_tile": "concrete", "floor_stone": "concrete", "stone": "concrete",
    "brass": "metal", "iron": "metal", "steel": "metal", "porcelain": "concrete", "glass_window": "glass",
    "mirror": "glass", "fabric_red": "rubber", "fabric_green": "rubber", "fabric_purple": "rubber",
    "fabric_cream": "rubber", "linen": "rubber", "rug_red": "rubber", "rug_blue": "rubber", "runner": "rubber", "rubble": "gravel",
}

FLIP = ((1, 0, 0), (0, -1, 0), (0, 0, -1))


def rot(deg):
    return yaw_cols(math.radians(deg))


def tarr(typ, items):
    if typ == "Vector3":
        body = ", ".join(vec(v) for v in items)
    elif typ == "float":
        body = ", ".join(fmt(float(v)) + ("" if "." in fmt(float(v)) else ".0") for v in items)
    else:
        body = ", ".join(str(int(v)) for v in items)
    return "Array[%s]([%s])" % (typ, body)


class Prop:
    """A HauntProp being written: where it stands and how it moves, and its solid boxes
    (in its own frame) for the checks at the end."""

    def __init__(self, name, path, origin, moves=None, turns=None, shown=None, bob=0.0, door=False):
        self.name, self.path, self.origin = name, path, origin
        self.moves, self.turns, self.shown = moves, turns, shown
        self.bob, self.door = bob, door
        self.solids = []

    def pose(self, layout):
        mv = self.moves[layout % len(self.moves)] if self.moves else (0, 0, 0)
        tn = self.turns[layout % len(self.turns)] if self.turns else 0.0
        return mv, tn

    def there(self, layout):
        return not self.shown or self.shown[layout % len(self.shown)] != 0

    def boxes(self, layout, mv=None, tn=None):
        if mv is None:
            mv, tn = self.pose(layout)
        c, s = math.cos(math.radians(tn)), math.sin(math.radians(tn))
        out = []
        for lo, hi in self.solids:
            xs, zs = [], []
            for x in (lo[0], hi[0]):
                for z in (lo[2], hi[2]):
                    # turned anticlockwise seen from above (yaw_cols)
                    xs.append(x * c + z * s)
                    zs.append(-x * s + z * c)
            o = self.origin
            out.append(((min(xs) + o[0] + mv[0], lo[1] + o[1] + mv[1] - self.bob, min(zs) + o[2] + mv[2]),
                        (max(xs) + o[0] + mv[0], hi[1] + o[1] + mv[1] + self.bob, max(zs) + o[2] + mv[2])))
        return out


def overlap(a, b, pad=0.0):
    return all(a[0][i] < b[1][i] - pad and b[0][i] < a[1][i] - pad for i in range(3))


class HauntedMap(Map):
    EXTRA = {
        "prop": "res://game/arena/haunt_prop.gd",
        "event": "res://game/arena/haunt_event.gd",
        "ghost": "res://game/arena/map_ghost.gd",
    }

    def __init__(self, *a, **kw):
        Map.__init__(self, *a, **kw)
        self.props = {}          # path -> Prop
        self.solids = []         # static solid boxes (world), for the checks
        self.openings = []       # doorways and windows
        self.spawn_pts = []
        self.weapon_pts = []
        self.rng = random.Random(1313)

    def node(self, name, parent, script, props, type_="Node3D", group=False):
        return self._add(name, type_, parent, props, script, group)

    def _prop_of(self, parent):
        p = parent
        while p:
            if p in self.props:
                return self.props[p]
            if "/" not in p:
                return None
            p = p.rsplit("/", 1)[0]
        return None

    def block(self, parent, name, kind, center, size, cols=IDENTITY, solid=True, drawn=True, extra=None, **kw):
        if solid:
            # (axis-lined extent of the box, for the checks)
            ext = [0.0, 0.0, 0.0]
            for i in range(3):
                ext[i] = sum(abs(cols[j][i]) * size[j] for j in range(3)) * 0.5
            lo = tuple(center[i] - ext[i] for i in range(3))
            hi = tuple(center[i] + ext[i] for i in range(3))
            prop = self._prop_of(parent)
            if prop is not None:
                prop.solids.append((lo, hi))
            elif kw.get("shape") not in ("wedge",) or True:
                self.solids.append((lo, hi, parent + "/" + name))
        path = Map.block(self, parent, name, kind, center, size, cols=cols, solid=solid, drawn=drawn, **kw)
        if extra:
            self.nodes[-1].props.extend(extra)
        return path

    def prop(self, name, parent, origin, moves=None, turns=None, shown=None, bob=0.0, period=5.0, phase=None,
             sway=0.0, spin=0.0, door=False):
        """A HauntProp group at `origin` (its blocks go in its own frame)."""
        props = [("transform", xform(IDENTITY, origin)), ("over_ground", "true")]
        if phase is None:
            phase = self.rng.random()
        if bob:
            props += [("bob", fmt(bob)), ("bob_period", fmt(period))]
        if bob or sway:
            props.append(("bob_phase", fmt(phase)))
        if sway:
            props.append(("sway", fmt(sway)))
        if spin:
            props.append(("twirl", fmt(spin)))
        if moves:
            props.append(("moves", tarr("Vector3", moves)))
        if turns:
            props.append(("turns", tarr("float", turns)))
        if shown:
            props.append(("shown", tarr("int", shown)))
        if door:
            props.append(("door", "true"))
        path = self.node(name, parent, "prop", props, group=True)
        self.props[path] = Prop(name, path, origin, moves, turns, shown, bob, door)
        return path

    # -- shapes that are not boxes (as in cirrus.py) -------------------------------
    def bev(self, parent, name, kind, lo, hi, bevel=0.06, **kw):
        c = tuple((a + b) * 0.5 for a, b in zip(lo, hi))
        s = tuple(abs(b - a) for a, b in zip(lo, hi))
        return self.block(parent, name, kind, c, s, shape="bevel", bevel=min(bevel, min(s) * 0.45), **kw)

    def dome(self, parent, name, kind, base, size, sides=12, flip=False, **kw):
        c = (base[0], base[1] + (-size[1] if flip else size[1]) * 0.5, base[2])
        return self.block(parent, name, kind, c, size, cols=FLIP if flip else IDENTITY, shape="dome", sides=sides, **kw)

    def cone(self, parent, name, kind, base, diameter, height, top=0.0, sides=12, flip=False, **kw):
        c = (base[0], base[1] + (-height if flip else height) * 0.5, base[2])
        return self.block(parent, name, kind, c, (diameter, height, diameter), cols=FLIP if flip else IDENTITY,
                          shape="cone", sides=sides, top=top, **kw)

    def ball(self, parent, name, kind, center, d, sides=10, **kw):
        """A round lump: two domes back to back."""
        self.dome(parent, name, kind, center, (d, d * 0.5, d), sides=sides, **kw)
        self.dome(parent, name, kind, center, (d * 0.999, d * 0.5, d * 0.999), sides=sides, flip=True, **kw)

    def write(self, path):
        scripts = dict(__import__("arena_builder").SCRIPTS)
        scripts.update(self.EXTRA)
        ids = {}
        out = ["[gd_scene format=3]", ""]
        for i, (k, p) in enumerate(scripts.items()):
            ids[k] = "%d_%s" % (i + 1, k)
            out.append('[ext_resource type="Script" path="%s" id="%s"]' % (p, ids[k]))
        out.append('[ext_resource type="Resource" path="%s" id="pal"]' % self.palette)
        sky = self.env["sky"]
        out += ["", '[sub_resource type="ProceduralSkyMaterial" id="ProceduralSkyMaterial_1"]']
        for k in ("sky_top_color", "sky_horizon_color", "ground_bottom_color", "ground_horizon_color"):
            out.append("%s = %s" % (k, color(sky[k])))
        out += ["sun_angle_max = 8.0", "sky_energy_multiplier = 0.6", "",
                '[sub_resource type="Sky" id="Sky_1"]', 'sky_material = SubResource("ProceduralSkyMaterial_1")', "",
                '[sub_resource type="Environment" id="Environment_1"]', "background_mode = 2", 'sky = SubResource("Sky_1")']
        out += self.env["lines"]
        out += ["", '[node name="%s" type="Node3D"]' % self.root, 'script = ExtResource("%s")' % ids["root"],
                'palette = ExtResource("pal")']
        for k, v in self.settings.items():
            out.append("%s = %s" % (k, v))
        out += ["", '[node name="Environment" type="WorldEnvironment" parent="."]', 'environment = SubResource("Environment_1")', ""]
        elev, azim, col, energy = self.sun
        e, az = math.radians(elev), math.radians(azim)
        Z = norm((math.sin(az) * math.cos(e), math.sin(e), -math.cos(az) * math.cos(e)))
        X = norm(cross((0, 1, 0), Z))
        out += ['[node name="Sun" type="DirectionalLight3D" parent="."]', "transform = %s" % xform((X, cross(Z, X), Z), (0, 0, 0)),
                "light_color = %s" % color(col), "light_energy = %s" % fmt(energy), "shadow_enabled = true",
                "directional_shadow_max_distance = 60.0", ""]
        for n in self.nodes:
            out.append('[node name="%s" type="%s" parent="%s"]' % (n.name, n.type, n.parent))
            for k, v in n.props:
                if k == "transform":
                    out.append("%s = %s" % (k, v))
            if n.script:
                out.append('script = ExtResource("%s")' % ids[n.script])
            for k, v in n.props:
                if k != "transform":
                    out.append("%s = %s" % (k, v))
            if n.group:
                out.append("metadata/_edit_group_ = true")
            out.append("")
        with open(path, "w") as fh:
            fh.write("\n".join(out))
        blocks = sum(1 for n in self.nodes if n.script == "block")
        print("wrote %s: %d nodes (%d blocks), %d props, %d spawns, %d weapon pickups" % (
            path, len(self.nodes), blocks, len(self.props), self.spawn_count, self.weapon_count))


# =====================================================================================
# Rooms, walls and the openings in them
# =====================================================================================

class Room:
    def __init__(self, name, x0, x1, z0, z1, y0, y1, wall, floor, ceiling="ceiling", outer=(), wainscot=True):
        self.name = name
        self.x0, self.x1, self.z0, self.z1, self.y0, self.y1 = x0, x1, z0, z1, y0, y1
        self.wall, self.floor, self.ceiling = wall, floor, ceiling
        self.outer = outer          # which sides are outside walls: "n", "s", "w", "e"
        self.wainscot = wainscot


ROOMS = [
    Room("Foyer", -XI, XI, ZI, ZS, G, CU, "wp_foyer", "floor_marble", outer=("s",)),
    Room("Dining", XW, -XI, ZI, ZS, G, CG, "wp_dining", "floor_oak", outer=("w", "s")),
    Room("Parlour", XI, XE, ZI, ZS, G, CG, "wp_parlour", "floor_oak", outer=("e", "s")),
    Room("Kitchen", XW, -XI, ZN, ZI, G, CG, "kitchen_wall", "floor_tile", outer=("w", "n"), wainscot=False),
    Room("Library", XI, XE, ZN, ZI, G, CG, "wp_library", "floor_dark", outer=("e", "n")),
    Room("BackHall", -XI, XI, ZN, ZI, G, CG, "wp_hall", "floor_dark", outer=("n",)),
    Room("Bedroom", XW, -XI, ZI, ZS, U, CU, "wp_bedroom", "floor_oak", outer=("w", "s")),
    Room("Nursery", XI, XE, ZI, ZS, U, CU, "wp_nursery", "floor_oak", outer=("e", "s")),
    Room("Bathroom", XW, -XI, ZN, ZI, U, CU, "bath_wall", "floor_tile", outer=("w", "n"), wainscot=False),
    Room("Study", XI, XE, ZN, ZI, U, CU, "wp_study", "floor_dark", outer=("e", "n")),
    Room("UpperHall", -XI, XI, ZN, ZI, U, CU, "wp_hall", "floor_dark", outer=("n",)),
]
ROOM = {r.name: r for r in ROOMS}

# Doorways: (name, axis, line, u0, u1, y0, open-in-each-layout or None for always open).
# axis "z": the wall runs along z at x = line (u is z); "x": along x at z = line (u is x).
DOORS = [
    ("FoyerDining", "z", -XI, 5.0, 7.0, G, None),
    ("FoyerParlour", "z", XI, 5.0, 7.0, G, None),
    ("FoyerHallW", "x", ZI, -4.5, -3.1, G, [1, 0, 1, 0]),
    ("FoyerHallE", "x", ZI, 3.1, 4.5, G, [0, 1, 0, 1]),
    ("DiningKitchen", "x", ZI, -11.0, -9.4, G, [1, 1, 0, 0]),
    ("DiningKitchenW", "x", ZI, -14.2, -12.6, G, [0, 0, 1, 1]),
    ("ParlourLibrary", "x", ZI, 9.4, 11.0, G, None),
    ("KitchenHall", "z", -XI, -6.8, -5.2, G, [1, 0, 0, 1]),
    ("LibraryHall", "z", XI, -6.8, -5.2, G, [0, 1, 1, 0]),
    ("FoyerDiningS", "z", -XI, 8.7, 10.2, G, [0, 1, 1, 0]),
    ("FoyerParlourN", "z", XI, 0.4, 1.9, G, [1, 0, 0, 1]),
    ("GalleryBedroom", "z", -XI, 5.0, 6.6, U, [1, 1, 0, 1]),
    ("GalleryNursery", "z", XI, 5.4, 7.0, U, [1, 0, 1, 1]),
    ("GalleryHall", "x", ZI, -0.8, 0.8, U, None),
    ("BedroomBath", "x", ZI, -11.6, -10.0, U, [0, 1, 0, 1]),
    ("NurseryStudy", "x", ZI, 10.0, 11.6, U, None),
    ("BathHall", "z", -XI, -6.0, -4.4, U, None),
    ("StudyHall", "z", XI, -6.0, -4.4, U, [1, 0, 1, 0]),
    ("GalleryBedroomN", "z", -XI, 1.6, 3.1, U, [0, 1, 1, 0]),
    ("GalleryNurseryS", "z", XI, 8.8, 10.3, U, [0, 1, 1, 0]),
]
# The boarded-up doorway (Library to Back Hall... no: Kitchen pantry to Back Hall): shoot it open.
BOARDED = ("PantryBoards", "z", -XI, -9.6, -8.4, G)

# Windows: (axis, line, u0, u1, y0, y1).
WINDOWS = []
for y0, y1 in ((1.2, 3.0), (U + 1.2, U + 3.0)):
    for (u0, u1) in ((-13.4, -11.8), (-8.4, -6.8), (6.8, 8.4), (11.8, 13.4)):
        WINDOWS.append(("x", ZS, u0, u1, y0, y1))        # south front
        WINDOWS.append(("x", ZN, u0, u1, y0, y1))        # north back
    for (u0, u1) in ((1.6, 3.2), (7.0, 8.6), (-8.6, -7.0), (-4.4, -2.8)):
        WINDOWS.append(("z", XW, u0, u1, y0, y1))        # west
        WINDOWS.append(("z", XE, u0, u1, y0, y1))        # east
# Stretches of wall a curtain must not hang into (tall bookcases beside a window):
# (axis, line, y0, y1, u0, u1).
CURTAIN_CLEAR = [
    ("x", ZN, G, CG, 8.5, 11.7),        # the Library's north cases
    ("z", XE, G, CU, -10.7, -8.8),      # the Library's and the Study's east cases
    ("z", XE, G, CU, -6.85, -4.55),
]
# The foyer's tall windows either side of the front door, and the fanlight over it.
for (u0, u1) in ((-3.6, -2.4), (2.4, 3.6)):
    WINDOWS.append(("x", ZS, u0, u1, 1.0, 3.4))
    WINDOWS.append(("x", ZS, u0, u1, U + 0.8, U + 3.2))
WINDOWS.append(("x", ZN, -1.0, 1.0, U + 1.0, U + 3.0))   # the upper hall's back window
FRONT_DOOR = (-1.3, 1.3, 0.0, 3.0)


def wall_holes(axis, line, lo, hi, y0, y1):
    """The openings in the wall on `line` between u = lo and hi and heights y0..y1, as
    (u0, u1, bottom, top, what)."""
    out = []
    for d in DOORS:
        name, ax, ln, u0, u1, dy, pattern = d
        if ax == axis and abs(ln - line) < 0.01 and u0 >= lo - 0.01 and u1 <= hi + 0.01 and dy >= y0 - 0.01 and dy < y1:
            out.append((u0, u1, dy, dy + DOOR_H, d))
    b = BOARDED
    if b[1] == axis and abs(b[2] - line) < 0.01 and b[3] >= lo and b[4] <= hi and b[5] >= y0 - 0.01 and b[5] < y1:
        out.append((b[3], b[4], b[5], b[5] + DOOR_H, b))
    for w in WINDOWS:
        ax, ln, u0, u1, wy0, wy1 = w
        if ax == axis and abs(ln - line) < 0.01 and u0 >= lo - 0.01 and u1 <= hi + 0.01 and wy0 >= y0 - 0.01 and wy1 <= y1 + 0.01:
            out.append((u0, u1, wy0, wy1, ("window",) + w))
    if axis == "x" and abs(line - ZS) < 0.01 and lo <= FRONT_DOOR[0] and hi >= FRONT_DOOR[1] and y0 <= 0.01:
        out.append((FRONT_DOOR[0], FRONT_DOOR[1], FRONT_DOOR[2], FRONT_DOOR[3], ("front",)))
    return sorted(out, key=lambda h: h[0])


def sides(room):
    """Each wall of a room: (side, axis, line, u0, u1, out) where out is +1 or -1, the way
    the face looks into the room."""
    r = room
    return [("n", "x", r.z0, r.x0, r.x1, 1), ("s", "x", r.z1, r.x0, r.x1, -1),
            ("w", "z", r.x0, r.z0, r.z1, 1), ("e", "z", r.x1, r.z0, r.z1, -1)]


def half_thick(room, side):
    return OT * 0.5 if side in room.outer else IT * 0.5


def face_of(room, side, line, out):
    return line + out * half_thick(room, side)


def house_wall(m, parent, name, kind, a, b, y0, y1, thick, holes=(), **kw):
    """Map.wall, but openings may stand one above another (a gallery doorway over a
    ground floor one): the wall is cut into strips at every opening's edges, and each
    strip is solid wherever no opening is."""
    along_x = abs(b[0] - a[0]) >= abs(b[1] - a[1])
    length = abs(b[0] - a[0]) if along_x else abs(b[1] - a[1])
    start = min(a[0], b[0]) if along_x else min(a[1], b[1])
    line = a[1] if along_x else a[0]
    cuts = sorted({0.0, length} | {min(max(v, 0.0), length) for h in holes for v in h[:2]})
    for u0, u1 in zip(cuts, cuts[1:]):
        if u1 - u0 < 0.01:
            continue
        um = (u0 + u1) * 0.5
        gaps = sorted((max(hb, y0), min(ht, y1)) for h0, h1, hb, ht in holes if h0 < um < h1)
        v = y0
        spans = []
        for gb, gt in gaps:
            if gb > v:
                spans.append((v, gb))
            v = max(v, gt)
        if v < y1:
            spans.append((v, y1))
        for v0, v1 in spans:
            if v1 - v0 < 0.01:
                continue
            label = name if not gaps else (name + ("Sill" if v1 <= gaps[0][0] + 0.01 else "Lintel"))
            if along_x:
                lo, hi = (start + u0, v0, line - thick / 2), (start + u1, v1, line + thick / 2)
            else:
                lo, hi = (line - thick / 2, v0, start + u0), (line + thick / 2, v1, start + u1)
            m.box(parent, label, kind, lo, hi, **kw)


def build_walls(m):
    f = m.folder("Walls")
    for r in ROOMS:
        g = m.group(r.name + "Walls", f)
        for side, axis, line, u0, u1, out in sides(r):
            th = half_thick(r, side)
            # The wall's end runs to the corner of the room's own half (the next wall's face
            # is inside it), so corners close.
            # Walls along x run the room's whole length (to the centre lines: they close
            # the corners); walls along z stop at their faces.
            if axis == "x":
                lo, hi = u0, u1
                tlo, thi = u0 + half_thick(r, "w"), u1 - half_thick(r, "e")
            else:
                lo, hi = u0 + half_thick(r, "n"), u1 - half_thick(r, "s")
                tlo, thi = lo, hi
            holes = [(h[0], h[1], h[2], h[3]) for h in wall_holes(axis, line, u0, u1, r.y0, r.y1)]
            centre = line + out * th * 0.5
            # (a, b) along the wall at the wall's centre line.
            if axis == "x":
                a, b = (lo, centre), (hi, centre)
            else:
                a, b = (centre, lo), (centre, hi)
            # Holes are measured from the wall's west/north end.
            rel = [(h0 - lo, h1 - lo, hb, ht) for h0, h1, hb, ht in holes]
            house_wall(m, g, side.upper() + "Wall", r.wall, a, b, r.y0, r.y1, th, rel, unbreakable=True)
            if side in r.outer:
                # The outside half: weatherboarding.
                oc = line - out * OT * 0.25
                olo, ohi = u0 - OT * 0.5, u1 + OT * 0.5
                if axis == "x":
                    oa, ob = (olo, oc), (ohi, oc)
                else:
                    oa, ob = (oc, olo), (oc, ohi)
                orel = [(h0 - olo, h1 - olo, hb, ht) for h0, h1, hb, ht in holes]
                house_wall(m, g, side.upper() + "Outside", "siding", oa, ob, r.y0 if r.y0 > 0 else -0.6, r.y1 + (0.3 if r.y1 > 7 else 0.3),
                       OT * 0.5, [(a0, a1, hb if hb > 0.01 else -0.6, ht) for a0, a1, hb, ht in orel], unbreakable=True)
            trims(m, g, r, side, axis, line, tlo, thi, out, holes)


def trims(m, g, r, side, axis, line, lo, hi, out, holes):
    """Skirting, wainscot, chair rail, picture rail and cornice along one wall of a room,
    broken at every opening that comes down through them."""
    face = face_of(r, side, line, out)
    y0, y1 = r.y0, r.y1
    if r.name == "Foyer":
        # The foyer's two storeys: trims on each.
        bands = [(G, CG), (U, CU)]
    else:
        bands = [(y0, y1)]
    for (b0, b1) in bands:
        runs = [(lo, hi)]
        for h0, h1, hb, ht in holes:
            if hb >= b1 or ht <= b0:
                continue
            # The trims stop under the opening's architrave or window frame, so no end of
            # them lies in the plane of the frame's side.
            h0, h1 = h0 - TRIM_TUCK, h1 + TRIM_TUCK
            new = []
            for a, b in runs:
                if h1 <= a or h0 >= b:
                    new.append((a, b))
                    continue
                if h0 > a:
                    new.append((a, h0))
                if h1 < b:
                    new.append((h1, b))
            runs = new
        low = [h for h in holes if h[2] <= b0 + 1.3 and h[3] > b0]   # (openings that come down to the dado)
        for a, b in runs:
            if b - a < 0.05:
                continue
            m.on_wall(g, "Skirting", "skirting", axis, face, out, a, b, b0, b0 + 0.21, 0.05)
            if r.wainscot:
                m.on_wall(g, "Wainscot", "wainscot", axis, face, out, a, b, b0 + 0.2, b0 + 1.1, 0.03)
                m.on_wall(g, "ChairRail", "chair_rail", axis, face, out, a, b, b0 + 1.06, b0 + 1.16, 0.07)
        # Higher trims break only at openings that reach them.
        for name, kind, ya, yb, depth in (("PictureRail", "chair_rail", b1 - 0.7, b1 - 0.64, 0.04),
                                          ("Cornice", "moulding", b1 - 0.22, b1, 0.1),
                                          ("CorniceLip", "moulding", b1 - 0.3, b1 - 0.22, 0.05)):
            runs2 = [(lo, hi)]
            for h0, h1, hb, ht in holes:
                if ht + 0.15 <= ya or hb - 0.15 >= yb:   # (its frame stands 12 cm round it)
                    continue
                h0, h1 = h0 - TRIM_TUCK, h1 + TRIM_TUCK
                new = []
                for a, b in runs2:
                    if h1 <= a or h0 >= b:
                        new.append((a, b))
                        continue
                    if h0 > a:
                        new.append((a, h0))
                    if h1 < b:
                        new.append((h1, b))
                runs2 = new
            for a, b in runs2:
                if b - a > 0.05:
                    m.on_wall(g, name, kind, axis, face, out, a, b, ya, yb, depth)


def build_floors(m):
    f = m.folder("Floors")
    # Ground floor: one floor per room, under the walls to their centre lines.
    for r in ROOMS:
        g = m.group(r.name + "Floor", f)
        if r.y0 == G:
            m.box(g, "Floor", r.floor, (r.x0, -0.3, r.z0), (r.x1, G, r.z1), unbreakable=True)
        else:
            # Upper floors: boards on top of a plaster ceiling for the room below.
            pieces = [(r.x0, r.z0, r.x1, r.z1)]
            if r.name == "UpperHall":
                pieces = cut(pieces, (SS_HOLE_X0, SS_Z0 - 0.2, SS_X1, SS_Z1))
            if r.name == "Bedroom":
                pieces = cut(pieces, HOLE)
            for (x0, z0, x1, z1) in pieces:
                m.box(g, "Floor", r.floor, (x0, U - 0.05, z0), (x1, U, z1), unbreakable=True)
                m.box(g, "Ceiling", "ceiling", (x0, CG, z0), (x1, U - 0.05, z1), unbreakable=True)
        # The roof over every room (the foyer's too): a ceiling.
        if r.y1 == CU:
            m.box(g, "Roof", "ceiling", (r.x0, CU, r.z0), (r.x1, CU + 0.3, r.z1), unbreakable=True)
    # The gallery round the foyer's void.
    g = m.group("Gallery", f)
    for name, (x0, z0, x1, z1) in (("North", (-XI, ZI, XI, STAIR_TOP)), ("West", (-XI, STAIR_TOP, -3.0, ZS)),
                                   ("East", (3.0, STAIR_TOP, XI, ZS)), ("South", (-3.0, 9.0, 3.0, ZS))):
        m.box(g, name + "Floor", "floor_dark", (x0, U - 0.05, z0), (x1, U, z1), unbreakable=True)
        m.box(g, name + "Ceiling", "ceiling", (x0, CG, z0), (x1, U - 0.05, z1), unbreakable=True)
    # Under the house: the foundation band, outside.
    g = m.group("Foundation", f)
    m.box(g, "Plinth", "foundation", (XW - 0.35, -0.7, ZN - 0.35), (XE + 0.35, -0.3, ZS + 0.35), unbreakable=True)


def cut(pieces, hole):
    """Rectangles (x0, z0, x1, z1) with `hole` taken out of them."""
    hx0, hz0, hx1, hz1 = hole
    out = []
    for (x0, z0, x1, z1) in pieces:
        if hx1 <= x0 or hx0 >= x1 or hz1 <= z0 or hz0 >= z1:
            out.append((x0, z0, x1, z1))
            continue
        if hz0 > z0:
            out.append((x0, z0, x1, hz0))
        if hz1 < z1:
            out.append((x0, hz1, x1, z1))
        if hx0 > x0:
            out.append((x0, max(z0, hz0), hx0, min(z1, hz1)))
        if hx1 < x1:
            out.append((hx1, max(z0, hz0), x1, min(z1, hz1)))
    return out


# =====================================================================================
# Doorways: frames, the doors that come and go, windows
# =====================================================================================

def door_rooms(d):
    """The rooms either side of a doorway: (room on the low side, room on the high side)."""
    name, axis, line, u0, u1, y0, _p = d[:7] if len(d) >= 7 else d + (None,)
    um = (u0 + u1) * 0.5
    found = []
    for r in ROOMS:
        if not (r.y0 <= y0 + 0.01 and r.y1 > y0 + 0.5):
            continue
        if axis == "z" and (abs(r.x0 - line) < 0.01 or abs(r.x1 - line) < 0.01) and r.z0 <= um <= r.z1:
            found.append(r)
        if axis == "x" and (abs(r.z0 - line) < 0.01 or abs(r.z1 - line) < 0.01) and r.x0 <= um <= r.x1:
            found.append(r)
    lo = [r for r in found if (r.x1 if axis == "z" else r.z1) <= line + 0.01]
    hi = [r for r in found if (r.x0 if axis == "z" else r.z0) >= line - 0.01]
    return (lo[0] if lo else None), (hi[0] if hi else None)


def architrave(m, g, axis, face, out, u0, u1, y0, y1):
    """A door frame on one face of a wall: two jambs and a head, standing proud, with a
    little cornice on the head."""
    m.on_wall(g, "Jamb", "wood_dark", axis, face, out, u0 - 0.16, u0, y0, y1 + 0.16, 0.06)
    m.on_wall(g, "Jamb", "wood_dark", axis, face, out, u1, u1 + 0.16, y0, y1 + 0.16, 0.06)
    m.on_wall(g, "Head", "wood_dark", axis, face, out, u0 - 0.16, u1 + 0.16, y1, y1 + 0.16, 0.06)
    m.on_wall(g, "HeadCap", "wood_dark", axis, face, out, u0 - 0.24, u1 + 0.24, y1 + 0.16, y1 + 0.24, 0.1)
    # (the plinths reach a centimetre past the jambs into the opening: their ends and the
    # jambs' must not lie in one plane)
    m.on_wall(g, "Plinth", "skirting", axis, face, out, u0 - 0.19, u0 + 0.012, y0, y0 + 0.28, 0.08)
    m.on_wall(g, "Plinth", "skirting", axis, face, out, u1 - 0.012, u1 + 0.19, y0, y0 + 0.28, 0.08)


def lining(m, g, axis, line, u0, u1, y0, y1, thick):
    """The inside of a doorway: a wooden lining on both jambs and the soffit, drawn only,
    inside the wall's own thickness."""
    a, b = line - thick * 0.5 + 0.005, line + thick * 0.5 - 0.005
    if axis == "x":
        m.strip(g, "LiningL", "wood", (u0, y0, a), (u0 + 0.025, y1, b))
        m.strip(g, "LiningR", "wood", (u1 - 0.025, y0, a), (u1, y1, b))
        m.strip(g, "Soffit", "wood", (u0, y1 - 0.025, a), (u1, y1, b))
        m.strip(g, "Threshold", "wood_dark", (u0, y0, a), (u1, y0 + 0.025, b))
    else:
        m.strip(g, "LiningL", "wood", (a, y0, u0), (b, y1, u0 + 0.025))
        m.strip(g, "LiningR", "wood", (a, y0, u1 - 0.025), (b, y1, u1))
        m.strip(g, "Soffit", "wood", (a, y1 - 0.025, u0), (b, y1, u1))
        m.strip(g, "Threshold", "wood_dark", (a, y0, u0), (b, y0 + 0.025, u1))


def build_doors(m):
    f = m.folder("Doorways")
    for d in DOORS:
        name, axis, line, u0, u1, y0, pattern = d
        y1 = y0 + DOOR_H
        lo, hi = door_rooms(d)
        thick = IT
        g = m.group(name, f)
        frame_parent = g
        if pattern:
            # The frame and the lining show only while the doorway is there...
            um = (u0 + u1) * 0.5
            origin = (um, y0, line) if axis == "x" else (line, y0, um)
            frame_parent = m.prop("Frame", g, origin, shown=list(pattern))
            fr = m.props[frame_parent]
            local = lambda p, o=origin: tuple(p[i] - o[i] for i in range(3))
            # (the frame's blocks are written in the prop's frame)
            build_frame_local(m, frame_parent, axis, line, u0, u1, y0, y1, thick, lo, hi, origin)
            # ...and the panel that seals it when it is not.
            panel = m.prop("Seal", g, origin, shown=[0 if v else 1 for v in pattern], door=True)
            build_seal_local(m, panel, axis, line, u0, u1, y0, y1, thick, lo, hi, origin)
        else:
            for r, out in ((lo, 1 if axis == "z" else 1), (hi, -1)):
                if r is None:
                    continue
                side_out = 1 if r is hi else -1
                face = line + side_out * thick * 0.5
                architrave(m, g, axis, face, side_out, u0, u1, y0, y1)
            lining(m, g, axis, line, u0, u1, y0, y1, thick)
        # An old door leaf, standing open against the wall in some (drawn only).
        if not pattern and name in ("FoyerDining", "ParlourLibrary", "NurseryStudy", "BathHall"):
            leaf_open(m, g, axis, line, u0, u1, y0, lo, hi)
    # The boarded-up pantry door (Kitchen to Back Hall): planks you can shoot through.
    name, axis, line, u0, u1, y0 = BOARDED
    g = m.group(name, f)
    y1 = y0 + DOOR_H
    lining(m, g, axis, line, u0, u1, y0, y1, IT)
    for r in door_rooms(BOARDED + (None,)):
        if r is None:
            continue
        out = 1 if r.x0 >= line - 0.01 else -1
        architrave(m, g, axis, line + out * IT * 0.5, out, u0, u1, y0, y1)
    m.box(g, "Boards", "board", (line - 0.06, y0, u0), (line + 0.06, y1, u1),
          extra=[("breakable", "true"), ("break_settings", '"Whole Block"'), ("break_health", "120.0")])
    for i, yy in enumerate((0.5, 1.2, 1.9)):
        for out in (-1, 1):
            x = line + out * 0.08
            m.rod(g, "Plank", "board", (x, y0 + yy - 0.2 + 0.1 * i, u0 - 0.1), (x, y0 + yy + 0.25 - 0.08 * i, u1 + 0.1), thick=0.04, wide=0.18)


def build_frame_local(m, parent, axis, line, u0, u1, y0, y1, thick, lo, hi, origin):
    o = origin
    sub = m.group("Parts", parent, at=(-o[0], -o[1], -o[2]), grouped=False)
    for r, side_out in ((lo, -1), (hi, 1)):
        if r is None:
            continue
        face = line + side_out * thick * 0.5
        architrave(m, sub, axis, face, side_out, u0, u1, y0, y1)
    lining(m, sub, axis, line, u0, u1, y0, y1, thick)


def build_seal_local(m, parent, axis, line, u0, u1, y0, y1, thick, lo, hi, origin):
    """The wall that fills a doorway while it is gone: each half in its room's wallpaper,
    with that room's skirting, wainscot and rail across it (so the wall reads whole)."""
    o = origin
    sub = m.group("Parts", parent, at=(-o[0], -o[1], -o[2]), grouped=False)
    prop = m.props[parent]
    for r, side_out in ((lo, -1), (hi, 1)):
        if r is None:
            continue
        a = line
        b = line + side_out * thick * 0.5
        if axis == "x":
            blo, bhi = (u0, y0, min(a, b)), (u1, y1, max(a, b))
        else:
            blo, bhi = (min(a, b), y0, u0), (max(a, b), y1, u1)
        m.box(sub, "Half", r.wall, blo, bhi, unbreakable=True)
        # (the box is in the map's frame inside `sub`, which undoes the prop's origin; note
        # its solid extent in the prop's own frame for the checks)
        prop.solids[-1] = (tuple(blo[i] - o[i] for i in range(3)), tuple(bhi[i] - o[i] for i in range(3)))
        face = b
        t0, t1 = u0 - TRIM_TUCK, u1 + TRIM_TUCK   # (meeting the wall's own trims, which stop short of the hole)
        m.on_wall(sub, "Skirting", "skirting", axis, face, side_out, t0, t1, y0, y0 + 0.21, 0.05)
        if r.wainscot:
            m.on_wall(sub, "Wainscot", "wainscot", axis, face, side_out, t0, t1, y0 + 0.2, y0 + 1.1, 0.03)
            m.on_wall(sub, "ChairRail", "chair_rail", axis, face, side_out, t0, t1, y0 + 1.06, y0 + 1.16, 0.07)
        # A scratched sign of the doorway that was: claw marks in the paper.
        for k in range(3):
            uu = u0 + 0.45 + 0.22 * k
            m.on_wall(sub, "Scratch", "soot", axis, face, side_out, uu, uu + 0.03, y0 + 1.5 - 0.05 * k, y0 + 2.1 - 0.05 * k, 0.012)


def leaf_open(m, g, axis, line, u0, u1, y0, lo, hi):
    """A door leaf swung back flat against the wall beside its doorway (drawn only)."""
    w = u1 - u0
    if axis == "z":
        x = line + IT * 0.5 + 0.12
        m.strip(g, "Leaf", "wood", (x, y0 + 0.02, u1 + 0.25), (x + 0.05, y0 + DOOR_H - 0.05, u1 + 0.25 + min(w, 1.0)))
        m.strip(g, "LeafPanel", "wood_dark", (x + 0.05, y0 + 0.3, u1 + 0.4), (x + 0.07, y0 + 1.1, u1 + 0.1 + min(w, 1.0)))
        m.strip(g, "LeafPanel", "wood_dark", (x + 0.05, y0 + 1.35, u1 + 0.4), (x + 0.07, y0 + 2.3, u1 + 0.1 + min(w, 1.0)))
        m.strip(g, "Knob", "brass", (x + 0.05, y0 + 1.0, u1 + 0.18 + min(w, 1.0)), (x + 0.11, y0 + 1.07, u1 + 0.23 + min(w, 1.0)))
    else:
        z = line + IT * 0.5 + 0.12
        m.strip(g, "Leaf", "wood", (u1 + 0.25, y0 + 0.02, z), (u1 + 0.25 + min(w, 1.0), y0 + DOOR_H - 0.05, z + 0.05))
        m.strip(g, "LeafPanel", "wood_dark", (u1 + 0.4, y0 + 0.3, z + 0.05), (u1 + 0.1 + min(w, 1.0), y0 + 1.1, z + 0.07))
        m.strip(g, "LeafPanel", "wood_dark", (u1 + 0.4, y0 + 1.35, z + 0.05), (u1 + 0.1 + min(w, 1.0), y0 + 2.3, z + 0.07))


def build_windows(m):
    f = m.folder("Windows")
    rng = random.Random(77)
    for i, w in enumerate(WINDOWS):
        axis, line, u0, u1, y0, y1 = w
        g = m.group("Window%d" % (i + 1), f)
        out = 1 if (axis == "x" and line < 0) or (axis == "z" and line < 0) else -1   # into the house
        # The glass, in the middle of the wall (it does not break).
        if axis == "x":
            m.box(g, "Glass", "glass_window", (u0, y0, line - 0.02), (u1, y1, line + 0.02), unbreakable=True)
        else:
            m.box(g, "Glass", "glass_window", (line - 0.02, y0, u0), (line + 0.02, y1, u1), unbreakable=True)
        inner = line + out * OT * 0.5
        # Sash bars, both sides of the glass.
        for s in (-1, 1):
            face = line + s * 0.02
            um = (u0 + u1) * 0.5
            m.on_wall(g, "Mullion", "wood_dark", axis, face, s, um - 0.03, um + 0.03, y0, y1, 0.03)
            for k in (1, 2):
                yy = y0 + (y1 - y0) * k / 3.0
                m.on_wall(g, "Bar", "wood_dark", axis, face, s, u0, u1, yy - 0.025, yy + 0.025, 0.03)
        # The frame and the sill inside.
        m.on_wall(g, "Frame", "wood_dark", axis, inner, out, u0 - 0.12, u0, y0 - 0.05, y1 + 0.1, 0.05)
        m.on_wall(g, "Frame", "wood_dark", axis, inner, out, u1, u1 + 0.12, y0 - 0.05, y1 + 0.1, 0.05)
        m.on_wall(g, "Frame", "wood_dark", axis, inner, out, u0 - 0.12, u1 + 0.12, y1, y1 + 0.12, 0.05)
        m.on_wall(g, "Sill", "wood_dark", axis, inner, out, u0 - 0.2, u1 + 0.2, y0 - 0.1, y0, 0.16)
        # Curtains: heavy, torn, drawn back to either side (drawn only).
        torn = rng.random()
        for side, (a, b) in enumerate(((u0 - 0.55, u0 + 0.12), (u1 - 0.12, u1 + 0.55))):
            for cax, cline, cy0, cy1, c0, c1 in CURTAIN_CLEAR:
                if cax == axis and abs(cline - line) < 0.01 and cy0 <= y0 < cy1:
                    if side == 0 and c0 < a + 0.3 and c1 > a:
                        a = c1 + 0.02
                    if side == 1 and c1 > b - 0.3 and c0 < b:
                        b = c0 - 0.02
            low = y0 - 0.9 + (0.6 if (side == 0) == (torn > 0.5) else 0.0)
            m.on_wall(g, "Curtain", "curtain", axis, inner, out, a, b, max(low, y0 - 1.1), y1 + 0.32, 0.12, lift=0.06)
            m.on_wall(g, "CurtainFold", "curtain", axis, inner, out, a + 0.15, a + 0.32, max(low, y0 - 1.1) + 0.3, y1 + 0.28, 0.05, lift=0.18)
        m.on_wall(g, "Pole", "brass", axis, inner, out, u0 - 0.7, u1 + 0.7, y1 + 0.34, y1 + 0.4, 0.06, lift=0.22)
        # Cobwebs in an upper corner of some.
        if rng.random() < 0.45:
            c = u0 if rng.random() < 0.5 else u1
            web(m, g, axis, inner + out * 0.01, out, c, y1 - 0.02, 1 if c == u0 else -1)


def web(m, g, axis, face, out, u, y, along):
    """A cobweb across a corner: a few thin see-through strands (drawn only)."""
    for k in range(4):
        a = (u, y - 0.05 - 0.12 * k, face + out * 0.01)
        b = (u + along * (0.12 + 0.14 * k), y, face + out * 0.01)
        if axis == "z":
            a = (a[2], a[1], a[0])
            b = (b[2], b[1], b[0])
        m.rod(g, "Web", "cobweb", a, b, thick=0.008, wide=0.02)
    if axis == "x":
        m.strip(g, "WebSheet", "cobweb", (min(u, u + along * 0.4), y - 0.4, face + out * 0.006 - 0.003),
                (max(u, u + along * 0.4), y - 0.02, face + out * 0.006 + 0.003))
    else:
        m.strip(g, "WebSheet", "cobweb", (face + out * 0.006 - 0.003, y - 0.4, min(u, u + along * 0.4)),
                (face + out * 0.006 + 0.003, y - 0.02, max(u, u + along * 0.4)))


def front_door(m):
    g = m.group("FrontDoor", m.folder("Entrance"))
    x0, x1, y0, y1 = FRONT_DOOR
    z = ZS - OT * 0.5   # the inside face
    # Two heavy leaves, shut and nailed over (solid: part of the wall).
    m.box(g, "Leaves", "mahogany", (x0, 0.0, ZS - 0.12), (x1, y1, ZS + 0.12), unbreakable=True)
    for xa, xb in ((x0 + 0.12, -0.04), (0.04, x1 - 0.12)):
        for ya, yb in ((0.3, 1.3), (1.55, 2.75)):
            m.strip(g, "Panel", "wood_dark", (xa, ya, z - 0.08 + 0.0), (xb, yb, z - 0.04 + 0.0))
    m.strip(g, "Knocker", "brass", (-0.45, 1.4, z - 0.13), (-0.3, 1.6, z - 0.08))
    m.strip(g, "Knocker", "brass", (0.3, 1.4, z - 0.13), (0.45, 1.6, z - 0.08))
    for k, (ya, yb) in enumerate(((0.6, 1.0), (1.6, 1.9), (2.3, 2.7))):
        m.rod(g, "Board", "board", (x0 - 0.3, ya, z - 0.16), (x1 + 0.3, yb, z - 0.16), thick=0.05, wide=0.22)
    architrave(m, g, "x", z, -1, x0, x1, 0.0, y1)
    # The fanlight over it.
    m.box(g, "Fanlight", "glass_window", (x0, y1 + 0.2, ZS - 0.02), (x1, y1 + 0.9, ZS + 0.02), unbreakable=True)


# =====================================================================================
# The stairs and the gallery
# =====================================================================================

def banister(m, g, a, b, y0, y1, posts=True, solid=True, kind="banister"):
    """A rail from (x, z) `a` to `b`, its top rising from y0 + 1 to y1 + 1 (on a stair) or
    level: an invisible solid panel to lean on and turned balusters to look at."""
    ax, az = a
    bx, bz = b
    L = math.hypot(bx - ax, bz - az)
    if solid:
        m.slab(g, "Guard", kind, (ax, y0 + 1.0, az), (bx, y1 + 1.0, bz), 0.1, thick=1.0, drawn=False, unbreakable=True) \
            if abs(y1 - y0) > 0.01 else (m.box(g, "Guard", kind, (min(ax, bx) - (0.05 if abs(az - bz) > 0.01 else 0), y0, min(az, bz) - (0.05 if abs(ax - bx) > 0.01 else 0)),
                                               (max(ax, bx) + (0.05 if abs(az - bz) > 0.01 else 0), y0 + 1.0, max(az, bz) + (0.05 if abs(ax - bx) > 0.01 else 0)),
                                               drawn=False, unbreakable=True))
    m.rod(g, "Handrail", kind, (ax, y0 + 1.0, az), (bx, y1 + 1.0, bz), thick=0.08, wide=0.11)
    m.rod(g, "Bottomrail", kind, (ax, y0 + 0.12, az), (bx, y1 + 0.12, bz), thick=0.05, wide=0.08)
    n = max(2, int(L / 0.32))
    for i in range(1, n):
        t = i / n
        x, z, y = ax + (bx - ax) * t, az + (bz - az) * t, y0 + (y1 - y0) * t
        m.block(g, "Baluster", kind, (x, y + 0.56, z), (0.045, 0.86, 0.045), shape="cyl", sides=6, solid=False)
    if posts:
        for (x, z, y) in ((ax, az, y0), (bx, bz, y1)):
            m.box(g, "Newel", kind, (x - 0.09, y, z - 0.09), (x + 0.09, y + 1.18, z + 0.09), solid=False)
            m.block(g, "NewelCap", kind, (x, y + 1.26, z), (0.2, 0.16, 0.2), shape="dome", sides=8, solid=False)


def grand_stair(m):
    f = m.folder("GrandStair")
    g = m.group("Stair", f)
    x0, x1 = -STAIR_W / 2, STAIR_W / 2
    m.stairs(g, "Flight", (0, G, STAIR_FOOT), (0, U, STAIR_TOP), STAIR_W, kind="stair", rise=0.2)
    # The carpet runner up the middle, step by step (drawn only, a hair over the treads).
    n = int(math.ceil(U / 0.2 - 1e-6))
    for i in range(n):
        t1 = (i + 1) / n
        top = U * t1
        za = STAIR_FOOT + (STAIR_TOP - STAIR_FOOT) * i / n
        zb = STAIR_FOOT + (STAIR_TOP - STAIR_FOOT) * t1
        m.strip(g, "Runner", "runner", (-0.9, top, min(za, zb)), (0.9, top + 0.02, max(za, zb)))
        m.strip(g, "RunnerRod", "brass", (-0.95, top + 0.02, max(za, zb) - 0.04), (0.95, top + 0.045, max(za, zb) - 0.015))
        # Down the riser, too, so it reads as one carpet from the foot of the stair.
        face = 1.0 if za > zb else -1.0
        m.strip(g, "RunnerRiser", "runner", (-0.9, top - 0.2, min(za, za + face * 0.02)), (0.9, top, max(za, za + face * 0.02)))
    # Closed in under its lower half (where there is no headroom), open under the top.
    under = 4.75
    steps = 8
    for i in range(steps):
        za = under + (STAIR_FOOT - under) * i / steps
        zb = under + (STAIR_FOOT - under) * (i + 1) / steps
        top = U * (STAIR_FOOT - zb) / (STAIR_FOOT - STAIR_TOP) - 0.32
        if top > 0.2:
            m.box(g, "UnderFill", "wainscot", (x0 + 0.02, G, za), (x1 - 0.02, top, zb), unbreakable=True)
    # String boards along both sides, and the banisters.
    for x in (x0 - 0.06, x1 + 0.06):
        m.slab(g, "String", "wood_dark", (x, 0.25, STAIR_FOOT + 0.1), (x, U + 0.25, STAIR_TOP), 0.12, thick=0.45, solid=False)
        banister(m, g, (x, STAIR_FOOT), (x, STAIR_TOP), G + 0.2, U, posts=True)
    # The gallery's railing round the void (open where the stair arrives).
    rg = m.group("GalleryRail", f)
    banister(m, rg, (-3.0, STAIR_TOP), (-3.0, 9.0), U, U)
    banister(m, rg, (3.0, STAIR_TOP), (3.0, 9.0), U, U)
    banister(m, rg, (-3.0, 9.0), (3.0, 9.0), U, U)
    banister(m, rg, (-3.0, STAIR_TOP), (x0 - 0.06, STAIR_TOP), U, U)
    banister(m, rg, (x1 + 0.06, STAIR_TOP), (3.0, STAIR_TOP), U, U)
    # The gallery's edge: a moulded fascia round the void.
    # (a centimetre proud of the floor's edge, so its face and the edge's are not one plane)
    for (lo, hi) in (((-3.06, CG - 0.12, STAIR_TOP), (-2.99, U + 0.04, 9.06)), ((2.99, CG - 0.12, STAIR_TOP), (3.06, U + 0.04, 9.06)),
                     ((-2.99, CG - 0.12, 8.99), (2.99, U + 0.04, 9.06)), ((-2.99, CG - 0.12, STAIR_TOP - 0.06), (x0, U + 0.04, STAIR_TOP + 0.01)),
                     ((x1, CG - 0.12, STAIR_TOP - 0.06), (2.99, U + 0.04, STAIR_TOP + 0.01))):
        m.strip(rg, "Fascia", "moulding", lo, hi)
    # Columns under the gallery's north corners (the south ones hang from carved brackets,
    # so the way round the stair's foot stays wide enough to walk).
    for (x, z) in ((-3.0, 1.0), (3.0, 1.0)):
        m.cyl(rg, "Column", "marble_white", (x, G, z), 0.24, CG - 0.25, sides=12, unbreakable=True)
        m.box(rg, "ColumnBase", "marble_white", (x - 0.2, G, z - 0.2), (x + 0.2, 0.18, z + 0.2), solid=False)
        m.box(rg, "ColumnCap", "marble_white", (x - 0.22, CG - 0.25, z - 0.22), (x + 0.22, CG - 0.01, z + 0.22), solid=False)
    for x in (-3.0, 3.0):
        m.box(rg, "Bracket", "moulding", (x - 0.16, CG - 0.7, 8.84), (x + 0.16, CG - 0.12, 9.16), solid=False)
        m.block(rg, "BracketDrop", "moulding", (x, CG - 0.78, 9.0), (0.18, 0.16, 0.18), shape="dome", sides=8, solid=False)


def servants_stair(m):
    f = m.folder("ServantsStair")
    g = m.group("Stair", f)
    zc = (SS_Z0 + SS_Z1) * 0.5
    m.stairs(g, "Flight", (SS_X0, G, zc), (SS_X1, U, zc), SS_Z1 - SS_Z0, kind="stair", rise=0.2, cheeks=(False, True), side="wood_dark")
    # A banister on its open side, from where it is high enough to need one.
    t0 = (-2.6 - SS_X0) / (SS_X1 - SS_X0)
    banister(m, g, (-2.6, SS_Z1 + 0.1), (SS_X1, SS_Z1 + 0.1), G + U * t0, U)
    # The hole above it, railed round on the upper floor.
    h = m.group("HoleRail", f)
    banister(m, h, (SS_HOLE_X0, SS_Z1 + 0.05), (SS_HOLE_X0 + 0.6, SS_Z1 + 0.05), U, U)
    banister(m, h, (SS_HOLE_X0 - 0.05, SS_Z0 + 0.3), (SS_HOLE_X0 - 0.05, SS_Z1), U, U)
    m.strip(h, "HoleEdge", "moulding", (SS_HOLE_X0 - 0.05, CG - 0.1, SS_Z1 - 0.02), (SS_X1 + 0.01, U + 0.03, SS_Z1 + 0.05))


def bedroom_hole(m):
    """The rotten patch in the Bedroom's floor that fell in: a hole into the Dining Room,
    broken boards hanging into it and the wreck on the floor below."""
    g = m.group("FloorHole", m.folder("Bedroom"))
    x0, z0, x1, z1 = HOLE
    rng = random.Random(9)
    # Jagged board ends round the rim (drawn only) and joists across.
    for k in range(9):
        x = x0 + (x1 - x0) * (k + 0.5) / 9
        m.strip(g, "BoardEnd", "floor_oak", (x - 0.1, U - 0.04, z0 - 0.02), (x + 0.1, U - 0.005, z0 + rng.uniform(0.05, 0.4)))
        m.strip(g, "BoardEnd", "floor_oak", (x - 0.1, U - 0.04, z1 - rng.uniform(0.05, 0.4)), (x + 0.1, U - 0.005, z1 + 0.02))
    m.box(g, "Joist", "wood_dark", (x0 + 0.6, CG - 0.12, z0), (x0 + 0.78, U - 0.06, z1), solid=False)
    m.rod(g, "Hanging", "floor_oak", (x1 - 0.4, U - 0.05, z0 + 0.3), (x1 - 0.9, CG - 1.1, z0 + 0.9), thick=0.04, wide=0.2)
    m.rod(g, "Hanging", "floor_oak", (x0 + 1.2, U - 0.05, z1 - 0.2), (x0 + 1.6, CG - 0.8, z1 - 0.9), thick=0.04, wide=0.2)
    # What fell: a heap of boards and plaster on the dining room floor (a low solid heap).
    cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
    m.bev(g, "Heap", "rubble", (cx - 0.9, G, cz - 0.7), (cx + 0.7, 0.45, cz + 0.8), bevel=0.2)
    for k in range(9):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.5, 1.4)
        px, pz = cx + math.cos(a) * r, cz + math.sin(a) * r
        w = rng.uniform(0.12, 0.3)
        m.bev(g, "Chunk", "plaster" if k % 3 else "rubble", (px - w, G, pz - w * 0.8), (px + w, G + rng.uniform(0.06, 0.18), pz + w * 0.8), bevel=0.04, solid=False)
    for k in range(7):
        a = rng.uniform(0, math.pi)
        r = rng.uniform(0.3, 1.2)
        px, pz = cx + math.cos(a) * r, cz + math.sin(a) * r
        m.rod(g, "Debris", "floor_oak", (px - 0.5, rng.uniform(0.05, 0.5), pz - 0.2), (px + 0.5, rng.uniform(0.05, 0.6), pz + 0.3), thick=0.04, wide=0.16)


# =====================================================================================
# Furniture (each built in its own frame: origin at the middle of its foot)
# =====================================================================================

def table(m, g, L, W, H, top_kind="mahogany", leg_kind="wood_dark", cloth=None, solid=True):
    m.bev(g, "Top", top_kind, (-L / 2, H - 0.08, -W / 2), (L / 2, H, W / 2), bevel=0.03, solid=solid)
    m.box(g, "Apron", leg_kind, (-L / 2 + 0.08, H - 0.2, -W / 2 + 0.08), (L / 2 - 0.08, H - 0.08, W / 2 - 0.08), solid=False)
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * (L / 2 - 0.12), sz * (W / 2 - 0.12)
            m.block(g, "Leg", leg_kind, (x, (H - 0.08) / 2, z), (0.09, H - 0.08, 0.09), shape="cone", top=0.12, sides=8, solid=False)
    if cloth:
        m.strip(g, "Cloth", cloth, (-L / 2 + 0.1, H, -W / 2 - 0.03), (L / 2 - 0.1, H + 0.012, W / 2 + 0.03))
        m.strip(g, "ClothHang", cloth, (-L / 2 + 0.1, H - 0.28, W / 2 + 0.03), (L / 2 - 0.1, H, W / 2 + 0.045))
        m.strip(g, "ClothHang", cloth, (-L / 2 + 0.1, H - 0.28, -W / 2 - 0.045), (L / 2 - 0.1, H, -W / 2 - 0.03))


def chair(m, g, kind="wood_dark", seat="fabric_red", solid=False, yaw=0.0):
    c = rot(yaw)

    def P(x, y, z):
        return (x * c[0][0] + z * c[2][0], y, x * c[0][2] + z * c[2][2])
    m.block(g, "Seat", seat, P(0, 0.47, 0), (0.48, 0.08, 0.46), cols=c, shape="bevel", bevel=0.02, solid=solid)
    m.block(g, "SeatFrame", kind, P(0, 0.41, 0), (0.5, 0.05, 0.48), cols=c, solid=False)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.block(g, "Leg", kind, P(sx * 0.2, 0.2, sz * 0.19), (0.05, 0.4, 0.05), cols=c, solid=False)
    m.block(g, "Back", kind, P(0, 0.95, 0.21), (0.46, 0.9, 0.05), cols=c, solid=False)
    m.block(g, "BackPad", seat, P(0, 0.98, 0.18), (0.34, 0.6, 0.02), cols=c, solid=False)
    m.block(g, "Crest", kind, P(0, 1.42, 0.21), (0.52, 0.08, 0.07), cols=c, shape="bevel", bevel=0.02, solid=False)


def candle(m, g, x, y, z, tall=0.18):
    m.cyl(g, "Candle", "candle", (x, y, z), 0.035, tall, sides=6, solid=False)
    m.cone(g, "Flame", "flame", (x, y + tall + 0.005, z), 0.03, 0.06, sides=5, solid=False)
    # A drip of wax.
    m.cyl(g, "Wax", "candle", (x + 0.015, y + tall * 0.4, z), 0.015, tall * 0.45, sides=4, solid=False)


def candelabra(m, g, x, y, z, arms=3):
    m.cyl(g, "Foot", "brass", (x, y, z), 0.14, 0.03, sides=8, solid=False)
    m.cyl(g, "Stem", "brass", (x, y, z), 0.035, 0.36, sides=6, solid=False)
    m.box(g, "Arm", "brass", (x - 0.16, y + 0.32, z - 0.015), (x + 0.16, y + 0.35, z + 0.015), solid=False)
    for k in range(arms):
        cx = x - 0.16 + 0.32 * k / max(arms - 1, 1)
        m.cyl(g, "Cup", "brass", (cx, y + 0.35, z), 0.06, 0.03, sides=6, solid=False)
        candle(m, g, cx, y + 0.38, z, 0.14)


def book_row(m, g, x0, x1, y, z0, z1, rng, axis="x", lean=True):
    """Books standing in a row along x (or z) between x0..x1, on a shelf at height y, their
    spines facing +z (the row's depth z0..z1)."""
    kinds = ["book_red", "book_green", "book_blue", "book_brown", "book_black"]
    u = x0 + 0.01
    while u < x1 - 0.06:
        w = rng.uniform(0.04, 0.09)
        h = rng.uniform(0.22, 0.34)
        if u + w > x1 - 0.01:
            break
        d = rng.uniform(0.75, 0.95) * (z1 - z0)
        if rng.random() < 0.07:
            u += rng.uniform(0.05, 0.15)   # a gap
            continue
        k = rng.choice(kinds)
        if axis == "x":
            m.strip(g, "Book", k, (u, y, z1 - d), (u + w - 0.004, y + h, z1 - 0.004))
        else:
            m.strip(g, "Book", k, (z1 - d, y, u), (z1 - 0.004, y + h, u + w - 0.004))
        u += w


def bookcase(m, g, W, H, D, rng, kind="wood_dark", face="+z", books=True, solid=True):
    """A bookcase in its own frame, its back on z = -D/2 and its open face toward +z
    (turn the group for other ways)."""
    m.box(g, "Carcass", kind, (-W / 2, 0.0, -D / 2), (W / 2, H, -D / 2 + 0.04), solid=solid)
    for s in (-1, 1):
        m.box(g, "Side", kind, (s * W / 2 - 0.04 * (s > 0), 0.0, -D / 2) if s < 0 else (W / 2 - 0.04, 0.0, -D / 2),
              (-W / 2 + 0.04, H, D / 2) if s < 0 else (W / 2, H, D / 2), solid=solid)
    m.box(g, "Top", kind, (-W / 2 - 0.05, H, -D / 2 - 0.03), (W / 2 + 0.05, H + 0.08, D / 2 + 0.04), solid=False)
    m.box(g, "Plinth", "wood_dark", (-W / 2 + 0.04, 0.0, -D / 2 + 0.04), (W / 2 - 0.04, 0.12, D / 2 - 0.02), solid=solid)
    shelves = max(2, int((H - 0.2) / 0.42))
    for i in range(shelves):
        y = 0.12 + (H - 0.2) * i / shelves
        m.box(g, "Shelf", kind, (-W / 2 + 0.04, y, -D / 2 + 0.04), (W / 2 - 0.04, y + 0.03, D / 2 - 0.02), solid=False)
        if books:
            book_row(m, g, -W / 2 + 0.05, W / 2 - 0.05, y + 0.03, -D / 2 + 0.05, D / 2 - 0.04, rng)
    # A solid back face for cover (its front is open, its books drawn only).
    if solid:
        m.box(g, "Fill", kind, (-W / 2 + 0.04, 0.12, -D / 2 + 0.04), (W / 2 - 0.04, H, -D / 2 + 0.2), drawn=False)


def armchair(m, g, fabric="fabric_green", solid=True):
    m.bev(g, "Base", fabric, (-0.45, 0.12, -0.42), (0.45, 0.45, 0.42), bevel=0.06, solid=solid)
    m.bev(g, "Cushion", fabric, (-0.33, 0.45, -0.38), (0.33, 0.58, 0.3), bevel=0.05, solid=False)
    m.bev(g, "Back", fabric, (-0.45, 0.45, 0.28), (0.45, 1.15, 0.44), bevel=0.06, solid=solid)
    for s in (-1, 1):
        m.bev(g, "Arm", fabric, (s * 0.45 - (0.14 if s > 0 else 0), 0.45, -0.42), (s * 0.45 + (0.14 if s < 0 else 0), 0.72, 0.3), bevel=0.05, solid=False)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.cyl(g, "Foot", "wood_dark", (sx * 0.38, 0.0, sz * 0.35), 0.07, 0.12, sides=6, solid=False)


def sofa(m, g, L=2.2, fabric="fabric_red", solid=True):
    m.bev(g, "Base", fabric, (-L / 2, 0.15, -0.45), (L / 2, 0.45, 0.45), bevel=0.06, solid=solid)
    for k in range(3):
        a = -L / 2 + 0.18 + (L - 0.36) * k / 3
        m.bev(g, "Cushion", fabric, (a + 0.01, 0.45, -0.4), (a + (L - 0.36) / 3 - 0.01, 0.6, 0.28), bevel=0.05, solid=False)
    m.bev(g, "Back", fabric, (-L / 2, 0.45, 0.26), (L / 2, 1.05, 0.45), bevel=0.06, solid=solid)
    for s in (-1, 1):
        m.bev(g, "Arm", fabric, (s * L / 2 - (0.2 if s > 0 else 0), 0.45, -0.45), (s * L / 2 + (0.2 if s < 0 else 0), 0.78, 0.4), bevel=0.07, solid=False)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.cone(g, "Foot", "wood_dark", (sx * (L / 2 - 0.1), 0.0, sz * 0.36), 0.06, 0.15, top=0.09, sides=6, solid=False)


def grand_piano(m, g):
    """A grand piano, keyboard toward -z."""
    m.bev(g, "Case", "black", (-0.75, 0.68, -0.8), (0.75, 1.0, 0.6), bevel=0.04)
    m.bev(g, "Tail", "black", (-0.75, 0.68, 0.6), (0.3, 1.0, 1.25), bevel=0.04)
    m.block(g, "TailRound", "black", (0.2, 0.84, 0.75), (1.1, 0.32, 1.1), shape="cyl", sides=16, solid=False)
    m.slab(g, "Lid", "black", (-0.72, 1.02, 0.9), (-0.72, 1.85, -0.5), 0.04, thick=1.3, solid=False) if False else None
    m.rod(g, "Lid", "black", (0.0, 1.03, 1.1), (0.0, 1.75, -0.4), thick=0.03, wide=1.45)
    m.rod(g, "Prop", "brass", (0.6, 1.0, 0.1), (0.6, 1.55, 0.1), thick=0.02)
    m.box(g, "Keybed", "black", (-0.72, 0.68, -1.05), (0.72, 0.82, -0.8), solid=False)
    m.box(g, "Keys", "porcelain", (-0.68, 0.82, -1.02), (0.68, 0.85, -0.85), solid=False)
    for k in range(22):
        x = -0.65 + 1.3 * k / 22
        if k % 7 in (2, 6):
            continue
        m.box(g, "Sharp", "black", (x, 0.85, -0.98), (x + 0.025, 0.875, -0.88), solid=False)
    m.box(g, "MusicStand", "black", (-0.4, 1.0, -0.78), (0.4, 1.3, -0.74), solid=False)
    m.strip(g, "Score", "paper", (-0.3, 1.04, -0.785), (0.25, 1.26, -0.78))
    for (x, z) in ((-0.62, -0.7), (0.62, -0.7), (-0.1, 1.1)):
        m.cone(g, "Leg", "black", (x, 0.0, z), 0.12, 0.68, top=0.16, sides=8, solid=False)
        m.cyl(g, "Caster", "brass", (x, -0.01, z), 0.09, 0.05, sides=6, solid=False)
    m.box(g, "Lyre", "black", (-0.06, 0.1, -0.62), (0.06, 0.68, -0.58), solid=False)
    m.box(g, "Pedals", "brass", (-0.12, 0.05, -0.68), (0.12, 0.08, -0.6), solid=False)


def four_poster(m, g):
    """A four-poster bed, its head toward -x."""
    L, W = 2.3, 1.7
    m.bev(g, "Frame", "mahogany", (-L / 2, 0.25, -W / 2), (L / 2, 0.5, W / 2), bevel=0.04)
    m.bev(g, "Mattress", "linen", (-L / 2 + 0.06, 0.5, -W / 2 + 0.05), (L / 2 - 0.05, 0.72, W / 2 - 0.05), bevel=0.06, solid=False)
    m.bev(g, "Cover", "fabric_purple", (-L / 2 + 0.6, 0.71, -W / 2 + 0.02), (L / 2 - 0.02, 0.78, W / 2 - 0.02), bevel=0.03, solid=False)
    m.strip(g, "CoverHang", "fabric_purple", (-L / 2 + 0.6, 0.3, W / 2 - 0.04), (L / 2 - 0.02, 0.72, W / 2 - 0.01))
    m.strip(g, "CoverHang", "fabric_purple", (-L / 2 + 0.6, 0.3, -W / 2 + 0.01), (L / 2 - 0.02, 0.72, -W / 2 + 0.04))
    for k in (-1, 1):
        m.bev(g, "Pillow", "linen", (-L / 2 + 0.12, 0.72, k * 0.4 - 0.32), (-L / 2 + 0.55, 0.88, k * 0.4 + 0.32), bevel=0.06, solid=False)
    m.box(g, "Headboard", "mahogany", (-L / 2 - 0.06, 0.25, -W / 2 + 0.06), (-L / 2 + 0.02, 1.5, W / 2 - 0.06))
    m.box(g, "Footboard", "mahogany", (L / 2 - 0.05, 0.25, -W / 2 + 0.06), (L / 2 + 0.03, 0.95, W / 2 - 0.06), solid=False)
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * (L / 2), sz * (W / 2)
            m.cyl(g, "Post", "mahogany", (x, 0.0, z), 0.11, 2.25, sides=8, solid=False)
            m.dome(g, "Finial", "brass", (x, 2.25, z), (0.13, 0.12, 0.13), sides=8, solid=False)
    m.box(g, "Canopy", "mahogany", (-L / 2 - 0.05, 2.1, -W / 2 - 0.05), (L / 2 + 0.05, 2.18, W / 2 + 0.05), solid=False)
    m.strip(g, "CanopyCloth", "fabric_purple", (-L / 2 + 0.05, 2.05, -W / 2 + 0.05), (L / 2 - 0.05, 2.1, W / 2 - 0.05))
    for sz in (-1, 1):
        z = sz * (W / 2 - 0.02)
        m.strip(g, "Drape", "fabric_purple", (-L / 2 + 0.05, 0.9, z - 0.015), (-L / 2 + 0.45, 2.05, z + 0.015))
        m.strip(g, "Drape", "fabric_purple", (L / 2 - 0.4, 1.1, z - 0.015), (L / 2 - 0.05, 2.05, z + 0.015))
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.cone(g, "Foot", "mahogany", (sx * (L / 2 - 0.1), 0.0, sz * (W / 2 - 0.1)), 0.1, 0.25, top=0.14, sides=6, solid=False)


def wardrobe(m, g, W=1.4, H=2.3, D=0.65, kind="mahogany"):
    """A wardrobe, its doors toward +z."""
    m.bev(g, "Body", kind, (-W / 2, 0.12, -D / 2), (W / 2, H, D / 2), bevel=0.03)
    m.box(g, "Cornice", kind, (-W / 2 - 0.06, H, -D / 2 - 0.04), (W / 2 + 0.06, H + 0.12, D / 2 + 0.06), solid=False)
    m.box(g, "Plinth", "wood_dark", (-W / 2 + 0.03, 0.0, -D / 2 + 0.03), (W / 2 - 0.03, 0.12, D / 2 - 0.02), solid=False)
    for s in (-1, 1):
        a, b = (-W / 2 + 0.06, -0.02) if s < 0 else (0.02, W / 2 - 0.06)
        m.box(g, "Door", "wood_dark", (a, 0.25, D / 2), (b, H - 0.12, D / 2 + 0.025), solid=False)
        m.box(g, "Mirror", "mirror", (a + 0.1, 0.6, D / 2 + 0.025), (b - 0.1, H - 0.4, D / 2 + 0.035), solid=False)
        m.box(g, "Handle", "brass", (s * 0.06 - 0.015, 1.1, D / 2 + 0.035), (s * 0.06 + 0.015, 1.3, D / 2 + 0.06), solid=False)


def dresser(m, g, W=1.3, H=0.95, D=0.5, kind="mahogany"):
    m.bev(g, "Body", kind, (-W / 2, 0.1, -D / 2), (W / 2, H, D / 2), bevel=0.03)
    m.box(g, "Top", kind, (-W / 2 - 0.04, H, -D / 2 - 0.03), (W / 2 + 0.04, H + 0.04, D / 2 + 0.03), solid=False)
    for k in range(3):
        y0 = 0.16 + (H - 0.2) * k / 3
        y1 = 0.16 + (H - 0.2) * (k + 1) / 3 - 0.03
        m.box(g, "Drawer", "wood_dark", (-W / 2 + 0.05, y0, D / 2), (W / 2 - 0.05, y1, D / 2 + 0.02), solid=False)
        for s in (-1, 1):
            m.box(g, "Pull", "brass", (s * W / 4 - 0.05, (y0 + y1) / 2 - 0.015, D / 2 + 0.02), (s * W / 4 + 0.05, (y0 + y1) / 2 + 0.015, D / 2 + 0.04), solid=False)


def clock(m, g):
    """A grandfather clock, its face toward +z."""
    m.bev(g, "Case", "mahogany", (-0.28, 0.0, -0.2), (0.28, 1.9, 0.2), bevel=0.03)
    m.bev(g, "Hood", "mahogany", (-0.33, 1.9, -0.23), (0.33, 2.45, 0.23), bevel=0.04, solid=False)
    m.dome(g, "Crest", "mahogany", (0.0, 2.45, 0.0), (0.6, 0.18, 0.4), sides=10, solid=False)
    m.block(g, "Face", "paper", (0.0, 2.17, 0.235), (0.4, 0.4, 0.01), cols=((1, 0, 0), (0, 0, 1), (0, -1, 0)), shape="cyl", sides=16, solid=False)
    m.box(g, "HandHour", "black", (-0.01, 2.17, 0.24), (0.11, 2.19, 0.248), solid=False)
    m.box(g, "HandMinute", "black", (-0.01, 2.02, 0.24), (0.01, 2.2, 0.248), solid=False)
    m.box(g, "Window", "glass_window", (-0.15, 0.6, 0.2), (0.15, 1.6, 0.215), solid=False)
    m.box(g, "Pendulum", "brass", (-0.012, 0.85, 0.15), (0.012, 1.55, 0.17), solid=False)
    m.cyl(g, "Bob", "brass", (0.0, 0.8, 0.16), 0.14, 0.02, sides=10, solid=False)


def armour(m, g):
    """A suit of armour on a stand, facing +z."""
    m.box(g, "Stand", "wood_dark", (-0.3, 0.0, -0.3), (0.3, 0.12, 0.3))
    for s in (-1, 1):
        m.cone(g, "Leg", "steel", (s * 0.12, 0.12, 0.0), 0.16, 0.85, top=0.2, sides=8, solid=False)
        m.box(g, "Sabaton", "steel", (s * 0.12 - 0.07, 0.12, -0.05), (s * 0.12 + 0.07, 0.2, 0.2), solid=False)
    m.bev(g, "Tasset", "steel", (-0.24, 0.92, -0.14), (0.24, 1.12, 0.16), bevel=0.04, solid=False)
    m.block(g, "Breastplate", "steel", (0.0, 1.38, 0.0), (0.52, 0.55, 0.34), shape="cyl", sides=10, solid=False)
    for s in (-1, 1):
        m.dome(g, "Pauldron", "steel", (s * 0.3, 1.6, 0.0), (0.24, 0.14, 0.26), sides=8, solid=False)
        m.cyl(g, "Arm", "steel", (s * 0.33, 1.0, 0.04), 0.11, 0.58, sides=8, solid=False)
        m.box(g, "Gauntlet", "steel", (s * 0.33 - 0.06, 0.9, 0.0), (s * 0.33 + 0.06, 1.02, 0.12), solid=False)
    m.cyl(g, "Gorget", "steel", (0.0, 1.64, 0.0), 0.2, 0.08, sides=10, solid=False)
    m.block(g, "Helm", "steel", (0.0, 1.82, 0.0), (0.26, 0.3, 0.28), shape="cyl", sides=10, solid=False)
    m.dome(g, "HelmTop", "steel", (0.0, 1.97, 0.0), (0.26, 0.12, 0.28), sides=10, solid=False)
    m.box(g, "Visor", "black", (-0.09, 1.82, 0.13), (0.09, 1.86, 0.145), solid=False)
    m.box(g, "Eyes", "eye_glow", (-0.07, 1.83, 0.141), (0.07, 1.85, 0.147), solid=False)
    m.dome(g, "Plume", "fabric_red", (0.0, 2.08, -0.04), (0.08, 0.3, 0.2), sides=6, solid=False)
    # Its halberd.
    m.cyl(g, "Shaft", "wood_dark", (0.42, 0.12, 0.08), 0.04, 2.3, sides=6, solid=False)
    m.box(g, "Blade", "steel", (0.44, 2.05, 0.06), (0.62, 2.35, 0.1), solid=False)
    m.cone(g, "Spike", "steel", (0.42, 2.42, 0.08), 0.06, 0.25, sides=6, solid=False)


def portrait(m, g, axis, face, out, u, y, w, h, rng, eyes=True):
    """An oil portrait in a gilt frame on a wall: someone pale, whose eyes glow."""
    m.on_wall(g, "Frame", "frame", axis, face, out, u - w / 2 - 0.09, u + w / 2 + 0.09, y - 0.09, y + h + 0.09, 0.05)
    m.on_wall(g, "Canvas", "canvas", axis, face, out, u - w / 2, u + w / 2, y, y + h, 0.02, lift=0.05)
    # The sitter: a dark coat and a pale face.
    m.on_wall(g, "Coat", "black", axis, face, out, u - w * 0.35, u + w * 0.35, y, y + h * 0.42, 0.01, lift=0.07)
    m.on_wall(g, "Face", "face", axis, face, out, u - w * 0.14, u + w * 0.14, y + h * 0.46, y + h * 0.78, 0.01, lift=0.07)
    m.on_wall(g, "Hair", "black", axis, face, out, u - w * 0.16, u + w * 0.16, y + h * 0.75, y + h * 0.86, 0.02, lift=0.07)
    if eyes:
        for s in (-1, 1):
            e = u + s * w * 0.06
            m.on_wall(g, "Eye", "eye_glow", axis, face, out, e - 0.015, e + 0.015, y + h * 0.64, y + h * 0.67, 0.006, lift=0.08)
    # A little brass plaque.
    m.on_wall(g, "Plaque", "brass", axis, face, out, u - 0.1, u + 0.1, y - 0.2, y - 0.13, 0.02)


def sconce(m, g, axis, face, out, u, y):
    """A wall candle on a brass arm."""
    m.on_wall(g, "Plate", "brass", axis, face, out, u - 0.05, u + 0.05, y - 0.12, y + 0.06, 0.02)
    p = (u, y, face + out * 0.15) if axis == "x" else (face + out * 0.15, y, u)
    m.cyl(g, "Cup", "brass", p, 0.08, 0.03, sides=6, solid=False)
    m.rod(g, "Arm", "brass", ((u, y - 0.05, face + out * 0.02) if axis == "x" else (face + out * 0.02, y - 0.05, u)),
          (p[0], p[1] + 0.005, p[2]), thick=0.02)
    candle(m, g, p[0], p[1] + 0.03, p[2], 0.15)


def rug(m, g, x0, z0, x1, z1, y, kind="rug_red", border="rug_border"):
    m.strip(g, "Rug", kind, (x0, y, z0), (x1, y + 0.02, z1))
    m.strip(g, "RugBorder", border, (x0 + 0.12, y + 0.02, z0 + 0.12), (x1 - 0.12, y + 0.026, z0 + 0.22))
    m.strip(g, "RugBorder", border, (x0 + 0.12, y + 0.02, z1 - 0.22), (x1 - 0.12, y + 0.026, z1 - 0.12))
    m.strip(g, "RugBorder", border, (x0 + 0.12, y + 0.02, z0 + 0.22), (x0 + 0.22, y + 0.026, z1 - 0.22))
    m.strip(g, "RugBorder", border, (x1 - 0.22, y + 0.02, z0 + 0.22), (x1 - 0.12, y + 0.026, z1 - 0.22))
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    m.strip(g, "RugMedallion", border, (cx - 0.35, y + 0.02, cz - 0.35), (cx + 0.35, y + 0.026, cz + 0.35))


def chandelier(m, g, arms=8, r=0.9):
    """A chandelier in its own frame (origin at the bottom of its bowl): drawn only."""
    m.cyl(g, "Chain", "iron", (0, 0.4, 0), 0.04, 2.0, sides=4, solid=False)
    m.dome(g, "Bowl", "brass", (0, 0.4, 0), (0.5, 0.4, 0.5), sides=10, flip=True, solid=False)
    m.block(g, "Ring", "brass", (0, 0.35, 0), (r * 2, 0.05, r * 2), shape="tube", sides=16, inner=r * 2 - 0.08, solid=False)
    m.block(g, "Ring2", "brass", (0, 0.75, 0), (r * 1.2, 0.04, r * 1.2), shape="tube", sides=12, inner=r * 1.2 - 0.06, solid=False)
    for k in range(arms):
        a = math.tau * k / arms
        x, z = math.cos(a) * r, math.sin(a) * r
        m.rod(g, "Arm", "brass", (0, 0.1, 0), (x, 0.36, z), thick=0.03)
        m.cyl(g, "Cup", "brass", (x, 0.38, z), 0.09, 0.03, sides=6, solid=False)
        candle(m, g, x, 0.41, z, 0.16)
        m.rod(g, "Crystal", "glass_window", (x, 0.34, z), (x, 0.12, z), thick=0.025)
        x2, z2 = math.cos(a + 0.4) * r * 0.6, math.sin(a + 0.4) * r * 0.6
        candle(m, g, x2, 0.78, z2, 0.12)
    # Cobwebs strung from it.
    for k in range(3):
        a = math.tau * k / 3 + 0.3
        m.rod(g, "Web", "cobweb", (math.cos(a) * r, 0.4, math.sin(a) * r), (math.cos(a + 0.9) * r, 0.2, math.sin(a + 0.9) * r), thick=0.006, wide=0.03)


def fireplace(m, g, axis, face, out, u, y, wide=2.2):
    """A fireplace on a wall: a stone chimney breast (solid), a black opening with a fire
    (glowing), a mantel with candles and a clock, and a mirror over it."""
    d = 0.6
    if axis == "z":
        lo = (min(face, face + out * d), y, u - wide / 2)
        hi = (max(face, face + out * d), y + 3.7 - 0.25, u + wide / 2)
        m.box(g, "Breast", "brick", lo, hi, unbreakable=True)
        fx = face + out * d
        m.box(g, "Surround", "stone", (min(fx, fx + out * 0.08), y, u - wide / 2 + 0.2), (max(fx, fx + out * 0.08), y + 1.25, u + wide / 2 - 0.2), solid=False)
        m.box(g, "Opening", "soot", (min(fx + out * 0.081, fx + out * 0.09), y, u - 0.55), (max(fx + out * 0.081, fx + out * 0.09), y + 0.95, u + 0.55), solid=False)
        m.box(g, "Mantel", "wood_dark", (min(fx, fx + out * 0.3), y + 1.25, u - wide / 2 + 0.05), (max(fx, fx + out * 0.3), y + 1.35, u + wide / 2 - 0.05), solid=False)
        m.box(g, "Hearth", "stone", (min(fx, fx + out * 0.55), y, u - wide / 2 + 0.1), (max(fx, fx + out * 0.55), y + 0.06, u + wide / 2 - 0.1), solid=False)
        m.box(g, "MirrorFrame", "frame", (min(fx, fx + out * 0.04), y + 1.6, u - 0.6), (max(fx, fx + out * 0.04), y + 2.8, u + 0.6), solid=False)
        m.box(g, "Mirror", "mirror", (min(fx + out * 0.04, fx + out * 0.055), y + 1.7, u - 0.5), (max(fx + out * 0.04, fx + out * 0.055), y + 2.7, u + 0.5), solid=False)
        # The fire: logs and flames, in front of the black.
        bx = fx + out * 0.25
        for k in range(3):
            m.lying_cyl(g, "Log", "wood_dark", (bx + out * 0.05 * k, y + 0.1 + 0.08 * (k == 2), u - 0.15 + 0.15 * k), 0.12, 0.7, axis="z", solid=False)
        m.box(g, "Embers", "ember", (min(bx - 0.15, bx + 0.15), y + 0.03, u - 0.32), (max(bx - 0.15, bx + 0.15), y + 0.08, u + 0.32), solid=False)
        for k in range(5):
            m.cone(g, "Flame", "flame", (bx, y + 0.16, u - 0.3 + 0.15 * k), 0.14, 0.3 + 0.12 * (k % 2), sides=5, solid=False)
        m.box(g, "Grate", "iron", (min(bx + out * 0.2, bx + out * 0.24), y, u - 0.45), (max(bx + out * 0.2, bx + out * 0.24), y + 0.3, u + 0.45), solid=False)
        mx = fx + out * 0.15
        candelabra(m, g, mx, y + 1.35, u - 0.7)
        candelabra(m, g, mx, y + 1.35, u + 0.7)
        m.box(g, "MantelClock", "mahogany", (mx - 0.1, y + 1.35, u - 0.15), (mx + 0.1, y + 1.62, u + 0.15), solid=False)
        m.block(g, "ClockFace", "paper", (mx + out * 0.105, y + 1.5, u), (0.16, 0.01, 0.16), cols=((0, 1, 0), (1, 0, 0), (0, 0, 1)), shape="cyl", sides=12, solid=False)
        # Fire irons.
        m.cyl(g, "Irons", "iron", (fx + out * 0.4, y, u + wide / 2 - 0.25), 0.03, 0.8, sides=4, solid=False)
        m.cyl(g, "Irons", "iron", (fx + out * 0.42, y, u + wide / 2 - 0.3), 0.03, 0.75, sides=4, solid=False)
        return (fx + out * 0.35, y + 0.6, u)
    raise ValueError("fireplaces are on walls along z")


# =====================================================================================
# The rooms' contents
# =====================================================================================

def foyer(m):
    f = m.folder("Foyer")
    rng = random.Random(3)
    g = m.group("Dressing", f)
    rug(m, g, -2.4, 8.9, 2.4, 10.5, G, "rug_red")
    # The grandfather clock under the west gallery, the umbrella stand, the coat rack.
    c = m.group("Clock", f, at=(-4.6, G, 3.0), yaw=-math.pi / 2)
    clock(m, c)
    m.cyl(g, "UmbrellaStand", "porcelain", (4.4, G, 10.2), 0.3, 0.6, sides=10, solid=False)
    for k in range(3):
        m.rod(g, "Umbrella", "black", (4.4 + 0.05 * k - 0.05, 0.1, 10.2), (4.3 + 0.1 * k, 0.95, 10.25 - 0.05 * k), thick=0.04)
    m.cyl(g, "CoatRack", "wood_dark", (-4.4, G, 10.3), 0.06, 1.9, sides=6, solid=False)
    for k in range(4):
        a = k * math.pi / 2
        m.rod(g, "Hook", "brass", (-4.4, 1.8, 10.3), (-4.4 + 0.25 * math.cos(a), 1.9, 10.3 + 0.25 * math.sin(a)), thick=0.025)
    m.cone(g, "RackFoot", "wood_dark", (-4.4, G, 10.3), 0.4, 0.1, sides=6, solid=False)
    m.box(g, "Coat", "black", (-4.65, 0.9, 10.15), (-4.45, 1.75, 10.5), solid=False)
    # Suits of armour either side of the stair's foot (solid: a little cover).
    for x in (-2.3, 2.3):
        a = m.group("Armour", f, at=(x, G, 8.2))
        armour(m, a)
    # Portraits round the gallery, sconces under it.
    for z in (3.5, 8.0):
        portrait(m, g, "z", -XI + 0.15, 1, z, U + 1.4, 0.8, 1.1, rng)
        portrait(m, g, "z", XI - 0.15, -1, z, U + 1.4, 0.8, 1.1, rng)
    portrait(m, g, "x", ZI + 0.15, 1, -3.0, U + 1.3, 1.0, 1.3, rng)
    portrait(m, g, "x", ZI + 0.15, 1, 3.0, U + 1.3, 1.0, 1.3, rng)
    for z in (2.2, 8.0):
        sconce(m, g, "z", -XI + 0.15, 1, z + 0.6, 2.2)
        sconce(m, g, "z", XI - 0.15, -1, z + 0.6, 2.2)
    sconce(m, g, "x", ZS - 0.2, -1, -1.9, 2.4)
    sconce(m, g, "x", ZS - 0.2, -1, 1.9, 2.4)
    # Busts on carved wall shelves over the gallery (above head height: the gallery is
    # narrow, and a bot must get round its corners).
    for x in (-2.4, 2.4):
        z = ZS - 0.2
        m.box(g, "Shelf", "marble_white", (x - 0.32, U + 1.86, z - 0.36), (x + 0.32, U + 1.96, z), solid=False)
        m.cone(g, "Corbel", "marble_white", (x, U + 1.5, z - 0.12), 0.08, 0.36, top=0.24, sides=8, solid=False)
        m.cyl(g, "Shoulders", "marble_white", (x, U + 1.96, z - 0.18), 0.3, 0.16, sides=10, solid=False)
        m.ball(g, "Head", "marble_white", (x, U + 2.3, z - 0.18), 0.2, solid=False)
    # A runner along the gallery.
    m.strip(g, "GalleryRunner", "runner", (-4.4, U, 1.3), (-3.6, U + 0.02, 10.6))
    m.strip(g, "GalleryRunner", "runner", (3.6, U, 1.3), (4.4, U + 0.02, 10.6))
    m.strip(g, "GalleryRunner", "runner", (-3.6, U, 9.6), (3.6, U + 0.02, 10.4))
    # Cobwebs in the corners up high.
    for (x, z, ax, al) in ((-4.84, ZS - 0.21, "x", 1), (4.84, ZS - 0.21, "x", -1)):
        web(m, g, ax, z, -1, x, CU - 0.05, al)
    # The floating chandelier over the void (drawn only: it turns slowly as it bobs).
    p = m.prop("Chandelier", f, (0.0, 5.6, 5.0), bob=0.25, period=6.0, spin=6.0)
    chandelier(m, p, arms=10, r=1.1)
    # A settee that drifts about the foyer floor: cover in the open.
    p = m.prop("Settee", f, (2.7, 0.35, 10.3), moves=[(0, 0, 0), (-5.6, 0, -3.4), (0.2, 0, -3.4), (0, 0, 0)],
               turns=[0, 90, -90, 0], bob=0.12, period=4.5)
    sofa(m, p, L=1.9, fabric="fabric_green")
    # A floating side table with a vase.
    p = m.prop("SideTable", f, (3.9, 0.5, 2.6), moves=[(0, 0, 0), (0, 0, 1.4), (0, 0, 0), (0, 0, 1.4)], bob=0.18, period=3.6)
    table(m, p, 0.7, 0.5, 0.75, solid=True)
    m.cyl(p, "Vase", "porcelain", (0, 0.75, 0), 0.2, 0.32, sides=8, solid=False)
    for k in range(4):
        m.rod(p, "DeadFlower", "greenery", (0, 1.0, 0), (0.18 * math.cos(k * 1.6), 1.35 + 0.05 * k, 0.18 * math.sin(k * 1.6)), thick=0.02)


def dining(m):
    f = m.folder("Dining")
    rng = random.Random(4)
    r = ROOM["Dining"]
    g = m.group("Dressing", f)
    rug(m, g, -13.2, 1.6, -6.8, 9.4, G, "rug_red")
    # The long table floats a little off the floor, and swings round when the house shifts.
    p = m.prop("Table", f, (-10.0, 0.45, 4.3), moves=[(0, 0, 0), (0, 0, 0.6), (0, 0, 0.6), (0, 0, 0)],
               turns=[0, 90, 0, 90], bob=0.15, period=5.5)
    table(m, p, 3.6, 1.2, 0.78, cloth="linen")
    candelabra(m, p, 0.0, 0.79, 0.0, arms=5)
    for k in range(6):
        x = -1.5 + 0.6 * k
        for s in (-1, 1):
            m.cyl(p, "Plate", "porcelain", (x, 0.792, s * 0.38), 0.24, 0.015, sides=10, solid=False)
            m.cyl(p, "Goblet", "brass", (x + 0.18, 0.792, s * 0.3), 0.05, 0.14, sides=6, solid=False)
    m.ball(p, "Skull", "bone", (1.4, 0.88, 0.0), 0.2, solid=False)
    # The chairs have floated up to the ceiling, turning slowly (drawn only).
    for k in range(8):
        x = -11.8 + 1.2 * (k % 4) + (0.3 if k >= 4 else 0)
        z = 3.2 if k < 4 else 5.4
        p = m.prop("Chair", f, (x + 0.6, 2.0 + 0.5 * rng.random(), z), bob=0.25, period=3.5 + rng.random() * 2, sway=40.0)
        chair(m, p, yaw=rng.uniform(-1.2, 1.2) + (math.pi if k >= 4 else 0.0))
    # The sideboard (solid) and the china cabinet.
    s = m.group("Sideboard", f, at=(-14.4, G, 6.0), yaw=math.pi / 2)
    dresser(m, s, W=2.2, H=0.95, D=0.55)
    candelabra(m, s, 0.0, 0.99, 0.0)
    for k in range(4):
        m.cyl(s, "Decanter", "glass_window", (-0.8 + 0.25 * k, 0.99, 0.05), 0.1, 0.26, sides=6, solid=False)
    c = m.group("ChinaCabinet", f, at=(-10.1, G, 10.45), yaw=0.0)
    m.bev(c, "Body", "mahogany", (-0.7, 0.0, -0.25), (0.7, 2.1, 0.25), bevel=0.03)
    for k in range(4):
        y = 0.5 + 0.4 * k
        m.box(c, "Shelf", "wood_dark", (-0.62, y, -0.26), (0.62, y + 0.03, -0.25), solid=False)
        for j in range(5):
            m.cyl(c, "Plate", "porcelain", (-0.5 + 0.25 * j, y + 0.03, -0.27), 0.2, 0.2, sides=8, solid=False) if False else \
                m.block(c, "Plate", "porcelain", (-0.5 + 0.25 * j, y + 0.13, -0.265), (0.2, 0.01, 0.2), cols=((1, 0, 0), (0, 0, -1), (0, 1, 0)), shape="cyl", sides=10, solid=False)
    m.box(c, "Glass", "glass_window", (-0.66, 0.4, -0.29), (0.66, 2.0, -0.275), solid=False)
    # A cabinet that wanders: it stands against the north wall, then crosses the room.
    p = m.prop("Cabinet", f, (-7.2, 0.3, 0.2), moves=[(0, 0, 0), (-0.8, 0, 4.0), (0, 0, 0), (-0.8, 0, 4.0)],
               turns=[180, 90, 180, 90], bob=0.1, period=4.0)
    wardrobe(m, p, W=1.3, H=1.9, D=0.55, kind="wood")
    # Sconces and portraits.
    for z in (4.6, 9.9):
        sconce(m, g, "z", XW + 0.2, 1, z, 2.1)
    portrait(m, g, "x", ZI + 0.15, 1, -7.2, 1.7, 0.9, 1.2, rng)
    portrait(m, g, "z", -XI - 0.15, -1, 2.8, 1.6, 0.7, 0.9, rng)
    web(m, g, "x", ZS - 0.2, -1, XW + 0.2, CG - 0.05, 1)


def parlour(m):
    f = m.folder("Parlour")
    rng = random.Random(5)
    g = m.group("Dressing", f)
    rug(m, g, 7.0, 2.0, 12.6, 8.6, G, "rug_blue")
    fire = fireplace(m, g, "z", XE - 0.2, -1, 5.5, G)
    m.lights.append(("ParlourFire", (fire[0] - 0.4, 1.0, fire[2]), (1.0, 0.55, 0.25), 1.6, 8.0))
    # The grand piano floats and drifts round the room.
    p = m.prop("Piano", f, (8.4, 0.4, 8.6), moves=[(0, 0, 0), (2.2, 0, -5.0), (0.0, 0, -5.6), (2.6, 0, 0.0)],
               turns=[20, 110, 200, -60], bob=0.14, period=6.0)
    grand_piano(m, p)
    # Sofa and armchairs round the fire.
    p = m.prop("Sofa", f, (10.4, 0.3, 5.5), moves=[(0, 0, 0), (-1.6, 0, 2.6), (0.6, 0, -2.6), (-1.6, 0, -2.6)],
               turns=[90, 0, 0, 180], bob=0.1, period=5.0)
    sofa(m, p, L=2.2, fabric="fabric_red")
    for (x, z, yaw) in ((12.6, 3.0, -30), (12.6, 8.0, 30)):
        p = m.prop("Armchair", f, (x, 0.5, z), bob=0.2, period=3.8, sway=12.0)
        armchair(m, p, "fabric_green")
    p = m.prop("TeaTable", f, (12.2, 0.6, 5.5), bob=0.22, period=3.1, sway=8.0)
    table(m, p, 0.8, 0.8, 0.45, top_kind="wood", solid=False)
    m.cyl(p, "Teapot", "porcelain", (0.1, 0.45, 0.0), 0.2, 0.18, sides=8, solid=False)
    for k in range(3):
        m.cyl(p, "Cup", "porcelain", (-0.25, 0.45, -0.25 + 0.25 * k), 0.08, 0.06, sides=6, solid=False)
    # A harp and a bookcase.
    h = m.group("Harp", f, at=(13.8, G, 1.0))
    m.box(h, "Base", "brass", (-0.25, 0.0, -0.15), (0.25, 0.15, 0.15))
    m.rod(h, "Column", "brass", (-0.2, 0.15, 0.0), (-0.2, 1.75, 0.0), thick=0.08)
    m.rod(h, "Neck", "brass", (-0.2, 1.75, 0.0), (0.4, 1.4, 0.0), thick=0.08)
    m.rod(h, "Body", "wood", (0.0, 0.15, 0.0), (0.4, 1.4, 0.0), thick=0.14, wide=0.24)
    for k in range(8):
        x = -0.15 + 0.07 * k
        m.rod(h, "String", "porcelain", (x, 0.25 + 0.16 * k, 0.0), (x, 1.68 - 0.04 * k, 0.0), thick=0.006)
    b = m.group("Bookcase", f, at=(10.1, G, 10.45), yaw=math.pi)
    bookcase(m, b, 1.8, 2.4, 0.45, rng)
    for z in (0.6, 9.4):
        sconce(m, g, "z", XE - 0.2, -1, z, 2.2)
    portrait(m, g, "x", ZI + 0.15, 1, 7.4, 1.6, 0.8, 1.1, rng)
    portrait(m, g, "x", ZI + 0.15, 1, 13.4, 1.6, 0.8, 1.1, rng)
    # A phonograph on a stand.
    m.box(g, "PhonoStand", "wood_dark", (13.9, G, 9.6), (14.6, 0.8, 10.3))
    m.box(g, "Phonograph", "mahogany", (14.0, 0.8, 9.7), (14.5, 0.95, 10.2), solid=False)
    m.cone(g, "Horn", "brass", (14.25, 0.95, 9.95), 0.12, 0.55, top=0.55, sides=10, solid=False)
    web(m, g, "z", XE - 0.2, -1, ZS - 0.2, CG - 0.05, -1)


def kitchen(m):
    f = m.folder("Kitchen")
    rng = random.Random(6)
    g = m.group("Dressing", f)
    # The range against the north wall, its hood and chimney.
    k = m.group("Range", f, at=(-10.1, G, -10.2))
    m.bev(k, "Body", "iron", (-1.0, 0.0, -0.5), (1.0, 0.9, 0.5), bevel=0.03)
    m.box(k, "Top", "steel", (-1.02, 0.9, -0.52), (1.02, 0.95, 0.52), solid=False)
    for j in range(4):
        m.cyl(k, "Ring", "black", (-0.6 + 0.4 * j, 0.95, -0.1), 0.26, 0.02, sides=10, solid=False)
    m.box(k, "OvenDoor", "black", (-0.8, 0.15, 0.5), (0.0, 0.7, 0.52), solid=False)
    m.box(k, "Firebox", "ember", (0.2, 0.2, 0.5), (0.7, 0.45, 0.515), solid=False)
    m.box(k, "Rail", "brass", (-0.95, 0.78, 0.52), (0.95, 0.81, 0.56), solid=False)
    m.box(k, "Hood", "steel", (-1.1, 2.4, -0.55), (1.1, 2.7, 0.45), solid=False)
    m.box(k, "Flue", "steel", (-0.3, 2.7, -0.55), (0.3, CG, -0.1), solid=False)
    m.cyl(k, "Kettle", "steel", (-0.6, 0.97, -0.1), 0.24, 0.2, sides=8, solid=False)
    m.cyl(k, "Pot", "iron", (0.2, 0.97, -0.1), 0.32, 0.25, sides=10, solid=False)
    m.box(k, "Gruel", "greenery", (0.08, 1.2, -0.22), (0.32, 1.205, 0.02), solid=False)
    m.lights.append(("KitchenRange", (-10.1, 1.2, -9.3), (1.0, 0.5, 0.2), 0.9, 6.0))
    # Counters along the west wall, the sink under the window.
    for (z0, z1) in ((-10.6, -4.6), (-3.4, -1.4)):
        c = m.group("Counter", f)
        m.box(c, "Cupboards", "wood_light", (XW + 0.2, G, z0), (XW + 0.8, 0.86, z1))
        m.box(c, "Worktop", "wood", (XW + 0.2, 0.86, z0 - 0.02), (XW + 0.85, 0.92, z1 + 0.02), solid=False)
        n = int((z1 - z0) / 0.6)
        for j in range(n):
            za = z0 + (z1 - z0) * j / n + 0.03
            zb = z0 + (z1 - z0) * (j + 1) / n - 0.03
            m.box(c, "Door", "wood", (XW + 0.8, 0.1, za), (XW + 0.82, 0.78, zb), solid=False)
            m.box(c, "Knob", "brass", (XW + 0.82, 0.62, (za + zb) / 2 - 0.02), (XW + 0.85, 0.66, (za + zb) / 2 + 0.02), solid=False)
    m.box(g, "Sink", "porcelain", (XW + 0.25, 0.7, -8.6), (XW + 0.81, 0.95, -7.2), solid=False)
    m.box(g, "SinkHole", "black", (XW + 0.32, 0.945, -8.5), (XW + 0.73, 0.955, -7.3), solid=False)
    m.rod(g, "Tap", "brass", (XW + 0.25, 0.95, -7.9), (XW + 0.45, 1.25, -7.9), thick=0.03)
    for j in range(5):
        z = -6.0 + 0.4 * j
        m.cyl(g, "Jar", "glass_window", (XW + 0.45, 0.92, z), 0.16, 0.24 + 0.04 * (j % 2), sides=6, solid=False)
        m.cyl(g, "JarStuff", ["greenery", "book_red", "paper"][j % 3], (XW + 0.45, 0.93, z), 0.12, 0.14, sides=6, solid=False)
    # Shelves on the north wall with crocks, and hanging pots that swing (drawn only).
    for (x0, x1, y) in ((-14.65, -13.5, 1.6), (-14.65, -13.5, 2.2), (-6.7, -5.3, 1.8), (-6.7, -5.3, 2.4)):
        m.on_wall(g, "Shelf", "wood", "x", ZN + 0.2, 1, x0, x1, y, y + 0.04, 0.3)
        xx = x0 + 0.15
        while xx < x1 - 0.2:
            h = rng.uniform(0.12, 0.3)
            m.cyl(g, "Crock", rng.choice(["pot", "porcelain", "brass"]), (xx, y + 0.04, ZN + 0.35), 0.16, h, sides=8, solid=False)
            xx += rng.uniform(0.22, 0.4)
    p = m.prop("PotRack", f, (-10.0, 3.1, -5.0), bob=0.08, period=2.6, sway=14.0)
    m.box(p, "Rack", "iron", (-1.0, 0.0, -0.3), (1.0, 0.05, 0.3), solid=False)
    for s in (-1, 1):
        m.rod(p, "Chain", "iron", (s * 0.9, 0.05, 0.0), (s * 0.5, 0.6, 0.0), thick=0.02)
    for j in range(6):
        x = -0.85 + 0.34 * j
        m.rod(p, "Hook", "iron", (x, 0.0, 0.0), (x, -0.25, 0.0), thick=0.015)
        m.cyl(p, "Pan", rng.choice(["iron", "brass", "steel"]), (x, -0.55, 0.0), 0.26 + 0.04 * (j % 3), 0.12, sides=10, solid=False)
    # The butcher's table floats in the middle, and moves.
    p = m.prop("Block", f, (-10.0, 0.35, -5.0), moves=[(0, 0, 0), (1.8, 0, 1.8), (-1.6, 0, 1.6), (1.6, 0, -1.8)],
               turns=[0, 90, 45, 0], bob=0.12, period=4.2)
    table(m, p, 2.0, 1.0, 0.86, top_kind="wood_light", leg_kind="wood")
    m.box(p, "Board", "wood", (-0.5, 0.86, -0.3), (0.2, 0.9, 0.2), solid=False)
    m.rod(p, "Cleaver", "steel", (0.4, 0.88, 0.0), (0.7, 0.88, 0.1), thick=0.01, wide=0.12)
    m.ball(p, "Cabbage", "greenery", (-0.7, 0.98, 0.25), 0.22, solid=False)
    m.ball(p, "Onion", "paper", (-0.4, 0.92, 0.3), 0.1, solid=False)
    # Barrels and sacks in the corner (solid barrels).
    for (x, z) in ((-6.0, -10.0), (-6.0, -9.2), (-6.8, -10.0)):
        m.cyl(g, "Barrel", "wood", (x, G, z), 0.65, 0.95, sides=12)
        m.block(g, "Hoop", "iron", (x, 0.2, z), (0.67, 0.05, 0.67), shape="tube", sides=12, inner=0.64, solid=False)
        m.block(g, "Hoop", "iron", (x, 0.75, z), (0.67, 0.05, 0.67), shape="tube", sides=12, inner=0.64, solid=False)
    m.bev(g, "Sack", "paper", (-6.6, G, -8.6), (-5.9, 0.55, -8.0), bevel=0.15, solid=False)
    # A pantry doorway, boarded up (BOARDED), and the dumbwaiter hatch.
    m.on_wall(g, "Hatch", "wood_dark", "z", -XI - 0.15, -1, -3.4, -2.6, 1.0, 1.8, 0.05)
    m.on_wall(g, "HatchHandle", "brass", "z", -XI - 0.15, -1, -3.1, -2.9, 1.1, 1.15, 0.08)
    m.lights.append(("KitchenCandle", (-14.2, 1.8, -2.4), (1.0, 0.7, 0.4), 0.5, 5.0))
    candle(m, g, XW + 0.5, 0.92, -2.4)
    candle(m, g, XW + 0.55, 0.92, -2.2, 0.12)


def library(m):
    f = m.folder("Library")
    rng = random.Random(7)
    g = m.group("Dressing", f)
    rug(m, g, 7.0, -9.4, 12.6, -3.0, G, "rug_red")
    # Bookcases along the north and east walls, floor to ceiling.
    for x, w in ((9.3, 1.6), (10.9, 1.6)):
        b = m.group("Shelves", f, at=(x, G, ZN + 0.2 + 0.27))   # (off the wall: clear of the skirting's and the picture rail's faces)
        bookcase(m, b, w - 0.02, 3.3, 0.5, rng)
    for z, w in ((-9.75, 1.9), (-5.7, 2.3)):
        b = m.group("Shelves", f, at=(XE - 0.2 - 0.25, G, z), yaw=math.pi / 2)
        bookcase(m, b, w, 3.3, 0.5, rng)
    # A rolling ladder on the north cases.
    m.rod(g, "Ladder", "wood", (9.7, G, -9.7), (10.0, 3.2, -10.2), thick=0.05)
    m.rod(g, "Ladder", "wood", (10.3, G, -9.7), (10.6, 3.2, -10.2), thick=0.05)
    for j in range(8):
        t = (j + 0.5) / 8
        m.rod(g, "Rung", "wood", (9.7 + 0.3 * t, 3.2 * t, -9.7 - 0.5 * t), (10.3 + 0.3 * t, 3.2 * t, -9.7 - 0.5 * t), thick=0.03)
    m.box(g, "LadderRail", "brass", (8.5, 3.15, -10.25), (11.7, 3.18, -10.22), solid=False)
    # Two free-standing cases that slide about: walls that move.
    p = m.prop("CaseA", f, (8.0, 0.25, -4.4), moves=[(0, 0, 0), (0, 0, -2.6), (2.2, 0, 0), (0, 0, -2.6)],
               turns=[0, 0, 90, 90], bob=0.08, period=5.2)
    bookcase(m, p, 2.4, 2.5, 0.5, rng)
    p = m.prop("CaseB", f, (12.0, 0.25, -6.0), moves=[(0, 0, 0), (-1.2, 0, 2.6), (-1.4, 0, -1.6), (-1.2, 0, 0.8)],
               turns=[90, 0, 0, 90], bob=0.08, period=4.7)
    bookcase(m, p, 2.4, 2.5, 0.5, rng)
    # A reading table and a lamp, the books circling it.
    t = m.group("ReadingTable", f, at=(10.2, G, -8.0))
    table(m, t, 1.8, 0.9, 0.8, top_kind="wood")
    m.cyl(t, "LampFoot", "brass", (0.5, 0.8, 0.1), 0.14, 0.4, sides=8, solid=False)
    m.cone(t, "LampShade", "lamp", (0.5, 1.2, 0.1), 0.42, 0.25, top=0.2, sides=10, solid=False)
    m.box(t, "OpenBook", "paper", (-0.4, 0.8, -0.15), (0.05, 0.83, 0.2), solid=False)
    m.lights.append(("LibraryLamp", (10.7, 1.6, -7.9), (1.0, 0.82, 0.55), 0.9, 7.0))
    p = m.prop("Books", f, (10.2, 2.1, -8.0), bob=0.3, period=4.0, spin=24.0)
    for k in range(9):
        a = math.tau * k / 9
        x, z = math.cos(a) * 1.3, math.sin(a) * 1.3
        kind = ["book_red", "book_green", "book_blue", "book_brown"][k % 4]
        y = 0.25 * math.sin(a * 2.0)
        m.block(p, "Book", kind, (x, y, z), (0.28, 0.06, 0.2), cols=rot(math.degrees(-a) + 20), solid=False)
        m.block(p, "Pages", "paper", (x, y + 0.035, z), (0.26, 0.01, 0.18), cols=rot(math.degrees(-a) + 20), solid=False)
    # A globe, an armchair.
    gl = m.prop("Globe", f, (13.4, 0.0, -8.0), spin=10.0)
    m.cyl(gl, "Stand", "wood_dark", (0, 0, 0), 0.4, 0.7, sides=8)
    m.block(gl, "Ring", "brass", (0, 1.0, 0), (0.75, 0.04, 0.75), cols=((1, 0, 0), (0, 0, 1), (0, -1, 0)), shape="tube", sides=16, inner=0.7, solid=False)
    m.ball(gl, "Ball", "book_blue", (0, 1.0, 0), 0.62, sides=12, solid=False)
    m.ball(gl, "Land", "book_green", (0.08, 1.12, 0.05), 0.4, sides=8, solid=False)
    p = m.prop("ReadingChair", f, (13.0, 0.6, -3.6), bob=0.18, period=3.3, sway=20.0)
    armchair(m, p, "fabric_red")
    portrait(m, g, "z", XI + 0.15, 1, -2.8, 1.5, 0.8, 1.1, rng)
    sconce(m, g, "x", ZI - 0.15, -1, 7.0, 2.2)


def back_hall(m):
    f = m.folder("BackHall")
    rng = random.Random(8)
    g = m.group("Dressing", f)
    # Portraits along the south wall: the family, watching.
    for k, x in enumerate((-1.6, 0.0, 1.6)):
        portrait(m, g, "x", ZI - 0.15, -1, x, 1.5, 0.9, 1.2, rng)
    # A bench under them, solid.
    b = m.group("Bench", f, at=(2.6, G, -2.0))
    m.bev(b, "Seat", "wood_dark", (-0.8, 0.4, -0.25), (0.8, 0.5, 0.25), bevel=0.03)
    for s in (-1, 1):
        m.box(b, "Leg", "wood_dark", (s * 0.7 - 0.04, 0.0, -0.22), (s * 0.7 + 0.04, 0.4, 0.22), solid=False)
    # The servants' bell board on the west wall.
    m.on_wall(g, "BellBoard", "wood_dark", "z", -XI + 0.15, 1, -8.3, -7.2, 2.0, 2.7, 0.04)
    for k in range(6):
        z = -8.2 + 0.18 * k
        m.on_wall(g, "Bell", "brass", "z", -XI + 0.15, 1, z, z + 0.08, 2.4, 2.5, 0.09)
    # A grandfather clock that keeps moving round the hall.
    p = m.prop("HallClock", f, (4.4, 0.15, -3.4), moves=[(0, 0, 0), (-3.2, 0, -3.0), (-6.6, 0, -3.4), (-2.0, 0, -1.2)],
               turns=[90, 0, 45, 90], bob=0.06, period=7.0)
    clock(m, p)
    # A side table with a candle (fixed), a hat stand.
    m.box(g, "HallTable", "mahogany", (-4.6, G, -3.6), (-4.0, 0.8, -2.2))
    candelabra(m, g, -4.3, 0.8, -2.9)
    m.lights.append(("HallCandle", (-4.0, 1.4, -2.9), (1.0, 0.7, 0.4), 0.55, 6.0))
    sconce(m, g, "z", XI - 0.15, -1, -3.0, 2.2)
    # A coal scuttle and boots by the stair.
    m.cyl(g, "Scuttle", "iron", (-4.4, G, -8.2), 0.4, 0.4, sides=8, solid=False)
    for k in range(2):
        m.box(g, "Boot", "black", (-3.9 + 0.2 * k, G, -8.4), (-3.78 + 0.2 * k, 0.35, -8.1), solid=False)


def bedroom(m):
    f = m.folder("Bedroom")
    rng = random.Random(10)
    g = m.group("Dressing", f)
    rug(m, g, -14.0, 1.2, -12.2, 4.4, U, "rug_blue")
    fire = fireplace(m, g, "z", XW + 0.2, 1, 5.1, U, wide=2.0)
    m.lights.append(("BedroomFire", (fire[0] + 0.4, U + 1.0, fire[2]), (1.0, 0.5, 0.22), 1.3, 7.5))
    # The bed floats, and wanders the room.
    p = m.prop("Bed", f, (-11.5, U + 0.5, 9.7), moves=[(0, 0, 0), (4.0, 0, -0.6), (2.4, 0, -6.2), (0.0, 0, -6.0)],
               turns=[0, 0, 90, 90], bob=0.16, period=6.5)
    four_poster(m, p)
    # The wardrobe slides from wall to wall.
    p = m.prop("Wardrobe", f, (-7.0, U + 0.05, 0.2), moves=[(0, 0, 0), (-6.6, 0, -0.1), (-0.4, 0, 9.4), (-6.6, 0, -0.1)],
               turns=[180, 180, 0, 180], bob=0.05, period=5.0)
    wardrobe(m, p)
    # A rocking chair that rocks by itself, the dresser, a vanity.
    p = m.prop("RockingChair", f, (-13.0, U + 0.2, 6.4), bob=0.12, period=2.2, sway=25.0)
    chair(m, p, kind="wood", seat="fabric_purple", yaw=math.pi / 2)
    m.lying_cyl(p, "Rocker", "wood", (0.0, 0.03, 0.0), 0.06, 0.9, axis="z", solid=False)
    d = m.group("Dresser", f, at=(-6.0, U, 10.4), yaw=math.pi)
    dresser(m, d)
    m.box(d, "MirrorFrame", "frame", (-0.5, 1.0, -0.2), (0.5, 1.9, -0.16), solid=False)
    m.box(d, "Mirror", "mirror", (-0.42, 1.08, -0.16), (0.42, 1.82, -0.15), solid=False)
    for k in range(3):
        m.cyl(d, "Bottle", "glass_window", (-0.4 + 0.15 * k, 0.99, 0.05), 0.07, 0.15, sides=6, solid=False)
    m.ball(d, "MusicBox", "brass", (0.35, 1.03, 0.05), 0.12, solid=False)
    portrait(m, g, "x", ZI + 0.15, 1, -13.0, U + 1.5, 0.8, 1.1, rng)
    sconce(m, g, "z", -XI - 0.15, -1, 8.2, U + 2.2)
    sconce(m, g, "x", ZS - 0.2, -1, -10.0, U + 2.3)
    # A nightdress drifting near the ceiling.
    p = m.prop("Nightdress", f, (-9.0, U + 1.9, 4.0), bob=0.3, period=4.6, spin=-15.0)
    m.cone(p, "Gown", "linen", (0.6, 0.0, 0.0), 0.7, 1.2, top=0.25, sides=10, solid=False)
    m.ball(p, "Collar", "linen", (0.6, 1.2, 0.0), 0.3, solid=False)
    bedroom_hole(m)


def nursery(m):
    f = m.folder("Nursery")
    rng = random.Random(11)
    g = m.group("Dressing", f)
    rug(m, g, 7.2, 1.6, 12.8, 6.4, U, "rug_blue", border="toy_yellow")
    # The crib, floating, its mobile turning over it.
    p = m.prop("Crib", f, (12.8, U + 0.45, 9.4), moves=[(0, 0, 0), (0.0, 0, -6.0), (-4.6, 0, -1.4), (0, 0, -6.0)],
               turns=[0, 90, 0, 90], bob=0.12, period=4.8)
    m.box(p, "Base", "wood_light", (-0.75, 0.3, -0.45), (0.75, 0.42, 0.45))
    m.bev(p, "Mattress", "linen", (-0.7, 0.42, -0.4), (0.7, 0.55, 0.4), bevel=0.04, solid=False)
    for s in (-1, 1):
        m.box(p, "Rail", "wood_light", (-0.78, 0.95, s * 0.45 - 0.03), (0.78, 1.0, s * 0.45 + 0.03), solid=False)
        m.box(p, "End", "wood_light", (s * 0.78 - 0.03, 0.0, -0.48), (s * 0.78 + 0.03, 1.15, 0.48))
        for k in range(9):
            x = -0.7 + 1.4 * k / 8
            m.box(p, "Slat", "wood_light", (x - 0.015, 0.42, s * 0.45 - 0.015), (x + 0.015, 0.95, s * 0.45 + 0.015), solid=False)
    m.ball(p, "Doll", "porcelain", (0.3, 0.62, 0.0), 0.16, solid=False)
    m.box(p, "DollDress", "toy_red", (0.0, 0.55, -0.1), (0.25, 0.62, 0.1), solid=False)
    mob = m.prop("Mobile", f, (12.8, U + 2.6, 9.4), moves=[(0, 0, 0), (0.0, 0, -6.0), (-4.6, 0, -1.4), (0, 0, -6.0)], spin=30.0)
    m.rod(mob, "Arm", "brass", (-0.5, 0.0, 0.0), (0.5, 0.0, 0.0), thick=0.02)
    m.rod(mob, "Arm", "brass", (0.0, 0.0, -0.5), (0.0, 0.0, 0.5), thick=0.02)
    m.cyl(mob, "String", "linen", (0, 0, 0), 0.01, 1.0, sides=3, solid=False)
    for k, (x, z, kind) in enumerate(((-0.5, 0, "toy_red"), (0.5, 0, "toy_blue"), (0, -0.5, "toy_yellow"), (0, 0.5, "glow_green"))):
        m.rod(mob, "Thread", "linen", (x, 0.0, z), (x, -0.35, z), thick=0.006)
        m.ball(mob, "Star", kind, (x, -0.42, z), 0.12, sides=6, solid=False)
    # The rocking horse rocks on its own.
    p = m.prop("RockingHorse", f, (8.0, U + 0.1, 3.0), bob=0.1, period=1.8, sway=18.0)
    m.lying_cyl(p, "Rocker", "wood", (0.0, 0.05, -0.22), 0.08, 1.4, axis="x", solid=False)
    m.lying_cyl(p, "Rocker", "wood", (0.0, 0.05, 0.22), 0.08, 1.4, axis="x", solid=False)
    m.bev(p, "Body", "porcelain", (-0.45, 0.5, -0.17), (0.45, 0.85, 0.17), bevel=0.08)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.rod(p, "Leg", "porcelain", (sx * 0.35, 0.55, sz * 0.12), (sx * 0.5, 0.1, sz * 0.22), thick=0.07)
    m.rod(p, "Neck", "porcelain", (0.35, 0.8, 0.0), (0.55, 1.15, 0.0), thick=0.16)
    m.bev(p, "Head", "porcelain", (0.48, 1.05, -0.09), (0.82, 1.24, 0.09), bevel=0.05, solid=False)
    m.box(p, "Mane", "toy_red", (0.3, 0.85, -0.03), (0.52, 1.25, 0.03), solid=False)
    m.box(p, "Saddle", "toy_red", (-0.15, 0.85, -0.18), (0.15, 0.9, 0.18), solid=False)
    m.box(p, "Eye", "eye_glow", (0.7, 1.16, -0.1), (0.73, 1.19, 0.1), solid=False)
    # A toy chest that wanders.
    p = m.prop("ToyChest", f, (8.0, U + 0.2, 9.9), moves=[(0, 0, 0), (5.6, 0, -2.3), (-1.4, 0, -8.7), (3.6, 0, -7.5)],
               turns=[0, 90, 90, 0], bob=0.1, period=3.9)
    m.bev(p, "Chest", "toy_blue", (-0.6, 0.0, -0.35), (0.6, 0.6, 0.35), bevel=0.04)
    m.bev(p, "Lid", "toy_blue", (-0.62, 0.6, -0.37), (0.62, 0.68, 0.37), bevel=0.03, solid=False)
    for k in range(5):
        m.box(p, "Block", ["toy_red", "toy_yellow", "toy_blue"][k % 3], (-0.5 + 0.2 * k, 0.68, -0.1), (-0.36 + 0.2 * k, 0.82, 0.04), solid=False)
    # Tea party: a little table, little chairs, and the guests.
    t = m.group("TeaParty", f, at=(10.5, U, 4.2))
    m.cyl(t, "Table", "wood_light", (0, 0, 0), 0.9, 0.5, sides=12)
    for k in range(4):
        a = math.tau * k / 4 + 0.4
        x, z = math.cos(a) * 0.75, math.sin(a) * 0.75
        m.cyl(t, "Stool", "toy_yellow", (x, 0, z), 0.32, 0.3, sides=8, solid=False)
        m.cyl(t, "Cup", "porcelain", (x * 0.5, 0.5, z * 0.5), 0.07, 0.05, sides=6, solid=False)
        guest = ["bone", "toy_red", "linen", "book_brown"][k]
        m.ball(t, "Guest", guest, (x, 0.48, z), 0.3, solid=False)
        m.ball(t, "GuestHead", guest, (x, 0.75, z), 0.2, solid=False)
    m.cyl(t, "Teapot", "porcelain", (0, 0.5, 0), 0.18, 0.16, sides=8, solid=False)
    # A dollhouse: the house in little, on a stand.
    d = m.group("Dollhouse", f, at=(XE - 0.6, U, 5.0), yaw=math.pi / 2)
    m.box(d, "Stand", "wood_dark", (-0.5, 0.0, -0.3), (0.5, 0.7, 0.3))
    m.box(d, "House", "siding", (-0.45, 0.7, -0.25), (0.45, 1.3, 0.2), solid=False)
    m.wedge(d, "Roof", "wood_dark", (-0.5, 1.3, -0.28), (0.5, 1.55, 0.23), tall="-z", solid=False) if hasattr(m, "wedge") else None
    for k in range(3):
        m.box(d, "Window", "lamp", (-0.35 + 0.3 * k, 0.9, 0.2), (-0.25 + 0.3 * k, 1.05, 0.21), solid=False)
    m.lights.append(("NurseryLight", (8.0, U + 2.2, 7.8), (0.5, 1.0, 0.65), 0.6, 7.0))
    m.cyl(g, "NightLight", "glow_green", (XI + 0.5, U, 8.0 - 0.3), 0.18, 0.3, sides=8, solid=False)
    # A teddy bear, alone in a corner.
    m.ball(g, "Teddy", "book_brown", (14.3, U + 0.2, 10.3), 0.4, solid=False)
    m.ball(g, "TeddyHead", "book_brown", (14.3, U + 0.55, 10.3), 0.28, solid=False)
    m.ball(g, "TeddyEar", "book_brown", (14.2, U + 0.7, 10.3), 0.1, solid=False)
    m.ball(g, "TeddyEar", "book_brown", (14.4, U + 0.7, 10.3), 0.1, solid=False)
    # Letters on the wall: wooden blocks spelling nothing nice.
    for k, kind in enumerate(("toy_red", "toy_blue", "toy_yellow", "toy_red", "toy_blue")):
        m.on_wall(g, "WallBlock", kind, "x", ZI + 0.15, 1, 7.2 + 0.4 * k, 7.5 + 0.4 * k, U + 1.6 + 0.05 * (k % 2), U + 1.9 + 0.05 * (k % 2), 0.08)
    portrait(m, g, "z", XE - 0.2, -1, 10.0, U + 1.5, 0.7, 0.9, rng)


def bathroom(m):
    f = m.folder("Bathroom")
    rng = random.Random(12)
    g = m.group("Dressing", f)
    # The clawfoot tub floats, slowly, from corner to corner.
    p = m.prop("Tub", f, (-12.6, U + 0.4, -9.0), moves=[(0, 0, 0), (1.0, 0, 3.4), (4.0, 0, 0.8), (-0.2, 0, 6.0)],
               turns=[0, 90, 0, 90], bob=0.14, period=5.6)
    m.bev(p, "Tub", "porcelain", (-0.9, 0.2, -0.42), (0.9, 0.78, 0.42), bevel=0.18)
    m.bev(p, "Water", "greenery", (-0.74, 0.6, -0.28), (0.74, 0.77, 0.28), bevel=0.06, solid=False)
    m.block(p, "Rim", "porcelain", (0.0, 0.79, 0.0), (1.84, 0.04, 0.86), shape="bevel", bevel=0.02, solid=False)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.cone(p, "Claw", "brass", (sx * 0.7, 0.0, sz * 0.3), 0.14, 0.22, top=0.07, sides=6, solid=False)
    m.rod(p, "Tap", "brass", (-0.9, 0.78, 0.0), (-0.75, 1.0, 0.0), thick=0.03)
    m.ball(p, "Duck", "toy_yellow", (0.3, 0.82, 0.1), 0.12, solid=False)
    # Pedestal sink and its mirror (the mirror shows something behind you).
    m.cyl(g, "Pedestal", "porcelain", (-9.0, U, ZN + 0.5), 0.25, 0.75, sides=8)
    m.bev(g, "Basin", "porcelain", (-9.35, U + 0.75, ZN + 0.22), (-8.65, U + 0.92, ZN + 0.75), bevel=0.06, solid=False)
    m.on_wall(g, "MirrorFrame", "frame", "x", ZN + 0.2, 1, -9.45, -8.55, U + 1.3, U + 2.3, 0.04)
    m.on_wall(g, "Mirror", "mirror", "x", ZN + 0.2, 1, -9.35, -8.65, U + 1.4, U + 2.2, 0.01, lift=0.04)
    m.on_wall(g, "Shape", "black", "x", ZN + 0.2, 1, -9.12, -8.92, U + 1.55, U + 2.0, 0.005, lift=0.05)
    m.on_wall(g, "ShapeEyes", "eye_glow", "x", ZN + 0.2, 1, -9.08, -8.96, U + 1.86, U + 1.89, 0.004, lift=0.055)
    # The toilet with its high cistern, a cabinet, towels.
    t = m.group("Toilet", f, at=(-6.2, U, -10.3))
    m.cyl(t, "Bowl", "porcelain", (0, 0, 0.1), 0.42, 0.42, sides=10)
    m.cyl(t, "Seat", "wood", (0, 0.42, 0.1), 0.46, 0.04, sides=10, solid=False)
    m.box(t, "Cistern", "porcelain", (-0.25, 1.9, -0.2), (0.25, 2.2, -0.05), solid=False)
    m.rod(t, "Pipe", "brass", (0, 1.9, -0.12), (0, 0.4, -0.12), thick=0.04)
    m.rod(t, "Chain", "brass", (0.2, 1.9, -0.05), (0.2, 1.3, -0.05), thick=0.01)
    c = m.group("Cabinet", f, at=(XW + 0.46, U, -1.75), yaw=-math.pi / 2)
    dresser(m, c, W=0.8, H=0.9, D=0.5, kind="porcelain")
    m.on_wall(g, "TowelRail", "brass", "z", XW + 0.2, 1, -6.3, -5.1, U + 1.2, U + 1.24, 0.08)
    m.on_wall(g, "Towel", "linen", "z", XW + 0.2, 1, -6.2, -5.6, U + 0.6, U + 1.22, 0.03, lift=0.06)
    m.on_wall(g, "Towel", "fabric_red", "z", XW + 0.2, 1, -5.55, -5.2, U + 0.75, U + 1.22, 0.03, lift=0.06)
    # Writing on the tiles.
    for k in range(5):
        m.on_wall(g, "Smear", "rug_red", "z", -XI - 0.15, -1, -9.6 + 0.3 * k, -9.4 + 0.3 * k, U + 1.7 - 0.06 * k, U + 2.1 - 0.08 * k, 0.006)
    m.lights.append(("BathCandle", (-9.0, U + 1.4, ZN + 0.9), (1.0, 0.75, 0.45), 0.5, 5.5))
    candle(m, g, -9.25, U + 0.92, ZN + 0.4)
    candle(m, g, -8.75, U + 0.92, ZN + 0.4, 0.12)


def study(m):
    f = m.folder("Study")
    rng = random.Random(13)
    g = m.group("Dressing", f)
    rug(m, g, 7.0, -9.0, 12.0, -3.4, U, "rug_red")
    for z, w in ((-9.75, 1.9), (-5.7, 2.3)):
        b = m.group("Shelves", f, at=(XE - 0.45, U, z), yaw=math.pi / 2)
        bookcase(m, b, w, 2.9, 0.5, rng)
    # The desk slides about the room, its chair after it.
    p = m.prop("Desk", f, (9.4, U + 0.3, -7.6), moves=[(0, 0, 0), (0, 0, 3.6), (2.2, 0, 2.0), (-2.4, 0, 3.2)],
               turns=[0, 180, 90, 0], bob=0.1, period=4.4)
    m.bev(p, "Top", "mahogany", (-1.0, 0.72, -0.5), (1.0, 0.8, 0.5), bevel=0.03)
    for s in (-1, 1):
        m.box(p, "Pedestal", "mahogany", (s * 0.95 - 0.25 * (s > 0), 0.0, -0.45) if s < 0 else (0.7, 0.0, -0.45),
              (-0.7, 0.72, 0.45) if s < 0 else (0.95, 0.72, 0.45))
    m.box(p, "Blotter", "fabric_green", (-0.5, 0.8, -0.3), (0.5, 0.81, 0.3), solid=False)
    m.box(p, "Letter", "paper", (-0.2, 0.81, -0.1), (0.1, 0.815, 0.15), solid=False)
    m.cyl(p, "Inkwell", "black", (0.6, 0.8, -0.2), 0.08, 0.08, sides=6, solid=False)
    m.rod(p, "Quill", "linen", (0.6, 0.86, -0.2), (0.75, 1.1, -0.1), thick=0.01, wide=0.04)
    m.cyl(p, "LampFoot", "brass", (-0.7, 0.8, 0.2), 0.1, 0.3, sides=6, solid=False)
    m.cone(p, "LampShade", "glow_green", (-0.7, 1.1, 0.2), 0.3, 0.16, top=0.16, sides=8, solid=False)
    # Its chair follows it (drawn only, floating higher).
    p = m.prop("DeskChair", f, (9.4, U + 1.0, -6.6), moves=[(0, 0, 0), (0, 0, 1.6), (1.2, 0, 2.0), (-2.4, 0, 2.2)],
               bob=0.2, period=2.9, sway=30.0)
    chair(m, p, kind="mahogany", seat="fabric_green")
    # A safe, a globe that floats, antlers, a map.
    m.bev(g, "Safe", "iron", (6.0, U, -10.6), (6.9, U + 1.0, -9.8), bevel=0.04)
    m.cyl(g, "Dial", "brass", (6.45, U + 0.6, -9.8), 0.14, 0.03, sides=10, solid=False) if False else \
        m.block(g, "Dial", "brass", (6.45, U + 0.6, -9.78), (0.16, 0.03, 0.16), cols=((1, 0, 0), (0, 0, 1), (0, -1, 0)), shape="cyl", sides=10, solid=False)
    gl = m.prop("FloatingGlobe", f, (7.0, U + 1.8, -2.4), bob=0.35, period=3.0, spin=-20.0)
    m.ball(gl, "Ball", "book_blue", (0, 0, 0), 0.6, sides=12, solid=False)
    m.ball(gl, "Land", "book_green", (0.1, 0.12, 0.05), 0.4, sides=8, solid=False)
    m.block(gl, "Ring", "brass", (0, 0, 0), (0.72, 0.04, 0.72), cols=((1, 0, 0), (0, 0, 1), (0, -1, 0)), shape="tube", sides=16, inner=0.68, solid=False)
    m.on_wall(g, "Plaque", "wood_dark", "z", XI + 0.15, 1, -8.6, -8.0, U + 2.0, U + 2.5, 0.06)
    for s in (-1, 1):
        m.rod(g, "Antler", "bone", (XI + 0.25, U + 2.3, -8.3), (XI + 0.5, U + 2.9, -8.3 + s * 0.45), thick=0.04)
        m.rod(g, "Tine", "bone", (XI + 0.4, U + 2.6, -8.3 + s * 0.22), (XI + 0.45, U + 2.85, -8.3 + s * 0.12), thick=0.03)
    m.ball(g, "Head", "book_brown", (XI + 0.35, U + 2.15, -8.3), 0.3, solid=False)
    m.on_wall(g, "Map", "paper", "x", ZN + 0.2, 1, 9.0, 11.2, U + 1.4, U + 2.6, 0.01)
    for k in range(6):
        m.on_wall(g, "MapLine", "book_brown", "x", ZN + 0.2, 1, 9.2 + 0.3 * k, 9.5 + 0.25 * k, U + 1.6 + 0.15 * (k % 3), U + 1.63 + 0.15 * (k % 3), 0.004, lift=0.01)
    m.lights.append(("StudyLamp", (9.0, U + 1.6, -6.0), (0.6, 1.0, 0.7), 0.6, 6.5))
    portrait(m, g, "x", ZI - 0.15, -1, 7.4, U + 1.5, 0.8, 1.1, rng)


def upper_hall(m):
    f = m.folder("UpperHall")
    rng = random.Random(14)
    g = m.group("Dressing", f)
    m.strip(g, "Runner", "runner", (-4.4, U, -8.37), (4.4, U + 0.02, -7.6))
    for x in (-3.4, -1.2, 1.2, 3.4):
        portrait(m, g, "x", ZI - 0.15, -1, x, U + 1.5, 0.7, 0.9, rng)
    # A suit of armour that walks the hall when nobody looks.
    p = m.prop("HallArmour", f, (3.6, U + 0.15, -3.0), moves=[(0, 0, 0), (-7.0, 0, 0.0), (-3.6, 0, -3.4), (0, 0, -3.4)],
               turns=[180, 90, 0, -90], bob=0.08, period=3.4)
    armour(m, p)
    # A linen press (solid) and a side table with a vase.
    l = m.group("LinenPress", f, at=(-4.3, U, -2.3), yaw=-math.pi / 2)
    wardrobe(m, l, W=1.2, H=2.1, D=0.55, kind="wood")
    m.box(g, "SideTable", "mahogany", (3.9, U, -8.4), (4.6, U + 0.85, -7.4))
    m.cyl(g, "Vase", "porcelain", (4.25, U + 0.85, -7.9), 0.24, 0.4, sides=8, solid=False)
    for k in range(4):
        m.rod(g, "DeadFlower", "greenery", (4.25, U + 1.2, -7.9), (4.25 + 0.2 * math.cos(k * 1.5), U + 1.6, -7.9 + 0.2 * math.sin(k * 1.5)), thick=0.02)
    sconce(m, g, "z", -XI + 0.15, 1, -8.0, U + 2.2)
    sconce(m, g, "z", XI - 0.15, -1, -2.6, U + 2.2)
    m.lights.append(("UpperHallSconce", (0.0, U + 2.6, -6.0), (1.0, 0.7, 0.4), 0.55, 6.5))
    # A floating candelabra drifting down the hall.
    p = m.prop("Candelabra", f, (0.0, U + 2.0, -5.5), bob=0.3, period=3.7, spin=12.0)
    candelabra(m, p, 0.0, 0.0, 0.0, arms=3)


# =====================================================================================
# Ghosts, lights, the haunting itself
# =====================================================================================

GHOSTS = [
    # (name, centre, route in the node's frame, speed, phase, size, tint)
    ("FoyerGhost", (0, 5.4, 5.0), [(3.2 * math.cos(a), 0.6 * math.sin(2 * a), 3.2 * math.sin(a)) for a in [k * math.tau / 8 for k in range(8)]],
     1.6, 0.0, 1.0, (0.72, 0.92, 1.0)),
    ("WestGhost", (0, 1.7, 0), [(-10, 0, 7), (-10, 0.3, 2), (-11, 0, -4), (-8, -0.2, -8), (-2, 0.2, -6), (-1, 0, 2), (-3, 0.2, 7)],
     1.4, 0.3, 0.95, (0.7, 1.0, 0.85)),
    ("EastGhost", (0, 1.6, 0), [(9, 0, 6), (12, 0.3, 2), (10, 0, -5), (6, -0.1, -8), (2, 0.2, -4), (3, 0.0, 3), (7, 0.2, 9)],
     1.5, 0.6, 1.05, (0.75, 0.88, 1.0)),
    ("BedroomGhost", (-10, U + 1.7, 0), [(-2, 0, 8), (2, 0.4, 4), (-1, 0, -4), (3, 0.3, -8), (-3, 0, -6), (-4, 0.2, 2)],
     1.2, 0.1, 0.9, (0.9, 0.85, 1.0)),
    ("NurseryGhost", (10, U + 1.5, 0), [(-2, 0, 8), (3, 0.3, 6), (2, 0.0, -2), (-1, 0.4, -8), (3, 0, -6), (-3, 0.2, 2)],
     1.0, 0.5, 0.6, (0.8, 1.0, 0.9)),
    ("RisingGhost", (-10, 0, -6), [(0, 1.6, 0), (2.5, 3.0, 1.5), (1.0, 5.6, 2.5), (-1.5, 6.0, 0.5), (-2.0, 3.6, -2.0), (0.5, 1.4, -2.0)],
     1.1, 0.2, 1.0, (0.68, 0.95, 1.0)),
    ("HallGhost", (0, U + 1.8, 0), [(-3.5, 0, -8), (3.5, 0.2, -8), (4, 0, -2), (4, 0.1, 6), (0, 0.3, 10), (-4, 0, 6), (-4, 0.1, -2)],
     1.8, 0.75, 1.1, (0.72, 0.9, 1.0)),
]


def ghosts(m):
    f = m.folder("Ghosts")
    for name, centre, route, speed, phase, size, tint in GHOSTS:
        m.node(name, f, "ghost", [("transform", xform(IDENTITY, centre)), ("route", tarr("Vector3", route)),
                                  ("speed", fmt(speed)), ("phase", fmt(phase)), ("size", fmt(size)), ("tint", color(tint)),
                                  ("moan_every", fmt(14.0 + 4.0 * phase)), ("look", "3")])


def lights(m):
    f = m.folder("Lights")
    # The chandeliers' and the rooms' own light, besides the fires and candles noted as built.
    m.lights.append(("FoyerChandelier", (0.0, 5.8, 5.0), (1.0, 0.78, 0.5), 1.4, 11.0))
    m.lights.append(("FoyerLow", (0.0, 2.4, 9.6), (1.0, 0.72, 0.45), 0.6, 7.0))
    m.lights.append(("DiningCandles", (-10.0, 2.0, 4.3), (1.0, 0.72, 0.42), 0.9, 8.5))
    m.lights.append(("GalleryWest", (-4.0, U + 2.4, 6.0), (1.0, 0.7, 0.42), 0.45, 6.0))
    m.lights.append(("GalleryEast", (4.0, U + 2.4, 4.0), (1.0, 0.7, 0.42), 0.45, 6.0))
    m.lights.append(("BedroomGlow", (-9.0, U + 2.6, 7.5), (0.75, 0.6, 1.0), 0.45, 7.0))
    for name, at, col, energy, rng_ in m.lights:
        m.node(name, f, None, [("transform", xform(IDENTITY, at)), ("light_color", color(col)), ("light_energy", fmt(energy)),
                               ("omni_range", fmt(rng_)), ("omni_attenuation", "1.4"), ("shadow_enabled", "false"),
                               ("light_specular", "0.3")], type_="OmniLight3D")


def haunting(m):
    m.node("Haunting", ".", "event", [("layouts", str(LAYOUTS)), ("hold_time", "22.0"), ("warn_time", "3.0"),
                                       ("move_time", "2.5"), ("lights", 'NodePath("../Lights")')], type_="Node")


# =====================================================================================
# Outside: the grounds at midnight, seen through the windows
# =====================================================================================

def outside(m):
    f = m.folder("Outside")
    rng = random.Random(21)
    g = m.group("Ground", f)
    m.box(g, "Lawn", "grass_dead", (-90, -1.0, -90), (90, -0.7, 90), solid=False)
    m.box(g, "Path", "dirt", (-1.4, -0.7, ZS + 0.4), (1.4, -0.68, 40), solid=False)
    m.box(g, "Step", "foundation", (-1.6, -0.7, ZS + 0.2), (1.6, -0.35, ZS + 1.0), solid=False)
    m.box(g, "Porch", "wood_dark", (-3.6, -0.36, ZS + 0.2), (3.6, -0.29, ZS + 2.6), solid=False)
    for x in (-3.4, 3.4):
        m.cyl(g, "PorchPost", "wood_dark", (x, -0.3, ZS + 2.4), 0.18, 3.6, sides=8, solid=False)
    m.box(g, "PorchRoof", "siding", (-3.8, 3.3, ZS + 0.2), (3.8, 3.45, ZS + 2.8), solid=False)
    # The iron fence round the grounds.
    fe = m.group("Fence", f)
    R = 26.0
    for side in range(4):
        for k in range(-13, 14):
            u = k * 2.0
            if side == 0 and abs(u) < 2.5:
                continue   # the gate
            x, z = [(u, R), (u, -R), (R, u), (-R, u)][side]
            m.box(fe, "Bar", "fence", (x - 0.04, -0.7, z - 0.04), (x + 0.04, 1.4, z + 0.04), solid=False)
            m.cone(fe, "Spike", "fence", (x, 1.4, z), 0.12, 0.25, sides=4, solid=False)
        a, b = [((-R, R), (R, R)), ((-R, -R), (R, -R)), ((R, -R), (R, R)), ((-R, -R), (-R, R))][side]
        for y in (0.0, 1.1):
            m.box(fe, "Rail", "fence", (min(a[0], b[0]) - 0.03, y, min(a[1], b[1]) - 0.03), (max(a[0], b[0]) + 0.03, y + 0.06, max(a[1], b[1]) + 0.03), solid=False)
    # Gravestones east and south-east, leaning.
    gr = m.group("Graveyard", f)
    for k in range(26):
        x = rng.uniform(19, 24) if k % 2 else rng.uniform(-10, 24)
        z = rng.uniform(13.5, 24) if k % 2 == 0 else rng.uniform(-20, 24)
        if abs(x) < 17 and abs(z) < 13:
            continue
        lean = rng.uniform(-12, 12)
        h = rng.uniform(0.8, 1.5)
        cols = rot(rng.uniform(-20, 20))
        if rng.random() < 0.6:
            m.block(gr, "Stone", "gravestone", (x, -0.7 + h / 2, z), (0.7, h, 0.18), cols=cols, shape="bevel", bevel=0.05, solid=False)
            m.block(gr, "Top", "gravestone", (x, -0.7 + h, z), (0.7, 0.1, 0.18), cols=((cols[0][0], 0, cols[0][2]), (0, 0, 1), (cols[2][0], -1, cols[2][2])) if False else cols, shape="cyl", sides=10, solid=False)
        else:
            m.block(gr, "Cross", "gravestone", (x, -0.7 + h / 2, z), (0.14, h, 0.14), cols=cols, solid=False)
            m.block(gr, "CrossBar", "gravestone", (x, -0.7 + h * 0.72, z), (0.6, 0.13, 0.14), cols=cols, solid=False)
        m.box(gr, "Mound", "dirt", (x - 0.5, -0.7, z + 0.2), (x + 0.5, -0.6, z + 2.0), solid=False)
    # Dead trees.
    tr = m.group("Trees", f)
    for k, (x, z) in enumerate(((-22, 16), (-24, -8), (21, -18), (-14, -22), (8, -21), (-20, 22), (22, 6))):
        h = rng.uniform(6, 10)
        m.cone(tr, "Trunk", "tree", (x, -0.7, z), 0.9, h, top=0.2, sides=8, solid=False)
        for j in range(6):
            a = rng.uniform(0, math.tau)
            y = rng.uniform(h * 0.4, h * 0.95)
            L = rng.uniform(1.5, 3.5)
            m.rod(tr, "Branch", "tree", (x, y - 0.7, z), (x + math.cos(a) * L, y - 0.7 + rng.uniform(0.5, 2.0), z + math.sin(a) * L), thick=0.14)
    # Hills on the skyline, mist on the ground, the moon.
    h = m.group("Distance", f)
    for k in range(9):
        a = math.tau * k / 9 + 0.2
        m.dome(h, "Hill", "hill", (math.cos(a) * 95, -1.0, math.sin(a) * 95), (60, rng.uniform(10, 22), 40), sides=10, solid=False)
    for k in range(10):
        a = math.tau * k / 10
        r = rng.uniform(17, 24)
        m.box(h, "Mist", "mist", (math.cos(a) * r - 4, -0.7, math.sin(a) * r - 4), (math.cos(a) * r + 4, 0.6, math.sin(a) * r + 4), solid=False)
    # The moon, far off, where the moonlight comes from.
    elev, azim = MOON
    e, az = math.radians(elev), math.radians(azim)
    d = (math.sin(az) * math.cos(e), math.sin(e), -math.cos(az) * math.cos(e))
    c = tuple(v * 140 for v in d)
    Z = norm(d)
    X = norm(cross((0, 1, 0), Z))
    Y = cross(Z, X)
    m.block(h, "Moon", "moon", c, (14, 0.5, 14), cols=(X, Z, tuple(-v for v in Y)), shape="cyl", sides=24, solid=False)


MOON = (32.0, 205.0)   # elevation, azimuth (from north toward east): low in the south-west


# =====================================================================================
# Players, pickups and the checks
# =====================================================================================

SPAWNS = [
    ((-4.0, G, 10.2), (0, 5)), ((4.0, G, 0.4), (0, 5)), ((-4.0, U, 8.0), (0, 5)), ((4.0, U, 2.0), (0, 5)),
    ((-13.8, G, 9.8), (-10, 4)), ((-6.2, G, 9.6), (-10, 4)), ((12.6, G, 10.0), (10, 4)), ((6.8, G, 0.2), (10, 4)),
    ((-13.6, G, -2.4), (-10, -6)), ((6.6, G, -9.6), (10, -6)), ((0.0, G, -3.0), (0, -6)), ((-13.8, U, 2.6), (-10, 5)),
    ((14.0, U, 0.2), (10, 5)), ((-7.0, U, -7.2), (-10, -4)), ((13.4, U, -2.2), (10, -6)), ((-3.0, U, -6.0), (0, -6)),
]
PICKUPS = [
    ((2.2, G, 3.4), "shotgun"), ((-2.2, G, 4.2), "akimbo"), ((-7.0, G, 7.6), "revolver"), ((6.4, G, 4.0), "machine_pistol"),
    ((-13.2, G, -6.0), "rifle"), ((13.4, G, -2.0), "shotgun"), ((-2.8, G, -4.4), "sword"), ((-7.2, U, 5.0), "break_action"),
    ((9.5, U, 9.8), "hammer"), ((-8.0, U, -6.0), "sword"), ((12.8, U, -7.4), "burst_rifle"), ((0.0, U, -3.6), "revolver"),
    ((0.0, U, 10.0), "lever_action"),
]


def players(m):
    for pos, toward in SPAWNS:
        m.spawn(pos, toward)
        m.spawn_pts.append(pos)
    for pos, w in PICKUPS:
        m.weapon(pos, w)
        m.weapon_pts.append(pos)


def check(m):
    """Before writing: nothing that moves ends up in a wall, on a spawn point, over a
    pickup, in a doorway that is always open or in another thing that moves, in any
    layout (boxes only: the Godot test checks the real shapes)."""
    problems = []
    statics = [(lo, hi, n) for lo, hi, n in m.solids if (hi[1] - lo[1]) > 0.06 and not n.startswith("Floors")]
    props = [p for p in m.props.values() if p.solids and not p.door]
    keep_clear = []
    for d in DOORS:
        name, axis, line, u0, u1, y0, pattern = d
        if axis == "x":
            keep_clear.append(((u0 - 0.1, y0, line - 1.0), (u1 + 0.1, y0 + 2.0, line + 1.0), name))
        else:
            keep_clear.append(((line - 1.0, y0, u0 - 0.1), (line + 1.0, y0 + 2.0, u1 + 0.1), name))
    # The stairs' feet and heads.
    keep_clear.append(((-1.5, G, STAIR_FOOT), (1.5, G + 2.0, STAIR_FOOT + 1.2), "grand stair foot"))
    keep_clear.append(((-1.5, U, STAIR_TOP - 1.9), (1.5, U + 2.0, STAIR_TOP), "grand stair head"))
    keep_clear.append(((SS_X1, U, SS_Z0), (SS_X1 + 1.5, U + 2.0, SS_Z1 + 1.0), "servants' stair head"))
    keep_clear.append(((SS_X0 - 0.6, G, SS_Z0), (SS_X0 + 1.0, G + 2.0, SS_Z1 + 1.2), "servants' stair foot"))
    for L in range(LAYOUTS):
        for p in props:
            for b in p.boxes(L):
                for lo, hi, n in statics:
                    if overlap(b, (lo, hi), 0.01):
                        problems.append("layout %d: %s inside %s" % (L, p.path, n))
                for s in m.spawn_pts:
                    if overlap(b, ((s[0] - 0.5, s[1], s[2] - 0.5), (s[0] + 0.5, s[1] + 1.9, s[2] + 0.5))):
                        problems.append("layout %d: %s on the spawn at %s" % (L, p.path, s))
                for w in m.weapon_pts:
                    if overlap(b, ((w[0] - 0.6, w[1], w[2] - 0.6), (w[0] + 0.6, w[1] + 1.8, w[2] + 0.6))):
                        problems.append("layout %d: %s over the pickup at %s" % (L, p.path, w))
                for lo, hi, n in keep_clear:
                    if overlap(b, (lo, hi)):
                        problems.append("layout %d: %s in the way at %s" % (L, p.path, n))
        for i, p in enumerate(props):
            for q in props[i + 1:]:
                if any(overlap(a, b) for a in p.boxes(L) for b in q.boxes(L)):
                    problems.append("layout %d: %s and %s overlap" % (L, p.path, q.path))
    # Gliding from one layout to the next, they must not pass through walls.
    for L in range(LAYOUTS):
        for N in range(LAYOUTS):
            if N == L:
                continue
            for p in props:
                (ma, ta), (mb, tb) = p.pose(L), p.pose(N)
                for t in (0.25, 0.5, 0.75):
                    mv = tuple(a + (b - a) * t for a, b in zip(ma, mb))
                    tn = ta + (tb - ta) * t
                    for b in p.boxes(L, mv, tn):
                        for lo, hi, n in statics:
                            if overlap(b, (lo, hi), 0.02) and "Walls" in n:
                                problems.append("%d->%d: %s passes through %s" % (L, N, p.path, n))
    for s in m.spawn_pts:
        for lo, hi, n in statics:
            if overlap(((s[0] - 0.42, s[1] + 0.05, s[2] - 0.42), (s[0] + 0.42, s[1] + 1.8, s[2] + 0.42)), (lo, hi)):
                problems.append("spawn %s inside %s" % (s, n))
    for w in m.weapon_pts:
        for lo, hi, n in statics:
            if overlap(((w[0] - 0.45, w[1] + 0.05, w[2] - 0.45), (w[0] + 0.45, w[1] + 1.6, w[2] + 0.45)), (lo, hi)):
                problems.append("pickup %s inside %s" % (w, n))
    seen = set()
    out = []
    for p in problems:
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def write_palette(path):
    out = ['[gd_resource type="Resource" script_class="MapPalette" format=3]', "",
           '[ext_resource type="Script" path="res://game/arena/map_palette.gd" id="1_pal"]', "", "[resource]",
           'script = ExtResource("1_pal")']

    def dict_lines(name, typ, d, conv):
        return "%s = Dictionary[String, %s]({\n%s\n})" % (name, typ, ",\n".join('"%s": %s' % (k, conv(d[k])) for k in sorted(d)))

    num = lambda v: "%s.0" % int(v) if float(v) == int(v) else fmt(v)
    out.append(dict_lines("colors", "Color", COLORS, color))
    out.append(dict_lines("glow", "float", GLOW, num))
    out.append(dict_lines("surface", "String", SURFACE, lambda v: '"%s"' % v))
    out.append("roughness = 0.86")
    out.append(dict_lines("breakable", "float", BREAKABLE, num))
    out.append(dict_lines("material", "String", MATERIAL, lambda v: '"%s"' % v))
    with open(path, "w") as fh:
        fh.write("\n".join(out) + "\n")


def build(path, strict=True):
    moon_col = (0.62, 0.7, 1.0)
    m = HauntedMap("HauntedHouse", PAL,
                   {"sky": {"sky_top_color": (0.015, 0.02, 0.06), "sky_horizon_color": (0.1, 0.1, 0.18),
                            "ground_bottom_color": (0.01, 0.01, 0.015), "ground_horizon_color": (0.06, 0.06, 0.1)},
                    "lines": ["ambient_light_source = 2", "ambient_light_color = Color(0.5, 0.48, 0.66, 1)",
                              "ambient_light_energy = 0.62", "tonemap_mode = 2", "tonemap_white = 2.4",
                              "glow_enabled = true", "glow_intensity = 0.9", "glow_bloom = 0.08",
                              "ssao_enabled = true", "ssao_intensity = 1.6",
                              "fog_enabled = true", "fog_light_color = Color(0.16, 0.17, 0.26, 1)",
                              "fog_light_energy = 0.8", "fog_density = 0.012", "fog_sky_affect = 0.4"]},
                   (MOON[0], MOON[1], moon_col, 0.75),
                   {"face_shade": "Vector3(0.9, 0.82, 0.62)", "kill_height": "-12.0",
                    "bounds": "Rect2(-17, -13, 34, 26)", "swing_point": "Vector3(0, 7, 5)"})
    m.lights = []
    build_floors(m)
    build_walls(m)
    build_doors(m)
    build_windows(m)
    front_door(m)
    grand_stair(m)
    servants_stair(m)
    foyer(m)
    dining(m)
    parlour(m)
    kitchen(m)
    library(m)
    back_hall(m)
    bedroom(m)
    nursery(m)
    bathroom(m)
    study(m)
    upper_hall(m)
    ghosts(m)
    lights(m)
    haunting(m)
    outside(m)
    players(m)
    problems = check(m)
    for p in problems:
        print("  ! " + p)
    if problems and strict:
        raise SystemExit("%d problems: nothing written" % len(problems))
    m.write(path)
    write_palette(path.replace("game/maps/", "game/maps/palettes/").replace(".tscn", ".tres"))
