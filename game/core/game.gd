extends Node
## Moves the game between screens: main menu, lobby, arena.
## Listens to the network so every player changes screen at the same moment.

const MAIN_MENU := "res://game/ui/main_menu.tscn"
const LOBBY := "res://game/ui/lobby_menu.tscn"
const ARENA := "res://game/arena/arena.tscn"
const RESULTS := "res://game/ui/results_menu.tscn"

enum Mode { NONE, PRACTICE, BOT, ONLINE }

## Most bots in one offline match: you plus these fill a five-player free-for-all.
const MAX_BOTS := 4
## Team modes (Search and Destroy, Capture the Flag) take more: you and seven bots are 4v4.
const MAX_TEAM_BOTS := 7

var mode: Mode = Mode.NONE
## A message to show on the main menu (for example "The host left").
var pending_notice := ""
## The last bot match's settings, for a rematch and the next Vs Bots lobby. "bots": how
## many bots (1 is a 1v1); "levels": each one's difficulty (else all "difficulty").
## "game": "ffa", "dm" or "race" (one the map can host).
var last_bot := {"difficulty": 1, "kills": 10, "map": Maps.default_id(), "bots": 1, "game": "ffa"}
## The map and kind of game last picked for practice.
var last_practice_map := Maps.default_id()
var last_practice_game := "ffa"
## The map last picked for each kind of game, so the menus remember both.
var last_map := {"ffa": Maps.default_id("ffa"), "dm": Maps.default_id("dm"), "race": Maps.default_id("race")}
## The maps a random map may pick from in Vs Bots and Practice (as stored; see
## LobbySettings.pool_for). The menus' map drop-downs offer "Random map" (Maps.RANDOM).
var last_map_pool: Array = []
## The movement variant last picked (MovementTuning.VARIANTS) on the Practice or Vs Bots
## page or in a lobby you hosted; the next match you set up starts with it.
var last_movement := MovementTuning.DEFAULT_VARIANT


func _ready() -> void:
	Net.match_started.connect(_on_match_started)
	Match.match_over.connect(_on_match_over)
	Net.session_ended.connect(_on_session_ended)
	Net.joined_lobby.connect(_on_joined_lobby)
	Net.join_failed.connect(_on_join_failed)
	Net.players_changed.connect(_on_players_changed)
	_run_dev_args.call_deferred()


func local_name() -> String:
	if DevArgs.player_name != "":
		return DevArgs.player_name
	if Settings.player_name != "":
		return Settings.player_name
	return "Player"


## The robot this copy of the game plays as.
func local_character() -> String:
	return DevArgs.character if DevArgs.character != "" else Settings.character


## The release this copy of the game is ("v0.1.29"), or "DEV BUILD" when it is not a
## release build. The playtest build workflow stamps the version tag into the project
## (application/config/version) before it exports the game.
func version_label() -> String:
	var v := version()
	return v if v != "" else "DEV BUILD"


## The release this copy is ("v0.1.29"), or "" for a build that is not a release
## (the editor, a local export). --fake-version=vX.Y.Z pretends (tests).
func version() -> String:
	if DevArgs.fake_version != "":
		return DevArgs.fake_version
	return str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()


## Compares two release versions ("v0.1.29"): -1 if a is older than b, 0 if the
## same, 1 if newer.
static func compare_versions(a: String, b: String) -> int:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0


## What to tell a player whose copy is on `mine` when the host is on `host`: both
## versions, and that whoever is behind should update. "" when they match or either
## is not a release build.
static func version_mismatch_text(host: String, mine: String) -> String:
	if host == "" or mine == "" or compare_versions(host, mine) == 0:
		return ""
	if compare_versions(mine, host) < 0:
		return "The host is on %s and you are on %s. Update your game to %s or newer to join (the latest is on the Releases page)." % [host, mine, host]
	return "The host is on %s and you are on %s. The host needs to update their game to %s for you to join." % [host, mine, mine]


