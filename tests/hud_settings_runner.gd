extends Node
## HUD option checks (started by tests/hud_settings_test.gd). Nothing here writes
## settings.cfg: saving and loading go through a ConfigFile in memory.

var _fails: Array[String] = []
var _draws := {}   # control name -> times its draw ran to the end of our counter


func run() -> void:
	await get_tree().process_frame
	print("HUD settings checks")
	var keep := HudConfig.new()
	_copy(Settings.hud, keep)
	var keep_layouts := [Settings.hud_first_person, Settings.hud_third_person]

	_check_defaults()
	_check_round_trip()
	_check_bad_values()
	await _check_hud_draws()
	await _check_preview()
	await _check_settings_tab()

	_copy(keep, Settings.hud)
	Settings.hud_first_person = keep_layouts[0]
	Settings.hud_third_person = keep_layouts[1]
	if _fails.is_empty():
		print("PASS: every check passed")
	else:
		print("FAIL:\n  " + "\n  ".join(_fails))
	get_tree().quit(1 if not _fails.is_empty() else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)


func _copy(from: HudConfig, to: HudConfig) -> void:
	for key in HudConfig.SPEC:
		to.set(key, from.get(key))


## The defaults are the HUD as it was before it had options.
func _check_defaults() -> void:
	print("  defaults")
	var d := HudConfig.new()
	var was := {"scale": 1.0, "opacity": 1.0, "crosshair": "weapon", "crosshair_color": "white", "crosshair_size": 1.0,
		"crosshair_gap": 5.0, "crosshair_thickness": 2.0, "crosshair_outline": true, "crosshair_dot": true,
		"hit_markers": true, "damage_numbers": true, "feed_corner": "right", "feed_lines": 5, "moves": "full",
		"speed": true, "killcam_points": true}
	_expect(was.keys().size() == HudConfig.SPEC.size(), "every option has a default to check (%d of %d)" % [was.size(), HudConfig.SPEC.size()])
	for key in was:
		_expect(d.get(key) == was[key] and typeof(d.get(key)) == typeof(was[key]), "default %s is %s (got %s)" % [key, was[key], d.get(key)])
		_expect(HudConfig.SPEC[key][0] == d.get(key), "SPEC's default for %s matches the field's" % key)
	_expect(d.is_default(), "a new HudConfig is at its defaults")
	_expect(d.color() == HudStyle.WHITE, "the default crosshair colour is the HUD's white")
	_expect(Hud.FEED_MAX >= HudConfig.SPEC.feed_lines[2], "the kill feed keeps enough lines for the most the option allows")
	d.scale = 1.2
	d.moves = "off"
	d.reset()
	_expect(d.is_default(), "reset() puts everything back")


## Save to a settings file's text and read it back.
func _check_round_trip() -> void:
	print("  save and load")
	var a := HudConfig.new()
	var odd := {"scale": 1.25, "opacity": 0.45, "crosshair": "circle", "crosshair_color": "green", "crosshair_size": 1.75,
		"crosshair_gap": 12.0, "crosshair_thickness": 3.0, "crosshair_outline": false, "crosshair_dot": false,
		"hit_markers": false, "damage_numbers": false, "feed_corner": "left", "feed_lines": 8, "moves": "compact",
		"speed": false, "killcam_points": false}
	for key in odd:
		a.set(key, odd[key])
	var cfg := ConfigFile.new()
	cfg.set_value("hud", "first_person", "clean")   # what Settings already keeps there stays
	a.save_to(cfg)
	var again := ConfigFile.new()
	_expect(again.parse(cfg.encode_to_text()) == OK, "the saved text parses")
	var b := HudConfig.new()
	b.load_from(again)
	for key in odd:
		_expect(b.get(key) == odd[key], "%s survives a save and load (%s, got %s)" % [key, odd[key], b.get(key)])
	_expect(typeof(b.feed_lines) == TYPE_INT, "feed_lines loads as a whole number")
	_expect(again.get_value("hud", "first_person") == "clean", "the layout key in [hud] is left alone")
	var empty := HudConfig.new()
	empty.scale = 0.9
	empty.load_from(ConfigFile.new())
	_expect(empty.is_default(), "nothing saved: the defaults")


