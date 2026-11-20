"""Halcyon: the inside of a colony ship (the biggest arena: 140 x 140 m, up to 16 players).

    python3 tools/arena/build_arena_maps.py halcyon

writes game/maps/halcyon.tscn and game/maps/palettes/halcyon.tres FROM SCRATCH. The scene
is an ordinary map scene and is what people edit afterwards (in the Godot editor), so
running this again OVERWRITES ANY HAND EDITS: only do it to rebuild the whole map on purpose.

Layout: a round Control Room in the middle (glass dome above, a ring of glass in the
floor, the terminal on a raised dais) with four spoke corridors out to four tall rooms,
Hangar (north), Hydroponics (east), Engineering (south) and Cargo Bay (west), and an
outer ring corridor joining the rooms through three corner sections and the Cryo/Habitat
zone (south-west). A lower maintenance deck runs under the spokes and the ring, with a
round passage under the Control Room and two stairwells up into it.

Heights: lower deck -6 m, main deck 0 m, corridor ceilings 6 m, the tall rooms run from
-6 m up to 26-30 m with decks about every 7 m, dome apex 15 m. The reactor pit in
Engineering drops below the kill height (-16 m). The centrifuge ring (a MapSpinner,
never solid) turns round the hull outside; the MapTerminal on the dais starts the
GravityEvent, which slows it.

Surfaces: the palette's Surface list (SURFACE below) has the surface shader draw panel
seams, tiles, grating, vent slats and hazard stripes on a kind, with no blocks. On top
of that each place has a "Details" group of drawn-only pieces (ribs, vents, displays,
conduits, beams, floor lines, grates, stencils): never solid, never more than 0.3 m
off a wall or floor.

Angles in this file are measured the way a node's yaw is: 0 = south (+z), 90 = east,
180 = north, 270 = west.
"""
import math
from arena_builder import Map, palette, yaw_cols, xform, fmt, vec, color, norm, cross, facing, IDENTITY

PAL = "res://game/maps/palettes/halcyon.tres"
SKY = "res://game/maps/sky/halcyon_sky.gdshader"

COLORS = {
    # the ship
    "hull": (0.84, 0.86, 0.89), "hull_white": (0.94, 0.95, 0.97), "hull_dark": (0.4, 0.42, 0.48),
    "hull_ext": (0.33, 0.37, 0.46),
    "trim": (0.15, 0.16, 0.19), "floor": (0.52, 0.54, 0.59), "floor_dark": (0.3, 0.32, 0.36),
    "stair": (0.46, 0.48, 0.53), "catwalk": (0.38, 0.4, 0.46), "rail": (0.22, 0.23, 0.27),
    "girder": (0.32, 0.34, 0.4), "pipe": (0.55, 0.47, 0.36), "pipe_blue": (0.3, 0.42, 0.55),
    "light": (1.0, 1.0, 1.0), "light_dim": (0.8, 0.85, 1.0),
    "glass_hull": (0.62, 0.82, 1.0, 0.14), "glass_pane": (0.7, 0.92, 1.0, 0.3),
    # one accent per place
    "accent_white": (0.85, 0.92, 1.0), "accent_cyan": (0.15, 0.85, 1.0), "accent_green": (0.3, 1.0, 0.42),
    "accent_orange": (1.0, 0.4, 0.06), "accent_yellow": (1.0, 0.84, 0.16), "accent_ice": (0.68, 0.87, 1.0),
    # control room
    "dais": (0.92, 0.93, 0.96), "console": (0.18, 0.2, 0.25), "holo": (0.3, 0.6, 1.0),
    # hangar
    "shuttle": (0.92, 0.93, 0.95), "shuttle_dark": (0.2, 0.22, 0.27), "engine_glow": (0.5, 0.85, 1.0),
    "crate": (0.58, 0.6, 0.65), "crate_dark": (0.36, 0.38, 0.44),
    # hydroponics
    "planter": (0.82, 0.84, 0.83), "soil": (0.3, 0.22, 0.16), "plant": (0.25, 0.62, 0.28),
    "plant_dark": (0.15, 0.44, 0.2), "grow_light": (1.0, 0.72, 0.95), "tank": (0.62, 0.72, 0.74),
    # engineering
    "reactor": (1.0, 0.42, 0.08), "reactor_core": (1.0, 0.7, 0.3), "pit_glow": (1.0, 0.3, 0.04),
    "machine": (0.3, 0.3, 0.34),
    # cargo
    "container_yellow": (0.9, 0.72, 0.18), "container_blue": (0.2, 0.42, 0.66), "container_teal": (0.16, 0.52, 0.5),
    "container_grey": (0.56, 0.58, 0.6), "container_orange": (0.86, 0.48, 0.2), "crane": (0.95, 0.76, 0.12),
    # cryo and the ring's side rooms
    "pod": (0.86, 0.89, 0.93), "pod_glow": (0.4, 0.72, 1.0), "bunk": (0.3, 0.36, 0.5), "table": (0.8, 0.81, 0.85),
    "seat": (0.25, 0.44, 0.68), "sofa": (0.24, 0.4, 0.6), "medbed": (0.93, 0.95, 0.96), "med_green": (0.25, 0.85, 0.55),
    # wall and floor details
    "rib": (0.36, 0.38, 0.44), "vent": (0.24, 0.25, 0.3), "grate": (0.3, 0.31, 0.36), "hazard": (0.96, 0.76, 0.1),
    "screen": (0.07, 0.09, 0.13), "cable": (0.2, 0.2, 0.25),
    # the centrifuge
    "ring": (0.72, 0.75, 0.82), "ring_dark": (0.28, 0.31, 0.38), "ring_light": (0.8, 0.94, 1.0),
}
GLOW = {
    "light": 1.5, "light_dim": 0.7, "accent_white": 1.4, "accent_cyan": 2.0, "accent_green": 1.6, "accent_orange": 1.5,
    "accent_yellow": 1.5, "accent_ice": 1.6, "holo": 1.8, "engine_glow": 2.5, "grow_light": 1.8, "reactor": 1.1,
    "reactor_core": 1.8, "pit_glow": 1.6, "pod_glow": 0.9, "med_green": 1.6, "ring_light": 2.6,
}
# Patterns the surface shader draws on a kind (MapScenery.SURFACES): no blocks needed.
SURFACE = {
    "hull": "panels", "hull_ext": "panels", "hull_white": "panels_plain", "hull_dark": "plates",
    "floor": "tiles", "floor_dark": "plates", "catwalk": "grating", "stair": "treads", "shuttle": "panels_plain",
    "container_yellow": "corrugated", "container_blue": "corrugated", "container_teal": "corrugated",
    "container_grey": "corrugated", "container_orange": "corrugated",
    "vent": "slats", "grate": "grating", "hazard": "hazard",
}
BREAKABLE = {"glass_pane": 25}   # glass_hull (dome, floor glass, hull windows) is not here: it never breaks

LOW = -6.0          # lower deck floor
H = 6.0             # main deck ceiling
HUB_R = 15.0        # control room, inside the wall
BAND_R = 18.5       # how far the round deck under and round the control room reaches
ROOM = 32.0         # the four rooms start this far from the middle
HULL = 66.0         # inside face of the hull

T_HANGAR = (0.9, 0.97, 1.0)
T_HYDRO = (0.91, 1.0, 0.92)
T_ENG = (1.0, 0.95, 0.88)
T_CARGO = (1.0, 0.98, 0.87)
T_CRYO = (0.9, 0.95, 1.0)


def adiff(a, b):
    """How far apart two angles are, in degrees (0..180)."""
    return abs((a - b + 180.0) % 360.0 - 180.0)


def polar(r, deg, y=0.0, c=(0.0, 0.0)):
    th = math.radians(deg)
    return (c[0] + r * math.sin(th), y, c[1] + r * math.cos(th))


class HalcyonMap(Map):
    """arena_builder's Map with what only this map needs: nodes with other scripts (the
    terminal, the event, the spinner), a sky made by a shader, and a sun with no shadows
    (inside a ship it is only a soft fill light)."""

    EXTRA = {
        "spinner": "res://game/arena/map_spinner.gd",
        "terminal": "res://game/arena/map_terminal.gd",
        "gravity": "res://game/arena/gravity_event.gd",
    }

    def node(self, name, parent, script, props, type_="Node3D"):
        return self._add(name, type_, parent, props, script, False)

    def sign(self, text, pos, yaw=0.0, size=96, col=(1, 1, 1, 1), parent="Signs", pixel=0.01, outline=True):
        # ("CARGO BAY 2" and the second "CARGO BAY" sign would both be named Sign_CargoBay2.)
        before = len(self.nodes)
        Map.sign(self, text, pos, yaw, size, col, parent, pixel, outline)
        node = self.nodes[before]
        if text[-1:].isdigit():
            node.name += "_"

    def flat_sign(self, text, pos, cols, size=64, pixel=0.012, col=(1, 1, 1, 0.5), parent="Signs"):
        """A Label3D lying on a floor (a stencil): cols are its right, top and facing axes."""
        props = [("transform", xform(cols, pos)), ("pixel_size", fmt(pixel)), ("modulate", color(col)),
                 ("outline_size", "0"), ("shaded", "true"), ("text", '"%s"' % text), ("font_size", str(size))]   # (shaded: it takes the room's light, so it goes blue with the rest in low gravity)
        name = "Paint_" + "".join(ch for ch in text.title() if ch.isalnum())[:24]
        self._add(name + ("_" if text[-1:].isdigit() else ""), "Label3D", parent, props, None, False)

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
        out += ["", '[sub_resource type="ShaderMaterial" id="ShaderMaterial_sky"]', 'shader = ExtResource("sky")', "",
                '[sub_resource type="Sky" id="Sky_1"]', 'sky_material = SubResource("ShaderMaterial_sky")', "",
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
                "light_color = %s" % color(col), "light_energy = %s" % fmt(energy), "light_specular = 0.2", ""]
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
        print("wrote %s: %d nodes (%d blocks), %d spawns, %d weapon pickups" % (path, len(self.nodes), blocks, self.spawn_count, self.weapon_count))


class Frame:
    """Builds in one set of coordinates and places the result turned or mirrored: the
    four spokes are one spoke turned, three corners of the ring are one corner mirrored.
    (x, z) -> (a x + b z, c x + d z), each of a, b, c, d being 0, 1 or -1."""

    def __init__(self, m, mat=(1, 0, 0, 1)):
        self.m, self.mat = m, mat

    def pt(self, p):
        a, b, c, d = self.mat
        return (a * p[0] + b * p[2], p[1], c * p[0] + d * p[2])

    def yaw(self, fx, fz):
        """The yaw of something that faces (fx, fz) in this frame."""
        w = self.pt((fx, 0, fz))
        return math.atan2(w[0], w[2])

    def box(self, g, name, kind, lo, hi, **kw):
        p, q = self.pt(lo), self.pt(hi)
        return self.m.box(g, name, kind, tuple(map(min, p, q)), tuple(map(max, p, q)), **kw)

    def strip(self, g, name, kind, lo, hi, **kw):
        """A drawn-only box: light strips, paint, trim."""
        return self.box(g, name, kind, lo, hi, solid=False, **kw)

    def slab(self, g, name, kind, a, b, width, **kw):
        return self.m.slab(g, name, kind, self.pt(a), self.pt(b), width, **kw)

    def wall(self, g, name, kind, axis, line, a, b, y0, y1, t=1.0, holes=(), **kw):
        """A wall along `axis` ("x" or "z") centred on `line`, from a to b along it, with
        openings: holes are (from, to, bottom, top), in the same coordinates."""
        def piece(u0, u1, v0, v1, label):
            if u1 - u0 < 0.01 or v1 - v0 < 0.01:
                return
            if axis == "x":
                self.box(g, label, kind, (u0, v0, line - t / 2), (u1, v1, line + t / 2), **kw)
            else:
                self.box(g, label, kind, (line - t / 2, v0, u0), (line + t / 2, v1, u1), **kw)
        u = a
        for h0, h1, hb, ht in sorted(holes):
            piece(u, h0, y0, y1, name)
            piece(h0, h1, y0, hb, name + "Sill")
            piece(h0, h1, ht, y1, name + "Lintel")
            u = h1
        piece(u, b, y0, y1, name)

    def rail(self, g, axis, line, a, b, y, gaps=(), kind="rail"):
        self.wall(g, "Rail", kind, axis, line, a, b, y, y + 1.1, 0.12, [(g0, g1, y, y + 1.1) for g0, g1 in gaps])
        for g0, g1 in gaps:   # hazard stripes on the edge wherever a railing leaves a way off
            if axis == "x":
                self.strip(g, "GapEdge", "hazard", (g0, y, line - 0.16), (g1, y + 0.04, line + 0.16))
            else:
                self.strip(g, "GapEdge", "hazard", (line - 0.16, y, g0), (line + 0.16, y + 0.04, g1))

    def on_wall(self, g, name, kind, axis, face, out, a, b, y0, y1, depth=0.12, lift=0.0, **kw):
        """A drawn-only box on a wall. The wall runs along `axis` ("x" or "z") with its face
        at `face` on the other axis, looking toward `out` (+1 or -1). The box covers a..b
        along the wall and y0..y1, and stands `depth` off it (starting `lift` off it)."""
        n0, n1 = sorted((face + out * lift, face + out * (lift + depth)))
        if axis == "x":
            self.strip(g, name, kind, (a, y0, n0), (b, y1, n1), **kw)
        else:
            self.strip(g, name, kind, (n0, y0, a), (n1, y1, b), **kw)

    def floor_label(self, text, pos, up, **kw):
        """A stencil painted on the floor, read by someone walking the way `up` (x, z) points."""
        u = self.pt((up[0], 0, up[1]))
        Y = norm((u[0], 0.0, u[2]))
        self.m.flat_sign(text, self.pt(pos), ((-Y[2], 0.0, Y[0]), Y, (0, 1, 0)), **kw)

    def way_sign(self, text, pos, face, toward, **kw):
        """A sign on a wall that points the way: `face` (x, z) is the way it looks, `toward`
        the way to go. The arrows come out on the right side in a mirrored frame too."""
        f, t = self.pt((face[0], 0, face[1])), self.pt((toward[0], 0, toward[1]))
        right = (f[2], -f[0])   # the right hand of someone reading it
        self.sign(text + " >>" if t[0] * right[0] + t[2] * right[1] > 0 else "<< " + text, pos, face, **kw)

    def chevron(self, g, kind, tip, toward, y, size=0.9, width=0.16):
        """A chevron painted on the floor, its point at `tip` (x, z), pointing `toward` (x, z)."""
        T, d = self.pt((tip[0], y, tip[1])), self.pt((toward[0], 0, toward[1]))
        dx, dz = norm((d[0], d[2]))
        for turn in (-1, 1):
            a = math.radians(138.0) * turn
            bx, bz = dx * math.cos(a) - dz * math.sin(a), dx * math.sin(a) + dz * math.cos(a)
            self.m.block(g, "Chevron", kind, (T[0] + bx * size / 2, y + 0.013, T[2] + bz * size / 2), (width, 0.026, size),
                         cols=yaw_cols(math.atan2(bx, bz)), solid=False)

    def deck(self, g, name, kind, x0, x1, z0, z1, top, thick=0.5, holes=(), **kw):
        """A flat slab with rectangular holes cut in it: holes are (x0, x1, z0, z1)."""
        rects = [(x0, x1, z0, z1)]
        for hx0, hx1, hz0, hz1 in holes:
            nxt = []
            for a0, a1, b0, b1 in rects:
                if hx1 <= a0 or hx0 >= a1 or hz1 <= b0 or hz0 >= b1:
                    nxt.append((a0, a1, b0, b1))
                    continue
                if hx0 > a0:
                    nxt.append((a0, hx0, b0, b1))
                if hx1 < a1:
                    nxt.append((hx1, a1, b0, b1))
                c0, c1 = max(a0, hx0), min(a1, hx1)
                if hz0 > b0:
                    nxt.append((c0, c1, b0, hz0))
                if hz1 < b1:
                    nxt.append((c0, c1, hz1, b1))
            rects = nxt
        for r in rects:
            self.box(g, name, kind, (r[0], top - thick, r[2]), (r[1], top, r[3]), **kw)

    def sign(self, text, pos, face, **kw):
        self.m.sign(text, self.pt(pos), yaw=self.yaw(*face), **kw)

    def spawn(self, pos, toward):
        w = self.pt((toward[0], 0, toward[1]))
        self.m.spawn(self.pt(pos), (w[0], w[2]))

    def weapon(self, pos, weapon):
        self.m.weapon(self.pt(pos), weapon)


TURN = [(1, 0, 0, 1), (0, -1, 1, 0), (-1, 0, 0, -1), (0, 1, -1, 0)]   # north, east, south, west
MIRROR_X = (-1, 0, 0, 1)
MIRROR_Z = (1, 0, 0, -1)


