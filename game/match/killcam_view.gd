class_name KillcamView
extends Node3D
## Plays a KillClip: the killer's view (their camera, their first-person arms and gun,
## their shots) with everyone else as stand-in bodies moving the way the clip says.
## Added to a world that already has the map in it: the arena (the death killcam) or
## the results screen's own little world (see KillcamScreen).
##
## Plays once and holds the last frame (`finished`), or, with `loop`, starts over.
##
## A blow (a kick, a crash into a wall, a blade; see KillScore.is_blow) plays in third
## person instead: the killer is a body like everyone else and the camera follows close
## behind them, turned towards the victim, so you see the swing or the kick land.
##
## A body knocked out falls the way it fell in the match: when the clip has its remains
## (KillClip.Wreck), the body gives way to the replay's own ragdoll or giblets, posed
## from that recording on the replay's clock (so slow motion slows the fall too, and a
## video saved frame by frame has it frame by frame). They are this replay's, freed
## with it or when it starts over. With gore off (Settings.gore), or with no recording,
## the body stays and plays its death instead.
##
## The map's moving parts (see MapReplay) are drawn as the clip has them at each moment,
## in `map` (the arena's, or the results screen's copy), and drawn live again when the
## replay ends. The killer's eyes turn onto the aim of each of their shots as it goes
## (KillClip.aim_fix), so the crosshair is where theirs was when they fired.

signal finished
signal kill_moment   ## the killing blow lands

const SLOW := 0.3            ## results screen: the kill plays at this speed...
const SLOW_FROM := 0.25      ## ...from this long before it...
const SLOW_UNTIL := 0.45     ## ...to this long after
const S := MovementController.State
## Third person: the camera sits this far behind the killer's head...
const CHASE_BACK := 3.4
const CHASE_UP := 0.9          ## ...this far above it...
const CHASE_SIDE := 0.7        ## ...this far to the right...
const CHASE_EASE := 18.0       ## ...and keeps up at this rate (1/s: tight, so a fast killer stays close)
const LOOK_EASE := 6.0         ## where it looks turns at this rate (smoother)
const CHASE_VICTIM := 18.0     ## turns towards the victim when they are this close (m)

var clip: KillClip
var slow_motion := false
var loop := false
## Stepped by hand (step()), rockets and all, instead of with the game's frames: for
## saving a video at a steady frame rate however fast the computer draws.
var manual := false
var time := 0.0              ## where we are, on the killer's clock (see KillClip)
var done := false
var camera: Camera3D
## Sounds: the killer's gun and movement as your own (2D); everyone else's guns and
## movement (footsteps, jumps, landings, slides, the grapple: PlayerSounds) in the world
## (3D) when `world_sound`.
var world_sound := true
## Watched from behind the killer (a blow), not through their eyes.
var third_person := false
## The map it plays in (its moving parts are put back as they were). Default: the one
## being played (MapRoot.current).
var map: Node

var _puppet: Player          # stands in for the killer, for their first-person arms
var _view: ViewModel
var _weapon := ""
var _ghosts: Dictionary = {} # id -> Ghost
var _fx: Node3D              # tracers, rockets, explosions
var _events: Array = []      # [time the killer saw it, event], in order
var _next := 0
var _killed := false
var _hook_rope: HookRope     # the killer's grappling hook rope
var _seen := {}              # killer: swing/kick counters last seen (see _watch)
var _akimbo_shots := 0
var _was_reloading := false
var _killer_body := Node3D.new()   # where the killer's feet are (their movement sounds come from here)
var _killer_anim := RobotAnimInput.new()
var _killer_sounds: PlayerSounds
var _chase_ready := false    # third person: the camera has been placed once (then it eases)
var _chase_look := Vector3.ZERO
var _wrecks: Dictionary = {}  # KillClip.Wreck -> the replay's own Ragdoll or Gibs for it (null: none could be made)
var _aim_keys: Array = []     # the killer's shots (KillClip.aim_keys)
var _shown_props: Array = []  # the map's parts this replay has drawn (to draw live again when it ends)


