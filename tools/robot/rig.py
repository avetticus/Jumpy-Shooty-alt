"""Skeleton, pose solving (forward kinematics plus two-bone IK for arms and legs)
and baking of animation clips.

Every bone's rest orientation is the identity, and the rest pose is standing
straight with the arms hanging down. So a bone's rotation reads naturally:
  +X pitch swings a hanging limb forward, +Y yaw turns left, +Z roll tips to the right side up.

A pose is described by a "spec": a plain dict (see solve()). Specs with the same
shape can be blended number by number, which keeps planted feet planted and lets
whole-body spins go past 180 degrees.
"""
import math
import numpy as np
from m3 import v, norm, euler, frame, quat, rx, ry, rz

FPS = 30


class Bone:
    def __init__(self, index, name, parent, pos):
        self.index, self.name, self.parent, self.pos = index, name, parent, np.array(pos, dtype=float)


class Skeleton:
    def __init__(self, spec):
        self.spec = list(spec)
        self.bones = []
        self._by_name = {}
        for name, parent, pos in spec:
            b = Bone(len(self.bones), name, self._by_name[parent].index if parent else -1, pos)
            self.bones.append(b)
            self._by_name[name] = b

    def index(self, name):
        return self._by_name[name].index

    def bone(self, name):
        return self._by_name[name]

    def offset(self, name):
        b = self._by_name[name]
        return b.pos - (self.bones[b.parent].pos if b.parent >= 0 else 0.0)

    def names(self):
        return [b.name for b in self.bones]


FIST = 0.045   # from the wrist to the middle of the fist (where a grip sits)

# The gun is modelled barrel-forward (-Z), sights up; in the rest pose the arm hangs
# down, so the gun hangs barrel-down. This turns gun-space directions into bone space.
GUN_REST = rx(-90)

# The hands. Each has a trigger finger, the other three fingers moving as one, and a
# thumb, of two bones each. Where the knuckles are, from the grip (the middle of the
# fist, where a gun's grip or a blade's handle sits) with the arm hanging at rest: x out
# from the body, y up, z back. The palm is on the outside of the grip, facing in, the
# fingers hang down from it and curl in and round under the grip, and the thumb is at
# the front edge of the palm, pointing forward. The three fingers' knuckle is higher than
# the trigger finger's: a gun's grip slopes back, and the fingers follow it.
GRIP_AT = (0.215, 0.835, 0.0)
FINGER_OUT = 0.027              # the knuckles' line, out from the middle of the grip
INDEX_AT = (FINGER_OUT, -0.024, -0.006)
FINGERS_AT = (FINGER_OUT, -0.011, 0.0455)
THUMB_AT = (0.028, 0.016, -0.03)
FINGER_BONES = (0.055, 0.035)   # a finger's two bones, knuckle to joint and joint to tip: the
#                                 first is long enough to cross the front of a grip, the second lies along its far side
THUMB_BONES = (0.034, 0.028)


def _finger_bones(side):
    s = -1.0 if side == "l" else 1.0

    def at(p, down=0.0, forward=0.0):
        return (s * (GRIP_AT[0] + p[0]), GRIP_AT[1] + p[1] - down, GRIP_AT[2] + p[2] - forward)
    return [
        ("index_" + side, "hand_" + side, at(INDEX_AT)),
        ("index_%s2" % side, "index_" + side, at(INDEX_AT, down=FINGER_BONES[0])),
        ("fingers_" + side, "hand_" + side, at(FINGERS_AT)),
        ("fingers_%s2" % side, "fingers_" + side, at(FINGERS_AT, down=FINGER_BONES[0])),
        ("thumb_" + side, "hand_" + side, at(THUMB_AT)),
        ("thumb_%s2" % side, "thumb_" + side, at(THUMB_AT, forward=THUMB_BONES[0])),
    ]


