"""Animation clips for the long guns: the shotgun, the assault rifle and the marksman rifles.
(The pistol's are in animations.py; it is the default, so its clips have plain names.)

Each long gun has its own version of every clip in which the hands hold the gun,
named "<clip>_<gun>" ("aim_rifle", "fp_reload_anti_materiel"). The game uses that version
when the player holds that gun, and the plain clip otherwise. The body clips (run,
slide, flips...) are shared: the game lays the gun's "aim" over the arms.

How a long gun is held: the right fist on the grip, the stock tucked in by the right
shoulder, and the left fist on the gun's support point (weapons.SUPPORT), solved by
the rig's "grip" so it stays on the gun whatever the gun does: on the shotgun it
rides the pump. The chest turns a little to the right (a bladed stance) to bring the
left shoulder forward, since a robot's arms are not long enough to reach a rifle's
handguard square-on. The game turns the chest by the aim clip's twist too.

New clips per gun:
  body:  aim (gun up), carry (sprinting: gun across the chest), reload, fire (the
         shotgun's pump, the bolt-action's bolt), respawn
  arms:  fp_idle, fp_one_hand, fp_sprint, fp_slide, fp_wall_l, fp_wall_r, fp_dive,
         fp_tuck, fp_mantle, fp_raise, fp_reload, fp_fire (shotgun, bolt-action)
The shotgun reloads a shell at a time: its reload clips are one shell, looped.
"""
import numpy as np
from m3 import euler
from rig import BODY, GUN_REST, Clip, FIST, keyed, merged, solve
import animations as A
import sidearm_anims
import long_reloads
from weapons import SUPPORT

LONG = ("shotgun", "rifle", "break_action", "smg", "burst_rifle", "lmg", "lever_action",
        "bolt_action", "railgun", "rocket_launcher", "grenade_launcher",
        "air_cannon", "minigun", "battle_rifle", "nail_gun",
        "crossbow", "anti_materiel", "plasma_cannon")
# Sidearms held like the pistol: they keep its poses but have their own reloads.
SIDEARMS = ("revolver", "machine_pistol")

# How each long gun is held, reloaded and worked after a shot.
#   hold: whose hold it copies; reload: mag (drop the magazine, with "handle": charge or
#   bolt after), shell (a shell at a time into the tube, looped), break (tip the barrels
#   open), cover (lift the top cover, swap the box), gate (a round into the side gate,
#   looped), top (a round in through the open bolt, looped), cell (swap the power cell),
#   rocket (a new rocket in at the back), drum (a grenade into the drum, looped);
#   fire: pump, bolt, lever, vent (the railgun's sleeve snaps back).
SPEC = {
    "shotgun": {"hold": "shotgun", "reload": "shell", "fire": "pump"},
    "rifle": {"hold": "rifle", "reload": "mag", "handle": "charge", "handle_at": (-0.06, 0.07, -0.13)},
    "break_action": {"hold": "shotgun", "reload": "break"},
    "smg": {"hold": "rifle", "reload": "mag", "handle": "charge", "handle_at": (-0.03, 0.07, -0.10), "mag_hold": (0.0, -0.10, -0.085)},
    "burst_rifle": {"hold": "rifle", "reload": "mag", "handle": "charge", "handle_at": (-0.034, 0.075, 0.02), "mag_hold": (0.0, -0.08, -0.10)},
    "lmg": {"hold": "rifle", "reload": "cover", "mag_hold": (0.0, -0.05, -0.12)},
    "lever_action": {"hold": "rifle", "reload": "gate", "fire": "lever"},
    "bolt_action": {"hold": "sniper", "reload": "top", "fire": "bolt", "bolt": (-0.08, 0.06, -0.01)},
    "railgun": {"hold": "sniper", "reload": "cell", "fire": "vent", "mag_hold": (0.0, -0.005, 0.105)},
    "rocket_launcher": {"hold": "rocket_launcher", "reload": "rocket"},
    "grenade_launcher": {"hold": "shotgun", "reload": "drum"},
    # The third batch (each copies a hold and a way of reloading from the guns above)
    "air_cannon": {"hold": "shotgun", "reload": "cell", "mag_hold": (0.0, 0.0, -0.16)},
    "minigun": {"hold": "rifle", "reload": "cover", "mag_hold": (0.0, -0.05, -0.12)},
    "battle_rifle": {"hold": "rifle", "reload": "mag", "handle": "charge", "handle_at": (-0.035, 0.07, -0.12)},
    "nail_gun": {"hold": "rifle", "reload": "mag", "mag_hold": (0.0, -0.035, -0.17)},
    "crossbow": {"hold": "rifle", "reload": "top"},
    "anti_materiel": {"hold": "sniper", "reload": "mag", "handle": "bolt", "fire": "bolt", "bolt": (-0.092, 0.065, -0.02),
                      "mag_hold": (0.0, -0.03, -0.12)},
    "plasma_cannon": {"hold": "shotgun", "reload": "cell", "mag_hold": (0.0, -0.005, 0.11)},
}