## The mobility tool this copy of the game takes into a match.
func local_mobility() -> String:
	return DevArgs.mobility if DevArgs.mobility != "" else Settings.mobility


## The gun this copy of the game takes into a match.
func local_weapon() -> String:
	return DevArgs.weapon if DevArgs.weapon != "" else Settings.weapon


## The movement variant the next match you set up uses: --movement, else the last picked.
func movement_choice() -> String:
	return DevArgs.movement if DevArgs.movement != "" else MovementTuning.valid_variant(last_movement)


func goto_main_menu(notice: String = "") -> void:
	if notice != "":
		pending_notice = notice
	mode = Mode.NONE
	_release_mouse()
	get_tree().change_scene_to_file.call_deferred(MAIN_MENU)


## The graphics benchmark (Settings > Graphics): flies over three maps and saves a
## report (see Benchmark). Only from the menus, never during a match.
func start_benchmark() -> void:
	mode = Mode.NONE
	var bench := Benchmark.new()
	bench.finished.connect(func(path: String):
		print("BENCHMARK_REPORT %s" % path)
		if DevArgs.benchmark:
			get_tree().quit())
	get_tree().change_scene_to_node.call_deferred(bench)


func goto_lobby() -> void:
	_release_mouse()
	get_tree().change_scene_to_file.call_deferred(LOBBY)


func start_practice(map: String = "", game: String = "") -> void:
	mode = Mode.PRACTICE
	if map != "":
		last_practice_map = map
		last_practice_game = _game_for(map, game)
		if map != Maps.RANDOM:
			last_map[last_practice_game] = map
	Net.start_offline(local_name(), local_character(), local_weapon(), local_mobility())
	Net.match_settings = with_map(Net.match_settings, _map_choice(last_practice_map), DevArgs.game if DevArgs.game != "" else last_practice_game)
	Net.match_settings["weapons"] = DevArgs.allowed_weapons.duplicate()   # practice: every weapon (unless a test says)
	Net.match_settings["jetpack"] = DevArgs.jetpack   # ...and no jetpack (unless a test says)
	Net.match_settings["movement"] = movement_choice()
	Net.host_start_match()


## `game` if the map can host it, else the map's own kind of game. A random map takes
## `game` as it is.
func _game_for(map: String, game: String) -> String:
	if map == Maps.RANDOM:
		return Maps.valid_game(game)
	return game if game in Maps.games_of(map) else Maps.game_of(map)


## Match settings with the map (or Maps.RANDOM: one from the pool, picked as the match
## starts; see Net.host_pick_random_map) and kind of game set.
func with_map(settings: Dictionary, map: String, game: String) -> Dictionary:
	var s := settings.duplicate()
	var g := _game_for(map, game)
	s["random_map"] = map == Maps.RANDOM
	s["map"] = map if map != Maps.RANDOM else Maps.default_id(g)
	s["game"] = g
	if map == Maps.RANDOM:
		s["map_pool"] = DevArgs.map_pool.duplicate() if not DevArgs.map_pool.is_empty() else last_map_pool.duplicate()
	return LobbySettings.clean(s)


