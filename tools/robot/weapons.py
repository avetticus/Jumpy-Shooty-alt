"""The guns. Each is modelled in gun space (barrel -Z, sights +Y, origin where the
right fist closes on the grip) and tied to the three gun bones:

  pistol        the gun itself (the bone is called "pistol" for history; every gun uses it)
  pistol_slide  the part that moves when the gun is worked: the pistol's slide, the
                shotgun's pump, the rifle's charging handle, the anti-materiel rifle's bolt
  pistol_mag    the magazine (the shotgun's: one shell, kept out of sight inside the
                receiver until a reload brings it out)

Every robot carries every gun in its model file; the game shows only the one the
player picked. A gun's triangles use materials named "<gun>.<kind>" (see KINDS), so
the game can tell which surfaces belong to which gun.

The look: made in the same factory as the robots and the melee weapons. A gunmetal
frame, armour-plate panels on its flanks, steel barrels, a near-black grip, and lit
parts in the player's trim colour ("glow": a channel along the gun and a window in
its power cell). Each keeps the outline of the real gun it is named after, a little
chunkier. What a reload moves is on the slide and magazine bones; each gun's vents
(the part a reload snaps open, on a bone of their own) are added with _vent().

The barrel line, the muzzle and where the hands go (SUPPORT, and the bolts, handles
and magazines in weapon_anims.py) are fixed points: a new shape has to be built
round them.
"""
import math

import numpy as np

from kit import Part, loft, rect, box, prism, ball
from rig import BODY, DUALS, GUN_REST

IDS = ("pistol", "shotgun", "rifle", "revolver", "machine_pistol", "break_action",
       "burst_rifle", "lmg", "lever_action", "railgun", "rocket_launcher", "grenade_launcher", "akimbo",
       # The third batch
       "air_cannon", "minigun",
       "battle_rifle", "crossbow", "anti_materiel",
       # Two-gun weapons (rig.DUALS)
       "dual_revolver", "dual_machine_pistol")

# Where the left fist holds each gun (gun space: the middle of the fist), and on which
# bone: the shotgun's hand rides on the pump. Under a fore-end the hand is cupped, palm
# up, and the point is 2 cm above the fore-end's underside (the palm is that far from
# the middle of the fist); "upright": an upright handle, held like a second grip. The
# pistol is held in both hands round the grip instead.
SUPPORT = {
    "shotgun": {"grip": (0.0, 0.027, -0.30), "on": "pistol_slide"},
    "rifle": {"grip": (0.0, 0.047, -0.235)},
    "break_action": {"grip": (0.0, 0.025, -0.30), "on": "pistol_vent"},  # the fore-end swings down with the barrels
    "burst_rifle": {"grip": (0.0, 0.044, -0.25)},
    "lmg": {"grip": (0.0, 0.025, -0.27)},
    "lever_action": {"grip": (0.0, 0.033, -0.28)},
    "railgun": {"grip": (0.0, 0.036, -0.27)},
    "rocket_launcher": {"grip": (0.0, -0.02, -0.24), "upright": True},  # the front handle under the tube
    "grenade_launcher": {"grip": (0.0, 0.025, -0.28)},
    "air_cannon": {"grip": (0.0, -0.045, -0.30), "upright": True},      # the front handle under the tank
    "minigun": {"grip": (0.0, -0.045, -0.30), "upright": True},         # the front handle under the barrels
    "battle_rifle": {"grip": (0.0, 0.043, -0.27)},
    "crossbow": {"grip": (0.0, 0.044, -0.25)},
    "anti_materiel": {"grip": (0.0, 0.030, -0.32)},
}


def _lin(r, g, b):
    """A colour as the game's own code writes it (sRGB), turned into what a model file holds (linear)."""
    return tuple(round(((c + 0.055) / 1.055) ** 2.4 if c > 0.04045 else c / 12.92, 4) for c in (r, g, b))


# The first five are the melee weapons' own colours (MeleeModel.KINDS), so a gun and a
# blade look cut from the same stock.
KINDS = {
    "dark": {"color": _lin(0.17, 0.18, 0.21), "metallic": 0.4, "roughness": 0.45},     # the gunmetal frame
    "plate": {"color": _lin(0.90, 0.91, 0.93), "metallic": 0.1, "roughness": 0.55},    # the robots' armour plate
    "steel": {"color": _lin(0.78, 0.80, 0.83), "metallic": 0.55, "roughness": 0.3},    # barrels and bare metal
    "detail": {"color": _lin(0.36, 0.38, 0.42), "metallic": 0.3, "roughness": 0.5},
    "grip": {"color": _lin(0.10, 0.10, 0.11), "metallic": 0.05, "roughness": 0.75},
    "accent": {"color": (0.95, 0.35, 0.25), "metallic": 0.1, "roughness": 0.5},    # paint in the player's colour
    # Lit parts. The game shows them in the player's trim colour and can dim and brighten
    # them (RobotModel.set_gun_glow).
    "glow": {"color": (0.95, 0.35, 0.25), "metallic": 0.0, "roughness": 0.4, "emission": (0.95, 0.35, 0.25)},
    "lens": {"color": (0.05, 0.10, 0.14), "metallic": 0.2, "roughness": 0.15, "emission": (0.10, 0.45, 0.60)},
}

# The bone each gun's vents ride on (a two-gun weapon's left gun: "pistol_l_vent"): a
# reload snaps them open (the "vent" key of a pose, see rig.solve).
VENT_BONE = "pistol_vent"


def materials():
    return {"%s.%s" % (g, k): dict(m) for g in IDS for k, m in KINDS.items()}


def _place(part, bone="pistol"):
    o = BODY.bone(bone).pos
    return Part(part.t @ GUN_REST.T + o)


def _sec(w, h, fwd, y=0.0, x=0.0, ch=0.0):
    """A rectangle across the barrel line: w wide, h tall, `fwd` metres in front of the grip."""
    return rect(w, h, fwd, ch, cx=x, cz=y)


def _run(secs):
    """Loft rings made by _sec into a part running forwards (-Z)."""
    return loft(secs).rot(pitch=-90)


def _tube(r, back, front, y, sides=8, x=0.0, r_front=None):
    """A round bar along the barrel line from `back` to `front` metres ahead of the grip
    (r_front: a different radius at the front, for a cone)."""
    return prism(sides, r, front - back, r_top=r_front, phase=0.39).rot(pitch=-90).move(x, y, -(back + front) / 2.0)


def _rings(r, starts, length, y, sides=8, x=0.0):
    """Short collars round the barrel line, one starting at each of `starts`."""
    out = Part([])
    for f in starts:
        out = out + _tube(r, f, f + length, y, sides, x)
    return out


def _ears(p):
    """Triangles (index triples) filling the outline p (counter-clockwise, no crossings)."""
    idx = list(range(len(p)))
    out = []
    while len(idx) > 3:
        for k in range(len(idx)):
            i, j, l = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = p[i], p[j], p[l]
            if (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) <= 1e-12:
                continue   # a corner that turns inwards

            def inside(q):
                d1 = (b[0] - a[0]) * (q[1] - a[1]) - (b[1] - a[1]) * (q[0] - a[0])
                d2 = (c[0] - b[0]) * (q[1] - b[1]) - (c[1] - b[1]) * (q[0] - b[0])
                d3 = (a[0] - c[0]) * (q[1] - c[1]) - (a[1] - c[1]) * (q[0] - c[0])
                return d1 > 1e-12 and d2 > 1e-12 and d3 > 1e-12
            if any(inside(p[m]) for m in idx if m not in (i, j, l)):
                continue
            out.append((i, j, l))
            idx.pop(k)
            break
        else:
            break
    out.append(tuple(idx[:3]))
    return out


def _slab(outline, x0, x1, bevel=0.0, cap0=True):
    """A plate cut out of the gun's side view: `outline` is [(forward, up), ...] round its
    edge, and it runs across the gun from x0 to x1. bevel: how far the face at x1 is set
    in from the edge all round (a pressed panel, not a slab)."""
    p = [(float(f), float(y)) for f, y in outline]
    n = len(p)
    if sum(p[i][0] * p[(i + 1) % n][1] - p[(i + 1) % n][0] * p[i][1] for i in range(n)) < 0:
        p.reverse()
    s = 1.0 if x1 > x0 else -1.0
    normals = []
    for i in range(n):
        a, b = p[i], p[(i + 1) % n]
        length = math.hypot(b[0] - a[0], b[1] - a[1]) or 1.0
        normals.append(((b[1] - a[1]) / length, -(b[0] - a[0]) / length))
    face = p
    if bevel > 0.0:
        face = []
        for i in range(n):
            n1, n2 = normals[i - 1], normals[i]
            k = max(1.0 + n1[0] * n2[0] + n1[1] * n2[1], 0.35)
            face.append((p[i][0] - bevel * (n1[0] + n2[0]) / k, p[i][1] - bevel * (n1[1] + n2[1]) / k))
    xb = x1 - s * bevel if bevel > 0.0 else x1
    tris = []

    def at(q, x):
        return np.array([x, q[1], -q[0]])

    def tri(a, b, c, out):
        if np.dot(np.cross(b - a, c - a), out) < 0:
            b, c = c, b
        tris.append([a, b, c])

    for i in range(n):
        j = (i + 1) % n
        out = np.array([0.0, normals[i][1], -normals[i][0]])
        tri(at(p[i], x0), at(p[j], x0), at(p[j], xb), out)
        tri(at(p[i], x0), at(p[j], xb), at(p[i], xb), out)
        if bevel > 0.0:
            lean = out + np.array([s, 0.0, 0.0])
            tri(at(p[i], xb), at(p[j], xb), at(face[j], x1), lean)
            tri(at(p[i], xb), at(face[j], x1), at(face[i], x1), lean)
    fill = _ears(p)
    for i, j, l in fill:
        if cap0:
            tri(at(p[i], x0), at(p[j], x0), at(p[l], x0), np.array([-s, 0.0, 0.0]))
        tri(at(face[i], x1), at(face[j], x1), at(face[l], x1), np.array([s, 0.0, 0.0]))
    return Part([t for t in tris if np.linalg.norm(np.cross(t[1] - t[0], t[2] - t[0])) > 1e-10])