# How a long gun is held: relaxed and low, the stock in beside the chest, not up at the
# cheek, tipped a touch inward (cant) and pointing a little in toward the middle (the
# hand's yaw), the chest turned to the right to bring the left shoulder round to the
# fore-end. The same in both views; in first person it sits low and off to the right.
# Third person, model space (the robot stands at the origin, facing -Z): where the
# right fist holds the grip, how far the chest turns to the right, the fist's turn.
HOLD = {
    "shotgun": {"grip": (0.10, 1.33, -0.19), "twist": -34.0, "hand": (90.0, 3.0, 0.0), "cant": 8.0},
    "rifle": {"grip": (0.10, 1.33, -0.20), "twist": -34.0, "hand": (90.0, 3.0, 0.0), "cant": 8.0},
    "sniper": {"grip": (0.10, 1.34, -0.18), "twist": -36.0, "hand": (90.0, 3.0, 0.0), "cant": 6.0},
    "rocket_launcher": {"grip": (0.10, 1.36, -0.25), "twist": -26.0, "hand": (90.0, 0.0, 0.0), "cant": 0.0},   # on the shoulder
}
# First person, relative to the camera.
FP_HOLD = {
    "shotgun": {"grip": (0.235, -0.262, -0.32), "twist": -42.0, "hand": (90.0, 5.0, 0.0), "cant": 8.0},
    "rifle": {"grip": (0.235, -0.256, -0.33), "twist": -42.0, "hand": (90.0, 5.0, 0.0), "cant": 8.0},
    "sniper": {"grip": (0.24, -0.264, -0.32), "twist": -42.0, "hand": (90.0, 5.0, 0.0), "cant": 6.0},
    "rocket_launcher": {"grip": (0.23, -0.31, -0.33), "twist": -30.0, "hand": (90.0, 4.0, 0.0), "cant": 3.0},
}
for _g in LONG:
    HOLD.setdefault(_g, HOLD[SPEC[_g]["hold"]])
    FP_HOLD.setdefault(_g, FP_HOLD[SPEC[_g]["hold"]])
# First person only: the shoulders sit lower and further forward than the body's, so the
# arms come up into view from below instead of across it (only the arms are drawn), and
# a little to the right, behind the gun. How far forward is fitted to each gun (_fit).
FP_HIPS = (0.07, 0.86, -0.14)
EYE_Y = A.EYE[1]
REACH = 0.462    # how far from its shoulder the left wrist is at most (the arm is 0.52 long): the elbow stays bent

# Reload lengths match WeaponData (the shotgun's is one shell; it loops).
RELOAD = {"shotgun": 0.5, "rifle": 1.9, "break_action": 1.7, "smg": 1.6, "burst_rifle": 2.0,
          "lmg": 3.6, "lever_action": 0.45, "bolt_action": 0.5, "railgun": 2.6, "rocket_launcher": 1.5,
          "grenade_launcher": 0.55, "revolver": 2.0, "machine_pistol": 1.4,
          "air_cannon": 1.8, "minigun": 4.5, "battle_rifle": 2.1, "nail_gun": 2.0, "crossbow": 1.3,
          "anti_materiel": 3.2, "plasma_cannon": 2.4}
FIRE = {"shotgun": 0.6, "lever_action": 0.66, "bolt_action": 0.95, "railgun": 0.5,
        "anti_materiel": 1.8}
LOOPED = ("shotgun", "lever_action", "bolt_action", "grenade_launcher")   # a round at a time
# The left hand under a fore-end: palm up, the fingers across under the gun and up its
# right side (the fist's turn, relative to the gun's). A gun held by an upright handle
# (weapons.SUPPORT: "upright") is held as the forearm comes, like a second grip.
CUPPED = (-90.0, 0.0, 90.0)
UPRIGHT = (0.0, 0.0, 0.0)      # ...the left fist turned as the right one is on the grip, the wrist behind the handle
POLE_R = (0.7, -1.0, 0.1)
POLE_L = (-0.6, -1.0, 0.2)