def ring(m, g, name, kind, r0, r1, y0, y1, n, c=(0.0, 0.0), skip=None, **kw):
    """A ring (or a round wall) made of n straight boxes: the inside faces touch a circle
    of radius r0, the outside ones one of radius r1. skip(centre angle in degrees) leaves
    a segment out (doorways)."""
    w = 2.0 * r1 * math.tan(math.pi / n) + 0.02
    for i in range(n):
        deg = 360.0 * (i + 0.5) / n
        if skip and skip(deg):
            continue
        m.block(g, name, kind, polar((r0 + r1) / 2.0, deg, (y0 + y1) / 2.0, c), (w, y1 - y0, r1 - r0),
                cols=yaw_cols(math.radians(deg)), **kw)


def hoop(m, g, name, kind, r, width, y0, y1, c=(0.0, 0.0), sides=36):
    """A drawn-only band round a circle (trim, light strips)."""
    m.block(g, name, kind, (c[0], (y0 + y1) / 2.0, c[1]), (2 * r, y1 - y0, 2 * r), shape="tube", inner=2 * (r - width),
            sides=sides, solid=False)


def build(path):
    m = HalcyonMap("Halcyon", PAL,
                   {"lines": ["ambient_light_source = 2", "ambient_light_color = Color(0.84, 0.9, 1, 1)",
                              "ambient_light_energy = 1.0", "reflected_light_source = 1", "tonemap_mode = 2",
                              "tonemap_white = 2.8", "ssao_enabled = true", "glow_enabled = true", "glow_intensity = 0.9"]},
                   (72, 200, (0.86, 0.92, 1.0), 0.42),
                   {"face_shade": "Vector3(0.92, 0.83, 0.64)", "kill_height": "-16.0",
                    "bounds": "Rect2(-70, -70, 140, 140)", "swing_point": "Vector3(0, 14.6, 0)"})
    control_room(m)
    stairwell(m, "StairwellNE", 135.0)
    stairwell(m, "StairwellSW", 315.0)
    f = m.folder("Spokes")
    spoke(m, f, 0, "SpokeNorth", "HANGAR", "accent_cyan")
    spoke(m, f, 1, "SpokeEast", "HYDROPONICS", "accent_green")
    spoke(m, f, 2, "SpokeSouth", "ENGINEERING", "accent_orange")
    spoke(m, f, 3, "SpokeWest", "CARGO BAY", "accent_yellow")
    hangar(m)
    engineering(m)
    cargo(m)
    hydroponics(m)
    f = m.folder("OuterRing")
    corner(m, f, "RingNE", (1, 0, 0, 1), "lounge", 31.0, "accent_cyan", "accent_green", "HANGAR", "HYDROPONICS")
    corner(m, f, "RingNW", MIRROR_X, "storage", 31.0, "accent_cyan", "accent_yellow", "HANGAR", "CARGO BAY")
    corner(m, f, "RingSE", MIRROR_Z, "medbay", 25.0, "accent_orange", "accent_green", "ENGINEERING", "HYDROPONICS")
    cryo(m)
    centrifuge(m)
    event(m)
    spawns(m)
    pickups(m)
    m.write(path)
    palette(path.replace("game/maps/", "game/maps/palettes/").replace(".tscn", ".tres"), COLORS, GLOW, BREAKABLE, roughness=0.8, surface=SURFACE)


# ---------------------------------------------------------------------------
# The hub

def hub_door(deg):
    """The doorway a piece of the control room wall at this angle is part of, if any."""
    for s in (0, 90, 180, 270):
        if adiff(deg, s) <= 20:
            return "spoke"
    for s in (135, 315):
        if adiff(deg, s) <= 15:
            return "stair"
    return None


def lower_gap(deg):
    """Openings in the outer wall of the round passage under the control room: the four
    lower spokes, and the foot of each stairwell's ramp."""
    for s in (0, 90, 180, 270):
        if adiff(deg, s) <= 10:
            return True
    return any(adiff(deg, s) < 1 for s in (125, 135, 305, 315))


def control_room(m):
    f = m.folder("ControlRoom")
    g = m.group("Floor", f)
    m.cyl(g, "Column", "hull", (0, -10, 0), 12.0, 10.0, sides=36)   # holds the dais up through the shaft; its top is the floor
    ring(m, g, "FloorGlass", "glass_hull", 5.8, 10.3, -0.31, -0.01, 36, unbreakable=True)
    ring(m, g, "Deck", "floor", 10.0, BAND_R, -0.5, 0.0, 36)
    hoop(m, g, "GlassRim", "trim", 10.25, 0.35, 0.0, 0.03)
    hoop(m, g, "GlassRim", "trim", 6.15, 0.35, 0.0, 0.03)
    hoop(m, g, "FloorLight", "accent_white", 14.9, 0.3, 0.0, 0.04)

    g = m.group("Wall", f)
    ring(m, g, "Wall", "hull_white", HUB_R, HUB_R + 0.8, 0.0, H, 36, skip=hub_door)
    ring(m, g, "Lintel", "trim", HUB_R, HUB_R + 0.8, 5.2, H, 36, skip=lambda d: not hub_door(d))
    # The wall, the lintels and the spokes' jambs all end at one height: one dark cap lies on
    # top of them (cut to the wall's own outline, so none of it shows under a ceiling).
    k = math.cos(math.pi / 36)
    hoop(m, g, "WallCap", "trim", (HUB_R + 0.8) / k, 0.8 / k, H, H + 0.03)
    hoop(m, g, "WallLight", "accent_white", 14.98, 0.12, 5.35, 5.55)
    ring(m, g, "WallTrim", "trim", HUB_R - 0.1, HUB_R, 1.0, 1.12, 36, skip=hub_door, solid=False)   # (pieces, so it stops at the doorways)
    for deg, text in ((0, "ENGINEERING"), (90, "HYDROPONICS"), (180, "HANGAR"), (270, "CARGO BAY"), (135, "DECK 2"), (315, "DECK 2")):
        m.sign(text, polar(14.84, deg, 5.8), yaw=math.radians(deg + 180), size=40, pixel=0.008)

    # The dome: a cap of a 17 m sphere, in rings of flat glass panes, closed by a round pane.
    g = m.group("Dome", f)
    centre, R = (0.0, -2.0, 0.0), 17.15
    lats = [math.degrees(math.asin(8.0 / 17.0)), 42.0, 56.0, 70.0, 82.0]
    counts = [18, 18, 12, 12]
    for k in range(4):
        la, lb = math.radians(lats[k]), math.radians(lats[k + 1])
        lm, n = (la + lb) / 2.0, counts[k]
        length = 2.0 * R * math.sin((lb - la) / 2.0) + 0.12
        width = 2.0 * R * math.cos(la) * math.tan(math.pi / n) + 0.1
        mid = R * math.cos((lb - la) / 2.0)
        for i in range(n):
            th = 2.0 * math.pi * (i + 0.5) / n
            out = (math.cos(lm) * math.sin(th), math.sin(lm), math.cos(lm) * math.cos(th))
            X = (math.cos(th), 0.0, -math.sin(th))
            m.block(g, "Pane", "glass_hull", tuple(c + mid * o for c, o in zip(centre, out)), (width, 0.3, length),
                    cols=(X, out, cross(X, out)), unbreakable=True)
        hoop(m, g, "Rib", "trim", 17.0 * math.cos(la) + 0.2, 0.4, -2.0 + 17.0 * math.sin(la) - 0.12, -2.0 + 17.0 * math.sin(la) + 0.12)
    top = math.radians(lats[4])
    m.cyl(g, "Cap", "glass_hull", (0, -2.0 + 17.0 * math.sin(top) - 0.05, 0), 2 * 17.0 * math.cos(top) + 0.8, 0.3, sides=12, unbreakable=True)
    hoop(m, g, "Rib", "trim", 17.0 * math.cos(top) + 0.3, 0.3, -2.0 + 17.0 * math.sin(top) - 0.15, -2.0 + 17.0 * math.sin(top) + 0.1, sides=12)

    # The dais: two round steps anyone can hop up, and a ramp toward each spoke.
    g = m.group("Dais", f)
    m.cyl(g, "Step", "trim", (0, 0, 0), 10.4, 0.6, sides=24)
    m.cyl(g, "Top", "dais", (0, 0.6, 0), 8.0, 0.6, sides=24)
    hoop(m, g, "TopLight", "accent_white", 3.95, 0.25, 1.2, 1.23, sides=24)
    for deg in (0, 90, 180, 270):
        m.slab(g, "Ramp", "floor", polar(7.4, deg, 0.0), polar(3.8, deg, 1.2), 2.6, thick=0.3)
    g = m.group("Terminal", f)
    m.box(g, "Console", "console", (-0.45, 1.2, -0.45), (0.45, 2.25, 0.45))
    m.box(g, "ConsoleTop", "trim", (-0.55, 2.25, -0.55), (0.55, 2.31, 0.55), solid=False)
    for s in (-1, 1):
        m.box(g, "ConsoleLight", "holo", (-0.47, 1.5, s * 0.46 - 0.01), (0.47, 1.6, s * 0.46 + 0.01), solid=False)
        m.box(g, "ConsoleLight", "holo", (s * 0.46 - 0.01, 1.5, -0.47), (s * 0.46 + 0.01, 1.6, 0.47), solid=False)
    m.node("MapTerminal", g, "terminal", [("transform", xform(IDENTITY, (0, 1.2, 0))), ("event", 'NodePath("../../../LowGravity")')])

    # Details: a post each side of every doorway, a line of each room's colour on the floor
    # toward its spoke with its name stencilled by the door, and displays and vents on
    # the wall between the doors.
    g = m.group("Details", f)
    I = Frame(m)
    for deg, accent, text in ((0, "accent_orange", "ENGINEERING"), (90, "accent_green", "HYDROPONICS"),
                              (180, "accent_cyan", "HANGAR"), (270, "accent_yellow", "CARGO BAY")):
        m.block(g, "GuideLine", accent, polar(11.7, deg, 0.012), (0.18, 0.024, 2.0), cols=yaw_cols(math.radians(deg)), solid=False)
        I.floor_label(text, polar(13.5, deg, 0.06), (math.sin(math.radians(deg)), math.cos(math.radians(deg))), size=56)
        for side in (-21.2, 21.2):
            m.block(g, "DoorPost", "rib", polar(14.92, deg + side, 2.6), (0.5, 5.2, 0.16), cols=yaw_cols(math.radians(deg + side)), solid=False)
    for deg in (135, 315):
        I.floor_label("DECK 2", polar(13.5, deg, 0.06), (math.sin(math.radians(deg)), math.cos(math.radians(deg))), size=56)
        for side in (-16.2, 16.2):
            m.block(g, "DoorPost", "rib", polar(14.92, deg + side, 2.6), (0.5, 5.2, 0.16), cols=yaw_cols(math.radians(deg + side)), solid=False)
    for deg in (35, 45, 55, 215, 225, 235):   # (the middle of a wall piece, so they sit flat on it)
        cols = yaw_cols(math.radians(deg))
        m.block(g, "ScreenFrame", "rib", polar(14.95, deg, 2.95), (2.3, 1.7, 0.08), cols=cols, solid=False)
        m.block(g, "Screen", "screen", polar(14.9, deg, 2.95), (2.06, 1.46, 0.04), cols=cols, solid=False)
        m.block(g, "ScreenBar", "holo", polar(14.87, deg, 3.3 if deg % 20 == 5 else 2.6), (1.5, 0.14, 0.02), cols=cols, solid=False)
    for deg in (115, 155, 295, 335):
        cols = yaw_cols(math.radians(deg))
        m.block(g, "Vent", "vent", polar(14.96, deg, 4.3), (1.8, 0.6, 0.06), cols=cols, solid=False)
        m.block(g, "Vent", "vent", polar(14.96, deg, 0.55), (1.8, 0.5, 0.06), cols=cols, solid=False)

    # The lower deck goes round the shaft under the floor glass, never under it.
    g = m.group("LowerRing", f)
    ring(m, g, "Floor", "floor_dark", 10.6, 18.8, LOW - 0.5, LOW, 36)
    ring(m, g, "ShaftWall", "hull", 10.2, 11.0, -10.0, -0.5, 36)
    ring(m, g, "OuterWall", "hull_dark", BAND_R, BAND_R + 0.8, LOW - 0.5, -0.5, 36, skip=lower_gap)
    for y in (-2.5, -5.5, -8.5):
        hoop(m, g, "ShaftLight", "accent_white", 10.2, 0.15, y, y + 0.2)
        hoop(m, g, "ColumnTrim", "trim", 6.12, 0.12, y, y + 0.25)
    hoop(m, g, "Pipe", "pipe", 18.45, 0.35, -0.86, -0.5)   # under the ceiling, so it passes over the openings
    hoop(m, g, "Pipe", "pipe_blue", 11.5, 0.3, -1.3, -1.0)
    ring(m, g, "LowLight", "light_dim", BAND_R - 0.06, BAND_R, -3.2, -3.0, 36, skip=lower_gap, solid=False)   # (pieces: none across an opening)
    hoop(m, g, "LowLight", "light_dim", 11.1, 0.06, -3.2, -3.0)
    hoop(m, g, "Grate", "grate", 15.4, 1.2, LOW, LOW + 0.012)
    hoop(m, g, "Cable", "cable", 15.1, 0.5, -0.72, -0.5)
    for deg in (35, 55, 105, 155, 215, 235, 285, 335):
        m.block(g, "Rib", "rib", polar(BAND_R - 0.06, deg, (LOW - 0.5) / 2.0), (0.35, 5.5, 0.14), cols=yaw_cols(math.radians(deg)), solid=False)


def stairwell(m, name, deg):
    """A stairwell from the lower deck up to a doorway of the control room, between two
    spokes. Built in its own frame: -z runs outward from the middle, +x to the right of
    someone walking out. From the door a lobby runs out, turns back on itself and a ramp
    comes down toward the middle, onto the round passage under the control room. The
    lobby's right-hand side is open above the foot of the ramp: a quick way down."""
    g = m.group(name, at=(0, 0, 0), yaw=math.radians(deg - 180.0))
    m.box(g, "Lobby", "floor", (-4, -0.5, -28), (0, 0, -18.3))
    m.box(g, "Landing", "floor", (-4, -0.5, -32.5), (4, 0, -28))
    m.slab(g, "Ramp", "stair", (2, 0, -28), (2, LOW, -18.5), 4.0, thick=0.4)
    m.box(g, "Foot", "floor_dark", (0, LOW - 0.5, -18.7), (4, LOW, -16.5))
    m.box(g, "Wall", "hull", (-4.6, 0, -33.1), (-4, H, -15.3))
    m.box(g, "Wall", "hull", (4, LOW - 0.5, -33.1), (5, H, -18.5))
    m.box(g, "Wall", "hull", (4, 0, -18.5), (5, H, -15.3))
    m.box(g, "Wall", "hull", (-4.6, -0.5, -33.1), (5, H, -32.5))
    m.box(g, "Under", "hull_dark", (-0.3, LOW - 0.5, -28), (0, -0.5, -18.5))
    m.box(g, "Under", "hull_dark", (-4.6, LOW - 0.5, -19.3), (0, -0.5, -18.5))
    m.box(g, "Ceiling", "hull", (-4.6, H, -33.1), (5, H + 0.5, -15.5))
    m.box(g, "Rail", "rail", (-0.06, 0, -28), (0.06, 1.1, -22.5))
    m.box(g, "Light", "light", (-3, H - 0.08, -30.5), (3, H, -29.5), solid=False)
    m.box(g, "Light", "light", (-3, H - 0.08, -22), (3, H, -21), solid=False)
    m.box(g, "Strip", "accent_white", (-4.02, 2.0, -32), (-3.96, 2.2, -16.5), solid=False)
    m.box(g, "Strip", "accent_white", (3.96, 2.0, -32), (4.02, 2.2, -19), solid=False)
    # Details: ribs up the walls, a vent, hazard stripes where the lobby's side is open
    # and across the head of the ramp, and the deck numbers on the floor.
    for z in (-30.5, -25.0, -20.0):
        m.box(g, "Rib", "rib", (-4.0, 0, z - 0.2), (-3.86, H, z + 0.2), solid=False)
    for z in (-30.5, -24.0):
        m.box(g, "Rib", "rib", (3.86, 0, z - 0.2), (4.0, H, z + 0.2), solid=False)
    m.box(g, "Vent", "vent", (-2.9, 4.2, -32.5), (-1.1, 4.8, -32.44), solid=False)
    m.box(g, "Vent", "vent", (1.1, 0.55, -32.5), (2.9, 1.05, -32.44), solid=False)
    m.box(g, "EdgeHazard", "hazard", (-0.4, 0, -22.5), (0.0, 0.04, -18.5), solid=False)
    m.box(g, "RampHazard", "hazard", (0.1, 0, -28.5), (3.9, 0.04, -28.05), solid=False)
    m.flat_sign("DECK 2", (2.0, 0.06, -29.6), ((-1, 0, 0), (0, 0, 1), (0, 1, 0)), size=56, parent=g)
    m.flat_sign("DECK 1", (-2.0, 0.06, -24.0), ((-1, 0, 0), (0, 0, 1), (0, 1, 0)), size=56, parent=g)


