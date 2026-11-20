extends Node
## Random map and lobby song checks (see LobbySettings, Music):
##  - the stored pool is cleaned (unknown and test maps dropped, every map is []); only
##    the maps for the game set up count, and with none of them ticked, all of them do;
##  - ticking and unticking: the other games' maps stay as they were; the last map
##    ticked for a game stays ticked;
##  - the pick is always from the pool, never the map just played when the pool has
##    another, and covers the whole pool; the host's pick goes into match_settings.map;
##  - the song setting is cleaned;
##  - the lobby: "Random map" in the host's drop-down turns it on, the pool shows and its
##    chips change it, the song drop-down lists Shuffle and every song and changes it;
##    a client sees read-only lines instead;
##  - Vs Bots and Practice: "Random map" in their drop-downs too, with the pool;
##    Game.with_map turns a random choice into settings;
##  - the music: a song cut short fades out over FADE seconds; the state sent to clients
##    carries it; a picked song plays at once.
## Started by tests/host_controls_test.gd.

var _fails: Array[String] = []


func run() -> void:
	await get_tree().process_frame
	print("Host controls checks")
	_pool_rules()
	_picking()
	_song_setting()
	await _lobby()
	await _menus()
	_music()
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


func _pool_rules() -> void:
	print("  pool rules")
	var arenas := Maps.random_ids("ffa")
	var races := Maps.random_ids("race")
	_expect(not "testing_grounds" in arenas and not "castle_v2" in arenas and "office" in arenas, "Random never picks a test map")
	_expect(races == Maps.ids_for("race"), "a race's pool is the race maps")
	_expect(LobbySettings.normalized_pool(["office", "nowhere", "testing_grounds", "office"]) == ["office"], "unknown and test maps are dropped, each map once")
	_expect(LobbySettings.normalized_pool(arenas + races) == [], "every map ticked is stored as []")
	_expect(LobbySettings.normalized_pool("office") == [], "a pool that is not a list is every map")
	_expect(LobbySettings.pool_for([], "ffa") == arenas, "[]: every arena")
	_expect(LobbySettings.pool_for(["office", "foundry"], "ffa") == ["office"], "only the game's own maps count (a shoot-out)")
	_expect(LobbySettings.pool_for(["office", "foundry"], "race") == ["foundry"], "only the game's own maps count (a race)")
	_expect(LobbySettings.pool_for(["office"], "race") == races, "none of this game's maps ticked: all of them")
	_expect(LobbySettings.pool_for(["office", "castle"], "dm") == ["office", "castle"], "a Deathmatch uses the arenas")
	# Ticking and unticking.
	var p := LobbySettings.pool_toggled([], "ffa", "office")
	_expect(not "office" in LobbySettings.pool_for(p, "ffa") and LobbySettings.pool_for(p, "ffa").size() == arenas.size() - 1, "unticking a map takes it out")
	_expect(LobbySettings.pool_for(p, "race") == races, "...and leaves the race maps alone")
	p = LobbySettings.pool_toggled(p, "ffa", "office")
	_expect(p == [], "ticking it again: every map ([])")
	var one := []
	for id in arenas:
		if id != "kilnworks":
			one = LobbySettings.pool_toggled(one, "ffa", id)
	_expect(LobbySettings.pool_for(one, "ffa") == ["kilnworks"], "untick all but one")
	_expect(LobbySettings.pool_toggled(one, "ffa", "kilnworks") == one, "the last map ticked stays ticked")
	_expect(LobbySettings.pool_toggled(one, "ffa", "foundry") == one and LobbySettings.pool_toggled(one, "ffa", "testing_grounds") == one,
		"a map for another game (or a test map) cannot be ticked for this one")
	_expect(LobbySettings.pool_for(LobbySettings.pool_toggled(one, "race", "foundry"), "ffa") == ["kilnworks"], "unticking a race map keeps the arena pool")
	_expect(LobbySettings.pool_summary([], "ffa").contains(str(arenas.size())), "the summary says how many maps: " + LobbySettings.pool_summary([], "ffa"))
	_expect(LobbySettings.pool_summary(["office", "castle"], "ffa").contains("Office"), "...or which: " + LobbySettings.pool_summary(["office", "castle"], "ffa"))