def right(grip, hand=(90.0, 0.0, 0.0), cant=0.0):
    """The right arm with its fist on the grip at `grip` (model space). hand: the fist's
    turn ((90, 0, 0) points the gun straight ahead); cant rolls the gun about its barrel."""
    wrist = np.array(grip, dtype=float) + euler(hand) @ np.array([0.0, FIST, 0.0])
    return {"ik": tuple(float(x) for x in wrist), "space": "model", "pole": POLE_R, "hand": hand, "cant": cant}


def fp_right(x, y, z, hand=(90.0, 0.0, 0.0), cant=0.0):
    return right((x, y + EYE_Y, z), hand, cant)


def support(gun, **extra):
    """The left fist on the gun's support point (the pump, the handguard)."""
    s = SUPPORT[gun]
    out = {"grip": s["grip"], "on": s.get("on", "pistol"), "pole": POLE_L}
    out["hand"] = UPRIGHT if s.get("upright") else CUPPED
    if s.get("upright"):
        out["fingers"] = "foregrip"
    out.update(extra)
    return out


def on_gun(point, on="pistol", **extra):
    out = {"grip": point, "on": on, "pole": POLE_L}
    out.update(extra)
    return out


def _add(a, b):
    return tuple(x + y for x, y in zip(a, b))


_FITS = {}


def _reach(spec):
    """How far the left wrist is from its shoulder in a pose (metres), and how far the arm
    falls short of where the pose wants the hand."""
    rot, pos = solve(BODY, spec)
    G, P = {}, {}
    for b in BODY.bones:
        if b.parent < 0:
            G[b.name], P[b.name] = rot[b.name], pos[b.name]
        else:
            pn = BODY.bones[b.parent].name
            G[b.name] = G[pn] @ rot[b.name]
            P[b.name] = P[pn] + G[pn] @ pos[b.name]
    arm = spec["arm_l"]
    on = arm.get("on", "pistol")
    contact = P[on] + G[on] @ GUN_REST @ np.array(arm["grip"], dtype=float)
    hand_rot = G["pistol"] @ euler(arm["hand"])
    wrist = contact + hand_rot @ np.array([0.0, FIST, 0.0])
    return float(np.linalg.norm(wrist - P["upper_arm_l"])), float(np.linalg.norm(P["hand_l"] - wrist))


def _fit(gun, fp):
    """How far the hold is shifted for this gun so that the left hand reaches its fore-end
    with the elbow still bent: in first person the shoulders come forward (only the arms
    are drawn), in third the gun comes back beside the chest. Metres."""
    key = (gun, fp)
    if key not in _FITS:
        _FITS[key] = 0.0
        lo, hi = 0.0, 0.30
        if _reach(held(gun, fp))[0] > REACH:
            for _ in range(12):
                _FITS[key] = (lo + hi) / 2.0
                if _reach(held(gun, fp))[0] > REACH:
                    lo = _FITS[key]
                else:
                    hi = _FITS[key]
            _FITS[key] = hi
    return _FITS[key]


def _base(gun, fp):
    h = (FP_HOLD if fp else HOLD)[gun]
    grip = _add(h["grip"], (0.0, EYE_Y, 0.0)) if fp else _add(h["grip"], (0.0, 0.0, _FITS.get((gun, fp), 0.0)))
    return grip, h["twist"]


def _pose(twist, arm_r, arm_l, **more):
    spec = {"chest": (0.0, twist, 0.0), "arm_r": arm_r, "arm_l": arm_l,
            "slide": 0.0, "slide_turn": 0.0, "slide_axis": 0.06, "mag": (0.0, 0.0, 0.0), "mag_rot": (0.0, 0.0, 0.0)}
    spec.update(more)
    return spec


def held(gun, fp=False, offset=(0.0, 0.0, 0.0), hand=None, cant=None, left=None, **more):
    """The gun in both hands (or in the right only, when `left` is given), as it is held
    (HOLD), moved by `offset`; hand, cant: the right fist's turn, if not the hold's own."""
    grip, twist = _base(gun, fp)
    h = (FP_HOLD if fp else HOLD)[gun]
    hand = h["hand"] if hand is None else hand
    cant = h["cant"] if cant is None else cant
    if fp:
        more.setdefault("hips", {"pos": _add(FP_HIPS, (0.0, 0.0, -_FITS.get((gun, fp), 0.0))), "rot": (0.0, 0.0, 0.0)})
    return _pose(twist, right(_add(grip, offset), hand, cant), left if left is not None else support(gun), **more)


# ---------------------------------------------------------------------------
# Body (third person)

for _g in LONG:
    _fit(_g, False)
    _fit(_g, True)