## One other player: a body that moves and animates the way the clip says.
class Ghost:
	var root := Node3D.new()
	var visual := Node3D.new()
	var robot: RobotModel
	var animator: RobotAnimator
	var anim := RobotAnimInput.new()
	var weapon := "?"
	var hook_rope: HookRope   # their grappling hook rope
	var sounds: PlayerSounds  # their footsteps, jumps, landings... (in the world)
	var seen := {}
	var akimbo_shots := 0


func setup(watch: KillClip, slow: bool = false) -> KillcamView:
	clip = watch
	slow_motion = slow
	name = "Killcam"
	third_person = KillScore.is_blow(int(clip.info.get("tags", 0)))
	time = clip.start
	for e in clip.events:
		_events.append([clip.event_time(e), e])
	_events.sort_custom(func(a, b): return a[0] < b[0])
	_aim_keys = clip.aim_keys()
	return self


func _ready() -> void:
	_fx = Node3D.new()
	_fx.name = "KillcamFx"
	add_child(_fx)
	_killer_body.name = "KillerBody"
	add_child(_killer_body)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 800.0
	camera.fov = Settings.field_of_view
	camera.set_cull_mask_value(CameraRig.BODY_LAYER, false)
	camera.set_cull_mask_value(CameraRig.VIEW_BODY_LAYER, false)
	add_child(camera)
	camera.make_current()
	_hook_rope = HookRope.new()   # (made up front, hidden until the clip has a rope; headless Godot reports "material is null" errors on a replay without it)
	add_child(_hook_rope)
	_hook_rope.hide_line()
	_frame(0.0)


func _exit_tree() -> void:
	_clear_props()
	if _puppet:
		_puppet.free()   # never in the tree: freed by hand
		_puppet = null


## 0..1 through the clip.
func progress() -> float:
	return clampf((time - clip.start) / maxf(clip.end - clip.start, 0.01), 0.0, 1.0)


## Seconds of the clip left to play, at normal speed.
func time_left() -> float:
	return maxf(clip.end - time, 0.0)


func restart() -> void:
	time = clip.start
	done = false
	_killed = false
	_next = 0
	for child in _fx.get_children():
		_fx.remove_child(child)   # (out at once: the replay makes its rockets again under the same names)
		child.queue_free()
	_wrecks.clear()   # (they were in _fx)
	for g in _ghosts.values():
		(g as Ghost).seen.clear()
		(g as Ghost).animator.respawn()
	_seen.clear()
	_chase_ready = false
	_clear_props()   # (so walls that break in it break again)
	_frame(0.0)


func _process(delta: float) -> void:
	if not manual:
		step(delta)


## Moves the clip on by `delta` seconds (slower round the kill in slow motion).
func step(delta: float) -> void:
	if done:
		return
	if manual:
		for rocket in _fx.get_children():
			if rocket is Projectile:
				(rocket as Projectile)._physics_process(delta)
	var rate := 1.0
	if slow_motion and time >= clip.kill_time - SLOW_FROM and time <= clip.kill_time + SLOW_UNTIL:
		rate = SLOW
	time = minf(time + delta * rate, clip.end)
	_frame(delta)
	if time >= clip.end:
		if loop:
			restart()
		else:
			done = true
			finished.emit()


func _frame(delta: float) -> void:
	_play_props()
	if third_person:
		_play_ghost(clip.killer, delta)
	else:
		_play_killer(delta)
	for id in clip.tracks:
		if id != clip.killer:
			_play_ghost(id, delta)
	_play_wrecks()
	if third_person:
		_chase(delta)
	while _next < _events.size() and _events[_next][0] <= time:
		_play_event(_events[_next][1])
		_next += 1
	if not _killed and time >= clip.kill_time:
		_killed = true
		kill_moment.emit()


# ---------------------------------------------------------------------------
# The killer: their eyes and arms

