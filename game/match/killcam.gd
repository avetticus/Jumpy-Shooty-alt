extends Node
## Killcams. Autoload at /root/Killcam.
##
## Every copy of the game keeps the last few seconds of the match: for every player,
## what it drew for them about 30 times a second (see Player.shown_state), and the
## shots, rockets and blows the host told it about. That is all data the game already
## receives to draw the match, so a killcam costs no extra network traffic per frame.
##
## When you are knocked out, the last BEFORE seconds play again from the eyes of
## whoever got you (KillcamView), in the time you wait to respawn anyway. Jump or
## fire skips it.
##
## The host scores every kill (KillScore) and sends the score with the death, a few
## numbers per kill. Each copy keeps the clips of the KEEP best kills it has seen.
## When the match ends the host names the best ones (Match.highlights) and every copy
## plays its own recording of them on the results screen. Every copy sees the same
## kills, scored by the same host, so they all keep the same clips.
##
## Timing: other players reach us a little late (the trip over the network, plus the
## smoothing in SnapshotBuffer), and the killer saw everyone else late too. Each frame
## is stored at the time it really happened (our game clock, _clock, less how late it
## came), and
## the replay shows each player as late as the killer would have seen them, so the
## killer's aim lines up with their target the way it did on their screen.
##
## A death's remains (a ragdoll or giblets, see Remains) are recorded as they fall
## (KillClip.Wreck), for WRECK_FOR seconds, so a replay shows the body fall the way it
## did here. Physics runs on the game's own clock, which a replay in slow motion or a
## video saved frame by frame does not keep to, so replays play the recording back
## rather than simulate the fall again. After the match ends the fall of the last kill
## is still recorded while the arena is there (it is often one of the best kills).
##
## The map's moving parts (a crane and its load, flying islands, walls shot through:
## see MapReplay) are recorded too, at the time they are drawn (every copy draws the
## map in the present), so a replay puts them back where they were. And every shot
## says exactly where it was aimed (Match.shot_aimed): the replay holds the killer's
## crosshair to that, and moves whoever they hit to where the hit says (see KillClip).

signal started   ## the death killcam began
signal ended     ## ...and finished, was skipped, or you respawned

const RATE := 30.0              ## frames recorded per second
const HISTORY := 7.0            ## seconds kept
const BEFORE := 2.5             ## the death killcam: seconds before the kill...
const AFTER := 0.5              ## ...and after it (together: the respawn wait)
const HIGHLIGHT_BEFORE := 3.0   ## results screen: a little more lead-in...
const HIGHLIGHT_AFTER := 1.0    ## ...and follow-through
const STREAK_LEAD := 1.0        ## a multikill starts this long before its first kill
const VIEW_INTERP := 0.085      ## how far in the past a player's game typically draws others (SnapshotBuffer)
const KEEP := 3                 ## clips kept for the results screen
const MIN_LEAD := 1.0           ## the death killcam needs this much of the killer before the kill
const SKIP_AFTER := 0.75        ## the death killcam can be skipped once it has played this long
                                ## (so a jump or shot already on its way as you die does not skip it)
const WRECK_FOR := 5.0           ## seconds of each body's fall recorded (then it holds still)
const STICK_AGAIN := 1.0         ## a sticky grenade still stuck is recorded again this often (see _restick)

## The best kills' clips, by kill number (see Match.kill_log).
var clips: Dictionary = {}
## The death killcam playing now, or null.
var view: KillcamView = null
var watched := 0.0              ## seconds the death killcam has been playing

var _tracks: Dictionary = {}    # id -> KillClip.Track, the last HISTORY seconds
var _events: Array = []         # shots and so on, the last HISTORY seconds
var _timer := 0.0
## Game time (seconds of play, so a slowed-down or stalled game replays at the speed it
## was played). Recording, kills and replays all count in it.
var _clock := 0.0
var _pending: Array = []        # kills waiting for their follow-through to be recorded
var _kill_times: Dictionary = {}   # seq -> when it happened (for multikills)
var _rocket_owner: Dictionary = {} # projectile id -> who fired it
var _stuck: Dictionary = {}        # sticky grenade id -> [its latest "stick" event, when it was last recorded]
var _wrecks: Array = []         # KillClip.Wreck, oldest first
var _wreck_of: Dictionary = {}  # remains (instance id) -> [its Wreck, how late its player is drawn]
var _props: Dictionary = {}     # the map's moving parts: key -> KillClip.PropTrack (see MapReplay)
var _over := false               # the match has ended (see _settling)


