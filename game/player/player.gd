class_name Player
extends CharacterBody3D
## A player in the arena. The same scene is used for:
##  - the local player: reads input, runs movement, fires, sends snapshots;
##  - remote players: shown from snapshots, smoothed by SnapshotBuffer.
##  - bots: simulated on the host like a local player, but input comes from a
##    BotBrain instead of the keyboard, and there is no camera.

const COIL_ROLL := 0.075  ## radians the view tips for each radian the chest is coiled in a melee swing
const SEND_RATE := 40.0  ## snapshots per second (40 rather than 30 keeps fast grapple swings accurate on lossy networks)
const CAPSULE_RADIUS := 0.4
const CAPSULE_HEIGHT := 1.8
const VIEWMODEL_LAYER := 3   ## render layer for the first-person gun
const CROUCH_HEIGHT := 1.1
const PRONE_HEIGHT := 0.8    ## lying on your front (belly slide)
const TUCK_LIFT := CAPSULE_HEIGHT - CROUCH_HEIGHT
const OVERDUE_RESPAWN := 1.0  ## seconds a living remote player may stay hidden waiting for their respawn snapshot
const SNAPSHOT_SIZE := 12     ## floats in a snapshot (see make_snapshot), before a grappling hook shot on the end

var _dev_group := -1   # --swap-on-death: the weapon group to pick (see dev_swap_after_death)
var peer_id := 1
var is_local := false   ## simulated on this machine (you, or a bot when hosting)
var is_bot := false
var brain: RefCounted   ## BotBrain in a fight, RaceBrain in a race (and for --autopilot)
var alive := true
var racing := false     ## this match is a race: no gun, no bumping into each other

var input := PlayerInput.new()
var motor: MovementController
var rig: CameraRig
var visual: Node3D
var buffer := SnapshotBuffer.new()   ## remote: received states; local: own recent states (for the host's rewind)
var weapon: WeaponState
## Time (on this player's clock) at which we are currently drawing them. Sent with shots.
var last_render_time := -1.0

var _send_timer := 0.0
var _scripted_time := 0.0
var _remote_state := 0
var _teleport_count := 0          # local: bumped on every respawn; remote: last seen value
var _awaiting_respawn := false    # remote: hidden until the first post-respawn snapshot
## Lives are numbered by the host (the spawn index of Match._respawned; 0 before the
## first respawn) and the number travels in snapshots, so a copy can tell which life a
## snapshot is from whichever of the two (snapshot or respawn) gets here first.
var _life := 0                    # local: this life's number
var _seen_life := -1              # remote: the life of the newest snapshot (-1: none yet)
var _awaited_life := -1           # remote: the life we were told they are back in
var _dead_life := -1              # remote: the newest life we knew of when they died
var _newest_snap := -INF          # remote: sender time of the newest snapshot (older ones that arrive late are dropped)
var _newest_snap_at := 0.0        # remote: when it got here (our clock)
var _hidden_for := 0.0            # remote: seconds hidden waiting for the respawn snapshot (see _check_overdue_respawn)
var _hidden_snaps := 0            # remote: snapshots that arrived in that time
var robot: RobotModel             ## the body everyone sees
var character := ""               ## the robot it was built as (an id from Characters)
var _ammo := {}                   # local, Deathmatch: weapon id -> rounds left in the ones you are not holding
var _move_bonus := 1.0            # the speed bonus of the weapon in hand, applied to motor.tuning
var _pending_gun := ""            # Deathmatch: the weapon to hold once back from the dead
var animator: RobotAnimator
var view: ViewModel               ## first-person arms and gun (your own player only)
var sounds: PlayerSounds          ## footsteps, jumps, reloads... (see game/audio/)
var _anim := RobotAnimInput.new()
var _corpse_drop := 0.0           # a body shot in mid-air falls to the ground (visual only)
var _corpse_fall := 0.0
var _corpse_room := 0.0
var _in_remains := false          # the body is hidden because remains took its place (see hide_for_remains)
var _logged_anim := ""            # --sync-log: the last animation we printed
var _fell_reported := false
var _fire_buffer := 0.0           # a click slightly too early still fires when the gun is ready
var _hook_rope: HookRope          # the grappling hook's rope and hook (made when first needed; see Grapple)
var _hook_line: HookLine          # remote: their latest grappling hook shot, rebuilt from their snapshots
var _hook_old: HookLine           # remote: the shot before it (it may still be whipping back when the next is fired)
var _hook_look: Array = []        # what is drawn of the hook this frame (HookLine.look; [] nothing)
var _hook_stage := HookLine.OFF   # ...and the stage that was in last frame (its sounds go by the changes)
var _hook_guard := [0, 0.0]       # remote: [shot, time] the flight was last checked against the map (see _guard_hook)
var _hook_logged := [0, 0]        # --sync-log: [shot, moments of it already printed]
var _rope_seen := false           # remote, --sync-log: their rope was tight last frame
var _roll := 0.0                  # local: camera tilt while wall-running
var _shape: CollisionShape3D
var _height := CAPSULE_HEIGHT     # remote: collision shape height for the pose we draw
var _visual_yaw := 0.0
# Another player: where they were at the moment we draw them at, before MapRoot.carried
# moved them along with an island under way (the killcam records this, beside where
# the island was at that same moment; INF until the first snapshot).
var _uncarried := Vector3.INF
var _flying := false              # local: the debug menu's noclip is on
var _swings := 0                  # local: melee swings so far (travels in snapshots, wrapping at 4)
var _seen_swings := -1            # the swing count last shown (starts the swing animation and sound)
var _strike_left := -1.0          # local: seconds until the current swing's blow lands
var _charge := -1.0               # local: seconds the swing button has been held (winding up), or -1
var _swing_power := 0.0           # local: how wound up the swing in flight is, 0..1
var _swing_side := 0              # which tap this wind-up or swing is: 0 from the right, 1 from the left (they take turns)
var _seen_side := 1               # the side of the last swing shown
var _since_swing := 9.0           # seconds since the last swing shown was let go
var _shown_power := 0.0           # how wound up the last swing shown was (its hit effects go by it)
var _slam_cool := 0.0             # local: seconds until you can ground slam again (see GroundSlam)
var _slamming := false            # local: in a ground slam, on the way down
var _slam_power := 0.0            # local: how wound up that slam is, 0..1
var _seen_wind := -1.0            # seconds this player has been seen winding up (drives the wind-up pose), or -1
var _blast_held := -1.0           # local, the air cannon: seconds the trigger has been held (charging), or -1
var _blast_power := 0.0           # local: how charged the blast just let go is, 0..1
var _seen_charge := -1.0          # seconds this player's air cannon has been seen charging, or -1
var _charge_glow: MeshInstance3D  # the air cannon's glow at the muzzle while it charges (made when first needed)
var _slam_wait := 0.0             # local: a crash just hurt; the next can't for a moment
var _trail: SwingTrail            # the glowing smear behind a blade mid-blow (melee only)
var _glide_fx: GlideFx            # the wind trail and speed streaks of a glide
var _punch := Vector2.ZERO        # own view: a quick jolt of the camera (yaw, pitch) from your own blows
var _punch_roll := 0.0
var _coil_roll := 0.0             # own view: tipped by a melee wind-up
var _kicks := 0                   # local: kicks so far (travels in snapshots, wrapping at 4)
var _seen_kicks := -1
var _kick_cool := 0.0             # local: seconds until you can kick again
var _kick_strike := -1.0          # local: seconds until the kick lands
var _fly_kick := 0.0              # local: seconds left of a flying kick (0 = not flying)
var _fly_target: Player           # local: who the flying kick is going for
var _seen_flying := false
var _seen_boosts := -1
var _tether_id := 0               # local: the player your hook is on, as told to the host
var _tug_by := 0                  # local: someone has you hooked and is reeling you in
var _tug_left := 0.0
var _tug_fresh := false
var _flame: Node3D                # rocket-boot flames under the feet
var _flame_t := 0.0
var _burst_left := 0              # local: rounds of a burst still to fire
var _akimbo_shots := 0            # akimbo: shots so far (yours, or seen); odd ones leave the left gun
var _akimbo_left := false         # akimbo: the last shot came from the left gun
var _burst_wait := 0.0            # local: seconds until the next round of the burst
## The tool on the mobility button (an id from Mobility): the grapple or blink. A
## race always has the grapple.
var mobility := Mobility.GRAPPLE
var blink: Blink                  # local, with blink
## Local: everyone's jetpack (hold Space in mid-air: see MovementController.space_jet).
## None in a race.
var jetpack: Jetpack
var _seen_jet := false            # the jetpack was firing last frame (its sound and flame)


func _init() -> void:
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(46.0)
	floor_stop_on_slope = true
	collision_layer = 1 << 1   # layer 2: players
	collision_mask = 1 | (1 << 1)


func setup(id: int, local: bool, bot: bool = false) -> void:
	peer_id = id
	is_local = local
	is_bot = bot
	name = "Player_%d" % id
	set_multiplayer_authority(id)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	shape.shape = capsule
	shape.position.y = CAPSULE_HEIGHT * 0.5
	add_child(shape)
	_shape = shape

	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	character = Net.player_character(id)
	if DevArgs.sync_log:   # for tests/check_anim.py: which robot each copy shows for each player
		if local:
			print("CHAR SELF %d %s" % [id, character])
		else:
			print("CHAR SEEN %d %d %s" % [Net.my_id(), id, character])
	racing = Race.active
	if racing:
		collision_mask = 1   # racers pass through each other (a tunnel is never blocked)
	var gun := Net.player_weapon(id) if not racing else "none"
	if DevArgs.sync_log:   # which gun each copy shows each player holding
		print("GUN %s %d %d %s" % ["SELF" if local else "SEEN", Net.my_id(), id, gun])
	robot = RobotModel.new().build(character, Net.player_color(id), false, gun, false, Teams.paint_for(id))
	visual.add_child(robot)
	animator = RobotAnimator.new(robot)
	sounds = PlayerSounds.new(self, local and not bot, gun)
	if sounds.own and not racing and gun != "none":
		Sound.play("equip_" + gun)   # bringing your gun up as the match starts

	if is_bot:
		motor = MovementController.new(MovementTuning.for_variant(LobbySettings.movement()))   # (the host's pick: everyone moves the same way)
		weapon = _make_weapon(Net.player_weapon(id))
		_apply_move_bonus()
		if racing:
			brain = RaceBrain.new(self, Net.players[id].get("difficulty", 1))
		else:
			brain = BotBrain.new(self, Net.players[id].get("difficulty", 1))
	elif is_local:
		motor = MovementController.new(MovementTuning.for_variant(LobbySettings.movement()))   # (the host's pick: everyone moves the same way)
		weapon = _make_weapon(Net.player_weapon(id))
		_apply_move_bonus()
		if racing and DevArgs.autopilot:
			brain = RaceBrain.new(self, DevArgs.bot_level)
		rig = CameraRig.new()
		add_child(rig)
		rig.setup(self)
		robot.set_layer(CameraRig.BODY_LAYER)
		robot.add_view_mesh(CameraRig.VIEW_BODY_LAYER)
		view = ViewModel.new()
		rig.camera.add_child(view)
		view.setup(self, Net.player_color(id))
		view.visible = not racing   # no gun to hold in a race: you see your body, not arms
	_build_flame()
	if motor:
		motor.grapple.hook_players = not racing
		jetpack = null if racing else Jetpack.new()   # (a race is the grapple's: no jetpack)
	set_mobility(Net.player_mobility(id))
	if WeaponData.melee(robot.weapon):
		_trail = SwingTrail.new().setup(RobotModel.trim_color(Net.player_color(id)))
		add_child(_trail)
	_glide_fx = GlideFx.new().setup(RobotModel.trim_color(Net.player_color(id)))
	add_child(_glide_fx)
	if rig:
		_glide_fx.set_trail_layers(1 << (CameraRig.BODY_LAYER - 1))   # (your own: not in your first-person view)
	Match.melee_landed.connect(_on_melee_landed)
	Match.ground_slammed.connect(_on_ground_slammed)


# ---------------------------------------------------------------------------
# Per-frame