def _both(part):
    """The part and its mirror image on the gun's other side."""
    return part + part.mirrored()


def _core(outline, w, bevel=0.0):
    """A slab on the gun's centre line, w wide (see _slab)."""
    return _both(_slab(outline, 0.0, -w / 2.0, bevel, cap0=False))


def _panels(outline, x, thick=0.005, bevel=0.002):
    """A pair of panels, one on each flank: `outline` in the side view, standing from x
    out to x + thick."""
    return _both(_slab(outline, -x, -x - thick, bevel, cap0=False))


def _slats(f0, n, pitch, y0, y1, x, t=0.006, lean=0.006, thick=0.004):
    """A row of n slanted vent slats on each flank, the first at f0, `pitch` apart."""
    out = Part([])
    for i in range(n):
        f = f0 + i * pitch
        out = out + _panels([(f, y0), (f + t, y0), (f + t + lean, y1), (f + lean, y1)], x, thick, 0.0)
    return out


def _add(mesh, gun, kind, bone, part):
    # A two-gun weapon's left gun rides on its own bones ("pistol_l", "pistol_l_slide"...).
    mesh.add(_place(part, "pistol_l" if bone.startswith("pistol_l") else "pistol"), "%s.%s" % (gun, kind), bone)


def _vent(mesh, gun, kind, part, bone=VENT_BONE):
    """The gun's vents: the part a reload snaps open."""
    _add(mesh, gun, kind, bone, part)


def _grip(pitch=-16.0, w=0.036, h=0.112, d=0.05, y=-0.035, z=0.02):
    """The pistol grip in the right fist."""
    return box(w, h, d, 0.011).rot(pitch=pitch).move(0, y, z)


def _guard(front=0.08, drop=-0.014):
    """The trigger guard: a bar under the trigger and a slanted bar up to the frame."""
    return _core([(0.012, drop - 0.006), (front - 0.012, drop - 0.006), (front + 0.004, 0.026), (front - 0.008, 0.026),
                  (front - 0.018, drop + 0.006), (0.012, drop + 0.006)], 0.012)


def _cell(w, h, d, pitch=0.0, y=0.0, z=0.0, window=0.5):
    """A power cell (most guns' magazine): [its body, the lit window down its front, its
    base pad], to be added as "detail", "glow" and "accent"."""
    body = box(w, h, d, 0.006).rot(pitch=pitch).move(0, y, z)
    lit = box(w + 0.003, h * window, d * 0.34).move(0, -h * (1.0 - window) * 0.25, -d * 0.36).rot(pitch=pitch).move(0, y, z)
    pad = box(w + 0.004, 0.012, d + 0.004, 0.006).move(0, -h / 2.0 + 0.002, 0).rot(pitch=pitch).move(0, y, z)
    return body, lit, pad


def _stock(mesh, g, back, top, heel, toe, w=0.042, neck=-0.045, open_frame=False):
    """A shoulder stock running back from the receiver to the butt at `back`: its top
    line at `top`, the butt from `heel` (top) down to `toe`. A gunmetal spine, an armour
    cheek panel on each flank and a butt pad in the player's colour. open_frame: a
    skeleton stock (two bars and the butt)."""
    if open_frame:
        spine = _core([(neck, top), (back + 0.03, top - 0.004), (back + 0.03, top - 0.03), (neck, top - 0.03)], w * 0.6, 0.003)
        strut = _core([(neck + 0.02, toe + 0.05), (neck + 0.02, toe + 0.074), (back + 0.03, toe + 0.03), (back + 0.03, toe + 0.006)], w * 0.6, 0.003)
        butt = _core([(back + 0.04, heel), (back + 0.008, heel - 0.006), (back + 0.008, toe + 0.006), (back + 0.04, toe)], w, 0.005)
        _add(mesh, g, "dark", "pistol", spine + strut + butt)
        _add(mesh, g, "plate", "pistol", _panels([(neck - 0.005, top - 0.004), (back + 0.07, top - 0.007), (back + 0.07, top - 0.026),
                                                (neck - 0.005, top - 0.026)], w * 0.3, 0.004))
    else:
        body = _core([(neck, top), (back + 0.03, top - 0.003), (back + 0.008, heel - 0.004), (back + 0.008, toe + 0.006),
                      (back + 0.035, toe), (back + 0.10, toe + 0.05), (neck, top - 0.058)], w, 0.006)
        _add(mesh, g, "dark", "pistol", body)
        _add(mesh, g, "plate", "pistol", _panels([(neck - 0.012, top - 0.008), (back + 0.045, top - 0.012), (back + 0.045, toe + 0.026),
                                                (back + 0.105, toe + 0.064), (neck - 0.012, top - 0.047)], w / 2.0 - 0.001, 0.005))
    _add(mesh, g, "accent", "pistol", _core([(back + 0.008, heel - 0.002), (back - 0.008, heel - 0.008), (back - 0.008, toe + 0.008),
                                            (back + 0.008, toe + 0.002)], w + 0.006, 0.004))


def _dot_sight(f, y, w=0.03, h=0.034, length=0.06):
    """A small reflex sight: [its housing, its lens], the lens facing the shooter."""
    housing = _core([(f, y), (f + length, y), (f + length, y + h), (f + length - 0.014, y + h + 0.006),
                     (f + 0.012, y + h + 0.006), (f, y + h * 0.5)], w, 0.004)
    lens = box(w - 0.008, h - 0.008, 0.003).move(0, y + h * 0.5 + 0.004, -f + 0.0005)
    return housing, lens


def _scope(f0, f1, y, r=0.019, bell=0.028):
    """A telescopic sight from f0 to f1 on the line y: [tube, mounts, front lens, a band
    in the player's colour]."""
    tube = (_tube(r * 1.25, f0, f0 + 0.03, y, 8) + _tube(r, f0 + 0.03, f1 - 0.07, y, 8)
            + _tube(r, f1 - 0.07, f1 - 0.045, y, 8, r_front=bell) + _tube(bell, f1 - 0.045, f1, y, 8))
    span = f1 - f0
    mounts = (_core([(f0 + span * 0.22, y - r - 0.03), (f0 + span * 0.22 + 0.022, y - r - 0.03), (f0 + span * 0.22 + 0.018, y), (f0 + span * 0.22 + 0.004, y)], 0.022)
              + _core([(f0 + span * 0.58, y - r - 0.03), (f0 + span * 0.58 + 0.022, y - r - 0.03), (f0 + span * 0.58 + 0.018, y), (f0 + span * 0.58 + 0.004, y)], 0.022))
    lens = _tube(bell * 0.84, f1 - 0.002, f1 + 0.002, y, 8)
    band = _tube(r * 1.12, f0 + span * 0.40, f0 + span * 0.40 + 0.016, y, 8)
    return tube, mounts, lens, band


# ---------------------------------------------------------------------------
# Sidearms

def _bones(side):
    """A gun's four bones: the right hand's ("pistol", "pistol_slide"...) or, with side
    "_l", the second gun's in the left fist ("pistol_l", "pistol_l_slide"...)."""
    return "pistol" + side, "pistol%s_slide" % side, "pistol%s_mag" % side, "pistol%s_vent" % side


