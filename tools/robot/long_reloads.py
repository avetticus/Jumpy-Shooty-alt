"""The long guns' reloads, family by family (the sidearms' are in sidearm_anims.py). Each
is a function of time giving the pose: both arms, the fingers, the gun's moving parts and
whatever the left hand brings to it, from the gun's own hold (weapon_anims.held).

Shotguns:
    Shotgun          a shell at a time, each thumbed in with a flick (it loops); when the
                     tube is full the left hand lets go and the gun is spun once forward
                     round the right hand, racking itself ("reload_end")
    Break-Action     snapped open (the empties fly back over the shoulder), two new shells
                     pushed in together, flicked shut with the wrist alone
    Air Cannon       the tank is spun loose and dropped, a new one is tossed up, caught
                     under the gun and spun in, and the side vents hiss shut

The game's side of each (what flies out, the glow, steam) is timed to these keys in
game/combat/reload_fx.gd, and the sounds in game/audio/sfx_list.gd.
"""
import numpy as np
from m3 import norm, rx, ry, rz, v
from rig import FIST, GUN_REST, ZERO, _slerp_m, ease, keyed
import animations as A
import sidearm_anims as S
from weapons import BREAK_HINGE, SUPPORT

at, hand_at, euler_of = A._at, A._hand_at, A._euler_of
PALM_L = A.PALM_L
UP, LEFT = (0.0, 1.0, 0.0), (-1.0, 0.0, 0.0)
TIPS = v(0.014, -0.03, 0.0)   # from the middle of the left fist to what its fingertips pinch (the hand's own space)


def turn_of(palm, wrist):
    """A left hand's turn: `palm` the way the palm faces, `wrist` the way from the fist back to the wrist."""
    y = norm(v(*wrist))
    x = v(*palm)
    x = norm(x - y * float(np.dot(x, y)))
    return np.column_stack([x, y, np.cross(x, y)])


CUPPED = turn_of(UP, LEFT)                       # under a fore-end, palm up (gun space)
UPRIGHT = turn_of((1.0, 0.0, 0.0), (0.0, 0.0, 1.0))   # round an upright front handle


class Long:
    """One long gun in one view (first or third person): its hold, and where the left hand goes."""

    def __init__(self, gun, fp):
        import weapon_anims as W
        self.W, self.gun, self.fp = W, gun, fp
        rest = W.held(gun, fp)
        self.base = {k: val for k, val in rest.items() if k not in ("arm_r", "arm_l")}
        self.twist = rest["chest"][1]
        # Where the gun is worked on: up and in toward the middle of the view, or up in front of the chest.
        self.work = (-0.09, 0.06, 0.02) if fp else (0.0, 0.03, 0.03)
        self.pole = tuple(ry(self.twist) @ v(*W.POLE_L))
        s = SUPPORT[gun]
        self.fore = v(*s["grip"])
        self.rest_l = ("gun", self.fore, UPRIGHT if s.get("upright") else CUPPED)
        self.rest_fingers = "foregrip" if s.get("upright") else "support"
        # Down at the belt, for whatever goes into the gun next; and clear of the gun, out to the left.
        self.belt = ("free", v(-0.06, W.EYE_Y - 0.55, -0.16) if fp else v(-0.20, 0.98, -0.08), turn_of((0.9, 0.4, 0.0), (0.0, 0.5, 1.0)))
        self.clear = ("free", v(-0.16, W.EYE_Y - 0.36, -0.30) if fp else v(-0.24, 1.14, -0.20), turn_of((1.0, 0.2, 0.0), (-0.2, -0.4, 1.0)))

    def right(self, by=ZERO, hand=None, cant=None, work=1.0):
        """The right arm, the gun moved `by` from where it is worked on (work=0: from its hold)."""
        off = tuple(float(a * work + b) for a, b in zip(self.work, by))
        return self.W.held(self.gun, self.fp, offset=off, hand=hand, cant=cant)["arm_r"]

    def gun_at(self, arm_r):
        """The gun for that right arm, as the hand holds it: (gun space -> the model's, where its grip is)."""
        turn, place = A._frames(dict(self.base, arm_r=arm_r), "model")["gun"]
        return turn @ GUN_REST, place

    def left(self, t, arm_r, keys):
        """The left arm at time t. keys: [(time, where[, ease])...], `where` ("gun", point, turn)
        on the gun (gun space: it goes with the gun) or ("free", point, turn) in the model's
        space, or a function of time giving one. Returns (the arm, its fist, its turn)."""
        aim, grip = self.gun_at(arm_r)

        def placed(k):
            k = k(t) if callable(k) else k
            pole = v(*(k[3] if len(k) > 3 else self.pole))   # (a fourth: which way the elbow goes, in the model's space)
            return (grip + aim @ k[1], aim @ k[2], pole) if k[0] == "gun" else (k[1], k[2], pole)
        if t <= keys[0][0]:
            p, m, pole = placed(keys[0][1])
        elif t >= keys[-1][0]:
            p, m, pole = placed(keys[-1][1])
        else:
            for i in range(1, len(keys)):
                if t <= keys[i][0]:
                    u = ease((t - keys[i - 1][0]) / (keys[i][0] - keys[i - 1][0]), keys[i][2] if len(keys[i]) > 2 else "smooth")
                    (p0, m0, e0), (p1, m1, e1) = placed(keys[i - 1][1]), placed(keys[i][1])
                    p, m, pole = p0 + (p1 - p0) * u, _slerp_m(m0, m1, u), e0 + (e1 - e0) * u
                    break
        wrist = p + m @ v(0.0, FIST, 0.0)
        return {"ik": tuple(float(x) for x in wrist), "space": "model", "pole": tuple(float(x) for x in pole), "hand": euler_of(m),
                "cant": 0.0}, p, m

    def pose(self, t, keys_r, keys_l, fingers_l, fingers_r="gun", ref=None):
        """The pose at time t, less the gun's parts: (spec, the gun's frame, the left fist, its
        turn). ref: the right arm the gun is where it would be for, if it is out of the hand."""
        spec = dict(self.base)
        spec["arm_r"] = keyed(t, keys_r)
        spec["arm_l"], fist, turn = self.left(t, ref or spec["arm_r"], keys_l)
        spec["fingers_l"] = hand_at(t, fingers_l)
        spec["fingers_r"] = hand_at(t, fingers_r) if not isinstance(fingers_r, str) else fingers_r
        return spec, self.gun_at(ref or spec["arm_r"]), fist, turn

    def let_go(self, spec, ref, turn, pivot):
        """The gun out of the right hand: where it would be held by the arm `ref`, turned
        `turn` (gun space) about `pivot`, wherever the right hand itself has gone."""
        aim0, grip0 = self.gun_at(ref)
        aim, grip = self.gun_at(spec["arm_r"])
        spec["pistol"] = {"pos": tuple(aim.T @ (grip0 + aim0 @ (pivot - turn @ pivot) - grip)), "rot": euler_of(aim.T @ aim0 @ turn)}

    def body(self, spec, t, yaw=None, pitch=None, roll=None):
        """Third person: the chest goes with the reload, on top of the hold's own turn."""
        if self.fp:
            return
        y = at(t, yaw) if yaw else 0.0
        spec["chest"] = (at(t, pitch) if pitch else 0.0, self.twist + y, at(t, roll) if roll else 0.0)
        spec["spine"] = (0.0, y * 0.4, 0.0)


def on_palm(obj, radius, turn):
    """Where the left fist is, for something of that radius lying in its palm with its middle at `obj`."""
    return obj - turn @ (v(0.0, FIST, 0.0) + PALM_L) - turn[:, 0] * radius


def in_palm(fist, turn, radius):
    """The middle of something of that radius lying in the left palm."""
    return fist + turn @ (v(0.0, FIST, 0.0) + PALM_L) + turn[:, 0] * radius


def _put(spec, frame, middle, turn, own):
    S._put(spec, frame[0], frame[1], middle, turn, own)


# ---------------------------------------------------------------------------
# The pump guns: a shell at a time (the clip is one shell; it loops), and the rack that
# ends it once the tube is full.

SHELL = v(0.0, 0.05, -0.035)              # the middle of the shell, seated in the receiver (gun space)
PORT = SHELL + v(0.0, -0.06, 0.005)       # ...and at the loading port under it
SPIN_PIVOT = v(0.0, 0.006, -0.026)        # the trigger finger in the guard: a spun gun turns about it


def _shell_poses(L):
    tilt = L.right((0.0, 0.0, 0.0), (96.0, 10.0, 0.0), -52.0)   # rolled over: the port turned up to the left hand
    took = L.right((0.004, 0.012, 0.0), (99.0, 10.0, 0.0), -57.0)
    flick = L.right((0.0, -0.006, 0.0), (93.0, 9.0, 0.0), -40.0)
    return tilt, took, flick


UNDER = turn_of((0.0, 1.0, 0.0), (-0.8, -0.4, 0.4))   # the left hand coming up under the gun from the left


def shells(gun, fp):
    """One shell: up from the belt in the fingertips, thumbed into the port, and the hand
    flicks away as the gun rocks back from it."""
    L = Long(gun, fp)
    n = L.W.RELOAD[gun] / 0.5   # (written for the shotgun's half second)
    tilt, took, flick = _shell_poses(L)
    keys_r = [(0.0, tilt), (0.2 * n, tilt), (0.27 * n, took, "out"), (0.33 * n, flick, "out"), (0.43 * n, tilt), (0.5 * n, tilt)]

    def holding(shell):
        return ("gun", shell - UNDER @ TIPS, UNDER)
    keys_l = [(0.0, L.belt), (0.2 * n, holding(PORT), "out"), (0.27 * n, holding(SHELL), "in"),
              (0.34 * n, ("gun", PORT + v(-0.07, -0.07, 0.03), UNDER), "out"), (0.5 * n, L.belt)]
    fingers = [(0.0, "pinch"), (0.26 * n, "pinch"), (0.32 * n, "open", "out"), (0.42 * n, "relaxed"), (0.5 * n, "pinch")]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        spec["vent_pos"] = (0.0, 0.006, 0.0)   # the heat shield stands open while the gun is fed
        L.body(spec, t, [(0.0, 0.0), (0.27 * n, 3.0, "out"), (0.5 * n, 0.0)])
        if not 0.27 * n <= t < 0.40 * n:   # in the fingertips (the game hides it while the hand fetches the next)
            _put(spec, frame, fist + turn @ TIPS, np.eye(3), SHELL)
        return spec
    return pose