def spoke(m, f, k, name, room, accent):
    """A spoke corridor (built as the north one) with the lower deck's spoke under it."""
    F = Frame(m, TURN[k])
    g = m.group(name, f)
    hole = (-1.5, 1.5, -28.5, -25.5)   # a grated drop hole down to the lower deck
    F.deck(g, "Floor", "floor", -5.8, 5.8, -32.6, -14.0, 0.0, holes=[hole])
    F.box(g, "Ceiling", "hull", (-5.8, H, -31.9), (5.8, H + 0.5, -15.2))   # (ends inside the room's wall, not flush with its face)
    for s in (-1, 1):
        F.box(g, "Wall", "hull", (s * 5.0, 0, -31.9), (s * 5.8, H, -13.9))
        F.strip(g, "Strip", accent, (s * 4.96, 2.0, -31.0), (s * 5.02, 2.22, -15.5))
        F.strip(g, "FloorTrim", "trim", (s * 4.55, 0, -31.0), (s * 5.0, 0.02, -15.5))
        F.box(g, "LowerWall", "hull_dark", (s * 3.0, LOW - 0.5, -31.0), (s * 3.6, -0.5, -18.2))
        F.strip(g, "Pipe", "pipe" if s < 0 else "pipe_blue", (s * 2.98, -1.7, -31.0), (s * 2.66, -1.38, -18.6))
        F.strip(g, "LowLight", "light_dim", (s * 2.99, -3.2, -30.0), (s * 2.93, -3.0, -19.5))
    F.strip(g, "Light", "light", (-1.6, H - 0.08, -21.5), (1.6, H, -19.5))
    F.strip(g, "Light", "light", (-1.6, H - 0.08, -31.0), (1.6, H, -29.5))
    # Two pylons, set apart, break the long view down the corridor and give cover.
    for x, z in ((-2.9, -19.5), (2.9, -23.0)):
        F.box(g, "Pylon", "trim", (x - 0.8, 0, z - 0.8), (x + 0.8, H, z + 0.8))
        F.strip(g, "PylonLight", accent, (x - 0.83, 2.6, z - 0.83), (x + 0.83, 2.8, z + 0.83))
    hx0, hx1, hz0, hz1 = hole
    for lo, hi in (((hx0 - 0.3, 0, hz0 - 0.3), (hx1 + 0.3, 0.03, hz0)), ((hx0 - 0.3, 0, hz1), (hx1 + 0.3, 0.03, hz1 + 0.3)),
                   ((hx0 - 0.3, 0, hz0), (hx0, 0.03, hz1)), ((hx1, 0, hz0), (hx1 + 0.3, 0.03, hz1))):
        F.strip(g, "HoleRim", "accent_yellow", lo, hi)
    for i in range(3):   # what is left of the grate, hanging open
        F.strip(g, "Grate", "rail", (hx0 + 0.25 + i * 0.5, -0.45, hz0), (hx0 + 0.37 + i * 0.5, -0.38, hz1))
    F.box(g, "LowerFloor", "floor_dark", (-3.6, LOW - 0.5, -31.0), (3.6, LOW, -18.2))   # (to the room's wall: its threshold carries on)
    F.sign(room, (0, 5.75, -30.94), (0, 1), size=48, pixel=0.008)
    F.sign("CONTROL ROOM", (0, 5.6, -15.86), (0, -1), size=48, pixel=0.008)

    # Details. Walls: a dark base and cornice, ribs, a display and vents in the bays
    # between them, a pipe along the ceiling. Floor: a line of the room's colour with
    # chevrons toward it, grates at both doors, hazard stripes round the drop hole, and
    # where each end leads stencilled on the floor.
    for s in (-1, 1):
        face, out = s * 5.0, -s
        F.on_wall(g, "Base", "rib", "z", face, out, -30.9, -15.4, 0.0, 0.35, 0.1)   # (clear of the doorway's lit frame)
        F.on_wall(g, "Cornice", "rib", "z", face, out, -30.9, -15.4, 5.3, 5.5, 0.1)
        ribs(F, g, "z", face, out, (-30.5, -26.0, -21.5, -17.0), 0.35, 5.3)
        z_screen, z_vent = (-28.25, -19.25) if s < 0 else (-19.25, -28.25)
        screen(F, g, "z", face, out, z_screen, 2.7, accent)
        vent(F, g, "z", face, out, z_vent, 4.2)
        vent(F, g, "z", face, out, z_vent, 0.6, h=0.5)
        F.strip(g, "CeilingPipe", "pipe" if s < 0 else "pipe_blue", (s * 4.3 - 0.18, H - 0.5, -31.0), (s * 4.3 + 0.18, H - 0.14, -15.4))
        # lower deck
        lface = s * 3.0
        ribs(F, g, "z", lface, out, (-28.0, -24.5, -21.0), LOW, -0.5, width=0.3, depth=0.12, name="LowerRib")
        junction_box(F, g, "z", lface, out, -26.25 if s < 0 else -22.75, -5.0, accent)
        F.strip(g, "Cable", "cable", (s * 2.1 - 0.2, -0.72, -31.0), (s * 2.1 + 0.2, -0.5, -18.6))   # (clear of the drop hole)
    for z in (-27.3, -24.3, -17.6):
        F.strip(g, "Beam", "girder", (-5.0, H - 0.35, z - 0.25), (5.0, H, z + 0.25))
    F.strip(g, "GuideLine", accent, (-0.08, 0, -31.0), (0.08, 0.024, -29.4))
    F.strip(g, "GuideLine", accent, (-0.08, 0, -24.6), (0.08, 0.024, -18.0))
    for z in (-23.6, -20.6):
        F.chevron(g, accent, (0, z), (0, -1), 0.0)
    F.strip(g, "Grate", "grate", (-4.5, 0, -31.8), (4.5, 0.012, -31.0))
    F.strip(g, "Grate", "grate", (-4.5, 0, -16.0), (4.5, 0.012, -15.2))
    hole_hazard(F, g, hole, 0.0)
    F.floor_label(room, (0, 0.06, -30.2), (0, -1))
    F.floor_label("CONTROL ROOM", (0, 0.06, -17.0), (0, 1))
    F.strip(g, "LowerGrate", "grate", (-0.6, LOW, -31.0), (0.6, LOW + 0.012, -18.6))
    hole_hazard(F, g, (hole[0] + 0.5, hole[1] - 0.5, hole[2] + 0.5, hole[3] - 0.5), LOW, inner=0.5, wide=0.4)   # where you land


# ---------------------------------------------------------------------------
# What the four rooms share

def shell(F, g, x0, x1, z0, z1, top, tint, holes, floor_holes=(), floor="floor"):
    """The box a tall room sits in: floor at the lower deck, 1 m walls with openings
    (holes: side -> [(from, to, bottom, top)]), and a ceiling. Under an opening that
    starts at the floor (a doorway) the wall has no sill and the room's floor stops at
    the wall: the doorway's own threshold (see doorway()) is the only floor there, so
    no two floors lie in the same plane and flicker."""
    F.holes = holes   # (noted on the frame: strips along this room's walls stop at its openings)
    cut = list(floor_holes)
    walls = {}
    for side in "nswe":
        walls[side] = [(h0, h1, LOW - 0.5 if hb <= LOW else hb, ht) for h0, h1, hb, ht in holes.get(side, ())]
        for h0, h1, hb, ht in holes.get(side, ()):
            if hb <= LOW:
                cut.append({"n": (h0, h1, z0 - 1, z0), "s": (h0, h1, z1, z1 + 1), "w": (x0 - 1, x0, h0, h1), "e": (x1, x1 + 1, h0, h1)}[side])
    F.deck(g, "Floor", floor, x0 - 1, x1 + 1, z0 - 1, z1 + 1, LOW, holes=cut)
    F.box(g, "Ceiling", "hull", (x0 - 1, top, z0 - 1), (x1 + 1, top + 0.5, z1 + 1))
    F.wall(g, "WallN", "hull", "x", z0 - 0.5, x0 - 1, x1 + 1, LOW - 0.5, top, 1.0, walls["n"], tint=tint)
    F.wall(g, "WallS", "hull", "x", z1 + 0.5, x0 - 1, x1 + 1, LOW - 0.5, top, 1.0, walls["s"], tint=tint)
    F.wall(g, "WallW", "hull", "z", x0 - 0.5, z0, z1, LOW - 0.5, top, 1.0, walls["w"], tint=tint)
    F.wall(g, "WallE", "hull", "z", x1 + 0.5, z0, z1, LOW - 0.5, top, 1.0, walls["e"], tint=tint)
    for side, axis, face, out, a, b in (("n", "x", z0, 1, x0, x1), ("s", "x", z1, -1, x0, x1),
                                        ("w", "z", x0, 1, z0, z1), ("e", "z", x1, -1, z0, z1)):
        wall_band(F, g, "Base", "rib", axis, face, out, a, b, LOW, LOW + 0.4, 0.1, holes.get(side, ()))


def doorway(F, g, axis, line, a, b, la, lb, accent):
    """Finishes an opening that serves both decks (a..b on the main deck, la..lb below):
    the wall between the two lower jambs, both thresholds and a lit frame."""
    def bx(name, kind, u0, u1, y0, y1, **kw):
        if u1 - u0 < 0.01:
            return
        if axis == "x":
            F.box(g, name, kind, (u0, y0, line - 0.5), (u1, y1, line + 0.5), **kw)
        else:
            F.box(g, name, kind, (line - 0.5, y0, u0), (line + 0.5, y1, u1), **kw)
    bx("DoorFill", "hull_dark", a, la, LOW - 0.5, -0.5)
    bx("DoorFill", "hull_dark", lb, b, LOW - 0.5, -0.5)
    bx("Threshold", "floor", a, b, -0.5, 0.0)
    bx("Threshold", "floor_dark", la, lb, LOW - 0.5, LOW)
    for u in (a, b):
        if axis == "x":
            F.strip(g, "DoorLight", accent, (u - 0.1, 0, line - 0.56), (u + 0.1, 5.5, line + 0.56))
        else:
            F.strip(g, "DoorLight", accent, (line - 0.56, 0, u - 0.1), (line + 0.56, 5.5, u + 0.1))


def lights(F, g, x0, x1, z0, z1, y, nx, nz, kind="light", size=(5.0, 2.0)):
    """A grid of light panels under a ceiling at height y."""
    for i in range(nx):
        for j in range(nz):
            x = x0 + (x1 - x0) * (i + 0.5) / nx
            z = z0 + (z1 - z0) * (j + 0.5) / nz
            F.strip(g, "Light", kind, (x - size[0] / 2, y - 0.1, z - size[1] / 2), (x + size[0] / 2, y, z + size[1] / 2))


def wall_strips(F, g, x0, x1, z0, z1, y, accent, skip=()):
    """A strip of the room's colour round its walls at height y (skip: sides to leave bare).
    It stops short of every opening in the wall (the room's shell() noted them), so no
    strip hangs across a doorway or a window."""
    holes = getattr(F, "holes", {})
    for side, axis, face, out, a, b in (("n", "x", z0, 1, x0, x1), ("s", "x", z1, -1, x0, x1),
                                        ("w", "z", x0, 1, z0, z1), ("e", "z", x1, -1, z0, z1)):
        if side in skip:
            continue
        gaps = [(h0 - 0.15, h1 + 0.15, hb, ht) for h0, h1, hb, ht in holes.get(side, ())]
        wall_band(F, g, "Strip", accent, axis, face, out, a + 0.5, b - 0.5, y, y + 0.3, 0.05, gaps)


def outside(F, g, side, x0, x1, z0, z1, top, accent):
    """The face a tall room turns to the control room, as seen through the dome: dark
    hull plating above the corridor roofs, with bands of the room's own colour."""
    def bx(name, kind, a, b, y0, y1, out0, out1):
        if side == "n":
            F.strip(g, name, kind, (a, y0, z0 - 1 - out1), (b, y1, z0 - 1 - out0))
        elif side == "s":
            F.strip(g, name, kind, (a, y0, z1 + 1 + out0), (b, y1, z1 + 1 + out1))
        elif side == "w":
            F.strip(g, name, kind, (x0 - 1 - out1, y0, a), (x0 - 1 - out0, y1, b))
        else:
            F.strip(g, name, kind, (x1 + 1 + out0, y0, a), (x1 + 1 + out1, y1, b))
    a, b = (x0 - 1, x1 + 1) if side in "ns" else (z0 - 1, z1 + 1)
    bx("Plating", "hull_ext", a, b, 6.5, top + 0.5, 0.0, 0.1)
    for y in (10.0, top - 3.0):
        bx("PlatingBand", accent, a + 1.5, b - 1.5, y, y + 0.35, 0.1, 0.16)
    bx("PlatingTrim", "trim", a, b, top - 0.6, top + 0.5, 0.1, 0.2)
    n = int((b - a) / 9.0)
    for i in range(n):
        u = a + (b - a) * (i + 0.5) / n
        bx("PlatingWindow", "light_dim", u - 1.6, u + 1.6, 14.0, 14.5, 0.1, 0.14)
        bx("PlatingRib", "trim", u + (b - a) / n / 2 - 0.2, u + (b - a) / n / 2 + 0.2, 6.5, top - 0.6, 0.1, 0.18)


def wall_ribs(F, g, x0, x1, z0, z1, top, skip=(), step=8.0):
    """Dark ribs up the walls above door height and a band under them, so the tall
    rooms read as built of panels (and show how high you are)."""
    for side, a, b in (("n", x0, x1), ("s", x0, x1), ("w", z0, z1), ("e", z0, z1)):
        if side in skip:
            continue
        n = max(1, int(round((b - a) / step)))
        marks = [a + (b - a) * i / n for i in range(1, n)]
        for u in marks + [None]:
            if u is None:
                lo, hi = (a, 6.2), (b, 6.6)   # the band
            else:
                lo, hi = (u - 0.25, 6.6), (u + 0.25, top)
            if side == "n":
                F.strip(g, "Rib", "trim", (lo[0], lo[1], z0 - 0.02), (hi[0], hi[1], z0 + 0.1))
            elif side == "s":
                F.strip(g, "Rib", "trim", (lo[0], lo[1], z1 - 0.1), (hi[0], hi[1], z1 + 0.02))
            elif side == "w":
                F.strip(g, "Rib", "trim", (x0 - 0.02, lo[1], lo[0]), (x0 + 0.1, hi[1], hi[0]))
            else:
                F.strip(g, "Rib", "trim", (x1 - 0.1, lo[1], lo[0]), (x1 + 0.02, hi[1], hi[0]))


# ---------------------------------------------------------------------------
# Two surfaces of different colours in the same plane flicker, so nothing here shares a
# height with anything else it overlaps. Paint on a floor goes in layers: grates 12 mm
# thick, lines 24 mm (the first pass's trims are 20 mm), hole rims 30 mm, hazard
# stripes 40 mm, words 60 mm up. Wall pieces differ in how far they stand off the wall.
#
# Wall and floor details. The surface shader draws the panel seams, tiles, grating and
# stripes (SURFACE above); these are the pieces that stand out from a wall or lie on a
# floor. All of them are drawn only, never solid, and none stands more than 0.3 m off
# its surface, so nothing here can snag a wall run, a slide or a swing.

def wall_band(F, g, name, kind, axis, face, out, a, b, y0, y1, depth=0.1, holes=()):
    """A band along a wall, left out wherever an opening (from, to, bottom, top) crosses it."""
    u = a
    for h0, h1, hb, ht in sorted(holes):
        if hb >= y1 or ht <= y0 or h1 <= a or h0 >= b:
            continue
        if h0 - u > 0.05:
            F.on_wall(g, name, kind, axis, face, out, u, h0, y0, y1, depth)
        u = max(u, h1)
    if b - u > 0.05:
        F.on_wall(g, name, kind, axis, face, out, u, b, y0, y1, depth)


def ribs(F, g, axis, face, out, at, y0, y1, width=0.4, depth=0.14, name="Rib"):
    for u in at:
        F.on_wall(g, name, "rib", axis, face, out, u - width / 2, u + width / 2, y0, y1, depth)