def _pistol_one(mesh, g, side=""):
    frame_b, slide_b, mag_b, vent_b = _bones(side)
    _add(mesh, g, "grip", frame_b, _grip(-14, 0.038, 0.112, 0.05, -0.036, 0.018))
    frame = _core([(-0.068, 0.05), (0.178, 0.05), (0.178, 0.032), (0.172, 0.026), (-0.03, 0.024), (-0.068, 0.036)], 0.038, 0.004)
    _add(mesh, g, "dark", frame_b, frame + _guard(0.076))
    _add(mesh, g, "glow", frame_b, box(0.024, 0.012, 0.066).move(0, 0.021, -0.13))   # the core the vent covers
    # The vent: hinged at its back top corner (PISTOL_VENT_PIVOT in animations.py).
    _vent(mesh, g, "dark", _core([(0.086, 0.027), (0.172, 0.027), (0.163, 0.004), (0.096, 0.004)], 0.04, 0.004), vent_b)
    _vent(mesh, g, "detail", _slats(0.1, 4, 0.015, 0.008, 0.023, 0.02, t=0.007, lean=0.004, thick=0.003), vent_b)
    slide = _core([(-0.068, 0.052), (0.176, 0.052), (0.176, 0.082), (0.16, 0.092), (-0.05, 0.092), (-0.068, 0.08)], 0.04, 0.006)
    _add(mesh, g, "dark", slide_b, slide)
    _add(mesh, g, "plate", slide_b, _panels([(-0.03, 0.056), (0.088, 0.056), (0.106, 0.071), (0.168, 0.071), (0.168, 0.084),
                                            (0.156, 0.088), (-0.03, 0.088)], 0.019, 0.005))
    _add(mesh, g, "glow", slide_b, _panels([(0.101, 0.057), (0.167, 0.057), (0.167, 0.066), (0.112, 0.066)], 0.0195, 0.002, 0.0))
    _add(mesh, g, "detail", slide_b, _slats(-0.062, 4, 0.008, 0.058, 0.086, 0.0195, t=0.004, lean=0.003, thick=0.003)
         + box(0.022, 0.008, 0.012).move(0, 0.096, 0.052) + box(0.006, 0.009, 0.014).move(0, 0.0965, -0.162))
    _add(mesh, g, "steel", frame_b, _tube(0.013, 0.17, 0.198, 0.068, 8))
    _add(mesh, g, "detail", frame_b, _tube(0.0155, 0.183, 0.191, 0.068, 8))
    _add(mesh, g, "detail", mag_b, box(0.026, 0.11, 0.034).rot(pitch=-14).move(0, -0.045, 0.02))
    _add(mesh, g, "glow", mag_b, box(0.032, 0.01, 0.042, 0.006).move(0, -0.058, 0).rot(pitch=-14).move(0, -0.045, 0.02))


def pistol(mesh):
    """A chunky sidearm, about 26 cm: armour plates on the slide with a lit channel under
    their step, and a power cell in the grip whose lit base shows under it. Its vent is
    the chin under the barrel: a reload drops it open on its hinge, off a lit core."""
    _pistol_one(mesh, "pistol")


def _revolver_one(mesh, g, side=""):
    frame_b, slide_b, mag_b, vent_b = _bones(side)
    _add(mesh, g, "grip", frame_b, box(0.038, 0.12, 0.05, 0.012).rot(pitch=-22).move(0, -0.04, 0.024))
    _add(mesh, g, "plate", frame_b, box(0.044, 0.066, 0.028, 0.008).rot(pitch=-22).move(0, -0.046, 0.027))
    _add(mesh, g, "detail", frame_b, box(0.042, 0.012, 0.054, 0.012).move(0, -0.062, 0).rot(pitch=-22).move(0, -0.04, 0.024))
    frame = (_core([(-0.04, 0.012), (0.022, 0.012), (0.022, 0.084), (-0.012, 0.084), (-0.04, 0.052)], 0.038, 0.005)
             + _core([(0.0, 0.076), (0.116, 0.076), (0.116, 0.09), (0.0, 0.09)], 0.026, 0.003)
             + _core([(0.0, 0.006), (0.116, 0.006), (0.116, 0.019), (0.0, 0.019)], 0.022, 0.003))
    barrel = _core([(0.1, 0.036), (0.236, 0.036), (0.281, 0.054), (0.281, 0.086), (0.272, 0.092), (0.1, 0.092)], 0.03, 0.005)
    _add(mesh, g, "dark", frame_b, frame + barrel + _guard(0.074))
    _add(mesh, g, "plate", frame_b, _panels([(0.114, 0.056), (0.262, 0.056), (0.272, 0.062), (0.272, 0.084), (0.114, 0.084)], 0.0145, 0.004))
    _add(mesh, g, "glow", frame_b, _panels([(0.114, 0.042), (0.238, 0.042), (0.252, 0.051), (0.114, 0.051)], 0.0148, 0.002, 0.0))
    _add(mesh, g, "steel", frame_b, _tube(0.012, 0.274, 0.287, 0.066, 8))
    vents = Part([])
    for f in (0.128, 0.162, 0.196, 0.23):
        vents = vents + box(0.016, 0.006, 0.02).move(0, 0.094, -f)
    _vent(mesh, g, "detail", vents, vent_b)
    _add(mesh, g, "detail", frame_b, box(0.006, 0.012, 0.012).move(0, 0.097, -0.268))
    # The cylinder, on the magazine bone: it swings out to the side.
    _add(mesh, g, "steel", mag_b, _tube(0.031, 0.025, 0.098, 0.046, 6))
    _add(mesh, g, "glow", mag_b, _tube(0.0325, 0.052, 0.066, 0.046, 6))
    _add(mesh, g, "detail", mag_b, _tube(0.0325, 0.084, 0.092, 0.046, 6))
    _add(mesh, g, "dark", frame_b, _tube(0.008, 0.098, 0.105, 0.046, 6))   # the crane
    # The hammer, on the slide bone: it rocks back after a shot.
    _add(mesh, g, "detail", slide_b, box(0.012, 0.03, 0.016, 0.003).rot(pitch=20).move(0, 0.078, 0.022))


def _machine_pistol_one(mesh, g, side=""):
    frame_b, slide_b, mag_b, vent_b = _bones(side)
    _add(mesh, g, "grip", frame_b, _grip(-12, 0.036, 0.11, 0.05, -0.035, 0.018))
    frame = _core([(-0.066, 0.05), (0.175, 0.05), (0.175, 0.024), (-0.03, 0.024), (-0.066, 0.036)], 0.036, 0.004)
    stop = _core([(0.146, 0.026), (0.182, 0.026), (0.176, -0.014), (0.16, -0.014)], 0.024, 0.004)
    _add(mesh, g, "dark", frame_b, frame + _guard(0.076))
    _add(mesh, g, "detail", frame_b, stop)
    _vent(mesh, g, "detail", _slats(0.086, 4, 0.014, 0.028, 0.046, 0.018, t=0.006, lean=0.004, thick=0.003), vent_b)
    slide = _core([(-0.066, 0.052), (0.172, 0.052), (0.172, 0.084), (-0.05, 0.084), (-0.066, 0.074)], 0.04, 0.005)
    _add(mesh, g, "dark", slide_b, slide)
    _add(mesh, g, "plate", slide_b, _panels([(-0.024, 0.056), (0.164, 0.056), (0.164, 0.069), (0.062, 0.069), (0.048, 0.081),
                                            (-0.024, 0.081)], 0.019, 0.005))
    _add(mesh, g, "glow", slide_b, _panels([(0.067, 0.072), (0.164, 0.072), (0.164, 0.08), (0.058, 0.08)], 0.0195, 0.002, 0.0))
    _add(mesh, g, "detail", slide_b, _slats(-0.06, 4, 0.008, 0.058, 0.08, 0.0195, t=0.004, lean=0.003, thick=0.003)
         + box(0.02, 0.007, 0.012).move(0, 0.088, 0.05))
    _add(mesh, g, "steel", frame_b, _tube(0.016, 0.172, 0.237, 0.064, 6))
    _add(mesh, g, "detail", frame_b, _rings(0.0185, (0.184, 0.203, 0.222), 0.008, 0.064, 6))
    cell = box(0.027, 0.21, 0.036, 0.005)
    lit = box(0.031, 0.07, 0.012).move(0, -0.056, -0.014)
    pad = box(0.032, 0.014, 0.041, 0.006).move(0, -0.1, 0)
    for kind, part in (("detail", cell), ("glow", lit), ("accent", pad)):
        _add(mesh, g, kind, mag_b, part.rot(pitch=-12).move(0, -0.08, 0.012))


def revolver(mesh):
    """A big six-shooter, about 34 cm: a slab-sided barrel with an armour panel and a lit
    channel along it, a cylinder with a lit band that swings out to the left for reloads,
    and a hammer that cocks back after every shot."""
    _revolver_one(mesh, "revolver")


def machine_pistol(mesh):
    """A boxy full-auto sidearm, about 27 cm: a long power cell with a lit window, a finned
    compensator and a hand stop under the muzzle."""
    _machine_pistol_one(mesh, "machine_pistol")


# The sidearms that can be built on either hand's bones (side "" or "_l").
ONE = {"pistol": _pistol_one, "revolver": _revolver_one, "machine_pistol": _machine_pistol_one}


def dual(weapon):
    """A two-gun weapon (rig.DUALS: the Dual Pistols, id "akimbo"...): its sidearm in each
    fist, the same gun built twice, on the right-hand gun bones and on the left
    ("pistol_l"...). Its surfaces are "<weapon>.<kind>", so the game shows them only
    when it is picked."""
    def build(mesh):
        for side in ("", "_l"):
            ONE[DUALS[weapon]](mesh, weapon, side)
    return build


