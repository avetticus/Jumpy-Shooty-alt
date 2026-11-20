class_name SettingsPanel
extends VBoxContainer
## Settings, used from the main menu and the in-game pause menu. Built in a
## MenuFrame: the title and tabs stay at the top and Back at the bottom while the
## tab's own controls scroll between them if the window is short.
## Five tabs (Controls, Camera, HUD, Audio, Graphics); every change applies at once
## (Controls also rebinds keys: click one, then press the new key or mouse button)
## and is saved when you leave, except the display and quality settings on the Graphics tab: those
## wait for Apply, and a new resolution or screen mode puts itself back after a few
## seconds unless you press Keep (in case the new one is unusable).
## HUD has its own tab because of its preview (HudPreview), which sits in the header
## under the tabs so it stays in view while the HUD options scroll under it.

signal closed

const TABS := ["Controls", "Camera", "HUD", "Audio", "Graphics"]
const HUD_TAB := 2
## The short controls list on the pause menu: [action, description]. Keys come from
## the current bindings.
const CHEAT_SHEET := [
	["move", "Move"], ["sprint", "Sprint"], ["glide", "Glide: hold in mid-air (weakens the longer you hold)"], ["jump", "Jump; again in mid-air to flip; hold in mid-air: jetpack"],
	["crouch", "Crouch; moving forward: dive, moving back: slide on your back"], ["dive", "Dive (keep holding to land in a belly slide)"],
	["kick", "Kick"], ["boost", "Rocket boots"], ["grapple", "Grappling hook"],
	["interact", "Interact: press at a map terminal"],
	["fire", "Shoot; melee: hold to wind up, let go to swing"], ["reload", "Reload"],
	["toggle_camera", "First / third person"], ["scoreboard", "Scoreboard"],
	["debug_menu", "Debug menu (Practice and Vs Bots)"],
]

const DISPLAY_KEYS := ["fullscreen", "vsync", "resolution", "frame_rate", "quality",
	"msaa", "screen_aa", "render_scale", "fsr_sharpness", "shadows", "ao", "glow"]
const CONFIRM_SECONDS := 15

static var _last_tab := 0
static var _preview_third := false   # the HUD preview showed the third-person layout last
static var _advanced_open := false   # the Graphics tab's advanced settings were showing last

var _frame: MenuFrame
var _preview: HudPreview   # HUD tab, in the frame's header
var _page: VBoxContainer
var _pending := {}       # display settings picked on the Graphics tab, not applied yet
var _revert_to := {}     # what Revert (or running out of time) puts back
var _countdown := 0
var _timer: Timer
var _apply_btn: Button
var _confirm_row: HBoxContainer
var _confirm_label: Label
var _listen: Array = []      # [action, slot] waiting for a key or mouse button (Controls tab)
var _binds_box: VBoxContainer
var _bind_note: Label
var _into: Control       # where _row, _switch, _option and _slider put things (null: the page)
var _quality_btn: OptionButton
var _advanced: VBoxContainer
var _last_option: OptionButton   # the drop-down _option made last


## `frame`: the page this panel is built in. The title and the tabs go in its header
## and Back in its footer, so they stay on screen while a long tab (Controls) scrolls.
func _init(frame: MenuFrame = null) -> void:
	_frame = frame


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var top: Node = _frame.header if _frame else self
	UiKit.title(top, "Settings", 38, false, "Options")
	UiKit.segmented(top, TABS, _last_tab, _show_tab)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 12)
	add_child(_page)
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_preview_third = Settings.third_person   # the HUD preview starts on the view you play in
	_show_tab(_last_tab)
	if _frame:
		_frame.back_button("Back", _on_back)
	else:
		UiKit.button(self, "Back", _on_back)


