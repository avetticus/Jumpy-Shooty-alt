class_name PortraitPoser
extends RefCounted
## How the character on a portrait's stage (RobotPreview, staged) holds its weapon.
##
## The body is the game's own: a RobotAnimator standing still, so the stance, the
## breathing, each torso's own idle habit, a blade's guard and a reload are exactly what
## a match shows (and whatever those gain later shows here too). Over that, every six
## to ten seconds, the character changes between three holds:
##
##   front   the weapon up in front of it: a gun aimed, a blade raised;
##   low     relaxed, both hands still on it: a gun pointed at the floor ahead, a blade
##           in its low guard;
##   side    one-handed, the other arm hanging: a gun down by its leg, a blade trailing
##           behind it, its point just off the floor; or, for the big ones
##           (SHOULDER_GUNS, SHOULDER_MELEE), upright against its shoulder.
##
## Now and then it gets from one to the next with a flourish: a gun's reload (its spent
## cell and all), a blade's cut.

enum { FRONT, LOW, SIDE }

const HOLD_MIN := 6.0          ## seconds in a hold, at least...
const HOLD_MAX := 10.0         ## ...and at most
const FIRST := 3.5             ## the first hold is this short, so it is soon seen to move
const BLEND := 0.85            ## seconds from one hold to the next
const FLOURISH_CHANCE := 0.4   ## how often a change of hold comes with a flourish
const LOW_ANGLE := 0.72        ## radians a gun is lowered in the low hold
const SHELLS := 2              ## a gun loaded a round at a time: this many go in before its last flourish

## The big guns and the long-handled weapons: too much to dangle from one hand.
const SHOULDER_GUNS := ["rocket_launcher", "grenade_launcher", "lmg", "minigun", "anti_materiel", "railgun"]
const SHOULDER_MELEE := ["hammer", "bat", "spear"]

## Where the right hand's grip goes and how the weapon lies, in the chest's own frame at
## shoulder height (x right, y up, -z forward): [grip, where the barrel or blade points,
## where the gun's top (or the blade's edge) faces].
const GUN_SIDE := [Vector3(0.27, -0.585, 0.03), Vector3(0.05, -0.90, -0.43), Vector3(0.0, 0.43, -0.90)]
const GUN_SHOULDER := [Vector3(0.25, -0.44, -0.08), Vector3(0.0, 0.88, 0.47), Vector3(0.0, -0.47, 0.88)]
const BLADE_FRONT := [Vector3(0.12, -0.45, -0.28), Vector3(-0.50, 0.55, -0.67), Vector3(0.0, -0.77, -0.63)]
const BLADE_SIDE := [Vector3(0.30, -0.57, 0.04), Vector3(0.52, -0.50, 0.69), Vector3(0.0, -0.81, -0.59)]
const BLADE_SHOULDER := [Vector3(0.26, -0.52, -0.02), Vector3(0.04, 0.80, 0.60), Vector3(0.0, 0.60, -0.80)]
const ELBOW_DOWN := Vector3(0.35, -0.5, 0.8)     ## which way the right elbow points with the weapon at the side...
const ELBOW_UP := Vector3(0.75, -0.6, 0.25)      ## ...and on the shoulder

var robot: RobotModel
var animator: RobotAnimator
var hold := FRONT          ## the hold it is in, or on its way to

var _inp := RobotAnimInput.new()
var _melee := false
var _fists := false        # a weapon on each fist (or none at all): nothing to hold out or shoulder
var _empty := false        # empty hands
var _akimbo := false
var _shoulder := false
var _two_handed := false
var _w := [1.0, 0.0, 0.0]  # how much of each hold shows (FRONT, LOW, SIDE)
var _left := HOLD_MIN      # seconds until the next change
var _next := -1            # the hold to go to after a flourish at the weapon's own hold
var _flourish := -1.0      # seconds a flourish still has to run, or -1
var _reloading := false
var _reload_for := 0.0     # seconds the reload itself is held on for (the rest is its last flourish)
var _cut := 0
var _arm_l: PackedInt32Array
var _rng := RandomNumberGenerator.new()


## fx: where a reload's spent cell is thrown (a node in the portrait's world that keeps still).
func _init(model: RobotModel, fx: Node = null) -> void:
	robot = model
	animator = RobotAnimator.new(model)
	animator.fx_parent = fx
	_rng.randomize()
	var id := model.weapon
	_empty = id == "none" or id == ""
	if not _empty:
		var data := WeaponData.by_id(id)
		_melee = data.is_melee()
		_akimbo = data.is_akimbo()
		_two_handed = data.two_handed
		_fists = _melee and id in MeleeModel.BOTH_FISTS
		_shoulder = WeaponData.look_of(id) in (SHOULDER_MELEE if _melee else SHOULDER_GUNS)
	hold = _home()
	_w = [0.0, 0.0, 0.0]
	_w[hold] = 1.0
	_left = FIRST
	for n in ["upper_arm_l", "forearm_l", "hand_l"] + Hands.LEFT:
		if model.rig.bones.has(n):
			_arm_l.append(model.rig.bones[n])
	_inp.state = MovementController.State.GROUND
	_inp.alive = true