# How a hand is held: (trigger finger's knuckle, its joint, the three fingers' knuckle,
# their joint, their rake, the thumb's swing down, its swing across the palm, its
# joint), in degrees. A curl of 0 is a finger straight out from the palm, 90 a right
# angle. The rake tips the three fingers' knuckle line to follow a sloping grip. The
# thumb at rest points forward: swung down 90 it lies along the fingers; swung across,
# it closes over them. Poses blend number by number.
HANDS = {
    "open": (4.0, 4.0, 4.0, 4.0, 0.0, 58.0, -14.0, 4.0),
    "flat": (0.0, 0.0, 0.0, 0.0, 0.0, 66.0, -6.0, 0.0),             # a slap
    "relaxed": (26.0, 36.0, 32.0, 42.0, 0.0, 62.0, 14.0, 22.0),    # a free hand
    "fist": (84.0, 100.0, 84.0, 100.0, 0.0, 24.0, 80.0, 32.0),     # the thumb across the front of the fingers
    "gun": (86.0, 88.0, 86.0, 88.0, -14.0, 88.0, 0.0, 6.0),        # round a gun's grip, the thumb along its frame
    "trigger": (86.0, 8.0, 20.0, 16.0, 0.0, 50.0, -12.0, 0.0),     # only the trigger finger through the guard (a spin)
    "handle": (74.0, 106.0, 88.0, 94.0, -26.0, 6.0, 10.0, 10.0),  # round a blade's handle (which leans in the fist), the thumb along it
    "support": (48.0, 74.0, 48.0, 74.0, 0.0, 40.0, 30.0, 26.0),    # under or round a long gun's fore-end
    "wrap": (84.0, 72.0, 84.0, 72.0, -14.0, 100.0, 20.0, 6.0),      # round the right hand on a pistol's grip
    "foregrip": (84.0, 90.0, 84.0, 90.0, 0.0, 34.0, 62.0, 30.0),   # round an upright handle under a gun
    "pinch": (40.0, 52.0, 44.0, 56.0, 0.0, 44.0, 50.0, 30.0),      # something small held between thumb and fingers
}


BODY = Skeleton([
    ("root", None, (0, 0, 0)),
    ("hips", "root", (0, 0.96, 0)),
    ("spine", "hips", (0, 1.06, 0)),
    ("chest", "spine", (0, 1.22, 0)),
    ("head", "chest", (0, 1.50, 0)),
    ("upper_arm_l", "chest", (-0.215, 1.40, 0)),
    ("forearm_l", "upper_arm_l", (-0.215, 1.13, 0)),
    ("hand_l", "forearm_l", (-0.215, 0.88, 0)),
    *_finger_bones("l"),
    ("grapple", "forearm_l", (-0.285, 0.90, 0)),      # where the grapple rope leaves the left wrist
    # The second pistol of the akimbo pair, in the left fist (the same three gun bones, mirrored).
    ("pistol_l", "hand_l", (-0.215, 0.835, 0)),
    ("pistol_l_slide", "pistol_l", (-0.215, 0.835, 0)),
    ("pistol_l_mag", "pistol_l", (-0.215, 0.835, 0)),
    ("pistol_l_vent", "pistol_l", (-0.215, 0.835, 0)),
    ("muzzle_akimbo_l", "pistol_l", (-0.215, 0.835 - 0.20, -0.064)),
    ("upper_arm_r", "chest", (0.215, 1.40, 0)),
    ("forearm_r", "upper_arm_r", (0.215, 1.13, 0)),
    ("hand_r", "forearm_r", (0.215, 0.88, 0)),
    *_finger_bones("r"),
    ("pistol", "hand_r", (0.215, 0.835, 0)),          # the grip, in the fist
    ("pistol_slide", "pistol", (0.215, 0.835, 0)),
    ("pistol_mag", "pistol", (0.215, 0.835, 0)),
    ("pistol_vent", "pistol", (0.215, 0.835, 0)),     # the gun's vents: a reload snaps them open
    ("muzzle", "pistol", (0.215, 0.835 - 0.20, -0.064)),  # where shots leave the barrel
    # The other guns' muzzles (in gun space: forward, up), added below.
    ("thigh_l", "hips", (-0.10, 0.90, 0)),
    ("shin_l", "thigh_l", (-0.10, 0.50, 0)),
    ("foot_l", "shin_l", (-0.10, 0.10, 0)),
    ("thigh_r", "hips", (0.10, 0.90, 0)),
    ("shin_r", "thigh_r", (0.10, 0.50, 0)),
    ("foot_r", "shin_r", (0.10, 0.10, 0)),
])

