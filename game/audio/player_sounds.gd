class_name PlayerSounds
extends RefCounted
## The sounds one player's body and gun make: footsteps, jumps, landings, slides,
## wall runs, the grapple, reload steps and working the pump or bolt.
##
## It reads the same RobotAnimInput the animation does, so it works the same way for
## you, for bots and for other players (whose movement arrives in snapshots): it
## listens for changes (started a slide, landed, the reload began) rather than being
## told. Your own sounds play in your head; everyone else's are placed on their body.
## A killcam's replayed players (see KillcamView) use it too: `player` is then just
## the body's node, and `map` the replay's copy of the map.

const S := MovementController.State

var player: Node3D   ## the body (a Player, or a killcam's replayed body)
var map: MapRoot     ## where to look up what is underfoot; null: the match's map
var own := false          ## your own player: sounds in your head, not placed in the world
var weapon_id := "pistol"

var _started := false
var _state := 0
var _crouched := false
var _wall_jumps := 0
var _replay_stage := HookLine.OFF   # a killcam's replayed hook, as replayed_hook last saw it
var _alive := true
var _fall := 0.0             # fastest downward speed since leaving the ground
var _stride := 0.0           # metres walked since the last footstep
var _reloading := false
var _reload_t := -1.0
var _reload_next := 0
var _fire_t := -1.0
var _end_t := -1.0           # into the flourish that ends a shell-at-a-time reload (SfxList.RELOAD_END_STEPS)
var _end_next := 0
var _since_shot := 99.0
var _fire_next := 0
var _quiet := 0.0              # seconds of silence left (just spawned: no landing thud)
var _wind: Node               # a glide's wind: a looping player of its own (on the body, or in your head for yours)
var _wind_on := 0.0           # how far its wind is faded in, 0..1
var _glide_t := 0.0           # seconds into the glide under way (or the one just let go)
var _hum: Node                # the air cannon charging: a looping hum that rises (see charging)


func _init(p: Node3D, is_own: bool, gun: String) -> void:
	player = p
	own = is_own
	weapon_id = gun


func _play(sound: String, kind: String = "move", volume_db: float = 0.0, jitter: float = 0.04) -> Node:
	if own:
		return Sound.play(sound, volume_db, jitter)
	return Sound.play_at(sound, player.global_position + Vector3(0, 0.6, 0), kind, volume_db, jitter)


## Gun handling sounds come from the gun, a little quieter for other players.
func _play_gun(sound: String) -> void:
	if own:
		Sound.play(sound, 0.0, 0.03)
	else:
		Sound.play_at(sound, player.global_position + Vector3(0, 1.3, 0), "gun", 2.0, 0.03)


## Done with: lets go of the glide's own player (the body is getting a new PlayerSounds).
func free_voices() -> void:
	if is_instance_valid(_wind):
		_wind.queue_free()
	_wind = null
	if is_instance_valid(_hum):
		_hum.queue_free()
	_hum = null


## The air cannon charging, `amount` 0..1 (below 0: it is not): a hum that climbs in
## pitch and loudness with the charge and stops the moment it is let go. It has a
## looping player of its own, made the first time it is needed (as the glide's wind).
func charging(amount: float) -> void:
	if amount < 0.0:
		if _hum and _hum.playing:
			_hum.stop()
		return
	if _hum == null:
		if Sound.silent or not is_instance_valid(player) or not player.is_inside_tree():
			return
		var stream: AudioStream = Sound.stream("charge_hum")
		if stream == null:
			return
		stream = stream.duplicate()
		if stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
		if own:
			_hum = AudioStreamPlayer.new()
		else:
			var p3 := AudioStreamPlayer3D.new()
			var r: Array = Sound.RANGE.move   # (heard a fair way off: a warning)
			p3.unit_size = r[0]
			p3.max_distance = r[1]
			p3.position = Vector3(0, 1.3, 0)
			_hum = p3
		_hum.stream = stream
		_hum.bus = Sound.BUS_SFX
		player.add_child(_hum)
	_hum.pitch_scale = lerpf(0.55, 1.7, amount)
	_hum.volume_db = float(SfxList.VOLUME.get("charge_hum", -11.0)) + lerpf(-6.0, 4.0, amount) + (0.0 if own else 2.0)
	if not _hum.playing:
		_hum.play()


