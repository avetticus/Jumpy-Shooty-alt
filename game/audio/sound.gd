extends Node
## Every sound effect in the game. Autoload at /root/Sound.
##
## The sounds themselves are made by code (tools/audio/make_sfx.py) and live in
## game/audio/sfx/. This script plays them:
##  - play(): sounds that belong to you (your gun, your steps, menus, hit markers).
##    Not positional: they sit in the middle of your head.
##  - play_at(): everyone else's sounds, placed in the world (3D), so you can hear
##    where a fight is. They get quieter and duller with distance.
## Names ending in a number ("step_1".."step_6") are variants: play("step") picks one.
##
## Buses: Master <- Effects (all of this) and Master <- Music (the songs: see Music). The
## Audio sliders in Settings set their volumes. A limiter on Master keeps gunfire
## from clipping.
##
## It also hooks every menu button by itself (hover and click sounds) and plays the
## combat feedback that comes from the host's match events (hit markers, kills, hurt).
##
## Capturing (a killcam saved as a video, see KillcamExport): between capture_begin()
## and capture_end() nothing plays; each sound is noted instead (when, what, how loud,
## where, and where the ears were), for the video's sound track.

const SFX_DIR := "res://game/audio/sfx/"
const BUS_SFX := "Effects"
const BUS_MUSIC := "Music"


## How far away a sound carries (metres): [full volume within, silent beyond].
const RANGE := {
	"fire": [14.0, 220.0], "far": [60.0, 320.0], "impact": [4.0, 60.0], "whiz": [2.0, 12.0],
	"move": [3.0, 45.0], "step": [2.5, 38.0], "gun": [2.0, 24.0], "body": [5.0, 70.0],
}
## Beyond this distance another player's shot also plays the gun's distant version.
const FAR_FROM := 28.0
## Buttons with these labels play the "back" sound.
const BACK_BUTTONS := ["back", "resume", "leave lobby", "leave match", "main menu"]
const POOL_2D := 24
const POOL_3D := 64

var _streams := {}     # name -> AudioStream
var _variants := {}    # base name -> [names]
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _next_2d := 0
var _next_3d := 0
var _last_played := {}   # name -> time, to stop a flood of the same sound in one moment
var _head_kill := {}     # victim id -> my last hit on them was a headshot
## No sound card (headless test runs and servers): everything runs and logs, nothing plays.
var silent := DisplayServer.get_name() == "headless"
## While capturing: the sounds noted so far (see capture_begin).
var captured: Array = []
var _capturing := false
var _capture_time := 0.0
var _capture_ears := Transform3D()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # menus over a paused game still click
	_setup_buses()
	_load_streams()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_pool_2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = BUS_SFX
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.attenuation_filter_db = -18.0
		p.panning_strength = 1.0
		add_child(p)
		_pool_3d.append(p)
	Settings.changed.connect(apply_volumes)
	apply_volumes()
	get_tree().node_added.connect(_on_node_added)
	Net.match_started.connect(func(): play("match_start"))
	Match.match_over.connect(func(_r): play("match_end"))
	Match.player_hit.connect(_on_player_hit)
	Match.player_died.connect(_on_player_died)
	Match.player_respawned.connect(_on_player_respawned)
	Match.melee_landed.connect(_on_melee_landed)
	Match.ground_slammed.connect(_on_ground_slammed)
	Match.slammed.connect(_on_slammed)


# ---------------------------------------------------------------------------
# Volume

func _setup_buses() -> void:
	for bus_name in [BUS_SFX, BUS_MUSIC]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")
	var sfx := AudioServer.get_bus_index(BUS_SFX)
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var comp := AudioEffectCompressor.new()   # glues overlapping gunfire together
		comp.threshold = -14.0
		comp.ratio = 3.0
		comp.attack_us = 800.0
		comp.release_ms = 120.0
		AudioServer.add_bus_effect(sfx, comp)
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var limit := AudioEffectHardLimiter.new()
		limit.ceiling_db = -0.5
		AudioServer.add_bus_effect(master, limit)


