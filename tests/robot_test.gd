extends SceneTree
## Headless checks on the robot models (every playable character) and the animator.
## Run: godot --headless --path . --script tests/robot_test.gd
##
## For each character in Characters: the model files hold every bone and clip the game
## asks for, the skeleton matches the others (so animations and the hitbox are shared),
## each movement state plays the right animation, and the poses make sense for the
## hitbox: standing height, crouch height, feet on the floor, gun following the aim.
## Then the body as you see it in first person: no head or arms, kept under and behind
## the camera in every move, and never upside down in front of your eyes.

const S := MovementController.State
const CROUCH_HEIGHT := 1.1   ## CROUCH_HEIGHT (the player script needs the full game to load)
const PRONE_HEIGHT := 0.8    ## Player.PRONE_HEIGHT

const BODY_CLIPS := ["aim", "idle", "run", "sprint", "crouch_idle", "crouch_walk", "slide",
	"air", "air_tuck", "land", "wall_run_l", "wall_run_r", "wall_jump_l", "wall_jump_r",
	"vault", "climb", "grapple", "dive", "roll", "belly_slide", "belly_crawl", "flip_front", "flip_back", "flip_left",
	"flip_right", "reload", "death", "respawn",
	"view_slide", "view_air_tuck", "view_roll", "view_flip_front", "view_flip_back", "view_flip_left", "view_flip_right"]
const ARM_CLIPS := ["fp_idle", "fp_one_hand", "fp_sprint", "fp_slide", "fp_wall_l", "fp_wall_r",
	"fp_dive", "fp_tuck", "fp_mantle", "fp_raise", "fp_reload"]
const BODY_BONES := ["root", "hips", "spine", "chest", "head", "upper_arm_l", "forearm_l", "hand_l",
	"upper_arm_r", "forearm_r", "hand_r", "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r",
	"foot_r", "pistol", "pistol_slide", "pistol_mag", "pistol_vent", "muzzle", "grapple", "muzzle_shotgun", "muzzle_rifle",
	"pistol_l", "pistol_l_slide", "pistol_l_mag", "pistol_l_vent",
	"index_l", "index_l2", "fingers_l", "fingers_l2", "thumb_l", "thumb_l2",
	"index_r", "index_r2", "fingers_r", "fingers_r2", "thumb_r", "thumb_r2"]
const LONG_GUNS := ["shotgun", "rifle", "anti_materiel"]
## Each long gun's own versions of these (e.g. "aim_rifle"); the pump and bolt guns also have "fire".
const GUN_BODY_CLIPS := ["aim", "carry", "reload", "respawn"]
const GUN_ARM_CLIPS := ["fp_idle", "fp_one_hand", "fp_sprint", "fp_slide", "fp_wall_l", "fp_wall_r",
	"fp_dive", "fp_tuck", "fp_mantle", "fp_raise", "fp_reload"]
const ARM_BONES := ["upper_arm_l", "forearm_l", "hand_l", "upper_arm_r", "forearm_r", "hand_r",
	"pistol", "pistol_slide", "pistol_mag", "pistol_vent", "muzzle", "grapple",
	"pistol_l", "pistol_l_slide", "pistol_l_mag", "pistol_l_vent",
	"index_l", "index_l2", "fingers_l", "fingers_l2", "thumb_l", "thumb_l2",
	"index_r", "index_r2", "fingers_r", "fingers_r2", "thumb_r", "thumb_r2"]
## A gun in each hand (every weapon with a left muzzle: the Dual Pistols...) has its own
## aim and reload, and first-person poses, never the one-gun ones (e.g. "aim_akimbo").
const DUAL_BODY_CLIPS := ["aim", "reload"]
const DUAL_ARM_CLIPS := ["fp_idle", "fp_sprint", "fp_one_hand", "fp_wall_r", "fp_dive", "fp_raise", "fp_reload"]

var failures := 0
var robot: RobotModel
var animator: RobotAnimator
var _character := ""
var _weapon := "pistol"
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_checks()
	print("ROBOT TEST PASSED" if failures == 0 else "ROBOT TEST FAILED: %d" % failures)
	_drop_robot()
	quit(1 if failures else 0)
	_done = true
	return false