def aim(gun):
    return lambda t: held(gun)


def carry(gun):
    """Sprinting: the gun across the chest, muzzle up and to the left."""
    def fn(t):
        spec = _pose(0.0, right((0.13, 1.16, -0.25), hand=(122.0, 38.0, 0.0), cant=-20.0), support(gun))
        return spec
    return fn


def _away_body():
    return {"ik": (-0.20, 0.98, -0.08), "space": "model", "pole": (-0.6, -0.3, 1.0), "hand": (30.0, 0.0, 0.0)}


def _away_fp():
    return {"ik": (-0.06, EYE_Y - 0.55, -0.16), "space": "model", "pole": (-0.6, -0.3, 1.0), "hand": (30.0, 0.0, 0.0)}


def reload_clip(gun, fp):
    if gun in long_reloads.RELOADS:
        return long_reloads.RELOADS[gun](gun, fp)
    away = _away_fp() if fp else _away_body()
    rest = held(gun, fp)
    tilt = held(gun, fp, offset=(-0.02, 0.02, 0.04), hand=(98.0, 12.0, 0.0), cant=32.0)
    spec = SPEC[gun]
    style = spec["reload"]
    if style in NEW_RELOADS:
        return NEW_RELOADS[style](gun, fp, rest, tilt, away)
    mag_hold = spec.get("mag_hold", (0.0, -0.09, -0.10))   # the left fist on the magazine
    start = dict(tilt)
    keys = [(0.0, rest)]

    def k(t, base, left, ease="smooth", **more):
        spec = dict(base)
        spec["arm_l"] = left
        spec.update(more)
        keys.append((t, spec, ease))

    k(0.18, tilt, on_gun(mag_hold, "pistol_mag"))
    k(0.30, tilt, on_gun(mag_hold, "pistol_mag"), mag=(0.0, -0.03, 0.01))
    k(0.48, tilt, away, "in", mag=(0.0, -0.75, 0.06))
    k(0.80, tilt, on_gun(mag_hold, "pistol_mag"), "linear", mag=(0.0, -0.20, 0.06))
    k(1.02, tilt, on_gun(mag_hold, "pistol_mag"), "out", mag=(0.0, -0.04, 0.01))
    k(1.12, tilt, on_gun(mag_hold, "pistol_mag"), "in")
    if spec.get("handle") == "charge":
        handle = spec["handle_at"]
        k(1.32, rest, on_gun(handle, "pistol_slide"))
        k(1.44, rest, on_gun(handle, "pistol_slide"), "out", slide=0.075)
        k(1.52, rest, on_gun(handle, "pistol_slide"), "in")
        k(1.74, rest, support(gun))
        k(1.90, rest, support(gun))
    elif spec.get("handle") is None:
        k(1.32, rest, support(gun))
        k(1.45, rest, support(gun))
    else:
        bolt = (-0.088, 0.06, -0.02)
        k(1.40, rest, on_gun(bolt, "pistol_slide"))
        k(1.55, rest, on_gun(bolt, "pistol_slide"), "out", slide_turn=-70.0)
        k(1.75, rest, on_gun(bolt, "pistol_slide"), "out", slide_turn=-70.0, slide=0.09)
        k(1.92, rest, on_gun(bolt, "pistol_slide"), "in", slide_turn=-70.0)
        k(2.02, rest, on_gun(bolt, "pistol_slide"), "in")
        k(2.24, rest, support(gun))
        k(2.40, rest, support(gun))
    del start
    return _scaled(keys, RELOAD[gun])


def _scaled(keys, length):
    """Keys stretched (or squeezed) to `length` seconds."""
    k = length / keys[-1][0]
    keys = [(key[0] * k,) + tuple(key[1:]) for key in keys]
    return lambda t: keyed(t, keys)


def _hinge(rot, pivot):
    """mag / mag_rot that turn the magazine-bone part by `rot` (pitch, yaw, roll) about `pivot` (gun space)."""
    p = np.array(pivot, dtype=float)
    off = p - euler(rot) @ p
    return {"mag_rot": tuple(float(x) for x in rot), "mag": tuple(float(x) for x in off)}


