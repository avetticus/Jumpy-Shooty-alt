class_name Hud
extends CanvasLayer
## In-game HUD. Two layouts show your own state: Twin arcs (health and ammo as arcs
## either side of the crosshair, moves under it) and Clean (health and ammo in the
## bottom corners). Settings picks one for first person and one for third person.
## Shared by both: the score bar, kill feed, crosshair with grapple ring, hit
## markers and damage numbers, damage direction arrows, the low-health edge, the
## kill confirmation, the death screen and the Tab scoreboard.
## Drawn in code; see HudArcs and HudClean for the layouts and HudStyle for the look.
##
## Settings → HUD tunes it (see HudConfig): the scale and opacity apply to everything
## you see while playing (the crosshair has its own size and stays opaque), drawn as
## if the screen were smaller (or bigger) and scaled to fit, so the middle stays in
## the middle and the corners in the corners. The full-screen pages (the killcam,
## the death screen, the Tab scoreboard) are never scaled or faded.
##
## While you wait to respawn the screen has two columns that cannot overlap: who got
## you, the countdown and the weapons to come back with on the left, the scoreboard
## on the right.

const FEED_LIFETIME := 6.0
const FEED_MAX := 8   ## the most the kill feed keeps; Settings → HUD picks how many show (see _age)
const HIT_TIME := 0.2
const KILL_HIT_TIME := 0.4
const NUMBER_TIME := 0.8
const ARROW_TIME := 1.6
const CONFIRM_TIME := 1.8
## Your kill's killcam points: by the crosshair one line at a time, the total for
## POINTS_TOTAL seconds, then each part ("+60  HEADSHOT") for POINTS_STEP; and the
## whole list, bottom left, for POINTS_TIME, to read at leisure.
const POINTS_TOTAL := 0.5
const POINTS_STEP := 0.225
const POINTS_TIME := 6.0
const POINTS_LIST_BOTTOM := 168.0   ## the list's last line, up from the bottom: above the Clean layout's moves
const DEATH_W := 600.0          ## the death screen's left column
const BOARD_W := 780.0          ## the scoreboard
const DEATH_GAP := 36.0
const DEATH_TOP := 104.0
const RESPAWN_GRACE := 0.5      ## the death screen ignores the respawn key for this long
                                ## (a press meant to skip the killcam does not respawn you too)

## Everything the layouts show about the local player, filled in once per frame.
class View:
	var hp := 100.0
	var hp_trail := 100.0       ## health a moment ago: the gap shows as a red chunk that drains away
	var ammo := 0
	var magazine := 12
	var reloading := false
	var reload := 0.0           ## 0..1
	var weapon := ""
	var gun := "pistol"         ## WeaponData id
	var crosshair := "cross"
	var spread_px := 0.0        ## the gun's spread on screen, in pixels from the middle
	var ready := 1.0            ## 0..1: the pump or bolt is being worked (slow guns only)
	var character := ""
	var speed := 0.0            ## horizontal, m/s
	var move_state := ""
	## [label, key, readiness 0..1, active] for grapple, dive, flip, slide, rocket boots, kick
	var moves: Array = []
	var race := false           ## a race: no health or ammo to show
	var melee := false          ## a sword, hammer or dagger: no ammo, a swing that recharges
	var swing := 1.0            ## melee: 0..1, ready to swing again at 1 (the air cannon: ready to charge)
	var blast := false          ## the air cannon: no ammo, a charge instead
	var charge := -1.0          ## the air cannon: how charged, 0..1 (-1: not charging)

enum { GRAPPLE_NO_TARGET, GRAPPLE_IN_RANGE, GRAPPLE_COOLING, GRAPPLE_ON, GRAPPLE_FLYING }

var view := View.new()
var style := "arcs"
var grapple := GRAPPLE_NO_TARGET
var grapple_cooldown := 0.0     ## 1 = just let go, 0 = ready
var tether := 0.0
## The mobility tool (see Mobility). The jetpack's fuel (on Space when the host turns
## it on: 1 = full).
var mobility := Mobility.GRAPPLE
var jet_fuel := 1.0
const JET_COLOR := Color(0.25, 0.7, 1.0)   ## the jetpack's fuel arc, when not low

var _root: Control
var _flash: ColorRect
var _vignette: TextureRect
var _layout: Control
var _screens: Control           ## the killcam, the death screen, world markers: never scaled or faded
var _overlay: Control           ## the rest of the HUD: scaled and faded with the layout
var _cross: Control             ## the crosshair, on top: never faded
var _scoreboard: PanelContainer
var _score_rows: VBoxContainer
var _score_title: Label

var _feed: Array = []           # {killer, victim, head, age, gun (HudStyle.kill_icon), wall (into a wall), how}
var _numbers: Array = []        # {value, head, age, x}
var _arrows: Array = []         # {from: Vector3, age}
var _hit_time := 0.0
var _hit_kind := "hit"          # hit, head, kill
var _confirm := {}              # {name, age}
var _promo := {}                # Gun Game: {text, sub, age}: you just moved up (or down) the ladder
var _points := {}               # your last kill's killcam score: {total, parts (KillScore.breakdown), age}
var _last_head := {}            # target id -> was the last hit on them a headshot
var _dead := false
var _killer := 0
var _killer_hp := 0.0
var _killer_dist := -1.0
var _killed_by_head := false
var _killed_how := ""            # how they got you, for the death screen (see death_how)
var _killer_view: RobotPreview   # the robot that got you, on the death screen
var _movement_tag: Label   # "Movement: Variant B" in a corner while the A/B variant is on
var _respawn_left := 0.0
var _screen_age := 0.0          # how long the death screen has been up (not the killcam)
var _asked := false             # asked to respawn (Match.request_respawn)
var _pulse := 0.0
var _board_age := 0.0
var _race: HudRace
var _teams: HudTeams   ## team modes: the score bar, objective markers and banners
## You are watching (Net.spectating): no health, gun or crosshair; who is winning,
## the kill feed and how to fly instead.
var spectating := false
## Search and Destroy, out for the round: who you are watching (Arena.follow_cam), or "".
var follow_name := ""


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.make_theme()
	add_child(_root)

	_flash = _full_rect(ColorRect.new())
	_flash.color = Color(0.9, 0.05, 0.05, 0.0)
	_vignette = _full_rect(TextureRect.new())
	_vignette.texture = _vignette_texture()
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.modulate.a = 0.0
	_layout = _full_rect(Control.new())
	_layout.draw.connect(_draw_layout)
	_screens = _full_rect(Control.new())
	_screens.draw.connect(_draw_screens)
	_overlay = _full_rect(Control.new())
	_overlay.draw.connect(_draw_overlay)
	_cross = _full_rect(Control.new())
	_cross.draw.connect(_draw_cross)
	_killer_view = RobotPreview.new(Vector2(150, 190), 1.15)
	_killer_view.turn = false
	_killer_view.visible = false
	_root.add_child(_killer_view)
	_movement_tag = Label.new()
	_movement_tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_movement_tag.position = Vector2(12, 8)
	_movement_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_movement_tag.add_theme_font_size_override("font_size", 14)
	_movement_tag.add_theme_color_override("font_color", UiKit.TEXT_DIM)
	_movement_tag.visible = false
	_root.add_child(_movement_tag)
	_build_scoreboard()
	_race = HudRace.new()
	_teams = HudTeams.new()
	Teams.changed.connect(_refresh_scoreboard)
	Race.changed.connect(_refresh_scoreboard)

	Match.state_changed.connect(_refresh_scoreboard)
	Match.player_hit.connect(_on_hit)
	Match.player_died.connect(_on_died)
	Match.player_respawned.connect(_on_respawned)
	Match.gun_game_level.connect(_on_gun_game_level)
	Match.dummy_hit.connect(_on_dummy_hit)
	Match.golden_gun_passed.connect(_on_golden_gun_passed)
	Match.kill_scored.connect(_on_kill_scored)


## 0..1: how much of the HUD shows (the end of a match fades it out, see MatchEndFade).
func set_fade(alpha: float) -> void:
	_root.modulate.a = alpha


func _full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(c)
	return c


