extends Node
## Developer command-line options, used by tools/run_local and the automated tests.
## Pass them after a "--" on the Godot command line, for example:
##   godot --path . -- --host --name=Austin --autostart=2
##
## --host               Host a direct-IP lobby straight away.
## --join=CODE          Join a lobby straight away, by its lobby code or by address (ADDRESS may include :PORT).
## --port=PORT         Host only: port to listen on (default 24680).
## --name=NAME          Player name for this copy of the game.
## --autostart=N        Host only: start the match once N players are in the lobby.
## --character=ID      Play as this robot (needle, vanguard, kestrel, bulwark, rivet, specter, orbit, templar, or a
##                      Character Creator id "custom:n=Name|l=frog|t=human|h=goblin|hat=top_hat") without changing the saved choice.
## --color=N           Your colour in a free-for-all: a number in Net.PLAYER_COLORS (0 red, 1 blue, 2 green...).
## --switch-character  Online: pick the next robot each time you come back to the lobby after a match (tests).
## --weapon=ID          Take this gun (pistol, shotgun, rifle, railgun) without changing the saved choice.
## --bot-weapon=ID      Every bot takes this gun (instead of one at random).
## --allowed-weapons=A,B  Host / Vs Bots: only these weapons may be picked (one id: a single gun for everyone).
## --jetpack           Host / Practice / Vs Bots: everyone has the jetpack (the lobby setting; off by default).
## --lobby-size=N       Host: the lobby takes at most N players (2 to 16).
## --fake-version=vX.Y.Z Pretend this copy is that release (the version check when joining; tests).
## --ready-at=SEC       Lobby: say you are ready SEC seconds after the lobby opens (tests).
## --kick-at=SEC:NAME   Host: kick the player called NAME SEC seconds after the lobby opens (tests).
## --start-when-ready   Host: start the match as soon as everyone (at least 2) is ready (tests).
## --move-at=SEC:NAME   Host: move the player called NAME to the spectators SEC seconds after the lobby opens (tests).
## --play-at=SEC,SEC    Spectator: press Play at these seconds after the lobby opens (tests).
## --mobility=ID        Take this mobility tool (grapple) without changing the saved choice.
## --bot-mobility=ID    Every bot takes this mobility tool (instead of one at random).
## --movement=ID        Host / Practice / Vs Bots: the movement variant everyone plays with (b; see MovementTuning.VARIANTS).
## --switch-weapon      Online: pick the next gun each time you come back to the lobby after a match (tests).
## --swap-on-death      Pick the next weapon each time you die, as if pressing its number key (tests).
## --unlock-all        Nothing in the Character Creator is locked behind an achievement (see Achievements).
## --spectate          Watch instead of play: --join joins as a spectator; with --host or --bot, you spectate.
## --practice           Skip the menus and drop into the arena alone.
## --benchmark          Run the graphics benchmark (see Benchmark), print where the report went, and quit.
## --map=ID             Which map to play: construction_site, office, rail_yard, lost_temple, neon_arcade, castle, halcyon, testing_grounds, or a race map
##                      (rooftop_run, foundry, sky_ruins, summit_plunge: that makes it a race) (host, practice and bot).
##                      --map=random: a random map, picked as the match starts (from --map-pool, if given).
## --map-pool=ID,ID     The maps a random map may pick from (host, practice and bot; see LobbySettings).
## --song=NAME          Host: the lobby plays this song (a file name in game/audio/music/, without .mp3).
## --song-at=SEC:NAME   Host: pick NAME as the lobby song SEC seconds after the lobby opens (tests).
## --race               With --practice, --bot or --host and no --map: race on the first race map.
## --game=GAME          ffa or dm (Deathmatch: start unarmed, pick weapons up off the map), with --practice, --bot or --host.
## --autopilot          Your own racer runs the course like a bot would (race tests and screenshots).
## --bot-level=LEVEL    With --autopilot: run the course at this bot difficulty (default 3, Expert).
## --bot=LEVEL          Skip the menus and start a 1v1 against a bot (0 Easy, 1 Normal, 2 Hard, 3 Expert).
## --host-bots=N        With --host: the lobby starts with N bots (at --bot-level), run by the host.
## --bots=N             With --bot: play against N bots (1 to 4; up to 7 in the team modes) in a free-for-all (or team match) instead of one.
## --scripted-input     The local player moves on its own (for sync tests).
## --sync-log           Print position samples used by tests/check_sync.py.
## --sound-log          Print every sound effect as it plays ("SFX name", "SFX3D name"): tests/audio_test.sh.
## --quit-after=SECONDS Quit automatically after this many seconds.
## --net-sim=L,J,P     Simulate a bad connection: L ms latency, up to J ms extra jitter,
##                      P percent of movement packets lost (incoming, this copy only).
## --delay-respawn=MS  Client: apply another player's respawn MS milliseconds late, as if the message
##                      were held up on the way, so their first snapshot from the new life arrives first (tests).
## --scripted-fire     With --scripted-input: aim at the nearest opponent and shoot.
## --map-event=SEC     Start the map's events (Halcyon's low gravity) SEC seconds after start, as if a terminal
##                      had fired them (host, practice and bot matches; tests and screenshots).
## --eager-terminal    Bots go for a map terminal whenever one is ready and they have nobody to fight (tests;
##                      normally they only try now and then).
## --rules=kills:N | time:MINUTES | gungame | killcam | snd | ctf  Set the win condition or mode (Gun Game, Killcam and the team modes, Search and Destroy and Capture the Flag, also work with --bot).
## --kill-target=N      Host only: override the kill target for this match.
## --points=N           Host or --bot, Killcam mode: set the points to win (a lobby setting, so clients see it too).
## --time-limit=SECONDS Host only: override the match length (safety cap in tests).
## --auto-return       Leave the results screen after 2 seconds (lobby online, rematch vs a bot).
## --menu=PAGE          Open the main menu on this page: play, practice, bot, multiplayer, settings, profile, creator, achievements, card.
## --showcase=N         Start the main menu's character showcase on its Nth character (from 1; screenshots).
## --settings-tab=N     Open Settings on this tab (0 Controls, 1 Camera, 2 HUD, 3 Audio, 4 Graphics).
## --pause-page=PAGE    Open the pause menu on this page when it opens: loadout, settings (screenshots).
## --manual-respawn     Wait for a Jump or Fire press to respawn, as in a real game, even in a
##                      headless or scripted run (those otherwise ask as soon as the wait is over).
## --fall=SEC           Your player falls out of the arena SEC seconds after start (shows the death screen; screenshots).
## --save-killcam=N     On the results screen, save best kill #N as a video straight away, into the game's
##                      own data folder (user://killcams) rather than Videos (tests).
## --hud=STYLE          Use this HUD layout in both views: arcs or clean (screenshots).
## --hud-scale=X        HUD scale, 0.75 to 1.25 (screenshots).
## --third-person      Start in third-person view (not saved to settings).
## --speed=X            Game speed (0.25: quarter speed, for filming a move in slow motion; Practice and Vs Bots).
## --screenshot=SEC:PATH Save a screenshot SEC seconds after start (repeatable).
## --press=SEC:ACTION   Press an input action (e.g. toggle_camera) SEC seconds after start (repeatable).
## --hold=SEC:ACTION:DURATION  Hold an input action down for DURATION seconds, starting SEC seconds after start (repeatable).
## --from-start         Count the SEC of --hold from when your player is in a running match, not from launch (so a
##                      scripted move happens at the same moment after spawning online, however long joining took).
## --spawn=X,Y,Z,YAW[,PITCH]  Start the local player here (degrees), e.g. to look at the training yard.
## --game-clock        Count the SEC of the options below in game time instead of real time. With Godot's own
##                      --fixed-fps 60 (before the "--") a scripted run plays out the same however slowly it renders.
## --look=SEC:YAW,PITCH  Turn the local player's view by YAW and to PITCH (degrees) SEC seconds after start (repeatable).
## --window=X,Y,W,H     Window position and size, so several copies can sit side by side.