def _cover_reload(gun, fp, rest, tilt, away):
    """LMG: lift the top cover, drop the empty box, hang a new one and slam the cover."""
    cover = {"slide_pivot": (0.095, 0.16)}
    lid = (0.0, 0.10, -0.02)
    box_at = SPEC[gun]["mag_hold"]

    def k(t, base, left, ease="smooth", pitch=0.0, **more):
        spec = dict(base, arm_l=left, slide_pitch=pitch, **cover)
        spec.update(more)
        return (t, spec, ease)
    keys = [
        k(0.0, rest, support(gun)),
        k(0.30, tilt, on_gun(lid, "pistol_slide")),
        k(0.55, tilt, on_gun(lid, "pistol_slide"), "out", pitch=-62.0),
        k(0.80, tilt, on_gun(box_at, "pistol_mag"), pitch=-62.0),
        k(0.95, tilt, on_gun(box_at, "pistol_mag"), pitch=-62.0, mag=(0.0, -0.04, 0.0)),
        k(1.30, tilt, away, "in", pitch=-62.0, mag=(0.0, -0.8, 0.05)),
        k(1.90, tilt, on_gun(box_at, "pistol_mag"), "linear", pitch=-62.0, mag=(0.0, -0.25, 0.05)),
        k(2.25, tilt, on_gun(box_at, "pistol_mag"), "out", pitch=-62.0, mag=(0.0, 0.0, 0.0)),
        k(2.55, tilt, on_gun(lid, "pistol_slide"), pitch=-62.0),
        k(2.85, tilt, on_gun(lid, "pistol_slide"), "in", pitch=0.0),
        k(3.05, rest, on_gun(lid, "pistol_slide")),
        k(3.35, rest, support(gun)),
        k(3.60, rest, support(gun)),
    ]
    return _scaled(keys, RELOAD[gun])


def _gate_reload(gun, fp, rest, tilt, away):
    """Lever-action: a round from the belt, pushed into the loading gate. Loops."""
    rnd = (0.0, 0.055, -0.04)
    start_off = (-0.06, -0.28, 0.06)
    gate_off = (-0.03, -0.01, -0.02)
    side = held(gun, fp, offset=(-0.02, 0.02, 0.04), hand=(96.0, 18.0, 0.0), cant=-24.0)
    keys = [
        (0.0, dict(side, arm_l=on_gun(rnd, "pistol_mag"), mag=start_off)),
        (0.20, dict(side, arm_l=on_gun(rnd, "pistol_mag"), mag=gate_off), "out"),
        (0.30, dict(side, arm_l=on_gun(rnd, "pistol_mag"), mag=(0.0, 0.0, 0.0)), "in"),
        (0.45, dict(side, arm_l=on_gun(_add(rnd, start_off))), "smooth"),
    ]
    return _scaled(keys, RELOAD[gun])


def _top_reload(gun, fp, rest, tilt, away):
    """Bolt-action: bolt open, a round pressed down into the action from above. Loops."""
    bolt_open = {"slide_turn": -70.0, "slide": 0.09}
    top = (0.0, 0.09, -0.06)
    above = _add(top, (-0.03, 0.10, 0.04))
    work = dict(tilt, **bolt_open)
    keys = [
        (0.0, dict(work, arm_l=on_gun(above))),
        (0.22, dict(work, arm_l=on_gun(top)), "out"),
        (0.30, dict(work, arm_l=on_gun(_add(top, (0.0, -0.02, 0.0)))), "in"),
        (0.50, dict(work, arm_l=on_gun(above)), "smooth"),
    ]
    return _scaled(keys, RELOAD[gun])


def _cell_reload(gun, fp, rest, tilt, away):
    """Railgun: pop the spent power cell out of the back, slot in a fresh one."""
    cell = SPEC[gun]["mag_hold"]

    def k(t, base, left, ease="smooth", **more):
        return (t, dict(base, arm_l=left, **more), ease)
    keys = [
        k(0.0, rest, support(gun)),
        k(0.35, tilt, on_gun(cell, "pistol_mag")),
        k(0.55, tilt, on_gun(cell, "pistol_mag"), "out", mag=(0.0, -0.03, 0.03)),
        k(0.85, tilt, away, "in", mag=(0.0, -0.8, 0.1)),
        k(1.45, tilt, on_gun(cell, "pistol_mag"), "linear", mag=(0.0, -0.22, 0.08)),
        k(1.80, tilt, on_gun(cell, "pistol_mag"), "out", mag=(0.0, 0.0, 0.0)),
        k(1.95, tilt, on_gun(cell, "pistol_mag"), "in"),
        k(2.30, rest, support(gun)),
        k(2.60, rest, support(gun)),
    ]
    return _scaled(keys, RELOAD[gun])