func _checks() -> void:
	print("Robot model files")
	_expect("at least two characters to choose from", Characters.LIST.size() >= 2)
	_expect("an unknown character falls back to the default", Characters.valid("nobody") == Characters.default_id())
	var first := RobotRig.open(Characters.body(Characters.default_id()))
	for id in Characters.ids():
		var body_clips := BODY_CLIPS.duplicate()
		var arm_clips := ARM_CLIPS.duplicate()
		for gun in LONG_GUNS:
			for c in GUN_BODY_CLIPS:
				body_clips.append(c + "_" + gun)
			for c in GUN_ARM_CLIPS:
				arm_clips.append(c + "_" + gun)
			if gun != "rifle":
				body_clips.append("fire_" + gun)
				arm_clips.append("fp_fire_" + gun)
		var body_bones := BODY_BONES.duplicate()
		var arm_bones := ARM_BONES.duplicate()
		for gun in _duals():
			var data := WeaponData.by_id(gun)
			for c in DUAL_BODY_CLIPS:
				body_clips.append(c + "_" + gun)
			for c in DUAL_ARM_CLIPS:
				arm_clips.append(c + "_" + gun)
			body_bones.append_array([data.muzzle_bone, data.muzzle_bone_left])
			arm_bones.append_array([data.muzzle_bone, data.muzzle_bone_left])
		_check_file(Characters.body(id), body_bones, body_clips)
		_check_file(Characters.arms(id), arm_bones, arm_clips)
		for gun in _duals():
			for path in [Characters.body(id), Characters.arms(id)]:
				var sides := _gun_sides(path, gun)
				_expect("%s: %s has a gun in each hand" % [path.get_file(), gun], sides[0] > 50 and sides[1] > 50, str(sides))
		var rig := RobotRig.open(Characters.body(id))
		var same := rig.bone_names == first.bone_names
		for i in mini(rig.rest_pos.size(), first.rest_pos.size()):
			same = same and rig.rest_pos[i].distance_to(first.rest_pos[i]) < 0.001
		_expect("%s: same skeleton as %s" % [id, Characters.default_id()], same)

	print("Animation flags survive packing")
	var inp := RobotAnimInput.new()
	inp.flags = RobotAnimInput.make_flags(true, false, true, RobotAnimInput.FLIP_LEFT, 6)
	_expect("wall on the right", inp.wall_right())
	_expect("not vaulting", not inp.vaulting())
	_expect("reloading", inp.reloading())
	_expect("flip direction", inp.flip() == RobotAnimInput.FLIP_LEFT)
	_expect("wall-jump counter wraps", inp.wall_jumps() == 2)
	_expect("fits a snapshot float exactly", int(float(inp.flags)) == inp.flags and inp.flags < 128)

	for id in Characters.ids():
		_character = id
		_drop_robot()
		_check_character()
		for gun in LONG_GUNS:
			_drop_robot()
			_check_gun(gun)
		for gun in _duals():
			_drop_robot()
			_check_dual(gun)
		_drop_robot()
	_check_habits()


## A robot's own idle (its habit: "idle_<torso>") goes by the torso, in the Character
## Creator too, runs in step with the plain idle's breathing, and never turns the chest
## (so the gun) or moves it sideways from where the plain idle has it.
func _check_habits() -> void:
	print("Idle habits")
	var plain_len := RobotRig.open(Characters.body(Characters.default_id())).length("idle")
	var other := ""   # a body with no habit of its own, to mix parts with (none, now that every body has one)
	for part in Characters.part_ids():
		if not RobotRig.open(Characters.body(Characters.default_id())).has_clip("idle_" + part):
			other = part
			break
	var found := 0
	for id in Characters.part_ids():
		var rig := RobotRig.open(Characters.body(Characters.default_id()))
		var habit: String = "idle_" + id
		if not rig.has_clip(habit):
			continue
		found += 1
		if id in Characters.ids():
			robot = RobotModel.new().build(id, Color(1, 0.3, 0.2))
			_expect("%s stands in its own idle" % id, robot.idle == habit, robot.idle)
			_drop_robot()
		var mixed := CustomCharacter.new()
		mixed.torso = id
		robot = RobotModel.new().build(mixed.to_id(), Color(1, 0.3, 0.2))
		_expect("a custom character with %s's torso stands in its idle" % id, robot.idle == habit, robot.idle)
		_drop_robot()
		if other != "":
			mixed.torso = other
			mixed.head = id
			robot = RobotModel.new().build(mixed.to_id(), Color(1, 0.3, 0.2))
			_expect("but not one with only its head", robot.idle == "idle", robot.idle)
			_drop_robot()
		var breaths := rig.length(habit) / plain_len
		_expect("%s's idle is a whole number of breaths long" % id, absf(breaths - roundf(breaths)) < 0.001, "%.3f" % breaths)
		var a := rig.new_pose()
		var b := rig.new_pose()
		var turned := 0.0
		var moved := 0.0
		var lifted := 0.0
		var t := 0.0
		while t < rig.length(habit):
			rig.sample(a, "idle", fmod(t, plain_len))
			rig.sample(b, habit, t)
			var ca := _chest(rig, a)
			var cb := _chest(rig, b)
			turned = maxf(turned, ca.basis.get_rotation_quaternion().angle_to(cb.basis.get_rotation_quaternion()))
			moved = maxf(moved, Vector2(ca.origin.x - cb.origin.x, ca.origin.z - cb.origin.z).length())
			lifted = maxf(lifted, absf(ca.origin.y - cb.origin.y))
			t += 0.05
		_expect("%s's habit never turns the chest (and the gun) or moves it sideways" % id, turned < deg_to_rad(0.5) and moved < 0.005,
			"%.2f deg, %.3f m" % [rad_to_deg(turned), moved])
		_expect("and raises or lowers it only a little", lifted < 0.035, "%.3f m" % lifted)
	_expect("every robot and every creature has a habit", found == Characters.part_ids().size(), "%d of %d" % [found, Characters.part_ids().size()])


