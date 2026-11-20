class_name RobotAnimator
extends RefCounted
## Chooses and blends the robot's animation from what the player is doing.
##
## Each frame, in this order:
##  1. Body: one source per movement state ("loco" = idle/run/sprint by speed,
##     "slide", "air", "flip_back", ...), cross-faded when the state changes.
##  2. Short overlays: landing dip, wall-jump kick, respawn boot-up.
##  3. Arms: gun up in the aim pose wherever the robot can shoot; reload on top.
##  4. Aim: spine, chest, arms and head pitch so the gun points where the player aims.
##  5. Legs turn at the waist to face the way the robot is moving (it can strafe
##     and back-pedal while the upper body keeps aiming).
##  6. Recoil, and the left arm reaching for the grapple anchor.
## On the grappling hook's rope, once it has pulled tight, the body hangs from that arm
## instead of holding a pose (RopeSwing): tipped along the rope, the legs trailing a beat
## behind, the gun loose at the side until you shoot. It is laid over the steps above.
## Dived into that rope, the body zips along it instead: in line with the way it is going,
## with a corkscrew as the rope pulls tight and a flip over the top on arriving (RopeSwing).
## Gliding has no clip either (see _glide_body): a snappy launch into a sleek,
## stretched-out flying pose, the hips tipped into the wind along the track and the
## legs together trailing in line behind them (the waist turn in update points them
## down the track, however far round that is), while everything above the waist keeps
## aiming wherever you look. As the glide weakens (read from how fast it is falling, so
## everyone sees the same), the body tips nose-down and the legs start to kick. Let go
## of the glide in mid-air after GLIDE_FLIP_AFTER seconds of it and the body backflips
## out of the pose (see _glide_flip_body): one long, open backflip over the line of the
## track, straight out of the flying pose with no stop in between, looks only. Any move
## cuts it short; a shot (or a swing) hurries it to its end so the arms can aim, and so
## does the floor coming up (see glide_flip_floor_in), so it lands on its feet.
## A melee weapon has no clips: MeleeSwing says where the weapon is (ready, wound up,
## mid-blow) and bends the arms to hold it, in both hands where the weapon allows.
## The clips come from the model file; see tools/robot/animations.py. A long gun has its
## own version of the clips where the hands hold the gun ("aim_rifle", "reload_shotgun";
## tools/robot/weapon_anims.py), used instead of the plain (pistol) ones. Long guns also
## turn the chest a little (a bladed stance; the twist is in their aim clip), carry the
## gun across the chest when sprinting, and work a pump or bolt after each shot.

const S := MovementController.State
const RUN_SPEED := 8.0
const SPRINT_SPEED := 11.5
const CROUCH_SPEED := 4.0
const WALL_SPEED := 10.5
const FADE_DEFAULT := 0.12
const HABIT_AFTER := 2.5        ## seconds after a shot before a robot goes back to its idle habit
const FEET_STILL := 0.6         ## m/s: standing or crouched and slower than this, each foot rests on the ground under it
const FEET_REACH := 0.3         ## a foot goes at most this far up or down to find the ground...
const FEET_DROP := 0.12         ## ...and the hips come down at most this far to let the lower one reach it
const RELOAD_CUT_FADE := 0.12   ## seconds a reload that is cut short takes to ease back to the hold
const CRAWL_SPEED := 2.0
const FADES := {"roll": 0.05, "belly_slide": 0.07, "vault": 0.06, "climb": 0.08, "death": 0.08, "loco": 0.14,
	"crouch": 0.16, "slide": 0.1,   # (down into a crouch a touch slower than the default, into a slide a touch quicker)
	"flip_front": 0.06, "flip_back": 0.06, "flip_left": 0.06, "flip_right": 0.06, "glide": 0.08, "glide_flip": 0.1}
const FLIPS := ["flip_front", "flip_back", "flip_left", "flip_right"]
const VIEW_BACK := -0.02        ## first person: the front of the chest sits this far behind the eyes (just ahead of them)...
const VIEW_BACK_DOWN := 0.32    ## ...and this much further back when looking straight down,
const VIEW_BACK_FROM := 0.7     ## moving back as you look down past this (radians): the collar stays out of sight
## First person: in these the torso keeps the pose's lean. In everything else it is
## stood upright over the hips, which brings the knees forward into view.
const VIEW_KEEP_LEAN := ["crouch", "slide", "dive", "roll", "belly_slide", "death", "tuck"]
const VIEW_UPRIGHT_MAX := 0.6   ## radians of forward lean taken out, at most
const VIEW_SIDE := 0.10         ## the body may shift this far sideways to stay under the eyes
const VIEW_NECK_BELOW := 0.12   ## and its neck is kept at least this far below them
const AIRBORNE := ["air", "tuck", "grapple", "wall_l", "wall_r", "flip_front", "flip_back", "flip_left", "flip_right", "glide", "glide_flip"]
const SPIN_PIVOT := Vector3(0.0, 1.0, 0.0)   ## a mid-air melee wind-up spins the body about here (its middle)
## Gliding (see _glide_body): the hips tip into the wind along the track, further the
## faster you go and further still (nose-down) as the glide weakens; the legs trail in
## line behind them.
const GLIDE_LEAN_HANG := 6.0    ## degrees the hips tip forward when you are hardly moving (hanging in the air)...
const GLIDE_LEAN := 58.0        ## ...at GLIDE_FAST and above (the sleek, stretched-out flying pose)...
const GLIDE_LEAN_DIVE := 84.0   ## ...and once the glide has weakened into a fall (nose-down)
const GLIDE_FAST := 12.0        ## m/s
const GLIDE_LEGS := 10.0        ## degrees the legs ride higher than the line of the body (toes pointed, streamlined)
const GLIDE_CHEST := 42.0       ## degrees the chest leans into the flight when you aim down the track (none aiming across it)...
const GLIDE_CHEST_DIVE := 62.0  ## ...and once it has weakened into a fall
const GLIDE_WEAK_FALL := 16.0   ## falling this fast (m/s) the glide shows fully weakened
const GLIDE_LAUNCH := 0.24      ## seconds the snap into the pose takes (it overshoots a little and settles)
const GLIDE_KICK := 26.0        ## degrees the legs kick through, fully weakened...
const GLIDE_KICK_RATE := 3.4    ## ...this many times a second
## Letting go of a glide in mid-air after at least this many seconds of it backflips you out of it.
const GLIDE_FLIP_AFTER := 0.4
const GLIDE_FLIP_TIME := 0.95   ## seconds the backflip takes, left alone
const GLIDE_FLIP_HURRY := 0.18  ## a shot or a swing: what is left of it is over in this long
const GLIDE_FLIP_LAND := 0.06   ## the floor coming up: it is round this long before the landing
const GLIDE_FLIP_RATE_MAX := 3.0   ## ...but it never goes round more than this many times as fast for that
## The backflip as key moments: [share of its time, degrees round (from the glide's own
## lean at 0), back arch (+ open, - curled in), arms out wide, left knee to the chest,
## right knee to the chest]. Open and slow over the top (arched, arms wide, one knee up
## and the other leg long behind), a quick tuck through the last of the turn, then out
## into the fall.
const GLIDE_FLIP_KEYS := [
	[0.0, 0.0, 0.3, 0.0, 0.0, 0.0],
	[0.14, 30.0, 0.85, 0.7, 0.1, 0.0],
	[0.36, 120.0, 1.0, 1.0, 0.55, 0.0],
	[0.58, 190.0, 0.7, 1.0, 0.85, 0.1],
	[0.8, 318.0, -0.7, 0.2, 1.0, 0.75],
	[1.0, 360.0, 0.0, 0.0, 0.0, 0.0],
]
## On the rope (RopeSwing) the gun hangs at your side. A shot brings it
## up at once; it stays up this long after the last one (seconds), then drops this fast.
const ROPE_AIM_HOLD := 0.6
const ROPE_AIM_DROP := 4.0
const ROPE_CHEST := 0.45        ## how much of the hips' lean the chest gives back while the gun is down (aiming: all of it)
const ROPE_VIEW := 0.55         ## your own body in first person leans this much of what everyone else sees
const ZIP_AIM_UP := 12.0        ## ...this fast (a second)
const ZIP_CHEST := 0.55         ## zipping along the rope (dived into it), a shot brings the chest this much of the way back up to aim from
const DRAG_TURN := 10.0         ## dragged along the floor on your belly by the rope, the body turns to face the hook this fast
## [right arm, left arm, torso]: how much each follows the aim in each source.
const AIM_WEIGHTS := {
	"loco": [1.0, 1.0, 1.0], "crouch": [1.0, 1.0, 1.0], "slide": [1.0, 0.0, 1.0],
	"air": [1.0, 1.0, 1.0], "tuck": [1.0, 1.0, 1.0], "grapple": [1.0, 0.0, 0.6],
	"wall_l": [1.0, 0.0, 0.7], "wall_r": [1.0, 0.0, 0.7], "belly_slide": [1.0, 1.0, 0.35],
	"glide": [1.0, 1.0, 1.0],
}   # (not "glide_flip": the arms are tucked into the backflip and the weapon goes loose)