def _rocket_reload(gun, fp, rest, tilt, away):
    """Rocket launcher: a new rocket from the hip, up behind the shoulder and slid into the back of the tube."""
    grab = SPEC[gun].get("grab", (0.0, 0.115, -0.36))   # a point on the rocket's body
    low = (-0.04, -0.36, 0.10)
    behind = (0.0, -0.02, 0.22)
    lift = held(gun, fp, offset=(0.0, 0.02, 0.0), hand=(96.0, 6.0, 0.0), cant=12.0)

    def k(t, base, left, ease="smooth", **more):
        return (t, dict(base, arm_l=left, **more), ease)
    keys = [
        k(0.0, rest, away, mag=low),
        k(0.30, lift, on_gun(grab, "pistol_mag"), "out", mag=low),
        k(0.70, lift, on_gun(grab, "pistol_mag"), "smooth", mag=behind),
        k(1.05, lift, on_gun(grab, "pistol_mag"), "in", mag=(0.0, 0.0, 0.0)),
        k(1.25, rest, support(gun), "smooth"),
        k(1.50, rest, support(gun)),
    ]
    return _scaled(keys, RELOAD[gun])


def _drum_reload(gun, fp, rest, tilt, away):
    """Grenade launcher: a grenade pushed into the front of the drum, which turns one chamber. Loops."""
    face = (0.03, 0.07, -0.27)
    start = _add(face, (-0.08, -0.26, 0.10))
    keys = [
        (0.0, dict(tilt, arm_l=on_gun(start), mag_rot=(0.0, 0.0, 0.0))),
        (0.24, dict(tilt, arm_l=on_gun(face), mag_rot=(0.0, 0.0, 0.0)), "out"),
        (0.32, dict(tilt, arm_l=on_gun(_add(face, (0.0, 0.0, 0.03))), mag_rot=(0.0, 0.0, 0.0)), "in"),
        (0.44, dict(tilt, arm_l=on_gun(face), mag_rot=(0.0, 0.0, 60.0)), "out"),
        (0.55, dict(tilt, arm_l=on_gun(start), mag_rot=(0.0, 0.0, 60.0)), "smooth"),
    ]
    for i, key in enumerate(keys):   # the drum turns about its own axis, not the grip
        spec = dict(key[1])
        spec.update(_hinge(spec["mag_rot"], (0.0, 0.07, 0.0)))
        keys[i] = (key[0], spec) + tuple(key[2:])
    return lambda t: keyed(t, keys)


NEW_RELOADS = {"cover": _cover_reload, "gate": _gate_reload, "top": _top_reload,
               "cell": _cell_reload, "rocket": _rocket_reload, "drum": _drum_reload}


def fire_clip(gun, fp):
    rest = held(gun, fp)
    dip = held(gun, fp, offset=(0.0, -0.015, 0.02), hand=(86.0, 3.0, 0.0), cant=-6.0)
    style = SPEC[gun].get("fire")
    if style == "pump":
        return lambda t: keyed(t, [
            (0.0, rest), (0.10, rest),
            (0.24, dict(dip, slide=0.08), "out"),
            (0.38, dict(rest, slide=0.0), "in"),
            (0.60, rest),
        ])
    if style == "lever":
        pin = {"slide_pivot": (-0.012, 0.065)}
        flick = held(gun, fp, offset=(0.0, -0.01, 0.015), hand=(84.0, 0.0, 0.0), cant=-4.0)
        return lambda t: keyed(t, [
            (0.0, dict(rest, slide_pitch=0.0, **pin)), (0.08, dict(rest, slide_pitch=0.0, **pin)),
            (0.22, dict(flick, slide_pitch=48.0, **pin), "out"),
            (0.38, dict(rest, slide_pitch=0.0, **pin), "in"),
            (0.66, dict(rest, slide_pitch=0.0, **pin)),
        ])
    if style == "vent":
        return lambda t: keyed(t, [
            (0.0, dict(rest, slide=0.0)), (0.04, dict(dip, slide=0.06), "out"),
            (0.36, dict(rest, slide=0.0), "smooth"), (0.5, rest),
        ])
    bolt = SPEC[gun].get("bolt", (-0.088, 0.06, -0.02))
    work = held(gun, fp, offset=(0.0, 0.0, 0.02), hand=(92.0, -4.0, 0.0), cant=14.0)

    def at_bolt(**more):
        return dict(work, arm_l=on_gun(bolt, "pistol_slide"), **more)
    keys = [
        (0.0, rest), (0.12, rest),
        (0.32, at_bolt()),
        (0.42, at_bolt(slide_turn=-70.0), "out"),
        (0.56, at_bolt(slide_turn=-70.0, slide=0.09), "out"),
        (0.70, at_bolt(slide_turn=-70.0), "in"),
        (0.78, at_bolt(), "in"),
        (0.98, rest),
        (1.10, rest),
    ]
    return _scaled(keys, FIRE[gun])