## This player's gun just fired.
func fired() -> void:
	_since_shot = 0.0
	_end_t = -1.0
	if SfxList.FIRE_STEPS.has(WeaponData.look_of(weapon_id)):
		_fire_t = 0.0
		_fire_next = 0


## Came back to life somewhere new: no landing or step sounds from the jump there.
func respawned() -> void:
	_started = false
	_quiet = 0.3
	if own and weapon_id != "none":
		Sound.play("equip_" + weapon_id)


## A mobility tool found nothing in range (the grapple's whoosh of a miss).
func grapple_missed() -> void:
	_play("grapple_miss")


## The grappling hook (see HookLine's stages): its hook has gone from doing `was` to
## doing `now`, at `at`. The launcher fires as the hook leaves; the hook clacks where it
## bites; the rope thrums as it pulls tight; let go, it reels back (with nothing
## caught, the whoosh of a miss).
func hook_stage(was: int, now: int, at: Vector3) -> void:
	if not _alive:
		return
	match now:
		HookLine.FLYING:
			_play("grapple_fire")
		HookLine.BITING:
			_hook_bite(at)
		HookLine.TAUT:
			if was == HookLine.FLYING or was == HookLine.OFF:
				_hook_bite(at)   # (bitten and tight between two frames)
			_play("grapple_taut")
		HookLine.RETRACT:
			_play("grapple_miss" if was == HookLine.FLYING else "grapple_release", "move", -3.0 if was == HookLine.FLYING else 0.0)


## A killcam's replayed hook (Player.shown_state: [hook, slack, seconds since the
## shot, seconds since it pulled tight], or null): the same sounds as hook_stage, for
## as much of the stage as the recording keeps (out, tight, gone).
func replayed_hook(look) -> void:
	var now := HookLine.OFF if look == null else (HookLine.TAUT if float(look[3]) >= 0.0 else HookLine.FLYING)
	if now == _replay_stage:
		return
	var was := _replay_stage
	_replay_stage = now
	if now == HookLine.OFF:
		now = HookLine.RETRACT   # (gone: it was let go)
	hook_stage(was, now, look[0] if look != null else player.global_position)


func _hook_bite(at: Vector3) -> void:
	if own:
		Sound.play("grapple_attach", 0.0, 0.05)
	else:
		Sound.play_at("grapple_attach", at, "move", 0.0, 0.05)


## Called every frame with what the body is doing. `shown`: false while another
## player is hidden (waiting to reappear after a respawn).
func update(delta: float, a: RobotAnimInput, shown: bool) -> void:
	var alive := a.alive and shown
	if not _started or not alive or not _alive:
		_reset(a)
		_alive = alive
		_started = true
		return
	_quiet = maxf(_quiet - delta, 0.0)
	var speed := Vector2(a.velocity.x, a.velocity.z).length()
	if _quiet > 0.0:
		_reset_movement(a)   # just spawned: settle without sounds
	else:
		_movement(a, speed, delta)
	_gun(a, delta)


func _reset(a: RobotAnimInput) -> void:
	_reset_movement(a)
	_reloading = a.reloading() and a.alive
	_reload_t = -1.0
	_fire_t = -1.0


func _reset_movement(a: RobotAnimInput) -> void:
	_wind_on = 0.0
	if _wind and _wind.playing:
		_wind.stop()
	_state = a.state
	_crouched = a.crouched
	_wall_jumps = a.wall_jumps()
	_fall = 0.0
	_stride = 0.0