## The Audio sliders (Settings) on the buses. Called whenever a setting changes.
func apply_volumes() -> void:
	_set_bus_volume("Master", Settings.master_volume)
	_set_bus_volume(BUS_SFX, Settings.sfx_volume)
	_set_bus_volume(BUS_MUSIC, Settings.music_volume)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i == -1:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(i, linear <= 0.001)


# ---------------------------------------------------------------------------
# Playing

func _load_streams() -> void:
	var dir := DirAccess.open(SFX_DIR)
	var names: Array[String] = []
	if dir:
		for f in dir.get_files():
			# Exported games keep only the imported copies: "x.wav.import" stands for "x.wav".
			f = f.trim_suffix(".import")
			if f.ends_with(".wav") and not names.has(f.get_basename()):
				names.append(f.get_basename())
	for sound in names:
		var stream := load(SFX_DIR + sound + ".wav") as AudioStream
		if stream == null:
			continue
		_streams[sound] = stream
		var parts := sound.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			if not _variants.has(parts[0]):
				_variants[parts[0]] = []
			_variants[parts[0]].append(sound)


func has_sound(sound: String) -> bool:
	return _streams.has(sound) or _variants.has(sound)


func stream(sound: String) -> AudioStream:
	for hidden in WeaponData.HIDDEN:   # the Golden Gun sounds like the revolver it looks like
		if hidden in sound:
			sound = sound.replace(hidden, WeaponData.look_of(hidden))
	if _variants.has(sound):
		var list: Array = _variants[sound]
		return _streams[list[randi() % list.size()]]
	return _streams.get(sound)


func _volume_of(sound: String) -> float:
	if SfxList.VOLUME.has(sound):
		return SfxList.VOLUME[sound]
	var base := sound.rsplit("_", true, 1)[0]
	return SfxList.VOLUME.get(base, -10.0)


## True if this sound already started in the last `gap` seconds (stops pile-ups,
## for example ten shotgun pellets hitting one wall).
func _too_soon(key: String, gap: float) -> bool:
	var now := _capture_time if _capturing else Time.get_ticks_msec() / 1000.0
	if now - _last_played.get(key, -10.0) < gap:
		return true
	_last_played[key] = now
	return false


## A sound of your own: not positional.
func play(sound: String, volume_db: float = 0.0, pitch_jitter: float = 0.0) -> AudioStreamPlayer:
	var s := stream(sound)
	if s == null:
		return null
	if _capturing:
		captured.append({"t": _capture_time, "stream": s, "db": _volume_of(sound) + volume_db,
			"pitch": 1.0 + randf_range(-pitch_jitter, pitch_jitter)})
		return null
	if DevArgs.sound_log:
		print("SFX %s" % sound)
	if silent:
		return null
	var p := _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D
	p.stream = s
	p.volume_db = _volume_of(sound) + volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()
	return p


## A sound in the world at `pos`. `kind` picks how far it carries (see RANGE).
func play_at(sound: String, pos: Vector3, kind: String = "move", volume_db: float = 0.0, pitch_jitter: float = 0.0) -> AudioStreamPlayer3D:
	var s := stream(sound)
	if s == null:
		return null
	if _capturing:
		captured.append({"t": _capture_time, "stream": s, "db": _volume_of(sound) + volume_db,
			"pitch": 1.0 + randf_range(-pitch_jitter, pitch_jitter), "at": pos, "range": RANGE.get(kind, RANGE.move),
			"ears": _capture_ears})
		return null
	if DevArgs.sound_log:
		print("SFX3D %s %.1f" % [sound, pos.distance_to(listener_position())])
	if silent:
		return null
	var p := _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D
	var r: Array = RANGE.get(kind, RANGE.move)
	p.stream = s
	p.unit_size = r[0]
	p.max_distance = r[1]
	p.attenuation_filter_cutoff_hz = 9000.0 if kind in ["fire", "far"] else 6000.0
	p.volume_db = _volume_of(sound) + volume_db
	p.max_db = 3.0
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.global_position = pos
	p.play()
	return p


