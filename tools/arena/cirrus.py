"""Cirrus: a university campus on floating islands (about 135 x 135 m, up to 16 players).

    python3 tools/arena/build_arena_maps.py cirrus

writes game/maps/cirrus.tscn and game/maps/palettes/cirrus.tres FROM SCRATCH. The scene is
an ordinary map scene and is what people edit afterwards (in the Godot editor), so running
this again OVERWRITES ANY HAND EDITS: only do it to rebuild the whole map on purpose.

Layout: the Quad, a round lawn in the middle with the clock tower on it, and five
building islands round it, each a MapIsland: Observatory (north), Labs (north-east),
Lecture Hall (south-east), Cafeteria (south-west) and Library (north-west). All five
are one island shape (a short fan toward the quad, a wide deck behind with the
building on it) with a different building. There is no writing anywhere: each building
is told by its colour and its shape (a dome, glass and roof stacks, a shell roof, a
striped awning, a columned front).

Open sky between everything: an island's tip is 24.4 m (80 ft) from the quad's rim and
neighbours are 24.4 m apart, with no walkways at all. Five stepping stones stand just
off the quad's rim, and five banner masts on the rim and one on each island's tip are
grapple points.

The scene has all five islands at their homes. In a match only two are up at a time
(the LayoutEvent "Layout"): every 60 s the bell goes, eight seconds later the other
three fall away below the map (taking whoever is still on them) and a new pair comes
up, arranged one of five ways picked at random. See game/arena/layout_event.gd.

The numbers behind the gaps (measured with the real movement code): a sprinting jump
clears 7.5 m, with a dive 12.5 m, with a flip 14 m, with a flip and a dive 20.5 m, with
a glide as well 26 m; the rocket boots carry a jump 32 m on the level and at most
10.5 m up (12.8 m with a ledge grab). So 24.4 m is beyond any plain jump, within reach
of the whole chain of moves, and easy for the grapple or the boots.

The look: nothing stepped or stacked. Roofs are slopes, cones and domes (MapBlock's
wedge, cone and dome shapes), furniture and trims are bevelled, stairs are closed in
by sloping sides, trees are round clumps.

Angles in this file are measured the way a node's yaw is: 0 = south (+z), 90 = east,
180 = north, 270 = west. An island is built in its own frame: -z toward the quad, +z
outward, y = 0 its deck.
"""
import math
from arena_builder import Map, yaw_cols, xform, fmt, vec, color, norm, cross, IDENTITY

PAL = "res://game/maps/palettes/cirrus.tres"
SKY = "res://game/maps/sky/cirrus_sky.gdshader"

# The islands: (name, home angle, accent kind, roof kind)
ISLANDS = [
    ("Observatory", 180.0, "accent_purple", "roof_slate"),
    ("Labs", 108.0, "accent_teal", "roof_slate"),
    ("LectureHall", 36.0, "accent_red", "roof_terracotta"),
    ("Cafeteria", 324.0, "accent_orange", "roof_terracotta"),
    ("Library", 252.0, "accent_blue", "roof_terracotta"),
]
QUAD_R = 14.3
GAP = 24.4         # open sky between the quad's rim and an island's tip, and between neighbours (80 ft)
TIP = QUAD_R + GAP # the tip of an island's deck, metres from the middle
FAN = 9.0          # the fan's length, tip to shoulders
R0 = TIP + FAN + 2.0   # an island's own origin is this far from the middle
STONE_R = 19.5     # the stepping stones' middles
MAST_R = 12.8
DOWN = 120.0       # how far below its home an island is parked when it is down
SIN36, COS36 = math.sin(math.radians(36.0)), math.cos(math.radians(36.0))


def edge_x(z):
    """How far out an island's deck may reach at its own z: its side edges are the lines
    half a GAP from the half-way lines to its neighbours, so the gap between two islands
    is GAP all the way along."""
    return ((z + R0) * SIN36 - GAP / 2) / COS36


# An island's deck: a fan from its tip (ZT, half as wide as WT) to its shoulders (ZS,
# WS), then the main deck, as wide as the shoulders, back to MAIN_Z1.
ZT = TIP - R0
ZS = -2.0
WT = edge_x(ZT)
WS = edge_x(ZS)
MAIN_Z1 = 14.2
EDGE_LEN = (ZS - ZT) / COS36     # along a side edge of the fan, tip to shoulder
F2 = 5.5           # first upper floor
F3 = 11.0
RUN = 9.2          # metres a stair takes to climb one floor (31 degrees)

FLIP = ((1, 0, 0), (0, -1, 0), (0, 0, -1))     # upside down
LIE_Z = ((1, 0, 0), (0, 0, 1), (0, -1, 0))     # its own y along world z
LIE_X = ((0, -1, 0), (1, 0, 0), (0, 0, 1))     # its own y along world x
TURN = ((0, 0, 1), (0, 1, 0), (-1, 0, 0))      # its own x along world z (a quarter turn)

COLORS = {
    # buildings
    "stone": (0.9, 0.84, 0.72), "stone_warm": (0.83, 0.72, 0.56), "stone_dark": (0.62, 0.55, 0.46),
    "column": (0.95, 0.91, 0.82), "trim": (0.74, 0.5, 0.24), "brass": (0.82, 0.64, 0.28), "metal": (0.3, 0.29, 0.31),
    "roof_terracotta": (0.72, 0.36, 0.24), "roof_slate": (0.34, 0.39, 0.46), "dome_copper": (0.4, 0.66, 0.6),
    "floor_wood": (0.6, 0.44, 0.3), "floor_tile": (0.82, 0.8, 0.75), "stair": (0.66, 0.6, 0.52), "stair_tread": (0.8, 0.75, 0.66),
    "rail": (0.66, 0.5, 0.26),
    # one accent per building
    "accent_purple": (0.5, 0.36, 0.78), "accent_teal": (0.14, 0.66, 0.68), "accent_red": (0.74, 0.2, 0.2),
    "accent_orange": (0.93, 0.52, 0.12), "accent_blue": (0.2, 0.36, 0.74),
    # ground
    "paving": (0.8, 0.74, 0.64), "path": (0.86, 0.8, 0.68), "lawn": (0.42, 0.62, 0.26),
    "hedge": (0.26, 0.46, 0.2), "leaves": (0.34, 0.58, 0.24), "leaves_gold": (0.8, 0.62, 0.2), "bark": (0.4, 0.29, 0.2),
    "rock": (0.56, 0.48, 0.4), "rock_dark": (0.4, 0.34, 0.3), "planter": (0.76, 0.7, 0.6), "soil": (0.34, 0.25, 0.18),
    # walkways
    "bridge_deck": (0.5, 0.48, 0.47), "span_light": (1.0, 0.7, 0.2), "mast": (0.36, 0.33, 0.32),
    # light
    "engine": (0.3, 0.9, 1.0), "engine_ring": (0.6, 0.42, 0.24), "lamp": (1.0, 0.86, 0.6),
    "window_lit": (1.0, 0.8, 0.45), "screen": (0.62, 0.8, 1.0), "bell": (0.86, 0.64, 0.24),
    "clock_face": (0.96, 0.93, 0.84), "clock_hand": (0.16, 0.15, 0.17),
    # glass: only glass_lab breaks
    "glass_lab": (0.62, 0.95, 0.96, 0.32), "glass_window": (0.75, 0.88, 1.0, 0.2), "glass_sky": (0.8, 0.92, 1.0, 0.16),
    # things
    "shelf": (0.42, 0.29, 0.2), "books_red": (0.62, 0.2, 0.18), "books_blue": (0.2, 0.32, 0.56), "books_green": (0.24, 0.44, 0.3),
    "books_gold": (0.78, 0.62, 0.3), "table": (0.68, 0.52, 0.36), "seat": (0.56, 0.18, 0.2), "counter": (0.78, 0.76, 0.72),
    "equipment": (0.55, 0.58, 0.62), "equipment_dark": (0.26, 0.28, 0.32), "telescope": (0.93, 0.93, 0.9),
    "statue": (0.36, 0.52, 0.46), "kiosk": (0.82, 0.3, 0.26), "banner_gold": (0.92, 0.72, 0.2), "banner_red": (0.72, 0.18, 0.2),
    "banner_blue": (0.2, 0.34, 0.7), "awning": (0.95, 0.92, 0.84),
    # decor
    "pot": (0.72, 0.42, 0.3), "leaves_dark": (0.2, 0.44, 0.24), "ivy": (0.22, 0.42, 0.2),
    "flower_red": (0.86, 0.22, 0.2), "flower_yellow": (0.96, 0.8, 0.22), "flower_white": (0.97, 0.95, 0.9), "flower_pink": (0.92, 0.5, 0.66),
    "cushion_blue": (0.26, 0.4, 0.62), "cushion_green": (0.3, 0.48, 0.36), "rug_red": (0.6, 0.2, 0.2), "rug_blue": (0.2, 0.3, 0.5),
    "rug_cream": (0.88, 0.82, 0.68), "frame": (0.3, 0.2, 0.14), "canvas": (0.94, 0.9, 0.8), "glass_ware": (0.8, 0.95, 1.0, 0.36),
    "star_panel": (0.1, 0.13, 0.26),
}
GLOW = {"engine": 2.2, "lamp": 0.35, "window_lit": 0.2, "span_light": 2.4, "screen": 1.3, "clock_face": 0.5}
# The game's usual patterns, drawn twice the size and under half as strong (see
# write_palette): the walls read as walls, not as a grid of cubes.
SURFACE = {
    "stone": "blocks", "stone_warm": "blocks", "stone_dark": "blocks", "paving": "slabs", "path": "slabs",
    "lawn": "grass", "hedge": "clumps", "leaves": "clumps", "leaves_gold": "clumps", "bark": "bark", "rock": "strata",
    "rock_dark": "strata", "roof_terracotta": "shingles", "roof_slate": "shingles", "floor_wood": "planks",
    "floor_tile": "tiles", "bridge_deck": "plates", "soil": "dirt", "ivy": "clumps", "leaves_dark": "clumps",
}
SURFACE_SCALE = 2.0
SURFACE_STRENGTH = 0.45
MATERIAL = {
    "lawn": "dirt", "soil": "dirt", "hedge": "dirt", "leaves": "dirt", "leaves_gold": "dirt", "floor_wood": "wood",
    "shelf": "wood", "table": "wood", "bark": "wood", "bridge_deck": "metal", "rail": "metal", "mast": "metal",
    "brass": "metal", "bell": "metal", "equipment": "metal", "equipment_dark": "metal", "telescope": "metal",
    "statue": "metal", "dome_copper": "metal", "glass_lab": "glass", "glass_window": "glass", "glass_sky": "glass",
    "glass_ware": "glass", "ivy": "dirt", "leaves_dark": "dirt", "pot": "concrete", "frame": "wood",
}
BREAKABLE = {"glass_lab": 25}   # the labs' glass walls: a pistol shot shatters a pane. No other glass breaks.


def polar(r, deg, y=0.0):
    th = math.radians(deg)
    return (r * math.sin(th), y, r * math.cos(th))


def rot(deg):
    return yaw_cols(math.radians(deg))


class CirrusMap(Map):
    """arena_builder's Map with what only this map needs: nodes with other scripts (the
    islands, the walkways, the layout event, grapple points, bots' crossings), the
    shapes that are not boxes, and a sky made by a shader."""

    EXTRA = {
        "island": "res://game/arena/map_island.gd",
        "layout": "res://game/arena/layout_event.gd",
        "spinner": "res://game/arena/map_spinner.gd",
        "hook": "res://game/arena/map_grapple_point.gd",
        "link": "res://game/arena/map_jump_link.gd",
    }

    def node(self, name, parent, script, props, type_="Node3D", group=False):
        return self._add(name, type_, parent, props, script, group)

    def spawn_in(self, parent, pos, toward):
        """A spawn point inside a group (an island): pos and toward are in the group's frame."""
        self.spawn_count += 1
        yaw = math.atan2(-(toward[0] - pos[0]), -(toward[1] - pos[2]))
        self._add("Spawn%d" % self.spawn_count, "Marker3D", parent, [("transform", xform(yaw_cols(yaw), pos))], "spawn", False)

    def weapon_in(self, parent, pos, weapon):
        self.weapon_count += 1
        props = [("transform", xform(IDENTITY, pos)), ("weapon", '"%s"' % weapon)]
        self._add(weapon.title().replace("_", ""), "Marker3D", parent, props, "weapon", False)

    # -- shapes that are not boxes ---------------------------------------------
    def bev(self, parent, name, kind, lo, hi, bevel=0.08, **kw):
        """A box from corner `lo` to corner `hi` with its edges cut off."""
        c = tuple((a + b) * 0.5 for a, b in zip(lo, hi))
        s = tuple(abs(b - a) for a, b in zip(lo, hi))
        return self.block(parent, name, kind, c, s, shape="bevel", bevel=min(bevel, min(s) * 0.45), **kw)

    def dome(self, parent, name, kind, base, size, sides=12, flip=False, yaw=0.0, **kw):
        """Half a ball standing on `base` (the middle of its flat side), size (x, y, z);
        `flip`: hanging under `base` instead."""
        c = (base[0], base[1] + (-size[1] if flip else size[1]) * 0.5, base[2])
        cols = FLIP if flip else (yaw_cols(math.radians(yaw)) if yaw else IDENTITY)
        return self.block(parent, name, kind, c, size, cols=cols, shape="dome", sides=sides, **kw)

    def cone(self, parent, name, kind, base, diameter, height, top=0.0, sides=12, flip=False, yaw=0.0, **kw):
        """A cone standing on `base` (or, flipped, hanging under it: wide at `base`)."""
        c = (base[0], base[1] + (-height if flip else height) * 0.5, base[2])
        cols = FLIP if flip else (yaw_cols(math.radians(yaw)) if yaw else IDENTITY)
        return self.block(parent, name, kind, c, (diameter, height, diameter), cols=cols, shape="cone", sides=sides, top=top, **kw)

    def wedge(self, parent, name, kind, lo, hi, tall="-z", **kw):
        """A slope filling the box `lo`..`hi`, its tall side toward `tall` (-z, +z, -x or +x)."""
        c = tuple((a + b) * 0.5 for a, b in zip(lo, hi))
        dx, dy, dz = (abs(b - a) for a, b in zip(lo, hi))
        cols, size = {
            "-z": (IDENTITY, (dx, dy, dz)),
            "+z": (((-1, 0, 0), (0, 1, 0), (0, 0, -1)), (dx, dy, dz)),
            "+x": (((0, 0, 1), (0, 1, 0), (-1, 0, 0)), (dz, dy, dx)),
            "-x": (((0, 0, -1), (0, 1, 0), (1, 0, 0)), (dz, dy, dx)),
        }[tall]
        return self.block(parent, name, kind, c, size, cols=cols, shape="wedge", **kw)

    def tri(self, parent, name, kind, corner, leg_x, leg_z, y0, y1, **kw):
        """A right triangle seen from above (a wedge lying on its side): the right angle at
        `corner` (x, z), one leg `leg_x` long along x and the other `leg_z` along z (each
        may be negative), from height y0 to y1."""
        sx = 1.0 if leg_x > 0 else -1.0
        sz = 1.0 if leg_z > 0 else -1.0
        cols = ((0, -sx * sz, 0), (sx, 0, 0), (0, 0, sz))
        c = (corner[0] + leg_x * 0.5, (y0 + y1) * 0.5, corner[1] + leg_z * 0.5)
        return self.block(parent, name, kind, c, (y1 - y0, abs(leg_x), abs(leg_z)), cols=cols, shape="wedge", **kw)

    def rail_box(self, parent, lo, hi):
        """A railing filling the box lo..hi (1 m high, thin one way): two brass bars and
        a post at each end to look at, and an invisible solid panel to lean on."""
        self.box(parent, "RailPanel", "rail", lo, hi, drawn=False)
        along_x = (hi[0] - lo[0]) >= (hi[2] - lo[2])
        y0, y1 = lo[1], hi[1]
        for name, a, b in (("RailTop", y1 - 0.09, y1), ("RailBar", y0 + 0.42, y0 + 0.5)):
            self.strip(parent, name, "rail", (lo[0], a, lo[2]), (hi[0], b, hi[2]))
        length = (hi[0] - lo[0]) if along_x else (hi[2] - lo[2])
        count = max(2, int(round(length / 2.2)) + 1)
        for i in range(count):
            u = i / (count - 1)
            if along_x:
                x = lo[0] + 0.05 + (length - 0.1) * u
                self.strip(parent, "RailPost", "metal", (x - 0.05, y0, lo[2] - 0.01), (x + 0.05, y1 - 0.09, hi[2] + 0.01))
            else:
                z = lo[2] + 0.05 + (length - 0.1) * u
                self.strip(parent, "RailPost", "metal", (lo[0] - 0.01, y0, z - 0.05), (hi[0] + 0.01, y1 - 0.09, z + 0.05))

    def rail(self, parent, name, kind, a, b, y, height=1.1, thick=0.12, holes=(), **kw):
        """Brass railings ("rail") are drawn as bars; anything else is a low wall, as in arena_builder."""
        if kind != "rail":
            return Map.rail(self, parent, name, kind, a, b, y, height, thick, holes, **kw)
        along_x = abs(b[0] - a[0]) >= abs(b[1] - a[1])
        length = abs(b[0] - a[0]) if along_x else abs(b[1] - a[1])
        start = min(a[0], b[0]) if along_x else min(a[1], b[1])
        line = a[1] if along_x else a[0]
        u = 0.0
        runs = []
        for h0, h1 in sorted(holes):
            if h0 - u > 0.05:
                runs.append((u, h0))
            u = h1
        if length - u > 0.05:
            runs.append((u, length))
        for u0, u1 in runs:
            if along_x:
                self.rail_box(parent, (start + u0, y, line - thick / 2), (start + u1, y + height, line + thick / 2))
            else:
                self.rail_box(parent, (line - thick / 2, y, start + u0), (line + thick / 2, y + height, start + u1))

    def write(self, path):
        scripts = dict(__import__("arena_builder").SCRIPTS)
        scripts.update(self.EXTRA)
        ids = {}
        out = ["[gd_scene format=3]", ""]
        for i, (k, p) in enumerate(scripts.items()):
            ids[k] = "%d_%s" % (i + 1, k)
            out.append('[ext_resource type="Script" path="%s" id="%s"]' % (p, ids[k]))
        out.append('[ext_resource type="Resource" path="%s" id="pal"]' % self.palette)
        out.append('[ext_resource type="Shader" path="%s" id="sky"]' % SKY)
        elev, azim, col, energy = self.sun
        e, az = math.radians(elev), math.radians(azim)
        Z = norm((math.sin(az) * math.cos(e), math.sin(e), -math.cos(az) * math.cos(e)))
        X = norm(cross((0, 1, 0), Z))
        out += ["", '[sub_resource type="ShaderMaterial" id="ShaderMaterial_sky"]', 'shader = ExtResource("sky")',
                "shader_parameter/sun_dir = %s" % vec(Z), "",
                '[sub_resource type="Sky" id="Sky_1"]', 'sky_material = SubResource("ShaderMaterial_sky")', "",
                '[sub_resource type="Environment" id="Environment_1"]', "background_mode = 2", 'sky = SubResource("Sky_1")']
        out += self.env["lines"]
        out += ["", '[node name="%s" type="Node3D"]' % self.root, 'script = ExtResource("%s")' % ids["root"],
                'palette = ExtResource("pal")']
        for k, v in self.settings.items():
            out.append("%s = %s" % (k, v))
        out += ["", '[node name="Environment" type="WorldEnvironment" parent="."]', 'environment = SubResource("Environment_1")', ""]
        out += ['[node name="Sun" type="DirectionalLight3D" parent="."]', "transform = %s" % xform((X, cross(Z, X), Z), (0, 0, 0)),
                "light_color = %s" % color(col), "light_energy = %s" % fmt(energy), "shadow_enabled = true",
                "directional_shadow_max_distance = 190.0", ""]
        for n in self.nodes:
            groups = [v for k, v in n.props if k == "groups"]
            out.append('[node name="%s" type="%s" parent="%s"%s]' % (n.name, n.type, n.parent, " groups=%s" % groups[0] if groups else ""))
            for k, v in n.props:
                if k == "transform":
                    out.append("%s = %s" % (k, v))
            if n.script:
                out.append('script = ExtResource("%s")' % ids[n.script])
            for k, v in n.props:
                if k != "transform" and k != "groups":
                    out.append("%s = %s" % (k, v))
            if n.group:
                out.append("metadata/_edit_group_ = true")
            out.append("")
        with open(path, "w") as fh:
            fh.write("\n".join(out))
        blocks = sum(1 for n in self.nodes if n.script == "block")
        print("wrote %s: %d nodes (%d blocks), %d spawns, %d weapon pickups" % (path, len(self.nodes), blocks, self.spawn_count, self.weapon_count))


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
    out.append("surface_scale = %s" % fmt(SURFACE_SCALE))
    out.append("surface_strength = %s" % fmt(SURFACE_STRENGTH))
    out.append("roughness = 0.88")
    out.append(dict_lines("breakable", "float", BREAKABLE, num))
    out.append(dict_lines("material", "String", MATERIAL, lambda v: '"%s"' % v))
    with open(path, "w") as fh:
        fh.write("\n".join(out) + "\n")