func _movement(a: RobotAnimInput, speed: float, delta: float) -> void:
	var state: int = a.state
	var grounded_states := [S.GROUND, S.CROUCH, S.SLIDE, S.ROLL, S.BELLY_SLIDE]
	var was_air: bool = not (_state in grounded_states) and _state not in [S.MANTLE, S.WALL_RUN, S.WALL_SIT]
	if state == S.GLIDE and _state != S.GLIDE:
		_fall = 0.0   # a glide catches the fall: the landing after it is only as hard as what comes after
		_glide_t = 0.0
	if state in [S.AIR, S.DIVE, S.FLIP, S.GRAPPLE, S.GLIDE]:
		_fall = minf(_fall, a.velocity.y)   # (a long glide weakens into a real fall)
	if state == S.GLIDE:
		_glide_t += delta
	_glide_wind(state == S.GLIDE, a.velocity.length(), delta)

	if state != _state:
		match state:
			S.SLIDE: _play("slide")
			S.BELLY_SLIDE: _play("belly_slide", "move", 0.0 if was_air else -3.0)
			S.ROLL: _play("roll")
			S.DIVE: _play("dive")
			S.FLIP: _play("flip")
			S.WALL_RUN: _play("wall_run")
			S.MANTLE: _play("vault" if a.vaulting() else "ledge_climb")
			S.AIR:
				if _state in grounded_states and a.velocity.y > 2.5:
					_play("jump")
				elif _state == S.GLIDE and _glide_t >= RobotAnimator.GLIDE_FLIP_AFTER:
					var whoosh := _play("flip", "move", -2.0, 0.0)   # let go of a glide: the backflip out of it (see RobotAnimator)
					if whoosh:
						whoosh.set("pitch_scale", 0.62)   # (a longer, lower whoosh: it is one long flip)
		# Landing (a slide, roll or belly slide out of the air brings its own sound).
		if was_air and state in [S.GROUND, S.CROUCH]:
			_land()
		if state in grounded_states or state == S.WALL_RUN or state == S.WALL_SIT:
			_fall = 0.0
	if a.wall_jumps() != _wall_jumps:
		_play("wall_jump")
	if a.crouched != _crouched and state in [S.GROUND, S.CROUCH]:
		_play("crouch" if a.crouched else "stand")
	_steps(a, state, speed, delta)
	_state = state
	_crouched = a.crouched
	_wall_jumps = a.wall_jumps()


## A glide's wind: loops for as long as the glide lasts, higher and louder the faster
## you are going, and fades out quickly when it ends. It has a player of its own (not
## one of Sound's shared ones), made the first time it is needed.
func _glide_wind(gliding: bool, speed: float, delta: float) -> void:
	_wind_on = move_toward(_wind_on, 1.0 if gliding else 0.0, delta * (10.0 if gliding else 6.0))
	if _wind_on <= 0.0:
		if _wind and _wind.playing:
			_wind.stop()
		return
	if _wind == null:
		if Sound.silent or not is_instance_valid(player) or not player.is_inside_tree():
			return
		var stream: AudioStream = Sound.stream("glide")
		if stream == null:
			return
		stream = stream.duplicate()
		if stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
		if own:
			_wind = AudioStreamPlayer.new()
		else:
			var p3 := AudioStreamPlayer3D.new()
			var r: Array = Sound.RANGE.move
			p3.unit_size = r[0]
			p3.max_distance = r[1]
			p3.position = Vector3(0, 0.9, 0)
			_wind = p3
		_wind.stream = stream
		_wind.bus = Sound.BUS_SFX
		player.add_child(_wind)
	var fast := clampf(speed / 25.0, 0.0, 1.0)
	_wind.pitch_scale = lerpf(0.85, 1.4, fast)
	_wind.volume_db = float(SfxList.VOLUME.get("glide", -10.0)) + lerpf(-6.0, 3.0, fast) + linear_to_db(maxf(_wind_on, 0.001))
	if not _wind.playing:
		_wind.play()


func _land() -> void:
	var v := -_fall
	if v > 15.0:
		_play("land_hard", "body")
	elif v > 4.0:
		_play("land", "move", lerpf(-6.0, 0.0, clampf((v - 4.0) / 8.0, 0.0, 1.0)))
	_stride = 0.0