func _physics_process(delta: float) -> void:
	if not is_local:
		return
	if is_bot:
		if Cheats.bots_frozen():
			_hold_still()
		else:
			brain.update(delta)
	elif brain:
		brain.update(delta)   # --autopilot
	elif DevArgs.scripted_input:
		_scripted_input(delta)
	else:
		read_local_input()
	if racing and Race.frozen():
		_hold_still()   # on the start line: you can look round, not move
		input.clear_edges()
	if alive:
		_set_crosshair_ray()
		var was_on := motor.grapple.attached
		# Blink takes the mobility button: the grapple never sees it.
		var roped := Mobility.is_grapple(mobility)
		var mobility_pressed := input.grapple_pressed and not roped
		if not roped:
			input.grapple = false
			input.grapple_pressed = false
		var fly := Cheats.flying() and not is_bot
		if fly != _flying:
			_flying = fly
			motor.reset()
			velocity = Vector3.ZERO
		if fly:
			_fly(delta)
		else:
			_update_tug(delta)
			_steer_flying_kick(delta)
			if _fly_kick > 0.0:
				input.glide = false   # mid flying kick: you are already going somewhere
				input.glide_pressed = false
			var boosts := motor.boosts
			if jetpack:
				var jet_was_on := jetpack.on
				# Space held in mid-air flies it (MovementController.space_jet says when).
				# (A ground slam is committed: the jetpack does not fire on the way down.)
				velocity = jetpack.step(velocity, motor.space_jet and motor.state != MovementController.State.SLAM, is_on_floor(), motor._wish_dir(input), delta)
				if jetpack.on and is_on_floor():
					motor.warped = true   # lift off: no floor snap or ground friction this step
				if jetpack.on and not jet_was_on and DevArgs.sync_log:
					print("JETPACK %d" % peer_id)
			motor.has_jetpack = jetpack != null
			motor.hang = _charge >= 0.0 and not (jetpack and jetpack.on)   # winding a melee swing up slows a fall (the jetpack takes over from it)
			motor.step(self, input, delta)
			if not racing and is_on_floor():
				# A floor that turns under you (an island swinging round, see MapIsland)
				# turns you with it, so what you were looking at on it stays in view.
				var turning := get_platform_angular_velocity().y
				if turning != 0.0:
					input.yaw += turning * delta
			_watch_ground_slam()
			if motor.boosts != boosts and DevArgs.sync_log:
				print("BOOST %d" % peer_id)
			_check_slam(delta)
			_update_mobility(delta, mobility_pressed and motor.state != MovementController.State.SLAM)   # (no blinking out of a slam)
		_report_tether()
		if Cheats.cooldowns_off() and not is_bot:
			motor.clear_cooldowns()
		if DevArgs.sync_log and motor.grapple.attached != was_on:
			print("ROPE SELF %d %s" % [peer_id, "on" if motor.grapple.attached else "off"])
		if DevArgs.sync_log and Mobility.is_grapple(mobility):
			_log_own_hook(motor.grapple)
		_visual_yaw = input.yaw
		if not racing:
			if weapon:
				_update_weapon(delta)   # (Deathmatch, empty hands: only the kick)
			_update_kick(delta)
	else:
		velocity = Vector3.ZERO
		_report_tether()
	input.clear_edges()
	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer += 1.0 / SEND_RATE
		var now := Net.now()
		if not is_bot:
			Net.send_snapshot(now, make_snapshot())
		else:
			Net.send_bot_snapshot(peer_id, now, make_snapshot())   # (online: the host sends for its bots)
		buffer.push(now, now, _sent_position(), velocity, input.yaw, input.pitch, _my_pose(), _my_anim_flags())
	if DevArgs.sync_log:
		var sp := _sent_position()  # without the leg tuck, which is a pose, not movement
		print("SYNC SELF %d %.4f %.4f %.4f %.4f %d %.2f %.2f %.2f" % [peer_id, Net.now(), sp.x, sp.y, sp.z, _my_pose(), velocity.x, velocity.y, velocity.z])