def screen(F, g, axis, face, out, u, y, accent, w=2.4, h=1.3):
    """A wall display: a frame, a dark screen and two lit bars of the place's colour."""
    F.on_wall(g, "ScreenFrame", "rib", axis, face, out, u - w / 2 - 0.12, u + w / 2 + 0.12, y - 0.12, y + h + 0.12, 0.08)
    F.on_wall(g, "Screen", "screen", axis, face, out, u - w / 2, u + w / 2, y, y + h, 0.04, lift=0.08)
    F.on_wall(g, "ScreenBar", accent, axis, face, out, u - w / 2 + 0.2, u + w / 2 - 0.6, y + h - 0.4, y + h - 0.25, 0.02, lift=0.12)
    F.on_wall(g, "ScreenBar", accent, axis, face, out, u - w / 2 + 0.2, u - 0.1, y + 0.3, y + 0.45, 0.02, lift=0.12)


def vent(F, g, axis, face, out, u, y, w=1.8, h=0.6):
    F.on_wall(g, "Vent", "vent", axis, face, out, u - w / 2, u + w / 2, y, y + h, 0.06)


def junction_box(F, g, axis, face, out, u, y, accent):
    F.on_wall(g, "JunctionBox", "machine", axis, face, out, u - 0.5, u + 0.5, y, y + 1.2, 0.15)
    F.on_wall(g, "JunctionLight", accent, axis, face, out, u - 0.35, u + 0.35, y + 0.85, y + 1.0, 0.02, lift=0.15)


def hole_hazard(F, g, hole, y, inner=0.3, wide=0.45):
    """Hazard stripes round a hole in a floor (x0, x1, z0, z1), outside its rim."""
    hx0, hx1, hz0, hz1 = hole
    a, b = inner, inner + wide
    for lo, hi in (((hx0 - b, hz0 - b), (hx1 + b, hz0 - a)), ((hx0 - b, hz1 + a), (hx1 + b, hz1 + b)),
                   ((hx0 - b, hz0 - a), (hx0 - a, hz1 + a)), ((hx1 + a, hz0 - a), (hx1 + b, hz1 + a))):
        F.strip(g, "HoleHazard", "hazard", (lo[0], y, lo[1]), (hi[0], y + 0.04, hi[1]))


def corner_pipes(F, g, corners, top):
    """Two pipes up a room's corner, from the lower deck to the ceiling: (x, z, toward x, toward z)."""
    for x, z, sx, sz in corners:
        F.m.cyl(g, "CornerPipe", "pipe", F.pt((x + sx * 0.45, LOW, z + sz * 0.45)), 0.6, top - LOW, sides=8, solid=False)
        F.m.cyl(g, "CornerPipe", "pipe_blue", F.pt((x + sx * 1.15, LOW, z + sz * 0.4)), 0.42, top - LOW, sides=8, solid=False)


# ---------------------------------------------------------------------------
# Hangar (north): the biggest open volume, two shuttles, a viewport onto space

def hangar(m):
    F = Frame(m)
    f = m.folder("Hangar")
    X0, X1, Z0, Z1, TOP = -30.0, 30.0, -HULL, -ROOM, 30.0
    A = "accent_cyan"
    g = m.group("Shell", f)
    shell(F, g, X0, X1, Z0, Z1, TOP, T_HANGAR, {
        "s": [(-5, 5, LOW, 5.5)], "n": [(-24, 24, 1.0, 23.0)],
        "e": [(-66, -56, LOW, 5.5)], "w": [(-66, -56, LOW, 5.5)]})
    doorway(F, g, "x", Z1 + 0.5, -5, 5, -3, 3, A)
    doorway(F, g, "z", X1 + 0.5, -66, -56, -62, -56, A)
    doorway(F, g, "z", X0 - 0.5, -66, -56, -62, -56, A)
    F.box(g, "Viewport", "glass_hull", (-24, 1.0, Z0 - 0.7), (24, 23.0, Z0 - 0.3), unbreakable=True)
    for x in (-16, -8, 0, 8, 16):
        F.strip(g, "Mullion", "trim", (x - 0.15, 1.0, Z0 - 0.25), (x + 0.15, 23.0, Z0 + 0.1))
    F.strip(g, "Mullion", "trim", (-24, 11.8, Z0 - 0.25), (24, 12.2, Z0 + 0.1))
    F.strip(g, "ViewportFrame", A, (-24.3, 0.7, Z0 - 0.02), (24.3, 1.0, Z0 + 0.06))
    F.strip(g, "ViewportFrame", A, (-24.3, 23.0, Z0 - 0.02), (24.3, 23.3, Z0 + 0.06))
    wall_strips(F, g, X0, X1, Z0, Z1, -2.6, A, skip=("n",))
    wall_strips(F, g, X0, X1, Z0, Z1, 13.0, A, skip=("n",))
    wall_ribs(F, g, X0, X1, Z0, Z1, TOP, skip=("n",))
    outside(F, g, "s", X0, X1, Z0, Z1, TOP, A)
    lights(F, g, X0 + 4, X1 - 4, Z0 + 4, Z1 - 4, TOP, 4, 3, size=(7.0, 2.5))
    for z in (-62, -55, -48, -41, -34.5):
        F.box(g, "Girder", "girder", (X0, 26.5, z - 0.5), (X1, 27.5, z + 0.5))

    # Main deck level: a balcony along the south wall and down both sides to the ring doors.
    g = m.group("Balcony", f)
    F.box(g, "Deck", "floor", (X0, -0.4, -40), (X1, 0, Z1))
    for s in (-1, 1):
        F.box(g, "Deck", "floor", (min(s * 24, s * 30), -0.4, Z0), (max(s * 24, s * 30), 0, -40))
        F.rail(g, "z", s * 24, -62, -40, 0.0)
        F.slab(g, "Ramp", "stair", (s * 18.5, 0, -40), (s * 18.5, LOW, -51), 5.0, thick=0.4)
        for x in (s * 8, s * 22):
            F.box(g, "Post", "girder", (x - 0.3, LOW, -39.9), (x + 0.3, -0.4, -39.3))
        F.box(g, "Post", "girder", (s * 24.3 - 0.3, LOW, -53.3), (s * 24.3 + 0.3, -0.4, -52.7))
        F.strip(g, "EdgeLight", A, (min(s * 16, s * 24), -0.4, -40.05), (max(s * 16, s * 24), -0.25, -39.98))
    F.rail(g, "x", -40, -24, 24, 0.0, gaps=[(-21, -16), (16, 21)])
    F.strip(g, "EdgeLight", A, (-16, -0.4, -40.05), (16, -0.25, -39.98))
    lights(F, g, -24, 24, -39, -33, -0.42, 4, 1, kind="light_dim", size=(4.0, 1.2))

    # 7 m: a catwalk along the south wall with the control booth in the middle, walked up
    # to by the ramp on the west wall. 14 m: the launch gantry (grapple only). 20 m: a perch.
    g = m.group("Booth", f)
    F.box(g, "Catwalk", "catwalk", (X0, 6.7, -35), (X1, 7, Z1))
    F.box(g, "BoothFloor", "catwalk", (-8, 6.7, -39), (8, 7, -35))
    F.box(g, "BoothGlass", "glass_pane", (-8, 7, -39.1), (8, 9.5, -38.9))   # free of the roof and sides, so it can break
    F.box(g, "BoothRoof", "hull", (-8.5, 9.8, -39.5), (8.5, 10.2, Z1))
    for s in (-1, 1):
        F.box(g, "BoothSide", "hull", (s * 8 - 0.15, 7, -38.8), (s * 8 + 0.15, 9.8, -36.6))
        F.rail(g, "x", -35, min(s * 8.2, s * 30), max(s * 8.2, s * 30), 7.0, gaps=[(-30, -26)] if s < 0 else ())
    F.box(g, "Desk", "console", (-5, 7, -38.6), (5, 7.9, -37.9))
    F.strip(g, "DeskLight", A, (-5, 7.9, -38.6), (5, 7.95, -37.9))
    F.strip(g, "BoothLight", A, (-8.5, 9.6, -39.52), (8.5, 9.8, -39.45))
    F.box(g, "WestCatwalk", "catwalk", (X0, 6.7, -42), (-26, 7, -35))
    F.slab(g, "WestRamp", "stair", (-28, 0, -54), (-28, 7, -42), 4.0, thick=0.35)
    F.rail(g, "z", -26, -42, -35, 7.0)
    g = m.group("Gantry", f)
    F.box(g, "Catwalk", "catwalk", (-26, 13.7, -52), (26, 14, -48))
    F.rail(g, "x", -52, -26, 26, 14.0, gaps=[(-4, 4)])
    F.rail(g, "x", -48, -26, 26, 14.0, gaps=[(-14, -10), (10, 14)])
    for x in (-24, -8, 8, 24):
        for z in (-52.2, -47.8):
            F.box(g, "Hanger", "girder", (x - 0.2, 13.7, z - 0.2), (x + 0.2, 26.5, z + 0.2))
    for s in (-1, 1):
        F.box(g, "LaunchRail", "girder", (s * 12 - 0.4, 12.9, -64), (s * 12 + 0.4, 13.7, -40.5))
        F.strip(g, "RailLight", A, (s * 12 - 0.42, 13.1, -63.95), (s * 12 + 0.42, 13.25, -40.55))
        F.box(g, "Clamp", "crane", (s * 12 - 1.0, 10.9, -58), (s * 12 + 1.0, 12.9, -56))
    F.box(g, "Perch", "catwalk", (26, 19.7, -58), (X1, 20, -50))
    F.box(g, "PerchBrace", "girder", (26, 19.0, -54.3), (X1, 19.7, -53.7))
    F.strip(g, "PerchLight", A, (25.95, 19.7, -58), (26.02, 19.9, -50))

    shuttle(m, f, "ShuttleA", (-8.0, LOW, -56.0), 0.22)
    shuttle(m, f, "ShuttleB", (9.5, LOW, -57.0), -0.3)
    g = m.group("Deck", f)
    for x0, z0, x1, z1 in ((-15.5, -64, -0.5, -47), (2, -65, 17, -48)):   # painted landing pads
        F.strip(g, "PadLine", A, (x0, LOW, z0), (x1, LOW + 0.02, z0 + 0.25))
        F.strip(g, "PadLine", A, (x0, LOW, z1 - 0.25), (x1, LOW + 0.02, z1))
        F.strip(g, "PadLine", A, (x0, LOW, z0), (x0 + 0.25, LOW + 0.02, z1))
        F.strip(g, "PadLine", A, (x1 - 0.25, LOW, z0), (x1, LOW + 0.02, z1))
    for (x, z, w, d, h, kind) in ((-26, -47, 3.0, 2.0, 1.5, "crate"), (-26.5, -44.5, 2.0, 2.0, 2.2, "crate_dark"),
                                  (22, -61, 3.0, 3.0, 1.5, "crate"), (25.5, -61.5, 2.0, 2.0, 2.6, "crate_dark"),
                                  (-2, -44, 4.0, 1.6, 1.2, "crate"), (0, -37, 2.4, 2.4, 1.4, "crate_dark"),
                                  (-21, -63.5, 2.4, 2.4, 2.0, "crate")):
        F.box(g, "Crate", kind, (x - w / 2, LOW, z - d / 2), (x + w / 2, LOW + h, z + d / 2))
    F.sign("HANGAR", (0, 8.6, Z1 - 0.06), (0, -1), size=120, pixel=0.014, col=(0.5, 0.9, 1, 1))
    F.floor_label("BAY 1", (-8, LOW + 0.06, -45.6), (0, -1), size=96, pixel=0.02, col=(0.5, 0.9, 1, 0.8))
    F.floor_label("BAY 2", (9.5, LOW + 0.06, -46.6), (0, -1), size=96, pixel=0.02, col=(0.5, 0.9, 1, 0.8))
    g = m.group("Details", f)
    corner_pipes(F, g, ((X0, Z1, 1, -1), (X1, Z1, -1, -1)), TOP)
    for x in (-10.0, 10.0):
        screen(F, g, "x", Z1, -1, x, 2.3, A)
        vent(F, g, "x", Z1, -1, x, 4.4)
    for x in (-27.0, -18.0, 18.0, 27.0):
        vent(F, g, "x", Z1, -1, x, -5.3)
    for s in (-1, 1):
        F.strip(g, "RampHazard", "hazard", (s * 18.5 - 2.5, LOW, -51.6), (s * 18.5 + 2.5, LOW + 0.04, -51.05))
        ribs(F, g, "x", Z1, -1, (s * 6.2, s * 14.0, s * 22.0), 0.0, 6.2)
    F.strip(g, "ViewportHazard", "hazard", (-24, LOW, Z0 + 0.1), (24, LOW + 0.04, Z0 + 0.7))
    F.strip(g, "Grate", "grate", (-24, LOW, -42.2), (24, LOW + 0.012, -41.4))


def shuttle(m, f, name, at, yaw):
    """A parked shuttle, nose to the north: cover on the deck, and a climb by the wing."""
    g = m.group(name, f, at=at, yaw=yaw)
    for s in (-1, 1):
        m.box(g, "Skid", "shuttle_dark", (min(s * 1.4, s * 1.8), 0, -5), (max(s * 1.4, s * 1.8), 0.5, 5))
        m.box(g, "Wing", "shuttle", (min(s * 2.5, s * 7), 1.6, 0.5), (max(s * 2.5, s * 7), 2.1, 6))
        m.box(g, "WingTip", "accent_cyan", (min(s * 7, s * 7.15), 1.6, 0.5), (max(s * 7, s * 7.15), 2.1, 6), solid=False)
        m.lying_cyl(g, "Engine", "shuttle_dark", (s * 1.4, 2.1, 7.6), 1.7, 1.4, axis="z", sides=10)
        m.lying_cyl(g, "EngineGlow", "engine_glow", (s * 1.4, 2.1, 8.33), 1.2, 0.08, axis="z", sides=10, solid=False)
        m.box(g, "Stripe", "accent_cyan", (min(s * 2.5, s * 2.53), 2.3, -5.5), (max(s * 2.5, s * 2.53), 2.6, 6.5), solid=False)
    m.box(g, "Body", "shuttle", (-2.5, 0.5, -6), (2.5, 3.6, 7))
    m.box(g, "Nose", "shuttle", (-1.9, 0.7, -9), (1.9, 2.9, -6))
    m.box(g, "Cockpit", "shuttle_dark", (-1.5, 2.9, -8.2), (1.5, 3.3, -6), solid=False)
    m.box(g, "Fin", "shuttle", (-0.25, 3.6, 3.5), (0.25, 6.0, 7))


# ---------------------------------------------------------------------------
# Engineering (south): the reactor core, ringed catwalks round it, the pit under it

