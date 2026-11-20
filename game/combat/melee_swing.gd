class_name MeleeSwing
extends RefCounted
## How a melee weapon is held, wound up and swung. Shared by the body everyone sees
## (RobotAnimator) and your own first-person arms (ViewModel).
##
## Each weapon has three blows:
##  - two taps that take turns, the first from the right and the next from the left
##    (`side` 0 and 1; whoever swings keeps count, see Player);
##  - a heavy blow of its own, for a swing wound up to HEAVY_AT or more.
## and they all go the same way:
##  - ready: the weapon held in a guard;
##  - winding up, while the button is held: the weapon draws back to the coming tap's
##    side, then travels on to where the heavy blow starts, the body coiling with
##    it, further the longer it is held. This is the only sign of how charged a swing
##    is (there is no meter), so it is big enough to read from across the arena;
##    fully wound, the weapon trembles;
##  - the blow, on letting go: one smooth curve from wherever the wind-up had got to,
##    whipping through the moment it lands, on past the target (further the more it
##    was wound up) and round to ready again. The edge leads.
## A blow that lands freezes the swing for a moment (hit_stop) so the hit has weight.
## The timing is the same for every blow of a weapon (see impact_time and length), unless
## a blow says otherwise (Karate's spinning kicks take longer to land than its jab).
##
## The weapon is animated, not the arms: each key says where the grip is and which
## way the blade points, in the "hold frame" (the chest's own space: +X right, +Y up,
## -Z forward, from the point midway between the shoulders), and the arms are then
## bent to reach it (hold()). So the hands stay on the weapon whatever the body is
## doing, and every robot (they share a skeleton) swings the same way.

const STRIKE := 0.13     ## seconds from letting go to the end of the blow, times the weapon's pace
const HIT_AT := 0.55     ## how far into the blow it lands
const FOLLOW := 0.12
const RECOVER := 0.3
const MIN_WOUND := 0.7   ## how far a tap draws back, as a part of the tap's own coil
const DRAW := 14.0       ## how quickly the pose follows the wind-up (per second)...
const DRAW_TAP := 26.0   ## ...and the first draw back, which a tap has only a moment for
const SETTLE := 7.0      ## how quickly the weapon eases back to rest when nothing is happening
const LEAD_AT := 0.45    ## how far into the time before it lands a blow passes its "lead" key
const HEAVY_AT := 0.5    ## wound up this far or more (0..1), the blow is the weapon's heavy one
const TAP_SPAN := 0.2    ## the first part of the wind-up draws back to the tap's coil; the rest travels on to the heavy blow's
const COMBO_RESET := 1.0 ## seconds without a swing before the taps start from the right again