var model: RobotModel
var rig: RobotRig
## The gun in the hands (an id from WeaponData). Set it with set_weapon().
var weapon := "pistol"
## What the body is doing right now, e.g. "loco", "slide", "flip_back". Tests read this.
var source := ""
## Posing your own body for the first-person camera: the torso stays upright under
## the camera instead of leaning with the aim, and the moves that have a "view_"
## clip (slide, tuck, flips, the landing roll) play that instead: made to be seen
## from the eyes, with the legs brought up into view.
var first_person := false:
	set(on):
		_snap_view = _snap_view or on != first_person   # the camera swaps bodies in one frame, so no easing
		first_person = on

var _pose: RobotPose
var _from: RobotPose
var _base: RobotPose
var _tmp: RobotPose
var _aim: RobotPose
var _fade := 1.0
var _fade_time := FADE_DEFAULT
var _time := 0.0          # seconds in the current source
var _phase := 0.0         # stride phase, 0..1
var _idle_time := 0.0
var _habit := 0.0         # how much of the torso's own idle shows (see RobotModel.idle), 0..1
var _feet := Vector2.ZERO    # the ground under each foot (RobotAnimInput.feet), eased
var _feet_w := 0.0           # how much the feet are rested on it, 0..1
var _twist := 0.0
var _reverse := false
var _air_t := 0.5
var _land := 0.0          # how hard the last landing was, 0..1 (0: none showing)
var _land_t := 0.0        # seconds into it
var _aim_r := 1.0
var _aim_l := 1.0
var _torso := 1.0
var _recoil := 0.0
var _recoil_l := 0.0      # akimbo: the left gun's own kick (_recoil is the right's)
var _akimbo := false      # a pistol in each hand: each arm kicks on its own shots
var _since_fire := 99.0
var _reload_t := -1.0
var _reload_rate := 1.0   # clip seconds a second: the reload clip plays out over the gun's reload_time
var _reload_w := 0.0
var _was_reloading := false
var _reload_from := 0.0   # a reload cut short: where in the clip it stopped...
var _reload_out := 0.0    # ...and how much of that pose is still held (it eases back to the hold)
var _reload_out_clip := ""   # ...and which clip it was
var _end_t := -1.0        # a shell-at-a-time reload's last flourish ("reload_end"), once the gun is full
var _reload_chest := Quaternion.IDENTITY   # the reload clip's chest and spine as it starts: what it
var _reload_spine := Quaternion.IDENTITY   # turns them by from there is added to the body's own
var _fx_t := -1.0         # how far into the reload the gun's effects were last frame (ReloadFx)
## Where a reload's spent cell is put (the arena). Null: none is thrown.
var fx_parent: Node = null
var _respawn_t := -1.0
var _kick_t := -1.0
var _kick_right := false
var _wall_jumps := -1
var _grapple_w := 0.0
var _prev_vy := 0.0
var _dead_time := -1.0
var _power := 1.0
var _lean := 1.0          # how much the torso leans with the aim (0 in first person)
var _upright := 0.0       # first person: how much of the torso's forward lean is taken out
var _view_clip := false   # first person: the body is playing a "view_" clip this frame...
var _pin := 0.0           # ...so its neck is pinned to the camera (eases in and out)
var _snap_view := false   # first person was just switched on or off
var _stance := Quaternion.IDENTITY   # the chest's turn for the gun's stance (from its aim clip)
var _carry := 0.0         # sprinting with a long gun: arms holding it across the chest
var _carry_pose: RobotPose
var _fire_t := -1.0       # time into the gun's fire clip (pump, bolt), or -1
var _kick := 1.0
var _loop_reload := false
var _melee := false       # a melee weapon: held and swung by MeleeSwing, not by clips
var _swing := MeleeSwing.new()
var _hold := 1.0          # how much the arms hold the weapon up (0 in a flip, a roll, a climb)
var _swing_key: Array = []   # the swing's pose this frame
var _sink := 0.0             # how far the body has sunk into its knees with the swing, 0..1
var _airborne := false       # off the ground in a plain fall, flip or glide: a melee wind-up takes its mid-air form
var _was_slam := false       # in a ground slam last frame
var _tuck := 0.0             # how far the legs are drawn up by a mid-air wind-up or a slam, 0..1
var _leg_t := -1.0        # time into a kick, or -1
var _flying_kick := false # in a flying kick: feet first
var _fly_w := 0.0
var _glide_secs := 0.0    # seconds into the glide under way (or the one just let go)
var _glide_weak := 0.0    # how weakened the glide looks, 0..1 (from its fall: see _glide_body)
var _gflip_t := -1.0      # seconds into a backflip out of a glide (of GLIDE_FLIP_TIME), or -1
var _gflip_rate := 1.0    # how fast it is going round (hurried by a shot or by the floor)
var _gflip_hurried := false   # a shot or a swing has hurried it: the arms are free again
var _gflip_from := 0.0    # the hips' forward lean it started from, radians
var _glide_lean := 0.0    # the hips' forward lean in the glide, radians (the backflip starts from it)
## How the body hangs on the rope (ViewModel reads it too, so your arms
## in first person move with the body everyone else sees).
var rope := RopeSwing.new()
var _rope_low := 0.0         # on the rope with the gun (or blade) down at your side, 0..1
var _drag := 0.0             # on your belly on the floor, dragged by the rope: the body's turn to face the hook, radians

var _b := {}                      # bone name -> index
var _arm_r: PackedInt32Array
var _arm_l: PackedInt32Array
var _not_arms: PackedInt32Array
var _legs_core: PackedInt32Array


func _init(robot: RobotModel) -> void:
	model = robot
	rig = robot.rig
	_pose = rig.new_pose()
	_from = rig.new_pose()
	_base = rig.new_pose()
	_tmp = rig.new_pose()
	_aim = rig.new_pose()
	_b = rig.bones
	_arm_r = _bones(["upper_arm_r", "forearm_r", "hand_r", "pistol", "pistol_slide", "pistol_mag", "pistol_vent"] + Hands.RIGHT)
	_arm_l = _bones(["upper_arm_l", "forearm_l", "hand_l", "pistol_l", "pistol_l_slide", "pistol_l_mag", "pistol_l_vent"] + Hands.LEFT)
	_legs_core = _bones(["hips", "spine", "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"])
	for i in rig.bone_names.size():
		if not (i in _arm_r or i in _arm_l):
			_not_arms.append(i)
	_carry_pose = rig.new_pose()
	set_weapon(robot.weapon if robot.weapon != "" else "pistol")


## Hold this gun: its stance, reload and fire animations.
func set_weapon(id: String) -> void:
	var data := WeaponData.by_id(WeaponData.valid(id))
	weapon = WeaponData.look_of(data.id)   # (clips go by the weapon it looks like: the Golden Gun is the revolver)
	_kick = data.kick
	_loop_reload = data.reload_per_round
	_melee = data.is_melee()
	_akimbo = data.is_akimbo()
	if _melee:
		_swing.set_weapon(weapon)
	if rig.has_clip(clip("aim")):
		rig.sample(_aim, clip("aim"), 0.0)
	_reload_rate = 1.0
	if rig.has_clip(clip("reload")):
		if not _loop_reload and data.reload_time > 0.0:
			_reload_rate = rig.length(clip("reload")) / data.reload_time   # (1 but for the railgun: its 2.6 s clip, a 1.5 s reload)
		rig.sample(_tmp, clip("reload"), 0.0)
		_reload_chest = _tmp.rot[_b["chest"]].normalized()
		_reload_spine = _tmp.rot[_b["spine"]].normalized()
	_reload_t = -1.0
	_reload_out = 0.0
	_end_t = -1.0
	_stance = _aim.rot[_b["chest"]].normalized()
	if rig.has_clip("carry_" + weapon):
		rig.sample(_carry_pose, "carry_" + weapon, 0.0)


## Lays the reload clip at time t over the arms, `w` of it, and adds what it turns the
## chest and spine by to the body's own (the shoulders go with a reload's flourish).
func _lay_reload(rclip: String, t: float, w: float) -> void:
	rig.sample(_tmp, rclip, t)
	_pose.blend_bones(_tmp, w, _arm_r)
	_pose.blend_bones(_tmp, w, _arm_l)
	if first_person or w <= 0.0:
		return
	for part in [["chest", _reload_chest], ["spine", _reload_spine]]:
		var b: int = _b[part[0]]
		var by: Quaternion = (part[1] as Quaternion).inverse() * _tmp.rot[b]
		_pose.rot[b] = _pose.rot[b] * Quaternion.IDENTITY.slerp(by.normalized(), w)