def engineering(m):
    F = Frame(m)
    f = m.folder("Engineering")
    X0, X1, Z0, Z1, TOP = -24.0, 24.0, ROOM, HULL, 28.0
    C = (0.0, 49.0)
    A = "accent_orange"
    g = m.group("Shell", f)
    shell(F, g, X0, X1, Z0, Z1, TOP, T_ENG, {
        "n": [(-5, 5, LOW, 5.5)], "e": [(56, 66, LOW, 5.5)], "w": [(60, 66, LOW, 5.5)],
        "s": [(-14, -6, 2.0, 5.5), (6, 14, 2.0, 5.5)]},
        floor_holes=[(-8, 8, 41, 57)])
    doorway(F, g, "x", Z0 - 0.5, -5, 5, -3, 3, A)
    doorway(F, g, "z", X1 + 0.5, 56, 66, 56, 62, A)
    doorway(F, g, "z", X0 - 0.5, 60, 66, 60, 66, "accent_ice")
    for x0, x1 in ((-14, -6), (6, 14)):
        F.box(g, "Window", "glass_hull", (x0, 2.0, Z1 + 0.3), (x1, 5.5, Z1 + 0.7), unbreakable=True)
    wall_strips(F, g, X0, X1, Z0, Z1, -2.6, A)
    wall_strips(F, g, X0, X1, Z0, Z1, 11.5, A)
    wall_strips(F, g, X0, X1, Z0, Z1, 20.0, A)
    wall_ribs(F, g, X0, X1, Z0, Z1, TOP)
    outside(F, g, "n", X0, X1, Z0, Z1, TOP, A)
    lights(F, g, X0 + 4, X1 - 4, Z0 + 3, Z1 - 3, TOP, 3, 2, size=(6.0, 2.0))
    for z in (36, 43, 55, 62):
        F.box(g, "Girder", "girder", (X0, 24.5, z - 0.5), (X1, 25.5, z + 0.5))

    # The pit: the map's one hazard. It drops far below the kill height.
    g = m.group("ReactorPit", f)
    for lo, hi in (((-9, -34, 40), (9, LOW - 0.5, 41)), ((-9, -34, 57), (9, LOW - 0.5, 58)),
                   ((-9, -34, 41), (-8, LOW - 0.5, 57)), ((8, -34, 41), (9, LOW - 0.5, 57))):
        F.box(g, "PitWall", "hull_dark", lo, hi, tint=(1.0, 0.8, 0.62))
    F.strip(g, "PitFloor", "reactor_core", (-8, -33.6, 41), (8, -33.2, 57))
    for y in (-10, -16, -22, -28):
        F.strip(g, "PitGlow", "pit_glow", (-8, y, 41.0), (8, y + 0.3, 41.06))
        F.strip(g, "PitGlow", "pit_glow", (-8, y, 56.94), (8, y + 0.3, 57.0))
        F.strip(g, "PitGlow", "pit_glow", (-8.0, y, 41), (-7.94, y + 0.3, 57))
        F.strip(g, "PitGlow", "pit_glow", (7.94, y, 41), (8.0, y + 0.3, 57))
    for lo, hi in (((-8.6, LOW, 40.4), (8.6, LOW + 0.03, 41)), ((-8.6, LOW, 57), (8.6, LOW + 0.03, 57.6)),
                   ((-8.6, LOW, 41), (-8, LOW + 0.03, 57)), ((8, LOW, 41), (8.6, LOW + 0.03, 57))):
        F.strip(g, "PitEdge", "pit_glow", lo, hi)
    F.rail(g, "x", 40.7, -8, 8, LOW, gaps=[(-6, -3), (3, 6)], kind="accent_orange")
    F.rail(g, "x", 57.3, -8, 8, LOW, gaps=[(-6, -3), (3, 6)], kind="accent_orange")
    F.rail(g, "z", -8.3, 41, 57, LOW, gaps=[(43, 46), (52, 55)], kind="accent_orange")
    F.rail(g, "z", 8.3, 41, 57, LOW, gaps=[(43, 46), (52, 55)], kind="accent_orange")

    g = m.group("Reactor", f)
    m.cyl(g, "Core", "reactor", (C[0], -33.0, C[1]), 6.0, 55.0, sides=16)
    for y in (-3.0, 4.2, 12.2, 19.8):
        m.cyl(g, "Collar", "trim", (C[0], y, C[1]), 7.0, 0.6, sides=16)
    m.cyl(g, "CoreCap", "trim", (C[0], 22.0, C[1]), 8.5, 1.2, sides=16)
    m.cyl(g, "CoreStem", "girder", (C[0], 23.2, C[1]), 3.0, TOP - 23.2, sides=12)
    hoop(m, g, "CapLight", A, 4.3, 0.2, 22.3, 22.6, c=C, sides=16)

    # Ringed catwalks round the core at 0, 8 and 16 m, each reached by its own bridges.
    g = m.group("Catwalks", f)
    for y in (0.0, 8.0, 16.0):
        ring(m, g, "Ring", "catwalk", 5.0, 8.0, y - 0.3, y, 16, c=C)
        hoop(m, g, "RingLight", A, 8.1, 0.12, y - 0.34, y - 0.08, c=C, sides=16)   # (not level with the catwalk's underside)
    F.box(g, "Bridge", "catwalk", (-1.5, -0.3, 37), (1.5, 0, 41.3))
    F.box(g, "Bridge", "catwalk", (-1.5, -0.3, 56.7), (1.5, 0, 60))
    F.box(g, "Bridge", "catwalk", (7.7, -0.3, 47.5), (19, 0, 50.5))
    F.box(g, "Bridge", "catwalk", (-19, -0.3, 47.5), (-7.7, 0, 50.5))
    F.box(g, "Bridge", "catwalk", (7.7, 7.7, 47.5), (20, 8, 50.5))
    F.box(g, "Bridge", "catwalk", (-20, 7.7, 47.5), (-7.7, 8, 50.5))
    F.box(g, "Bridge", "catwalk", (-1.5, 15.7, 36), (1.5, 16, 41.3))
    F.box(g, "Bridge", "catwalk", (-1.5, 15.7, 56.7), (1.5, 16, 62))
    for z0, z1 in ((37, 41.3), (56.7, 60)):
        for s in (-1, 1):
            F.rail(g, "z", s * 1.5, z0, z1, 0.0)
    for x0, x1 in ((7.7, 19), (-19, -7.7)):
        F.rail(g, "x", 47.5, x0, x1, 0.0)
    F.box(g, "LedgeEast", "catwalk", (20, 7.7, 38), (X1, 8, Z1))
    F.box(g, "LedgeWest", "catwalk", (X0, 7.7, 38), (-20, 8, 60))
    F.box(g, "LedgeSouth", "catwalk", (0, 7.7, 62.5), (20, 8, Z1))
    F.slab(g, "Ramp", "stair", (-16, 0, 64.25), (0, 8, 64.25), 3.5, thick=0.35)
    F.rail(g, "z", 20, 38, 47.5, 8.0)
    F.rail(g, "z", 20, 50.5, 62.5, 8.0)
    F.rail(g, "z", -20, 38, 47.5, 8.0)
    F.rail(g, "z", -20, 50.5, 60, 8.0)
    F.rail(g, "x", 62.5, 0, 20, 8.0, gaps=[(0, 1.5)])
    F.box(g, "LedgeHighN", "catwalk", (-10, 15.7, Z0), (10, 16, 36))
    F.box(g, "LedgeHighS", "catwalk", (-10, 15.7, 62), (10, 16, Z1))

    # Main deck level: a balcony right round the room, with two ramps down to the floor.
    g = m.group("Balcony", f)
    F.box(g, "Deck", "floor", (X0, -0.4, Z0), (X1, 0, 37))
    F.box(g, "Deck", "floor", (X0, -0.4, 60), (X1, 0, Z1))
    F.box(g, "Deck", "floor", (X0, -0.4, 37), (-19, 0, 60))
    F.box(g, "Deck", "floor", (19, -0.4, 37), (X1, 0, 60))
    F.slab(g, "Ramp", "stair", (14.5, 0, 37), (14.5, LOW, 48), 5.0, thick=0.4)
    F.slab(g, "Ramp", "stair", (-14.5, 0, 60), (-14.5, LOW, 49), 5.0, thick=0.4)
    F.rail(g, "x", 37, -19, 19, 0.0, gaps=[(-1.5, 1.5), (12, 17)])
    F.rail(g, "x", 60, -19, 19, 0.0, gaps=[(-1.5, 1.5), (-17, -12)])
    F.rail(g, "z", -19, 37, 60, 0.0, gaps=[(47.5, 50.5)])
    F.rail(g, "z", 19, 37, 60, 0.0, gaps=[(47.5, 50.5)])
    for x, z in ((-19.3, 37.3), (19.3, 37.3), (-19.3, 59.7), (19.3, 59.7), (-19.3, 48.9), (19.3, 44)):
        F.box(g, "Post", "girder", (x - 0.3, LOW, z - 0.3), (x + 0.3, -0.4, z + 0.3))
    lights(F, g, X0 + 2, X1 - 2, Z0 + 0.5, 36.5, -0.42, 4, 1, kind="light_dim", size=(4.0, 1.2))
    lights(F, g, X0 + 2, X1 - 2, 60.5, Z1 - 0.5, -0.42, 4, 1, kind="light_dim", size=(4.0, 1.2))

    g = m.group("Machines", f)
    for (x0, z0, x1, z1, h) in ((-23, 39, -20.5, 46, 3.0), (-23, 52, -20.5, 58, 2.4), (20.5, 51, 23, 58, 3.0),
                                (-6, 34, -3.5, 36.5, 1.6), (3.5, 61.5, 7, 64, 1.6), (10, 58.5, 13, 61, 2.2)):
        F.box(g, "Machine", "machine", (x0, LOW, z0), (x1, LOW + h, z1))
        F.strip(g, "MachineLight", A, (x0 - 0.02, LOW + h - 0.5, z0 - 0.02), (x1 + 0.02, LOW + h - 0.3, z1 + 0.02))
    F.sign("ENGINEERING", (0, 10.0, Z0 + 0.06), (0, 1), size=120, pixel=0.014, col=(1, 0.75, 0.4, 1))
    g = m.group("Details", f)
    corner_pipes(F, g, ((X0, Z0, 1, 1), (X1, Z0, -1, 1)), TOP)
    for x in (-10.0, 10.0):
        screen(F, g, "x", Z0, 1, x, 2.3, A)
        vent(F, g, "x", Z0, 1, x, 4.4)
    for s in (-1, 1):
        ribs(F, g, "x", Z0, 1, (s * 6.2, s * 14.0, s * 20.0), 0.0, 6.2)
        vent(F, g, "z", s * 24.0, -s, 36.0, -5.3)
        vent(F, g, "z", s * 24.0, -s, 50.0, -5.3)
    # The pit again: hazard stripes right round it, outside the glowing edge.
    hole_hazard(F, g, (-8, 8, 41, 57), LOW, inner=0.6, wide=0.6)
    F.strip(g, "RampHazard", "hazard", (12.0, LOW, 48.05), (17.0, LOW + 0.04, 48.6))
    F.strip(g, "RampHazard", "hazard", (-17.0, LOW, 48.4), (-12.0, LOW + 0.04, 48.95))
    F.floor_label("REACTOR PIT", (0, LOW + 0.06, 38.7), (0, 1), size=72, col=(1, 0.7, 0.3, 0.85))
    F.floor_label("REACTOR PIT", (0, LOW + 0.06, 59.3), (0, -1), size=72, col=(1, 0.7, 0.3, 0.85))
    


# ---------------------------------------------------------------------------
# Cargo bay (west): container stacks, lanes between them, a gantry crane overhead

def cargo(m):
    F = Frame(m)
    f = m.folder("CargoBay")
    X0, X1, Z0, Z1, TOP = -HULL, -ROOM, -24.0, 24.0, 26.0
    A = "accent_yellow"
    g = m.group("Shell", f)
    shell(F, g, X0, X1, Z0, Z1, TOP, T_CARGO, {
        "e": [(-5, 5, LOW, 5.5)], "n": [(-66, -56, LOW, 5.5)], "s": [(-66, -60, LOW, 5.5)],
        "w": [(-14, -6, 9.5, 13.0), (6, 14, 9.5, 13.0)]})
    doorway(F, g, "z", X1 + 0.5, -5, 5, -3, 3, A)
    doorway(F, g, "x", Z0 - 0.5, -66, -56, -62, -56, A)
    doorway(F, g, "x", Z1 + 0.5, -66, -60, -66, -60, "accent_ice")
    for z0, z1 in ((-14, -6), (6, 14)):
        F.box(g, "Window", "glass_hull", (X0 - 0.7, 9.5, z0), (X0 - 0.3, 13.0, z1), unbreakable=True)
    wall_strips(F, g, X0, X1, Z0, Z1, -2.6, A)
    wall_strips(F, g, X0, X1, Z0, Z1, 15.5, A, skip=("w",))
    wall_ribs(F, g, X0, X1, Z0, Z1, TOP, skip=("w",))
    outside(F, g, "e", X0, X1, Z0, Z1, TOP, A)
    lights(F, g, X0 + 4, X1 - 4, Z0 + 4, Z1 - 4, TOP, 2, 4, size=(6.0, 2.0))
    for x in (-62, -52, -42, -35):
        F.box(g, "Girder", "girder", (x - 0.5, 23.0, Z0), (x + 0.5, 24.0, Z1))

    g = m.group("Balcony", f)
    F.box(g, "Deck", "floor", (-38, -0.4, Z0), (X1, 0, Z1))
    F.box(g, "Deck", "floor", (X0, -0.4, Z0), (-38, 0, -18))
    F.box(g, "Deck", "floor", (X0, -0.4, 18), (-38, 0, Z1))
    for s in (-1, 1):
        F.slab(g, "Ramp", "stair", (-38, 0, s * 14.5), (-49, LOW, s * 14.5), 5.0, thick=0.4)
        F.rail(g, "x", s * 18, -62, -38, 0.0, gaps=[(-52, -48)])
        for x in (-38.3, -50, -62):
            F.box(g, "Post", "girder", (x - 0.3, LOW, s * 18.3 - 0.3), (x + 0.3, -0.4, s * 18.3 + 0.3))
    F.rail(g, "z", -38, -18, 18, 0.0, gaps=[(-17, -12), (12, 17), (-2, 2)])
    F.strip(g, "EdgeLight", A, (-38.05, -0.4, -12), (-37.98, -0.25, 12))
    lights(F, g, -37.5, -32.5, Z0 + 2, Z1 - 2, -0.42, 1, 5, kind="light_dim", size=(1.2, 4.0))

    # Container stacks: (x0, z0, long axis, containers long, levels, colours bottom to top).
    g = m.group("Containers", f)
    stacks = [
        (-46.0, -9.0, "z", 12, 2, ("container_yellow", "container_grey")),
        (-46.0, 5.0, "z", 6, 1, ("container_blue",)),
        (-52.0, -10.0, "z", 12, 4, ("container_teal", "container_orange", "container_grey", "container_yellow")),
        (-52.0, 4.0, "z", 6, 3, ("container_orange", "container_blue", "container_teal")),
        (-58.0, -8.0, "z", 12, 6, ("container_blue", "container_grey", "container_yellow", "container_teal", "container_orange", "container_blue")),
        (-58.0, 6.0, "z", 6, 2, ("container_grey", "container_yellow")),
        (-64.0, -12.0, "z", 12, 3, ("container_orange", "container_teal", "container_grey")),
        (-64.0, 2.0, "z", 12, 4, ("container_yellow", "container_blue", "container_orange", "container_grey")),
        (-62.0, -16.6, "x", 12, 1, ("container_grey",)),
        (-61.4, 14.0, "x", 12, 2, ("container_teal", "container_yellow")),
    ]
    for (x, z, axis, length, levels, kinds) in stacks:
        for i in range(levels):
            lo = (x, LOW + i * 2.6, z)
            hi = (x + 2.6, LOW + (i + 1) * 2.6, z + length) if axis == "z" else (x + length, LOW + (i + 1) * 2.6, z + 2.6)
            F.box(g, "Container", kinds[i], lo, hi)
            if axis == "z":   # the doors on one end, a darker band
                F.strip(g, "Doors", "trim", (x + 0.2, lo[1] + 0.2, z - 0.03), (x + 2.4, hi[1] - 0.2, z + 0.0))
            else:
                F.strip(g, "Doors", "trim", (x - 0.03, lo[1] + 0.2, z + 0.2), (x + 0.0, hi[1] - 0.2, z + 2.4))

    # 8 m: catwalks on the west and south walls, walked up to by the ramp on the west wall.
    # 19 m: the gantry crane, its hook and a hanging container (grapple only).
    g = m.group("Catwalks", f)
    F.slab(g, "Ramp", "stair", (-64.25, 0, -18), (-64.25, 8, -2), 3.5, thick=0.35)
    F.box(g, "Catwalk", "catwalk", (X0, 7.7, -2), (-62.5, 8, Z1))
    F.box(g, "Catwalk", "catwalk", (-62.5, 7.7, 21), (-40, 8, Z1))
    F.rail(g, "z", -62.5, -2, 21, 8.0, gaps=[(8, 11)])
    F.rail(g, "x", 21, -62.5, -40, 8.0, gaps=[(-52, -49)])
    g = m.group("Crane", f)
    for s in (-1, 1):
        F.box(g, "CraneRail", "girder", (X0, 18.2, s * 21 - 0.4), (X1, 19.0, s * 21 + 0.4))
        for x in (-64, -52, -40):
            F.box(g, "Bracket", "girder", (x - 0.3, 17.2, min(s * 21, s * 24)), (x + 0.3, 18.2, max(s * 21, s * 24)))
    F.box(g, "Bridge", "crane", (-53.5, 19.0, -21.4), (-50.5, 20.2, 21.4))
    F.box(g, "Trolley", "trim", (-54, 18.0, 3), (-50, 19.0, 7))
    F.strip(g, "Cable", "rail", (-52.1, 14.6, 4.9), (-51.9, 18.0, 5.1))
    F.box(g, "Hung", "container_orange", (-53.3, 12.0, 2), (-50.7, 14.6, 8))
    F.strip(g, "CraneLight", A, (-53.52, 19.3, -21), (-53.45, 19.6, 21))
    F.strip(g, "CraneLight", A, (-50.55, 19.3, -21), (-50.48, 19.6, 21))
    g = m.group("Deck", f)
    for z in (-11.2, 0.0, 11.2):   # hazard lines across the lanes
        F.strip(g, "Line", A, (-48.6, LOW, z - 0.15), (-39, LOW + 0.02, z + 0.15))
    for (x, z, w, d, h, kind) in ((-41, -21, 2.4, 2.0, 1.4, "crate"), (-43.5, -21.5, 2.0, 2.0, 2.2, "crate_dark"),
                                  (-41, 21, 3.0, 2.0, 1.5, "crate"), (-35, 6.5, 2.0, 3.0, 1.3, "crate_dark")):
        F.box(g, "Crate", kind, (x - w / 2, LOW, z - d / 2), (x + w / 2, LOW + h, z + d / 2))
    F.sign("CARGO BAY 2", (X1 - 0.06, 7.6, 0), (-1, 0), size=120, pixel=0.014, col=(1, 0.9, 0.4, 1))
    g = m.group("Details", f)
    corner_pipes(F, g, ((X1, Z0, -1, 1), (X1, Z1, -1, -1)), TOP)
    for z in (-10.0, 10.0):
        screen(F, g, "z", X1, -1, z, 2.3, A)
        vent(F, g, "z", X1, -1, z, 4.4)
    for s in (-1, 1):
        ribs(F, g, "z", X1, -1, (s * 6.2, s * 14.0, s * 20.0), 0.0, 6.2)
        vent(F, g, "z", X1, -1, s * 8.0, -5.3)
        F.strip(g, "RampHazard", "hazard", (-49.6, LOW, s * 14.5 - 2.5), (-49.05, LOW + 0.04, s * 14.5 + 2.5))
    for i, x in enumerate((-47.7, -53.7, -59.7)):   # the lanes between the stacks
        F.floor_label("LANE %d" % (i + 1), (x, LOW + 0.06, 12.6), (0, -1), size=56, col=(1, 0.9, 0.4, 0.8))
        F.strip(g, "LaneLine", A, (x - 0.06, LOW, -9.5), (x + 0.06, LOW + 0.0244, 10.5))
    F.strip(g, "Grate", "grate", (-42.4, LOW, -20), (-41.6, LOW + 0.012, 20))


