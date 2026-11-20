extends Node
## Multiplayer core: hosting, joining, the lobby player list, and the messages
## that run a match. One player hosts (peer id 1) and everyone else connects to them.
##
## The connection itself comes from a "transport". Today that is direct IP (ENet),
## used for LAN play and for running several copies on one PC. Steam slots in as a
## second transport later without changing anything else in this file.
##
## Gameplay messages are routed through this autoload (always at /root/Net) rather
## than through arena nodes, so a message that arrives while a peer is still loading
## the arena is safely ignored instead of erroring.

signal players_changed
signal joined_lobby                     # we are connected and registered
signal join_failed(reason: String)
signal session_ended(reason: String)    # host left, or we were refused or kicked
signal match_started
signal internet_changed                 # host only: internet_state / public_ip changed

const DEFAULT_PORT := 24680
const BOT_ID_BASE := 9001
const MAX_PLAYERS := 16
## Spectators do not take a player's place; this many can watch on top of a full lobby.
const MAX_SPECTATORS := 8
## One colour per player, all different (the first five are the originals). You get
## the first free one unless you picked one (see set_my_color).
const PLAYER_COLORS := [
	Color(0.95, 0.35, 0.25), Color(0.25, 0.65, 0.95), Color(0.40, 0.85, 0.35),
	Color(0.95, 0.80, 0.25), Color(0.75, 0.40, 0.95), Color(0.20, 0.90, 0.85),
	Color(1.00, 0.55, 0.75), Color(0.98, 0.58, 0.15), Color(0.60, 0.95, 0.20),
	Color(0.30, 0.35, 0.95), Color(0.92, 0.92, 0.95), Color(0.65, 0.25, 0.30),
	Color(0.55, 0.75, 0.55), Color(0.95, 0.95, 0.45), Color(0.45, 0.45, 0.50),
	Color(0.70, 0.50, 0.30),
]

const PLAYER_COLOR_NAMES := ["Red", "Blue", "Green", "Yellow", "Purple", "Cyan", "Pink", "Orange", "Lime", "Indigo",
	"White", "Maroon", "Sage", "Lemon", "Grey", "Brown"]

## peer id -> { "name": String, "color": int, "character": String (see Characters),
##   "weapon": String (see WeaponData), "mobility": String (see Mobility),
##   "card" and "icon": String (see CallingCard), "level": int (see PlayerLevel) },
## plus "bot": true and "difficulty" for computer players (ids from BOT_ID_BASE up), which the host simulates.
var players: Dictionary = {}
## Spectators: connected peers who watch with a free-flying camera instead of playing.
## peer id -> { "name": String }. They are never in `players`, so nothing that counts,
## spawns, scores or draws players ever sees them: nobody can see or hit a spectator.
var spectators: Dictionary = {}
var in_match := false
var is_online := false
var port := DEFAULT_PORT  ## the port we are hosting on

## Host only: whether friends can reach us over the internet. When we host, the game
## asks the router (UPnP) to open the port and tells us our public address.
## "" (not hosting), "checking", "open" (friends join at public_ip) or "failed".
var internet_state := ""
var public_ip := ""
var _upnp: UPNP = null        # the router we opened the port on, to close it again
var _upnp_thread: Thread = null

## The game and win condition chosen by the host in the lobby.
## game: "ffa" (free-for-all, a 1v1 with two players) or "race" (see Maps and Race).
## mode: "kills" (first to `kills`) or "time" (most kills after `minutes`); free-for-all only.
## race_minutes: a race's time limit.
## map: which map to play (an id from Maps; it must be one for the game).
## powerups: Deathmatch only, whether the map's power-ups (ItemPickup) are out.
## Plus the lobby settings (see LobbySettings), such as which weapons are allowed.
var match_settings := LobbySettings.clean({"game": "ffa", "mode": "kills", "kills": 15, "minutes": 8, "race_minutes": 10, "map": Maps.default_id(), "powerups": true})

## Each player's ping to the host in ms (peer id -> ms), measured by the host from its
## ENet links and sent to everyone every PING_GAP seconds (the Tab scoreboard shows it).
var pings: Dictionary = {}
const PING_GAP := 2.0
var _ping_wait := 0.0

## The arena currently running, if any. It registers itself here.
var arena: Node = null

var _local_name := "Player"
var _local_character := Characters.default_id()
var _local_weapon := WeaponData.default_id()
var _local_mobility := Mobility.default_id()
var _join_spectating := false   # the join under way is to watch, not to play


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_setup_version_check()
	(func(): Match.player_died.connect(_on_player_died)).call_deferred()   # Match is the next autoload
	(func(): Achievements.progressed.connect(_on_progress)).call_deferred()


static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0


func is_host() -> bool:
	return multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id()


func host_id() -> int:
	return 1


# ---------------------------------------------------------------------------
# Starting and stopping sessions

## Play alone (bot mode and practice). Uses the offline peer, so the same code
## paths run with this player as "host".
func start_offline(player_name: String, character: String, weapon: String = "", mobility: String = "") -> void:
	leave()
	_local_name = player_name
	_local_character = Characters.valid(character)
	_local_weapon = WeaponData.valid(weapon)
	_local_mobility = Mobility.valid(mobility)
	players = {1: {"name": player_name, "color": _wanted_color(), "character": _local_character, "weapon": LobbySettings.fit_weapon(_local_weapon), "mobility": LobbySettings.fit_mobility(_local_mobility)}}
	_wear(1, Settings.calling_card, Settings.icon)
	players[1]["level"] = my_level()
	is_online = false
	players_changed.emit()


func host_direct(player_name: String, character: String, listen_port: int = DEFAULT_PORT, weapon: String = "", mobility: String = "") -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(listen_port, MAX_PLAYERS - 1 + MAX_SPECTATORS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_local_name = player_name
	_local_character = Characters.valid(character)
	_local_weapon = WeaponData.valid(weapon)
	_local_mobility = Mobility.valid(mobility)
	players = {1: {"name": player_name, "color": _wanted_color(), "character": _local_character, "weapon": LobbySettings.fit_weapon(_local_weapon), "mobility": LobbySettings.fit_mobility(_local_mobility)}}
	_wear(1, Settings.calling_card, Settings.icon)
	players[1]["level"] = my_level()
	is_online = true
	players_changed.emit()
	joined_lobby.emit()
	port = listen_port
	print("[net] hosting on port %d" % port)
	_open_router_port()
	return OK


## spectate: join to watch (see set_spectating) rather than to play.
func join_direct(player_name: String, character: String, address: String, weapon: String = "", mobility: String = "", spectate: bool = false) -> Error:
	leave()
	var join_port := DEFAULT_PORT
	if ":" in address:
		join_port = int(address.get_slice(":", 1))
		address = address.get_slice(":", 0)
	if address.strip_edges() == "":
		address = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, join_port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_local_name = player_name
	_local_character = Characters.valid(character)
	_local_weapon = WeaponData.valid(weapon)
	_local_mobility = Mobility.valid(mobility)
	_join_spectating = spectate
	is_online = true
	print("[net] joining %s:%d%s" % [address, join_port, " to spectate" if spectate else ""])
	return OK


func leave() -> void:
	_close_router_port()
	in_match = false
	is_online = false
	players.clear()
	spectators.clear()
	pings.clear()
	moved_by_host = false
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


# ---------------------------------------------------------------------------
# Internet hosting: ask the router to forward our port (UPnP), on a thread because
# finding the router takes a second or two.

func _open_router_port() -> void:
	internet_state = "checking"
	public_ip = ""
	internet_changed.emit()
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_work.bind(port))


