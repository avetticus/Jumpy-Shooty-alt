extends Node
## Player settings (mouse, camera, audio, graphics) and the control scheme.
## Saved to user://settings.cfg. Every other script reads settings from here.

signal changed

const SAVE_PATH := "user://settings.cfg"

# Controls
var mouse_sensitivity: float = 0.12  # degrees of turn per pixel of mouse movement
var invert_y: bool = false

# Camera
var field_of_view: float = 95.0
var third_person: bool = false

# HUD: which layout to show in each camera view (see HUD_STYLES)
const HUD_STYLES := {"arcs": "Twin arcs (around the crosshair)", "clean": "Clean (corners)"}
var hud_first_person: String = "arcs"
var hud_third_person: String = "clean"
## Scale, opacity, crosshair and which parts of the HUD show (see HudConfig).
var hud := HudConfig.new()
## When you are knocked out, watch the kill again from the eyes of whoever got you.
var killcam: bool = true

# Audio (0..1)
var master_volume: float = 0.8
var music_volume: float = 0.6
var sfx_volume: float = 0.9

# Graphics
var fullscreen: bool = false
var vsync: bool = true
## Vector2i.ZERO means native: the screen's own resolution in fullscreen, and whatever
## size the window is in windowed mode.
var resolution: Vector2i = Vector2i.ZERO
## Frame rate cap. 0 = no cap, -1 = match the monitor's refresh rate.
var frame_rate: int = 0
## What is left of a robot that is knocked out (see Remains).
const GORE := {"full": "Ragdolls and giblets", "ragdolls": "Ragdolls only", "off": "Off"}
var gore: String = "full"
## Graphics quality: a preset from GraphicsQuality.PRESETS, or "custom" when the advanced
## settings below don't match one. "" until the first launch picks one for this computer.
var quality: String = ""
## The advanced settings (see GraphicsQuality for what each does).
var msaa: int = 4
var screen_aa: String = "smaa"
var render_scale: float = 1.0
var fsr_sharpness: float = 0.2
var shadows: String = "high"
var ao: String = "high"
var glow: bool = true
const GRAPHICS_KEYS := ["msaa", "screen_aa", "render_scale", "fsr_sharpness", "shadows", "ao", "glow"]

## Resolutions offered in the menu (only those that fit the screen are shown).
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(3840, 2160), Vector2i(3440, 1440), Vector2i(2560, 1440), Vector2i(2560, 1080),
	Vector2i(1920, 1080), Vector2i(1680, 1050), Vector2i(1600, 900), Vector2i(1366, 768),
	Vector2i(1280, 720),
]
## Frame rate caps offered in the menu, besides "no cap" and "match monitor".
const FRAME_RATES: Array[int] = [30, 60, 75, 120, 144, 165, 240, 360]

# What apply() last put on the window, so it only resizes when the resolution changes.
var _resolution_scale := 1.0   # how much of the screen 3D is drawn at, from the fullscreen Resolution
var _applied_resolution := Vector2i(-1, -1)
var _applied_fullscreen := false

# Profile
var player_name: String = ""
var character: String = Characters.default_id()   # the robot you play as (see Characters)
var weapon: String = WeaponData.default_id()       # the gun you take into matches (see WeaponData)
var mobility: String = Mobility.default_id()       # the tool on the mobility button: the grappling hook (see Mobility)
var player_color := -1   # your colour in a free-for-all: a number in Net.PLAYER_COLORS, or -1 for the first free one
var calling_card: String = CallingCard.DEFAULT_CARD   # the banner behind your name (see CallingCard)
var icon: String = CallingCard.DEFAULT_ICON           # the badge beside it
## Characters made in the Character Creator, as ids (see CustomCharacter), newest last.
var custom_characters: Array = []
const MAX_CUSTOM := 12
## Achievements you track (up to Achievements.MAX_TRACKED ids): the Profile page shows them first.
var tracked_achievements: Array = []
## When the profile (name, characters, card, picks, tracked achievements) last changed
## here (unix seconds): an account's cloud save keeps whichever copy is newer (see CloudSave).
var profile_updated_at := 0.0
var _profile_key := ""
var last_address: String = ""   # the lobby code (or address) you last joined (filled in on the Join box next time)