func _ready() -> void:
	Net.match_started.connect(_on_match_started)
	Match.kill_scored.connect(_on_kill_scored)
	Match.shot_aimed.connect(func(shooter: int, eye: Vector3, aim: Vector3):
		_event({"kind": "aim", "who": shooter, "eye": eye, "aim": aim}))
	Match.shot_fired.connect(func(shooter: int, muzzle: Vector3, ends: PackedVector3Array, hits: Array):
		_event({"kind": "shot", "who": shooter, "muzzle": muzzle, "ends": ends, "hits": hits, "weapon": Net.player_weapon(shooter)}))
	Match.projectile_fired.connect(func(id: int, shooter: int, weapon_id: String, origin: Vector3, direction: Vector3, sticky: bool):
		_rocket_owner[id] = shooter
		_event({"kind": "projectile", "who": shooter, "id": id, "weapon": weapon_id, "origin": origin, "direction": direction, "sticky": sticky}))
	Match.exploded.connect(func(id: int, at: Vector3, weapon_id: String):
		_event({"kind": "boom", "who": int(_rocket_owner.get(id, 0)), "id": id, "at": at, "weapon": weapon_id})
		_rocket_owner.erase(id)
		_stuck.erase(id))
	Match.projectile_stuck.connect(func(id: int, how: Dictionary):
		var e := {"kind": "stick", "who": int(how.get("who", 0)), "id": id, "how": how, "armed": false}
		_event(e)
		_stuck[id] = [e, _clock])
	Match.projectile_armed.connect(func(id: int):
		if _stuck.has(id):
			var e: Dictionary = _stuck[id][0]
			_event({"kind": "armed", "who": int(e.who), "id": id})
			_stuck[id][0] = e.merged({"armed": true}, true))
	Match.projectile_gone.connect(func(id: int):
		_event({"kind": "gone", "who": int(_rocket_owner.get(id, 0)), "id": id})
		_rocket_owner.erase(id)
		_stuck.erase(id))
	Match.melee_landed.connect(func(attacker: int, weapon_id: String, points: PackedVector3Array):
		_event({"kind": "melee", "who": attacker, "weapon": weapon_id, "points": points}))
	Match.match_over.connect(_on_match_over)
	Match.player_respawned.connect(_on_respawned)


func _on_match_started() -> void:
	stop()
	_tracks.clear()
	_events.clear()
	_pending.clear()
	_kill_times.clear()
	_rocket_owner.clear()
	_stuck.clear()
	clips.clear()
	_wrecks.clear()
	_wreck_of.clear()
	_props.clear()
	_over = false
	_timer = 0.0


func _recording() -> bool:
	return Net.arena != null and is_instance_valid(Net.arena) and Match.running and not Race.active \
		and Net.arena.players_root != null


func _process(delta: float) -> void:
	if watching():
		watched += delta
	var recording := _recording()
	if not recording and not _settling():
		return
	_clock += delta
	_timer -= delta
	if _timer <= 0.0:
		_timer = maxf(_timer + 1.0 / RATE, 0.0)
		if recording:
			_record()
		else:
			_record_wrecks(_clock)
	if not recording:
		return
	var now := _clock
	while not _pending.is_empty() and float(_pending[0].at) <= now:
		_capture(_pending.pop_front())


# ---------------------------------------------------------------------------
# Recording