# ---------------------------------------------------------------------------
# Hydroponics (east): terraces of planting beds up the east wall, grow lights, pipes

def hydroponics(m):
    F = Frame(m)
    f = m.folder("Hydroponics")
    X0, X1, Z0, Z1, TOP = ROOM, HULL, -24.0, 24.0, 28.0
    A = "accent_green"
    g = m.group("Shell", f)
    shell(F, g, X0, X1, Z0, Z1, TOP, T_HYDRO, {
        "w": [(-5, 5, LOW, 5.5)], "n": [(56, 66, LOW, 5.5)], "s": [(56, 66, LOW, 5.5)],
        "e": [(-22, -16, 1.5, 4.5), (16, 22, 1.5, 4.5)]})
    doorway(F, g, "z", X0 - 0.5, -5, 5, -3, 3, A)
    doorway(F, g, "x", Z0 - 0.5, 56, 66, 56, 62, A)
    doorway(F, g, "x", Z1 + 0.5, 56, 66, 56, 62, A)
    for z0, z1 in ((-22, -16), (16, 22)):
        F.box(g, "Window", "glass_hull", (X1 + 0.3, 1.5, z0), (X1 + 0.7, 4.5, z1), unbreakable=True)
    wall_strips(F, g, X0, X1, Z0, Z1, -2.6, A, skip=("e",))
    wall_strips(F, g, X0, X1, Z0, Z1, 22.5, A)
    wall_ribs(F, g, X0, X1, Z0, Z1, TOP, skip=("e",))
    outside(F, g, "w", X0, X1, Z0, Z1, TOP, A)
    lights(F, g, X0 + 3, X1 - 3, Z0 + 4, Z1 - 4, TOP, 2, 4, size=(6.0, 2.0))
    for z in (-18, -6, 6, 18):
        F.box(g, "Girder", "girder", (X0, 24.5, z - 0.5), (X1, 25.5, z + 0.5))

    # Main deck level: the west balcony, the east terrace (over an undercroft the lower
    # deck comes in through) and two catwalks between them along the north and south walls.
    g = m.group("Balcony", f)
    F.box(g, "Deck", "floor", (X0, -0.4, Z0), (38, 0, Z1))
    F.box(g, "Deck", "floor", (50, -0.4, Z0), (X1, 0, Z1))
    for s in (-1, 1):
        F.box(g, "Catwalk", "catwalk", (38, -0.3, min(s * 19, s * 24)), (50, 0, max(s * 19, s * 24)))
        F.rail(g, "x", s * 19, 38, 50, 0.0, gaps=[(40, 44)] if s < 0 else [(44, 48)])
    F.slab(g, "Ramp", "stair", (42, 0, -19), (42, LOW, -8), 4.0, thick=0.4)
    F.slab(g, "Ramp", "stair", (46, 0, 19), (46, LOW, 8), 4.0, thick=0.4)
    F.rail(g, "z", 38, -19, 19, 0.0, gaps=[(-1.5, 1.5)])
    F.rail(g, "z", 50, -19, 19, 0.0, gaps=[(-9, -6), (6, 9)])
    for z in (-18.7, -3, 3, 18.7):
        F.box(g, "Post", "girder", (37.4, LOW, z - 0.3), (38, -0.4, z + 0.3))
        F.box(g, "Post", "girder", (50, LOW, z - 0.3), (50.6, -0.4, z + 0.3))
    lights(F, g, 51, 65, Z0 + 3, Z1 - 3, -0.42, 2, 4, kind="light_dim", size=(3.0, 1.2))
    lights(F, g, 32.5, 37.5, Z0 + 2, Z1 - 2, -0.42, 1, 5, kind="light_dim", size=(1.2, 4.0))

    # The terraces: each step 6 m up. A ramp climbs the first; the rest is for the grapple.
    g = m.group("Terraces", f)
    F.box(g, "Terrace", "hull_white", (55, 0, -14), (X1, 6, 14), tint=T_HYDRO)
    F.box(g, "Terrace", "hull_white", (59, 6, -14), (X1, 12, 14), tint=T_HYDRO)
    F.box(g, "Terrace", "hull_white", (62.5, 12, -14), (X1, 18, 14), tint=T_HYDRO)
    F.slab(g, "Ramp", "stair", (53.6, 0, -13.5), (53.6, 6, -1.5), 2.8, thick=0.35)
    F.box(g, "RampTop", "catwalk", (52.2, 5.7, -1.5), (55, 6, 1.5))
    for y, x0 in ((6, 55), (12, 59), (18, 62.5)):
        F.strip(g, "TerraceLight", A, (x0 - 0.04, y - 0.33, -14), (x0 + 0.02, y - 0.1, 14))
    # Planting beds on every step (and in front of the terrace).
    for (x0, x1, y, zs) in ((50.6, 52.0, 0, ((-18.5, -15), (3, 12.5), (15, 18.5))), (56.6, 58.4, 6, ((-13, -6), (3.5, 13))),
                            (60.4, 62.0, 12, ((-13, -4), (-1, 5), (8, 13))), (64.0, 65.5, 18, ((-13, -8), (4, 13)))):
        for z0, z1 in zs:
            F.box(g, "Planter", "planter", (x0, y, z0), (x1, y + 0.7, z1))
            F.strip(g, "Soil", "soil", (x0 + 0.1, y + 0.7, z0 + 0.1), (x1 - 0.1, y + 0.74, z1 - 0.1))
            F.strip(g, "Plants", "plant", (x0 + 0.15, y + 0.74, z0 + 0.2), (x1 - 0.15, y + 1.25, z1 - 0.2))
            F.strip(g, "Plants", "plant_dark", (x0 + 0.4, y + 1.25, z0 + 0.5), (x1 - 0.4, y + 1.6, z1 - 0.5))

    # Across the open space: a bridge at 6 m to a ledge on the west wall, a high catwalk
    # at 14 m, irrigation pipes you can run along, and grow-light rigs hung at all heights.
    g = m.group("Crossings", f)
    F.box(g, "Bridge", "catwalk", (35, 5.7, -1.5), (52.2, 6, 1.5))
    F.box(g, "Ledge", "catwalk", (X0, 5.7, -10), (35, 6, 10))
    F.rail(g, "x", -1.5, 38, 50, 6.0)
    F.rail(g, "z", 35, -10, 10, 6.0, gaps=[(-1.5, 1.5), (-8, -5)])
    F.box(g, "HighCatwalk", "catwalk", (44, 13.7, Z0), (46.5, 14, Z1))
    for z in (-16, 0, 16):
        for x in (44.1, 46.4):
            F.box(g, "Hanger", "girder", (x - 0.12, 14, z - 0.12), (x + 0.12, 24.5, z + 0.12))
    m.lying_cyl(g, "Pipe", "pipe_blue", (49.0, 9.0, -11), 0.9, 34.0, axis="x", sides=10)
    m.lying_cyl(g, "Pipe", "pipe", (40.0, 19.0, 0), 0.9, 48.0, axis="z", sides=10)
    m.lying_cyl(g, "Pipe", "pipe_blue", (49.0, 21.0, 12), 0.9, 34.0, axis="x", sides=10)
    for (x, y, z, along) in ((41, 10.5, -8, "z"), (47, 17.5, 6, "z"), (41, 20.5, 14, "z"), (53, 10.5, 9, "z"), (57.5, 16, -6, "z"),
                             (61, 21, 4, "z"), (37, 12.5, 12, "z"), (48, 6.5, -15, "x")):
        if along == "z":
            lo, hi = (x - 0.7, y, z - 3.5), (x + 0.7, y + 0.4, z + 3.5)
        else:
            lo, hi = (x - 3.5, y, z - 0.7), (x + 3.5, y + 0.4, z + 0.7)
        F.box(g, "GrowRig", "trim", lo, hi)
        F.strip(g, "GrowLight", "grow_light", (lo[0] + 0.1, y - 0.06, lo[2] + 0.1), (hi[0] - 0.1, y, hi[2] - 0.1))
        F.box(g, "RigHanger", "girder", (x - 0.1, y + 0.4, z - 0.1), (x + 0.1, 24.5, z + 0.1))

    # Glass: grow rooms on the terrace's corners and panes along the undercroft. Shooting
    # them out opens sightlines; every one has an open way round it.
    g = m.group("GrowRooms", f)
    for s in (-1, 1):
        F.box(g, "Pane", "glass_pane", (52.1, 0, s * 15.6 - 0.1), (55, 3.6, s * 15.6 + 0.1))               # a grow room by the terrace
        F.box(g, "Pane", "glass_pane", (50, LOW, min(s * 4, s * 12)), (50.2, -0.5, max(s * 4, s * 12)))   # the undercroft's front
        F.box(g, "Pane", "glass_pane", (32.2, 0, s * 11 - 0.1), (35.2, 3.6, s * 11 + 0.1))                 # seedling bays on the west balcony
        F.box(g, "Tank", "tank", (58, LOW, min(s * 8, s * 12)), (62, LOW + 3.2, max(s * 8, s * 12)))
        F.strip(g, "TankLight", A, (57.98, LOW + 2.5, min(s * 8, s * 12)), (58.0, LOW + 2.8, max(s * 8, s * 12)))
    F.box(g, "Pump", "machine", (54, LOW, -1.5), (57, LOW + 2.0, 1.5))
    F.box(g, "Bed", "planter", (38.5, LOW, -3), (40.5, LOW + 0.8, 3))
    F.strip(g, "Plants", "plant", (38.7, LOW + 0.8, -2.8), (40.3, LOW + 1.5, 2.8))
    F.sign("HYDROPONICS", (X0 + 0.06, 8.6, 0), (1, 0), size=120, pixel=0.014, col=(0.55, 1, 0.6, 1))
    g = m.group("Details", f)
    corner_pipes(F, g, ((X0, Z0, 1, 1), (X0, Z1, 1, -1)), TOP)
    for z in (-7.5, 7.5):
        screen(F, g, "z", X0, 1, z, 2.3, A)
        vent(F, g, "z", X0, 1, z, 4.4)
    for s in (-1, 1):
        ribs(F, g, "z", X0, 1, (s * 6.2, s * 14.5, s * 20.0), 0.0, 5.7)
        vent(F, g, "z", X0, 1, s * 8.0, -5.3)
        F.strip(g, "Drain", "grate", (40.8, LOW, s * 5.6 - 0.4), (49.8, LOW + 0.012, s * 5.6 + 0.4))   # irrigation drains
    F.strip(g, "RampHazard", "hazard", (40.0, LOW, -7.95), (44.0, LOW + 0.04, -7.4))
    F.strip(g, "RampHazard", "hazard", (44.0, LOW, 7.4), (48.0, LOW + 0.04, 7.95))
    F.floor_label("IRRIGATION", (45.3, LOW + 0.06, 0), (1, 0), size=56, col=(0.55, 1, 0.6, 0.8))


# ---------------------------------------------------------------------------
# The outer ring: three corners alike (built as the north-east one), each with a side room

def corner(m, f, name, mat, room, x_start, accent_h, accent_v, room_h, room_v):
    """One corner of the ring corridor, on both decks: a leg along the north hull from
    the hangar's east door, a leg down the east hull to the hydroponics' north door, a
    side room in the angle between them, a ramp between the decks and a drop hole.
    x_start: where the first leg begins (the wall of the room it leaves)."""
    F = Frame(m, mat)
    g = m.group(name, f)
    hole = (40.0, 43.0, -62.5, -59.5)
    # Main deck
    F.deck(g, "Floor", "floor", x_start - 0.5, 67, -67, -56, 0.0, holes=[hole])
    F.box(g, "Floor", "floor", (55.2, -0.5, -56), (67, 0, -24.5))
    F.box(g, "Ceiling", "hull", (x_start, H, -67), (67, H + 0.5, -55.2))
    F.box(g, "Ceiling", "hull", (55.2, H, -55.2), (67, H + 0.5, -25))
    F.wall(g, "Hull", "hull", "x", -66.5, x_start, 67, LOW - 0.5, H, 1.0, [(34, 52, 1.4, 4.2), (54, 64, 1.4, 4.2)])
    F.wall(g, "Hull", "hull", "z", 66.5, -66, -25, LOW - 0.5, H, 1.0, [(-64, -58, 1.4, 4.2), (-53, -29, 1.4, 4.2)])
    F.box(g, "Window", "glass_hull", (34, 1.4, -66.7), (52, 4.2, -66.3), unbreakable=True)
    F.box(g, "Window", "glass_hull", (54, 1.4, -66.7), (64, 4.2, -66.3), unbreakable=True)
    F.box(g, "Window", "glass_hull", (66.3, 1.4, -64), (66.7, 4.2, -58), unbreakable=True)
    F.box(g, "Window", "glass_hull", (66.3, 1.4, -53), (66.7, 4.2, -29), unbreakable=True)
    for x in (40, 46, 59):
        F.strip(g, "Mullion", "trim", (x - 0.1, 1.4, -66.3), (x + 0.1, 4.2, -65.95))
    for z in (-47, -41, -35):
        F.strip(g, "Mullion", "trim", (65.95, 1.4, z - 0.1), (66.3, 4.2, z + 0.1))
    # Inner walls: the side room opens off both legs, an alcove off the first, the ramp off the second.
    F.wall(g, "Wall", "hull", "x", -55.6, x_start, 56, 0, H, 0.8, [(35.5, 39.5, 0, 4.0), (47, 55, 0, 5.0)])
    F.wall(g, "Wall", "hull", "z", 55.6, -56, -25, 0, H, 0.8, [(-55, -47, 0, 5.0), (-46, -42, 0, 4.5)])
    F.strip(g, "Strip", accent_h, (x_start + 0.5, 2.0, -56.04), (35.35, 2.22, -55.98))   # (stops at the alcove's doorway)
    F.strip(g, "Strip", accent_h, (39.65, 2.0, -56.04), (46.5, 2.22, -55.98))
    F.strip(g, "Strip", accent_v, (55.98, 2.0, -41.5), (56.04, 2.22, -25.5))
    F.strip(g, "FloorTrim", "trim", (x_start, 0, -66.0), (66, 0.02, -65.6))
    F.strip(g, "FloorTrim", "trim", (65.6, 0, -66), (66, 0.02, -25))
    lights(F, g, x_start + 2, 54, -63, -59, H, 3, 1, size=(4.0, 1.4))
    lights(F, g, 59, 63, -52, -28, H, 1, 3, size=(1.4, 4.0))
    hx0, hx1, hz0, hz1 = hole
    for lo, hi in (((hx0 - 0.3, 0, hz0 - 0.3), (hx1 + 0.3, 0.03, hz0)), ((hx0 - 0.3, 0, hz1), (hx1 + 0.3, 0.03, hz1 + 0.3)),
                   ((hx0 - 0.3, 0, hz0), (hx0, 0.03, hz1)), ((hx1, 0, hz0), (hx1 + 0.3, 0.03, hz1))):
        F.strip(g, "HoleRim", "accent_yellow", lo, hi)
    # A maintenance alcove
    F.box(g, "AlcoveFloor", "floor_dark", (35.5, -0.5, -55.2), (39.5, 0, -52.2))
    F.box(g, "AlcoveWall", "hull_dark", (34.9, 0, -55.2), (35.5, 4.6, -51.6))
    F.box(g, "AlcoveWall", "hull_dark", (39.5, 0, -55.2), (40.1, 4.6, -51.6))
    F.box(g, "AlcoveWall", "hull_dark", (35.5, 0, -52.2), (39.5, 4.6, -51.6))
    F.box(g, "AlcoveCeiling", "hull_dark", (34.9, 4.0, -55.2), (40.1, 4.6, -52.2))
    F.strip(g, "AlcovePipe", "pipe", (35.5, 0.6, -52.6), (39.5, 0.95, -52.25))
    F.strip(g, "AlcovePipe", "pipe_blue", (35.5, 2.6, -52.6), (39.5, 2.95, -52.25))
    F.strip(g, "AlcoveLight", "accent_yellow", (36.5, 3.9, -53.9), (38.5, 4.0, -53.5))
    # The side room in the angle
    F.box(g, "RoomFloor", "floor", (45.2, -0.5, -55.2), (55.2, 0, -45.2))
    F.box(g, "RoomCeiling", "hull", (45.2, H, -55.2), (55.2, H + 0.5, -45.2))
    F.box(g, "RoomWall", "hull", (45.2, 0, -55.2), (46, H, -45.2))
    F.box(g, "RoomWall", "hull", (46, 0, -46), (55.2, H, -45.2))
    F.strip(g, "RoomLight", "light", (48.5, H - 0.08, -52), (52.5, H, -50))
    side_room(F, g, room)
    # Ramp bay: main deck down to the lower deck
    F.box(g, "RampLanding", "floor", (51, -0.5, -46), (55.2, 0, -42))
    F.slab(g, "Ramp", "stair", (53.1, 0, -42), (53.1, LOW, -31), 4.2, thick=0.4)
    F.box(g, "RampFoot", "floor_dark", (51, LOW - 0.5, -31), (56, LOW, -27))
    F.box(g, "RampWall", "hull", (50.4, LOW - 0.5, -45.2), (51, H, -26.4))
    F.box(g, "RampWall", "hull", (50.4, LOW - 0.5, -27), (55.2, H, -26.4))
    F.box(g, "RampCeiling", "hull", (50.4, H, -45.2), (55.2, H + 0.5, -26.4))
    F.strip(g, "RampLight", "light_dim", (52.4, H - 0.08, -38), (53.8, H, -34))
    F.strip(g, "RampStrip", "accent_white", (50.98, 1.0, -41.5), (51.04, 1.2, -27.5))
    # Lower deck: tighter, darker, pipes along the walls
    F.box(g, "LowerFloor", "floor_dark", (x_start - 0.5, LOW - 0.5, -62.8), (62.8, LOW, -55.2))
    F.box(g, "LowerFloor", "floor_dark", (55.2, LOW - 0.5, -55.2), (62.8, LOW, -24.5))
    F.box(g, "LowerWall", "hull_dark", (x_start, LOW - 0.5, -62.8), (62.8, -0.5, -62))
    F.box(g, "LowerWall", "hull_dark", (62, LOW - 0.5, -62), (62.8, -0.5, -25))
    F.box(g, "LowerWall", "hull_dark", (x_start, LOW - 0.5, -56), (56, -0.5, -55.2))
    F.wall(g, "LowerWall", "hull_dark", "z", 55.6, -56, -25, LOW - 0.5, -0.5, 0.8, [(-31, -27, LOW - 0.5, -1.5)])   # (no sill: the floors run through)
    F.strip(g, "Pipe", "pipe", (x_start, -1.7, -61.98), (61.7, -1.35, -61.66))
    F.strip(g, "Pipe", "pipe_blue", (61.66, -1.2, -61.7), (61.98, -0.85, -25.5))
    F.strip(g, "Pipe", "pipe", (x_start, -2.4, -56.34), (55.5, -2.05, -56.02))
    F.strip(g, "LowLight", "light_dim", (x_start + 1, -3.2, -61.99), (61, -3.0, -61.93))
    F.strip(g, "LowLight", "light_dim", (61.93, -3.2, -61), (61.99, -3.0, -26))
    for x in (36, 48):
        F.box(g, "Valve", "machine", (x, LOW, -57.2), (x + 1.2, LOW + 1.3, -56))
    corner_details(F, m.group("Details", g), x_start, accent_h, accent_v, room_h, room_v, hole)


