class_name CharacterShowcase
extends Control
## The right-hand side of the main menu's front page: the characters you can play,
## one at a time, close up, like the trailer of a film. Each gets a few seconds and
## one of four camera moves (a slow rise from the boots to the face, a fall from the
## face that pulls back to show the whole body, a low hero angle that circles round,
## a profile drifting up to the head), lit for it: a warm or cool key light that
## casts shadows, a strong coloured rim light from behind, a glow on the wall behind
## and a ring of light on the floor. Between characters the picture fades out and the
## next one fades in, its name sliding in along the bottom.
##
## The cast: every robot, newest first, between whole creatures from the Character
## Creator (a goblin, a frog, a dude...), and your own newest custom characters near
## the start. Its own small 3D world, like RobotPreview.

const SHOT := 7.0        ## seconds on each character
const FADE := 0.9        ## seconds to fade out at the end of a shot, and in at the start
const STANDARD_HEIGHT := 1.8   ## how tall the shots are written for (a robot); others scale

## [character id, the weapon in its hands]. Robots and whole creatures, in turn.
const CAST := [
	["templar", "shotgun"],
	["custom:n=Goblin|l=goblin|t=goblin|h=goblin", "axe"],
	["needle", "pistol"],
	["custom:n=Frog|l=frog|t=frog|h=frog", "pistol"],
	["vanguard", "rifle"],
	["custom:n=Dude|l=human|t=human|h=human|hat=cap", "shotgun"],
	["kestrel", "revolver"],
	["custom:n=Bones|l=skeleton|t=skeleton|h=skeleton", "scythe"],
	["bulwark", "lmg"],
	["custom:n=Wizard|l=wizard|t=wizard|h=wizard|hat=wizard", "derringer"],
	["rivet", "machine_pistol"],
	["custom:n=Whiskers|l=cat|t=cat|h=cat", "revolver"],
	["specter", "crossbow"],
	["custom:n=Cosmo|l=astronaut|t=astronaut|h=astronaut", "laser_rifle"],
	["orbit", "akimbo"],
	["custom:n=Ninja|l=ninja|t=ninja|h=ninja", "dagger"],
]

## The camera moves. Heights are shares of the character's height; `dist` is metres
## for a robot-sized character; `yaw` is degrees round from straight in front
## (positive: to its left as you look); `side` slides the picture so the character
## sits off centre; `roll` tilts the camera. Each pair is [start, end].
const MOVES := [
	{"name": "rise", "y": [0.14, 0.90], "look": [0.18, 0.90], "dist": [2.05, 1.55], "yaw": [-30.0, -12.0], "fov": 34.0, "roll": [0.0, -2.0], "side": 0.20},
	{"name": "descend", "y": [0.96, 0.60], "look": [0.92, 0.50], "dist": [1.05, 2.70], "yaw": [26.0, 10.0], "fov": 32.0, "roll": [2.5, 0.0], "side": -0.22},
	{"name": "hero", "y": [0.16, 0.28], "look": [0.70, 0.88], "dist": [2.00, 1.45], "yaw": [44.0, 4.0], "fov": 36.0, "roll": [-4.0, 3.0], "side": 0.18},
	{"name": "profile", "y": [0.55, 0.90], "look": [0.55, 0.86], "dist": [2.10, 1.60], "yaw": [-70.0, -38.0], "fov": 30.0, "roll": [0.0, 0.0], "side": 0.16},
]

## [key light, rim light, glow on the wall], one after another.
const LOOKS := [
	[Color(1.0, 0.86, 0.70), Color(0.35, 0.85, 1.0), Color(0.25, 0.65, 1.0)],
	[Color(0.80, 0.88, 1.0), Color(1.0, 0.50, 0.18), Color(1.0, 0.45, 0.15)],
	[Color(1.0, 0.92, 0.85), Color(0.85, 0.35, 1.0), Color(0.60, 0.30, 1.0)],
	[Color(0.95, 0.95, 1.0), Color(0.30, 1.0, 0.75), Color(0.15, 0.85, 0.75)],
]

const FEATHER_SHADER := "shader_type canvas_item;
render_mode blend_premul_alpha;
// Fade the picture out toward its edges, so it melts into the menu behind it. (The 3D
// comes on a clear background, its edges already multiplied by how much of a pixel
// they cover: it is blended, and faded, that way.)
uniform vec4 feather = vec4(0.22, 0.04, 0.08, 0.10);   // left, right, top, bottom
uniform float fade = 1.0;                              // the whole picture, in and out
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float m = smoothstep(0.0, feather.x, UV.x) * smoothstep(1.0, 1.0 - feather.y, UV.x)
		* smoothstep(0.0, feather.z, UV.y) * smoothstep(1.0, 1.0 - feather.w, UV.y);
	COLOR = c * m * fade;
}"