# Where each long gun's shots leave its barrel, in gun space (x, up, back). The pistol's is "muzzle".
MUZZLES = {"shotgun": (0.0, 0.070, -0.60), "rifle": (0.0, 0.052, -0.565), "sniper": (0.0, 0.058, -0.86),
           "revolver": (0.0, 0.066, -0.285), "machine_pistol": (0.0, 0.064, -0.235),
           "break_action": (0.0, 0.066, -0.66), "smg": (0.0, 0.052, -0.47), "burst_rifle": (0.0, 0.056, -0.62),
           "lmg": (0.0, 0.060, -0.80), "lever_action": (0.0, 0.066, -0.78), "bolt_action": (0.0, 0.060, -0.80),
           "railgun": (0.0, 0.062, -0.80), "rocket_launcher": (0.0, 0.115, -0.70),
           "grenade_launcher": (0.0, 0.070, -0.52), "akimbo": (0.0, 0.064, -0.20),
           # The third batch
           "derringer": (0.0, 0.076, -0.135), "air_cannon": (0.0, 0.075, -0.62),
           "minigun": (0.0, 0.050, -0.86), "battle_rifle": (0.0, 0.056, -0.72), "laser_rifle": (0.0, 0.060, -0.665),
           "nail_gun": (0.0, 0.050, -0.50), "crossbow": (0.0, 0.076, -0.56), "anti_materiel": (0.0, 0.060, -1.12),
           "plasma_cannon": (0.0, 0.070, -0.62)}


def _with_muzzles(skel_spec):
    grip = np.array((0.215, 0.835, 0.0))
    out = list(skel_spec)
    at = [n for n, _, _ in out].index("muzzle") + 1
    for weapon, p in MUZZLES.items():
        pos = grip + GUN_REST @ np.array(p)
        out.insert(at, ("muzzle_" + weapon, "pistol", tuple(float(x) for x in pos)))
        at += 1
    return out


BODY = Skeleton(_with_muzzles(BODY.spec))

MOVING_BONES = ("root", "hips", "pistol", "pistol_slide", "pistol_mag", "pistol_vent",
                "pistol_l", "pistol_l_slide", "pistol_l_mag", "pistol_l_vent")  # bones whose position is animated

ZERO = (0.0, 0.0, 0.0)
OVERREACH = []   # how far beyond reach each over-stretched limb was asked to go (for checking new poses)


def _two_bone(S, T, l1, l2, pole, knee):
    """Returns (upper R, lower R, end position). pole: where the elbow/knee points."""
    d = T - S
    dist = np.linalg.norm(d)
    reach = (l1 + l2) * 0.999
    if dist > reach * 1.02:
        OVERREACH.append(dist / reach)
    if dist > reach:
        d = d / dist * reach
        dist = reach
    if dist < 1e-4:
        d, dist = v(0, -1e-4, 0), 1e-4
    dirn = d / dist
    perp = pole - dirn * np.dot(pole, dirn)
    if np.linalg.norm(perp) < 1e-5:
        alt = v(0, 0, 1) if abs(dirn[2]) < 0.9 else v(1, 0, 0)
        perp = alt - dirn * np.dot(alt, dirn)
    perp = norm(perp)
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    E = S + dirn * a + perp * h
    d1 = norm(E - S)
    d2 = norm(S + d - E)
    z = -perp if knee else perp
    Ru = frame(y=-d1, z=z)
    Rl = frame(x=Ru[:, 0], y=-d2)
    return Ru, Rl, S + d