func _upnp_work(open_port: int) -> void:
	var upnp := UPNP.new()
	var ip := ""
	if upnp.discover(2000, 2) == UPNP.UPNP_RESULT_SUCCESS and upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		if upnp.add_port_mapping(open_port, open_port, "Jumpy Shooty", "UDP") == UPNP.UPNP_RESULT_SUCCESS:
			ip = upnp.query_external_address()
	_upnp_done.call_deferred(upnp, ip, open_port)


func _upnp_done(upnp: UPNP, ip: String, opened_port: int) -> void:
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if internet_state != "checking" or opened_port != port:
		if ip != "":
			upnp.delete_port_mapping(opened_port, "UDP")   # we stopped hosting meanwhile
		return
	# A private address here means the internet provider shares one public address
	# between many homes (carrier-grade NAT): friends cannot reach us that way.
	if ip == "" or _is_private(ip):
		internet_state = "failed"
		if ip != "":
			upnp.delete_port_mapping(opened_port, "UDP")
		print("[net] could not open port %d on the router" % opened_port)
	else:
		_upnp = upnp
		internet_state = "open"
		public_ip = ip
		print("[net] router port %d open; public address %s" % [opened_port, ip])
	print("[net] lobby code %s (%s:%d)" % [lobby_code(), join_ip(), port])
	internet_changed.emit()


func _close_router_port() -> void:
	if _upnp:
		_upnp.delete_port_mapping(port, "UDP")
		_upnp = null
	internet_state = ""
	public_ip = ""


func _exit_tree() -> void:
	_drop_version_check()
	_close_router_port()
	if _upnp_thread:
		_upnp_thread.wait_to_finish()


## The lobby code friends type to join us (see LobbyCode): our public address once the
## router is open, else our address on the local network. "" when not hosting, or
## while we are still asking the router.
func lobby_code() -> String:
	if not is_online or not is_host() or internet_state == "checking":
		return ""
	return LobbyCode.encode(join_ip(), port)


## The address the lobby code stands for (shown too, for LAN and development use).
func join_ip() -> String:
	return public_ip if internet_state == "open" else lan_ip()


## Our address on the local network (127.0.0.1 if we cannot find one).
static func lan_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1"


static func _is_private(ip: String) -> bool:
	var p := ip.split(".")
	if p.size() != 4:
		return true
	var a := int(p[0])
	var b := int(p[1])
	return a == 10 or a == 127 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31) \
		or (a == 100 and b >= 64 and b <= 127)


# ---------------------------------------------------------------------------
# Connection events

func _on_connected_to_server() -> void:
	_tune_link(1)
	_register.rpc_id(1, _local_name, _local_character, _local_weapon, _local_mobility, _join_spectating, Settings.player_color)
	_choose_card.rpc_id(1, Settings.calling_card, Settings.icon)   # (after _register: they arrive in order)
	_choose_level.rpc_id(1, my_level())


func _on_connection_failed() -> void:
	leave()
	join_failed.emit("Could not reach the host.")


# ---------------------------------------------------------------------------
# Version check. Before a copy joins, the two say which release they are, in the
# multiplayer API's authentication step: plain bytes, not RPCs, so it works between
# any two versions (RPCs only line up between copies of the same version). The
# joining copy compares: a different release leaves and says which version each side
# is on (and who should update). A build that is not a release (the editor, a local
# export, the tests) says "" and is let through.

const HELLO := "jumpy-shooty|"   ## then the version; the format must never change

var _version_refusal := ""   # the joiner: why it is leaving (shown instead of "could not reach")


func _setup_version_check() -> void:
	var api := multiplayer as SceneMultiplayer
	if api == null:
		return
	api.auth_timeout = 5.0
	api.auth_callback = _on_auth
	api.peer_authenticating.connect(_say_hello)


## A link is starting: tell the other side which release this copy is.
func _say_hello(id: int) -> void:
	(multiplayer as SceneMultiplayer).send_auth(id, (HELLO + Game.version()).to_utf8_buffer())


## The multiplayer API outlives this node: let go of its callbacks (else they keep this
## script loaded at exit).
func _drop_version_check() -> void:
	var api := multiplayer as SceneMultiplayer
	if api == null:
		return
	api.auth_callback = Callable()
	if api.peer_authenticating.is_connected(_say_hello):
		api.peer_authenticating.disconnect(_say_hello)


## The other side's hello: the host lets the joiner in (the joiner decides whether
## the versions go together); the joiner checks the host's version.
func _on_auth(id: int, data: PackedByteArray) -> void:
	var api := multiplayer as SceneMultiplayer
	var text := data.get_string_from_utf8()
	var theirs := text.trim_prefix(HELLO) if text.begins_with(HELLO) else ""
	if is_host():
		if DevArgs.sync_log:
			print("VERSION_HELLO %d %s" % [id, theirs if theirs != "" else "dev"])
		api.complete_auth(id)
		return
	var why := Game.version_mismatch_text(theirs, Game.version())
	if why == "":
		api.complete_auth(id)
		return
	print("[net] the host is on %s, this copy on %s: not joining" % [theirs, Game.version()])
	if DevArgs.sync_log:
		print("VERSION_MISMATCH %s %s" % [theirs, Game.version()])
	_version_refusal = why
	_leave_for_version.call_deferred()


## This copy is a client whose link to the host is up (past the version check), so
## messages to the host get there.
func connected_to_host() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not is_host() and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and 1 in multiplayer.get_peers()


func _leave_for_version() -> void:
	var why := _version_refusal
	_version_refusal = ""
	leave()
	join_failed.emit(why)


func _on_server_disconnected() -> void:
	print("[net] host disconnected")
	leave()
	session_ended.emit("The host left, so the match ended.")


func _on_peer_connected(id: int) -> void:
	# The new peer registers itself; see _register. Here the host only tunes the link.
	if is_host():
		_tune_link(id)


## ENet normally starts dropping unreliable packets when ping wobbles ("throttling").
## For a game of up to 16 players that bandwidth saving isn't needed, and the dropped movement
## updates make players stutter, so we switch throttling off.
func _tune_link(id: int) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		var link: ENetPacketPeer = peer.get_peer(id)
		if link:
			link.throttle_configure(5000, ENetPacketPeer.PACKET_THROTTLE_SCALE, 0)


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	var was_spectating := spectators.erase(id)
	if players.erase(id) or was_spectating:
		print("[net] %d left" % id)
		_broadcast_players.call_deferred()