var host := false
var join_address := ""
var player_name := ""
var port := 0
var autostart := 0
var practice := false
var benchmark := false
var spectate := false
var unlock_all := false
var character := ""
var switch_character := false
var weapon := ""
var bot_weapon := ""
var allowed_weapons: Array = []   ## --allowed-weapons (see LobbySettings)
var jetpack := false              ## --jetpack (see LobbySettings.jetpack)
var lobby_size := 0               ## --lobby-size
var fake_version := ""            ## --fake-version
var ready_at := -1.0              ## --ready-at
var kick_at := -1.0               ## --kick-at (when)
var kick_name := ""               ## --kick-at (who)
var start_when_ready := false     ## --start-when-ready
var move_at := -1.0               ## --move-at (when)
var move_name := ""               ## --move-at (who)
var play_at: Array = []           ## --play-at
var mobility := ""
var bot_mobility := ""
var switch_weapon := false
var swap_on_death := false
var map := ""
var map_pool: Array = []   ## --map-pool (see LobbySettings.pool_for)
var song := ""             ## --song
var song_at := -1.0        ## --song-at (when)
var song_later := ""       ## --song-at (which)
var movement := ""         ## --movement (see MovementTuning.VARIANTS; "" keeps the menu's choice)
var race := false
var game := ""   ## --game=dm: a Deathmatch (on an arena map)
var autopilot := false
var bot_level := 3
var host_bots := 0
var bot := -1
var bots := 1
var scripted_input := false
var manual_respawn := false
var sync_log := false
var sound_log := false
var scripted_fire := false
var eager_terminal := false
var map_event_at := -1.0     # --map-event: seconds after start (-1 = never)
## With --scripted-input: also hook the nearest opponent now and then and flying-kick
## them, kick anyone close, and fire the rocket boots every few seconds (tests).
var scripted_kicks := false
var auto_return := false
var kill_target := 0
var points_target := 0
var rules := ""
var time_limit := 0.0
var quit_after := 0.0
var save_killcam := 0
var menu := ""
var showcase := 0
var pause_page := ""
var fall_at := -1.0          # --fall: seconds after start (-1 = never)
var window_rect := Rect2i()
var net_sim_latency := 0.0
var net_sim_jitter := 0.0
var net_sim_loss := 0.0
var delay_respawn := 0.0     # --delay-respawn: milliseconds
var screenshots: Array = []  # [seconds, path]
var presses: Array = []      # [seconds, action]
var holds: Array = []        # [start seconds, action, end seconds, is down]
var spawn: Array = []        # [Vector3 position, yaw, pitch] in radians, or empty
var looks: Array = []        # [seconds, yaw turn, pitch] in radians
var drives_keys := false     # --hold or --press was given: the player listens even if the mouse is not captured