func _record() -> void:
	var now := _clock
	for node in Net.arena.players_root.get_children():
		var p := node as Player
		if p == null or p.is_queued_for_deletion() or p.robot == null:
			continue
		var track: KillClip.Track = _tracks.get(p.peer_id)
		if track == null:
			track = KillClip.Track.new()
			_tracks[p.peer_id] = track
		track.character = p.character
		track.color = Net.player_color(p.peer_id)
		track.paint = Teams.paint_for(p.peer_id)   # (kept with the clip: the results screen comes after the teams are gone)
		track.name = Net.player_name(p.peer_id)
		track.push(now - _lag(p), p.shown_state())
		track.trim(now - HISTORY)
	while not _events.is_empty() and float(_events[0].t) < now - HISTORY:
		_events.pop_front()   # (in place: a death killcam playing holds this same array)
	_restick(now)
	_record_wrecks(now)
	_record_props(now)


## A sticky grenade can sit stuck far longer than the HISTORY kept, and a clip that
## starts after it stuck still has to show it: every STICK_AGAIN seconds each one still
## stuck is recorded stuck again (the same "stick" event, armed or not by now), so every
## clip has one from just before it starts (see KillClip.cut).
func _restick(now: float) -> void:
	for id in _stuck.keys():
		var entry: Array = _stuck[id]
		if now - float(entry[1]) >= STICK_AGAIN:
			var e: Dictionary = (entry[0] as Dictionary).duplicate()
			_event(e)
			_stuck[id] = [e, now]


## The map's moving parts, as they are drawn now (see MapReplay).
func _record_props(now: float) -> void:
	var map: Node = Net.arena.get("layout")
	for part in MapReplay.parts(map):
		var track: KillClip.PropTrack = _props.get(part[0])
		if track == null:
			track = KillClip.PropTrack.new()
			_props[part[0]] = track
		track.look(now, part[1].call("replay_capture"))
		track.trim(now - HISTORY)


## The remains in the arena: a new recording for each new one, and where every one
## still falling has got to.
func _record_wrecks(now: float) -> void:
	for node in Remains.bodies():
		var key := (node as Object).get_instance_id()
		if _wreck_of.has(key) or not node.is_inside_tree():
			continue
		var lag := _lag_of(int(node.get("who")))
		var w := KillClip.Wreck.of(node, now - lag - float(node.call("age")))   # (made since the last frame)
		_wreck_of[key] = [w, lag]
		_wrecks.append(w)
	for key in _wreck_of.keys():
		var node := instance_from_id(key) as Node3D
		var entry: Array = _wreck_of[key]
		var w: KillClip.Wreck = entry[0]
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			_wreck_of.erase(key)   # gone (dissolved, or the oldest of too many): it holds its last frame
		elif w.last_time() - w.first_time() < WRECK_FOR:
			w.push(now - float(entry[1]), node.call("capture"))
	while not _wrecks.is_empty() and (_wrecks[0] as KillClip.Wreck).first_time() < now - HISTORY - Remains.LIFETIME:
		_wrecks.pop_front()   # (in place, like _events)


## The match is over but a body is still falling (the last kill's, most likely): keep
## recording it while the arena is there.
func _settling() -> bool:
	if not _over or Net.arena == null or not is_instance_valid(Net.arena):
		return false
	for node in Remains.bodies():
		var entry: Array = _wreck_of.get((node as Object).get_instance_id(), [])
		if entry.is_empty() or (entry[0] as KillClip.Wreck).last_time() - (entry[0] as KillClip.Wreck).first_time() < WRECK_FOR:
			return true
	return false


## How late this copy draws player `id` (0 if they are not in the arena).
func _lag_of(id: int) -> float:
	var players: Node = Net.arena.get("players_root") if Net.arena else null
	var p: Player = players.get_node_or_null("Player_%d" % id) as Player if players else null
	return _lag(p) if p else 0.0


func _event(e: Dictionary) -> void:
	if not _recording():
		return
	e["t"] = _clock - _delay(int(e.who))
	_events.append(e)


## Which computer runs a player: the host runs the bots.
static func _machine(id: int) -> int:
	return 1 if Net.is_bot(id) else id