func _broadcast_players() -> void:
	if is_host() and is_online:
		_sync_spectators.rpc(spectators)
		_sync_players.rpc(players)


# ---------------------------------------------------------------------------
# Lobby

@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String, character: String, weapon: String, mobility: String = "", spectate: bool = false, color: int = -1) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if spectate and spectators.size() >= MAX_SPECTATORS:
		_refused.rpc_id(id, "The lobby has no room for more spectators.")
		_drop_peer_later(id)
		return
	if not spectate and players.size() >= LobbySettings.max_players():
		_refused.rpc_id(id, "The lobby is full (%d players)." % LobbySettings.max_players())
		_drop_peer_later(id)
		return
	if spectate:
		host_add_spectator(id, player_name)
	else:
		host_add_player(id, player_name, character, weapon, mobility, color)
	_sync_settings.rpc_id(id, match_settings)
	_sync_spectators.rpc(spectators)
	_sync_players.rpc(players)
	if in_match:
		_late_join.rpc_id(id)


## Host: put a player who has just connected in the list. Their weapon must be one the
## lobby allows (see LobbySettings); if not, they get one that is. color: the colour
## they would like (see set_my_color), theirs if nobody has it.
func host_add_player(id: int, player_name: String, character: String, weapon: String, mobility: String = "", color: int = -1) -> void:
	players[id] = {"name": _unique_name(player_name.strip_edges().left(20)), "color": _free_color(),
		"character": Characters.valid(character), "weapon": LobbySettings.fit_weapon(WeaponData.valid(weapon)), "mobility": LobbySettings.fit_mobility(Mobility.valid(mobility))}
	_take_color(id, color)
	if in_match and Teams.active():
		players[id]["team"] = Teams.smaller_team()   # joining a team match: onto the smaller team
	print("[net] %d joined as %s (%s, %s)" % [id, players[id].name, players[id].character, players[id].weapon])


@rpc("authority", "call_local", "reliable")
func _sync_players(new_players: Dictionary) -> void:
	var was_registered := is_registered()
	players = new_players
	_log_loadouts()
	players_changed.emit()
	if not was_registered and is_registered() and not is_host():
		joined_lobby.emit()


## Who is watching. Always sent just before _sync_players (same channel, so in order).
@rpc("authority", "call_local", "reliable")
func _sync_spectators(new_spectators: Dictionary) -> void:
	var was_registered := is_registered()
	spectators = new_spectators
	if not was_registered and is_registered() and not is_host():
		joined_lobby.emit()   # joined to watch


## We are in the lobby or match, as a player or a spectator.
func is_registered() -> bool:
	return players.has(my_id()) or spectators.has(my_id())


# ---------------------------------------------------------------------------
# Spectating: watch with a free-flying camera (see SpectatorCamera). A spectator has no
# robot anywhere, is not on the scoreboard and does not count toward a full lobby.

func is_spectator(id: int) -> bool:
	return spectators.has(id)


## This copy of the game is watching rather than playing.
func spectating() -> bool:
	return spectators.has(my_id())


## Spectators, sorted by id (for lists).
func spectator_ids() -> Array:
	var ids := spectators.keys()
	ids.sort()
	return ids


func spectator_name(id: int) -> String:
	return str(spectators[id].get("name", "?")) if spectators.has(id) else "?"


## Start (on) or stop (off) watching, in the lobby or mid-match. Stopping puts you back
## in as a player with the loadout you last picked; in a match you drop straight in.
## Nothing happens if there is no room (16 players, or MAX_SPECTATORS watching).
func set_spectating(on: bool) -> void:
	if is_host():
		host_set_spectating(my_id(), on, _local_character, _local_weapon, _local_mobility)
	else:
		_ask_spectate.rpc_id(1, on, _local_character, _local_weapon, _local_mobility)


@rpc("any_peer", "call_remote", "reliable")
func _ask_spectate(on: bool, character: String, weapon: String, mobility: String) -> void:
	if is_host():
		host_set_spectating(multiplayer.get_remote_sender_id(), on, character, weapon, mobility)


## Host: move a person between the players and the spectators. Bots never spectate.
## Returns whether anything changed.
func host_set_spectating(id: int, on: bool, character: String = "", weapon: String = "", mobility: String = "") -> bool:
	if on:
		if not players.has(id) or is_bot(id) or spectators.size() >= MAX_SPECTATORS:
			return false
		var name := str(players[id].name)
		players.erase(id)
		spectators[id] = {"name": name}
		print("[net] %d (%s) is spectating" % [id, name])
	else:
		if not spectators.has(id) or not player_slot_free():   # no room in the lobby size
			if DevArgs.sync_log and spectators.has(id):
				print("SPECTATE_FULL %d" % id)
			return false
		var name := str(spectators[id].name)
		spectators.erase(id)
		host_add_player(id, name, character, weapon, mobility)
		print("[net] %d (%s) stopped spectating" % [id, name])
	if DevArgs.sync_log:
		print("SPECTATE %d %s" % [id, "on" if on else "off"])
	if is_online:
		_sync_spectators.rpc(spectators)
	_players_updated()
	return true


## Host: put someone who has just connected to watch in the spectator list.
func host_add_spectator(id: int, player_name: String) -> void:
	var wanted := player_name.strip_edges().left(20)
	spectators[id] = {"name": _unique_name(wanted if wanted != "" else "Spectator")}
	print("[net] %d joined to spectate as %s" % [id, spectators[id].name])


## Pick the robot you play as. Works in the lobby; the host tells everyone. A change
## made once the match has started is ignored (it applies from the next lobby on).
func set_my_character(character: String) -> void:
	_local_character = Characters.valid(character)
	if is_host():
		_apply_character(my_id(), _local_character)
	else:
		_choose_character.rpc_id(1, _local_character)


## Call when the lobby opens: if a pick was ignored because the match had just
## started, send it again now.
func confirm_my_character() -> void:
	if players.has(my_id()) and player_character(my_id()) != _local_character:
		set_my_character(_local_character)
	if players.has(my_id()) and player_loadout_weapon(my_id()) != LobbySettings.fit_weapon(_local_weapon):
		set_my_weapon(_local_weapon)   # the host gives you an allowed one if this one is not
	if players.has(my_id()) and player_loadout_mobility(my_id()) != LobbySettings.fit_mobility(_local_mobility):
		set_my_mobility(_local_mobility)
	if players.has(my_id()) and (player_card(my_id()) != Settings.calling_card or player_icon(my_id()) != Settings.icon):
		set_my_card(Settings.calling_card, Settings.icon)
	if players.has(my_id()) and Settings.player_color >= 0 and color_index(my_id()) != Settings.player_color and not color_taken(Settings.player_color):
		set_my_color(Settings.player_color)   # the colour you like is free again