func _play_killer(delta: float) -> void:
	var track: KillClip.Track = clip.tracks.get(clip.killer)
	if track == null or track.is_empty():
		return
	var f := track.sample(time)
	var weapon := str(f[11])
	if weapon != _weapon:
		_build_arms(weapon, track.color)
	var feet: Vector3 = f[0]
	var yaw := float(f[2])
	var pitch := float(f[3])
	var pose := int(f[4])
	var eye := feet + Vector3(0, float(f[10]), 0)
	var fix := KillClip.aim_fix(_aim_keys, time)   # onto the aim of their shots
	var w := float(fix[0])
	if w > 0.0:
		yaw = lerp_angle(yaw, float(fix[1]), w)
		pitch = lerpf(pitch, float(fix[2]), w)
		if fix[3] != Vector3.INF and (fix[3] as Vector3).distance_to(eye) <= KillClip.AIM_REACH:
			eye = eye.lerp(fix[3], w)
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, _roll(f))), eye)
	# The arms follow what the killer was doing (see ViewModel).
	var p := _puppet
	p.alive = bool(f[8])
	p._anim.flags = int(f[5])   # (what alt fire holds them in: the pistols on their side, see Player.alt_held)
	p.velocity = f[1]
	p.input.yaw = yaw
	p.input.pitch = pitch
	p.input.sprint = Vector2(p.velocity.x, p.velocity.z).length() > 9.0
	p.motor.state = Player.pose_state(pose)
	p.motor.crouched = Player.pose_crouched(pose)
	var right := Vector3.RIGHT.rotated(Vector3.UP, yaw)
	p.motor.wall_normal = -right if int(f[5]) & 1 else right
	p.motor.grapple.attached = bool(f[6])
	p.motor.grapple.anchor = f[7]
	var reloading := int(f[5]) & 4 != 0
	if p.weapon:
		if reloading and not _was_reloading:
			p.weapon.ammo = 0
			p.weapon.start_reload()
		elif not reloading and p.weapon.is_reloading():
			p.weapon.reset()
		p.weapon.update(delta)
	_was_reloading = reloading
	_watch(int(f[5]), weapon, _seen, null)
	# Their footsteps, jumps and landings, as your own.
	_killer_body.global_position = feet
	var a := _killer_anim
	a.state = p.motor.state
	a.crouched = p.motor.crouched
	a.velocity = f[1]
	a.yaw = yaw
	a.pitch = pitch
	a.flags = int(f[5])
	a.grapple_on = bool(f[6])
	a.grapple_anchor = f[7]
	a.alive = p.alive
	a.set_hook_replayed(_hook_look(f))   # (so the body hangs on that rope as it did in the match: RopeSwing)
	if _killer_sounds == null or _killer_sounds.weapon_id != weapon:
		_killer_sounds = PlayerSounds.new(_killer_body, true, weapon)
		_killer_sounds.map = map as MapRoot
	_killer_sounds.update(delta, a, true)
	if _view:
		_view.hang(delta, a, feet)
		_view.update(delta)
	var hand := _view.marker("grapple") if _view else camera.global_position
	var look = _hook_look(f) if p.alive else null
	_killer_sounds.replayed_hook(look)
	_hook_rope = _draw_hook(_hook_rope, self, hand, look)


## For the tests' logs: "<the killer's shots in the clip> <the most the recording was
## off at one (degrees), before the replay put it right>".
func aim_report() -> String:
	var worst := 0.0
	var n := 0
	for key in _aim_keys:
		if float(key[0]) < clip.start or float(key[0]) > clip.end:
			continue
		n += 1
		worst = maxf(worst, clip.aim_miss(key))
	return "%d %.1f" % [n, worst]


## The map's moving parts as the clip has them now.
func _play_props() -> void:
	if clip.props.is_empty():
		return
	var where: Node = map if map != null and is_instance_valid(map) else MapRoot.current
	for key in clip.props:
		var part := MapReplay.find(where, key)
		if part == null:
			continue
		var look := (clip.props[key] as KillClip.PropTrack).at(time)
		if look[0] == null:
			continue
		part.call("replay_show", look[0], look[1], look[2], self)
		if not _shown_props.has(part):
			_shown_props.append(part)


func _clear_props() -> void:
	for part in _shown_props:
		if is_instance_valid(part):
			part.call("replay_clear")
	_shown_props.clear()


## Leaning away from a wall while running along it, as the killer's camera did.
func _roll(f: Array) -> float:
	if Player.pose_state(int(f[4])) != S.WALL_RUN:
		return 0.0
	return deg_to_rad(7.0) * (1.0 if int(f[5]) & 1 else -1.0)