## What a key holds.
enum { GRIP, BLADE, LEAD, TURN, LEAN, LEFT, HANDS }
## Each key: [where the grip (the right hand) is, which way the blade points, which way
## its edge faces (the way it is travelling), chest turn (+ = to the left; the spine adds
## half as much again), lean (+ = forward), where the left hand holds it (metres along
## the weapon from the right hand: - = toward the pommel), and perhaps how much the left
## hand holds it at all (1 if left out; 0 = it hangs free, as in a relaxed carry)].
##
## A weapon's blows: "ready", then "taps" (two, taking turns) and "heavy", each with "wound" (where
## the wind-up draws to), "hit" (the moment it lands) and "end" (the end of a full
## follow-through), and perhaps "lead" (passed on the way in, so that even a blow from
## barely drawn back comes round from its own side) and "way" (which way it crosses the
## view, where the blade's turning does not say). "air", if there is one, is the weapon's
## own wind-up and blow off the ground: "wound", "hit" and "end" again, with "axis" and
## "turns" (the body goes round that axis this many times in all, one long spin from the
## start of the wind-up to the moment the blow lands; + is to the left about UP) and
## "wind" (how much of that a full wind-up covers, the blow bringing the rest: SPIN_WIND unless
## given), "dive" (instead of turning: the body tips about the axis, back by dive.x radians as
## it winds up and over by dive.y into the blow, as in a dive, and comes level again after;
## other players see it, your own view stays level), "legs" (the legs' own part in it: two
## sets of [right thigh, right knee, left thigh, left knee] in radians, wound up and as the blow
## lands; a thigh is + lifted in front and - trailing behind, a knee + bent) and "after" (turns the body carries on round after the blow lands, the
## same way, or to the left if it did not spin before). A key named "fp_" and one of those
## ("fp_ready", "fp_wound", "fp_hit"...) is used instead in first person, where the weapon
## has to stay in view and clear of the middle of it, and a thrust has to go where you look.
const MOVES := {
	"sword": {
		# A low guard, at ease: both hands at the hip, the point low and forward (in first person it is
		# lifted into view, the blade lying across below the crosshair). Flat cuts from each side; the heavy blow
		# is a diagonal cut from high by the right shoulder down to the left hip, the whole body behind it.
		"ready": [Vector3(0.08, -0.42, -0.2), Vector3(-0.4, -0.38, -0.83), Vector3(0.0, -0.9, 0.42), -0.25, 0.04, -0.13],
		"fp_ready": [Vector3(0.06, -0.3, -0.38), Vector3(-0.55, -0.1, -0.83), Vector3(0.0, -1.0, 0.1), -0.25, 0.04, -0.13],
		"taps": [
			{
				"wound": [Vector3(0.12, -0.08, -0.24), Vector3(0.75, 0.4, 0.55), Vector3(0.35, 0.0, -0.94), -0.8, -0.08, -0.15],
				"fp_wound": [Vector3(0.1, -0.1, -0.36), Vector3(0.5, 0.85, 0.1), Vector3(0.35, 0.0, -0.94), -0.6, -0.05, -0.15],
				"lead": [Vector3(0.14, -0.14, -0.3), Vector3(0.92, 0.12, -0.3), Vector3(-0.3, 0.0, -0.95), -0.35, 0.05, -0.15],
				"hit": [Vector3(0.02, -0.18, -0.42), Vector3(0.15, 0.03, -0.99), Vector3(-1.0, 0.0, 0.0), 0.15, 0.2, -0.15],
				"end": [Vector3(-0.1, -0.16, -0.3), Vector3(-0.95, 0.0, -0.2), Vector3(-0.4, 0.0, 0.9), 0.85, 0.2, -0.15],
			},
			{
				"wound": [Vector3(-0.08, -0.1, -0.26), Vector3(-0.75, 0.4, 0.55), Vector3(0.35, 0.0, 0.94), 0.75, -0.08, -0.15],
				"fp_wound": [Vector3(-0.4, -0.24, -0.32), Vector3(-0.7, 0.68, 0.2), Vector3(0.35, 0.0, 0.94), 0.55, -0.05, -0.15],
				"lead": [Vector3(-0.1, -0.15, -0.3), Vector3(-0.92, 0.12, -0.3), Vector3(-0.3, 0.0, 0.95), 0.35, 0.05, -0.15],
				"hit": [Vector3(0.02, -0.18, -0.42), Vector3(-0.15, 0.03, -0.99), Vector3(-1.0, 0.0, 0.0), -0.1, 0.2, -0.15],
				"end": [Vector3(0.14, -0.16, -0.28), Vector3(0.95, 0.0, -0.2), Vector3(-0.4, 0.0, -0.9), -0.85, 0.2, -0.15],
			},
		],
		"heavy": {
			"wound": [Vector3(0.14, 0.1, -0.14), Vector3(0.5, 0.3, 0.81), Vector3(-0.3, -0.5, -0.8), -1.1, -0.2, -0.15],
			"fp_wound": [Vector3(0.06, -0.02, -0.4), Vector3(0.42, 0.88, 0.22), Vector3(-0.3, -0.3, -0.9), -0.85, -0.12, -0.15],
			"hit": [Vector3(0.0, -0.2, -0.42), Vector3(0.2, 0.25, -0.95), Vector3(-0.7, -0.7, 0.0), 0.25, 0.38, -0.15],
			"end": [Vector3(-0.16, -0.36, -0.22), Vector3(-0.75, -0.6, -0.2), Vector3(-0.3, -0.4, 0.86), 1.05, 0.4, -0.15],
		},
		# In mid-air: one forward somersault, the blade trailing back over the shoulder, into a vertical slash
		# straight down in front as it comes round.
		"air": {
			"wound": [Vector3(0.1, 0.1, -0.08), Vector3(0.1, 0.45, 0.89), Vector3(0.0, 0.89, -0.45), -0.35, -0.35, -0.15],
			"fp_wound": [Vector3(0.16, -0.02, -0.36), Vector3(0.25, 0.9, 0.35), Vector3(0.0, 0.35, -0.94), -0.3, -0.1, -0.15],
			"lead": [Vector3(0.06, 0.16, -0.28), Vector3(0.05, 0.95, -0.3), Vector3(0.0, -0.3, -0.95), -0.1, 0.0, -0.15],
			"hit": [Vector3(0.02, -0.12, -0.44), Vector3(0.03, -0.25, -0.97), Vector3(0.0, -0.97, 0.25), 0.1, 0.45, -0.15],
			"end": [Vector3(0.0, -0.34, -0.28), Vector3(0.05, -0.9, 0.42), Vector3(0.0, 0.42, 0.9), 0.15, 0.5, -0.15],
			"axis": Vector3(-1.0, 0.0, 0.0),
			"turns": 1.0,
			"wind": 0.9,
		},
	},
	"hammer": {
		# The hands apart on the haft, the head carried low. Flat swings from each side; the heavy blow is one
		# huge swing round from far behind the right shoulder, the body turning hard through it.
		"ready": [Vector3(0.08, -0.42, -0.2), Vector3(-0.4, -0.38, -0.83), Vector3(0.0, -0.9, 0.42), -0.25, 0.04, -0.2],
		"fp_ready": [Vector3(0.06, -0.3, -0.38), Vector3(-0.55, -0.1, -0.83), Vector3(0.0, -1.0, 0.1), -0.25, 0.04, -0.2],
		"taps": [
			{
				"wound": [Vector3(0.12, -0.08, -0.24), Vector3(0.75, 0.4, 0.55), Vector3(0.35, 0.0, -0.94), -0.864, -0.08, -0.2],
				"fp_wound": [Vector3(0.1, -0.1, -0.36), Vector3(0.5, 0.85, 0.1), Vector3(0.35, 0.0, -0.94), -0.648, -0.05, -0.2],
				"lead": [Vector3(0.14, -0.14, -0.3), Vector3(0.92, 0.12, -0.3), Vector3(-0.3, 0.0, -0.95), -0.378, 0.05, -0.2],
				"hit": [Vector3(0.02, -0.18, -0.42), Vector3(0.15, 0.03, -0.99), Vector3(-1.0, 0.0, 0.0), 0.162, 0.2, -0.2],
				"end": [Vector3(-0.1, -0.16, -0.3), Vector3(-0.95, 0.0, -0.2), Vector3(-0.4, 0.0, 0.9), 0.918, 0.2, -0.2],
			},
			{
				"wound": [Vector3(-0.08, -0.1, -0.26), Vector3(-0.75, 0.4, 0.55), Vector3(0.35, 0.0, 0.94), 0.81, -0.08, -0.2],
				"fp_wound": [Vector3(-0.4, -0.24, -0.32), Vector3(-0.7, 0.68, 0.2), Vector3(0.35, 0.0, 0.94), 0.594, -0.05, -0.2],
				"lead": [Vector3(-0.1, -0.15, -0.3), Vector3(-0.92, 0.12, -0.3), Vector3(-0.3, 0.0, 0.95), 0.378, 0.05, -0.2],
				"hit": [Vector3(0.02, -0.18, -0.42), Vector3(-0.15, 0.03, -0.99), Vector3(-1.0, 0.0, 0.0), -0.108, 0.2, -0.2],
				"end": [Vector3(0.14, -0.16, -0.28), Vector3(0.95, 0.0, -0.2), Vector3(-0.4, 0.0, -0.9), -0.918, 0.2, -0.2],
			},
		],
		"heavy": {
			"wound": [Vector3(0.14, -0.04, -0.16), Vector3(0.62, 0.2, 0.76), Vector3(0.75, 0.0, -0.62), -1.2, -0.15, -0.2],
			"fp_wound": [Vector3(0.06, -0.02, -0.4), Vector3(0.42, 0.88, 0.22), Vector3(-0.3, -0.3, -0.9), -0.85, -0.12, -0.2],
			"lead": [Vector3(0.14, -0.14, -0.3), Vector3(0.92, 0.1, -0.3), Vector3(-0.3, 0.0, -0.95), -0.5, 0.08, -0.2],
			"hit": [Vector3(0.0, -0.18, -0.44), Vector3(0.2, 0.0, -0.98), Vector3(-1.0, 0.0, 0.0), 0.3, 0.3, -0.2],
			"end": [Vector3(-0.12, -0.14, -0.24), Vector3(-0.75, 0.05, 0.65), Vector3(0.65, 0.0, 0.75), 1.25, 0.25, -0.2],
		},
		# In mid-air: one long turn right round, the hammer out at arm's length, from the start of the wind-up
		# to the moment the huge swing at the end of it lands.
		"air": {
			"wound": [Vector3(0.3, -0.06, -0.42), Vector3(0.75, 0.05, -0.65), Vector3(-0.65, 0.0, -0.75), -0.3, 0.0, -0.2],
			"fp_wound": [Vector3(0.2, -0.08, -0.44), Vector3(0.8, 0.3, -0.5), Vector3(-0.65, 0.0, -0.75), -0.3, 0.0, -0.2],
			"hit": [Vector3(0.0, -0.18, -0.44), Vector3(0.2, 0.0, -0.98), Vector3(-1.0, 0.0, 0.0), 0.3, 0.3, -0.2],
			"end": [Vector3(-0.12, -0.14, -0.24), Vector3(-0.75, 0.05, 0.65), Vector3(0.65, 0.0, 0.75), 1.25, 0.25, -0.2],
			"axis": Vector3(0.0, 1.0, 0.0),
			"turns": 1.0,
		},
	},
	"axe": {
		# Diagonal chops, down from the right shoulder and then down from the left; the heavy blow comes from
		# high behind the head and is driven down past the hip.
		"ready": [Vector3(0.08, -0.42, -0.2), Vector3(-0.4, -0.38, -0.83), Vector3(0.0, -0.9, 0.42), -0.25, 0.04, -0.17],
		"fp_ready": [Vector3(0.06, -0.3, -0.38), Vector3(-0.55, -0.1, -0.83), Vector3(0.0, -1.0, 0.1), -0.25, 0.04, -0.17],
		"taps": [
			{
				"wound": [Vector3(0.13, 0.04, -0.18), Vector3(0.55, 0.55, 0.63), Vector3(-0.3, -0.5, -0.8), -0.8, -0.1, -0.17],
				"fp_wound": [Vector3(0.1, -0.1, -0.36), Vector3(0.5, 0.85, 0.1), Vector3(0.35, 0.0, -0.94), -0.6, -0.05, -0.17],
				"hit": [Vector3(0.0, -0.2, -0.42), Vector3(0.2, 0.25, -0.95), Vector3(-0.7, -0.7, 0.0), 0.18, 0.28, -0.17],
				"end": [Vector3(-0.14, -0.32, -0.24), Vector3(-0.75, -0.55, -0.36), Vector3(-0.3, -0.4, 0.86), 0.8, 0.3, -0.17],
			},
			{
				"wound": [Vector3(-0.13, 0.04, -0.18), Vector3(-0.55, 0.55, 0.63), Vector3(0.3, -0.5, -0.8), 0.8, -0.1, -0.17],
				"fp_wound": [Vector3(-0.4, -0.24, -0.32), Vector3(-0.7, 0.68, 0.2), Vector3(0.35, 0.0, 0.94), 0.55, -0.05, -0.17],
				"hit": [Vector3(0.0, -0.2, -0.42), Vector3(-0.2, 0.25, -0.95), Vector3(0.7, -0.7, 0.0), -0.18, 0.28, -0.17],
				"end": [Vector3(0.14, -0.32, -0.24), Vector3(0.75, -0.55, -0.36), Vector3(0.3, -0.4, 0.86), -0.8, 0.3, -0.17],
			},
		],
		"heavy": {
			"wound": [Vector3(0.12, 0.16, -0.1), Vector3(0.35, 0.45, 0.82), Vector3(-0.2, 0.8, -0.55), -1.1, -0.25, -0.17],
			"fp_wound": [Vector3(0.06, -0.02, -0.4), Vector3(0.42, 0.88, 0.22), Vector3(-0.3, -0.3, -0.9), -0.85, -0.12, -0.17],
			"hit": [Vector3(0.0, -0.22, -0.42), Vector3(0.15, 0.15, -0.98), Vector3(-0.55, -0.83, 0.0), 0.25, 0.42, -0.17],
			"end": [Vector3(-0.1, -0.38, -0.22), Vector3(-0.6, -0.75, -0.28), Vector3(-0.3, -0.3, 0.9), 1.05, 0.5, -0.17],
		},
		# In mid-air: one cartwheel with the axe held high over the head, into a big chop straight down in front.
		"air": {
			"wound": [Vector3(0.04, 0.16, -0.08), Vector3(0.05, 0.6, 0.8), Vector3(0.0, 0.8, -0.6), -0.2, -0.35, -0.17],
			"fp_wound": [Vector3(0.12, 0.0, -0.34), Vector3(0.15, 0.95, 0.25), Vector3(0.0, 0.25, -0.97), -0.2, -0.1, -0.17],
			"lead": [Vector3(0.04, 0.16, -0.28), Vector3(0.05, 0.95, -0.3), Vector3(0.0, -0.3, -0.95), -0.05, 0.0, -0.17],
			"hit": [Vector3(0.0, -0.2, -0.44), Vector3(0.05, -0.15, -0.99), Vector3(0.0, -0.99, 0.15), 0.1, 0.5, -0.17],
			"end": [Vector3(0.0, -0.38, -0.26), Vector3(0.0, -0.8, -0.6), Vector3(0.0, -0.6, 0.8), 0.15, 0.55, -0.17],
			"axis": Vector3(0.0, 0.0, 1.0),
			"turns": 1.0,
			"wind": 0.9,
		},
	},
	"bat": {
		# Hands together at the knob. A flat swing and a backhand; the heavy blow is a home run, cocked high
		# behind the right shoulder and finished all the way round over the left.
		"ready": [Vector3(0.08, -0.42, -0.2), Vector3(-0.4, -0.38, -0.83), Vector3(0.0, -0.9, 0.42), -0.25, 0.04, -0.11],
		"fp_ready": [Vector3(0.06, -0.3, -0.38), Vector3(-0.55, -0.1, -0.83), Vector3(0.0, -1.0, 0.1), -0.25, 0.04, -0.11],
		"taps": [
			{
				"wound": [Vector3(0.12, -0.08, -0.24), Vector3(0.75, 0.4, 0.55), Vector3(0.35, 0.0, -0.94), -0.8, -0.08, -0.11],
				"fp_wound": [Vector3(0.1, -0.1, -0.36), Vector3(0.5, 0.85, 0.1), Vector3(0.35, 0.0, -0.94), -0.6, -0.05, -0.11],
				"lead": [Vector3(0.14, -0.14, -0.3), Vector3(0.92, 0.12, -0.3), Vector3(-0.3, 0.0, -0.95), -0.35, 0.05, -0.11],
				"hit": [Vector3(0.02, -0.18, -0.42), Vector3(0.15, 0.03, -0.99), Vector3(-1.0, 0.0, 0.0), 0.15, 0.2, -0.11],
				"end": [Vector3(-0.1, -0.16, -0.3), Vector3(-0.95, 0.0, -0.2), Vector3(-0.4, 0.0, 0.9), 0.85, 0.2, -0.11],
			},
			{
				"wound": [Vector3(-0.08, -0.1, -0.26), Vector3(-0.75, 0.4, 0.55), Vector3(0.35, 0.0, 0.94), 0.75, -0.08, -0.11],
				"fp_wound": [Vector3(-0.4, -0.24, -0.32), Vector3(-0.7, 0.68, 0.2), Vector3(0.35, 0.0, 0.94), 0.55, -0.05, -0.11],
				"lead": [Vector3(-0.1, -0.15, -0.3), Vector3(-0.92, 0.12, -0.3), Vector3(-0.3, 0.0, 0.95), 0.35, 0.05, -0.11],
				"hit": [Vector3(0.02, -0.18, -0.42), Vector3(-0.15, 0.03, -0.99), Vector3(-1.0, 0.0, 0.0), -0.1, 0.2, -0.11],
				"end": [Vector3(0.14, -0.16, -0.28), Vector3(0.95, 0.0, -0.2), Vector3(-0.4, 0.0, -0.9), -0.85, 0.2, -0.11],
			},
		],
		"heavy": {
			"wound": [Vector3(0.16, 0.0, -0.12), Vector3(0.25, 0.8, 0.55), Vector3(0.6, 0.0, -0.8), -1.2, -0.1, -0.11],
			"fp_wound": [Vector3(0.06, -0.02, -0.4), Vector3(0.42, 0.88, 0.22), Vector3(-0.3, -0.3, -0.9), -0.85, -0.12, -0.11],
			"lead": [Vector3(0.14, -0.12, -0.3), Vector3(0.92, 0.0, -0.38), Vector3(-0.38, 0.0, -0.92), -0.4, 0.1, -0.11],
			"hit": [Vector3(0.0, -0.16, -0.44), Vector3(0.2, 0.08, -0.98), Vector3(-1.0, 0.0, 0.0), 0.3, 0.22, -0.11],
			"end": [Vector3(-0.12, 0.02, -0.2), Vector3(-0.45, 0.55, 0.7), Vector3(0.7, 0.1, 0.7), 1.25, 0.05, -0.11],
		},
		# In mid-air: coiled right back like a batter, knees up, and the home run carries the body on round a
		# whole turn after it lands.
		"air": {
			"wound": [Vector3(0.18, 0.04, -0.04), Vector3(0.15, 0.85, 0.5), Vector3(0.6, 0.0, -0.8), -1.5, -0.25, -0.11],
			"fp_wound": [Vector3(0.06, -0.02, -0.4), Vector3(0.42, 0.88, 0.22), Vector3(-0.3, -0.3, -0.9), -0.85, -0.12, -0.11],
			"lead": [Vector3(0.14, -0.12, -0.3), Vector3(0.92, 0.0, -0.38), Vector3(-0.38, 0.0, -0.92), -0.4, 0.1, -0.11],
			"hit": [Vector3(0.0, -0.16, -0.44), Vector3(0.2, 0.08, -0.98), Vector3(-1.0, 0.0, 0.0), 0.3, 0.22, -0.11],
			"end": [Vector3(-0.12, 0.02, -0.2), Vector3(-0.45, 0.55, 0.7), Vector3(0.7, 0.1, 0.7), 1.25, 0.05, -0.11],
			"axis": Vector3(0.0, 1.0, 0.0),
			"after": 1.0,
		},
	},
	"spear": {
		# Carried level at the hip, the left hand forward on the shaft. Every blow is a thrust: quick jabs, high
		# then low; the heavy blow is drawn far back and driven right out, the shaft turning as it goes.
		"ready": [Vector3(0.14, -0.3, -0.02), Vector3(-0.3, -0.12, -0.95), Vector3(0.0, -1.0, 0.0), -0.3, 0.0, 0.27],
		"fp_ready": [Vector3(0.12, -0.2, -0.1), Vector3(-0.34, 0.06, -0.94), Vector3(0.0, -1.0, 0.0), -0.24, 0.0, 0.27],
		"taps": [
			{
				"wound": [Vector3(0.22, -0.16, 0.06), Vector3(-0.6, 0.12, -0.79), Vector3(0.0, -1.0, 0.0), -0.55, -0.08, 0.27],
				"hit": [Vector3(0.02, -0.08, -0.38), Vector3(0.5, 0.1, -0.86), Vector3(0.0, -1.0, 0.0), 0.3, 0.3, 0.05],
				"fp_hit": [Vector3(0.06, -0.1, -0.3), Vector3(-0.14, 0.04, -0.99), Vector3(0.0, -1.0, 0.0), 0.3, 0.3, 0.05],
				"end": [Vector3(0.0, -0.09, -0.42), Vector3(0.55, 0.08, -0.83), Vector3(0.0, -1.0, 0.0), 0.36, 0.36, 0.05],
				"fp_end": [Vector3(0.05, -0.11, -0.33), Vector3(-0.14, 0.02, -0.99), Vector3(0.0, -1.0, 0.0), 0.36, 0.36, 0.05],
			},
			{
				"wound": [Vector3(0.22, -0.28, 0.06), Vector3(-0.6, -0.1, -0.79), Vector3(0.0, -1.0, 0.0), -0.55, -0.08, 0.27],
				"hit": [Vector3(0.02, -0.2, -0.33), Vector3(0.5, -0.22, -0.86), Vector3(0.0, -1.0, 0.0), 0.3, 0.3, 0.05],
				"fp_hit": [Vector3(0.06, -0.22, -0.3), Vector3(-0.14, -0.12, -0.99), Vector3(0.0, -1.0, 0.0), 0.3, 0.3, 0.05],
				"end": [Vector3(0.0, -0.21, -0.37), Vector3(0.55, -0.26, -0.83), Vector3(0.0, -1.0, 0.0), 0.36, 0.36, 0.05],
				"fp_end": [Vector3(0.05, -0.23, -0.33), Vector3(-0.14, -0.14, -0.99), Vector3(0.0, -1.0, 0.0), 0.36, 0.36, 0.05],
			},
		],
		"heavy": {
			"wound": [Vector3(0.28, -0.16, 0.14), Vector3(-0.82, 0.04, -0.57), Vector3(0.0, -1.0, 0.0), -0.95, -0.18, 0.3],
			"hit": [Vector3(0.0, -0.12, -0.44), Vector3(0.64, 0.0, -0.77), Vector3(0.77, 0.0, 0.64), 0.42, 0.4, 0.04],
			"fp_hit": [Vector3(0.05, -0.12, -0.34), Vector3(-0.12, 0.0, -0.99), Vector3(0.99, 0.0, -0.12), 0.42, 0.4, 0.04],
			"end": [Vector3(0.0, -0.13, -0.45), Vector3(0.66, 0.0, -0.75), Vector3(0.75, 0.0, 0.66), 0.46, 0.44, 0.04],
			"fp_end": [Vector3(0.05, -0.13, -0.35), Vector3(-0.12, -0.02, -0.99), Vector3(0.99, 0.0, -0.12), 0.46, 0.44, 0.04],
		},
		# In mid-air: arched back like a javelin thrower, the spear raised over the shoulder, into a thrust driven down
		# ahead as the body dives after it.
		"air": {
			"wound": [Vector3(0.24, 0.28, -0.02), Vector3(-0.67, -0.3, -0.67), Vector3(0.0, -1.0, 0.0), -0.4, -0.45, 0.2],
			"hit": [Vector3(0.0, -0.16, -0.44), Vector3(0.62, -0.15, -0.77), Vector3(0.78, 0.0, 0.63), 0.42, 0.5, 0.04],
			"fp_hit": [Vector3(0.05, -0.16, -0.34), Vector3(-0.12, -0.3, -0.95), Vector3(0.99, 0.0, -0.12), 0.42, 0.6, 0.04],
			"end": [Vector3(0.0, -0.17, -0.46), Vector3(0.63, -0.17, -0.76), Vector3(0.77, 0.0, 0.64), 0.46, 0.52, 0.04],
			"fp_end": [Vector3(0.05, -0.17, -0.35), Vector3(-0.12, -0.32, -0.94), Vector3(0.99, 0.0, -0.12), 0.46, 0.65, 0.04],
		},
	},
	"dagger": {
		# One hand, the other fist up in a guard. A forehand slash and a backhand; the heavy blow is a stab,
		# drawn back to the ribs and lunged straight out.
		"ready": [Vector3(0.2, -0.3, -0.2), Vector3(-0.2, 0.45, -0.87), Vector3(-0.5, -0.5, -0.7), -0.2, 0.0, 0.0],
		"fp_ready": [Vector3(0.2, -0.2, -0.3), Vector3(-0.1, 0.62, -0.78), Vector3(-0.6, -0.2, -0.6), -0.08, 0.0, 0.0],
		"taps": [
			{
				"wound": [Vector3(0.34, -0.08, -0.1), Vector3(0.62, 0.3, -0.72), Vector3(0.75, 0.0, 0.66), -0.75, -0.05, 0.0],
				"hit": [Vector3(0.04, -0.14, -0.44), Vector3(-0.5, 0.1, -0.86), Vector3(-0.86, 0.0, 0.5), 0.25, 0.2, 0.0],
				"end": [Vector3(-0.12, -0.15, -0.3), Vector3(-0.95, 0.0, -0.3), Vector3(-0.3, 0.0, 0.95), 0.7, 0.15, 0.0],
			},
			{
				"wound": [Vector3(-0.14, -0.1, -0.24), Vector3(-0.75, 0.3, 0.1), Vector3(-0.1, 0.0, -1.0), 0.7, -0.05, 0.0],
				"hit": [Vector3(0.06, -0.14, -0.44), Vector3(0.35, 0.1, -0.93), Vector3(0.93, 0.0, 0.35), -0.2, 0.2, 0.0],
				"end": [Vector3(0.32, -0.16, -0.2), Vector3(0.95, 0.0, -0.3), Vector3(0.3, 0.0, 0.95), -0.7, 0.15, 0.0],
			},
		],
		"heavy": {
			"wound": [Vector3(0.3, -0.16, 0.04), Vector3(-0.25, 0.05, -0.97), Vector3(0.0, -1.0, 0.0), -0.9, -0.1, 0.0],
			"hit": [Vector3(0.02, -0.12, -0.5), Vector3(0.6, 0.0, -0.8), Vector3(0.0, -1.0, 0.0), 0.4, 0.4, 0.0],
			"fp_hit": [Vector3(0.1, -0.14, -0.46), Vector3(-0.2, 0.0, -0.98), Vector3(0.0, -1.0, 0.0), 0.4, 0.4, 0.0],
			"end": [Vector3(0.0, -0.12, -0.52), Vector3(0.64, 0.0, -0.77), Vector3(0.0, -1.0, 0.0), 0.45, 0.44, 0.0],
			"fp_end": [Vector3(0.1, -0.14, -0.48), Vector3(-0.2, -0.02, -0.98), Vector3(0.0, -1.0, 0.0), 0.45, 0.44, 0.0],
		},
		# In mid-air: a dive. The body arches back, the dagger drawn back to the ribs, then throws itself
		# forward and down head first behind a stab at full stretch.
		"air": {
			"wound": [Vector3(0.3, -0.14, 0.08), Vector3(-0.25, 0.15, -0.96), Vector3(0.0, -1.0, 0.0), -0.7, -0.3, 0.0],
			"fp_wound": [Vector3(0.28, -0.22, -0.2), Vector3(-0.1, 0.1, -0.99), Vector3(0.0, -1.0, 0.0), -0.4, -0.05, 0.0],
			"hit": [Vector3(0.04, 0.3, -0.44), Vector3(0.5, 0.5, -0.7), Vector3(0.0, -1.0, 0.0), 0.4, 0.2, 0.0],
			"fp_hit": [Vector3(0.1, -0.16, -0.46), Vector3(-0.2, -0.2, -0.96), Vector3(0.0, -1.0, 0.0), 0.4, 0.5, 0.0],
			"end": [Vector3(0.03, 0.3, -0.46), Vector3(0.52, 0.48, -0.7), Vector3(0.0, -1.0, 0.0), 0.45, 0.22, 0.0],
			"fp_end": [Vector3(0.1, -0.17, -0.48), Vector3(-0.2, -0.22, -0.95), Vector3(0.0, -1.0, 0.0), 0.45, 0.52, 0.0],
			"axis": Vector3(-1.0, 0.0, 0.0),
			"dive": Vector2(0.3, 0.8),
		},
	},
	"brass_knuckles": {
		# Both fists, held loose. Hooks that take turns, the left then the right (a blow marked "left" is the
		# left fist's, its keys as if it were the right); the heavy blow is a right uppercut from down by the hip.
		"fists": true,
		"ready": [Vector3(0.15, -0.2, -0.26), Vector3(0.0, 1.0, 0.1), Vector3(0.0, 0.0, -1.0), 0.0, 0.0, 0.0],
		"fp_ready": [Vector3(0.16, -0.12, -0.3), Vector3(0.0, 1.0, 0.1), Vector3(0.0, 0.0, -1.0), 0.0, 0.0, 0.0],
		"taps": [
			{
				"wound": [Vector3(0.34, -0.1, -0.06), Vector3(0.0, 1.0, 0.0), Vector3(0.4, 0.0, -0.92), -0.75, -0.05, 0.0],
				"hit": [Vector3(0.0, -0.08, -0.42), Vector3(0.0, 1.0, 0.0), Vector3(-0.95, 0.0, -0.3), 0.35, 0.2, 0.0],
				"end": [Vector3(-0.13, -0.1, -0.3), Vector3(0.0, 1.0, 0.0), Vector3(-0.8, 0.0, 0.6), 0.75, 0.14, 0.0],
				"way": Vector2(-1.0, 0.0),
				"left": true,
			},
			{
				"wound": [Vector3(0.34, -0.1, -0.06), Vector3(0.0, 1.0, 0.0), Vector3(0.4, 0.0, -0.92), -0.75, -0.05, 0.0],
				"hit": [Vector3(0.0, -0.08, -0.42), Vector3(0.0, 1.0, 0.0), Vector3(-0.95, 0.0, -0.3), 0.35, 0.2, 0.0],
				"end": [Vector3(-0.13, -0.1, -0.3), Vector3(0.0, 1.0, 0.0), Vector3(-0.8, 0.0, 0.6), 0.75, 0.14, 0.0],
				"way": Vector2(-1.0, 0.0),
			},
		],
		"heavy": {
			"wound": [Vector3(0.26, -0.44, -0.1), Vector3(0.9, 0.3, 0.0), Vector3(0.0, 0.3, -0.95), -0.8, 0.3, 0.0],
			"hit": [Vector3(0.06, -0.02, -0.36), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, -0.1), 0.4, -0.1, 0.0],
			"end": [Vector3(0.02, 0.2, -0.28), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.95, 0.3), 0.7, -0.22, 0.0],
			"way": Vector2(0.0, 1.0),
		},
		# In mid-air: a superman punch. The right knee comes up as if to kick and the right fist is cocked by
		# the jaw; then the leg snaps straight back and the fist goes straight out, the body flung flat behind it.
		"air": {
			"wound": [Vector3(0.24, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0), -0.7, -0.15, 0.0],
			"fp_wound": [Vector3(0.26, -0.24, -0.16), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0), -0.6, -0.1, 0.0],
			"hit": [Vector3(0.04, 0.2, -0.49), Vector3(0.0, 0.85, 0.53), Vector3(0.0, 0.53, -0.85), 0.6, 0.25, 0.0],
			"fp_hit": [Vector3(0.06, -0.04, -0.5), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0), 0.45, 0.2, 0.0],
			"end": [Vector3(0.03, 0.2, -0.51), Vector3(0.0, 0.85, 0.53), Vector3(0.0, 0.53, -0.85), 0.65, 0.28, 0.0],
			"fp_end": [Vector3(0.05, -0.05, -0.52), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0), 0.5, 0.22, 0.0],
			"axis": Vector3(-1.0, 0.0, 0.0),
			"dive": Vector2(0.1, 0.4),
			"legs": [[1.6, 1.9, 0.05, 0.25], [-1.0, 0.1, 0.6, 1.3]],
		},
	},
	"karate": {
		# No weapon at all: fists up in a fighting guard, and a combo of six that runs on as long as you keep
		# swinging (see "taps": each blow is the next one along, back to the first after a pause). A jab and a
		# cross, a roundhouse kick, a left hook, a spinning back fist and a spinning hook kick. The heavy blow
		# is a tornado kick: a hop, a whole turn in the air and the right foot round at head height. Off the
		# ground: a helicopter kick, two turns with the right leg straight out.
		# Kicks give "legs" (chambered, landing, and perhaps follow-through: see _leg_keys) and the foot
		# that strikes ("limb", for its trail); the arms keep a guard or fling out for balance.
		# Spinning blows give "turns" (+ to the left), and every blow its own "pace" against the weapon's.
		"fists": true,
		"ready": [Vector3(0.13, -0.1, -0.28), Vector3(0.0, 1.0, 0.25), Vector3(0.0, -0.25, -1.0), 0.0, 0.0, 0.0],
		"fp_ready": [Vector3(0.15, -0.12, -0.3), Vector3(0.0, 1.0, 0.15), Vector3(0.0, 0.0, -1.0), 0.0, 0.0, 0.0],
		"taps": [
			{   # jab: the left fist straight out, turning over as it lands
				"wound": [Vector3(0.16, -0.08, -0.2), Vector3(0.0, 1.0, 0.2), Vector3(0.0, -0.2, -1.0), -0.2, -0.04, 0.0],
				"hit": [Vector3(0.1, -0.02, -0.56), Vector3(-1.0, 0.0, 0.05), Vector3(0.0, 0.0, -1.0), 0.45, 0.14, 0.0],
				"end": [Vector3(0.11, -0.03, -0.52), Vector3(-1.0, 0.05, 0.05), Vector3(0.0, 0.0, -1.0), 0.45, 0.14, 0.0],
				"fp_hit": [Vector3(0.1, -0.04, -0.56), Vector3(-1.0, 0.0, 0.05), Vector3(0.0, 0.0, -1.0), 0.35, 0.1, 0.0],
				"fp_end": [Vector3(0.11, -0.05, -0.52), Vector3(-1.0, 0.05, 0.05), Vector3(0.0, 0.0, -1.0), 0.35, 0.1, 0.0],
				"left": true,
				"pace": 0.8,
			},
			{   # cross: the right fist from the chin, the hips and shoulders turning in behind it
				"wound": [Vector3(0.2, -0.08, -0.12), Vector3(0.0, 1.0, 0.2), Vector3(0.0, -0.2, -1.0), -0.45, -0.06, 0.0],
				"hit": [Vector3(0.0, -0.02, -0.58), Vector3(-1.0, 0.0, 0.05), Vector3(0.0, 0.0, -1.0), 0.75, 0.24, 0.0],
				"end": [Vector3(0.0, -0.03, -0.55), Vector3(-1.0, 0.05, 0.05), Vector3(0.0, 0.0, -1.0), 0.8, 0.24, 0.0],
				"fp_hit": [Vector3(0.04, -0.04, -0.58), Vector3(-1.0, 0.0, 0.05), Vector3(0.0, 0.0, -1.0), 0.6, 0.18, 0.0],
				"fp_end": [Vector3(0.04, -0.05, -0.55), Vector3(-1.0, 0.05, 0.05), Vector3(0.0, 0.0, -1.0), 0.6, 0.18, 0.0],
				"pace": 0.9,
			},
			{   # roundhouse kick: the right knee up, the hips turned right over and the shin snapped round
				"wound": [Vector3(0.14, -0.08, -0.26), Vector3(0.0, 1.0, 0.2), Vector3(0.0, -0.2, -1.0), -0.35, -0.05, 0.0],
				"hit": [Vector3(0.3, -0.3, 0.06), Vector3(0.0, 1.0, 0.3), Vector3(0.4, 0.0, -0.9), 1.0, -0.3, 0.0],
				"end": [Vector3(0.26, -0.24, -0.02), Vector3(0.0, 1.0, 0.3), Vector3(0.4, 0.0, -0.9), 1.15, -0.28, 0.0],
				"fp_hit": [Vector3(0.3, -0.24, -0.1), Vector3(0.0, 1.0, 0.3), Vector3(0.4, 0.0, -0.9), 0.6, -0.1, 0.0],
				"fp_end": [Vector3(0.26, -0.2, -0.14), Vector3(0.0, 1.0, 0.3), Vector3(0.4, 0.0, -0.9), 0.7, -0.1, 0.0],
				"legs": [[1.7, 2.2, -0.05, 0.25, 0.8, 0.0], [2.15, 0.1, -0.1, 0.15, 1.2, 0.0], [1.9, 0.6, -0.1, 0.15, 1.1, 0.0]],
				"limb": "foot_r",
				"way": Vector2(-1.0, 0.2),
				"pace": 1.3,
				"strike": 1.8,
			},
			{   # left hook: wide from the side, the body turning hard through it
				"wound": [Vector3(0.34, -0.1, -0.06), Vector3(0.0, 1.0, 0.0), Vector3(0.4, 0.0, -0.92), -0.75, -0.05, 0.0],
				"hit": [Vector3(0.0, -0.06, -0.44), Vector3(0.0, 1.0, 0.0), Vector3(-0.95, 0.0, -0.3), 0.45, 0.2, 0.0],
				"end": [Vector3(-0.14, -0.08, -0.3), Vector3(0.0, 1.0, 0.0), Vector3(-0.8, 0.0, 0.6), 0.85, 0.14, 0.0],
				"way": Vector2(-1.0, 0.0),
				"left": true,
				"pace": 0.9,
			},
			{   # spinning back fist: a whole turn to the right, the left arm flung out and whipped round level
				"wound": [Vector3(0.3, -0.06, -0.1), Vector3(0.0, 1.0, 0.0), Vector3(0.6, 0.0, -0.8), -0.6, -0.05, 0.0],
				"lead": [Vector3(0.5, 0.0, -0.1), Vector3(0.0, 1.0, 0.0), Vector3(0.2, 0.0, -0.98), -0.3, 0.0, 0.0],
				"hit": [Vector3(0.08, 0.0, -0.54), Vector3(0.0, 1.0, 0.0), Vector3(-1.0, 0.0, 0.0), 0.3, 0.1, 0.0],
				"end": [Vector3(-0.2, -0.02, -0.42), Vector3(0.0, 1.0, 0.0), Vector3(-0.7, 0.0, 0.7), 0.7, 0.1, 0.0],
				"fp_lead": [Vector3(0.45, -0.04, -0.3), Vector3(0.0, 1.0, 0.0), Vector3(0.2, 0.0, -0.98), -0.3, 0.0, 0.0],
				"way": Vector2(-1.0, 0.0),
				"left": true,
				"turns": -1.0,
				"pace": 1.4,
				"strike": 2.6,
			},
			{   # spinning hook kick: a whole turn to the right, the right leg straight and swept round high
				"wound": [Vector3(0.14, -0.08, -0.26), Vector3(0.0, 1.0, 0.2), Vector3(0.0, -0.2, -1.0), -0.4, -0.05, 0.0],
				"hit": [Vector3(-0.1, -0.12, -0.2), Vector3(0.0, 1.0, 0.25), Vector3(0.0, -0.2, -1.0), -0.6, -0.3, 0.0],
				"end": [Vector3(-0.06, -0.1, -0.22), Vector3(0.0, 1.0, 0.25), Vector3(0.0, -0.2, -1.0), -0.9, -0.25, 0.0],
				"fp_hit": [Vector3(0.0, -0.12, -0.26), Vector3(0.0, 1.0, 0.25), Vector3(0.0, -0.2, -1.0), -0.3, -0.1, 0.0],
				"fp_end": [Vector3(0.02, -0.1, -0.28), Vector3(0.0, 1.0, 0.25), Vector3(0.0, -0.2, -1.0), -0.4, -0.1, 0.0],
				"legs": [[1.1, 1.8, 0.05, 0.3, 0.6, 0.0], [2.25, 0.05, -0.05, 0.15, 1.15, 0.0], [1.9, 0.35, -0.05, 0.15, 1.0, 0.0]],
				"limb": "foot_r",
				"way": Vector2(1.0, 0.1),
				"turns": -1.0,
				"pace": 1.6,
				"strike": 3.0,
			},
		],
		"heavy": {   # tornado kick: crouched low and coiled, then a hop and a whole turn, the right foot round at head height
			"wound": [Vector3(0.2, -0.2, -0.14), Vector3(0.0, 1.0, 0.2), Vector3(0.4, -0.2, -0.9), -1.2, 0.15, 0.0],
			"lead": [Vector3(0.36, 0.06, -0.06), Vector3(0.0, 1.0, 0.0), Vector3(0.6, 0.0, -0.8), -0.6, -0.1, 0.0],
			"hit": [Vector3(0.0, -0.1, -0.24), Vector3(0.0, 1.0, 0.25), Vector3(0.0, -0.2, -1.0), -0.4, -0.35, 0.0],
			"end": [Vector3(0.04, -0.1, -0.24), Vector3(0.0, 1.0, 0.25), Vector3(0.0, -0.2, -1.0), -0.7, -0.3, 0.0],
			"fp_wound": [Vector3(0.22, -0.2, -0.24), Vector3(0.0, 1.0, 0.2), Vector3(0.4, -0.2, -0.9), -0.8, 0.1, 0.0],
			"fp_lead": [Vector3(0.36, -0.02, -0.2), Vector3(0.0, 1.0, 0.0), Vector3(0.6, 0.0, -0.8), -0.4, -0.05, 0.0],
			"fp_hit": [Vector3(0.04, -0.12, -0.28), Vector3(0.0, 1.0, 0.25), Vector3(0.0, -0.2, -1.0), -0.3, -0.1, 0.0],
			"fp_end": [Vector3(0.06, -0.12, -0.28), Vector3(0.0, 1.0, 0.25), Vector3(0.0, -0.2, -1.0), -0.4, -0.1, 0.0],
			"legs": [[0.6, 1.9, 1.3, 2.2, 0.3, 0.2], [2.35, 0.05, 0.9, 2.0, 1.05, 0.1], [2.0, 0.4, 0.7, 1.7, 0.9, 0.1]],
			"limb": "foot_r",
			"way": Vector2(1.0, 0.2),
			"turns": -1.0,
			"hop": 4.5,
			"pace": 1.5,
			"strike": 3.0,
		},
		# In mid-air: a helicopter kick. Two turns to the right, arms flung wide and the right leg straight out
		# to the side, sweeping everything round you.
		"air": {
			"wound": [Vector3(0.48, 0.04, -0.12), Vector3(0.0, 1.0, 0.0), Vector3(0.3, 0.0, -0.95), -0.3, -0.1, 0.0],
			"fp_wound": [Vector3(0.4, -0.06, -0.3), Vector3(0.0, 1.0, 0.0), Vector3(0.3, 0.0, -0.95), -0.2, -0.05, 0.0],
			"hit": [Vector3(0.1, -0.02, -0.5), Vector3(0.0, 1.0, 0.0), Vector3(-1.0, 0.0, 0.0), 0.3, 0.1, 0.0],
			"end": [Vector3(-0.16, -0.06, -0.36), Vector3(0.0, 1.0, 0.0), Vector3(-0.7, 0.0, 0.7), 0.6, 0.1, 0.0],
			"legs": [[1.45, 0.15, 0.5, 1.7, 1.25, 0.25], [1.55, 0.0, 0.4, 1.9, 1.35, 0.2]],
			"limb": "foot_r",
			"axis": Vector3(0.0, 1.0, 0.0),
			"turns": -2.0,
			"wind": 0.75,
		},
	},
}
## How long the blow, follow-through and recovery take, against the sword's.
const PACE := {"sword": 1.0, "hammer": 1.3, "dagger": 0.6, "brass_knuckles": 0.55, "spear": 0.85, "axe": 1.15, "bat": 1.1,
	"scythe": 1.2, "mace": 1.05, "machete": 0.7, "wrench": 0.9, "energy_sword": 0.85,
	"karate": 0.62}