DERRINGER_HINGE = (0.034, 0.042)   # (up, forward) of the grip: the barrels tip down about it


# ---------------------------------------------------------------------------
# Shotguns

def _shotgun_body(mesh, g, back, sight_port=False):
    """The pump gun's body: the grip, a receiver with an armour panel and the lit
    channel under its step, the stock, and one charge shell for reloads (hidden inside
    the receiver until a reload brings it out)."""
    _add(mesh, g, "grip", "pistol", box(0.04, 0.12, 0.052, 0.011).rot(pitch=-20).move(0, -0.035, 0.022))
    receiver = _core([(-0.055, 0.03), (0.19, 0.022), (0.2, 0.04), (0.2, 0.088), (0.18, 0.096), (-0.03, 0.096), (-0.055, 0.08)], 0.05, 0.006)
    _add(mesh, g, "dark", "pistol", receiver + _guard(0.082))
    _add(mesh, g, "plate", "pistol", _panels([(-0.036, 0.058), (0.108, 0.058), (0.124, 0.071), (0.188, 0.071), (0.188, 0.09), (-0.02, 0.09),
                                             (-0.036, 0.08)], 0.0245, 0.005))
    _add(mesh, g, "glow", "pistol", _panels([(0.118, 0.054), (0.19, 0.054), (0.19, 0.066), (0.132, 0.066)], 0.025, 0.002, 0.0))
    _stock(mesh, g, back, 0.082, 0.076, -0.034, 0.046)
    _add(mesh, g, "glow", "pistol_mag", _tube(0.011, 0.02, 0.07, 0.05, 6))
    _add(mesh, g, "detail", "pistol_mag", _tube(0.0115, 0.0, 0.02, 0.05, 6))


def _pump(kind_body, kind_ribs):
    """The pump (on the slide bone: the left fist rides on it): [body, ribs]."""
    body = _run([_sec(0.05, 0.046, 0.21, 0.036, ch=0.013), _sec(0.06, 0.058, 0.236, 0.036, ch=0.016),
                 _sec(0.06, 0.058, 0.364, 0.036, ch=0.016), _sec(0.05, 0.046, 0.39, 0.036, ch=0.013)])
    ribs = Part([])
    for i in range(4):
        ribs = ribs + _run([_sec(0.063, 0.061, 0.256 + i * 0.03, 0.036, ch=0.017), _sec(0.063, 0.061, 0.268 + i * 0.03, 0.036, ch=0.017)])
    return (kind_body, body), (kind_ribs, ribs)


def shotgun(mesh):
    """Pump-action, about 80 cm: a thick barrel under a slatted heat shield, a charge tube
    below it, and a ribbed pump in the player's colour that racks back after every shot."""
    g = "shotgun"
    _shotgun_body(mesh, g, -0.25)
    _add(mesh, g, "steel", "pistol", _tube(0.019, 0.19, 0.585, 0.072, 8))
    _add(mesh, g, "dark", "pistol", _tube(0.023, 0.552, 0.602, 0.072, 8) + _tube(0.014, 0.19, 0.515, 0.036, 8)
         + box(0.008, 0.012, 0.012).move(0, 0.098, -0.585))
    _add(mesh, g, "detail", "pistol", _tube(0.0165, 0.5, 0.522, 0.036, 8))
    slats = Part([])
    for i in range(7):
        slats = slats + box(0.03, 0.006, 0.02, 0.004).move(0, 0.094, -(0.235 + i * 0.04))
    _vent(mesh, g, "detail", slats)
    for kind, part in _pump("grip", "accent"):
        _add(mesh, g, kind, "pistol_slide", part)


BREAK_HINGE = (0.045, 0.13)   # (up, forward) of the grip: the barrels tip down about it


def break_action(mesh):
    """A side-by-side double barrel, about 85 cm, with an armour stock and fore-end and a
    lit rib between the barrels. The barrels and fore-end are its vent part: they tip down
    on their hinge (BREAK_HINGE) to reload; the two shells in the breech are on the
    magazine bone."""
    g = "break_action"
    _add(mesh, g, "grip", "pistol", box(0.038, 0.11, 0.05, 0.011).rot(pitch=-22).move(0, -0.034, 0.024))
    receiver = _core([(-0.046, 0.024), (0.13, 0.02), (0.13, 0.084), (-0.02, 0.088), (-0.046, 0.07)], 0.052, 0.006)
    _add(mesh, g, "dark", "pistol", receiver + _guard(0.08))
    _add(mesh, g, "plate", "pistol", _panels([(-0.03, 0.034), (0.118, 0.03), (0.118, 0.076), (-0.012, 0.08), (-0.03, 0.064)], 0.0255, 0.005))
    _add(mesh, g, "detail", "pistol", _slats(0.0, 4, 0.024, 0.04, 0.066, 0.0305, t=0.008, lean=0.006, thick=0.003))
    _add(mesh, g, "detail", "pistol", box(0.012, 0.016, 0.03).rot(pitch=-30).move(0, 0.09, 0.0))   # top lever
    _stock(mesh, g, -0.27, 0.07, 0.068, -0.045, 0.046)
    _vent(mesh, g, "steel", _tube(0.018, 0.13, 0.66, 0.066, 8, x=-0.018) + _tube(0.018, 0.13, 0.66, 0.066, 8, x=0.018))
    _vent(mesh, g, "dark", box(0.074, 0.018, 0.53).move(0, 0.05, -0.395)
          + _run([_sec(0.08, 0.044, 0.6, 0.066, ch=0.014), _sec(0.08, 0.044, 0.628, 0.066, ch=0.014)]))
    _vent(mesh, g, "glow", box(0.007, 0.006, 0.44).move(0, 0.086, -0.37))
    _vent(mesh, g, "plate", _run([_sec(0.066, 0.044, 0.14, 0.03, ch=0.014), _sec(0.07, 0.05, 0.36, 0.03, ch=0.016)]))
    _vent(mesh, g, "accent", _run([_sec(0.073, 0.022, 0.36, 0.035), _sec(0.073, 0.022, 0.38, 0.035)]))
    # The two shells: their rims stand a little proud of the breech (hidden by the receiver until the barrels tip open).
    for x in (-0.018, 0.018):
        _add(mesh, g, "accent", "pistol_mag", _tube(0.0135, 0.136, 0.19, 0.066, 8, x=x))
        _add(mesh, g, "steel", "pistol_mag", _tube(0.0155, 0.128, 0.137, 0.066, 8, x=x))


def air_cannon(mesh):
    """A compressed-air cannon, about 75 cm: a wide armour barrel ending in a flared bell
    with a lit throat, an air tank slung underneath (its magazine) and a front handle."""
    g = "air_cannon"
    _add(mesh, g, "grip", "pistol", _grip(-16, 0.038))
    body = _core([(-0.066, 0.014), (0.16, 0.014), (0.172, 0.03), (0.172, 0.104), (0.15, 0.117), (-0.03, 0.117), (-0.066, 0.08)], 0.06, 0.008)
    bracket = _core([(0.262, -0.004), (0.336, -0.004), (0.346, 0.042), (0.252, 0.042)], 0.03, 0.004)
    _add(mesh, g, "dark", "pistol", body + bracket + _guard(0.08))
    _add(mesh, g, "plate", "pistol", _panels([(-0.046, 0.05), (0.158, 0.05), (0.158, 0.108), (-0.02, 0.108), (-0.046, 0.082)], 0.0295, 0.005)
         + _tube(0.041, 0.172, 0.5, 0.075, 10))
    _vent(mesh, g, "detail", _slats(-0.02, 5, 0.028, 0.06, 0.098, 0.0345, t=0.009, lean=0.007, thick=0.003))
    _add(mesh, g, "accent", "pistol", _rings(0.0435, (0.3, 0.42), 0.03, 0.075, 10))
    _add(mesh, g, "dark", "pistol", _tube(0.046, 0.495, 0.62, 0.075, 10, r_front=0.078))
    _add(mesh, g, "glow", "pistol", _tube(0.05, 0.6, 0.6215, 0.075, 10, r_front=0.066) + box(0.03, 0.006, 0.06).move(0, 0.119, -0.08))
    _add(mesh, g, "grip", "pistol", box(0.032, 0.085, 0.038, 0.009).move(0, -0.032, -0.30))
    _stock(mesh, g, -0.24, 0.086, 0.08, -0.03, 0.044)
    _add(mesh, g, "steel", "pistol_mag", _tube(0.03, 0.06, 0.26, 0.0, 10))
    _add(mesh, g, "glow", "pistol_mag", _tube(0.032, 0.12, 0.15, 0.0, 10))
    _add(mesh, g, "detail", "pistol_mag", _tube(0.024, 0.255, 0.275, 0.0, 10) + _tube(0.032, 0.062, 0.076, 0.0, 10))


# ---------------------------------------------------------------------------
# Automatics

def _handle(x, y, z, w=0.03):
    """A charging handle on the left of the receiver (on the slide bone: a reload pulls it back)."""
    return box(w, 0.018, 0.034, 0.005).move(x, y, z)