## Red at the screen edges, clear in the middle (shown at low health).
func _vignette_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(0.75, 0.05, 0.05, 0.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(0.75, 0.05, 0.05, 0.55))
	g.add_point(0.55, Color(0.75, 0.05, 0.05, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.15, 0.5)
	t.width = 256
	t.height = 256
	return t


# ---------------------------------------------------------------------------
# Every frame

func set_players(_players: Dictionary) -> void:
	_refresh_scoreboard()


func update_local(p: Player) -> void:
	var delta := get_process_delta_time()
	var variant := p.motor.tuning.variant if p.motor else MovementTuning.DEFAULT_VARIANT
	_movement_tag.visible = variant != MovementTuning.DEFAULT_VARIANT   # testers always know which one they are on
	_movement_tag.text = "Movement: " + MovementTuning.variant_name(variant)
	var me := p.peer_id
	style = Settings.hud_style()
	_pulse += delta

	var v := view
	v.hp = Match.health.get(me, Match.MAX_HEALTH)
	v.hp_trail = maxf(v.hp, move_toward(v.hp_trail, v.hp, delta * (0.0 if _hit_recently() else 60.0)))
	v.character = Characters.name_of(Net.player_character(me))
	if p.weapon:
		v.weapon = p.weapon.data.display_name
		v.ammo = p.weapon.ammo
		v.magazine = p.weapon.data.magazine
		v.reloading = p.weapon.is_reloading()
		v.reload = p.weapon.reload_progress()
		var data := p.weapon.data
		v.gun = data.id
		v.crosshair = data.crosshair
		var cam := get_viewport().get_camera_3d()
		var fov := cam.fov if cam else 75.0
		v.spread_px = tan(deg_to_rad(data.spread_degrees * p.spread_scale())) / tan(deg_to_rad(fov) * 0.5) * get_viewport().get_visible_rect().size.y * 0.5
		v.ready = 1.0 - p.weapon.cooldown() / data.fire_interval if data.fire_interval >= 0.5 else 1.0
		v.melee = data.is_melee()
		v.swing = 1.0 - p.weapon.cooldown() / data.fire_interval if data.fire_interval > 0.0 else 1.0
		v.blast = data.is_blast()
		v.charge = p.blast_charge()
	else:   # Deathmatch, empty hands: shown like a blade (no ammo), the kick is the weapon
		v.weapon = "Unarmed"
		v.gun = "none"
		v.crosshair = "dot"
		v.melee = true
		v.blast = false
		v.swing = p.kick_readiness()
		v.reloading = false
		v.ready = 1.0
	v.race = Race.active
	v.speed = Vector2(p.velocity.x, p.velocity.z).length()
	v.move_state = MovementController.State.keys()[p.motor.state].replace("_", " ")

	var g := p.motor.grapple
	tether = g.length if g.attached else 0.0
	mobility = p.mobility
	jet_fuel = p.jetpack.fuel if p.jetpack else 1.0   # (none unless the host turned it on, and never in a race)
	if not Mobility.is_grapple(mobility):
		grapple = GRAPPLE_NO_TARGET
	elif g.attached:
		grapple = GRAPPLE_ON
	elif g.busy():
		grapple = GRAPPLE_FLYING   # the hook is on its way, or the slack is coming in
	elif g.cooldown_left > 0.0:
		grapple = GRAPPLE_COOLING
		grapple_cooldown = g.cooldown_left / p.motor.tuning.grapple_cooldown
	elif p.alive and not g.find_target(p, p.input).is_empty():
		grapple = GRAPPLE_IN_RANGE
	else:
		grapple = GRAPPLE_NO_TARGET
	var mt := p.motor.tuning
	v.moves = [[Mobility.hud_label(mobility), _key_label("grapple", "MMB"), p.mobility_readiness(), grapple == GRAPPLE_ON or grapple == GRAPPLE_FLYING]]
	if mt.ctrl_moves:   # Variant B: Ctrl dives forward and slides backward
		v.moves.append(["DIVE", "CTRL", p.motor.dive_readiness(), false])
	else:
		v.moves.append(["DIVE", "Q", p.motor.dive_readiness(), false])
	if mt.flips_on and not mt.space_boost:
		v.moves.append(["FLIP", "SPACE", p.motor.flip_readiness(), false])
	if mt.glides_on:
		v.moves.append(["GLIDE", _key_label("glide", "ALT"), p.motor.glide_readiness(), p.motor.state == MovementController.State.GLIDE])
	v.moves.append(["SLIDE", "CTRL" if mt.ctrl_moves else "C", p.motor.slide_boost_readiness(), false])
	v.moves.append(["BOOST", "SPACE" if mt.space_boost else "E", p.motor.boost_readiness(), p.motor.since_boost < 0.3])
	if not Race.active:
		v.moves.append(["KICK", "F", p.kick_readiness(), p.flying_kick()])
		if p.weapon and p.weapon.data.is_melee():
			v.moves.append(["SLAM", "C", p.ground_slam_readiness(), p.ground_slamming()])

	_age(delta)
	_teams.age(delta)
	if _respawn_left > 0.0:
		_respawn_left = maxf(_respawn_left - delta, 0.0)
	var watching := _dead and Killcam.watching()   # the killcam has the screen while it plays
	_screen_age = _screen_age + delta if _dead and not watching else 0.0
	if _dead and not _asked and _respawn_left <= 0.0 and DevArgs.auto_respawn():
		_ask_respawn()   # tests: nobody is there to press a key
	_scoreboard.visible = Input.is_action_pressed("scoreboard") or (_dead and not watching and follow_name == "")
	_killer_view.visible = _dead and _killer != 0 and not watching and follow_name == ""
	if _scoreboard.visible:
		_place_scoreboard()
		_board_age += delta
		if _board_age > 0.5:   # keeps the clock and ping in its title current
			_board_age = 0.0
			_refresh_scoreboard()
	_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 1.2)
	if Race.active:
		_race.age(delta)
		_flash.color = Color(1, 1, 1, _race.flash())
	var low := p.alive and v.hp <= HudStyle.LOW_HEALTH
	var pulse := 0.75 + 0.25 * sin(_pulse * 5.0)
	_vignette.modulate.a = move_toward(_vignette.modulate.a, pulse if low else 0.0, delta * 3.0)
	_layout.visible = not _dead and not _scoreboard.visible
	_layout.queue_redraw()
	_redraw()


## Redraws everything but the layout, at the opacity Settings → HUD asks for.
func _redraw() -> void:
	_layout.modulate.a = Settings.hud.opacity
	_overlay.modulate.a = Settings.hud.opacity
	_screens.queue_redraw()
	_overlay.queue_redraw()
	_cross.queue_redraw()


## Spectating: called every frame instead of update_local.
func set_spectating(on: bool) -> void:
	spectating = on
	_dead = false
	_killer_view.visible = false
	_vignette.modulate.a = 0.0
	_flash.color.a = 0.0
	_layout.visible = not on
	_redraw()


func update_spectator() -> void:
	var delta := get_process_delta_time()
	_age(delta)
	_teams.age(delta)
	_scoreboard.visible = Input.is_action_pressed("scoreboard")
	if _scoreboard.visible:
		_place_scoreboard()
		_board_age += delta
		if _board_age > 0.5:
			_board_age = 0.0
			_refresh_scoreboard()
	_layout.visible = false
	_redraw()