## The newer blades swing like one of the first seven: the machete and energy sword
## cut like the longsword, the mace and wrench like the hammer, and the scythe sweeps
## wide like the bat.
const MOVES_LIKE := {"machete": "sword", "energy_sword": "sword", "mace": "hammer",
	"wrench": "hammer", "scythe": "bat"}
## One-handed weapons: where the left fist is held, up in a guard.
const GUARD := Vector3(-0.13, -0.1, -0.3)
## Which way each elbow points (down, out and a little back), in the hold frame.
const ELBOW_R := Vector3(0.55, -0.8, 0.25)
const ELBOW_L := Vector3(-0.55, -0.8, 0.25)
## How much of the chest's turn the hips make too, and how far the body tips sideways with it.
const HIPS_TURN := 0.45
const SIDE_LEAN := 0.16
## How much an elbow gives way to keep its wrist straight (0: not at all).
const WRIST_EASE := 1.1

## A ground slam (see GroundSlam), the same for every weapon: on the way down the weapon
## is raised overhead, and it is driven into the floor in front as you land. The fists
## go in knuckles first. (The left hand holds where the weapon's ready stance has it.)
const SLAM_FALL := [Vector3(0.06, 0.22, -0.1), Vector3(0.0, 0.75, 0.66), Vector3(0.0, 0.66, -0.75), 0.0, -0.35, 0.0]
const SLAM_HIT := [Vector3(0.0, -0.4, -0.36), Vector3(0.0, -0.55, -0.83), Vector3(0.0, -0.83, 0.55), 0.0, 0.75, 0.0]
const FIST_SLAM_FALL := [Vector3(0.22, 0.12, -0.08), Vector3(1.0, 0.0, 0.0), Vector3(0.0, -0.3, -0.95), -0.5, -0.3, 0.0]
const FIST_SLAM_HIT := [Vector3(0.06, -0.5, -0.3), Vector3(1.0, 0.0, 0.0), Vector3(0.0, -1.0, -0.1), 0.3, 0.8, 0.0]
const SLAM_STRIKE := 0.05   ## seconds from touching down to the weapon hitting the floor
const SLAM_HOLD := 0.28     ## ...it stays there this long...
const SLAM_RISE := 0.45     ## ...and this long getting back up
const AIR_BLEND := 6.0      ## how quickly a wind-up changes between its ground and mid-air forms (per second)
const SPIN_WIND := 0.8      ## how much of a mid-air spin a full wind-up takes you round, unless the move says: the blow brings the rest
const SPIN_MAX := 12.0      ## the fastest a wind-up turns you (radians a second, for each turn the move makes)
const SPIN_LATE := 0.6      ## a wind-up that leaves the ground wound up further than this still spins as if from here
const SPIN_COMMIT := 0.25   ## let go with less of the turn than this done, the body comes back the short way instead
const SPIN_SETTLE := 14.0   ## how quickly a mid-air spin that is over comes back round to facing forward (radians a second)

