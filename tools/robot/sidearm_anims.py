"""The sidearms' reloads (the pistol's own is in animations.py: these are built the same
way, from the same rest poses). Each is a function of time giving the pose: the arms
and fingers, the gun's moving parts, and whatever the left hand brings to the gun.

    Machine Pistol   the cell drops out, a new one is driven up into the grip on the palm,
                     a quick spin backwards round the trigger finger
    Revolver         the cylinder flicked out, the empties dumped, a speed loader pushed
                     in, the cylinder flicked shut and one big slow spin forward
    Derringer        the barrels tip open and throw their empties, two rounds flipped in
                     off the thumb, snapped shut with a flick of the wrist
    Dual Pistols     both cells flicked out sideways and the vents dropped open, the arms
    ("akimbo")       cross (the left gun dipping under the right) to push the guns down on
                     new cells, then uncross with both guns spinning together

The game's side of each (what flies out, the glow and steam) is timed to these
keys in game/combat/reload_fx.gd, and the sounds in game/audio/sfx_list.gd.
"""
import numpy as np
from m3 import norm, rx, rz, v
from rig import FIST, GUN_REST, ZERO, _slerp_m, ease, keyed, merged
import animations as A
from weapons import DERRINGER_HINGE

at, hand_at, moved, euler_of = A._at, A._hand_at, A._moved, A._euler_of
PALM_L = A.PALM_L
SPIN_PIVOT = v(*A.PISTOL_SPIN_PIVOT)   # the trigger finger in the guard: a spun gun turns about it


class View:
    """One view's (first or third person's) rest poses, and the places the left hand goes."""

    def __init__(self, fp):
        self.fp = fp
        self.rest_r = moved(A.FP_R if fp else A.AIM_R, ZERO)
        self.rest_l = moved(A.FP_L if fp else A.AIM_L, ZERO)
        self.cant = self.rest_r["cant"]
        self.space = self.rest_r["space"]
        self.body = A.FP_BODY if fp else {}
        # Where the gun is worked on: up and in toward the middle of the view, or up in front of the chest.
        self.work = v(-0.05, 0.09, 0.01) if fp else v(0.02, 0.05, 0.04)
        if fp:
            left = {"hip": A.fp_arm_l(-0.02, -0.52, -0.16, hand=(40.0, 0.0, 0.0)),
                    "lift": A.fp_arm_l(-0.03, -0.37, -0.33, hand=(64.0, -30.0, 0.0)),
                    "clear": A.fp_arm_l(-0.07, -0.32, -0.29, hand=(80.0, -30.0, 0.0)),
                    "out": A.fp_arm_l(-0.15, -0.27, -0.36, hand=(96.0, -8.0, 0.0))}
            left = {k: A.in_view(a) for k, a in left.items()}
        else:
            left = {"hip": A._arm("l", (-0.21, -0.30, -0.05), (30.0, 0.0, 0.0)),
                    "lift": A._arm("l", (-0.11, -0.08, -0.26), (64.0, -30.0, 0.0)),
                    "clear": A._arm("l", (-0.14, -0.04, -0.23), (80.0, -30.0, 0.0)),
                    "out": A._arm("l", (-0.24, 0.02, -0.26), (96.0, -8.0, 0.0))}
        self.hip, self.lift, self.clear, self.out = [moved(left[k], ZERO) for k in ("hip", "lift", "clear", "out")]

    def right(self, by=ZERO, hand=None, cant=None, work=1.0):
        """The right arm, the gun moved `by` from where it is worked on (work=0: from rest)."""
        return moved(self.rest_r, tuple(self.work * work + v(*by)), hand, cant)

    def spec(self, arm_r, arm_l, **more):
        out = dict(self.body, arm_r=arm_r, arm_l=arm_l)
        out.update(more)
        return out

    def frames(self, arm_r, arm_l=None, **more):
        return A._frames(self.spec(arm_r, arm_l or self.rest_l, **more), self.space)

    def gun(self, arm_r, **more):
        """The gun for that right arm: (gun space -> the arms' space, where its grip is)."""
        turn, place = self.frames(arm_r, **more)["gun"]
        return turn @ GUN_REST, place

    def _arm(self, wrist, turn, pole=None):
        return {"ik": tuple(float(x) for x in wrist), "space": self.space, "pole": pole or self.rest_l["pole"],
                "hand": euler_of(turn), "cant": 0.0}

    def fist_on(self, arm_r, point, palm=(1.0, 0.0, 0.0), wrist=(0.0, 0.0, 1.0), **more):
        """The left arm with its fist at `point` on the gun (gun space: x right, y up, z back).
        palm: the way the palm faces; wrist: the way from the fist back to the wrist (both
        gun-space directions; the fingers point the other way from the wrist)."""
        aim, grip = self.gun(arm_r, **more)
        y = norm(v(*wrist))
        x = v(*palm)
        x = norm(x - y * float(np.dot(x, y)))
        turn = aim @ np.column_stack([x, y, np.cross(x, y)])
        return self._arm(grip + aim @ v(*point) + turn @ v(0.0, FIST, 0.0), turn)

    def palm_on(self, arm_r, point, into, along=(0.0, 0.25, -1.0), off=0.0, **more):
        """The left arm with the flat of its palm on `point` of the gun, facing `into`, the
        fingers lying `along` the gun (gun-space directions), held `off` metres back from it."""
        aim, grip = self.gun(arm_r, **more)
        x = aim @ norm(v(*into))
        f = aim @ v(*along)
        f = norm(f - x * float(np.dot(f, x)))
        turn = np.column_stack([x, -f, np.cross(x, -f)])
        return self._arm(grip + aim @ v(*point) - x * off - turn @ PALM_L, turn)