const RING_SHADER := "shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
// A ring of light on the floor round the character's feet, and a soft pool inside it.
uniform vec4 tint : source_color = vec4(0.4, 0.9, 1.0, 1.0);
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float ring = smoothstep(0.78, 0.85, r) * (1.0 - smoothstep(0.85, 0.93, r));
	float pool = (1.0 - smoothstep(0.0, 0.95, r)) * 0.28;
	ALBEDO = tint.rgb;
	ALPHA = clamp((ring * 0.85 + pool) * tint.a, 0.0, 1.0);
}"

var caption := ""        ## a line along the bottom ("15 MAPS · 45 WEAPONS · 8 GAMEMODES")

var _view: SubViewport
var _picture: PortraitView          # the 3D, at the screen's own sharpness, with your anti-aliasing picks
var _feather: ShaderMaterial
var _overlay: Control
var _camera: Camera3D
var _key: SpotLight3D
var _rim: SpotLight3D
var _fill: DirectionalLight3D
var _ring: MeshInstance3D
var _ring_material: ShaderMaterial
var _stage: Node3D

var _cast: Array = []    # [{id, gun, name, kicker, blurb}]
var _index := -1         # which of the cast is on
var _entry := {}         # RobotPreview.posed() of the one on
var _height := STANDARD_HEIGHT
var _t := 0.0            # seconds into this shot
var _idle := 0.0         # seconds into the idle animation
var _fade := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture = PortraitView.new()
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var feather := Shader.new()
	feather.code = FEATHER_SHADER
	_feather = ShaderMaterial.new()
	_feather.shader = feather
	_picture.picture.material = _feather
	add_child(_picture)
	_view = _picture.view
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.80)
	env.ambient_light_energy = 0.28   # low: the lights do the work, and the shadows stay deep
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC   # the same film look as the arenas
	env.tonemap_white = 2.8
	var world := WorldEnvironment.new()
	world.environment = env
	_view.add_child(world)
	_key = SpotLight3D.new()
	_key.spot_range = 9.0
	_key.spot_angle = 30.0
	_key.spot_angle_attenuation = 1.6
	_key.shadow_enabled = true
	_key.shadow_blur = 1.5
	_view.add_child(_key)
	_rim = SpotLight3D.new()
	_rim.spot_range = 9.0
	_rim.spot_angle = 34.0
	_view.add_child(_rim)
	_fill = DirectionalLight3D.new()   # a faint cool light from below the camera, so nothing goes flat black
	_fill.light_energy = 0.25
	_fill.light_color = Color(0.55, 0.65, 1.0)
	_view.add_child(_fill)
	_camera = Camera3D.new()
	_camera.near = 0.05
	_view.add_child(_camera)
	_stage = Node3D.new()
	_view.add_child(_stage)
	_ring = MeshInstance3D.new()
	var disc := PlaneMesh.new()
	disc.size = Vector2(1.9, 1.9)
	_ring.mesh = disc
	_ring.position.y = 0.01
	_ring_material = ShaderMaterial.new()
	var ring_shader := Shader.new()
	ring_shader.code = RING_SHADER
	_ring_material.shader = ring_shader
	_ring.material_override = _ring_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_view.add_child(_ring)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


## Start the show with the standard cast and, near the start, these characters of
## your own (custom character ids). Does nothing if that show is already on.
func start(own: Array = []) -> void:
	var cast := []
	for c in CAST:
		cast.append(_member(c[0], c[1], ""))
	var at := 1
	for id in own:
		if Characters.has(id):
			cast.insert(at, _member(id, "pistol", "YOUR CHARACTER"))
			at += 2   # a standard one between each of yours
	if _index >= 0 and cast.map(func(m): return m.id) == _cast.map(func(m): return m.id):
		return
	_cast = cast
	_show(posmod(DevArgs.showcase - 1, _cast.size()) if DevArgs.showcase > 0 else 0)


## The one on now (its index in the cast), for tests.
func current() -> int:
	return _index


func cast_size() -> int:
	return _cast.size()


## Cut to the next character now (tests and screenshots).
func skip(to: int = -1, seconds_in: float = 0.0) -> void:
	_show(posmod(to if to >= 0 else _index + 1, _cast.size()))
	_t = seconds_in
	_place(0.0)