# ---------------------------------------------------------------------------
# Pieces every building uses. All in the frame of the group they are given.

def floor(m, g, name, kind, x0, x1, z0, z1, top, thick=0.3, holes=(), **kw):
    """A floor slab with rectangular holes (x0, x1, z0, z1) cut out of it."""
    xs = sorted(set([x0, x1] + [v for h in holes for v in h[:2] if x0 < v < x1]))
    zs = sorted(set([z0, z1] + [v for h in holes for v in h[2:] if z0 < v < z1]))
    for j in range(len(zs) - 1):
        run = None
        for i in range(len(xs) - 1):
            cx, cz = (xs[i] + xs[i + 1]) / 2, (zs[j] + zs[j + 1]) / 2
            hole = any(h[0] <= cx <= h[1] and h[2] <= cz <= h[3] for h in holes)
            if hole:
                if run:
                    m.box(g, name, kind, (run[0], top - thick, zs[j]), (run[1], top, zs[j + 1]), **kw)
                run = None
            else:
                run = (run[0], xs[i + 1]) if run else (xs[i], xs[i + 1])
        if run:
            m.box(g, name, kind, (run[0], top - thick, zs[j]), (run[1], top, zs[j + 1]), **kw)



def wall(m, g, name, kind, a, b, y0, y1, t, holes=(), **kw):
    """A straight wall along x or z from (x, z) `a` to `b`, from height y0 to y1, with
    openings (from, to, bottom, top): metres along the wall from its west or north end,
    and heights. Unlike arena_builder's wall, openings may stand one above another. A
    fifth number makes the top of the opening an arch that many metres high."""
    along_x = abs(b[0] - a[0]) >= abs(b[1] - a[1])
    length = abs(b[0] - a[0]) if along_x else abs(b[1] - a[1])
    start = min(a[0], b[0]) if along_x else min(a[1], b[1])
    line = a[1] if along_x else a[0]
    us = sorted(set([0.0, length] + [v for h in holes for v in h[:2] if 0.0 < v < length]))
    for i in range(len(us) - 1):
        u0, u1 = us[i], us[i + 1]
        um = (u0 + u1) / 2
        gaps = sorted((max(h[2], y0), min(h[3], y1)) for h in holes if h[0] <= um <= h[1])
        y = y0
        runs = []
        for lo, hi in gaps:
            if lo > y + 0.01:
                runs.append((y, lo))
            y = max(y, hi)
        if y1 > y + 0.01:
            runs.append((y, y1))
        for lo, hi in runs:
            if along_x:
                m.box(g, name, kind, (start + u0, lo, line - t / 2), (start + u1, hi, line + t / 2), **kw)
            else:
                m.box(g, name, kind, (line - t / 2, lo, start + u0), (line + t / 2, hi, start + u1), **kw)
    for h in holes:
        if len(h) > 4 and h[4] > 0:
            u = start + (h[0] + h[1]) / 2
            size = (h[1] - h[0], h[4], t)
            if along_x:
                m.block(g, name + "Arch", kind, (u, h[3] - h[4] / 2, line), size, shape="arch", sides=8, **kw)
            else:
                m.block(g, name + "Arch", kind, (line, h[3] - h[4] / 2, u), size, cols=TURN, shape="arch", sides=8, **kw)


def walls(m, g, kind, x0, x1, z0, z1, y0, y1, t=0.4, front=(), back=(), west=(), east=(), name="Wall", **kw):
    """Four walls round a rectangle, their middles on its edges. front is the wall at z0
    (toward the quad), back at z1, west at x0, east at x1. Openings are (from, to, bottom,
    top[, arch]): metres along the wall from its west end (front, back) or its front end
    (west, east), and heights."""
    h = t / 2
    shift = lambda holes, d: [(o[0] + d, o[1] + d) + tuple(o[2:]) for o in holes]
    wall(m, g, name + "Front", kind, (x0 - h, z0), (x1 + h, z0), y0, y1, t, shift(front, h), **kw)
    wall(m, g, name + "Back", kind, (x0 - h, z1), (x1 + h, z1), y0, y1, t, shift(back, h), **kw)
    wall(m, g, name + "West", kind, (x0, z0 + h), (x0, z1 - h), y0, y1, t, shift(west, -h), **kw)
    wall(m, g, name + "East", kind, (x1, z0 + h), (x1, z1 - h), y0, y1, t, shift(east, -h), **kw)


def band(m, g, kind, x0, x1, z0, z1, y0, y1, t=0.4, out=0.08, name="Band"):
    """A drawn-only band of colour round the outside of a building's walls (its accent)."""
    h = t / 2
    m.strip(g, name, kind, (x0 - h - out, y0, z0 - h - out), (x1 + h + out, y1, z0 - h))
    m.strip(g, name, kind, (x0 - h - out, y0, z1 + h), (x1 + h + out, y1, z1 + h + out))
    m.strip(g, name, kind, (x0 - h - out, y0, z0 - h), (x0 - h, y1, z1 + h))
    m.strip(g, name, kind, (x1 + h, y0, z0 - h), (x1 + h + out, y1, z1 + h))



def roof(m, g, kind, x0, x1, z0, z1, top, holes=(), parapet=0.8):
    """A flat roof to walk on: the slab (with holes: hatches to drop in by, skylights), a
    cornice under its edge and a low stone parapet with a cap round it."""
    # (a plain ceiling under it, the roof's own colour only on top)
    floor(m, g, "Roof", "stone_warm", x0 - 0.3, x1 + 0.3, z0 - 0.3, z1 + 0.3, top, 0.35, holes)
    floor(m, g, "RoofSkin", kind, x0 - 0.3, x1 + 0.3, z0 - 0.3, z1 + 0.3, top + 0.02, 0.02, holes, solid=False)
    for lo, hi in (((x0 - 0.55, top - 0.75, z0 - 0.55), (x1 + 0.55, top - 0.35, z0 - 0.2)), ((x0 - 0.55, top - 0.75, z1 + 0.2), (x1 + 0.55, top - 0.35, z1 + 0.55)),
                   ((x0 - 0.55, top - 0.75, z0 - 0.2), (x0 - 0.2, top - 0.35, z1 + 0.2)), ((x1 + 0.2, top - 0.75, z0 - 0.2), (x1 + 0.55, top - 0.35, z1 + 0.2))):
        m.bev(g, "Cornice", "trim", lo, hi, 0.12, solid=False)
    if parapet > 0:
        low_wall(m, g, (x0 - 0.15, z0 - 0.15), (x1 + 0.15, z0 - 0.15), top, parapet)
        low_wall(m, g, (x0 - 0.15, z1 + 0.15), (x1 + 0.15, z1 + 0.15), top, parapet)
        low_wall(m, g, (x0 - 0.15, z0), (x0 - 0.15, z1), top, parapet)
        low_wall(m, g, (x1 + 0.15, z0), (x1 + 0.15, z1), top, parapet)
    for hx0, hx1, hz0, hz1 in holes:
        for lo, hi in (((hx0 - 0.15, top, hz0 - 0.15), (hx1 + 0.15, top + 0.18, hz0)), ((hx0 - 0.15, top, hz1), (hx1 + 0.15, top + 0.18, hz1 + 0.15)),
                       ((hx0 - 0.15, top, hz0), (hx0, top + 0.18, hz1)), ((hx1, top, hz0), (hx1 + 0.15, top + 0.18, hz1))):
            m.strip(g, "HatchRim", "metal", lo, hi)


def low_wall(m, g, a, b, y, height=0.9, holes=(), kind="stone"):
    """A low stone wall with a cap (a parapet, a balustrade) along x or z, with gaps."""
    along_x = abs(b[0] - a[0]) >= abs(b[1] - a[1])
    length = abs(b[0] - a[0]) if along_x else abs(b[1] - a[1])
    start = min(a[0], b[0]) if along_x else min(a[1], b[1])
    line = a[1] if along_x else a[0]
    u = 0.0
    runs = []
    for h0, h1 in sorted(holes):
        if h0 - u > 0.05:
            runs.append((u, h0))
        u = h1
    if length - u > 0.05:
        runs.append((u, length))
    for u0, u1 in runs:
        if along_x:
            m.box(g, "Parapet", kind, (start + u0, y, line - 0.15), (start + u1, y + height - 0.1, line + 0.15))
            m.bev(g, "ParapetCap", "stone_warm", (start + u0 - 0.04, y + height - 0.1, line - 0.24), (start + u1 + 0.04, y + height, line + 0.24), 0.04)
        else:
            m.box(g, "Parapet", kind, (line - 0.15, y, start + u0), (line + 0.15, y + height - 0.1, start + u1))
            m.bev(g, "ParapetCap", "stone_warm", (line - 0.24, y + height - 0.1, start + u0 - 0.04), (line + 0.24, y + height, start + u1 + 0.04), 0.04)


def lit_windows(m, g, axis, face, out, spots, y0, y1, width=1.6, arched=False):
    """Drawn-only window panels on an outside wall (they light up at sunset): spots are
    positions along the wall. Arched: a round head on each."""
    for u in spots:
        m.on_wall(g, "WindowFrame", "metal", axis, face, out, u - width / 2 - 0.1, u + width / 2 + 0.1, y0 - 0.1, y1 + (0 if arched else 0.1), depth=0.06)
        m.on_wall(g, "Window", "window_lit", axis, face, out, u - width / 2, u + width / 2, y0, y1, depth=0.05, lift=0.06)
        if arched:
            cols = LIE_Z if axis == "x" else LIE_X
            at = lambda d: (u, y1, face + out * d) if axis == "x" else (face + out * d, y1, u)
            m.block(g, "WindowFrame", "metal", at(0.03), (width + 0.2, 0.05, width + 0.2), cols=cols, shape="cyl", sides=16, solid=False)
            m.block(g, "Window", "window_lit", at(0.08), (width, 0.04, width), cols=cols, shape="cyl", sides=16, solid=False)


def lamp_post(m, g, x, z, y=0.0, height=3.2):
    m.cyl(g, "LampPost", "metal", (x, y, z), 0.16, height, sides=8)
    m.dome(g, "Lamp", "lamp", (x, y + height + 0.24, z), (0.52, 0.26, 0.52), sides=8, solid=False)
    m.dome(g, "Lamp", "lamp", (x, y + height + 0.24, z), (0.52, 0.24, 0.52), sides=8, flip=True, solid=False)
    m.cone(g, "LampCap", "metal", (x, y + height + 0.4, z), 0.66, 0.22, sides=8, solid=False)


def tree(m, g, x, z, y=0.0, kind="leaves", size=1.0):
    """A tapering trunk and three round clumps of leaves."""
    t = m.group("Tree", g, at=(x, y, z))
    s = size
    m.cone(t, "Trunk", "bark", (0, 0, 0), 0.62 * s, 3.2 * s, top=0.34 * s, sides=8)
    for i, (dx, dy, dz, r) in enumerate(((0.0, 3.9, 0.0, 1.9), (1.15, 3.2, 0.55, 1.35), (-0.95, 3.3, -0.75, 1.45))):
        tint = (1.0, 1.0, 1.0) if i else (1.07, 1.07, 1.0)
        m.dome(t, "Leaves", kind, (dx * s, dy * s, dz * s), (2 * r * s, 0.95 * r * s, 2 * r * s), sides=10, solid=False, tint=tint)
        m.dome(t, "Leaves", kind, (dx * s, dy * s, dz * s), (2 * r * s, 0.6 * r * s, 2 * r * s), sides=10, flip=True, solid=False, tint=(0.88, 0.88, 0.88))


def bench(m, g, x, z, y=0.0):
    """A park bench along x: a slatted seat and back on two legs."""
    m.box(g, "BenchBody", "table", (x - 1.0, y, z - 0.26), (x + 1.0, y + 0.5, z + 0.3), drawn=False)
    m.bev(g, "BenchSeat", "table", (x - 1.05, y + 0.4, z - 0.26), (x + 1.05, y + 0.5, z + 0.22), 0.03, solid=False)
    m.bev(g, "BenchBack", "table", (x - 1.05, y + 0.62, z + 0.2), (x + 1.05, y + 1.0, z + 0.28), 0.03, solid=False)
    for dx in (-0.8, 0.8):
        m.strip(g, "BenchLeg", "metal", (x + dx - 0.04, y, z - 0.2), (x + dx + 0.04, y + 0.4, z + 0.26))
        m.strip(g, "BenchLeg", "metal", (x + dx - 0.04, y + 0.4, z + 0.2), (x + dx + 0.04, y + 0.95, z + 0.26))


def table(m, g, lo, hi, y=0.0, height=0.78, kind="table"):
    """A table from (x, z) `lo` to `hi`: a thin top on two trestles. Solid as one box."""
    (x0, z0), (x1, z1) = lo, hi
    m.box(g, "TableBody", kind, (x0, y, z0), (x1, y + height, z1), drawn=False)
    m.bev(g, "TableTop", kind, (x0 - 0.05, y + height - 0.08, z0 - 0.05), (x1 + 0.05, y + height, z1 + 0.05), 0.03, solid=False)
    if x1 - x0 >= z1 - z0:
        for x in (x0 + 0.35, x1 - 0.35):
            m.strip(g, "TableLeg", kind, (x - 0.06, y, z0 + 0.08), (x + 0.06, y + height - 0.08, z1 - 0.08), tint=(0.8, 0.8, 0.8))
    else:
        for z in (z0 + 0.35, z1 - 0.35):
            m.strip(g, "TableLeg", kind, (x0 + 0.08, y, z - 0.06), (x1 - 0.08, y + height - 0.08, z + 0.06), tint=(0.8, 0.8, 0.8))


def counter(m, g, lo, hi, y=0.0, height=1.05, kind="counter", top="table"):
    """A counter or a workbench from (x, z) `lo` to `hi`: a body set back under a top that
    overhangs, on a dark plinth. Solid as one box."""
    (x0, z0), (x1, z1) = lo, hi
    m.box(g, "CounterBody", kind, (x0, y, z0), (x1, y + height, z1), drawn=False)
    m.strip(g, "CounterPlinth", "metal", (x0 + 0.1, y, z0 + 0.1), (x1 - 0.1, y + 0.12, z1 - 0.1))
    m.strip(g, "CounterFront", kind, (x0 + 0.04, y + 0.12, z0 + 0.04), (x1 - 0.04, y + height - 0.09, z1 - 0.04))
    m.bev(g, "CounterTop", top, (x0 - 0.06, y + height - 0.09, z0 - 0.06), (x1 + 0.06, y + height, z1 + 0.06), 0.035, solid=False)


def engines(m, g, spots, y, size=2.2):
    """Glowing engines under an island (drawn only): a collar, a nozzle narrowing down
    from it, and the flame."""
    for x, z in spots:
        m.cyl(g, "EngineCollar", "engine_ring", (x, y - 0.5, z), size + 0.5, 0.5, sides=12, solid=False)
        m.cone(g, "EngineNozzle", "engine_ring", (x, y - 0.5, z), size, 0.9, top=size * 0.66, sides=12, flip=True, solid=False, tint=(0.82, 0.82, 0.82))
        m.cyl(g, "Engine", "engine", (x, y - 1.5, z), size * 0.62, 0.12, sides=12, solid=False)
        m.cone(g, "EngineFlame", "engine", (x, y - 1.5, z), size * 0.5, size * 0.7, sides=10, flip=True, solid=False, tint=(1.15, 1.15, 1.15))


def stairs(m, g, name, a, b, width, fill=True, base=None, sides=(True, True), side_kind="stone_warm"):
    """A staircase from its foot `a` to its head `b` (each x, y, z), along x or z. You walk
    on an invisible ramp (the bots' navigation mesh does too); the steps are drawn only,
    each with a lighter tread that overhangs the one below, and a sloping side closes
    them in so no zigzag shows. `fill`: solid down to `base` (the foot's height unless
    given); otherwise open underneath, with a sloping soffit. `sides`: which of the two
    sloping sides to make (the north or west one, the south or east one): leave out one
    that would lie inside a wall."""
    sg = m.group(name, g)
    m.slab(sg, "Ramp", "stair", a, b, width, thick=0.3, drawn=False, unbreakable=True)
    rise = b[1] - a[1]
    n = max(1, int(round(rise / 0.22)))
    dx, dz = b[0] - a[0], b[2] - a[2]
    along_x = abs(dx) >= abs(dz)
    floor_y = a[1] if base is None else base
    sgn = 1.0 if (dx if along_x else dz) > 0 else -1.0
    for i in range(n):
        t0, t1 = i / n, (i + 1) / n
        top = a[1] + rise * t1
        low = floor_y if fill else top - 0.42
        if along_x:
            p, q = a[0] + dx * t0, a[0] + dx * t1
            m.strip(sg, "Step", "stair", (min(p, q), low, a[2] - width / 2), (max(p, q), top - 0.05, a[2] + width / 2))
            p -= sgn * 0.05
            m.strip(sg, "Tread", "stair_tread", (min(p, q), top - 0.05, a[2] - width / 2), (max(p, q), top, a[2] + width / 2))
        else:
            p, q = a[2] + dz * t0, a[2] + dz * t1
            m.strip(sg, "Step", "stair", (a[0] - width / 2, low, min(p, q)), (a[0] + width / 2, top - 0.05, max(p, q)))
            p -= sgn * 0.05
            m.strip(sg, "Tread", "stair_tread", (a[0] - width / 2, top - 0.05, min(p, q)), (a[0] + width / 2, top, max(p, q)))
    if fill:
        if along_x:
            m.wedge(sg, "Fill", "stair", (min(a[0], b[0]), floor_y, a[2] - width / 2), (max(a[0], b[0]), b[1], a[2] + width / 2),
                    tall="+x" if dx > 0 else "-x", drawn=False, unbreakable=True)
        else:
            m.wedge(sg, "Fill", "stair", (a[0] - width / 2, floor_y, min(a[2], b[2])), (a[0] + width / 2, b[1], max(a[2], b[2])),
                    tall="+z" if dz > 0 else "-z", drawn=False, unbreakable=True)
    else:
        m.slab(sg, "Soffit", side_kind, (a[0], a[1] - 0.2, a[2]), (b[0], b[1] - 0.2, b[2]), width, thick=0.26, solid=False)
    for on, s in zip(sides, (-1.0, 1.0)):
        if on:
            off = s * (width / 2 + 0.08)
            sa = (a[0], a[1] + 0.2, a[2] + off) if along_x else (a[0] + off, a[1] + 0.2, a[2])
            sb = (b[0], b[1] + 0.2, b[2] + off) if along_x else (b[0] + off, b[1] + 0.2, b[2])
            m.slab(sg, "Side", side_kind, sa, sb, 0.16, thick=0.8, solid=False)
    return sg


# ---------------------------------------------------------------------------
# Decor: plants, furniture, lights. Small things are drawn only (solid=False), so
# nothing snags a slide, a wall run or a swing; only big pieces (shelves, counters,
# desks, large planters, tree trunks) are solid, as cover. Lamps are the kind "lamp":
# they come on at sunset with the windows, and turn red on an island that is doomed.