def _add_cell(mesh, g, w, h, d, pitch, y, z, window=0.5):
    """A power cell on the magazine bone: grey body, lit window, base pad in the player's colour."""
    body, lit, pad = _cell(w, h, d, pitch, y, z, window)
    _add(mesh, g, "detail", "pistol_mag", body)
    _add(mesh, g, "glow", "pistol_mag", lit)
    _add(mesh, g, "accent", "pistol_mag", pad)


def _add_sight(mesh, g, f, y, w=0.03, h=0.034, length=0.064):
    housing, lens = _dot_sight(f, y, w, h, length)
    _add(mesh, g, "dark", "pistol", housing)
    _add(mesh, g, "lens", "pistol", lens)


def _add_scope(mesh, g, f0, f1, y, r=0.019, bell=0.028):
    tube, mounts, lens, band = _scope(f0, f1, y, r, bell)
    _add(mesh, g, "dark", "pistol", tube)
    _add(mesh, g, "detail", "pistol", mounts)
    _add(mesh, g, "lens", "pistol", lens)
    _add(mesh, g, "accent", "pistol", band)


def rifle(mesh):
    """Assault rifle, about 80 cm: an armoured receiver and handguard, a curved power
    cell with a lit front, a reflex sight, and a charging handle on the left side."""
    g = "rifle"
    _add(mesh, g, "grip", "pistol", _grip(-18))
    receiver = _core([(-0.066, 0.018), (0.035, 0.018), (0.035, -0.012), (0.126, -0.012), (0.134, 0.03), (0.186, 0.03), (0.186, 0.092),
                      (-0.04, 0.092), (-0.066, 0.07)], 0.046, 0.006)
    hand = _run([_sec(0.046, 0.05, 0.18, 0.052, ch=0.014), _sec(0.046, 0.05, 0.43, 0.052, ch=0.014)])
    _add(mesh, g, "dark", "pistol", receiver + hand + _guard(0.076) + box(0.008, 0.03, 0.012).move(0, 0.092, -0.40))
    _add(mesh, g, "plate", "pistol", _panels([(-0.046, 0.056), (0.088, 0.056), (0.104, 0.069), (0.179, 0.069), (0.179, 0.088), (-0.03, 0.088),
                                             (-0.046, 0.078)], 0.0225, 0.005)
         + _panels([(0.196, 0.034), (0.416, 0.034), (0.428, 0.046), (0.428, 0.07), (0.196, 0.07)], 0.0225, 0.005))
    _add(mesh, g, "glow", "pistol", _panels([(0.098, 0.052), (0.181, 0.052), (0.181, 0.064), (0.112, 0.064)], 0.023, 0.002, 0.0))
    _vent(mesh, g, "dark", _slats(0.226, 6, 0.031, 0.04, 0.064, 0.0275, t=0.01, lean=0.007, thick=0.002))
    _add(mesh, g, "steel", "pistol", _tube(0.012, 0.43, 0.525, 0.052, 6))
    _add(mesh, g, "detail", "pistol", _tube(0.018, 0.518, 0.567, 0.052, 6) + box(0.022, 0.008, 0.2).move(0, 0.096, -0.075))
    _add_sight(mesh, g, 0.02, 0.1, 0.032, 0.034, 0.07)
    _stock(mesh, g, -0.215, 0.084, 0.078, -0.025, 0.042)
    # The curved cell: its body, the lit strip down its front, and its base pad.
    mag = loft([rect(0.032, 0.075, 0.0, 0.008, cz=-0.08), rect(0.032, 0.075, -0.07, 0.008, cz=-0.09),
                rect(0.032, 0.07, -0.15, 0.008, cz=-0.11), rect(0.032, 0.068, -0.19, 0.008, cz=-0.125)])
    lit = loft([rect(0.035, 0.014, -0.03, cz=-0.119), rect(0.035, 0.014, -0.07, cz=-0.1235), rect(0.035, 0.014, -0.15, cz=-0.141),
                rect(0.035, 0.014, -0.17, cz=-0.148)])
    _add(mesh, g, "detail", "pistol_mag", mag)
    _add(mesh, g, "glow", "pistol_mag", lit)
    _add(mesh, g, "accent", "pistol_mag", box(0.035, 0.012, 0.074, 0.004).move(0, -0.185, -0.125))
    _add(mesh, g, "detail", "pistol_slide", _handle(-0.036, 0.07, -0.13))


def burst_rifle(mesh):
    """A sleek burst rifle, about 85 cm: a long armour shroud split by a lit line, a long
    top sight with a glowing lens, a box cell and a charging handle at the back."""
    g = "burst_rifle"
    _add(mesh, g, "grip", "pistol", _grip(-18))
    core = _run([_sec(0.046, 0.056, -0.06, 0.06, ch=0.014), _sec(0.046, 0.056, 0.2, 0.06, ch=0.014),
                 _sec(0.05, 0.064, 0.24, 0.056, ch=0.018), _sec(0.05, 0.064, 0.5, 0.056, ch=0.018),
                 _sec(0.036, 0.044, 0.56, 0.056, ch=0.012)])
    sight = _core([(-0.04, 0.086), (0.16, 0.086), (0.16, 0.122), (0.14, 0.128), (-0.02, 0.128), (-0.04, 0.11)], 0.03, 0.005)
    _add(mesh, g, "dark", "pistol", core + sight + _guard(0.078))
    _add(mesh, g, "plate", "pistol", _panels([(-0.046, 0.04), (0.19, 0.04), (0.19, 0.084), (-0.03, 0.084), (-0.046, 0.07)], 0.0225, 0.005)
         + _panels([(0.236, 0.063), (0.5, 0.063), (0.54, 0.064), (0.5, 0.086), (0.236, 0.086)], 0.0245, 0.005)
         + _panels([(0.236, 0.027), (0.5, 0.027), (0.54, 0.047), (0.5, 0.05), (0.236, 0.05)], 0.0245, 0.005))
    _add(mesh, g, "glow", "pistol", _panels([(0.236, 0.051), (0.525, 0.051), (0.525, 0.062), (0.236, 0.062)], 0.025, 0.002, 0.0))
    _add(mesh, g, "detail", "pistol", _slats(0.02, 5, 0.03, 0.048, 0.076, 0.0275, t=0.009, lean=0.007, thick=0.003))
    _add(mesh, g, "steel", "pistol", _tube(0.011, 0.56, 0.622, 0.056, 6))
    _add(mesh, g, "lens", "pistol", box(0.022, 0.022, 0.003).move(0, 0.107, -0.1605))
    _stock(mesh, g, -0.24, 0.084, 0.08, -0.03, 0.044)
    _add_cell(mesh, g, 0.03, 0.14, 0.05, 8.0, -0.045, -0.10)
    # Its vent part is a second cell, in the same place: the new one a reload knocks the old one out
    # with (the game draws it only while the left hand has it: ReloadFx "spare").
    for kind, part in zip(("detail", "glow", "accent"), _cell(0.03, 0.14, 0.05, 8.0, -0.045, -0.10)):
        _vent(mesh, g, kind, part)
    _add(mesh, g, "detail", "pistol_slide", _handle(-0.036, 0.075, 0.02))


def battle_rifle(mesh):
    """A battle rifle, about 95 cm: a long barrel with a muzzle brake, a straight cell, an
    armour handguard with cooling slots, and a low-power scope."""
    g = "battle_rifle"
    _add(mesh, g, "grip", "pistol", _grip(-16))
    receiver = _core([(-0.066, 0.018), (0.14, 0.018), (0.15, 0.03), (0.2, 0.03), (0.2, 0.094), (-0.04, 0.094), (-0.066, 0.072)], 0.048, 0.006)
    cap = _run([_sec(0.057, 0.057, 0.452, 0.05, ch=0.017), _sec(0.048, 0.048, 0.482, 0.052, ch=0.014)])
    _add(mesh, g, "dark", "pistol", receiver + cap + _guard(0.078))
    _add(mesh, g, "plate", "pistol", _panels([(-0.046, 0.054), (0.098, 0.054), (0.114, 0.067), (0.192, 0.067), (0.192, 0.09), (-0.03, 0.09),
                                             (-0.046, 0.078)], 0.0235, 0.005)
         + _run([_sec(0.054, 0.054, 0.2, 0.05, ch=0.016), _sec(0.054, 0.054, 0.455, 0.05, ch=0.016)]))
    _add(mesh, g, "glow", "pistol", _panels([(0.108, 0.05), (0.194, 0.05), (0.194, 0.062), (0.122, 0.062)], 0.024, 0.002, 0.0))
    _vent(mesh, g, "dark", _slats(0.236, 5, 0.04, 0.04, 0.062, 0.027, t=0.014, lean=0.008, thick=0.002))
    _add(mesh, g, "steel", "pistol", _tube(0.012, 0.46, 0.685, 0.056, 6))
    _add(mesh, g, "detail", "pistol", _run([_sec(0.034, 0.034, 0.672, 0.056, ch=0.01), _sec(0.034, 0.034, 0.722, 0.056, ch=0.01)]))
    _add_scope(mesh, g, -0.03, 0.17, 0.127, 0.017, 0.022)
    _stock(mesh, g, -0.25, 0.086, 0.08, -0.035, 0.044)
    _add_cell(mesh, g, 0.03, 0.13, 0.052, 0.0, -0.04, -0.09)
    _add(mesh, g, "detail", "pistol_slide", _handle(-0.037, 0.07, -0.12))