## Round trip (seconds) between a computer and the host. A copy that is not the host
## only knows its own, and takes the other players' to be about the same.
func _rtt(machine: int) -> float:
	if machine == 1 or not Net.is_online:
		return 0.0
	var peer := multiplayer.multiplayer_peer
	if not peer is ENetMultiplayerPeer:
		return 0.0
	var link: ENetPacketPeer = (peer as ENetMultiplayerPeer).get_peer(machine if Net.is_host() else 1)
	return link.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) / 1000.0 if link else 0.0


## How long news from player `id` takes to reach this copy (it goes through the host).
func _delay(id: int) -> float:
	return (_rtt(_machine(id)) + _rtt(_machine(Net.my_id()))) * 0.5


## How far in the past this copy draws a player.
func _lag(p: Player) -> float:
	return 0.0 if p.is_local else p.buffer.delay() + _delay(p.peer_id)


## How far in the past the killer's screen showed player `id`.
func _seen_late(killer: int, id: int) -> float:
	if _machine(killer) == _machine(id):
		return 0.0
	return VIEW_INTERP + (_rtt(_machine(killer)) + _rtt(_machine(id))) * 0.5


# ---------------------------------------------------------------------------
# Kills

func _on_kill_scored(info: Dictionary) -> void:
	if not _recording():
		return
	var now := _clock
	var kill_time := now - _delay(int(info.killer))
	_kill_times[int(info.seq)] = kill_time
	var start := kill_time - HIGHLIGHT_BEFORE
	if int(info.streak) > 0:   # a multikill: from just before the first of them
		for k in Match.kill_log:
			if int(k.killer) == int(info.killer) and _kill_times.has(int(k.seq)) and int(k.seq) < int(info.seq) \
					and kill_time - float(_kill_times[int(k.seq)]) <= KillScore.MULTI_WINDOW:
				start = minf(start, float(_kill_times[int(k.seq)]) - STREAK_LEAD)
	start = maxf(start, kill_time - HISTORY + 2.0)   # (still recorded when the clip is kept)
	var clip := _live_clip(info, kill_time, start, kill_time + HIGHLIGHT_AFTER)
	_pending.append({"clip": clip, "at": now + HIGHLIGHT_AFTER + 0.4})
	if int(info.victim) == Net.my_id() and Settings.killcam:
		_start_death_cam(_live_clip(info, kill_time, kill_time - BEFORE, kill_time + AFTER))


## A clip that reads straight from what is being recorded (it fills in as it plays).
func _live_clip(info: Dictionary, kill_time: float, start: float, end: float) -> KillClip:
	var clip := KillClip.new()
	clip.info = info
	clip.killer = int(info.killer)
	clip.victim = int(info.victim)
	clip.kill_time = kill_time
	clip.start = start
	clip.end = end
	clip.map = Net.map_id()
	clip.tracks = _tracks.duplicate()   # the same Track objects, still being added to
	clip.events = _events
	clip.wrecks = _wrecks
	clip.props = _props.duplicate()   # the same PropTracks, still being added to
	for id in Net.players:
		clip.offsets[id] = -_seen_late(clip.killer, id)
		clip.event_offsets[id] = _seen_late(clip.killer, id)
	return clip


## The kill's follow-through is recorded: keep its clip if it is one of the best.
func _capture(entry: Dictionary) -> void:
	var live: KillClip = entry.clip
	if not live.has_killer():   # (a best kill keeps what there is, even right after the start)
		return
	var clip := live.cut()
	clip.align_to_hits()
	clips[int(clip.info.seq)] = clip
	while clips.size() > KEEP:
		var worst = null
		for seq in clips:
			var c: KillClip = clips[seq]
			if worst == null or int(c.info.score) < int(worst.info.score) \
					or (int(c.info.score) == int(worst.info.score) and int(c.info.seq) > int(worst.info.seq)):
				worst = c
		clips.erase(int(worst.info.seq))