def solve(skel, spec):
    """Turns a pose spec into local bone rotations and positions.

    spec keys (all optional; anything left out stays at rest):
      root:  {pos, rot}                       model-space placement of the whole body
      hips:  {pos, rot}                       pos is absolute, in model space
      spine, chest, head: (pitch, yaw, roll)
      arm_l, arm_r:  {fk: euler, bend: deg, hand: euler}
                  or {ik: wrist target, space: model|chest|hips, pole: dir, hand: euler in that space (optional),
                      cant: roll about the fingers (tilts a held gun), hand_local: euler}
      leg_l, leg_r:  {fk: euler, bend: deg, foot: euler}
                  or {ik: ankle target, space: model|hips, pole: dir, foot: euler in model space}
      fingers_l, fingers_r: how the hand is held: hand("open"), hand("fist")... (see HANDS)
      pistol: {pos, rot}   offset and rotation in the hand, in gun space (barrel -Z, up +Y)
      slide: float         slide travel backwards, metres
      mag:   (x, y, z)     magazine offset in gun space ("mag_rot": its turn, euler)
      vent_roll: float     the vent part turned about the barrel's line instead (a minigun's barrels), through "vent_pivot"
      vent:  float         how far the gun's vents are open, degrees, hinged about a sideways line
                           through "vent_pivot": (up, forward) of the grip; "vent_pos": (x, y, z)
                           slides them instead (or as well), in gun space
    Returns (rotations {bone: 3x3}, positions {bone: local xyz}).
    """
    if "_blend" in spec:
        a, b, u = spec["_blend"]
        ra, pa = solve(skel, a)
        rb, pb = solve(skel, b)
        rot = {k: _slerp_m(ra[k], rb[k], u) for k in ra}
        pos = {k: pa[k] * (1 - u) + pb[k] * u for k in pa}
        return rot, pos

    G = {}   # global rotation per bone
    Pg = {}  # global position per bone
    L = {}   # local rotation
    T = {}   # local translation

    def place(name, local_rot, local_pos=None):
        b = skel.bone(name)
        t = skel.offset(name) if local_pos is None else np.array(local_pos, dtype=float)
        if b.parent < 0:
            G[name] = local_rot
            Pg[name] = t
        else:
            pn = skel.bones[b.parent].name
            G[name] = G[pn] @ local_rot
            Pg[name] = Pg[pn] + G[pn] @ t
        L[name] = local_rot
        T[name] = t

    def place_global(name, global_rot):
        b = skel.bone(name)
        pn = skel.bones[b.parent].name
        place(name, G[pn].T @ global_rot)

    root = spec.get("root", {})
    place("root", euler(root.get("rot", ZERO)), root.get("pos", ZERO))
    hips = spec.get("hips", {})
    hips_pos = np.array(hips.get("pos", skel.bone("hips").pos), dtype=float)
    place("hips", euler(hips.get("rot", ZERO)), G["root"].T @ (hips_pos - Pg["root"]))
    place("spine", euler(spec.get("spine", ZERO)))
    place("chest", euler(spec.get("chest", ZERO)))
    place("head", euler(spec.get("head", ZERO)))

    def space(name):
        if name == "model":
            return G["root"], Pg["root"]
        return G[name], Pg[name]

    for side in ("l", "r"):
        leg = spec.get("leg_" + side, {})
        th, sh, ft = "thigh_" + side, "shin_" + side, "foot_" + side
        if "ik" in leg:
            R, O = space(leg.get("space", "model"))
            target = O + R @ np.array(leg["ik"], dtype=float)
            pole = R @ np.array(leg.get("pole", (0.0, 0.0, -1.0)), dtype=float)
            S = Pg["hips"] + G["hips"] @ skel.offset(th)
            l1 = np.linalg.norm(skel.offset(sh))
            l2 = np.linalg.norm(skel.offset(ft))
            Ru, Rl, _ = _two_bone(S, target, l1, l2, pole, knee=True)
            place_global(th, Ru)
            place_global(sh, Rl)
            place_global(ft, R @ euler(leg.get("foot", ZERO)))
        else:
            place(th, euler(leg.get("fk", ZERO)))
            place(sh, rx(-leg.get("bend", 0.0)))
            place(ft, euler(leg.get("foot", ZERO)))

    # The right arm (which holds the gun) first, then the gun, then the left arm, which
    # can hold on to a point on the gun ("grip").
    for side in ("r", "l"):
        arm = spec.get("arm_" + side, {})
        up, fo, ha = "upper_arm_" + side, "forearm_" + side, "hand_" + side
        S = Pg["chest"] + G["chest"] @ skel.offset(up)
        l1 = np.linalg.norm(skel.offset(fo))
        l2 = np.linalg.norm(skel.offset(ha))
        if "grip" in arm and "pistol" in G:
            # Hold a point on the gun (gun space; on the gun's frame, or riding on its
            # slide / pump with "on": "pistol_slide"). The fist closes on that point.
            on = arm.get("on", "pistol")
            contact = Pg[on] + G[on] @ GUN_REST @ np.array(arm["grip"], dtype=float)
            if "hand" in arm:   # the fist's turn, relative to the right fist on the grip
                hand_rot = G["pistol"] @ euler(arm["hand"])
                target = contact - hand_rot @ v(0.0, -FIST, 0.0)
            else:               # in line with the forearm
                hand_rot = None
                target = contact - norm(contact - S) * FIST
            pole = G["chest"] @ np.array(arm.get("pole", (-0.6, -1.0, 0.2)), dtype=float)
            Ru, Rl, _ = _two_bone(S, target, l1, l2, pole, knee=False)
            place_global(up, Ru)
            place_global(fo, Rl)
            if hand_rot is not None:
                place_global(ha, hand_rot)
            else:
                place(ha, euler(arm.get("hand_local", ZERO)))
        elif "ik" in arm:
            R, O = space(arm.get("space", "model"))
            target = O + R @ np.array(arm["ik"], dtype=float)
            pole = R @ np.array(arm.get("pole", (0.3 if side == "r" else -0.3, -1.0, 0.6)), dtype=float)
            Ru, Rl, _ = _two_bone(S, target, l1, l2, pole, knee=False)
            place_global(up, Ru)
            place_global(fo, Rl)
            if "hand" in arm:
                place_global(ha, R @ euler(arm["hand"]) @ ry(arm.get("cant", 0.0)))
            else:
                place(ha, euler(arm.get("hand_local", ZERO)))
        else:
            place(up, euler(arm.get("fk", ZERO)))
            place(fo, rx(arm.get("bend", 0.0)))
            place(ha, euler(arm.get("hand", ZERO)))
        _place_fingers(spec, place, side, arm)
        if side == "r" and "pistol" in skel._by_name:
            _place_gun(skel, spec, place)
        if side == "l" and "pistol_l" in skel._by_name:
            _place_left_gun(skel, spec, place)

    for b in skel.bones:   # marker bones (muzzle, grapple) just ride along
        if b.name not in L:
            place(b.name, np.eye(3))
    return L, T