def _ammo_box(mesh, g, w, h, d, y, z):
    """A box of ammunition on the magazine bone: a lit gauge on each flank, a band in the player's colour."""
    _add(mesh, g, "detail", "pistol_mag", box(w, h, d, 0.012).move(0, y, z))
    _add(mesh, g, "glow", "pistol_mag", _panels([(-z - d * 0.3, y - h * 0.22), (-z + d * 0.3, y - h * 0.22), (-z + d * 0.3, y + h * 0.18),
                                                (-z - d * 0.3, y + h * 0.18)], w / 2.0, 0.002, 0.0))
    _add(mesh, g, "accent", "pistol_mag", box(w + 0.003, 0.018, d + 0.003, 0.012).move(0, y - h * 0.38, z))


def _carry_handle(f0, f1, y):
    return (box(0.016, 0.05, 0.016).move(0, y, -f0) + box(0.016, 0.05, 0.016).move(0, y, -f1)
            + box(0.018, 0.016, f1 - f0 + 0.03, 0.004).move(0, y + 0.028, -(f0 + f1) / 2.0))


def lmg(mesh):
    """A belt-fed light machine gun, about 1 m: a big armoured receiver with a top cover,
    a box of ammunition hanging underneath, a ringed barrel shroud and a carry handle."""
    g = "lmg"
    _add(mesh, g, "grip", "pistol", _grip(-18, 0.038))
    receiver = _core([(-0.076, 0.012), (0.24, 0.012), (0.25, 0.03), (0.25, 0.088), (-0.05, 0.088), (-0.076, 0.066)], 0.062, 0.008)
    guard = _run([_sec(0.056, 0.05, 0.25, 0.03, ch=0.014), _sec(0.056, 0.05, 0.42, 0.03, ch=0.014)])
    _add(mesh, g, "dark", "pistol", receiver + guard + _guard(0.08))
    _add(mesh, g, "plate", "pistol", _panels([(-0.056, 0.036), (0.138, 0.036), (0.154, 0.05), (0.24, 0.05), (0.24, 0.082), (-0.04, 0.082),
                                             (-0.056, 0.068)], 0.0305, 0.005))
    _add(mesh, g, "glow", "pistol", _panels([(0.148, 0.032), (0.242, 0.032), (0.242, 0.045), (0.162, 0.045)], 0.031, 0.002, 0.0))
    _add(mesh, g, "detail", "pistol", _tube(0.028, 0.25, 0.66, 0.06, 8) + _carry_handle(0.10, 0.26, 0.112)
         + box(0.012, 0.012, 0.18).rot(pitch=8).move(-0.027, 0.02, -0.52) + box(0.012, 0.012, 0.18).rot(pitch=8).move(0.027, 0.02, -0.52))
    _vent(mesh, g, "accent", _rings(0.0305, (0.45, 0.49, 0.53, 0.57, 0.61), 0.02, 0.06, 8))
    _add(mesh, g, "steel", "pistol", _tube(0.013, 0.66, 0.76, 0.06, 6))
    _add(mesh, g, "dark", "pistol", _tube(0.021, 0.755, 0.802, 0.06, 6))
    _stock(mesh, g, -0.27, 0.086, 0.08, -0.04, 0.05)
    _add(mesh, g, "dark", "pistol_slide", box(0.066, 0.016, 0.2, 0.005).move(0, 0.095, -0.06))   # the top cover
    _add(mesh, g, "plate", "pistol_slide", box(0.048, 0.005, 0.15, 0.004).move(0, 0.1045, -0.06))
    _ammo_box(mesh, g, 0.072, 0.11, 0.12, -0.04, -0.12)


MINIGUN_AXIS = (0.05, 0.0)   # (up, forward) of the grip: the line the barrels turn about


def minigun(mesh):
    """A minigun, about 1 m: six barrels round a spindle, an armoured motor housing behind
    them with a lit ring, an ammunition box underneath (its top lid opens to reload), a
    carry handle and a front handle under the barrels."""
    g = "minigun"
    y = 0.05
    _add(mesh, g, "grip", "pistol", _grip(-18, 0.038) + box(0.032, 0.085, 0.038, 0.009).move(0, -0.032, -0.30))
    housing = _run([_sec(0.08, 0.092, -0.08, y, ch=0.022), _sec(0.08, 0.092, 0.2, y, ch=0.022), _sec(0.07, 0.08, 0.24, y, ch=0.018)])
    bracket = _core([(0.275, -0.004), (0.325, -0.004), (0.335, 0.012), (0.265, 0.012)], 0.03, 0.004)
    _add(mesh, g, "dark", "pistol", housing + bracket + _guard(0.08))
    _add(mesh, g, "plate", "pistol", _panels([(-0.062, 0.03), (0.078, 0.03), (0.094, 0.044), (0.19, 0.044), (0.19, 0.08), (-0.046, 0.08),
                                             (-0.062, 0.066)], 0.0395, 0.005))
    _add(mesh, g, "glow", "pistol", _panels([(0.088, 0.026), (0.192, 0.026), (0.192, 0.04), (0.102, 0.04)], 0.04, 0.002, 0.0)
         + _tube(0.0475, 0.3, 0.326, y, 10))
    _add(mesh, g, "detail", "pistol", _slats(-0.04, 4, 0.026, 0.05, 0.074, 0.0445, t=0.009, lean=0.007, thick=0.003))
    barrels = Part([])
    for i in range(6):
        a = i * math.pi / 3.0
        barrels = barrels + _tube(0.011, 0.24, 0.86, y + 0.026 * math.sin(a), 6, x=0.026 * math.cos(a))
    # The barrels and their clamps are its vent part: a reload spins them up (about MINIGUN_AXIS).
    _vent(mesh, g, "steel", barrels)
    _vent(mesh, g, "dark", _tube(0.045, 0.56, 0.59, y, 10) + _tube(0.043, 0.82, 0.85, y, 10))
    _add(mesh, g, "dark", "pistol", _tube(0.045, 0.26, 0.3, y, 10))
    _add(mesh, g, "detail", "pistol", _carry_handle(0.0, 0.18, 0.12))
    _stock(mesh, g, -0.225, 0.088, 0.084, -0.03, 0.05)
    _add(mesh, g, "dark", "pistol_slide", box(0.07, 0.016, 0.14, 0.005).move(0, 0.1, -0.06))    # the top lid
    _add(mesh, g, "plate", "pistol_slide", box(0.05, 0.005, 0.1, 0.004).move(0, 0.1095, -0.06))
    _ammo_box(mesh, g, 0.072, 0.1, 0.13, -0.05, -0.12)


# ---------------------------------------------------------------------------
# Precision

def _bolt(mesh, g, x, y, z, r=0.014, length=0.07):
    """A bolt on the slide bone, worked from the left: its body, the stem, and a ball knob."""
    _add(mesh, g, "steel", "pistol_slide", box(0.02, 0.022, length, 0.004).move(x + 0.058, y, z - 0.015))
    _add(mesh, g, "dark", "pistol_slide", prism(6, 0.007, 0.05).rot(roll=90).move(x + 0.027, y, z))
    _add(mesh, g, "accent", "pistol_slide", ball(r).move(x, y, z))