## The settings were written (Account syncs a signed-in player's profile from this).
signal saved


func _ready() -> void:
	_setup_input_map()
	load_settings()
	if quality == "":
		set_quality(GraphicsQuality.first_launch())
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cfg.get_value("controls", "invert_y", invert_y)
	field_of_view = cfg.get_value("camera", "field_of_view", field_of_view)
	third_person = cfg.get_value("camera", "third_person", third_person)
	hud_first_person = _hud_style(cfg.get_value("hud", "first_person", hud_first_person))
	hud_third_person = _hud_style(cfg.get_value("hud", "third_person", hud_third_person))
	killcam = bool(cfg.get_value("hud", "killcam", killcam))
	hud.load_from(cfg)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	music_volume = cfg.get_value("audio", "music_volume", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)
	fullscreen = cfg.get_value("graphics", "fullscreen", fullscreen)
	vsync = cfg.get_value("graphics", "vsync", vsync)
	var res = cfg.get_value("graphics", "resolution", resolution)
	resolution = res if res is Vector2i else Vector2i.ZERO
	frame_rate = int(cfg.get_value("graphics", "frame_rate", frame_rate))
	var g := str(cfg.get_value("graphics", "gore", gore))
	gore = g if GORE.has(g) else "full"
	if cfg.has_section_key("graphics", "quality"):
		var picks := {}
		for k in GRAPHICS_KEYS:
			picks[k] = cfg.get_value("graphics", k, get(k))
		set_graphics(GraphicsQuality.clean(picks))
		quality = GraphicsQuality.matching(graphics())
	player_name = cfg.get_value("profile", "player_name", player_name)
	character = Characters.valid(str(cfg.get_value("profile", "character", character)))
	player_color = clampi(int(cfg.get_value("profile", "color", player_color)), -1, 15)
	calling_card = CallingCard.valid_card(str(cfg.get_value("profile", "calling_card", calling_card)))
	icon = CallingCard.valid_icon(str(cfg.get_value("profile", "icon", icon)))
	custom_characters.clear()
	var saved = cfg.get_value("creator", "characters", [])
	if saved is Array:
		for id in saved:
			if Characters.is_custom(str(id)) and custom_characters.size() < MAX_CUSTOM:
				custom_characters.append(Characters.valid(str(id)))
	weapon = WeaponData.valid(str(cfg.get_value("profile", "weapon", weapon)))
	mobility = Mobility.valid(str(cfg.get_value("profile", "mobility", mobility)))
	last_address = str(cfg.get_value("network", "last_address", last_address))
	tracked_achievements.clear()
	var tracked = cfg.get_value("profile", "tracked", [])
	if tracked is Array:
		for id in tracked:
			if not str(id) in tracked_achievements:
				tracked_achievements.append(str(id))
	profile_updated_at = float(cfg.get_value("profile", "updated_at", 0.0))
	_profile_key = profile_key()
	_load_bindings(cfg)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("camera", "field_of_view", field_of_view)
	cfg.set_value("camera", "third_person", third_person)
	cfg.set_value("hud", "first_person", hud_first_person)
	cfg.set_value("hud", "third_person", hud_third_person)
	cfg.set_value("hud", "killcam", killcam)
	hud.save_to(cfg)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "resolution", resolution)
	cfg.set_value("graphics", "frame_rate", frame_rate)
	cfg.set_value("graphics", "gore", gore)
	if quality != "":
		cfg.set_value("graphics", "quality", quality)
		for k in GRAPHICS_KEYS:
			cfg.set_value("graphics", k, get(k))
	cfg.set_value("profile", "player_name", player_name)
	cfg.set_value("profile", "character", character)
	cfg.set_value("profile", "color", player_color)
	cfg.set_value("profile", "calling_card", calling_card)
	cfg.set_value("profile", "icon", icon)
	cfg.set_value("creator", "characters", custom_characters)
	cfg.set_value("profile", "weapon", weapon)
	cfg.set_value("profile", "mobility", mobility)
	cfg.set_value("network", "last_address", last_address)
	cfg.set_value("profile", "tracked", tracked_achievements)
	if profile_key() != _profile_key:
		_profile_key = profile_key()
		profile_updated_at = Time.get_unix_time_from_system()
	cfg.set_value("profile", "updated_at", profile_updated_at)
	_save_bindings(cfg)
	cfg.save(SAVE_PATH)
	saved.emit()