## An offline match against computer players: a 1v1 with one bot, or a
## free-for-all with up to MAX_BOTS (you plus four bots is a full five).
## gun_game: Gun Game rules instead of first to `kills_to_win` (see GunGame).
## game: "dm" for a Deathmatch ("" keeps the last one, or follows the map).
## rules: "kills", or a free-for-all mode with rules of its own ("gungame", "killcam", or the
## team modes "snd" and "ctf": GunGame.RULES). In a team mode you are Red and the bots alternate
## Blue, Red, Blue... (up to MAX_TEAM_BOTS).
## weapons: the weapons allowed in a shoot-out (see LobbySettings; [] all of them,
## null keeps the last choice). jetpack: everyone has the jetpack (null keeps the last choice).
## killcam: the Killcam mode's {"killcam_points", "killcam_minutes"} (see KillcamMode;
## {} keeps the last choice).
func start_bot(difficulty: int, kills_to_win: int, map: String = "", bots: int = 0, rules: String = "kills", game: String = "",
		weapons = null, jetpack = null, killcam: Dictionary = {}) -> void:
	if not rules in GunGame.RULES:
		rules = "kills"
	mode = Mode.BOT
	if bots <= 0:
		bots = int(last_bot.get("bots", 1))
	bots = clampi(bots, 1, max_bots(rules))
	var picked: String = map if map != "" else last_bot.map
	if game == "":
		game = str(last_bot.get("game", ""))
	if weapons == null:
		weapons = last_bot.get("weapons", [])
	if not DevArgs.allowed_weapons.is_empty():
		weapons = DevArgs.allowed_weapons
	if jetpack == null:
		jetpack = last_bot.get("jetpack", false) == true
	if DevArgs.jetpack:
		jetpack = true
	var killcam_points := KillcamMode.clean_points(killcam.get("killcam_points", last_bot.get("killcam_points")))
	if DevArgs.points_target > 0:
		killcam_points = KillcamMode.clean_points(DevArgs.points_target)
	var killcam_minutes := KillcamMode.clean_minutes(killcam.get("killcam_minutes", last_bot.get("killcam_minutes")))
	var levels_before := bot_levels()   # (each bot's level, kept for a rematch with the same bots)
	var same_bots := levels_before.size() == bots and difficulty == int(last_bot.get("difficulty", -1))
	last_bot = {"difficulty": difficulty, "levels": levels_before if same_bots else [], "kills": kills_to_win, "map": picked, "bots": bots, "game": _game_for(picked, game),
		"rules": rules, "weapons": LobbySettings.normalized_weapons(weapons), "jetpack": jetpack == true,
		"killcam_points": killcam_points, "killcam_minutes": killcam_minutes}
	if picked != Maps.RANDOM:
		last_map[last_bot.game] = picked
	Net.start_offline(local_name(), local_character(), local_weapon(), local_mobility())
	Net.match_settings = with_map({"mode": rules, "kills": kills_to_win, "minutes": 8, "race_minutes": 10,
		"weapons": last_bot.weapons, "jetpack": last_bot.jetpack,
		"killcam_points": killcam_points, "killcam_minutes": killcam_minutes, "movement": movement_choice()},
		_map_choice(last_bot.map), DevArgs.game if DevArgs.game != "" else last_bot.game)
	var levels := bot_levels()
	for i in bots:
		Net.add_bot(int(levels[i]) if i < levels.size() else difficulty, DevArgs.bot_weapon, DevArgs.bot_mobility)
	Net.host_start_match()


## Each bot's difficulty in the last bot match (or lobby).
func bot_levels() -> Array:
	var levels = last_bot.get("levels", [])
	if not levels is Array or (levels as Array).size() != int(last_bot.get("bots", 1)):
		levels = []
		for i in int(last_bot.get("bots", 1)):
			levels.append(int(last_bot.get("difficulty", 1)))
	return levels


## Vs Bots: the lobby (see LobbyMenu), offline, set up as last time: you and your bots on
## the left, the match in the middle, your loadout on the right. Start plays it
## (start_bot_lobby).
func open_bot_lobby() -> void:
	mode = Mode.BOT
	Net.start_offline(local_name(), local_character(), local_weapon(), local_mobility())
	Net.match_settings = with_map({"mode": str(last_bot.get("rules", "kills")), "kills": int(last_bot.get("kills", 10)),
		"minutes": 8, "race_minutes": 10, "weapons": last_bot.get("weapons", []), "jetpack": last_bot.get("jetpack", false) == true or DevArgs.jetpack,
		"killcam_points": KillcamMode.clean_points(last_bot.get("killcam_points")),
		"killcam_minutes": KillcamMode.clean_minutes(last_bot.get("killcam_minutes")), "movement": movement_choice()},
		_map_choice(str(last_bot.get("map", Maps.default_id()))), str(last_bot.get("game", "ffa")))
	for d in bot_levels():
		Net.add_bot(int(d), DevArgs.bot_weapon, DevArgs.bot_mobility)
	goto_lobby()