def lever_action(mesh):
    """A lever-action rifle, about 95 cm: an armour stock and fore-end, a charge tube
    under the eight-sided barrel, and the lever loop behind the trigger."""
    g = "lever_action"
    _add(mesh, g, "grip", "pistol", box(0.036, 0.10, 0.046, 0.011).rot(pitch=-24).move(0, -0.03, 0.026))
    receiver = _core([(-0.036, 0.012), (0.15, 0.012), (0.16, 0.03), (0.16, 0.088), (-0.01, 0.088), (-0.036, 0.066)], 0.042, 0.006)
    bands = (_core([(0.44, 0.03), (0.462, 0.03), (0.462, 0.082), (0.44, 0.082)], 0.032, 0.004)
             + _core([(0.68, 0.03), (0.7, 0.03), (0.7, 0.082), (0.68, 0.082)], 0.032, 0.004))
    _add(mesh, g, "dark", "pistol", receiver + bands + _tube(0.01, 0.15, 0.70, 0.04, 6)
         + box(0.006, 0.018, 0.012).move(0, 0.088, -0.752) + box(0.016, 0.012, 0.012).move(0, 0.094, -0.12))
    _add(mesh, g, "plate", "pistol", _panels([(-0.022, 0.046), (0.068, 0.046), (0.084, 0.06), (0.152, 0.06), (0.152, 0.083), (-0.006, 0.083),
                                             (-0.022, 0.07)], 0.0205, 0.005)
         + _run([_sec(0.046, 0.044, 0.162, 0.035, ch=0.013), _sec(0.046, 0.044, 0.42, 0.035, ch=0.013)]))
    _add(mesh, g, "glow", "pistol", _panels([(0.078, 0.042), (0.154, 0.042), (0.154, 0.056), (0.092, 0.056)], 0.021, 0.002, 0.0))
    _add(mesh, g, "accent", "pistol", _run([_sec(0.049, 0.047, 0.418, 0.035, ch=0.014), _sec(0.049, 0.047, 0.436, 0.035, ch=0.014)]))
    vents = Part([])
    for f in (0.03, 0.058, 0.086):
        vents = vents + box(0.022, 0.006, 0.016, 0.004).move(0, 0.09, -f)
    _vent(mesh, g, "detail", vents)
    _add(mesh, g, "steel", "pistol", _tube(0.014, 0.15, 0.78, 0.066, 8))
    _add(mesh, g, "detail", "pistol", box(0.006, 0.01, 0.03).move(-0.022, 0.055, -0.06))   # loading gate
    _stock(mesh, g, -0.275, 0.064, 0.058, -0.058, 0.044, neck=-0.03)
    # The lever loop, on the slide bone: it swings down about its pin and back.
    lever = (box(0.01, 0.01, 0.075).move(0, -0.012, -0.03) + box(0.01, 0.06, 0.01).move(0, -0.04, 0.008)
             + box(0.01, 0.01, 0.05).move(0, -0.07, -0.01) + box(0.01, 0.05, 0.01).move(0, -0.045, -0.036))
    _add(mesh, g, "detail", "pistol_slide", lever)
    _add(mesh, g, "accent", "pistol_slide", box(0.012, 0.012, 0.03).move(0, -0.072, -0.01))
    _add(mesh, g, "glow", "pistol_mag", _tube(0.007, 0.02, 0.06, 0.055, 6))   # one round, for reloads (hidden in the action)


def anti_materiel(mesh):
    """An anti-materiel rifle, about 1.35 m: a heavy barrel in an armour shroud with a huge
    muzzle brake, a big scope, a box cell, a bipod folded under and a bolt on the left."""
    g = "anti_materiel"
    _add(mesh, g, "grip", "pistol", _grip(-16, 0.038))
    receiver = _core([(-0.086, 0.026), (0.26, 0.026), (0.27, 0.04), (0.27, 0.086), (0.26, 0.094), (-0.06, 0.094), (-0.086, 0.076)], 0.056, 0.007)
    fore = _run([_sec(0.058, 0.05, 0.272, 0.035, ch=0.016), _sec(0.058, 0.05, 0.5, 0.035, ch=0.016)])
    brake = _run([_sec(0.074, 0.05, 1.02, 0.06, ch=0.014), _sec(0.074, 0.05, 1.122, 0.06, ch=0.014)])
    _add(mesh, g, "dark", "pistol", receiver + fore + brake + _guard(0.08))
    _add(mesh, g, "plate", "pistol", _panels([(-0.066, 0.048), (0.128, 0.048), (0.144, 0.062), (0.26, 0.062), (0.26, 0.089), (-0.05, 0.089),
                                             (-0.066, 0.078)], 0.0275, 0.005)
         + _run([_sec(0.05, 0.044, 0.272, 0.066, ch=0.014), _sec(0.05, 0.044, 0.56, 0.066, ch=0.014), _sec(0.04, 0.036, 0.6, 0.062, ch=0.012)]))
    _add(mesh, g, "glow", "pistol", _panels([(0.138, 0.044), (0.262, 0.044), (0.262, 0.058), (0.152, 0.058)], 0.028, 0.002, 0.0))
    _vent(mesh, g, "dark", _slats(0.3, 7, 0.036, 0.056, 0.078, 0.025, t=0.014, lean=0.008, thick=0.002))
    _add(mesh, g, "accent", "pistol", _panels([(1.044, 0.05), (1.098, 0.05), (1.098, 0.07), (1.044, 0.07)], 0.037, 0.002, 0.0))
    _add(mesh, g, "steel", "pistol", _tube(0.019, 0.26, 1.03, 0.06, 6))
    _add(mesh, g, "detail", "pistol", box(0.014, 0.014, 0.26).rot(pitch=6).move(-0.032, 0.02, -0.66)
         + box(0.014, 0.014, 0.26).rot(pitch=6).move(0.032, 0.02, -0.66) + _rings(0.022, (0.7, 0.86), 0.02, 0.06, 6))
    _add_scope(mesh, g, -0.08, 0.28, 0.14, 0.022, 0.032)
    _stock(mesh, g, -0.28, 0.094, 0.1, -0.04, 0.05)
    _add_cell(mesh, g, 0.038, 0.1, 0.09, 0.0, -0.02, -0.12, 0.6)
    _bolt(mesh, g, -0.092, 0.065, -0.02, 0.016, 0.08)


RAIL_HINGE = (0.098, 0.22)   # (up, forward) of the grip: the top rail's hinge


def railgun(mesh):
    """A railgun, about 1 m: two long armoured rails over lit coils, a power cell that
    clips in behind the grip, and a sleeve that snaps back when it fires."""
    g = "railgun"
    _add(mesh, g, "grip", "pistol", _grip(-14, 0.038))
    body = _core([(-0.076, 0.016), (0.22, 0.016), (0.28, 0.03), (0.28, 0.094), (0.22, 0.1), (-0.05, 0.1), (-0.076, 0.076)], 0.06, 0.008)
    rails = _core([(0.22, 0.016), (0.76, 0.016), (0.79, 0.026), (0.79, 0.036), (0.22, 0.036)], 0.05, 0.004)
    # The top rail is its vent part: a reload flares it open on its hinge at the back (RAIL_HINGE).
    _vent(mesh, g, "dark", _core([(0.22, 0.088), (0.8, 0.088), (0.8, 0.1), (0.76, 0.108), (0.22, 0.108)], 0.05, 0.004))
    _vent(mesh, g, "plate", _panels([(0.3, 0.091), (0.77, 0.091), (0.742, 0.105), (0.3, 0.105)], 0.0245, 0.004))
    sight = _core([(-0.02, 0.098), (0.14, 0.098), (0.14, 0.126), (0.0, 0.131), (-0.02, 0.12)], 0.028, 0.004)
    _add(mesh, g, "dark", "pistol", body + rails + sight + _guard(0.08))
    _add(mesh, g, "plate", "pistol", _panels([(-0.056, 0.05), (0.098, 0.05), (0.114, 0.064), (0.21, 0.064), (0.21, 0.094), (-0.04, 0.094),
                                             (-0.056, 0.08)], 0.0295, 0.005)
         + _panels([(0.3, 0.019), (0.752, 0.019), (0.774, 0.033), (0.3, 0.033)], 0.0245, 0.004))
    _add(mesh, g, "glow", "pistol", _panels([(0.108, 0.046), (0.214, 0.046), (0.214, 0.06), (0.122, 0.06)], 0.03, 0.002, 0.0)
         + _rings(0.026, [0.32 + i * 0.075 for i in range(6)], 0.025, 0.062, 8))
    _add(mesh, g, "detail", "pistol", _slats(-0.03, 4, 0.024, 0.068, 0.09, 0.0345, t=0.008, lean=0.006, thick=0.003))
    _add(mesh, g, "steel", "pistol", _tube(0.012, 0.28, 0.78, 0.062, 6))
    _add(mesh, g, "lens", "pistol", box(0.02, 0.02, 0.003).move(0, 0.113, -0.1405))
    _stock(mesh, g, -0.26, 0.092, 0.086, -0.035, 0.05)
    _add(mesh, g, "detail", "pistol_slide", _tube(0.036, 0.24, 0.30, 0.062, 8))   # the recoil sleeve
    _add(mesh, g, "detail", "pistol_mag", box(0.034, 0.07, 0.07, 0.008).move(0, -0.005, 0.105))
    _add(mesh, g, "glow", "pistol_mag", box(0.037, 0.03, 0.05).move(0, -0.01, 0.105))


CRANK_PIVOT = (0.04, 0.03)   # (up, forward) of the grip: the crank's axle (it runs across the gun)
CRANK_ARM = 0.034            # from the axle to the crank's knob