func _picking() -> void:
	print("  picking")
	var pool := ["office", "castle", "halcyon"]
	var seen := {}
	var ok := true
	var repeat := false
	var last := "office"
	for i in 300:
		var m := LobbySettings.pick_map(pool, "ffa", last)
		ok = ok and m in pool
		repeat = repeat or m == last
		seen[m] = true
		last = m
	_expect(ok, "300 picks: every one from the pool")
	_expect(not repeat, "never the map just played (the pool has others)")
	_expect(seen.size() == pool.size(), "every map in the pool comes up")
	_expect(LobbySettings.pick_map(["cirrus"], "ffa", "cirrus") == "cirrus", "a pool of one: that map, even again")
	var race_ok := true
	for i in 50:
		race_ok = race_ok and LobbySettings.pick_map(["office", "sky_ruins", "foundry"], "race") in ["sky_ruins", "foundry"]
	_expect(race_ok, "a race picks only from the race maps ticked")
	# The host's pick goes into the settings everyone gets (offline, this copy hosts).
	Net.start_offline("Host", "needle", "bolt_action")
	var s := Net.match_settings.duplicate()
	s["game"] = "ffa"
	s["mode"] = "kills"
	s["map"] = "office"
	s["random_map"] = true
	s["map_pool"] = ["office", "kilnworks"]
	Net.set_match_settings(s)
	Net.host_pick_random_map()
	_expect(Net.map_id() == "kilnworks", "the host picks from the pool, not the map just played (got %s)" % Net.map_id())
	_expect(Net.match_settings.random_map and Net.match_settings.map_pool == ["office", "kilnworks"], "Random stays on for the next match, with its pool")
	s = Net.match_settings.duplicate()
	s["random_map"] = false
	Net.set_match_settings(s)
	Net.host_pick_random_map()
	_expect(Net.map_id() == "kilnworks", "Random off: the map stays as the host set it")
	# Changing the game: the pool follows it.
	s = Net.match_settings.duplicate()
	s = GunGame.with_mode(s, "race", Maps.default_id("race"))
	s["random_map"] = true
	Net.set_match_settings(s)
	Net.host_pick_random_map()
	_expect(Maps.game_of(Net.map_id()) == "race" and Net.game_kind() == "race", "a race: a race map (%s)" % Net.map_id())


func _song_setting() -> void:
	print("  song setting")
	_expect(LobbySettings.clean({}).song == "" and LobbySettings.clean({}).random_map == false and LobbySettings.clean({}).map_pool == [],
		"new settings: shuffle, no random map, every map")
	_expect(LobbySettings.clean({"song": 5}).song == "" and LobbySettings.clean({"random_map": "yes"}).random_map == false, "bad values are cleaned")
	var names := Music.song_names()
	_expect(names.size() >= 2, "there are songs to pick from (%d)" % names.size())
	_expect(LobbySettings.clean({"song": names[0]}).song == names[0], "a song's name is kept")
	_expect(Music.title_of("") == "Shuffle" and Music.title_of("immersive_bark_2") == "Immersive Bark 2", "song titles read well")