enum { REST, WIND, SWING, SLAM }

var weapon := "sword"
var two_handed := true
var both_fists := false    ## a weapon on each fist (brass knuckles): either can strike, see left_fist() and other_fist()
var first_person := false  ## use the first-person keys (set before set_weapon)
var _ready: Array = []
var _taps: Array = []      # the two taps: {"wound", "hit", "end"}
var _heavy := {}
var _air_move := {}        # the mid-air wind-up and blow, if the weapon has one ("air" in MOVES)
var _pace := 1.0
var _phase := REST
var _cur: Array = []       # the pose right now (a key)
var _other: Array = []     # both fists: the fist that is not striking, easing back to ready (a key, as if it were the right)
var _left := false         # both fists: _cur is the left fist's
var _path: Array = []      # the blow in flight: the keys it passes through...
var _times := PackedFloat32Array()   # ...and when (seconds from letting go)
var _sweep: Array = []     # ...and where it is wound from and ends (which way it sweeps)
var _t := 0.0              # seconds into the blow
var _charge := 0.0         # how wound up, 0..1
var _side := 0             # which tap the wind-up is for, or the blow is
var _power := 0.0          # how wound up the blow in flight was
var _is_heavy := false     # the blow in flight is the heavy one
var _drawn := 0.0          # how far the pose itself has drawn back, 0..1 (it lags the charge)
var _wound := false        # wind() was called since the last sample: still holding
var _stop := 0.0           # hit-stop left: the swing is frozen
var _clock := 0.0
var _in_air := false       # the wind-up (or the blow) is a mid-air one
var _air := 0.0            # how far the pose has gone over to its mid-air form, 0..1
var _spin := 0.0           # radians the body has spun round in a mid-air wind-up
var _diving := false       # a mid-air blow is tipping the body over in a dive
var _leg := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]   # a move's own legs: right thigh, right knee, left thigh, left knee, right and left thigh out (radians)
var _leg_w := 0.0          # ...and how much they take over, 0..1
var _spin_base := -1.0     # how wound up the swing was when it left the ground (the spin starts from there); -1: not spinning
var _spinning := false     # a blow is bringing the spin round
var _spin_from := 0.0      # ...from here...
var _spin_first := 0.0     # ...to here as it lands (the end of the turn)...
var _spin_to := 0.0        # ...and on to here by the end of the follow-through
var _length := 0.0         # how long the blow in flight takes
var _bp := 1.0             # the pace of the blow in flight (the weapon's, times the blow's own "pace")...
var _sm := 1.0             # ...and how much longer than that it takes to land (the blow's own "strike")
var _axis := Vector3.UP    # what the body spins about right now (a mid-air move's axis, or UP for a spin on the ground)
var _ground_spin := false  # the spin is a blow's own, on the ground (see "turns" in a blow): your own view leaves it out
var _blow_legs: Array = [] # the blow in flight poses the legs (a kick): its leg keys (see "legs" in a blow)...
var _legs_from: Array = [] # ...and where the legs were as it was let go
var _limb := ""            # the blow in flight is a kick: the foot that strikes ("foot_r", "foot_l")
var _landed := 0.0         # a ground slam has touched down: 1, easing to 0 as you get back up