func _draw_spectating(ci: CanvasItem, size: Vector2) -> void:
	var cx := size.x * 0.5
	var y := 38.0
	var top := "SPECTATING"
	if follow_name != "":   # locked onto a player
		if Teams.active():
			_teams.draw_bar(ci, size, self)
			_teams.draw_banner(ci, size)
		_draw_following(ci, size, "%s FLY FREE" % Settings.action_text("interact"))
		return
	if Teams.active():   # the teams' score and what is going on, then the fly keys
		_teams.draw_bar(ci, size, self)
		_teams.draw_banner(ci, size)
		HudStyle.label(ci, Vector2(cx, y + 58.0), top, 11, HudStyle.ORANGE, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_fly_keys(ci, size)
		return
	if Match.time_left < 1e8:
		var t := int(ceil(Match.time_left))
		top = "%d:%02d   SPECTATING" % [t / 60, t % 60]
	_pill(ci, Vector2(cx, y), top, 22, HudStyle.ORANGE)
	var rows: Array = Match.build_results() if not Race.active else []
	var sub := Maps.name_of(Net.map_id()).to_upper()
	if not rows.is_empty():
		sub += "  ·  LEADING: %s %d" % [str(rows[0].name).to_upper(), int(rows[0].kills)]
	elif Race.active:
		sub += "  ·  RACE"
	HudStyle.label(ci, Vector2(cx, y + 34.0), sub, 11, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	_draw_fly_keys(ci, size)


## Out for the round, watching someone (see FollowCamera).
func _draw_following(ci: CanvasItem, size: Vector2, last: String = "BACK WHEN THE NEXT ROUND STARTS") -> void:
	var cx := size.x * 0.5
	var target: int = Net.arena.follow_cam.target if Net.arena and Net.arena.follow_cam else 0
	var col := Teams.team_color(Teams.team_of(target)) if Teams.team_of(target) >= 0 else HudStyle.ORANGE
	_pill(ci, Vector2(cx, size.y - 92.0), "SPECTATING  %s" % follow_name.to_upper(), 18, col)
	var keys := "%s NEXT PLAYER   ·   %s PREVIOUS   ·   HOLD %s SCOREBOARD   ·   %s" % [
		Settings.action_text("fire"), Settings.action_text("grapple"), Settings.action_text("scoreboard"), last.to_upper()]
	HudStyle.label(ci, Vector2(cx, size.y - 56.0), keys.to_upper(), 11, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_fly_keys(ci: CanvasItem, size: Vector2) -> void:
	var cx := size.x * 0.5
	var keys := "%s %s %s %s FLY   ·   %s UP   ·   %s DOWN   ·   HOLD %s FAST   ·   %s WATCH A PLAYER   ·   HOLD %s SCOREBOARD   ·   ESC MENU: JOIN IN" % [
		Settings.action_text("move_forward"), Settings.action_text("move_left"), Settings.action_text("move_back"),
		Settings.action_text("move_right"), Settings.action_text("jump"), Settings.action_text("crouch"),
		Settings.action_text("sprint"), Settings.action_text("fire"), Settings.action_text("scoreboard")]
	HudStyle.label(ci, Vector2(cx, size.y - 34.0), keys.to_upper(), 11, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER)


func _hit_recently() -> bool:
	return _flash.color.a > 0.05


func _age(delta: float) -> void:
	_hit_time = maxf(_hit_time - delta, 0.0)
	for list in [_feed, _numbers, _arrows]:
		for e in list:
			e.age += delta
	_feed = _feed.filter(func(e): return e.age < FEED_LIFETIME)
	while _feed.size() > Settings.hud.feed_lines:   # how many lines Settings → HUD shows
		_feed.pop_front()
	_numbers = _numbers.filter(func(e): return e.age < NUMBER_TIME)
	_arrows = _arrows.filter(func(e): return e.age < ARROW_TIME)
	if not _confirm.is_empty():
		_confirm.age += delta
		if _confirm.age > CONFIRM_TIME:
			_confirm = {}
	if not _points.is_empty():
		_points.age += delta
		if _points.age > POINTS_TIME:
			_points = {}
	if not _promo.is_empty():
		_promo.age += delta
		if _promo.age > 2.2:
			_promo = {}


## Gun Game: you moved up the ladder (or were kicked back down it).
## Golden Gun: it changed hands (see GoldenGun).
func _on_golden_gun_passed(to: int, from: int) -> void:
	var me := Net.my_id()
	if to == me:
		_promo = {"text": "YOU HAVE THE GOLDEN GUN", "sub": "ONE ROUND  ·  WHOEVER IT HITS DIES  ·  A KILL RELOADS IT", "age": 0.0}
	elif from == me:
		_promo = {"text": "%s TOOK THE GOLDEN GUN" % Net.player_name(to).to_upper(), "sub": "KILL THEM TO TAKE IT BACK", "age": 0.0}
	else:
		_promo = {"text": "%s HAS THE GOLDEN GUN" % Net.player_name(to).to_upper(), "sub": "KILL THEM TO TAKE IT", "age": 0.0}


func _on_gun_game_level(id: int, level: int) -> void:
	if id != Net.my_id():
		return
	var name := WeaponData.name_of(GunGame.weapon_at(level)).to_upper()
	var last := level >= GunGame.steps() - 1
	_promo = {"text": name, "sub": "LAST WEAPON: ONE KILL TO WIN" if last else "WEAPON %d OF %d" % [level + 1, GunGame.steps()],
		"age": 0.0}


# ---------------------------------------------------------------------------
# Match events

func _on_hit(shooter: int, target: int, damage: float, headshot: bool) -> void:
	_last_head[target] = headshot
	var me := Net.my_id()
	if shooter == me and target != me:
		_hit_time = HIT_TIME
		_hit_kind = "head" if headshot else "hit"
		_numbers.append({"value": int(round(damage)), "head": headshot, "age": 0.0, "x": randf_range(-8.0, 8.0)})
	if target == me:
		_flash.color.a = 0.18
		var who: Player = Net.arena.get_player(shooter) if Net.arena and shooter != me else null
		if who:
			_arrows.append({"from": who.global_position, "age": 0.0})


## A target dummy brought down counts as a kill for the marker and the confirmation.
func _on_dummy_hit(shooter: int, _dummy: int, _damage: float, _headshot: bool, killed: bool) -> void:
	if killed and shooter == Net.my_id():
		_hit_time = KILL_HIT_TIME
		_hit_kind = "kill"
		_confirm = {"name": "Target dummy", "age": 0.0}


## You got a kill: show what it scored for the killcams, and where the points came from.
func _on_kill_scored(info: Dictionary) -> void:
	if int(info.killer) != Net.my_id() or int(info.victim) == Net.my_id():
		return
	var parts := KillScore.breakdown(info)
	_points = {"total": int(info.score), "parts": parts, "age": 0.0}
	if DevArgs.sync_log:
		print("KILL_POINTS %d %d %d %s" % [Net.my_id(), int(info.seq), int(info.score),
			",".join(parts.map(func(p): return "%s=%d" % [p[0], p[1]]))])


func _on_died(victim: int, killer: int) -> void:
	var me := Net.my_id()
	var head: bool = killer != 0 and _was_headshot(victim)
	if killer == victim:
		killer = 0   # crashed into a wall on their own
	# What did it, as the host saw it (an older host doesn't say: the gun they hold).
	var cause: String = Match.death_cause.get(victim, "")
	var told := str((Match.death_fx.get(victim, {}) as Dictionary).get("with", ""))
	var with := told
	if with == "" and killer != 0:
		with = Net.player_weapon(killer)
	var wall := cause == "slam" and killer != 0   # shoved into a wall: what shoved them, then the wall
	_feed.append({"killer": killer, "victim": victim, "head": head, "age": 0.0, "gun": with, "wall": wall,
		"how": {"slam": "crashed", "bomb": "blown up"}.get(cause, "fell")})
	if DevArgs.sync_log:
		print("FEED %d %d %d %s%s" % [me, killer, victim, with if killer != 0 else _feed.back().how, " wall" if wall else ""])
	while _feed.size() > FEED_MAX:
		_feed.pop_front()
	if killer == me and victim != me:
		_hit_time = KILL_HIT_TIME
		_hit_kind = "kill"
		_confirm = {"name": Net.player_name(victim), "age": 0.0}
	if victim == me:
		_dead = true
		_killer = killer if killer != victim else 0
		_killer_hp = Match.health.get(killer, 0.0)
		_killed_by_head = _was_headshot(me)
		_killed_how = death_how(told if cause == "slam" else with, cause)   # (not told what threw you: just the wall)
		_killer_dist = -1.0
		var mine: Player = Net.arena.get_player(me) if Net.arena else null
		var theirs: Player = Net.arena.get_player(_killer) if Net.arena and _killer != 0 else null
		if mine and theirs:
			_killer_dist = mine.global_position.distance_to(theirs.global_position)
		if _killer != 0:
			_killer_view.show_robot(Net.player_character(_killer), Net.player_color(_killer))
		_killer_view.visible = _killer != 0
		_respawn_left = Match.RESPAWN_DELAY
		_screen_age = 0.0
		_asked = false
		_arrows.clear()
		_numbers.clear()
		_refresh_scoreboard()


## Was `victim`'s death a headshot: the host's word on the killing blow (Match.death_fx),
## or, with none (an older host), whether the last hit on them was one.
func _was_headshot(victim: int) -> bool:
	var fx: Dictionary = Match.death_fx.get(victim, {})
	return bool(fx.head) if fx.has("head") else bool(_last_head.get(victim, false))


## Dead: Jump or Fire brings you back once the wait is over (you can change your
## loadout first; see Match.request_respawn). Not while the killcam plays (they skip
## it there), nor in the first RESPAWN_GRACE seconds of the death screen.
func _unhandled_input(event: InputEvent) -> void:
	if not _dead or _asked or Race.active or Killcam.watching() or not Match.respawn_needs_press(Net.my_id()) or Teams.no_respawn():
		return   # (Search and Destroy: everyone comes back at the next round)
	if event.is_echo() or not (event.is_action_pressed("jump") or event.is_action_pressed("fire")):
		return
	if Net.arena and Net.arena.menu_open():
		return
	get_viewport().set_input_as_handled()
	if _respawn_left > 0.0 or _screen_age < RESPAWN_GRACE:
		if DevArgs.sync_log:
			print("RESPAWN TOO SOON %.2f %.2f" % [_respawn_left, _screen_age])
		return
	if DevArgs.sync_log:
		print("RESPAWN BY %s %.2f" % [event.as_text(), _screen_age])
	_ask_respawn()


func _ask_respawn() -> void:
	_asked = true
	Match.request_respawn()


func _on_respawned(id: int, _spawn_index: int) -> void:
	if id == Net.my_id():
		_dead = false
		_killer_view.visible = false
		_respawn_left = 0.0
		view.hp_trail = Match.MAX_HEALTH


# ---------------------------------------------------------------------------
# Drawing

## HUD scale (Settings → HUD): from here on `ci` draws as if the screen were
## `size / s`, scaled up by `s` from the top-left corner, so the middle stays in the
## middle and each corner in its corner. Returns that size.
static func scaled(ci: CanvasItem, size: Vector2, s: float) -> Vector2:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	return size / s


func _draw_layout() -> void:
	var c := scaled(_layout, _layout.size, Settings.hud.scale) * 0.5
	if style == "clean":
		HudClean.draw(_layout, c, view)
	else:
		HudArcs.draw(_layout, c, view)


## Full-screen pages under the rest of the HUD, at the screen's own size: the killcam,
## the death screen, who you watch when out for the round; and the team modes'
## markers, which sit on spots in the world.
func _draw_screens() -> void:
	var ci := _screens
	var size := ci.size
	if spectating or Race.active:
		return
	if _dead and Killcam.watching():
		var back := "RESPAWN IN %.1f S" % _respawn_left if _respawn_left > 0.0 else ""
		KillcamOverlay.draw(ci, Rect2(Vector2.ZERO, size), Killcam.view, "KILLCAM",
			("%s  SKIP" % Settings.action_text("jump").to_upper() + ("   ·   " + back if back != "" else "")) if Killcam.can_skip() else back)
	elif _dead and follow_name != "":
		_draw_following(ci, size)
	elif _dead:
		_draw_death(ci, size)
	if _dead and Teams.active() and not Killcam.watching():
		_teams.draw_banner(ci, size)
	if not _dead and not _scoreboard.visible and Teams.active():
		_teams.draw_play(ci, size)


func _draw_overlay() -> void:
	var ci := _overlay
	var cfg := Settings.hud
	var size := scaled(ci, ci.size, cfg.scale)
	var c := size * 0.5
	if spectating:
		if not _scoreboard.visible:
			_draw_spectating(ci, size)
		if not Race.active:
			_draw_feed(ci, size)
		return
	if Race.active:
		if not _scoreboard.visible:
			_race.draw(ci, size, self)
	else:
		if Teams.active():
			_teams.draw_bar(ci, size, self)
		else:
			_draw_score_bar(ci, size)
		_draw_feed(ci, size)
	if _dead or _scoreboard.visible:
		return
	_draw_arrows(ci, c)
	if not _promo.is_empty():
		var pa := clampf((2.2 - _promo.age) / 0.4, 0.0, 1.0) * clampf(_promo.age / 0.08, 0.0, 1.0)
		HudStyle.text(ci, Vector2(c.x, c.y + 150.0), _promo.text, 26, Color(HudStyle.ORANGE, pa), HORIZONTAL_ALIGNMENT_CENTER)
		HudStyle.text(ci, Vector2(c.x, c.y + 176.0), _promo.sub, 13, Color(1, 1, 1, 0.8 * pa), HORIZONTAL_ALIGNMENT_CENTER)
	if Net.is_deathmatch() and not Race.active:
		_draw_inventory(ci, Vector2(c.x, size.y - 74.0))
		var boost: float = Match.damage_boost.get(Net.my_id(), 0.0)
		if boost > 0.0:
			HudStyle.text(ci, Vector2(c.x, size.y - 104.0), "2× DAMAGE  %d" % ceili(boost), 16,
				Color(1.0, 0.3, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
	for n in (_numbers if cfg.damage_numbers else []):
		var t: float = n.age / NUMBER_TIME
		var col: Color = HudStyle.YELLOW if n.head else HudStyle.WHITE
		col.a = 1.0 - t * t
		HudStyle.text(ci, c + Vector2(40.0 + n.x, -38.0 - 26.0 * t), str(n.value), 20, col)
	if not _confirm.is_empty():
		var a := clampf((CONFIRM_TIME - _confirm.age) / 0.4, 0.0, 1.0)
		var y := c.y - (128.0 if style == "arcs" else 92.0)
		var w1 := HudStyle.text_width("ELIMINATED  ", 20)
		var w := w1 + HudStyle.text_width(_confirm.name, 20)
		HudStyle.text(ci, Vector2(c.x - w * 0.5, y), "ELIMINATED", 20, Color(HudStyle.RED, a))
		HudStyle.text(ci, Vector2(c.x - w * 0.5 + w1, y), _confirm.name, 20, Color(1, 1, 1, a))
	if grapple == GRAPPLE_ON and tether > 0.0:
		HudStyle.text(ci, c + Vector2(40, 34), "%d m" % roundi(tether), 13, Color(1.0, 0.7, 0.45))
	if not _points.is_empty() and cfg.killcam_points:
		_draw_points(ci, c)


## Your kill's killcam score: one line at a time under the kill confirmation (the
## total, then each part), and the whole list in the bottom left. No backgrounds.
func _draw_points(ci: CanvasItem, c: Vector2) -> void:
	var age: float = _points.age
	var parts: Array = _points.parts
	# By the crosshair: the total, then each part in turn.
	var y := c.y - (100.0 if style == "arcs" else 64.0)
	if age < POINTS_TOTAL:
		var a := clampf(age / 0.08, 0.0, 1.0)
		var pop := 1.0 + 0.3 * clampf(1.0 - age / 0.12, 0.0, 1.0)
		HudStyle.text(ci, Vector2(c.x, y), "+%d" % int(_points.total), int(24 * pop), Color(HudStyle.ORANGE, a), HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var i := int((age - POINTS_TOTAL) / POINTS_STEP)
		if i < parts.size():
			var into := age - POINTS_TOTAL - i * POINTS_STEP
			var a := clampf(into / 0.05, 0.0, 1.0) * clampf((POINTS_STEP - into) / 0.05, 0.0, 1.0)
			var p: Array = parts[i]
			var num := "+%d" % p[1]
			var gap := 10.0
			var w := HudStyle.text_width(num, 20) + gap + HudStyle.text_width(p[0], 15, false)
			var x := c.x - w * 0.5
			var nw := HudStyle.text(ci, Vector2(x, y), num, 20, Color(_points_color(p, i), a))
			HudStyle.text(ci, Vector2(x + nw + gap, y), p[0], 15, Color(1, 1, 1, 0.9 * a), HORIZONTAL_ALIGNMENT_LEFT, false)
	# Bottom left: all of it, to look over.
	var fade := clampf((POINTS_TIME - age) / 0.5, 0.0, 1.0) * clampf(age / 0.2, 0.0, 1.0)
	draw_points_list(ci, c.y * 2.0, int(_points.total), parts, fade)


## The killcam score's whole list, bottom left on a screen `height` tall (also the
## HUD preview's in Settings).
static func draw_points_list(ci: CanvasItem, height: float, total: int, parts: Array, fade: float) -> void:
	var lx := HudClean.MARGIN
	var col := 0.0   # the words line up after the widest "+100"
	for p in parts:
		col = maxf(col, HudStyle.text_width("+%d" % p[1], 14) + 10.0)
	var ly: float = height - POINTS_LIST_BOTTOM - (parts.size() - 1) * 19.0
	var hw := HudStyle.label(ci, Vector2(lx, ly - 28.0), "KILLCAM SCORE", 10, Color(1, 1, 1, 0.7 * fade))
	HudStyle.text(ci, Vector2(lx + hw + 10.0, ly - 29.0), str(total), 20, Color(HudStyle.ORANGE, fade))
	for i in parts.size():
		var p: Array = parts[i]
		HudStyle.text(ci, Vector2(lx, ly), "+%d" % p[1], 14, Color(_points_color(p, i), fade))
		HudStyle.text(ci, Vector2(lx + col, ly), p[0], 12, Color(1, 1, 1, 0.8 * fade), HORIZONTAL_ALIGNMENT_LEFT, false)
		ly += 19.0


## Gold for the parts that make a highlight (a headshot, a flick, a multikill).
static func _points_color(part: Array, i: int) -> Color:
	var words := str(part[0])
	var gold := words == "HEADSHOT" or words.begins_with("TRICKSHOT") or words.begins_with("FLICK") or (words.ends_with(" KILL") and i > 0)
	return HudStyle.YELLOW if gold else HudStyle.WHITE


## Under the crosshair ring: the jetpack's fuel while it is not full (an arc, orange
## when low).
func _draw_mobility_marks(ci: CanvasItem, c: Vector2, ring: float) -> void:
	if jet_fuel < 0.999:   # (a full tank, or no jetpack, shows nothing)
		var span := 110.0
		var from := 90.0 - span * 0.5
		HudStyle.arc(ci, c, ring + 6.0, from, from + span, Color(1, 1, 1, 0.15), 3.0)
		if jet_fuel > 0.01:
			var col := Color(HudStyle.ORANGE, 0.95) if jet_fuel < Jetpack.RESTART else Color(JET_COLOR, 0.95)
			HudStyle.arc(ci, c, ring + 6.0, from, from + span * jet_fuel, col, 3.0)


func _draw_cross() -> void:
	if spectating or _dead or _scoreboard.visible:
		return
	_draw_crosshair(_cross, _cross.size * 0.5)


## The grapple ring and the marks under it grow with the HUD scale; the crosshair
## and hit markers keep their own size (Settings → HUD → Crosshair).
func _draw_crosshair(ci: CanvasItem, c: Vector2) -> void:
	var cfg := Settings.hud
	var hud_scale := Transform2D(0.0, Vector2(cfg.scale, cfg.scale), 0.0, c * (1.0 - cfg.scale))   # about the middle
	ci.draw_set_transform_matrix(hud_scale)
	var ring := 30.0 if style == "arcs" else 22.0
	match grapple:
		GRAPPLE_IN_RANGE:
			HudStyle.arc(ci, c, ring, 0, 360, Color(HudStyle.CYAN, 0.9), 2.0)
		GRAPPLE_ON:
			HudStyle.arc(ci, c, ring, 0, 360, Color(HudStyle.ORANGE, 0.95), 3.0)
		GRAPPLE_FLYING:   # a broken ring, turning: the hook is out but not pulling yet
			var spin := fmod(Time.get_ticks_msec() * 0.5, 360.0)
			for k in 4:
				HudStyle.arc(ci, c, ring, spin + k * 90.0, spin + k * 90.0 + 52.0, Color(HudStyle.ORANGE, 0.8), 2.0)
		GRAPPLE_COOLING:
			HudStyle.arc(ci, c, ring, 0, 360, Color(1, 1, 1, 0.15), 2.0)
			HudStyle.arc(ci, c, ring, -90, -90 + 360.0 * (1.0 - grapple_cooldown), Color(1, 1, 1, 0.6), 2.0)
		_:
			HudStyle.arc(ci, c, ring, 0, 360, Color(1, 1, 1, 0.12), 1.5)
	_draw_mobility_marks(ci, c, ring)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	HudStyle.crosshair(ci, c, view.crosshair, view.spread_px, cfg)
	ci.draw_set_transform_matrix(hud_scale)
	if view.blast and view.charge >= 0.0:   # the air cannon charging: a ring closes round the crosshair
		var full := view.charge >= 1.0
		HudStyle.arc(ci, c, ring - 6.0, -90.0, -90.0 + 360.0 * view.charge, Color(HudStyle.WHITE if full else HudStyle.CYAN, 0.9), 3.0 if full else 2.0)
	if view.ready < 1.0:   # working the pump or bolt: a small bar fills under the crosshair
		var bar := Rect2(c + Vector2(-14.0, 20.0), Vector2(28.0, 3.0))
		ci.draw_rect(bar, Color(1, 1, 1, 0.2))
		ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * view.ready, bar.size.y)), Color(1, 1, 1, 0.8))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	if _hit_time > 0.0 and cfg.hit_markers:
		HudStyle.hit_marker(ci, c, _hit_kind)


## Red chevrons around the crosshair pointing at whoever just hit you.
func _draw_arrows(ci: CanvasItem, c: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for a in _arrows:
		var local: Vector3 = cam.global_transform.basis.inverse() * (a.from - cam.global_position)
		var ang := atan2(local.x, -local.z) - PI / 2.0
		var alpha := clampf((ARROW_TIME - a.age) / 0.5, 0.0, 1.0) * 0.9
		var dir := Vector2.from_angle(ang)
		var side := dir.orthogonal()
		var r := 150.0
		var pts := PackedVector2Array([c + dir * r + side * 15.0, c + dir * (r + 17.0), c + dir * r - side * 15.0])
		ci.draw_polyline(pts, Color(0, 0, 0, alpha * 0.5), 8.0, true)
		ci.draw_polyline(pts, Color(HudStyle.RED, alpha), 5.0, true)


## Top centre: your kills, the clock, and the best of everyone else.
func _draw_score_bar(ci: CanvasItem, size: Vector2) -> void:
	var cx := size.x * 0.5
	var y := 38.0
	var me := Net.my_id()
	var timed := Match.time_left < 1e8
	var clock := ""
	if timed:
		var t := int(ceil(Match.time_left))
		clock = "%d:%02d" % [t / 60, t % 60]
	if Game.mode == Game.Mode.PRACTICE or Net.players.size() < 2:
		var s := "Practice  ·  %s" % Maps.name_of(Net.map_id())
		if timed:
			s = clock + "   " + s
		_pill(ci, Vector2(cx, y), s, 20, HudStyle.WHITE)
		return
	var best_id := 0
	for row in Match.build_results():
		if row.id != me:
			best_id = row.id
			break
	var gun_game := GunGame.active()
	var mid := clock if timed else "First to %d" % Match.kill_target
	var mid_w := _pill(ci, Vector2(cx, y), mid, 28 if timed else 20, HudStyle.WHITE)
	var gap := mid_w * 0.5 + 10.0
	var killcam := KillcamMode.active()
	var mine := "YOU %d" % Match.kills(me)
	if gun_game:   # how far along the ladder: weapon 5 of 16
		mine = "YOU %d/%d" % [Match.level(me) + 1, GunGame.steps()]
	elif killcam:   # points, not kills
		mine = "YOU %s" % KillcamMode.format(Match.points(me))
	_pill(ci, Vector2(cx - gap - (HudStyle.text_width(mine, 22) + 32.0) * 0.5, y), mine, 22, HudStyle.ORANGE)
	if best_id != 0:
		var theirs := "%s %d" % [Net.player_name(best_id).to_upper(), Match.kills(best_id)]
		if gun_game:
			theirs = "%s %d/%d" % [Net.player_name(best_id).to_upper(), Match.level(best_id) + 1, GunGame.steps()]
		elif killcam:
			theirs = "%s %s" % [Net.player_name(best_id).to_upper(), KillcamMode.format(Match.points(best_id))]
		_pill(ci, Vector2(cx + gap + (HudStyle.text_width(theirs, 22) + 32.0) * 0.5, y), theirs, 22, HudStyle.WHITE)
	var sub := "FIRST TO %d" % Match.kill_target if Match.kill_target > 0 and timed else ("MOST KILLS WINS" if timed else "")
	if gun_game:
		var lv := Match.level(me)
		sub = "GUN GAME  ·  LAST WEAPON: GET A KILL TO WIN" if lv >= GunGame.steps() - 1 \
			else "GUN GAME  ·  NEXT: %s" % WeaponData.name_of(GunGame.weapon_at(lv + 1)).to_upper()
	elif GoldenGun.active():
		var holder := GoldenGun.holder()
		sub = "GOLDEN GUN  ·  YOU HAVE IT: ONE ROUND, WHOEVER IT HITS DIES" if holder == me \
			else ("GOLDEN GUN  ·  %s HAS IT: KILL THEM TO TAKE IT" % Net.player_name(holder).to_upper() if holder != 0 else "GOLDEN GUN")
	elif killcam:
		sub = "KILLCAM  ·  FIRST TO %s  ·  #1 KILLCAM +%s AT THE END" % [KillcamMode.format(KillcamMode.target()), KillcamMode.format(KillcamMode.BEST_BONUS)]
	if sub != "":
		HudStyle.label(ci, Vector2(cx, y + 34.0), sub, 10, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER)


## A rounded plate with text in it, centred on `at`. Returns its width.
func pill(ci: CanvasItem, at: Vector2, s: String, size: int, color: Color) -> float:
	return _pill(ci, at, s, size, color)


func _pill(ci: CanvasItem, at: Vector2, s: String, size: int, color: Color) -> float:
	return draw_pill(ci, at, s, size, color)


## The score bar's plate (also the HUD preview's in Settings).
static func draw_pill(ci: CanvasItem, at: Vector2, s: String, size: int, color: Color) -> float:
	var w := HudStyle.text_width(s, size) + 32.0
	var h := size + 14.0
	var r := Rect2(at.x - w * 0.5, at.y - h * 0.5, w, h)
	HudStyle.framed_plate(ci, r, 8.0, Color(0.03, 0.045, 0.07, 0.72), Color(HudStyle.LINE, 0.3))
	# A coloured line along the bottom: orange under yours, cool blue under the rest.
	var line := color if color != HudStyle.WHITE else Color(HudStyle.CYAN, 0.7)
	ci.draw_rect(Rect2(r.position.x, r.end.y - 2.0, w - 8.0, 2.0), line)
	HudStyle.text(ci, at, s, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	return w


## Top right (or top left: Settings → HUD): the latest knockouts, newest at the
## bottom. Yours are orange.
func _draw_feed(ci: CanvasItem, size: Vector2) -> void:
	var me := Net.my_id()
	var left := Settings.hud.feed_corner == "left" and not _dead   # (out of the killcam's and death screen's way)
	var y := 34.0
	for e in _feed:
		var alpha := clampf((FEED_LIFETIME - e.age) / 0.6, 0.0, 1.0)
		var mine: bool = e.killer == me or e.victim == me
		var victim := Net.player_name(e.victim)
		var parts: Array = []   # [text, colour] drawn right to left
		if e.killer == 0:
			parts = [[e.how, Color(1, 1, 1, 0.65)], [victim, Net.player_color(e.victim)]]
		else:
			parts = [[victim, Net.player_color(e.victim)]]
			if e.head:
				parts.append(["@head", Color.WHITE])   # the headshot icon, between the gun and the victim
			if e.get("wall", false):   # (an entry from before the wall icon has none)
				parts.append(["@wall", Color.WHITE])
			parts.append(["@gun", Color.WHITE])
			parts.append([Net.player_name(e.killer), Net.player_color(e.killer)])
		var widths: Array = []
		var total := 0.0
		for part in parts:
			var w := _gun_width(e.gun) if part[0] == "@gun" else HudStyle.text_width(part[0], 16)
			if part[0] == "@head":
				w = HudStyle.headshot_width()
			elif part[0] == "@wall":
				w = HudStyle.WALL_W
			widths.append(w)
			total += w + 8.0
		var right := feed_right(size.x, total, left)
		var plate := Rect2(right - total - 16.0, y - 14.0, total + 16.0 + 8.0, 28.0)
		HudStyle.plate(ci, plate, 3.0, Color(HudStyle.ORANGE, 0.28 * alpha) if mine else Color(HudStyle.PANEL, HudStyle.PANEL.a * alpha))
		if mine:
			ci.draw_rect(Rect2(plate.position, Vector2(3, plate.size.y)), Color(HudStyle.ORANGE, alpha))
		var x := right - 4.0
		for i in parts.size():
			var part: Array = parts[i]
			var col: Color = part[1]
			col = Color(col.lightened(0.25), col.a * alpha)
			if part[0] == "@gun":
				HudStyle.kill_icon(ci, e.gun, Vector2(x - widths[i], y - 4.0), Color(1, 1, 1, 0.9 * alpha), 1.1)
			elif part[0] == "@head":   # (16 tall: centred on the line)
				HudStyle.headshot_icon(ci, Vector2(x - widths[i], y - 8.0), Color(1, 1, 1, 0.9 * alpha))
			elif part[0] == "@wall":
				HudStyle.wall_impact(ci, Vector2(x - widths[i], y - 4.0), Color(1, 1, 1, 0.9 * alpha), 1.1)
			else:
				HudStyle.text(ci, Vector2(x, y), part[0], 16, col, HORIZONTAL_ALIGNMENT_RIGHT)
			x -= widths[i] + 8.0
		y += 32.0


## Where a kill feed line `total` wide ends on the right (its parts are laid out
## leftward from there): its plate 14 px in from the right edge of a screen
## `width` across, or from the left edge.
static func feed_right(width: float, total: float, left: bool) -> float:
	return total + 30.0 if left else width - 22.0


func _gun_width(gun: String) -> float:
	return HudStyle.kill_icon_width(gun)   # (a weapon, or the kick or rope that did a kill)


## How a player got you, for the line under their name on the death screen: `with`
## and `cause` as in Match.death_fx and Match.death_cause ("Kick", "Kicked into a wall",
## "Rocket Launcher into a wall", "Shotgun").
static func death_how(with: String, cause: String) -> String:
	if cause == "slam":
		match with:
			"kick", "flying_kick":
				return "Kicked into a wall"
			"rope":
				return "Reeled into a wall"
			"", "none":
				return "Smashed into a wall"
		return "%s into a wall" % WeaponData.name_of(with)   # shoved by a blast or a shot
	match with:
		"kick":
			return "Kick"
		"flying_kick":
			return "Flying kick"
		"rope":
			return "Reeled in"
		"none":
			return "Bare feet"
	return WeaponData.name_of(with)


## Where the death screen's left column starts: it and the scoreboard sit side by
## side, centred as a pair.
func _death_left(size: Vector2) -> float:
	return maxf(20.0, (size.x - (DEATH_W + DEATH_GAP + BOARD_W)) * 0.5)


## Who got you (their robot, name, what was left of them, how), a bar counting down
## to your respawn, and the weapons you can come back with. The scoreboard shows
## beside it (see _place_scoreboard).
func _draw_death(ci: CanvasItem, size: Vector2) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.66))
	var top := Color(0.6, 0.05, 0.05, 0.38)
	ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, 260), Vector2(0, 260)]),
		PackedColorArray([top, top, Color(top, 0), Color(top, 0)]))
	var w := DEATH_W
	var card := Rect2(_death_left(size), DEATH_TOP, w, 164.0)
	var stripe := Net.player_color(_killer) if _killer != 0 else Color(1, 1, 1, 0.4)
	HudStyle.framed_plate(ci, card, 18.0, Color(0.03, 0.045, 0.07, 0.9), Color(HudStyle.RED, 0.55))
	ci.draw_rect(Rect2(card.position + Vector2(0, 18), Vector2(5, card.size.y - 18)), stripe)
	HudStyle.brackets(ci, card.grow(7.0), 16.0, Color(HudStyle.RED, 0.7), 2.0)
	var x := card.position.x + (176.0 if _killer != 0 else 30.0)
	var y := card.position.y
	if _killer != 0:
		_killer_view.position = card.position + Vector2(18, -26)
		HudStyle.label(ci, Vector2(x, y + 30), "ELIMINATED BY", 12, HudStyle.RED)
		# Their calling card, with their name on it.
		CallingCard.draw(ci, Rect2(x - 10, y + 39, card.end.x - x - 6, 44), Net.player_card(_killer), Net.player_icon(_killer), 0.7)
		HudStyle.text(ci, Vector2(x + 40, y + 61), Net.player_name(_killer), 30, stripe.lightened(0.45))
		var with := "%s  ·  %s" % [Characters.name_of(Net.player_character(_killer)), _killed_how]
		HudStyle.text(ci, Vector2(x, y + 97), with, 15, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT, false)
		var chips: Array = ["%d HP LEFT" % ceili(_killer_hp)]
		if _killed_by_head:
			chips.append("HEADSHOT")
		if _killer_dist >= 0.0:
			chips.append("%d M AWAY" % roundi(_killer_dist))
		var cx := x
		for chip in chips:
			var icon := HudStyle.headshot_width() * 0.8 + 5.0 if chip == "HEADSHOT" else 0.0   # the icon before the word
			var cw := HudStyle.text_width(chip, 12) + 18.0 + icon
			var col: Color = HudStyle.YELLOW if chip == "HEADSHOT" else Color(1, 1, 1, 0.85)
			HudStyle.plate(ci, Rect2(cx, y + 112, cw, 24), 6.0, Color(1, 1, 1, 0.09))
			if icon > 0.0:
				HudStyle.headshot_icon(ci, Vector2(cx + 9, y + 124 - 8.0 * 0.8), Color(1, 1, 1, 0.9), 0.8)   # white, like the feed's
			HudStyle.text(ci, Vector2(cx + 9 + icon, y + 124), chip, 12, col)
			cx += cw + 6.0
	else:
		var crashed: bool = Match.death_cause.get(Net.my_id(), "") == "slam"
		HudStyle.label(ci, Vector2(x, y + 44), "ELIMINATED", 12, HudStyle.RED)
		HudStyle.text(ci, Vector2(x, y + 82), "You crashed" if crashed else "You fell", 38, HudStyle.WHITE)
		HudStyle.text(ci, Vector2(x, y + 118), "Hit a wall too fast" if crashed else "Out of the arena", 15, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT, false)
	# Respawn countdown.
	var progress := clampf(1.0 - _respawn_left / Match.RESPAWN_DELAY, 0.0, 1.0)
	var bar := Rect2(card.position.x, card.end.y + 18.0, w, 6.0)
	ci.draw_rect(bar, Color(1, 1, 1, 0.15))
	ci.draw_rect(Rect2(bar.position, Vector2(w * progress, bar.size.y)), HudStyle.ORANGE)
	ci.draw_rect(Rect2(bar.position.x + w * progress - 2.0, bar.position.y - 3.0, 4.0, 12.0), Color.WHITE)
	var row := bar.end.y + 18.0
	if Teams.no_respawn():   # Search and Destroy: out for the rest of the round
		var a := 0.8 + 0.2 * sin(_pulse * 3.0)
		HudStyle.label(ci, Vector2(bar.position.x, row), "OUT FOR THIS ROUND  ·  BACK WHEN THE NEXT ONE STARTS", 12, Color(1, 1, 1, a))
	elif not Match.respawn_needs_press(Net.my_id()):
		HudStyle.label(ci, Vector2(bar.position.x, row), "RESPAWNING", 12, Color(1, 1, 1, 0.85))
		HudStyle.text(ci, Vector2(bar.end.x, row), "%.1f s" % _respawn_left, 15, HudStyle.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	elif _asked:
		HudStyle.label(ci, Vector2(bar.position.x, row), "RESPAWNING...", 12, HudStyle.ORANGE)
	elif _respawn_left > 0.0 or _screen_age < RESPAWN_GRACE:
		var lw := HudStyle.label(ci, Vector2(bar.position.x, row), "PICK YOUR LOADOUT", 12, Color(1, 1, 1, 0.85))
		if _respawn_left > 0.0:
			HudStyle.text(ci, Vector2(bar.position.x + lw + 12.0, row), "%.1f s" % _respawn_left, 15, HudStyle.WHITE)
	else:   # ready: a pulsing call to come back
		var a := 0.75 + 0.25 * sin(_pulse * 5.0)
		var keys := "%s OR %s" % [Settings.action_text("jump").to_upper(), Settings.action_text("fire").to_upper()]
		var w1 := HudStyle.text(ci, Vector2(bar.position.x, row + 2.0), keys, 16, Color(HudStyle.ORANGE, a))
		HudStyle.label(ci, Vector2(bar.position.x + w1 + 10.0, row + 2.0), "TO RESPAWN", 12, Color(1, 1, 1, a))
	if Match.respawn_needs_press(Net.my_id()) and not _asked and not Teams.no_respawn():
		HudStyle.label(ci, Vector2(bar.end.x, row + 2.0), "ESC  LOADOUT", 10, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	var mid := card.position.x + w * 0.5
	if Net.is_deathmatch():
		HudStyle.label(ci, Vector2(mid, bar.end.y + 56.0), "YOU COME BACK EMPTY-HANDED  ·  FIND WEAPONS ON THE MAP", 11,
			Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_draw_weapon_swap(ci, Vector2(mid, bar.end.y + 56.0))


## Deathmatch: your two weapon slots (keys 1 and 2), each with its weapon's name
## and rounds left; the one in your hands is lit and underlined.
func _draw_inventory(ci: CanvasItem, at: Vector2) -> void:
	var me := Net.my_id()
	var slots := Net.player_inventory(me)
	var held := Net.player_weapon(me)
	var p: Player = Net.arena.local_player if Net.arena else null
	var cell := Vector2(150.0, 48.0)
	var gap := 8.0
	var total := slots.size() * cell.x + (slots.size() - 1) * gap
	var x := at.x - total * 0.5
	if Net.player_weapons(me).is_empty():
		HudStyle.text(ci, Vector2(at.x, at.y - 12.0), "UNARMED  ·  WALK OVER A WEAPON TO PICK IT UP  ·  F KICK", 12,
			Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	for i in slots.size():
		var id: String = slots[i]
		var r := Rect2(x + i * (cell.x + gap), at.y, cell.x, cell.y)
		var owned := id != ""
		var on := owned and id == held
		var fill := Color(HudStyle.ORANGE, 0.35) if on else (Color(0.05, 0.06, 0.08, 0.8) if owned else Color(0.05, 0.06, 0.08, 0.35))
		HudStyle.plate(ci, r, 4.0, fill)
		if on:
			ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3.0), Vector2(r.size.x, 3.0)), HudStyle.ORANGE)
		var a := 1.0 if on else (0.75 if owned else 0.3)
		HudStyle.text(ci, r.position + Vector2(7.0, 11.0), str(i + 1), 11, Color(1, 1, 1, a * 0.8))
		if not owned:
			HudStyle.text(ci, r.position + cell * 0.5 + Vector2(0, 4.0), "EMPTY", 11, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER)
			continue
		var w := _gun_width(id) * 0.8
		HudStyle.weapon_icon(ci, id, r.position + Vector2((cell.x - w) * 0.5, 12.0), Color(1, 1, 1, a), 0.8)
		var label := WeaponData.by_id(id).short_name.to_upper()
		if p and WeaponData.by_id(id).magazine > 0:   # (a blade, or the air cannon: nothing to count)
			label += "  %d" % p.ammo_for(id)
		HudStyle.text(ci, r.position + Vector2(cell.x * 0.5, 38.0), label, 11, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER)


## While you wait to respawn: the weapons you can come back with, in their groups
## (a number key picks a group, again goes on through it; the wheel goes through them all).
## In Gun Game: the weapon you come back with, and the next one.
func _draw_weapon_swap(ci: CanvasItem, at: Vector2) -> void:
	var mine := Net.player_weapon(Net.my_id())
	if KillcamMode.active():
		HudStyle.text(ci, Vector2(at.x, at.y + 4.0), "SNIPERS ONLY", 16, HudStyle.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		HudStyle.text(ci, Vector2(at.x, at.y + 26.0), "EVERY KILL SCORES ITS KILLCAM POINTS  ·  YOU HAVE %s" % KillcamMode.format(Match.points(Net.my_id())), 12,
			Color(1, 1, 1, 0.65), HORIZONTAL_ALIGNMENT_CENTER)
		return
	if GunGame.active():
		var lv := Match.level(Net.my_id())
		var line := "WEAPON %d OF %d: %s" % [lv + 1, GunGame.steps(), WeaponData.name_of(mine).to_upper()]
		HudStyle.text(ci, Vector2(at.x, at.y + 4.0), line, 16, HudStyle.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		if lv + 1 < GunGame.steps():
			HudStyle.text(ci, Vector2(at.x, at.y + 26.0), "NEXT: %s" % WeaponData.name_of(GunGame.weapon_at(lv + 1)).to_upper(), 12,
				Color(1, 1, 1, 0.65), HORIZONTAL_ALIGNMENT_CENTER)
		return
	var only := LobbySettings.only_weapon()
	if only != "":   # the host set one gun for everyone
		HudStyle.text(ci, Vector2(at.x, at.y + 4.0), "EVERYONE HAS THE %s" % WeaponData.name_of(only).to_upper(), 16, HudStyle.WHITE,
			HORIZONTAL_ALIGNMENT_CENTER)
		HudStyle.text(ci, Vector2(at.x, at.y + 26.0), "THE HOST'S RULE FOR THIS MATCH", 12, Color(1, 1, 1, 0.65), HORIZONTAL_ALIGNMENT_CENTER)
		return
	var groups := LobbySettings.weapon_groups()   # only the weapons the host allows
	var gap := 6.0
	var total := DEATH_W
	var cell := Vector2((total - (groups.size() - 1) * gap) / groups.size(), 25.0)
	var x := at.x - total * 0.5
	HudStyle.label(ci, Vector2(x, at.y - 10.0), "COME BACK WITH", 11, Color(1, 1, 1, 0.85))
	var keys := "PRESS 1" if groups.size() == 1 else "PRESS 1-%d" % groups.size()
	HudStyle.label(ci, Vector2(x + total, at.y - 10.0), keys + " OR SCROLL", 10, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	for g in groups.size():
		var gx := x + g * (cell.x + gap)
		var list: Array = groups[g][1]
		var has_mine := mine in list
		ci.draw_rect(Rect2(gx, at.y + 4.0, cell.x, 2.0), HudStyle.ORANGE if has_mine else Color(HudStyle.CYAN, 0.45))
		HudStyle.text(ci, Vector2(gx + 2.0, at.y + 17.0), str(g + 1), 12, HudStyle.ORANGE if has_mine else Color(1, 1, 1, 0.85))
		HudStyle.label(ci, Vector2(gx + 16.0, at.y + 17.0), String(groups[g][0]).to_upper(), 9, Color(1, 1, 1, 0.7))
		for i in list.size():
			var id: String = list[i]
			var r := Rect2(gx, at.y + 28.0 + i * (cell.y + 3.0), cell.x, cell.y)
			var on := id == mine
			HudStyle.plate(ci, r, 6.0, Color(HudStyle.ORANGE, 0.9) if on else Color(0.04, 0.055, 0.085, 0.88))
			var name := WeaponData.by_id(id).short_name.to_upper()
			var col := Color(0.08, 0.06, 0.04) if on else Color(1, 1, 1, 0.78)
			var fs := 11 if name.length() <= 11 else 10
			ci.draw_string(HudStyle.font(true), r.position + Vector2(9.0, 17.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# ---------------------------------------------------------------------------
# Scoreboard (hold Tab; also shown while you wait to respawn)

func _build_scoreboard() -> void:
	_scoreboard = PanelContainer.new()
	var box := UiKit.cut_box(Color(0.03, 0.045, 0.07, 0.9), 18, 18, 14)
	box.set_border_width_all(1)
	box.border_color = Color(HudStyle.LINE, 0.3)
	_scoreboard.add_theme_stylebox_override("panel", box)
	_scoreboard.custom_minimum_size = Vector2(BOARD_W, 0)
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard.visible = false
	_root.add_child(_scoreboard)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_scoreboard.add_child(col)
	_score_title = _cell(col, "", 12, HudStyle.CYAN.lerp(Color.WHITE, 0.3), true)
	_score_title.add_theme_font_override("font", HudStyle.font_spaced(1))
	_score_title.clip_text = true   # one line: a long title is trimmed, never taller
	_score_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var rule := ColorRect.new()
	rule.color = Color(HudStyle.LINE, 0.25)
	rule.custom_minimum_size = Vector2(0, 1)
	col.add_child(rule)
	_score_rows = VBoxContainer.new()
	_score_rows.add_theme_constant_override("separation", 3)
	col.add_child(_score_rows)


## Where the scoreboard goes: beside the death screen's left column while you wait
## to respawn, otherwise (Tab) in the middle of the screen. Never off the screen.
func _place_scoreboard() -> void:
	_scoreboard.reset_size()
	var view := _root.size
	var board := _scoreboard.size
	var at := (view - board) * 0.5
	if _dead and not Race.active:
		at = Vector2(_death_left(view) + DEATH_W + DEATH_GAP, DEATH_TOP)
	at.x = clampf(at.x, 12.0, maxf(view.x - board.x - 12.0, 12.0))
	at.y = clampf(at.y, 12.0 if _dead else 84.0, maxf(view.y - board.y - 12.0, 12.0))
	_scoreboard.position = at


func _cell(parent: Node, text: String, size: int, color: Color, bold: bool = true, right: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", HudStyle.font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(l)
	return l


## One line of the scoreboard: a plate with the player's colour down its left edge
## (yours tinted orange). `cells`: [text, width (0 = takes what is left), size,
## colour, bold, right-aligned]. `tight`: a full lobby, so thinner rows.
func _board_row(cells: Array, stripe: Color, mine: bool = false, heading: bool = false, tight: bool = false) -> void:
	var p := PanelContainer.new()
	var pad := 0 if heading else (1 if tight else 5)
	var box := UiKit.cut_box(Color(0, 0, 0, 0) if heading else (Color(HudStyle.ORANGE, 0.2) if mine else Color(1, 1, 1, 0.05)), 7, 12, pad)
	box.border_width_left = 4
	box.border_color = stripe
	p.add_theme_stylebox_override("panel", box)
	_score_rows.add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	p.add_child(row)
	for c in cells:
		var l := _cell(row, c[0], c[2], c[3], c[4], c[5])
		if c[1] > 0.0:
			l.custom_minimum_size = Vector2(c[1], 0)
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _refresh_scoreboard() -> void:
	if not _score_rows:
		return
	if Race.active:
		_refresh_race_board()
		return
	var title := Maps.name_of(Net.map_id())
	var gun_game := GunGame.active()
	var killcam := KillcamMode.active()
	if Teams.active():
		title += "  ·  %s  ·  Red %d - %d Blue" % [Teams.MODE_NAMES[Teams.mode()], Teams.score[0], Teams.score[1]]
		if Teams.is_snd():
			title += "  ·  Round %d" % Teams.round_number
	if gun_game:
		title += "  ·  Gun Game: %d weapons" % GunGame.steps()
	elif killcam:
		title += "  ·  Killcam: first to %s" % KillcamMode.format(KillcamMode.target())
	if Match.kill_target > 0:
		title += "  ·  First to %d" % Match.kill_target
	if Match.time_left < 1e8:
		var t := int(ceil(Match.time_left))
		title += "  ·  %d:%02d left" % [t / 60, t % 60]
	var ping := _ping_ms()
	if ping >= 0:
		title += "  ·  Ping %d ms" % ping
	if not Net.spectators.is_empty():
		title += "  ·  %d watching" % Net.spectators.size()
	_score_title.text = title.to_upper()
	UiKit.clear(_score_rows)
	# A full 16-player lobby: tighter rows so the board still fits the screen.
	var tight := Net.players.size() > 8
	var dim := Color(1, 1, 1, 0.6)
	var none := Color(0, 0, 0, 0)
	# Every mode shows the score (each kill's killcam points); in Killcam it is the main
	# column, so kills come next to it instead. Online, each player's ping too.
	var online := Net.is_online
	var heads := [["#", 22.0, 11, dim, false, false], ["PLAYER", 0.0, 11, dim, false, false],
		["ROBOT  ·  WEAPON", 180.0, 11, dim, false, false], ["WEAPON #" if gun_game else ("POINTS" if killcam else "KILLS"), 90.0 if killcam else 64.0, 11, dim, false, true],
		["KILLS" if killcam else "SCORE", 64.0 if killcam else 80.0, 11, dim, false, true], ["DEATHS", 56.0, 11, dim, false, true]]
	if online:
		heads.append(["PING", 52.0, 11, dim, false, true])
	_board_row(heads, none, false, true)
	var rank := 0
	for row in Match.build_results():
		rank += 1
		var mine: bool = row.id == Net.my_id()
		var col := HudStyle.ORANGE if mine else HudStyle.WHITE
		var cells := [[str(rank), 22.0, 15, dim, true, false],
			[row.name + ("  (bot)" if Net.is_bot(row.id) else ""), 0.0, 17, col, true, false],
			["%s  ·  %s" % [Characters.name_of(Net.player_character(row.id)), _weapon_label(row.id)], 180.0, 14, Color(col, 0.75), false, false],
			[("%d/%d" % [row.level + 1, GunGame.steps()]) if gun_game else (KillcamMode.format(row.points) if killcam else str(row.kills)),
				90.0 if killcam else 64.0, 19, col, true, true],
			[str(row.kills) if killcam else KillcamMode.format(row.points), 64.0 if killcam else 80.0, 15, Color(col, 0.85), killcam, true],
			[str(row.deaths), 56.0, 15, Color(col, 0.75), false, true]]
		if online:
			cells.append(_ping_cell(row.id, col))
		_board_row(cells, Net.player_color(row.id), mine, false, tight)


## The scoreboard's ping for one player: ms (yellow from 100, red from 200), HOST
## for the host, a dash while not measured yet.
func _ping_cell(id: int, col: Color) -> Array:
	var ms := Net.player_ping(id)
	if id == Net.host_id():
		return ["HOST", 52.0, 11, Color(col, 0.6), false, true]
	if ms < 0:
		return ["-", 52.0, 14, Color(col, 0.5), false, true]
	var tint := Color(col, 0.8) if ms < 100 else (HudStyle.YELLOW if ms < 200 else HudStyle.RED)
	return [str(ms), 52.0, 14, tint, false, true]


## The race version: place, racer, gates passed, time (or how far along), resets.
func _refresh_race_board() -> void:
	var title := "%s  ·  Race" % Maps.name_of(Net.map_id())
	if Race.time >= 0.0:
		title += "  ·  %s" % Race.format_time(Race.time)
	if Race.end_at < INF:
		title += "  ·  ends in %d s" % maxi(int(ceil(Race.end_at - Race.time)), 0)
	var ping := _ping_ms()
	if ping >= 0:
		title += "  ·  Ping %d ms" % ping
	_score_title.text = title.to_upper()
	UiKit.clear(_score_rows)
	var tight := Net.players.size() > 8
	var dim := Color(1, 1, 1, 0.6)
	var heads := [["#", 22.0, 11, dim, false, false], ["RACER", 0.0, 11, dim, false, false], ["GATES", 80.0, 11, dim, false, true],
		["TIME", 110.0, 11, dim, false, true], ["RESETS", 70.0, 11, dim, false, true]]
	if Net.is_online:
		heads.append(["PING", 52.0, 11, dim, false, true])
	_board_row(heads, Color(0, 0, 0, 0), false, true)
	var rank := 0
	for row in Race.standings():
		rank += 1
		var mine: bool = row.id == Net.my_id()
		var col := HudStyle.ORANGE if mine else HudStyle.WHITE
		var cells := [[str(rank), 22.0, 15, dim, true, false],
			[row.name + ("  (bot)" if Net.is_bot(row.id) else ""), 0.0, 17, col, true, false],
			["%d / %d" % [row.cp, Race.gates], 80.0, 15, Color(col, 0.75), false, true],
			[Race.format_time(row.time) if row.finished else "racing", 110.0, 17 if row.finished else 14,
				HudStyle.YELLOW if row.finished else Color(col, 0.6), row.finished, true],
			[str(row.resets), 70.0, 15, Color(col, 0.75), false, true]]
		if Net.is_online:
			cells.append(_ping_cell(row.id, col))
		_board_row(cells, Net.player_color(row.id), mine, false, tight)


func _ping_ms() -> int:
	var peer := Net.multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer and not Net.is_host():
		var host_peer: ENetPacketPeer = peer.get_peer(1)
		if host_peer:
			return int(host_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	return -1


## The scoreboard's weapon column: the gun's short name ("Unarmed" in a Deathmatch
## before they find one).
func _weapon_label(id: int) -> String:
	var gun := Net.player_weapon(id)
	return WeaponData.by_id(gun).short_name if gun != "none" else "Unarmed"


## Mouse buttons as a move's keycap shows them.
const MOUSE_KEYCAPS := {MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_XBUTTON1: "M4", MOUSE_BUTTON_XBUTTON2: "M5", MOUSE_BUTTON_WHEEL_UP: "WHL UP", MOUSE_BUTTON_WHEEL_DOWN: "WHL DN"}


## The first key bound to `action`, as the HUD shows it ("ALT", "MMB"), or `fallback`.
func _key_label(action: String, fallback: String) -> String:
	var list: Array = Settings.bindings.get(action, [])
	if list.is_empty():
		return fallback
	var ev := Settings.binding_event(str(list[0]))
	if ev is InputEventMouseButton:
		return MOUSE_KEYCAPS.get(ev.button_index, fallback)   # (short: "MIDDLE MOUSE" would not fit the keycap)
	var text := Settings.binding_text(str(list[0])).to_upper()
	return text if text != "" else fallback
