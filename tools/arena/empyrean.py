"""Empyrean Tower: a wizard's tower in low orbit (183 m tall, up to 16 players).

    python3 tools/arena/build_arena_maps.py empyrean

writes game/maps/empyrean.tscn and game/maps/palettes/empyrean.tres FROM SCRATCH. The
scene is an ordinary map scene and is what people edit afterwards (in the Godot editor),
so running this again OVERWRITES ANY HAND EDITS: only do it to rebuild the whole map on
purpose.

The tower is round and tapers: 61 m across at its foot (y = 0), 40 m at the eaves
(y = 183), under a conical roof with a crystal and an orrery at its peak; a root of rock
hangs under it. Six tiers of 30.5 m, from the bottom: Arcane Engine (cyan), Grand Library
(gold), Alchemy Labs (green), Menagerie (teal), Summoning Chamber (violet), Observatory
(silver). A hollow shaft 16 m across runs up the middle from the Engine's core to the
Observatory.

Every tier but the top one is the same plan, turned the same way (so stairs and lifts
line up from tier to tier), measured in 24 sectors of 15 degrees:
  - sectors 0-9 (0 to 150 degrees): the feature room, open to the shaft, 19 m tall,
    with balconies along its back wall at 6.35 m and (at both ends) 12.7 m;
  - sectors 10-23: three storeys (0, 6.35, 12.7 m) of rooms on the shaft side and a
    corridor along the outer wall, two lanes wide. The outer lane carries two spiral
    ramps, one from each end, up to 19 m;
  - 19 m: the upper hall, all the way round, from which two long ramps climb to the
    next tier.
The Observatory is one room under the roof with a gallery half way round.

Outside (40% gravity: MapRoot.gravity_outside, with MapGravityZones filling the tower):
thrusters and buttresses round the foot, balconies at every tier behind force-field
doorways, the docking ring at 91.5 m with a parked starship, sensor masts on the roof,
and a field of debris with three chunks that orbit (MapIslands turned by an OrbitEvent).

Angles are measured the way a node's yaw is: 0 = south (+z), 90 = east (+x). `P(r, deg,
y)` is a point; a block placed with `rot(deg)` has its own z pointing outward and its
own x along the wall.
"""
import math
import random
from arena_builder import xform, fmt, vec, color, norm, cross, IDENTITY, yaw_cols
from cirrus import CirrusMap, FLIP, LIE_X, LIE_Z

PAL = "res://game/maps/palettes/empyrean.tres"
SKY = "res://game/maps/sky/empyrean_sky.gdshader"

TIER = 30.5            # a tier's height
TIERS = 6
TOP = TIER * TIERS     # the eaves: 183 m
R_FOOT = 30.5          # the wall's outer face at y = 0
R_TOP = 20.0           # ...and at the eaves
WALL = 1.0             # the shell's thickness
RS = 8.0               # the shaft's radius
SEG = 48               # wall pieces round the tower (7.5 degrees each)
SEC = 24               # floor sectors (15 degrees each)
L1, L2, L3 = 6.35, 12.7, 19.0   # the storeys inside a tier, above its floor
BAND = 5.2             # the corridor: two lanes along the outer wall
LANE = 2.6
FEAT = 10              # sectors 0..9 are the feature room
ROOT_DEPTH = 42.0      # the root rock hangs this far below y = 0
KILL = -(ROOT_DEPTH + 46.0)     # the burn layer: 150 ft below the lowest rock
NAMES = ["ArcaneEngine", "GrandLibrary", "AlchemyLabs", "Menagerie", "SummoningChamber", "Observatory"]
ACCENT = ["accent_cyan", "accent_gold", "accent_green", "accent_teal", "accent_violet", "accent_silver"]
ACCENT_RGB = [(0.25, 0.9, 1.0), (1.0, 0.76, 0.28), (0.35, 0.95, 0.4), (0.2, 0.85, 0.7), (0.66, 0.4, 1.0), (0.88, 0.92, 1.0)]
LIFT_A, LIFT_B = 75.0, 255.0    # the shaft lifts' angles
LIFT_R = RS - 1.75
DOOR_N, DOOR_W = 213.75, 303.75 # the corridor's two doors to the outside (the middles of wall pieces 28 and 40)
LIFT_C, LIFT_D = DOOR_W, DOOR_N # the outside lifts stand off those doors' balconies
C_R = R_FOOT + 3.2              # ...and how far out their beams stand
D_R = 0.0                       # (set below, from the docking ring)
RING_Y = TIER * 3               # the docking ring: the Menagerie's floor
RING_R = 37.0
PAD_DEG = 255.0                 # the landing pad, and the starship on it


def ro(y):
    """The wall's outer face at height y."""
    return R_FOOT - (R_FOOT - R_TOP) * (y / TOP)


def ri(y):
    return ro(y) - WALL


D_R = ro(RING_Y) + 3.6
TILT = math.atan((R_FOOT - R_TOP) / TOP)    # how far the wall leans in


def rc(i):
    """Tier i's corridor wall: where the rooms end and the corridor begins."""
    return ri(TIER * (i + 1)) - BAND


def P(r, deg, y=0.0):
    th = math.radians(deg)
    return (r * math.sin(th), y, r * math.cos(th))


def rot(deg):
    return yaw_cols(math.radians(deg))


def lean(deg, tilt=TILT):
    """A wall piece's own frame at angle deg: x along the wall, y up and leaning in, z outward."""
    th = math.radians(deg)
    out = (math.sin(th), 0.0, math.cos(th))
    X = (math.cos(th), 0.0, -math.sin(th))
    Y = norm((-out[0] * math.sin(tilt), math.cos(tilt), -out[2] * math.sin(tilt)))
    return (X, Y, cross(X, Y))


def chord(r, n):
    """How wide a box must be to fill one of n sectors at radius r."""
    return 2.0 * r * math.tan(math.pi / n)


COLORS = {
    # the fantasy half: pale stone, brass, dark trim
    "stone": (0.84, 0.78, 0.68), "stone_floor": (0.58, 0.52, 0.46), "stone_dark": (0.33, 0.28, 0.33),
    # each tier's own floor: flags laid in rings round the shaft, a rune glowing on some
    "floor_engine": (0.4, 0.41, 0.47), "floor_library": (0.68, 0.56, 0.42), "floor_labs": (0.52, 0.56, 0.5),
    "floor_menagerie": (0.46, 0.5, 0.44), "floor_summoning": (0.3, 0.25, 0.37), "floor_observatory": (0.2, 0.22, 0.36),
    "brass": (0.8, 0.6, 0.26), "wood": (0.42, 0.29, 0.2), "roof": (0.3, 0.26, 0.42),
    "rock": (0.42, 0.38, 0.44), "rock_dark": (0.27, 0.24, 0.31),
    # the sci-fi half: gunmetal and silver alloy, darker seams
    "alloy": (0.62, 0.66, 0.72), "alloy_floor": (0.45, 0.48, 0.54), "alloy_dark": (0.2, 0.22, 0.27),
    "ship": (0.74, 0.77, 0.83), "ramp": (0.5, 0.5, 0.56), "catwalk": (0.36, 0.38, 0.44),
    # light
    "glow": (1.0, 0.82, 0.45), "conduit": (0.35, 0.9, 1.0), "screen": (0.85, 0.95, 1.0),
    "accent_cyan": ACCENT_RGB[0], "accent_gold": ACCENT_RGB[1], "accent_green": ACCENT_RGB[2],
    "accent_teal": ACCENT_RGB[3], "accent_violet": ACCENT_RGB[4], "accent_silver": ACCENT_RGB[5],
    "crystal": (0.6, 0.95, 1.0, 0.82), "hazard_glow": (1.0, 0.45, 0.95), "jet": (0.5, 0.85, 1.0, 0.55),
    "burn": (1.0, 0.55, 0.3, 0.2), "burn_haze": (1.0, 0.7, 0.5, 0.06),
    # see-through
    "field": (0.45, 0.8, 1.0, 0.22), "holo": (0.5, 0.95, 1.0, 0.34), "holo_gold": (1.0, 0.82, 0.4, 0.36),
    "glass_stained": (0.75, 0.4, 0.95, 0.42), "glass_clear": (0.75, 0.9, 1.0, 0.2), "fluid": (0.4, 1.0, 0.5, 0.45),
    # things
    "books_red": (0.6, 0.2, 0.2), "books_blue": (0.2, 0.3, 0.55), "books_green": (0.22, 0.42, 0.3),
    "leaf": (0.24, 0.6, 0.42), "leaf_alien": (0.5, 0.3, 0.72), "vine": (0.2, 0.44, 0.34), "soil": (0.3, 0.24, 0.2),
    "drone": (0.82, 0.84, 0.9), "planet_holo": (0.3, 0.9, 0.85, 0.4),
    # decor
    "cloth_blue": (0.15, 0.22, 0.52), "cloth_red": (0.52, 0.13, 0.17), "cloth_green": (0.15, 0.38, 0.24),
    "cloth_teal": (0.1, 0.36, 0.4), "cloth_violet": (0.33, 0.16, 0.52), "carpet": (0.42, 0.11, 0.2),
    "parchment": (0.87, 0.79, 0.6), "flame": (1.0, 0.6, 0.22), "slit": (1.0, 0.74, 0.38),
    # phantoms: the impossible things outside, plainly not there
    "phantom": (0.72, 0.8, 1.0, 0.3), "phantom_light": (0.86, 0.9, 1.0, 0.55), "phantom_roof": (0.52, 0.45, 0.9, 0.42),
}
GLOW = {"glow": 1.6, "conduit": 2.0, "screen": 1.2, "accent_cyan": 1.8, "accent_gold": 1.6, "accent_green": 1.6,
        "accent_teal": 1.7, "accent_violet": 1.9, "accent_silver": 1.3, "crystal": 2.4, "hazard_glow": 3.0, "jet": 3.0,
        "burn": 1.9, "burn_haze": 1.3, "field": 1.6, "holo": 1.5, "holo_gold": 1.5, "fluid": 1.3, "planet_holo": 1.4,
        "glass_stained": 0.35, "flame": 2.6, "slit": 1.7, "phantom": 0.8, "phantom_light": 1.5, "phantom_roof": 0.9}