def _spin(spec, turn, key="pistol", pivot=SPIN_PIVOT):
    """Turns the gun in the hand by `turn` degrees about the trigger finger."""
    if turn % 360.0 != 0.0:
        spec[key] = {"pos": tuple(pivot - rx(turn) @ pivot), "rot": (turn, 0.0, 0.0)}


def _hinged(turn, pivot):
    """The magazine-bone part turned `turn` degrees (pitch) about the sideways line through
    `pivot` ((up, forward) of the grip): {"mag_rot", "mag"}."""
    p = v(0.0, pivot[0], -pivot[1])
    return {"mag_rot": (turn, 0.0, 0.0), "mag": tuple(p - rx(turn) @ p)}


def _put(spec, aim, grip, middle, turn, own):
    """Sets the magazine-bone part (whose own middle, seated, is `own` in gun space) with its
    middle at `middle` (the arms' space), turned `turn` (in gun space)."""
    spec["mag_rot"] = euler_of(turn)
    spec["mag"] = tuple(aim.T @ (middle - grip) - turn @ own)


def _on_palm(frames, aim, out, half):
    """A cell standing in the left palm, its base on the palm: (its middle, its turn in gun
    space). out: the way out of the gun for it, seated (gun space); half: half its length."""
    turn_h, wrist = frames["hand_l"]
    n = turn_h @ v(1.0, 0.0, 0.0)
    side = turn_h @ v(0.0, 0.0, 1.0)
    world = np.column_stack([side, n, np.cross(side, n)])
    up = -norm(out)
    x = v(1.0, 0.0, 0.0)
    own = np.column_stack([x, up, np.cross(x, up)])
    return wrist + turn_h @ PALM_L + n * (half + 0.004), aim.T @ world @ own.T


def _flight(u, from_middle, from_turn, to_middle, to_turn, rise, flips):
    """Something tossed from the hand to its place: (middle, turn) `u` of the way there,
    rising `rise` metres on the way and turning over `flips` times."""
    middle = from_middle + (to_middle - from_middle) * ease(u, "in") + v(0.0, rise, 0.0) * 6.4 * u * (1.0 - u) * (1.0 - u)
    turn = _slerp_m(from_turn, to_turn, ease(min(u / 0.7, 1.0))) @ rx(-360.0 * flips * min(u / 0.85, 1.0))
    return middle, turn


def _body(spec, t, keys_yaw, keys_pitch=None, keys_roll=None, part=0.45):
    """Third person: the chest (and a part of it in the spine) goes with the reload."""
    yaw = at(t, keys_yaw)
    pitch = at(t, keys_pitch) if keys_pitch else 0.0
    roll = at(t, keys_roll) if keys_roll else 0.0
    spec["chest"] = (pitch, yaw, roll)
    spec["spine"] = (0.0, yaw * part, 0.0)