def crossbow(mesh):
    """A crossbow, about 85 cm: an armoured tiller with a rail on top, bow limbs across the
    front with lit tips and a lit string drawn back to the latch, and a bolt on the rail
    (its magazine)."""
    g = "crossbow"
    _add(mesh, g, "grip", "pistol", _grip(-18))
    tiller = _core([(-0.066, 0.014), (0.1, 0.018), (0.52, 0.034), (0.52, 0.064), (-0.04, 0.064), (-0.066, 0.05)], 0.04, 0.006)
    _add(mesh, g, "dark", "pistol", tiller + _guard(0.078) + box(0.056, 0.034, 0.05, 0.01).move(0, 0.06, -0.52))
    _add(mesh, g, "plate", "pistol", _panels([(0.0, 0.026), (0.1, 0.028), (0.49, 0.04), (0.49, 0.058), (0.0, 0.058)], 0.0195, 0.004))
    limbs = Part([])
    string = Part([])
    for side in (-1.0, 1.0):
        limbs = limbs + box(0.28, 0.016, 0.032, 0.005).rot(yaw=side * 14.0).move(side * 0.15, 0.06, -0.495)
        string = string + box(0.004, 0.004, 0.33).rot(yaw=side * 60.0).move(side * 0.14, 0.072, -0.37)
    _add(mesh, g, "plate", "pistol", limbs)
    _add(mesh, g, "glow", "pistol", string + box(0.022, 0.02, 0.034).move(-0.285, 0.06, -0.46) + box(0.022, 0.02, 0.034).move(0.285, 0.06, -0.46)
         + _panels([(0.12, 0.04), (0.47, 0.05), (0.47, 0.055), (0.12, 0.045)], 0.0238, 0.002, 0.0))
    _add(mesh, g, "steel", "pistol", box(0.016, 0.008, 0.56).move(0, 0.067, -0.26))   # the rail
    vents = Part([])
    for f in (0.502, 0.52, 0.538):
        vents = vents + box(0.042, 0.006, 0.01).move(0, 0.08, -f)
    _add(mesh, g, "detail", "pistol", vents)
    # Its vent part is the cocking crank on the left of the tiller: a reload spins it (about CRANK_PIVOT).
    up, fwd = CRANK_PIVOT
    _vent(mesh, g, "detail", prism(8, 0.013, 0.01).rot(roll=90).move(-0.029, up, -fwd) + box(0.008, 0.01, 0.04).move(-0.036, up, -fwd - 0.017))
    _vent(mesh, g, "accent", box(0.024, 0.014, 0.014, 0.004).move(-0.05, up, -fwd - CRANK_ARM))
    _add_sight(mesh, g, -0.01, 0.066, 0.028, 0.03, 0.05)
    _stock(mesh, g, -0.26, 0.066, 0.076, -0.035, 0.042)
    _add(mesh, g, "steel", "pistol_mag", _tube(0.006, 0.0, 0.5, 0.076, 6))
    _add(mesh, g, "accent", "pistol_mag", prism(4, 0.014, 0.06, r_top=0.0).rot(pitch=-90).move(0, 0.076, -0.53)
         + box(0.002, 0.024, 0.05).move(0, 0.086, -0.03))


# ---------------------------------------------------------------------------
# Heavies

def _round(n, r, back, front, y, r_front=None):
    """A fat tube along the barrel line (a launcher's)."""
    return prism(n, r, front - back, r_top=r_front, phase=0.31).rot(pitch=-90).move(0, y, -(back + front) / 2.0)


def _launcher_handles(mesh, g):
    """What the two shoulder launchers share: the grip and trigger under the tube, and the front handle."""
    _add(mesh, g, "grip", "pistol", box(0.032, 0.11, 0.05, 0.01).rot(pitch=-12).move(0, -0.03, 0.02)
         + box(0.032, 0.09, 0.04, 0.01).move(0, 0.008, -0.24))
    _add(mesh, g, "dark", "pistol", _core([(-0.035, 0.024), (0.075, 0.024), (0.085, 0.066), (-0.045, 0.066)], 0.032, 0.004)
         + _core([(0.21, 0.03), (0.27, 0.03), (0.28, 0.066), (0.2, 0.066)], 0.032, 0.004) + _guard(0.078))


def rocket_launcher(mesh):
    """A shoulder rocket launcher, about 1.05 m: a fat armour tube with a flared back blast
    cone, a lit conduit along each flank, a front handle and a sight box. The rocket
    (magazine bone) goes in at the back."""
    g = "rocket_launcher"
    y = 0.115
    _launcher_handles(mesh, g)
    _add(mesh, g, "plate", "pistol", _round(10, 0.06, -0.18, 0.68, y))
    _add(mesh, g, "dark", "pistol", _round(10, 0.07, 0.61, 0.684, y) + _round(10, 0.078, -0.28, -0.16, y, r_front=0.06)
         + _round(10, 0.064, 0.12, 0.3, y))
    _add(mesh, g, "accent", "pistol", _round(10, 0.0625, 0.38, 0.43, y) + _round(10, 0.0625, -0.03, 0.02, y))
    _add(mesh, g, "glow", "pistol", box(0.008, 0.014, 0.16).move(-0.0625, y, -0.21) + box(0.008, 0.014, 0.16).move(0.0625, y, -0.21))
    _vent(mesh, g, "detail", _round(10, 0.065, -0.14, -0.126, y) + _round(10, 0.065, -0.112, -0.098, y) + _round(10, 0.065, -0.084, -0.07, y))
    _add(mesh, g, "dark", "pistol", box(0.042, 0.052, 0.09, 0.009).move(-0.078, y + 0.02, -0.12))
    _add(mesh, g, "lens", "pistol", box(0.032, 0.036, 0.004).move(-0.078, y + 0.02, -0.166))
    # The rocket: its nose shows in the tube's mouth; a reload brings a new one in from behind.
    _add(mesh, g, "accent", "pistol_mag", prism(8, 0.04, 0.08, r_top=0.005).rot(pitch=-90).move(0, y, -0.72))
    _add(mesh, g, "steel", "pistol_mag", prism(8, 0.04, 0.5).rot(pitch=-90).move(0, y, -0.43))
    _add(mesh, g, "glow", "pistol_mag", prism(8, 0.042, 0.02).rot(pitch=-90).move(0, y, -0.2))


def grenade_launcher(mesh):
    """A revolving grenade launcher, about 75 cm: a fat six-round drum with a lit band
    (magazine bone), a short wide armour barrel, a skeleton stock and a bridge over the drum."""
    g = "grenade_launcher"
    _add(mesh, g, "grip", "pistol", _grip(-18, 0.038))
    shield = _core([(-0.066, 0.012), (0.1, 0.012), (0.1, 0.112), (0.072, 0.15), (0.04, 0.15), (0.0, 0.088), (-0.066, 0.06)], 0.05, 0.006)
    bridge = (_core([(0.04, 0.132), (0.31, 0.132), (0.31, 0.142), (0.29, 0.15), (0.04, 0.15)], 0.024, 0.004)
              + _core([(0.262, 0.098), (0.31, 0.098), (0.31, 0.136), (0.262, 0.136)], 0.024, 0.003))
    guard = _run([_sec(0.052, 0.05, 0.26, 0.03, ch=0.015), _sec(0.052, 0.05, 0.4, 0.03, ch=0.015)])
    _add(mesh, g, "dark", "pistol", shield + bridge + guard + _guard(0.08) + _tube(0.042, 0.474, 0.522, 0.07, 10)
         + _tube(0.012, 0.09, 0.27, 0.07, 6))
    _add(mesh, g, "plate", "pistol", _panels([(-0.042, 0.028), (0.088, 0.028), (0.088, 0.104), (0.064, 0.136), (0.047, 0.136), (0.008, 0.08), (-0.042, 0.056)], 0.0245, 0.004)
         + _tube(0.036, 0.262, 0.478, 0.07, 10))
    _add(mesh, g, "glow", "pistol", _tube(0.028, 0.5195, 0.5235, 0.07, 10))
    _add(mesh, g, "detail", "pistol", _rings(0.039, (0.3, 0.326, 0.352), 0.011, 0.07, 10))
    # Its vent part is one grenade, hidden inside the drum: a reload thumbs it into a chamber.
    _vent(mesh, g, "accent", _tube(0.02, 0.13, 0.19, 0.07, 8))
    _vent(mesh, g, "glow", _tube(0.021, 0.15, 0.162, 0.07, 8))
    _add(mesh, g, "detail", "pistol", box(0.012, 0.016, 0.01).move(0, 0.158, -0.07) + box(0.012, 0.03, 0.01).move(0, 0.12, -0.46))
    _stock(mesh, g, -0.25, 0.072, 0.076, -0.035, 0.04, open_frame=True)
    _add(mesh, g, "steel", "pistol_mag", _tube(0.069, 0.10, 0.26, 0.07, 6))
    _add(mesh, g, "glow", "pistol_mag", _tube(0.071, 0.165, 0.19, 0.07, 6))
    _add(mesh, g, "detail", "pistol_mag", _tube(0.071, 0.236, 0.25, 0.07, 6))
    _add(mesh, g, "detail", "pistol_slide", box(0.03, 0.03, 0.02).move(0, 0.08, 0.03))   # the hammer


BUILD = {"pistol": pistol, "shotgun": shotgun, "rifle": rifle, "revolver": revolver,
         "machine_pistol": machine_pistol, "break_action": break_action, "burst_rifle": burst_rifle,
         "lmg": lmg, "lever_action": lever_action, "railgun": railgun,
         "rocket_launcher": rocket_launcher, "grenade_launcher": grenade_launcher,
         "air_cannon": air_cannon, "minigun": minigun, "battle_rifle": battle_rifle,
         "crossbow": crossbow, "anti_materiel": anti_materiel}
BUILD.update({weapon: dual(weapon) for weapon in DUALS})


def add_all(mesh):
    for gun in IDS:
        BUILD[gun](mesh)