func _init(weapon_id: String = "sword", in_first_person: bool = false) -> void:
	first_person = in_first_person
	set_weapon(weapon_id)


func set_weapon(weapon_id: String) -> void:
	weapon = weapon_id
	var m := moves(weapon_id)
	_ready = _whole(_pick(m, "ready"))
	_taps = []
	for tap in m.taps:
		_taps.append(_blow(tap))
	_heavy = _blow(m.heavy)
	both_fists = m.get("fists", false)
	_air_move = {}
	if m.has("air"):
		_air_move = _blow(m.air)
		_air_move["axis"] = m.air.get("axis", Vector3.UP)
		_air_move["turns"] = m.air.get("turns", 0.0)
		_air_move["wind"] = m.air.get("wind", SPIN_WIND)
		_air_move["dive"] = m.air.get("dive", Vector2.ZERO)
		_air_move["legs"] = _leg_keys(m.air.get("legs", []))
		_air_move["after"] = m.air.get("after", 0.0)
	_pace = PACE.get(weapon_id, 1.0)
	_bp = _pace
	_sm = 1.0
	two_handed = WeaponData.by_id(weapon_id).two_handed
	stop()


func _blow(from: Dictionary) -> Dictionary:
	return {"wound": _whole(_pick(from, "wound")), "lead": _whole(_pick(from, "lead")), "hit": _whole(_pick(from, "hit")),
		"end": _whole(_pick(from, "end")), "left": from.get("left", false), "way": from.get("way", Vector2.ZERO),
		"pace": from.get("pace", 1.0), "strike": from.get("strike", 1.0), "turns": from.get("turns", 0.0), "legs": _leg_keys(from.get("legs", [])),
		"limb": from.get("limb", ""), "hop": from.get("hop", 0.0)}


## Leg keys with every part filled in: [right thigh, right knee, left thigh, left knee,
## right thigh out, left thigh out] (the last two, how far each thigh is lifted out to its
## own side, are 0 if left out).
static func _leg_keys(keys: Array) -> Array:
	var out := []
	for k in keys:
		out.append(k if (k as Array).size() >= 6 else (k as Array) + [0.0, 0.0])
	return out


## A key with every part filled in (both hands on, unless it says otherwise).
static func _whole(k: Array) -> Array:
	return k if k.size() != HANDS else k + [1.0]


func _pick(from: Dictionary, what: String) -> Array:
	return from["fp_" + what] if first_person and from.has("fp_" + what) else from.get(what, [])


## A weapon's blows (see MOVES).
static func moves(weapon_id: String) -> Dictionary:
	return MOVES.get(MOVES_LIKE.get(weapon_id, weapon_id), MOVES.sword)


## Still winding up this frame: `charge` 0..1 is how far (see WeaponData.charge_of),
## `side` which tap is coming (0 from the right, 1 from the left).
## `in_air`: off the ground, where a weapon winds up its own way (see "air" in MOVES).
func wind(charge: float, side: int = 0, in_air: bool = false) -> void:
	_charge = clampf(charge, 0.0, 1.0)
	_wound = true
	_in_air = in_air and not _air_move.is_empty()
	if not _in_air:
		_spin_base = -1.0
	elif _spin_base < 0.0:
		_spin_base = minf(_charge, SPIN_LATE)
		_axis = _air_move.get("axis", Vector3.UP)
		_ground_spin = false
	if _phase == REST or (_phase == SWING and _t >= (STRIKE * _sm + FOLLOW) * _bp):
		_phase = WIND
		_side = posmod(side, _taps.size())