func _process(delta: float) -> void:
	if is_local:
		if rig:
			_roll = lerp(_roll, _target_roll(), min(delta * 8.0, 1.0))
			_punch = _punch.lerp(Vector2.ZERO, 1.0 - exp(-delta * 14.0))
			_punch_roll = lerpf(_punch_roll, 0.0, 1.0 - exp(-delta * 12.0))
			# A melee wind-up tips the view the way the body coils; the blow tips it back through level.
			var coil := animator.melee_turn() if weapon and weapon.data.is_melee() and alive else 0.0
			if coil != 0.0 or _coil_roll != 0.0:   # (spinning in mid-air, the view rocks a little with each turn)
				coil += animator.melee_swing().air() * 0.5 * sin(animator.melee_swing().spin())
			_coil_roll = lerpf(_coil_roll, coil * COIL_ROLL, 1.0 - exp(-delta * 16.0))
			rig.set_view(input.yaw + _punch.x, clampf(input.pitch + _punch.y, deg_to_rad(-89.0), deg_to_rad(89.0)),
				motor.eye_height, _roll + _punch_roll + _coil_roll)
			rig.place()   # (now, not after this: the arms, and the ropes that start at them, go where this frame is drawn)
		var g := motor.grapple
		_anim.state = motor.state
		_anim.crouched = motor.crouched
		_anim.velocity = velocity
		_anim.pitch = input.pitch
		_anim.flags = _my_anim_flags()
		_anim.grapple_on = g.rope_out()   # (the arm follows the hook out)
		_anim.grapple_anchor = g.rope_end()
		# (What the body needs of that rope to hang on it: see RopeSwing.)
		_anim.set_hook(g.line.look(g.clock, g.rope_origin(self), g.rope_origin(self)) if alive else [])
		_watch_swings(delta)
		_watch_kicks()
		_animate(delta)
		sounds.update(delta, _anim, true)
		if view:
			view.update(delta)
		_draw_hook(g.line.look(g.clock, rope_origin(), g.rope_origin(self), Vector3.INF, _first_person()) if alive else [])
		_update_trail(delta)
		_update_glide_fx(delta)
		_update_flame(delta)
		return
	if _awaiting_respawn:
		_check_overdue_respawn(delta)
	if not buffer.has_data():
		return
	var rt := buffer.render_time(Net.now(), delta)
	last_render_time = rt
	var s := buffer.sample(rt)
	var shown: Vector3 = s[0]
	_uncarried = shown + Vector3(0, tuck_offset(s[4]), 0)
	if MapRoot.current != null and is_instance_valid(MapRoot.current):
		# We see them a moment late: on an island under way, put them where it is now.
		shown = MapRoot.current.carried(shown, buffer.delay())
	global_position = shown + Vector3(0, tuck_offset(s[4]), 0)
	velocity = s[1]
	if alive:
		_visual_yaw = s[2]
	_remote_state = s[4]
	_update_pose(height_for_pose(_remote_state))
	_anim.state = pose_state(_remote_state)
	_anim.crouched = pose_crouched(_remote_state)
	_anim.velocity = velocity
	_anim.pitch = s[3]
	_anim.flags = s[5]
	# Their grappling hook shot, at the same moment as their body (see HookLine).
	var shot := _hook_shot_at(rt) if Mobility.is_grapple(mobility) else null
	var hook_anchor := _hook_anchor(shot)
	var st := shot.stage(rt) if shot else HookLine.OFF
	_guard_hook(shot, rt)
	_anim.grapple_on = st != HookLine.OFF   # (the arm stays out until the hook is back)
	if st == HookLine.FLYING:
		_anim.grapple_anchor = shot.flight_pos(rt)
	elif st == HookLine.RETRACT:
		if not _hook_look.is_empty():
			_anim.grapple_anchor = _hook_look[1]   # (where it was a frame ago: it is coming to the wrist)
	elif _anim.grapple_on:
		_anim.grapple_anchor = hook_anchor if hook_anchor != Vector3.INF else shot.anchor_at(rt)
	var rope_at := global_position + Vector3(0, HookLine.ATTACH_HEIGHT, 0)
	_anim.set_hook(shot.look(rt, rope_at, rope_at, hook_anchor) if shot and alive else [])
	_watch_swings(delta)
	_watch_charge(delta)
	_watch_kicks()
	_animate(delta)
	sounds.update(delta, _anim, visual.visible)
	var tight := st == HookLine.TAUT and alive and not _awaiting_respawn
	if DevArgs.sync_log and tight != _rope_seen:
		print("ROPE SEEN %d %d %s" % [Net.my_id(), peer_id, "on" if tight else "off"])
	_rope_seen = tight
	var drawn := alive and not _awaiting_respawn and visual.visible
	var chest := global_position + Vector3(0, HookLine.ATTACH_HEIGHT, 0)
	_draw_hook(shot.look(rt, rope_origin(), chest, hook_anchor) if shot and drawn else [])
	if DevArgs.sync_log and not _hook_look.is_empty():
		# (For the log the rope's near end is the chest, as in _log_own_hook: each copy
		# draws it at the wrist of the body as it poses it, which is not the shot's to say.)
		var logged := shot.look(rt, chest, chest, hook_anchor)
		var hp: Vector3 = logged[1]
		print("HOOK SEEN %d %d %d %.4f %d %.3f %.3f %.3f %.3f %.4f" % [Net.my_id(), peer_id, shot.seq, rt, logged[0], hp.x, hp.y, hp.z, logged[2], delta])
	_update_trail(delta)
	_update_glide_fx(delta)
	_update_flame(delta)
	if DevArgs.sync_log and alive and not _awaiting_respawn:
		var sp: Vector3 = s[0]
		print("SYNC SEEN %d %d %.4f %.4f %.4f %.4f %.4f" % [Net.my_id(), peer_id, rt, sp.x, sp.y, sp.z, delta])


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or is_bot or DevArgs.scripted_input:
		return  # only your own player listens to the keyboard and mouse (a bot is local too)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := deg_to_rad(Settings.mouse_sensitivity)
		input.yaw -= event.relative.x * sens
		var dy: float = event.relative.y * sens * (-1.0 if Settings.invert_y else 1.0)
		input.pitch = clamp(input.pitch - dy, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event.is_action_pressed("toggle_camera"):
		Settings.set_third_person(not Settings.third_person)
	elif event.is_action_pressed("reload") and racing:
		Race.send_back(self, "reset")   # stuck? back to your last checkpoint
	elif event.is_action_pressed("reload") and weapon:
		weapon.start_reload()
	elif racing:
		pass
	elif not alive and event.is_action_pressed("grapple"):
		_next_mobility()
	elif Net.is_deathmatch():
		if alive:
			_switch_weapon(event)   # weapons come off the map, not from a pick while dead
	elif not alive:
		_pick_on_death(event)


## Waiting to respawn: the mouse wheel goes through every allowed weapon, and the number
## keys pick a group (1 sidearms, 2 shotguns... 6 melee; again goes on through the group).
## With only some weapons allowed (see LobbySettings), the groups are those that have
## any, numbered from 1; with a single gun there is nothing to pick.
func _pick_on_death(event: InputEvent) -> void:
	if GunGame.active() or KillcamMode.active():
		return   # Gun Game hands out the weapons; Killcam is snipers only
	var k := _weapon_slot(event, LobbySettings.weapon_groups().size()) if event else _dev_group
	var step := 0
	if event and event.is_action_pressed("weapon_next"):
		step = 1
	elif event and event.is_action_pressed("weapon_prev"):
		step = -1
	var pick := LobbySettings.death_pick(Net.player_weapon(peer_id), k, step)
	if pick == "" or alive:
		return
	if DevArgs.sync_log:
		print("SWAP %d %s" % [peer_id, pick])
	if not DevArgs.swap_on_death:
		Settings.weapon = pick
		Settings.save_settings()
	Sound.play("equip_" + pick)
	Net.set_my_weapon(pick)


## Waiting to respawn: the mobility button goes on to the next mobility tool.
func _next_mobility() -> void:
	var pick := LobbySettings.next_mobility(Net.pending_mobility())   # only the tools the host allows
	if pick == Net.pending_mobility():
		return   # one tool for everyone
	Settings.mobility = pick
	Settings.save_settings()
	Sound.play("ui_select")
	Net.set_my_mobility(pick)
	if DevArgs.sync_log:
		print("MOBILITY_PICK %d %s" % [peer_id, pick])


## Reads keyboard and mouse into `input`. Mouse look arrives in _unhandled_input.
func read_local_input() -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DevArgs.drives_keys
	if not captured:
		input.move = Vector2.ZERO
		input.sprint = false
		input.jump_held = false
		input.fire = false
		input.grapple = false
		input.dive = false
		input.interact = false
		return
	if Input.is_action_just_pressed("kick"):
		input.kick_pressed = true
	if Input.is_action_just_pressed("boost"):
		input.boost_pressed = true
	input.glide = Input.is_action_pressed("glide")
	if Input.is_action_just_pressed("glide"):
		input.glide_pressed = true
	input.move = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back"))
	input.sprint = Input.is_action_pressed("sprint")
	input.interact = Input.is_action_pressed("interact")
	input.crouch = Input.is_action_pressed("crouch")
	if Input.is_action_just_pressed("crouch"):
		input.crouch_pressed = true
	input.jump_held = Input.is_action_pressed("jump")
	input.fire = Input.is_action_pressed("fire")
	if Input.is_action_just_pressed("fire"):
		input.fire_pressed = true
	if Input.is_action_just_pressed("jump"):
		input.jump_pressed = true
	input.dive = Input.is_action_pressed("dive")
	if Input.is_action_just_pressed("dive"):
		input.dive_pressed = true
	input.grapple = Input.is_action_pressed("grapple")
	if Input.is_action_just_pressed("grapple"):
		input.grapple_pressed = true


## In third person, the grapple aims along the crosshair from the camera.
func _set_crosshair_ray() -> void:
	if rig and rig.is_third_person():
		var cam := rig.camera.global_transform
		input.aim_origin = cam.origin
		input.aim_dir = -cam.basis.z
	else:
		input.aim_origin = Vector3.ZERO
		input.aim_dir = Vector3.ZERO


# ---------------------------------------------------------------------------
# Shooting

func _update_weapon(delta: float) -> void:
	weapon.update(delta)
	if Cheats.ammo() and not is_bot:
		weapon.ammo = weapon.data.magazine
	if input.fire_pressed:
		_fire_buffer = 0.1
	else:
		_fire_buffer = max(_fire_buffer - delta, 0.0)
	if weapon.data.is_melee():
		_update_melee(delta)
		return
	if weapon.data.is_blast():
		_update_blast(delta)
		return
	if weapon.data.spin_up > 0.0:   # the minigun: holding the trigger spins the barrels up
		var spinning: bool = input.fire and Match.running and weapon.ammo > 0 and not weapon.is_reloading()
		weapon.spin = clampf(weapon.spin + (delta if spinning else -2.0 * delta) / weapon.data.spin_up, 0.0, 1.0)
	if _burst_left > 0:   # the rest of a burst, a round every burst_gap seconds
		_burst_wait -= delta
		if _burst_wait <= 0.0 and Match.running and weapon.ammo > 0 and not weapon.is_reloading():
			_burst_left -= 1
			_burst_wait = weapon.data.burst_gap
			weapon.ammo -= 1
			_fire_round()
			if weapon.ammo <= 0:
				_burst_left = 0
				weapon.start_reload()
		elif weapon.ammo <= 0 or weapon.is_reloading():
			_burst_left = 0
		return
	var wants: bool = input.fire if weapon.data.automatic else _fire_buffer > 0.0
	if not wants or not Match.running:
		return
	if not weapon.fire():
		if input.fire_pressed and weapon.ammo <= 0 and sounds.own:
			Sound.play("dry_click", 0.0, 0.03)   # empty: the gun clicks while it reloads
		return
	_fire_buffer = 0.0
	if weapon.data.burst > 1:
		_burst_left = weapon.data.burst - 1
		_burst_wait = weapon.data.burst_gap
	_fire_round()


## One round leaves the gun (a shot, or a rocket or grenade): sound, recoil, and the
## host is asked what it hit.
func _fire_round() -> void:
	_next_gun()
	Sound.gun_fire(weapon.data.id, muzzle_position(), sounds.own)
	sounds.fired()
	animator.fire(_akimbo_left)
	if DevArgs.sync_log:
		print("ANIM FIRE %d" % peer_id)
	if view:
		view.fire(_akimbo_left)
	var eye := eye_position()
	if weapon.data.is_projectile():
		Match.request_projectile(eye, _aim_direction(eye), peer_id)
		return
	if weapon.data.is_blast():
		_send_blast(eye)
		return
	var aim := _aim_direction(eye)
	var dirs := shot_directions(aim, weapon.data, spread_scale())
	# Show the shot straight away; the host decides whether it hit.
	var ends := PackedVector3Array()
	var hits := []
	var space := get_world_3d().direct_space_state
	for dir in dirs:
		var end := eye + dir * weapon.data.max_range
		var hit := {}
		if not weapon.data.pierce:   # the railgun's slug stops for nothing
			var ray := PhysicsRayQueryParameters3D.create(eye, end, 1 | (1 << 1), [get_rid()])
			hit = space.intersect_ray(ray)
			if hit:
				end = hit.position
		ends.append(end)
		hits.append(hit and (hit.collider is Player or hit.collider is TargetDummy))
	ShotFx.spawn(get_parent().get_parent(), muzzle_position(), ends, hits, weapon.data.id)  # into the arena, not among the players
	Sound.shot_landed(muzzle_position(), ends, hits, sounds.own)
	var view_times := {}
	for p in get_parent().get_children():
		if p != self and p is Player and p.last_render_time >= 0.0:
			view_times[p.peer_id] = p.last_render_time
	Match.request_shot(eye, dirs, view_times, weapon.data.id, peer_id, aim)


# ---------------------------------------------------------------------------
# The air cannon (WeaponData.Kind.BLAST; see AirBlast)

## Holding the trigger charges the blast (a glow swells at the muzzle and a hum rises:
## see _watch_charge), letting go blasts. The longer the charge, up to the weapon's
## charge_time, the harder it shoves. No ammo: only fire_interval between blasts.
func _update_blast(delta: float) -> void:
	if _blast_held >= 0.0:
		_blast_held += delta
		if not Match.running:
			_blast_held = -1.0
		elif not input.fire:
			_blast_power = weapon.data.charge_of(_blast_held)
			_blast_held = -1.0
			weapon.fire()
			_fire_round()
		return
	var wants := input.fire or _fire_buffer > 0.0
	if not wants or not Match.running or not weapon.can_fire():
		return
	_fire_buffer = 0.0
	_blast_held = 0.0
	if DevArgs.sync_log:
		print("ANIM CHARGE %d" % peer_id)


## The blast leaves the gun (from _fire_round): its streaks of air are drawn straight
## away, the view jolts with the charge, and the host is asked whom it shoved.
func _send_blast(eye: Vector3) -> void:
	var aim := _aim_direction(eye)
	var ends := AirBlast.fan(get_world_3d().direct_space_state, eye, aim, weapon.data, _blast_power, [get_rid()])
	ShotFx.spawn(get_parent().get_parent(), muzzle_position(), ends, [], weapon.data.id)   # (into the arena)
	if rig:
		rig.kick(lerpf(0.3, 1.0, _blast_power))
		_punch += Vector2(0.0, -lerpf(0.01, 0.05, _blast_power))
	var view_times := {}
	for p in get_parent().get_children():
		if p != self and p is Player and p.last_render_time >= 0.0:
			view_times[p.peer_id] = p.last_render_time
	Match.request_blast(eye, aim, view_times, _blast_power, peer_id)


## How charged your air cannon is right now, 0..1, or -1 when it is not charging (the
## HUD and the bots ask).
func blast_charge() -> float:
	return weapon.data.charge_of(_blast_held) if weapon != null and _blast_held >= 0.0 else -1.0


## An air cannon charging (yours, or one seen in someone's snapshots): a glow swells at
## the muzzle and a hum rises with it. For other players only "charging" travels (the
## wind-up flag); how far is worked out from how long it has been seen, as for a swing.
func _watch_charge(delta: float) -> void:
	var data: WeaponData = WeaponData.by_id(robot.weapon) if robot and WeaponData.has(robot.weapon) else null
	var on := alive and data != null and data.is_blast() \
		and (_blast_held >= 0.0 if is_local else RobotAnimInput.winding_of(_anim.flags))
	_seen_charge = (_blast_held if is_local else maxf(_seen_charge, 0.0) + delta) if on else -1.0
	var amount := data.charge_of(_seen_charge) if on else -1.0
	sounds.charging(amount)
	if amount >= 0.0 and _charge_glow == null:
		_charge_glow = AirBlast.make_glow()
		add_child(_charge_glow)
	if _charge_glow:
		var shown := amount >= 0.0 and (visual.visible or rig != null)
		AirBlast.show_glow(_charge_glow, muzzle_position() if shown else Vector3.ZERO, amount if shown else -1.0, _first_person())


# ---------------------------------------------------------------------------
# Melee

## Swinging a melee weapon: holding the button winds the swing up (the body coils;
## there is no meter), letting go swings. The longer the wind-up, up to the weapon's
## charge_time, the harder the blow and the further it lunges you. A tap still draws
## back for the weapon's `windup` first. The host decides what it hit.
func _update_melee(delta: float) -> void:
	var data := weapon.data
	_slam_cool = maxf(_slam_cool - delta, 0.0)
	if _strike_left >= 0.0:
		_strike_left -= delta
		if _strike_left < 0.0:
			_strike()
	if motor.grapple.hooked_player() or _fly_kick > 0.0:
		_charge = -1.0
		return   # a player on your hook: the swing button is a flying kick (see _update_kick)
	if _charge >= 0.0:
		_charge += delta
		if not Match.running:
			_charge = -1.0
		elif not input.fire and _charge >= data.windup:
			if input.crouch and can_ground_slam():
				_ground_slam()   # let go in mid-air with crouch held
			else:
				_swing()
		return
	var wants := input.fire or _fire_buffer > 0.0
	if not wants or not Match.running or _strike_left >= 0.0 or not weapon.can_fire():
		return
	_fire_buffer = 0.0
	_charge = 0.0
	_swing_side = _next_side()
	if DevArgs.sync_log:
		print("ANIM WIND %d" % peer_id)


## Which tap comes next: taps take turns (the right, then the left; Karate goes on
## through its combo), starting from the first again after a pause.
func _next_side() -> int:
	var n := MeleeSwing.combo_length(robot.weapon) if robot and WeaponData.melee(robot.weapon) else 2
	return 0 if _since_swing > MeleeSwing.COMBO_RESET else (_seen_side + 1) % n


## Let go: the swing starts from however far it was wound up.
func _swing() -> void:
	var data := weapon.data
	weapon.fire()
	_swing_power = data.charge_of(_charge)
	_charge = -1.0
	_swings += 1   # (which blow it is travels with it: see RobotAnimInput.step_of)
	var airborne := motor.state in [MovementController.State.AIR, MovementController.State.FLIP, MovementController.State.GLIDE]
	_strike_left = MeleeSwing.impact_time(data.id, _swing_side, _swing_power, airborne)   # when the blade is mid-blow on screen
	# A slow blow (a spinning kick) holds the next one off until it is nearly done.
	weapon.hold_off(MeleeSwing.blow_length(data.id, _swing_side, _swing_power, airborne) * 0.7)
	# A jumping kick lifts you off your feet.
	var hop := MeleeSwing.hop_of(data.id, _swing_side, _swing_power, airborne) if not airborne else 0.0
	if hop > 0.0 and velocity.y < hop:
		motor.knock(Vector3.UP * (hop - maxf(velocity.y, 0.0)))
	# Lunge toward where you look (never past a sprinting dive's speed).
	var ahead := Vector3.FORWARD.rotated(Vector3.UP, input.yaw)
	var along := velocity.dot(ahead)
	var lunge := data.lunge * lerpf(0.4, 1.0, _swing_power)
	if lunge > 0.0 and along < 14.0:
		motor.knock(ahead * minf(lunge, 14.0 - along))
	if DevArgs.sync_log:
		print("ANIM SWING %d %.2f %d" % [peer_id, _swing_power, _swing_side])


# Ground slam (see GroundSlam): let go of a swing wound up in mid-air with crouch held.

## A ground slam could start right now: a melee weapon, in the air with room to fall,
## not done already this time in the air, and off its cooldown.
func can_ground_slam() -> bool:
	return alive and not racing and weapon != null and weapon.data.is_melee() and _slam_cool <= 0.0 \
		and _fly_kick <= 0.0 and not motor.grapple.hooked_player() and motor.can_slam(self)


func _ground_slam() -> void:
	weapon.fire()
	_slam_power = weapon.data.charge_of(_charge)
	_charge = -1.0
	_slam_cool = GroundSlam.COOLDOWN
	_slamming = true
	motor.start_slam(self)
	if DevArgs.sync_log:
		print("ANIM GROUND_SLAM %d %.2f" % [peer_id, _slam_power])


## Your slam, each step: once it touches down the host is told (it decides who it hit).
func _watch_ground_slam() -> void:
	if not _slamming:
		return
	var fell := motor.take_slam_landing()
	if fell >= 0.0:
		_slamming = false
		var view_times := {}
		for p in get_parent().get_children():
			if p != self and p is Player and p.last_render_time >= 0.0:
				view_times[p.peer_id] = p.last_render_time
		Match.request_ground_slam(global_position, view_times, _slam_power, fell, peer_id)
	elif motor.state != MovementController.State.SLAM:
		_slamming = false   # it found no floor in time


## 0..1: the ground slam's cooldown (1 = ready). The HUD shows it with the moves.
func ground_slam_readiness() -> float:
	return 1.0 - _slam_cool / GroundSlam.COOLDOWN


func ground_slamming() -> bool:
	return _slamming


## A ground slam landed somewhere. Its own player's copy draws it (once); yours shakes
## if it was near, and dips hard if it was yours.
func _on_ground_slammed(attacker: int, _weapon_id: String, at: Vector3, power: float, points: PackedVector3Array) -> void:
	if attacker == peer_id:
		_shown_power = maxf(power, MeleeSwing.HEAVY_AT)
		var color := RobotModel.trim_color(Net.player_color(peer_id))
		MeleeFx.slam(get_parent().get_parent(), at, color, power)
		for i in mini(points.size(), 4):
			MeleeFx.hit(get_parent().get_parent(), points[i], at + Vector3(0, 0.4, 0), color, power)
	if rig:
		if attacker == peer_id:
			_punch += Vector2(randf_range(-0.01, 0.01), -lerpf(0.09, 0.2, power))
			_punch_roll += randf_range(-0.03, 0.03)
			rig.kick(lerpf(0.5, 1.0, power))
		else:
			shake(clampf(1.0 - global_position.distance_to(at) / 14.0, 0.0, 1.0) * lerpf(0.6, 1.6, power))


## How wound up your swing is right now, 0..1 (0 when not winding up).
func melee_charge() -> float:
	return weapon.data.charge_of(_charge) if weapon != null and _charge >= 0.0 else 0.0


## Holding a wind-up (the bots ask).
func winding_up() -> bool:
	return _charge >= 0.0


func _strike() -> void:
	if not alive:
		return
	if rig:   # your own blow: the view jolts the way the blade travels, harder the more it was wound up
		var way := animator.melee_swing().travel()
		var weight := lerpf(0.5, 1.5, _swing_power)
		_punch += Vector2(-way.x * 0.035, way.y * 0.02 - 0.012) * weight
		_punch_roll += -way.x * 0.03 * weight
	var eye := eye_position()
	var view_times := {}
	for p in get_parent().get_children():
		if p != self and p is Player and p.last_render_time >= 0.0:
			view_times[p.peer_id] = p.last_render_time
	Match.request_melee(eye, aim_forward(), view_times, _swing_power, peer_id)


## A wind-up or a new swing (yours, or one seen in someone's snapshots): the body
## coils while the swing is held, then the swing itself and its whoosh. For other
## players only "winding up" travels; how far is worked out from how long it has
## been seen, at the weapon's pace.
func _watch_swings(delta: float) -> void:
	var count := _swings & 3 if is_local else RobotAnimInput.swings_of(_anim.flags)
	var melee := alive and robot.weapon != "none" and WeaponData.melee(robot.weapon)
	var winding := melee and (_charge >= 0.0 if is_local else RobotAnimInput.winding_of(_anim.flags))
	_since_swing += delta
	if winding:
		if not is_local:
			_swing_side = RobotAnimInput.step_of(_anim.flags)   # (the wind-up says which blow is coming)
		_seen_wind = _charge if is_local else maxf(_seen_wind, 0.0) + delta
		var held := WeaponData.by_id(robot.weapon).charge_of(_seen_wind)
		animator.wind(held, _swing_side)
		if view:
			view.wind(held, _swing_side)
		if _trail:
			_trail.power = held   # (a mid-air wind-up already leaves a trail)
	if _seen_swings < 0:
		_seen_swings = count   # just appeared: no swing to replay
		return
	if count != _seen_swings:
		_seen_swings = count
		if melee:
			var power := _swing_power if is_local else WeaponData.by_id(robot.weapon).charge_of(_seen_wind)
			if DevArgs.sync_log and not is_local:
				print("ANIM SWUNG %d %d %.2f %d" % [Net.my_id(), peer_id, power, RobotAnimInput.step_of(_anim.flags)])
			_seen_side = _swing_side if is_local else RobotAnimInput.step_of(_anim.flags)
			_since_swing = 0.0
			_shown_power = power
			animator.swing(power, _seen_side)
			if view:
				view.swing(power, _seen_side)
			if _trail:
				_trail.power = power
			var loud := lerpf(-5.0, 2.0, power)   # a wound-up swing whooshes louder, and the heavy blow deeper
			var pitch := 0.84 if power >= MeleeSwing.HEAVY_AT else (1.05 if _seen_side % 2 == 0 else 1.12)
			if sounds.own:
				var whoosh := Sound.play("swing_" + robot.weapon, loud, 0.05)
				if whoosh:
					whoosh.pitch_scale *= pitch
			elif visual.visible:
				var whoosh := Sound.play_at("swing_" + robot.weapon, global_position + Vector3(0, 1.3, 0), "move", loud, 0.05)
				if whoosh:
					whoosh.pitch_scale *= pitch
		_seen_wind = -1.0
	elif not winding:
		_seen_wind = -1.0


## How wound up this player's last swing was, 0..1 (the hit sound goes by it).
func swing_power() -> float:
	return _shown_power


## A blow landed somewhere. Ours: the swing freezes for a moment (hit-stop), sparks fly
## from where it struck and the view jolts harder.
func _on_melee_landed(attacker: int, weapon_id: String, points: PackedVector3Array) -> void:
	if attacker != peer_id or points.is_empty():
		return
	if weapon_id == "kick" or weapon_id == "flying_kick":
		if rig:
			_punch += Vector2(randf_range(-0.02, 0.02), -0.05 if weapon_id == "flying_kick" else -0.025)
			_punch_roll += randf_range(-0.03, 0.03)
		return
	# Harder the more it was wound up: a longer freeze, more sparks, a bigger jolt.
	var freeze := MeleeSwing.hit_stop_time(_shown_power)
	animator.hit_stop(freeze)
	if view:
		view.hit_stop(freeze)
	var way := animator.melee_swing().travel()
	if visual.visible or rig:
		var from := global_position + Vector3(0, 1.3, 0)
		var sweep := Vector3.RIGHT.rotated(Vector3.UP, input.yaw if is_local else _anim.yaw) * way.x + Vector3.UP * way.y
		for i in mini(points.size(), 3):   # (into the arena, not among the players)
			MeleeFx.hit(get_parent().get_parent(), points[i], from, RobotModel.trim_color(Net.player_color(peer_id)), _shown_power, sweep)
	if rig:
		var weight := lerpf(0.6, 2.2, _shown_power)
		_punch += Vector2(-way.x * 0.02 + randf_range(-0.01, 0.01), way.y * 0.012 - 0.018) * weight
		_punch_roll += (-way.x * 0.02 + randf_range(-0.01, 0.01)) * weight


# ---------------------------------------------------------------------------
# Kick, flying kick (see Kick) and being reeled in by someone's hook

## F: a quick front kick, whatever you carry. With a player on your hook it is a
## flying kick instead (so is a melee weapon's swing).
func _update_kick(delta: float) -> void:
	_kick_cool = maxf(_kick_cool - delta, 0.0)
	if _kick_strike >= 0.0:
		_kick_strike -= delta
		if _kick_strike < 0.0:
			_kick_strike = -1.0
			if alive:
				_send_kick(aim_forward(), false)
	if not Match.running:
		return
	var g := motor.grapple
	var swing_kick := weapon != null and weapon.data.is_melee() and input.fire_pressed
	if g.hooked_player() and (input.kick_pressed or swing_kick) and _fly_kick <= 0.0:
		_start_flying_kick(g.target as Player)
		return
	if not input.kick_pressed or _kick_cool > 0.0 or _kick_strike >= 0.0 or _fly_kick > 0.0:
		return
	_kick_cool = Kick.COOLDOWN
	_kick_strike = Kick.WINDUP
	_kicks += 1
	var ahead := Vector3.FORWARD.rotated(Vector3.UP, input.yaw)
	if velocity.dot(ahead) < 10.0:
		motor.knock(ahead * Kick.LUNGE)
	if DevArgs.sync_log:
		print("ANIM KICK %d" % peer_id)


func kick_readiness() -> float:
	return 1.0 - _kick_cool / Kick.COOLDOWN


## Let go of the rope and fly at them feet first.
func _start_flying_kick(target: Player) -> void:
	motor.grapple.release()
	motor.grapple.cooldown_left = 0.0   # the kick is the payoff: the hook is ready again after it
	_fly_target = target
	_fly_kick = Kick.FLYING_TIME
	_kicks += 1
	_kick_cool = Kick.COOLDOWN
	var to := Grapple.target_point(target) - (global_position + Vector3(0, 1.1, 0))
	velocity = to.normalized() * maxf(velocity.length(), Kick.FLYING_SPEED)
	if DevArgs.sync_log:
		print("FLYING_KICK %d %d" % [peer_id, target.peer_id])


## While flying: bend toward them, and land the kick when close enough.
func _steer_flying_kick(delta: float) -> void:
	if _fly_kick <= 0.0:
		return
	_fly_kick -= delta
	var t := _fly_target
	if t == null or not is_instance_valid(t) or not t.alive or not t.visible_in_world():
		_fly_kick = 0.0
		return
	var to := Grapple.target_point(t) - (global_position + Vector3(0, 1.1, 0))
	if to.length() <= Kick.FLYING_REACH - 0.6:
		_fly_kick = 0.0
		_send_kick(to.normalized(), true)
		return
	var speed := maxf(velocity.length(), Kick.FLYING_SPEED)
	velocity = velocity.lerp(to.normalized() * speed, minf(Kick.FLYING_STEER * delta, 1.0))
	if _fly_kick <= 0.0:
		_send_kick(to.normalized(), true)   # ran out of time: one last try (the host checks the reach)


func flying_kick() -> bool:
	return _fly_kick > 0.0


func _send_kick(dir: Vector3, flying: bool) -> void:
	if rig:
		_punch += Vector2(0.0, -0.03)
	var view_times := {}
	for p in get_parent().get_children():
		if p != self and p is Player and p.last_render_time >= 0.0:
			view_times[p.peer_id] = p.last_render_time
	Match.request_kick(eye_position(), dir, view_times, flying, peer_id)


## Tell the host when the hook catches a player or lets go (they get reeled in too).
func _report_tether() -> void:
	var g := motor.grapple
	var now := (g.target as Player).peer_id if alive and g.hooked_player() and g.target is Player else 0
	if now == _tether_id:
		return
	if _tether_id != 0:
		Match.request_tether(_tether_id, false, peer_id)
	_tether_id = now
	if now != 0:
		Match.request_tether(now, true, peer_id)
		if DevArgs.sync_log:
			print("TETHER %d %d" % [peer_id, now])


## Someone hooked you (the host says so): you are dragged toward them.
func tug(by: int, on: bool) -> void:
	if not on:
		if by == _tug_by:
			_tug_by = 0
		return
	if not alive or _flying or motor == null:
		return
	_tug_by = by
	_tug_left = motor.tuning.tether_time + 0.3
	_tug_fresh = true
	if DevArgs.sync_log:
		print("TUGGED %d by %d" % [peer_id, by])


func _update_tug(delta: float) -> void:
	if _tug_by == 0:
		return
	_tug_left -= delta
	var other: Player = Net.arena.get_player(_tug_by) if Net.arena else null
	if _tug_left <= 0.0 or other == null or not other.alive:
		_tug_by = 0
		return
	var to := other.global_position - global_position
	var dist := to.length()
	var t := motor.tuning
	if dist < t.tether_meet:
		_tug_by = 0
		return
	var dir := to / dist
	var push := Vector3.ZERO
	var room := t.tug_speed - velocity.dot(dir)
	if room > 0.0:
		push = dir * minf(t.tug_accel * delta, room)
	if _tug_fresh:
		_tug_fresh = false
		push.y = maxf(push.y, t.tug_lift)   # yanked off your feet
	if push != Vector3.ZERO:
		motor.knock(push)


func being_tugged() -> bool:
	return _tug_by != 0


## Alive and drawn: something a hook or a kick can find.
func visible_in_world() -> bool:
	return alive and visual.visible and collision_layer != 0


## A new kick or rocket burst (yours, or one seen in someone's snapshots): the leg
## swings and whooshes; the boots flare.
func _watch_kicks() -> void:
	var count := _kicks & 3 if is_local else RobotAnimInput.kicks_of(_anim.flags)
	var flying := flying_kick() if is_local else RobotAnimInput.flying_of(_anim.flags)
	var boosts := (motor.boosts & 3) if is_local else RobotAnimInput.boosts_of(_anim.flags)
	if _seen_kicks < 0:
		_seen_kicks = count
		_seen_boosts = boosts
		_seen_flying = flying
		return
	if boosts != _seen_boosts:
		_seen_boosts = boosts
		if DevArgs.sync_log and not is_local:
			print("BOOST SEEN %d %d" % [Net.my_id(), peer_id])
		if alive and visual.visible:
			_flame_t = 0.45
			if sounds.own:
				Sound.play("rocket_boost", 0.0, 0.05)
			else:
				Sound.play_at("rocket_boost", global_position + Vector3(0, 0.3, 0), "move", 0.0, 0.05)
	if flying != _seen_flying:
		_seen_flying = flying
		animator.set_flying_kick(flying and alive)
	if count == _seen_kicks:
		return
	_seen_kicks = count
	if not alive:
		return
	animator.kick(flying)
	if DevArgs.sync_log and not is_local:
		print("KICK SEEN %d %d%s" % [Net.my_id(), peer_id, " flying" if flying else ""])
	var sound := "kick" if not flying else "flying_kick"
	if sounds.own:
		Sound.play(sound, 0.0, 0.05)
	elif visual.visible:
		Sound.play_at(sound, global_position + Vector3(0, 1.0, 0), "move", 0.0, 0.05)


## The glowing trail behind the blade while it cuts: on your first-person arms
## when you are looking through them, otherwise on the body.
func _update_trail(delta: float) -> void:
	if _trail == null:
		return
	var own_view := view != null and rig != null and not rig.is_third_person()
	var limb := animator.melee_swing().kicking() if alive and animator.cutting() else ""
	if limb != "" and visual.visible:   # a kick: the shin and foot leave the trail (your own leg, in first person too)
		var e := MeleeModel.kick_edge(robot, limb)
		_trail.add(e[0], e[1])
	elif own_view and view.visible and view.cutting():
		var e := view.edge()
		_trail.add(e[0], e[1])
	elif not own_view and alive and visual.visible and animator.cutting() and robot.melee:
		var e := MeleeModel.edge(robot.melee_left if animator.melee_swing().left_fist() and robot.melee_left else robot.melee)
		_trail.add(e[0], e[1])
	_trail.tick(delta)


## A glide's wind trail and speed streaks (everyone sees them), and in first person
## the view widening a little with its speed.
func _update_glide_fx(delta: float) -> void:
	var gliding := alive and visual.visible and _anim.state == MovementController.State.GLIDE
	if rig:
		rig.glide_widen = clampf((velocity.length() - 8.0) / 16.0, 0.0, 1.0) if gliding else 0.0
	if _glide_fx == null:
		return
	var feet := [robot.marker("foot_l"), robot.marker("foot_r")] if gliding else []
	_glide_fx.tick(delta, gliding, feet, velocity, global_position + Vector3(0, 0.9, 0))


## A hit or shove from the host: knocked along, and off your feet if it lifts you.
func knock(push: Vector3) -> void:
	if motor and alive and not _flying:
		motor.knock(push)
		if DevArgs.sync_log:
			print("KNOCK %d %.1f" % [peer_id, push.length()])


## Hit a wall or prop too fast? The host decides how much it hurts.
func _check_slam(delta: float) -> void:
	_slam_wait = maxf(_slam_wait - delta, 0.0)
	if racing or _slam_wait > 0.0 or motor.impact_speed < Match.SLAM_SPEED or not Match.running:
		return
	if (motor.since_boost < 0.4 or _fly_kick > 0.0) and not being_tugged():
		return   # your own rocket burst or flying kick into a wall doesn't hurt you
	_slam_wait = 0.5
	Match.request_slam(motor.impact_speed, motor.impact_point, peer_id)


## A light blade lets you run a little faster. (Takes off the old weapon's bonus
## first, so a Deathmatch weapon switch can call it again.)
func _apply_move_bonus() -> void:
	var bonus := weapon.data.move_bonus if weapon and not racing else 1.0
	if bonus != _move_bonus:
		var k := bonus / _move_bonus
		motor.tuning.run_speed *= k
		motor.tuning.sprint_speed *= k
		motor.tuning.air_speed *= k
		_move_bonus = bonus


## The local copy of a weapon (ammo, cooldown): null for empty hands ("none").
func _make_weapon(gun: String) -> WeaponState:
	return WeaponState.new(WeaponData.by_id(gun)) if WeaponData.has(gun) else null


# ---------------------------------------------------------------------------
# Deathmatch: carrying several weapons

## Hold a different weapon (or "none": empty hands) without respawning: the body,
## your first-person arms, the sounds and the local weapon state change in place,
## so you keep your speed, rope and everything else. Ammo is kept per weapon.
func equip(gun: String) -> void:
	if racing or robot == null:
		return
	if not alive:
		_pending_gun = gun   # dead: the body keeps what it fell with; the change shows on respawn
		return
	_pending_gun = ""
	change_weapon(gun)


## Deathmatch: walked over a weapon: a full magazine for it, carried or in hand.
func picked_up(gun: String) -> void:
	_ammo[gun] = WeaponData.by_id(gun).magazine
	if weapon and weapon.data.id == gun:
		weapon.reset()


## Deathmatch, alive: 1 or 2 takes out the weapon in that slot; the mouse wheel
## swaps to the other one.
func _switch_weapon(event: InputEvent) -> void:
	var slots := Net.player_inventory(peer_id)
	var current := robot.weapon
	var pick := ""
	var k := _weapon_slot(event, slots.size())
	if k >= 0:
		pick = slots[k]
	elif event.is_action_pressed("weapon_next") or event.is_action_pressed("weapon_prev"):
		for w in slots:
			if w != "" and w != current:
				pick = w
	if pick == "" or pick == current:
		return
	Net.switch_my_weapon(pick)


## Which weapon_N action `event` presses, as an index from 0 (-1 for none or past `count`).
func _weapon_slot(event: InputEvent, count: int) -> int:
	if event.is_echo():
		return -1
	for i in count:
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			return i
	return -1


## The ammo you have for a weapon you carry (HUD), -1 if unknown.
func ammo_for(gun: String) -> int:
	if weapon and weapon.data.id == gun:
		return weapon.ammo
	return int(_ammo.get(gun, WeaponData.by_id(gun).magazine))


## Gliding steadies your aim: every gun's spread is this much of its usual size.
const GLIDE_SPREAD := 0.5


## How wide this player's shots scatter right now, against the gun's own spread (1 = as usual).
func spread_scale() -> float:
	return GLIDE_SPREAD if motor and motor.state == MovementController.State.GLIDE else 1.0


## The directions of one shot's pellets (one for most guns), spread at random
## around `aim` by the gun's spread. A shotgun's pellets fill its cone evenly.
## `tighten` scales the spread (see spread_scale).
static func shot_directions(aim: Vector3, data: WeaponData, tighten: float = 1.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var spread := deg_to_rad(data.spread_degrees) * tighten
	var side := aim.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
	var up := side.cross(aim).normalized()
	for i in data.pellets:
		if data.pellets == 1:
			var d := aim.rotated(side, randf_range(-spread, spread))
			out.append(d.rotated(Vector3.UP, randf_range(-spread, spread)).normalized())
			continue
		# Pellets spread over a disc: one in the middle, the rest in rings, each nudged at random.
		var angle := TAU * (float(i) / data.pellets) + randf_range(-0.3, 0.3)
		var r := spread * (0.0 if i == 0 else sqrt(randf_range(0.25, 1.0)))
		var off := (side * cos(angle) + up * sin(angle)) * tan(r)
		out.append((aim + off).normalized())
	return out


func eye_position() -> Vector3:
	return global_position + Vector3(0, motor.eye_height if motor else CameraRig.EYE_HEIGHT, 0)


func aim_forward() -> Vector3:
	return Basis.from_euler(Vector3(input.pitch, input.yaw, 0.0)) * Vector3.FORWARD


## In third person the camera sits behind the shoulder, so we find what the crosshair
## points at from the camera, then shoot at that point from the eyes.
func _aim_direction(eye: Vector3) -> Vector3:
	var forward := aim_forward()
	if rig == null or not rig.is_third_person():
		return forward
	var cam := rig.camera.global_transform
	var from := cam.origin
	var to := from - cam.basis.z * (weapon.data.max_range if weapon else 200.0)
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1 | (1 << 1), [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var target: Vector3 = hit.position if hit else to
	var dir := (target - eye).normalized()
	return dir if dir.dot(forward) > 0.2 else forward


func muzzle_position() -> Vector3:
	var data := WeaponData.by_id(robot.weapon)
	var bone := data.muzzle_bone_left if _akimbo_left and data.is_akimbo() else data.muzzle_bone
	if view and not rig.is_third_person():
		return view.marker(bone)
	return robot.marker(bone)


## Akimbo: which gun this shot leaves from. They take turns, right first.
func _next_gun() -> void:
	_akimbo_left = WeaponData.by_id(robot.weapon).is_akimbo() and _akimbo_shots % 2 == 1
	_akimbo_shots += 1


## Where the grapple rope leaves the robot: the launcher on its left wrist.
func rope_origin() -> Vector3:
	if _first_person():
		return view.marker("grapple")
	return robot.marker("grapple")


## Is this body seen through its own eyes here (the first-person arms, not the robot)?
func _first_person() -> bool:
	return view != null and not rig.is_third_person()


## Another player's shot, as told by the host: kick their gun.
func show_shot() -> void:
	_next_gun()
	animator.fire(_akimbo_left)
	Sound.gun_fire(robot.weapon, muzzle_position(), false)
	sounds.fired()
	if DevArgs.sync_log:
		print("ANIM SHOT %d %d" % [Net.my_id(), peer_id])


# ---------------------------------------------------------------------------
# Life and death

## --swap-on-death (tests): just died, so press the next weapon's number key.
func dev_swap_after_death() -> void:
	var groups := LobbySettings.weapon_groups()
	var mine := Net.player_weapon(peer_id)
	var at := groups.find_custom(func(g): return mine in g[1])
	var group := (at + 1) % groups.size() if groups.size() > 1 else 0
	get_tree().create_timer(0.5).timeout.connect(func():
		if is_instance_valid(self) and is_inside_tree():
			_dev_group = group
			_pick_on_death(null)
			_dev_group = -1)


func set_dead() -> void:
	alive = false
	_in_remains = false
	_charge = -1.0
	_blast_held = -1.0
	_fly_kick = 0.0
	_tug_by = 0
	_flame_t = 0.0
	if motor:
		motor.reset()
	collision_layer = 0
	# The body stays where it fell and powers down. Shot in mid-air, it drops to the ground.
	_corpse_drop = 0.0
	_corpse_fall = 0.0
	var below := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.5, 0), global_position + Vector3(0, -80.0, 0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(below) if is_inside_tree() else {}
	_corpse_room = maxf(global_position.y - hit.position.y, 0.0) if hit else 200.0
	if not is_local and not buffer.has_data():
		visual.visible = false   # joined while they were dead: nothing to show yet
	if _awaiting_respawn:
		# Killed again before a snapshot from that life got here: we never saw them back.
		_awaiting_respawn = false
		if DevArgs.sync_log:
			print("RESPAWN_CANCEL %d %d" % [Net.my_id(), peer_id])
	_dead_life = maxi(_seen_life, _awaited_life)


## Dead: a ragdoll or giblets took the body's place (see Remains), so it is hidden
## until the respawn. The killcam still counts it as drawn (see shown_state).
func hide_for_remains() -> void:
	visual.visible = false
	_in_remains = true


## Local player: come back at a spawn point, in the life the host numbered `life`
## (see Match._respawned; -1 keeps the number, for a race's send-back).
func respawn_at(pos: Vector3, yaw: float, life: int = -1) -> void:
	teleport(pos, yaw)
	_teleport_count += 1
	if life >= 0:
		_life = life
	_fell_reported = false
	alive = true
	_ammo.clear()   # Deathmatch: what you carried went with you
	if _pending_gun != "":
		equip(_pending_gun)
	visual.visible = true
	collision_layer = 1 << 1
	animator.respawn()
	sounds.respawned()
	if view:
		view.respawn()
	if weapon:
		weapon.reset()
	_strike_left = -1.0
	_charge = -1.0
	_seen_wind = -1.0
	_kick_strike = -1.0
	_kick_cool = 0.0
	_slamming = false
	_slam_cool = 0.0
	_fly_kick = 0.0
	_tug_by = 0
	if blink:
		blink.reset()
	if jetpack:
		jetpack.reset()
	_send_timer = 0.0  # tell everyone at once


func respawn_count() -> int:
	return _teleport_count


func set_respawn_count(n: int) -> void:
	_teleport_count = n


## Arena.rebuild_player: the new body takes over which life the old one was in, and
## (for someone else) whether it was still waiting to see them back.
func carry_life_from(old: Player) -> void:
	_life = old._life
	_seen_life = old._seen_life
	_awaited_life = old._awaited_life
	_dead_life = old._dead_life
	if old._awaiting_respawn and not is_local:
		_awaiting_respawn = true
		visual.visible = false
		collision_layer = 0


## A blast went off nearby: the view jolts (0..1, how close).
func shake(amount: float) -> void:
	if amount <= 0.0:
		return
	_punch += Vector2(randf_range(-0.03, 0.03), randf_range(0.01, 0.04)) * amount
	_punch_roll += randf_range(-0.04, 0.04) * amount


## A new weapon in your hands right now ("none": empty hands), wherever you are and
## whatever you are doing: only the robot's model, arms, sounds and gun are rebuilt,
## not the movement, so you keep your speed and rope. Gun Game hands you the next
## weapon this way; a Deathmatch switch or pickup too (see equip). Ammo is kept per weapon.
func change_weapon(gun: String) -> void:
	if racing or robot == null or robot.weapon == gun:
		return
	if weapon:
		_ammo[weapon.data.id] = weapon.ammo
	var color := Net.player_color(peer_id)
	var was_visible := visual.visible
	visual.remove_child(robot)
	robot.queue_free()
	robot = RobotModel.new().build(character, color, false, gun, false, Teams.paint_for(peer_id))
	visual.add_child(robot)
	animator = RobotAnimator.new(robot)
	if sounds:
		sounds.free_voices()
	sounds = PlayerSounds.new(self, is_local and not is_bot, gun)
	_seen_swings = -1
	_seen_wind = -1.0
	_strike_left = -1.0
	_charge = -1.0
	_blast_held = -1.0
	_seen_charge = -1.0
	_burst_left = 0
	_akimbo_shots = 0
	_akimbo_left = false
	if is_local:
		weapon = _make_weapon(gun)
		if weapon and _ammo.has(gun):
			weapon.ammo = _ammo[gun]
		_apply_move_bonus()
		if is_bot and brain is BotBrain:
			(brain as BotBrain).weapon_changed()
	if rig:
		robot.set_layer(CameraRig.BODY_LAYER)
		robot.add_view_mesh(CameraRig.VIEW_BODY_LAYER)
		var shown := view.visible
		rig.camera.remove_child(view)
		view.queue_free()
		view = ViewModel.new()
		rig.camera.add_child(view)
		view.setup(self, color)
		view.respawn()
		view.visible = shown
		if sounds.own and gun != "none":
			Sound.play("equip_" + gun)
	if _trail:
		_trail.queue_free()
		_trail = null
	if WeaponData.melee(gun):
		_trail = SwingTrail.new().setup(RobotModel.trim_color(color))
		add_child(_trail)
	if _glide_fx:
		_glide_fx.set_color(RobotModel.trim_color(color))
	visual.visible = was_visible
	if DevArgs.sync_log:
		print("GUN %s %d %d %s" % ["SELF" if is_local else "SEEN", Net.my_id(), peer_id, gun])


## Remote player rebuilt while dead (they swapped weapons): hidden until they respawn.
func expect_dead() -> void:
	visual.visible = false


## Remote player: alive again in `life` (the host's number for it, see Match._respawned).
## Their snapshots and the news of the respawn travel separately, so either can get
## here first: if a snapshot from the new life is already here they show at once,
## otherwise they stay hidden until one arrives (where they were is no place to draw them).
func expect_respawn(life: int) -> void:
	alive = true
	if _pending_gun != "":
		equip(_pending_gun)
	sounds.respawned()
	_awaited_life = life
	if _seen_life >= life and buffer.has_data():
		_show_respawned("early")   # (a new life clears the buffer: it holds only snapshots from after the respawn)
		return
	_awaiting_respawn = true
	_hidden_for = 0.0
	_hidden_snaps = 0
	visual.visible = false
	if DevArgs.sync_log:
		print("RESPAWN_WAIT %d %d" % [Net.my_id(), peer_id])


## Remote player: back, and we know where: show them. `how` is for --sync-log: "snapshot"
## (it came after the respawn), "early" (before it) or "late" (the safety net).
func _show_respawned(how: String) -> void:
	_awaiting_respawn = false
	visual.visible = true
	collision_layer = 1 << 1
	animator.respawn()
	if DevArgs.sync_log:
		print("RESPAWN_SHOW %d %d %s" % [Net.my_id(), peer_id, how])


## Safety net: someone the host says is alive, still hidden waiting for a snapshot from
## their new life over a second after we were told, while their snapshots keep coming,
## is shown anyway. Being shot by someone you cannot see is worse than a jump on screen.
func _check_overdue_respawn(delta: float) -> void:
	_hidden_for += delta
	if _hidden_for < OVERDUE_RESPAWN or _hidden_snaps < 10 or not alive or not Match.is_alive(peer_id):
		return
	if Net.now() - _newest_snap_at > 0.5:
		return   # their snapshots have stopped coming: nothing new to draw them with
	if DevArgs.sync_log:
		print("RESPAWN_SHOW_LATE %d" % peer_id)
	_show_respawned("late")


func report_fell_once() -> void:
	if racing:
		Race.send_back(self, "fell")
		return
	if not _fell_reported and alive:
		_fell_reported = true
		Match.request_fell(peer_id)


# ---------------------------------------------------------------------------
# Network state

## Snapshot layout: position (3), velocity (3), yaw, pitch, movement state,
## respawn count (it also goes up on a blink), animation flags (see
## RobotAnimInput.make_flags), life (see _life). While a grappling hook shot is out
## (and a moment after): the whole shot (HookLine.pack) on the end, so any one
## snapshot is enough to draw it.
func make_snapshot() -> PackedFloat32Array:
	var p := _sent_position()
	var v := velocity
	var g := motor.grapple
	var out := PackedFloat32Array([p.x, p.y, p.z, v.x, v.y, v.z, input.yaw, input.pitch,
		float(_my_pose()), float(_teleport_count), float(_my_anim_flags()), float(_life)])
	if g.line.sending(g.clock):
		out.append_array(g.line.pack(g.clock))
	return out


func apply_snapshot(remote_time: float, data: PackedFloat32Array) -> void:
	if data.size() < 10:
		return
	if remote_time <= _newest_snap:
		return   # older than one already here (unreliable packets can arrive out of order): it would undo a respawn or a jump
	_newest_snap = remote_time
	_newest_snap_at = Net.now()
	var count := int(data[9])
	var life := int(data[11]) if data.size() >= SNAPSHOT_SIZE else _seen_life
	var new_life := life != _seen_life
	if count != _teleport_count or new_life:
		_teleport_count = count
		if alive and not _awaiting_respawn and visual.visible and buffer.has_data() and not new_life:
			_show_warp(latest_position(), Vector3(data[0], data[1], data[2]))   # a blink, not a respawn
		buffer.clear_history()  # never blend across a respawn
		if new_life and not alive and _dead_life >= 0 and life > _dead_life:
			# Back already, and we have not been told yet: the body that fell is not
			# dragged to where they are now. They show once the respawn gets here.
			visual.visible = false
			_in_remains = false
	_seen_life = life
	buffer.push(remote_time, Net.now(),
		Vector3(data[0], data[1], data[2]), Vector3(data[3], data[4], data[5]),
		data[6], data[7], int(data[8]), int(data[10]) if data.size() >= 11 else 0)
	if _awaiting_respawn:
		_hidden_snaps += 1
		if life >= _awaited_life:
			_show_respawned("snapshot")
	if data.size() >= SNAPSHOT_SIZE + HookLine.PACKED:
		if _hook_line == null or HookLine.packed_seq(data, SNAPSHOT_SIZE) != _hook_line.seq:
			_hook_old = _hook_line   # (the shot before may still be whipping back on our screen)
			_hook_line = HookLine.new()
		var known := _hook_line.moments()
		_hook_line.absorb(remote_time, data, SNAPSHOT_SIZE, _hook_old)
		if DevArgs.sync_log and _hook_line.moments() != known:
			_log_hook("SEEN %d %d" % [Net.my_id(), peer_id], _hook_line, known, 0.0)
	elif _hook_line and _hook_line.t_release == INF:
		_hook_line.drop(remote_time)   # no more news of a shot we never saw end: it is over


func latest_position() -> Vector3:
	if not buffer.has_data():
		return global_position
	var last = buffer.snaps[-1]
	return last.pos + Vector3(0, tuck_offset(last.state), 0)


## Newest known velocity: from snapshots, or the body's own for a player with none.
func latest_velocity() -> Vector3:
	if not buffer.has_data():
		return velocity
	return buffer.snaps[-1].vel


func latest_time() -> float:
	return buffer.snaps[-1].t if buffer.has_data() else Net.now()


## Movement state, crouch and leg tuck packed into one number for snapshots:
## state + 100 if crouched + 1000 x the tuck in centimetres.
static func make_pose(state: int, crouched: bool, tuck: float = 0.0) -> int:
	return state + (100 if crouched else 0) + 1000 * int(round(tuck * 100.0))


static func pose_state(pose: int) -> int:
	return pose % 100


static func pose_crouched(pose: int) -> bool:
	return (pose / 100) % 10 == 1


## Tucking the legs in the air lifts the feet without moving the head. Snapshots
## carry the feet as if not tucked (so the position never jumps) plus this offset.
static func tuck_offset(pose: int) -> float:
	return (pose / 1000) / 100.0


func _my_pose() -> int:
	return make_pose(motor.state, motor.crouched, motor.tuck)


func _sent_position() -> Vector3:
	return global_position - Vector3(0, motor.tuck, 0)


## Body height for a pose (shorter when crouched, shortest on your belly): used for the hitbox.
static func height_for_pose(pose: int) -> float:
	if pose_state(pose) == MovementController.State.BELLY_SLIDE:
		return PRONE_HEIGHT
	return CROUCH_HEIGHT if pose_crouched(pose) else CAPSULE_HEIGHT


## Which way this player faced at time t (on this player's clock): for stabs in the back.
func yaw_at(t: float) -> float:
	return buffer.sample(t)[2] if buffer.has_data() else input.yaw


## Was this player crouched at time t (on this player's clock)?
func pose_at(t: float) -> int:
	return buffer.sample(t)[4] if buffer.has_data() else (_my_pose() if motor else 0)


## Remote players: shrink the collision shape when they crouch or lie down. (Your
## own shape is handled by the movement code.) The drawn body follows through its animation.
func _update_pose(h: float) -> void:
	if is_equal_approx(h, _height):
		return
	_height = h
	(_shape.shape as CapsuleShape3D).height = h
	_shape.position.y = h * 0.5


## The small animation facts that travel in snapshots (see RobotAnimInput.make_flags).
func _my_anim_flags() -> int:
	var right := Vector3.RIGHT.rotated(Vector3.UP, input.yaw)
	var wall := motor.wall_normal if motor.state in [MovementController.State.WALL_RUN, MovementController.State.WALL_SIT] else motor.kick_wall
	var flip := RobotAnimInput.FLIP_BACK
	var f := motor.flip_dir
	if absf(f.x) > absf(f.y):
		flip = RobotAnimInput.FLIP_RIGHT if f.x > 0.0 else RobotAnimInput.FLIP_LEFT
	elif f.y > 0.0:
		flip = RobotAnimInput.FLIP_FRONT
	return RobotAnimInput.make_flags(wall.dot(right) < 0.0, motor.is_vaulting(),
		weapon != null and weapon.is_reloading(), flip, motor.wall_jumps, _swings,
		_kicks, _fly_kick > 0.0, motor.boosts, (_charge >= 0.0 or _blast_held >= 0.0) and alive, jetpack != null and jetpack.on and alive, _swing_side,
		motor.state == MovementController.State.GRAPPLE and input.move.length() > 0.3,
		RobotAnimInput.zip_of(motor.dove_in and motor.state == MovementController.State.GRAPPLE, motor.dove_side))


## Turns the body to face its yaw and plays its animation.
func _animate(delta: float) -> void:
	if not alive and _corpse_drop < _corpse_room:
		_corpse_fall += 22.0 * delta
		_corpse_drop = minf(_corpse_drop + _corpse_fall * delta, _corpse_room)
	elif alive:
		_corpse_drop = 0.0
	var first_person := rig.first_person_amount() if rig and alive else 0.0
	visual.transform = Transform3D(Basis(Vector3.UP, _visual_yaw), Vector3(0, -_corpse_drop, 0))
	_anim.alive = alive
	_anim.yaw = _visual_yaw
	if first_person > 0.0 and motor and motor.auto_tucked():
		_anim.crouched = false   # Variant B: your own legs do not pull up for the automatic tuck in first person
	animator.first_person = first_person > 0.0
	animator.fx_parent = get_parent().get_parent() if is_inside_tree() else null   # a reload's spent cell goes into the arena
	_anim.feet = _feet_ground()
	if animator.glide_flipping():
		animator.glide_flip_floor_in(_floor_in())   # (the backflip out of a glide is round before the landing)
	animator.update(delta, _anim, visual.global_transform)
	if rig:
		animator.place_for_view(first_person, motor.eye_height, input.pitch)
	if DevArgs.sync_log:
		_log_animation()


## The ground under each foot, measured from the floor this body stands on (see
## RobotAnimInput.feet): a short ray straight down through each foot. Only while
## standing or crouching still, which is the only time RobotAnimator uses it.
func _feet_ground() -> Vector2:
	if not alive or robot == null or not is_inside_tree():
		return Vector2.ZERO
	if not (_anim.state in [MovementController.State.GROUND, MovementController.State.CROUCH]):
		return Vector2.ZERO
	if Vector2(_anim.velocity.x, _anim.velocity.z).length() > RobotAnimator.FEET_STILL:
		return Vector2.ZERO
	var space := get_world_3d().direct_space_state
	var floor_y := global_position.y
	var out := Vector2.ZERO
	for i in 2:
		var at := robot.marker("foot_l" if i == 0 else "foot_r")
		var ray := PhysicsRayQueryParameters3D.create(Vector3(at.x, floor_y + RobotAnimator.FEET_REACH + 0.1, at.z),
			Vector3(at.x, floor_y - RobotAnimator.FEET_REACH - 0.1, at.z), 1, [get_rid()])
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			out[i] = (hit.position as Vector3).y - floor_y
	return out


## Seconds until this body, falling as it is, reaches the floor below it (a long time
## when there is none within 60 m). For anyone's body: it goes by where it is and how
## it is moving, as this copy of the game shows it.
func _floor_in() -> float:
	if not is_inside_tree():
		return 99.0
	var from := global_position + Vector3(0, 0.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 60, 0), 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return 99.0
	var drop := maxf(from.y - (hit.position as Vector3).y - 0.5, 0.0)
	var g := 22.0 * (motor.gravity_scale if motor else 1.0)
	return (velocity.y + sqrt(velocity.y * velocity.y + 2.0 * g * drop)) / g


## For tests/check_anim.py: prints the animation this body shows whenever it changes.
## Your own player and the bot print what they are doing (SELF); every other player
## prints what this copy of the game draws for them (SEEN).
func _log_animation() -> void:
	var shown := animator.source + ("+reload" if alive and _anim.reloading() else "")
	if shown == _logged_anim or not visual.visible:
		return
	_logged_anim = shown
	_print_animation(shown)


func _print_animation(shown: String) -> void:
	if is_local:
		print("ANIM SELF %d %.4f %s" % [peer_id, Net.now(), shown])
	elif buffer.has_data():
		print("ANIM SEEN %d %d %.4f %s" % [Net.my_id(), peer_id, last_render_time, shown])


func _exit_tree() -> void:
	if DevArgs.sync_log and _logged_anim != "":
		_print_animation("-")  # this body is gone (match over, or the player left)


## Lean the camera away from the wall while wall-running.
func _target_roll() -> float:
	if motor.state != MovementController.State.WALL_RUN:
		return 0.0
	var right := Vector3.RIGHT.rotated(Vector3.UP, input.yaw)
	return -motor.wall_normal.dot(right) * deg_to_rad(7.0)


## What this copy of the game draws for this player right now, for the killcam's
## recording (see Killcam): [feet, velocity, yaw, pitch, pose, animation flags,
## rope on, rope anchor, alive, drawn, eye height above the feet, weapon in hand,
## the grappling hook's rope]. That last one is null with no rope drawn, otherwise
## [where the hook is, slack, seconds since the shot, seconds since it pulled tight]:
## what HookRope drew it from, so the replay draws the same rope ("rope on" and
## "rope anchor" only say where the arm points).
## A body hidden only because remains took its place counts as drawn: the replay has
## remains of its own to put there (see KillcamView), or shows the body as it was.
func shown_state() -> Array:
	var pose := _my_pose() if is_local and motor else _remote_state
	var eye := motor.eye_height if is_local and motor else eye_for_pose(pose) - tuck_offset(pose)   # (a remote body is drawn lifted by its tuck)
	var hook := _hook_look
	if not hook.is_empty() and _first_person():
		# (Your own hook was drawn from your first-person arm; the replay shows your
		# body from outside, so it gets the hook as everyone else saw it.)
		var mine := motor.grapple
		hook = mine.line.look(mine.clock, robot.marker("grapple"), mine.rope_origin(self))
	var at := global_position
	if not is_local and _uncarried != Vector3.INF and _uncarried.distance_to(at) < 4.0:   # (a stale one, after a respawn: no)
		at = _uncarried
	return [at, velocity, _visual_yaw, _anim.pitch, pose, _anim.flags, _anim.grapple_on and alive,
		_anim.grapple_anchor, alive, (visual.visible or (_in_remains and not alive)) and not _awaiting_respawn, eye, robot.weapon if robot else "none",
		hook.slice(1) if not hook.is_empty() else null]


## Eye height above the feet for a pose (as sent in snapshots).
static func eye_for_pose(pose: int) -> float:
	if pose_state(pose) == MovementController.State.BELLY_SLIDE:
		return 0.55
	return 1.0 if pose_crouched(pose) else CameraRig.EYE_HEIGHT


## Where this player's feet were at time t (on this player's clock).
func position_at(t: float) -> Vector3:
	if not buffer.has_data():
		return global_position
	var s := buffer.sample(t)
	return s[0] + Vector3(0, tuck_offset(s[4]), 0)


func teleport(pos: Vector3, yaw: float) -> void:
	_fly_kick = 0.0
	_tug_by = 0
	if motor:
		motor.reset()
	global_position = pos
	velocity = Vector3.ZERO
	input.yaw = yaw
	input.pitch = 0.0


## Local: jump to `pos` keeping on the move (a blink). Others see it as a jump, not a
## dash across the map: the respawn count goes up, so they don't blend from where you
## were.
func warp(pos: Vector3, vel: Vector3, yaw: float) -> void:
	var from := global_position
	motor.grapple.reset()
	if motor.state == MovementController.State.MANTLE:
		motor.state = MovementController.State.AIR
	global_position = pos
	velocity = vel
	motor.warped = true   # off the floor you were on: no snapping back to it, no ground friction
	input.yaw = yaw
	_teleport_count += 1
	_send_timer = 0.0   # tell everyone at once
	_show_warp(from, pos)


## Would this body fit with its feet at `feet`, clear of the map?
func fits_at(feet: Vector3) -> bool:
	if _shape == null or not is_inside_tree():
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape.shape
	q.transform = Transform3D(Basis.IDENTITY, feet + _shape.position + Vector3(0, 0.04, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


# ---------------------------------------------------------------------------
# Mobility: the grapple or blink (see Mobility). The jetpack is everyone's, on Space.

## Change the tool on the mobility button (picked while waiting to respawn).
func set_mobility(id: String) -> void:
	mobility = Mobility.GRAPPLE if racing else Mobility.valid(id)
	if not is_local:
		return
	blink = Blink.new() if mobility == Mobility.BLINK else null
	if motor == null:
		return
	if not Mobility.is_grapple(mobility):
		motor.grapple.reset()


## 0..1 how ready the mobility tool is (the HUD).
func mobility_readiness() -> float:
	if mobility == Mobility.BLINK:
		return blink.readiness() if blink else 1.0
	var g := motor.grapple if motor else null
	if g and g.cooldown_left > 0.0:
		return 1.0 - g.cooldown_left / motor.tuning.grapple_cooldown
	return 1.0


## Where the mobility tool aims: the crosshair ray in third person, the eyes otherwise.
## Bots can pick a direction of their own (PlayerInput.mobility_dir).
func mobility_aim() -> Array:
	if input.mobility_dir != Vector3.ZERO:
		return [eye_position(), input.mobility_dir.normalized()]
	if input.aim_dir != Vector3.ZERO:
		return [input.aim_origin, input.aim_dir]
	return [eye_position(), Basis.from_euler(Vector3(input.pitch, input.yaw, 0.0)) * Vector3.FORWARD]


func _update_mobility(delta: float, pressed: bool) -> void:
	if blink:
		blink.update(delta)
		if Cheats.cooldowns_off() and not is_bot:
			blink.reset()
		if pressed:
			_try_blink()


func _try_blink() -> void:
	if not blink.ready():
		return
	var aim := mobility_aim()
	var dir: Vector3 = aim[1]
	var to := Blink.destination(self, _shape, dir)
	if to == Vector3.INF:
		sounds.grapple_missed()
		blink._gap = Blink.GAP
		return
	blink.charges -= 1
	blink._gap = Blink.GAP
	if DevArgs.sync_log:
		print("BLINK %d %.2f" % [peer_id, global_position.distance_to(to)])
	warp(to, Blink.carry(velocity, dir), input.yaw)


## What a blink looks and sounds like, here and (from their snapshots) on every other
## copy: a flash where it left from and where it arrived, and a trail of sparks.
func _show_warp(from: Vector3, to: Vector3) -> void:
	if not is_inside_tree():
		return
	var mid := Vector3(0, body_height() * 0.5, 0)
	var fx_parent: Node = Net.arena if Net.arena else get_parent()
	if not (rig and rig.first_person_amount() > 0.5):
		Blink.flash(fx_parent, from + mid)
		Blink.flash(fx_parent, to + mid)
	Blink.trail(fx_parent, from + mid, to + mid)
	if is_local and not is_bot:
		Sound.play("blink", 0.0, 0.05)
	else:
		Sound.play_at("blink", to + mid, "move", 0.0, 0.05)


## How tall the body's collision shape is right now (crouching, belly sliding...).
func body_height() -> float:
	return (_shape.shape as CapsuleShape3D).height if _shape else CAPSULE_HEIGHT


# ---------------------------------------------------------------------------
# Debug menu cheats (offline only, see Cheats)

## Noclip: fly through everything. WASD moves along the view, Space up, Ctrl / C down, Shift faster.
func _fly(delta: float) -> void:
	var look := Basis.from_euler(Vector3(input.pitch, input.yaw, 0.0))
	var dir := look * Vector3(input.move.x, 0.0, -input.move.y)
	if input.jump_held:
		dir += Vector3.UP
	if input.crouch:
		dir += Vector3.DOWN
	velocity = dir.limit_length(1.0) * (32.0 if input.sprint else 12.0)
	global_position += velocity * delta
	motor.state = MovementController.State.AIR


## A frozen bot: stands where it is and holds fire (it still falls and can be shot).
func _hold_still() -> void:
	input.move = Vector2.ZERO
	input.sprint = false
	input.jump_held = false
	input.crouch = false
	input.dive = false
	input.grapple = false
	input.grapple_pressed = false
	input.fire = false
	input.kick_pressed = false
	input.boost_pressed = false
	input.glide = false
	input.glide_pressed = false


# ---------------------------------------------------------------------------
# Scripted input for automated tests

func _scripted_input(delta: float) -> void:
	_scripted_time += delta
	var t := _scripted_time
	input.move = Vector2(0.0, 1.0)
	input.yaw = sin(t * 0.7) * 2.2 + t * 0.6
	input.sprint = fmod(t, 4.0) < 2.0
	if fmod(t, 1.7) < delta:
		input.jump_pressed = true
	if fmod(t + 1.3, 3.4) < delta:
		input.jump_pressed = true   # mid-air: flip
	if fmod(t + 2.5, 5.3) < delta:
		input.dive_pressed = true
	var glide_t := fmod(t + 3.1, 3.4)   # near the top of every other jump: glide for a moment
	input.glide = glide_t < 0.6
	if glide_t < delta:
		input.glide_pressed = true
	input.dive = fmod(t + 7.8, 10.6) < 1.4   # every other dive: keep holding it, to land in a belly slide
	# Crouch (or slide, when fast) for a moment every 7 s.
	var was_crouching := input.crouch
	input.crouch = fmod(t, 7.0) > 5.8
	input.crouch_pressed = input.crouch and not was_crouching
	input.fire = false
	# Every 5 s, swing from a high point in the middle for a moment (tests the grapple online).
	var swing_phase := fmod(t + float(peer_id % 7), 5.0)
	input.grapple = swing_phase < 1.3
	if swing_phase < delta:
		var to_tower: Vector3 = Net.arena.layout.swing_point - eye_position()
		input.yaw = atan2(-to_tower.x, -to_tower.z)
		input.pitch = atan2(to_tower.y, Vector2(to_tower.x, to_tower.z).length())
		input.grapple_pressed = true
	if DevArgs.scripted_fire:
		var target := _nearest_visible_opponent()
		if target:
			var aim_height := 1.65 if fmod(t, 4.0) < 2.0 else 1.0  # alternate head and body
			var to: Vector3 = target.global_position + Vector3(0, aim_height, 0) - eye_position()
			input.yaw = atan2(-to.x, -to.z)
			input.pitch = atan2(to.y, Vector2(to.x, to.z).length())
			input.move = Vector2(1.0 if fmod(t, 3.0) < 1.5 else -1.0, 0.3)  # strafe while shooting
			if weapon and weapon.data.is_melee():
				input.move = Vector2(0.0, 1.0)   # a blade: run straight at them
			input.fire = true
			if weapon and weapon.data.is_melee():
				input.fire = fmod(t, 1.6) < 1.1   # wind a swing up for a second, then let go
				if MeleeSwing.combo_length(weapon.data.id) > 2:   # a combo (Karate): a run of quick taps, then a full wind-up
					input.fire = fmod(t, 0.42) < 0.1 if fmod(t, 4.0) < 3.0 else fmod(t, 4.0) < 3.8
			elif weapon and weapon.data.is_blast():
				input.fire = fmod(t, 2.0) < 1.6   # the air cannon: charge it right up, then let go
			if fmod(t, 0.2) < delta and input.fire:
				input.fire_pressed = true  # click about 5 times a second
		if fmod(t, 6.0) < delta and weapon:
			weapon.start_reload()  # top up now and then (tests the reload animation online)
	if DevArgs.scripted_kicks:
		_scripted_kicks(t, delta)


func _scripted_kicks(t: float, delta: float) -> void:
	if fmod(t + 0.7, 3.1) < delta:
		input.boost_pressed = true   # rocket boots, toward wherever the script is running
	var g := motor.grapple
	if g.hooked_player():
		input.grapple = true
		input.jump_pressed = false   # a jump would let go of the rope
		if global_position.distance_to(g.target.global_position) < 9.0:
			input.kick_pressed = true   # flying kick
		return
	var target := _nearest_visible_opponent()
	if target == null:
		return
	var d := global_position.distance_to(target.global_position)
	if d < 2.6:
		var to := target.global_position + Vector3(0, 1.0, 0) - eye_position()
		input.yaw = atan2(-to.x, -to.z)
		input.kick_pressed = true
	elif d > 7.0 and d < 35.0 and g.ready_to_fire() and fmod(t + 2.0, 4.3) < 1.5:
		var to := Grapple.target_point(target) - eye_position()
		input.yaw = atan2(-to.x, -to.z)
		input.pitch = atan2(to.y, Vector2(to.x, to.z).length())
		input.grapple = true
		input.grapple_pressed = true


func _nearest_visible_opponent() -> Player:
	var best: Player = null
	var best_d := INF
	var space := get_world_3d().direct_space_state
	for p in get_parent().get_children():
		if p == self or not p is Player or not p.alive or not p.visual.visible:
			continue
		var target: Vector3 = p.global_position + Vector3(0, 1.0, 0)
		var ray := PhysicsRayQueryParameters3D.create(eye_position(), target, 1)
		if space.intersect_ray(ray):
			continue  # behind a wall
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


# ---------------------------------------------------------------------------
# The grappling hook's rope (see Grapple, HookLine and HookRope)

## Draws the grappling hook's rope and hook from `look` (HookLine.look; [] for none),
## and plays the sounds of whatever has just happened to it.
func _draw_hook(look: Array) -> void:
	_hook_look = look
	var stage: int = look[0] if not look.is_empty() else HookLine.OFF
	if stage != _hook_stage:
		sounds.hook_stage(_hook_stage, stage, look[1] if not look.is_empty() else global_position)
		_hook_stage = stage
	if look.is_empty():
		if _hook_rope:
			_hook_rope.hide_line()
		return
	if _hook_rope == null:
		_hook_rope = HookRope.new()
		add_child(_hook_rope)
	_hook_rope.show_look(rope_origin(), look)


## Remote: which of their shots is on screen at their time `t` (null: none yet).
func _hook_shot_at(t: float) -> HookLine:
	if _hook_line and t >= _hook_line.t_launch:
		return _hook_line
	return _hook_old


## Remote: a shot hooked on a player ends on that player's chest as this copy draws
## them (INF: it is on a surface, or they are not to be seen: use the shot's own anchor).
func _hook_anchor(shot: HookLine) -> Vector3:
	if shot == null or shot.target_id == 0 or Net.arena == null:
		return Vector3.INF
	var on: Player = Net.arena.get_player(shot.target_id)
	return Grapple.target_point(on) if on and on.visible_in_world() else Vector3.INF


## Remote: a hook still flying on our screen, with no news yet of where it stopped
## (a late or lost packet), is held at the first wall on its way instead of being
## drawn flying on through it. The news, when it comes, takes over (HookLine.absorb).
func _guard_hook(shot: HookLine, t: float) -> void:
	if shot == null or shot.t_stop != INF or shot.stage(t) != HookLine.FLYING or not is_inside_tree():
		return
	var from := shot.flight_pos(float(_hook_guard[1])) if int(_hook_guard[0]) == shot.seq else shot.origin
	_hook_guard = [shot.seq, t]
	var to := shot.flight_pos(t)
	if from.distance_squared_to(to) < 0.0001:
		return
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	if not hit.is_empty():
		shot.hold = shot.origin.distance_to(hit.position)


## --sync-log, your own hook (or your bot's): each moment of the shot as it happens,
## and where the hook is every step, for tests/check_hook.py.
func _log_own_hook(hook: Grapple) -> void:
	var line := hook.line
	var known := int(_hook_logged[1]) if int(_hook_logged[0]) == line.seq else 0
	if line.moments() != known:
		_log_hook("SELF %d" % peer_id, line, known, Net.now() - hook.clock)
		_hook_logged = [line.seq, line.moments()]
	# (As everyone else sees it leave you, not from your first-person arm: that one is
	# only on your own screen. And with the rope's near end at the chest: every copy
	# draws it at the wrist of the body as it poses it, so the hook coming back is
	# compared by where it is on its way to the body.)
	var chest := hook.rope_origin(self)
	var look := line.look(hook.clock, chest, chest) if alive else []
	if not look.is_empty():
		var hp: Vector3 = look[1]
		print("HOOK SELF %d %d %.4f %d %.3f %.3f %.3f %.3f" % [peer_id, line.seq, Net.now(), look[0], hp.x, hp.y, hp.z, look[2]])


## Prints the moments of `line` not yet printed (`known`: HookLine.moments() before),
## as times on the clock of the player whose hook it is (`shift` takes the line's own
## times to that clock).
func _log_hook(who: String, line: HookLine, known: int, shift: float) -> void:
	var names := ["launch", "stop", "taut", "release"]
	var times := [line.t_launch, line.t_stop, line.t_taut, line.t_release]
	for i in 4:
		if line.moments() & (1 << i) != 0 and known & (1 << i) == 0:
			var extra := (" caught %d" % line.target_id if line.caught else " missed") if i == 1 else ""
			if i == 0 and line.back:
				extra = " back"   # (a hook that caught on its way back: its record begins as it set off)
			print("HOOKEV %s %d %s %.4f%s" % [who, line.seq, names[i], float(times[i]) + shift, extra])



# ---------------------------------------------------------------------------
# Rocket boots: a burst of flame from both feet

func _build_flame() -> void:
	_flame = Node3D.new()
	_flame.visible = false
	visual.add_child(_flame)
	var outer := StandardMaterial3D.new()
	outer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer.albedo_color = Color(1.0, 0.55, 0.15, 0.8)
	outer.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var core := StandardMaterial3D.new()
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.albedo_color = Color(1.0, 0.95, 0.7, 0.9)
	core.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	for side in [-1.0, 1.0]:
		for layer in 2:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.11 if layer == 0 else 0.06
			cone.bottom_radius = 0.0
			cone.height = 0.75 if layer == 0 else 0.45
			cone.radial_segments = 8
			cone.rings = 1
			cone.material = outer if layer == 0 else core
			var m := MeshInstance3D.new()
			m.mesh = cone
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.position = Vector3(side * 0.14, -cone.height * 0.5, 0.0)
			_flame.add_child(m)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.omni_range = 4.0
	light.light_energy = 2.0
	light.position = Vector3(0, -0.2, 0)
	_flame.add_child(light)
	_flame.position = Vector3(0, 0.08, 0)


func _update_flame(delta: float) -> void:
	if _flame == null:
		return
	_flame_t = maxf(_flame_t - delta, 0.0)
	var jet := RobotAnimInput.jetpack_of(_anim.flags) and alive
	if jet:
		_flame_t = maxf(_flame_t, 0.3)   # the jetpack: the boot flames burn for as long as it fires
		if not _seen_jet and visual.visible:
			if sounds.own:
				Sound.play("rocket_boost", -4.0, 0.08)
			else:
				Sound.play_at("rocket_boost", global_position + Vector3(0, 0.3, 0), "move", -4.0, 0.08)
	_seen_jet = jet
	_flame.visible = _flame_t > 0.0 and alive and visual.visible
	if not _flame.visible:
		return
	var u := _flame_t / 0.45
	var length := maxf(u * (0.85 + 0.3 * randf()), 0.05)
	# Point the flames back the way the burst pushes you (away from where you are going).
	var aim := Vector3.DOWN
	if velocity.length() > 1.0:
		aim = visual.global_transform.basis.inverse() * -velocity.normalized()
	var turn := Quaternion(Vector3.DOWN, aim.normalized()) if aim.normalized().dot(Vector3.UP) < 0.999 else Quaternion(Vector3.RIGHT, PI)
	_flame.basis = Basis(turn) * Basis.from_scale(Vector3(1.0, length, 1.0))