def _turn(face, lo, hi):
    """A box given in a thing's own frame (it looks along its own +z) as map offsets, for
    a thing that looks along `face` (+z, -z, +x or -x)."""
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    if face == "+z":
        return (x0, y0, z0), (x1, y1, z1)
    if face == "-z":
        return (-x1, y0, -z1), (-x0, y1, -z0)
    if face == "+x":
        return (z0, y0, x0), (z1, y1, x1)
    return (-z1, y0, -x1), (-z0, y1, -x0)


def part(m, g, name, kind, at, face, lo, hi, bevel=None, **kw):
    """One box of a piece of furniture standing at `at` (x, y, z) and looking along `face`."""
    a, b = _turn(face, lo, hi)
    a = tuple(p + q for p, q in zip(at, a))
    b = tuple(p + q for p, q in zip(at, b))
    kw.setdefault("solid", False)
    if bevel:
        return m.bev(g, name, kind, a, b, bevel, **kw)
    return m.box(g, name, kind, a, b, **kw)


def ball(m, g, name, kind, at, size, sides=8, **kw):
    """A round lump: a dome and its mirror image under it. `at` is its middle."""
    kw.setdefault("solid", False)
    m.dome(g, name, kind, at, (size, size * 0.5, size), sides=sides, **kw)
    m.dome(g, name, kind, at, (size, size * 0.5, size), sides=sides, flip=True, **kw)


def clump(m, g, kind, at, size, tint=None):
    """A clump of leaves: round on top, shallower underneath."""
    m.dome(g, "Leaves", kind, at, (size, size * 0.5, size), sides=8, solid=False, tint=tint)
    m.dome(g, "Leaves", kind, at, (size, size * 0.3, size), sides=8, flip=True, solid=False, tint=(0.86, 0.86, 0.86))


def potted(m, g, x, z, y=0.0, size=1.0, kind="leaves", pot="pot"):
    """A plant in a pot: a low bushy one."""
    s = size
    m.cone(g, "Pot", pot, (x, y + 0.5 * s, z), 0.62 * s, 0.5 * s, top=0.42 * s, sides=10, flip=True, solid=False)
    m.cyl(g, "PotRim", pot, (x, y + 0.5 * s, z), 0.7 * s, 0.07 * s, sides=10, solid=False, tint=(0.9, 0.9, 0.9))
    clump(m, g, kind, (x, y + 0.82 * s, z), 0.95 * s)
    clump(m, g, kind, (x + 0.2 * s, y + 1.12 * s, z - 0.12 * s), 0.6 * s, tint=(1.08, 1.08, 1.0))


def floor_plant(m, g, x, z, y=0.0, size=1.0, kind="leaves_dark", pot="planter"):
    """A tall plant in a tub: a stem and three clumps up it."""
    s = size
    m.cyl(g, "Tub", pot, (x, y, z), 0.74 * s, 0.56 * s, sides=10, solid=False)
    m.cyl(g, "TubSoil", "soil", (x, y + 0.56 * s, z), 0.62 * s, 0.03, sides=10, solid=False)
    m.cyl(g, "Stem", "bark", (x, y + 0.56 * s, z), 0.09 * s, 1.5 * s, sides=6, solid=False)
    for dx, dy, dz, r in ((0.0, 2.1, 0.0, 1.0), (0.32, 1.55, 0.18, 0.8), (-0.28, 1.25, -0.22, 0.74)):
        clump(m, g, kind, (x + dx * s, y + dy * s, z + dz * s), r * s, tint=(1.06, 1.06, 1.0) if dy > 2 else None)


FLOWERS = ["flower_red", "flower_yellow", "flower_white", "flower_pink"]


def planter_box(m, g, lo, hi, y=0.0, height=0.5, flowers=True, hedge=True, seed=0):
    """A planter from (x, z) `lo` to `hi`: solid, low enough to vault, a hedge in it and
    flowers along its edges."""
    (x0, z0), (x1, z1) = lo, hi
    m.bev(g, "PlanterBox", "planter", (x0, y, z0), (x1, y + height, z1), 0.07)
    m.strip(g, "PlanterSoil", "soil", (x0 + 0.1, y + height, z0 + 0.1), (x1 - 0.1, y + height + 0.03, z1 - 0.1))
    along_x = (x1 - x0) >= (z1 - z0)
    if hedge:
        if along_x:
            m.bev(g, "Hedge", "hedge", (x0 + 0.5, y + height, z0 + 0.22), (x1 - 0.5, y + height + 0.55, z1 - 0.22), 0.2, solid=False)
        else:
            m.bev(g, "Hedge", "hedge", (x0 + 0.22, y + height, z0 + 0.5), (x1 - 0.22, y + height + 0.55, z1 - 0.5), 0.2, solid=False)
    if flowers:
        length = (x1 - x0) if along_x else (z1 - z0)
        n = max(2, int(length / 0.55))
        for i in range(n):
            u = 0.3 + (length - 0.6) * i / (n - 1)
            kind = FLOWERS[(i + seed) % 4]
            side = -1 if i % 2 else 1
            if along_x:
                at = (x0 + u, y + height + 0.1, (z0 + z1) / 2 + side * ((z1 - z0) / 2 - 0.16)) if hedge else (x0 + u, y + height + 0.1, (z0 + z1) / 2 + side * 0.12)
            else:
                at = ((x0 + x1) / 2 + side * ((x1 - x0) / 2 - 0.16), y + height + 0.1, z0 + u) if hedge else ((x0 + x1) / 2 + side * 0.12, y + height + 0.1, z0 + u)
            m.dome(g, "Flower", kind, at, (0.3, 0.2, 0.3), sides=6, solid=False)


def flower_bed(m, g, x, z, y=0.0, size=2.0, seed=0):
    """A round bed of flowers on a lawn: drawn only."""
    m.cyl(g, "Bed", "soil", (x, y, z), size, 0.08, sides=12, solid=False)
    clump(m, g, "hedge", (x, y + 0.3, z), size * 0.45)
    for i in range(7):
        a = math.radians(i * 360.0 / 7 + seed * 20.0)
        m.dome(g, "Flower", FLOWERS[(i + seed) % 4], (x + math.sin(a) * size * 0.34, y + 0.08, z + math.cos(a) * size * 0.34), (0.42, 0.3, 0.42), sides=6, solid=False)


def shrub(m, g, x, z, y=0.0, size=1.2, kind="hedge"):
    m.dome(g, "Shrub", kind, (x, y, z), (size, size * 0.62, size), sides=8, solid=False)
    m.dome(g, "Shrub", kind, (x + size * 0.34, y, z + size * 0.2), (size * 0.66, size * 0.44, size * 0.66), sides=8, solid=False, tint=(1.08, 1.08, 1.0))


def hanging_basket(m, g, x, y, z, drop=0.9, seed=0):
    """A basket of flowers hanging `drop` metres under (x, y, z)."""
    m.strip(g, "BasketChain", "metal", (x - 0.02, y - drop + 0.2, z - 0.02), (x + 0.02, y, z + 0.02))
    m.dome(g, "Basket", "pot", (x, y - drop + 0.2, z), (0.6, 0.32, 0.6), sides=8, flip=True, solid=False)
    clump(m, g, "leaves", (x, y - drop + 0.3, z), 0.74)
    for i in range(3):
        a = math.radians(i * 120.0 + seed * 40.0)
        m.dome(g, "Flower", FLOWERS[(i + seed) % 4], (x + math.sin(a) * 0.26, y - drop + 0.36, z + math.cos(a) * 0.26), (0.26, 0.2, 0.26), sides=6, solid=False)


def ivy(m, g, axis, face, out, u0, u1, y0, y1, seed=0):
    """Ivy up an outside wall: rounded clumps lying against it (thick at the foot, thinning
    out and wandering toward the top), each bulging a different amount so no two share a
    plane. Drawn only."""
    rng = __import__("random").Random(1000 + seed)
    if axis == "x":
        cols = ((1, 0, 0), (0, 0, out), (0, -out, 0))
    else:
        cols = ((0, -out, 0), (out, 0, 0), (0, 0, 1))
    rows = max(2, int(round((y1 - y0) / 0.95)))
    across = max(1, int(round((u1 - u0) / 1.05)))
    k = 0
    for r in range(rows):
        up = r / max(1, rows - 1)
        for c in range(across):
            if rng.random() < up * 0.62:
                continue    # bare wall showing through, more of it higher up
            w = rng.uniform(1.0, 1.7) * (1.0 - 0.3 * up)
            h = rng.uniform(1.0, 1.6) * (1.0 - 0.25 * up)
            d = rng.uniform(0.14, 0.3) * (1.0 - 0.4 * up)
            u = u0 + (c + 0.5 + rng.uniform(-0.3, 0.3)) * (u1 - u0) / across
            u = min(max(u, u0 + w * 0.4), u1 - w * 0.4)
            y = max(y0 + h * 0.3, y0 + (r + 0.5 + rng.uniform(-0.3, 0.3)) * (y1 - y0) / rows)
            tint = ((1.0, 1.0, 1.0), (0.86, 0.9, 0.86), (1.06, 1.08, 0.98))[k % 3]
            k += 1
            at = (u, y, face + out * d * 0.5) if axis == "x" else (face + out * d * 0.5, y, u)
            size = (w, d, h) if axis == "x" else (h, d, w)
            m.block(g, "Ivy", "ivy", at, size, cols=cols, shape="dome", sides=7, solid=False, tint=tint)


def chair(m, g, x, z, y=0.0, face="+z", kind="table", seat="seat"):
    """A plain chair: drawn only."""
    at = (x, y, z)
    part(m, g, "ChairSeat", seat, at, face, (-0.24, 0.42, -0.24), (0.24, 0.5, 0.24), bevel=0.03)
    part(m, g, "ChairBack", kind, at, face, (-0.24, 0.5, -0.26), (0.24, 0.98, -0.2), bevel=0.025)
    for sx in (-1, 1):
        part(m, g, "ChairLegs", kind, at, face, (sx * 0.22 - 0.025, 0, -0.22), (sx * 0.22 + 0.025, 0.42, 0.22), tint=(0.8, 0.8, 0.8))


def armchair(m, g, x, z, y=0.0, face="+z", kind="cushion_blue"):
    """A low upholstered armchair: drawn only."""
    at = (x, y, z)
    part(m, g, "ArmchairSeat", kind, at, face, (-0.46, 0.1, -0.4), (0.46, 0.5, 0.46), bevel=0.1)
    part(m, g, "ArmchairBack", kind, at, face, (-0.46, 0.38, -0.52), (0.46, 1.05, -0.3), bevel=0.1, tint=(0.9, 0.9, 0.9))
    for sx in (-1, 1):
        part(m, g, "ArmchairArm", kind, at, face, (sx * 0.43 - 0.11, 0.3, -0.42), (sx * 0.43 + 0.11, 0.72, 0.42), bevel=0.08, tint=(0.94, 0.94, 0.94))


def stool(m, g, x, z, y=0.0, height=0.66):
    m.cyl(g, "StoolSeat", "seat", (x, y + height - 0.07, z), 0.42, 0.07, sides=10, solid=False)
    m.cyl(g, "StoolLeg", "metal", (x, y, z), 0.07, height - 0.07, sides=6, solid=False)
    m.cyl(g, "StoolFoot", "metal", (x, y, z), 0.36, 0.03, sides=10, solid=False)


def side_table(m, g, x, z, y=0.0, kind="table"):
    m.cyl(g, "SideTable", kind, (x, y + 0.5, z), 0.66, 0.05, sides=12, solid=False)
    m.cyl(g, "SideTableLeg", "metal", (x, y, z), 0.07, 0.5, sides=6, solid=False)


def rug(m, g, lo, hi, y=0.0, kind="rug_red", border="rug_cream"):
    """A rug from (x, z) `lo` to `hi`: two thin layers on the floor."""
    (x0, z0), (x1, z1) = lo, hi
    m.strip(g, "RugBorder", border, (x0, y + 0.03, z0), (x1, y + 0.045, z1))
    m.strip(g, "Rug", kind, (x0 + 0.25, y + 0.045, z0 + 0.25), (x1 - 0.25, y + 0.058, z1 - 0.25))


def ceiling_light(m, g, x, y, z, drop=0.5, size=0.6):
    """A lamp hanging `drop` metres under a ceiling at height y."""
    m.strip(g, "LightRod", "metal", (x - 0.025, y - drop, z - 0.025), (x + 0.025, y, z + 0.025))
    m.cone(g, "LightShade", "brass", (x, y - drop - 0.02, z), size, 0.22, top=size * 0.3, sides=10, solid=False)
    m.dome(g, "Light", "lamp", (x, y - drop, z), (size * 0.7, size * 0.36, size * 0.7), sides=8, flip=True, solid=False)


def strip_light(m, g, lo, hi, y):
    """A long light flat under a ceiling at height y, from (x, z) `lo` to `hi`."""
    (x0, z0), (x1, z1) = lo, hi
    m.strip(g, "StripLightCase", "metal", (x0 - 0.04, y - 0.06, z0 - 0.04), (x1 + 0.04, y, z1 + 0.04))
    m.strip(g, "StripLight", "lamp", (x0, y - 0.1, z0), (x1, y - 0.06, z1))


def chandelier(m, g, x, y, z, drop=3.0, size=2.4, lamps=6):
    """A ring of lamps hanging `drop` metres under a ceiling at height y."""
    m.strip(g, "ChandelierRod", "metal", (x - 0.03, y - drop + 0.2, z - 0.03), (x + 0.03, y, z + 0.03))
    m.block(g, "ChandelierRing", "brass", (x, y - drop, z), (size, 0.1, size), shape="tube", sides=18, inner=size - 0.24, solid=False)
    m.cone(g, "ChandelierCrown", "brass", (x, y - drop, z), size * 0.5, 0.5, top=0.08, sides=10, solid=False)
    for i in range(lamps):
        a = math.radians(i * 360.0 / lamps)
        ball(m, g, "ChandelierLamp", "lamp", (x + math.sin(a) * (size / 2 - 0.06), y - drop + 0.17, z + math.cos(a) * (size / 2 - 0.06)), 0.28, sides=6)


def sconce(m, g, axis, face, out, u, y):
    """A wall lamp."""
    m.on_wall(g, "SconcePlate", "brass", axis, face, out, u - 0.1, u + 0.1, y - 0.22, y + 0.12, depth=0.07)
    at = (u, y + 0.12, face + out * 0.2) if axis == "x" else (face + out * 0.2, y + 0.12, u)
    m.cone(g, "SconceCup", "brass", at, 0.34, 0.2, top=0.16, sides=8, flip=True, solid=False)
    m.dome(g, "SconceLamp", "lamp", at, (0.34, 0.24, 0.34), sides=8, solid=False)


def picture(m, g, axis, face, out, u, y, w=1.4, h=1.0, colours=("accent_blue", "banner_gold"), seed=0):
    """A framed picture with no words in it: two or three flat shapes."""
    m.on_wall(g, "PictureFrame", "frame", axis, face, out, u - w / 2 - 0.07, u + w / 2 + 0.07, y - h / 2 - 0.07, y + h / 2 + 0.07, depth=0.05)
    m.on_wall(g, "PictureCanvas", "canvas", axis, face, out, u - w / 2, u + w / 2, y - h / 2, y + h / 2, depth=0.02, lift=0.05)
    a = 0.12 + 0.1 * (seed % 3)
    m.on_wall(g, "PictureShape", colours[0], axis, face, out, u - w / 2 + 0.1, u - w / 2 + 0.1 + w * (0.4 + a), y - h / 2 + 0.1, y + h * (a - 0.1), depth=0.012, lift=0.07)
    m.on_wall(g, "PictureShape", colours[1], axis, face, out, u + w * (0.1 - a / 2), u + w / 2 - 0.12, y - h * 0.1, y + h / 2 - 0.1, depth=0.012, lift=0.082)


def bin_(m, g, x, z, y=0.0):
    m.cone(g, "Bin", "metal", (x, y + 0.7, z), 0.5, 0.7, top=0.38, sides=10, flip=True, solid=False)
    m.cyl(g, "BinRim", "brass", (x, y + 0.7, z), 0.54, 0.05, sides=10, solid=False)


def monitor(m, g, x, y, z, face="+z"):
    """A screen on a stand, on a desk top at height y, looking along `face`."""
    at = (x, y, z)
    part(m, g, "Monitor", "equipment_dark", at, face, (-0.42, 0.16, -0.035), (0.42, 0.7, 0.035), bevel=0.03)
    part(m, g, "MonitorScreen", "screen", at, face, (-0.37, 0.21, 0.035), (0.37, 0.65, 0.045))
    part(m, g, "MonitorStand", "equipment_dark", at, face, (-0.05, 0.0, -0.04), (0.05, 0.16, 0.04))
    part(m, g, "MonitorFoot", "equipment_dark", at, face, (-0.2, 0.0, -0.13), (0.2, 0.025, 0.13))


def glassware(m, g, x, y, z, seed=0):
    """Three bits of lab glass on a bench top at height y."""
    m.cyl(g, "Beaker", "glass_ware", (x, y, z), 0.2, 0.26, sides=8, solid=False)
    m.cone(g, "Flask", "glass_ware", (x + 0.3, y, z + 0.06), 0.26, 0.3, top=0.08, sides=8, solid=False)
    m.cyl(g, "FlaskNeck", "glass_ware", (x + 0.3, y + 0.3, z + 0.06), 0.08, 0.12, sides=6, solid=False)
    m.cyl(g, "BeakerFill", FLOWERS[seed % 4] if seed % 2 else "accent_teal", (x, y, z), 0.16, 0.12 + 0.03 * (seed % 3), sides=8, solid=False)
    m.cyl(g, "TestTube", "glass_ware", (x - 0.24, y, z - 0.04), 0.07, 0.3, sides=6, solid=False)


def books(m, g, x, face_x, z0, z1, y, seed, depth=0.07, count=None, along="z"):
    """A row of books on a shelf whose face is at x (`face_x` +1 or -1 is the way it faces),
    from z0 to z1: groups of different heights and colours, with a gap here and there.
    along="x": the shelf runs along x instead (read x as z and z as x)."""
    rng = __import__("random").Random(seed)
    kinds = ["books_red", "books_blue", "books_green", "books_gold"]
    n = count or max(4, int((z1 - z0) / 0.6))
    w = (z1 - z0) / n
    for i in range(n):
        if rng.random() < 0.12:
            continue    # a gap: books out on loan
        a = z0 + i * w + 0.03
        b = z0 + (i + 1) * w - (0.03 if rng.random() < 0.7 else 0.16)
        h = rng.uniform(0.42, 0.72)
        xa, xb = sorted((x, x + face_x * depth))
        tint = (1.0, 1.0, 1.0) if rng.random() < 0.6 else (0.86, 0.86, 0.86)
        if along == "z":
            m.strip(g, "Books", kinds[rng.randrange(4)], (xa, y, a), (xb, y + h, b), tint=tint)
        else:
            m.strip(g, "Books", kinds[rng.randrange(4)], (a, y, xa), (b, y + h, xb), tint=tint)


def umbrella_table(m, g, x, z, y, kind):
    """A terrace table under a parasol, with two chairs: drawn only."""
    m.cyl(g, "CafeTable", "table", (x, y + 0.7, z), 1.2, 0.07, sides=14, solid=False)
    m.cyl(g, "ParasolPole", "metal", (x, y, z), 0.08, 2.5, sides=6, solid=False)
    m.cone(g, "Parasol", kind, (x, y + 2.2, z), 3.2, 0.7, top=0.1, sides=10, solid=False)
    m.cone(g, "ParasolTrim", "awning", (x, y + 2.14, z), 3.3, 0.08, top=3.2, sides=10, solid=False)
    chair(m, g, x - 0.95, z, y, "+x")
    chair(m, g, x + 0.95, z, y, "-x")


# ---------------------------------------------------------------------------
# The quad and the clock tower (they never move)