## The profile's fields in one string, to tell when one of them changed.
func profile_key() -> String:
	return var_to_str([player_name, character, player_color, calling_card, icon, weapon, mobility,
		custom_characters, tracked_achievements])


## Take a profile from the cloud (see CloudSave) without marking it as changed here.
func adopt_profile(updated_at: float) -> void:
	_profile_key = profile_key()
	profile_updated_at = updated_at


## Keep a custom character (replacing one with the same name). Returns its id.
func save_custom(c: CustomCharacter) -> String:
	var id := c.to_id()
	var at := custom_index(c.name)
	if at >= 0:
		custom_characters[at] = id
	else:
		if custom_characters.size() >= MAX_CUSTOM:
			custom_characters.pop_front()
		custom_characters.append(id)
	save_settings()
	return id


## Where the saved custom character with this name is, or -1.
func custom_index(char_name: String) -> int:
	for i in custom_characters.size():
		if CustomCharacter.parse(custom_characters[i]).name == CustomCharacter.clean_name(char_name):
			return i
	return -1


func delete_custom(id: String) -> void:
	custom_characters.erase(Characters.valid(id))
	if character == Characters.valid(id):
		character = Characters.default_id()
	save_settings()


func apply() -> void:
	if DisplayServer.get_name() != "headless":
		# Windowed: only leave fullscreen, so a window you maximized stays maximized.
		var current := DisplayServer.window_get_mode()
		var is_full := current == DisplayServer.WINDOW_MODE_FULLSCREEN or current == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if fullscreen and not is_full:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not fullscreen and is_full:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		_apply_resolution()
		Engine.max_fps = monitor_refresh_rate() if frame_rate < 0 else frame_rate
		_apply_graphics()
	changed.emit()   # Sound puts the volumes on the audio buses


## Fullscreen always covers the screen at its own resolution (the game can't change the
## monitor's mode), so there the chosen resolution sets how sharp the 3D picture is drawn
## before it is stretched to fill the screen; menus and the HUD stay sharp. In windowed
## mode it sets the window size (Native maximizes the window).
func _apply_resolution() -> void:
	var screen := screen_size()
	var res := resolution
	if res.x > screen.x or res.y > screen.y:
		res = Vector2i.ZERO   # saved on a bigger monitor: fall back to native
	_resolution_scale = clampf(float(res.y) / screen.y, 0.25, 1.0) if fullscreen and res != Vector2i.ZERO else 1.0
	if res == _applied_resolution and fullscreen == _applied_fullscreen:
		return
	var first := _applied_resolution == Vector2i(-1, -1)
	_applied_resolution = res
	_applied_fullscreen = fullscreen
	# Copies started side by side by tools/run_local keep the window --window gave them.
	var dev_args := get_node_or_null("/root/DevArgs")
	if fullscreen or (dev_args and dev_args.window_rect.size != Vector2i.ZERO):
		return
	if res == Vector2i.ZERO:
		# Native in a window: fill the screen (but leave the window alone at startup).
		if not first:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_size(res)
	DisplayServer.window_set_position(usable.position + (usable.size - res) / 2)


## The graphics picks (see GraphicsQuality) on the window, the renderer and the maps.
func _apply_graphics() -> void:
	var picks := graphics()
	GraphicsQuality.apply_global(picks)
	if is_inside_tree():
		var root := get_tree().root
		GraphicsQuality.apply_viewport(root, picks, _resolution_scale)
		GraphicsQuality.apply_environments(root, picks)