## The hold the game itself gives this weapon standing still (the others are laid over
## it): a gun is aimed, a blade is in its low guard.
func _home() -> int:
	return LOW if _melee and not _fists else FRONT


## Carry on where another poser (the same character with another gun or colour) was.
func resume(other: PortraitPoser) -> void:
	_left = maxf(other._left, 1.5)


func update(delta: float) -> void:
	_cycle(delta)
	_inp.flags = RobotAnimInput.make_flags(false, false, _reloading, 0, 0)
	animator.update(delta, _inp, robot.global_transform if robot.is_inside_tree() else Transform3D.IDENTITY)
	if _empty:   # nothing to hold: the arms just hang
		var bare: RobotPose = animator._pose
		_hang(bare, 1.0, true, true)
		_hang(bare, 1.0, false, true)
		bare.apply(robot.skeleton)
		robot.settle_sway()
		return
	for i in 3:
		_w[i] = move_toward(_w[i], 1.0 if i == hold else 0.0, delta / BLEND)
	var pose: RobotPose = animator._pose
	var changed := false
	if _melee and not _fists:
		changed = _lay_blade(pose, smoothstep(0.0, 1.0, _w[FRONT]), BLADE_FRONT, true) or changed
		changed = _lay_blade(pose, smoothstep(0.0, 1.0, _w[SIDE]), BLADE_SHOULDER if _shoulder else BLADE_SIDE, false) or changed
	elif _fists:
		changed = _drop_arms(pose, smoothstep(0.0, 1.0, maxf(_w[LOW], _w[SIDE])))
	else:
		changed = _lower_gun(pose, smoothstep(0.0, 1.0, _w[LOW])) or changed
		changed = _lay_gun(pose, smoothstep(0.0, 1.0, _w[SIDE]), GUN_SHOULDER if _shoulder else GUN_SIDE) or changed
	if changed:
		pose.apply(robot.skeleton)
		robot.settle_sway()


## When to change hold, and to what.
func _cycle(delta: float) -> void:
	if _empty:
		return
	if _flourish >= 0.0:
		_flourish -= delta
		_reload_for -= delta
		if _reload_for <= 0.0:
			_reloading = false
		if _flourish <= 0.0 and not (_melee and animator.melee_swing().active()):
			_flourish = -1.0
			_reloading = false
			if _next >= 0:
				hold = _next
				_next = -1
		return
	if _next >= 0:
		# On its way to the weapon's own hold, for a flourish there before going on.
		if _w[_home()] >= 0.999:
			_start_flourish()
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = _rng.randf_range(HOLD_MIN, HOLD_MAX)
	var choices := [FRONT, LOW, SIDE]
	if _fists:
		choices = [FRONT, SIDE]
	choices.erase(hold)
	var to: int = choices[_rng.randi() % choices.size()]
	var home := _home()
	if (hold == home or to == home) and _rng.randf() < FLOURISH_CHANCE and _can_flourish():
		_next = to
		if hold == home:
			_start_flourish()
		else:
			hold = home
		return
	hold = to


func _can_flourish() -> bool:
	if _melee:
		return true
	return animator.rig.has_clip(animator.clip("reload"))


## The flourish: a gun's reload, a blade's cut.
func _start_flourish() -> void:
	if _melee:
		_cut += 1
		animator.swing(0.0, _cut % 2)
		_flourish = 0.3
		return
	var data := WeaponData.by_id(robot.weapon)
	var length := animator.rig.length(animator.clip("reload"))
	_reloading = true
	if data.reload_per_round:
		_reload_for = length * SHELLS - 0.05
		var last := animator.clip("reload_end")
		_flourish = _reload_for + (animator.rig.length(last) if animator.rig.has_clip(last) else 0.0) + 0.25
	else:
		_reload_for = length - 0.05
		_flourish = length + 0.1


## Play the flourish now (for pictures and tests); false if this weapon has none.
func flourish_now() -> bool:
	if _empty or not _can_flourish() or _flourish >= 0.0:
		return false
	hold = _home()
	_w = [0.0, 0.0, 0.0]
	_w[hold] = 1.0
	_next = hold
	_start_flourish()
	return true


## Go straight to a hold (for pictures and tests).
func snap(to: int) -> void:
	hold = to
	_w = [0.0, 0.0, 0.0]
	_w[to] = 1.0
	_next = -1
	_flourish = -1.0
	_reloading = false
	_left = HOLD_MAX


# --- The holds, each laid over the pose the game gave

## The chest in the model's space: [its rotation, where it is].
static func _chest(pose: RobotPose, b: Dictionary) -> Array:
	var rot := pose.rot[b["root"]]
	var at := pose.pos[b["root"]]
	for bone in ["hips", "spine", "chest"]:
		var i: int = b[bone]
		at += rot * pose.pos[i]
		rot = rot * pose.rot[i]
	return [rot, at]