func _show_tab(i: int) -> void:
	_last_tab = i
	_stop_listening()
	_on_keep()   # leaving the tab while asked to keep new display settings keeps them
	UiKit.clear(_page)
	if is_instance_valid(_preview):
		_preview_third = _preview.third_person
		if _preview.get_parent():
			_preview.get_parent().remove_child(_preview)
		_preview.queue_free()
	match i:
		0:
			UiKit.section(_page, "Mouse")
			_slider("Sensitivity", 0.02, 0.5, 0.01, Settings.mouse_sensitivity, func(v): Settings.mouse_sensitivity = v)
			_switch("Invert mouse Y", Settings.invert_y, func(v): Settings.invert_y = v)
			_build_bindings()
		1:
			UiKit.section(_page, "Camera")
			_slider("Field of view", 70.0, 120.0, 1.0, Settings.field_of_view, func(v): Settings.field_of_view = v)
			_switch("Third-person camera (V switches in game)", Settings.third_person, func(v): Settings.third_person = v)
			_switch("Killcam when you are knocked out (Space skips it)", Settings.killcam, func(v): Settings.killcam = v)
		HUD_TAB:
			_build_hud()
		3:
			UiKit.section(_page, "Volume")
			_slider("Master", 0.0, 1.0, 0.05, Settings.master_volume, func(v): Settings.master_volume = v, true)
			_slider("Music", 0.0, 1.0, 0.05, Settings.music_volume, func(v): Settings.music_volume = v, true)
			_slider("Effects", 0.0, 1.0, 0.05, Settings.sfx_volume, func(v): Settings.sfx_volume = v, true)
		4:
			_build_display()
			UiKit.section(_page, "Effects")
			_option("Knocked-out robots", Settings.GORE, Settings.gore, func(v): Settings.gore = v)
			UiKit.label(_page, "A knocked-out robot falls as a ragdoll, and one that is blown up or hit far harder than it needed bursts into pieces. Either burns away after a few seconds.", true, 15)
			_build_benchmark()


## Graphics tab: the benchmark (see Benchmark). Menus only: it leaves the match screen.
func _build_benchmark() -> void:
	UiKit.section(_page, "Benchmark")
	UiKit.label(_page, "Flies a camera over %s for about %d seconds each and times every frame, at your window size and settings (vsync and the frame-rate cap are off while it runs). It saves a report you can open afterwards. Esc stops it." % [
		", ".join(Benchmark.MAPS.map(Maps.name_of)), roundi(Benchmark.WARMUP + Benchmark.ORBIT_TIME + Benchmark.STOPS * Benchmark.STOP_TIME)], true, 15)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_page.add_child(row)
	var run := UiKit.button(row, "Run benchmark", func():
		_on_back()
		Game.start_benchmark())
	run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.button(row, "Open reports folder", func():
		DirAccess.make_dir_recursive_absolute(Benchmark.FOLDER)
		OS.shell_open(Benchmark.folder()))
	if Net.in_match:
		run.disabled = true
		UiKit.label(_page, "Leave the match to run the benchmark.", true, 15)


func _on_back() -> void:
	_stop_listening()
	_on_keep()
	Settings.save_settings()
	closed.emit()


## Open on this tab next time (dev: screenshots of each tab).
static func open_on_tab(i: int) -> void:
	_last_tab = clampi(i, 0, TABS.size() - 1)


## Each pause-menu line: [keys, description].
static func cheat_sheet() -> Array:
	var rows := []
	for c in CHEAT_SHEET:
		var keys: String
		if c[0] == "move":
			keys = " ".join(["move_forward", "move_left", "move_back", "move_right"].map(Settings.action_text))
		else:
			keys = Settings.action_text(c[0])
		rows.append([keys, c[1]])
	return rows


# ---------------------------------------------------------------------------
# HUD tab: the layout for each view, then tuning on top of it (see HudConfig), with
# a live preview in the header.