SURFACE = {"stone": "masonry_runes", "stone_floor": "ring_flags", "stone_dark": "masonry_small",
           "floor_engine": "ring_flags_cyan", "floor_library": "ring_flags", "floor_labs": "ring_flags_green",
           "floor_menagerie": "ring_flags_teal", "floor_summoning": "ring_flags_violet", "floor_observatory": "ring_flags_stars", "alloy": "arcane_plates", "alloy_floor": "arcane_plates",
           "alloy_dark": "panels_plain", "ship": "panels_plain", "ramp": "treads", "catwalk": "grating", "roof": "shingles",
           "rock": "strata", "rock_dark": "strata", "wood": "planks"}
MATERIAL = {"floor_engine": "concrete", "floor_library": "concrete", "floor_labs": "concrete", "floor_menagerie": "concrete",
            "floor_summoning": "concrete", "floor_observatory": "concrete", "carpet": "wood",
            "stone": "concrete", "stone_floor": "concrete", "stone_dark": "concrete", "rock": "concrete", "rock_dark": "concrete",
            "alloy": "metal", "alloy_floor": "metal", "alloy_dark": "metal", "ship": "metal", "ramp": "metal", "catwalk": "metal",
            "brass": "metal", "glass_stained": "glass", "glass_clear": "glass", "wood": "wood", "roof": "concrete"}
BREAKABLE = {"glass_stained": 25}
FLOORS = ["floor_engine", "floor_library", "floor_labs", "floor_menagerie", "floor_summoning", "floor_observatory"]


class EmpyreanMap(CirrusMap):
    """CirrusMap (shapes that are not boxes, nodes with other scripts) with this map's nodes."""

    EXTRA = {
        "island": "res://game/arena/map_island.gd", "spinner": "res://game/arena/map_spinner.gd",
        "hook": "res://game/arena/map_grapple_point.gd", "link": "res://game/arena/map_jump_link.gd",
        "zone": "res://game/arena/map_gravity_zone.gd", "hazard": "res://game/arena/map_hazard.gd",
        "lift": "res://game/arena/map_lift_well.gd",
        "orbit": "res://game/arena/orbit_event.gd", "drone": "res://game/arena/map_drone.gd",
        "magic": "res://game/arena/map_magic.gd", "stream": "res://game/arena/map_magic_stream.gd",
        "field": "res://game/arena/map_magic_field.gd", "ambient": "res://game/arena/map_ambient_sound.gd",
    }

    def pb(self, g, name, kind, r0, r1, deg, width, y0, y1, **kw):
        """A box standing square to the radius at `deg`: from r0 to r1 out, `width` along the wall."""
        return self.block(g, name, kind, P((r0 + r1) * 0.5, deg, (y0 + y1) * 0.5), (width, y1 - y0, r1 - r0), cols=rot(deg), **kw)

    def bar(self, parent, name, kind, a, b, thick=0.3, wide=None, solid=True, **kw):
        """A straight bar from point a to point b at any angle (solid, unlike rod)."""
        d = tuple(q - p for p, q in zip(a, b))
        L = math.sqrt(sum(v * v for v in d))
        Z = norm(d)
        ref = (0, 1, 0) if abs(Z[1]) < 0.95 else (1, 0, 0)
        X = norm(cross(ref, Z))
        mid = tuple((p + q) * 0.5 for p, q in zip(a, b))
        return self.block(parent, name, kind, mid, (wide or thick, thick, L), cols=(X, cross(Z, X), Z), solid=solid, **kw)

    def hazard(self, g, name, kind, base, diameter, height, **kw):
        path = self.cyl(g, name, kind, base, diameter, height, sides=24, solid=False, **kw)
        self.nodes[-1].script = "hazard"
        return path

    def hook(self, parent, name, at, reach=None):
        props = [("transform", xform(IDENTITY, at))]
        if reach:
            props.append(("reach", fmt(reach)))
        return self.node(name, parent, "hook", props, type_="Marker3D")

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
                "directional_shadow_max_distance = 150.0", "directional_shadow_mode = 1", ""]
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
        blocks = sum(1 for n in self.nodes if n.script in ("block", "hazard"))
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
    out.append("surface_scale = 1.2")
    out.append("surface_strength = 0.9")
    out.append("roughness = 0.82")
    out.append(dict_lines("breakable", "float", BREAKABLE, num))
    out.append(dict_lines("material", "String", MATERIAL, lambda v: '"%s"' % v))
    with open(path, "w") as fh:
        fh.write("\n".join(out) + "\n")


# ---------------------------------------------------------------------------
# Floors: rings of sector slabs with holes cut where ramps come up

def ring(m, g, name, kind, y, r0, r1, sectors=range(SEC), holes=None, thick=0.5, cuts=(), **kw):
    """A flat ring floor whose top is at y, from radius r0 to r1, over `sectors`.
    holes: {sector: [(ra, rb), ...]} left open. cuts: radii every slab is split at
    (beside a hole, so a neighbour's square end does not reach far into it)."""
    holes = holes or {}
    ends = [k % SEC for k in sectors] if len(list(sectors)) < SEC else [-1]
    for k in sectors:
        k %= SEC
        near = any(((k + d) % SEC) in holes for d in (-1, 0, 1)) or k in (ends[0], ends[-1])
        edges = sorted(set([r0, r1] + ([c for c in cuts if r0 < c < r1] if near else [])))
        for a, b in zip(edges, edges[1:]):
            if any(ha - 0.01 <= a and b <= hb + 0.01 for ha, hb in holes.get(k, ())):
                continue
            m.pb(g, name, kind, a, b, (k + 0.5) * 360.0 / SEC, chord(b, SEC) + 0.02, y - thick, y, **kw)


def curved_ramp(m, g, name, r0, r1, deg0, deg1, y0, y1, kind="ramp", stub=3.0):
    """A ramp that follows the wall: from angle deg0 at height y0 to deg1 at y1, between
    radii r0 and r1, in straight pieces of 7.5 degrees or less. The first and last `stub`
    degrees are level (a landing at each end, so the way on and off is wide enough for the
    bots' navigation mesh as well as for people)."""
    way = 1.0 if deg1 > deg0 else -1.0
    rm = (r0 + r1) * 0.5
    a, b = deg0 + way * stub, deg1 - way * stub
    m.slab(g, name + "Foot", kind, P(rm, deg0, y0), P(rm, a, y0), r1 - r0, thick=0.4, unbreakable=True)
    m.slab(g, name + "Head", kind, P(rm, b, y1), P(rm, deg1, y1), r1 - r0, thick=0.4, unbreakable=True)
    n = max(1, int(math.ceil(abs(b - a) / 7.5 - 1e-6)))
    for j in range(n):
        a0 = a + (b - a) * j / n
        a1 = a + (b - a) * (j + 1) / n
        h0 = y0 + (y1 - y0) * j / n
        h1 = y0 + (y1 - y0) * (j + 1) / n
        m.slab(g, name, kind, P(rm, a0, h0), P(rm, a1, h1), r1 - r0, thick=0.4, unbreakable=True)