## How much of the screen's resolution 3D is drawn at before the render scale (the
## fullscreen Resolution setting; 1 in a window).
func resolution_scale() -> float:
	return _resolution_scale


## The advanced graphics settings, as GraphicsQuality takes them.
func graphics() -> Dictionary:
	var picks := {}
	for k in GRAPHICS_KEYS:
		picks[k] = get(k)
	return picks


func set_graphics(picks: Dictionary) -> void:
	for k in GRAPHICS_KEYS:
		if picks.has(k):
			set(k, picks[k])


## Pick a preset ("low", "medium", "high"): every advanced setting follows it.
func set_quality(id: String) -> void:
	if GraphicsQuality.PRESETS.has(id):
		set_graphics(GraphicsQuality.preset(id))
	quality = GraphicsQuality.matching(graphics())


func screen_size() -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return Vector2i(1920, 1080)
	return DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())


## The monitor's refresh rate in Hz, rounded (60 if the system won't say).
func monitor_refresh_rate() -> int:
	var hz := -1.0
	if DisplayServer.get_name() != "headless":
		hz = DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())
	return roundi(hz) if hz > 0.0 else 60


## Resolution choices for the menu: stored value -> text. Only those that fit the screen.
func resolution_choices() -> Dictionary:
	var screen := screen_size()
	var choices := {Vector2i.ZERO: "Native (%d x %d)" % [screen.x, screen.y]}
	for r in RESOLUTIONS:
		if r.x <= screen.x and r.y <= screen.y and r != screen:
			choices[r] = "%d x %d" % [r.x, r.y]
	return choices


## Frame rate choices for the menu: stored value -> text.
func frame_rate_choices() -> Dictionary:
	var choices := {-1: "Match monitor (%d Hz)" % monitor_refresh_rate()}
	for f in FRAME_RATES:
		choices[f] = "%d fps" % f
	choices[0] = "No cap"
	return choices


## The HUD layout for the current camera view.
func hud_style() -> String:
	return hud_third_person if third_person else hud_first_person


static func _hud_style(value) -> String:
	return str(value) if HUD_STYLES.has(str(value)) else "arcs"


## Settings → HUD → Reset HUD: both layouts and every HUD option back to the defaults
## (the killcam switch, on the Camera tab, stays as it is).
func reset_hud() -> void:
	hud_first_person = "arcs"
	hud_third_person = "clean"
	hud.reset()
	changed.emit()


func set_third_person(value: bool) -> void:
	third_person = value
	save_settings()
	changed.emit()


# ---------------------------------------------------------------------------
# Controls. The defaults are defined in code; the Controls tab on the Settings menu
# rebinds them, and anything changed is saved under [bindings] in settings.cfg.
# A binding is "key:<physical keycode>" or "mouse:<button index>".