func _build_hud() -> void:
	var hud := Settings.hud
	_preview = HudPreview.new(_preview_third)
	(_frame.header if _frame else _page).add_child(_preview)
	UiKit.section(_page, "Layout")
	_option("In first person", Settings.HUD_STYLES, Settings.hud_first_person, func(v): Settings.hud_first_person = v)
	_option("In third person", Settings.HUD_STYLES, Settings.hud_third_person, func(v): Settings.hud_third_person = v)
	UiKit.label(_page, "Twin arcs keeps health, ammo and move cooldowns round the crosshair. Clean puts them in the bottom corners.", true, 15)
	UiKit.section(_page, "Size and opacity")
	_slider("HUD scale", HudConfig.SPEC.scale[1], HudConfig.SPEC.scale[2], 0.05, hud.scale, func(v): hud.scale = v, true)
	_slider("HUD opacity", HudConfig.SPEC.opacity[1], HudConfig.SPEC.opacity[2], 0.05, hud.opacity, func(v): hud.opacity = v, true)
	UiKit.label(_page, "Scale and opacity cover everything you see while playing; the crosshair has its own size below and never fades. The killcam, death screen and scoreboard stay as they are.", true, 15)
	UiKit.section(_page, "Crosshair")
	_option("Style", HudConfig.CROSSHAIRS, hud.crosshair, func(v): hud.crosshair = v)
	_option("Colour", HudConfig.COLOR_NAMES, hud.crosshair_color, func(v): hud.crosshair_color = v)
	_slider("Size", HudConfig.SPEC.crosshair_size[1], HudConfig.SPEC.crosshair_size[2], 0.05, hud.crosshair_size, func(v): hud.crosshair_size = v, true)
	_slider("Gap", HudConfig.SPEC.crosshair_gap[1], HudConfig.SPEC.crosshair_gap[2], 1.0, hud.crosshair_gap, func(v): hud.crosshair_gap = v)
	_slider("Thickness", HudConfig.SPEC.crosshair_thickness[1], HudConfig.SPEC.crosshair_thickness[2], 1.0, hud.crosshair_thickness,
		func(v): hud.crosshair_thickness = v)
	_switch("Dark outline", hud.crosshair_outline, func(v): hud.crosshair_outline = v)
	_switch("Centre dot", hud.crosshair_dot, func(v): hud.crosshair_dot = v)
	UiKit.label(_page, "Weapon's own changes with the weapon: a cross, the shotgun's brackets, a ring for launchers, ticks round a dot for the marksman rifles.", true, 15)
	UiKit.section(_page, "Show")
	_switch("Hit markers", hud.hit_markers, func(v): hud.hit_markers = v)
	_switch("Damage numbers", hud.damage_numbers, func(v): hud.damage_numbers = v)
	_switch("Speed and what you are doing", hud.speed, func(v): hud.speed = v)
	_switch("Killcam score when you get a kill", hud.killcam_points, func(v): hud.killcam_points = v)
	_option("Moves", HudConfig.MOVES, hud.moves, func(v): hud.moves = v)
	_option("Kill feed", HudConfig.FEED_CORNERS, hud.feed_corner, func(v): hud.feed_corner = v)
	_slider("Kill feed lines", HudConfig.SPEC.feed_lines[1], HudConfig.SPEC.feed_lines[2], 1.0, hud.feed_lines, func(v): hud.feed_lines = int(v))
	UiKit.button(_page, "Reset HUD", func():
		Settings.reset_hud()
		_show_tab(HUD_TAB))


# ---------------------------------------------------------------------------
# Controls tab: click a binding, then press a key or mouse button for it.

func _build_bindings() -> void:
	UiKit.section(_page, "Keys")
	UiKit.label(_page, "Click a key, then press the new key or mouse button. Esc cancels, Backspace clears it. A key already used elsewhere moves here.", true, 15)
	_bind_note = UiKit.label(_page, "", false, 15)
	_bind_note.add_theme_color_override("font_color", UiKit.ACCENT)
	_bind_note.visible = false
	_binds_box = VBoxContainer.new()   # the page's frame scrolls: no second scroll bar inside it
	_binds_box.add_theme_constant_override("separation", 4)
	_binds_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_child(_binds_box)
	_fill_bindings()
	UiKit.button(_page, "Reset controls to defaults", func():
		_stop_listening()
		Settings.reset_bindings()
		_note("Controls reset to the defaults.")
		_fill_bindings())