var _start_ticks := 0
var _fixed_step := false     # --game-clock: count game time, so slow rendering does not shift the script
var _game_time := 0.0
var from_start := false     # --from-start
var _since_start := 0.0     # seconds your player has been in a running match


func _ready() -> void:
	_start_ticks = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		var key: String = arg
		var value := ""
		if "=" in arg:
			key = arg.get_slice("=", 0)
			value = arg.substr(key.length() + 1)
		match key:
			"--host": host = true
			"--join": join_address = value
			"--name": player_name = value
			"--port": port = int(value)
			"--autostart": autostart = int(value)
			"--practice": practice = true
			"--benchmark": benchmark = true
			"--spectate": spectate = true
			"--unlock-all": unlock_all = true
			"--character":
				if Characters.has(value):
					character = value
				else:
					push_warning("Unknown character: %s (characters: %s)" % [value, ", ".join(Characters.ids())])
			"--color": Settings.player_color = clampi(int(value), -1, 15)
			"--switch-character": switch_character = true
			"--weapon", "--bot-weapon":
				if WeaponData.has(value):
					if key == "--weapon":
						weapon = value
					else:
						bot_weapon = value
				else:
					push_warning("Unknown weapon: %s (weapons: %s)" % [value, ", ".join(WeaponData.IDS)])
			"--mobility", "--bot-mobility":
				value = Mobility.canonical(value)
				if Mobility.has(value):
					if key == "--mobility":
						mobility = value
					else:
						bot_mobility = value
				else:
					push_warning("Unknown mobility: %s (mobility: %s)" % [value, ", ".join(Mobility.IDS)])
			"--allowed-weapons":
				for w in value.split(",", false):
					if WeaponData.has(w):
						allowed_weapons.append(w)
					else:
						push_warning("Unknown weapon: %s (weapons: %s)" % [w, ", ".join(WeaponData.IDS)])
			"--lobby-size": lobby_size = int(value)
			"--fake-version": fake_version = value
			"--ready-at": ready_at = float(value)
			"--kick-at":
				kick_at = float(value.get_slice(":", 0))
				kick_name = value.substr(value.find(":") + 1)
			"--start-when-ready": start_when_ready = true
			"--move-at":
				move_at = float(value.get_slice(":", 0))
				move_name = value.substr(value.find(":") + 1)
			"--play-at":
				for t in value.split(",", false):
					play_at.append(float(t))
			"--jetpack": jetpack = true
			"--switch-weapon": switch_weapon = true
			"--swap-on-death": swap_on_death = true
			"--map":
				if Maps.has(value) or value == Maps.RANDOM:
					map = value
				else:
					push_warning("Unknown map: %s (maps: %s)" % [value, ", ".join(Maps.ids())])
			"--map-pool":
				for m in value.split(",", false):
					if Maps.has(m):
						map_pool.append(m)
					else:
						push_warning("Unknown map: %s (maps: %s)" % [m, ", ".join(Maps.ids())])
			"--song": song = value
			"--movement":
				if value in MovementTuning.VARIANTS:
					movement = value
				else:
					push_warning("Unknown movement variant: %s (variants: %s)" % [value, ", ".join(MovementTuning.VARIANTS)])
			"--song-at":
				song_at = float(value.get_slice(":", 0))
				song_later = value.substr(value.find(":") + 1)
			"--race": race = true
			"--game":
				if value in Maps.GAMES:
					game = value
				else:
					push_warning("Unknown game: %s (games: %s)" % [value, ", ".join(Maps.GAMES)])
			"--autopilot": autopilot = true
			"--bot-level": bot_level = clampi(int(value), 0, 3)
			"--host-bots": host_bots = clampi(int(value), 0, 15)
			"--bot": bot = clampi(int(value), 0, 3)
			"--bots": bots = clampi(int(value), 1, 7)   # (more than 4 only in the team modes: see Game.max_bots)
			"--scripted-input": scripted_input = true
			"--manual-respawn": manual_respawn = true
			"--sync-log": sync_log = true
			"--sound-log": sound_log = true
			"--scripted-fire": scripted_fire = true
			"--eager-terminal": eager_terminal = true
			"--map-event": map_event_at = float(value)
			"--scripted-kicks": scripted_kicks = true
			"--auto-return": auto_return = true
			"--menu": menu = value
			"--showcase": showcase = int(value)
			"--settings-tab": SettingsPanel.open_on_tab(int(value))
			"--pause-page": pause_page = value
			"--fall": fall_at = float(value)
			"--hud":
				if Settings.HUD_STYLES.has(value):
					Settings.hud_first_person = value
					Settings.hud_third_person = value
			"--hud-scale": Settings.hud.scale = HudConfig.valid("scale", float(value))
			"--kill-target": kill_target = int(value)
			"--points": points_target = int(value)
			"--rules": rules = value
			"--time-limit": time_limit = float(value)
			"--third-person": Settings.third_person = true
			"--quit-after": quit_after = float(value)
			"--save-killcam": save_killcam = int(value)
			"--net-sim":
				var q := value.split(",")
				net_sim_latency = float(q[0]) if q.size() > 0 else 0.0
				net_sim_jitter = float(q[1]) if q.size() > 1 else 0.0
				net_sim_loss = float(q[2]) if q.size() > 2 else 0.0
			"--delay-respawn": delay_respawn = maxf(float(value), 0.0)
			"--press":
				drives_keys = true
				presses.append([float(value.get_slice(":", 0)), value.substr(value.find(":") + 1)])
			"--hold":
				var h := value.split(":")
				if h.size() == 3:
					drives_keys = true
					holds.append([float(h[0]), h[1], float(h[0]) + float(h[2]), false])
			"--screenshot":
				screenshots.append([float(value.get_slice(":", 0)), value.substr(value.find(":") + 1)])
			"--game-clock": _fixed_step = true
			"--from-start": from_start = true
			"--speed": Cheats.time_scale = clampf(float(value), 0.05, 4.0)
			"--look":
				var l := value.get_slice(":", 1).split(",")
				if l.size() == 2:
					looks.append([float(value.get_slice(":", 0)), deg_to_rad(float(l[0])), deg_to_rad(float(l[1]))])
			"--spawn":
				var c := value.split(",")
				spawn = [Vector3(float(c[0]), float(c[1]), float(c[2])),
					deg_to_rad(float(c[3])) if c.size() > 3 else 0.0,
					deg_to_rad(float(c[4])) if c.size() > 4 else 0.0]
			"--window":
				var p := value.split(",")
				if p.size() == 4:
					window_rect = Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
			_: push_warning("Unknown dev argument: %s" % arg)
	if DisplayServer.get_name() == "headless":
		Engine.max_fps = 60  # several headless copies share the CPU in tests
	if window_rect.size != Vector2i.ZERO and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(window_rect.size)
		DisplayServer.window_set_position(window_rect.position)