## Note sounds instead of playing them, as if they happened `time` seconds into a video
## heard from `ears` (see `captured`). Until capture_end().
func capture_begin(time: float, ears: Transform3D) -> void:
	_capturing = true
	_capture_time = time
	_capture_ears = ears


func capture_end() -> void:
	_capturing = false


## Where the ears are: the camera in a match, or nowhere (menus).
func listener_position() -> Vector3:
	if _capturing:
		return _capture_ears.origin
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else Vector3(INF, INF, INF)


# ---------------------------------------------------------------------------
# Guns

## A gun going off. Your own shot plays the wide first-person version; anyone
## else's is placed at their muzzle, with a distant echo layer when they are far away.
func gun_fire(weapon_id: String, at: Vector3, own: bool) -> void:
	if own:
		play("fire_%s_fp" % weapon_id, 0.0, 0.025)
		return
	play_at("fire_" + weapon_id, at, "fire", 0.0, 0.03)
	var d := at.distance_to(listener_position())
	if d > FAR_FROM and d < INF:
		play_at("far_" + weapon_id, at, "far", lerpf(-8.0, 0.0, clampf((d - FAR_FROM) / 60.0, 0.0, 1.0)), 0.03)


## Where a shot's pellets ended: wall impacts, hits on bodies, and a whiz if a round
## passed close to your head. `own`: you fired it (no whiz).
func shot_landed(muzzle: Vector3, ends: PackedVector3Array, hits: Array, own: bool) -> void:
	var walls := 0
	var bodies := 0
	for i in ends.size():
		var hit: bool = hits[i] if i < hits.size() else false
		if hit and bodies < 2:
			bodies += 1
			play_at("impact_body", ends[i], "body", -2.0 * (bodies - 1), 0.06)
		elif not hit and walls < 3:   # a shotgun blast: a few impacts, not ten
			walls += 1
			if not _too_soon("impact%d" % walls, 0.02):
				play_at("impact_wall", ends[i], "impact", -3.0 * (walls - 1), 0.08)
				if randf() < 0.14:
					play_at("ricochet", ends[i], "impact", 0.0, 0.1)
	if own:
		return
	var ear := listener_position()
	if ear.x == INF:
		return
	for i in ends.size():
		var hit: bool = hits[i] if i < hits.size() else false
		var close := Geometry3D.get_closest_point_to_segment(ear, muzzle, ends[i])
		var d := close.distance_to(ear)
		# Passed by (not ending on you, not from right beside you), within a few metres.
		if d < 3.0 and close.distance_to(ends[i]) > 1.0 and close.distance_to(muzzle) > 4.0 and not hit:
			if not _too_soon("whiz", 0.08):
				play_at("whiz", close, "whiz", lerpf(0.0, -8.0, d / 3.0), 0.08)
			break


# ---------------------------------------------------------------------------
# Combat feedback (from the host's match events)

func _on_player_hit(shooter: int, target: int, _damage: float, headshot: bool) -> void:
	var me := Net.my_id()
	if shooter == me and target != me:
		_head_kill[target] = headshot
		if not _too_soon("hitmarker", 0.03):
			play("hitmarker_head" if headshot else "hitmarker", 0.0, 0.02)
	elif target == me:
		play("hurt_head" if headshot else "hurt", 0.0, 0.05)


func _on_player_died(victim: int, killer: int) -> void:
	var me := Net.my_id()
	if killer == me and victim != me:
		play("kill_head" if _head_kill.get(victim, false) else "kill")
	if victim == me:
		play("death")
	elif Net.arena:
		var p: Player = Net.arena.get_player(victim)
		if p:
			play_at("death", p.global_position + Vector3(0, 1.0, 0), "body", -2.0, 0.05)