func _lobby() -> void:
	print("  lobby")
	Net.start_offline("Host", "needle", "bolt_action")
	var s := Net.match_settings.duplicate()
	s = GunGame.with_mode(s, "ffa", "office")
	s["map"] = "office"
	s["random_map"] = false
	s["map_pool"] = []
	s["song"] = ""
	Net.set_match_settings(s)
	var lobby: Control = load("res://game/ui/lobby_menu.tscn").instantiate()
	get_tree().root.add_child(lobby)
	await get_tree().process_frame
	var map_button: Button = lobby.get("_map_button")
	var map_window: FloatingPanel = lobby.get("_map_window")
	var pool: MapPoolPicker = lobby.get("_map_pool")
	var song_button: Button = lobby.get("_song_button")
	var song_window: FloatingPanel = lobby.get("_song_window")
	_expect(map_button.is_visible_in_tree() and map_button.text == Maps.label("office"), "the host's map button shows the map (%s)" % map_button.text)
	map_button.pressed.emit()
	await get_tree().process_frame
	var choices := _choice_texts(map_window)
	_expect(map_window.is_open() and choices.size() == Maps.ids_for("ffa").size() + 1 and choices[-1] == "Random map",
		"the map window: every map, then Random map (%s)" % [choices])
	_expect(not pool.is_visible_in_tree(), "no pool while a map is picked")
	_choice(map_window, "Random map").pressed.emit()
	await get_tree().process_frame
	_expect(Net.match_settings.random_map == true and not map_window.is_open(), "picking Random turns the random map on and closes the window")
	_expect(map_button.text == "Random map", "the map button says Random map")
	_expect(pool.is_visible_in_tree() and pool._edit.visible, "the host sees the pool and can change it")
	pool._edit.pressed.emit()
	await get_tree().process_frame
	_expect(pool.window() != null and pool.window().is_open(), "Change opens the pool in a window of its own")
	(pool._chips["office"] as Button).pressed.emit()
	await get_tree().process_frame
	_expect(not "office" in LobbySettings.map_pool(), "the host's chip takes a map out of the pool")
	_expect(pool.window().is_open(), "the pool window stays open for more ticks")
	_expect(pool._chips.size() == Maps.random_ids("ffa").size(), "one chip per arena (no test maps)")
	pool.window().close()
	# The lobby song.
	_expect(song_button.is_visible_in_tree() and song_button.text == "Shuffle", "the host's song button shows the song (Shuffle)")
	song_button.pressed.emit()
	await get_tree().process_frame
	var songs := _choice_texts(song_window)
	_expect(song_window.is_open() and songs.size() == Music.song_names().size() + 1 and songs[0] == "Shuffle",
		"the song window: Shuffle and every song")
	_choice(song_window, Music.title_of(Music.song_names()[1])).pressed.emit()
	await get_tree().process_frame
	_expect(Net.match_settings.song == Music.song_names()[1] and not song_window.is_open(), "picking a song sets the lobby song (%s)" % Net.match_settings.song)
	# Back to a map.
	map_button.pressed.emit()
	await get_tree().process_frame
	_choice(map_window, Maps.label(Maps.ids_for("ffa")[1])).pressed.emit()
	await get_tree().process_frame
	_expect(not Net.match_settings.random_map and Net.map_id() == Maps.ids_for("ffa")[1], "picking a map turns Random off")
	_expect(not pool.is_visible_in_tree(), "...and hides the pool")
	# What everyone else sees: read-only lines (a client is any copy that is not the host).
	s = Net.match_settings.duplicate()
	s["random_map"] = true
	Net.set_match_settings(s)
	lobby.call("_refresh")
	var map_label: Label = lobby.get("_map_label")
	var song_label: Label = lobby.get("_song_label")
	_expect(not song_label.visible and song_button.visible and map_button.visible and not map_label.visible, "the host gets the buttons, not the lines")
	# Everyone else gets the lines, filled the same way (offline this copy is always the host).
	_expect(map_label.text.begins_with("Random map"), "the map line says Random (%s)" % map_label.text)
	_expect(song_label.text == Music.title_of(Music.song_names()[1]), "the song line names the host's song (%s)" % song_label.text)
	lobby.queue_free()
	await get_tree().process_frame