func _member(id: String, gun: String, kicker: String) -> Dictionary:
	var m := {"id": Characters.valid(id), "gun": gun}
	if CustomCharacter.is_custom(id):
		var c := CustomCharacter.parse(id)
		var whole := c.head == c.torso and c.torso == c.legs
		if kicker == "" and whole and Characters.is_kit(c.torso):
			m.name = Characters.part_name(c.torso)
			m.kicker = "CREATURE"
			m.blurb = Characters.part_info(c.torso).blurb
		else:
			m.name = c.name
			m.kicker = kicker if kicker != "" else "CUSTOM"
			m.blurb = c.blurb()
	else:
		var info := Characters.info(id)
		m.name = info.name
		m.kicker = kicker if kicker != "" else "ROBOT"
		m.blurb = info.blurb
	return m


func _show(i: int) -> void:
	_drop()
	_index = i
	_t = 0.0
	var m: Dictionary = _cast[i]
	var gun := String(m.gun)
	var robot := RobotModel.new().build(m.id, Net.PLAYER_COLORS[i % Net.PLAYER_COLORS.size()], false, gun)
	robot.rotation.y = PI   # facing the camera's starting side
	_stage.add_child(robot)
	_entry = RobotPreview.posed(robot, gun, i * 0.53)
	var box := robot.mesh.get_aabb()
	_height = clampf(box.end.y, 1.0, 2.6) if box.size != Vector3.ZERO else STANDARD_HEIGHT
	var look: Array = LOOKS[i % LOOKS.size()]
	_key.light_color = look[0]
	_rim.light_color = look[1]
	_ring_material.set_shader_parameter("tint", Color(look[1], 0.55))
	_ring.scale = Vector3.ONE * (_height / STANDARD_HEIGHT)
	_place(0.0)


func _drop() -> void:
	if not _entry.is_empty():
		RobotPreview.release(_entry.robot)
	_entry = {}


func _exit_tree() -> void:
	_drop()


func _process(delta: float) -> void:
	if _entry.is_empty() or not is_visible_in_tree():
		return
	_t += delta
	if _t >= SHOT:
		_show((_index + 1) % _cast.size())
	_place(delta)


## Put the camera and lights where this moment of the shot wants them.
func _place(delta: float) -> void:
	_idle += delta
	RobotPreview.pose_at(_entry, _idle + _entry.phase)
	var move: Dictionary = MOVES[_index % MOVES.size()]
	var u := clampf(_t / SHOT, 0.0, 1.0)
	u = lerpf(u, u * u * (3.0 - 2.0 * u), 0.6)   # glides in and out, but never stops
	var h := _height
	var k := h / STANDARD_HEIGHT
	var yaw := deg_to_rad(_between(move.yaw, u))
	var dist: float = _between(move.dist, u) * k
	var eye := Vector3(sin(yaw) * dist, _between(move.y, u) * h, cos(yaw) * dist)
	var target := Vector3(0, _between(move.look, u) * h, 0)
	_camera.fov = move.fov
	_camera.h_offset = move.side * k
	_camera.look_at_from_position(eye, target)
	_camera.rotate_object_local(Vector3.BACK, deg_to_rad(_between(move.roll, u)))
	# Key light high on one side of the camera, the rim behind on the other, both
	# swinging slowly round as the shot goes on.
	var key_yaw := yaw + deg_to_rad(52.0 - 14.0 * u)
	_key.look_at_from_position(Vector3(sin(key_yaw) * 3.2 * k, h * 1.45, cos(key_yaw) * 3.2 * k), Vector3(0, h * 0.62, 0))
	var rim_yaw := yaw + deg_to_rad(-150.0 + 20.0 * u)
	_rim.look_at_from_position(Vector3(sin(rim_yaw) * 3.0 * k, h * 1.25, cos(rim_yaw) * 3.0 * k), Vector3(0, h * 0.7, 0))
	_fill.look_at_from_position(eye + Vector3(0, -1.0, 0), target)
	# Fade the picture in and out, the lights coming up a moment after it.
	_fade = smoothstep(0.0, FADE, _t) * smoothstep(SHOT, SHOT - FADE, _t)
	var lit := smoothstep(0.1, FADE + 0.6, _t) * smoothstep(SHOT, SHOT - FADE * 0.8, _t)
	_key.light_energy = 3.9 * lit   # (tuned for the Filmic look: it holds less in the highlights than AgX did)
	_rim.light_energy = 9.0 * lit
	_feather.set_shader_parameter("fade", _fade)
	queue_redraw()
	_overlay.queue_redraw()