## A gun, low: both arms swing down about the shoulders, the way they follow your aim
## when you look at the floor, and the body stays as it was.
func _lower_gun(pose: RobotPose, w: float) -> bool:
	if w <= 0.0:
		return false
	var b := animator.rig.bones
	var across: Vector3 = animator._stance.inverse() * Vector3.RIGHT
	var down := Quaternion(across.normalized(), -LOW_ANGLE * w)
	pose.rot[b["upper_arm_r"]] = down * pose.rot[b["upper_arm_r"]]
	pose.rot[b["upper_arm_l"]] = down * pose.rot[b["upper_arm_l"]]
	return true


## A gun in the right hand alone, where `key` says; the chest squares up (a long gun's
## stance turned it) and the left arm hangs as it does with nothing to hold.
func _lay_gun(pose: RobotPose, w: float, key: Array) -> bool:
	if w <= 0.0:
		return false
	var rig := animator.rig
	var b := rig.bones
	var chest: int = b["chest"]
	var head: int = b["head"]
	var back: Quaternion = Quaternion.IDENTITY.slerp(animator._stance.inverse(), w)
	pose.rot[chest] = pose.rot[chest] * back
	pose.rot[head] = back.inverse() * pose.rot[head]
	var c := _chest(pose, b)
	var rot: Quaternion = c[0]
	var at: Vector3 = c[1]
	var frame := Basis(rot)
	var origin := at + rot * Vector3(0.0, pose.pos[b["upper_arm_r"]].y, 0.0)
	# Gun space: -z down the barrel, +y its top.
	var barrel: Vector3 = (key[1] as Vector3).normalized()
	var top: Vector3 = key[2]
	top = (top - barrel * top.dot(barrel)).normalized()
	var gun := frame * Basis(top.cross(-barrel), top, -barrel)
	var grip_bone: int = b["pistol"]
	var hand_rot := (gun * ReloadFx.GUN_REST.inverse()).get_rotation_quaternion() * pose.rot[grip_bone].inverse()
	var want: Vector3 = origin + frame * (key[0] as Vector3) - hand_rot * pose.pos[grip_bone]
	MeleeSwing._reach(pose, rig, rot, at, "r", want, hand_rot, frame * (ELBOW_UP if _shoulder else ELBOW_DOWN), w)
	_hang(pose, w, true, not _akimbo)   # (a gun in each hand: the left one stays in its hand, and comes down with the arm)
	return true


## A blade (or a hammer, or a spear) where `key` says. both: the left hand stays on
## the handle of a two-handed one; otherwise the left arm hangs.
func _lay_blade(pose: RobotPose, w: float, key: Array, both: bool) -> bool:
	if w <= 0.0:
		return false
	var rig := animator.rig
	var swing := animator.melee_swing()
	var ready: Array = swing._ready
	var k := [key[0], key[1], key[2], 0.0, 0.0, ready[MeleeSwing.LEFT], 1.0 if both else 0.0]
	MeleeSwing.hold(pose, rig, k, _two_handed, 0.0, w, w if both and _two_handed else 0.0)
	if not (both and _two_handed):
		_hang(pose, w, true, true)
	return true


## Fists (brass knuckles, bare hands): down from their guard to hang at the sides.
func _drop_arms(pose: RobotPose, w: float) -> bool:
	if w <= 0.0:
		return false
	_hang(pose, w, true, false)
	_hang(pose, w, false, false)
	return true


## One arm hanging at its side: straight down from the shoulder whichever way the chest
## leans, a little out from the body, the elbow easy. relax: the hand lets go as well.
func _hang(pose: RobotPose, w: float, left: bool, relax: bool) -> void:
	var rig := animator.rig
	var b := rig.bones
	var side := "l" if left else "r"
	var out := -1.0 if left else 1.0
	var chest: Quaternion = _chest(pose, b)[0]
	var down := chest.inverse() * Vector3.DOWN
	var hung := Quaternion(Vector3.DOWN, down) if down.dot(Vector3.DOWN) > -0.999 else Quaternion(Vector3.RIGHT, PI)
	var up: int = b["upper_arm_" + side]
	var fore: int = b["forearm_" + side]
	var hand: int = b["hand_" + side]
	pose.rot[up] = pose.rot[up].slerp(hung * Quaternion(Vector3.BACK, 0.13 * out) * Quaternion(Vector3.RIGHT, -0.06), w)
	pose.rot[fore] = pose.rot[fore].slerp(Quaternion(Vector3.RIGHT, 0.3), w)
	pose.rot[hand] = pose.rot[hand].slerp(Quaternion(Vector3.RIGHT, 0.12) * Quaternion(Vector3.UP, 0.25 * out), w)
	if relax:
		Hands.set_hand(pose, rig, "relaxed", w, left)