## A melee blow landed: a clang where each one struck (the hammer's is a heavy crash).
## The more the swing was wound up, the deeper and louder it lands, and a blow wound
## up enough to be the weapon's heavy one has a thump under it.
func _on_melee_landed(attacker: int, weapon_id: String, points: PackedVector3Array) -> void:
	var by: Player = Net.arena.get_player(attacker) if Net.arena else null
	var power := by.swing_power() if by and weapon_id != "kick" and weapon_id != "flying_kick" else 0.0
	for i in mini(points.size(), 2):
		var hit: String = {"hammer": "hammer_hit", "flying_kick": "hammer_hit", "axe": "hammer_hit", "bat": "bat_hit",
			"brass_knuckles": "punch_hit", "mace": "hammer_hit", "wrench": "bat_hit", "scythe": "melee_hit",
			"karate": "punch_hit"}.get(weapon_id, "melee_hit")
		var clang := play_at(hit, points[i], "body", -2.0 * i + lerpf(-1.5, 2.0, power), 0.06)
		if clang:
			clang.pitch_scale *= lerpf(1.04, 0.88, power)
		if power >= MeleeSwing.HEAVY_AT and i == 0:
			play_at("heavy_hit", points[i], "body", lerpf(-4.0, 0.0, power), 0.05)


## A ground slam landed (see GroundSlam): a boom from where it struck, bigger the harder it was.
func _on_ground_slammed(_attacker: int, _weapon_id: String, at: Vector3, power: float, _points: PackedVector3Array) -> void:
	var boom := play_at("ground_slam", at + Vector3(0, 0.3, 0), "body", lerpf(-5.0, 2.0, power), 0.05)
	if boom:
		boom.pitch_scale *= lerpf(1.1, 0.9, power)


## Someone crashed into a wall hard enough to hurt.
func _on_slammed(id: int, where: Vector3, speed: float) -> void:
	var loud := clampf((speed - Match.SLAM_SPEED) / 12.0, 0.0, 1.0)
	if id == Net.my_id():
		play("slam", lerpf(-5.0, 0.0, loud), 0.05)
	else:
		play_at("slam", where, "body", lerpf(-5.0, 0.0, loud), 0.05)


func _on_player_respawned(id: int, _spawn: int) -> void:
	if id == Net.my_id():
		play("respawn")


# ---------------------------------------------------------------------------
# Menus: every button and slider gets sounds without each menu asking for them.
# A button can choose its click with set_meta("sfx", "back" | "confirm" | "select" | "none").

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var b := node as BaseButton
		b.mouse_entered.connect(_on_button_hover.bind(b))
		if b is OptionButton:
			(b as OptionButton).item_selected.connect(func(_i): play("ui_click"))
			b.pressed.connect(func(): play("ui_tick"))
		else:
			b.pressed.connect(_on_button_pressed.bind(b))
	elif node is Range and node is Slider:
		(node as Slider).value_changed.connect(_on_slider_changed.bind(node))


func _on_button_hover(b: BaseButton) -> void:
	if not b.disabled and str(b.get_meta("sfx", "")) != "none" and not _too_soon("ui_hover", 0.03):
		play("ui_hover", 0.0, 0.03)


func _on_button_pressed(b: BaseButton) -> void:
	var kind := str(b.get_meta("sfx", ""))
	if kind == "none":
		return
	if kind == "":
		if b is CheckButton or b is CheckBox:
			kind = "toggle"
		elif b is Button and (b as Button).text.strip_edges().to_lower() in BACK_BUTTONS:
			kind = "back"
		elif b is Button and (b as Button).theme_type_variation == "PrimaryButton":
			kind = "confirm"
		else:
			kind = "click"
	play("ui_" + kind)


func _on_slider_changed(_value: float, slider: Slider) -> void:
	if slider.is_visible_in_tree() and not _too_soon("ui_tick", 0.04):
		play("ui_tick", 0.0, 0.02)


## Quitting: let go of every sound so none is still playing as the game shuts down.
func _exit_tree() -> void:
	stop_all()


func stop_all() -> void:
	for p in _pool_2d:
		p.stop()
		p.stream = null
	for p in _pool_3d:
		p.stop()
		p.stream = null