def shotgun_end(gun, fp):
    """Full: the left hand lets go, the right arm swings out and the gun goes once round the
    right hand, muzzle down first, its pump thrown back and forward again on the way; the
    left hand catches the pump as it comes level."""
    L = Long(gun, fp)
    tilt = _shell_poses(L)[0]
    wind = L.right((0.02, -0.03, 0.0), (84.0, 6.0, 0.0), -10.0)
    out = L.right((0.07 if fp else 0.21, 0.02, -0.07 if fp else -0.02), (92.0, -2.0, 0.0), 0.0)
    top = L.right((0.07 if fp else 0.21, 0.06, -0.07 if fp else -0.02), (97.0, -2.0, 0.0), 0.0)
    catch = L.right((0.0, -0.03, 0.0), (84.0, 5.0, 0.0), work=0.0)
    over = L.right((0.0, 0.008, 0.0), work=0.0)
    rest = L.right(work=0.0)
    keys_r = [(0.0, tilt), (0.10, wind), (0.20, out, "out"), (0.36, top), (0.50, out), (0.57, catch, "in"), (0.64, over, "out"),
              (0.70, rest), (0.75, rest)]
    keys_l = [(0.0, L.belt), (0.16, L.clear, "out"), (0.48, L.clear), (0.62, L.rest_l), (0.75, L.rest_l)]
    fingers_l = [(0.0, "relaxed"), (0.48, "relaxed"), (0.62, L.rest_fingers)]
    fingers_r = [(0.0, "gun"), (0.10, "gun"), (0.18, "trigger", "out"), (0.48, "trigger"), (0.56, "gun", "in")]

    def pose(t):
        spec, _, _, _ = L.pose(t, keys_r, keys_l, fingers_l, fingers_r)
        spec["slide"] = at(t, [(0.0, 0.0), (0.17, 0.0), (0.26, 0.08, "out"), (0.40, 0.08), (0.47, 0.0, "in")])
        spec["vent_pos"] = (0.0, at(t, [(0.0, 0.006), (0.44, 0.006), (0.48, 0.0, "in")]), 0.0)
        S._spin(spec, at(t, [(0.0, 0.0), (0.12, 0.0), (0.20, -70.0, "in"), (0.46, -300.0, "linear"), (0.54, -360.0, "out"), (0.75, -360.0)]),
                pivot=SPIN_PIVOT)
        L.body(spec, t, [(0.0, 0.0), (0.2, 10.0, "out"), (0.5, 6.0), (0.66, -3.0), (0.75, 0.0)], [(0.0, 0.0), (0.3, -4.0), (0.6, 2.0), (0.75, 0.0)])
        return spec
    return pose


# ---------------------------------------------------------------------------
# Break-action (1.7 s). The barrels and fore-end are the gun's vent part: they tip down on
# the hinge (weapons.BREAK_HINGE); the pair of shells is on the magazine bone.

HINGE = v(0.0, BREAK_HINGE[0], -BREAK_HINGE[1])
PAIR = v(0.0, 0.066, -0.16)   # the middle of the pair of shells, seated (gun space)
OPENED = -38.0


def _tipped(point, turn):
    return HINGE + rx(turn) @ (v(*point) - HINGE)


def break_action(gun, fp):
    L = Long(gun, fp)
    rest = L.right(work=0.0)
    lift = L.right((0.0, 0.012, 0.0), (95.0, 3.0, 0.0), work=0.0)
    snap = L.right((0.0, -0.02, 0.0), (74.0, 5.0, 0.0), -4.0, work=0.6)     # the wrist snapped down: the barrels fall open
    show = L.right((0.0, 0.0, 0.02), (90.0, 10.0, 0.0), -14.0)              # the breech offered to the left hand
    took = L.right((0.0, -0.014, 0.014), (86.0, 10.0, 0.0), -14.0)
    wind = L.right((0.0, -0.035, 0.01), (74.0, 6.0, 0.0), -4.0)
    flick = L.right((0.0, 0.05, 0.0), (114.0, 4.0, 0.0), 2.0)               # flicked up: the barrels swing shut
    over = L.right((0.0, -0.014, 0.0), (85.0, 4.0, 0.0), work=0.0)
    keys_r = [(0.0, rest), (0.06, lift), (0.14, snap, "out"), (0.22, L.right((0.0, -0.01, 0.0), (80.0, 6.0, 0.0), -6.0, work=0.8)),
              (0.42, show), (0.74, show), (0.79, took, "out"), (0.88, show), (0.99, wind), (1.08, flick, "out"), (1.20, over),
              (1.32, rest), (1.70, rest)]
    turn_keys = [(0.0, 0.0), (0.08, 0.0), (0.15, OPENED - 7.0, "out"), (0.22, OPENED), (1.02, OPENED), (1.075, 0.0, "in")]

    def fore(t):   # the fore-end goes down with the barrels
        turn = at(t, turn_keys)
        return ("gun", _tipped(L.fore, turn), rx(turn) @ CUPPED)
    into = rx(OPENED) @ v(0.0, 0.0, -1.0)          # the way into the open barrels
    seat = _tipped(PAIR, OPENED)                  # where the pair sits with the barrels open
    behind = turn_of((0.8, -0.6, 0.0), tuple(-into + v(-0.5, 0.1, 0.0)))   # the left hand behind the breech, fingers toward it

    def holding(back):
        return ("gun", seat - into * back - behind @ TIPS, behind)
    keys_l = [(0.0, fore), (0.18, fore), (0.44, L.belt, "in"), (0.66, holding(0.11)), (0.77, holding(0.0), "in"), (0.84, holding(0.07), "out"),
              (0.96, L.clear), (1.12, L.clear), (1.28, fore), (1.70, fore)]
    fingers = [(0.0, "support"), (0.18, "support"), (0.3, "relaxed"), (0.44, "pinch"), (0.77, "pinch"), (0.84, "open", "out"),
               (0.98, "relaxed"), (1.14, "relaxed"), (1.28, "support")]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        tipped = at(t, turn_keys)
        spec["vent"] = tipped
        spec["vent_pivot"] = BREAK_HINGE
        if 0.2 <= t < 0.77:   # the new pair, in the fingertips (the game hides it until the hand has it)
            _put(spec, frame, fist + turn @ TIPS, rx(OPENED), PAIR)
        else:
            spec.update(S._hinged(tipped, BREAK_HINGE))
            if 0.15 <= t < 0.2:   # the empties start back out of the breech (the game's own flying ones take over)
                spec["mag"] = tuple(v(*spec["mag"]) - rx(tipped) @ v(0.0, 0.0, -1.0) * at(t, [(0.15, 0.0), (0.2, 0.1, "linear")]))
        L.body(spec, t, [(0.0, 0.0), (0.15, 5.0, "out"), (0.42, -4.0), (0.8, -7.0), (1.08, 5.0, "out"), (1.32, 0.0)],
               [(0.0, 0.0), (0.15, 6.0, "out"), (0.42, 2.0), (0.99, 4.0), (1.08, -5.0, "out"), (1.32, 0.0)])
        return spec
    return pose


# ---------------------------------------------------------------------------
# Air cannon (1.8 s)

TANK = v(0.0, 0.0, -0.16)   # the middle of the tank, slung under the gun (gun space); it screws in along the barrel
TANK_R = 0.031


def air_cannon(gun, fp):
    L = Long(gun, fp)
    rest = L.right(work=0.0)
    tip = L.right((0.0, 0.0, 0.0), (100.0, 8.0, 0.0), -16.0)
    shake = L.right((0.0, 0.03, 0.0), (104.0, 8.0, 0.0), -20.0)            # jerked up: the loose tank drops away
    low = L.right((0.0, -0.03, 0.0), (86.0, 8.0, 0.0), -10.0)              # down to meet the new one
    took = L.right((0.0, -0.012, 0.0), (91.0, 8.0, 0.0), -12.0)            # it lands in the hand under the gun
    seated = L.right((0.0, 0.016, 0.0), (95.0, 8.0, 0.0), -14.0)           # ...and is driven home
    keys_r = [(0.0, rest), (0.12, tip), (0.33, tip), (0.39, shake, "out"), (0.62, low), (0.94, low), (0.99, took, "out"), (1.22, seated),
              (1.32, tip), (1.58, rest), (1.8, rest)]
    under = turn_of((0.0, 1.0, 0.0), (-0.8, -0.45, 0.35))

    def cradling(obj, twist=0.0):
        m = rz(twist) @ under
        return ("gun", on_palm(obj, TANK_R, m), m)
    loose = TANK + v(0.0, -0.012, 0.03)
    caught = TANK + v(0.0, -0.055, 0.02)
    keys_l = [(0.0, L.rest_l), (0.04, L.rest_l), (0.13, cradling(TANK)), (0.24, cradling(TANK, 34.0)), (0.34, cradling(loose, -20.0)),
              (0.42, cradling(loose + v(-0.04, -0.07, 0.0)), "out"), (0.60, L.belt, "in"), (0.70, cradling(TANK + v(-0.03, -0.30, 0.03))),
              (0.78, cradling(TANK + v(-0.03, -0.20, 0.02)), "out"), (0.90, cradling(caught + v(0.0, -0.04, 0.0))), (0.96, cradling(caught)),
              (1.0, cradling(caught + v(0.0, -0.018, 0.0)), "out"), (1.22, cradling(TANK, 30.0)), (1.30, cradling(TANK + v(0.0, -0.03, 0.0))),
              (1.46, L.rest_l), (1.8, L.rest_l)]
    fingers = [(0.0, L.rest_fingers), (0.04, L.rest_fingers), (0.13, "support"), (0.36, "support"), (0.42, "open", "out"), (0.6, "support"),
               (0.74, "support"), (0.79, "open", "out"), (0.94, "open"), (1.0, "support"), (1.3, "support"), (1.46, L.rest_fingers)]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        aim, grip = frame
        open_ = at(t, [(0.0, 0.0), (0.10, 0.0), (0.15, 1.3, "out"), (0.22, 1.0), (1.26, 1.0), (1.30, 0.0, "in")])
        spec["vent_pos"] = (0.0, 0.004 * open_, 0.012 * open_)
        if t < 0.12 or t >= 1.22:
            pass   # screwed in
        elif t < 0.36:    # spun loose
            u = (t - 0.12) / 0.24
            _put(spec, frame, grip + aim @ (TANK + (loose - TANK) * u), rz(720.0 * ease(u, "in")), TANK)
        elif t < 0.44:    # dropped (the game's own falling tank takes over)
            _put(spec, frame, grip + aim @ (loose + v(-0.3, -0.5, 0.0) * (t - 0.36)), np.eye(3), TANK)
        elif t < 0.78:    # the new one, lying in the left palm
            _put(spec, frame, in_palm(fist, turn, TANK_R), np.eye(3), TANK)
        elif t < 0.96:    # tossed: up in an arc, end over end once, down into the hand waiting under the gun
            u = (t - 0.78) / 0.18
            start = in_palm(*L.left(t, spec["arm_r"], [(0.0, cradling(TANK + v(-0.03, -0.20, 0.02)))])[1:], TANK_R)
            end = grip + aim @ caught
            middle = start + (end - start) * u + v(0.0, 0.09, 0.0) * 4.0 * u * (1.0 - u)
            _put(spec, frame, middle, rx(-360.0 * ease(u)), TANK)
        else:             # spun in as the hand pushes it up
            u = (t - 0.96) / 0.26
            _put(spec, frame, in_palm(fist, turn, TANK_R), rz(-720.0 * (1.0 - ease(u, "out"))), TANK)
        L.body(spec, t, [(0.0, 0.0), (0.39, 6.0, "out"), (0.62, -3.0), (0.99, -6.0), (1.22, 4.0, "out"), (1.58, 0.0)],
               [(0.0, 0.0), (0.39, -5.0, "out"), (0.62, 5.0), (0.99, 6.0), (1.22, -3.0, "out"), (1.58, 0.0)])
        return spec
    return pose