def quad(m):
    g = m.group("Quad", grouped=False)
    isl = m.group("Island", g)
    m.cyl(isl, "Lawn", "lawn", (0, -1.0, 0), QUAD_R * 2, 1.0, sides=36)
    m.cyl(isl, "Kerb", "stone_warm", (0, -1.2, 0), QUAD_R * 2 + 0.6, 1.02, sides=36, solid=False)
    # The rock under it: one long taper, and a darker root below.
    m.cone(isl, "Rock", "rock", (0, -1.0, 0), QUAD_R * 2 - 1.0, 7.0, top=13.0, sides=14, flip=True)
    m.cone(isl, "Rock", "rock_dark", (0, -8.0, 0), 13.0, 5.0, top=5.0, sides=10, flip=True)
    engines(m, isl, [(0, 0)], -13.0, 4.2)
    engines(m, isl, [polar(9.4, a)[::2] for a in (60, 180, 300)], -5.0, 1.8)
    # Paths from the tower out toward each island, and a round apron under the tower.
    p = m.group("Paths", g)
    for _name, deg, _a, _r in ISLANDS:
        m.block(p, "Path", "path", polar(10.9, deg, 0.011), (3.2, 0.022, 7.0), cols=rot(deg), solid=False)
    m.cyl(p, "TowerApron", "path", (0, 0, 0), 17.0, 0.03, sides=28, solid=False)
    m.node("Centre", g, None, [("transform", xform(IDENTITY, (0, 0, 0)))], type_="Marker3D")
    # Five planters round the rim, each with a banner mast: the mast's top is a grapple
    # point, the way over from an island. They stand 18 degrees to one side of each
    # island's line (the stepping stones are 18 degrees to the other side), so the line
    # itself is clear to set off along. "Land" is where a bot that hooks the mast comes down.
    rim = m.group("Rim", g, grouped=False)
    banners = ["banner_gold", "banner_red", "banner_blue"]
    for i, (_n, isl_deg, _a, _r) in enumerate(ISLANDS):
        deg = isl_deg - 18.0
        pl = m.group("Planter", rim, at=polar(MAST_R, deg), yaw=math.radians(deg))
        m.bev(pl, "Planter", "planter", (-1.8, 0, -0.7), (1.8, 0.6, 0.7), 0.1)
        m.bev(pl, "Hedge", "hedge", (-1.65, 0.6, -0.55), (1.65, 1.15, 0.55), 0.22)
        m.cyl(pl, "Mast", "mast", (0, 1.15, 0), 0.26, 7.8, sides=8)
        m.strip(pl, "Banner", banners[i % 3], (0.15, 5.9, -0.04), (1.3, 8.7, 0.04))
        m.dome(pl, "Finial", "brass", (0, 8.95, 0), (0.5, 0.3, 0.5), sides=8, solid=False)
        hook = m.node("Hook%d" % (i + 1), pl, "hook", [("transform", xform(IDENTITY, (0, 9.2, 0))), ("reach", "60.0"),
                                                       ("groups", '["quad_masts"]')], type_="Marker3D")
        m.node("Land", hook, None, [("transform", xform(IDENTITY, (0, -9.2, -4.4)))], type_="Marker3D")
    # Trees and benches: cover on the lawn, and something to break up the long views.
    for i, (_n, deg, _a, _r) in enumerate(ISLANDS):
        x, _y, z = polar(9.6, deg + 36.0)
        tree(m, g, x, z, kind="leaves_gold" if i % 2 else "leaves", size=1.15)
        bx, _y, bz = polar(8.8, deg + 8.0)
        b = m.group("Bench", g, at=(bx, 0, bz), yaw=math.radians(deg + 8.0))
        bench(m, b, 0, 0)
        # A spawn point for when no island has room (they are all on the move): facing out.
        m.spawn(polar(10.5, deg + 18.0), polar(30.0, deg + 18.0)[::2])
    # Flower beds and shrubs on the lawn (drawn only: nothing to trip on), ivy and shrubs
    # round the tower's foot, lamps round the rim.
    gd = m.group("Garden", g, grouped=False)
    for i, (_n, deg, _a, _r) in enumerate(ISLANDS):
        x, _y, z = polar(11.6, deg + 27.0)
        flower_bed(m, gd, x, z, 0, 2.2, seed=i)
        x, _y, z = polar(11.2, deg - 9.0)
        flower_bed(m, gd, x, z, 0, 1.8, seed=i + 2)
        x, _y, z = polar(12.6, deg + 9.0)
        shrub(m, gd, x, z, 0, 1.2)
        # (well away from the masts, deg - 18: a post beside one knocks people landing
        # off the grapple off their line)
        x, _y, z = polar(12.9, deg + 15.0)
        lamp_post(m, gd, x, z, 0, 3.4)
    O = TOWER_OUT
    for sx in (-1, 1):
        for sz in (-1, 1):
            shrub(m, gd, sx * (O + 1.3), sz * (O - 1.6), 0, 1.5)
            shrub(m, gd, sx * (O - 1.8), sz * (O + 1.2), 0, 1.3)
    ivy(m, gd, "x", O, 1, -4.3, -1.0, 0, 8.5, seed=20)       # south face (no door), either side of its slits
    ivy(m, gd, "x", O, 1, 1.0, 4.3, 0, 6.0, seed=24)
    ivy(m, gd, "z", O, 1, -4.2, 4.2, 0, 6.5, seed=21)        # east face (no door)
    ivy(m, gd, "x", -O, -1, 2.0, 4.3, 0, 7.5, seed=22)       # north face, beside the door
    ivy(m, gd, "z", -O, -1, -4.3, -2.0, 0, 6.0, seed=23)     # west face, beside the door
    tower(m, g)
    return g


TOWER_IN = 4.6      # half the inside of the tower
TOWER_OUT = 5.2
FLIGHTS = 9         # flights of the stair, each along one wall
STEP = 2.9          # each flight climbs this much (29 degrees)
BELFRY = FLIGHTS * STEP   # the belfry floor
STAIR_W = 2.0
CLOCK_Y = 23.2      # the middle of the clock faces
LEDGE_Y = 20.4      # the upper ledge


def tower(m, quad_group):
    g = m.group("ClockTower", quad_group, grouped=False)
    shell = m.group("Shell", g)
    I, O = TOWER_IN, TOWER_OUT
    mid = (I + O) / 2
    # Doors north and west (the stair starts along the south wall and climbs past the
    # east one); tall arched slits all the way up, a different pair of walls each time,
    # to hook and to shoot from.
    slit_ns = lambda y: (O - 0.7, O + 0.7, y, y + 2.6, 0.7)
    slit_we = lambda y: (I - 0.7, I + 0.7, y, y + 2.6, 0.7)
    wall(m, shell, "WallNorth", "stone", (-O, -mid), (O, -mid), 0, BELFRY - 0.4, O - I, [(O - 1.6, O + 1.6, 0.0, 4.2, 1.4), slit_ns(7.0), slit_ns(16.9)])
    wall(m, shell, "WallSouth", "stone", (-O, mid), (O, mid), 0, BELFRY - 0.4, O - I, [slit_ns(4.4), slit_ns(12.2)])
    wall(m, shell, "WallWest", "stone", (-mid, -I), (-mid, I), 0, BELFRY - 0.4, O - I, [(I - 1.6, I + 1.6, 0.0, 4.2, 1.4), slit_we(9.6), slit_we(16.6)])
    wall(m, shell, "WallEast", "stone", (mid, -I), (mid, I), 0, BELFRY - 0.4, O - I, [slit_we(6.8), slit_we(14.7)])
    m.box(shell, "Floor", "floor_tile", (-I, -0.02, -I), (I, 0.03, I), solid=False)
    # Outside: a pilaster up each corner, two cornices, and the upper ledge right under
    # the belfry's overhang (a power weapon's spot): ledges to hook and to stand on.
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.bev(shell, "Pilaster", "stone_warm", (sx * O - 0.8, 0, sz * O - 0.8), (sx * O + 0.8, 7.4, sz * O + 0.8), 0.18)
            m.bev(shell, "Pilaster", "stone_warm", (sx * O - 0.5, 7.4, sz * O - 0.5), (sx * O + 0.5, LEDGE_Y - 0.4, sz * O + 0.5), 0.12)
    for y, out, kind in ((9.0, 0.6, "trim"), (15.5, 0.6, "trim"), (LEDGE_Y, 1.0, "stone_warm")):
        for lo, hi in (((-O - out, y - 0.4, -O - out), (O + out, y, -O)), ((-O - out, y - 0.4, O), (O + out, y, O + out)),
                       ((-O - out, y - 0.4, -O), (-O, y, O)), ((O, y - 0.4, -O), (O + out, y, O))):
            m.bev(shell, "UpperLedge" if out > 0.7 else "Cornice", kind, lo, hi, 0.1)
    # A clock face on every side, between the upper ledge and the belfry. No numbers:
    # twelve marks, a short hand that stays put and a long one that counts the layout
    # down (a MapSpinner the LayoutEvent turns: once round, at twelve when the bell goes).
    for deg in (0, 90, 180, 270):
        c = m.group("Clock", g, at=polar(O, deg, CLOCK_Y), yaw=math.radians(deg))
        m.block(c, "Face", "clock_face", (0, 0, 0.09), (4.4, 0.18, 4.4), cols=LIE_Z, shape="cyl", sides=28, solid=False)
        m.block(c, "Rim", "brass", (0, 0, 0.05), (4.9, 0.1, 4.9), cols=LIE_Z, shape="cyl", sides=28, solid=False)
        for k in range(12):
            phi = math.radians(k * 30.0)
            cols = ((math.cos(phi), -math.sin(phi), 0), (math.sin(phi), math.cos(phi), 0), (0, 0, 1))
            long_mark = k % 3 == 0
            r = 1.72 if long_mark else 1.82
            m.block(c, "Mark", "clock_hand", (r * math.sin(phi), r * math.cos(phi), 0.2), (0.16 if long_mark else 0.1, 0.56 if long_mark else 0.36, 0.04), cols=cols, solid=False)
        phi = math.radians(300.0)
        cols = ((math.cos(phi), -math.sin(phi), 0), (math.sin(phi), math.cos(phi), 0), (0, 0, 1))
        m.block(c, "HourHand", "clock_hand", (0.5 * math.sin(phi), 0.5 * math.cos(phi), 0.22), (0.22, 1.25, 0.05), cols=cols, solid=False)
        hand = m.node("CountdownHand", c, "spinner", [("transform", xform(((1, 0, 0), (0, 0, 1), (0, -1, 0)), (0, 0, 0.26))),
                                                      ("speed", "0.0"), ("driven", "1")])
        m.block(hand, "Hand", "clock_hand", (0, 0.02, -0.72), (0.14, 0.05, 2.0), solid=False)
        m.block(hand, "Hub", "brass", (0, 0.06, 0), (0.42, 0.08, 0.42), shape="cyl", sides=12, solid=False)
    # The stair: nine flights round the inside walls, a landing in each corner, the
    # middle left open (a shaft to grapple up).
    st = m.group("Stair", g, grouped=False)
    a = I - STAIR_W / 2      # the middle of a flight, across it
    e = I - STAIR_W          # where a flight meets a landing
    for k in range(FLIGHTS):
        y = k * STEP
        side = k % 4
        if side == 0:
            p0, p1, land, open_side = (-e, y, a), (e, y + STEP, a), (e, I, e, I), (True, False)
        elif side == 1:
            p0, p1, land, open_side = (a, y, e), (a, y + STEP, -e), (e, I, -I, -e), (True, False)
        elif side == 2:
            p0, p1, land, open_side = (e, y, -a), (-e, y + STEP, -a), (-I, -e, -I, -e), (False, True)
        else:
            p0, p1, land, open_side = (-a, y, -e), (-a, y + STEP, e), (-I, -e, e, I), (False, True)
        stairs(m, st, "Flight%d" % (k + 1), p0, p1, STAIR_W, base=y - 0.05, sides=open_side)
        if k < FLIGHTS - 1:
            m.box(st, "Landing", "stair", (land[0], y + STEP - 0.3, land[2]), (land[1], y + STEP, land[3]))
    # The belfry: wider than the tower (it overhangs the upper ledge), an arch on each of
    # its four sides, the bell hanging in the middle.
    bf = m.group("Belfry", g, grouped=False)
    W = O + 1.0
    # (the last flight comes up along the south wall to the south-east corner: the floor
    # is left open over it and over the landing it starts from)
    floor(m, bf, "BelfryFloor", "stone_warm", -W, W, -W, W, BELFRY, 0.4, [(-I, e, e, I)])
    top = BELFRY + 5.4
    P = W - 0.7             # the middle of a corner pier
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.bev(bf, "Pier", "stone", (sx * P - 0.7, BELFRY, sz * P - 0.7), (sx * P + 0.7, top, sz * P + 0.7), 0.14)
    span = 2 * (P - 0.7)
    for s in (-1, 1):
        m.block(bf, "Arch", "stone", (0, top - 1.0, s * P), (span, 2.0, 1.0), shape="arch", sides=10, top=0.6)
        m.block(bf, "Arch", "stone", (s * P, top - 1.0, 0), (span, 2.0, 1.0), cols=TURN, shape="arch", sides=10, top=0.6)
        low_wall(m, bf, (-span / 2, s * P), (span / 2, s * P), BELFRY, 1.0)
        low_wall(m, bf, (s * P, -span / 2), (s * P, span / 2), BELFRY, 1.0)
    # (a rail round the stair hole, so nobody backs into it)
    m.rail(bf, "StairRail", "rail", (-I, e), (e, e), BELFRY, 1.0)
    m.rail(bf, "StairRail", "rail", (-I, e), (-I, I), BELFRY, 1.0)
    m.rail(bf, "StairRail", "rail", (-I, I), (e, I), BELFRY, 1.0)
    # The roof: an eave, and a tall four-sided spire, each side one clean slope (too
    # steep to stand on).
    m.bev(bf, "Eave", "trim", (-W - 0.6, top, -W - 0.6), (W + 0.6, top + 0.45, W + 0.6), 0.16)
    side = 2 * (W + 0.3)
    m.cone(bf, "Spire", "roof_slate", (0, top + 0.45, 0), side * math.sqrt(2.0), 11.5, sides=4, yaw=45.0)
    apex = top + 0.45 + 11.5
    m.cone(bf, "Finial", "brass", (0, apex - 0.7, 0), 0.5, 2.6, sides=8, solid=False)
    m.dome(bf, "FinialBall", "brass", (0, apex + 0.9, 0), (0.7, 0.35, 0.7), sides=8, solid=False)
    m.dome(bf, "FinialBall", "brass", (0, apex + 0.9, 0), (0.7, 0.35, 0.7), sides=8, flip=True, solid=False)
    # The bell: it hangs from a beam between two of the arches and swings when it tolls
    # (a MapSpinner the LayoutEvent rocks). Nobody rings it: the clock does.
    m.box(bf, "Yoke", "metal", (-P + 0.3, top - 0.5, -0.2), (P - 0.3, top - 0.1, 0.2))
    bell = m.node("Bell", bf, "spinner", [("transform", xform(((0, 1, 0), (1, 0, 0), (0, 0, -1)), (0, top - 0.5, 0))),
                                          ("speed", "0.0"), ("driven", "2")])
    up = ((0, -1, 0), (1, 0, 0), (0, 0, 1))      # a block's own y along the spinner's x (world up)
    m.block(bell, "Crown", "bell", (-0.35, 0, 0), (0.7, 0.7, 0.7), cols=up, shape="cyl", sides=10)
    m.block(bell, "Body", "bell", (-1.7, 0, 0), (2.9, 2.0, 2.9), cols=up, shape="cone", sides=16, top=1.5)
    m.block(bell, "Lip", "bell", (-2.8, 0, 0), (3.2, 0.22, 3.2), cols=up, shape="cyl", sides=16, tint=(1.1, 1.1, 1.1))
    m.block(bell, "Clapper", "metal", (-2.7, 0, 0), (0.3, 1.0, 0.3), cols=up, shape="cyl", sides=8)
    # The power weapon on the upper ledge, north side.
    m.weapon_in(g, (0, LEDGE_Y, -O - 0.5), "anti_materiel")


# ---------------------------------------------------------------------------
# One island: the deck, the rock under it, its two bridge halves