func _build_arms(weapon: String, color: Color) -> void:
	_weapon = weapon
	if _view:
		_view.queue_free()
		_view = null
	if _puppet == null:
		_puppet = Player.new()
		_puppet.peer_id = clip.killer
		_puppet.motor = MovementController.new()
	_puppet.weapon = WeaponState.new(WeaponData.by_id(weapon)) if WeaponData.has(weapon) else null
	_view = ViewModel.new()
	camera.add_child(_view)
	_view.setup(_puppet, color)
	_view.respawn()
	_akimbo_shots = 0


## Third person: the camera behind and above the killer, looking where they look, or
## (when the victim is close by and in the clip) between the killer and the victim.
## It stays on the killer's side of walls.
func _chase(delta: float) -> void:
	var track: KillClip.Track = clip.tracks.get(clip.killer)
	var g: Ghost = _ghosts.get(clip.killer)
	if track == null or track.is_empty() or g == null:
		return
	var f := track.sample(time)
	var yaw := float(f[2])
	var head: Vector3 = f[0] + Vector3(0, 1.6, 0)
	var forward := Vector3.FORWARD.rotated(Vector3.UP, yaw)
	var right := Vector3.RIGHT.rotated(Vector3.UP, yaw)
	var look := head + forward * 6.0
	var victim: Ghost = _ghosts.get(clip.victim)
	var chest := Vector3.INF
	if victim and victim.root.visible:
		chest = victim.root.global_position + Vector3(0, 1.1, 0)
	else:   # fallen: where their remains are
		for w: KillClip.Wreck in _wrecks:
			if w.who == clip.victim and _wrecks[w] != null:
				chest = _wrecks[w].focus()
	if chest != Vector3.INF and chest.distance_to(head) < CHASE_VICTIM:
		look = head.lerp(chest, 0.6)
	var want := head - forward * CHASE_BACK + Vector3.UP * CHASE_UP + right * CHASE_SIDE
	if is_inside_tree():   # stay on this side of a wall
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(head, want))
		if not hit.is_empty():
			want = hit.position + (head - hit.position).normalized() * 0.35
	var k := 1.0 - exp(-CHASE_EASE * delta)
	var kl := 1.0 - exp(-LOOK_EASE * delta)
	if not _chase_ready:
		camera.global_position = want
		_chase_look = look
		_chase_ready = true
	else:
		camera.global_position = camera.global_position.lerp(want, k)
		_chase_look = _chase_look.lerp(look, kl)
	if camera.global_position.distance_to(_chase_look) > 0.05:
		camera.look_at(_chase_look, Vector3.UP)


## Someone fired: their gun's handling sounds (working a pump or bolt) follow.
func _fired(who: int) -> void:
	if who == clip.killer and not third_person:
		if _killer_sounds:
			_killer_sounds.fired()
	elif _ghosts.has(who) and (_ghosts[who] as Ghost).sounds:
		(_ghosts[who] as Ghost).sounds.fired()


# ---------------------------------------------------------------------------
# Everyone else

func _play_ghost(id: int, delta: float) -> void:
	var track: KillClip.Track = clip.tracks[id]
	var t := clip.time_for(id, time)
	if track.is_empty() or t < track.first_time() - 0.5:
		return
	var f := track.sample(t)
	var g: Ghost = _ghosts.get(id)
	if g == null or g.weapon != str(f[11]):
		g = _build_ghost(id, track, str(f[11]))
	g.root.visible = bool(f[9]) and t <= track.last_time() + 1.0
	g.root.global_position = f[0]
	g.visual.transform = Transform3D(Basis(Vector3.UP, float(f[2])), Vector3.ZERO)
	var pose := int(f[4])
	var a := g.anim
	a.state = Player.pose_state(pose)
	a.crouched = Player.pose_crouched(pose)
	a.velocity = f[1]
	a.yaw = float(f[2])
	a.pitch = float(f[3])
	a.flags = int(f[5])
	a.grapple_on = bool(f[6])
	a.grapple_anchor = f[7]
	a.alive = bool(f[8])
	a.set_hook_replayed(_hook_look(f))   # (so the body hangs on that rope as it did in the match: RopeSwing)
	_watch(a.flags, g.weapon, g.seen, g)
	g.animator.update(delta, a, g.visual.global_transform)
	if world_sound:
		if g.sounds == null:
			g.sounds = PlayerSounds.new(g.root, false, g.weapon)
		g.sounds.map = map as MapRoot
		g.sounds.update(delta, a, g.root.visible)
	var look = _hook_look(f) if a.alive and g.root.visible else null
	if world_sound:
		g.sounds.replayed_hook(look)
	g.hook_rope = _draw_hook(g.hook_rope, g.root, g.robot.marker("grapple"), look)