## The gun's own version of a clip if it has one ("reload" -> "reload_rifle"), otherwise the clip.
func clip(base: String) -> String:
	var own := base + "_" + weapon
	return own if rig.has_clip(own) else base


func _bones(names: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for n in names:
		if _b.has(n):
			out.append(_b[n])
	return out


## A shot was fired: kick the gun (akimbo: the one in the left hand when `left`).
func fire(left: bool = false) -> void:
	if _akimbo and left:
		_recoil_l = _kick
	else:
		_recoil = _kick
	_since_fire = 0.0
	rope.hurry_flip()
	_end_glide_flip()
	if rope.w > 0.0:
		_aim_r = 1.0   # on the rope the gun was down at your side: it is up for this shot, not on its way
	if _end_t >= 0.0:   # a shot cuts the last flourish short: it eases back to the hold
		_reload_from = _end_t
		_reload_out_clip = clip("reload_end")
		_reload_out = 1.0
		_end_t = -1.0
	if rig.has_clip("fire_" + weapon):
		_fire_t = 0.0


## Winding a melee swing up, this frame: `charge` 0..1 is how far (the body coils with
## it), `side` which tap is coming (see MeleeSwing).
func wind(charge: float, side: int = 0) -> void:
	if _melee:
		_swing.wind(charge, side, _airborne)
		rope.hurry_flip()
		_end_glide_flip()


## The swing was let go, `power` 0..1 wound up.
func swing(power: float, side: int = 0) -> void:
	if _melee:
		_swing.swing(power, side, _airborne)
		_since_fire = 0.0
		rope.hurry_flip()
		_end_glide_flip()


## A kick (see Kick): the right leg snaps out in front.
func kick(flying: bool = false) -> void:
	rope.hurry_flip()
	_leg_t = 0.0 if not flying else -1.0
	if flying:
		_flying_kick = true


## A flying kick starts or ends: both legs out, leaning back, for as long as it lasts.
func set_flying_kick(on: bool) -> void:
	_flying_kick = on


## Front kick, over the pose: [thigh lift, knee bend, lean back] at time t.
const KICK_KEYS := [[0.0, 0.0, 0.0, 0.0], [0.07, 1.5, 1.9, 0.15], [0.15, 1.65, 0.05, 0.35], [0.26, 1.55, 0.1, 0.3], [0.45, 0.0, 0.0, 0.0]]


func _kick_sample(t: float) -> Array:
	for i in range(1, KICK_KEYS.size()):
		var b: Array = KICK_KEYS[i]
		if t <= b[0]:
			var a: Array = KICK_KEYS[i - 1]
			var u := smoothstep(0.0, 1.0, (t - a[0]) / (b[0] - a[0]))
			return [lerpf(a[1], b[1], u), lerpf(a[2], b[2], u), lerpf(a[3], b[3], u)]
	return [0.0, 0.0, 0.0]


func _apply_kick(delta: float, alive: bool) -> void:
	_fly_w = move_toward(_fly_w, 1.0 if (_flying_kick and alive) else 0.0, delta * 9.0)
	var lift := 0.0
	var bend := 0.0
	var lean := 0.0
	var w := 0.0
	if _leg_t >= 0.0:
		var k := _kick_sample(_leg_t)
		lift = k[0]
		bend = k[1]
		lean = k[2]
		w = 1.0
		_leg_t += delta
		if _leg_t >= KICK_KEYS[-1][0] or not alive:
			_leg_t = -1.0
	if _fly_w > 0.0:
		lift = lerpf(lift, 1.45, _fly_w)
		bend = lerpf(bend, 0.0, _fly_w)
		lean = lerpf(lean, 0.75, _fly_w)
		w = maxf(w, _fly_w)
	if w <= 0.0:
		return
	var t_r: int = _b["thigh_r"]
	var s_r: int = _b["shin_r"]
	_pose.rot[t_r] = _pose.rot[t_r].slerp(Quaternion(Vector3.RIGHT, lift), w)
	_pose.rot[s_r] = _pose.rot[s_r].slerp(Quaternion(Vector3.RIGHT, -bend), w)
	if _fly_w > 0.0:   # the other leg tucked up under you
		var t_l: int = _b["thigh_l"]
		var s_l: int = _b["shin_l"]
		_pose.rot[t_l] = _pose.rot[t_l].slerp(Quaternion(Vector3.RIGHT, 0.9), _fly_w)
		_pose.rot[s_l] = _pose.rot[s_l].slerp(Quaternion(Vector3.RIGHT, -1.9), _fly_w)
	var sp: int = _b["spine"]
	_pose.rot[sp] = Quaternion(Vector3.RIGHT, lean * w) * _pose.rot[sp]


## The blow landed: freeze the swing for a moment so the hit has weight.
func hit_stop(seconds: float = 0.07) -> void:
	_swing.hit_stop(seconds)


## How far a melee swing has turned the chest from where it rests, radians (+ = to the left).
func melee_turn() -> float:
	if not _melee or _swing_key.is_empty():
		return 0.0
	return (float(_swing_key[MeleeSwing.TURN]) - _swing.rest_turn()) * _hold


## The swing itself (its glow, its power, whether it is the heavy blow).
func melee_swing() -> MeleeSwing:
	return _swing


## In the middle of a blow (the swing trail is drawn).
func cutting() -> bool:
	return _swing.active() and _swing.cutting()


## Back to life: play the boot-up over whatever the body is doing.
func respawn() -> void:
	_respawn_t = 0.0
	_swing.stop()
	rope.stop()
	_dead_time = -1.0
	_reload_t = -1.0
	_land = 0.0
	_kick_t = -1.0
	_leg_t = -1.0
	_flying_kick = false
	_gflip_t = -1.0
	_fade = 1.0


func update(delta: float, inp: RobotAnimInput, model_xform: Transform3D) -> void:
	var local_vel := inp.velocity.rotated(Vector3.UP, -inp.yaw)   # x right, -z forward
	var speed := Vector2(local_vel.x, local_vel.z).length()
	rope.update(delta, inp, model_xform.origin)

	# --- 1. Body
	if source == "glide":
		_glide_secs += delta
	if _gflip_t >= 0.0:
		_gflip_t += delta * _gflip_rate
	var key := _pick(inp)
	if key != source:
		_switch(key, inp)
	_time += delta
	_fade = minf(_fade + delta / _fade_time, 1.0)
	_sample_body(key, inp, local_vel, speed, delta)
	if _fade < 1.0:
		_tmp.copy(_from)
		_tmp.blend(_pose, smoothstep(0.0, 1.0, _fade))
		_pose.copy(_tmp)
	_base.copy(_pose)
	_prev_vy = inp.velocity.y

	# --- 2. Overlays
	if _land > 0.0 and rig.has_clip("land"):
		# The landing plays through once (it dips, then comes back up a little past
		# standing), as strong as the fall was hard, and lets go over its second half.
		var land_len := rig.length("land")
		rig.sample(_tmp, "land", _land_t)
		_pose.blend_bones(_tmp, _land * (1.0 - smoothstep(0.5, 1.0, _land_t / land_len)), _not_arms)
		_land_t += delta
		if _land_t >= land_len:
			_land = 0.0
	var jumps := inp.wall_jumps()
	if _wall_jumps >= 0 and jumps != _wall_jumps and inp.alive:
		_kick_t = 0.0
		_kick_right = inp.wall_right()
	_wall_jumps = jumps
	if _kick_t >= 0.0:
		var kick_clip := "wall_jump_r" if _kick_right else "wall_jump_l"
		if rig.has_clip(kick_clip) and _kick_t < rig.length(kick_clip) and key in ["air", "tuck"]:
			var len := rig.length(kick_clip)
			rig.sample(_tmp, kick_clip, _kick_t)
			_pose.blend_bones(_tmp, clampf((len - _kick_t) / (len * 0.5), 0.0, 1.0), _not_arms)
			_kick_t += delta
		else:
			_kick_t = -1.0
	if _respawn_t >= 0.0:
		var rclip := clip("respawn")
		if rig.has_clip(rclip) and _respawn_t < rig.length(rclip) and inp.alive:
			rig.sample(_tmp, rclip, _respawn_t)
			_pose.blend(_tmp, 1.0 - smoothstep(0.3, 1.0, _respawn_t / rig.length(rclip)))
			_respawn_t += delta
		else:
			_respawn_t = -1.0
	# Let go of the rope on the way up: one roll forward, over whatever the fall is showing.
	var roll := rope.flip()
	if roll >= 0.0 and rig.has_clip("flip_front"):
		var roll_clip := _seen("flip_front")
		rig.sample(_tmp, roll_clip, roll * rig.length(roll_clip))
		_pose.blend(_tmp, clampf(minf(roll / 0.12, (1.0 - roll) / 0.18), 0.0, 1.0))
	# On the rope: the body tips over to hang along it (the chest less, and not at all with the gun up).
	var hanging := rope.w > 0.0 and key == "grapple"
	if hanging:
		# (Zipping along it, the whole body is in the line with the gun down; a shot brings the chest part of the way up.)
		var chest_up := lerpf(lerpf(1.0, ROPE_CHEST, _rope_low), lerpf(ZIP_CHEST, 0.0, _rope_low), rope.zip)
		rope.lay_body(_pose, _b, inp.yaw, 1.0 if first_person else chest_up, ROPE_VIEW if first_person else 1.0, not first_person)

	# --- First person: stand the torso up over the hips
	var ease := 1000.0 if _snap_view else delta
	_snap_view = false
	_pin = move_toward(_pin, 1.0 if _view_clip else 0.0, ease / 0.1)
	_upright = move_toward(_upright, 1.0 if first_person and not _view_clip and key not in VIEW_KEEP_LEAN else 0.0, ease * 6.0)
	if _upright > 0.0:
		var lower: Quaternion = _pose.rot[_b["root"]] * _pose.rot[_b["hips"]]
		var up := lower * _pose.rot[_b["spine"]] * _pose.rot[_b["chest"]] * Vector3.UP
		var forward_lean := clampf(atan2(-up.z, up.y), 0.0, VIEW_UPRIGHT_MAX)
		_pose.rot[_b["spine"]] = lower.inverse() * Quaternion(Vector3.RIGHT, forward_lean * _upright) * lower * _pose.rot[_b["spine"]]

	# --- 3. Arms
	_since_fire += delta
	var want: Array = AIM_WEIGHTS.get(key, [0.0, 0.0, 0.0])
	var want_r: float = want[0]
	var want_l: float = want[1] if not _melee else 0.0   # a melee weapon is held in one hand
	var sprinting := key == "loco" and speed > RUN_SPEED + 1.0 and _since_fire > 0.7 and _reload_t < 0.0 and _end_t < 0.0
	if sprinting:
		want_r = 0.0   # sprinting: arms pump (a long gun is carried across the chest), until you shoot
		want_l = 0.0
	var has_carry := weapon != "pistol" and rig.has_clip("carry_" + weapon)
	_carry = move_toward(_carry, 1.0 if sprinting and has_carry and inp.alive else 0.0, delta * 7.0)
	if _respawn_t >= 0.0:
		want_r = 0.0
		want_l = 0.0
	if roll >= 0.0 and not rope.flip_hurried():
		want_r = 0.0   # rolling off the rope: the arms are tucked in, until a shot cuts it short
		want_l = 0.0
	# On the rope the gun (or the blade) hangs at your side, until you use it.
	var in_use := _since_fire < ROPE_AIM_HOLD or inp.reloading() or _reload_t >= 0.0 or _end_t >= 0.0 or _fire_t >= 0.0 \
		or (_melee and _swing.active())
	# (Zipping, a shot has the whole upper body to bring round to the aim: it comes up fast.)
	_rope_low = move_toward(_rope_low, 1.0 if hanging and not in_use and inp.alive else 0.0,
		delta * (ZIP_AIM_UP if hanging and in_use and rope.zip > 0.0 else (ROPE_AIM_DROP if hanging else 9.0)))
	if hanging and not in_use:
		want_r = 0.0
		rope.lay_arm(_pose, _b, inp.yaw, 1.0, rig, _melee)
	_aim_r = move_toward(_aim_r, want_r, delta * (ROPE_AIM_DROP if hanging and want_r < _aim_r else 9.0))
	_aim_l = move_toward(_aim_l, want_l, delta * 9.0)
	_torso = move_toward(_torso, float(want[2]) * (1.0 - rope.zip * _rope_low if hanging else 1.0), delta * 8.0)   # (zipping with the gun down, the body stays in its line whatever the aim)
	if _carry > 0.0:
		_pose.blend_bones(_carry_pose, _carry, _arm_r)
		_pose.blend_bones(_carry_pose, _carry, _arm_l)
	_pose.blend_bones(_aim, _aim_r, _arm_r)
	_pose.blend_bones(_aim, _aim_l, _arm_l)

	var reloading := inp.reloading() and inp.alive
	var rclip := clip("reload")
	if reloading and not _was_reloading and rig.has_clip(rclip):
		_reload_t = 0.0
	_was_reloading = reloading
	_reload_w = 0.0
	if _reload_t >= 0.0:
		var rlen := rig.length(rclip)
		if _loop_reload and reloading and _reload_t >= rlen:
			_reload_t = fmod(_reload_t, rlen)   # a shell at a time: round and round until full
		if _reload_t >= rlen or not inp.alive or (not reloading and (_loop_reload or _reload_t < rlen - 0.3)):
			if _loop_reload and not reloading and inp.alive and _since_fire > 0.2 and rig.has_clip(clip("reload_end")):
				_end_t = 0.0   # full, and not stopped by a shot: the last flourish
			elif _reload_t < rlen and inp.alive:
				# Cut short (the gun was swapped, or fired between shells): the arms ease
				# back to the hold from where they were, not in one frame.
				_reload_from = _reload_t
				_reload_out_clip = rclip
				_reload_out = 1.0
			_reload_t = -1.0
		else:
			_reload_w = 1.0 if _loop_reload else clampf(minf(_reload_t / 0.1, (rlen - _reload_t) / 0.15), 0.0, 1.0)
			if want[2] <= 0.0:
				_reload_w = 0.0   # mid-flip, mid-roll: the hands are busy
			_lay_reload(rclip, _reload_t, _reload_w)
			_reload_t += delta * _reload_rate
	if _end_t >= 0.0:
		var eclip := clip("reload_end")
		var elen := rig.length(eclip)
		if _end_t >= elen or not inp.alive or reloading or want[2] <= 0.0:
			_end_t = -1.0
		else:
			_reload_w = clampf((elen - _end_t) / 0.12, 0.0, 1.0)
			_lay_reload(eclip, _end_t, _reload_w)
			_end_t += delta
	if _reload_t < 0.0 and _end_t < 0.0 and _reload_out > 0.0:
		_reload_out = move_toward(_reload_out, 0.0, delta / RELOAD_CUT_FADE) if rig.has_clip(_reload_out_clip) and want[2] > 0.0 else 0.0
		if _reload_out > 0.0:
			_lay_reload(_reload_out_clip, _reload_from, smoothstep(0.0, 1.0, _reload_out))

	# The pump or the bolt, after a shot (the left hand only where it is on the gun)
	if _fire_t >= 0.0:
		var fclip := "fire_" + weapon
		var flen := rig.length(fclip)
		if _fire_t >= flen or not inp.alive or _reload_w > 0.0:
			_fire_t = -1.0
		else:
			var fw := clampf(minf(_fire_t / 0.06, (flen - _fire_t) / 0.12), 0.0, 1.0)
			rig.sample(_tmp, fclip, _fire_t)
			_pose.blend_bones(_tmp, fw * _aim_r, _arm_r)
			_pose.blend_bones(_tmp, fw * minf(_aim_l, _aim_r), _arm_l)
			_fire_t += delta

	# A melee weapon: the body turns and leans with the wind-up and the blow (the arms
	# are bent to hold the weapon once the chest is where it will be, below).
	if _melee:
		if not inp.alive:
			_swing.stop()
		# A ground slam: the weapon overhead on the way down, driven into the floor on landing.
		_airborne = inp.state in [S.AIR, S.FLIP, S.GLIDE]
		var slam := inp.state == S.SLAM and inp.alive
		if slam:
			_swing.slam_fall()
		elif _was_slam and inp.alive:
			_swing.slam_land(1.0)
		_was_slam = slam
		_swing_key = _swing.sample(delta)
		var busy := _swing.active() and inp.alive
		var carried: bool = want[0] > 0.0 and inp.alive and _respawn_t < 0.0 and not (hanging and not in_use)   # (on the rope it hangs from the hand)
		_hold = move_toward(_hold, 1.0 if busy or carried else 0.0, delta * (ROPE_AIM_DROP if hanging and not busy else 9.0))
		# On its feet the body sinks into its knees as it coils (less on the run), then turns.
		var low := MeleeSwing.sink(_swing_key) * _hold * (1.0 - 0.6 * clampf(speed / 6.0, 0.0, 1.0)) if key == "loco" else 0.0
		low = maxf(low, _swing.landed())   # a slam lands in a deep crouch
		_sink = move_toward(_sink, low, delta * (20.0 if _swing.landed() > 0.0 else 8.0))
		# Off the ground, a wind-up of the weapon's own (and a slam) draws the legs up.
		_tuck = move_toward(_tuck, (0.75 if slam else 0.6 * _swing.air()) if inp.alive else 0.0, delta * 7.0)
		if maxf(_sink, _tuck) > 0.0:
			rig.sample(_tmp, "crouch_idle", 0.0)
			_pose.blend_bones(_tmp, maxf(_sink, _tuck), _legs_core)
		# A mid-air move with legs of its own (the superman punch: knee up, then kicked back).
		# A kick (a blow with legs of its own, on the ground) shows in first person too: your own leg comes up into view.
		var legs := _swing.legs()
		if not legs.is_empty() and (not first_person or _swing.legs_kick()) and inp.alive:
			var w: float = legs[4]
			for leg in [["thigh_r", "shin_r", 0, 5, 1.0], ["thigh_l", "shin_l", 2, 6, -1.0]]:
				var thigh: int = _b[leg[0]]
				var shin: int = _b[leg[1]]
				var out := Quaternion(Vector3.BACK, float(legs[leg[3]]) * float(leg[4]))   # lifted out to its own side
				_pose.rot[thigh] = _pose.rot[thigh].slerp(Quaternion(Vector3.RIGHT, legs[leg[2]]) * out, w)
				_pose.rot[shin] = _pose.rot[shin].slerp(Quaternion(Vector3.RIGHT, -legs[leg[2] + 1]), w)
			# A leg lifted out to the side tips the hips up after it (the body leans away), so a kick goes high.
			var tilt := (float(legs[5]) - float(legs[6])) * 0.4 * w
			if tilt != 0.0:
				_pose.rot[_b["hips"]] = Quaternion(Vector3.BACK, tilt) * _pose.rot[_b["hips"]]
				_pose.rot[_b["spine"]] = Quaternion(Vector3.BACK, -tilt * 0.6) * _pose.rot[_b["spine"]]
		MeleeSwing.turn_body(_pose, _b, _swing_key, _hold)
		# A mid-air wind-up spins the whole body about its middle (not the body you see from
		# inside it: your own view stays level, and the arms go round it instead).
		if _swing.spin() != 0.0 and not first_person and inp.alive:
			var round := Quaternion(_swing.spin_axis(), _swing.spin())
			var root: int = _b["root"]
			_pose.rot[root] = round * _pose.rot[root]
			_pose.pos[root] = SPIN_PIVOT + round * (_pose.pos[root] - SPIN_PIVOT)
		if model.melee:
			MeleeModel.set_glow(model.melee, _swing.glow() if inp.alive else 0.0)
		if model.melee_left:
			MeleeModel.set_glow(model.melee_left, _swing.glow() if inp.alive else 0.0)
	_apply_kick(delta, inp.alive)

	# A long gun's stance: the chest turns a little to bring the left shoulder forward
	var stance := maxf(_aim_r, _reload_w)
	var twist := Quaternion.IDENTITY.slerp(_stance, stance)
	_pose.rot[_b["chest"]] = _pose.rot[_b["chest"]] * twist
	_pose.rot[_b["head"]] = twist.inverse() * _pose.rot[_b["head"]]   # the head keeps looking where you aim

	# --- 4. Aim pitch through the spine, then the arms make up the difference
	var hips: int = _b["hips"]
	var spine: int = _b["spine"]
	var chest: int = _b["chest"]
	var head: int = _b["head"]
	_lean = move_toward(_lean, 0.0 if first_person else 1.0, ease * 8.0)
	var p := inp.pitch * _torso * _lean
	_pose.rot[spine] = Quaternion(Vector3.RIGHT, p * 0.25) * _pose.rot[spine]
	_pose.rot[chest] = Quaternion(Vector3.RIGHT, p * 0.25) * _pose.rot[chest]
	_pose.rot[head] = Quaternion(Vector3.RIGHT, p * 0.2) * _pose.rot[head]
	var chest_rot: Quaternion = _pose.rot[_b["root"]] * _pose.rot[hips] * _pose.rot[spine] * _pose.rot[chest]
	var chest_fwd := chest_rot * Vector3.FORWARD
	var chest_pitch := asin(clampf(chest_fwd.y, -1.0, 1.0))
	_recoil = _recoil * exp(-delta * 16.0)
	_recoil_l = _recoil_l * exp(-delta * 16.0)
	var aim_lift := clampf(inp.pitch - chest_pitch, -1.7, 1.7)
	var lift := aim_lift + minf(_recoil, 1.5) * 0.2
	var lift_l := aim_lift + minf(_recoil_l if _akimbo else _recoil, 1.5) * 0.2
	var up_r: int = _b["upper_arm_r"]
	var up_l: int = _b["upper_arm_l"]
	var w_r := maxf(_aim_r, _reload_w)
	var w_l := maxf(_aim_l, _reload_w)
	var across := twist.inverse() * Vector3.RIGHT   # the body's left-right axis, seen from the turned chest
	_pose.rot[up_r] = Quaternion(across, lift * w_r) * _pose.rot[up_r]
	_pose.rot[up_l] = Quaternion(across, lift_l * w_l) * _pose.rot[up_l]
	if _b.has("pistol_slide") and (weapon == "pistol" or _akimbo):
		_pose.pos[_b["pistol_slide"]] += Vector3(0.0, 0.035 * _recoil, 0.0)
	if _akimbo and _b.has("pistol_l_slide"):
		_pose.pos[_b["pistol_l_slide"]] += Vector3(0.0, 0.035 * _recoil_l, 0.0)
	if _melee and _hold > 0.0:
		# The weapon follows the aim up and down about the shoulders, a little less than a gun does.
		# (The swing's own lean is taken out in full, so a thrust stays level as the body leans into it.)
		MeleeSwing.hold(_pose, rig, _swing_key, _swing.two_handed,
			clampf(inp.pitch - chest_pitch, -1.2, 1.2) * 0.8 + float(_swing_key[MeleeSwing.LEAN]) * _hold * 0.2, _hold, _hold,
			Vector3.ZERO, _swing.other_fist(), _swing.left_fist())

	# --- 6 (before the waist turn, which must not move the chest). Grapple arm
	_grapple_w = move_toward(_grapple_w, 1.0 if (inp.grapple_on and inp.alive) else 0.0, delta * 10.0)
	_reach_rope(inp, model_xform)

	# --- 5. Legs face the way we are moving
	var twist_target := 0.0
	if key in ["loco", "crouch"] and speed > 1.5:
		var angle := atan2(local_vel.x, -local_vel.z)   # 0 forward, positive to the right
		if _reverse and absf(angle) < deg_to_rad(95.0):
			_reverse = false
		elif not _reverse and absf(angle) > deg_to_rad(115.0):
			_reverse = true
		if _reverse:
			angle -= signf(angle) * PI
		twist_target = -angle
	elif key == "glide" or key == "glide_flip":
		_reverse = false
		if speed > 1.0:
			twist_target = -atan2(local_vel.x, -local_vel.z)   # the legs trail behind wherever you are going, however far round that is
	elif hanging:
		_reverse = false
		twist_target = rope.twist(inp.yaw, rope.zip * _rope_low) * rope.w   # the hips face along the swing; the chest stays on your aim
	else:
		_reverse = false
	_twist = lerp_angle(_twist, twist_target, 1.0 - exp(-delta * 12.0))
	if key == "glide_flip" and not first_person:
		# The backflip goes over the line of the track: the whole body turns to it, not just the legs.
		var whole := Quaternion(Vector3.UP, _twist)
		var root_i: int = _b["root"]
		_pose.rot[root_i] = whole * _pose.rot[root_i]
		_pose.pos[root_i] = whole * _pose.pos[root_i]
	elif absf(_twist) > 0.002:
		var h: Quaternion = _pose.rot[hips]
		var turned := Quaternion(Vector3.UP, _twist) * h
		_pose.rot[hips] = turned
		# (Zipping along the rope with the gun down, the chest goes round with the hips: the whole body faces down the line.)
		var keep := 1.0 - rope.zip * _rope_low if hanging else 1.0
		_pose.rot[spine] = _pose.rot[spine].slerp(turned.inverse() * h * _pose.rot[spine], keep)
		if keep < 1.0:
			_reach_rope(inp, model_xform)   # (the chest has moved: the hook arm finds the rope again)
	if hanging:
		rope.lay_legs(_pose, _b, inp.yaw)
	# Dragged along the floor on your belly by the rope: the whole body turns to face the
	# hook (not the body you see from inside it, and not while you shoot: it aims again).
	var drag_to := 0.0
	if key == "belly_slide" and inp.hook_taut >= 0.0 and not first_person and not in_use:
		var pull := rope.rope(inp.yaw)
		if Vector2(pull.x, pull.z).length() > 0.2:
			drag_to = atan2(-pull.x, -pull.z)
	_drag = lerp_angle(_drag, drag_to, 1.0 - exp(-delta * DRAG_TURN))
	if absf(_drag) > 0.002:
		var round_to := Quaternion(Vector3.UP, _drag)
		var root_at: int = _b["root"]
		_pose.rot[root_at] = round_to * _pose.rot[root_at]
		_pose.pos[root_at] = round_to * _pose.pos[root_at]
		_reach_rope(inp, model_xform)

	# --- Power (visor glow): off when dead, back on at respawn
	var power_target := 1.0
	if _dead_time >= 0.0:
		_dead_time += delta
		power_target = 0.0 if _dead_time > 0.25 else (1.0 if fmod(_dead_time, 0.1) < 0.05 else 0.2)
	_power = move_toward(_power, power_target, delta * (12.0 if power_target < _power else 2.5))
	model.set_power(_power)

	if _akimbo:
		Hands.set_hand(_pose, rig, "gun", 1.0 - _reload_w, true)   # the left hand has a gun of its own, whatever the arm is doing (a reload poses it itself)
	_plant_feet(delta, inp, key, speed)
	_pose.apply(model.skeleton)
	model.settle_sway(rope.stream(inp.yaw, inp.velocity) * rope.w if hanging else Vector3.ZERO)   # a custom character's cape and tail
	# The reload's own effects: the gun's glow, the spent cell thrown clear. (In first
	# person the arms you see are ViewModel's, and it throws the cell.)
	var fx_t := _reload_t if _reload_w > 0.0 and _reload_t >= 0.0 else -1.0
	ReloadFx.update(model, weapon, _fx_t, fx_t, null if first_person else fx_parent, inp.velocity)
	_fx_t = fx_t


## The left arm reaches for the grappling hook (its launcher is on that wrist), from
## wherever the chest is in the pose now.
func _reach_rope(inp: RobotAnimInput, model_xform: Transform3D) -> void:
	if _grapple_w <= 0.0:
		return
	var hips: int = _b["hips"]
	var spine: int = _b["spine"]
	var chest: int = _b["chest"]
	var up_l: int = _b["upper_arm_l"]
	var root_at := Transform3D(Basis(_pose.rot[_b["root"]]), _pose.pos[_b["root"]])
	var chest_at := root_at * Transform3D(Basis(_pose.rot[hips]), _pose.pos[hips]) * Transform3D(Basis(_pose.rot[spine]), _pose.pos[spine]) \
		* Transform3D(Basis(_pose.rot[chest]), _pose.pos[chest])
	var to_anchor := model_xform.affine_inverse() * inp.grapple_anchor - chest_at * _pose.pos[up_l]
	if to_anchor.length_squared() <= 0.01:
		return
	var dir := chest_at.basis.inverse() * to_anchor.normalized()
	var reach := Quaternion(Vector3.DOWN, dir) if dir.dot(Vector3.DOWN) > -0.999 else Quaternion(Vector3.RIGHT, PI)
	_pose.rot[up_l] = _pose.rot[up_l].slerp(reach, _grapple_w)
	# (The jolt as the rope pulls tight straightens it right out.)
	_pose.rot[_b["forearm_l"]] = _pose.rot[_b["forearm_l"]].slerp(Quaternion(Vector3.RIGHT, 0.12 * (1.0 - clampf(rope.lunged(), 0.0, 1.0) * rope.w)), _grapple_w)
	_pose.rot[_b["hand_l"]] = _pose.rot[_b["hand_l"]].slerp(Quaternion.IDENTITY, _grapple_w)


## Standing or crouching still on a slope or a step: each foot rests on the ground under
## it (RobotAnimInput.feet) and the hips come down a little for the lower one, in place
## of both feet staying level with one in the air or in the ground. Looks only: the
## body's place and its hitbox are the player's, as ever.
func _plant_feet(delta: float, inp: RobotAnimInput, key: String, speed: float) -> void:
	var on := key in ["loco", "crouch"] and speed < FEET_STILL and inp.alive and _land <= 0.0
	_feet_w = move_toward(_feet_w, 1.0 if on else 0.0, delta * 5.0)
	if on:
		var want := Vector2(clampf(inp.feet.x, -FEET_REACH, FEET_REACH), clampf(inp.feet.y, -FEET_REACH, FEET_REACH))
		_feet = _feet.lerp(want, 1.0 - exp(-delta * 10.0))
	# (On level ground this does nothing at all: the legs are left exactly as the clip has them.)
	var w := smoothstep(0.0, 1.0, _feet_w) * clampf((absf(_feet.x) + absf(_feet.y)) / 0.02, 0.0, 1.0)
	if w <= 0.001:
		return
	var root: int = _b["root"]
	var hips: int = _b["hips"]
	var root_at := Transform3D(Basis(_pose.rot[root]), _pose.pos[root])
	var before := root_at * Transform3D(Basis(_pose.rot[hips]), _pose.pos[hips])
	_pose.pos[hips] += root_at.basis.inverse() * Vector3(0.0, clampf(minf(_feet.x, _feet.y), -FEET_DROP, 0.0) * w, 0.0)
	var after := root_at * Transform3D(Basis(_pose.rot[hips]), _pose.pos[hips])
	_reach_foot(before, after, "l", _feet.x, w)
	_reach_foot(before, after, "r", _feet.y, w)


## One leg bent (or straightened) to put its ankle `rise` above where the clip has it,
## from hips that have moved from `before` to `after`. The knee keeps the way it points,
## and the foot the way it lies.
func _reach_foot(before: Transform3D, after: Transform3D, side: String, rise: float, w: float) -> void:
	var th: int = _b["thigh_" + side]
	var sh: int = _b["shin_" + side]
	var ft: int = _b["foot_" + side]
	var thigh0 := before * Transform3D(Basis(_pose.rot[th]), _pose.pos[th])
	var shin0 := thigh0 * Transform3D(Basis(_pose.rot[sh]), _pose.pos[sh])
	var foot0 := shin0 * Transform3D(Basis(_pose.rot[ft]), _pose.pos[ft])
	var hip := after * _pose.pos[th]
	var upper := _pose.pos[sh].length()
	var lower := _pose.pos[ft].length()
	var to := foot0.origin + Vector3(0.0, rise * w, 0.0) - hip
	if to.length_squared() < 0.000001:
		return
	var dist := clampf(to.length(), absf(upper - lower) + 0.01, (upper + lower) * 0.999)
	var dir := to.normalized()
	var along := (upper * upper - lower * lower + dist * dist) / (2.0 * dist)
	var out := sqrt(maxf(upper * upper - along * along, 0.0))
	var knee0 := shin0.origin + (after.origin - before.origin) - hip   # the knee as the clip has it, from the hip
	var side_dir := knee0 - dir * knee0.dot(dir)
	if side_dir.length_squared() < 0.000001:
		side_dir = after.basis * Vector3.FORWARD
		side_dir -= dir * side_dir.dot(dir)
	side_dir = side_dir.normalized()
	var knee := hip + dir * along + side_dir * out
	var ankle := hip + dir * dist
	var hinge := dir.cross(side_dir).normalized()   # the knee's axis: both bones' own +X (as rig.py's legs have it)
	var thigh_y := (hip - knee).normalized()
	var shin_y := (knee - ankle).normalized()
	var thigh_rot := Basis(hinge, thigh_y, hinge.cross(thigh_y)).get_rotation_quaternion()
	var shin_rot := Basis(hinge, shin_y, hinge.cross(shin_y)).get_rotation_quaternion()
	_pose.rot[th] = _pose.rot[th].slerp(after.basis.get_rotation_quaternion().inverse() * thigh_rot, w)
	_pose.rot[sh] = _pose.rot[sh].slerp(thigh_rot.inverse() * shin_rot, w)
	_pose.rot[ft] = _pose.rot[ft].slerp(shin_rot.inverse() * foot0.basis.get_rotation_quaternion(), w)


## Your own body in first person: you see your legs and torso (not the head or the
## arms; ViewModel draws those). Call after update(). The body is kept under and a
## little behind the camera whatever it is doing, so you never look into your own
## chest: its neck stays behind the eyes (by the depth of this robot's chest),
## further back the more you look down.
## amount: 1 in first person, 0 in third person (CameraRig.first_person_amount).
func place_for_view(amount: float, eye_height: float, pitch: float) -> void:
	if model.view_mesh:
		model.view_mesh.visible = amount > 0.0
	if amount <= 0.0:
		model.position = Vector3.ZERO
		return
	var neck := model.bone_position("head")
	var back := model.chest_front + VIEW_BACK \
		+ VIEW_BACK_DOWN * clampf((-pitch - VIEW_BACK_FROM) / (deg_to_rad(89.0) - VIEW_BACK_FROM), 0.0, 1.0)
	var height := eye_height - VIEW_NECK_BELOW - neck.y
	var offset := Vector3(clampf(-neck.x, -VIEW_SIDE, VIEW_SIDE), minf(height, 0.0), back - neck.z)
	# A "view_" clip is made for the camera: its neck goes exactly where the camera expects it.
	offset = offset.lerp(Vector3(-neck.x, height, back - neck.z), _pin)
	model.position = offset * amount


func _pick(inp: RobotAnimInput) -> String:
	if not inp.alive:
		_gflip_t = -1.0
		return "death"
	# Let go of a glide in mid-air (after a real glide, not a tap): backflip out of it.
	# Anything but a plain fall (landing, the rope, a flip, a dive, a wall) cuts it short.
	if inp.state != S.AIR:
		_gflip_t = -1.0
	elif source == "glide" and _glide_secs >= GLIDE_FLIP_AFTER:
		_gflip_t = 0.0
		_gflip_rate = 1.0
		_gflip_hurried = false
		_gflip_from = _glide_lean
	if _gflip_t >= 0.0 and _gflip_t < GLIDE_FLIP_TIME:
		return "glide_flip"
	_gflip_t = -1.0
	match inp.state:
		S.GROUND: return "loco"
		S.CROUCH: return "crouch"
		S.SLIDE: return "slide"
		S.AIR: return "tuck" if inp.crouched else "air"
		S.GRAPPLE: return "grapple"
		S.WALL_RUN, S.WALL_SIT: return "wall_r" if inp.wall_right() else "wall_l"   # (a wall sit leans on the wall-run pose for now)
		S.MANTLE: return "vault" if inp.vaulting() else "climb"
		S.DIVE: return "dive"
		S.ROLL: return "roll"
		S.BELLY_SLIDE: return "belly_slide"
		S.FLIP: return FLIPS[inp.flip()]
		S.GLIDE: return "glide"
	return "air"


func _switch(key: String, inp: RobotAnimInput) -> void:
	# Landing: dip in proportion to how hard we came down.
	if source in AIRBORNE and key in ["loco", "crouch"] and _prev_vy < -3.0:
		_land = clampf(-_prev_vy / 13.0, 0.3, 1.0)
		_land_t = 0.0
	if key == "air":
		_air_t = _air_target(inp.velocity.y)
	if key == "death":
		_dead_time = 0.0
	if key == "glide" and source != "glide_flip":
		_glide_secs = 0.0   # a new glide (back into one out of its backflip, it carries on)
		_glide_weak = 0.0
	_from.copy(_base)
	_fade = 0.0 if source != "" else 1.0
	_fade_time = FADES.get(key, FADE_DEFAULT)
	_time = 0.0
	source = key


func _air_target(vy: float) -> float:
	return clampf(remap(vy, 7.0, -12.0, 0.0, 1.0), 0.0, 1.0)


## The clip to play for `clip`: in first person, its "view_" version if there is one.
func _seen(clip: String) -> String:
	if first_person and rig.has_clip("view_" + clip):
		_view_clip = true
		return "view_" + clip
	return clip


func _sample_body(key: String, inp: RobotAnimInput, local_vel: Vector3, speed: float, delta: float) -> void:
	var direction := -1.0 if _reverse else 1.0
	_view_clip = false
	match key:
		"loco":
			var wr := clampf(speed / RUN_SPEED, 0.0, 1.0)
			var ws := clampf((speed - RUN_SPEED) / (SPRINT_SPEED - RUN_SPEED), 0.0, 1.0)
			var run_len := rig.length("run")
			var sprint_len := rig.length("sprint")
			var rate := clampf(speed / lerpf(RUN_SPEED, SPRINT_SPEED, ws), 0.6, 1.5) / lerpf(run_len, sprint_len, ws)
			_phase = fposmod(_phase + rate * delta * direction, 1.0)
			# Standing still: the plain idle, and over it the torso's own (its habit), which is
			# a whole number of the plain one's breaths long. Not while shooting or reloading.
			var calm := _since_fire > HABIT_AFTER and _reload_t < 0.0 and _end_t < 0.0 and not (_melee and _swing.active())
			_habit = move_toward(_habit, 1.0 if calm and model.idle != "idle" else 0.0, delta * 4.0)
			_idle_time = fmod(_idle_time + delta, rig.length(model.idle))
			rig.sample(_pose, "idle", fmod(_idle_time, rig.length("idle")))
			if _habit > 0.0 and wr < 1.0:
				rig.sample(_tmp, model.idle, _idle_time)
				_pose.blend(_tmp, smoothstep(0.0, 1.0, _habit))
			if wr > 0.01:
				rig.sample(_tmp, "run", _phase * run_len)
				_pose.blend(_tmp, smoothstep(0.0, 1.0, wr))
			if ws > 0.01:
				rig.sample(_tmp, "sprint", _phase * sprint_len)
				_pose.blend(_tmp, ws)
		"crouch":
			var wc := clampf(speed / (CROUCH_SPEED * 0.6), 0.0, 1.0)
			var walk_len := rig.length("crouch_walk")
			_phase = fposmod(_phase + clampf(speed / CROUCH_SPEED, 0.5, 1.6) / walk_len * delta * direction, 1.0)
			_idle_time = fmod(_idle_time + delta, rig.length("crouch_idle"))
			rig.sample(_pose, "crouch_idle", _idle_time)
			if wc > 0.01:
				rig.sample(_tmp, "crouch_walk", _phase * walk_len)
				_pose.blend(_tmp, smoothstep(0.0, 1.0, wc))
		"air":
			_air_t = lerpf(_air_t, _air_target(inp.velocity.y), 1.0 - exp(-delta * 14.0))
			rig.sample(_pose, "air", _air_t * rig.length("air"))
		"tuck":
			_loop("air_tuck")
		"glide":
			rig.sample(_pose, "air", 0.5 * rig.length("air"))
			_glide_body(inp.velocity, delta)
		"glide_flip":
			var turned := clampf(_gflip_t / GLIDE_FLIP_TIME, 0.0, 1.0)
			if first_person and rig.has_clip("view_flip_back"):
				# Your own legs, made to be seen from the eyes: kicked up in front, tucked, dropped away.
				var fclip := _seen("flip_back")
				rig.sample(_pose, fclip, turned * rig.length(fclip))
			else:
				_glide_flip_body(turned, inp.velocity.y)
		"belly_slide":
			# Sliding: a still pose. Slowed to a crawl: the knees work, at crawling pace.
			_loop("belly_slide")
			var wc := clampf((CRAWL_SPEED + 0.6 - speed) / 0.6, 0.0, 1.0) * clampf(speed / 0.5, 0.0, 1.0)
			if wc > 0.01 and rig.has_clip("belly_crawl"):
				var crawl_len := rig.length("belly_crawl")
				_phase = fposmod(_phase + clampf(speed / CRAWL_SPEED, 0.4, 1.4) / crawl_len * delta, 1.0)
				rig.sample(_tmp, "belly_crawl", _phase * crawl_len)
				_pose.blend(_tmp, smoothstep(0.0, 1.0, wc))
		"slide", "grapple", "dive":
			_loop(key)
		"wall_l", "wall_r":
			var clip := "wall_run_l" if key == "wall_l" else "wall_run_r"
			if rig.has_clip(clip):
				var wlen := rig.length(clip)
				_phase = fposmod(_phase + clampf(speed / WALL_SPEED, 0.6, 1.4) / wlen * delta, 1.0)
				rig.sample(_pose, clip, _phase * wlen)
			else:
				_loop("air")
		_:   # one-shots: vault, climb, roll, flips, death
			var clip := _seen(key)
			if rig.has_clip(clip):
				rig.sample(_pose, clip, minf(_time, rig.length(clip)))
			else:
				rig.sample(_pose, "air", 0.5 * rig.length("air"))


## Gliding: the body tipped into the wind along the track (the waist turn in update
## points the hips down it), the legs together in line behind, toes pointed, drifting
## gently. The chest leans into the flight only as far as you aim down the track; aim
## across it or back along it and the upper body stays up on your aim. It snaps into
## the pose (a little past it, then settles), and as the glide weakens (it shows in how
## fast you fall) it tips nose-down and the legs start to kick.
func _glide_body(velocity: Vector3, delta: float) -> void:
	var fast := clampf(Vector2(velocity.x, velocity.z).length() / GLIDE_FAST, 0.0, 1.0)
	_glide_weak = move_toward(_glide_weak, clampf(-velocity.y / GLIDE_WEAK_FALL, 0.0, 1.0), delta * 2.5)
	var weak := smoothstep(0.0, 1.0, _glide_weak)
	var u := clampf(_time / GLIDE_LAUNCH, 0.0, 1.0)
	var c3 := 2.4   # ease out with a little overshoot: it snaps into the pose
	var snap := 1.0 + (c3 + 1.0) * pow(u - 1.0, 3.0) + c3 * pow(u - 1.0, 2.0)
	var lean := deg_to_rad(lerpf(lerpf(GLIDE_LEAN_HANG, GLIDE_LEAN, fast), GLIDE_LEAN_DIVE, weak)) * snap
	var along := maxf(cos(_twist), 0.0)   # 1 aiming down the track, 0 aiming across it or back
	var chest := deg_to_rad(lerpf(GLIDE_CHEST, GLIDE_CHEST_DIVE, weak)) * along * snap
	var drift := sin(_time * TAU / 1.6) * deg_to_rad(3.0) * (1.0 - weak)
	var kick := sin(_time * TAU * GLIDE_KICK_RATE) * deg_to_rad(GLIDE_KICK) * weak
	var legs := deg_to_rad(GLIDE_LEGS) * fast * snap
	_glide_lean = lean
	_pose.rot[_b["hips"]] = Quaternion(Vector3.RIGHT, -lean)
	# The spine gives the hips' lean back, less what the chest leans in: the chest is where
	# the aim (step 4) and the arms build from, and the waist turn keeps it there.
	_pose.rot[_b["spine"]] = Quaternion(Vector3.RIGHT, lean - chest) * _pose.rot[_b["spine"]]
	# (thigh angles are from the tipped hips: the legs ride a touch above its line)
	_pose.rot[_b["thigh_l"]] = Quaternion(Vector3.RIGHT, -legs - drift + kick) * Quaternion(Vector3.BACK, -0.04)
	_pose.rot[_b["thigh_r"]] = Quaternion(Vector3.RIGHT, -legs * 0.8 + drift - kick) * Quaternion(Vector3.BACK, 0.04)
	_pose.rot[_b["shin_l"]] = Quaternion(Vector3.RIGHT, -deg_to_rad(6.0 + 34.0 * weak * (0.5 + 0.5 * sin(_time * TAU * GLIDE_KICK_RATE))))
	_pose.rot[_b["shin_r"]] = Quaternion(Vector3.RIGHT, -deg_to_rad(lerpf(16.0, 10.0, fast) + 34.0 * weak * (0.5 - 0.5 * sin(_time * TAU * GLIDE_KICK_RATE))))
	_pose.rot[_b["foot_l"]] = Quaternion(Vector3.RIGHT, -deg_to_rad(42.0))
	_pose.rot[_b["foot_r"]] = Quaternion(Vector3.RIGHT, -deg_to_rad(42.0))
	_pose.pos[_b["hips"]] += Vector3(0.0, 0.015 * sin(_time * TAU / 1.6), 0.0)


## The backflip out of a glide, `turned` 0..1 of the way through (GLIDE_FLIP_KEYS): the
## body goes on round from the lean the glide left it at, backward, about its hips: up
## out of the flying pose with the back arched and the arms flung wide, slow over the
## top with one knee up and the other leg long behind, a quick tuck through the last of
## the turn, and out into the fall's own pose.
func _glide_flip_body(turned: float, vy: float) -> void:
	rig.sample(_pose, "air", _air_target(vy) * rig.length("air"))
	var k := _flip_key(turned)
	var own := 1.0 - smoothstep(0.82, 1.0, turned)   # how much is the flip's pose, not yet the fall's
	var angle := lerpf(-_gflip_from, 0.0, clampf(turned / 0.14, 0.0, 1.0)) + deg_to_rad(k[0])
	var arch: float = k[1]
	var wide: float = clampf(k[2], 0.0, 1.0)
	var knee_l: float = clampf(k[3], 0.0, 1.0)
	var knee_r: float = clampf(k[4], 0.0, 1.0)
	var hips: int = _b["hips"]
	_pose.rot[hips] = Quaternion(Vector3.RIGHT, angle) * Quaternion.IDENTITY.slerp(_pose.rot[hips], 1.0 - own)
	_to(_b["spine"], Quaternion(Vector3.RIGHT, arch * 0.42), own)
	_to(_b["chest"], Quaternion(Vector3.RIGHT, arch * 0.34), own)
	_to(_b["head"], Quaternion(Vector3.RIGHT, arch * 0.38), own)   # looking back over for the way down
	# One knee drawn to the chest, the other leg long behind; both in for the tuck.
	_to(_b["thigh_l"], Quaternion(Vector3.RIGHT, lerpf(-0.2, 1.95, knee_l)) * Quaternion(Vector3.BACK, -0.06), own)
	_to(_b["shin_l"], Quaternion(Vector3.RIGHT, -lerpf(0.2, 2.2, knee_l)), own)
	_to(_b["thigh_r"], Quaternion(Vector3.RIGHT, lerpf(-0.55, 1.7, knee_r)) * Quaternion(Vector3.BACK, 0.06), own)
	_to(_b["shin_r"], Quaternion(Vector3.RIGHT, -lerpf(0.12, 2.0, knee_r)), own)
	_to(_b["foot_l"], Quaternion(Vector3.RIGHT, -0.75), own)
	_to(_b["foot_r"], Quaternion(Vector3.RIGHT, -0.75), own)
	# The arms flung out wide and a little back; in to the chest for the tuck.
	var tucked := clampf(-arch / 0.7, 0.0, 1.0)
	for side in [["upper_arm_r", "forearm_r", 1.0], ["upper_arm_l", "forearm_l", -1.0]]:
		var out := Quaternion(Vector3.BACK, float(side[2]) * lerpf(0.25, 1.3, wide)) * Quaternion(Vector3.RIGHT, lerpf(0.75, -0.45, wide))
		_to(_b[side[0]], out, own)
		_to(_b[side[1]], Quaternion(Vector3.RIGHT, lerpf(0.3, 1.7, tucked)), own)


## GLIDE_FLIP_KEYS at `turned`, eased through the keys: [degrees round, arch, arms, left knee, right knee].
func _flip_key(turned: float) -> Array:
	var keys := GLIDE_FLIP_KEYS
	var i := 0
	while i < keys.size() - 2 and turned > float(keys[i + 1][0]):
		i += 1
	var a: Array = keys[i]
	var b: Array = keys[i + 1]
	var before: Array = keys[maxi(i - 1, 0)]
	var after: Array = keys[mini(i + 2, keys.size() - 1)]
	var t0: float = a[0]
	var w := clampf((turned - t0) / (float(b[0]) - t0), 0.0, 1.0)
	var out := []
	for n in range(1, a.size()):
		out.append(cubic_interpolate_in_time(float(a[n]), float(b[n]), float(before[n]), float(after[n]), w,
			float(b[0]) - t0, float(before[0]) - t0 - (0.1 if i == 0 else 0.0), float(after[0]) - t0 + (0.1 if i + 2 > keys.size() - 1 else 0.0)))
	return out


## Bone `i` goes `w` of the way to `rot`.
func _to(i: int, rot: Quaternion, w: float) -> void:
	_pose.rot[i] = _pose.rot[i].slerp(rot, w)


## A shot or a swing hurries a backflip out of a glide to its end (the arms are wanted).
func _end_glide_flip() -> void:
	if _gflip_t >= 0.0 and _gflip_t < GLIDE_FLIP_TIME:
		_gflip_hurried = true
		_gflip_rate = maxf(_gflip_rate, (GLIDE_FLIP_TIME - _gflip_t) / GLIDE_FLIP_HURRY)


## Backflipping out of a glide (the player says how long until the floor while it is).
func glide_flipping() -> bool:
	return source == "glide_flip" and _gflip_t >= 0.0


## ...and a shot or a swing has hurried it: the arms are free again already.
func glide_flip_hurried() -> bool:
	return _gflip_hurried


## The floor is `seconds` away: the backflip goes round faster if it must, to be over
## just before the landing (up to GLIDE_FLIP_RATE_MAX times as fast: lower than that
## and the landing cuts it short).
func glide_flip_floor_in(seconds: float) -> void:
	if _gflip_t < 0.0:
		return
	var left := GLIDE_FLIP_TIME - _gflip_t
	_gflip_rate = maxf(_gflip_rate, minf(left / maxf(seconds - GLIDE_FLIP_LAND, 0.02), GLIDE_FLIP_RATE_MAX))


func _loop(clip: String) -> void:
	clip = _seen(clip)
	if not rig.has_clip(clip):
		rig.sample(_pose, "air", 0.5 * rig.length("air"))
		return
	rig.sample(_pose, clip, fmod(_time, rig.length(clip)))