## The Vs Bots lobby's Start: remember how it is set up (for a rematch and next time),
## then play.
func start_bot_lobby() -> void:
	remember_bot_lobby()
	Net.host_start_match()


func remember_bot_lobby() -> void:
	var s := Net.match_settings
	var levels: Array = Net.bot_ids().map(func(id): return int(Net.players[id].get("difficulty", 1)))
	var random := bool(s.get("random_map", false))
	last_bot = {"difficulty": int(levels[0]) if not levels.is_empty() else int(last_bot.get("difficulty", 1)),
		"levels": levels, "bots": maxi(levels.size(), 1), "kills": int(s.get("kills", 10)),
		"map": Maps.RANDOM if random else str(s.get("map", Maps.default_id())), "game": str(s.get("game", "ffa")),
		"rules": str(s.get("mode", "kills")), "weapons": LobbySettings.normalized_weapons(s.get("weapons", [])),
		"jetpack": s.get("jetpack", false) == true,
		"killcam_points": KillcamMode.clean_points(s.get("killcam_points")), "killcam_minutes": KillcamMode.clean_minutes(s.get("killcam_minutes"))}
	if random:
		last_map_pool = s.get("map_pool", [])
	elif Maps.has(str(last_bot.map)):
		last_map[last_bot.game] = last_bot.map
	last_movement = str(s.get("movement", last_movement))


## The most bots an offline match with these rules can have.
static func max_bots(rules: String) -> int:
	return MAX_TEAM_BOTS if rules in Teams.MODES else MAX_BOTS


## Same bots and rules again (from the results screen).
func rematch_bot() -> void:
	start_bot(last_bot.difficulty, last_bot.kills, "", last_bot.bots, str(last_bot.get("rules", "kills")), str(last_bot.get("game", "")))


## The map to play: the one picked in the menu, unless --map=ID overrides it.
func _map_choice(picked: String) -> String:
	if DevArgs.map != "":
		return DevArgs.map
	if DevArgs.race:
		return Maps.default_id("race")
	return picked if Maps.has(picked) or picked == Maps.RANDOM else Maps.default_id()


func host_online() -> Error:
	mode = Mode.ONLINE
	var port := DevArgs.port if DevArgs.port > 0 else Net.DEFAULT_PORT
	var err := Net.host_direct(local_name(), local_character(), port, local_weapon(), local_mobility())
	if err == OK and LobbySettings.movement() != movement_choice():
		var with_movement := Net.match_settings.duplicate()
		with_movement["movement"] = movement_choice()
		Net.set_match_settings(with_movement)
	if err == OK and (DevArgs.map != "" or DevArgs.race):
		Net.set_match_settings(with_map(Net.match_settings, _map_choice(""), DevArgs.game if DevArgs.game != "" else ("race" if DevArgs.race else "")))
	elif err == OK and DevArgs.game != "":
		var with_game := Net.match_settings.duplicate()
		with_game["game"] = DevArgs.game
		with_game["map"] = Maps.default_id(DevArgs.game)
		Net.set_match_settings(with_game)
	if err == OK and DevArgs.rules != "":
		var s := Net.match_settings.duplicate()
		var kind := DevArgs.rules.get_slice(":", 0)
		var amount := float(DevArgs.rules.get_slice(":", 1))
		s.mode = kind if kind == "time" or kind in GunGame.RULES else "kills"
		if kind == "time":
			s.minutes = amount
		elif not kind in GunGame.RULES:
			s.kills = int(amount)
		Net.set_match_settings(s)
	if err == OK and not (DevArgs.allowed_weapons.is_empty() and not DevArgs.jetpack and DevArgs.lobby_size == 0 \
			and DevArgs.points_target == 0 and DevArgs.song == ""):
		var s := Net.match_settings.duplicate()   # tests: lobby settings, in one go
		if DevArgs.lobby_size > 0:
			s["max_players"] = DevArgs.lobby_size
		if not DevArgs.allowed_weapons.is_empty():
			s["weapons"] = DevArgs.allowed_weapons.duplicate()
		if DevArgs.jetpack:
			s["jetpack"] = true
		if DevArgs.points_target > 0:
			s["killcam_points"] = DevArgs.points_target
		if DevArgs.song != "":
			s["song"] = DevArgs.song
		Net.set_match_settings(s)
	if err == OK:
		for i in DevArgs.host_bots:   # tests: bots in an online lobby
			Net.add_bot(DevArgs.bot_level, DevArgs.bot_weapon, DevArgs.bot_mobility)
	return err