def _place_fingers(spec, place, side, arm):
    """The fingers and thumb of one hand: "fingers_l" / "fingers_r" in the pose (a name in
    HANDS or its eight numbers), or "fingers" in the arm's own pose. Left out: the right
    hand is round a gun's grip, the left under a long gun if it holds one ("grip" in its
    arm) and relaxed if not."""
    how = spec.get("fingers_" + side, arm.get("fingers"))
    if how is None:
        how = "gun" if side == "r" else ("support" if "grip" in arm else "relaxed")
    index1, index2, mitt1, mitt2, rake, down, across, joint = HANDS[how] if isinstance(how, str) else how
    s = -1.0 if side == "l" else 1.0   # the left hand is the right's mirror image
    place("index_" + side, rz(-s * index1))
    place("index_%s2" % side, rz(-s * index2))
    place("fingers_" + side, rx(rake) @ rz(-s * mitt1))
    place("fingers_%s2" % side, rz(-s * mitt2))
    place("thumb_" + side, rx(-down) @ ry(s * across))
    place("thumb_%s2" % side, ry(s * joint))


def hand(how):
    """A hand pose's numbers, for a pose's "fingers_l" / "fingers_r" (so that it blends
    with another by number)."""
    return HANDS[how]


def _place_gun(skel, spec, place):
    """The gun in the right fist, its slide (or pump, or bolt) and its magazine (or shell).
    All three are modelled around the grip, in gun space (barrel -Z, sights +Y)."""
    gun = spec.get("pistol", {})
    place("pistol", GUN_REST @ euler(gun.get("rot", ZERO)) @ GUN_REST.T,
          skel.offset("pistol") + GUN_REST @ np.array(gun.get("pos", ZERO), dtype=float))
    # The slide moves back along the barrel; a bolt can also turn about the bore ("slide_turn",
    # degrees, about a line "slide_axis" metres above the grip).
    # A lever (or a top cover) swings about a sideways line instead ("slide_pitch", degrees,
    # about the point "slide_pivot": (up, forward) of the grip).
    turn = rz(spec.get("slide_turn", 0.0)) @ rx(spec.get("slide_pitch", 0.0))
    if "slide_pivot" in spec:
        axis = v(0.0, spec["slide_pivot"][0], -spec["slide_pivot"][1])
    else:
        axis = v(0.0, spec.get("slide_axis", 0.0), 0.0)
    place("pistol_slide", GUN_REST @ turn @ GUN_REST.T, GUN_REST @ (v(0, 0, spec.get("slide", 0.0)) + axis - turn @ axis))
    place("pistol_mag", GUN_REST @ euler(spec.get("mag_rot", ZERO)) @ GUN_REST.T,
          GUN_REST @ np.array(spec.get("mag", ZERO), dtype=float))
    _place_vent(spec, place, "pistol_vent", "")