# ---------------------------------------------------------------------------
# The shell: 48 leaning wall pieces a tier, with openings

def openings(i):
    """Tier i's openings in the outer wall: {segment: [(y from, y to, what)]} above its
    floor, with what = "field" (a force-field doorway), "hole" (blown out) or "glass"."""
    out = {}

    def add(deg, width, y0, y1, what):
        first = int(round(deg / 7.5 - width / 2.0))
        for s in range(first, first + width):
            out.setdefault(s % SEG, []).append((y0, y1, what))

    if i < 5:
        add(75, 2, 0.0, 7.5, "field")            # the feature room's great arch
        add(DOOR_N, 1, 0.0, 4.6, "field")        # corridor doors
        add(DOOR_W, 1, 0.0, 4.6, "field")
        # Stained glass (it breaks): a rose window over the great arch, and one on each
        # spiral ramp's first landing. Each is two wall pieces wide and faces due east,
        # north or west, so its pane is a box square to the map (which is what lets it break).
        add(90, 2, L2 + 1.2, L2 + 5.0, "glass")
        add(180, 2, L1 + 1.3, L1 + 5.0, "glass")
        add(270, 2, L1 + 1.3, L1 + 5.0, "glass")
        if i in (1, 2, 4):
            add(255, 2, L1, L1 + 5.2, "hole")    # a blown-out stretch of wall
        if i == 3:
            add(258.75, 1, 0.0, 4.6, "field")    # the docking ring's third door
    else:
        add(75, 2, 0.0, 9.0, "field")
        add(DOOR_N, 1, 0.0, 4.6, "field")
        add(DOOR_W, 1, 0.0, 4.6, "field")
        add(165, 3, 0.0, 12.0, "sky")            # the observatory's great openings: plain, to the sky
        add(345, 3, 0.0, 12.0, "sky")
    return out


def shell(m, i):
    f = m.folder("Shell", NAMES[i])
    y0 = TIER * i
    cuts = openings(i)
    panels = m.group("Wall", f)
    fields = m.group("ForceFields", f)
    frames = m.group("Frames", f)
    for s in range(SEG):
        deg = (s + 0.5) * 7.5
        kind = "stone"       # (built of stone, all of it: the sci-fi is what was fitted to it later)
        spans = [(0.0, TIER)]
        for (a, b, what) in sorted(cuts.get(s, [])):
            last = spans.pop()
            spans += [(last[0], a), (b, last[1])]
        for a, b in spans:
            if b - a < 0.05:
                continue
            ym = y0 + (a + b) * 0.5
            r = ro(ym) - WALL * 0.5
            m.block(panels, "Panel", kind, P(r, deg, ym), (chord(ro(y0 + a), SEG) + 0.04, (b - a) / math.cos(TILT), WALL), cols=lean(deg))
        for (a, b, what) in cuts.get(s, []):
            ym = y0 + (a + b) * 0.5
            r = ro(ym) - WALL * 0.5
            w = chord(ro(ym), SEG)
            if what == "field":
                # The force field: drawn only. It stands on the gravity zone's edge.
                m.block(fields, "Field", "field", P(r + 0.3, deg, ym), (w, b - a, 0.12), cols=rot(deg), solid=False)

    # Frames round the openings: alloy emitters for a field, brass for glass, torn stone for a hole.
    done = set()
    for s in sorted(cuts):
        for (a, b, what) in cuts[s]:
            run = [s]
            while ((run[-1] + 1) % SEG) in cuts and (a, b, what) in cuts[(run[-1] + 1) % SEG]:
                run.append((run[-1] + 1) % SEG)
            if (run[0], a) in done or ((s - 1) % SEG in cuts and (a, b, what) in cuts[(s - 1) % SEG]):
                continue
            done.add((run[0], a))
            mid = (run[0] + len(run) * 0.5) * 7.5
            half = len(run) * 3.75
            ya, yb = y0 + a, y0 + b
            r = ro((ya + yb) * 0.5)
            if what in ("field", "sky"):
                for side in (-1, 1):
                    m.pb(frames, "Emitter", "alloy_dark", r - 1.3, r + 0.35, mid + side * (half + 0.55), 0.6, ya, yb + 0.5)
                    m.pb(frames, "EmitterGlow", ACCENT[i] if what == "field" else "glow", r + 0.35, r + 0.45, mid + side * (half + 0.55), 0.22, ya + 0.4, yb - 0.2, solid=False)
                    m.pb(frames, "EmitterGlowIn", ACCENT[i] if what == "field" else "glow", r - 1.4, r - 1.3, mid + side * (half + 0.55), 0.22, ya + 0.4, yb - 0.2, solid=False)
                m.pb(frames, "Lintel", "brass" if what == "sky" else "alloy_dark", r - 1.3, r + 0.35, mid, chord(r, SEG) * len(run) + 1.6, yb, yb + 0.7)
                # A stone arch springs over it: the fantasy half of every doorway.
                m.block(frames, "Arch", "stone_dark", P(r + 0.1, mid, yb + 1.75), (chord(r, SEG) * len(run) + 3.0, 2.1, 1.5), cols=rot(mid),
                        shape="arch", sides=16, inner=chord(r, SEG) * len(run) + 1.0, top=0.5)
            elif what == "glass":
                # One pane across both wall pieces, square to the map. It stops short of the
                # head above it and of the wall each side (a pane something rests on or runs
                # into never breaks); brass jambs and an alloy sill and head frame it.
                rm = (r - WALL * 0.5) * math.cos(math.radians(7.5)) + 0.1
                half_w = (r - WALL) * math.sin(math.radians(7.5)) - 0.55
                m.pb(panels, "StainedGlass", "glass_stained", rm - 0.1, rm + 0.1, mid, 2 * half_w, ya + 0.02, yb - 0.16)
                th = math.radians(mid)
                c = P(rm, mid, (ya + yb) * 0.5)
                for side in (-1, 1):       # (square to the pane, a finger's width clear of it)
                    off = side * (half_w + 0.4)
                    m.block(frames, "GlassJamb", "brass", (c[0] + math.cos(th) * off, c[1], c[2] - math.sin(th) * off), (0.6, yb - ya + 0.6, 0.9), cols=rot(mid))
                m.pb(frames, "GlassHead", "alloy_dark", rm - 0.5, rm + 0.5, mid, 2 * half_w + 1.4, yb, yb + 0.4)
                m.pb(frames, "GlassSill", "alloy_dark", rm - 0.5, rm + 0.5, mid, 2 * half_w + 1.4, ya - 0.4, ya)
                m.pb(frames, "GlassRune", ACCENT[i], rm + 0.5, rm + 0.56, mid, 2 * half_w, yb + 0.1, yb + 0.3, solid=False)
            else:
                rng = random.Random(i * 31 + s)
                for n in range(7):   # broken stone round the hole, and a bent alloy rib
                    dd = mid + rng.uniform(-half - 1.2, half + 1.2)
                    yy = rng.choice([ya - 0.3, yb + 0.3]) + rng.uniform(-0.3, 0.3)
                    m.block(frames, "Rubble", "stone_dark" if n % 3 else "alloy_dark", P(r - 0.5, dd, yy),
                            (rng.uniform(0.8, 1.6), rng.uniform(0.5, 1.1), 1.5), cols=rot(dd + rng.uniform(-25, 25)), shape="bevel", bevel=0.2)


