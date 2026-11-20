class_name HudPreview
extends HBoxContainer
## Settings → HUD: the in-game HUD in miniature over a dark backdrop, drawn by the
## real code (HudArcs or HudClean, HudStyle.crosshair, the score bar's plates and the
## killcam score list from Hud) from a made-up moment: 72 health with a red chunk
## just lost, half a magazine, two moves recharging, a kill in the feed. Redrawn every
## frame, so it follows each option as it changes. Beside it, the crosshair close up
## at twice its real size, and a switch between the first- and third-person layouts.

const SCREEN := Vector2(1600, 900)   ## the screen the miniature stands for (the size the HUD is laid out for)
const SIZE := Vector2(512, 288)
const ZOOM := 2.0                    ## the close-up
const SIDE := 330.0                  ## the close-up's column
## The feed's sample lines: [killer, victim, gun, headshot, yours].
const FEED := [["YOU", "RIVET", "pistol", true, true], ["ORBIT", "NEEDLE", "shotgun", false, false],
	["KESTREL", "ORBIT", "anti_materiel", true, false], ["YOU", "BULWARK", "pistol", false, true]]
const POINTS := [["KILL", 100], ["HEADSHOT", 60], ["SPEED 21 M/S", 85]]

var third_person := false   ## which view's layout the miniature shows

var _view := Hud.View.new()
var _screen: Control   # the miniature: the backdrop
var _hud: Control      # its HUD, faded with the HUD opacity
var _cross: Control    # its crosshair, never faded
var _close: Control    # the close-up
var _time := 0.0


func _init(third: bool = false) -> void:
	third_person = third
	add_theme_constant_override("separation", 12)
	_fill_view()
	_screen = Control.new()
	_screen.custom_minimum_size = SIZE
	_screen.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_screen.clip_contents = true
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.draw.connect(_draw_backdrop.bind(_screen, false))
	add_child(_screen)
	_hud = _layer(_screen, _draw_hud)
	_cross = _layer(_screen, _draw_cross)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side.custom_minimum_size = Vector2(SIDE, 0)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(side)
	_close = Control.new()
	_close.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_close.clip_contents = true
	_close.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close.draw.connect(_draw_close)
	side.add_child(_close)
	UiKit.segmented(side, ["First person", "Third person"], 1 if third_person else 0, func(i): third_person = i == 1)


func _layer(parent: Control, on_draw: Callable) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(on_draw)
	parent.add_child(c)
	return c


func _fill_view() -> void:
	var v := _view
	v.hp = 72.0
	v.hp_trail = 84.0
	v.ammo = 6
	v.magazine = 12
	v.weapon = WeaponData.name_of("pistol")
	v.gun = "pistol"
	v.crosshair = WeaponData.by_id("pistol").crosshair
	v.spread_px = 2.0
	v.character = Characters.name_of(Settings.character)
	v.speed = 11.4
	v.move_state = "SLIDE"
	v.moves = [["GRAPPLE", "MMB", 1.0, false], ["DIVE", "Q", 0.35, false], ["FLIP", "SPACE", 1.0, false],
		["GLIDE", "ALT", 1.0, false], ["SLIDE", "CTRL", 0.6, false], ["BOOST", "E", 1.0, false], ["KICK", "F", 1.0, false]]


func _process(delta: float) -> void:
	_time += delta
	_hud.modulate.a = Settings.hud.opacity
	for c in [_screen, _hud, _cross, _close]:
		c.queue_redraw()


## A hit marker flashes now and then, like a shot landing.
func _hitting() -> bool:
	return fmod(_time, 1.6) < 0.3


## Dark sky over a floor grid running off to the horizon, so the HUD reads as it would in game.
func _draw_backdrop(ci: Control, close: bool) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	var horizon := r.size.y * (0.5 if close else 0.56)
	var sky := Color(0.07, 0.1, 0.15)
	var haze := Color(0.16, 0.2, 0.27)
	var floor_col := Color(0.05, 0.06, 0.08)
	ci.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(r.size.x, 0), Vector2(r.size.x, horizon), Vector2(0, horizon)]),
		PackedColorArray([sky, sky, haze, haze]))
	ci.draw_rect(Rect2(0, horizon, r.size.x, r.size.y - horizon), floor_col)
	var line := Color(UiKit.CYAN, 0.09)
	var mid := r.size.x * 0.5
	for i in range(-12, 13):
		ci.draw_line(Vector2(mid + i * 18.0, horizon), Vector2(mid + i * 150.0, r.size.y), line, 1.0)
	var y := horizon
	var step := 3.0
	while y < r.size.y:
		ci.draw_line(Vector2(0, y), Vector2(r.size.x, y), line, 1.0)
		y += step
		step *= 1.45
	ci.draw_rect(r, Color(UiKit.LINE, 0.5), false, 1.0)