def _place_vent(spec, place, bone, side):
    """A gun's vents ("vent", "vent_pivot", "vent_pos"; the left gun's: "vent_l"...)."""
    turn = rx(spec.get("vent" + side, 0.0)) @ rz(spec.get("vent_roll" + side, 0.0))
    pivot = spec.get("vent_pivot" + side, (0.0, 0.0))
    axis = v(0.0, pivot[0], -pivot[1])
    place(bone, GUN_REST @ turn @ GUN_REST.T,
          GUN_REST @ (np.array(spec.get("vent_pos" + side, ZERO), dtype=float) + axis - turn @ axis))


def _place_left_gun(skel, spec, place):
    """The akimbo pair's second pistol, in the left fist: "pistol_l" {pos, rot} in the
    hand (gun space), "slide_l" (slide travel back, metres) and "mag_l" (magazine offset)."""
    gun = spec.get("pistol_l", {})
    place("pistol_l", GUN_REST @ euler(gun.get("rot", ZERO)) @ GUN_REST.T,
          skel.offset("pistol_l") + GUN_REST @ np.array(gun.get("pos", ZERO), dtype=float))
    place("pistol_l_slide", np.eye(3), GUN_REST @ v(0, 0, spec.get("slide_l", 0.0)))
    place("pistol_l_mag", GUN_REST @ euler(spec.get("mag_rot_l", ZERO)) @ GUN_REST.T,
          GUN_REST @ np.array(spec.get("mag_l", ZERO), dtype=float))
    _place_vent(spec, place, "pistol_l_vent", "_l")


def _slerp_m(a, b, u):
    qa, qb = quat(a), quat(b)
    return _quat_to_m(_slerp_q(qa, qb, u))


def _slerp_q(qa, qb, u):
    d = float(np.dot(qa, qb))
    if d < 0:
        qb, d = -qb, -d
    if d > 0.9995:
        q = qa + (qb - qa) * u
        return q / np.linalg.norm(q)
    th = math.acos(d)
    return (qa * math.sin((1 - u) * th) + qb * math.sin(u * th)) / math.sin(th)