def ribs(m):
    """What runs up the outside the whole height: eight stone buttress ribs, a conduit of
    light clamped to each (fitted later, like everything alloy), and brass bands at every tier."""
    g = m.group("Ribs", "Exterior")
    for k in range(8):
        deg = k * 45.0 + 11.25      # (clear of every doorway and window)
        for i in range(TIERS):      # (one length to a tier: a rib in one piece would count as running through every window it passes)
            ym = TIER * (i + 0.5)
            m.block(g, "Rib", "stone_dark", P(ro(ym) + 0.35, deg, ym), (1.5, TIER / math.cos(TILT), 0.9), cols=lean(deg))
            for q in range(4):          # the clamps that hold the conduit to the stone
                yc = TIER * i + 4.0 + q * 7.4
                m.block(g, "ConduitClamp", "alloy", P(ro(yc) + 0.84, deg, yc), (0.8, 0.5, 0.3), cols=lean(deg), solid=False)
            m.block(g, "Conduit", "conduit", P(ro(ym) + 0.86, deg, ym), (0.3, TIER / math.cos(TILT) - 1.8, 0.14), cols=lean(deg), solid=False)
        for i in range(1, TIERS + 1):       # a housing where each tier's band crosses the rib
            y = TIER * i - 0.5
            m.block(g, "RibNode", "alloy_dark", P(ro(y) + 0.7, deg, y), (2.2, 1.6, 1.3), cols=rot(deg), shape="bevel", bevel=0.25)
    for i in range(1, TIERS + 1):
        y = TIER * i
        m.block(g, "Band", "brass", (0, y - 0.5, 0), (2 * ro(y - 0.5) + 0.5, 0.9, 2 * ro(y - 0.5) + 0.5), shape="tube", sides=SEG,
                inner=2 * ro(y - 0.5) - 0.6, solid=False)


# ---------------------------------------------------------------------------
# One tier's structure (every tier but the Observatory)

def tier(m, i):
    y0 = TIER * i
    f = m.folder(NAMES[i])
    acc = ACCENT[i]
    Rc = rc(i)
    Rw = ri(y0 + TIER)                 # the wall's inner face at the tier's top: lanes are measured from here
    corr = list(range(FEAT, SEC))      # c0..c13
    c = lambda k: FEAT + k
    floor_kind = FLOORS[i]
    # Where the ramps from the tier below come up through this floor (the mid lane).
    up_lane = (rc(i) - 3.4, rc(i) - 0.6)
    g = m.group("Floors", f)
    if i == 0:
        ring(m, g, "Floor", floor_kind, y0, 3.8, ri(y0) + 0.6, thick=0.8)
    else:
        holes = {c(4): [up_lane], c(5): [up_lane], c(8): [up_lane], c(9): [up_lane]}
        ring(m, g, "Floor", floor_kind, y0, RS, ri(y0) + 0.6, holes=holes, cuts=up_lane, thick=0.6)
    # The storeys at 6.35 and 12.7: rooms and corridor on sectors 10-23, balconies in the feature room.
    lanes = (RS + 4.8, RS + 9.6, Rc, Rc + LANE)
    outer = (Rc + LANE, 99.0)
    for lvl, y, gone, feat in ((1, y0 + L1, (0, 1, 13, 12), range(FEAT)), (2, y0 + L2, (2, 3, 11, 10), (0, 1, 2, 7, 8, 9))):
        holes = {c(k): [outer] for k in gone}
        ring(m, g, "Storey%d" % lvl, "stone_floor", y, RS, ri(y) + 0.6, sectors=corr, holes=holes, cuts=lanes)
        for run in ((feat,) if lvl == 1 else ((0, 1, 2), (7, 8, 9))):
            ring(m, g, "Balcony%d" % lvl, "stone_floor", y, Rc, ri(y) + 0.6, sectors=run)
        # A low parapet along each balcony's open edge, with gaps to drop or swing through.
        for k in feat:
            if k % 3 != 1:
                m.pb(g, "Parapet", "brass", Rc - 0.12, Rc + 0.12, (k + 0.5) * 15.0, chord(Rc, SEC), y, y + 1.0)
    # 19 m: the upper hall's floor, all the way round.
    holes = {c(k): [outer] for k in (4, 5, 9, 8)}
    ring(m, g, "UpperFloor", "stone_floor", y0 + L3, RS, ri(y0 + L3) + 0.6, holes=holes, cuts=lanes)
    # Trim round the shaft's rim on the two full floors (drawn only).
    for y in (y0, y0 + L3):
        m.block(g, "ShaftRim", "brass", (0, y - 0.2, 0), (2 * RS + 0.1, 0.5, 2 * RS + 0.1), shape="tube", sides=SEG, inner=2 * RS - 0.5, solid=False)

    # The two spiral ramps in the corridor's outer lane, one from each end.
    g = m.group("Ramps", f)
    for n, (a, b) in enumerate(((0.0, L1), (L1, L2), (L2, L3))):
        curved_ramp(m, g, "SpiralA", Rc + LANE + 0.1, Rw, 150.0 + n * 30.0, 180.0 + n * 30.0, y0 + a, y0 + b)
        curved_ramp(m, g, "SpiralB", Rc + LANE + 0.1, Rw, 360.0 - n * 30.0, 330.0 - n * 30.0, y0 + a, y0 + b)
    # ...and the two long ramps from the upper hall to the next tier (its mid lane).
    nxt = (rc(i + 1) - 3.4, rc(i + 1) - 0.6)
    curved_ramp(m, g, "UpA", nxt[0], nxt[1], 150.0, 240.0, y0 + L3, y0 + TIER)
    curved_ramp(m, g, "UpB", nxt[0], nxt[1], 360.0, 270.0, y0 + L3, y0 + TIER)

    # Walls inside: the corridor wall (doors every third sector), and the feature room's two ends.
    g = m.group("Walls", f)
    wall_kind = "stone"
    for lvl, ya in enumerate((0.0, L1, L2)):
        yb = (L1, L2, L3)[lvl] - 0.5
        for k in range(14):
            deg = (c(k) + 0.5) * 15.0
            w = chord(Rc, SEC)
            if k % 3 == 2:
                for side in (-1, 1):
                    m.pb(g, "Jamb", wall_kind, Rc - 0.2, Rc + 0.2, deg + side * math.degrees((w * 0.5 - 0.5) / Rc), 1.0, y0 + ya, y0 + yb)
                m.pb(g, "DoorHead", "stone_dark", Rc - 0.25, Rc + 0.25, deg, w - 1.9, y0 + ya + 3.3, y0 + yb)
                m.pb(g, "DoorLight", acc, Rc - 0.3, Rc + 0.3, deg, w - 2.2, y0 + ya + 3.1, y0 + ya + 3.3, solid=False)
            else:
                m.pb(g, "CorridorWall", wall_kind, Rc - 0.2, Rc + 0.2, deg, w + 0.02, y0 + ya, y0 + yb)
    for deg, name in ((0.0, "EndWallSouth"), (150.0, "EndWallNorth")):
        for lvl, ya in enumerate((0.0, L1, L2)):
            yb = (L1, L2, L3)[lvl] - 0.5
            # (a doorway on the corridor's inner lane at every storey, and a wide one by the shaft on the floor)
            # On the floor both lanes are open (a wide arch onto the foot of a spiral ramp);
            # upstairs a doorway on the inner lane, and an open bay by the shaft to look and
            # drop into the feature room.
            pieces = [(RS + 6.5, Rc + 0.3)] if lvl == 0 else [(RS + 6.5, Rc + 0.3), (Rc + LANE - 0.2, ri(y0 + yb) + 0.3), (RS + 0.3, RS + 2.5)]
            for r0, r1 in pieces:
                m.pb(g, name, "stone" if lvl == 0 else wall_kind, r0, r1, deg, 0.6, y0 + ya, y0 + yb)
            m.pb(g, name + "Head", "stone_dark", Rc + 0.3, (ri(y0 + yb) + 0.3) if lvl == 0 else (Rc + LANE - 0.2), deg, 0.6, y0 + ya + (4.4 if lvl == 0 else 3.4), y0 + yb)
            if lvl == 0:
                m.pb(g, name + "Head", "stone_dark", RS + 1.5, RS + 6.5, deg, 0.6, y0 + 4.2, y0 + yb)
                m.pb(g, name + "Post", "brass", RS + 0.9, RS + 1.5, deg, 0.9, y0, y0 + yb)
    # Room dividers on the shaft side of the corridor (they break the long curve into rooms).
    for lvl, ya in enumerate((0.0, L1, L2)):
        yb = (L1, L2, L3)[lvl] - 0.5
        for k in ((3, 11) if lvl == 0 else (1, 7, 12)):
            deg = c(k) * 15.0
            m.pb(g, "Divider", wall_kind, RS + 3.4, Rc - 3.9, deg, 0.5, y0 + ya, y0 + yb)
    # Pillars in the upper hall: a colonnade round the shaft's rim, and one along the feature side's wall.
    for k in range(SEC):
        deg = k * 15.0 + 7.5
        if min(abs((deg - a + 180) % 360 - 180) for a in (LIFT_A, LIFT_B)) > 12.0 and k % 2 == 0:
            m.cyl(g, "Pillar", "stone", P(RS + 1.3, deg, y0 + L3), 1.3, TIER - L3 - 0.6, sides=10)
        if k < FEAT and k % 2:
            m.cyl(g, "Pillar", "stone", P(Rw - 1.4, deg, y0 + L3), 1.3, TIER - L3 - 0.6, sides=10)
    return f