func _build_ghost(id: int, track: KillClip.Track, weapon: String) -> Ghost:
	var old: Ghost = _ghosts.get(id)
	if old:
		old.root.queue_free()
	var g := Ghost.new()
	g.weapon = weapon
	g.root.name = "Ghost_%d" % id
	add_child(g.root)
	g.root.add_child(g.visual)
	g.robot = RobotModel.new().build(track.character, track.color, false, weapon, false, track.paint)
	g.visual.add_child(g.robot)
	g.animator = RobotAnimator.new(g.robot)
	g.sounds = PlayerSounds.new(g.root, false, weapon)
	g.hook_rope = HookRope.new()   # (up front, as the killer's)
	g.root.add_child(g.hook_rope)
	g.hook_rope.hide_line()
	_ghosts[id] = g
	return g


## Remains: from the moment of each death in the clip, the replay's own ragdoll or
## giblets where the recording says, the body they replaced out of sight until it is
## back (respawned). Only deaths the clip shows: a body left lying from before it
## starts (someone's previous death) is not drawn, so the only one that falls is the
## one that falls in the replay.
func _play_wrecks() -> void:
	for w: KillClip.Wreck in clip.wrecks:
		var t := clip.time_for(w.who, time)
		var shown := t >= w.first_time() and t < w.first_time() + Remains.LIFETIME and _gore_shows(w) \
			and w.first_time() >= clip.time_for(w.who, clip.start) \
			and (third_person or w.who != clip.killer)   # (no body of the killer's own in front of their eyes)
		var body: Node3D = _wrecks.get(w)
		if not shown:
			if body:
				body.queue_free()
			_wrecks.erase(w)
			continue
		if not _wrecks.has(w):
			body = _make_wreck(w)
			_wrecks[w] = body
		if body == null:
			continue   # (none could be made: the body stays, playing its death)
		body.call("pose", w.pose_at(t))
		var g: Ghost = _ghosts.get(w.who)
		# Hidden while dead (and just at the death, when its frames may still say alive).
		if g and (not g.anim.alive or t - w.first_time() < 0.2):
			g.root.visible = false


## Remains show as the game would show them now: none with gore off, and giblets only
## with full gore (Settings.gore). Without them the body plays its death instead.
func _gore_shows(w: KillClip.Wreck) -> bool:
	return Settings.gore != "off" and (w.kind != "gibs" or Settings.gore == "full")


## The replay's own ragdoll or giblets for `w`, made from the body it replaces (posed as
## it was at the death), in _fx. Null if none can be made.
func _make_wreck(w: KillClip.Wreck) -> Node3D:
	var g: Ghost = _ghosts.get(w.who)
	var source: RobotModel = g.robot if g and g.weapon == w.weapon else null
	var spare: RobotModel = null   # no body to make them from (not in the clip): a fresh one
	if source == null:
		spare = RobotModel.new().build(w.character, w.color, false, w.weapon if w.weapon != "" else "pistol", false, w.paint)
		_fx.add_child(spare)
		source = spare
	var made: Node3D = null
	if w.kind == "gibs":
		made = Gibs.puppet(source, w.scrap, RobotModel.trim_color(w.color))
	else:
		made = Ragdoll.puppet(w.character, w.color, w.weapon if w.weapon != "" else "pistol", source.skeleton, w.paint)
	if made:
		_fx.add_child(made)
		if made is Ragdoll:
			(made as Ragdoll).model.global_transform = source.global_transform   # (where the body was, so it is not culled)
		var t := clip.time_for(w.who, time)
		made.call("pose", w.pose_at(t))
		if made is Gibs and t - w.first_time() < 0.3:   # (not for pieces already lying there when the clip starts)
			var mid := (made as Gibs).focus()
			(made as Gibs).effects(mid, w.fx, false)
			_sound("heavy_hit", mid, false)
		if DevArgs.sync_log:
			print("KILLCAM WRECK %d %d %s %.2f %.2f" % [Net.my_id(), w.who, w.kind, time - clip.kill_time, w.last_time() - w.first_time()])   # (when, and how much of the fall was recorded)
	if spare:
		for i in spare.mesh.get_surface_override_material_count() if spare.mesh else 0:   # headless Godot grumbles otherwise
			spare.mesh.set_surface_override_material(i, null)
		spare.free()
	return made