def island(m, name, deg, accent, roof_kind, building):
    at = polar(R0, deg)
    g = m.node(name, ".", "island", [("transform", xform(rot(deg), at))])
    d = m.group("Deck", g)
    # The deck: a fan (a strip down the middle and a triangle either side, so its side
    # edges are straight lines) and the main deck behind it.
    m.box(d, "Fan", "paving", (-WT, -0.8, ZT), (WT, 0, ZS))
    for sx in (-1, 1):
        m.tri(d, "FanSide", "paving", (sx * WT, ZS), sx * (WS - WT), ZT - ZS, -0.8, 0)
    m.box(d, "MainDeck", "paving", (-WS, -0.8, ZS), (WS, 0, MAIN_Z1))
    for lo, hi in (((-WT - 0.15, -1.0, ZT - 0.15), (WT + 0.15, -0.3, ZT)), ((-WS - 0.15, -1.0, MAIN_Z1), (WS + 0.15, -0.3, MAIN_Z1 + 0.15)),
                   ((-WS - 0.15, -1.0, ZS), (-WS, -0.3, MAIN_Z1)), ((WS, -1.0, ZS), (WS + 0.15, -0.3, MAIN_Z1))):
        m.strip(d, "Kerb", "stone_warm", lo, hi)
    # The rock under it: three round bellies, the lowest the darkest, and the engines.
    m.dome(d, "Rock", "rock", (0, -0.8, (ZS + MAIN_Z1) / 2), (2 * WS - 1.0, 8.0, MAIN_Z1 - ZS - 0.6), sides=12, flip=True)
    m.dome(d, "Rock", "rock", (0, -0.8, -6.3), (2 * WT - 3.0, 5.5, 9.0), sides=10, flip=True)
    m.dome(d, "Rock", "rock_dark", (0, -4.0, 5.0), (17.0, 9.5, 10.5), sides=10, flip=True)
    engines(m, d, [(0, 5.0)], -13.3, 3.4)
    engines(m, d, [(-12.0, 6.0), (12.0, 6.0), (0, -6.3)], -5.9, 1.9)
    # Rails along the edges, open at the tip (where people land) and here and there.
    r = m.group("Rails", g)
    for sx in (-1, 1):
        yaw = math.atan2(sx * SIN36, COS36)
        edge = m.group("EdgeRail", r, at=(sx * WT, 0, ZT), yaw=yaw)
        m.strip(edge, "Kerb", "stone_warm", (0.0 if sx > 0 else -0.15, -1.0, 0.0), (0.15 if sx > 0 else 0.0, -0.3, EDGE_LEN))
        for t0, t1 in ((0.8, 4.4), (6.4, EDGE_LEN - 0.6)):
            m.rail_box(edge, (-sx * 0.2 - 0.06, 0, t0), (-sx * 0.2 + 0.06, 1.0, t1))
        m.rail(r, "Rail", "rail", (sx * (WS - 0.1), ZS + 0.4), (sx * (WS - 0.1), MAIN_Z1), 0, 1.0, holes=[(5.0, 8.0)])
    m.rail(r, "Rail", "rail", (-WS, MAIN_Z1 - 0.1), (WS, MAIN_Z1 - 0.1), 0, 1.0, holes=[(6.5, 9.5), (2 * WS - 9.5, 2 * WS - 6.5)])
    # Lamps down both edges, and the building's colour laid into the paving where the
    # tip is and flying on a banner either side of it.
    for z in (ZT + 0.6, (ZT + ZS) / 2, ZS - 0.4):
        for sx in (-1, 1):
            lamp_post(m, d, sx * (edge_x(z) - 0.7), z)
    m.strip(d, "Inlay", accent, (-2.0, 0, ZT + 0.6), (2.0, 0.022, ZT + 6.0))
    # A banner mast either side of the landing. The tall one's top is a grapple point:
    # the way over from the quad.
    for sx, height in ((-1, 6.0), (1, 9.0)):
        m.cyl(d, "BannerMast", "mast", (sx * 5.0, 0, ZT + 3.2), 0.24, height, sides=8)
        m.strip(d, "Banner", accent, (sx * 5.0 + 0.14, height - 3.0, ZT + 3.16), (sx * 5.0 + 1.4, height - 0.2, ZT + 3.24))
        m.dome(d, "Finial", "brass", (sx * 5.0, height, ZT + 3.2), (0.44, 0.26, 0.44), sides=8, solid=False)
    m.node("ArrivalHook", g, "hook", [("transform", xform(IDENTITY, (5.0, 9.3, ZT + 3.2))), ("reach", "60.0")], type_="Marker3D")
    # Green on the plaza, clear of the middle where people land: a planter at each corner
    # of the tip, a tree in a tub and a bench either side, a bin by a lamp.
    gd = m.group("Garden", g, grouped=False)
    for i, sx in enumerate((-1, 1)):
        x0, x1 = sorted((sx * 8.2, sx * 11.6))
        planter_box(m, gd, (x0, ZT + 0.5), (x1, ZT + 1.4), seed=i + int(deg) % 4)
        m.cyl(gd, "TreeTub", "planter", (sx * 11.2, 0, ZT + 4.6), 2.2, 0.5, sides=12)
        m.cyl(gd, "TreeTubSoil", "soil", (sx * 11.2, 0.5, ZT + 4.6), 1.9, 0.04, sides=12, solid=False)
        tree(m, gd, sx * 11.2, ZT + 4.6, 0.5, kind="leaves_gold" if (i + int(deg) // 36) % 2 else "leaves", size=0.85)
        for a in range(5):
            th = math.radians(a * 72.0 + 20.0)
            m.dome(gd, "Flower", FLOWERS[(a + i) % 4], (sx * 11.2 + math.sin(th) * 0.75, 0.54, ZT + 4.6 + math.cos(th) * 0.75), (0.3, 0.2, 0.3), sides=6, solid=False)
        bench(m, gd, sx * 11.2, ZT + 7.0)
        shrub(m, gd, sx * (edge_x(ZT + 7.6) - 1.4), ZT + 7.6, 0, 1.1)
    bin_(m, gd, -(edge_x(ZT + 0.6) - 1.5), ZT + 0.7)
    building(m, g, accent, roof_kind)
    return g


def stones(m):
    """Five stepping stones just off the quad's rim, 18 degrees round from each island's
    line: a hop from the quad, somewhere to break a long crossing, and a pickup on three
    of them. A statue, two kiosks and two planters."""
    f = m.group("SteppingStones", grouped=False)
    kinds = ["statue", "kiosk", "planter", "kiosk", "planter"]
    for i, (name, deg, _a, _r) in enumerate(ISLANDS):
        g = m.group("Stone" + name, f, at=polar(STONE_R, deg + 18.0), yaw=math.radians(deg + 18.0))
        m.cyl(g, "Top", "paving", (0, 0.1, 0), 4.6, 0.5, sides=14)
        m.cone(g, "Rock", "rock", (0, 0.1, 0), 4.2, 2.6, top=1.6, sides=10, flip=True)
        engines(m, g, [(0, 0)], -2.5, 1.3)
        what = kinds[i]
        if what == "statue":
            m.bev(g, "Plinth", "stone_warm", (-0.7, 0.6, 0.5), (0.7, 1.4, 1.9), 0.1)
            m.cone(g, "Obelisk", "statue", (0, 1.4, 1.2), 1.0, 2.6, top=0.3, sides=4, yaw=45.0)
            m.dome(g, "Orb", "brass", (0, 4.0, 1.2), (0.6, 0.3, 0.6), sides=8, solid=False)
            m.dome(g, "Orb", "brass", (0, 4.0, 1.2), (0.6, 0.3, 0.6), sides=8, flip=True, solid=False)
        elif what == "kiosk":
            m.cyl(g, "Kiosk", "kiosk", (0, 0.6, 1.2), 1.9, 2.0, sides=10)
            m.cone(g, "KioskRoof", "awning", (0, 2.6, 1.2), 2.9, 0.9, top=0.3, sides=10)
            m.strip(g, "Hatch", "window_lit", (-0.5, 1.5, 0.2), (0.5, 2.2, 0.3))
        else:
            m.cyl(g, "Planter", "planter", (0, 0.6, 1.15), 2.3, 0.5, sides=12)
            m.cyl(g, "Soil", "soil", (0, 1.1, 1.15), 2.0, 0.06, sides=12, solid=False)
            tree(m, g, 0, 1.15, 1.1, kind="leaves_gold" if i % 2 else "leaves", size=0.62)
        lamp_post(m, g, -1.5, -0.9, 0.6, 3.4)
        shrub(m, g, 1.4, -0.9, 0.6, 0.9)
        for a in range(3):
            m.dome(g, "Flower", FLOWERS[(a + i) % 4], (0.9 + 0.5 * a, 0.6, -1.5 + 0.3 * (a % 2)), (0.3, 0.2, 0.3), sides=6, solid=False)
    return f


# ---------------------------------------------------------------------------
# The buildings. Each stands on its island's main deck: x from -14 to 14, z from -1.4
# (the front, facing the quad) to 13.6, unless it says otherwise. That leaves a walkway
# down each side wide enough for the bots' navigation mesh. Floors are 5.5 m apart and
# the big rooms are two floors high: room to grapple, flip and use the rocket boots.
#
# For the bots' navigation mesh a stair is 2.2 m wide and climbs at 31 degrees or less
# (5.5 m up takes 9.2 m along), with 2 m of clear floor before its foot and beyond its
# head, and nothing narrower than about 2 m on the way to either. Where a stair comes
# up through a floor, the hole starts while the stair still has 2.4 m of headroom.

BX0, BX1, BZ0, BZ1 = -14.0, 14.0, -1.4, 13.6
IX0, IX1, IZ0, IZ1 = BX0 + 0.2, BX1 - 0.2, BZ0 + 0.2, BZ1 - 0.2   # inside the walls
SW = 2.2           # a stair's width


def fx(x0, x1, y0, y1, arch=0.0, west=BX0):
    """An opening in a front or back wall, given by its x."""
    return (x0 - west, x1 - west, y0, y1, arch)


def sz(z0, z1, y0, y1, arch=0.0):
    """An opening in a side wall, given by its z."""
    return (z0 - BZ0, z1 - BZ0, y0, y1, arch)


def door_banners(m, g, accent, x, z=BZ0, y0=4.6, y1=8.2, half=2.4):
    """The building's colour on a banner either side of its front door."""
    for s in (-1, 1):
        m.strip(g, "DoorBanner", accent, (x + s * half - 0.45, y0, z - 0.3), (x + s * half + 0.45, y1, z - 0.24))
        m.strip(g, "BannerRod", "brass", (x + s * half - 0.55, y1, z - 0.34), (x + s * half + 0.55, y1 + 0.08, z - 0.2))


def library(m, g, accent, roof_kind):
    """Three floors of stacks round a tall hall: shelf lanes on the ground, mezzanines at
    5.5 and 11 m, a reading room under the skylight, and a perch under the roof that only
    the grapple reaches. Its shape: a columned porch with a low gable over the door, and
    tall round-headed windows."""
    b = m.group("Building", g, grouped=False)
    sh = m.group("Shell", b)
    top = 18.0
    walls(m, sh, "stone", BX0, BX1, BZ0, BZ1, 0, top,
          front=[fx(-1.6, 1.6, 0, 4.2, 1.3), fx(-10.5, -7.5, 1.2, 4.4, 1.0), fx(7.5, 10.5, 1.2, 4.4, 1.0),
                 fx(-10.5, -7.5, 6.7, 9.9, 1.0), fx(7.5, 10.5, 6.7, 9.9, 1.0), fx(-1.5, 1.5, 12.2, 15.4, 1.0)],
          back=[fx(-11.5, -8.5, 6.7, 9.9, 1.0), fx(8.0, 11.0, 12.2, 15.4, 1.0), fx(-4.5, -1.5, 12.2, 15.4, 1.0)],
          west=[sz(5.0, 8.2, 0, 4.0, 1.2), sz(2.0, 5.0, 12.2, 15.4, 1.0)],
          east=[sz(5.0, 8.2, 0, 4.0, 1.2), sz(8.0, 11.0, 6.7, 9.9, 1.0)])
    band(m, sh, accent, BX0, BX1, BZ0, BZ1, 4.95, 5.4)
    band(m, sh, "trim", BX0, BX1, BZ0, BZ1, 10.6, 10.9)
    band(m, sh, "stone_warm", BX0, BX1, BZ0, BZ1, 0.0, 0.7, out=0.1, name="Plinth")
    floor(m, sh, "Floor", "floor_wood", IX0, IX1, IZ0, IZ1, 0.03, 0.03, solid=False)
    # The roof: a skylight over the reading room, a hatch over the top mezzanine.
    roof(m, sh, roof_kind, BX0, BX1, BZ0, BZ1, top + 0.35, holes=[(-5.0, 5.0, 2.0, 8.0), (8.0, 9.8, 3.0, 4.8)])
    m.box(sh, "Skylight", "glass_sky", (-5.0, top + 0.1, 2.0), (5.0, top + 0.25, 8.0), unbreakable=True)
    for x in (-1.7, 1.7):
        m.strip(sh, "SkylightBar", "metal", (x - 0.06, top + 0.25, 2.0), (x + 0.06, top + 0.33, 8.0))
    # The porch: six columns, a beam across them and a low gable on top.
    po = m.group("Porch", b)
    pz = BZ0 - 3.0
    for x in (-8.5, -5.1, -1.9, 1.9, 5.1, 8.5):
        m.bev(po, "ColumnBase", "stone_warm", (x - 0.6, 0, pz - 0.6), (x + 0.6, 0.4, pz + 0.6), 0.08)
        m.cyl(po, "Column", "column", (x, 0.4, pz), 0.84, 7.8, sides=14)
        m.bev(po, "ColumnCap", "stone_warm", (x - 0.62, 8.2, pz - 0.62), (x + 0.62, 8.6, pz + 0.62), 0.1)
    m.box(po, "PorchBeam", "column", (-9.4, 8.6, pz - 0.7), (9.4, 9.5, BZ0 - 0.2))
    m.bev(po, "PorchCornice", "trim", (-9.7, 9.5, pz - 1.0), (9.7, 9.8, BZ0 - 0.2), 0.1)
    for s, tall in ((-1, "+x"), (1, "-x")):
        m.wedge(po, "Gable", "column", (min(0, s * 9.7), 9.8, pz - 0.9), (max(0, s * 9.7), 12.2, BZ0 - 0.2), tall=tall)
    m.block(po, "GableDisc", accent, (0, 10.7, pz - 0.92), (1.3, 0.06, 1.3), cols=LIE_Z, shape="cyl", sides=16, solid=False)
    lit_windows(m, sh, "x", BZ1 + 0.2, 1, [-9.0, -4.5, 0.0, 4.5, 9.0], 1.4, 3.8, arched=True)
    lit_windows(m, sh, "x", BZ1 + 0.2, 1, [3.0], 12.6, 14.6, arched=True)
    # Mezzanines: at 5.5 m along the west side and part of the back, at 11 m along the
    # east side and the back. Stairs: ground to 5.5 m against the back wall, 5.5 m to
    # 11 m against the front.
    mz = m.group("Mezzanines", b, grouped=False)
    floor(m, mz, "Mezzanine1", "floor_wood", IX0, -6.0, IZ0, IZ1, F2)
    floor(m, mz, "Mezzanine1", "floor_wood", -6.0, -1.2, 9.4, IZ1, F2)
    m.rail(mz, "Rail", "rail", (-6.0, 1.0), (-6.0, 9.4), F2, 1.0)
    m.rail(mz, "Rail", "rail", (-6.0, 9.4), (-1.2, 9.4), F2, 1.0)
    m.rail(mz, "Rail", "rail", (-1.2, 9.4), (-1.2, 11.2), F2, 1.0)
    stairs(m, mz, "StairUp", (8.0, 0, 12.3), (-1.2, F2, 12.3), SW, sides=(True, False))
    floor(m, mz, "Mezzanine2", "floor_wood", 6.0, IX1, IZ0, IZ1, F3)
    floor(m, mz, "Mezzanine2", "floor_wood", IX0, 6.0, 9.4, IZ1, F3)
    m.rail(mz, "Rail", "rail", (6.0, 1.0), (6.0, 9.4), F3, 1.0)
    m.rail(mz, "Rail", "rail", (IX0, 9.4), (6.0, 9.4), F3, 1.0)
    # (up from the west mezzanine along the front wall, to a landing that joins the east one)
    stairs(m, mz, "StairUp2", (-6.0, F2, -0.1), (3.2, F3, -0.1), SW, fill=False, sides=(False, True))
    floor(m, mz, "Landing2", "floor_wood", 3.2, 6.0, IZ0, 1.0, F3)
    m.rail(mz, "Rail", "rail", (3.2, 1.0), (6.0, 1.0), F3, 1.0)
    # The perch: hung from the roof over the hall, 4 m above the top mezzanine and with
    # no stair. The library's power weapon.
    pe = m.group("Perch", b)
    m.bev(pe, "Perch", "floor_wood", (-3.0, 14.7, 3.0), (1.0, 15.0, 6.6), 0.06)
    for x, z in ((-2.8, 3.2), (0.8, 3.2), (-2.8, 6.4), (0.8, 6.4)):
        m.strip(pe, "Hanger", "metal", (x - 0.05, 15.0, z - 0.05), (x + 0.05, top + 0.1, z + 0.05))
    m.weapon_in(pe, (-1.0, 15.0, 4.8), "rocket_launcher")
    # Shelf stacks on the ground: lanes running front to back, books on both faces.
    st = m.group("Stacks", b, grouped=False)
    for i, x in enumerate((-10.8, -8.0, 5.0, 7.8, 10.6)):
        z0, z1 = (1.6, 8.6) if x < 0 else (1.6, 8.8)
        s = m.group("Stack", st)
        m.box(s, "ShelfBody", "shelf", (x - 0.35, 0, z0), (x + 0.35, 3.2, z1), drawn=False)
        m.bev(s, "Shelf", "shelf", (x - 0.35, 0, z0), (x + 0.35, 3.2, z1), 0.06, solid=False)
        m.bev(s, "ShelfTop", "shelf", (x - 0.45, 3.2, z0 - 0.1), (x + 0.45, 3.32, z1 + 0.1), 0.04, solid=False, tint=(0.85, 0.85, 0.85))
        for j in range(3):
            m.strip(s, "ShelfBoard", "shelf", (x - 0.44, 0.28 + j * 0.95, z0 + 0.05), (x + 0.44, 0.34 + j * 0.95, z1 - 0.05), tint=(0.85, 0.85, 0.85))
            for face in (-1, 1):
                books(m, s, x + face * 0.35, face, z0 + 0.2, z1 - 0.2, 0.34 + j * 0.95, seed=i * 10 + j * 2 + (face > 0))
    # Shelves along the mezzanine walls.
    m.box(st, "WallShelf", "shelf", (-13.0, F2, IZ1 - 0.6), (-7.5, F2 + 2.6, IZ1 - 0.05))
    for j in range(3):
        books(m, st, IZ1 - 0.6, -1, -12.9, -7.6, F2 + 0.25 + j * 0.8, seed=60 + j, along="x")
    m.box(st, "WallShelf", "shelf", (IX1 - 0.6, F3, 3.0), (IX1 - 0.05, F3 + 2.6, 7.4))
    for j in range(3):
        books(m, st, IX1 - 0.6, -1, 3.1, 7.3, F3 + 0.25 + j * 0.8, seed=70 + j)
    # The reading room: tables under the skylight, a lamp on each.
    for x in (-2.6, 1.4):
        table(m, st, (x - 0.7, 2.6), (x + 0.7, 6.0))
        m.dome(st, "ReadingLamp", "lamp", (x, 0.78, 4.3), (0.44, 0.3, 0.44), sides=8, solid=False)
    door_banners(m, sh, accent, 0.0, pz + 0.9, 4.6, 7.8, 3.5)
    library_decor(m, b, accent, top)
    sp = m.group("Spawns", g, grouped=False)
    m.spawn_in(sp, (-12.4, 0, 10.6), (-12.4, 0.0))           # behind the west stacks, looking down the wall lane
    m.spawn_in(sp, (-10.0, F2, 3.0), (0.0, 5.0))             # west mezzanine, looking over the hall
    m.spawn_in(sp, (10.0, F3, 6.0), (0.0, 5.0))              # top mezzanine
    m.spawn_in(sp, (8.0, 0, -6.5), (0.0, -16.0))             # the plaza, looking at the quad
    w = m.group("WeaponSpawns", g, grouped=False)
    m.weapon_in(w, (6.4, 0, 5.0), "sword")                  # a lane between the east stacks
    m.weapon_in(w, (0, 0, ZT + 2.6), "smg")                  # the tip, where people land
    m.weapon_in(w, (-8.0, F3, 11.4), "bolt_action")          # the top floor's back strip


def lecture_hall(m, g, accent, roof_kind):
    """One big room two floors high: a bowl of seating tiers climbing from the stage
    (east) to an upper concourse (west) at 5.5 m, an aisle up each side, and a projection
    booth high in the south-west corner. Its shape: a low shell of a roof over the stage."""
    b = m.group("Building", g, grouped=False)
    sh = m.group("Shell", b)
    top = 12.2
    walls(m, sh, "stone", BX0, BX1, BZ0, BZ1, 0, top,
          front=[fx(5.6, 8.8, 0, 4.2, 1.3), fx(-13.0, -10.0, F2 + 1.2, F2 + 4.4, 1.0), fx(-4.0, -1.0, 7.4, 10.6, 1.0)],
          back=[fx(6.0, 9.0, 1.2, 4.4, 1.0)],
          west=[sz(7.6, 10.6, F2, F2 + 2.8)], east=[sz(11.3, 13.3, 0, 3.6, 1.0)])
    band(m, sh, accent, BX0, BX1, BZ0, BZ1, 4.95, 5.4)
    band(m, sh, "stone_warm", BX0, BX1, BZ0, BZ1, 0.0, 0.7, out=0.1, name="Plinth")
    floor(m, sh, "Floor", "floor_wood", IX0, IX1, IZ0, IZ1, 0.03, 0.03, solid=False)
    roof(m, sh, roof_kind, BX0, BX1, BZ0, BZ1, top + 0.35, holes=[(-4.0, -2.2, 5.0, 6.8)])
    # The shell: half a flattened ball over the stage end of the roof.
    m.dome(sh, "RoofShell", roof_kind, (6.6, top + 0.35, 6.1), (13.6, 3.4, 13.6), sides=20)
    m.dome(sh, "RoofShellCap", "brass", (6.6, top + 3.65, 6.1), (1.4, 0.5, 1.4), sides=10, solid=False)
    door_banners(m, sh, accent, 7.2)
    lit_windows(m, sh, "z", BX1 + 0.2, 1, [1.5, 5.0, 8.5], 6.6, 9.6, arched=True)
    lit_windows(m, sh, "x", BZ1 + 0.2, 1, [-9.0, -4.5, 0.0], 7.0, 9.8, arched=True)
    # The stage and the giant screen.
    hall = m.group("Hall", b, grouped=False)
    m.box(hall, "Stage", "floor_wood", (9.0, 0, 1.0), (IX1, 0.6, 11.2), tint=(0.86, 0.86, 0.86))
    m.wedge(hall, "StageRamp", "stair", (7.2, 0, 4.0), (9.0, 0.6, 8.2), tall="+x")
    m.strip(hall, "ScreenFrame", "metal", (IX1 - 0.12, 1.6, 1.8), (IX1, 9.8, 10.4))
    m.strip(hall, "Screen", "screen", (IX1 - 0.2, 1.8, 2.0), (IX1 - 0.12, 9.6, 10.2))
    m.bev(hall, "Lectern", "table", (10.4, 0.6, 5.5), (11.1, 1.8, 6.7), 0.08)
    # Seven tiers, each 0.79 m up and 1.8 m deep, with a row of seats; then the concourse.
    N = 7
    CX = 5.0 - N * 1.8      # where the concourse begins
    for i in range(N):
        x1 = 5.0 - i * 1.8
        x0 = x1 - 1.8
        y = F2 * (i + 1) / N
        m.box(hall, "Tier", "stone_dark", (x0, 0, 1.0), (x1, y, 11.2))
        for z0, z1 in ((1.5, 5.6), (6.6, 10.7)):
            # (one solid lump per row to bump into; a seat and a back for each place, drawn)
            m.box(hall, "SeatsBody", "seat", (x0 + 0.3, y, z0), (x0 + 1.0, y + 0.45, z1), drawn=False)
            m.strip(hall, "SeatPlinth", "metal", (x0 + 0.5, y, z0 + 0.1), (x0 + 0.86, y + 0.3, z1 - 0.1))
            for k in range(5):
                za = z0 + k * 0.82
                m.bev(hall, "Seat", "seat", (x0 + 0.36, y + 0.3, za + 0.06), (x0 + 1.0, y + 0.46, za + 0.76), 0.06, solid=False)
                m.bev(hall, "SeatBack", "seat", (x0 + 0.14, y + 0.3, za + 0.06), (x0 + 0.36, y + 1.05, za + 0.76), 0.07, solid=False, tint=(0.86, 0.86, 0.86))
    floor(m, hall, "Concourse", "floor_wood", IX0, CX, IZ0, IZ1, F2, 0.3)
    m.box(hall, "ConcourseBase", "stone_dark", (IX0, 0, IZ0), (CX, F2 - 0.3, IZ1))
    # An aisle up each side wall: ground to the concourse.
    stairs(m, hall, "AisleNorth", (5.0, 0, -0.1), (CX, F2, -0.1), SW, sides=(False, True))
    stairs(m, hall, "AisleSouth", (5.0, 0, 12.3), (CX, F2, 12.3), SW, sides=(True, False))
    # The projection booth: a box in the south-west corner above the concourse, a stair
    # up to it along the west wall.
    bo = m.group("ProjectionBooth", b)
    BY = 8.8
    m.box(bo, "BoothFloor", "floor_wood", (IX0, BY - 0.3, 6.7), (-10.4, BY, IZ1))
    wall(m, bo, "BoothFront", "stone_warm", (-10.4, 6.7), (-10.4, IZ1), BY, top, 0.3, [(1.2, 5.6, BY + 0.9, BY + 2.6)])
    m.block(bo, "Projector", "equipment_dark", (-11.6, BY + 1.3, 10.0), (0.7, 1.3, 0.7), cols=LIE_X, shape="cyl", sides=10, solid=False)
    m.bev(bo, "ProjectorStand", "equipment", (-12.0, BY, 9.7), (-11.2, BY + 0.9, 10.3), 0.06)
    stairs(m, bo, "BoothStair", (-12.6, F2, 1.2), (-12.6, BY, 6.7), SW, sides=(False, True))
    # A balcony outside the west door (the door is under the booth).
    m.bev(b, "Balcony", "stone_warm", (BX0 - 2.8, F2 - 0.3, 5.8), (BX0 - 0.2, F2, 10.9), 0.08)
    m.rail(b, "BalconyRail", "rail", (BX0 - 2.7, 5.8), (BX0 - 2.7, 10.9), F2, 1.0)
    m.rail(b, "BalconyRail", "rail", (BX0 - 2.7, 5.86), (BX0 - 0.2, 5.86), F2, 1.0)
    m.rail(b, "BalconyRail", "rail", (BX0 - 2.7, 10.84), (BX0 - 0.2, 10.84), F2, 1.0)
    lecture_decor(m, b, accent, top)
    sp = m.group("Spawns", g, grouped=False)
    m.spawn_in(sp, (11.6, 0.6, 8.6), (0.0, 6.0))             # the stage, looking up the tiers
    m.spawn_in(sp, (-10.8, F2, 3.4), (0.0, 6.0))             # the concourse, looking down at the stage
    m.spawn_in(sp, (-12.2, BY, 11.6), (-5.0, 10.0))          # the booth, looking through its window
    m.spawn_in(sp, (15.4, 0, 6.0), (15.4, -4.0))             # the east walkway
    w = m.group("WeaponSpawns", g, grouped=False)
    m.weapon_in(w, (11.6, 0.6, 2.4), "break_action")
    m.weapon_in(w, (0, 0, ZT + 2.6), "shotgun")
    m.weapon_in(w, (-12.4, BY, 8.2), "bolt_action")               # the booth


def labs(m, g, accent, roof_kind):
    """Two floors. Ground: a corridor along the front and three labs behind glass walls
    that shatter when shot (never the only way through: every lab has an open door).
    Upstairs: an open lab floor with more glass, and a balcony over the door. Its shape:
    a wall of glass across the upper floor, and stacks and vents on the roof."""
    b = m.group("Building", g, grouped=False)
    sh = m.group("Shell", b)
    top = 11.6
    walls(m, sh, "stone", BX0, BX1, BZ0, BZ1, 0, top,
          front=[fx(2.0, 5.2, 0, 4.0), fx(8.0, 12.0, 1.2, 4.2), fx(2.0, 5.2, F2, F2 + 3.6),
                 fx(-12.6, -1.4, F2 + 0.9, F2 + 4.5), fx(8.0, 12.0, F2 + 1.0, F2 + 4.2)],
          back=[fx(-11.0, -8.0, 1.2, 4.2), fx(-1.5, 1.5, 1.2, 4.2), fx(8.0, 11.0, 1.2, 4.2), fx(-5.0, 5.0, F2 + 1.0, F2 + 4.2)],
          west=[sz(-0.8, 2.0, 0, 3.8), sz(7.0, 10.0, F2 + 1.0, F2 + 4.2)], east=[sz(-0.8, 2.0, 0, 3.8), sz(7.0, 10.0, F2 + 1.0, F2 + 4.2)])
    band(m, sh, accent, BX0, BX1, BZ0, BZ1, 4.95, 5.4)
    band(m, sh, "stone_warm", BX0, BX1, BZ0, BZ1, 0.0, 0.7, out=0.1, name="Plinth")
    floor(m, sh, "Floor", "floor_tile", IX0, IX1, IZ0, IZ1, 0.03, 0.03, solid=False)
    roof(m, sh, roof_kind, BX0, BX1, BZ0, BZ1, top + 0.35, holes=[(10.0, 11.8, 0.2, 2.0)])
    door_banners(m, sh, accent, 3.6, BZ0, 9.6, 11.2, 2.5)
    # The glass wall across the upper floor's front: you see through it, it does not break.
    m.box(sh, "GlassWall", "glass_window", (-12.6, F2 + 0.9, BZ0 - 0.05), (-1.4, F2 + 4.5, BZ0 + 0.05), unbreakable=True)
    for x in (-10.36, -8.12, -5.88, -3.64):
        m.strip(sh, "Mullion", "metal", (x - 0.05, F2 + 0.9, BZ0 - 0.12), (x + 0.05, F2 + 4.5, BZ0 + 0.12))
    m.strip(sh, "Mullion", "metal", (-12.6, F2 + 2.65, BZ0 - 0.1), (-1.4, F2 + 2.75, BZ0 + 0.1))
    lit_windows(m, sh, "x", BZ1 + 0.2, 1, [-11.0, 11.0], F2 + 1.2, F2 + 4.0)
    # On the roof: three stacks, two vent units and a duct.
    rf = m.group("RoofPlant", b, grouped=False)
    R = top + 0.35
    for x, z, h in ((-10.5, 10.5, 3.2), (-8.6, 10.5, 2.4), (-6.7, 10.5, 2.8)):
        m.cyl(rf, "Stack", "equipment", (x, R, z), 1.0, h, sides=12)
        m.cone(rf, "StackCap", "equipment_dark", (x, R + h + 0.25, z), 1.5, 0.5, top=0.3, sides=12, solid=False)
        m.cyl(rf, "StackNeck", "equipment_dark", (x, R + h, z), 0.5, 0.25, sides=8, solid=False)
    for x in (-2.0, 3.6):
        m.bev(rf, "VentUnit", "equipment", (x, R, 8.6), (x + 3.4, R + 1.5, 11.4), 0.14)
        m.cyl(rf, "VentFan", "equipment_dark", (x + 1.7, R + 1.5, 10.0), 1.8, 0.12, sides=14, solid=False)
    m.lying_cyl(rf, "Duct", "equipment", (-3.6, R + 0.5, 10.0), 0.8, 3.4, axis="x", sides=10)
    m.weapon_in(rf, (-6.0, R, 4.5), "battle_rifle")
    # Ground: the corridor is z -1.2..3.4; three labs behind it, a glass front on each
    # beside its open doorway, and glass between the labs.
    gl = m.group("GroundLabs", b, grouped=False)
    cz = 3.4
    # (solid posts where panes meet; each pane stops just short of the lintel so nothing rests on it)
    for x in (-11.1, -7.9, -4.6, -1.3, 1.3, 4.6, 7.9, 11.1):
        m.box(gl, "Post", "metal", (x - 0.1, 0, cz - 0.1), (x + 0.1, 3.6, cz + 0.1))
    m.box(gl, "Lintel", "metal", (IX0, 3.6, cz - 0.1), (IX1, 4.0, cz + 0.1))
    m.box(gl, "Transom", "glass_window", (IX0, 4.0, cz - 0.05), (IX1, F2 - 0.3, cz + 0.05), unbreakable=True)
    for x0, x1 in ((-11.0, -8.0), (-7.8, -4.7), (-4.5, -1.4), (1.4, 4.5), (4.7, 7.8), (8.0, 11.0)):
        m.box(gl, "LabGlass", "glass_lab", (x0, 0, cz - 0.05), (x1, 3.54, cz + 0.05))
    # (the ways in: at the west and east ends, and through the middle lab's front)
    for x in (-4.6, 4.6):
        for z in (5.8, 8.1):
            m.box(gl, "DividerPost", "metal", (x - 0.1, 0, z - 0.1), (x + 0.1, 3.6, z + 0.1))
        m.box(gl, "DividerLintel", "metal", (x - 0.1, 3.6, cz + 0.1), (x + 0.1, 4.0, 8.2))
        m.box(gl, "DividerTransom", "glass_window", (x - 0.05, 4.0, cz + 0.1), (x + 0.05, F2 - 0.3, 8.2), unbreakable=True)
        m.box(gl, "LabGlass", "glass_lab", (x - 0.05, 0, cz + 0.12), (x + 0.05, 3.54, 5.68))
        m.box(gl, "LabGlass", "glass_lab", (x - 0.05, 0, 5.92), (x + 0.05, 3.54, 7.98))
        m.box(gl, "DividerWall", "stone_warm", (x - 0.1, 0, 8.2), (x + 0.1, F2 - 0.3, IZ1))
    for x in (-9.2, 0.0, 9.2):
        counter(m, gl, (x - 2.0, 12.2), (x + 2.0, 13.3))
        m.cyl(gl, "Flask", "equipment", (x - 1.2, 1.05, 12.75), 0.5, 0.7, sides=10, solid=False)
        m.dome(gl, "FlaskTop", "glass_ware", (x - 1.2, 1.75, 12.75), (0.5, 0.3, 0.5), sides=10, solid=False)
    m.cyl(gl, "Tank", "equipment_dark", (-12.6, 0, 6.5), 1.3, 2.4, sides=12)
    m.dome(gl, "TankTop", "equipment_dark", (-12.6, 2.4, 6.5), (1.3, 0.5, 1.3), sides=12, solid=False)
    m.cyl(gl, "Centrifuge", "equipment", (12.3, 0, 6.5), 1.6, 1.2, sides=14)
    m.dome(gl, "CentrifugeLid", "equipment_dark", (12.3, 1.2, 6.5), (1.6, 0.4, 1.6), sides=14, solid=False)
    # Upstairs: the stair climbs east along the corridor's front wall, to just short of the
    # front door; an open floor with two glass screens, and a balcony over the door.
    up = m.group("UpperLab", b, grouped=False)
    sx0, sx1 = -10.6, -10.6 + RUN
    floor(m, up, "Floor2", "floor_tile", IX0, IX1, IZ0, IZ1, F2, 0.3, holes=[(sx0 - 0.2, sx1, IZ0, 1.0)])
    stairs(m, up, "StairUp", (sx0, 0, -0.1), (sx1, F2, -0.1), SW, sides=(False, True))
    m.rail(up, "Rail", "rail", (sx0 - 0.2, 1.0), (sx1, 1.0), F2, 1.0)
    m.rail(up, "Rail", "rail", (sx0 - 0.2, IZ0 + 0.1), (sx0 - 0.2, 1.0), F2, 1.0)
    for x in (-5.0, 6.0):
        for z in (3.9, 7.0, 10.1):
            m.box(up, "ScreenPost", "metal", (x - 0.1, F2, z - 0.1), (x + 0.1, F2 + 3.6, z + 0.1))
        m.box(up, "LabGlass", "glass_lab", (x - 0.05, F2, 4.02), (x + 0.05, F2 + 3.3, 6.88))
        m.box(up, "LabGlass", "glass_lab", (x - 0.05, F2, 7.12), (x + 0.05, F2 + 3.3, 9.98))
    for x in (-10.0, 0.5, 10.5):
        counter(m, up, (x - 1.8, 12.2), (x + 1.8, 13.3), y=F2)
        m.bev(up, "Apparatus", "equipment_dark", (x - 0.6, F2 + 1.05, 12.45), (x + 0.6, F2 + 1.7, 13.05), 0.1, solid=False)
    m.bev(up, "Balcony", "stone_warm", (0.6, F2 - 0.3, BZ0 - 2.6), (6.6, F2, BZ0 - 0.2), 0.08)
    m.rail(up, "BalconyRail", "rail", (0.66, BZ0 - 2.5), (6.54, BZ0 - 2.5), F2, 1.0)
    m.rail(up, "BalconyRail", "rail", (0.66, BZ0 - 2.5), (0.66, BZ0 - 0.2), F2, 1.0)
    m.rail(up, "BalconyRail", "rail", (6.54, BZ0 - 2.5), (6.54, BZ0 - 0.2), F2, 1.0)
    labs_decor(m, b, accent, top)
    sp = m.group("Spawns", g, grouped=False)
    m.spawn_in(sp, (-9.0, 0, 9.6), (-12.4, 3.4))             # lab 1, looking at its door
    m.spawn_in(sp, (11.0, F2, 9.0), (2.0, 6.0))              # upstairs, the east end
    m.spawn_in(sp, (-8.0, 0, -7.0), (0.0, -14.0))            # the plaza
    m.spawn_in(sp, (15.4, 0, 6.0), (15.4, -4.0))             # the east walkway, looking along it to the bridge
    w = m.group("WeaponSpawns", g, grouped=False)
    m.weapon_in(w, (9.5, F2, 4.5), "revolver")
    m.weapon_in(w, (0, 0, ZT + 2.6), "burst_rifle")


def cafeteria(m, g, accent, roof_kind):
    """A dining hall two floors high with a balcony round all four sides, a serving
    counter at the west end and big windows along the back (they look out at the planet).
    The door is west of the middle; the stair to the balcony climbs along the front wall
    east of it. Its shape: a striped awning all along the front, over a terrace."""
    b = m.group("Building", g, grouped=False)
    sh = m.group("Shell", b)
    top = 11.6
    walls(m, sh, "stone", BX0, BX1, BZ0, BZ1, 0, top,
          front=[fx(-6.0, -2.8, 0, 4.2, 1.3), fx(-12.5, -8.5, 1.2, 4.2, 1.0), fx(-9.0, -5.0, F2 + 1.2, F2 + 4.4, 1.0), fx(4.0, 8.0, F2 + 1.2, F2 + 4.4, 1.0)],
          back=[fx(-12.5, -5.5, 0.8, 4.4), fx(-3.5, 3.5, 0.8, 4.4), fx(5.5, 12.5, 0.8, 4.4), fx(-8.0, -2.0, F2 + 1.0, F2 + 4.2, 1.0), fx(2.0, 8.0, F2 + 1.0, F2 + 4.2, 1.0)],
          west=[sz(9.4, 12.4, 0, 3.8, 1.0)], east=[sz(2.6, 5.8, 0, 4.0, 1.2), sz(7.0, 10.0, F2 + 1.0, F2 + 4.2, 1.0)])
    band(m, sh, accent, BX0, BX1, BZ0, BZ1, 5.75, 6.2)
    band(m, sh, "stone_warm", BX0, BX1, BZ0, BZ1, 0.0, 0.7, out=0.1, name="Plinth")
    floor(m, sh, "Floor", "floor_tile", IX0, IX1, IZ0, IZ1, 0.03, 0.03, solid=False)
    roof(m, sh, roof_kind, BX0, BX1, BZ0, BZ1, top + 0.35, holes=[(-0.9, 0.9, 5.5, 7.3)])
    # The big windows: glass you look through but cannot break or pass.
    for x0, x1 in ((-12.5, -5.5), (-3.5, 3.5), (5.5, 12.5)):
        m.box(sh, "PictureWindow", "glass_window", (x0, 0.8, BZ1 - 0.06), (x1, 4.4, BZ1 + 0.06), unbreakable=True)
        m.strip(sh, "Mullion", "metal", ((x0 + x1) / 2 - 0.05, 0.8, BZ1 - 0.12), ((x0 + x1) / 2 + 0.05, 4.4, BZ1 + 0.12))
    lit_windows(m, sh, "z", BX0 - 0.2, -1, [1.5, 5.0], F2 + 1.2, F2 + 4.0, arched=True)
    # The awning: stripes of the building's colour and cream sloping out from the front
    # wall over the terrace, on thin posts.
    aw = m.group("Awning", b)
    n = 18
    wide = 25.2 / n
    for i in range(n):
        x0 = -12.6 + i * wide
        m.wedge(aw, "Stripe", accent if i % 2 == 0 else "awning", (x0, 4.55, BZ0 - 3.8), (x0 + wide, 5.55, BZ0 - 0.2), tall="+z")
    m.strip(aw, "AwningEdge", "brass", (-12.7, 4.47, BZ0 - 3.86), (12.7, 4.55, BZ0 - 3.74))
    for x in (-12.4, -7.4, -1.4, 4.4, 9.4, 12.4):
        m.cyl(aw, "AwningPost", "metal", (x, 0, BZ0 - 3.6), 0.14, 4.5, sides=8)
    for x in (2.0, 7.0, 11.0):
        m.cyl(aw, "CafeTable", "table", (x, 0.7, BZ0 - 2.2), 1.3, 0.08, sides=14)
        m.cyl(aw, "CafeTableLeg", "metal", (x, 0, BZ0 - 2.2), 0.16, 0.7, sides=8)
    # The balcony at 5.5 m, all the way round, open in the middle. The stair climbs along
    # the front wall, east of the door.
    ba = m.group("Balcony", b, grouped=False)
    sx0, sx1 = 10.4, 10.4 - RUN       # the stair's foot (east) and head (west)
    floor(m, ba, "Balcony", "floor_wood", IX0, IX1, IZ0, 3.2, F2, holes=[(sx1, sx0 + 0.2, IZ0, 1.0)])
    floor(m, ba, "Balcony", "floor_wood", 10.0, IX1, 3.2, 9.6, F2)
    floor(m, ba, "Balcony", "floor_wood", IX0, IX1, 9.6, IZ1, F2)
    floor(m, ba, "Balcony", "floor_wood", IX0, -10.2, 3.2, 9.6, F2)
    m.rail(ba, "Rail", "rail", (-10.2, 3.2), (10.0, 3.2), F2, 1.0)
    m.rail(ba, "Rail", "rail", (-10.2, 9.6), (10.0, 9.6), F2, 1.0)
    m.rail(ba, "Rail", "rail", (-10.2, 3.2), (-10.2, 9.6), F2, 1.0)
    m.rail(ba, "Rail", "rail", (10.0, 3.2), (10.0, 9.6), F2, 1.0)
    m.rail(ba, "Rail", "rail", (sx1, 1.0), (sx0 + 0.2, 1.0), F2, 1.0)
    m.rail(ba, "Rail", "rail", (sx0 + 0.2, IZ0 + 0.1), (sx0 + 0.2, 1.0), F2, 1.0)
    stairs(m, ba, "StairUp", (sx0, 0, -0.1), (sx1, F2, -0.1), SW, sides=(False, True))
    # Long tables (chairs both sides of the front row, one side of the back one, so
    # there is room to walk all round), and the serving counter at the west end.
    hall = m.group("Hall", b, grouped=False)
    for z, bench_at in ((4.6, (-1.1, 1.1)), (9.4, (-1.1,))):
        for x in (-4.8, 3.6):
            table(m, hall, (x - 2.6, z - 0.5), (x + 2.6, z + 0.5))
            for dz in bench_at:
                for dx in (-1.95, -0.65, 0.65, 1.95):
                    chair(m, hall, x + dx, z + dz * 0.8, 0, "-z" if dz > 0 else "+z")
    counter(m, hall, (-12.8, 1.6), (-11.8, 8.2))
    m.strip(hall, "MenuBoard", "screen", (IX0, 2.4, 2.2), (IX0 + 0.08, 4.0, 7.6))
    m.strip(hall, "HeatLamp", "lamp", (-12.7, 2.2, 2.0), (-11.9, 2.3, 7.8))
    for x in (-7.0, 0.0, 7.0):   # (narrow shelves to eat at, against the windows: the balcony stays clear to walk)
        m.bev(hall, "BalconyShelf", "table", (x - 1.6, F2 + 0.95, IZ1 - 0.45), (x + 1.6, F2 + 1.05, IZ1), 0.03)
    cafeteria_decor(m, b, accent, top)
    sp = m.group("Spawns", g, grouped=False)
    m.spawn_in(sp, (9.0, 0, 11.6), (0.0, 6.0))               # by the windows, looking down the hall
    m.spawn_in(sp, (-12.0, F2, 6.0), (0.0, 6.0))             # the balcony's west end
    m.spawn_in(sp, (11.0, F2, 11.5), (0.0, 11.5))            # the back balcony
    m.spawn_in(sp, (9.0, 0, -8.5), (0.0, -16.0))             # the plaza
    w = m.group("WeaponSpawns", g, grouped=False)
    m.weapon_in(w, (-0.6, 0, 7.0), "machine_pistol")         # the aisle between the tables
    m.weapon_in(w, (0, 0, ZT + 2.6), "rifle")
    m.weapon_in(w, (-6.0, F2, 11.6), "shotgun")         # the back balcony


def observatory(m, g, accent, roof_kind):
    """A square hall with the dome standing on its roof terrace. Inside the dome: the
    telescope (it turns slowly, above head height); a slit in the dome opens to the sky.
    The cap on top of the dome is a power weapon's spot. Its shape: the dome."""
    b = m.group("Building", g, grouped=False)
    sh = m.group("Shell", b)
    x0, x1, z0, z1 = -13.4, 13.4, BZ0, BZ1
    ox = lambda a, c, lo, hi, arch=0.0: fx(a, c, lo, hi, arch, west=x0)
    walls(m, sh, "stone", x0, x1, z0, z1, 0, F2,
          front=[ox(-1.6, 1.6, 0, 4.2, 1.3), ox(-9.5, -6.5, 1.2, 4.4, 1.0), ox(6.5, 9.5, 1.2, 4.4, 1.0)],
          back=[ox(8.0, 11.0, 1.2, 4.4, 1.0)],
          west=[sz(3.0, 6.2, 0, 4.0, 1.2)], east=[sz(5.0, 8.2, 0, 4.0, 1.2)])
    band(m, sh, accent, x0, x1, z0, z1, 4.5, 4.95)
    band(m, sh, "stone_warm", x0, x1, z0, z1, 0.0, 0.7, out=0.1, name="Plinth")
    floor(m, sh, "Floor", "floor_tile", x0 + 0.2, x1 - 0.2, z0 + 0.2, z1 - 0.2, 0.03, 0.03, solid=False)
    door_banners(m, sh, accent, 0.0, z0, 4.6, 5.4, 2.6)
    # The terrace (the hall's roof). The stair climbs west along the back wall and comes
    # out in the terrace's back corner, west of the dome.
    T = F2 + 0.3
    foot, head = 1.1, -8.6
    # (the hole starts where the stair still has 2.4 m of headroom under the terrace)
    floor(m, sh, "Terrace", "paving", x0 - 0.2, x1 + 0.2, z0 - 0.2, z1 + 0.2, T, 0.3, holes=[(head, -4.0, 11.2, z1 - 0.2)])
    stairs(m, sh, "StairUp", (foot, 0, 12.3), (head, T, 12.3), SW, sides=(True, False))
    low_wall(m, sh, (x0 - 0.05, z0 - 0.05), (x1 + 0.05, z0 - 0.05), T, 0.9, holes=[(4.0, 7.0)])
    low_wall(m, sh, (x0 - 0.05, z1 + 0.05), (x1 + 0.05, z1 + 0.05), T, 0.9)
    low_wall(m, sh, (x0 - 0.05, z0 + 0.1), (x0 - 0.05, z1 - 0.1), T, 0.9)
    low_wall(m, sh, (x1 + 0.05, z0 + 0.1), (x1 + 0.05, z1 - 0.1), T, 0.9, holes=[(1.5, 4.5)])
    m.rail(sh, "Rail", "rail", (head, 11.2), (-4.0, 11.2), T, 1.0)
    m.rail(sh, "Rail", "rail", (-4.0, 11.2), (-4.0, z1 - 0.3), T, 1.0)
    counter(m, sh, (-12.0, 9.0), (-7.4, 10.0))
    m.cyl(sh, "OrreryBase", "equipment_dark", (-6.0, 0, 5.0), 1.6, 1.0, sides=12)
    m.block(sh, "OrreryRing", "brass", (-6.0, 1.9, 5.0), (3.0, 0.08, 3.0), shape="tube", sides=20, inner=2.7, solid=False)
    m.block(sh, "OrreryRing", "brass", (-6.0, 1.9, 5.0), (2.1, 0.08, 2.1), cols=((0.9, 0.44, 0), (-0.44, 0.9, 0), (0, 0, 1)), shape="tube", sides=18, inner=1.85, solid=False)
    for kind, base, size in (("lamp", (-6.0, 1.9, 5.0), 0.7), ("accent_teal", (-4.6, 1.95, 5.3), 0.32), ("accent_red", (-6.6, 1.95, 4.2), 0.26)):
        m.dome(sh, "OrreryBall", kind, base, (size, size / 2, size), sides=8, solid=False)
        m.dome(sh, "OrreryBall", kind, base, (size, size / 2, size), sides=8, flip=True, solid=False)
    m.cyl(sh, "OrreryStem", "brass", (-6.0, 1.0, 5.0), 0.14, 0.6, sides=6, solid=False)
    lit_windows(m, sh, "z", x1 + 0.2, 1, [0.6, 10.6], 1.4, 3.8, arched=True)
    # The dome: a twenty-sided drum on the terrace and half a ball on top of it, a real
    # shell you stand inside. One wall piece in four is glass; the slit is open from the
    # terrace to the top.
    C = (5.0, 6.0)       # the dome's middle on the terrace (x, z)
    dm = m.group("Dome", b, grouped=False)
    R, n = 6.4, 20
    H = 4.2              # the drum's height
    seg = 2 * R * math.tan(math.pi / n) + 0.06
    door_side = 15      # the wall piece facing west (toward the stair): the way in
    slit_side = 2
    for i in range(n):
        deg = i * 360.0 / n
        if i == slit_side:
            continue    # the slit: open from the terrace to the top
        px, _py, pz = polar(R, deg)
        cols = rot(deg)
        if i == door_side:
            m.block(dm, "DrumLintel", "stone", (C[0] + px, T + 3.6, C[1] + pz), (seg, 1.2, 0.4), cols=cols)
        elif i % 4 == 0:
            m.block(dm, "DrumSill", "stone", (C[0] + px, T + 0.5, C[1] + pz), (seg, 1.0, 0.4), cols=cols)
            m.block(dm, "DomeGlass", "glass_sky", (C[0] + px, T + 2.1, C[1] + pz), (seg, 2.2, 0.12), cols=cols, unbreakable=True)
            m.block(dm, "DrumLintel", "stone", (C[0] + px, T + 3.7, C[1] + pz), (seg, 1.0, 0.4), cols=cols)
        else:
            m.block(dm, "Drum", "stone", (C[0] + px, T + H / 2, C[1] + pz), (seg, H, 0.4), cols=cols)
        bx, _by, bz = polar(R + 0.24, deg)
        m.block(dm, "DrumBand", accent, (C[0] + bx, T + H - 0.35, C[1] + bz), (seg, 0.4, 0.08), cols=cols, solid=False)
    m.block(dm, "DomeRing", "brass", (C[0], T + H + 0.1, C[1]), (2 * R + 1.0, 0.24, 2 * R + 1.0), shape="tube", sides=n, inner=2 * R - 0.5,
            cols=rot(9.0), solid=False)
    m.block(dm, "DomeShell", "dome_copper", (C[0], T + H + 3.3, C[1]), (2 * R + 0.4, 6.6, 2 * R + 0.4), cols=rot(slit_side * 360.0 / n),
            shape="dome", sides=n, inner=2 * R - 0.4, arc=360.0 - 360.0 / n)
    apex = T + H + 6.6
    m.cyl(dm, "DomeCap", "brass", (C[0], apex - 0.3, C[1]), 3.4, 0.4, sides=14)
    m.weapon_in(dm, (C[0] - 0.9, apex + 0.1, C[1]), "railgun")
    # Inside: the telescope's pier, and the telescope turning on it.
    m.cyl(dm, "Pier", "equipment_dark", (C[0], T, C[1]), 1.9, 2.8, sides=12)
    m.cyl(dm, "PierCap", "brass", (C[0], T + 2.8, C[1]), 2.4, 0.25, sides=12, solid=False)
    scope = m.node("Telescope", dm, "spinner", [("transform", xform(IDENTITY, (C[0], T + 3.6, C[1]))), ("speed", "5.0")])
    tilt = ((1, 0, 0), (0, 0.5, 0.866), (0, -0.866, 0.5))   # its own y (the tube's length) tipped 60 degrees toward +z
    m.block(scope, "Tube", "telescope", (0, 1.1, 1.9), (1.4, 5.8, 1.4), cols=tilt, shape="cyl", sides=12, solid=False)
    m.block(scope, "Hood", "equipment_dark", (0, 2.5, 4.3), (1.6, 0.7, 1.6), cols=tilt, shape="cyl", sides=12, solid=False)
    m.block(scope, "Eyepiece", "brass", (0, -0.35, -0.65), (0.6, 0.9, 0.6), cols=tilt, shape="cyl", sides=8, solid=False)
    m.block(scope, "Fork", "equipment", (0, -0.2, 0), (2.4, 0.6, 0.9), shape="bevel", bevel=0.1, solid=False)
    m.block(scope, "Counterweight", "equipment_dark", (0, -0.2, -1.7), (1.0, 1.0, 1.0), cols=tilt, shape="cyl", sides=10, solid=False)
    observatory_decor(m, b, accent, T, C, x0, x1)
    sp = m.group("Spawns", g, grouped=False)
    m.spawn_in(sp, (9.0, 0, 2.0), (0.0, 6.0))                # the hall
    m.spawn_in(sp, (-9.0, T, 2.0), (-9.0, -12.0))            # the terrace, west of the dome, looking at the quad
    m.spawn_in(sp, (-3.4, T, 6.0), (-8.0, -10.0))            # the terrace by the dome's door, looking out over the plaza
    m.spawn_in(sp, (-8.0, 0, -7.0), (0.0, -14.0))            # the plaza
    w = m.group("WeaponSpawns", g, grouped=False)
    m.weapon_in(w, (-9.0, 0, 3.0), "battle_rifle")
    m.weapon_in(w, (0, 0, ZT + 2.6), "revolver")
    m.weapon_in(w, (-11.0, T, 7.5), "crossbow")           # the terrace


# ---------------------------------------------------------------------------
# Decor, building by building (see the helpers above: small things are drawn only)

def library_decor(m, b, accent, top):
    d = m.group("Decor", b, grouped=False)
    # The reading room: chairs at the tables, a rug under them, a globe.
    rug(m, d, (-4.4, 1.9), (3.2, 6.7), kind="rug_red")
    for x in (-2.6, 1.4):
        for z in (3.4, 5.2):
            chair(m, d, x - 1.15, z, 0, "+x")
            chair(m, d, x + 1.15, z, 0, "-x")
        m.cyl(d, "LampStem", "brass", (x, 0.78, 4.3), 0.06, 0.34, sides=6, solid=False)
        m.cone(d, "LampShade", accent, (x, 1.06, 4.3), 0.5, 0.26, top=0.2, sides=10, solid=False)
        m.strip(d, "OpenBook", "canvas", (x - 0.3, 0.78, 3.2), (x + 0.3, 0.81, 3.6))
        m.strip(d, "OpenBook", "books_green", (x - 0.2, 0.78, 5.0), (x + 0.16, 0.86, 5.3))
    m.cyl(d, "GlobeStand", "frame", (3.9, 0, 8.6), 0.5, 0.9, sides=8, solid=False)
    m.block(d, "GlobeRing", "brass", (3.9, 1.4, 8.6), (1.2, 0.05, 1.2), cols=((0.92, 0.39, 0), (-0.39, 0.92, 0), (0, 0, 1)), shape="tube", sides=16, inner=1.06, solid=False)
    ball(m, d, "Globe", "accent_blue", (3.9, 1.4, 8.6), 0.96, sides=10)
    m.dome(d, "GlobeLand", "cushion_green", (3.9, 1.42, 8.6), (0.99, 0.34, 0.99), sides=5, solid=False)
    # Armchairs under the front windows, either side of the door.
    for sx, kind in ((-1, "cushion_blue"), (1, "cushion_green")):
        armchair(m, d, sx * 8.2, -0.5, 0, "+z", kind)
        armchair(m, d, sx * 9.9, -0.5, 0, "+z", kind)
        side_table(m, d, sx * 9.05, -0.6)
        floor_plant(m, d, sx * 12.9, -0.5, 0, 1.0)
        rug(m, d, (sx * 9.05 - 2.0, -1.0), (sx * 9.05 + 2.0, 1.2), kind="rug_blue")
    floor_plant(m, d, 2.6, -0.6, 0, 0.9)
    floor_plant(m, d, -2.6, -0.6, 0, 0.9)
    # The west mezzanine: a long desk against the wall, chairs, a rug and armchairs.
    table(m, d, (-13.7, 2.4), (-12.8, 5.8), y=F2)
    for z in (3.2, 4.9):
        chair(m, d, -12.25, z, F2, "-x")
        m.cyl(d, "LampStem", "brass", (-13.3, F2 + 0.78, z), 0.06, 0.34, sides=6, solid=False)
        m.cone(d, "LampShade", accent, (-13.3, F2 + 1.06, z), 0.46, 0.24, top=0.18, sides=10, solid=False)
    rug(m, d, (-11.4, 6.8), (-7.2, 9.0), y=F2, kind="rug_red")
    armchair(m, d, -10.2, 8.3, F2, "-z", "cushion_green")
    armchair(m, d, -8.5, 8.3, F2, "-z", "cushion_green")
    potted(m, d, -6.6, 0.4, F2, 0.9)
    floor_plant(m, d, -13.1, -0.5, F2, 0.9)
    # The top mezzanine: armchairs by the shelf, plants.
    rug(m, d, (9.0, 8.4), (13.2, 12.6), y=F3, kind="rug_blue")
    armchair(m, d, 10.2, 11.8, F3, "-z", "cushion_blue")
    armchair(m, d, 12.0, 11.8, F3, "-z", "cushion_blue")
    side_table(m, d, 11.1, 12.0, F3)
    floor_plant(m, d, 13.1, 0.0, F3, 0.9)
    potted(m, d, 6.6, 12.8, F3, 0.9)
    # Lights: under each mezzanine, and long ones down from the roof.
    for x, z in ((-10.0, 4.0), (-10.0, 11.0), (-3.6, 11.4)):
        ceiling_light(m, d, x, F2 - 0.3, z, 0.4)
    for x, z in ((10.0, 3.0), (10.0, 9.0), (-8.0, 11.4), (0.0, 11.4)):
        ceiling_light(m, d, x, F3 - 0.3, z, 0.5)
    for x, z in ((10.0, 5.0), (-9.0, 11.4), (10.0, 11.0), (-9.5, 3.0)):
        ceiling_light(m, d, x, top, z, 1.4, 0.8)
    # Pictures, and lamps by the door.
    picture(m, d, "x", IZ1, -1, 11.6, 2.4, 1.6, 1.1, ("accent_blue", "banner_gold"), 0)
    picture(m, d, "z", IX0, 1, 10.6, 2.3, 1.5, 1.1, ("accent_red", "canvas"), 1)
    picture(m, d, "z", IX1, -1, 10.8, 2.3, 1.5, 1.1, ("cushion_green", "banner_gold"), 2)
    picture(m, d, "z", IX0, 1, 10.5, F2 + 2.2, 1.6, 1.1, ("banner_gold", "accent_blue"), 1)
    for x in (-2.5, 2.5):
        sconce(m, d, "x", BZ0 - 0.2, -1, x, 3.1)
    bin_(m, d, 2.3, 12.9)
    # Outside: ivy up the back and the west wall, a garden on the roof.
    ivy(m, d, "x", BZ1 + 0.2, 1, -7.7, -5.8, 0, 8.5, seed=1)
    ivy(m, d, "x", BZ1 + 0.2, 1, 5.8, 7.7, 0, 7.0, seed=2)
    ivy(m, d, "z", BX0 - 0.2, -1, 9.0, 13.2, 0, 9.5, seed=3)
    R = top + 0.35
    planter_box(m, d, (-11.0, 10.4), (-4.0, 11.6), y=R, seed=0)
    planter_box(m, d, (-12.6, 1.0), (-11.4, 8.0), y=R, seed=1)
    potted(m, d, 12.4, 11.8, R, 1.2)
    potted(m, d, 6.6, 0.2, R, 1.2)
    shrub(m, d, -7.4, 0.6, R, 1.4)


def lecture_decor(m, b, accent, top):
    d = m.group("Decor", b, grouped=False)
    # The stage: curtains either side of the screen, a proper lectern, plants.
    for z0 in (1.02, 10.5):
        for k in range(4):
            m.cyl(d, "Curtain", "seat", (IX1 - 0.3, 0.6, z0 + 0.1 + k * 0.17), 0.24, 9.5, sides=8, solid=False, tint=(1.0, 1.0, 1.0) if k % 2 else (0.84, 0.84, 0.84))
    m.bev(d, "CurtainPelmet", "seat", (IX1 - 0.52, 9.9, 1.0), (IX1 - 0.04, 10.7, 11.2), 0.1, solid=False, tint=(0.8, 0.8, 0.8))
    m.strip(d, "PelmetTrim", "brass", (IX1 - 0.56, 9.86, 1.0), (IX1 - 0.5, 9.94, 11.2))
    m.wedge(d, "LecternTop", "frame", (10.3, 1.8, 5.45), (11.2, 2.0, 6.75), tall="+x", solid=False)
    m.strip(d, "LecternMic", "metal", (10.9, 2.0, 6.08), (10.94, 2.32, 6.12))
    stool(m, d, 11.9, 6.1, 0.6)
    floor_plant(m, d, 9.7, 1.6, 0.6, 1.0)
    floor_plant(m, d, 9.7, 10.6, 0.6, 1.0)
    rug(m, d, (9.6, 3.6), (12.6, 8.6), y=0.6, kind="rug_red")
    # The concourse: plants, a bench against the wall, pictures.
    floor_plant(m, d, -8.2, 6.1, F2, 0.9)
    potted(m, d, -8.2, -0.7, F2, 0.9)
    potted(m, d, -8.2, 12.9, F2, 0.9)
    for z, colours, seed in ((2.6, ("accent_red", "banner_gold"), 0), (5.0, ("accent_blue", "canvas"), 1)):
        picture(m, d, "z", IX0, 1, z, F2 + 2.2, 1.5, 1.1, colours, seed)
    # Sound panels down both side walls over the aisles, and hanging lights.
    for i, x in enumerate((-4.6, -1.0, 2.6)):
        m.on_wall(d, "SoundPanel", "cushion_blue" if i % 2 else accent, "x", IZ1, -1, x - 1.2, x + 1.2, 7.4, 9.4, depth=0.1)
        m.on_wall(d, "SoundPanel", accent if i % 2 else "cushion_blue", "x", IZ0, 1, x + 0.4, x + 2.8, 7.2, 9.2, depth=0.1)
    for x in (-5.0, 1.5):
        for z in (3.4, 8.8):
            ceiling_light(m, d, x, top, z, 1.2, 0.9)
    for x in (10.5, 12.5):
        for z in (3.0, 9.2):
            m.cone(d, "StageLight", "equipment_dark", (x, top - 0.5, z), 0.5, 0.5, top=0.26, sides=8, solid=False)
            m.dome(d, "StageLamp", "lamp", (x, top - 0.5, z), (0.4, 0.14, 0.4), sides=8, flip=True, solid=False)
    # Booth: a chair at the projector.
    chair(m, d, -12.6, 10.0, 8.8, "+x")
    # Outside: lamps by the door, ivy, planters and a bench on the flat of the roof.
    for x in (4.9, 9.5):
        sconce(m, d, "x", BZ0 - 0.2, -1, x, 3.1)
    ivy(m, d, "x", BZ1 + 0.2, 1, -12.8, -10.2, 0, 6.2, seed=4)
    ivy(m, d, "x", BZ1 + 0.2, 1, 10.4, 13.2, 0, 5.4, seed=5)
    ivy(m, d, "z", BX1 + 0.2, 1, -0.8, 3.0, 0, 5.8, seed=6)
    R = top + 0.35
    planter_box(m, d, (-12.6, 0.0), (-8.6, 1.2), y=R, seed=2)
    planter_box(m, d, (-12.6, 11.0), (-8.6, 12.2), y=R, seed=3)
    bench(m, d, -10.6, 8.6, R)
    potted(m, d, -6.6, 12.0, R, 1.2)
    potted(m, d, -1.4, 0.2, R, 1.1)


def labs_decor(m, b, accent, top):
    d = m.group("Decor", b, grouped=False)
    cz = 3.4
    # The three labs: a workbench in the middle of each with a screen, glass and stools;
    # stools at the wall benches; a cabinet against each inner wall.
    for i, (x, z) in enumerate(((-9.2, 6.9), (0.0, 5.9), (9.2, 6.5))):
        counter(m, d, (x - 1.6, z - 0.55), (x + 1.6, z + 0.55), height=0.95)
        monitor(m, d, x - 0.9, 0.95, z, "+z")
        glassware(m, d, x + 0.4, 0.95, z - 0.1, seed=i)
        m.cyl(d, "Microscope", "equipment_dark", (x + 1.15, 0.95, z + 0.1), 0.26, 0.06, sides=8, solid=False)
        m.cyl(d, "MicroscopeArm", "equipment", (x + 1.15, 1.01, z + 0.18), 0.08, 0.4, sides=6, solid=False)
        m.cone(d, "MicroscopeEye", "equipment_dark", (x + 1.15, 1.2, z + 0.06), 0.16, 0.3, top=0.08, sides=6, solid=False)
        stool(m, d, x - 0.7, z + 1.0)
        stool(m, d, x + 0.7, z + 1.0)
        for dx in (-0.9, 0.9):
            stool(m, d, [-9.2, 0.0, 9.2][i] + dx, 11.7)
        monitor(m, d, [-9.2, 0.0, 9.2][i] + 0.2, 1.05, 12.9, "-z")
        glassware(m, d, [-9.2, 0.0, 9.2][i] + 1.2, 1.05, 12.7, seed=i + 3)
        strip_light(m, d, (x - 1.4, 8.4), (x + 1.4, 8.7), F2 - 0.3)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 4.72, sx * 5.34))
        m.bev(d, "Cabinet", "counter", (x0, 0, 9.0), (x1, 2.3, 12.0), 0.05)
        face = x1 if sx > 0 else x0
        for z in (10.0, 11.0):
            m.strip(d, "CabinetSeam", "metal", (face - 0.01 if sx < 0 else face, 0.1, z - 0.015), (face if sx < 0 else face + 0.01, 2.2, z + 0.015))
        for z in (9.9, 10.1, 10.9, 11.1):
            m.strip(d, "CabinetHandle", "brass", (face - 0.04 if sx < 0 else face, 1.0, z - 0.02), (face if sx < 0 else face + 0.04, 1.3, z + 0.02))
    # The corridor: plants by the door, a bench under the window, lights, pictures.
    floor_plant(m, d, 1.3, -0.7, 0, 0.9)
    floor_plant(m, d, 5.9, -0.7, 0, 0.9)
    bench(m, d, 10.0, -0.75)
    bin_(m, d, 12.9, 2.7)
    for x in (-9.0, -3.0, 3.0, 9.0):
        strip_light(m, d, (x - 0.9, 2.1), (x + 0.9, 2.35), F2 - 0.3)
    picture(m, d, "x", IZ0, 1, 6.8, 2.4, 1.0, 1.3, (accent, "canvas"), 0)
    # Upstairs: two more workbenches, stools at the wall benches, plants, lights.
    for i, x in enumerate((-9.5, 2.0)):
        counter(m, d, (x - 1.6, 6.0), (x + 1.6, 7.1), y=F2, height=0.95)
        monitor(m, d, x + 0.8, F2 + 0.95, 6.55, "+z")
        glassware(m, d, x - 0.6, F2 + 0.95, 6.5, seed=i + 6)
        stool(m, d, x - 0.7, 7.6, F2)
        stool(m, d, x + 0.7, 7.6, F2)
    for x in (-10.0, 0.5, 10.5):
        stool(m, d, x - 0.8, 11.7, F2)
        monitor(m, d, x + 1.0, F2 + 1.05, 12.9, "-z")
    floor_plant(m, d, 13.0, -0.5, F2, 1.0)
    floor_plant(m, d, -13.0, 11.0, F2, 1.0)
    potted(m, d, 7.0, -0.6, F2, 0.9)
    for x in (-9.0, -1.5, 3.0, 10.0):
        strip_light(m, d, (x - 1.2, 8.3), (x + 1.2, 8.6), top)
        strip_light(m, d, (x - 1.2, 2.6), (x + 1.2, 2.9), top)
    picture(m, d, "z", IX1, -1, 4.0, F2 + 2.4, 1.6, 1.1, (accent, "banner_gold"), 2)
    # The balcony over the door: two plants.
    potted(m, d, 1.3, BZ0 - 2.0, F2, 0.8)
    potted(m, d, 5.9, BZ0 - 2.0, F2, 0.8)
    # Outside: lamps by the door, ivy, planters on the roof.
    for x in (1.3, 5.9):
        sconce(m, d, "x", BZ0 - 0.2, -1, x, 3.0)
    ivy(m, d, "x", BZ1 + 0.2, 1, -6.6, -3.4, 0, 5.2, seed=7)
    ivy(m, d, "x", BZ1 + 0.2, 1, 3.4, 6.6, 0, 6.4, seed=8)
    ivy(m, d, "z", BX0 - 0.2, -1, 4.0, 8.4, 0, 5.0, seed=9)
    R = top + 0.35
    planter_box(m, d, (-12.6, 0.0), (-8.0, 1.2), y=R, seed=1)
    planter_box(m, d, (1.6, 0.0), (7.6, 1.2), y=R, seed=2)
    potted(m, d, 12.4, 11.8, R, 1.2)