# ---------------------------------------------------------------------------
# Automatics

class Cell:
    """A gun's power cell (or box of ammunition): where it sits, and how the left hand holds it."""
    OFF = v(0.012, 0.0, 0.0)   # from the middle of the fist to the cell in it (the hand's own space)

    def __init__(self, mid, out, half, grab=0.5):
        self.mid, self.out, self.half = v(*mid), norm(v(*out)), half   # its middle seated, the way out (gun space), half its length
        self.grab = self.out * (half * grab)                           # where the fist closes on it, from its middle
        x = v(1.0, 0.0, 0.0)
        self.m0 = np.column_stack([x, np.cross(self.out, x), self.out])   # the left hand's turn holding it (palm on its left, wrist behind)
        self.base = self.mid + self.out * half

    def hold(self, back=0.0, by=ZERO, turn=None):
        """Where the left hand is, holding the cell `back` metres out of its seat (moved `by`, turned `turn`: gun space)."""
        r = np.eye(3) if turn is None else turn
        m = r @ self.m0
        return ("gun", self.mid + self.out * back + v(*by) + r @ self.grab - m @ self.OFF, m)

    def carried(self, fist, turn):
        """The cell in the left hand: (its middle, its turn), in the model's space."""
        rot = turn @ self.m0.T
        return fist + turn @ self.OFF - rot @ self.grab, rot

    def carry(self, spec, frame, fist, turn):
        middle, rot = self.carried(fist, turn)
        _put(spec, frame, middle, frame[0].T @ rot, self.mid)

    def thrown(self, spec, t, t0, far=0.2):
        """The spent cell starting out of the gun (the game's own flying one takes over)."""
        spec["mag"] = tuple(self.out * at(t, [(t0, 0.0), (t0 + 0.07, far, "linear")]))


def _open(t, a, b):
    """0..1: a vent snaps open at `a` (a little too far, and settles) and shut at `b`."""
    return at(t, [(0.0, 0.0), (a - 0.04, 0.0), (a, 1.2, "out"), (a + 0.07, 1.0), (b, 1.0), (b + 0.05, 0.0, "in")])


SIDE = turn_of((1.0, 0.0, 0.0), (-0.55, -0.35, 0.75))   # the left hand on a charging handle on the left of the gun


def racking(handle, t0, t1, travel=0.075):
    """The left hand works a charging handle: hold of it by t0, hauled back by t1, let fly.
    Returns (the slide's keys, the hand on it (a left key), the hand flung clear after)."""
    slide_keys = [(0.0, 0.0), (t0, 0.0), (t1, travel, "out"), (t1 + 0.05, travel), (t1 + 0.10, 0.0, "in")]
    grab = v(*handle) + v(-0.02, 0.0, 0.0)

    def hand(t):
        return ("gun", grab + v(0.0, 0.0, at(min(t, t1 + 0.05), slide_keys)), SIDE)
    return slide_keys, hand, ("gun", grab + v(-0.05, 0.01, travel + 0.04), SIDE)


def smg(gun, fp):
    """The cell is thrown out with a flick of the wrist, a new one pushed up into the well,
    and with the left hand on the foregrip the right lets go: the gun goes once round the
    foregrip like a propeller and the right hand catches the grip again."""
    L = Long(gun, fp)
    C = Cell((0.0, -0.06, -0.085), (0.0, -1.0, 0.0), 0.085)
    rest = L.right(work=0.0)
    wind = L.right((0.0, -0.01, 0.0), (88.0, 4.0, 0.0), -4.0, work=0.0)
    flick = L.right((0.01, 0.03, 0.0), (99.0, 6.0, 0.0), 52.0, work=0.5)     # rolled hard over: the cell is thrown out
    hold = L.right((0.0, 0.0, 0.01), (98.0, 9.0, 0.0), -20.0)
    ready = L.right((0.0, 0.01, 0.01), (100.0, 9.0, 0.0), -23.0)
    knock = L.right((0.0, 0.04, 0.005), (104.0, 8.0, 0.0), -16.0)
    level = L.right((0.0, 0.0, -0.02 if fp else -0.07), (90.0, 3.0, 0.0), 0.0, work=0.6)   # held level (and clear of the chest), for the spin
    away = L.right((0.07, -0.13, 0.12), (62.0, 0.0, 0.0), 0.0, work=0.6)      # the right hand out of the way of it
    over = L.right((0.0, 0.006, 0.0), work=0.0)
    keys_r = [(0.0, rest), (0.05, wind), (0.12, flick, "out"), (0.30, hold), (0.60, ready), (0.70, ready), (0.75, knock, "out"),
              (0.88, level), (0.93, level), (1.02, away, "out"), (1.22, away), (1.32, level, "in"), (1.42, over), (1.50, rest), (1.6, rest)]
    keys_l = [(0.0, L.rest_l), (0.10, L.rest_l), (0.34, L.belt, "in"), (0.56, C.hold(0.2)), (0.70, C.hold(0.0), "in"), (0.86, L.rest_l),
              (1.6, L.rest_l)]
    fingers_l = [(0.0, "foregrip"), (0.10, "foregrip"), (0.2, "relaxed"), (0.34, "foregrip"), (0.70, "foregrip"), (0.76, "open", "out"),
                 (0.86, "foregrip")]
    fingers_r = [(0.0, "gun"), (0.91, "gun"), (0.97, "open", "out"), (1.25, "open"), (1.32, "gun", "in")]

    def pose(t):
        out = 0.88 <= t <= 1.32
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers_l, fingers_r, ref=level if out else None)
        if out:
            L.let_go(spec, level, ry(at(t, [(0.9, 0.0), (0.99, 50.0, "in"), (1.21, 310.0, "linear"), (1.30, 360.0, "out")])), L.fore)
        spec["vent_pos"] = (0.0, 0.0, -0.012 * _open(t, 0.12, 0.72))
        if 0.09 <= t < 0.16:
            C.thrown(spec, t, 0.09)
        elif 0.16 <= t < 0.70:
            C.carry(spec, frame, fist, turn)
        L.body(spec, t, [(0.0, 0.0), (0.12, 6.0, "out"), (0.4, 0.0), (0.75, -6.0, "in"), (1.0, 4.0), (1.32, -3.0), (1.5, 0.0)],
               [(0.0, 0.0), (0.12, -4.0, "out"), (0.4, 0.0), (0.75, -3.0), (1.1, 2.0), (1.5, 0.0)])
        return spec
    return pose


def rifle(gun, fp):
    """The cell is shaken out, the new one is tossed up end over end and caught again on its
    way to the gun, pushed home, and the charging handle is raked back with a sweep of the arm."""
    L = Long(gun, fp)
    C = Cell((0.0, -0.095, -0.10), (0.0, -0.97, -0.23), 0.1)
    rest = L.right(work=0.0)
    dip = L.right((0.0, -0.014, 0.0), (86.0, 4.0, 0.0), work=0.0)
    jerk = L.right((0.0, 0.035, 0.0), (106.0, 6.0, 0.0), -14.0, work=0.6)
    hold = L.right((0.0, 0.0, 0.01), (98.0, 9.0, 0.0), -22.0)
    ready = L.right((0.0, 0.012, 0.01), (100.0, 9.0, 0.0), -25.0)
    knock = L.right((0.0, 0.04, 0.005), (104.0, 8.0, 0.0), -18.0)
    level = L.right((0.0, 0.0, 0.0), (91.0, 7.0, 0.0), -8.0, work=0.7)
    yank = L.right((0.0, 0.0, 0.03), (93.0, 7.0, 0.0), -10.0, work=0.7)
    slam = L.right((0.0, -0.006, -0.02), (88.0, 6.0, 0.0), -4.0, work=0.7)
    keys_r = [(0.0, rest), (0.06, dip), (0.14, jerk, "out"), (0.30, hold), (0.6, hold), (0.86, ready), (1.07, ready), (1.12, knock, "out"),
              (1.24, hold), (1.36, level), (1.48, yank, "out"), (1.58, slam, "out"), (1.70, level), (1.82, rest), (1.9, rest)]
    slide_keys, on_handle, flung = racking((-0.036, 0.07, -0.13), 1.36, 1.48)
    low = C.hold(0.20, (-0.12, 0.0, 0.0))     # (out to the left of the gun, where the toss can be seen)
    high = C.hold(0.13, (-0.12, 0.0, 0.0))
    keys_l = [(0.0, L.rest_l), (0.08, L.rest_l), (0.40, L.belt, "in"), (0.55, low), (0.62, high, "out"), (0.74, low), (0.86, high),
              (0.98, C.hold(0.16)), (1.10, C.hold(0.0), "in"), (1.20, C.hold(0.03)), (1.36, on_handle), (1.52, on_handle), (1.64, flung, "out"),
              (1.82, L.rest_l), (1.9, L.rest_l)]
    fingers = [(0.0, "support"), (0.08, "support"), (0.25, "relaxed"), (0.40, "foregrip"), (0.60, "foregrip"), (0.64, "open", "out"),
               (0.84, "open"), (0.88, "foregrip"), (1.10, "foregrip"), (1.18, "open"), (1.36, "foregrip"), (1.52, "foregrip"),
               (1.60, "open", "out"), (1.72, "relaxed"), (1.82, "support")]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        spec["slide"] = at(t, slide_keys)
        open_ = _open(t, 0.14, 1.12)
        spec["vent_pos"] = (0.0, 0.004 * open_, 0.008 * open_)
        if 0.11 <= t < 0.18:
            C.thrown(spec, t, 0.11)
        elif 0.62 <= t < 0.86:   # tossed: up end over end, and back into the hand
            u = (t - 0.62) / 0.24
            (m0, r0), (m1, r1) = [C.carried(*L.left(t, spec["arm_r"], [(0.0, k)])[1:]) for k in (high, high)]
            middle = m0 + (m1 - m0) * u + v(0.0, 0.18, 0.0) * 4.0 * u * (1.0 - u)
            _put(spec, frame, middle, frame[0].T @ r0 @ rx(-360.0 * u), C.mid)
        elif 0.18 <= t < 1.10:
            C.carry(spec, frame, fist, turn)
        L.body(spec, t, [(0.0, 0.0), (0.14, 6.0, "out"), (0.5, 2.0), (1.12, -8.0, "in"), (1.48, -4.0), (1.58, 5.0, "out"), (1.82, 0.0)],
               [(0.0, 0.0), (0.14, -5.0, "out"), (0.5, 0.0), (1.12, -4.0), (1.48, 0.0), (1.58, 4.0, "out"), (1.82, 0.0)])
        return spec
    return pose


