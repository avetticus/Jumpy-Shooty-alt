extends Node
## Lobby settings checks (see LobbySettings):
##  - stored values are cleaned (unknown weapons dropped, all of them is "any");
##  - the host keeps everyone to the allowed weapons: its own pick, a player who joins
##    with a weapon that is not allowed, a later pick of one, a change of the setting,
##    and bots (at random or --bot-weapon); lifting it gives the host its pick back;
##  - one gun: everyone has it and there is nothing to pick;
##  - Gun Game and a Deathmatch ignore the setting;
##  - the death screen's keys and scroll go through the allowed weapons only;
##  - the weapon pickers: the lobby's offers only allowed weapons (and gives way to a
##    note with one gun), the host's control changes the setting, the pause menu's
##    Loadout offers only allowed weapons (none with one gun);
##  - the jetpack: off by default; the host turns it on (a Deathmatch too, never a race);
##    an old saved list of allowed mobility tools, or a pick of a tool that is gone, loads
##    cleanly as the grappling hook; the host's toggle in the lobby changes it.
##  - the lobby size is kept between 2 and 16; players ready up, the host can only
##    start once everyone is ready (bots and the host count as ready), the lobby shows
##    who is ready and gives the host a Kick button on everyone else's row.
## Started by tests/lobby_settings_test.gd.

var _fails: Array[String] = []


func run() -> void:
	await get_tree().process_frame
	print("Lobby settings checks")
	_cleaning()
	_host_enforces()
	_bots()
	_other_modes()
	_death_pick()
	_host_control()
	await _lobby_menu()
	await _loadout_menu()
	await _jetpack()
	await _ready_and_size()
	await _floating_windows()
	Net.leave()
	if _fails.is_empty():
		print("PASS: every check passed")
	else:
		print("FAIL:\n  " + "\n  ".join(_fails))
	get_tree().quit(1 if not _fails.is_empty() else 0)