static func _between(pair: Array, u: float) -> float:
	return lerpf(pair[0], pair[1], u)


## Behind the picture: a soft glow on the "wall" behind the character in the rim
## light's colour, and a shaft of light falling from above.
func _draw() -> void:
	if _index < 0:
		return
	var s := size
	var look: Array = LOOKS[_index % LOOKS.size()]
	var move: Dictionary = MOVES[_index % MOVES.size()]
	var c := Vector2(s.x * (0.5 - move.side * 0.32), s.y * 0.46)
	var glow := Color(look[2], 0.20 * _fade)
	_radial(c, Vector2(s.x * 0.42, s.y * 0.55), glow)
	_radial(c, Vector2(s.x * 0.16, s.y * 0.30), Color(look[2], 0.10 * _fade))
	var shaft := Color(look[2], 0.07 * _fade)
	var top := c.x + s.x * 0.06
	draw_polygon(PackedVector2Array([Vector2(top - 40, 0), Vector2(top + 40, 0), Vector2(c.x + 190, s.y), Vector2(c.x - 150, s.y)]),
		PackedColorArray([shaft, shaft, Color(shaft, 0), Color(shaft, 0)]))


## An ellipse of colour fading out to its edge.
func _radial(c: Vector2, r: Vector2, color: Color) -> void:
	var n := 40
	var clear := Color(color, 0)
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		draw_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r]),
			PackedColorArray([color, clear, clear]))


## In front of the picture, along the bottom: what the character is and its name,
## sliding in after the picture fades up; under them a tick for each of the cast
## (this one lit) and the caption.
func _draw_overlay() -> void:
	if _index < 0:
		return
	var s := _overlay.size
	var m: Dictionary = _cast[_index]
	# A dark band along the bottom, so the name reads over a bright character.
	var scrim := Color(0, 0, 0, 0.55 * _fade)
	_overlay.draw_polygon(PackedVector2Array([Vector2(0, s.y - 300.0), Vector2(s.x, s.y - 300.0), Vector2(s.x, s.y), Vector2(0, s.y)]),
		PackedColorArray([Color(scrim, 0), Color(scrim, 0), scrim, scrim]))
	var vis := smoothstep(0.45, 1.35, _t) * smoothstep(SHOT - 0.1, SHOT - FADE * 0.9, _t)
	var slide := (1.0 - smoothstep(0.45, 1.35, _t)) * 36.0
	var x := s.x * 0.22 + 10.0 - slide
	var y := s.y - 210.0
	_overlay.draw_rect(Rect2(x - 18.0, y - 8.0, 4.0, 92.0), Color(UiKit.ACCENT, vis))
	HudStyle.label(_overlay, Vector2(x, y), "%s  ·  %02d / %02d" % [m.kicker, _index + 1, _cast.size()], 13, Color(UiKit.CYAN, 0.9 * vis))
	var name_font := HudStyle.font(true)
	var big := 58
	var base := y + 20.0 + name_font.get_ascent(big)
	_overlay.draw_string_outline(name_font, Vector2(x, base), String(m.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, big, 10, Color(0, 0, 0, 0.35 * vis))
	_overlay.draw_string(name_font, Vector2(x, base), String(m.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, big, Color(1, 1, 1, vis))
	var blurb_font := HudStyle.font(false)
	_overlay.draw_string(blurb_font, Vector2(x, base + 30.0), m.blurb, HORIZONTAL_ALIGNMENT_LEFT, s.x * 0.74, 15,
		Color(UiKit.TEXT_DIM, 0.95 * vis))
	# A tick for each of the cast, and a line filling under this one's as the shot runs.
	var tx := s.x * 0.22 - 8.0
	var ty := s.y - 70.0
	var step := minf(22.0, (s.x * 0.7) / maxf(_cast.size(), 1))
	for k in _cast.size():
		var on := k == _index
		_overlay.draw_rect(Rect2(tx + k * step, ty, step - 6.0, 3.0), Color(UiKit.ACCENT, 0.95) if on else Color(1, 1, 1, 0.18))
	_overlay.draw_rect(Rect2(tx + _index * step, ty + 5.0, (step - 6.0) * clampf(_t / SHOT, 0, 1), 1.0), Color(UiKit.ACCENT, 0.6))
	if caption != "":
		HudStyle.label(_overlay, Vector2(s.x - 40.0, ty + 1.0), caption, 12, Color(UiKit.CYAN, 0.75), HORIZONTAL_ALIGNMENT_RIGHT)