## Rebindable actions in the order the Controls tab lists them: [action, label, defaults].
## Each action has up to MAX_BINDS bindings.
const ACTIONS := [
	["move_forward", "Move forward", ["key:%d" % KEY_W]],
	["move_back", "Move back", ["key:%d" % KEY_S]],
	["move_left", "Move left", ["key:%d" % KEY_A]],
	["move_right", "Move right", ["key:%d" % KEY_D]],
	["jump", "Jump (mid-air: flip; hold: jetpack)", ["key:%d" % KEY_SPACE]],
	["sprint", "Sprint", ["key:%d" % KEY_SHIFT]],
	["glide", "Glide (hold in mid-air)", ["key:%d" % KEY_ALT]],
	["crouch", "Crouch / slide", ["key:%d" % KEY_CTRL, "key:%d" % KEY_C]],
	["dive", "Dive", ["key:%d" % KEY_Q]],
	["kick", "Kick", ["key:%d" % KEY_F]],
	["boost", "Rocket boots", ["key:%d" % KEY_E]],
	["interact", "Interact", ["key:%d" % KEY_G]],
	["grapple", "Grappling hook", ["mouse:%d" % MOUSE_BUTTON_MIDDLE]],
	["fire", "Shoot / swing", ["mouse:%d" % MOUSE_BUTTON_LEFT]],
	["reload", "Reload (race: last checkpoint)", ["key:%d" % KEY_R]],
	["weapon_1", "Weapon slot 1", ["key:%d" % KEY_1]],
	["weapon_2", "Weapon slot 2", ["key:%d" % KEY_2]],
	["weapon_3", "Weapon group 3 (respawn pick)", ["key:%d" % KEY_3]],
	["weapon_4", "Weapon group 4 (respawn pick)", ["key:%d" % KEY_4]],
	["weapon_5", "Weapon group 5 (respawn pick)", ["key:%d" % KEY_5]],
	["weapon_6", "Weapon group 6 (respawn pick)", ["key:%d" % KEY_6]],
	["weapon_next", "Next weapon", ["mouse:%d" % MOUSE_BUTTON_WHEEL_DOWN]],
	["weapon_prev", "Previous weapon", ["mouse:%d" % MOUSE_BUTTON_WHEEL_UP]],
	["toggle_camera", "First / third person", ["key:%d" % KEY_V]],
	["scoreboard", "Scoreboard (hold)", ["key:%d" % KEY_TAB]],
	["debug_menu", "Debug menu (Practice, Vs Bots)", ["key:%d" % KEY_F1, "key:%d" % KEY_QUOTELEFT]],
]
const MAX_BINDS := 2
## Pairs of actions that may share a key without it counting as a conflict
## (sprint is for the ground, glide for the air).
const CAN_SHARE := [["sprint", "glide"]]
## Saved bindings older than this are brought up to date as they load (see _load_bindings).
## 2: the glide moved from Shift to Alt, which Dive gave up.
## 3: the mobility button moved from right mouse to middle mouse (see _mobility_to_middle).
const BINDINGS_VERSION := 3

## Not rebindable: Esc always opens the menu (and cancels a rebind).
const FIXED_BINDINGS := {"pause": ["key:%d" % KEY_ESCAPE]}

## The current bindings: action -> Array of binding strings.
var bindings := {}


func default_bindings(action: String) -> Array:
	for a in ACTIONS:
		if a[0] == action:
			return (a[2] as Array).duplicate()
	return []


func _setup_input_map() -> void:
	for a in ACTIONS:
		bindings[a[0]] = (a[2] as Array).duplicate()
	for action in FIXED_BINDINGS:
		_ensure_action(action)
		for b in FIXED_BINDINGS[action]:
			InputMap.action_add_event(action, binding_event(b))
	_apply_bindings()


func _apply_bindings() -> void:
	for action in bindings:
		_ensure_action(action)
		for b in bindings[action]:
			var ev := binding_event(b)
			if ev:
				InputMap.action_add_event(action, ev)


func _load_bindings(cfg: ConfigFile) -> void:
	var version := int(cfg.get_value("bindings", "version", 1))
	var alt := "key:%d" % KEY_ALT
	for a in ACTIONS:
		var saved = cfg.get_value("bindings", a[0]) if cfg.has_section_key("bindings", a[0]) else null
		if saved == null and a[0] == "glide" and cfg.has_section_key("bindings", "float"):
			saved = cfg.get_value("bindings", "float")   # the glide used to be the float: keep a key chosen for it
		if version < 2 and a[0] == "glide":
			saved = null   # the glide moved to Alt: a key saved for it before goes back to that
		if saved is Array:
			var list := []
			for b in saved:
				if version < 2 and str(b) == alt and a[0] != "glide":
					continue   # (Alt is the glide's now: Dive, or anything else saved with it, gives it up)
				if binding_event(str(b)) and not list.has(str(b)) and list.size() < MAX_BINDS:
					list.append(str(b))
			bindings[a[0]] = list
	if version < 3:
		_mobility_to_middle(cfg.has_section_key("bindings", "grapple"))
	_apply_bindings()