func _expect(ok: bool, what: String) -> void:
	print("    %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


## Offline, this copy is the host (as in Vs Bots); a shoot-out with `weapons` allowed.
func _settings(weapons: Array, game: String = "ffa", mode: String = "kills") -> void:
	var s := Net.match_settings.duplicate()
	s["game"] = game
	s["map"] = Maps.default_id(game)
	s["mode"] = mode
	s["weapons"] = weapons
	Net.set_match_settings(s)


func _cleaning() -> void:
	print("  stored values")
	_expect(LobbySettings.clean({}).get("weapons") == [], "a missing setting is filled in with its default (any weapon)")
	_expect(LobbySettings.normalized_weapons(["bolt_action", "nonsense", "pistol", "bolt_action"]) == ["pistol", "bolt_action"],
		"unknown weapons are dropped and each is listed once, in the pickers' order")
	_expect(LobbySettings.normalized_weapons(WeaponData.IDS) == [], "allowing every weapon is stored as any weapon")
	_expect(LobbySettings.normalized_weapons("rifle") == [], "a value that is not a list means any weapon")
	_expect(Net.match_settings.has("weapons"), "the lobby's settings have the weapons setting from the start")


func _host_enforces() -> void:
	print("  the host enforces it")
	Net.start_offline("Host", "needle", "bolt_action")
	_settings(["shotgun", "rifle"])
	_expect(Net.match_settings.weapons == ["shotgun", "rifle"], "the setting is kept in the match settings everyone is sent")
	_expect(Net.player_loadout_weapon(1) == "shotgun", "the host's saved bolt-action is not allowed, so it gets the first allowed weapon")
	_expect(Net.pending_weapon() == "shotgun", "the pause menu would show the allowed weapon")
	Net.set_my_weapon("bolt_action")
	_expect(Net.player_loadout_weapon(1) == "shotgun", "picking a weapon that is not allowed changes nothing")
	Net.set_my_weapon("rifle")
	_expect(Net.player_loadout_weapon(1) == "rifle", "picking an allowed weapon works")
	Net.host_add_player(2, "Client", "orbit", "railgun")
	_expect(Net.player_loadout_weapon(2) == "shotgun", "a player who joins with a weapon that is not allowed gets an allowed one")
	Net._apply_weapon(2, "rocket_launcher")
	_expect(Net.player_loadout_weapon(2) == "shotgun", "a client asking for a weapon that is not allowed is refused")
	Net._apply_weapon(2, "rifle")
	_expect(Net.player_loadout_weapon(2) == "rifle", "a client asking for an allowed weapon gets it")
	_settings(["railgun"])
	_expect(Net.player_loadout_weapon(1) == "railgun" and Net.player_loadout_weapon(2) == "railgun",
		"one gun: when the host sets it, everyone is given that gun")
	_expect(LobbySettings.only_weapon() == "railgun", "one gun: it is the only weapon")
	Net.players[2]["weapon"] = "bolt_action"   # however it got there...
	Net.host_fit_loadouts()               # ...nobody starts the match with it
	_expect(Net.player_loadout_weapon(2) == "railgun", "starting the match swaps out any weapon that is not allowed")
	_settings([])
	_expect(Net.player_loadout_weapon(1) == "rifle", "when every weapon is allowed again, the host gets back the one it picked")
	_expect(LobbySettings.only_weapon() == "" and LobbySettings.allowed_weapons().size() == WeaponData.IDS.size(),
		"any weapon: every weapon is allowed")


func _bots() -> void:
	print("  bots")
	Net.start_offline("Host", "needle", "pistol")
	_settings(["spear", "bat"])
	var ok := true
	for i in 12:
		var id := Net.add_bot(1)
		ok = ok and Net.player_loadout_weapon(id) in ["spear", "bat"]
		Net.remove_bot(id)
	_expect(ok, "bots take a gun at random from the allowed ones")
	var forced := Net.add_bot(1, "bolt_action")
	_expect(Net.player_loadout_weapon(forced) == "spear", "a --bot-weapon that is not allowed gives way to an allowed one")
	Net.remove_bot(forced)
	var fine := Net.add_bot(1, "bat")
	_expect(Net.player_loadout_weapon(fine) == "bat", "a --bot-weapon that is allowed is kept")


func _other_modes() -> void:
	print("  Gun Game and Deathmatch")
	Net.start_offline("Host", "needle", "pistol")
	_settings(["bolt_action"], "ffa", "gungame")
	_expect(not LobbySettings.weapons_apply() and LobbySettings.allowed_weapons().size() == WeaponData.IDS.size(),
		"Gun Game ignores the setting (it has its own ladder)")
	_settings(["bolt_action"], "dm")
	_expect(not LobbySettings.weapons_apply() and LobbySettings.only_weapon() == "", "a Deathmatch ignores the setting (weapons are on the map)")
	_expect(Net.match_settings.weapons == ["bolt_action"], "the setting is kept for when the host goes back to a shoot-out")
	_settings(["bolt_action"], "ffa")
	_expect(LobbySettings.only_weapon() == "bolt_action", "back in a shoot-out it applies again")


func _death_pick() -> void:
	print("  death screen pick")
	Net.start_offline("Host", "needle", "pistol")
	_settings(["pistol", "revolver", "shotgun", "bolt_action"])
	var groups := LobbySettings.weapon_groups()
	_expect(groups.map(func(g): return g[0]) == ["Sidearms", "Shotguns", "Marksman"], "only the classes with allowed weapons are listed (%s)" % [groups])
	_expect(groups[0][1] == ["pistol", "revolver"], "a class lists only its allowed weapons")
	_expect(LobbySettings.death_pick("pistol", 0, 0) == "revolver", "key 1 goes on through the allowed sidearms")
	_expect(LobbySettings.death_pick("revolver", 0, 0) == "pistol", "...and round again")
	_expect(LobbySettings.death_pick("pistol", 2, 0) == "bolt_action", "key 3 is the third class shown (marksman: the bolt-action)")
	_expect(LobbySettings.death_pick("pistol", 5, 0) == "", "a key past the classes shown does nothing")
	_expect(LobbySettings.death_pick("bolt_action", -1, 1) == "pistol", "scrolling on from the last allowed weapon goes back to the first")
	_expect(LobbySettings.death_pick("pistol", -1, -1) == "bolt_action", "scrolling back goes through the allowed weapons only")
	_expect(LobbySettings.death_pick("smg", -1, 1) == "pistol", "from a weapon that is not allowed, scrolling gives the first allowed one")
	_settings(["bolt_action"])
	_expect(LobbySettings.death_pick("bolt_action", 0, 0) == "" and LobbySettings.death_pick("bolt_action", -1, 1) == "",
		"one gun: the keys and the wheel pick nothing")


func _host_control() -> void:
	print("  the host's control")
	var c := AllowedWeaponsPicker.new([])
	var got := []
	c.changed.connect(func(ids: Array): got.append(ids))
	c._on_chip("pistol")
	_expect(c.value().size() == WeaponData.IDS.size() - 1 and not "pistol" in c.value(), "unticking a weapon leaves the rest allowed")
	c.preferred = "bolt_action"
	c._set_single(true)
	_expect(c.value() == ["bolt_action"], "One gun starts on your own weapon")
	c._on_chip("rifle")
	_expect(c.value() == ["rifle"], "One gun: pressing another weapon makes that the one")
	c._set_single(false)
	c._on_chip("rifle")
	_expect(c.value() == ["rifle"], "the last allowed weapon cannot be unticked")
	c._on_chip("smg")
	_expect(c.value() == ["smg", "rifle"], "Any mix: ticking adds a weapon")
	c._all.pressed.emit()
	_expect(c.value() == [] and got.size() == 5, "Allow all goes back to any weapon; every change was reported (%d)" % got.size())
	c.free()


func _lobby_menu() -> void:
	print("  lobby")
	Net.start_offline("Host", "needle", "bolt_action")
	_settings(["shotgun", "rifle", "bolt_action"])
	var lobby: Control = load("res://game/ui/lobby_menu.tscn").instantiate()
	get_tree().root.add_child(lobby)
	await get_tree().process_frame
	var picker: WeaponPicker = lobby.find_children("*", "WeaponPicker", true, false)[0]
	var control: AllowedWeaponsPicker = lobby.find_children("*", "AllowedWeaponsPicker", true, false)[0]
	_expect(picker.allowed() == ["shotgun", "rifle", "bolt_action"], "the lobby's weapon cards offer only the allowed weapons")
	_expect(picker._cards["pistol"].disabled and not picker._cards["bolt_action"].disabled, "weapons that are not allowed are greyed out")
	_expect(control.is_visible_in_tree() and control._edit.visible, "the host sees the Weapons allowed control and can change it")
	control._set_single(true)
	await get_tree().process_frame
	_expect(Net.match_settings.weapons == ["bolt_action"], "the host's control changes the lobby setting (one gun: its own bolt-action)")
	_expect(lobby._weapon_card.disabled and lobby._no_weapon_note.visible, "one gun: the weapon card cannot be pressed and a note says why")
	_settings([], "dm")
	await get_tree().process_frame
	_expect(not control.is_visible_in_tree(), "a Deathmatch does not show the setting")
	lobby.queue_free()
	await get_tree().process_frame


func _loadout_menu() -> void:
	print("  pause menu loadout")
	Net.start_offline("Host", "needle", "bolt_action")
	for weapons in [["shotgun", "rifle"], ["bat"]]:
		_settings(weapons)
		Net.in_match = true
		var menu := PauseMenu.new()
		get_tree().root.add_child(menu)
		await get_tree().process_frame
		menu.call("_show_loadout")
		await get_tree().process_frame
		var guns := menu.find_children("*", "WeaponPicker", true, false)
		if weapons.size() > 1:
			_expect(guns.size() == 1 and (guns[0] as WeaponPicker).allowed() == weapons, "the Loadout offers only the allowed weapons")
			_expect(guns.size() == 1 and (guns[0] as WeaponPicker).current == "shotgun", "...starting on an allowed one (the saved bolt-action is not)")
		else:
			_expect(guns.is_empty(), "one gun: the Loadout has no weapon to pick")
		menu.queue_free()
		Net.in_match = false
		await get_tree().process_frame


func _jetpack() -> void:
	print("  jetpack")
	_expect(LobbySettings.clean({}).get("jetpack") == false, "a missing jetpack setting means no jetpack")
	_expect(LobbySettings.clean({"jetpack": "yes"}).get("jetpack") == false, "...and anything but true is off")
	_expect(LobbySettings.clean({"jetpack": true}).get("jetpack") == true, "true is on")
	_expect(not LobbySettings.clean({"mobility": ["blink", "portal"]}).has("mobility"), "an old saved list of allowed mobility tools is dropped")
	Net.start_offline("Host", "needle", "pistol", "blink")
	_expect(Net.player_loadout_mobility(1) == "grapple", "an old saved pick of a tool that is gone is the grappling hook")
	Net.host_add_player(2, "Client", "orbit", "rifle", "portal")
	_expect(Net.player_loadout_mobility(2) == "grapple", "a player who joins asking for a tool that is gone gets the hook")
	var forced := Net.add_bot(1, "", "blink")
	_expect(Net.player_loadout_mobility(forced) == "grapple", "so does a bot")
	Net.remove_bot(forced)
	var s := Net.match_settings.duplicate()
	s["game"] = "ffa"
	s["map"] = Maps.default_id("ffa")
	s["mode"] = "kills"
	s["weapons"] = []
	s.erase("jetpack")
	Net.set_match_settings(s)
	_expect(not LobbySettings.jetpack(), "nobody has the jetpack by default")
	s = Net.match_settings.duplicate()
	s["jetpack"] = true
	Net.set_match_settings(s)
	_expect(LobbySettings.jetpack(), "the host turns it on")
	s["game"] = "dm"
	s["map"] = Maps.default_id("dm")
	Net.set_match_settings(s)
	_expect(LobbySettings.jetpack(), "a Deathmatch has it too")
	s["game"] = "race"
	s["map"] = Maps.default_id("race")
	Net.set_match_settings(s)
	_expect(not LobbySettings.jetpack_apply() and not LobbySettings.jetpack(), "a race never has it")
	s["game"] = "ffa"
	s["map"] = Maps.default_id("ffa")
	s["jetpack"] = false
	Net.set_match_settings(s)
	var lobby: Control = load("res://game/ui/lobby_menu.tscn").instantiate()
	get_tree().root.add_child(lobby)
	await get_tree().process_frame
	var toggle: CheckButton = lobby._jetpack
	_expect(toggle.is_visible_in_tree() and not toggle.disabled and not toggle.button_pressed, "the host sees the Jetpack toggle in the lobby, off")
	toggle.button_pressed = true
	await get_tree().process_frame
	_expect(Net.match_settings.jetpack == true and LobbySettings.jetpack(), "the host's toggle turns the lobby setting on")
	toggle.button_pressed = false
	await get_tree().process_frame
	_expect(Net.match_settings.jetpack == false, "...and off again")
	lobby.queue_free()
	await get_tree().process_frame
	Net.players.erase(2)


func _ready_and_size() -> void:
	print("  lobby size, ready and kick")
	_expect(LobbySettings.clean({}).max_players == 16, "the lobby takes 16 players unless the host says otherwise")
	_expect(LobbySettings.clean({"max_players": 1}).max_players == 2 and LobbySettings.clean({"max_players": 40}).max_players == 16,
		"the lobby size stays between 2 and 16")
	Net.start_offline("Host", "needle", "pistol")
	Net.players[2] = {"name": "Client", "color": 1, "character": "orbit", "weapon": "rifle", "mobility": "grapple"}
	Net.players[3] = {"name": "Other", "color": 2, "character": "rivet", "weapon": "smg", "mobility": "grapple"}
	var s := Net.match_settings.duplicate()
	s["game"] = "ffa"
	s["map"] = Maps.default_id("ffa")
	s["mode"] = "kills"
	s["max_players"] = 4
	Net.set_match_settings(s)
	_expect(LobbySettings.max_players() == 4, "the host's lobby size is kept in the match settings")
	_expect(Net.is_ready(1) and not Net.is_ready(2) and Net.not_ready() == [2, 3], "the host counts as ready; the others start not ready")
	Net.is_online = true   # pretend: the ready rule is for online lobbies
	Net.host_start_match()
	_expect(not Net.in_match, "the host cannot start while anyone is not ready")
	Net._apply_ready(2, true)
	_expect(Net.is_ready(2) and Net.not_ready() == [3], "a player who readies up is ready")
	var bot := Net.add_bot(1)
	_expect(Net.is_ready(bot), "bots are always ready")
	Net.is_online = false   # (bots can only be taken out offline)
	Net.remove_bot(bot)
	Net.is_online = true
	var lobby: Control = load("res://game/ui/lobby_menu.tscn").instantiate()
	get_tree().root.add_child(lobby)
	await get_tree().process_frame
	var start: Button = lobby._start
	_expect(start.disabled and "1" in start.text, "Start waits for the one player not ready yet (%s)" % start.text)
	var kicks := lobby.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text == "Kick")
	_expect(kicks.size() == 2, "the host has a Kick button on each other player's row (%d)" % kicks.size())
	var moves := lobby.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text == "Spectate" and b.get_parent() != lobby._spectate.get_parent())
	_expect(moves.size() == 2, "the host has a Spectate button on each other player's row (%d)" % moves.size())
	_expect(Net.player_slot_free(), "a player slot is free in a lobby of 4 with 3 players")
	Net.spectators[5] = {"name": "Watcher"}
	_expect(not Net.host_move_to_spectators(1) and Net.players.has(1), "the host cannot move itself to the spectators this way")
	Net.players[4] = {"name": "Fourth", "color": 3, "character": "orbit", "weapon": "rifle", "mobility": "grapple"}
	_expect(not Net.player_slot_free() and not Net.host_set_spectating(5, false), "with the lobby full, a spectator cannot come back to play")
	Net.players.erase(4)
	_expect(Net.host_set_spectating(5, false) and Net.players.has(5) and not Net.spectators.has(5), "with a slot free, a spectator comes back to play")
	Net.players.erase(5)
	Net.players_changed.emit()   # the lobby redraws without the test player
	var tags := []
	for l in lobby.find_children("*", "Label", true, false):
		if (l as Label).text in ["READY", "NOT READY"]:
			tags.append((l as Label).text)
	tags.sort()
	_expect(tags == ["NOT READY", "READY"], "the list shows who is ready (%s)" % [tags])
	_expect(lobby._size_box.visible and int(lobby._size.value) == 4 and int(lobby._size.min_value) == 3,
		"the host sets the lobby size, never below the players already in")
	Net._apply_ready(3, true)
	await get_tree().process_frame
	_expect(Net.all_ready() and not start.disabled and start.text == "START MATCH", "once everyone is ready the host can start")
	Net._apply_ready(3, false)
	_expect(not Net.all_ready(), "a player can take back their ready")
	lobby.queue_free()
	Net.is_online = false
	await get_tree().process_frame