## The HUD at the HUD scale, the miniature standing for a SCREEN-sized screen.
func _draw_hud() -> void:
	var ci := _hud
	var cfg := Settings.hud
	var screen := Hud.scaled(ci, ci.size, cfg.scale * ci.size.x / SCREEN.x)   # SCREEN / scale, shrunk to fit
	var c := screen * 0.5
	var style := Settings.hud_third_person if third_person else Settings.hud_first_person
	if style == "clean":
		HudClean.draw(ci, c, _view)
	else:
		HudArcs.draw(ci, c, _view)
	# The score bar, as in a match.
	var mid_w := Hud.draw_pill(ci, Vector2(c.x, 38.0), "2:47", 28, HudStyle.WHITE)
	var gap := mid_w * 0.5 + 10.0
	for s in [["YOU 3", HudStyle.ORANGE, -1.0], ["RIVET 2", HudStyle.WHITE, 1.0]]:
		Hud.draw_pill(ci, Vector2(c.x + s[2] * (gap + (HudStyle.text_width(s[0], 22) + 32.0) * 0.5), 38.0), s[0], 22, s[1])
	HudStyle.label(ci, Vector2(c.x, 72.0), "MOST KILLS WINS", 10, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	_draw_feed(ci, screen.x, cfg)
	if cfg.damage_numbers:
		HudStyle.text(ci, c + Vector2(42.0, -46.0), "34", 20, HudStyle.WHITE)
	if cfg.killcam_points:
		Hud.draw_points_list(ci, screen.y, 245, POINTS, 1.0)


## The kill feed's sample lines, as many as the feed shows, laid out like Hud's.
func _draw_feed(ci: CanvasItem, width: float, cfg: HudConfig) -> void:
	var y := 34.0
	for n in cfg.feed_lines:
		var e: Array = FEED[n % FEED.size()]
		var mine: bool = e[4]
		var parts: Array = [[e[1], Color(0.45, 0.75, 1.0)]]
		if e[3]:
			parts.append(["HEAD", HudStyle.YELLOW])
		parts.append(["@gun", Color.WHITE])
		parts.append([e[0], HudStyle.ORANGE if mine else Color(0.6, 1.0, 0.55)])
		var widths: Array = []
		var total := 0.0
		for part in parts:
			var w := HudStyle.weapon_width(e[2]) if part[0] == "@gun" else HudStyle.text_width(part[0], 16 if part[0] != "HEAD" else 11)
			widths.append(w)
			total += w + 8.0
		var right := Hud.feed_right(width, total, cfg.feed_corner == "left")
		var plate := Rect2(right - total - 16.0, y - 14.0, total + 16.0 + 8.0, 28.0)
		HudStyle.plate(ci, plate, 3.0, Color(HudStyle.ORANGE, 0.28) if mine else HudStyle.PANEL)
		if mine:
			ci.draw_rect(Rect2(plate.position, Vector2(3, plate.size.y)), HudStyle.ORANGE)
		var x := right - 4.0
		for i in parts.size():
			var part: Array = parts[i]
			if part[0] == "@gun":
				HudStyle.weapon_icon(ci, e[2], Vector2(x - widths[i], y - 4.0), Color(1, 1, 1, 0.9), 1.1)
			else:
				HudStyle.text(ci, Vector2(x, y), part[0], 16 if part[0] != "HEAD" else 11, (part[1] as Color).lightened(0.25),
					HORIZONTAL_ALIGNMENT_RIGHT)
			x -= widths[i] + 8.0
		y += 32.0


## The crosshair at its own size, with the grapple ring round it at the HUD scale.
func _draw_cross() -> void:
	var k := _cross.size.x / SCREEN.x
	_draw_crosshair(_cross, SCREEN * 0.5, Transform2D(0.0, Vector2(k, k), 0.0, Vector2.ZERO))


## The close-up: the crosshair at ZOOM times its real size.
func _draw_close() -> void:
	_draw_backdrop(_close, true)
	var c := _close.size * 0.5
	_draw_crosshair(_close, Vector2.ZERO, Transform2D(0.0, Vector2(ZOOM, ZOOM), 0.0, c))
	_close.draw_set_transform_matrix(Transform2D.IDENTITY)
	HudStyle.label(_close, Vector2(10.0, 14.0), "CROSSHAIR  ×%d" % int(ZOOM), 10, Color(1, 1, 1, 0.6))


## The grapple ring (nothing to grab), the crosshair and now and then a hit marker,
## centred on `c` in the space `base` puts on the screen.
func _draw_crosshair(ci: CanvasItem, c: Vector2, base: Transform2D) -> void:
	var cfg := Settings.hud
	var ring := 30.0 if (Settings.hud_third_person if third_person else Settings.hud_first_person) == "arcs" else 22.0
	ci.draw_set_transform_matrix(base * Transform2D(0.0, Vector2(cfg.scale, cfg.scale), 0.0, c * (1.0 - cfg.scale)))
	HudStyle.arc(ci, c, ring, 0, 360, Color(1, 1, 1, 0.12), 1.5)
	ci.draw_set_transform_matrix(base)
	HudStyle.crosshair(ci, c, _view.crosshair, _view.spread_px, cfg)
	if cfg.hit_markers and _hitting():
		HudStyle.hit_marker(ci, c, "hit")