func net_sim_enabled() -> bool:
	return net_sim_latency > 0.0 or net_sim_jitter > 0.0 or net_sim_loss > 0.0


func any() -> bool:
	return host or join_address != "" or practice or bot >= 0


func _elapsed() -> float:
	return _game_time if _fixed_step else (Time.get_ticks_msec() - _start_ticks) / 1000.0


## Held actions change on a physics step (before the players run theirs), so the
## step that reads them sees the key go down.
func _physics_process(delta: float) -> void:
	if from_start and Match.running and Net.arena and Net.arena.local_player:
		_since_start += delta
	var elapsed := _since_start if from_start else _elapsed()
	for hold in holds.duplicate():
		if not hold[3] and elapsed >= hold[0]:
			hold[3] = true
			Input.action_press(hold[1])
			print("[dev] holding: %s at %.2f" % [hold[1], elapsed])
		elif hold[3] and elapsed >= hold[2]:
			holds.erase(hold)
			Input.action_release(hold[1])


func _process(delta: float) -> void:
	_game_time += delta
	var elapsed := _elapsed()
	for press in presses.duplicate():
		if elapsed >= press[0]:
			presses.erase(press)
			for down in [true, false]:
				var ev := InputEventAction.new()
				ev.action = press[1]
				ev.pressed = down
				Input.parse_input_event(ev)
			print("[dev] pressed: %s" % press[1])
	if map_event_at >= 0.0 and elapsed >= map_event_at and Net.arena:
		map_event_at = -1.0
		for e in get_tree().get_nodes_in_group(MapEvent.GROUP):
			(e as MapEvent).host_start()
	if fall_at >= 0.0 and elapsed >= fall_at and Net.arena and Net.arena.local_player:
		fall_at = -1.0
		Net.arena.local_player.report_fell_once()
	for look in looks.duplicate():
		if elapsed >= look[0]:
			looks.erase(look)
			var me: Player = Net.arena.local_player if Net.arena else null
			if me:
				me.input.yaw += look[1]
				me.input.pitch = look[2]
	for shot in screenshots.duplicate():
		if elapsed >= shot[0]:
			screenshots.erase(shot)
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot[1])
			print("[dev] screenshot saved: %s at %.2f" % [shot[1], elapsed])
	if quit_after > 0.0 and elapsed >= quit_after:
		print("[dev] quit-after reached")
		quit_after = 0.0
		Net.leave()
		get_tree().quit()


## Tests: ask to respawn as soon as the wait is over (nobody is there to press a key),
## unless --manual-respawn.
func auto_respawn() -> bool:
	return (scripted_input or DisplayServer.get_name() == "headless") and not manual_respawn