## Pause menu "Loadout": change robot and/or weapon mid-match. It takes effect when
## you next respawn: sent now if you are dead (or racing, where nobody dies), else
## as soon as you die (see _on_player_died). "" keeps the weapon (or mobility) as it is.
func set_loadout(character: String, weapon: String, mobility: String = "") -> void:
	_local_character = Characters.valid(character)
	if weapon != "":
		_local_weapon = WeaponData.valid(weapon)
	if mobility != "":
		_local_mobility = Mobility.valid(mobility)
	if not in_match or not Match.is_alive(my_id()) or Race.active:
		confirm_my_character()


## The robot and weapon you will have after your next respawn.
func pending_character() -> String:
	return _local_character


func pending_weapon() -> String:
	return LobbySettings.fit_weapon(_local_weapon)


func pending_mobility() -> String:
	return LobbySettings.fit_mobility(_local_mobility)


func _on_player_died(victim: int, _killer: int) -> void:
	if victim == my_id():
		confirm_my_character()   # a loadout picked while alive applies now, for the respawn


@rpc("any_peer", "call_remote", "reliable")
func _choose_character(character: String) -> void:
	if is_host():
		_apply_character(multiplayer.get_remote_sender_id(), character)


func _apply_character(id: int, character: String) -> void:
	if not players.has(id) or players[id].get("character", "") == Characters.valid(character):
		return
	if in_match and not Race.active and (Match.is_alive(id) or not Match.running):
		return   # mid-fight you can only change robot while waiting to respawn
	players[id]["character"] = Characters.valid(character)
	print("[net] %d picked %s" % [id, players[id].character])
	if is_online:
		_sync_players.rpc(players)
	else:
		players_changed.emit()


## Show this calling card and icon with your name (ids from CallingCard). Any time.
func set_my_card(card: String, icon: String) -> void:
	if is_host():
		_apply_card(my_id(), card, icon)
	else:
		_choose_card.rpc_id(1, card, icon)


@rpc("any_peer", "call_remote", "reliable")
func _choose_card(card: String, icon: String) -> void:
	if is_host():
		_apply_card(multiplayer.get_remote_sender_id(), card, icon)


func _apply_card(id: int, card: String, icon: String) -> void:
	if not _wear(id, card, icon):
		return
	print("[net] %d wears %s / %s" % [id, players[id].card, players[id].icon])
	if is_online:
		_sync_players.rpc(players)
	else:
		players_changed.emit()


## Put a card and an icon on a player: real ones only (anything made up becomes the
## default). Returns whether anything changed.
func _wear(id: int, card: String, icon: String) -> bool:
	card = CallingCard.valid_card(card)
	icon = CallingCard.valid_icon(icon)
	if not players.has(id) or (players[id].get("card", "") == card and players[id].get("icon", "") == icon):
		return false
	players[id]["card"] = card
	players[id]["icon"] = icon
	return true


## Your level (from your experience: see PlayerLevel).
static func my_level() -> int:
	return PlayerLevel.of(Achievements.stat("xp")).level


## A player's level, or 0 if they have none to show (a bot, or an older copy).
func player_level(id: int) -> int:
	return int(players[id].get("level", 0)) if players.has(id) else 0


## Experience came in (a kill, a match's end, a sync from your account): tell the
## lobby if it took you up a level. Not mid-match (the lobby asks again when it opens).
func send_my_level() -> void:
	_on_progress()


func _on_progress() -> void:
	var id := my_id()
	if in_match or not players.has(id) or player_level(id) == my_level():
		return
	if is_host():
		_apply_level(id, my_level())
	else:
		_choose_level.rpc_id(1, my_level())


@rpc("any_peer", "call_remote", "reliable")
func _choose_level(level: int) -> void:
	if is_host():
		_apply_level(multiplayer.get_remote_sender_id(), level)


func _apply_level(id: int, level: int) -> void:
	level = clampi(level, 1, 9999)
	if not players.has(id) or player_level(id) == level:
		return
	players[id]["level"] = level
	if is_online:
		_sync_players.rpc(players)
	else:
		players_changed.emit()


## A player's calling card and icon (the defaults for anyone who has not said).
func player_card(id: int) -> String:
	return CallingCard.valid_card(str(players[id].get("card", ""))) if players.has(id) else CallingCard.DEFAULT_CARD


func player_icon(id: int) -> String:
	return CallingCard.valid_icon(str(players[id].get("icon", ""))) if players.has(id) else CallingCard.DEFAULT_ICON


## Pick your colour (a number in PLAYER_COLORS): your robot's trim and visor, your
## name and your stripes in a free-for-all (a team mode dresses you in your team's).
## Works in the lobby, for a colour no other player has; a bot hands its colour over.
func set_my_color(index: int) -> void:
	if is_host():
		_apply_color(my_id(), index)
	else:
		_choose_color.rpc_id(1, index)


@rpc("any_peer", "call_remote", "reliable")
func _choose_color(index: int) -> void:
	if is_host():
		_apply_color(multiplayer.get_remote_sender_id(), index)


func _apply_color(id: int, index: int) -> void:
	if in_match or not _take_color(id, index):
		return   # (in a match everything is already drawn in the colour you have)
	print("[net] %d took colour %d" % [id, index])
	if is_online:
		_sync_players.rpc(players)
	else:
		players_changed.emit()


## Host: give a player the colour they asked for, if no other player has it. A bot
## that has it takes theirs instead, but not mid-match, when it is already drawn.
func _take_color(id: int, index: int) -> bool:
	if not players.has(id) or index < 0 or index >= PLAYER_COLORS.size() or players[id].color == index:
		return false
	for other in players:
		if other != id and players[other].color == index:
			if not is_bot(other) or in_match:
				return false
			players[other]["color"] = players[id].color
	players[id]["color"] = index
	return true


## The number of a player's colour in PLAYER_COLORS (-1: no such player).
func color_index(id: int) -> int:
	return int(players[id].color) if players.has(id) else -1


## Whether another player (not a bot) already has this colour.
func color_taken(index: int) -> bool:
	for id in players:
		if id != my_id() and players[id].color == index and not is_bot(id):
			return true
	return false


## The colour you chose in the menus (Settings.player_color), or the first one.
func _wanted_color() -> int:
	return Settings.player_color if Settings.player_color >= 0 and Settings.player_color < PLAYER_COLORS.size() else 0


## The colour the menus show you in before there is a lobby.
func menu_color() -> Color:
	return PLAYER_COLORS[_wanted_color()]


## Pick the weapon you take into the match (an id from WeaponData). Works in the lobby,
## and during a fight while you are dead (you come back with it). A pick made while
## you are alive is ignored, and confirm_my_character() sends it again in the next lobby.
func set_my_weapon(weapon: String) -> void:
	_local_weapon = WeaponData.valid(weapon)
	if is_host():
		_apply_weapon(my_id(), _local_weapon)
	else:
		_choose_weapon.rpc_id(1, _local_weapon)


@rpc("any_peer", "call_remote", "reliable")
func _choose_weapon(weapon: String) -> void:
	if is_host():
		_apply_weapon(multiplayer.get_remote_sender_id(), weapon)