## Let go: the blow starts from wherever the wind-up had got to. `power` 0..1 is how
## wound up it was: HEAVY_AT or more is the heavy blow, less the tap from `side`,
## and either follows through further the harder it is.
## `in_air`: let go off the ground: a swing wound up enough to be the heavy blow is the
## weapon's mid-air blow instead, and whatever spin the wind-up had comes round to
## the front as it lands.
func swing(power: float, side: int = 0, in_air: bool = false) -> void:
	_phase = SWING
	_t = 0.0
	_stop = 0.0
	_wound = false
	_landed = 0.0
	_power = clampf(power, 0.0, 1.0)
	_side = posmod(side, _taps.size())
	_is_heavy = _power >= HEAVY_AT
	_in_air = in_air and _is_heavy and not _air_move.is_empty()
	var blow: Dictionary = (_air_move if _in_air else _heavy) if _is_heavy else _taps[_side]
	_use_fist(blow.left)
	var through := lerpf(0.8, 1.0, (_power - HEAVY_AT) / (1.0 - HEAVY_AT)) if _is_heavy else lerpf(0.55, 1.0, _power / HEAVY_AT)
	_bp = _pace * float(blow.pace)
	_sm = float(blow.strike)
	var strike := STRIKE * _bp * _sm
	_length = length()
	# A spin under way finishes its turn as the blow lands (and a mid-air blow may carry
	# on round again after it); one barely begun comes back the short way.
	var full: float = TAU * float(_air_move.get("turns", 0.0))
	_spin_base = -1.0
	_spin_from = _spin
	_spin_first = full if full != 0.0 and absf(_spin) >= absf(full) * SPIN_COMMIT else roundf(_spin / TAU) * TAU
	_spin_to = _spin_first + (TAU * float(_air_move.get("after", 0.0)) * (signf(full) if full != 0.0 else 1.0) if _in_air else 0.0)
	_ground_spin = false
	if _in_air:
		_axis = _air_move.get("axis", Vector3.UP)
	elif float(blow.turns) != 0.0:
		# A blow with a spin of its own (a spinning kick): the body goes right round as
		# it comes in, about UP, facing front again as it lands.
		_axis = Vector3.UP
		_ground_spin = true
		_spin_from = _spin - roundf(_spin / TAU) * TAU
		_spin_first = TAU * float(blow.turns)
		_spin_to = _spin_first
	_spinning = _spin != 0.0 or _spin_to != 0.0
	_diving = _in_air and (_air_move.get("dive", Vector2.ZERO) as Vector2).y != 0.0
	if _diving:
		_spinning = false
	_path = [_cur.duplicate(), blow.hit, _mix(blow.hit, blow.end, through), _ready]
	_times = PackedFloat32Array([0.0, strike * HIT_AT, strike + FOLLOW * _bp, _length])
	_sweep = [blow.wound, blow.end, blow.way, blow.left]
	if not (blow.lead as Array).is_empty():
		_path.insert(1, blow.lead)
		_times.insert(1, strike * HIT_AT * LEAD_AT)
	# A kick: the legs go through keys of their own, from wherever they were.
	_limb = blow.limb
	_blow_legs = blow.legs if not _in_air else []
	if not _blow_legs.is_empty():
		_legs_from = _leg.duplicate() if _leg_w > 0.0 else [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		_leg_w = 1.0


## Winding up or swinging (not just holding the weapon ready).
func active() -> bool:
	return _phase != REST


func winding() -> bool:
	return _phase == WIND


func stop() -> void:
	_phase = REST
	_cur = _ready.duplicate()
	_other = _ready.duplicate()
	_air = 0.0
	_spin = 0.0
	_spinning = false
	_diving = false
	_leg_w = 0.0
	_blow_legs = []
	_limb = ""
	_ground_spin = false
	_landed = 0.0
	_in_air = false
	_wound = false
	_charge = 0.0
	_drawn = 0.0


## Seconds from letting go to the blow landing: `step` is which tap of the combo it is,
## `power` how wound up (HEAVY_AT or more: the heavy blow, or off the ground the weapon's
## mid-air one when `in_air`). Every blow of the older weapons takes the same time.
static func impact_time(weapon_id: String, step: int = 0, power: float = 0.0, in_air: bool = false) -> float:
	var blow := blow_of(weapon_id, step, power, in_air)
	return STRIKE * PACE.get(weapon_id, 1.0) * float(blow.get("pace", 1.0)) * float(blow.get("strike", 1.0)) * HIT_AT


## How long a blow takes, from letting go to back at ready (see impact_time).
static func blow_length(weapon_id: String, step: int = 0, power: float = 0.0, in_air: bool = false) -> float:
	var blow := blow_of(weapon_id, step, power, in_air)
	return (STRIKE * float(blow.get("strike", 1.0)) + FOLLOW + RECOVER) * PACE.get(weapon_id, 1.0) * float(blow.get("pace", 1.0))


## A blow's own pace, against the weapon's (a spinning kick takes longer than a jab).
static func blow_pace(weapon_id: String, step: int = 0, power: float = 0.0, in_air: bool = false) -> float:
	return float(blow_of(weapon_id, step, power, in_air).get("pace", 1.0))


## The keys of one blow as MOVES has them (see impact_time for the arguments).
static func blow_of(weapon_id: String, step: int = 0, power: float = 0.0, in_air: bool = false) -> Dictionary:
	var m := moves(weapon_id)
	if power >= HEAVY_AT:
		return m.air if in_air and m.has("air") else m.heavy
	return m.taps[posmod(step, (m.taps as Array).size())]


## How many taps the weapon's combo goes through before it starts again (2 for most:
## one from each side).
static func combo_length(weapon_id: String) -> int:
	return (moves(weapon_id).taps as Array).size()


## Letting go of a blow lifts you this fast (metres a second; a jumping kick), or 0.
static func hop_of(weapon_id: String, step: int = 0, power: float = 0.0, in_air: bool = false) -> float:
	return float(blow_of(weapon_id, step, power, in_air).get("hop", 0.0))


## How long a blow that lands freezes for: longer the more it was wound up.
static func hit_stop_time(power: float) -> float:
	return lerpf(0.05, 0.12, clampf(power, 0.0, 1.0))


## The blow landed: hold the swing still for a moment.
func hit_stop(seconds: float = 0.07) -> void:
	if _phase == SWING:
		_stop = seconds


## In the blow or the start of its follow-through: the blade is cutting (draw its trail).
func cutting() -> bool:
	if _phase == WIND:   # spinning in mid-air, the weapon is already carving the air
		return _air > 0.6 and _charge > 0.25 and float(_air_move.get("turns", 0.0)) != 0.0
	if _phase == SLAM:
		return false
	if _landed > 0.0:
		return _t < SLAM_STRIKE + 0.06
	return _phase == SWING and _t < (STRIKE * _sm + FOLLOW * (1.0 if _is_heavy else 0.7)) * _bp


## A ground slam, on the way down: the weapon is raised overhead. Call every frame of the fall.
func slam_fall() -> void:
	if _phase != SLAM:
		_phase = SLAM
		_use_fist(false)
	_wound = false
	_in_air = false
	_charge = 0.0


## The slam touched down: the weapon is driven into the floor, held there, and brought back up.
func slam_land(power: float) -> void:
	_phase = SWING
	_t = 0.0
	_stop = 0.0
	_power = clampf(power, 0.0, 1.0)
	_is_heavy = true
	_landed = 1.0
	_spin_from = _spin
	_spin_base = -1.0
	_spin_first = roundf(_spin / TAU) * TAU
	_spin_to = _spin_first
	_spinning = _spin != 0.0
	_diving = false
	_length = SLAM_STRIKE + SLAM_HOLD + SLAM_RISE
	var hit := _slam_key(true)
	_path = [_cur.duplicate(), hit, hit, _ready]
	_times = PackedFloat32Array([0.0, SLAM_STRIKE, SLAM_STRIKE + SLAM_HOLD, _length])
	_sweep = [_slam_key(false), hit, Vector2(0, -1), false]


## In a ground slam, falling.
func slamming() -> bool:
	return _phase == SLAM


## How deep in the landing of a ground slam: 1 as it hits, easing to 0 on the way back up.
func landed() -> float:
	return _landed


func _slam_key(hit: bool) -> Array:
	var k: Array = ((FIST_SLAM_HIT if hit else FIST_SLAM_FALL) if both_fists else (SLAM_HIT if hit else SLAM_FALL)).duplicate()
	k[LEFT] = minf(_ready[LEFT], -0.1)   # (a hand up the shaft, as on the spear, comes back behind the other: it would not reach)
	return _whole(k)


## How far the wind-up or blow has gone over to its mid-air form, 0..1.
func air() -> float:
	return _air


## The legs of a mid-air move that poses them: [right thigh, right knee, left thigh, left
## knee, how much they take over 0..1], or [] when it leaves them alone.
func legs() -> Array:
	return [] if _leg_w <= 0.0 else [_leg[0], _leg[1], _leg[2], _leg[3], _leg_w, _leg[4], _leg[5]]


## The legs are a kick's (a blow on the ground), which your own body shows in first person
## too (a mid-air move's legs are only seen from outside).
func legs_kick() -> bool:
	return not _blow_legs.is_empty() and _phase == SWING


## The spin of a mid-air wind-up: which way up the body turns about, and how far round it
## is (radians). Whoever draws the body turns it (see RobotAnimator); in first person
## the arms go round the view instead.
func spin_axis() -> Vector3:
	return _axis


func spin() -> float:
	if first_person and (_air_move.get("dive", Vector2.ZERO) as Vector2) != Vector2.ZERO and not _ground_spin:
		return 0.0   # a dive tips the body, not the view
	if first_person and _ground_spin:
		return 0.0   # a spinning kick on the ground: your own view stays put, the arms and leg come round into it
	return _spin


## The spin under way is a blow's own on the ground (a spinning kick), not a mid-air one.
func ground_spin() -> bool:
	return _ground_spin and _spin != 0.0


## The blow in flight is a kick: the foot that strikes ("foot_r" or "foot_l"), or "".
func kicking() -> String:
	return _limb if _phase == SWING else ""


## The blow in flight is the heavy one, and how wound up it was.
func heavy() -> bool:
	return _phase == SWING and _is_heavy


func power() -> float:
	return _power


## Which way the blow in flight sweeps across the view (x right, y up; zero for a thrust).
func travel() -> Vector2:
	if _sweep.is_empty():
		return Vector2.ZERO
	var across: Vector2 = _sweep[2]
	if across == Vector2.ZERO:
		var d: Vector3 = (_sweep[1][BLADE] as Vector3).normalized() - (_sweep[0][BLADE] as Vector3).normalized()
		across = Vector2(d.x, d.y)
		if across.length_squared() <= 0.09:
			return Vector2.ZERO
	if _sweep[3]:
		across.x = -across.x   # the left fist's blow is the right's in a mirror
	return across.normalized()


## Both fists: the blow or wind-up is the left fist's (the key from sample() is then
## for the left fist, as if it were the right, and other_fist() for the right).
func left_fist() -> bool:
	return both_fists and _left


## Both fists: the pose of the fist that is not striking (a key, as if it were the right fist).
func other_fist() -> Array:
	return _other.duplicate() if both_fists else []


## Makes the left or right fist the one the swing moves; the other carries on from
## where it was, back to ready.
func _use_fist(left: bool) -> void:
	if not both_fists or left == _left:
		return
	var was := _cur
	_cur = _other
	_other = was
	_left = left


## The longest a blow takes, from letting go to back at ready.
func length() -> float:
	return (STRIKE * _sm + FOLLOW + RECOVER) * _bp


## The pose right now (a key, see MOVES); advances the clock by delta.
func sample(delta: float) -> Array:
	_clock += delta
	var follow := 1.0 - exp(-delta * (DRAW_TAP if _phase == WIND and _charge < TAP_SPAN else DRAW))
	match _phase:
		WIND:
			if not _wound:   # let go without a swing (the match ended, a flying kick took over)
				_phase = REST
			else:
				_air = move_toward(_air, 1.0 if _in_air else 0.0, delta * AIR_BLEND)
				_use_fist(_heavy.left if _charge >= TAP_SPAN else _taps[_side].left)
				var target := _wind_target()
				if _air > 0.0:   # in mid-air the weapon winds up its own way
					target = _mix(target, _air_move.wound, smoothstep(0.0, 1.0, _air))
				if _spin_base >= 0.0:
					# ...and the body goes round with the charge: one long spin, most of the
					# way by the time it is fully wound, the rest left for the blow.
					var done := clampf((_charge - _spin_base) / (1.0 - _spin_base), 0.0, 1.0)
					var back: float = (_air_move.dive as Vector2).x   # (a dive arches back first instead)
					if back != 0.0:
						_spin = move_toward(_spin, -back * done, delta * SPIN_MAX * 0.25)
					else:
						_spin = move_toward(_spin, TAU * float(_air_move.turns) * float(_air_move.wind) * done, delta * SPIN_MAX * absf(float(_air_move.turns)))
				elif _spin != 0.0:   # back on the ground part way round: face front again the short way
					_spin = move_toward(_spin, roundf(_spin / TAU) * TAU, delta * SPIN_SETTLE)
				_cur = _mix(_cur, target, follow)
				_drawn = lerpf(_drawn, _wind_depth(), follow)
		SWING:
			_cur = _along(_path, _times, _t)
			_drawn = move_toward(_drawn, 0.0, delta * 8.0)
			if _diving:   # a dive: tipped right over as the blow lands, held through it, level again after
				var over: float = (_air_move.dive as Vector2).y
				var lands: float = _times[_times.size() - 3]
				var ends: float = _times[_times.size() - 2]
				if _t < lands:
					_spin = lerpf(_spin_from, over, _ease_out(_t / maxf(lands, 0.001)))
				elif _t < ends:
					_spin = over
				else:
					_spin = over * (1.0 - smoothstep(ends, _length, _t))
					_diving = _t < _length
			elif _spinning:   # the spin comes round to the front as the blow lands (and may carry on round after it)
				var lands: float = _times[_times.size() - 3]
				var ends: float = _times[_times.size() - 2]
				if _t < lands:
					var u := _t / maxf(lands, 0.001)
					if _ground_spin:
						u = 0.4 * u + 0.6 * u * u   # a spinning kick gathers pace into the blow
					_spin = lerpf(_spin_from, _spin_first, u)
				elif _spin_to != _spin_first and _t < ends:
					_spin = lerpf(_spin_first, _spin_to, _ease_out((_t - lands) / maxf(ends - lands, 0.001)))
				else:
					_spin = 0.0
					_spinning = false
					_ground_spin = false
			if _landed > 0.0:
				_landed = 1.0 - smoothstep(SLAM_STRIKE + SLAM_HOLD, _length, _t)
			if _stop > 0.0:
				_stop -= delta
			else:
				_t += delta
			if _t >= _length:
				_phase = REST
				_charge = 0.0
				_landed = 0.0
		SLAM:
			_cur = _mix(_cur, _slam_key(false), 1.0 - exp(-delta * DRAW_TAP))
	# The legs of a mid-air move that has its own: where they wind up to, snapped to
	# where the blow puts them and held through it, then let go.
	var pair: Array = _air_move.get("legs", [])
	var legs_in := 0.0
	if _phase == SWING and not _blow_legs.is_empty() and _landed == 0.0:
		# A kick: chambered (the knee up) by half way to the moment it lands, snapped out
		# as it lands, held through the follow-through, then let go.
		var lands: float = _times[_times.size() - 3]
		var ends: float = _times[_times.size() - 2]
		var keys: Array = [_legs_from, _blow_legs[0], _blow_legs[1], _blow_legs[2] if _blow_legs.size() > 2 else _blow_legs[1]]
		var at := PackedFloat32Array([0.0, lands * 0.55, lands, ends])
		var i := 0
		while i < 2 and _t > at[i + 1]:
			i += 1
		var u := clampf((_t - at[i]) / maxf(at[i + 1] - at[i], 0.001), 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u) if i != 1 else u * u   # (into the blow it gathers pace)
		for j in 6:
			_leg[j] = lerpf(float(keys[i][j]), float(keys[i + 1][j]), u)
		legs_in = 1.0 if _t < ends + (_length - ends) * 0.35 else 0.0
	elif _phase == WIND and not _in_air:
		# Winding a kick up on the ground: the weight shifts and the knee starts to come up.
		var coming: Dictionary = _heavy if _charge >= TAP_SPAN else _taps[_side]
		if not (coming.legs as Array).is_empty():
			var goal: Array = coming.legs[0]
			for j in 6:
				_leg[j] = lerpf(_leg[j], float(goal[j]) * 0.35, 1.0 - exp(-delta * 14.0))
			legs_in = smoothstep(0.0, 0.5, _charge)
	elif not pair.is_empty():
		var goal: Array = []
		var quick := 10.0
		if _phase == WIND and _in_air:
			goal = pair[0]
			legs_in = smoothstep(0.0, 1.0, _air) * smoothstep(0.0, 0.3, _charge)
		elif _phase == SWING and _in_air and _landed == 0.0:
			goal = pair[1]
			quick = 45.0
			legs_in = 1.0 if _t < _times[_times.size() - 2] else 0.0
		if not goal.is_empty():
			for i in 6:
				_leg[i] = lerpf(_leg[i], goal[i], 1.0 - exp(-delta * quick))
	if _phase != SWING:
		_blow_legs = []
	_leg_w = move_toward(_leg_w, legs_in, delta * (12.0 if legs_in > _leg_w else 5.0))
	if _phase != WIND:
		_air = move_toward(_air, 0.0, delta * AIR_BLEND)
	if _phase != WIND and _phase != SWING and _spin != 0.0:   # a spin left over (landed, let go): back to the front the short way
		var to := roundf(_spin / TAU) * TAU
		_spin = move_toward(_spin, to, delta * SPIN_SETTLE)
		if is_equal_approx(_spin, to):
			_spin = 0.0
	if _phase == REST:
		_cur = _mix(_cur, _ready, 1.0 - exp(-delta * SETTLE))
		_drawn = lerpf(_drawn, 0.0, follow)
	_wound = false
	if both_fists:
		_other = _mix(_other, _ready, 1.0 - exp(-delta * DRAW))
	var out := _cur.duplicate()
	if both_fists:   # the body turns with both fists: one way for the right, the other for the left
		var way := -1.0 if _left else 1.0
		out[TURN] = (float(_cur[TURN]) - float(_other[TURN])) * way
		out[LEAN] = float(_cur[LEAN]) + float(_other[LEAN])
	if _phase == REST:   # at ease: the weapon rides the body's breathing, never quite still
		out[GRIP] = out[GRIP] as Vector3 + Vector3(0.004 * sin(_clock * 1.3), 0.007 * sin(_clock * 1.9), 0.0)
		out[BLADE] = (out[BLADE] as Vector3 + Vector3(0.02 * sin(_clock * 1.1 + 1.0), 0.0, 0.014 * sin(_clock * 1.7))).normalized()
	if _phase == SWING and _stop > 0.0:   # frozen on the blow: the weapon judders against what it hit
		out[GRIP] = out[GRIP] as Vector3 + Vector3(sin(_clock * 173.0), sin(_clock * 211.0), sin(_clock * 131.0)) * 0.006 * lerpf(0.5, 1.0, _power)
	if _phase == WIND and _charge >= 1.0:   # fully wound: straining to hold it
		out[BLADE] = (out[BLADE] as Vector3 + Vector3(sin(_clock * 41.0), sin(_clock * 53.0), 0.0) * 0.022).normalized()
	return out


## Where the wind-up is drawing the weapon to right now. The body leads: it has done
## most of its coiling by half way, and the weapon comes round after it.
func _wind_target() -> Array:
	var tap: Array = _taps[_side].wound
	if _charge < TAP_SPAN:
		return _mix(_ready, tap, MIN_WOUND + (1.0 - MIN_WOUND) * _ease_out(_charge / TAP_SPAN))
	if _taps[_side].left != _heavy.left:
		tap = _ready   # the heavy blow is the other fist's: it comes from ready, and the tap's fist goes back
	var u := (_charge - TAP_SPAN) / (1.0 - TAP_SPAN)
	var out := _mix(tap, _heavy.wound, smoothstep(0.0, 1.0, u))
	var body := _ease_out(u)
	out[TURN] = lerpf(tap[TURN], _heavy.wound[TURN], body)
	out[LEAN] = lerpf(tap[LEAN], _heavy.wound[LEAN], body)
	return out


## ...and how far that is, 0..1.
func _wind_depth() -> float:
	if _charge < TAP_SPAN:
		return 0.3 * (MIN_WOUND + (1.0 - MIN_WOUND) * _ease_out(_charge / TAP_SPAN))
	return lerpf(0.3, 1.0, _ease_out((_charge - TAP_SPAN) / (1.0 - TAP_SPAN)))


## How far the weapon is drawn back right now: -1 fully wound up, 0 at ready or in a
## blow. The first-person view makes room for it.
func coil() -> float:
	return -_drawn if _phase == WIND else 0.0


## How far the chest is turned in the ready stance.
func rest_turn() -> float:
	return _ready[TURN]


## How brightly the weapon's glowing parts shine right now (1 = as at rest): they
## build with the wind-up, flicker when it is full, and flare as the blow goes.
func glow() -> float:
	match _phase:
		SLAM:
			return 3.0
		WIND:
			var full := 0.35 * sin(_clock * 37.0) if _charge >= 1.0 else 0.0
			return 1.0 + 1.6 * _drawn + full
		SWING:
			var flare := lerpf(1.4, 3.2, _power)
			return 1.0 + flare * (1.0 - smoothstep(0.0, (STRIKE * _sm + FOLLOW) * _bp * 1.6, _t))
	return 1.0


## The ready pose of a weapon.
static func ready(weapon_id: String) -> Array:
	return _whole(moves(weapon_id).ready).duplicate()


static func _mix(a: Array, b: Array, u: float) -> Array:
	var ba: Vector3 = (a[BLADE] as Vector3).normalized()
	var bb: Vector3 = (b[BLADE] as Vector3).normalized()
	var la: Vector3 = (a[LEAD] as Vector3).normalized()
	var lb: Vector3 = (b[LEAD] as Vector3).normalized()
	return [(a[GRIP] as Vector3).lerp(b[GRIP], u), _turn(ba, bb, u), _turn(la, lb, u),
		lerpf(a[TURN], b[TURN], u), lerpf(a[LEAN], b[LEAN], u), lerpf(a[LEFT], b[LEFT], u),
		lerpf(a[HANDS] if a.size() > HANDS else 1.0, b[HANDS] if b.size() > HANDS else 1.0, u)]


## From one direction to another along the arc between them.
static func _turn(a: Vector3, b: Vector3, u: float) -> Vector3:
	if a.dot(b) > 0.9995 or a.dot(b) < -0.999:
		return a.lerp(b, u).normalized() if a.dot(b) > 0.0 else a
	return a.slerp(b, u)


## The pose at time t on one smooth curve through `path` (keys) at `times`: it starts
## and ends still, and passes each key in between at speed, so a blow gathers pace into
## the moment it lands and carries on through it.
static func _along(path: Array, times: PackedFloat32Array, t: float) -> Array:
	var last := path.size() - 1
	if t <= times[0]:
		return (path[0] as Array).duplicate()
	if t >= times[last]:
		return (path[last] as Array).duplicate()
	var i := 0
	while i < last - 1 and t > times[i + 1]:
		i += 1
	var span := times[i + 1] - times[i]
	var u := (t - times[i]) / span
	var out := []
	for part in HANDS + 1:
		var a: Variant = path[i][part]
		var b: Variant = path[i + 1][part]
		var turning: bool = part == BLADE or part == LEAD
		if turning:
			a = (a as Vector3).normalized()
			b = (b as Vector3).normalized()
		var v: Variant = _curve(a, b, _slope(path, times, i, part), _slope(path, times, i + 1, part), u, span)
		if turning:
			v = (v as Vector3).normalized() if (v as Vector3).length_squared() > 0.0004 else _turn(a, b, u)
		out.append(v)
	return out


## How fast one part of a key is changing as the curve passes key i (still at both ends).
static func _slope(path: Array, times: PackedFloat32Array, i: int, part: int) -> Variant:
	var here: Variant = path[i][part]
	if i == 0 or i == path.size() - 1:
		return here * 0.0
	var before := times[i] - times[i - 1]
	var after := times[i + 1] - times[i]
	var a: Variant = path[i - 1][part]
	var b: Variant = path[i + 1][part]
	if part == BLADE or part == LEAD:
		a = (a as Vector3).normalized()
		b = (b as Vector3).normalized()
		here = (here as Vector3).normalized()
	# The shorter side counts for more: the blow's speed carries through its landing...
	var into: Variant = (here - a) / before
	var out_of: Variant = (b - here) / after
	var slope: Variant = (into * after + out_of * before) / (before + after)
	# ...but never so fast that it would shoot past the next key and come back (a thrust
	# stops where it lands; a part that turns round at this key is still as it does).
	if slope is Vector3:
		return Vector3(_held(slope.x, into.x, out_of.x), _held(slope.y, into.y, out_of.y), _held(slope.z, into.z, out_of.z))
	return _held(slope, into, out_of)


static func _held(slope: float, into: float, out_of: float) -> float:
	if into * out_of <= 0.0:
		return 0.0
	return signf(slope) * minf(absf(slope), 3.0 * minf(absf(into), absf(out_of)))


static func _curve(a: Variant, b: Variant, slope_a: Variant, slope_b: Variant, u: float, span: float) -> Variant:
	var u2 := u * u
	var u3 := u2 * u
	return a * (2.0 * u3 - 3.0 * u2 + 1.0) + slope_a * (span * (u3 - 2.0 * u2 + u)) + b * (-2.0 * u3 + 3.0 * u2) + slope_b * (span * (u3 - u2))


# ---------------------------------------------------------------------------
# Laying a key over a pose

## How far the body sinks into its knees for key `k`, 0..1: coiled right round (wound
## up, or at the end of a big follow-through) it sits low; at the moment of the blow it is up.
static func sink(k: Array) -> float:
	return smoothstep(0.25, 1.05, absf(k[TURN])) * 0.5


## Turns and leans the whole body with the swing (`weight` 0..1): the hips come round
## with it (and the legs with them), the spine and chest further still, and the body
## tips away from the way it is coiled. Call before hold(), and before anything that
## reads where the chest is.
static func turn_body(pose: RobotPose, bones: Dictionary, k: Array, weight: float = 1.0) -> void:
	if weight <= 0.0:
		return
	var turn: float = k[TURN] * weight
	var lean: float = k[LEAN] * weight
	if bones.has("hips"):
		var hp: int = bones["hips"]
		pose.rot[hp] = Quaternion(Vector3.UP, turn * HIPS_TURN) * pose.rot[hp]
	if bones.has("chest"):
		var c: int = bones["chest"]
		pose.rot[c] = Quaternion(Vector3.UP, turn) * pose.rot[c]
	if bones.has("spine"):
		var sp: int = bones["spine"]
		pose.rot[sp] = Quaternion(Vector3.UP, turn * 0.5) * Quaternion(Vector3.BACK, turn * SIDE_LEAN) * Quaternion(Vector3.RIGHT, -lean) * pose.rot[sp]
	if bones.has("head"):   # the head keeps looking ahead, as far as a neck turns
		var h: int = bones["head"]
		pose.rot[h] = Quaternion(Vector3.UP, clampf(-turn * (1.5 + HIPS_TURN), -1.15, 1.15)) * pose.rot[h]


## Bends the arms so the weapon is where key `k` says: the right hand on the grip,
## and the left on the handle too (`two_handed`) or up in a guard.
## pitch: the hold frame tips up or down by this much (aiming), about the shoulders.
## right, left: how much each arm takes the pose, 0..1 (the left lets go to grapple).
## shift: moves the whole hold (first person: up into view).
## other: a weapon on each fist (see other_fist()): the pose of the fist that is not
## striking. Then `k` is the striking fist's, and `left_strikes` says which fist that is.
static func hold(pose: RobotPose, rig: RobotRig, k: Array, two_handed: bool, pitch: float = 0.0,
		right: float = 1.0, left: float = 1.0, shift: Vector3 = Vector3.ZERO, other: Array = [], left_strikes: bool = false) -> void:
	if right <= 0.0 and left <= 0.0:
		return
	var b := rig.bones
	# Where the chest is, in the model's space.
	var rot := pose.rot[b["root"]]
	var at := pose.pos[b["root"]]
	for bone in ["hips", "spine", "chest"]:
		var i: int = b[bone]
		at += rot * pose.pos[i]
		rot = rot * pose.rot[i]
	var up_r: int = b["upper_arm_r"]
	var up_l: int = b["upper_arm_l"]
	var frame := Basis(rot * Quaternion(Vector3.RIGHT, pitch))
	var origin := at + rot * Vector3(0.0, pose.pos[up_r].y, 0.0)
	var palm: Vector3 = rig.rest_pos[b["pistol"]]   # from the hand bone to the grip
	var kr: Array = other if (left_strikes and not other.is_empty()) else k
	# The weapon: grip, blade (+Y), edge (-Z), in the hold frame and then in the model's space.
	var held := _weapon_basis(kr)
	var blade: Vector3 = frame * held.y
	var hand_rot := (frame * held * MeleeModel.HOLD.inverse()).get_rotation_quaternion()
	var grip: Vector3 = origin + frame * (kr[GRIP] as Vector3 + shift)
	# Right arm
	var solved := _reach(pose, rig, rot, at, "r", grip - hand_rot * palm, hand_rot, frame * ELBOW_R, right)
	if b.has("pistol"):
		pose.rot[b["pistol"]] = pose.rot[b["pistol"]].slerp(Quaternion.IDENTITY, right)
	# The fingers: round the handle, or a fist for a weapon worn on it.
	Hands.set_hand(pose, rig, "fist" if not other.is_empty() else "handle", right, false)
	left *= float(k[HANDS]) if k.size() > HANDS else 1.0
	if left <= 0.0:
		return
	Hands.set_hand(pose, rig, "handle" if two_handed and other.is_empty() else "fist", left, true)
	var hand_l := hand_rot
	var want: Vector3
	if not other.is_empty():
		# The left fist: its own key, as the right fist's would be in a mirror.
		var kl: Array = k if left_strikes else other
		var m := (_weapon_basis(kl) * MeleeModel.HOLD.inverse())
		m = Basis(Vector3(m.x.x, -m.x.y, -m.x.z), Vector3(-m.y.x, m.y.y, m.y.z), Vector3(-m.z.x, m.z.y, m.z.z))
		hand_l = (frame * m).get_rotation_quaternion()
		var there: Vector3 = kl[GRIP] as Vector3 + shift
		want = origin + frame * Vector3(-there.x, there.y, there.z) - hand_l * Vector3(-palm.x, palm.y, palm.z)
		if b.has("pistol_l"):
			pose.rot[b["pistol_l"]] = pose.rot[b["pistol_l"]].slerp(Quaternion.IDENTITY, left)
	elif two_handed:
		# On the handle, coming at it from the left shoulder's side.
		var on_handle: Vector3 = solved + hand_rot * palm + blade * float(k[LEFT])
		var to_shoulder := at + rot * pose.pos[up_l] - on_handle
		to_shoulder = to_shoulder - blade * to_shoulder.dot(blade)
		var wrist := hand_rot * -palm
		wrist = wrist - blade * wrist.dot(blade)
		if to_shoulder.length_squared() > 0.0001 and wrist.length_squared() > 0.000001:
			hand_l = Quaternion(blade, wrist.normalized().signed_angle_to(to_shoulder.normalized(), blade)) * hand_rot
		want = on_handle - hand_l * palm
	else:
		hand_l = Quaternion(frame) * Quaternion(Vector3.RIGHT, 2.2)   # the forearm up, the fist by the chin
		want = origin + frame * (GUARD + shift)
	_reach(pose, rig, rot, at, "l", want, hand_l, frame * ELBOW_L, left)


## Which way key `k` turns the weapon, in the hold frame: its blade (+Y) and its edge (-Z).
static func _weapon_basis(k: Array) -> Basis:
	var blade: Vector3 = (k[BLADE] as Vector3).normalized()
	var lead: Vector3 = k[LEAD]
	lead = (lead - blade * lead.dot(blade)).normalized()
	return Basis(blade.cross(-lead), blade, -lead)


## Two-bone reach: bends one arm so its hand bone is at `want` (as near as it can
## get), turned to `hand_rot`, with the elbow toward `elbow`. All in the model's
## space. Returns where the hand bone ended up.
static func _reach(pose: RobotPose, rig: RobotRig, chest_rot: Quaternion, chest_at: Vector3, side: String,
		want: Vector3, hand_rot: Quaternion, elbow: Vector3, weight: float) -> Vector3:
	var b := rig.bones
	var up: int = b["upper_arm_" + side]
	var fore: int = b["forearm_" + side]
	var hand: int = b["hand_" + side]
	var shoulder := chest_at + chest_rot * pose.pos[up]
	var upper_len := pose.pos[fore].length()
	var fore_len := pose.pos[hand].length()
	var to := want - shoulder
	var dist := clampf(to.length(), absf(upper_len - fore_len) + 0.01, (upper_len + fore_len) * 0.999)
	var dir := to.normalized() if to.length_squared() > 0.000001 else chest_rot * Vector3.FORWARD
	var along := (upper_len * upper_len - fore_len * fore_len + dist * dist) / (2.0 * dist)
	var out := sqrt(maxf(upper_len * upper_len - along * along, 0.0))
	# The elbow: toward `elbow`, giving way to the side that keeps the wrist straight
	# (the forearm in line with the hand's own grip).
	var wrist := hand_rot * Vector3.UP
	var side_dir := (elbow - dir * elbow.dot(dir)).normalized() + (wrist - dir * wrist.dot(dir)) * WRIST_EASE
	side_dir = side_dir.normalized() if side_dir.length_squared() > 0.000001 else dir.cross(chest_rot * Vector3.RIGHT).normalized()
	var elbow_at := shoulder + dir * along + side_dir * out
	var hand_at := shoulder + dir * dist
	var hinge := side_dir.cross(dir).normalized()   # the elbow's axis: both bones' own +X
	var up_y := (shoulder - elbow_at).normalized()
	var fore_y := (elbow_at - hand_at).normalized()
	var up_rot := Basis(hinge, up_y, hinge.cross(up_y)).get_rotation_quaternion()
	var fore_rot := Basis(hinge, fore_y, hinge.cross(fore_y)).get_rotation_quaternion()
	var w := clampf(weight, 0.0, 1.0)
	pose.rot[up] = pose.rot[up].slerp(chest_rot.inverse() * up_rot, w)
	pose.rot[fore] = pose.rot[fore].slerp(up_rot.inverse() * fore_rot, w)
	pose.rot[hand] = pose.rot[hand].slerp(fore_rot.inverse() * hand_rot, w)
	return hand_at


static func _ease_out(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return 1.0 - (1.0 - u) * (1.0 - u)