def respawn(gun):
    """Boot-up: kneeling with the head down, then up to ready, gun in both hands."""
    idle = A.idle(0.0)
    ready = merged(idle, chest=(idle["chest"][0], idle["chest"][1] + HOLD[gun]["twist"], 0.0),
                   arm_r=held(gun)["arm_r"], arm_l=support(gun))
    kneel = merged(A.crouch_idle(0.0), chest=A.LOW_CHEST, head=(-28.0, 0.0, 0.0),
                   arm_r=right((0.12, 0.80, -0.30), hand=(30.0, 10.0, 0.0)), arm_l=support(gun))
    return lambda t: keyed(t, [(0.0, kneel), (0.15, kneel), (0.6, ready, "out")])


def body_clips():
    out = []
    for gun in LONG:
        out += [
            Clip("aim_" + gun, 1 / 30, aim(gun)),
            Clip("carry_" + gun, 1 / 30, carry(gun)),
            Clip("reload_" + gun, RELOAD[gun], reload_clip(gun, False), loop=gun in LOOPED, fps=long_reloads.FPS.get(gun, 30)),
            Clip("respawn_" + gun, 0.6, respawn(gun)),
        ]
        if gun in long_reloads.ENDS:
            out.append(Clip("reload_end_" + gun, long_reloads.ENDS[gun][0], long_reloads.ENDS[gun][1](gun, False)))
        if gun in FIRE:
            out.append(Clip("fire_" + gun, FIRE[gun], fire_clip(gun, False)))
    out += [Clip("reload_" + g, RELOAD[g], sidearm_reload(g, False)) for g in SIDEARMS]
    out += akimbo_body_clips()
    return out


# ---------------------------------------------------------------------------
# First-person arms

def fp_clips_for(gun):
    def fp(offset=(0.0, 0.0, 0.0), **kw):
        return held(gun, True, offset=offset, **kw)

    away_l = A.FP_L_AWAY
    one = dict(offset=(0.025, -0.03, 0.01), cant=-8.0, left=away_l)
    idle = fp()
    clips = {
        "fp_idle": lambda t: idle,
        "fp_one_hand": lambda t: fp(**one),
        "fp_sprint": lambda t: fp(offset=(-0.05, -0.06, 0.02), hand=(80.0, 32.0, 0.0), cant=-30.0),
        "fp_slide": lambda t: fp(offset=(0.02, 0.0, 0.0), cant=-20.0, left=A.fp_slide(0)["arm_l"]),
        "fp_wall_l": lambda t: fp(offset=(0.03, -0.01, 0.0), cant=10.0, left=A.fp_wall_l(0)["arm_l"]),
        "fp_wall_r": lambda t: fp(offset=(0.01, -0.01, 0.01), cant=-14.0),
        "fp_dive": lambda t: fp(offset=(-0.02, 0.03, -0.04)),
        "fp_tuck": lambda t: fp(offset=(-0.01, -0.10, 0.07), hand=(100.0, 12.0, 0.0)),
    }
    reach = fp(offset=(0.08, -0.12, 0.03), hand=(70.0, -8.0, 0.0), cant=-30.0, left=A.fp_mantle(0)["arm_l"])
    push = fp(offset=(0.10, -0.26, 0.08), hand=(64.0, -8.0, 0.0), cant=-35.0, left=A.fp_mantle(0.45)["arm_l"])
    clips["fp_mantle"] = lambda t: keyed(t, [(0.0, reach), (0.08, reach), (0.34, push, "in"), (0.45, push)])
    down = fp(offset=(0.0, -0.20, 0.08), hand=(62.0, 18.0, 0.0))
    clips["fp_raise"] = lambda t: keyed(t, [(0.0, down), (0.1, down), (0.4, idle, "out")])
    out = []
    for name, fn in clips.items():
        length = {"fp_mantle": 0.45, "fp_raise": 0.4}.get(name, 1 / 30)
        out.append(Clip("%s_%s" % (name, gun), length, fn))
    out.append(Clip("fp_reload_" + gun, RELOAD[gun], reload_clip(gun, True), loop=gun in LOOPED, fps=long_reloads.FPS.get(gun, 30)))
    if gun in long_reloads.ENDS:
        out.append(Clip("fp_reload_end_" + gun, long_reloads.ENDS[gun][0], long_reloads.ENDS[gun][1](gun, True)))
    if gun in FIRE:
        out.append(Clip("fp_fire_" + gun, FIRE[gun], fire_clip(gun, True)))
    return out