# ---------------------------------------------------------------------------
# Machine pistol (1.4 s)

MP_CELL = v(0.0, -0.08, 0.012)            # the middle of the cell seated in the grip (gun space)
MP_OUT = norm(v(0.0, -0.978, 0.208))      # the way out of the grip
MP_HALF = 0.107


def machine_pistol(fp):
    V = View(fp)
    rest = V.rest_r
    dip = V.right((0.004, -0.012, 0.0), cant=V.cant + 6.0, work=0.0)
    drop = V.right((0.0, 0.02, 0.0), (126.0, 8.0, 0.0), -14.0)      # muzzle up with a jerk: the cell falls out of the grip
    hold = V.right((0.0, -0.01, 0.01), (116.0, 10.0, 0.0), -24.0)   # tipped a little outward, waiting
    ready = V.right((0.0, 0.0, 0.01), (119.0, 11.0, 0.0), -27.0)
    knock = V.right((0.0, 0.045, 0.005), (110.0, 8.0, 0.0), -16.0)  # the new cell driven home knocks the gun up
    spin = V.right((0.0, 0.03, -0.02), (93.0, 5.0, 0.0), 2.0)
    top = V.right((0.0, 0.045, -0.02), (97.0, 5.0, 0.0), 2.0)
    catch = V.right((0.0, -0.022, 0.0), (85.0, 4.0, 0.0), V.cant, work=0.0)
    over = V.right((0.0, 0.007, 0.0), work=0.0)
    keys_r = [(0.0, rest), (0.04, dip), (0.11, drop, "out"), (0.24, hold), (0.56, ready), (0.655, ready), (0.70, knock, "out"),
              (0.79, spin), (0.91, top), (1.03, spin), (1.10, catch, "in"), (1.18, over, "out"), (1.26, rest), (1.40, rest)]
    base = MP_CELL + MP_OUT * (MP_HALF + 0.004)   # the base of the seated cell

    def under(off):
        return V.palm_on(ready, base, -MP_OUT, off=off)
    keys_l = [(0.0, V.rest_l), (0.06, V.rest_l), (0.28, V.hip, "in"), (0.42, V.lift), (0.55, under(0.19)), (0.655, under(0.0), "in"),
              (0.72, under(0.05), "out"), (0.86, V.clear), (1.0, moved(V.clear, (-0.02, -0.03, 0.02))), (1.12, V.clear),
              (1.30, V.rest_l), (1.40, V.rest_l)]

    def pose(t):
        arm_r = keyed(t, keys_r)
        spec = V.spec(arm_r, keyed(t, keys_l))
        spec["fingers_r"] = hand_at(t, [(0.0, "gun"), (0.72, "gun"), (0.80, "trigger", "out"), (1.0, "trigger"), (1.09, "gun", "in")])
        spec["fingers_l"] = hand_at(t, [(0.0, "wrap"), (0.06, "wrap"), (0.2, "relaxed"), (0.3, "support"), (0.6, "support"),
                                        (0.655, "flat"), (0.72, "flat"), (0.84, "relaxed"), (1.14, "relaxed"), (1.30, "wrap")])
        open_ = at(t, [(0.0, 0.0), (0.07, 0.0), (0.11, 1.2, "out"), (0.17, 1.0), (0.69, 1.0), (0.74, 0.0, "in")])
        spec["vent_pos"] = (0.0, -0.007 * open_, 0.009 * open_)
        spec["slide"] = at(t, [(0.0, 0.0), (0.07, 0.0), (0.10, 0.04, "out"), (1.10, 0.04), (1.15, 0.0, "in")])
        _spin(spec, at(t, [(0.0, 0.0), (0.77, 0.0), (0.83, 60.0, "in"), (0.99, 300.0, "linear"), (1.07, 360.0, "out"), (1.4, 360.0)]))
        if not fp:
            _body(spec, t, [(0.0, 0.0), (0.12, 5.0, "out"), (0.5, 2.0), (0.67, -9.0, "in"), (0.9, -3.0), (1.2, 0.0)],
                  [(0.0, 0.0), (0.12, -4.0, "out"), (0.6, -2.0), (0.9, -4.0), (1.2, 0.0)])
        if 0.07 <= t < 0.14:     # out, straight down the grip (the game's own falling cell takes over from here)
            spec["mag"] = tuple(MP_OUT * at(t, [(0.07, 0.0), (0.14, 0.22, "linear")]))
        elif 0.14 <= t < 0.655:  # the new one, standing in the left palm
            frames = A._frames(spec, V.space)
            aim = frames["gun"][0] @ GUN_REST
            middle, turn = _on_palm(frames, aim, MP_OUT, MP_HALF)
            _put(spec, aim, frames["gun"][1], middle, turn, MP_CELL)
        return spec
    return pose