def corner_details(F, g, x_start, accent_h, accent_v, room_h, room_v, hole):
    """What the ring corridor's walls and floors carry (drawn only). room_h and accent_h:
    the room at the end of the first leg and its colour; room_v, accent_v: the second leg's."""
    # Main deck, hull side: a base and cornice, ribs between the windows, vents under
    # them and a conduit under the ceiling.
    xa, zb = x_start + 0.08, -25.08   # (clear of the lit frames of the rooms' doorways)
    F.on_wall(g, "Base", "rib", "x", -66, 1, xa, 66, 0.0, 0.35, 0.1)
    F.on_wall(g, "Base", "rib", "z", 66, -1, -66, zb, 0.0, 0.35, 0.1)
    F.on_wall(g, "Cornice", "rib", "x", -66, 1, xa, 66, 4.5, 4.7, 0.1)
    F.on_wall(g, "Cornice", "rib", "z", 66, -1, -66, zb, 4.5, 4.7, 0.1)
    F.on_wall(g, "Conduit", "pipe", "x", -66, 1, xa, 65.7, 5.6, 5.85, 0.25)
    F.on_wall(g, "Conduit", "pipe_blue", "z", 66, -1, -65.7, zb, 5.6, 5.85, 0.25)
    ribs(F, g, "x", -66, 1, [x_start + 1.2, 53.0, 65.0] + ([29.5] if x_start < 28 else []), 0.35, 4.5)
    ribs(F, g, "z", 66, -1, (-65.0, -55.5, -27.0), 0.35, 4.5)
    for x in (38.0, 48.0, 59.0):
        vent(F, g, "x", -66, 1, x, 0.55, h=0.5)
    for z in (-61.0, -47.0, -35.0):
        vent(F, g, "z", 66, -1, z, 0.55, h=0.5)
    # Inner walls: ribs, a display on each leg, vents.
    wall_band(F, g, "Base", "rib", "x", -56, -1, xa, 56, 0.0, 0.35, 0.1, [(35.5, 39.5, 0, 4.0), (47, 55, 0, 5.0)])
    wall_band(F, g, "Base", "rib", "z", 56, 1, -56, zb, 0.0, 0.35, 0.1, [(-55, -47, 0, 5.0), (-46, -42, 0, 4.5)])
    ribs(F, g, "x", -56, -1, [x_start + 1.2, 40.6, 46.1] + ([30.5] if x_start < 28 else []), 0.35, H)
    ribs(F, g, "z", 56, 1, (-41.3, -36.2, -30.2, -25.6), 0.35, H)
    screen(F, g, "x", -56, -1, 43.35, 2.7, accent_h)
    screen(F, g, "z", 56, 1, -33.2, 2.7, accent_v)
    vent(F, g, "x", -56, -1, 43.35, 4.6)
    vent(F, g, "z", 56, 1, -38.75, 4.2)
    vent(F, g, "z", 56, 1, -27.9, 0.6, h=0.5)
    if x_start < 28:
        vent(F, g, "x", -56, -1, 28.0, 4.2)
    # Ceiling beams between the lights.
    first = x_start + 2.0
    for i in (1, 2):
        x = first + (54.0 - first) * i / 3.0
        F.strip(g, "Beam", "girder", (x - 0.25, H - 0.35, -66), (x + 0.25, H, -56))
    for z in (-55.6, -44.0, -36.0, -27.0):
        F.strip(g, "Beam", "girder", (56, H - 0.35, z - 0.25), (66, H, z + 0.25))
    F.strip(g, "Beam", "girder", (55.35, H - 0.35, -66), (55.85, H, -56))
    # Floor: two lines to follow, one in each room's colour; grates where the corridor
    # meets each room; hazard stripes round the drop hole.
    F.strip(g, "GuideLine", accent_h, (x_start + 0.5, 0, -57.58), (57.58, 0.024, -57.42))
    F.strip(g, "GuideLine", accent_h, (57.42, 0, -57.42), (57.58, 0.024, -25.5))
    F.strip(g, "GuideLine", accent_v, (x_start + 0.5, 0, -57.18), (57.18, 0.024, -57.02))
    F.strip(g, "GuideLine", accent_v, (57.02, 0, -57.02), (57.18, 0.024, -25.5))
    F.chevron(g, accent_h, (x_start + 3.0, -58.3), (-1, 0), 0.0, size=0.7)
    F.chevron(g, accent_v, (58.3, -28.0), (0, 1), 0.0, size=0.7)
    F.strip(g, "Grate", "grate", (x_start + 0.6, 0, -65.5), (x_start + 1.4, 0.012, -56.5))
    F.strip(g, "Grate", "grate", (56.5, 0, -26.4), (65.5, 0.012, -25.6))
    hole_hazard(F, g, hole, 0.0)
    F.floor_label("DECK 1", (61.5, 0.06, -61.5), (1, 0))
    F.way_sign(room_v, (65.9, 5.08, -61.0), (-1, 0), (0, 1), size=44, pixel=0.008)
    F.way_sign(room_h, (61.0, 5.08, -65.9), (0, 1), (-1, 0), size=44, pixel=0.008)
    # Lower deck: ribs, junction boxes, cables overhead, a grate down the middle, and
    # stripes where you land under the drop hole.
    ribs(F, g, "x", -62, 1, [x for x in (30.0, 36.0, 42.0, 48.0, 54.0, 60.0) if x > x_start + 1], LOW, -0.5, width=0.3, depth=0.12, name="LowerRib")
    ribs(F, g, "z", 62, -1, (-51.0, -45.0, -39.0, -33.0, -27.0), LOW, -0.5, width=0.3, depth=0.12, name="LowerRib")
    junction_box(F, g, "x", -56, -1, 42.0, -5.0, accent_h)
    junction_box(F, g, "x", -56, -1, 52.5, -5.0, accent_h)
    junction_box(F, g, "z", 56, 1, -40.0, -5.0, accent_v)
    F.strip(g, "Cable", "cable", (x_start, -0.72, -59.3), (59.3, -0.5, -58.7))
    F.strip(g, "Cable", "cable", (58.7, -0.72, -59.3), (59.3, -0.5, -25.0))
    F.strip(g, "LowerGrate", "grate", (x_start + 0.5, LOW, -59.5), (59.5, LOW + 0.012, -58.5))
    F.strip(g, "LowerGrate", "grate", (58.5, LOW, -58.5), (59.5, LOW + 0.012, -25.5))
    F.strip(g, "LandingHazard", "hazard", (hole[0] - 0.5, LOW, -62.0), (hole[0], LOW + 0.04, -59.0))
    F.strip(g, "LandingHazard", "hazard", (hole[1], LOW, -62.0), (hole[1] + 0.5, LOW + 0.04, -59.0))
    F.strip(g, "LandingHazard", "hazard", (hole[0], LOW, -59.5), (hole[1], LOW + 0.04, -59.0))
    F.floor_label("DECK 2", (59.0, LOW + 0.06, -60.6), (1, 0), size=56)


def side_room(F, g, kind):
    if kind == "lounge":
        F.box(g, "Sofa", "sofa", (46.2, 0, -52), (47.3, 0.9, -47))
        F.box(g, "Sofa", "sofa", (48, 0, -47.1), (53, 0.9, -46.1))
        F.box(g, "Table", "table", (49.2, 0, -51), (51.2, 0.6, -49.5))
        F.box(g, "Planter", "planter", (46.2, 0, -46.9), (47.4, 1.0, -46.1))
        F.strip(g, "Plants", "plant", (46.3, 1.0, -46.8), (47.3, 1.9, -46.2))
        F.sign("OBSERVATION LOUNGE", (50.6, 5.3, -55.1), (0, -1), size=48, pixel=0.012)
    elif kind == "storage":
        for (x, z, w, d, h, k) in ((47.2, -47.5, 2.0, 2.4, 2.0, "crate"), (49.6, -47.3, 2.2, 2.0, 1.2, "crate_dark"),
                                   (47.0, -51.5, 1.6, 1.6, 1.4, "crate_dark"), (53.2, -47.2, 2.0, 2.0, 2.6, "crate")):
            F.box(g, "Crate", k, (x - w / 2, 0, z - d / 2), (x + w / 2, h, z + d / 2))
        F.sign("STORAGE", (50.6, 5.3, -55.1), (0, -1), size=48, pixel=0.012)
    else:
        for x in (47.6, 51.8):
            F.box(g, "Bed", "medbed", (x - 0.9, 0, -48.4), (x + 0.9, 0.8, -46.1))
            F.strip(g, "BedLight", "med_green", (x - 0.9, 1.6, -46.14), (x + 0.9, 1.75, -46.08))
        F.box(g, "Cabinet", "medbed", (46.1, 0, -53.5), (46.9, 2.0, -50))
        F.strip(g, "Cross", "med_green", (46.9, 1.2, -52.2), (46.95, 1.5, -51.3))
        F.sign("MEDBAY", (50.6, 5.3, -55.1), (0, -1), size=48, pixel=0.012)


# ---------------------------------------------------------------------------
# Cryo and habitat (south-west): the one tight part of the map