## New swings, kicks and wind-ups from the animation flags (see Player._watch_swings).
## `g` is null for the killer (their arms move instead of a body).
func _watch(flags: int, weapon: String, seen: Dictionary, g: Ghost) -> void:
	var melee := weapon != "none" and WeaponData.melee(weapon)
	var swings := RobotAnimInput.swings_of(flags)
	var kicks := RobotAnimInput.kicks_of(flags)
	var flying := RobotAnimInput.flying_of(flags)
	if not seen.has("swings"):
		seen.merge({"swings": swings, "kicks": kicks, "flying": flying, "wind": -1.0})
		return
	if melee and RobotAnimInput.winding_of(flags):
		seen.wind = maxf(float(seen.wind), 0.0) + get_process_delta_time()
		var held := WeaponData.by_id(weapon).charge_of(seen.wind)
		var coming := RobotAnimInput.step_of(flags)   # (which blow of the combo is coming)
		if g:
			g.animator.wind(held, coming)
		elif _view:
			_view.wind(held, coming)
	if swings != int(seen.swings):
		seen.swings = swings
		if melee:
			var power := WeaponData.by_id(weapon).charge_of(maxf(float(seen.wind), 0.0))
			var step := RobotAnimInput.step_of(flags)   # (which blow of the combo it is: a jab, a spinning kick...)
			if g:
				g.animator.swing(power, step)
			elif _view:
				_view.swing(power, step)
		seen.wind = -1.0
	if g and flying != bool(seen.flying):
		g.animator.set_flying_kick(flying)
	seen.flying = flying
	if kicks != int(seen.kicks):
		seen.kicks = kicks
		if g:
			g.animator.kick(flying)
		if world_sound or g == null:
			_sound("kick" if not flying else "flying_kick", camera.global_position if g == null else g.root.global_position, g == null)


# ---------------------------------------------------------------------------
# Shots, rockets, blows