## The lobby shows only what is picked; a button opens a floating window with every
## choice (mode for the host; robot and weapon for everyone).
func _floating_windows() -> void:
	print("  floating windows")
	# The lobby saves your picks as your own (Settings): put back what was there after.
	var kept := [Settings.weapon, Settings.mobility, Settings.character]
	Net.start_offline("Host", "needle", "rifle", "grapple")
	var s := Net.match_settings.duplicate()
	s["game"] = "ffa"
	s["map"] = Maps.default_id("ffa")
	s["mode"] = "kills"
	s["weapons"] = []
	Net.set_match_settings(s)
	var lobby: Control = load("res://game/ui/lobby_menu.tscn").instantiate()
	get_tree().root.add_child(lobby)
	await get_tree().process_frame
	var panels := [lobby._mode_panel, lobby._robot_panel, lobby._weapon_panel]
	_expect(panels.all(func(p): return not p.is_open()), "every window starts closed")
	_expect(lobby._mode_button.text == "Shoot-out" and lobby._weapon_card.id == "rifle"
		and lobby._character._name_button.text == Characters.name_of("needle"), "the page shows what is picked")
	lobby._mode_button.pressed.emit()
	await get_tree().process_frame
	_expect(lobby._mode_panel.is_open() and lobby._mode_blurb.text.begins_with("Shoot-out:"), "the host's mode button opens the mode window, about the mode picked")
	(lobby._game_row.get_child(GunGame.MODES.find("gungame")) as Button).mouse_entered.emit()
	_expect(lobby._mode_blurb.text.begins_with("Gun Game:"), "hovering a mode shows what it is")
	(lobby._game_row.get_child(GunGame.MODES.find("gungame")) as Button).pressed.emit()
	await get_tree().process_frame
	_expect(not lobby._mode_panel.is_open() and GunGame.active() and lobby._mode_button.text == "Gun Game", "picking a mode closes the window and the button shows it")
	s = Net.match_settings.duplicate()
	s["mode"] = "kills"
	Net.set_match_settings(s)
	lobby._weapon_card.pressed.emit()
	await get_tree().process_frame
	_expect(lobby._weapon_panel.is_open(), "the weapon card opens the weapon window")
	lobby._weapon._on_pressed("shotgun")
	await get_tree().process_frame
	_expect(not lobby._weapon_panel.is_open() and lobby._weapon_card.id == "shotgun" and Net.player_loadout_weapon(1) == "shotgun",
		"picking a weapon closes the window, and the card and the lobby have it")
	lobby._character._name_button.pressed.emit()
	await get_tree().process_frame
	_expect(lobby._robot_panel.is_open() and lobby._character.list.is_visible_in_tree(), "the robot's name opens the robot window")
	lobby._robot_panel.close()
	_expect(not lobby._robot_panel.is_open(), "a window closes without a pick (click outside or Esc)")
	# The Character Creator, from the robot window ("Make new character").
	lobby._character._name_button.pressed.emit()
	await get_tree().process_frame
	var make: Array = lobby._character.list.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text == "Make new character")
	_expect(make.size() == 1, "the robot window has a Make new character button")
	make[0].pressed.emit()
	await get_tree().process_frame
	var creator_panel: FloatingPanel = lobby._creator_panel
	_expect(creator_panel != null and creator_panel.is_open() and not lobby._robot_panel.is_open()
		and creator_panel.content.find_children("*", "CharacterCreator", true, false).size() == 1,
		"it opens the Character Creator in a window (the robot window closes)")
	var cancel: Array = creator_panel.content.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text == "Cancel")
	cancel[0].pressed.emit()
	await get_tree().process_frame
	_expect(lobby._creator_panel == null, "Cancel closes the creator without saving")
	# A character saved in the creator joins the robot list (kept in memory only here).
	var saved: Array = Settings.custom_characters.duplicate()
	var fresh := CustomCharacter.new()
	fresh.name = "Lobby Test"
	var fresh_id := fresh.to_id()
	Settings.custom_characters.append(fresh_id)
	lobby._character.refresh_custom()
	_expect(lobby._character._buttons.has(fresh_id), "a newly saved character gets a button in the robot window")
	Settings.custom_characters.erase(fresh_id)
	lobby._character.refresh_custom()
	_expect(not lobby._character._buttons.has(fresh_id), "a deleted one loses its button")
	Settings.custom_characters = saved
	Settings.weapon = kept[0]
	Settings.mobility = kept[1]
	Settings.character = kept[2]
	Settings.save_settings()
	for rule in [lobby._allowed]:
		rule._edit.pressed.emit()
		await get_tree().process_frame
		_expect(rule.window() != null and rule.window().is_open(), "a loadout rule's Change opens its chips in a window")
		rule._edit.pressed.emit()
		_expect(not rule.window().is_open(), "...and Change again closes it")
	lobby.queue_free()
	await get_tree().process_frame