def cafeteria_decor(m, b, accent, top):
    d = m.group("Decor", b, grouped=False)
    # On the tables: a vase and plates. On the counter: trays, a glass guard, stools.
    for z in (4.6, 9.4):
        for i, x in enumerate((-4.8, 3.6)):
            m.cyl(d, "Vase", "glass_ware", (x, 0.78, z), 0.14, 0.24, sides=8, solid=False)
            m.dome(d, "VaseFlower", FLOWERS[(i + int(z)) % 4], (x, 1.02, z), (0.3, 0.2, 0.3), sides=6, solid=False)
            for dx in (-1.6, 1.5):
                m.cyl(d, "Plate", "canvas", (x + dx, 0.78, z + 0.05), 0.34, 0.025, sides=10, solid=False)
    for i, z in enumerate((2.4, 4.0, 5.6, 7.2)):
        m.bev(d, "Tray", "equipment", (-12.7, 1.05, z - 0.3), (-11.95, 1.09, z + 0.3), 0.015, solid=False)
        m.dome(d, "Dish", FLOWERS[i % 4] if i % 2 else "banner_gold", (-12.32, 1.09, z), (0.42, 0.16, 0.42), sides=8, solid=False)
    m.strip(d, "CounterGuard", "glass_ware", (-11.86, 1.35, 1.8), (-11.82, 1.9, 8.0))
    for z in (1.8, 8.0):
        m.strip(d, "GuardPost", "metal", (-11.88, 1.05, z - 0.03), (-11.8, 1.9, z + 0.03))
    for z in (2.6, 4.2, 5.8, 7.4):
        stool(m, d, -11.1, z)
    m.bev(d, "DrinksMachine", "equipment", (-13.7, 0, 8.5), (-13.0, 2.1, 9.2), 0.06, solid=False)
    m.strip(d, "DrinksPanel", "screen", (-13.0, 1.1, 8.6), (-12.98, 1.8, 9.1))
    # Plants, a couple of small tables on the west balcony, bins.
    floor_plant(m, d, 13.1, 1.9, 0, 1.1)
    floor_plant(m, d, -13.1, 12.9, 0, 1.1)
    floor_plant(m, d, 13.1, 12.9, 0, 1.1)
    potted(m, d, -7.0, -0.7, 0, 1.0)
    bin_(m, d, -2.2, -0.8)
    for z in (4.6, 8.2):
        m.cyl(d, "CafeTable", "table", (-12.4, F2 + 0.72, z), 1.0, 0.06, sides=12, solid=False)
        m.cyl(d, "CafeTableLeg", "metal", (-12.4, F2, z), 0.08, 0.72, sides=6, solid=False)
        chair(m, d, -12.4, z - 0.85, F2, "+z")
        chair(m, d, -12.4, z + 0.85, F2, "-z")
    floor_plant(m, d, 13.1, 12.8, F2, 1.0)
    floor_plant(m, d, -13.1, -0.5, F2, 1.0)
    potted(m, d, 13.1, -0.5, F2, 0.9)
    # Chandeliers over the hall, lamps under the balcony, pictures.
    for x in (-4.8, 3.6):
        chandelier(m, d, x, top, 6.4, 3.2, 2.6)
    for x, z in ((-9.0, 1.0), (-1.5, 1.2), (-8.0, 11.5), (0.0, 11.5), (8.0, 11.5), (12.0, 6.4), (-12.0, 6.4)):
        ceiling_light(m, d, x, F2 - 0.3, z, 0.4)
    picture(m, d, "z", IX1, -1, 0.2, 2.4, 1.3, 1.0, (accent, "canvas"), 0)
    picture(m, d, "z", IX1, -1, 12.0, F2 + 2.3, 1.6, 1.1, ("accent_red", "banner_gold"), 1)
    picture(m, d, "x", IZ0, 1, -11.0, F2 + 2.3, 1.4, 1.0, ("cushion_green", accent), 2)
    # The terrace under the awning: chairs at the tables, hanging baskets, planters along
    # its edge, lamps by the door.
    for x in (2.0, 7.0, 11.0):
        chair(m, d, x - 0.95, BZ0 - 2.2, 0, "+x")
        chair(m, d, x + 0.95, BZ0 - 2.2, 0, "-x")
    for i, x in enumerate((-11.0, -8.0, -1.0, 4.5, 9.0)):
        hanging_basket(m, d, x, 4.55, BZ0 - 3.0, 0.95, seed=i)
    planter_box(m, d, (-12.0, BZ0 - 4.1), (-7.9, BZ0 - 3.3), seed=0)
    planter_box(m, d, (4.9, BZ0 - 4.1), (8.9, BZ0 - 3.3), seed=2)
    for x in (-6.6, -2.2):
        sconce(m, d, "x", BZ0 - 0.2, -1, x, 3.1)
    # Outside: ivy, and tables under parasols on the roof.
    ivy(m, d, "z", BX1 + 0.2, 1, 9.0, 13.0, 0, 5.6, seed=10)
    ivy(m, d, "z", BX0 - 0.2, -1, 0.0, 4.6, 0, 5.2, seed=11)
    R = top + 0.35
    umbrella_table(m, d, -8.0, 3.0, R, accent)
    umbrella_table(m, d, -8.0, 10.0, R, accent)
    umbrella_table(m, d, 8.0, 10.0, R, accent)
    planter_box(m, d, (3.6, 0.0), (10.6, 1.2), y=R, seed=1)
    potted(m, d, -12.4, 6.4, R, 1.2)