func _play_event(e: Dictionary) -> void:
	var who := int(e.who)
	var mine := who == clip.killer
	match str(e.kind):
		"shot":
			var weapon := str(e.weapon)
			var data := WeaponData.by_id(weapon)
			var muzzle: Vector3 = e.muzzle
			var left := false
			if mine and _view:
				left = data.is_akimbo() and _akimbo_shots % 2 == 1
				_akimbo_shots += 1
				_view.fire(left)
				muzzle = _view.marker(data.muzzle_bone_left if left else data.muzzle_bone)
			elif _ghosts.has(who):
				var g: Ghost = _ghosts[who]
				left = data.is_akimbo() and g.akimbo_shots % 2 == 1
				g.akimbo_shots += 1
				g.animator.fire(left)
				muzzle = g.robot.marker(data.muzzle_bone_left if left else data.muzzle_bone)
			ShotFx.spawn(_fx, muzzle, e.ends, e.hits, weapon)
			_fired(who)
			if mine:
				Sound.gun_fire(weapon, muzzle, true)
			elif world_sound:
				Sound.gun_fire(weapon, muzzle, false)
		"projectile":
			var data := WeaponData.by_id(str(e.weapon))
			var muzzle := Vector3.INF
			if mine and _view:
				_view.fire()
				muzzle = _view.marker(data.muzzle_bone)
			elif _ghosts.has(who):
				(_ghosts[who] as Ghost).animator.fire()
				muzzle = (_ghosts[who] as Ghost).robot.marker(data.muzzle_bone)
			var track: KillClip.Track = clip.tracks.get(who)
			var color := RobotModel.trim_color(track.color if track else Color.WHITE)
			var rocket := Projectile.make(int(e.id), data, e.origin, e.direction, muzzle, color, bool(e.get("sticky", false)))
			rocket.set_physics_process(not manual)   # (stepped with the clip instead)
			_fx.add_child(rocket)
			if mine:
				Sound.gun_fire(data.id, camera.global_position, true)
			elif world_sound:
				Sound.gun_fire(data.id, e.origin, false)
		"boom":
			var rocket := _fx.get_node_or_null("Projectile_%d" % int(e.id))
			if rocket:
				rocket.queue_free()
			ShotFx.landed(_fx, e.at, WeaponData.by_id(str(e.weapon)))
			_sound(ShotFx.landed_sound(WeaponData.by_id(str(e.weapon))), e.at, false)
		"stick":
			_play_stick(e)
		"armed":
			var sticky := _fx.get_node_or_null("Projectile_%d" % int(e.id)) as Projectile
			if sticky and not sticky.armed:
				sticky.arm()
				_sound("ui_tick", sticky.global_position, false)
		"gone":
			var sticky := _fx.get_node_or_null("Projectile_%d" % int(e.id))
			if sticky:
				sticky.queue_free()
		"melee":
			if mine and _view and str(e.weapon) not in ["kick", "flying_kick"] and not (e.points as PackedVector3Array).is_empty():
				_view.hit_stop()


## A sticky grenade stuck (or is still stuck: Killcam records it again every second, so
## one stuck before the clip began is there from its start). It rides the stand-in body
## of the player it is on, or the part of the map it is on.
func _play_stick(e: Dictionary) -> void:
	var how: Dictionary = e.how
	var sticky := _fx.get_node_or_null("Projectile_%d" % int(e.id)) as Projectile
	var fresh := sticky == null or not sticky.stuck
	if sticky == null:
		var track: KillClip.Track = clip.tracks.get(int(e.who))
		var color := RobotModel.trim_color(track.color if track else Color.WHITE)
		sticky = Projectile.make(int(e.id), WeaponData.by_id(str(how.get("weapon", ""))), how.at, Vector3.DOWN, Vector3.INF, color, true)
		sticky.set_physics_process(not manual)
		_fx.add_child(sticky)
	if fresh:
		var on := int(how.get("on", 0))
		var ride: Node3D = null
		if on > 0:
			ride = (_ghosts[on] as Ghost).visual if _ghosts.has(on) else (_killer_body if on == clip.killer else null)
		else:
			ride = Projectile.frame_in(map if map != null and is_instance_valid(map) else MapRoot.current, how)
		sticky.stick(how, ride)
		if clip.event_time(e) >= clip.start:   # (not for one stuck before the clip began)
			_sound("grenade_in", sticky.global_position, false)
	if bool(e.get("armed", false)) and not sticky.armed:
		sticky.arm()


func _sound(sound: String, at: Vector3, own: bool) -> void:
	if own or not world_sound:
		Sound.play(sound, -2.0 if own else -8.0, 0.05)
	else:
		Sound.play_at(sound, at, "fire", 0.0, 0.05)


# ---------------------------------------------------------------------------
# Grapple ropes (drawn like Player's, with HookRope)

## The grappling hook's rope in frame `f`, as it was drawn in the match (see
## Player.shown_state): [hook, slack, seconds since the shot, seconds since it pulled
## tight], or null for none.
static func _hook_look(f: Array):
	return f[12] if f.size() > 12 else null


## Draws that rope (HookRope, the same code the match drew it with), making `rope`
## under `holder` the first time one is needed. Returns the rope.
func _draw_hook(rope: HookRope, holder: Node, hand: Vector3, look) -> HookRope:
	if look == null:
		if rope:
			rope.hide_line()
		return rope
	if rope == null:
		rope = HookRope.new()
		holder.add_child(rope)
	rope.show_line(hand, look[0], float(look[1]), float(look[2]), float(look[3]))
	return rope