def _quat_to_m(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


# ---------------------------------------------------------------------------
# Blending specs

def _same_shape(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(_same_shape(a[k], b[k]) for k in a)
    if isinstance(a, str) or isinstance(b, str):
        return a == b
    if isinstance(a, (tuple, list)) and isinstance(b, (tuple, list)):
        return len(a) == len(b)
    return isinstance(a, (int, float)) and isinstance(b, (int, float))


def _mix(a, b, u):
    if isinstance(a, dict):
        return {k: _mix(a[k], b[k], u) for k in a}
    if isinstance(a, str):
        return a
    if isinstance(a, (tuple, list)):
        return tuple(x * (1 - u) + y * u for x, y in zip(a, b))
    return a * (1 - u) + b * u


def mix(a, b, u):
    """Blend two specs. Number by number when they have the same shape, otherwise
    by blending the solved poses."""
    if u <= 0:
        return a
    if u >= 1:
        return b
    keys = set(a) | set(b)
    if "_blend" not in keys and all(k in a and k in b and _same_shape(a[k], b[k]) for k in keys):
        return _mix(a, b, u)
    return {"_blend": (a, b, u)}


def ease(u, kind="smooth"):
    u = min(max(u, 0.0), 1.0)
    if kind == "linear":
        return u
    if kind == "in":
        return u * u
    if kind == "out":
        return 1 - (1 - u) * (1 - u)
    return u * u * (3 - 2 * u)


def keyed(t, keys):
    """keys: [(time, spec), ...] or [(time, spec, ease), ...] where ease shapes the
    move INTO that key. Returns the spec at time t."""
    if t <= keys[0][0]:
        return keys[0][1]
    for i in range(1, len(keys)):
        if t <= keys[i][0]:
            t0, t1 = keys[i - 1][0], keys[i][0]
            kind = keys[i][2] if len(keys[i]) > 2 else "smooth"
            return mix(keys[i - 1][1], keys[i][1], ease((t - t0) / (t1 - t0), kind))
    return keys[-1][1]


def mirror(spec):
    """Left-right mirror image of a pose (the gun stays in the right hand's bone)."""
    def flip_euler(e):
        return (e[0], -e[1], -e[2])

    def flip_pos(p):
        return (-p[0], p[1], p[2])

    out = {}
    for k, val in spec.items():
        if k in ("spine", "chest", "head"):
            out[k] = flip_euler(val)
        elif k in ("hips", "root"):
            out[k] = {kk: (flip_pos(vv) if kk == "pos" else flip_euler(vv)) for kk, vv in val.items()}
        elif k[:4] in ("arm_", "leg_"):
            other = k[:4] + ("r" if k.endswith("l") else "l")
            limb = {}
            for kk, vv in val.items():
                if kk in ("ik", "pole"):
                    limb[kk] = flip_pos(vv)
                elif kk in ("fk", "hand", "hand_local", "foot"):
                    limb[kk] = flip_euler(vv)
                elif kk == "cant":
                    limb[kk] = -vv
                else:
                    limb[kk] = vv
            out[other] = limb
        else:
            out[k] = val
    return out


def merged(base, **over):
    out = dict(base)
    out.update(over)
    return out


# ---------------------------------------------------------------------------
# Clips

class Clip:
    def __init__(self, name, duration, fn, loop=False, fps=FPS, lean=False):
        """fps: frames a second it is baked at (more, for a clip with a part that turns fast:
        between frames a bone's place goes in a straight line, so a part spun about a point
        that is not its bone's own wobbles if the frames are far apart).
        lean: leave out every bone the clip never moves from its rest (the game reads a
        bone a clip does not hold as at rest: RobotRig.sample), which keeps a long clip small."""
        self.name, self.duration, self.fn, self.loop, self.fps, self.lean = name, duration, fn, loop, fps, lean
        self.times = []
        self.rotations = {}
        self.positions = {}

    def bake(self, skel):
        n = max(int(round(self.duration * self.fps)), 1)
        self.times = [i / self.fps for i in range(n + 1)]
        self.times[-1] = self.duration
        rots = {b: [] for b in skel.names()}
        poss = {b: [] for b in MOVING_BONES if b in skel._by_name}
        for i, t in enumerate(self.times):
            tt = 0.0 if (self.loop and i == n) else t
            L, T = solve(skel, self.fn(tt))
            for b in rots:
                q = quat(L[b])
                if rots[b] and np.dot(rots[b][-1], q) < 0:
                    q = -q
                rots[b].append(q)
            for b in poss:
                poss[b].append(T[b])
        self.rotations = {b: np.array(q, dtype=np.float32) for b, q in rots.items()}
        self.positions = {b: np.array(p, dtype=np.float32) for b, p in poss.items()}
        if self.lean:
            still = np.array([0.0, 0.0, 0.0, 1.0], dtype=np.float32)
            self.rotations = {b: q for b, q in self.rotations.items() if np.abs(np.abs(q) - still).max() > 1e-5}
            self.positions = {b: p for b, p in self.positions.items() if np.abs(p - skel.offset(b)).max() > 1e-5}
        return self