def arms_clips():
    out = []
    for gun in LONG:
        out += fp_clips_for(gun)
    out += [Clip("fp_reload_" + g, RELOAD[g], sidearm_reload(g, True)) for g in SIDEARMS]
    out += akimbo_arms_clips()
    return out


# ---------------------------------------------------------------------------
# Sidearms (held like the pistol, with the pistol's poses)

def sidearm_reload(gun, fp):
    return sidearm_anims.RELOADS[gun](fp)


# ---------------------------------------------------------------------------
# Akimbo: a pistol in each fist. The left gun rides on its own bones ("pistol_l"...),
# so every pose here sets both arms out front, mirror images of each other. Shots
# alternate between the guns; the game kicks whichever arm fired (no fire clip).

AKIMBO = "akimbo"
AKIMBO_RELOAD = 2.0   # WeaponData.akimbo().reload_time


def _mirror_arm(arm):
    """The left arm as the mirror image of a right-arm spec."""
    out = dict(arm)
    out["ik"] = (-arm["ik"][0], arm["ik"][1], arm["ik"][2])
    out["pole"] = (-arm["pole"][0], arm["pole"][1], arm["pole"][2])
    if "hand" in arm:
        out["hand"] = (arm["hand"][0], -arm["hand"][1], -arm["hand"][2])
    out["cant"] = -arm.get("cant", 0.0)
    return out


def _pair(right_arm, **more):
    spec = {"arm_r": right_arm, "arm_l": _mirror_arm(right_arm),
            "slide": 0.0, "mag": (0.0, 0.0, 0.0), "slide_l": 0.0, "mag_l": (0.0, 0.0, 0.0),
            "fingers_l": "gun"}   # the left hand has a gun of its own
    spec.update(more)
    return spec


def _ak_arm(fp, pos, hand=(90.0, 0.0, 0.0), cant=0.0):
    return A.fp_arm_r(*pos, hand=hand, cant=cant) if fp else A._arm("r", pos, hand, cant)


# Where the right fist holds its gun: third person in chest space, first person from the camera.
AK_AIM = {False: ((0.125, 0.25, -0.445), (90.0, 5.0, 0.0), -8.0),
          True: ((0.155, -0.16, -0.42), (90.0, 4.0, 0.0), -6.0)}


def akimbo_rest(fp, offset=(0.0, 0.0, 0.0), hand=None, cant=None, **more):
    pos, h, c = AK_AIM[fp]
    return _pair(_ak_arm(fp, _add(pos, offset), hand if hand is not None else h, c if cant is None else cant), **more)


def akimbo_reload(fp):
    return sidearm_anims.akimbo(fp)


AK_REST_ARM = {fp: akimbo_rest(fp)["arm_r"] for fp in (False, True)}


def akimbo_body_clips():
    return [
        Clip("aim_akimbo", 1 / 30, lambda t: akimbo_rest(False)),
        Clip("reload_akimbo", AKIMBO_RELOAD, akimbo_reload(False)),
    ]


def akimbo_arms_clips():
    idle = akimbo_rest(True)
    down = akimbo_rest(True, offset=(0.02, -0.25, 0.18), hand=(60.0, 10.0, 0.0))
    sprint = akimbo_rest(True, offset=(0.045, -0.13, 0.12), hand=(125.0, 18.0, 0.0), cant=-18.0)
    one = dict(akimbo_rest(True, offset=(0.02, 0.0, 0.0)), arm_l=A.FP_L_AWAY)
    wall_r = dict(akimbo_rest(True, offset=(0.02, 0.0, 0.0), cant=-16.0))
    wall_r["arm_l"] = AK_REST_ARM_L_FP
    dive = akimbo_rest(True, offset=(-0.02, 0.045, -0.08))
    return [
        Clip("fp_idle_akimbo", 1 / 30, lambda t: idle),
        Clip("fp_sprint_akimbo", 1 / 30, lambda t: sprint),
        Clip("fp_one_hand_akimbo", 1 / 30, lambda t: one),
        Clip("fp_wall_r_akimbo", 1 / 30, lambda t: wall_r),
        Clip("fp_dive_akimbo", 1 / 30, lambda t: dive),
        Clip("fp_raise_akimbo", 0.4, lambda t: keyed(t, [(0.0, down), (0.1, down), (0.4, idle, "out")])),
        Clip("fp_reload_akimbo", AKIMBO_RELOAD, akimbo_reload(True)),
    ]


AK_REST_ARM_L_FP = akimbo_rest(True)["arm_l"]