def burst_rifle(gun, fp):
    """The new cell comes up beside the old one and knocks it out of the gun on its way in;
    the handle at the back is racked, and the gun is rolled up off the shoulders and settled."""
    L = Long(gun, fp)
    C = Cell((0.0, -0.045, -0.10), (0.0, -0.99, -0.139), 0.07)
    rest = L.right(work=0.0)
    hold = L.right((0.0, 0.0, 0.01), (97.0, 9.0, 0.0), -18.0)
    struck = L.right((0.02, 0.006, 0.01), (97.0, 7.0, 0.0), -12.0)
    knock = L.right((0.0, 0.04, 0.005), (103.0, 8.0, 0.0), -14.0)
    level = L.right((0.0, 0.0, 0.0), (91.0, 7.0, 0.0), -8.0, work=0.7)
    yank = L.right((0.0, 0.0, 0.03), (93.0, 7.0, 0.0), -10.0, work=0.7)
    slam = L.right((0.0, -0.006, -0.02), (88.0, 6.0, 0.0), -4.0, work=0.7)
    up = L.right((0.0, 0.07, 0.05), (106.0, 8.0, 0.0), -34.0, work=0.5)       # rolled up and back off the shoulder...
    drop = L.right((0.0, -0.02, 0.0), (84.0, 4.0, 0.0), work=0.0)            # ...and dropped back into the hold
    keys_r = [(0.0, rest), (0.30, hold), (0.57, hold), (0.62, struck, "out"), (0.72, hold), (0.82, hold), (0.87, knock, "out"), (0.96, hold),
              (1.06, level), (1.20, yank, "out"), (1.30, slam, "out"), (1.46, up), (1.62, drop, "in"), (1.76, rest), (2.0, rest)]
    slide_keys, on_handle, flung = racking((-0.036, 0.075, 0.02), 1.08, 1.20)
    keys_l = [(0.0, L.rest_l), (0.06, L.rest_l), (0.32, L.belt, "in"), (0.54, C.hold(0.03, (-0.10, -0.02, 0.0))),
              (0.61, C.hold(0.05, (-0.025, 0.0, 0.0)), "in"), (0.72, C.hold(0.16)), (0.84, C.hold(0.0), "in"), (0.94, C.hold(0.04)),
              (1.08, on_handle), (1.24, on_handle), (1.36, ("gun", v(-0.14, 0.03, 0.02), SIDE), "out"), (1.62, L.rest_l), (2.0, L.rest_l)]
    fingers = [(0.0, "support"), (0.06, "support"), (0.2, "relaxed"), (0.32, "foregrip"), (0.84, "foregrip"), (0.92, "open"), (1.08, "foregrip"),
               (1.24, "foregrip"), (1.32, "open", "out"), (1.46, "relaxed"), (1.62, "support")]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        spec["slide"] = at(t, slide_keys)
        aim, grip = frame
        if 0.2 <= t < 0.84:   # the new cell (the gun's spare: it does not turn) in the left hand
            spec["vent_pos"] = tuple(aim.T @ (C.carried(fist, turn)[0] - grip) - C.mid)
        if 0.61 <= t < 0.84:  # the old one, knocked out sideways (the game's own flying one takes over)
            spec["mag"] = tuple(v(0.25, -0.5, 0.0) * min(t - 0.61, 0.1))
        L.body(spec, t, [(0.0, 0.0), (0.3, 3.0), (0.62, -6.0, "in"), (0.87, -8.0), (1.2, -3.0), (1.3, 5.0, "out"), (1.46, 8.0), (1.62, -4.0, "in"),
                         (1.8, 0.0)],
               [(0.0, 0.0), (0.62, 2.0), (0.87, -3.0), (1.3, 3.0), (1.46, -8.0), (1.62, 5.0, "in"), (1.8, 0.0)],
               [(0.0, 0.0), (1.3, 0.0), (1.46, 9.0), (1.62, -4.0, "in"), (1.8, 0.0)])
        return spec
    return pose


def battle_rifle(gun, fp):
    """The heavy cell is hauled out by hand and flung aside, the new one is set in the well
    and driven home with the flat of the palm, and the gun is tipped up to rack it."""
    L = Long(gun, fp)
    C = Cell((0.0, -0.04, -0.09), (0.0, -1.0, 0.0), 0.065)
    rest = L.right(work=0.0)
    brace = L.right((0.0, 0.0, 0.0), (94.0, 6.0, 0.0), -10.0, work=0.5)
    hauled = L.right((0.0, -0.045, 0.0), (88.0, 6.0, 0.0), -14.0, work=0.5)
    sprung = L.right((0.0, 0.02, 0.0), (97.0, 7.0, 0.0), -8.0, work=0.5)
    hold = L.right((0.0, 0.0, 0.01), (98.0, 9.0, 0.0), -20.0)
    slammed = L.right((0.0, 0.05, 0.005), (105.0, 8.0, 0.0), -14.0)
    far = -0.04 if fp else 0.0   # (in first person, held further off: it fills the view)
    tipped = L.right((0.0, 0.04, 0.06 + far), (128.0 if fp else 138.0, 10.0, 0.0), -6.0)   # muzzle up, to rack it
    yank = L.right((0.0, 0.02, 0.075 + far), (131.0 if fp else 141.0, 10.0, 0.0), -8.0)
    slam = L.right((0.0, 0.05, 0.05 + far), (124.0 if fp else 134.0, 9.0, 0.0), -4.0)
    over = L.right((0.0, -0.016, 0.0), (85.0, 4.0, 0.0), work=0.0)
    keys_r = [(0.0, rest), (0.14, brace), (0.24, brace), (0.31, hauled, "out"), (0.42, sprung), (0.62, hold), (1.07, hold), (1.12, slammed, "out"),
              (1.24, hold), (1.42, tipped), (1.56, yank, "out"), (1.66, slam, "out"), (1.76, tipped), (1.92, over, "in"), (2.0, rest), (2.1, rest)]
    slide_keys, on_handle, flung = racking((-0.037, 0.07, -0.12), 1.44, 1.56)
    up = turn_of((0.0, 1.0, 0.0), (-0.8, -0.45, 0.35))   # the palm up under the cell's base

    def palm(below):
        return ("gun", on_palm(C.base - v(0.0, below, 0.0), 0.0, up), up)
    keys_l = [(0.0, L.rest_l), (0.04, L.rest_l), (0.17, C.hold(0.0)), (0.24, C.hold(0.0)), (0.32, C.hold(0.24), "out"),
              (0.40, C.hold(0.30, (-0.20, -0.02, 0.06)), "out"), (0.62, L.belt, "in"), (0.84, C.hold(0.2)), (0.96, C.hold(0.06), "in"),
              (1.04, palm(0.19)), (1.11, palm(0.06), "in"), (1.20, palm(0.05)), (1.44, on_handle), (1.60, on_handle), (1.72, flung, "out"),
              (1.94, L.rest_l), (2.1, L.rest_l)]
    fingers = [(0.0, "support"), (0.04, "support"), (0.17, "foregrip"), (0.36, "foregrip"), (0.42, "open", "out"), (0.62, "foregrip"),
               (0.96, "foregrip"), (1.02, "flat"), (1.2, "flat"), (1.44, "foregrip"), (1.60, "foregrip"), (1.68, "open", "out"),
               (1.82, "relaxed"), (1.94, "support")]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        spec["slide"] = at(t, slide_keys)
        open_ = _open(t, 0.30, 1.12)
        spec["vent_pos"] = (0.0, 0.004 * open_, 0.01 * open_)
        if 0.17 <= t < 0.96:      # the old one, hauled out in the hand (the game throws it, and hides this until the new one is in the hand)
            C.carry(spec, frame, fist, turn)
        elif 0.96 <= t < 1.11:    # sat in the well, until the palm drives it home
            spec["mag"] = tuple(C.out * at(t, [(0.96, 0.06), (1.05, 0.06), (1.11, 0.0, "in")]))
        L.body(spec, t, [(0.0, 0.0), (0.31, -8.0, "out"), (0.42, 4.0), (0.7, 0.0), (1.12, -8.0, "in"), (1.42, -2.0), (1.56, -6.0), (1.66, 5.0, "out"),
                         (2.0, 0.0)],
               [(0.0, 0.0), (0.31, 7.0, "out"), (0.42, -2.0), (0.7, 0.0), (1.12, -5.0, "in"), (1.42, -6.0), (1.66, -3.0), (2.0, 0.0)])
        return spec
    return pose


def nail_gun(gun, fp):
    """The spent strip is flicked out of the bottom, a new one is pushed up most of the way,
    and the gun is swung down and knocked on the thigh to seat it."""
    L = Long(gun, fp)
    C = Cell((0.0, -0.03, -0.18), (0.0, -1.0, 0.0), 0.015, grab=0.0)
    rest = L.right(work=0.0)
    flick = L.right((0.0, -0.02, 0.0), (72.0, 6.0, 0.0), 30.0, work=0.4)
    hold = L.right((0.0, 0.0, 0.01), (94.0, 10.0, 0.0), -18.0)
    took = L.right((0.0, 0.025, 0.01), (98.0, 10.0, 0.0), -16.0)
    # Swung down beside the thigh (in first person, only as far as the bottom of the view).
    if fp:
        down = L.right((0.02, -0.01, 0.03), (70.0, 4.0, 0.0), 4.0, work=0.0)
        tap = L.right((0.015, -0.035, 0.04), (66.0, 4.0, 0.0), 4.0, work=0.0)
        sprung = L.right((0.02, 0.0, 0.02), (74.0, 4.0, 0.0), 4.0, work=0.0)
    else:
        down = L.right((0.03, -0.15, 0.10), (62.0, 4.0, 0.0), 4.0, work=0.0)
        tap = L.right((0.02, -0.19, 0.11), (58.0, 4.0, 0.0), 4.0, work=0.0)
        sprung = L.right((0.03, -0.14, 0.09), (66.0, 4.0, 0.0), 4.0, work=0.0)
    keys_r = [(0.0, rest), (0.05, L.right((0.0, 0.01, 0.0), (94.0, 4.0, 0.0), work=0.0)), (0.12, flick, "out"), (0.32, hold), (0.78, hold),
              (0.86, took, "out"), (0.94, hold), (1.08, down), (1.16, tap, "in"), (1.26, sprung, "out"), (1.6, rest), (2.0, rest)]
    keys_l = [(0.0, L.rest_l), (0.08, L.rest_l), (0.40, L.belt, "in"), (0.64, C.hold(0.2)), (0.84, C.hold(0.045), "in"),
              (0.94, C.hold(0.10, (-0.03, 0.0, 0.0)), "out"), (1.06, L.rest_l), (2.0, L.rest_l)]
    fingers = [(0.0, "foregrip"), (0.08, "foregrip"), (0.24, "relaxed"), (0.40, "foregrip"), (0.84, "foregrip"), (0.92, "open", "out"),
               (1.06, "foregrip")]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        open_ = _open(t, 0.12, 1.16)
        spec["vent_pos"] = (0.0, 0.004 * open_, 0.01 * open_)
        if 0.09 <= t < 0.16:
            C.thrown(spec, t, 0.09)
        elif 0.16 <= t < 0.84:
            C.carry(spec, frame, fist, turn)
        elif t < 1.17:   # most of the way in, until the knock
            spec["mag"] = tuple(C.out * at(t, [(0.84, 0.045), (1.14, 0.045), (1.17, 0.0, "in")]))
        L.body(spec, t, [(0.0, 0.0), (0.12, 5.0, "out"), (0.4, 0.0), (0.86, -5.0, "in"), (1.16, 8.0), (1.6, 0.0)],
               [(0.0, 0.0), (0.12, 5.0, "out"), (0.4, 0.0), (1.08, 8.0), (1.16, 13.0, "in"), (1.26, 9.0, "out"), (1.6, 0.0)])
        return spec
    return pose