func _apply_weapon(id: int, weapon: String) -> void:
	weapon = LobbySettings.fit_weapon(WeaponData.valid(weapon))   # only what the lobby allows
	if not players.has(id) or players[id].get("weapon", "") == weapon:
		return
	if str(players[id].get("weapon", "")) in WeaponData.HIDDEN:
		return   # the Golden Gun's holder keeps it until the host passes it on (see GoldenGun)
	if in_match and (GunGame.active() or KillcamMode.active()):
		return   # Gun Game hands out the weapons; Killcam is snipers only
	if in_match and (Match.is_alive(id) or Race.active or not Match.running):
		return   # mid-fight you can only swap while waiting to respawn
	players[id]["weapon"] = weapon
	print("[net] %d took the %s" % [id, players[id].weapon])
	if is_online:
		_sync_players.rpc(players)
	else:
		players_changed.emit()


## Pick the mobility tool (an id from Mobility): the grapple or blink.
## Same rules as the weapon: in the lobby, or during a fight while you are dead.
func set_my_mobility(mobility: String) -> void:
	_local_mobility = Mobility.valid(mobility)
	if is_host():
		_apply_mobility(my_id(), _local_mobility)
	else:
		_choose_mobility.rpc_id(1, _local_mobility)


@rpc("any_peer", "call_remote", "reliable")
func _choose_mobility(mobility: String) -> void:
	if is_host():
		_apply_mobility(multiplayer.get_remote_sender_id(), mobility)


func _apply_mobility(id: int, mobility: String) -> void:
	mobility = LobbySettings.fit_mobility(Mobility.valid(mobility))   # only what the lobby allows
	if not players.has(id) or players[id].get("mobility", "") == mobility:
		return
	if in_match and (Match.is_alive(id) or Race.active or not Match.running):
		return   # mid-fight you can only swap while waiting to respawn
	players[id]["mobility"] = mobility
	print("[net] %d took the %s" % [id, players[id].mobility])
	if is_online:
		_sync_players.rpc(players)
	else:
		players_changed.emit()


## Host only: give a player a weapon now, alive or not (Gun Game), and tell everyone.
func host_set_weapon(id: int, weapon: String) -> void:
	if not is_host() or not players.has(id) or players[id].get("weapon", "") == WeaponData.valid(weapon):
		return
	players[id]["weapon"] = WeaponData.valid(weapon)
	if is_online:
		_sync_players.rpc(players)
	else:
		players_changed.emit()


## Host only: change the mode, map, win condition or lobby settings and tell everyone.
func set_match_settings(settings: Dictionary) -> void:
	if not is_host():
		return
	_sync_settings.rpc(settings)


@rpc("authority", "call_local", "reliable")
func _sync_settings(settings: Dictionary) -> void:
	match_settings = settings
	var game := Maps.valid_game(str(match_settings.get("game", "")))
	var map := str(match_settings.get("map", ""))
	if Maps.has(map) and not map.begins_with("res://") and not Maps.fits(map, game):
		map = ""   # a map for another game: race maps only race, arenas only fight
	if not Maps.has(map):
		match_settings["map"] = Maps.default_id(game)
	map = str(match_settings.map)
	match_settings["game"] = game if game in Maps.games_of(map) else Maps.game_of(map)
	match_settings = LobbySettings.clean(match_settings)
	if DevArgs.sync_log:
		print("LOBBY_SETTINGS %d weapons=%s" % [my_id(), ",".join(LobbySettings.allowed_weapons())])
		print("LOBBY_MOBILITY %d mobility=%s" % [my_id(), ",".join(LobbySettings.allowed_mobility())])
		print("LOBBY_MAP %d map=%s random=%s pool=%s song=%s" % [my_id(), map_id(), match_settings.random_map,
			",".join(LobbySettings.map_pool()), match_settings.song])
		print("LOBBY_MOVEMENT %d movement=%s" % [my_id(), LobbySettings.movement()])
	if is_host() and not in_match:
		host_fit_loadouts()   # weapons no longer allowed are swapped (everyone is told)
	elif players.has(my_id()) and not in_match:
		confirm_my_character()   # a weapon allowed again: ask for the one you picked
	players_changed.emit()  # lobby screens refresh on this


## Host: everyone's weapon and mobility tool are ones the lobby allows (see
## LobbySettings); a player with one that is not gets the first that is. Tells everyone if anything changed.
func host_fit_loadouts() -> void:
	if not is_host():
		return
	var changed := false
	for id in players:
		# Your own pick is known here, so you get it back once it is allowed again.
		if str(players[id].get("weapon", "")) in WeaponData.HIDDEN:
			continue   # the Golden Gun's holder keeps it (see GoldenGun)
		var wanted := _local_weapon if id == my_id() else str(players[id].get("weapon", ""))
		var w := LobbySettings.fit_weapon(WeaponData.valid(wanted))
		if players[id].get("weapon", "") != w:
			players[id]["weapon"] = w
			changed = true
		var wanted_mobility := _local_mobility if id == my_id() else str(players[id].get("mobility", ""))
		var m := LobbySettings.fit_mobility(Mobility.valid(wanted_mobility))
		if players[id].get("mobility", "") != m:
			players[id]["mobility"] = m
			changed = true
	if changed:
		_players_updated()


## --sync-log: the weapon everyone has on record.
func _log_loadouts() -> void:
	if DevArgs.sync_log:
		var ids := players.keys()
		ids.sort()
		print("LOADOUTS %d %s" % [my_id(), " ".join(ids.map(func(i): return "%d:%s" % [i, players[i].get("weapon", "")]))])
		print("MOBILITY_LOADOUTS %d %s" % [my_id(), " ".join(ids.map(func(i): return "%d:%s" % [i, players[i].get("mobility", "")]))])


@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
	leave()
	session_ended.emit(reason)


## Host: cut a peer off a moment after telling it why (so the message gets there), in
## case it does not leave by itself.
func _drop_peer_later(id: int) -> void:
	get_tree().create_timer(1.0).timeout.connect(func():
		var peer := multiplayer.multiplayer_peer
		if is_host() and peer is ENetMultiplayerPeer and (peer as ENetMultiplayerPeer).get_peer(id):
			(peer as ENetMultiplayerPeer).disconnect_peer(id))


# ---------------------------------------------------------------------------
# Kick and ready (online lobby)

## Host: remove a player from the lobby (not mid-match). They are told and sent back to
## the main menu.
## Host: move another player to the spectators (in the lobby, not mid-match). They are
## told, and come back with Play (set_spectating) when the lobby has room for them.
func host_move_to_spectators(id: int) -> bool:
	if not is_host() or not is_online or in_match or id == host_id() or is_bot(id) or not players.has(id):
		return false
	if not host_set_spectating(id, true):
		return false
	if DevArgs.sync_log:
		print("MOVED_TO_SPECTATORS %d" % id)
	_moved_by_host.rpc_id(id)
	return true


## This copy was moved to the spectators by the host (the lobby says so until you play again).
var moved_by_host := false