## Joins the lobby with this code, or at this address (see LobbyCode.parse; check its
## "error" first to tell the player what is wrong: a bad code returns ERR_INVALID_DATA).
## spectate: join to watch with a free camera (see Net.set_spectating).
func join_online(code_or_address: String, spectate: bool = false) -> Error:
	var where := LobbyCode.parse(code_or_address)
	if where.error != "":
		return ERR_INVALID_DATA
	mode = Mode.ONLINE
	return Net.join_direct(local_name(), local_character(), "%s:%d" % [where.host, where.port], local_weapon(), local_mobility(),
		spectate or DevArgs.spectate)


func leave_to_menu() -> void:
	Net.leave()
	goto_main_menu()


func quit_game() -> void:
	Net.leave()
	get_tree().quit()


# ---------------------------------------------------------------------------

func _on_joined_lobby() -> void:
	if not Net.in_match:
		goto_lobby()


func _on_join_failed(reason: String) -> void:
	if DevArgs.sync_log:
		print("JOIN_FAILED %s" % reason)
	goto_main_menu(reason)


func _on_session_ended(reason: String) -> void:
	if DevArgs.sync_log:
		print("SESSION_ENDED %s" % reason)
	goto_main_menu(reason)


func _on_match_started() -> void:
	get_tree().change_scene_to_file.call_deferred(ARENA)


## The match is over: slow motion and a fade to "MATCH OVER" (MatchEndFade), then the
## results (which play the best kills).
func _on_match_over(results: Array) -> void:
	_release_mouse()
	if Net.arena == null or not is_instance_valid(Net.arena):
		Net.in_match = false
		get_tree().change_scene_to_file.call_deferred(RESULTS)
		return
	var fade := MatchEndFade.new()
	Net.arena.add_child(fade)   # (goes with the arena when the results come up)
	fade.done.connect(func():
		Net.in_match = false   # (only now: until then nobody swaps loadouts in front of the fade)
		get_tree().change_scene_to_file.call_deferred(RESULTS))
	fade.play(results)


func _on_players_changed() -> void:
	# Dev/test: start as soon as enough players have joined. After a match the lobby
	# restarts on its own timer instead (so a change in the lobby does not cut it short).
	if DevArgs.autostart > 0 and Net.is_host() and not Net.in_match and Net.players.size() >= DevArgs.autostart \
			and Match.last_results.is_empty():
		print("[dev] autostart with %d players" % Net.players.size())
		Net.host_start_match(true)


func _run_dev_args() -> void:
	if DevArgs.bot >= 0:
		start_bot(DevArgs.bot, DevArgs.kill_target if DevArgs.kill_target > 0 else 10, "", DevArgs.bots, DevArgs.rules)
		if DevArgs.spectate:
			Net.set_spectating(true)   # watch the bots
	elif DevArgs.benchmark:
		start_benchmark()
	elif DevArgs.practice:
		start_practice()
	elif DevArgs.host:
		var err := host_online()
		if err != OK:
			push_error("Could not host: %s" % error_string(err))
		elif DevArgs.spectate:
			Net.set_spectating(true)
	elif DevArgs.join_address != "":
		var err := join_online(DevArgs.join_address)
		if err == ERR_INVALID_DATA:
			push_error("Could not join %s: %s" % [DevArgs.join_address, LobbyCode.parse(DevArgs.join_address).error])
		elif err != OK:
			push_error("Could not join: %s" % error_string(err))


func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