LID_UP = turn_of((0.0, 1.0, 0.0), (-0.7, -0.5, 0.5))        # the left palm up, under the back edge of a top cover
LID_DOWN = turn_of((0.0, -1.0, 0.0), (-0.8, 0.35, 0.5))     # ...and down, on top of it
ACROSS = turn_of((0.0, -1.0, 0.0), (-1.0, 0.3, 0.15))       # the forearm lying across the top of the gun
ELBOW_UP = (-0.5, 0.7, 0.5)


def lmg(gun, fp):
    """The top cover is knocked open from underneath, the empty box is hauled off and flung
    aside, a new one is hung, and the cover is smashed shut with the forearm."""
    L = Long(gun, fp)
    C = Cell((0.0, -0.04, -0.12), (0.0, -1.0, 0.0), 0.055, grab=0.3)
    cover = (0.095, 0.16)
    lid = v(0.0, 0.088, 0.03)       # the back edge of the cover
    rest = L.right(work=0.0)
    hold = L.right((0.0, 0.0, 0.0), (96.0, 8.0, 0.0), -14.0, work=0.8)
    pop = L.right((0.0, 0.02, 0.0), (99.0, 8.0, 0.0), -12.0, work=0.8)
    hauled = L.right((0.0, -0.04, 0.0), (91.0, 8.0, 0.0), -16.0, work=0.8)
    hung = L.right((0.0, 0.04, 0.0), (101.0, 8.0, 0.0), -10.0, work=0.8)
    level = L.right((0.0, 0.0, 0.0), (90.0, 6.0, 0.0), -4.0, work=0.6)
    smashed = L.right((0.0, -0.06, 0.0), (83.0, 6.0, 0.0), -2.0, work=0.6)
    keys_r = [(0.0, rest), (0.26, hold), (0.32, pop, "out"), (0.46, hold), (0.82, hold), (0.90, hauled, "out"), (1.05, hold), (1.74, hold),
              (1.80, hung, "out"), (1.95, hold), (2.3, level), (2.5, level), (2.56, smashed, "in"), (2.72, level, "out"), (3.1, rest), (3.6, rest)]
    keys_l = [(0.0, L.rest_l), (0.08, L.rest_l), (0.25, ("gun", lid + v(-0.02, -0.07, 0.03), LID_UP)), (0.31, ("gun", lid + v(-0.02, 0.0, 0.02), LID_UP), "in"),
              (0.40, ("gun", lid + v(-0.09, -0.01, 0.03), LID_UP), "out"), (0.64, C.hold(0.0)), (0.80, C.hold(0.0)), (0.90, C.hold(0.2), "out"),
              (1.0, C.hold(0.28, (-0.22, 0.0, 0.05)), "out"), (1.35, L.belt, "in"), (1.6, C.hold(0.22)), (1.8, C.hold(0.0), "in"),
              (1.92, C.hold(0.05)), (2.34, ("gun", v(0.09, 0.25, -0.07), ACROSS, ELBOW_UP)), (2.48, ("gun", v(0.09, 0.27, -0.07), ACROSS, ELBOW_UP)),
              (2.56, ("gun", v(0.12, 0.12, -0.07), ACROSS, ELBOW_UP), "in"), (2.72, ("gun", v(0.10, 0.17, -0.07), ACROSS, ELBOW_UP), "out"),
              (3.1, L.rest_l), (3.6, L.rest_l)]
    fingers = [(0.0, "support"), (0.08, "support"), (0.22, "flat"), (0.42, "flat"), (0.64, "foregrip"), (0.96, "foregrip"), (1.02, "open", "out"),
               (1.35, "foregrip"), (1.8, "foregrip"), (1.9, "open"), (2.3, "fist"), (2.75, "fist"), (3.1, "support")]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        spec["slide_pivot"] = cover
        spec["slide_pitch"] = at(t, [(0.0, 0.0), (0.28, 0.0), (0.35, -76.0, "out"), (0.44, -62.0), (2.5, -62.0), (2.56, 0.0, "in")])
        spec["vent_pos"] = (0.0, 0.0, -0.02 * _open(t, 0.34, 2.52))
        if 0.64 <= t < 1.8:
            C.carry(spec, frame, fist, turn)
        L.body(spec, t, [(0.0, 0.0), (0.32, 4.0, "out"), (0.9, -6.0, "out"), (1.05, 2.0), (1.8, -7.0, "in"), (2.3, 6.0), (2.56, -9.0, "in"), (3.1, 0.0)],
               [(0.0, 0.0), (0.32, -3.0, "out"), (0.9, 6.0, "out"), (1.05, 0.0), (1.8, -4.0, "in"), (2.3, -6.0), (2.56, 9.0, "in"), (3.1, 0.0)])
        return spec
    return pose


def minigun(gun, fp):
    """The lid is knocked open, the empty box hauled off and flung aside, a new one hung,
    the lid slapped shut; and as it locks the barrels spin up and run down, the gun shaking."""
    from weapons import MINIGUN_AXIS
    L = Long(gun, fp)
    C = Cell((0.0, -0.05, -0.12), (0.0, -1.0, 0.0), 0.05, grab=0.3)
    cover = (0.1, 0.13)
    lid = v(0.0, 0.092, 0.01)
    top = v(0.0, 0.112, -0.06)
    rest = L.right(work=0.0)
    hold = L.right((0.0, 0.0, 0.0), (96.0, 8.0, 0.0), -12.0, work=0.7)
    pop = L.right((0.0, 0.02, 0.0), (99.0, 8.0, 0.0), -10.0, work=0.7)
    hauled = L.right((0.0, -0.04, 0.0), (91.0, 8.0, 0.0), -14.0, work=0.7)
    hung = L.right((0.0, 0.04, 0.0), (101.0, 8.0, 0.0), -8.0, work=0.7)
    level = L.right((0.0, 0.0, 0.0), (90.0, 6.0, 0.0), -4.0, work=0.5)
    slapped = L.right((0.0, -0.035, 0.0), (85.0, 6.0, 0.0), -2.0, work=0.5)
    keys_r = [(0.0, rest), (0.40, hold), (0.48, pop, "out"), (0.62, hold), (0.92, hold), (1.0, hauled, "out"), (1.18, hold), (2.13, hold),
              (2.20, hung, "out"), (2.36, hold), (2.6, level), (2.68, level), (2.74, slapped, "in"), (2.88, level, "out"), (3.1, rest), (4.5, rest)]

    def flat_on(height):
        return ("gun", on_palm(top + v(0.0, height, 0.0), 0.0, LID_DOWN), LID_DOWN)
    keys_l = [(0.0, L.rest_l), (0.16, L.rest_l), (0.40, ("gun", lid + v(-0.02, -0.07, 0.03), LID_UP)), (0.47, ("gun", lid + v(-0.02, 0.0, 0.02), LID_UP), "in"),
              (0.56, ("gun", lid + v(-0.09, -0.01, 0.03), LID_UP), "out"), (0.78, C.hold(0.0)), (0.90, C.hold(0.0)), (1.0, C.hold(0.2), "out"),
              (1.12, C.hold(0.28, (-0.22, 0.0, 0.05)), "out"), (1.5, L.belt, "in"), (1.95, C.hold(0.22)), (2.2, C.hold(0.0), "in"),
              (2.32, C.hold(0.05)), (2.62, flat_on(0.16)), (2.74, flat_on(0.0), "in"), (2.86, flat_on(0.05), "out"), (3.1, L.rest_l), (4.5, L.rest_l)]
    fingers = [(0.0, "foregrip"), (0.16, "foregrip"), (0.36, "flat"), (0.58, "flat"), (0.78, "foregrip"), (1.08, "foregrip"), (1.14, "open", "out"),
               (1.5, "foregrip"), (2.2, "foregrip"), (2.3, "open"), (2.54, "flat"), (2.88, "flat"), (3.1, "foregrip")]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        spec["slide_pivot"] = cover
        spec["slide_pitch"] = at(t, [(0.0, 0.0), (0.44, 0.0), (0.51, -76.0, "out"), (0.60, -62.0), (2.68, -62.0), (2.74, 0.0, "in")])
        spec["vent_pivot"] = MINIGUN_AXIS
        spec["vent_roll"] = at(t, [(0.0, 0.0), (2.85, 0.0), (3.3, 170.0, "in"), (3.8, 540.0, "linear"), (4.3, 720.0, "out"), (4.5, 720.0)])
        if 0.78 <= t < 2.2:
            C.carry(spec, frame, fist, turn)
        # It shakes as the barrels run.
        shake = at(t, [(0.0, 0.0), (2.95, 0.0), (3.3, 1.0), (3.85, 1.0), (4.3, 0.0)]) * 0.0035
        if shake > 0.0:
            arm = dict(spec["arm_r"])
            arm["ik"] = tuple(a + b for a, b in zip(arm["ik"], (shake * np.sin(t * 88.0), shake * np.sin(t * 131.0 + 1.0), 0.0)))
            spec["arm_r"] = arm
            spec["arm_l"] = L.left(t, arm, keys_l)[0]
        L.body(spec, t, [(0.0, 0.0), (0.48, 4.0, "out"), (1.0, -6.0, "out"), (1.18, 2.0), (2.2, -7.0, "in"), (2.62, 4.0), (2.74, -5.0, "in"), (3.1, 0.0)],
               [(0.0, 0.0), (0.48, -3.0, "out"), (1.0, 6.0, "out"), (1.18, 0.0), (2.2, -4.0, "in"), (2.62, -3.0), (2.74, 5.0, "in"), (3.1, 0.0)])
        return spec
    return pose


# ---------------------------------------------------------------------------
# Precision

def bolt_work(knob, grab, up, back0, back1, fwd0, fwd1, down0, down1, travel=0.09, axis=0.06):
    """The left hand works a bolt on the left of the gun: on its knob by `grab`, turned up
    by `up`, drawn back over back0..back1, home over fwd0..fwd1, down over down0..down1.
    Returns (the bolt's turn keys, its travel keys, the hand on the knob (a left key))."""
    turn_keys = [(0.0, 0.0), (grab, 0.0), (up, -70.0, "out"), (down0, -70.0), (down1, 0.0, "in")]
    slide_keys = [(0.0, 0.0), (back0, 0.0), (back1, travel, "out"), (fwd0, travel), (fwd1, 0.0, "in")]
    c = v(0.0, axis, 0.0)
    k = v(*knob) + v(-0.02, 0.0, 0.0)

    def hand(t):
        a = at(t, turn_keys)
        return ("gun", c + rz(a) @ (k - c) + v(0.0, 0.0, at(t, slide_keys)), rz(a * 0.4) @ SIDE)
    return turn_keys, slide_keys, hand


GATE = turn_of((1.0, 0.0, 0.0), (-0.5, -0.5, 0.7))   # the left hand at a loading gate on the gun's left side
LEVER_ROUND = v(0.0, 0.055, -0.04)                  # the lever-action's round, seated (gun space)
LEVER_PIN = (-0.012, 0.065)
LEVER_LOOP = v(0.0, -0.035, -0.014)                 # the middle of the lever's loop: a spun gun turns about the hand in it