## Anything of the wrong kind or out of range falls back to the default.
func _check_bad_values() -> void:
	print("  bad saved values")
	var bad := {"scale": "big", "opacity": 5.0, "crosshair": "laser", "crosshair_color": 3, "crosshair_size": NAN,
		"crosshair_gap": -4, "crosshair_thickness": "2", "crosshair_outline": 1, "crosshair_dot": "true",
		"hit_markers": [true], "damage_numbers": 0, "feed_corner": "bottom", "feed_lines": 99, "moves": true,
		"speed": "yes", "killcam_points": 2.0}
	_expect(bad.size() == HudConfig.SPEC.size(), "every option gets a bad value")
	var cfg := ConfigFile.new()
	for key in bad:
		cfg.set_value("hud", key, bad[key])
	var c := HudConfig.new()
	for key in HudConfig.SPEC:
		c.set(key, HudConfig.SPEC[key][0])
	c.scale = 1.1   # (so falling back is seen, not just left alone)
	c.load_from(cfg)
	for key in bad:
		_expect(c.get(key) == HudConfig.SPEC[key][0], "bad %s (%s) falls back to %s (got %s)" % [key, bad[key], HudConfig.SPEC[key][0], c.get(key)])
	_expect(HudConfig.valid("feed_lines", 6.0) == 6 and typeof(HudConfig.valid("feed_lines", 6.0)) == TYPE_INT, "a whole number saved as 6.0 reads as 6")
	_expect(HudConfig.valid("scale", 1) == 1.0 and typeof(HudConfig.valid("scale", 1)) == TYPE_FLOAT, "a scale saved as 1 reads as 1.0")
	_expect(is_equal_approx(HudConfig.valid("scale", 0.8), 0.8), "a good scale is kept")


## The real HUD draws every combination, including the extremes, and the feed keeps
## only as many lines as asked.
func _check_hud_draws() -> void:
	print("  the HUD draws at the extremes")
	Net.start_offline("Host", "needle", "pistol")
	var bot := Net.add_bot(1)
	var hud := Hud.new()
	add_child(hud)
	await get_tree().process_frame
	for c in ["_layout", "_screens", "_overlay", "_cross"]:
		var ctl: Control = hud.get(c)
		_draws[c] = 0
		ctl.draw.connect(func(): _draws[c] += 1)
	var me := Net.my_id()
	for i in Hud.FEED_MAX:
		hud._feed.append({"killer": me if i % 2 == 0 else bot, "victim": bot if i % 2 == 0 else me, "head": i % 3 == 0,
			"age": 0.0, "gun": "pistol", "wall": false, "how": "fell"})
	var cfg := Settings.hud
	cfg.feed_lines = 3
	hud._age(0.0)
	_expect(hud._feed.size() == 3, "the feed keeps 3 lines when asked for 3 (has %d)" % hud._feed.size())
	cfg.feed_lines = 8
	for i in 6:
		hud._feed.append({"killer": me, "victim": bot, "head": false, "age": 0.0, "gun": "rifle", "wall": false, "how": "fell"})
	hud._age(0.0)
	_expect(hud._feed.size() == 8, "the feed keeps 8 lines when asked for 8 (has %d)" % hud._feed.size())

	var v := hud.view
	v.hp = 25.0
	v.hp_trail = 60.0
	v.ammo = 4
	v.magazine = 30
	v.weapon = "Rifle"
	v.spread_px = 14.0
	v.ready = 0.5
	v.moves = [["GRAPPLE", "MMB", 1.0, true], ["DIVE", "Q", 0.3, false], ["FLIP", "SPACE", 1.0, false], ["KICK", "F", 0.0, false]]
	var frames := 0
	for scale in [0.75, 1.25]:
		for on in [false, true]:
			for layout in ["arcs", "clean"]:
				for xhair in HudConfig.CROSSHAIRS:
					for kind in ["cross", "spread", "ring", "dot", "melee"]:
						cfg.reset()
						cfg.scale = scale
						cfg.opacity = 0.3 if not on else 1.0
						cfg.crosshair = xhair
						cfg.crosshair_size = 0.5 if on else 2.0
						cfg.crosshair_gap = 0.0 if on else 20.0
						cfg.crosshair_thickness = 4.0 if on else 1.0
						for key in ["crosshair_outline", "crosshair_dot", "hit_markers", "damage_numbers", "speed", "killcam_points"]:
							cfg.set(key, on)
						cfg.moves = "compact" if on else "off"
						cfg.feed_corner = "left" if on else "right"
						hud.style = layout
						v.crosshair = kind
						v.melee = kind == "melee"
						hud._hit_time = 0.1
						hud._hit_kind = ["hit", "head", "kill"][frames % 3]
						hud._numbers = [{"value": 34, "head": true, "age": 0.2, "x": 3.0}]
						hud._points = {"total": 245, "parts": [["KILL", 100], ["HEADSHOT", 60], ["SPEED 21 M/S", 85]], "age": 0.3 + (frames % 4) * 0.4}
						hud._layout.queue_redraw()
						hud._redraw()
						await get_tree().process_frame
						frames += 1
	# Knocked out: the death screen at its own size under a scaled, faded feed on the left (it moves right).
	hud._dead = true
	cfg.feed_corner = "left"
	cfg.scale = 1.25
	hud._redraw()
	await get_tree().process_frame
	_expect(hud._overlay.modulate.a == cfg.opacity and hud._layout.modulate.a == cfg.opacity, "the HUD opacity reaches the layout and the overlay")
	_expect(hud._cross.modulate.a == 1.0 and hud._screens.modulate.a == 1.0, "the crosshair and the full-screen pages never fade")
	for c in _draws:
		_expect(_draws[c] >= frames, "%s drew every frame (%d of %d)" % [c, _draws[c], frames])
	print("    %d combinations drawn" % frames)
	cfg.reset()
	hud.queue_free()
	Net.leave()
	await get_tree().process_frame