# ---------------------------------------------------------------------------
# Revolver (2.0 s; the Golden Gun's too)

CYLINDER_HINGE = (-0.02, 0.02)        # the crane: the cylinder swings out to the left about it (x, up)
CYLINDER_OPEN = v(-0.042, 0.044, 0.0)  # the middle of the open cylinder, across the gun


def _swung(roll):
    p = v(CYLINDER_HINGE[0], CYLINDER_HINGE[1], 0.0)
    return {"mag_rot": (0.0, 0.0, roll), "mag": tuple(p - rz(roll) @ p)}


def revolver(fp):
    V = View(fp)
    rest = V.rest_r
    dip = V.right((-0.006, -0.008, 0.0), cant=V.cant + 14.0, work=0.0)
    flick = V.right((0.03, 0.0, 0.0), (98.0, 4.0, 0.0), -44.0)       # snapped over to the right: the cylinder swings out
    settle = V.right((0.02, 0.0, 0.0), (104.0, 6.0, 0.0), -30.0)
    up = V.right((0.0, -0.035 if fp else 0.06, 0.04), (150.0, 8.0, 0.0), -16.0)   # muzzle up: the empties fall out
    load = V.right((-0.01, -0.01, 0.02), (64.0, 14.0, 0.0), -36.0)   # muzzle down, the open cylinder turned up to the left hand
    push = V.right((-0.01, -0.024, 0.016), (61.0, 14.0, 0.0), -36.0)
    wind = V.right((0.0, -0.01, 0.01), (84.0, 8.0, 0.0), -50.0)      # wound up the other way...
    shut = V.right((-0.03, 0.03, 0.0), (96.0, 2.0, 0.0), 36.0)       # ...and flicked over to the left: the cylinder slams shut
    out = V.right((0.06, 0.03, -0.04), (92.0, -2.0, 0.0), 0.0)       # the spin: the arm sweeps out to the right...
    top = V.right((0.04, 0.085, -0.03), (98.0, 0.0, 0.0), 0.0)       # ...up...
    back = V.right((0.0, 0.05, -0.01), (92.0, 3.0, 0.0), 2.0)        # ...and back in
    catch = V.right((0.0, -0.028, 0.0), (84.0, 4.0, 0.0), V.cant, work=0.0)
    over = V.right((0.0, 0.008, 0.0), work=0.0)
    keys_r = [(0.0, rest), (0.05, dip), (0.13, flick, "out"), (0.22, settle), (0.36, up, "out"), (0.47, moved(up, (0.0, -0.012, 0.0))),
              (0.72, load), (0.90, load), (0.95, push, "out"), (1.03, load), (1.10, wind), (1.18, shut, "out"), (1.27, back),
              (1.38, out), (1.52, top), (1.64, back), (1.71, catch, "in"), (1.79, over, "out"), (1.87, rest), (2.0, rest)]
    # The left hand brings a speed loader to the back of the open cylinder and pushes it in.
    # It comes in from the left, the loader in its fingertips, so the cylinder stays in view.
    behind = CYLINDER_OPEN + v(-0.06, -0.012, 0.0)

    def loader(back_off):
        return V.fist_on(load, behind + v(0.0, 0.0, back_off), palm=(0.0, -0.35, -1.0), wrist=(-1.0, -0.45, 0.3), **_swung(80.0))
    keys_l = [(0.0, V.rest_l), (0.06, V.rest_l), (0.34, V.hip, "in"), (0.60, V.lift), (0.84, loader(0.07)), (0.94, loader(0.025), "in"),
              (1.02, loader(0.09), "out"), (1.16, V.out), (1.30, V.clear), (1.50, moved(V.clear, (-0.02, -0.03, 0.02))),
              (1.68, V.clear), (1.88, V.rest_l), (2.0, V.rest_l)]

    def pose(t):
        spec = V.spec(keyed(t, keys_r), keyed(t, keys_l))
        spec["fingers_r"] = hand_at(t, [(0.0, "gun"), (1.22, "gun"), (1.30, "trigger", "out"), (1.60, "trigger"), (1.70, "gun", "in")])
        spec["fingers_l"] = hand_at(t, [(0.0, "wrap"), (0.06, "wrap"), (0.22, "relaxed"), (0.5, "pinch"), (0.95, "pinch"),
                                        (1.03, "open", "out"), (1.2, "relaxed"), (1.7, "relaxed"), (1.88, "wrap")])
        spec.update(_swung(at(t, [(0.0, 0.0), (0.09, 0.0), (0.16, 96.0, "out"), (0.24, 80.0), (1.13, 80.0), (1.18, 0.0, "in")])))
        spec["vent_pos"] = (0.0, at(t, [(0.0, 0.0), (0.12, 0.0), (0.17, 0.009, "out"), (1.16, 0.007), (1.20, 0.0, "in")]), 0.0)
        spec["slide"] = 0.0
        _spin(spec, at(t, [(0.0, 0.0), (1.27, 0.0), (1.36, -60.0, "in"), (1.58, -300.0, "linear"), (1.68, -360.0, "out"), (2.0, -360.0)]))
        if not fp:
            _body(spec, t, [(0.0, 0.0), (0.14, 8.0, "out"), (0.4, 3.0), (0.72, -6.0), (0.95, -10.0), (1.18, -12.0, "out"), (1.4, 6.0),
                            (1.7, 2.0), (1.9, 0.0)],
                  [(0.0, 0.0), (0.36, -5.0, "out"), (0.72, 4.0), (1.0, 5.0), (1.2, 0.0), (1.5, -5.0), (1.8, 0.0)])
        return spec
    return pose