def _lever_tilt(L):
    return L.right((0.0, 0.0, 0.0), (95.0, 12.0, 0.0), -46.0)   # rolled over: the gate turned up to the left hand


def lever_rounds(gun, fp):
    """One round: up from the belt in the fingertips and thumbed in through the gate."""
    L = Long(gun, fp)
    n = L.W.RELOAD[gun] / 0.45
    tilt = _lever_tilt(L)
    took = L.right((0.008, 0.004, 0.0), (95.0, 11.0, 0.0), -42.0)
    keys_r = [(0.0, tilt), (0.19 * n, tilt), (0.26 * n, took, "out"), (0.36 * n, tilt), (0.45 * n, tilt)]

    def holding(p):
        return ("gun", p - GATE @ TIPS, GATE)
    gate = LEVER_ROUND + v(-0.05, 0.0, 0.0)
    keys_l = [(0.0, L.belt), (0.19 * n, holding(gate), "out"), (0.26 * n, holding(LEVER_ROUND + v(-0.018, 0.0, 0.0)), "in"),
              (0.33 * n, ("gun", gate + v(-0.06, -0.05, 0.04), GATE), "out"), (0.45 * n, L.belt)]
    fingers = [(0.0, "pinch"), (0.25 * n, "pinch"), (0.31 * n, "open", "out"), (0.39 * n, "relaxed"), (0.45 * n, "pinch")]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        spec["slide_pivot"] = LEVER_PIN
        spec["slide_pitch"] = 0.0
        spec["vent_pos"] = (0.0, 0.006, 0.0)
        L.body(spec, t, [(0.0, 0.0), (0.26 * n, 3.0, "out"), (0.45 * n, 0.0)])
        if not 0.26 * n <= t < 0.37 * n:
            _put(spec, frame, fist + turn @ TIPS, np.eye(3), LEVER_ROUND)
        return spec
    return pose


def lever_end(gun, fp):
    """Full: the left hand lets go and the rifle is spun once forward round the hand in the
    lever's loop, the lever thrown open and shut by the swing; the left hand catches the fore-end."""
    L = Long(gun, fp)
    tilt = _lever_tilt(L)
    wind = L.right((0.02, -0.03, 0.0), (84.0, 6.0, 0.0), -10.0)
    out = L.right((0.07 if fp else 0.22, 0.02, -0.07 if fp else -0.02), (92.0, -2.0, 0.0), 0.0)
    top = L.right((0.07 if fp else 0.22, 0.06, -0.07 if fp else -0.02), (97.0, -2.0, 0.0), 0.0)
    catch = L.right((0.0, -0.03, 0.0), (84.0, 5.0, 0.0), work=0.0)
    over = L.right((0.0, 0.008, 0.0), work=0.0)
    rest = L.right(work=0.0)
    keys_r = [(0.0, tilt), (0.10, wind), (0.20, out, "out"), (0.34, top), (0.47, out), (0.54, catch, "in"), (0.61, over, "out"),
              (0.67, rest), (0.7, rest)]
    keys_l = [(0.0, L.belt), (0.16, L.clear, "out"), (0.45, L.clear), (0.59, L.rest_l), (0.7, L.rest_l)]
    fingers_l = [(0.0, "relaxed"), (0.45, "relaxed"), (0.59, L.rest_fingers)]
    fingers_r = [(0.0, "gun"), (0.10, "gun"), (0.18, "trigger", "out"), (0.45, "trigger"), (0.53, "gun", "in")]

    def pose(t):
        spec, _, _, _ = L.pose(t, keys_r, keys_l, fingers_l, fingers_r)
        spec["slide_pivot"] = LEVER_PIN
        spec["slide_pitch"] = at(t, [(0.0, 0.0), (0.16, 0.0), (0.25, 52.0, "out"), (0.38, 52.0), (0.45, 0.0, "in")])
        spec["vent_pos"] = (0.0, at(t, [(0.0, 0.006), (0.42, 0.006), (0.46, 0.0, "in")]), 0.0)
        S._spin(spec, at(t, [(0.0, 0.0), (0.12, 0.0), (0.20, -70.0, "in"), (0.43, -300.0, "linear"), (0.51, -360.0, "out"), (0.7, -360.0)]),
                pivot=LEVER_LOOP)
        L.body(spec, t, [(0.0, 0.0), (0.2, 10.0, "out"), (0.47, 6.0), (0.62, -3.0), (0.7, 0.0)], [(0.0, 0.0), (0.3, -4.0), (0.56, 2.0), (0.7, 0.0)])
        return spec
    return pose


BOLT_ROUND = v(0.0, 0.07, -0.0525)   # the bolt-action's round (its vent part), seated in the action


def _bolt_work_pose(L):
    """The open action turned toward the left hand (in first person kept low and out: the hand
    over it would otherwise fill the view)."""
    if L.fp:
        return L.right((0.0, -0.03, -0.05), (92.0, 8.0, 0.0), 18.0, work=0.3)
    return L.right((0.0, 0.0, 0.0), (96.0, 10.0, 0.0), 22.0)


def bolt_rounds(gun, fp):
    """One round, the bolt standing open: brought down over the action and pressed in with the thumb."""
    L = Long(gun, fp)
    n = L.W.RELOAD[gun] / 0.5
    work = _bolt_work_pose(L)
    pressed = dict(work, ik=tuple(x + y for x, y in zip(work["ik"], (0.0, -0.014, 0.0))))
    keys_r = [(0.0, work), (0.22 * n, work), (0.29 * n, pressed, "out"), (0.40 * n, work), (0.5 * n, work)]

    def holding(p):
        return ("gun", p - LID_DOWN @ TIPS, LID_DOWN)
    keys_l = [(0.0, L.belt), (0.20 * n, holding(BOLT_ROUND + v(0.0, 0.07, 0.0)), "out"), (0.28 * n, holding(BOLT_ROUND + v(0.0, 0.03, 0.0)), "in"),
              (0.36 * n, holding(BOLT_ROUND + v(-0.04, 0.10, 0.02)), "out"), (0.5 * n, L.belt)]
    fingers = [(0.0, "pinch"), (0.26 * n, "pinch"), (0.32 * n, "open", "out"), (0.42 * n, "relaxed"), (0.5 * n, "pinch")]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        spec["slide_turn"] = -70.0
        spec["slide"] = 0.09
        aim, grip = frame
        if t < 0.26 * n:      # in the fingertips
            spec["vent_pos"] = tuple(aim.T @ (fist + turn @ TIPS - grip) - BOLT_ROUND)
        elif t < 0.30 * n:    # thumbed down into the action
            spec["vent_pos"] = (0.0, 0.03 * (1.0 - (t - 0.26 * n) / (0.04 * n)), 0.0)
        L.body(spec, t, [(0.0, 0.0), (0.29 * n, -3.0, "out"), (0.5 * n, 0.0)])
        return spec
    return pose


HEEL = turn_of((0.0, 0.0, -1.0), (-0.6, -0.5, 0.3))   # the left palm facing forward, behind a bolt's knob


def bolt_end(gun, fp):
    """Full: the bolt is slammed home with the heel of the hand and knocked down."""
    L = Long(gun, fp)
    work = _bolt_work_pose(L)
    struck = dict(work, ik=tuple(x + y for x, y in zip(work["ik"], (0.0, 0.0, -0.035))))
    down = L.right((0.0, -0.02, -0.01), (88.0, 7.0, 0.0), 6.0, work=0.5)
    rest = L.right(work=0.0)
    keys_r = [(0.0, work), (0.15, work), (0.22, struck, "out"), (0.30, down), (0.48, rest), (0.55, rest)]
    c = v(0.0, 0.06, 0.0)
    knob = v(*L.W.SPEC[gun]["bolt"])
    opened = c + rz(-70.0) @ (knob - c) + v(0.0, 0.0, 0.09)
    keys_l = [(0.0, L.belt), (0.14, ("gun", on_palm(opened + v(0.0, 0.0, 0.08), 0.013, HEEL), HEEL)),
              (0.21, ("gun", on_palm(opened - v(0.0, 0.0, 0.09), 0.013, HEEL), HEEL), "in"),
              (0.29, ("gun", on_palm(knob, 0.013, LID_DOWN), LID_DOWN)), (0.36, ("gun", on_palm(knob + v(-0.03, 0.04, 0.0), 0.013, LID_DOWN), LID_DOWN), "out"),
              (0.5, L.rest_l), (0.55, L.rest_l)]
    fingers = [(0.0, "relaxed"), (0.12, "flat"), (0.32, "flat"), (0.5, L.rest_fingers)]

    def pose(t):
        spec, _, _, _ = L.pose(t, keys_r, keys_l, fingers)
        spec["slide"] = at(t, [(0.0, 0.09), (0.15, 0.09), (0.21, 0.0, "in")])
        spec["slide_turn"] = at(t, [(0.0, -70.0), (0.21, -70.0), (0.29, 0.0, "in")])
        L.body(spec, t, [(0.0, 0.0), (0.22, -7.0, "in"), (0.5, 0.0)], [(0.0, 0.0), (0.22, 4.0, "in"), (0.5, 0.0)])
        return spec
    return pose