def observatory_decor(m, b, accent, T, C, x0, x1):
    d = m.group("Decor", b, grouped=False)
    # The hall: screens on the desk, a chair, armchairs under the back window, star charts.
    for x in (-11.2, -9.7, -8.2):
        monitor(m, d, x, 1.05, 9.5, "-z")
    chair(m, d, -9.7, 8.4, 0, "+z")
    rug(m, d, (7.2, 9.6), (11.8, 13.0), kind="rug_blue")
    armchair(m, d, 8.5, 10.6, 0, "+z", "cushion_blue")
    armchair(m, d, 10.5, 10.6, 0, "+z", "cushion_blue")
    side_table(m, d, 9.5, 11.6)
    rng = __import__("random").Random(77)
    for x in (-4.0, 4.0):
        m.on_wall(d, "ChartFrame", "brass", "x", BZ0 + 0.2, 1, x - 1.6, x + 1.6, 1.3, 3.9, depth=0.04)
        m.on_wall(d, "Chart", "star_panel", "x", BZ0 + 0.2, 1, x - 1.5, x + 1.5, 1.4, 3.8, depth=0.03, lift=0.04)
        m.block(d, "ChartRing", "brass", (x + 0.3, 2.6, BZ0 + 0.285), (1.7, 0.012, 1.7), cols=LIE_Z, shape="tube", sides=20, inner=1.62, solid=False)
        m.block(d, "ChartRing", "brass", (x - 0.5, 2.3, BZ0 + 0.3), (0.9, 0.012, 0.9), cols=LIE_Z, shape="tube", sides=16, inner=0.84, solid=False)
        for k in range(12):
            u, v, s = x + rng.uniform(-1.35, 1.35), rng.uniform(1.55, 3.65), rng.choice((0.05, 0.07, 0.1))
            m.on_wall(d, "Star", "lamp", "x", BZ0 + 0.2, 1, u - s / 2, u + s / 2, v - s / 2, v + s / 2, depth=0.012, lift=0.075)
    floor_plant(m, d, 2.6, -0.6, 0, 0.9)
    floor_plant(m, d, -2.6, -0.6, 0, 0.9)
    floor_plant(m, d, 12.5, -0.5, 0, 1.0)
    potted(m, d, -12.6, 12.6, 0, 1.0)
    for x, z in ((-7.0, 3.0), (7.0, 3.0), (7.0, 9.0), (-3.0, 8.4)):
        ceiling_light(m, d, x, F2, z, 0.4)
    picture(m, d, "z", x1 - 0.2, -1, 1.5, 2.4, 1.5, 1.1, (accent, "banner_gold"), 0)
    # The terrace: a long planter down the west side, plants at the dome's door.
    planter_box(m, d, (x0 + 0.5, 2.6), (x0 + 1.5, 6.4), y=T, seed=3)
    potted(m, d, C[0] - 7.2, C[1] - 1.7, T, 0.9)
    potted(m, d, C[0] - 7.2, C[1] + 1.7, T, 0.9)
    potted(m, d, 12.4, 12.6, T, 1.1)
    shrub(m, d, -12.4, 0.0, T, 1.3)
    # Inside the dome: a control desk with screens against the east wall.
    counter(m, d, (C[0] + 3.6, C[1] - 1.4), (C[0] + 4.4, C[1] + 1.4), y=T, height=0.95, kind="equipment")
    monitor(m, d, C[0] + 4.1, T + 0.95, C[1] - 0.6, "-x")
    monitor(m, d, C[0] + 4.1, T + 0.95, C[1] + 0.6, "-x")
    stool(m, d, C[0] + 3.0, C[1], T)
    # Outside: lamps by the door, ivy.
    for x in (-2.5, 2.5):
        sconce(m, d, "x", BZ0 - 0.2, -1, x, 3.1)
    ivy(m, d, "x", BZ1 + 0.2, 1, -12.4, -6.0, 0, 5.3, seed=12)
    ivy(m, d, "z", x0 - 0.2, -1, 8.0, 13.0, 0, 5.2, seed=13)
    ivy(m, d, "z", x1 + 0.2, 1, 1.9, 4.7, 0, 5.0, seed=14)