@rpc("authority", "call_remote", "reliable")
func _moved_by_host() -> void:
	moved_by_host = true
	if DevArgs.sync_log:
		print("MOVED_BY_HOST")
	players_changed.emit()


## Room for one more player in the lobby (a spectator can come back to play).
func player_slot_free() -> bool:
	return players.size() < LobbySettings.max_players()


func host_kick(id: int) -> void:
	if not is_host() or not is_online or in_match or id == host_id() or not players.has(id) or is_bot(id):
		return
	print("[net] kicked %d (%s)" % [id, player_name(id)])
	if DevArgs.sync_log:
		print("KICKED %d" % id)
	players.erase(id)
	_refused.rpc_id(id, "The host removed you from the lobby.")
	_drop_peer_later(id)
	_players_updated()


## Whether a player has said they are ready in the lobby. The host is ready when it
## presses Start; bots are always ready.
func is_ready(id: int) -> bool:
	return id == host_id() or is_bot(id) or bool(players[id].get("ready", false)) if players.has(id) else false


## The players the host is still waiting for (not ready yet).
func not_ready() -> Array:
	var ids := players.keys().filter(func(i): return not is_ready(i))
	ids.sort()
	return ids


## Everyone is ready (the host can start).
func all_ready() -> bool:
	return not_ready().is_empty()


## Say you are ready (or not) in the lobby; the host tells everyone.
func set_my_ready(on: bool) -> void:
	if is_host():
		_apply_ready(my_id(), on)
	else:
		_choose_ready.rpc_id(1, on)


@rpc("any_peer", "call_remote", "reliable")
func _choose_ready(on: bool) -> void:
	if is_host():
		_apply_ready(multiplayer.get_remote_sender_id(), on)


func _apply_ready(id: int, on: bool) -> void:
	if not players.has(id) or in_match or bool(players[id].get("ready", false)) == on:
		return
	players[id]["ready"] = on
	if DevArgs.sync_log:
		print("READY %d %s" % [id, "on" if on else "off"])
	_players_updated()


func _unique_name(wanted: String) -> String:
	if wanted == "":
		wanted = "Player"
	var taken := []
	for p in players.values():
		taken.append(p.name)
	for p in spectators.values():
		taken.append(p.name)
	var candidate := wanted
	var n := 2
	while candidate in taken:
		candidate = "%s %d" % [wanted, n]
		n += 1
	return candidate


func _free_color() -> int:
	var used := []
	for p in players.values():
		used.append(p.color)
	for i in PLAYER_COLORS.size():
		if not i in used:
			return i
	return 0


## Names for computer players, so several bots can be told apart on the scoreboard.
const BOT_NAMES := ["Gizmo", "Sprocket", "Bolt", "Piston", "Widget", "Ratchet", "Dynamo"]   # never the name of a robot you can play


## Adds a computer player. Returns its id (0 if there is no room). The host runs every
## bot (offline, or in an online lobby: everyone else sees them like any player, their
## movement relayed by the host: see send_bot_snapshot).
## Bots take turns through the robots, starting with the one after yours, so in a
## 1v1 the bot never plays the robot you picked; colours always differ. Each bot
## takes a gun and a mobility tool at random from those the lobby allows (or `weapon`
## and `mobility`, if given and allowed).
func add_bot(difficulty: int, weapon: String = "", mobility: String = "") -> int:
	if not is_host():
		return 0
	var id := BOT_ID_BASE
	while players.has(id):
		id += 1
	var index := id - BOT_ID_BASE
	var character := player_character(my_id())
	var guns := LobbySettings.allowed_weapons()
	var tools := LobbySettings.allowed_mobility()
	for i in index + 1:
		character = Characters.next(character)
	players[id] = {
		"name": "%s (%s)" % [BOT_NAMES[index % BOT_NAMES.size()], BotDifficulty.NAMES[difficulty]],
		"color": _free_color(), "bot": true, "difficulty": difficulty,
		"card": CallingCard.CARDS[randi() % CallingCard.CARDS.size()].id, "icon": CallingCard.ICONS[randi() % CallingCard.ICONS.size()].id,
		"character": character,
		"weapon": LobbySettings.fit_weapon(WeaponData.valid(weapon)) if weapon != "" else guns[randi() % guns.size()],
		"mobility": LobbySettings.fit_mobility(Mobility.valid(mobility)) if mobility != "" else tools[randi() % tools.size()],
	}
	if in_match and Teams.active():
		players[id]["team"] = Teams.smaller_team()   # the debug menu adding one mid-match
	_players_updated()
	return id


## Takes a computer player out (the host).
func remove_bot(id: int) -> void:
	if is_bot(id) and is_host():
		players.erase(id)
		_players_updated()


## Host: how hard a bot plays (a number in BotDifficulty.NAMES), in the lobby. Its name
## says so: "Gizmo (Hard)".
func set_bot_difficulty(id: int, difficulty: int) -> void:
	if not is_bot(id) or not is_host() or in_match:
		return
	difficulty = clampi(difficulty, 0, BotDifficulty.NAMES.size() - 1)
	var base := str(players[id].name).get_slice(" (", 0)
	players[id]["difficulty"] = difficulty
	players[id]["name"] = "%s (%s)" % [base, BotDifficulty.NAMES[difficulty]]
	_players_updated()


## The bots in this session, in the order they were added.
func bot_ids() -> Array:
	var ids := players.keys().filter(func(i): return is_bot(i))
	ids.sort()
	return ids


func is_bot(id: int) -> bool:
	return players.has(id) and players[id].get("bot", false)


func has_bots() -> bool:
	for id in players:
		if is_bot(id):
			return true
	return false


func player_name(id: int) -> String:
	return players[id].name if players.has(id) else "?"


## The robot a player is playing as (an id from Characters).
func player_character(id: int) -> String:
	return Characters.valid(str(players[id].get("character", ""))) if players.has(id) else Characters.default_id()


## The gun a player is using (an id from WeaponData). In a Deathmatch it is the
## weapon in their hands, or "none" before they have picked one up.
func player_weapon(id: int) -> String:
	if not players.has(id):
		return WeaponData.default_id()
	if in_match and is_deathmatch():
		var held := str(players[id].get("held", "none"))
		return held if WeaponData.has(held) else "none"
	return WeaponData.valid(str(players[id].get("weapon", "")))


## The mobility tool a player has (an id from Mobility). A race always has the grapple,
## and so does a bot on a map that asks for it (MapRoot.bots_grapple).
func player_mobility(id: int) -> String:
	if Race.active or (in_match and game_kind() == "race"):
		return Mobility.GRAPPLE
	if is_bot(id) and MapRoot.current != null and is_instance_valid(MapRoot.current) and MapRoot.current.bots_grapple:
		return Mobility.GRAPPLE   # a map bots only get round with the grapple
	return player_loadout_mobility(id)


## The mobility tool a player picked (whatever the game).
func player_loadout_mobility(id: int) -> String:
	return Mobility.valid(str(players[id].get("mobility", ""))) if players.has(id) else Mobility.default_id()