func _on_match_over(_results: Array) -> void:
	stop()
	_over = true
	if Net.arena != null and is_instance_valid(Net.arena):
		_record_wrecks(_clock)   # the last kill's remains, if they came this frame (its clip is cut now)
	for entry in _pending:   # the winning kill ends the match: keep what there is of it
		_capture(entry)
	_pending.clear()
	if DevArgs.sync_log:
		var have := []
		for h in Match.highlights:
			have.append("%d:%s" % [h.seq, "clip" if clips.has(int(h.seq)) else "none"])
		print("KILLCAM_CLIPS %d %s" % [Net.my_id(), " ".join(have)])


## The clip of one of the match's best kills, or null if this copy did not see it.
func clip_for(highlight: Dictionary) -> KillClip:
	return clips.get(int(highlight.get("seq", -1)))


# ---------------------------------------------------------------------------
# The death killcam

func watching() -> bool:
	return view != null and is_instance_valid(view)


## The death killcam has played long enough to be skipped (see SKIP_AFTER).
func can_skip() -> bool:
	return watching() and watched >= SKIP_AFTER


func _start_death_cam(clip: KillClip) -> void:
	stop()
	var arena := Net.arena
	if arena == null or not clip.has_killer(MIN_LEAD):
		if DevArgs.sync_log:
			print("KILLCAM NONE %d %d" % [Net.my_id(), clip.killer])
		return
	var guessed := float(clip.offsets.get(clip.victim, 0.0))
	clip.align_to_hits()
	var playing := KillcamView.new()
	view = playing
	watched = 0.0
	view.map = arena.get("layout")
	view.setup(clip, false)
	arena.add_child(view)
	arena.players_root.visible = false   # the replay's bodies stand in for the live ones
	Remains.set_hidden(true)              # ...and its remains for the ones lying there now
	if DevArgs.sync_log:
		var kt: KillClip.Track = clip.tracks[clip.killer]
		print("KILLCAM PLAY %d %d %d %d %.2f %.2f" % [Net.my_id(), clip.killer, int(clip.info.seq), kt.frames.size(), kt.first_time() - clip.kill_time, kt.last_time() - clip.kill_time])
		# KILLCAM SYNC <me> <killer> <shots aimed> <map parts> <victim moved to meet the hits (ms)>
		print("KILLCAM SYNC %d %d %d %s %.0f" % [Net.my_id(), clip.killer, clip.aim_keys().size(), ",".join(clip.props.keys()),
			(float(clip.offsets.get(clip.victim, 0.0)) - guessed) * 1000.0])
	view.finished.connect(func():
		if view != playing:
			return   # (one that was just stopped)
		if DevArgs.sync_log:
			print("KILLCAM DONE %d" % Net.my_id())
			print("KILLCAM AIM %d %s" % [Net.my_id(), playing.aim_report()])
		stop())   # on to the death screen, to pick a loadout and respawn
	started.emit()


## Jump or fire skips the death killcam.
func skip() -> void:
	if watching():
		if DevArgs.sync_log:
			print("KILLCAM SKIP %d" % Net.my_id())
		stop()


func stop() -> void:
	if view == null:
		return
	if is_instance_valid(view):
		view.queue_free()
	view = null
	var arena := Net.arena
	Remains.set_hidden(false)
	if arena and is_instance_valid(arena) and arena.players_root:
		arena.players_root.visible = true
		var me: Player = arena.local_player
		if me and me.rig:
			me.rig.camera.make_current()
	ended.emit()


func _on_respawned(id: int, _spawn: int) -> void:
	if id == Net.my_id() and watching():
		if DevArgs.sync_log:
			print("KILLCAM END %d" % Net.my_id())
		stop()


func _unhandled_input(event: InputEvent) -> void:
	if watching() and not event.is_echo() and (event.is_action_pressed("jump") or event.is_action_pressed("fire")):
		if can_skip():
			if DevArgs.sync_log:
				print("KILLCAM SKIP BY %s %.2f" % [event.as_text(), watched])
			skip()
		elif DevArgs.sync_log:
			print("KILLCAM TOO SOON %.2f" % watched)
		get_viewport().set_input_as_handled()   # (too soon: still the killcam's, not the game's)