## Bindings saved before version 3: the mobility button was on right mouse (the default
## then, so only saved if you changed it), and it is on middle mouse now. A right mouse
## it had moves to middle mouse; with nothing saved for it, it takes the new default.
## Only if you had put middle mouse on something else does it keep right mouse instead,
## as it was, so nothing you chose is taken from you.
func _mobility_to_middle(saved: bool) -> void:
	var right := "mouse:%d" % MOUSE_BUTTON_RIGHT
	var middle := "mouse:%d" % MOUSE_BUTTON_MIDDLE
	var middle_taken := false
	for a in ACTIONS:
		if a[0] != "grapple" and (bindings[a[0]] as Array).has(middle):
			middle_taken = true
	var list: Array = (bindings["grapple"] as Array).duplicate() if saved else [right]   # (nothing saved: it had the old default)
	var i := list.find(right)
	if i >= 0 and not middle_taken and not list.has(middle):
		list[i] = middle
	bindings["grapple"] = list


func _save_bindings(cfg: ConfigFile) -> void:
	cfg.set_value("bindings", "version", BINDINGS_VERSION)
	for a in ACTIONS:
		if bindings[a[0]] != a[2]:
			cfg.set_value("bindings", a[0], bindings[a[0]])


## Puts `binding` in slot `slot` of `action` (an empty binding clears the slot). If
## another action had it, that action loses it. Returns the labels of the actions it
## was taken from (empty when it was free).
func rebind(action: String, slot: int, binding: String) -> Array:
	var taken := []
	if binding != "":
		if FIXED_BINDINGS.pause.has(binding):
			return taken
		for a in ACTIONS:
			if a[0] != action and bindings[a[0]].has(binding) and not _can_share(action, a[0]):
				bindings[a[0]].erase(binding)
				taken.append(a[1])
	var list: Array = bindings[action]
	list.erase(binding)
	if slot < list.size():
		if binding == "":
			list.remove_at(slot)
		else:
			list[slot] = binding
	elif binding != "":
		list.append(binding)
	_apply_bindings()
	save_settings()
	return taken


static func _can_share(a: String, b: String) -> bool:
	for pair in CAN_SHARE:
		if pair.has(a) and pair.has(b):
			return true
	return false


func reset_bindings() -> void:
	for a in ACTIONS:
		bindings[a[0]] = (a[2] as Array).duplicate()
	_apply_bindings()
	save_settings()


## The binding string for a key or mouse button press, or "" if it can't be bound.
static func event_binding(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
		return "key:%d" % code if code != KEY_NONE else ""
	if ev is InputEventMouseButton and ev.button_index != MOUSE_BUTTON_NONE:
		return "mouse:%d" % ev.button_index
	return ""


static func binding_event(b: String) -> InputEvent:
	var parts := b.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	var code := int(parts[1])
	if parts[0] == "key" and code > 0:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		return ev
	if parts[0] == "mouse" and code > 0:
		var ev := InputEventMouseButton.new()
		ev.button_index = code
		return ev
	return null


const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse", MOUSE_BUTTON_MIDDLE: "Middle mouse",
	MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down",
	MOUSE_BUTTON_WHEEL_LEFT: "Wheel left", MOUSE_BUTTON_WHEEL_RIGHT: "Wheel right",
	MOUSE_BUTTON_XBUTTON1: "Mouse 4", MOUSE_BUTTON_XBUTTON2: "Mouse 5",
}


## How a binding is shown: the key as printed on your keyboard layout, or the mouse button.
static func binding_text(b: String) -> String:
	var ev := binding_event(b)
	if ev is InputEventMouseButton:
		return MOUSE_NAMES.get(ev.button_index, "Mouse %d" % ev.button_index)
	if ev is InputEventKey:
		var code: int = ev.physical_keycode
		if DisplayServer.get_name() != "headless":
			var local := DisplayServer.keyboard_get_keycode_from_physical(code)
			if local != KEY_NONE:
				code = local
		return OS.get_keycode_string(code)
	return ""


## Everything bound to `action`, as shown in menus ("Q / Alt"); "-" when nothing is.
func action_text(action: String) -> String:
	var names := []
	for b in bindings.get(action, []):
		names.append(binding_text(b))
	return " / ".join(names) if not names.is_empty() else "-"


func _ensure_action(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