## The weapon a player chose in the lobby or the loadout (what they spawn with
## outside a Deathmatch).
func player_loadout_weapon(id: int) -> String:
	return WeaponData.valid(str(players[id].get("weapon", ""))) if players.has(id) else WeaponData.default_id()


## Deathmatch: how many weapons you can carry, one slot per key (1 and 2).
const SLOTS := 2


## Deathmatch: the weapons a player is carrying (picked up since they last died), by
## slot: SLOTS entries, "" for an empty slot. Slot 1 is key 1, slot 2 is key 2.
func player_inventory(id: int) -> Array:
	var slots: Array = players[id].get("inventory", []) if players.has(id) else []
	slots = slots.duplicate()
	slots.resize(SLOTS)
	for i in SLOTS:
		if slots[i] == null:
			slots[i] = ""
	return slots


## Deathmatch: the weapons a player carries, without the empty slots.
func player_weapons(id: int) -> Array:
	return player_inventory(id).filter(func(w): return w != "")


# ---------------------------------------------------------------------------
# Deathmatch inventory (the host decides; everyone is told through `players`)

## Deathmatch: hold one of the weapons you carry ("none": put it away). The host
## checks you have it.
func switch_my_weapon(weapon: String) -> void:
	if is_host():
		_apply_held(my_id(), weapon)
	else:
		_choose_held.rpc_id(1, weapon)


@rpc("any_peer", "call_remote", "reliable")
func _choose_held(weapon: String) -> void:
	if is_host():
		_apply_held(multiplayer.get_remote_sender_id(), weapon)


## Host: `id` holds `weapon` now, if they carry it (bots call this directly).
func _apply_held(id: int, weapon: String) -> void:
	if not players.has(id) or not is_deathmatch() or not Match.is_alive(id):
		return
	if weapon != "none" and not weapon in player_weapons(id):
		return
	if str(players[id].get("held", "none")) == weapon:
		return
	players[id]["held"] = weapon
	_players_updated()


## Host: `id` walked over `weapon`. One they already carry only refills its ammo (on
## their own copy; see Arena). Otherwise it goes in their first empty slot (and in
## their hands if those were empty), or, with both slots full, it replaces the weapon
## in their hands. Returns true if what they carry changed.
func host_give_weapon(id: int, weapon: String) -> bool:
	if not players.has(id) or not WeaponData.has(weapon):
		return false
	var slots := player_inventory(id)
	if weapon in slots:
		return false
	var held := str(players[id].get("held", "none"))
	var at := slots.find("")
	if at < 0:
		at = maxi(slots.find(held), 0)   # full: swap out the one in your hands
		held = weapon
	slots[at] = weapon
	if not WeaponData.has(held):
		held = weapon
	players[id]["inventory"] = slots
	players[id]["held"] = held
	_players_updated()
	return true


## Host: `id` died (or a Deathmatch is starting): empty hands, nothing carried.
func host_clear_inventory(id: int, tell: bool = true) -> void:
	if not players.has(id):
		return
	var empty := []
	empty.resize(SLOTS)
	empty.fill("")
	players[id]["inventory"] = empty
	players[id]["held"] = "none"
	if tell:
		_players_updated()


## Host: everyone hears about a change to `players`.
func _players_updated() -> void:
	if is_online:
		_sync_players.rpc(players)
	else:
		players_changed.emit()


## A player's colour (their robot, name and stripes): in a team mode, their team's.
func player_color(id: int) -> Color:
	var team := Teams.team_of(id)
	if team >= 0:
		return Teams.team_color(team)
	return PLAYER_COLORS[players[id].color] if players.has(id) else Color.WHITE


# ---------------------------------------------------------------------------
# Match flow

## "ffa", "dm" or "race": what kind of game is set up (one the map can host).
func game_kind() -> String:
	var game := str(match_settings.get("game", ""))
	return game if game in Maps.games_of(map_id()) else Maps.game_of(map_id())


## Deathmatch: everyone starts unarmed and picks weapons up off the map.
func is_deathmatch() -> bool:
	return game_kind() == "dm"


## Deathmatch: whether the host turned power-ups on in the lobby (on unless said otherwise).
func powerups_on() -> bool:
	return bool(match_settings.get("powerups", true))


## The id of the map being played (or about to be).
func map_id() -> String:
	return str(match_settings.get("map", Maps.default_id()))


## Host: start the match. Online, only once everyone is ready (see all_ready), unless
## `force` (dev autostart). Everyone's ready goes back to off for the next lobby.
func host_start_match(force: bool = false) -> void:
	if not is_host() or _starting:
		return
	if is_online and not force and not all_ready():
		return
	_starting = true
	host_pick_random_map()
	for id in players:
		players[id].erase("ready")   # (handing out the weapons below changes the players, which can call this again: dev autostart)
	host_fit_loadouts()   # nobody starts with a weapon the lobby does not allow
	var teams_before := players.values().map(func(p): return p.get("team", -1))
	Teams.host_assign()   # team modes: everyone onto Red or Blue (otherwise no teams)
	var teams_changed := teams_before != players.values().map(func(p): return p.get("team", -1))
	if GunGame.active() or KillcamMode.active() or teams_changed:   # the first rung of the ladder; Killcam: the sniper
		for id in players:
			if GunGame.active() or KillcamMode.active():
				players[id]["weapon"] = GunGame.weapon_at(0) if GunGame.active() else KillcamMode.WEAPON
	_players_updated()   # the weapons and teams above, and nobody ready any more
	_log_loadouts()
	_start_match.rpc()
	_starting = false


var _starting := false


## Host: with a random map set (see LobbySettings), pick one of the pool's maps (not the
## one just played, when the pool has others) and tell everyone, before the match
## starts. The pick stays in match_settings.map, so a late joiner loads it too.
func host_pick_random_map() -> void:
	if not is_host() or not bool(match_settings.get("random_map", false)):
		return
	var s := match_settings.duplicate()
	s["map"] = LobbySettings.pick_map(s.get("map_pool", []), game_kind(), map_id())
	if DevArgs.sync_log:
		print("RANDOM_MAP %d %s pool=%s" % [my_id(), s.map, ",".join(LobbySettings.map_pool())])
	_sync_settings.rpc(s)   # (reliable and in order: everyone has it before the match starts)


@rpc("authority", "call_local", "reliable")
func _start_match() -> void:
	in_match = true
	if DevArgs.sync_log:
		print("MATCH_START %d players" % players.size())
		print("MATCH_MAP %d %s" % [my_id(), map_id()])
	match_started.emit()


@rpc("authority", "call_remote", "reliable")
func _late_join() -> void:
	in_match = true
	if DevArgs.sync_log:
		print("MATCH_MAP %d %s (late)" % [my_id(), map_id()])
	match_started.emit()


# ---------------------------------------------------------------------------
# Map objects: terminals players press "interact" at, and the events they set off (see
# MapTerminal and MapEvent). A player only says when they start and stop holding; the
# host checks range and timing, decides, and tells everyone what state things are in.