func _fill_bindings() -> void:
	if not is_instance_valid(_binds_box):
		return
	UiKit.clear(_binds_box)
	for a in Settings.ACTIONS:
		var action: String = a[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_binds_box.add_child(row)
		var l := UiKit.label(row, a[1], false, 16)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var list: Array = Settings.bindings[action]
		if list.is_empty():
			l.add_theme_color_override("font_color", UiKit.ACCENT)
		for slot in Settings.MAX_BINDS:
			var b := Button.new()
			b.theme_type_variation = "Chip"
			b.custom_minimum_size = Vector2(150, 38)
			b.clip_text = true
			b.focus_mode = Control.FOCUS_NONE   # so Space or Enter can be bound, not press it again
			if slot < list.size():
				b.text = Settings.binding_text(list[slot])
			else:
				b.text = "Unbound" if slot == 0 else "+"
				b.modulate = Color(1, 1, 1, 0.55)
			b.pressed.connect(_start_listening.bind(action, mini(slot, list.size()), b))
			row.add_child(b)
		var reset := Button.new()
		reset.text = "↺"
		reset.theme_type_variation = "Chip"
		reset.tooltip_text = "Back to the default for this action"
		reset.custom_minimum_size = Vector2(38, 38)
		reset.focus_mode = Control.FOCUS_NONE
		reset.disabled = list == Settings.default_bindings(action)
		reset.pressed.connect(func():
			_stop_listening()
			_reset_action(action))
		row.add_child(reset)


func _reset_action(action: String) -> void:
	while not Settings.bindings[action].is_empty():
		Settings.rebind(action, 0, "")
	var taken := []
	for b in Settings.default_bindings(action):
		taken.append_array(Settings.rebind(action, Settings.bindings[action].size(), b))
	_report(taken, action)
	_fill_bindings()


func _start_listening(action: String, slot: int, b: Button) -> void:
	_stop_listening()
	_listen = [action, slot]
	b.text = "Press a key..."
	b.modulate = UiKit.ACCENT


func _stop_listening() -> void:
	if _listen.is_empty():
		return
	_listen = []
	_fill_bindings()


func _input(event: InputEvent) -> void:
	if _listen.is_empty() or not is_visible_in_tree():
		return
	if not (event is InputEventKey or event is InputEventMouseButton) or not event.pressed or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	var action: String = _listen[0]
	var slot: int = _listen[1]
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		_stop_listening()
		return
	var binding := Settings.event_binding(event)
	if event is InputEventKey and event.keycode == KEY_BACKSPACE:
		binding = ""
	elif binding == "":
		return
	_listen = []
	var taken := Settings.rebind(action, slot, binding)
	_report(taken, action)
	_fill_bindings()


func _report(taken: Array, action: String) -> void:
	if taken.is_empty():
		_note("")
		return
	var label := ""
	for a in Settings.ACTIONS:
		if a[0] == action:
			label = a[1]
	_note("Moved from %s to %s." % [", ".join(taken), label])


func _note(text: String) -> void:
	if is_instance_valid(_bind_note):
		_bind_note.text = text
		_bind_note.visible = text != ""


# ---------------------------------------------------------------------------
# Graphics tab: display and quality settings wait for Apply.

func _build_display() -> void:
	_pending = _current_display()
	UiKit.section(_page, "Display")
	_switch("Fullscreen", _pending.fullscreen, func(v): _pick("fullscreen", v), false)
	_switch("V-Sync", _pending.vsync, func(v): _pick("vsync", v), false)
	_option("Resolution", Settings.resolution_choices(), _pending.resolution, func(v): _pick("resolution", v), false)
	_option("Frame rate", Settings.frame_rate_choices(), _pending.frame_rate, func(v): _pick("frame_rate", v), false)
	UiKit.label(_page, "Windowed, Resolution sets the window size. In fullscreen it sets how sharp the 3D world is drawn (you'll see it in a match, not in menus). Frame rate caps how fast the game draws; your monitor's refresh rate is set in your computer's display settings.", true, 15)
	_build_quality()
	if Engine.is_embedded_in_editor():
		var note := UiKit.label(_page, "You're running the game inside the Godot editor, which keeps it in its own panel, so window size and fullscreen won't change here. They work in the exported game, or after turning off \"Embed Game on Next Play\" in the editor's Game tab.", false, 15)
		note.add_theme_color_override("font_color", UiKit.ACCENT)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	_page.add_child(bar)
	_apply_btn = UiKit.primary_button(bar, "Apply", _on_apply)
	_apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_row = HBoxContainer.new()
	_confirm_row.add_theme_constant_override("separation", 12)
	_page.add_child(_confirm_row)
	_confirm_label = UiKit.label(_confirm_row, "", false, 18)
	_confirm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.button(_confirm_row, "Keep", _on_keep).custom_minimum_size.x = 120
	UiKit.button(_confirm_row, "Revert", _on_revert).custom_minimum_size.x = 120
	_confirm_row.visible = false
	_update_apply()


## Quality: a preset, and under it the advanced settings it stands for (changing one of
## those makes the preset Custom).
func _build_quality() -> void:
	UiKit.section(_page, "Quality")
	_option("Quality", GraphicsQuality.QUALITY_NAMES, _pending.quality, _pick_quality, false)
	_quality_btn = _last_option
	UiKit.label(_page, "High suits a gaming PC; Low keeps laptops and built-in graphics smooth. Run the benchmark below to see how your computer does.", true, 15)
	var open := Button.new()
	open.theme_type_variation = "Chip"
	open.focus_mode = Control.FOCUS_NONE
	open.custom_minimum_size = Vector2(0, 38)
	open.text = "Advanced  ▾" if _advanced_open else "Advanced  ▸"
	open.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_page.add_child(open)
	_advanced = VBoxContainer.new()
	_advanced.add_theme_constant_override("separation", 12)
	_advanced.visible = _advanced_open
	_page.add_child(_advanced)
	open.pressed.connect(func():
		_advanced_open = not _advanced_open
		_advanced.visible = _advanced_open
		open.text = "Advanced  ▾" if _advanced_open else "Advanced  ▸")
	_fill_advanced()


func _fill_advanced() -> void:
	if not is_instance_valid(_advanced):
		return
	UiKit.clear(_advanced)
	_into = _advanced
	_option("MSAA", GraphicsQuality.MSAA_NAMES, _pending.msaa, func(v): _pick_advanced("msaa", v), false)
	_option("Screen-space AA", GraphicsQuality.SCREEN_AA_NAMES, _pending.screen_aa, func(v): _pick_advanced("screen_aa", v), false)
	UiKit.label(_advanced, "MSAA smooths the edges of models and the map. Screen-space AA catches the rest: glowing effects and edges inside surfaces.", true, 15)
	_slider("Render scale", 0.5, 1.0, 0.05, _pending.render_scale, func(v): _pick_advanced("render_scale", v), true, false)
	_slider("Sharpening", 0.0, 2.0, 0.1, 2.0 - _pending.fsr_sharpness, func(v): _pick_advanced("fsr_sharpness", 2.0 - v), false, false)
	UiKit.label(_advanced, "Below 100%, the 3D world is drawn smaller and stretched to fit with AMD FSR 1, which sharpens as it stretches. Menus and the HUD stay sharp. Sharpening only matters below 100%.", true, 15)
	_option("Shadows", GraphicsQuality.SHADOW_NAMES, _pending.shadows, func(v): _pick_advanced("shadows", v), false)
	_option("Ambient occlusion", GraphicsQuality.AO_NAMES, _pending.ao, func(v): _pick_advanced("ao", v), false)
	_switch("Glow", _pending.glow, func(v): _pick_advanced("glow", v), false)
	UiKit.label(_advanced, "Ambient occlusion darkens corners and the ground under things; High adds a little coloured light bouncing off nearby surfaces.", true, 15)
	_into = null


func _pick_quality(id: String) -> void:
	if GraphicsQuality.PRESETS.has(id):
		var picks := GraphicsQuality.preset(id)
		for k in picks:
			_pending[k] = picks[k]
	_pending.quality = GraphicsQuality.matching(_pending)
	_select(_quality_btn, GraphicsQuality.QUALITY_NAMES, _pending.quality)
	_fill_advanced()
	_update_apply()


func _pick_advanced(key: String, value) -> void:
	_pending[key] = value
	_pending.quality = GraphicsQuality.matching(_pending)
	_select(_quality_btn, GraphicsQuality.QUALITY_NAMES, _pending.quality)
	_update_apply()


static func _select(o: OptionButton, choices: Dictionary, value) -> void:
	if is_instance_valid(o):
		o.selected = maxi(choices.keys().find(value), 0)


func _current_display() -> Dictionary:
	var d := {}
	for k in DISPLAY_KEYS:
		d[k] = Settings.get(k)
	return d


func _set_display(d: Dictionary) -> void:
	for k in DISPLAY_KEYS:
		Settings.set(k, d[k])
	Settings.apply()
	Settings.save_settings()


func _pick(key: String, value) -> void:
	_pending[key] = value
	_update_apply()


func _has_changes() -> bool:
	var now := _current_display()
	for k in DISPLAY_KEYS:
		if now[k] != _pending[k]:
			return true
	return false


func _update_apply() -> void:
	if is_instance_valid(_apply_btn):
		_apply_btn.disabled = not _has_changes() or not _timer.is_stopped()


func _on_apply() -> void:
	var before := _current_display()
	_set_display(_pending)
	if before.fullscreen != _pending.fullscreen or before.resolution != _pending.resolution:
		_revert_to = before   # a new screen mode or size: ask before keeping it
		_countdown = CONFIRM_SECONDS
		_confirm_row.visible = true
		_confirm_label.text = _confirm_text()
		_timer.start()
	_update_apply()


func _tick() -> void:
	_countdown -= 1
	if _countdown <= 0:
		_on_revert()
	elif is_instance_valid(_confirm_label):
		_confirm_label.text = _confirm_text()


func _confirm_text() -> String:
	return "Keep these settings? Reverting in %d s" % _countdown


func _on_keep() -> void:
	if not is_instance_valid(_timer) or _timer.is_stopped():
		return
	_timer.stop()
	_revert_to = {}
	if is_instance_valid(_confirm_row):
		_confirm_row.visible = false
	_update_apply()


func _on_revert() -> void:
	_timer.stop()
	if not _revert_to.is_empty():
		_set_display(_revert_to)
	_revert_to = {}
	UiKit.clear(_page)
	_build_display()


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	(_into if _into else _page).add_child(row)
	var l := UiKit.label(row, text, false, 18)
	l.custom_minimum_size = Vector2(200, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return row


## `live`: apply the change at once (otherwise the caller decides when).
func _slider(text: String, lo: float, hi: float, step: float, value: float, setter: Callable, percent: bool = false, live: bool = true) -> void:
	var row := _row(text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var v := UiKit.label(row, _fmt(value, step, percent), false, 18)
	v.custom_minimum_size = Vector2(64, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_override("font", HudStyle.font(true))
	s.value_changed.connect(func(x):
		setter.call(x)
		v.text = _fmt(x, step, percent)
		if live:
			Settings.apply())


## `live`: apply the change at once (otherwise the caller decides when).
func _switch(text: String, value: bool, setter: Callable, live: bool = true) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.add_theme_font_size_override("font_size", 18)
	c.toggled.connect(func(x):
		setter.call(x)
		if live:
			Settings.apply())
	(_into if _into else _page).add_child(c)


## A drop-down. `choices` maps each stored value to the text shown for it.
func _option(text: String, choices: Dictionary, value: Variant, setter: Callable, live: bool = true) -> void:
	var row := _row(text)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.custom_minimum_size = Vector2(0, 44)
	o.add_theme_font_size_override("font_size", 18)
	var keys := choices.keys()
	for k in keys:
		o.add_item(choices[k])
	o.selected = maxi(keys.find(value), 0)
	o.item_selected.connect(func(i):
		setter.call(keys[i])
		if live:
			Settings.apply())
	row.add_child(o)
	_last_option = o


func _fmt(x: float, step: float, percent: bool) -> String:
	if percent:
		return "%d%%" % roundi(x * 100.0)
	return str(int(x)) if step >= 1.0 else "%.2f" % x