## Robot footsteps: one per stride, longer strides at speed. Quieter crouched,
## lighter and quicker on a wall, a drag of metal when crawling.
func _steps(a: RobotAnimInput, state: int, speed: float, delta: float) -> void:
	var stride := 0.0
	var sound := "step"
	var vol := 0.0
	match state:
		S.GROUND:
			if speed > 1.0:
				stride = 1.25 + speed * 0.1
				vol = lerpf(-5.0, 1.5, clampf((speed - 1.0) / 10.0, 0.0, 1.0))
		S.CROUCH:
			if speed > 0.8:
				stride = 1.0
				vol = -8.0
		S.WALL_RUN:
			stride = 1.9
			vol = -2.0
		S.BELLY_SLIDE:
			if speed > 0.4 and speed < 2.6:   # crawling
				stride = 0.75
				sound = "crawl"
	if stride <= 0.0:
		_stride = 0.9   # standing still: the first step comes soon after you set off
		return
	_stride += speed * delta
	if _stride >= stride:
		_stride = 0.0
		# What you are standing on changes the step (see BlockMaterials). A wall run
		# keeps the plain step: the wall is beside you, not under you.
		var pitch := 1.0
		if state != S.WALL_RUN:
			var info := BlockMaterials.info(surface())
			if sound == "step":
				sound = info.step
			pitch = info.step_pitch
			vol += info.step_db
		var p: Node
		if own:
			p = Sound.play(sound, vol, 0.07)
		else:
			p = Sound.play_at(sound, player.global_position, "step", vol, 0.07)
		if p:
			p.pitch_scale *= pitch


## What this player is standing on (a BlockMaterials name).
func surface() -> String:
	var on := map if map and is_instance_valid(map) else MapRoot.current
	if on == null or not is_instance_valid(on):
		return BlockMaterials.DEFAULT
	return on.material_at(player.global_position)


func _gun(a: RobotAnimInput, delta: float) -> void:
	var reloading := a.reloading()
	if reloading and not _reloading:
		_reload_t = 0.0
		_reload_next = 0
		_fire_t = -1.0   # the reload takes over from the pump or bolt
	elif not reloading:
		if _reloading and _since_shot > 0.2 and SfxList.RELOAD_END_STEPS.has(WeaponData.look_of(weapon_id)):
			_end_t = 0.0   # full, and not stopped by a shot: the gun is racked with a flourish
			_end_next = 0
		_reload_t = -1.0
	_since_shot += delta
	if _end_t >= 0.0:
		var ends: Array = SfxList.RELOAD_END_STEPS.get(WeaponData.look_of(weapon_id), [])
		_end_t += delta
		while _end_next < ends.size() and _end_t >= ends[_end_next][0]:
			_play_gun(ends[_end_next][1])
			_end_next += 1
		if _end_next >= ends.size() or reloading:
			_end_t = -1.0
	_reloading = reloading
	if _reload_t >= 0.0:
		var steps: Array = SfxList.RELOAD_STEPS.get(WeaponData.look_of(weapon_id), [])
		_reload_t += delta
		while _reload_next < steps.size() and _reload_t >= steps[_reload_next][0]:
			_play_gun(steps[_reload_next][1])
			_reload_next += 1
		if WeaponData.has(weapon_id) and WeaponData.by_id(weapon_id).reload_per_round and _reload_next >= steps.size():
			var shell := WeaponData.by_id(weapon_id).reload_time
			if _reload_t >= shell:   # next shell
				_reload_t -= shell
				_reload_next = 0
	if _fire_t >= 0.0:
		var steps: Array = SfxList.FIRE_STEPS.get(WeaponData.look_of(weapon_id), [])
		_fire_t += delta
		while _fire_next < steps.size() and _fire_t >= steps[_fire_next][0]:
			_play_gun(steps[_fire_next][1])
			_fire_next += 1
		if _fire_next >= steps.size():
			_fire_t = -1.0