def cryo(m):
    F = Frame(m)
    f = m.folder("Cryo")
    A = "accent_ice"
    CH = 5.0   # ceilings are lower here
    g = m.group("Corridor", f)
    hole = (-65.0, -62.0, 61.5, 64.5)
    F.deck(g, "Floor", "floor", -67, -59.2, 24.5, 67, 0.0, holes=[hole])
    F.box(g, "Floor", "floor", (-59.2, -0.5, 59.2), (-24.5, 0, 67))
    F.box(g, "Ceiling", "hull", (-67, CH, 25), (-59.2, CH + 0.5, 67))
    F.box(g, "Ceiling", "hull", (-59.2, CH, 59.2), (-25, CH + 0.5, 67))
    F.wall(g, "Hull", "hull", "z", -66.5, 25, 67, LOW - 0.5, CH, 1.0, [(30, 44, 1.4, 3.8), (48, 58, 1.4, 3.8)], tint=T_CRYO)
    F.wall(g, "Hull", "hull", "x", 66.5, -66, -25, LOW - 0.5, CH, 1.0, [(-58, -44, 1.4, 3.8), (-40, -30, 1.4, 3.8)], tint=T_CRYO)
    F.box(g, "Window", "glass_hull", (-66.7, 1.4, 30), (-66.3, 3.8, 44), unbreakable=True)
    F.box(g, "Window", "glass_hull", (-66.7, 1.4, 48), (-66.3, 3.8, 58), unbreakable=True)
    F.box(g, "Window", "glass_hull", (-58, 1.4, 66.3), (-44, 3.8, 66.7), unbreakable=True)
    F.box(g, "Window", "glass_hull", (-40, 1.4, 66.3), (-30, 3.8, 66.7), unbreakable=True)
    # Inner walls of the two legs, with doorways and pod-bay windows (glass that breaks).
    F.wall(g, "Wall", "hull", "z", -59.6, 25, 60, 0, CH, 0.8,
           [(36, 39, 0, 3.4), (41, 47, 0.9, 3.4), (49, 52, 0, 3.4), (54, 58.5, 0.9, 3.4)], tint=T_CRYO)
    F.wall(g, "Wall", "hull", "x", 59.6, -60, -25, 0, CH, 0.8,
           [(-57.5, -52, 0.9, 3.4), (-50, -47, 0, 3.4), (-39.5, -35.5, 0.9, 3.4), (-34, -31, 0, 3.4)], tint=T_CRYO)
    F.box(g, "Pane", "glass_pane", (-59.7, 0.9, 41), (-59.5, 3.32, 47))
    F.box(g, "Pane", "glass_pane", (-59.7, 0.9, 54), (-59.5, 3.32, 58.5))
    F.box(g, "Pane", "glass_pane", (-57.5, 0.9, 59.5), (-52, 3.32, 59.7))
    F.box(g, "Pane", "glass_pane", (-39.5, 0.9, 59.5), (-35.5, 3.32, 59.7))
    F.strip(g, "Strip", A, (-66.02, 0.9, 26), (-65.96, 1.1, 65))
    F.strip(g, "Strip", A, (-65, 0.9, 65.96), (-26, 1.1, 66.02))
    F.strip(g, "FloorTrim", "trim", (-66, 0, 25), (-65.6, 0.02, 66))
    F.strip(g, "FloorTrim", "trim", (-66, 0, 65.6), (-25, 0.02, 66))
    for z in (37, 51):
        F.strip(g, "Mullion", "trim", (-66.3, 1.4, z - 0.1), (-65.95, 3.8, z + 0.1))
    for x in (-51, -35):
        F.strip(g, "Mullion", "trim", (x - 0.1, 1.4, 65.95), (x + 0.1, 3.8, 66.3))
    F.strip(g, "Strip", A, (-60.04, 4.3, 26), (-59.98, 4.5, 59))
    F.strip(g, "Strip", A, (-59, 4.3, 59.98), (-26, 4.5, 60.04))
    lights(F, g, -65, -61, 28, 58, CH, 1, 4, kind="light_dim", size=(1.2, 3.0))
    lights(F, g, -58, -28, 61, 65, CH, 4, 1, kind="light_dim", size=(3.0, 1.2))
    hx0, hx1, hz0, hz1 = hole
    for lo, hi in (((hx0 - 0.3, 0, hz0 - 0.3), (hx1 + 0.3, 0.03, hz0)), ((hx0 - 0.3, 0, hz1), (hx1 + 0.3, 0.03, hz1 + 0.3)),
                   ((hx0 - 0.3, 0, hz0), (hx0, 0.03, hz1)), ((hx1, 0, hz0), (hx1 + 0.3, 0.03, hz1))):
        F.strip(g, "HoleRim", "accent_yellow", lo, hi)
    # Lower deck under both legs
    F.box(g, "LowerFloor", "floor_dark", (-67, LOW - 0.5, 24.5), (-59.2, LOW, 67))
    F.box(g, "LowerFloor", "floor_dark", (-59.2, LOW - 0.5, 59.2), (-24.5, LOW, 67))
    F.box(g, "LowerWall", "hull_dark", (-60, LOW - 0.5, 25), (-59.2, -0.5, 60))
    F.box(g, "LowerWall", "hull_dark", (-60, LOW - 0.5, 59.2), (-25, -0.5, 60))
    F.strip(g, "Pipe", "pipe", (-60.34, -1.7, 25.5), (-60.02, -1.35, 59.5))
    F.strip(g, "Pipe", "pipe_blue", (-59.5, -1.2, 60.02), (-25.5, -0.85, 60.34))
    F.strip(g, "LowLight", "light_dim", (-65.99, -3.2, 26), (-65.93, -3.0, 65))
    F.strip(g, "LowLight", "light_dim", (-65, -3.2, 65.93), (-26, -3.0, 65.99))
    F.sign("CRYO BAY", (-60.1, 4.0, 43.9), (-1, 0), size=56, pixel=0.012, col=(0.75, 0.9, 1, 1))
    F.sign("CREW MESS", (-32.5, 4.0, 60.1), (0, 1), size=56, pixel=0.012, col=(0.75, 0.9, 1, 1))

    # Details, as in the other corners of the ring (the cargo bay's and engineering's
    # colours lead out of here).
    g = m.group("Details", f)
    F.on_wall(g, "Base", "rib", "z", -66, 1, 25.08, 66, 0.0, 0.3, 0.1)   # (25.08: clear of the lit frames of the rooms' doorways)
    F.on_wall(g, "Base", "rib", "x", 66, -1, -66, -25.08, 0.0, 0.3, 0.1)
    F.on_wall(g, "Conduit", "pipe_blue", "z", -66, 1, 25.08, 65.7, 4.55, 4.8, 0.25)
    F.on_wall(g, "Conduit", "pipe", "x", 66, -1, -65.7, -25.08, 4.55, 4.8, 0.25)
    ribs(F, g, "z", -66, 1, (27.5, 46.0, 59.5), 0.3, 4.55)
    ribs(F, g, "x", 66, -1, (-59.5, -42.0, -27.5), 0.3, 4.55)
    for z in (33.5, 40.5, 53.0):
        vent(F, g, "z", -66, 1, z, 0.42, h=0.4)
    for x in (-54.5, -47.5, -35.0):
        vent(F, g, "x", 66, -1, x, 0.42, h=0.4)
    ribs(F, g, "z", -60, -1, (26.5, 33.0, 40.2, 47.8, 53.2), 0.0, CH)
    ribs(F, g, "x", 60, 1, (-58.6, -51.0, -45.5, -40.5, -30.2, -26.5), 0.0, CH)
    for z in (35.5, 43.0, 50.5, 58.4):
        F.strip(g, "Beam", "girder", (-66, CH - 0.3, z - 0.2), (-60, CH, z + 0.2))
    for x in (-50.5, -43.0, -35.5, -27.6):
        F.strip(g, "Beam", "girder", (x - 0.2, CH - 0.3, 60), (x + 0.2, CH, 66))
    F.strip(g, "GuideLine", "accent_yellow", (-61.58, 0, 25.5), (-61.42, 0.024, 61.58))
    F.strip(g, "GuideLine", "accent_yellow", (-61.42, 0, 61.42), (-25.5, 0.024, 61.58))
    F.strip(g, "GuideLine", "accent_orange", (-61.18, 0, 25.5), (-61.02, 0.024, 61.18))
    F.strip(g, "GuideLine", "accent_orange", (-61.02, 0, 61.02), (-25.5, 0.024, 61.18))
    F.chevron(g, "accent_yellow", (-62.3, 28.0), (0, -1), 0.0, size=0.7)
    F.chevron(g, "accent_orange", (-28.0, 62.3), (1, 0), 0.0, size=0.7)
    F.strip(g, "Grate", "grate", (-65.5, 0, 25.6), (-60.5, 0.012, 26.4))
    F.strip(g, "Grate", "grate", (-26.4, 0, 60.5), (-25.6, 0.012, 65.5))
    hole_hazard(F, g, hole, 0.0, wide=0.35)
    F.floor_label("DECK 1", (-63.2, 0.06, 58.6), (0, 1))
    F.way_sign("ENGINEERING", (-63.0, 4.2, 65.9), (0, -1), (1, 0), size=40, pixel=0.008)
    F.way_sign("CARGO BAY", (-65.9, 4.2, 63.0), (1, 0), (0, -1), size=40, pixel=0.008)
    # Lower deck
    ribs(F, g, "z", -60, -1, (30.0, 36.0, 42.0, 48.0, 54.0), LOW, -0.5, width=0.3, depth=0.12, name="LowerRib")
    ribs(F, g, "x", 60, 1, (-55.0, -49.0, -43.0, -37.0, -31.0), LOW, -0.5, width=0.3, depth=0.12, name="LowerRib")
    junction_box(F, g, "z", -60, -1, 39.0, -5.0, A)
    junction_box(F, g, "x", 60, 1, -40.0, -5.0, A)
    F.strip(g, "Cable", "cable", (-61.3, -0.72, 25.0), (-60.7, -0.5, 61.3))   # (clear of the drop hole)
    F.strip(g, "Cable", "cable", (-61.3, -0.72, 60.7), (-25.0, -0.5, 61.3))
    F.strip(g, "LowerGrate", "grate", (-63.5, LOW, 25.5), (-62.5, LOW + 0.012, 60.5))
    F.strip(g, "LowerGrate", "grate", (-62.5, LOW, 62.5), (-25.5, LOW + 0.012, 63.5))
    hole_hazard(F, g, (hole[0] + 0.5, hole[1] - 0.5, hole[2] + 0.5, hole[3] - 0.5), LOW, inner=0.5, wide=0.4)
    F.floor_label("DECK 2", (-56.0, LOW + 0.06, 63.0), (1, 0), size=56)

    # The pod bay: rows of pods with narrow aisles between them.
    g = m.group("PodBay", f)
    F.box(g, "Floor", "floor", (-59.2, -0.5, 33), (-41.2, 0, 59.2), tint=T_CRYO)
    F.box(g, "Ceiling", "hull", (-59.2, 4.4, 33), (-41.2, 5.0, 59.2))
    F.box(g, "Wall", "hull", (-59.2, 0, 33), (-41.2, 4.4, 33.8), tint=T_CRYO)
    F.wall(g, "Wall", "hull", "z", -41.6, 33.8, 59.2, 0, 4.4, 0.8, [(44, 47.5, 0, 3.2), (53, 57, 0.9, 3.2)], tint=T_CRYO)
    F.box(g, "Pane", "glass_pane", (-41.7, 0.9, 53), (-41.5, 3.12, 57))
    # (x of the pod's back, which way it faces, the doorways in the wall behind it)
    rows = ((-59.2, 1, ((36, 39), (49, 52))), (-53.6, -1, ()), (-53.4, 1, ()), (-47.8, -1, ()), (-47.6, 1, ()),
            (-42.0, -1, ((44, 47.5),)))
    for x, face, doors in rows:
        lo_x, hi_x = (x, x + 1.0) if face > 0 else (x - 1.0, x)
        front = hi_x if face > 0 else lo_x
        for i in range(6):
            z = 37.0 + i * 2.8
            if any(z < d1 + 0.4 and z + 1.6 > d0 - 0.4 for d0, d1 in doors):
                continue
            F.box(g, "Pod", "pod", (lo_x, 0, z), (hi_x, 2.5, z + 1.6))
            F.strip(g, "PodCap", "trim", (lo_x - 0.06, 2.5, z - 0.06), (hi_x + 0.06, 2.72, z + 1.66))
            F.strip(g, "PodFoot", "trim", (lo_x - 0.06, 0, z - 0.06), (hi_x + 0.06, 0.2, z + 1.66))
            F.strip(g, "PodGlow", "pod_glow", (front - 0.03, 0.7, z + 0.3), (front + 0.03, 2.1, z + 1.3))
    lights(F, g, -57, -43.5, 36, 57, 4.4, 3, 3, kind="light_dim", size=(1.0, 3.0))
    for i, x in enumerate((-56.4, -50.6, -44.8)):   # the aisles: a line down each and its letter at the end
        F.strip(g, "AisleLine", A, (x - 0.06, 0, 36.6), (x + 0.06, 0.024, 58.6))
        F.floor_label("ROW " + "ABC"[i], (x, 0.06, 35.4), (0, 1), size=48, col=(0.75, 0.9, 1, 0.8))
        vent(F, g, "x", 33.8, 1, x, 3.4, w=1.6, h=0.5)

    # Crew mess and bunks.
    g = m.group("Mess", f)
    F.box(g, "Floor", "floor", (-41.2, -0.5, 40), (-25, 0, 59.2), tint=T_CRYO)
    F.box(g, "Ceiling", "hull", (-41.2, 4.4, 40), (-25, 5.0, 59.2))
    F.box(g, "Wall", "hull", (-41.2, 0, 40), (-25, 4.4, 40.8), tint=T_CRYO)
    F.box(g, "Wall", "hull", (-25.8, 0, 40.8), (-25, 4.4, 59.2), tint=T_CRYO)
    for z in (44.5, 50.5):
        F.box(g, "Table", "table", (-37, 0, z), (-33, 0.85, z + 1.4))
        F.box(g, "Bench", "seat", (-37, 0, z - 0.9), (-33, 0.45, z - 0.4))
        F.box(g, "Bench", "seat", (-37, 0, z + 1.8), (-33, 0.45, z + 2.3))
    for z in (42, 46.5, 51):
        F.box(g, "Bunk", "bunk", (-27.8, 0, z), (-25.8, 0.6, z + 3.2))
        F.box(g, "Bunk", "bunk", (-27.8, 1.9, z), (-25.8, 2.2, z + 3.2))
        F.box(g, "BunkEnd", "trim", (-27.8, 0, z + 3.2), (-25.8, 2.6, z + 3.4))
    F.box(g, "Counter", "table", (-40.4, 0, 41), (-36, 1.0, 42))
    F.strip(g, "CounterLight", A, (-40.4, 1.0, 41), (-36, 1.04, 42))
    lights(F, g, -40, -27, 42, 58, 4.4, 2, 2, kind="light_dim", size=(3.0, 1.0))
    screen(F, g, "x", 40.8, 1, -31.5, 1.9, A, w=3.0, h=1.4)
    vent(F, g, "x", 40.8, 1, -38.2, 3.5, h=0.5)
    F.on_wall(g, "Base", "rib", "x", 40.8, 1, -36.0, -25.8, 0.0, 0.3, 0.1)


# ---------------------------------------------------------------------------
# Outside the hull, and the event

def centrifuge(m):
    """The centrifuge ring: 84 m out, turning round the ship's long (north-south) axis, so
    it sweeps over the dome and under the floor glass. Its node is tipped so that its own
    y axis, the one a MapSpinner turns round, lies along z."""
    g = m.node("Centrifuge", ".", "spinner", [("transform", xform(((1, 0, 0), (0, 0, 1), (0, -1, 0)), (0, 2, 0))), ("speed", "6.0")])
    m.block(g, "Ring", "ring", (0, 0, 0), (176, 14, 176), shape="tube", inner=167, sides=48, solid=False)
    for y in (-8.5, 8.5):
        m.block(g, "Track", "ring_dark", (0, y, 0), (172, 1.6, 172), shape="tube", inner=168.5, sides=48, solid=False)
    for i in range(16):
        deg = i * 22.5
        cols = yaw_cols(math.radians(deg))
        m.block(g, "Module", "ring_dark", polar(81.6, deg), (11.0, 11.0, 3.6), cols=cols, solid=False)
        for y in (-2.6, 2.6):
            m.block(g, "Windows", "ring_light", polar(79.75, deg, y), (8.0, 0.9, 0.12), cols=cols, solid=False)
        m.block(g, "Beacon", "ring_light", polar(88.2, deg + 11.25), (1.6, 1.6, 0.5), cols=yaw_cols(math.radians(deg + 11.25)), solid=False)


def event(m):
    boxes = [(-13, 0.5, -13, 26, 12, 26), (-29, -5, -65, 58, 30, 32), (-23, -5, 33, 46, 30, 32),
             (-65, -5, -23, 32, 28, 46), (33, -5, -23, 32, 30, 46)]
    m.node("LowGravity", ".", "gravity", [
        ("mote_volumes", "Array[AABB]([%s])" % ", ".join("AABB(%s)" % ", ".join(fmt(v) for v in b) for b in boxes))], type_="Node")


# ---------------------------------------------------------------------------
# Players and pickups

def spawns(m):
    """22 spawn points on both decks, in every room but the control room. None can see the
    dais (tests/halcyon_test.gd checks). Each faces open floor."""
    for p, t in [
        # hangar: deck, deck, west balcony
        ((-23, LOW, -60), (0, -52)), ((26.5, LOW, -47), (5, -50)), ((-25, 0, -47), (0, -50)),
        # engineering: floor, floor, east balcony
        ((-15, LOW, 40), (-15, 56)), ((16, LOW, 57), (12, 40)), ((21.5, 0, 42), (0, 49)),
        # cargo: under the north balcony, the east lane, the balcony
        ((-63, LOW, -21), (-45, -21)), ((-41, LOW, -3), (-41, 12)), ((-35, 0, 19), (-35, 0)),
        # hydroponics: atrium floor, undercroft, west balcony, terrace corner
        ((47, LOW, -12), (47, 8)), ((63, LOW, 2), (52, 0)), ((35, 0, -17), (45, -17)), ((60, 0, 20), (52, 10)),
        # cryo: the mess, the west corridor
        ((-31, 0, 47), (-38, 47)), ((-63, 0, 33), (-63, 50)),
        # the ring's side rooms
        ((52.5, 0, -52.5), (58, -60)), ((-52.5, 0, -52.5), (-58, -60)), ((52.5, 0, 52.5), (58, 60)),
        # lower deck
        ((47, LOW, -59), (60, -59)), ((-59, LOW, -40), (-59, -28)), ((40, LOW, 59), (28, 59)), ((0, LOW, -21.5), (0, -31)),
    ]:
        m.spawn(p, t)


def pickups(m):
    """16 pickups, 16 different weapons. The five heavy ones sit up high where only the
    grapple (or low gravity) takes you; the rest are in the corridors, the ring and the
    lower deck. Nothing in the control room."""
    for p, w in [
        ((6.5, 16, 49), "rocket_launcher"),      # the top catwalk ring round the reactor
        ((0, 14, -50), "railgun"),               # the hangar's launch gantry
        ((64.2, 18, 0), "bolt_action"),               # the top hydroponics terrace
        ((-56.7, LOW + 15.6, -2), "grenade_launcher"),   # the six-high container stack
        ((28, 20, -54), "lmg"),                  # the perch high on the hangar's east wall
        ((-50.1, 0, 46), "shotgun"),             # a cryo pod aisle
        ((48, 0, -61), "smg"), ((61, 0, 40), "revolver"), ((-61, 0, -40), "break_action"),   # the ring
        ((-21, 0, -0.5), "rifle"), ((21, 0, 0.5), "burst_rifle"),                           # the west and east spokes
        ((-34.5, 0, 56.5), "sword"),             # the crew mess
        ((0, LOW, 14.5), "lever_action"),        # the round passage under the control room
        ((59, LOW, -45), "bolt_action"), ((-63, LOW, 45), "hammer"), ((0, LOW, 24), "machine_pistol"),   # lower deck
    ]:
        m.weapon(p, w)