def observatory_structure(m):
    i = 5
    y0 = TIER * i
    f = m.folder(NAMES[i])
    g = m.group("Floors", f)
    up_lane = (rc(i) - 3.4, rc(i) - 0.6)
    c = lambda k: FEAT + k
    holes = {c(4): [up_lane], c(5): [up_lane], c(8): [up_lane], c(9): [up_lane]}
    ring(m, g, "Floor", FLOORS[5], y0, RS, ri(y0) + 0.6, holes=holes, cuts=up_lane, thick=0.6)
    m.block(g, "ShaftRim", "brass", (0, y0 - 0.2, 0), (2 * RS + 0.1, 0.5, 2 * RS + 0.1), shape="tube", sides=SEG, inner=2 * RS - 0.5, solid=False)
    # The telescope's platform caps the shaft, on two spokes; the gaps look down the whole tower.
    m.cyl(g, "Platform", "alloy_floor", (0, y0 - 0.6, 0), 9.0, 0.6, sides=24)
    for deg in (165.0, 345.0):
        m.pb(g, "Spoke", "alloy_floor", 4.2, RS + 0.3, deg, 3.2, y0 - 0.5, y0)
    # The gallery: half way round at 9 m, a ramp up to each end.
    Rw = ri(y0 + TIER)
    ring(m, g, "Gallery", "catwalk", y0 + 9.0, Rw - 3.6, ri(y0 + 9.0) + 0.6, sectors=range(0, 12), thick=0.4)
    for k in range(12):
        if k % 3 != 1:
            m.pb(g, "GalleryRail", "brass", Rw - 3.7, Rw - 3.5, (k + 0.5) * 15.0, chord(Rw - 3.6, SEC), y0 + 9.0, y0 + 10.0)
    r = m.group("Ramps", f)
    curved_ramp(m, r, "GalleryRampA", Rw - 3.3, Rw - 0.2, 225.0, 180.0, y0, y0 + 9.0)
    curved_ramp(m, r, "GalleryRampB", Rw - 3.3, Rw - 0.2, 315.0, 360.0, y0, y0 + 9.0)
    # The ceiling, and the roof over it.
    m.cyl(g, "Ceiling", "alloy_dark", (0, TOP, 0), 2 * R_TOP + 0.4, 1.0, sides=SEG)
    return f


def roof(m):
    g = m.group("Roof", "Exterior")
    m.cone(g, "Eaves", "brass", (0, TOP + 1.0, 0), 2 * R_TOP + 5.0, 1.6, top=2 * R_TOP + 3.4, sides=SEG)
    m.cone(g, "Roof", "roof", (0, TOP + 2.6, 0), 2 * R_TOP - 1.0, 34.0, top=3.0, sides=SEG)     # (it leaves a ledge on the eaves)
    for k in range(8):       # alloy ribs up the roof, carrying the tower's conduits to the peak
        deg = k * 45.0 + 11.25
        a, b = P(R_TOP - 0.7, deg, TOP + 2.9), P(1.7, deg, TOP + 36.4)
        m.rod(g, "RoofRib", "brass", a, b, thick=0.5, wide=0.9)
        m.rod(g, "RoofConduit", "conduit", (a[0], a[1] + 0.3, a[2]), (b[0], b[1] + 0.3, b[2]), thick=0.14, wide=0.3)
    m.cyl(g, "Collar", "alloy_dark", (0, TOP + 36.0, 0), 4.4, 1.6, sides=16)
    m.cone(g, "CrystalSeat", "brass", (0, TOP + 37.6, 0), 4.0, 2.0, top=1.6, sides=12)
    # The great crystal: two cones foot to foot.
    m.cone(g, "Crystal", "crystal", (0, TOP + 44.0, 0), 4.6, 9.0, sides=6, yaw=15.0)
    m.cone(g, "CrystalFoot", "crystal", (0, TOP + 44.0, 0), 4.6, 4.6, sides=6, flip=True, yaw=15.0)
    # The orrery: brass rings turning slowly round the crystal, driven by servo housings.
    for n, (tip, size, speed) in enumerate((((1, 0, 0), 16.0, 5.0), ((0.6, 0, 0.8), 20.0, -3.5), ((0, 0, 1), 24.0, 2.4))):
        ax = norm((tip[0] * 0.5, 1.0, tip[2] * 0.5))
        X = norm(cross(ax, (0.3, 0.1, 1.0)))
        sp = m.node("Orrery%d" % (n + 1), g, "spinner", [("transform", xform((X, ax, cross(X, ax)), (0, TOP + 44.5, 0))), ("speed", fmt(speed))])
        m.block(sp, "Ring", "brass", (0, 0, 0), (size, 0.35, size), shape="tube", sides=32, inner=size - 0.9, solid=False)
        m.block(sp, "Servo", "alloy_dark", (size * 0.5 - 0.2, 0, 0), (1.3, 0.9, 1.3), shape="bevel", bevel=0.2, solid=False)
        m.block(sp, "Orb", ACCENT[(n * 2) % 6], (-size * 0.5 + 0.2, 0.375, 0), (1.5, 0.75, 1.5), shape="dome", sides=10, solid=False)
        m.block(sp, "OrbUnder", ACCENT[(n * 2) % 6], (-size * 0.5 + 0.2, -0.375, 0), (1.5, 0.75, 1.5), cols=FLIP, shape="dome", sides=10, solid=False)


# ---------------------------------------------------------------------------
# The shaft: the engine's core at the bottom, bridges, lifts and things to hook

BRIDGE_TURNS = (165.0, 15.0, 135.0)


def bridges():
    """The bridges across the shaft: (height, angle, tier). One at every tier's floor but
    the Engine's and at every upper hall, turned so no two line up."""
    out = []
    for i in range(5):
        for y in (TIER * i, TIER * i + L3):
            if y > 0.0:
                out.append((y, BRIDGE_TURNS[len(out) % 3], i))
    return out


# The river of magic that climbs the shaft (drawn in empyrean_magic.py). Its course is
# worked out here because the shaft's floating stones have to keep clear of it.
RIVER_FOOT, RIVER_HEAD = 11.0, TIER * 5 - 1.1       # the core crystal's tip; just under the Observatory's platform
RIVER_R = 3.0            # how far from the shaft's middle it runs
RIVER_HOLD = (3.4, 2.0)  # from this far below a bridge (its banners hang there) to this far above, it hardly turns...
RIVER_SLOW = 4.0         # ...this many degrees a metre, so it passes square on to the bridge, well clear of its rails


def _river_knots():
    """(height, angle) corners of the river's course: about a turn every 24 m, and at
    every bridge it is square on to it (90 degrees round from the bridge's ends)."""
    prev_y, prev_a = RIVER_FOOT, 60.0
    knots = [(prev_y, prev_a)]
    for y, d, _i in bridges():
        base = (d + 90.0) % 180.0
        want = prev_a + 15.0 * (y - prev_y)
        a = base + 180.0 * round((want - base) / 180.0)
        if a < prev_a + 25.0:
            a += 180.0
        knots += [(y - RIVER_HOLD[0], a - RIVER_SLOW * RIVER_HOLD[0]), (y + RIVER_HOLD[1], a + RIVER_SLOW * RIVER_HOLD[1])]
        prev_y, prev_a = y, a
    knots.append((RIVER_HEAD, prev_a + 15.0 * (RIVER_HEAD - prev_y)))
    return knots


_KNOTS = _river_knots()