def anti_materiel(gun, fp):
    """Everything about it is heavy: the muzzle sags, the huge cell is let drop, the new one
    is heaved up from the hip with a swing of the shoulders, and the bolt is hauled back and
    driven home with the whole upper body."""
    L = Long(gun, fp)
    wk = 0.15 if fp else 0.7   # (worked on in the middle of the view, the left forearm would cover it)
    C = Cell((0.0, -0.02, -0.12), (0.0, -1.0, 0.0), 0.05)
    rest = L.right(work=0.0)
    sag = L.right((0.0, -0.035, 0.0), (80.0, 5.0, 0.0), -6.0, work=0.5)
    jerk = L.right((0.0, 0.02, 0.0), (99.0, 6.0, 0.0), -12.0, work=0.6)
    hold = L.right((0.0, 0.0, 0.01), (95.0, 9.0, 0.0), -20.0)
    low = L.right((0.0, -0.03, 0.01), (90.0, 9.0, 0.0), -22.0)
    knock = L.right((0.0, 0.05, 0.0), (103.0, 8.0, 0.0), -14.0)
    level = L.right((0.0, 0.0, 0.0), (91.0, 7.0, 0.0), -8.0, work=wk)
    lifted = L.right((0.0, 0.012, 0.0), (92.0, 7.0, 0.0), -14.0, work=wk)
    pulled = L.right((0.02, 0.02, -0.05), (96.0, 3.0, 0.0), -20.0, work=wk)
    slammed = L.right((0.0, -0.012, 0.03), (86.0, 8.0, 0.0), -4.0, work=wk)
    keys_r = [(0.0, rest), (0.22, sag), (0.32, jerk, "out"), (0.52, hold), (1.0, low), (1.24, low), (1.31, knock, "out"), (1.5, hold),
              (1.72, level), (1.88, lifted), (2.14, pulled, "out"), (2.44, pulled), (2.56, slammed, "in"), (2.74, level), (3.02, rest), (3.2, rest)]
    turn_keys, slide_keys, on_bolt = bolt_work((-0.092, 0.065, -0.02), 1.72, 1.88, 1.94, 2.14, 2.44, 2.55, 2.6, 2.72)
    keys_l = [(0.0, L.rest_l), (0.1, L.rest_l), (0.60, L.belt, "in"), (0.86, C.hold(0.30, (-0.10, 0.0, 0.06))), (1.08, C.hold(0.20)),
              (1.30, C.hold(0.0), "in"), (1.44, C.hold(0.04)), (1.72, on_bolt), (2.74, on_bolt), (2.84, ("gun", v(-0.15, 0.04, 0.02), SIDE), "out"),
              (3.04, L.rest_l), (3.2, L.rest_l)]
    fingers = [(0.0, "support"), (0.1, "support"), (0.3, "relaxed"), (0.60, "foregrip"), (1.30, "foregrip"), (1.42, "open"), (1.72, "foregrip"),
               (2.74, "foregrip"), (2.82, "open", "out"), (2.94, "relaxed"), (3.04, "support")]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        spec["slide_turn"] = at(t, turn_keys)
        spec["slide"] = at(t, slide_keys)
        open_ = _open(t, 0.32, 1.32)
        spec["vent_pos"] = (0.0, 0.004 * open_, 0.012 * open_)
        if 0.29 <= t < 0.36:
            C.thrown(spec, t, 0.29, 0.12)
        elif 0.36 <= t < 1.30:
            C.carry(spec, frame, fist, turn)
        L.body(spec, t, [(0.0, 0.0), (0.32, 5.0, "out"), (0.6, 8.0), (0.86, 12.0), (1.31, -12.0, "in"), (1.72, -3.0), (2.14, -20.0, "out"),
                         (2.44, -21.0), (2.56, 7.0, "in"), (3.02, 0.0)],
               [(0.0, 0.0), (0.22, 6.0), (0.32, -3.0, "out"), (0.86, 7.0), (1.31, -6.0, "in"), (1.72, 0.0), (2.14, -9.0, "out"), (2.56, 8.0, "in"),
                (3.02, 0.0)],
               [(0.0, 0.0), (1.88, 0.0), (2.14, 9.0, "out"), (2.56, -3.0, "in"), (3.02, 0.0)])
        return spec
    return pose


def railgun(gun, fp):
    """The spent cell is kicked out glowing, the top rail and the sleeve flare open off the
    coils, a new cell is pushed in, and the rail snaps shut."""
    from weapons import RAIL_HINGE
    L = Long(gun, fp)
    C = Cell((0.0, -0.005, 0.105), (0.0, -1.0, 0.0), 0.035)
    rest = L.right(work=0.0)
    dip = L.right((0.0, -0.012, 0.0), (87.0, 4.0, 0.0), work=0.0)
    kick = L.right((0.0, 0.03, 0.01), (100.0, 6.0, 0.0), -12.0, work=0.5)
    flare = L.right((0.0, 0.0, 0.03), (94.0, 8.0, 0.0), -18.0)                 # it bucks as the rail flies open
    hold = L.right((0.0, 0.0, 0.0), (96.0, 9.0, 0.0), -22.0)
    knock = L.right((0.0, 0.035, 0.0), (101.0, 8.0, 0.0), -18.0)
    snap = L.right((0.0, -0.01, -0.03), (89.0, 6.0, 0.0), -6.0, work=0.6)
    keys_r = [(0.0, rest), (0.22, dip), (0.30, kick, "out"), (0.42, flare, "out"), (0.60, hold), (1.54, hold), (1.60, hold), (1.65, knock, "out"),
              (1.80, hold), (1.88, hold), (1.94, snap, "out"), (2.25, rest), (2.6, rest)]
    keys_l = [(0.0, L.rest_l), (0.34, L.rest_l), (0.46, L.clear, "out"), (0.84, L.belt, "in"), (1.30, C.hold(0.2)), (1.60, C.hold(0.0), "in"),
              (1.74, C.hold(0.04)), (2.05, L.rest_l), (2.6, L.rest_l)]
    fingers = [(0.0, "support"), (0.34, "support"), (0.44, "open", "out"), (0.6, "relaxed"), (0.84, "foregrip"), (1.60, "foregrip"),
               (1.72, "open"), (1.9, "relaxed"), (2.05, "support")]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        spec["vent_pivot"] = RAIL_HINGE
        spec["vent"] = at(t, [(0.0, 0.0), (0.36, 0.0), (0.42, 12.0, "out"), (0.52, 9.0), (1.88, 9.0), (1.93, 0.0, "in")])
        spec["slide"] = at(t, [(0.0, 0.0), (0.36, 0.0), (0.42, 0.07, "out"), (0.5, 0.06), (1.88, 0.06), (1.93, 0.0, "in")])
        if 0.27 <= t < 0.34:
            C.thrown(spec, t, 0.27, 0.12)
        elif 0.34 <= t < 1.60:
            C.carry(spec, frame, fist, turn)
        L.body(spec, t, [(0.0, 0.0), (0.30, 5.0, "out"), (0.42, -4.0, "out"), (0.84, 2.0), (1.65, -7.0, "in"), (1.94, 4.0, "out"), (2.25, 0.0)],
               [(0.0, 0.0), (0.30, -4.0, "out"), (0.42, -7.0, "out"), (0.84, 0.0), (1.65, -3.0, "in"), (1.94, 4.0, "out"), (2.25, 0.0)])
        return spec
    return pose


def crossbow(gun, fp):
    """A bolt is brought over the rail and dropped on, and the left hand spins the crank on
    the side of the tiller to draw the string."""
    from weapons import CRANK_PIVOT, CRANK_ARM
    L = Long(gun, fp)
    B = v(0.0, 0.076, -0.25)   # the middle of the bolt, lying on the rail
    rest = L.right(work=0.0)
    tilt = L.right((0.0, 0.0, 0.01), (95.0, 9.0, 0.0), 22.0)       # the rail and the crank turned toward the left hand
    took = L.right((0.0, -0.012, 0.01), (93.0, 9.0, 0.0), 22.0)
    keys_r = [(0.0, rest), (0.16, tilt), (0.54, tilt), (0.59, took, "out"), (0.68, tilt), (1.06, tilt), (1.25, rest), (1.3, rest)]
    axle = v(-0.05, CRANK_PIVOT[0], -CRANK_PIVOT[1])
    grasp = turn_of((0.0, 1.0, 0.0), (-0.35, 0.2, 1.0))
    turn_keys = [(0.0, 0.0), (0.74, 0.0), (0.80, -90.0, "in"), (0.98, -470.0, "linear"), (1.04, -540.0, "out"), (1.3, -540.0)]

    def on_crank(t):
        return ("gun", axle + rx(at(t, turn_keys)) @ v(-0.012, 0.0, -CRANK_ARM), grasp)

    def holding(p):
        return ("gun", p - LID_DOWN @ TIPS, LID_DOWN)
    keys_l = [(0.0, L.rest_l), (0.04, L.rest_l), (0.26, L.belt, "in"), (0.44, holding(B + v(0.0, 0.11, 0.0))), (0.51, holding(B + v(0.0, 0.035, 0.0)), "in"),
              (0.60, holding(B + v(-0.05, 0.09, 0.05)), "out"), (0.74, on_crank), (1.04, on_crank), (1.12, ("gun", axle + v(-0.06, 0.02, 0.0), grasp), "out"),
              (1.27, L.rest_l), (1.3, L.rest_l)]
    fingers = [(0.0, "support"), (0.04, "support"), (0.16, "relaxed"), (0.26, "pinch"), (0.51, "pinch"), (0.56, "open", "out"), (0.74, "foregrip"),
               (1.04, "foregrip"), (1.10, "open", "out"), (1.2, "relaxed"), (1.27, "support")]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        spec["vent_pivot"] = CRANK_PIVOT
        spec["vent"] = at(t, turn_keys)
        if t < 0.51:      # in the fingertips (the game hides it until the hand has it)
            _put(spec, frame, fist + turn @ TIPS, np.eye(3), B)
        elif t < 0.56:    # let go just over the rail
            spec["mag"] = (0.0, 0.035 * (1.0 - ((t - 0.51) / 0.05) ** 2), 0.0)
        L.body(spec, t, [(0.0, 0.0), (0.16, -3.0), (0.59, -5.0), (0.9, -8.0), (1.25, 0.0)], [(0.0, 0.0), (0.59, 3.0, "in"), (0.9, 4.0), (1.25, 0.0)])
        return spec
    return pose


SHAFT = turn_of((1.0, 0.0, 0.0), (0.0, -1.0, 0.3))   # the left fist round a shaft lying along the barrel


# ---------------------------------------------------------------------------
# Heavies

FLANK = turn_of((1.0, 0.0, 0.0), (-0.3, -0.6, 0.7))   # the left palm against the left flank of a tube


def rocket_launcher(gun, fp):
    """The launcher comes down off the shoulder and across the body, muzzle up; the left hand
    pulls a rocket off the back, twirls it once, feeds its tail into the muzzle and lets it
    slide home, and pats the tube before it goes back on the shoulder."""
    L = Long(gun, fp)
    G = v(0.0, 0.115, -0.3)   # where the hand holds the rocket (gun space, seated)
    D = 0.5                   # how far out of the tube it starts
    rest = L.right(work=0.0)
    off = (-0.13, -0.03, 0.34) if fp else (0.02, -0.19, 0.21)
    up = 106.0 if fp else 116.0   # (in first person it lies lower, so the muzzle and the rocket stay in view)
    across = L.right(off, (up, 34.0, 0.0), 0.0, work=0.0)
    seated = L.right((off[0], off[1] - 0.018, off[2] + 0.012), (up - 3.0, 34.0, 0.0), 0.0, work=0.0)
    patted = L.right((off[0] + 0.012, off[1], off[2]), (up, 32.0, 0.0), -4.0, work=0.0)
    keys_r = [(0.0, rest), (0.28, across), (0.93, across), (0.98, seated, "out"), (1.06, across), (1.12, across), (1.16, patted, "out"),
              (1.24, across), (1.46, rest), (1.5, rest)]
    behind = ("free", v(-0.2, L.W.EYE_Y - 0.12, 0.06) if fp else v(-0.13, 1.44, 0.15), turn_of((0.0, 0.0, 1.0), (0.2, -1.0, -0.2)))
    twirl = G + v(-0.15, 0.0, -D + 0.1)
    feed = G + v(0.0, 0.0, -D)

    def pat(off_):
        return ("gun", on_palm(v(-0.062 - off_, 0.115, -0.42), 0.0, FLANK), FLANK)
    keys_l = [(0.0, L.rest_l), (0.04, L.rest_l), (0.22, behind, "in"), (0.36, ("gun", twirl, SHAFT)), (0.60, ("gun", twirl, SHAFT)),
              (0.72, ("gun", feed, SHAFT)), (0.81, ("gun", feed + v(0.0, 0.0, 0.09), SHAFT)), (0.92, ("gun", feed + v(-0.10, 0.02, 0.06), SHAFT), "out"),
              (1.08, pat(0.10)), (1.15, pat(0.0), "in"), (1.24, pat(0.07), "out"), (1.44, L.rest_l), (1.5, L.rest_l)]
    fingers = [(0.0, L.rest_fingers), (0.04, L.rest_fingers), (0.14, "relaxed"), (0.22, "fist"), (0.81, "fist"), (0.87, "open", "out"),
               (1.06, "flat"), (1.26, "flat"), (1.44, L.rest_fingers)]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        if t < 0.72:      # in the fist (the game hides it until the hand has it), turned once end over end
            _put(spec, frame, fist, rx(at(t, [(0.0, 0.0), (0.36, 0.0), (0.60, -360.0)])), G)
        elif t < 0.96:    # fed in by the hand, then sliding home on its own
            spec["mag"] = (0.0, 0.0, at(t, [(0.72, -D), (0.81, -D + 0.09, "linear"), (0.96, 0.0, "in")]))
        spec["vent_pos"] = (0.0, 0.0, at(t, [(0.0, 0.0), (0.93, 0.0), (0.97, 0.02, "out"), (1.1, 0.0)]))
        L.body(spec, t, [(0.0, 0.0), (0.28, -12.0), (0.93, -14.0), (1.46, 0.0)], [(0.0, 0.0), (0.28, -5.0), (0.93, -5.0), (0.98, -2.0), (1.46, 0.0)])
        return spec
    return pose