BUILDINGS = {"Observatory": observatory, "Labs": labs, "LectureHall": lecture_hall, "Cafeteria": cafeteria, "Library": library}


# ---------------------------------------------------------------------------
# The event, and the bots' crossings

def event(m):
    lit = 'PackedStringArray("window_lit", "lamp")'
    m.node("Layout", ".", "layout", [
        ("up_count", "2"), ("hold_time", "60.0"), ("windup_time", "8.0"), ("move_time", "4.0"), ("down", fmt(DOWN)),
        ("tick_from", "Vector3(0, %s, 0)" % fmt(CLOCK_Y)),
        ("drift_turns", "PackedFloat32Array(-36, 36)"), ("close_in", "12.2"), ("far_out", "9.1"),
        ("far_heights", "PackedFloat32Array(7, -9)"), ("split_height", "8.0"),
        ("sun_direction", "Vector3(-0.93, 0.19, 0.31)"), ("sun_color", "Color(1, 0.5, 0.26, 1)"), ("sun_energy", "1.05"),
        ("ambient_color", "Color(0.66, 0.5, 0.62, 1)"), ("ambient_energy", "0.8"), ("fog_color", "Color(0.71, 0.49, 0.48, 1)"),
        ("lit_kinds", lit), ("lit_glow", "2.6"),
        ("flare_kinds", 'PackedStringArray("engine")'), ("flare_gain", "3.5"), ("doom_kinds", 'PackedStringArray("lamp")'),
        ("scraps", "360"), ("scrap_volume", "AABB(-70, -22, -70, 140, 56, 140)"),
    ], type_="Node")


def crossings(m, islands):
    """How bots cross the open sky (they all carry the grapple here: MapRoot.bots_grapple).
    From an island: stand at its tip, hook the nearest mast on the quad's rim, come down
    on the lawn beside it. To an island: stand on the quad's rim facing it (wherever it
    is just now), hook the tall mast on its tip, come down on its deck. People need no
    telling."""
    for name, _deg, _a, _r in ISLANDS:
        g = islands[name]
        m.node("ToQuad", g, "link", [("transform", xform(IDENTITY, (0, 0, ZT + 1.6))), ("how", "0"),
                                     ("hook_group", '&"quad_masts"'), ("leaves", "true")], type_="Marker3D")
        m.node("FromQuad", g, "link", [("transform", xform(IDENTITY, (0.6, 0, ZT + 5.0))), ("how", "0"),
                                       ("hook", 'NodePath("../ArrivalHook")'),
                                       ("round_from", 'NodePath("../../Quad/Centre")'), ("round_radius", fmt(QUAD_R - 1.7))], type_="Marker3D")


def build(path):
    m = CirrusMap("Cirrus", PAL,
                  {"lines": ["ambient_light_source = 2", "ambient_light_color = Color(1, 0.9, 0.74, 1)",
                             "ambient_light_energy = 0.82", "reflected_light_source = 1", "tonemap_mode = 2",
                             "tonemap_white = 3.2", "glow_enabled = true", "glow_intensity = 0.7", "glow_bloom = 0.06",
                             # (fog only below the map: what a falling island, or a falling player, vanishes into)
                             "fog_enabled = true", "fog_light_color = Color(0.9, 0.81, 0.73, 1)", "fog_sun_scatter = 0.0",
                             "fog_density = 0.0", "fog_sky_affect = 0.0", "fog_height = -34.0", "fog_height_density = 0.12"]},
                  (36.0, 236.0, (1.0, 0.88, 0.66), 1.3),
                  {"face_shade": "Vector3(0.9, 0.8, 0.66)", "kill_height": "-45.0",
                   "bounds": "Rect2(-100, -100, 200, 200)", "swing_point": "Vector3(0, 24, 0)", "winding_floors": "true",
                   "bots_grapple": "true"})
    quad(m)
    stones(m)
    islands = {}
    for name, deg, accent, roof_kind in ISLANDS:
        islands[name] = island(m, name, deg, accent, roof_kind, BUILDINGS[name])
    # Stepping-stone pickups (the stones never move).
    for (name, deg, _a, _r), weapon in zip(ISLANDS, ("crossbow", None, "grenade_launcher", None, "lever_action")):
        if weapon:
            m.weapon(polar(STONE_R - 0.9, deg + 18.0, 0.6), weapon)
    event(m)
    crossings(m, islands)
    m.write(path)
    write_palette(path.replace("game/maps/", "game/maps/palettes/").replace(".tscn", ".tres"))