def river_angle(y):
    y = min(max(y, RIVER_FOOT), RIVER_HEAD)
    for (y0, a0), (y1, a1) in zip(_KNOTS, _KNOTS[1:]):
        if y <= y1:
            return a0 + (a1 - a0) * (y - y0) / (y1 - y0)
    return _KNOTS[-1][1]


def river_at(y):
    """Where the river's middle is at height y (its corners rounded over a metre)."""
    deg = sum(river_angle(y + d) for d in (-0.5, -0.25, 0.0, 0.25, 0.5)) / 5.0
    u = min(max((y - RIVER_FOOT) / 3.5, 0.0), 1.0)
    return P(RIVER_R * u * u * (3 - 2 * u), deg, y)


def stone_at(y):
    """Where the floating stone (and its grapple anchor) at height y hangs: across the
    shaft from the river, clear of the two lift beams."""
    deg = (river_angle(y - 1.6) + 180.0) % 360.0
    while min(abs((deg - a + 180) % 360 - 180) for a in (LIFT_A, LIFT_B)) < 40.0:
        deg = (deg + 50.0) % 360.0
    return P(4.6, deg, y)


STONES = []      # where shaft() hung the floating stones (their grapple anchors), for the river's clearance check


def shaft(m):
    f = m.folder("Shaft")
    del STONES[:]
    g = m.group("Core", f)
    # The Arcane Engine's core: a crystal standing in a sunken, glowing basin. The basin and
    # everything within 3.4 m of the middle is deadly (a MapHazard): touch it and you die.
    m.cyl(g, "BasinFloor", "alloy_dark", (0, -0.9, 0), 7.6, 0.1, sides=24)
    for k in range(16):
        m.pb(g, "BasinKerb", "brass", 3.75, 4.15, k * 22.5, chord(4.15, 16) + 0.02, -0.8, 0.35, shape="bevel", bevel=0.1)
    m.hazard(g, "BasinGlow", "hazard_glow", (0, -0.75, 0), 7.4, 0.5)
    m.hazard(g, "CoreField", "hazard_glow", (0, -0.2, 0), 6.8, 12.0, drawn=False)
    m.cone(g, "CoreCrystal", "crystal", (0, 3.4, 0), 4.2, 7.6, sides=6)
    m.cone(g, "CoreCrystalFoot", "crystal", (0, 3.4, 0), 4.2, 3.9, sides=6, flip=True)
    m.block(g, "DangerRing", "hazard_glow", (0, 0.2, 0), (7.5, 0.1, 7.5), shape="tube", sides=32, inner=7.0, solid=False)
    # Containment rings: alloy hoops turning slowly round the crystal (scenery: never solid).
    for n, (ax, size, speed) in enumerate((((0.25, 1, 0), 9.4, 14.0), ((1, 0.35, 0.2), 10.6, -9.0), ((0.1, 0.4, 1), 11.8, 6.0))):
        Y = norm(ax)
        X = norm(cross(Y, (0.2, 0.3, 1.0)))
        sp = m.node("Containment%d" % (n + 1), g, "spinner", [("transform", xform((X, Y, cross(X, Y)), (0, 4.6, 0))), ("speed", fmt(speed))])
        m.block(sp, "Hoop", "alloy", (0, 0, 0), (size, 0.5, size), shape="tube", sides=32, inner=size - 0.8, solid=False)
        for q in range(4):
            m.block(sp, "Emitter", "accent_cyan", P(size * 0.5 - 0.2, q * 90.0), (0.8, 0.7, 0.8), shape="bevel", bevel=0.15, solid=False)
    # Bridges: at every tier's floor and at every upper hall, turned so no two line up.
    g = m.group("Bridges", f)
    for n, (y, deg, i) in enumerate(bridges(), 1):
        kind = "stone_floor" if n % 2 else "alloy_floor"
        m.pb(g, "Bridge", kind, -RS - 0.3, RS + 0.3, deg, 3.2, y - 0.5, y)
        for side in (-1, 1):
            th = math.radians(deg + 90.0)
            off = (math.sin(th) * 1.7 * side, 0, math.cos(th) * 1.7 * side)
            a, b = P(-RS + 1.0, deg, y + 0.45), P(RS - 1.0, deg, y + 0.45)
            m.bar(g, "BridgeRail", "brass" if n % 2 else "alloy_dark", tuple(p + o for p, o in zip(a, off)), tuple(p + o for p, o in zip(b, off)), thick=0.9, wide=0.2)
        m.block(g, "BridgeLamp", ACCENT[i], P(0, 0, y - 0.6), (1.2, 0.2, 1.2), shape="cyl", sides=12, solid=False)
    # Floating stones and grapple anchors up the shaft: never more than 25 m to the next one.
    g = m.group("Anchors", f)
    y = 12.0
    k = 0
    while y < TOP - 8.0:
        at = stone_at(y)
        deg = math.degrees(math.atan2(at[0], at[2]))
        STONES.append(at)
        m.block(g, "FloatingStone", "rock" if k % 2 else "alloy_dark", (at[0], at[1] - 1.6, at[2]), (2.2, 1.4, 2.2), shape="bevel", bevel=0.45, cols=rot(deg + 20))
        m.block(g, "StoneRune", ACCENT[min(int(y // TIER), 5)], (at[0], at[1] - 0.86, at[2]), (1.2, 0.08, 1.2), shape="cyl", sides=10, solid=False)
        m.hook(g, "ShaftAnchor", at)
        y += 21.0
        k += 1
    return f


def lifts(m):
    f = m.folder("Lifts")

    def lift(name, at, height, acc, stops, pad=True):
        """A tractor-beam lift at `at`, `height` tall, with a bots' link to each stop
        (a point on a floor beside the beam)."""
        g = m.group(name, f, at=at)
        m.node("Beam", g, "lift", [("height", fmt(height)), ("color", color(ACCENT_RGB[acc]))])
        # The emitter rings: alloy and brass machinery at the foot and the top.
        if pad:
            m.cyl(g, "Pad", "alloy_dark", (0, -0.5, 0), 4.6, 0.62, sides=24)
        m.block(g, "FootRing", "brass", (0, 0.16, 0), (4.4, 0.12, 4.4), shape="tube", sides=24, inner=3.4, solid=False)
        m.block(g, "FootGlow", ACCENT[acc], (0, 0.18, 0), (3.3, 0.1, 3.3), shape="tube", sides=24, inner=2.7, solid=False)
        for y in (height + 2.2,):
            m.block(g, "TopRing", "alloy", (0, y, 0), (4.6, 0.7, 4.6), shape="tube", sides=24, inner=3.5, solid=False)
            m.block(g, "TopRingBrass", "brass", (0, y + 0.5, 0), (4.2, 0.3, 4.2), shape="tube", sides=24, inner=3.6, solid=False)
            m.block(g, "TopGlow", ACCENT[acc], (0, y - 0.45, 0), (3.6, 0.2, 3.6), shape="tube", sides=24, inner=3.0, solid=False)
        for n, stop in enumerate(stops):
            land = tuple(s - a for s, a in zip(stop, at))
            m.node("Stop%d" % (n + 1), g, None, [("transform", xform(IDENTITY, land))], type_="Marker3D")
            m.node("Ride%d" % (n + 1), g, "link", [("how", "4"), ("landing", 'NodePath("../Stop%d")' % (n + 1))], type_="Marker3D")
        return g

    # In the shaft: A from the Engine to the Menagerie, B from the Labs to the Observatory.
    lift("LiftA", P(LIFT_R, LIFT_A, 0.0), TIER * 3 + 0.9, 0, [P(RS + 2.2, LIFT_A, TIER * k) for k in (1, 2, 3)], pad=False)
    lift("LiftB", P(LIFT_R, LIFT_B, TIER * 2), TIER * 3 + 0.9, 4, [P(RS + 2.2, LIFT_B, TIER * k) for k in (3, 4, 5)])
    # Outside: C from the Engine's west balcony to the Labs', D from the docking ring to the Observatory's.
    lift("LiftC", P(C_R, LIFT_C, 0.0), TIER * 2 + 0.9, 2, [P(ro(TIER * k) + 1.2, LIFT_C, TIER * k) for k in (1, 2)])
    lift("LiftD", P(D_R, LIFT_D, RING_Y), TIER * 2 + 0.9, 5, [P(ro(TIER * k) + 1.2, LIFT_D, TIER * k) for k in (4, 5)], pad=False)
    # Lift B's foot stands on a pad that juts into the shaft from the Labs' floor.
    return f


# ---------------------------------------------------------------------------
# Outside: balconies, the docking ring and its starship, thrusters, the root

def balconies(m):
    g = m.group("Balconies", "Exterior")
    for i in range(TIERS):
        y = TIER * i
        if i == 3:
            continue   # the docking ring is this tier's balcony
        for deg, width in ((75.0, 30.0), (DOOR_N, 22.5), (DOOR_W, 22.5)):
            depth = 5.0
            if deg == LIFT_C and i <= 2:
                depth = (C_R + 2.4 - ro(y)) if i == 0 else (C_R - 1.75 - ro(y))
            if deg == LIFT_D and i >= 4:
                depth = D_R - 1.75 - ro(y)
            r0, r1 = ro(y) - 0.4, ro(y) + depth
            n = int(round(width / 7.5))
            for s in range(n):
                d = deg - width * 0.5 + (s + 0.5) * 7.5
                m.pb(g, "Balcony", "stone_floor", r0, r1, d, chord(r1, SEG) + 0.02, y - 0.6, y)
                if not (s in (n // 2 - 1, n // 2) and depth > 4.0 and deg == 75.0):
                    m.pb(g, "BalconyRail", "brass", r1 - 0.2, r1, d, chord(r1, SEG), y, y + 1.0)
            # Brackets under it: a stone corbel and an alloy strut.
            for side in (-1, 1):
                d = deg + side * (width * 0.5 - 2.0)
                a, b = P(ro(y - 5.0) + 0.2, d, y - 5.0), P(r1 - 0.6, d, y - 0.6)
                m.bar(g, "Strut", "stone_dark", a, b, thick=0.5, wide=0.6)
            m.pb(g, "BalconyLight", ACCENT[i], r1 - 0.05, r1 + 0.06, deg, chord(r1, SEG) * n * 0.8, y - 0.45, y - 0.2, solid=False)


def docking_ring(m):
    f = m.folder("DockingRing", "Exterior")
    g = m.group("Ring", f)
    y = RING_Y
    r0 = ro(y) - 0.4
    for k in range(SEC):
        deg = (k + 0.5) * 15.0
        m.pb(g, "Deck", "alloy_floor", r0, RING_R, deg, chord(RING_R, SEC) + 0.02, y - 0.8, y)
        if abs((deg - PAD_DEG + 180) % 360 - 180) > 24:
            m.pb(g, "Rail", "alloy_dark", RING_R - 0.25, RING_R, deg, chord(RING_R, SEC), y, y + 1.0)
        m.pb(g, "RimLight", "accent_teal", RING_R, RING_R + 0.1, deg, chord(RING_R, SEC) * 0.6, y - 0.55, y - 0.25, solid=False)
    m.block(g, "Skirt", "brass", (0, y - 1.1, 0), (2 * RING_R + 0.3, 0.6, 2 * RING_R + 0.3), shape="tube", sides=SEG, inner=2 * RING_R - 1.2, solid=False)
    for k in range(12):      # struts down to the wall: half stone buttress, half alloy truss
        deg = k * 30.0 + 15.0
        a, b = P(ro(y - 12.0) + 0.3, deg, y - 12.0), P(RING_R - 1.5, deg, y - 0.8)
        m.bar(g, "RingStrut", "alloy", a, b, thick=0.7, wide=0.9)
    # The landing pad, and the starship parked on it.
    pad = m.group("Pad", f, at=P(RING_R + 13.0, PAD_DEG, y), yaw=math.radians(PAD_DEG))
    m.box(pad, "PadDeck", "alloy_floor", (-12, -0.8, -14.5), (12, 0, 14))
    m.box(pad, "PadEdge", "brass", (-12.3, -0.9, 13.9), (12.3, 0.1, 14.5))
    for x in (-12, 12):
        m.box(pad, "PadEdge", "brass", (x - 0.3, -0.9, -14.5), (x + 0.3, 0.1, 14.5))
    m.block(pad, "PadCircle", "accent_teal", (0, 0.03, 0), (18, 0.06, 18), shape="tube", sides=32, inner=17.0, solid=False)
    m.block(pad, "PadRune", "glow", (0, 0.03, 0), (9, 0.06, 9), shape="tube", sides=6, inner=8.3, solid=False)
    for x, z in ((-11, 12), (11, 12), (-11, -12), (11, -12)):
        m.cyl(pad, "PadLamp", "alloy_dark", (x, 0, z), 0.5, 2.6, sides=8)
        m.block(pad, "PadLampGlow", "accent_teal", (x, 2.8, z), (0.7, 0.4, 0.7), shape="bevel", bevel=0.1, solid=False)
    starship(m, pad)
    return f


def starship(m, pad):
    """The parked starship: an original design, long nose toward the tower's left, swept
    wings to stand on, twin engine pods with rune-ringed nozzles. You cannot get inside
    it: every part is one solid lump."""
    s = m.group("Starship", pad, at=(1.5, 0, 0), yaw=math.radians(90.0))
    # (in its own frame: nose toward -z, y = 0 the pad)
    for x in (-3.4, 3.4):        # landing skids
        m.bev(s, "Skid", "alloy_dark", (x - 0.4, 0, -4.5), (x + 0.4, 0.5, 5.5), bevel=0.15)
        for z in (-3.0, 4.0):
            m.box(s, "SkidLeg", "alloy_dark", (x - 0.25, 0.5, z - 0.25), (x + 0.25, 1.5, z + 0.25))
    m.bev(s, "Hull", "ship", (-2.6, 1.3, -6.5), (2.6, 4.3, 7.5), bevel=0.8)
    m.block(s, "Nose", "ship", (0, 2.6, -9.6), (4.2, 6.4, 4.2), cols=((1, 0, 0), (0, 0, -1), (0, 1, 0)), shape="cone", sides=12, top=0.9)
    m.block(s, "NoseTip", "brass", (0, 2.6, -13.1), (0.9, 0.7, 0.9), cols=((1, 0, 0), (0, 0, -1), (0, 1, 0)), shape="cone", sides=12)
    m.block(s, "Canopy", "glass_clear", (0, 4.2, -4.6), (2.6, 1.3, 4.4), shape="dome", sides=12, unbreakable=True)
    m.bev(s, "Spine", "alloy_dark", (-0.8, 4.3, -1.5), (0.8, 4.9, 7.0), bevel=0.2)
    for side in (-1, 1):
        # A swept wing: walkable, sloping gently down to its tip.
        m.slab(s, "Wing", "ship", (side * 2.4, 3.3, 2.5), (side * 10.5, 2.5, 4.5), 6.0, thick=0.5)
        m.slab(s, "WingTrim", "brass", (side * 2.4, 3.36, -0.3), (side * 10.5, 2.56, 1.7), 0.5, thick=0.3, solid=False)
        m.bev(s, "WingTip", "alloy_dark", (side * 10.2 - 0.5, 1.9, 1.2), (side * 10.2 + 0.5, 3.4, 8.2), bevel=0.25)
        m.block(s, "WingRune", "accent_teal", (side * 6.5, 3.02, 3.6), (2.4, 0.06, 2.4), shape="tube", sides=12, inner=1.9, solid=False)
        # An engine pod with a rune-ringed nozzle.
        m.lying_cyl(s, "Engine", "alloy", (side * 4.4, 3.0, 6.6), 2.4, 5.0, axis="z", sides=12)
        m.lying_cyl(s, "Nozzle", "alloy_dark", (side * 4.4, 3.0, 9.5), 2.0, 0.9, axis="z", sides=12)
        m.lying_cyl(s, "NozzleRing", "brass", (side * 4.4, 3.0, 9.2), 2.7, 0.3, axis="z", sides=12, solid=False)
        m.lying_cyl(s, "NozzleGlow", "accent_teal", (side * 4.4, 3.0, 9.98), 1.5, 0.1, axis="z", sides=12, solid=False)
    m.wedge(s, "Fin", "ship", (-0.3, 4.9, 2.5), (0.3, 7.6, 7.0), tall="+z")
    m.box(s, "FinCap", "brass", (-0.35, 7.5, 6.2), (0.35, 7.75, 7.1), solid=False)
    m.block(s, "HullStripe", "conduit", (0, 3.0, 0.5), (5.3, 0.25, 12.0), solid=False)
    return s


def thrusters(m):
    f = m.folder("Thrusters", "Exterior")
    for k in range(8):
        deg = k * 45.0 + 22.5
        g = m.group("Thruster", f, at=P(R_FOOT + 6.5, deg, 0.0), yaw=math.radians(deg))
        m.cyl(g, "Housing", "alloy", (0, -9.0, 0), 6.0, 10.0, sides=16)
        m.cone(g, "Shroud", "alloy_dark", (0, 1.0, 0), 6.0, 2.2, top=3.4, sides=16)
        m.cyl(g, "Cap", "brass", (0, 3.2, 0), 3.4, 0.4, sides=16)
        m.block(g, "CapRune", "glow", (0, 3.62, 0), (2.6, 0.06, 2.6), shape="tube", sides=8, inner=2.0, solid=False)
        m.cone(g, "Bell", "alloy_dark", (0, -9.0, 0), 5.4, 3.0, top=3.6, sides=16, flip=True)
        for b in range(3):
            m.block(g, "Band", "brass", (0, -7.0 + b * 3.2, 0), (6.3, 0.4, 6.3), shape="tube", sides=16, inner=5.8, solid=False)
        # The jet: drawn only (no collision, no damage).
        m.cone(g, "Jet", "jet", (0, -12.0, 0), 4.4, 18.0, sides=12, flip=True, solid=False)
        m.cone(g, "JetCore", "screen", (0, -12.0, 0), 2.0, 9.0, sides=8, flip=True, solid=False)
        # It hangs off the tower on a stone buttress and an alloy arm.
        m.box(g, "Arm", "alloy", (-1.0, -3.0, -7.5), (1.0, -1.0, -2.6))
        m.bar(g, "Buttress", "stone", (0, 1.0, -2.9), (0, 16.0, -7.1), thick=1.3, wide=1.6)
        m.rod(g, "Pipe", "conduit", (0.9, -2.0, -2.8), (0.9, -2.0, -7.0), thick=0.2, wide=0.2)
    # A wide stone apron round the foot, to land on.
    g = m.group("Apron", f)
    for k in range(SEC):
        m.pb(g, "Apron", "stone_floor", R_FOOT - 0.4, R_FOOT + 3.4, (k + 0.5) * 15.0, chord(R_FOOT + 3.4, SEC) + 0.02, -1.0, 0.0)
    m.block(g, "ApronTrim", "brass", (0, -0.5, 0), (2 * R_FOOT + 7.2, 0.5, 2 * R_FOOT + 7.2), shape="tube", sides=SEG, inner=2 * R_FOOT + 6.2, solid=False)
    return f


def root(m):
    g = m.group("Root", "Exterior")
    m.cyl(g, "Foundation", "stone_dark", (0, -2.4, 0), 2 * R_FOOT + 1.0, 1.6, sides=SEG)
    rng = random.Random(7)
    # The rock: cones hanging point down, each a different size and turn, so the outline is jagged.
    m.cone(g, "Rock", "rock", (0, -2.4, 0), 2 * R_FOOT - 1.0, ROOT_DEPTH - 6.0, top=5.0, sides=11, flip=True, yaw=10.0)
    m.cone(g, "RockTip", "rock_dark", (0, -ROOT_DEPTH + 4.4 + 4.0, 0), 9.0, 8.4, sides=7, flip=True, yaw=40.0)
    for k in range(9):
        deg = k * 40.0 + rng.uniform(-10, 10)
        r = rng.uniform(13.0, 23.0)
        depth = rng.uniform(12.0, 24.0)
        m.cone(g, "RockSpur", "rock_dark" if k % 2 else "rock", P(r, deg, -2.5), rng.uniform(9.0, 15.0), depth, sides=rng.choice([5, 6, 7]),
               flip=True, yaw=rng.uniform(0, 60))
    for k in range(10):      # crystals growing out of it, and chains with weights
        deg = k * 36.0 + 12.0
        r = rng.uniform(8.0, 24.0)
        y = -rng.uniform(6.0, 14.0) - (26.0 - r) * 0.7
        if k % 2:
            m.cone(g, "RootCrystal", "crystal", P(r, deg, y), rng.uniform(1.6, 2.6), rng.uniform(5.0, 9.0), sides=6, flip=True, yaw=rng.uniform(0, 60), solid=False)
        else:
            L = rng.uniform(8.0, 15.0)
            m.cyl(g, "Chain", "alloy_dark", P(r, deg, y - L), 0.3, L, sides=6, solid=False)
            m.block(g, "ChainWeight", "brass", P(r, deg, y - L - 0.7), (1.4, 1.4, 1.4), shape="bevel", bevel=0.35)
    # The burn layer: a hot, hazy band of light where the atmosphere begins. Fall into it and you burn up.
    b = m.group("BurnLayer", "Exterior")
    # (Rings of it, fainter the further out, so it has no hard rim; the Environment's
    # height fog below thickens everything that falls toward it into the same glow.)
    for n, (r0, r1, kind) in enumerate(((0.0, 160.0, "burn"), (160.0, 320.0, "burn"), (320.0, 560.0, "burn_haze"), (560.0, 900.0, "burn_haze"))):
        for layer in range(2 if n < 2 else 1):
            m.block(b, "Burn" if n < 2 else "BurnHaze", kind if layer == 0 else "burn_haze", (0, KILL + 1.0 + layer * 9.0 + n * 0.5, 0), (2 * r1, 1.0, 2 * r1),
                    shape="tube" if r0 > 0 else "cyl", sides=48, inner=2 * r0 if r0 > 0 else None, solid=False)


def zones(m):
    """Gravity: 40% everywhere (MapRoot.gravity_outside) but inside the tower's wall line,
    which these fill: the tower itself (it tapers) and the root below the Engine's floor."""
    g = m.folder("GravityZones")
    m.node("Tower", g, "zone", [("transform", xform(IDENTITY, (0, TOP * 0.5 - 0.5, 0))), ("shape", "1"),
                                ("size", vec((2 * (R_FOOT - 0.5), TOP + 1.0, 2 * (R_FOOT - 0.5)))), ("top", fmt((R_TOP - 0.5) / (R_FOOT - 0.5)))])


def build(path):
    m = EmpyreanMap("EmpyreanTower", PAL,
                    {"lines": ["ambient_light_source = 2", "ambient_light_color = Color(0.88, 0.85, 1, 1)",
                               "ambient_light_energy = 1.0", "reflected_light_source = 1", "tonemap_mode = 2",
                               "tonemap_white = 3.0", "glow_enabled = true", "glow_intensity = 0.85", "glow_bloom = 0.05",
                               # (fog only far below the tower: the hot haze of the burn layer, which anything falling sinks into)
                               "fog_enabled = true", "fog_light_color = Color(1, 0.56, 0.32, 1)", "fog_sun_scatter = 0.0",
                               "fog_density = 0.0", "fog_sky_affect = 0.0", "fog_height = %s" % fmt(KILL + 30.0), "fog_height_density = 0.045"]},
                    (24.0, 250.0, (0.82, 0.78, 1.0), 0.75),
                    {"face_shade": "Vector3(0.9, 0.8, 0.66)", "kill_height": fmt(KILL), "bounds": "Rect2(0, 0, 0, 0)",
                     "swing_point": vec(stone_at(33.0)), "winding_floors": "true", "bots_grapple": "true",
                     "gravity_outside": "0.4",
                     # Drawing: the biggest map by far. Its decoration casts no shadow, and the small pieces
                     # of it are left out beyond 80 m (in cubes a tier high, so those behind you are not drawn).
                     "decor_shadows": "false", "detail_range": "80.0", "detail_size": "1.5", "detail_chunk": fmt(TIER)})
    m.folder("Exterior")
    zones(m)
    folders = [tier(m, i) for i in range(5)] + [observatory_structure(m)]
    for i in range(TIERS):
        shell(m, i)
    ribs(m)
    roof(m)
    shaft(m)
    lifts(m)
    balconies(m)
    docking_ring(m)
    thrusters(m)
    root(m)
    import empyrean_dressing as dressing
    dressing.dress(m, folders)
    import empyrean_decor as decor
    decor.decorate(m, folders)
    import empyrean_magic as magic
    magic.enchant(m, folders)
    import empyrean_planes as planes
    print("  settled %d faces that shared a plane with another" % planes.settle(m))
    m.write(path)
    write_palette(path.replace("game/maps/", "game/maps/palettes/").replace(".tscn", ".tres"))