DRUM_AXIS = v(0.0, 0.07, 0.0)       # the grenade launcher's drum turns about this line
DRUM_CRANE = v(-0.06, 0.0, 0.0)     # ...and swings out to the left about this one
DRUM_OUT = 80.0
GRENADE = v(0.0, 0.07, -0.16)       # the grenade (the gun's vent part), hidden on the drum's axis


def _drum(swing, spin):
    """The drum swung out `swing` degrees on its crane and turned `spin` about its own axis:
    {"mag_rot", "mag"}, and where its middle has gone."""
    centre = DRUM_CRANE + rz(swing) @ (DRUM_AXIS - DRUM_CRANE)
    return {"mag_rot": (0.0, 0.0, swing + spin), "mag": tuple(centre - rz(swing + spin) @ DRUM_AXIS)}, centre - DRUM_AXIS


def _drum_tilt(L):
    return L.right((0.0, 0.0, 0.0), (95.0, 10.0, 0.0), -30.0)   # rolled over: the open drum turned up to the left hand


PUSH = turn_of((1.0, 0.0, 0.0), (-0.3, -0.3, 1.0))   # the left hand behind the open drum, fingers forward


def grenades(gun, fp):
    """One grenade, the drum hanging open on its crane: thumbed into a chamber from behind,
    and the drum clicks round one."""
    L = Long(gun, fp)
    n = L.W.RELOAD[gun] / 0.55
    tilt = _drum_tilt(L)
    took = L.right((0.0, -0.004, -0.012), (94.0, 10.0, 0.0), -28.0)
    keys_r = [(0.0, tilt), (0.24 * n, tilt), (0.31 * n, took, "out"), (0.42 * n, tilt), (0.55 * n, tilt)]
    shift = _drum(DRUM_OUT, 0.0)[1]
    chamber = GRENADE + shift + v(0.0, 0.04, 0.0)   # the top chamber of the open drum

    def holding(back):
        return ("gun", chamber + v(0.0, 0.0, back) - PUSH @ TIPS, PUSH)
    keys_l = [(0.0, L.belt), (0.22 * n, holding(0.13), "out"), (0.30 * n, holding(0.045), "in"), (0.38 * n, holding(0.16), "out"), (0.55 * n, L.belt)]
    fingers = [(0.0, "pinch"), (0.28 * n, "pinch"), (0.34 * n, "open", "out"), (0.44 * n, "relaxed"), (0.55 * n, "pinch")]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        aim, grip = frame
        spec.update(_drum(DRUM_OUT, at(t, [(0.0, 0.0), (0.36 * n, 0.0), (0.46 * n, 60.0, "out"), (0.55 * n, 60.0)]))[0])
        if t < 0.26 * n:       # in the fingertips
            spec["vent_pos"] = tuple(aim.T @ (fist + turn @ TIPS - grip) - GRENADE)
        elif t < 0.31 * n:     # pushed home into the chamber
            spec["vent_pos"] = tuple(chamber - GRENADE + v(0.0, 0.0, 0.085 * (1.0 - (t - 0.26 * n) / (0.05 * n))))
        else:                  # inside the drum
            spec["vent_pos"] = tuple(shift)
        L.body(spec, t, [(0.0, 0.0), (0.31 * n, -3.0, "out"), (0.55 * n, 0.0)])
        return spec
    return pose


def grenade_end(gun, fp):
    """Full: the left hand sets the drum spinning with a swipe, and a flick of the right
    wrist swings it shut, like a revolver's cylinder."""
    L = Long(gun, fp)
    tilt = _drum_tilt(L)
    wind = L.right((0.0, -0.01, 0.0), (92.0, 8.0, 0.0), -42.0)
    shut = L.right((-0.02, 0.02, 0.0), (95.0, 4.0, 0.0), 26.0)
    rest = L.right(work=0.0)
    keys_r = [(0.0, tilt), (0.30, tilt), (0.37, wind), (0.44, shut, "out"), (0.54, L.right((0.0, -0.01, 0.0), (88.0, 4.0, 0.0), work=0.0)),
              (0.64, rest), (0.7, rest)]
    shift = _drum(DRUM_OUT, 0.0)[1]
    side = GRENADE + shift + v(-0.085, 0.0, 0.0)   # the open drum's left flank

    def swipe(up, off_=0.0):
        return ("gun", on_palm(side + v(-off_, up, 0.0), 0.0, FLANK), FLANK)
    keys_l = [(0.0, L.belt), (0.10, swipe(0.07, 0.01)), (0.17, swipe(-0.06), "in"), (0.26, swipe(-0.12, 0.06), "out"), (0.42, L.clear),
              (0.62, L.rest_l), (0.7, L.rest_l)]
    fingers = [(0.0, "relaxed"), (0.08, "flat"), (0.2, "flat"), (0.3, "relaxed"), (0.5, "relaxed"), (0.62, L.rest_fingers)]

    def pose(t):
        spec, _, _, _ = L.pose(t, keys_r, keys_l, fingers)
        swing = at(t, [(0.0, DRUM_OUT), (0.38, DRUM_OUT), (0.44, 0.0, "in")])
        drum, moved = _drum(swing, at(t, [(0.0, 0.0), (0.11, 0.0), (0.17, 150.0, "in"), (0.44, 660.0, "out"), (0.7, 720.0)]))
        spec.update(drum)
        spec["vent_pos"] = tuple(moved)
        L.body(spec, t, [(0.0, 0.0), (0.37, -5.0), (0.44, 6.0, "out"), (0.64, 0.0)])
        return spec
    return pose


def plasma_cannon(gun, fp):
    """The spent core is kicked out glowing in a puff of steam, a new one is pushed in and
    twisted home, and the cannon shakes as it charges back up (the game's glow builds)."""
    L = Long(gun, fp)
    C = Cell((0.0, -0.005, 0.11), (0.0, -1.0, 0.0), 0.035)
    rest = L.right(work=0.0)
    dip = L.right((0.0, -0.012, 0.0), (87.0, 4.0, 0.0), work=0.0)
    kick = L.right((0.0, 0.035, 0.015), (101.0, 6.0, 0.0), -12.0, work=0.5)
    hold = L.right((0.0, 0.0, 0.0), (96.0, 9.0, 0.0), -22.0)
    knock = L.right((0.0, 0.03, 0.0), (100.0, 8.0, 0.0), -18.0)
    up = L.right((0.0, 0.01, -0.02), (93.0, 5.0, 0.0), work=0.3)
    keys_r = [(0.0, rest), (0.22, dip), (0.30, kick, "out"), (0.50, hold), (1.30, hold), (1.36, knock, "out"), (1.5, hold), (1.62, hold),
              (1.8, up), (2.2, up), (2.34, rest), (2.4, rest)]
    keys_l = [(0.0, L.rest_l), (0.34, L.rest_l), (0.46, L.clear, "out"), (0.80, L.belt, "in"), (1.14, C.hold(0.2, turn=ry(90.0))),
              (1.34, C.hold(0.05, turn=ry(90.0)), "in"), (1.6, C.hold(0.0)), (1.72, C.hold(0.04)), (2.0, L.rest_l), (2.4, L.rest_l)]
    fingers = [(0.0, "support"), (0.34, "support"), (0.44, "open", "out"), (0.6, "relaxed"), (0.80, "foregrip"), (1.6, "foregrip"),
               (1.7, "open"), (1.86, "relaxed"), (2.0, "support")]

    def pose(t):
        spec, frame, fist, turn = L.pose(t, keys_r, keys_l, fingers)
        open_ = at(t, [(0.0, 0.0), (0.26, 0.0), (0.32, 1.25, "out"), (0.42, 1.0), (2.16, 1.0), (2.21, 0.0, "in")])
        spec["vent_pos"] = (0.0, 0.01 * open_, 0.016 * open_)
        if 0.27 <= t < 0.34:
            C.thrown(spec, t, 0.27, 0.12)
        elif 0.34 <= t < 1.6:
            C.carry(spec, frame, fist, turn)
        # It shakes harder and harder as it charges, and stills as the vents shut.
        shake = at(t, [(0.0, 0.0), (1.62, 0.0), (2.16, 1.0, "in"), (2.24, 0.0)]) * 0.004
        if shake > 0.0:
            arm = dict(spec["arm_r"])
            arm["ik"] = tuple(a + b for a, b in zip(arm["ik"], (shake * np.sin(t * 95.0), shake * np.sin(t * 137.0 + 1.0), 0.0)))
            spec["arm_r"] = arm
            spec["arm_l"] = L.left(t, arm, keys_l)[0]
        L.body(spec, t, [(0.0, 0.0), (0.30, 5.0, "out"), (0.5, 0.0), (1.36, -7.0, "in"), (1.8, 0.0), (2.34, 0.0)],
               [(0.0, 0.0), (0.30, -5.0, "out"), (0.5, 0.0), (1.36, -3.0, "in"), (1.8, -3.0), (2.2, -5.0), (2.34, 0.0)])
        return spec
    return pose


RELOADS = {"rocket_launcher": rocket_launcher, "grenade_launcher": grenades, "plasma_cannon": plasma_cannon,
           "lever_action": lever_rounds, "bolt_action": bolt_rounds, "anti_materiel": anti_materiel, "railgun": railgun,
           "crossbow": crossbow, "smg": smg, "rifle": rifle, "burst_rifle": burst_rifle, "battle_rifle": battle_rifle, "nail_gun": nail_gun, "lmg": lmg,
           "minigun": minigun, "shotgun": shells, "break_action": break_action, "air_cannon": air_cannon}
FPS = {"air_cannon": 60, "smg": 60, "rifle": 60, "crossbow": 60, "rocket_launcher": 60}   # clips baked at more frames a second (rig.Clip): a part turning about its own middle
# What ends a shell-at-a-time reload once the gun is full: {gun: (seconds, clip)}.
ENDS = {"shotgun": (0.75, shotgun_end), "lever_action": (0.7, lever_end), "bolt_action": (0.55, bolt_end),
        "grenade_launcher": (0.7, grenade_end)}
