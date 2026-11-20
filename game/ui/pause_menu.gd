class_name PauseMenu
extends CanvasLayer
## Esc menu during a match. The game keeps running underneath (it is multiplayer).
## Three pages in one MenuFrame (so the buttons stay on screen at any window size):
## the menu itself with the controls beside it, Loadout, and Settings.

var _frame: MenuFrame


func _ready() -> void:
	layer = 20
	visible = false
	_frame = MenuFrame.new(1080, true)
	add_child(_frame)
	visibility_changed.connect(_on_shown)


func _on_shown() -> void:
	if not visible:
		return
	match DevArgs.pause_page:   # dev: open straight on a page (screenshots)
		"loadout": _show_loadout()
		"settings": _show_settings()
		_: _show_main()


func _show_main() -> void:
	_frame.clear(1080)
	_frame.title("Paused", "%s  ·  the match keeps going" % Maps.name_of(Net.map_id()))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	_frame.body.add_child(row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(360, 0)
	row.add_child(col)
	UiKit.primary_button(col, "Resume", func(): visible = false).grab_focus()
	UiKit.button(col, "Loadout", _show_loadout)
	UiKit.button(col, "Settings", _show_settings)
	if Net.spectating():
		var join := UiKit.button(col, "Stop spectating (join the match)", func():
			Net.set_spectating(false)
			visible = false)
		join.disabled = Net.players.size() >= Net.MAX_PLAYERS
	elif Game.mode != Game.Mode.PRACTICE:
		UiKit.button(col, "Spectate (watch with a free camera)", func():
			Net.set_spectating(true)
			visible = false)
	if Net.is_online and Net.is_host():
		UiKit.button(col, "End match now (show results)", Match.host_end_match)
	var leave_text := "Leave match"
	if Net.is_online and Net.is_host():
		leave_text = "Close lobby (ends it for everyone)"
	UiKit.button(col, leave_text, Game.leave_to_menu)
	var keys := VBoxContainer.new()
	keys.add_theme_constant_override("separation", 6)
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(keys)
	UiKit.section(keys, "Controls")
	for k in SettingsPanel.cheat_sheet():
		UiKit.key_row(keys, k[0], k[1].get_slice(";", 0))


## Change your robot and (in a shoot-out) your weapon mid-match. In a fight the change
## waits for your next respawn; a race has no deaths, so there it happens at once. A
## Deathmatch only offers the robot: weapons there come off the map. Only the weapons
## the host allows can be picked (see LobbySettings); with one gun for everyone, none.
func _show_loadout() -> void:
	var me := Net.my_id()
	var race := Race.active
	var deathmatch := Net.is_deathmatch() or GunGame.active() or KillcamMode.active()   # weapons come off the map, from the ladder, or it is snipers only
	var only := LobbySettings.only_weapon()
	var with_weapons := not race and not deathmatch and only == ""
	_frame.clear(1040 if with_weapons else 520)
	var note := "Your robot changes straight away." if race else "Changes apply the next time you respawn."
	if deathmatch:
		note += "  Weapons are found on the map." if Net.is_deathmatch() else ("  Killcam is snipers only." if KillcamMode.active() else "  Gun Game hands out the weapons.")
	var dead := not race and not Match.is_alive(me)
	if dead:
		note = "Changes apply when you respawn."
	if only != "" and not race and not deathmatch:
		note += "  Everyone has the %s this match." % WeaponData.name_of(only)
	_frame.title("Loadout", "Paused  /  robot and weapon")
	UiKit.label(_frame.header, note, true, 15)
	var picked := {"character": Net.pending_character(), "weapon": Net.pending_weapon(), "mobility": Net.pending_mobility()}
	var gun: String = picked.weapon if with_weapons or (only != "" and not race and not deathmatch) else "none"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	_frame.body.add_child(row)
	var robots := CharacterPicker.new(picked.character, Net.player_color(me), gun)
	robots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(robots)
	robots.picked.connect(func(id: String): picked.character = id)
	if with_weapons:
		robots.size_flags_horizontal = Control.SIZE_FILL
		var weapons := WeaponPicker.new(picked.weapon, LobbySettings.allowed_weapons())
		weapons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(weapons)
		weapons.picked.connect(func(id: String):
			picked.weapon = id
			robots.set_weapon(id))
	_frame.back_button("Back", _show_main)
	_frame.main_button("Apply", func():
		Settings.character = picked.character
		if with_weapons:   # otherwise your saved pick stays for matches that let you choose
			Settings.weapon = picked.weapon
		Settings.save_settings()
		Net.set_loadout(picked.character, picked.weapon if with_weapons else "", picked.mobility)
		if dead:
			visible = false   # back to the death screen, to respawn with it
		else:
			_show_main())


func _show_settings() -> void:
	_frame.clear(900)
	var panel := SettingsPanel.new(_frame)
	panel.closed.connect(_show_main)
	_frame.body.add_child(panel)