## Where a pose puts the chest, in the model's own space.
func _chest(rig: RobotRig, pose: RobotPose) -> Transform3D:
	var at := Transform3D.IDENTITY
	for bone in ["root", "hips", "spine", "chest"]:
		var i: int = rig.bones[bone]
		at = at * Transform3D(Basis(pose.rot[i]), pose.pos[i])
	return at


## The weapons with a gun in each hand.
func _duals() -> Array:
	return WeaponData.GUNS.filter(func(g): return WeaponData.by_id(g).is_akimbo())


## How many of a gun's vertices a model file holds by the right fist and by the left
## (rest pose: the arms hang at the sides): [right, left].
func _gun_sides(path: String, gun: String) -> Array:
	var full: Mesh = RobotModel._source(path)[0]
	var sides := [0, 0]
	for s in full.get_surface_count():
		var mat := full.surface_get_material(s)
		if mat == null or not mat.resource_name.begins_with(gun + "."):
			continue
		for v in (full.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if v.x > 0.1:
				sides[0] += 1
			elif v.x < -0.1:
				sides[1] += 1
	return sides


## A gun in each fist, both pointing ahead, and each arm kicks only on its own shots.
func _check_dual(gun: String) -> void:
	print("%s: %s" % [Characters.name_of(_character), WeaponData.name_of(gun)])
	_weapon = gun
	var data := WeaponData.by_id(gun)
	_fresh()
	_run(_input(S.GROUND, Vector3.ZERO, 0.0), 1.0)
	var right := robot.marker(data.muzzle_bone)
	var left := robot.marker(data.muzzle_bone_left)
	_expect("both guns out in front at chest height", right.z < -0.5 and left.z < -0.5 and right.y > 1.2 and left.y > 1.2,
		"%s %s" % [right, left])
	_expect("one gun in each hand", right.x > 0.05 and left.x < -0.05, "%s %s" % [right, left])
	for g in [["", data.muzzle_bone], ["_l", data.muzzle_bone_left]]:
		var dir := (robot.marker(g[1]) - robot.marker("pistol" + g[0])).normalized()
		_expect("the %s gun points forward" % ("left" if g[0] != "" else "right"), dir.dot(Vector3.FORWARD) > 0.9, str(dir))
	animator.fire(true)
	_run(_input(S.GROUND, Vector3.ZERO, 0.0), 2.0 / 60.0)
	var kick_l := robot.marker(data.muzzle_bone_left).y - left.y
	var kick_r := robot.marker(data.muzzle_bone).y - right.y
	_expect("a left-hand shot kicks the left gun, not the right", kick_l > 0.01 and absf(kick_r) < kick_l * 0.3, "%.3f vs %.3f" % [kick_l, kick_r])
	_run(_input(S.GROUND, Vector3.ZERO, 0.0), 1.0)
	right = robot.marker(data.muzzle_bone)   # (from where the idle has them now)
	left = robot.marker(data.muzzle_bone_left)
	animator.fire(false)
	_run(_input(S.GROUND, Vector3.ZERO, 0.0), 2.0 / 60.0)
	kick_l = robot.marker(data.muzzle_bone_left).y - left.y
	kick_r = robot.marker(data.muzzle_bone).y - right.y
	_expect("and a right-hand shot the right", kick_r > 0.01 and absf(kick_l) < kick_r * 0.3, "%.3f vs %.3f" % [kick_r, kick_l])
	_fresh()
	var reloading := _input(S.GROUND, Vector3.ZERO, 0.0)
	reloading.flags = RobotAnimInput.make_flags(false, false, true, 0, 0)
	_run(reloading, 0.4)
	# (Out of the grip, or swung out of the frame: a revolver's cylinder.)
	var out := []
	for side in ["", "_l"]:
		var mag := robot.skeleton.get_bone_pose(robot.rig.bones["pistol%s_mag" % side])
		out.append(mag.origin.length() > 0.03 or mag.basis.get_rotation_quaternion().get_angle() > deg_to_rad(30.0))
	_expect("reloading: both guns' cells are out", out[0] and out[1], str(out))
	_weapon = "pistol"


func _check_character() -> void:
	print("%s: each movement state plays its animation" % Characters.name_of(_character))
	var right := RobotAnimInput.make_flags(true, false, false, 0, 0)
	var vault := RobotAnimInput.make_flags(false, true, false, 0, 0)
	var flip_r := RobotAnimInput.make_flags(false, false, false, RobotAnimInput.FLIP_RIGHT, 0)
	var cases := [
		[S.GROUND, false, 0, true, "loco"], [S.CROUCH, true, 0, true, "crouch"],
		[S.SLIDE, true, 0, true, "slide"], [S.AIR, false, 0, true, "air"],
		[S.AIR, true, 0, true, "tuck"], [S.GRAPPLE, false, 0, true, "grapple"],
		[S.WALL_RUN, false, 0, true, "wall_l"], [S.WALL_RUN, false, right, true, "wall_r"],
		[S.MANTLE, false, vault, true, "vault"], [S.MANTLE, false, 0, true, "climb"],
		[S.DIVE, true, 0, true, "dive"], [S.ROLL, true, 0, true, "roll"],
		[S.BELLY_SLIDE, true, 0, true, "belly_slide"],
		[S.FLIP, false, 0, true, "flip_front"], [S.FLIP, false, flip_r, true, "flip_right"],
		[S.GLIDE, false, 0, true, "glide"],
		[S.GROUND, false, 0, false, "death"],
	]
	for c in cases:
		_fresh()
		var i := _input(c[0], Vector3.ZERO, 0.0)
		i.crouched = c[1]
		i.flags = c[2]
		i.alive = c[3]
		_run(i, 0.2)
		_expect("%s%s shows \"%s\"" % [S.keys()[c[0]], "" if c[3] else " (dead)", c[4]], animator.source == c[4],
			"got \"%s\"" % animator.source)

	print("%s: poses fit the hitbox" % Characters.name_of(_character))
	_fresh()
	_run(_input(S.GROUND, Vector3.ZERO, 0.0), 1.0)
	_near("standing: top of the head", _top(), 1.76, 0.08)
	_near("standing: lowest foot", _lowest_foot(), 0.10, 0.04)
	var level := robot.marker("muzzle")
	_expect("standing: gun held out in front", level.z < -0.35 and level.y > 1.2, str(level))
	_fresh()
	_run(_input(S.GROUND, Vector3.ZERO, deg_to_rad(40.0)), 1.0)
	var up := robot.marker("muzzle")
	_expect("aiming up 40 degrees raises the gun", up.y > level.y + 0.2, "%.2f vs %.2f" % [up.y, level.y])
	_fresh()
	_run(_input(S.GROUND, Vector3.ZERO, deg_to_rad(-40.0)), 1.0)
	var down := robot.marker("muzzle")
	_expect("aiming down 40 degrees lowers the gun", down.y < level.y - 0.2, "%.2f vs %.2f" % [down.y, level.y])

	_fresh()
	_run(_input(S.GROUND, Vector3(0, 0, -8), 0.0), 1.0)
	_near("running: top of the head", _top(), 1.72, 0.12)
	_expect("running: feet stay on or above the floor", _lowest_foot() > 0.02, "%.2f" % _lowest_foot())

	_fresh()
	var crouch := _input(S.CROUCH, Vector3.ZERO, 0.0)
	crouch.crouched = true
	_run(crouch, 1.0)
	_expect("crouched: head under the crouch height (%.1f m)" % CROUCH_HEIGHT,
		_top() < CROUCH_HEIGHT + 0.12, "%.2f" % _top())

	_fresh()
	var slide := _input(S.SLIDE, Vector3(0, 0, -12), 0.0)
	slide.crouched = true
	_run(slide, 1.0)
	_expect("sliding: head under the crouch height", _top() < CROUCH_HEIGHT + 0.12, "%.2f" % _top())

	for speed in [11.0, 1.5]:
		_fresh()
		var belly := _input(S.BELLY_SLIDE, Vector3(0, 0, -speed), 0.0)
		belly.crouched = true
		_run(belly, 1.0)
		var what := "belly-sliding" if speed > 5.0 else "crawling"
		var high := maxf(_top(), _highest_bone() + 0.1)
		_expect("%s: whole body under the prone height (%.1f m)" % [what, PRONE_HEIGHT], high < PRONE_HEIGHT, "%.2f" % high)
		_expect("%s: no joint sinks into the floor" % what, _lowest_bone() > 0.0, "%.2f" % _lowest_bone())
		var gun := robot.marker("muzzle")
		_expect("%s: gun out in front, off the floor" % what, gun.z < -0.6 and gun.y > 0.1, str(gun))

	_fresh()
	var gliding := _input(S.GLIDE, Vector3(0, 0, -12), 0.0)
	_run(gliding, 0.5)
	var held := robot.bone_position("muzzle")
	var aim := _gun_dir()
	_expect("gliding: gun still held out in front", held.z < -0.35 and held.y > 1.2, str(held))
	var seat := robot.bone_position("hips")
	var leg_l := robot.bone_position("foot_l") - seat
	var leg_r := robot.bone_position("foot_r") - seat
	_expect("gliding forward: both legs trail behind", leg_l.z > 0.3 and leg_r.z > 0.15 and absf(leg_l.x - leg_r.x) < 0.45,
		"%s %s" % [leg_l, leg_r])
	# Going sideways (to the right) while still looking ahead: the legs trail to the left, the gun stays put.
	_run(_input(S.GLIDE, Vector3(12, 0, 0), 0.0), 0.6)
	var side_l := robot.bone_position("foot_l") - robot.bone_position("hips")
	_expect("gliding sideways: the legs trail away from where you are going", side_l.x < -0.3 and absf(side_l.z) < 0.35, str(side_l))
	# (The chest leans into the flight only when you aim down the track, so the gun sits a
	# little higher aiming across it: where it points is what must not change.)
	_expect("gliding sideways: the gun stays on target", rad_to_deg(_gun_dir().angle_to(aim)) < 6.0,
		"%.1f degrees" % rad_to_deg(_gun_dir().angle_to(aim)))
	# Hanging in place: the legs hang nearly straight down.
	_run(_input(S.GLIDE, Vector3.ZERO, 0.0), 0.6)
	var hang := robot.bone_position("foot_l") - robot.bone_position("hips")
	_expect("gliding at a standstill: the legs hang", Vector2(hang.x, hang.z).length() < 0.3 and hang.y < -0.7, str(hang))
	# Weakened into a fall: nose-down, the legs higher than the hips behind.
	_fresh()
	_run(_input(S.GLIDE, Vector3(0, 0, -14), 0.0), 0.6)
	var fresh_head := robot.bone_position("head").y
	_run(_input(S.GLIDE, Vector3(0, -20, -14), 0.0), 1.0)
	var dive_leg := robot.bone_position("foot_l") - robot.bone_position("hips")
	_expect("a weakened glide tips nose-down", robot.bone_position("head").y < fresh_head - 0.15,
		"%.2f vs %.2f" % [robot.bone_position("head").y, fresh_head])
	_expect("...the legs streaming out behind", dive_leg.z > 0.55, str(dive_leg))
	# Letting go of a real glide in mid-air: a backflip out of it, then the fall.
	_fresh()
	_run(_input(S.GLIDE, Vector3(0, 0, -14), 0.0), 0.6)
	_run(_input(S.AIR, Vector3(0, -2, -14), 0.0), 0.1)
	_expect("letting go of a glide backflips out of it", animator.source == "glide_flip", "got \"%s\"" % animator.source)
	# One long flip: open over the top (upside down, arms flung wide), all the way round by the end.
	_run(_input(S.AIR, Vector3(0, -4, -14), 0.0), RobotAnimator.GLIDE_FLIP_TIME * 0.5 - 0.1)
	var hips_up := robot.skeleton.get_bone_global_pose(robot.rig.bones["hips"]).basis.y
	var hands := absf(robot.bone_position("hand_l").x - robot.bone_position("hand_r").x)
	_expect("...upside down halfway through", animator.source == "glide_flip" and hips_up.y < -0.7, "%s %s" % [animator.source, hips_up])
	_expect("...open, the arms flung wide", hands > 0.9, "%.2f m apart" % hands)
	_run(_input(S.AIR, Vector3(0, -8, -14), 0.0), RobotAnimator.GLIDE_FLIP_TIME * 0.5 - 0.05)
	_expect("...still going just before its time is up", animator.source == "glide_flip", "got \"%s\"" % animator.source)
	_run(_input(S.AIR, Vector3(0, -10, -14), 0.0), 0.12)
	_expect("...then the fall", animator.source == "air", "got \"%s\"" % animator.source)
	_fresh()
	_run(_input(S.GLIDE, Vector3(0, 0, -14), 0.2), 0.2)
	_run(_input(S.AIR, Vector3(0, -2, -14), 0.0), 0.1)
	_expect("a tap of the glide does not backflip", animator.source == "air", "got \"%s\"" % animator.source)
	_fresh()
	_run(_input(S.GLIDE, Vector3(0, 0, -14), 0.0), 0.6)
	_run(_input(S.AIR, Vector3(0, -2, -14), 0.0), 0.1)
	animator.fire()
	_expect("a shot hurries the backflip: the arms are free at once", animator.glide_flip_hurried())
	_run(_input(S.AIR, Vector3(0, -2, -14), 0.0), RobotAnimator.GLIDE_FLIP_HURRY + 0.04)
	_expect("...and it is round in a moment", animator.source == "air", "got \"%s\"" % animator.source)
	_fresh()
	_run(_input(S.GLIDE, Vector3(0, 0, -14), 0.0), 0.6)
	_run(_input(S.AIR, Vector3(0, -2, -14), 0.0), 0.1)
	animator.glide_flip_floor_in(0.4)
	_run(_input(S.AIR, Vector3(0, -2, -14), 0.0), 0.36)
	_expect("the floor coming up hurries it too: round before the landing", animator.source == "air", "got \"%s\"" % animator.source)
	_fresh()
	_run(_input(S.GLIDE, Vector3(0, 0, -14), 0.0), 0.6)
	_run(_input(S.AIR, Vector3(0, -2, -14), 0.0), 0.1)
	_run(_input(S.GRAPPLE, Vector3(0, -2, -14), 0.0), 0.05)
	_expect("another move cuts it short", animator.source == "grapple", "got \"%s\"" % animator.source)

	_fresh()
	var before := robot.marker("muzzle")
	_run(_input(S.GROUND, Vector3.ZERO, 0.0), 0.5)
	before = robot.marker("muzzle")
	animator.fire()
	_run(_input(S.GROUND, Vector3.ZERO, 0.0), 0.03)
	var kicked := robot.marker("muzzle")
	_expect("firing kicks the gun", kicked.distance_to(before) > 0.01, "%.3f m" % kicked.distance_to(before))
	_run(_input(S.GROUND, Vector3.ZERO, 0.0), 0.6)
	_expect("and it settles back on target", robot.marker("muzzle").distance_to(before) < 0.01)

	_fresh()
	var dead := _input(S.GROUND, Vector3.ZERO, 0.0)
	_run(dead, 0.3)
	dead.alive = false
	_run(dead, 2.0)
	_expect("dead: the body is down on the floor", _top() < 0.75, "%.2f" % _top())
	_expect("dead: nothing sinks through the floor", _lowest_bone() > -0.12, "%.2f" % _lowest_bone())
	_check_feet()
	_check_first_person()


## Standing still on uneven ground, each foot rests on the ground under it; on level
## ground, and on the move, the legs are exactly the clip's.
func _check_feet() -> void:
	_fresh()
	var still := _input(S.GROUND, Vector3.ZERO, 0.0)
	_run(still, 1.0)
	var level_l := robot.bone_position("foot_l").y
	var level_r := robot.bone_position("foot_r").y
	var level_hips := robot.bone_position("hips").y
	still.feet = Vector2(0.15, 0.0)
	_run(still, 3.0)   # (one whole breath of the idle on, so only the feet's ground has changed)
	_expect("a step under the left foot: that foot rests on it", absf(robot.bone_position("foot_l").y - level_l - 0.15) < 0.02,
		"%.3f m up" % (robot.bone_position("foot_l").y - level_l))
	_expect("and the other foot and the hips stay where they were", absf(robot.bone_position("foot_r").y - level_r) < 0.01
		and absf(robot.bone_position("hips").y - level_hips) < 0.01)
	still.feet = Vector2(0.0, -0.25)
	_run(still, 3.0)
	var drop := level_hips - robot.bone_position("hips").y
	_expect("a drop under the right foot: the hips come down for it, but only so far",
		drop > 0.08 and drop < RobotAnimator.FEET_DROP + 0.01, "%.3f m" % drop)
	_expect("and the right foot goes down toward it", robot.bone_position("foot_r").y < level_r - 0.1,
		"%.3f m" % (robot.bone_position("foot_r").y - level_r))
	_fresh()
	var moving := _input(S.GROUND, Vector3(0, 0, -6.0), 0.0)
	moving.feet = Vector2(0.2, -0.2)
	_run(moving, 1.0)
	var a := robot.bone_position("hips")
	_fresh()
	_run(_input(S.GROUND, Vector3(0, 0, -6.0), 0.0), 1.0)
	_expect("on the move the ground under the feet is left alone", robot.bone_position("hips").distance_to(a) < 0.005,
		"%.3f m" % robot.bone_position("hips").distance_to(a))


## A robot holding a long gun: it shows only that gun, holds it in both hands, aims
## it, works its pump or bolt, carries it when sprinting and reloads it.
func _check_gun(gun: String) -> void:
	print("%s with the %s" % [Characters.name_of(_character), WeaponData.name_of(gun)])
	_weapon = gun
	_fresh()
	var own := 0
	var others := []
	for i in robot.mesh.mesh.get_surface_count():
		var mname := robot.mesh.mesh.surface_get_material(i).resource_name
		if mname.begins_with(gun + "."):
			own += 1
		elif "." in mname:
			others.append(mname)
	_expect("shows its own gun and no other", own >= 3 and others.is_empty(), "%d surfaces; others %s" % [own, others])
	_expect("the animator holds the same gun", animator.weapon == gun)

	_run(_input(S.GROUND, Vector3.ZERO, 0.0), 1.0)
	var level := robot.muzzle()
	var grip := robot.marker("pistol")
	_expect("standing: barrel out in front at chest height", level.z < -0.55 and level.y > 1.2 and level.y < 1.7, str(level))
	_expect("standing: barrel points forward", (level - grip).normalized().dot(Vector3.FORWARD) > 0.9, str((level - grip).normalized()))
	var hands := robot.marker("hand_l").distance_to(robot.marker("hand_r"))
	_expect("standing: both hands on the gun", hands > 0.12 and hands < 0.45, "%.2f m apart" % hands)
	var head_fwd: Vector3 = robot.skeleton.get_bone_global_pose(robot.rig.bones["head"]).basis * Vector3.FORWARD
	_expect("standing: the chest turns but the head looks ahead", head_fwd.dot(Vector3.FORWARD) > 0.95, str(head_fwd))
	_fresh()
	_run(_input(S.GROUND, Vector3.ZERO, deg_to_rad(40.0)), 1.0)
	_expect("aiming up 40 degrees raises the barrel", robot.muzzle().y > level.y + 0.2, "%.2f" % robot.muzzle().y)
	var up_dir := (robot.muzzle() - robot.marker("pistol")).normalized()
	_expect("and points it up", up_dir.y > 0.45, str(up_dir))

	if gun != "rifle":
		_fresh()
		_run(_input(S.GROUND, Vector3.ZERO, 0.0), 0.5)
		var rest := robot.marker("pistol_slide").distance_to(robot.marker("pistol"))
		animator.fire()
		var moved := 0.0
		for i in 40:
			_run(_input(S.GROUND, Vector3.ZERO, 0.0), 1.0 / 60.0)
			moved = maxf(moved, absf(robot.marker("pistol_slide").distance_to(robot.marker("pistol")) - rest))
		_expect("firing works the %s" % ("pump" if gun == "shotgun" else "bolt"), moved > 0.05, "%.3f m" % moved)

	_fresh()
	_run(_input(S.GROUND, Vector3(0, 0, -11.5), 0.0), 1.0)
	var carried := (robot.muzzle() - robot.marker("pistol")).normalized()
	_expect("sprinting: carried across the chest, muzzle up", carried.y > 0.2 and animator._carry > 0.9, str(carried))

	_fresh()
	var reloading := _input(S.GROUND, Vector3.ZERO, 0.0)
	reloading.flags = RobotAnimInput.make_flags(false, false, true, 0, 0)
	_run(reloading, 1.0)
	var mid_reload := robot.marker("hand_l").distance_to(robot.marker("hand_r"))
	_run(reloading, 1.0)
	if gun == "shotgun":
		_expect("reloading: loads shell after shell while the reload lasts", animator._reload_t >= 0.0)
	_expect("reloading: the left hand leaves its hold", absf(mid_reload - hands) > 0.03 or gun == "shotgun", "%.2f vs %.2f" % [mid_reload, hands])
	_weapon = "pistol"


## Your own body in first person (Player does this for the local player only).
func _check_first_person() -> void:
	print("%s: the body you see in first person" % Characters.name_of(_character))
	_fresh()
	robot.add_view_mesh(4)
	var full := _triangles(robot.mesh.mesh)
	var seen := _triangles(robot.view_mesh.mesh)
	_expect("leaves out the head and arms", seen > 0 and seen < full * 0.8, "%d of %d triangles" % [seen, full])
	_expect("follows the same skeleton", robot.view_mesh.get_node_or_null(robot.view_mesh.skeleton) == robot.skeleton)
	_expect("casts no shadow of its own", robot.view_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	# In every move, wherever you look: the neck stays behind the eyes (which are at
	# x = z = 0, eye height) and below them, so you never look into your own chest.
	var flip_b := RobotAnimInput.make_flags(false, false, false, RobotAnimInput.FLIP_BACK, 0)
	var flip_l := RobotAnimInput.make_flags(false, false, false, RobotAnimInput.FLIP_LEFT, 0)
	var flip_r := RobotAnimInput.make_flags(false, false, false, RobotAnimInput.FLIP_RIGHT, 0)
	var moves := [   # [name, state, crouched, flags, velocity, eye height, seconds]
		["standing", S.GROUND, false, 0, Vector3.ZERO, 1.6, 0.6], ["sprinting", S.GROUND, false, 0, Vector3(0, 0, -11.5), 1.6, 0.6],
		["strafing", S.GROUND, false, 0, Vector3(8, 0, 0), 1.6, 0.6], ["crouched", S.CROUCH, true, 0, Vector3.ZERO, 1.0, 0.6],
		["sliding", S.SLIDE, true, 0, Vector3(0, 0, -12), 1.0, 0.6], ["jumping", S.AIR, false, 0, Vector3(0, 6, -8), 1.6, 0.6],
		["tucked", S.AIR, true, 0, Vector3(0, 0, -8), 1.0, 0.6], ["on the rope", S.GRAPPLE, false, 0, Vector3(0, 0, -12), 1.6, 0.6],
		["wall-running", S.WALL_RUN, false, 0, Vector3(0, 0, -10), 1.6, 0.6], ["climbing", S.MANTLE, false, 0, Vector3.ZERO, 1.6, 0.3],
		["diving", S.DIVE, true, 0, Vector3(0, 0, -14), 1.0, 0.6], ["rolling", S.ROLL, true, 0, Vector3(0, 0, -10), 1.0, 0.2],
		["belly-sliding", S.BELLY_SLIDE, true, 0, Vector3(0, 0, -9), 0.55, 0.6],
		["front flip", S.FLIP, false, 0, Vector3(0, 2, -9), 1.6, 0.22], ["backflip", S.FLIP, false, flip_b, Vector3(0, 2, -9), 1.6, 0.22],
		["left flip", S.FLIP, false, flip_l, Vector3(0, 2, -9), 1.6, 0.22], ["right flip", S.FLIP, false, flip_r, Vector3(0, 2, -9), 1.6, 0.22],
	]
	for m in moves:
		var worst_back := INF
		var worst_up := -INF
		for pitch in [0.0, -45.0, -88.0]:
			_fresh()
			animator.first_person = true
			var inp := _input(m[1], m[4], deg_to_rad(pitch))
			inp.crouched = m[2]
			inp.flags = m[3]
			_run_view(inp, m[6], m[5])
			var neck := robot.marker("head")
			worst_back = minf(worst_back, neck.z)
			worst_up = maxf(worst_up, neck.y - m[5])
		_expect("%s: neck behind the eyes (%.2f m) and below them (%.2f m)" % [m[0], worst_back, -worst_up],
			worst_back > robot.chest_front - 0.05 and worst_up < -0.11)

	# Flips and the landing roll: the same animation name as everyone else sees, but
	# the body never turns upside down in front of the camera (which stays level).
	for flip in [[0, "flip_front"], [flip_b, "flip_back"]]:
		for view in [false, true]:
			_fresh()
			animator.first_person = view
			var inp := _input(S.FLIP, Vector3(0, 2, -9), 0.0)
			inp.flags = flip[0]
			_run_view(inp, 0.22, 1.6, view)
			var upright := robot.marker("head").y > robot.marker("hips").y
			if view:
				_expect("%s in first person: still called %s, and the body stays upright" % [flip[1], flip[1]],
					animator.source == flip[1] and upright)
			else:
				_expect("%s in third person: the body is upside down halfway" % flip[1], not upright)
	_fresh()
	animator.first_person = true
	_run_view(_input(S.SLIDE, Vector3(0, 0, -12), 0.0), 0.6, 1.0)
	var toes := minf(robot.marker("foot_l").z, robot.marker("foot_r").z)
	var feet_up := maxf(robot.marker("foot_l").y, robot.marker("foot_r").y)
	_expect("sliding: the legs are out in front, in view at eye level", toes < -0.7 and feet_up > 1.0 - 1.09 * -toes,
		"toes %.2f m ahead, %.2f m up" % [-toes, feet_up])

	# The torso stays upright under the camera instead of leaning with the aim.
	for view in [false, true]:
		_fresh()
		animator.first_person = view
		_run_view(_input(S.GROUND, Vector3.ZERO, deg_to_rad(-60.0)), 0.8, 1.6, view)
		var lean := absf(robot.marker("head").z - robot.marker("spine").z)
		if view:
			_expect("looking down in first person: the torso stays upright", lean < 0.05, "%.2f m" % lean)
		else:
			_expect("looking down in third person: the torso leans with the aim", lean > 0.1, "%.2f m" % lean)

	# Back to third person: the body returns to where everyone else sees it.
	animator.place_for_view(0.0, 1.6, 0.0)
	_expect("third person: the body is back in place and the first-person copy hidden",
		robot.position == Vector3.ZERO and not robot.view_mesh.visible)


func _triangles(mesh: Mesh) -> int:
	var n := 0
	for i in mesh.get_surface_count():
		n += mesh.surface_get_array_index_len(i) / 3
	return n


## Like _run, also placing the body for the first-person camera each frame.
func _run_view(inp: RobotAnimInput, seconds: float, eye: float, view: bool = true) -> void:
	var t := 0.0
	while t < seconds:
		animator.update(1.0 / 60.0, inp, robot.global_transform)
		animator.place_for_view(1.0 if view else 0.0, eye, inp.pitch)
		t += 1.0 / 60.0



func _check_file(path: String, bones: Array, clips: Array) -> void:
	var rig := RobotRig.open(path)
	var missing_bones := bones.filter(func(b): return not rig.bones.has(b))
	var missing_clips := clips.filter(func(c): return not rig.has_clip(c))
	_expect("%s: all %d bones" % [path.get_file(), bones.size()], missing_bones.is_empty(), str(missing_bones))
	_expect("%s: all %d clips" % [path.get_file(), clips.size()], missing_clips.is_empty(), str(missing_clips))
	var empty := clips.filter(func(c): return rig.has_clip(c) and rig.length(c) <= 0.0)
	_expect("%s: no empty clips" % path.get_file(), empty.is_empty(), str(empty))


## A robot back in its starting state (one model, a new animator each time).
func _fresh() -> void:
	if robot == null:
		robot = RobotModel.new().setup(Characters.body(_character), Color(1, 0.3, 0.2), false, _weapon)
		root.add_child(robot)
	robot.position = Vector3.ZERO
	animator = RobotAnimator.new(robot)


func _drop_robot() -> void:
	if robot == null:
		return
	for i in robot.mesh.mesh.get_surface_count():   # headless Godot grumbles otherwise
		robot.mesh.set_surface_override_material(i, null)
	if robot.view_mesh:
		for i in robot.view_mesh.mesh.get_surface_count():
			robot.view_mesh.set_surface_override_material(i, null)
	robot.queue_free()
	robot = null


func _input(state: int, velocity: Vector3, pitch: float) -> RobotAnimInput:
	var inp := RobotAnimInput.new()
	inp.state = state
	inp.velocity = velocity
	inp.pitch = pitch
	return inp


func _run(inp: RobotAnimInput, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		animator.update(1.0 / 60.0, inp, robot.global_transform)
		t += 1.0 / 60.0


func _bone_y(bone: String) -> float:
	return robot.skeleton.get_bone_global_pose(robot.rig.bones[bone]).origin.y


## The head bone sits at the neck; the top of the head is about 0.26 m above it.
## Which way the gun in the right hand points (model space).
func _gun_dir() -> Vector3:
	return (robot.bone_position("muzzle") - robot.bone_position("pistol")).normalized()


func _top() -> float:
	var pose := robot.skeleton.get_bone_global_pose(robot.rig.bones["head"])
	return (pose * Vector3(0, 0.26, 0)).y


func _lowest_foot() -> float:
	return minf(_bone_y("foot_l"), _bone_y("foot_r"))


func _highest_bone() -> float:
	var high := -INF
	for b in BODY_BONES:
		if b not in ["root", "muzzle", "grapple"]:
			high = maxf(high, _bone_y(b))
	return high


func _lowest_bone() -> float:
	var low := INF
	for b in BODY_BONES:
		if b not in ["root", "muzzle", "grapple"]:
			low = minf(low, _bone_y(b))
	return low


func _near(what: String, value: float, expected: float, tolerance: float) -> void:
	_expect("%s = %.2f (expected %.2f ± %.2f)" % [what, value, expected, tolerance], absf(value - expected) <= tolerance)


func _expect(what: String, ok: bool, detail: String = "") -> void:
	print("  %s  %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  [" + detail + "]"])
	if not ok:
		failures += 1