# ---------------------------------------------------------------------------
# Derringer (1.4 s)

DERRINGER_ROUNDS = v(0.0, 0.063, -0.038)   # the middle of the pair of rounds, seated (gun space)


# ---------------------------------------------------------------------------
# Dual Pistols, id "akimbo" (2.0 s): a pistol in each fist. Both wrists flick outward and throw the cells out
# to the sides, the arms cross low so each gun is pushed down on a new cell at the far
# hip, and they uncross with both guns spinning forward together.

AK_OUT = A.CELL_OUT   # the way out of a pistol's grip
DUAL_PASS = {False: ((0.0, -0.11, 0.06), 30.0), True: ((0.0, -0.10, 0.06), 30.0)}   # as the arms pass: how much deeper the left gun goes, and how much further its muzzle tips down


def akimbo(fp):
    import weapon_anims as W
    pos0, hand0, cant0 = W.DUAL_AIM[fp]

    def arm(by, hand=hand0, cant=cant0):
        return W._dual_arm(fp, W._add(pos0, by), hand, cant)

    def left(a, by=ZERO):
        m = W._mirror_arm(a)
        m["ik"] = W._add(m["ik"], by)
        return m
    rest = arm(ZERO)
    dip = arm((0.0, -0.012, 0.0), cant=cant0 - 8.0)
    flick = arm((0.035, 0.04, 0.03), (106.0, -12.0, 0.0), 82.0)     # rolled over outward: the cell flies out to the side
    hold = arm((0.02, 0.02, 0.04), (100.0, -6.0, 0.0), 58.0)
    if fp:
        cross = arm((-0.25, -0.075, 0.05), (58.0, 40.0, 0.0), -22.0)   # across to the far hip, muzzle down (kept in view)
    else:
        cross = arm((-0.245, -0.27, 0.175), (52.0, 40.0, 0.0), -22.0)
    push = moved(cross, (0.0, -0.045, 0.0), (50.0, 40.0, 0.0))        # down on the new cell
    lifted = moved(cross, (0.0, 0.012, 0.0))
    wide = arm((0.07, 0.05, 0.02), (94.0, -8.0, 0.0), 0.0)          # uncrossed and out wide: the spin
    top = arm((0.07, 0.085, 0.02), (99.0, -8.0, 0.0), 0.0)
    catch = arm((0.0, -0.025, 0.0), (85.0, hand0[1], 0.0), cant0)
    over = arm((0.0, 0.008, 0.0))
    keys_r = [(0.0, rest), (0.06, dip), (0.14, flick, "out"), (0.28, hold), (0.58, cross), (0.66, cross), (0.71, push, "out"),
              (0.80, lifted), (1.0, wide, "out"), (1.2, top), (1.40, wide), (1.49, catch, "in"), (1.58, over, "out"), (1.68, rest), (2.0, rest)]
    behind = (0.0, -0.03, 0.06)   # the left arm crosses under and behind the right
    keys_l = [(k[0], left(k[1], behind if k[1] in (cross, push, lifted) else ZERO)) + tuple(k[2:]) for k in keys_r]
    # Where the arms pass each other, going in and coming out, the left gun dips under and
    # behind the right one, its muzzle tipped further down, so the two never run into each other.
    deep, tip = DUAL_PASS[fp]
    for t, more, ease_in in ((0.41, 1.4, "in"), (0.49, 1.4, "linear"), (0.845, 1.6, "linear")):
        i = next(i for i, k in enumerate(keys_l) if k[0] > t)
        keys_l[i] = (keys_l[i][0], keys_l[i][1], "out")
        passing = left(keyed(t, keys_r), W._add(behind, tuple(x * more for x in deep)))
        passing["hand"] = (passing["hand"][0] - tip * more,) + tuple(passing["hand"][1:])
        keys_l.insert(i, (t, passing, ease_in))

    def pose(t):
        spec = {"arm_r": keyed(t, keys_r), "arm_l": keyed(t, keys_l)}
        fingers = hand_at(t, [(0.0, "gun"), (0.96, "gun"), (1.04, "trigger", "out"), (1.36, "trigger"), (1.46, "gun", "in")])
        slide = at(t, [(0.0, 0.0), (0.10, 0.0), (0.14, 0.04, "out"), (1.50, 0.04), (1.56, 0.0, "in")])
        if t < 0.12 or t >= 0.71:
            mag = ZERO
        elif t < 0.2:    # out of the grip (the game's own flying cell takes over)
            mag = tuple(AK_OUT * at(t, [(0.12, 0.0), (0.2, 0.22, "linear")]))
        else:            # the new one, waiting at the hip: the gun comes down on it
            mag = tuple(AK_OUT * at(t, [(0.2, 0.2), (0.6, 0.2), (0.71, 0.0, "in")]))
        # Each pistol's chin drops open on its hinge as the cell flies, and snaps shut on the new one.
        vent = at(t, [(0.0, 0.0), (0.10, 0.0), (0.15, -38.0, "out"), (0.22, -32.0), (0.73, -32.0), (0.78, 0.0, "in")])
        spec.update({"fingers_r": fingers, "fingers_l": fingers, "slide": slide, "slide_l": slide, "mag": mag, "mag_l": mag,
                     "vent": vent, "vent_l": vent, "vent_pivot": A.PISTOL_VENT_PIVOT, "vent_pivot_l": A.PISTOL_VENT_PIVOT})
        turn = at(t, [(0.0, 0.0), (0.98, 0.0), (1.06, -60.0, "in"), (1.33, -300.0, "linear"), (1.44, -360.0, "out"), (2.0, -360.0)])
        _spin(spec, turn)
        _spin(spec, turn, "pistol_l")
        if not fp:
            _body(spec, t, [(0.0, 0.0), (2.0, 0.0)], [(0.0, 0.0), (0.14, -4.0, "out"), (0.4, 0.0), (0.7, 10.0, "out"), (1.0, -4.0),
                                                      (1.5, -3.0), (1.8, 0.0)])
        return spec
    return pose


RELOADS = {"machine_pistol": machine_pistol, "revolver": revolver}
# The two-gun weapons' (rig.DUALS).
DUAL_RELOADS = {"akimbo": akimbo}