## The local player `who` (you, or one of the host's bots) started or stopped holding
## interact at terminal number `index`.
func terminal_hold(index: int, holding: bool, who: int = 0) -> void:
	if is_host():
		_host_terminal_hold(index, who if who != 0 else my_id(), holding)
	elif is_online:
		_terminal_hold.rpc_id(1, index, holding)


@rpc("any_peer", "call_remote", "reliable")
func _terminal_hold(index: int, holding: bool) -> void:
	if is_host():
		_host_terminal_hold(index, multiplayer.get_remote_sender_id(), holding)


func _host_terminal_hold(index: int, who: int, holding: bool) -> void:
	var terminal := MapTerminal.at(get_tree(), index)
	if terminal:
		terminal.host_set_holding(who, holding)


## Host: tell everyone (or only peer `to`) what state a terminal is in.
func send_terminal_state(index: int, phase: int, who: int, progress: float, to: int = 0) -> void:
	if not is_host():
		return
	if to != 0:
		_terminal_state.rpc_id(to, index, phase, who, progress)
	else:
		_terminal_state.rpc(index, phase, who, progress)


@rpc("authority", "call_local", "reliable")
func _terminal_state(index: int, phase: int, who: int, progress: float) -> void:
	var terminal := MapTerminal.at(get_tree(), index)
	if terminal:
		terminal.apply_state(phase, who, progress)


## Host: tell everyone (or only peer `to`) whether a map event is running and how far in.
func send_map_event_state(index: int, running: bool, elapsed: float, to: int = 0) -> void:
	if not is_host():
		return
	var event := MapEvent.at(get_tree(), index)
	var state := event.state if event else 0   # (a LayoutEvent's layout; 0 for the others)
	if to != 0:
		_map_event_state.rpc_id(to, index, running, elapsed, state)
	else:
		_map_event_state.rpc(index, running, elapsed, state)


@rpc("authority", "call_local", "reliable")
func _map_event_state(index: int, running: bool, elapsed: float, state: int = 0) -> void:
	var event := MapEvent.at(get_tree(), index)
	if event:
		event.take_state(state)
		event.apply_state(running, elapsed)
		if DevArgs.sync_log:
			print("MAP_EVENT %d %s %.2f %d" % [index, "on" if running else "off", elapsed, state])


## A copy that has just built the arena asks the host where the terminals and events are.
func request_map_state() -> void:
	if not is_host() and is_online:
		_map_state_request.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _map_state_request() -> void:
	if not is_host():
		return
	var to := multiplayer.get_remote_sender_id()
	var events := get_tree().get_nodes_in_group(MapEvent.GROUP)
	for i in events.size():
		var e := events[i] as MapEvent
		if e.running or e.state != 0:   # (an event that has run and left the map in another state)
			send_map_event_state(i, e.running, e.elapsed, to)
	var terminals := get_tree().get_nodes_in_group(MapTerminal.GROUP)
	for i in terminals.size():
		var t := terminals[i] as MapTerminal
		send_terminal_state(i, t.phase, t.channeler, t.progress, to)


# ---------------------------------------------------------------------------
# Player state. Each player sends its own movement snapshot ~30 times a second.
# The host relays it to everyone else (Godot's server relay).

## time: the sender's clock (seconds, full precision). data: see Player.make_snapshot().
func send_snapshot(time: float, data: PackedFloat32Array) -> void:
	if not is_online or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_snapshot.rpc(time, data)


## Host, online: a bot's movement, sent for it (a bot has no connection of its own).
func send_bot_snapshot(id: int, time: float, data: PackedFloat32Array) -> void:
	if not is_online or not is_host() or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_bot_snapshot.rpc(id, time, data)


@rpc("authority", "call_remote", "unreliable", 1)
func _bot_snapshot(id: int, time: float, data: PackedFloat32Array) -> void:
	if not is_bot(id):
		return
	if DevArgs.net_sim_enabled():
		_sim_receive(id, time, data)
	else:
		_deliver_snapshot(id, time, data)


@rpc("any_peer", "call_remote", "unreliable", 1)
func _snapshot(time: float, data: PackedFloat32Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if DevArgs.net_sim_enabled():
		_sim_receive(sender, time, data)
	else:
		_deliver_snapshot(sender, time, data)


func _deliver_snapshot(sender: int, time: float, data: PackedFloat32Array) -> void:
	if arena and is_instance_valid(arena):
		arena.on_snapshot(sender, time, data)


# ---------------------------------------------------------------------------
# Bad-network simulation for testing (--net-sim=LATENCY_MS,JITTER_MS,LOSS_PERCENT).
# Delays and drops incoming movement snapshots so we can check that other players
# still look smooth on a poor connection.

var _sim_queue: Array = []  # [deliver_at, sender, time, data]


func _sim_receive(sender: int, time: float, data: PackedFloat32Array) -> void:
	if randf() * 100.0 < DevArgs.net_sim_loss:
		return
	var delay := (DevArgs.net_sim_latency + randf() * DevArgs.net_sim_jitter) / 1000.0
	_sim_queue.append([now() + delay, sender, time, data])


func _process(delta: float) -> void:
	_share_pings(delta)
	if _sim_queue.is_empty():
		return
	var t := now()
	var keep: Array = []
	for item in _sim_queue:
		if item[0] <= t:
			_deliver_snapshot(item[1], item[2], item[3])
		else:
			keep.append(item)
	_sim_queue = keep


# ---------------------------------------------------------------------------
# Ping: the host knows the round trip to each client (ENet keeps it), so it sends
# everyone the list now and then. A client knows its own round trip best itself.

## Host: every PING_GAP seconds, tell everyone each player's ping.
func _share_pings(delta: float) -> void:
	if not is_host() or not is_online:
		return
	_ping_wait -= delta
	if _ping_wait > 0.0:
		return
	_ping_wait = PING_GAP
	var now_pings := {}
	for id in players:
		if id != host_id() and not is_bot(id):
			var ms := _rtt_to(id)
			if ms >= 0:
				now_pings[id] = ms
	_sync_pings.rpc(now_pings)


@rpc("authority", "call_local", "unreliable_ordered")
func _sync_pings(new_pings: Dictionary) -> void:
	pings = new_pings
	if DevArgs.sync_log:
		var ids := pings.keys()
		ids.sort()
		print("PINGS %d %s" % [my_id(), " ".join(ids.map(func(i): return "%d:%d" % [i, pings[i]]))])


## The round trip in ms on our ENet link to `id` (-1 if there is none).
func _rtt_to(id: int) -> int:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		var link: ENetPacketPeer = (peer as ENetMultiplayerPeer).get_peer(id)
		if link:
			return int(link.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	return -1


## A player's ping to the host in ms: 0 for the host itself, -1 when there is none
## (bots, playing offline, or not measured yet). Your own comes from your own link.
func player_ping(id: int) -> int:
	if not is_online or is_bot(id) or not players.has(id):
		return -1
	if id == host_id():
		return 0
	if id == my_id():
		return _rtt_to(host_id())
	return int(pings.get(id, -1))