func _menus() -> void:
	print("  Vs Bots and Practice")
	var menu: Control = load("res://game/ui/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	for page in ["_show_practice"]:   # (Vs Bots is the lobby now)
		menu.call(page)
		await get_tree().process_frame
		var picks := menu.find_children("*", "OptionButton", true, false).filter(func(o): return o.has_meta("pool") and o.is_visible_in_tree())
		_expect(picks.size() == 1, "%s: a map drop-down with a pool" % page)
		if picks.is_empty():
			continue
		var pick: OptionButton = picks[0]
		var pool: MapPoolPicker = pick.get_meta("pool")
		_expect(pick.get_item_metadata(pick.item_count - 1) == Maps.RANDOM, "%s: Random map in the drop-down" % page)
		pick.select(pick.item_count - 1)
		pick.item_selected.emit(pick.item_count - 1)
		_expect(pool.is_visible_in_tree() and pool._edit.visible, "%s: picking Random shows the pool, to change" % page)
		pool._open(true)
		(pool._chips["castle"] as Button).pressed.emit()
		_expect(not "castle" in LobbySettings.pool_for(Game.last_map_pool, "ffa"), "%s: its chips change the pool" % page)
		(pool._chips["castle"] as Button).pressed.emit()
		pick.select(0)
		pick.item_selected.emit(0)
		_expect(not pool.is_visible_in_tree(), "%s: a map picked hides the pool" % page)
	menu.queue_free()
	await get_tree().process_frame
	# Starting a match with Random: the settings it makes.
	Game.last_map_pool = ["office", "castle", "foundry"]
	var s := Game.with_map({"mode": "kills"}, Maps.RANDOM, "ffa")
	_expect(s.random_map and s.game == "ffa" and Maps.fits(s.map, "ffa") and s.map_pool == ["office", "castle", "foundry"], "Random in Vs Bots: on, with the pool")
	s = Game.with_map({"mode": "kills"}, Maps.RANDOM, "race")
	_expect(s.random_map and s.game == "race" and Maps.game_of(s.map) == "race", "Random for a race: a race")
	s = Game.with_map(s, "office", "ffa")
	_expect(not s.random_map and s.map == "office", "a map picked: Random is off")
	Net.start_offline("Host", "needle", "bolt_action")
	Net.match_settings = Game.with_map(Net.match_settings, Maps.RANDOM, "ffa")
	Net.host_pick_random_map()
	_expect(Net.map_id() in ["office", "castle"], "Vs Bots: the pick is one of the pool's arenas (%s)" % Net.map_id())


func _music() -> void:
	print("  music")
	var now := Music.host_now()
	Music._songs.clear()
	Music._start(0, now - 10.0, false)
	_expect(Music._stop_time(Music._songs[0]) == Music._length(0), "a song plays to its end")
	Music._fade_out_all(now)
	Music._start(1, now, false)
	var old: Dictionary = Music._songs[0]
	_expect(is_equal_approx(Music._stop_time(old), 10.0 + Music.FADE), "cut short: it fades out over FADE seconds from now")
	_expect(Music.current_song() == Music.song_names()[1], "the picked song is the one playing now")
	var state: Array = Music._state()
	_expect(state.size() == 2 and is_equal_approx(float(state[0][2]), now + Music.FADE) and float(state[1][2]) < 0.0,
		"the state sent to clients says when the old song is gone")
	# A client takes the host's state, cut and all.
	Music._songs.clear()
	Music._play(state)
	_expect(Music._songs.size() == 2 and is_equal_approx(float(Music._songs[0].end), now + Music.FADE) and Music.current_song() == Music.song_names()[1],
		"a client plays the same: the old song fading out, the picked one in")
	Music._fade_out_all(now + 1.0)
	_expect(is_equal_approx(float(Music._songs[0].end), now + Music.FADE), "fading out again never makes a song last longer")
	_expect(Music._lobby_song() == -1, "offline (no lobby): no lobby song, the songs shuffle")


## The texts of the choice buttons in a lobby window (see the lobby's _open_choices).
func _choice_texts(window: FloatingPanel) -> Array:
	return window.content.find_children("*", "Button", true, false).map(func(b): return (b as Button).text)


func _choice(window: FloatingPanel, text: String) -> Button:
	for b in window.content.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return Button.new()