## The Settings preview draws in both views at the extremes.
func _check_preview() -> void:
	print("  the preview draws")
	var p := HudPreview.new(false)
	add_child(p)
	var count := [0]
	p._hud.draw.connect(func(): count[0] += 1)
	var cfg := Settings.hud
	var frames := 0
	for third in [false, true]:
		for scale in [0.75, 1.25]:
			for xhair in HudConfig.CROSSHAIRS:
				for on in [false, true]:
					cfg.reset()
					cfg.scale = scale
					cfg.crosshair = xhair
					for key in ["crosshair_outline", "crosshair_dot", "hit_markers", "damage_numbers", "speed", "killcam_points"]:
						cfg.set(key, on)
					cfg.moves = "compact" if on else "off"
					cfg.feed_corner = "left" if on else "right"
					cfg.feed_lines = 8 if on else 3
					p.third_person = third
					await get_tree().process_frame
					frames += 1
	_expect(count[0] >= frames, "the preview drew every frame (%d of %d)" % [count[0], frames])
	cfg.reset()
	p.queue_free()
	await get_tree().process_frame


## Settings → HUD: the preview sits in the header (and leaves with the tab), and Reset
## HUD puts the layouts and every option back.
func _check_settings_tab() -> void:
	print("  the HUD tab")
	var frame := MenuFrame.new()
	add_child(frame)
	SettingsPanel.open_on_tab(SettingsPanel.HUD_TAB)
	var panel := SettingsPanel.new(frame)
	frame.body.add_child(panel)
	for i in 4:
		await get_tree().process_frame
	_expect(SettingsPanel.TABS[SettingsPanel.HUD_TAB] == "HUD", "the HUD tab is where HUD_TAB says")
	_expect(not frame.header.find_children("*", "HudPreview", true, false).is_empty(), "the HUD tab shows its preview in the header")
	Settings.hud.scale = 1.25
	Settings.hud.crosshair = "circle"
	Settings.hud_first_person = "clean"
	var reset := _find(panel, "Reset HUD")
	_expect(reset != null, "the HUD tab has a Reset HUD button")
	if reset:
		reset.pressed.emit()
		await get_tree().process_frame
		_expect(Settings.hud.is_default(), "Reset HUD puts every option back")
		_expect(Settings.hud_first_person == "arcs" and Settings.hud_third_person == "clean", "Reset HUD puts the layouts back")
		_expect(frame.header.find_children("*", "HudPreview", true, false).size() == 1, "after Reset HUD there is still exactly one preview")
	panel.call("_show_tab", 1)
	await get_tree().process_frame
	_expect(frame.header.find_children("*", "HudPreview", true, false).is_empty(), "the preview leaves with the HUD tab")
	SettingsPanel.open_on_tab(0)
	frame.queue_free()
	await get_tree().process_frame


func _find(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var r := _find(c, text)
		if r:
			return r
	return null
