extends SceneTree
## Quick check of control rebinding: defaults, conflicts, save/load, reset, and the
## Controls tab capturing a key. godot --headless --path . -s tests/controls_check.gd

func _ok(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		_fails += 1

var _fails := 0

func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	return e

func _initialize() -> void:
	await process_frame
	var S = root.get_node("/root/Settings")
	S.reset_bindings()
	_ok(InputMap.action_has_event("kick", _key(KEY_F)), "F kicks by default")
	_ok(S.action_text("dive") == "Q", "dive shows Q: " + S.action_text("dive"))
	_ok(S.bindings.glide == ["key:%d" % KEY_ALT] and InputMap.action_has_event("glide", _key(KEY_ALT)), "Alt glides")
	_ok(InputMap.action_has_event("sprint", _key(KEY_SHIFT)) and not InputMap.action_has_event("glide", _key(KEY_SHIFT)), "Shift sprints only")
	var on_alt := []
	for a in S.ACTIONS:
		if a[0] != "glide" and (a[2] as Array).has("key:%d" % KEY_ALT):
			on_alt.append(a[1])
	_ok(on_alt.is_empty(), "nothing else is on Alt by default %s" % [on_alt])
	# The mobility button is middle mouse; right mouse is alt fire's alone by default.
	var middle := "mouse:%d" % MOUSE_BUTTON_MIDDLE
	var right := "mouse:%d" % MOUSE_BUTTON_RIGHT
	_ok(S.bindings.grapple == [middle] and S.action_text("grapple") == "Middle mouse", "the mobility tool is on middle mouse: " + S.action_text("grapple"))
	var on_right := []
	for a in S.ACTIONS:
		if a[0] != "alt_fire" and (a[2] as Array).has(right):
			on_right.append(a[1])
	_ok(on_right.is_empty(), "nothing else is on right mouse by default %s" % [on_right])
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	_ok(S.bindings.alt_fire == [right] and InputMap.action_has_event("alt_fire", rmb) and S.action_text("alt_fire") == "Right mouse",
		"alt fire is on right mouse: " + S.action_text("alt_fire"))
	# Bindings saved before the mobility button moved to middle mouse (version 2).
	var v2 := ConfigFile.new()
	v2.set_value("bindings", "version", 2)
	S._load_bindings(v2)
	_ok(S.bindings.grapple == [middle], "nothing saved for it: an old player gets middle mouse")
	_ok(S.bindings.alt_fire == [right], "...and alt fire gets right mouse")
	v2.set_value("bindings", "grapple", [right, "key:%d" % KEY_X])
	S._load_bindings(v2)
	_ok(S.bindings.grapple == [middle, "key:%d" % KEY_X], "right mouse saved for it moves to middle mouse, keeping the second binding: %s" % [S.bindings.grapple])
	v2.set_value("bindings", "grapple", ["key:%d" % KEY_X])
	S._load_bindings(v2)
	_ok(S.bindings.grapple == ["key:%d" % KEY_X], "a key you moved it to is kept")
	v2.set_value("bindings", "grapple", null)
	v2.set_value("bindings", "kick", [middle])
	S._load_bindings(v2)
	_ok(S.bindings.grapple == [right] and S.bindings.kick == [middle], "middle mouse already yours for something else: it keeps right mouse, as it was")
	_ok(S.bindings.alt_fire.is_empty(), "...so alt fire starts unbound rather than take right mouse from it: %s" % [S.bindings.alt_fire])
	# Bindings saved before alt fire came in (version 3): it takes right mouse if free.
	S.reset_bindings()
	var v3 := ConfigFile.new()
	v3.set_value("bindings", "version", 3)
	S.bindings.alt_fire = []
	S._load_bindings(v3)
	_ok(S.bindings.alt_fire == [right], "right mouse free: an old player's alt fire gets it")
	v3.set_value("bindings", "kick", ["key:%d" % KEY_F, right])
	S._load_bindings(v3)
	_ok(S.bindings.alt_fire.is_empty() and S.bindings.kick == ["key:%d" % KEY_F, right], "right mouse already yours for something else: it stays there and alt fire starts unbound")
	var v4 := ConfigFile.new()
	S._save_bindings(v4)
	_ok(int(v4.get_value("bindings", "version", 0)) == S.BINDINGS_VERSION and S.BINDINGS_VERSION == 4, "saved as version 4, so each move happens only once")
	_ok(v4.get_value("bindings", "alt_fire", null) == [], "...and an unbound alt fire is saved as unbound")
	S.bindings.kick = ["key:%d" % KEY_F]
	S._load_bindings(v4)
	_ok(S.bindings.alt_fire.is_empty(), "loaded again, it stays unbound (right mouse free or not, it is your choice now)")
	S.reset_bindings()
	# Bindings saved before the glide moved to Alt: brought up to date as they load.
	var old := ConfigFile.new()
	old.set_value("bindings", "glide", ["key:%d" % KEY_SHIFT])
	old.set_value("bindings", "dive", ["key:%d" % KEY_Q, "key:%d" % KEY_ALT])
	old.set_value("bindings", "interact", ["key:%d" % KEY_ALT, "key:%d" % KEY_G])
	S._load_bindings(old)
	_ok(S.bindings.glide == ["key:%d" % KEY_ALT], "an old saved glide key goes back to Alt: %s" % [S.bindings.glide])
	_ok(S.bindings.dive == ["key:%d" % KEY_Q] and S.bindings.interact == ["key:%d" % KEY_G], "...and Alt comes off whatever else had it saved")
	var newer := ConfigFile.new()
	S._save_bindings(newer)
	newer.set_value("bindings", "glide", ["mouse:%d" % MOUSE_BUTTON_XBUTTON2])
	S._load_bindings(newer)
	_ok(S.bindings.glide == ["mouse:%d" % MOUSE_BUTTON_XBUTTON2], "a glide key saved since then is kept")
	S.reset_bindings()
	_ok(InputMap.action_has_event("interact", _key(KEY_G)), "G is interact by default (press it at a map terminal)")
	var shared := []
	for a in S.ACTIONS:
		if a[0] != "interact" and (a[2] as Array).has("key:%d" % KEY_G):
			shared.append(a[1])
	_ok(shared.is_empty(), "no other action uses G by default %s" % [shared])
	_ok(S.rebind("glide", 1, "key:%d" % KEY_SHIFT).is_empty() and S.bindings.sprint.size() == 1, "glide may share Shift with sprint (not a conflict)")
	var taken: Array = S.rebind("boost", 0, "key:%d" % KEY_F)
	_ok(taken == ["Kick"], "F taken from Kick")
	_ok(InputMap.action_has_event("boost", _key(KEY_F)) and not InputMap.action_has_event("kick", _key(KEY_F)), "F boosts, no longer kicks")
	_ok(S.bindings.kick.is_empty(), "Kick unbound")
	S.rebind("grapple", 1, "mouse:%d" % MOUSE_BUTTON_XBUTTON1)
	_ok(S.action_text("grapple") == "Middle mouse / Mouse 4", "grapple has a second binding: " + S.action_text("grapple"))
	_ok(S.rebind("jump", 0, "key:%d" % KEY_ESCAPE).is_empty() and S.bindings.jump == ["key:%d" % KEY_SPACE], "Esc can't be taken")
	# Saved and loaded
	S.bindings = {}
	for a in S.ACTIONS:
		S.bindings[a[0]] = a[2].duplicate()
	S.load_settings()
	_ok(S.bindings.boost == ["key:%d" % KEY_F] and S.bindings.kick.is_empty(), "rebinds survive a reload")
	_ok(InputMap.action_has_event("grapple", InputEventMouseButton.new()) == false, "sanity")
	S.reset_bindings()
	S.load_settings()
	_ok(S.bindings.kick == ["key:%d" % KEY_F] and S.bindings.boost == ["key:%d" % KEY_E], "reset to defaults saved")
	# The Controls tab: click a binding, press a key
	var panel_script: GDScript = load("res://game/ui/settings_panel.gd")
	var panel: Node = panel_script.new()
	root.add_child(panel)
	await process_frame
	var box: VBoxContainer = panel._binds_box
	_ok(box.get_child_count() == S.ACTIONS.size(), "one row per action")
	var kick_i := -1
	for i in S.ACTIONS.size():
		if S.ACTIONS[i][0] == "kick":
			kick_i = i
	var kick_row: Node = box.get_child(kick_i)
	(kick_row.get_child(1) as Button).emit_signal("pressed")
	_ok(panel._listen == ["kick", 0], "listening for Kick")
	Input.parse_input_event(_key(KEY_G))
	await process_frame
	await process_frame
	_ok(S.bindings.kick == ["key:%d" % KEY_G], "Kick rebound to G in the menu")
	(box.get_child(kick_i).get_child(2) as Button).emit_signal("pressed")
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_RIGHT
	m.pressed = true
	Input.parse_input_event(m)
	await process_frame
	await process_frame
	_ok(S.bindings.kick == ["key:%d" % KEY_G, "mouse:%d" % MOUSE_BUTTON_RIGHT] and S.bindings.grapple == ["mouse:%d" % MOUSE_BUTTON_MIDDLE], "right mouse added as Kick's second")
	_ok(S.bindings.alt_fire.is_empty() and panel._bind_note.text == "Moved from Alt fire (tilt pistols, sticky grenades) to Kick.",
		"...taken from alt fire: " + panel._bind_note.text)
	(box.get_child(0).get_child(1) as Button).emit_signal("pressed")
	Input.parse_input_event(_key(KEY_ESCAPE))
	await process_frame
	await process_frame
	_ok(S.bindings.move_forward == ["key:%d" % KEY_W] and panel._listen.is_empty(), "Esc cancels")
	print(panel_script.cheat_sheet()[0], panel_script.cheat_sheet()[8])
	S.reset_bindings()
	var alt_rows: Array = panel_script.cheat_sheet().filter(func(r): return str(r[1]).begins_with("Alt fire"))
	_ok(alt_rows.size() == 1 and alt_rows[0][0] == "Right mouse", "the pause menu's controls list alt fire on right mouse: %s" % [alt_rows])
	# What alt fire does is the weapon's to say; a held one travels in the animation flags.
	_ok(WeaponData.by_id("pistol").alt == "tilt" and WeaponData.by_id("akimbo").alt == "tilt"
		and WeaponData.by_id("grenade_launcher").alt == "sticky" and WeaponData.by_id("shotgun").alt == "",
		"the pistols tilt, the grenade launcher goes sticky, the rest have no alt fire")
	_ok(WeaponData.by_id("pistol").alt_is_hold() and not WeaponData.by_id("grenade_launcher").alt_is_hold(), "the tilt is held, the sticky grenade pressed")
	var held := RobotAnimInput.make_flags(true, false, true, RobotAnimInput.FLIP_RIGHT, 3, 3, 3, true, 3, true, true, 7, true, 3, true)
	var sent := int(PackedFloat32Array([float(held)])[0])   # (as it goes in a snapshot)
	_ok(RobotAnimInput.alt_of(sent) and not RobotAnimInput.alt_of(held & ~(1 << 22)) and sent == held, "alt held survives a snapshot, beside every other flag")
	var pi := PlayerInput.new()
	pi.alt_fire = true
	pi.alt_fire_pressed = true
	pi.clear_edges()
	_ok(pi.alt_fire and not pi.alt_fire_pressed, "the press lasts a frame, the hold stays")
	print("FAILS %d" % _fails)
	quit(1 if _fails else 0)
