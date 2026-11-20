extends Node
## The rules of a match, run by the host. Autoload at /root/Match.
##
## The host is the referee: it decides hits, damage, deaths, respawns, scores and
## when the match ends, then tells everyone. Other players only *ask* (for example
## "I fired from here, in this direction, and this is what I could see").
##
## Hits are decided by the host *with rewind*: the shooter tells the host at what
## moment it was seeing each opponent, the host moves each opponent back to where
## they were at that moment, and checks the shot against those positions. So you
## hit what you aimed at on your screen, but the host has the final say.

signal state_changed               ## scores, health or timer changed
signal player_hit(shooter: int, target: int, damage: float, headshot: bool)
signal player_died(victim: int, killer: int)
signal player_respawned(id: int, spawn_index: int)   ## spawn_index: a new number for every respawn (it numbers the life: see Player._life)
## A target dummy was hit (it also sends player_hit, with the dummy's id as the target).
signal dummy_hit(shooter: int, dummy: int, damage: float, headshot: bool, killed: bool)
## One end per pellet; `vias`: per pellet, where it went into and came out of portals on
## the way ([in, out, ...], empty for a straight one: see Portals.path_bends).
signal shot_fired(shooter: int, muzzle: Vector3, ends: PackedVector3Array, hits: Array, vias: Array)
## Just before shot_fired: where the shooter was aiming (from `eye`, before any spread),
## so a killcam can point the killer's crosshair exactly where it was (see Killcam).
signal shot_aimed(shooter: int, eye: Vector3, aim: Vector3)
signal match_over(results: Array)
## A melee swing landed: who swung, with what, and where each blow struck (for sounds and sparks).
signal melee_landed(attacker: int, weapon_id: String, points: PackedVector3Array)
## A ground slam landed at `at` (see GroundSlam): `power` 0..1 is how big, `points` where it struck people.
signal ground_slammed(attacker: int, weapon_id: String, at: Vector3, power: float, points: PackedVector3Array)
## Someone hit a wall hard enough to hurt (for the crash sound everyone hears).
signal slammed(id: int, where: Vector3, speed: float)
## A rocket or grenade left `shooter`'s gun (everyone draws it: see Projectile).
signal projectile_fired(id: int, shooter: int, weapon_id: String, origin: Vector3, direction: Vector3)
## ...and blew up here.
signal exploded(id: int, at: Vector3, weapon_id: String)
## Gun Game: a player moved up (or down) the ladder to the weapon at `level`.
signal gun_game_level(id: int, level: int)
## A player got a kill, scored for the killcams (see KillScore); `info` is also kept in
## `kill_log`. Sent just before player_died for the same kill.
signal kill_scored(info: Dictionary)
## Golden Gun: `to` now holds the Golden Gun (`from` lost it, 0 at the start or when it
## had nobody to go to). See GoldenGun.
signal golden_gun_passed(to: int, from: int)

const MAX_HEALTH := 100.0
## After a death you wait at least this long; then you come back when you press Jump
## or Fire (see request_respawn), so there is time to change your loadout first.
## Bots, and you in Practice, come back on their own.
const RESPAWN_DELAY := 3.0
## A press this close to the end of the wait still counts (the client's own countdown
## can run a little ahead of the host's).
const RESPAWN_EARLY := 0.3
const MAX_REWIND := 0.6           ## seconds; older views are clamped (anti-abuse)
const HIT_FORGIVENESS := 0.08     ## metres added to player radius when checking hits
const HEAD_HEIGHT := 1.45         ## a hit above this height (from the feet) is a headshot
## Slamming into a wall or prop: hitting it faster than this (m/s, straight into it)
## hurts, SLAM_DAMAGE per m/s over, up to SLAM_MAX. Landings on the floor never count.
const SLAM_SPEED := 17.5
const SLAM_DAMAGE := 4.0
const SLAM_MAX := 80.0
## A crash within this many seconds of being shoved counts as the shover's hit (and kill).
const SHOVE_CREDIT := 3.0
## A killing blow that does this much more damage than the health left blows the body
## apart (giblets, see death_fx), and so does a blast at GIB_BLAST of its full strength or more.
## 75, not 50: a sniper headshot on a full-health player is 150 damage, 50 over, and should
## not blow them apart every time; one on a hurt player, or an anti-materiel headshot, does.
const GIB_OVERKILL := 75.0
const GIB_BLAST := 0.5
## kill_target 0 means "no kill target" (time-limit matches).
var kill_target := 15
var time_left := 480.0
var running := false
## id -> {"kills": int, "deaths": int}
var scores: Dictionary = {}
## id -> float
var health: Dictionary = {}
## id -> seconds until respawn (only for dead players); at 0 it waits for them to ask
var respawn_timers: Dictionary = {}
## Host: dead players who asked to come back (id -> true), respawned once their wait is over.
var respawn_asked: Dictionary = {}
## Results of the last finished match, for the results screen.
var last_results: Array = []

var _last_shot_time: Dictionary = {}   # host: id -> Net.now() of last accepted shot
var _last_slam_time: Dictionary = {}   # host: id -> Net.now() of last crash that hurt
var _last_shove: Dictionary = {}       # host: id -> [who shoved them, Net.now(), with what (see death_fx "with")]
var _last_kick_time: Dictionary = {}   # host: id -> Net.now() of last accepted kick
var _last_ground_slam: Dictionary = {}   # host: id -> Net.now() of last accepted ground slam
var _tethers: Dictionary = {}          # host: id -> [the player their hook is on, Net.now()]
var _projectiles: Dictionary = {}      # host: id -> {pos, vel, shooter, weapon, t}
var _next_projectile := 1
## How each player last died: "" (shot or cut down), "fell", or "slam" (hit a wall too hard).
var death_cause: Dictionary = {}
## How each player last died, as the host saw the killing blow (the same on every copy):
##   with: what did it: a WeaponData id, "kick", "flying_kick", "rope" (reeled in),
##         "none" (empty hands), or "" (nobody: a fall, a crash on your own, the bomb).
##         With cause "slam" it is what threw them into the wall.
##   head: the killing blow was a headshot.
##   gib:  the body is blown apart (a blast, the bomb, or GIB_OVERKILL), not a ragdoll.
##   push: the knockback the blow gave (world space; zero for most bullets).
##   dir:  the way the blow travelled (world space, length 1; zero if not known).
##   at:   (blasts only) where it went off.
## Empty for a death with nothing to tell (and for one sent by an older host).
var death_fx: Dictionary = {}
var _respawn_counter := 0
var _late_respawns: Dictionary = {}   # --delay-respawn: id -> spawn index of a respawn not applied yet
## Every kill this match (by another player), in order, as scored by the host:
## {seq, killer, victim, score, tags, streak, distance, weapon}. The same on every copy.
var kill_log: Array = []
## The match's best kills for the results screen, picked by the host (KillScore.best).
var highlights: Array = []
var _kill_seq := 0                     # host: kills so far this match
var _recent_kills: Dictionary = {}     # host: killer -> [Net.now() of their recent kills]
var _blow_flying := false              # host: the kick being dealt is a flying kick

## Deathmatch weapon pickups (see WeaponPickup), by their index in the map: the ones
## taken and not back yet. Every copy keeps this; the host decides it.
signal pickup_changed(index: int, taken: bool, by: int, weapon: String)
const PICKUP_RESPAWN := 10.0      ## seconds until a taken weapon is back
const PICKUP_REACH := 1.4         ## metres from the pickup to the player's middle
var pickups_taken: Dictionary = {}
var _pickup_timers: Dictionary = {}   # host: index -> seconds until it is back

## Deathmatch power-ups (see ItemPickup), by their index in the map: the ones taken
## and not back yet. Every copy keeps this; the host decides it.
signal item_changed(index: int, taken: bool, by: int)
## Uber health can take you this far past MAX_HEALTH (it does not wear off).
const MAX_OVERHEAL := 200.0
var items_taken: Dictionary = {}
var _item_timers: Dictionary = {}     # host: index -> seconds until it is back
## id -> seconds of double damage left (every copy counts it down; the host decides it).
var damage_boost: Dictionary = {}


func _ready() -> void:
	Net.match_started.connect(_on_match_started)
	Net.players_changed.connect(_on_players_changed)


func is_alive(id: int) -> bool:
	return health.get(id, MAX_HEALTH) > 0.0


func kills(id: int) -> int:
	return scores[id].kills if scores.has(id) else 0


func deaths(id: int) -> int:
	return scores[id].deaths if scores.has(id) else 0


# ---------------------------------------------------------------------------
# Starting

func _on_match_started() -> void:
	running = true
	if DevArgs.sync_log and KillcamMode.active():   # (every copy: the host's settings reach them all)
		print("KILLCAM_RULES %d %d %d" % [Net.my_id(), KillcamMode.target(), KillcamMode.minutes()])
	last_results = []
	kill_log.clear()
	highlights.clear()
	_pickup_timers.clear()
	_item_timers.clear()
	damage_boost.clear()
	if Net.is_host():
		pickups_taken.clear()   # (a late joiner keeps what the host told it; see _pickups_sync)
		items_taken.clear()
		if Net.is_deathmatch():
			for id in Net.players:
				Net.host_clear_inventory(id, false)   # everyone starts with empty hands
			Net._players_updated()
		# The host's lobby settings decide the win condition (dev options override them).
		var s: Dictionary = Net.match_settings
		if s.mode == "time":
			kill_target = 0
			time_left = float(s.minutes) * 60.0
		else:
			kill_target = int(s.kills)
			time_left = INF
		if DevArgs.kill_target > 0:
			kill_target = DevArgs.kill_target
		if DevArgs.time_limit > 0.0:
			time_left = DevArgs.time_limit
		if Maps.game_of(Net.map_id()) == "race":
			kill_target = 0   # a race ends at the finish (see Race), or at its time limit
			time_left = float(s.get("race_minutes", 10)) * 60.0 + Race.COUNTDOWN
			if DevArgs.time_limit > 0.0:
				time_left = DevArgs.time_limit
		if Game.mode == Game.Mode.PRACTICE:
			kill_target = 0
			time_left = INF
		elif GunGame.active():
			kill_target = 0   # it ends when someone gets through the ladder
			time_left = GunGame.TIME_LIMIT if DevArgs.time_limit <= 0.0 else DevArgs.time_limit
		elif KillcamMode.active():
			kill_target = 0   # it ends on points (KillcamMode.target()) or the clock
			time_left = KillcamMode.minutes() * 60.0 if DevArgs.time_limit <= 0.0 else DevArgs.time_limit
		elif Teams.active():
			kill_target = 0   # it ends on rounds or captures (see Teams), or the clock in Capture the Flag
			time_left = Teams.match_time()
		scores.clear()
		health.clear()
		respawn_timers.clear()
		respawn_asked.clear()
		_last_shot_time.clear()
		_last_slam_time.clear()
		_last_shove.clear()
		_last_kick_time.clear()
		_last_ground_slam.clear()
		_tethers.clear()
		_projectiles.clear()
		death_cause.clear()
		death_fx.clear()
		_kill_seq = 0
		_recent_kills.clear()
		for id in Net.players:
			scores[id] = {"kills": 0, "deaths": 0, "level": 0, "points": 0}
			health[id] = MAX_HEALTH
		_broadcast_state()
		_golden_own.clear()
		if GoldenGun.active():
			_host_give_golden(GoldenGun.pick_next(0), 0)   # a random player starts with it


func _on_players_changed() -> void:
	if not Net.is_host() or not running:
		return
	var changed := false
	for id in Net.players:
		if not scores.has(id):  # someone joined mid-match
			scores[id] = {"kills": 0, "deaths": 0, "level": 0, "points": 0}
			health[id] = MAX_HEALTH
			if Teams.no_respawn() and Teams.phase != Teams.Phase.OVER:
				health[id] = 0.0   # Search and Destroy: in from the next round
			changed = true
			if GunGame.active():
				Net.host_set_weapon(id, GunGame.weapon_at(0))
			elif KillcamMode.active():
				Net.host_set_weapon(id, KillcamMode.WEAPON)
			if Net.is_online and not Net.is_bot(id) and id != Net.my_id():
				_pickups_sync.rpc_id(id, pickups_taken.keys())   # which weapons are gone right now
				_items_sync.rpc_id(id, items_taken.keys(), damage_boost)
	for id in scores.keys():
		if not Net.players.has(id):
			scores.erase(id)
			health.erase(id)
			respawn_timers.erase(id)
			respawn_asked.erase(id)
			changed = true
	if changed:
		_broadcast_state()
	if GoldenGun.active() and not _golden_busy and GoldenGun.holder() == 0 and Net.players.size() > 0:
		_host_give_golden(GoldenGun.pick_next(0), 0)   # the holder left: someone else gets it


func _broadcast_state() -> void:
	_sync_state.rpc(kill_target, time_left, scores, health)


@rpc("authority", "call_local", "reliable")
func _sync_state(target: int, remaining: float, new_scores: Dictionary, new_health: Dictionary) -> void:
	kill_target = target
	time_left = remaining
	scores = new_scores
	health = new_health
	running = true
	state_changed.emit()


# ---------------------------------------------------------------------------
# Clock

func _process(delta: float) -> void:
	if not running:
		return
	time_left = max(time_left - delta, 0.0)
	for id in damage_boost.keys():
		damage_boost[id] -= delta
		if damage_boost[id] <= 0.0:
			damage_boost.erase(id)
	if not Net.is_host():
		return
	for id in respawn_timers.keys():
		respawn_timers[id] = maxf(respawn_timers[id] - delta, 0.0)
		if respawn_timers[id] <= 0.0 and (respawn_asked.has(id) or not respawn_needs_press(id)):
			respawn_timers.erase(id)
			respawn_asked.erase(id)
			_host_respawn(id)
	if Net.is_deathmatch():
		_host_pickups(delta)
		_host_items(delta)
	if time_left <= 0.0:
		host_end_match()


# ---------------------------------------------------------------------------
# Deathmatch weapon pickups. The host watches who walks over one, gives them the
# weapon and tells everyone the pickup is gone; PICKUP_RESPAWN seconds later it is back.

func _host_pickups(delta: float) -> void:
	for i in _pickup_timers.keys():
		_pickup_timers[i] -= delta
		if _pickup_timers[i] <= 0.0:
			_pickup_timers.erase(i)
			_pickup_state.rpc(i, false, 0, "")
	if Net.arena == null:
		return
	var pickups: Array = Net.arena.pickups
	for i in pickups.size():
		if pickups_taken.has(i):
			continue
		var pickup: WeaponPickup = pickups[i]
		for p in Net.arena.players_root.get_children():
			var player := p as Player
			if not player.alive or not is_alive(player.peer_id):
				continue
			if (player.global_position + Vector3(0, 0.9, 0)).distance_to(pickup.spot) > PICKUP_REACH:
				continue
			Net.host_give_weapon(player.peer_id, pickup.weapon)
			_pickup_timers[i] = PICKUP_RESPAWN
			_pickup_state.rpc(i, true, player.peer_id, pickup.weapon)
			break


@rpc("authority", "call_local", "reliable")
func _pickup_state(index: int, taken: bool, by: int, weapon: String) -> void:
	if taken:
		pickups_taken[index] = true
	else:
		pickups_taken.erase(index)
	pickup_changed.emit(index, taken, by, weapon)


@rpc("authority", "call_remote", "reliable")
func _pickups_sync(taken: Array) -> void:
	pickups_taken.clear()
	for i in taken:
		pickups_taken[int(i)] = true
		pickup_changed.emit(int(i), true, 0, "")


# ---------------------------------------------------------------------------
# Deathmatch power-ups (ItemPickup). Like the weapons: the host watches who walks
# over one, applies it and tells everyone it is gone until its respawn time is up.
# A health item stays put for someone who could not use it (full health).

func _host_items(delta: float) -> void:
	for i in _item_timers.keys():
		_item_timers[i] -= delta
		if _item_timers[i] <= 0.0:
			_item_timers.erase(i)
			_item_state.rpc(i, false, 0, health, {})
	if Net.arena == null:
		return
	var items: Array = Net.arena.items
	for i in items.size():
		if items_taken.has(i):
			continue
		var item: ItemPickup = items[i]
		for p in Net.arena.players_root.get_children():
			var player := p as Player
			if not player.alive or not is_alive(player.peer_id):
				continue
			if (player.global_position + Vector3(0, 0.9, 0)).distance_to(item.spot) > PICKUP_REACH:
				continue
			if not _host_apply_item(player.peer_id, item.kind):
				continue
			_item_timers[i] = ItemPickup.respawn_time(item.kind)
			var boost := {}
			if damage_boost.has(player.peer_id):
				boost[player.peer_id] = damage_boost[player.peer_id]
			_item_state.rpc(i, true, player.peer_id, health, boost)
			break


## Gives `id` what the item does; false if they cannot use it now (it stays).
func _host_apply_item(id: int, kind: String) -> bool:
	if kind == "damage":
		damage_boost[id] = ItemPickup.DAMAGE_BOOST_TIME
		return true
	var cap := MAX_OVERHEAL if ItemPickup.overheals(kind) else MAX_HEALTH
	var hp: float = health.get(id, MAX_HEALTH)
	if hp >= cap:
		return false
	health[id] = minf(hp + ItemPickup.heal_amount(kind), cap)
	return true


@rpc("authority", "call_local", "reliable")
func _item_state(index: int, taken: bool, by: int, new_health: Dictionary, boost: Dictionary) -> void:
	if taken:
		items_taken[index] = true
	else:
		items_taken.erase(index)
	health = new_health
	for id in boost:
		damage_boost[id] = boost[id]
	item_changed.emit(index, taken, by)
	state_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _items_sync(taken: Array, boost: Dictionary) -> void:
	items_taken.clear()
	damage_boost = boost
	for i in taken:
		items_taken[int(i)] = true
		item_changed.emit(int(i), true, 0)


## How much a hit from `shooter` is worth (double while they carry the damage boost).
func damage_multiplier(shooter: int) -> float:
	return ItemPickup.DAMAGE_BOOST_MULTIPLIER if damage_boost.has(shooter) else 1.0


# ---------------------------------------------------------------------------
# Shooting

## Called by the local player when it fires. `directions` holds one direction per
## pellet (one for most guns, ten for the shotgun). view_times maps each opponent's
## peer id to the moment (on that opponent's clock) this player was seeing them.
## Bots (simulated on the host) pass their own id as `shooter`. `aim`: where the
## crosshair was (before the spread; ZERO: the first direction), for killcams.
func request_shot(origin: Vector3, directions: PackedVector3Array, view_times: Dictionary, weapon_id: String, shooter: int = 0,
		aim: Vector3 = Vector3.ZERO) -> void:
	if Net.is_host():
		_host_shot(shooter if shooter != 0 else Net.my_id(), origin, directions, view_times, weapon_id, aim)
	else:
		_shot_request.rpc_id(1, origin, directions, view_times, weapon_id, aim)


@rpc("any_peer", "call_remote", "reliable")
func _shot_request(origin: Vector3, directions: PackedVector3Array, view_times: Dictionary, weapon_id: String, aim: Vector3) -> void:
	if Net.is_host():
		_host_shot(multiplayer.get_remote_sender_id(), origin, directions, view_times, weapon_id, aim)


func _host_shot(shooter: int, origin: Vector3, directions: PackedVector3Array, view_times: Dictionary, weapon_id: String,
		aim: Vector3 = Vector3.ZERO) -> void:
	if not running or not is_alive(shooter) or not Net.arena:
		return
	# The gun is the one the shooter took into the match, whatever the message says.
	weapon_id = Net.player_weapon(shooter)
	if weapon_id == "none" or WeaponData.melee(weapon_id):
		return   # Deathmatch: nothing in their hands (or a blade) can't shoot
	var weapon := WeaponData.by_id(weapon_id)
	var now := Net.now()
	# Fire rate check (a little slack for network timing).
	# (In game time: the debug menu can speed the game up offline.)
	if (now - _last_shot_time.get(shooter, -10.0)) * Engine.time_scale < weapon.shot_gap() * 0.7:
		return
	if weapon.is_melee() or weapon.is_projectile():
		return
	_last_shot_time[shooter] = now
	var shooter_node: Player = Net.arena.get_player(shooter)
	if shooter_node == null or directions.is_empty():
		return
	# The shot must start near where the host believes the shooter is.
	if origin.distance_to(shooter_node.latest_position() + Vector3(0, CameraRig.EYE_HEIGHT, 0)) > 3.0:
		return
	if directions.size() > weapon.pellets:
		directions = directions.slice(0, weapon.pellets)

	# Rewind each opponent once to what the shooter saw.
	var space := (Net.arena as Node3D).get_world_3d().direct_space_state
	var bodies := _rewound_bodies(shooter, view_times)   # [id, feet, height, facing yaw]
	var breaks := _breakables()

	var damage := {}   # target id -> total damage of this shot
	var heads := {}    # target id -> a pellet hit the head
	var shove := {}    # target id -> knockback of this shot (each pellet pushes along its path)
	var dirs := {}     # target id -> the way a pellet that hit them was going
	var ends := PackedVector3Array()
	var hit_mask := 0
	var log := []
	var vias := []     # per pellet: where it went into and came out of portals (Portals.path_bends)
	var portals: Portals = Net.arena.get("portals")   # (a test's stand-in arena may have none)
	for i in directions.size():
		var direction := directions[i].normalized()
		# Its path: to where it hits the level, through any portals on the way (each
		# leg after a portal starts out of the other one, turned to match).
		var legs: Array = portals.shot_path(space, origin, direction, weapon.max_range, 1) if portals \
			else [{"a": origin, "b": origin + direction * weapon.max_range, "dir": direction,
				"hit": space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + direction * weapon.max_range, 1))}]   # layer 1: level only
		var last: Dictionary = legs[legs.size() - 1]
		var world_hit: Dictionary = last.hit
		var end: Vector3 = last.b
		vias.append(Portals.path_bends(legs))
		var wall_cell := -1
		if world_hit and breaks:
			wall_cell = breaks.cell_at(world_hit.collider, world_hit.position, world_hit.normal)
		var travelled := 0.0   # along the legs before this one (damage falls off with the whole way)
		if weapon.pierce:   # the railgun: everyone along the line
			for leg in legs:
				var dir: Vector3 = leg.dir
				for bb in bodies:
					var hit := _ray_body(leg.a, leg.b, bb)
					if hit.is_empty():
						continue
					hit_mask |= 1 << i
					var dmg := weapon.damage_at(travelled + hit.dist) * (weapon.headshot_multiplier if hit.head else 1.0)
					damage[bb[0]] = damage.get(bb[0], 0.0) + dmg
					shove[bb[0]] = shove.get(bb[0], Vector3.ZERO) \
						+ Vector3(dir.x, 0.0, dir.z).normalized() * weapon.knockback + Vector3.UP * weapon.knockback_up
					heads[bb[0]] = heads.get(bb[0], false) or hit.head
					dirs[bb[0]] = dir
					if DevArgs.sync_log:
						log.append("hit %d at %.2f m%s" % [bb[0], hit.height, " head" if hit.head else ""])
				travelled += (leg.a as Vector3).distance_to(leg.b)
			if wall_cell >= 0:
				breaks.damage(wall_cell, weapon.damage_at(travelled) * weapon.structure_damage)
			ends.append(end)
			continue
		# The nearest opponent the pellet passes through, leg by leg.
		var best_target := 0
		var best_dist := INF
		var best_point := end
		var best_head := false
		var best_height := 0.0
		var best_dir := direction
		for leg in legs:
			var la: Vector3 = leg.a
			var lb: Vector3 = leg.b
			for bb in bodies:
				var feet: Vector3 = bb[1]
				var height: float = bb[2]
				var r := Player.CAPSULE_RADIUS + HIT_FORGIVENESS
				var a := feet + Vector3(0, Player.CAPSULE_RADIUS, 0)
				var top := feet + Vector3(0, height - Player.CAPSULE_RADIUS, 0)
				var pts := Geometry3D.get_closest_points_between_segments(la, lb, a, top)
				if pts[0].distance_to(pts[1]) <= r:
					var d := travelled + la.distance_to(pts[0])
					if d < best_dist:
						best_dist = d
						best_target = bb[0]
						best_point = pts[0]
						best_height = pts[0].y - feet.y
						best_head = best_height >= height - (Player.CAPSULE_HEIGHT - HEAD_HEIGHT)
						best_dir = leg.dir
			if best_target != 0:
				# Hit on this leg: the path stops here (the portals after it are not reached).
				var cut := legs.find(leg)
				vias[i] = Portals.path_bends(legs.slice(0, cut + 1))
				break
			travelled += la.distance_to(lb)
		if best_target != 0:
			end = best_point
			hit_mask |= 1 << i
			var dmg := weapon.damage_at(best_dist) * (weapon.headshot_multiplier if best_head else 1.0)
			damage[best_target] = damage.get(best_target, 0.0) + dmg
			shove[best_target] = shove.get(best_target, Vector3.ZERO) \
				+ Vector3(best_dir.x, 0.0, best_dir.z).normalized() * weapon.knockback + Vector3.UP * weapon.knockback_up
			heads[best_target] = heads.get(best_target, false) or best_head
			dirs[best_target] = best_dir
		elif wall_cell >= 0:
			breaks.damage(wall_cell, weapon.damage_at(travelled) * weapon.structure_damage)
		ends.append(end)
		if DevArgs.sync_log:
			log.append(("hit %d at %.2f m%s" % [best_target, best_height, " head" if best_head else ""]) if best_target else "miss")
	if aim.length_squared() < 0.0001:
		aim = directions[0]
	_shot_effect.rpc(shooter, origin, ends, hit_mask, aim.normalized(), vias)
	_flush_breaks()
	for id in damage:
		if is_dummy(id):
			_host_dummy_damage(shooter, id, damage[id], heads[id])
		else:
			_host_damage(shooter, id, damage[id], heads[id], "", {"with": weapon.id, "push": shove[id], "dir": dirs[id]})
			_host_shove(shooter, id, shove[id], weapon.id)
	if DevArgs.sync_log:
		# One line per shot (the first pellet that hit, if any), then the gun and its pellets.
		var first := "miss"
		for entry in log:
			if entry != "miss":
				first = entry
				break
		print("SHOT %d %s" % [shooter, first])
		print("PELLETS %d %s %d/%d" % [shooter, weapon_id, log.size() - log.count("miss"), log.size()])


## Where a ray from `origin` to `end` passes through body `b` ([id, feet, height, yaw]):
## {dist, height, head}, or {} if it misses.
func _ray_body(origin: Vector3, end: Vector3, b: Array) -> Dictionary:
	var feet: Vector3 = b[1]
	var height: float = b[2]
	var r := Player.CAPSULE_RADIUS + HIT_FORGIVENESS
	var pts := Geometry3D.get_closest_points_between_segments(origin, end,
		feet + Vector3(0, Player.CAPSULE_RADIUS, 0), feet + Vector3(0, height - Player.CAPSULE_RADIUS, 0))
	if pts[0].distance_to(pts[1]) > r:
		return {}
	var h: float = pts[0].y - feet.y
	return {"dist": origin.distance_to(pts[0]), "height": h, "head": h >= height - (Player.CAPSULE_HEIGHT - HEAD_HEIGHT)}


# ---------------------------------------------------------------------------
# Rockets and grenades (WeaponData.Kind.PROJECTILE). The host flies each one (the
# same path everyone draws), and decides where it blows up and who it hurts.

## Called by the local player (or a bot) when it fires a rocket or grenade: from the
## eyes, toward where it aims.
func request_projectile(origin: Vector3, direction: Vector3, shooter: int = 0) -> void:
	if Net.is_host():
		_host_projectile(shooter if shooter != 0 else Net.my_id(), origin, direction)
	else:
		_projectile_request.rpc_id(1, origin, direction)


@rpc("any_peer", "call_remote", "reliable")
func _projectile_request(origin: Vector3, direction: Vector3) -> void:
	if Net.is_host():
		_host_projectile(multiplayer.get_remote_sender_id(), origin, direction)


func _host_projectile(shooter: int, origin: Vector3, direction: Vector3) -> void:
	if not running or not is_alive(shooter) or not Net.arena or Race.active or direction.length_squared() < 0.0001:
		return
	var weapon := WeaponData.by_id(Net.player_weapon(shooter))
	if not weapon.is_projectile():
		return
	var now := Net.now()
	if (now - _last_shot_time.get(shooter, -10.0)) * Engine.time_scale < weapon.fire_interval * 0.7:
		return
	var who: Player = Net.arena.get_player(shooter)
	if who == null or origin.distance_to(who.latest_position() + Vector3(0, CameraRig.EYE_HEIGHT, 0)) > 3.0:
		return
	_last_shot_time[shooter] = now
	direction = direction.normalized()
	var id := _next_projectile
	_next_projectile += 1
	_projectiles[id] = {"pos": origin, "vel": direction * weapon.projectile_speed, "shooter": shooter,
		"weapon": weapon.id, "t": 0.0}
	if DevArgs.sync_log:
		print("PROJECTILE %d %s %d" % [shooter, weapon.id, id])
	_projectile_spawn.rpc(id, shooter, weapon.id, origin, direction)


@rpc("authority", "call_local", "reliable")
func _projectile_spawn(id: int, shooter: int, weapon_id: String, origin: Vector3, direction: Vector3) -> void:
	projectile_fired.emit(id, shooter, weapon_id, origin, direction)


func _physics_process(delta: float) -> void:
	if _projectiles.is_empty() or not Net.is_host():
		return
	if not running or Net.arena == null:
		_projectiles.clear()
		return
	var space := (Net.arena as Node3D).get_world_3d().direct_space_state
	for id in _projectiles.keys():
		var p: Dictionary = _projectiles[id]
		var w := WeaponData.by_id(p.weapon)
		var from: Vector3 = p.pos
		var vel: Vector3 = p.vel
		vel.y -= w.projectile_gravity * delta
		var to := from + vel * delta
		p.vel = vel
		p.t += delta
		# Into someone (not the shooter: it leaves from inside them)?
		var direct := 0
		var head := false
		var at := to
		var best := INF
		for b in _live_bodies(p.shooter, true):
			var pts := Geometry3D.get_closest_points_between_segments(from, to,
				b[1] + Vector3(0, Player.CAPSULE_RADIUS, 0), b[1] + Vector3(0, b[2] - Player.CAPSULE_RADIUS, 0))
			if pts[0].distance_to(pts[1]) <= Player.CAPSULE_RADIUS + 0.12:
				var d := from.distance_to(pts[0])
				if d < best:
					best = d
					direct = b[0]
					at = pts[0]
					head = pts[0].y - b[1].y >= b[2] - (Player.CAPSULE_HEIGHT - HEAD_HEIGHT)
		var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
		# Into a portal before anything else: out of the other one, turned to match
		# (Projectile flies its look through the same way on every copy).
		var gates: Portals = Net.arena.get("portals")   # (a test's stand-in arena may have none)
		var gate: Dictionary = gates.crossing(from, to) if gates else {}
		if gate and from.distance_to(gate.at) < best and (not wall or from.distance_to(gate.at) <= from.distance_to(wall.position) + 0.05):
			var through := Projectile.through_portal(gate, from, to, p.vel)
			p.pos = through[0]
			p.vel = through[1]
			continue
		if wall and from.distance_to(wall.position) < best:
			_host_explode(id, wall.position + wall.normal * 0.05, 0, wall.collider, wall.normal)
		elif direct != 0:
			_host_explode(id, at, direct, null, Vector3.UP, head)
		elif p.t >= w.fuse:
			_host_explode(id, to, 0)
		else:
			p.pos = to


## Everyone alive who can be hit, where they are now: [id, feet, height]. Not `except`
## (nor, with `allies_too`, anyone on their team).
func _live_bodies(except: int = 0, allies_too: bool = false) -> Array:
	var out := []
	for id in Net.players:
		if id == except or not is_alive(id) or (allies_too and Teams.same_team(except, id)):
			continue
		var p: Player = Net.arena.get_player(id)
		if p:
			out.append([id, p.latest_position(), Player.height_for_pose(p.pose_at(p.latest_time()))])
	for d in Net.arena.dummies:
		if not (d as TargetDummy).is_down():
			out.append([dummy_id(d.index), d.global_position, Player.CAPSULE_HEIGHT])
	return out


## `head`: a direct hit to the head (a crossbow bolt or a nail does the weapon's headshot damage).
## A dart (not WeaponData.explosive) hurts only whoever it hit directly.
func _host_explode(id: int, at: Vector3, direct: int, collider: Object = null, normal: Vector3 = Vector3.UP, head: bool = false) -> void:
	var p: Dictionary = _projectiles.get(id, {})
	_projectiles.erase(id)
	if p.is_empty():
		return
	var w := WeaponData.by_id(p.weapon)
	var shooter: int = p.shooter
	_projectile_boom.rpc(id, at, w.id)
	var space := (Net.arena as Node3D).get_world_3d().direct_space_state
	var hits := []   # [id, damage, shove]
	for b in _live_bodies():
		var feet: Vector3 = b[1]
		var near := Geometry3D.get_closest_point_to_segment(at, feet + Vector3(0, Player.CAPSULE_RADIUS, 0),
			feet + Vector3(0, b[2] - Player.CAPSULE_RADIUS, 0))
		if not w.explosive and b[0] != direct:
			continue
		if Teams.same_team(shooter, b[0]):
			continue   # no blast damage or shove for teammates
		var d := 0.0 if b[0] == direct else maxf(at.distance_to(near) - Player.CAPSULE_RADIUS, 0.0)
		if d > w.splash_radius:
			continue
		if b[0] != direct and not space.intersect_ray(PhysicsRayQueryParameters3D.create(at, near, 1)).is_empty():
			continue   # behind a wall
		var f := 1.0 if d <= w.splash_inner else clampf(1.0 - (d - w.splash_inner) / (w.splash_radius - w.splash_inner), 0.0, 1.0)
		var dmg := w.damage * f * (w.self_damage if b[0] == shooter else 1.0)
		if b[0] == direct and head:
			dmg *= w.headshot_multiplier
		var away := feet + Vector3(0, b[2] * 0.5, 0) - at
		away = away.normalized() if away.length_squared() > 0.0001 else Vector3.UP
		hits.append([b[0], dmg, away * w.knockback * f + Vector3.UP * w.knockback_up * f, away, f if w.explosive else 0.0])
	if DevArgs.sync_log:
		print("BOOM %d %s %d hit %d" % [shooter, w.id, direct, hits.size()])
	var breaks := _breakables()
	if breaks and collider:
		breaks.damage(breaks.cell_at(collider, at - normal * 0.05, normal), w.damage * w.structure_damage)
		_flush_breaks()
	for h in hits:
		if is_dummy(h[0]):
			_host_dummy_damage(shooter, h[0], h[1], false)
		else:
			if h[1] >= 1.0:
				var blow := {"with": w.id, "push": h[2], "dir": h[3], "blast": h[4]}
				if w.explosive:
					blow["at"] = at
				_host_damage(shooter, h[0], h[1], false, "", blow)
			_host_shove(shooter, h[0], h[2], w.id)


@rpc("authority", "call_local", "reliable")
func _projectile_boom(id: int, at: Vector3, weapon_id: String) -> void:
	exploded.emit(id, at, weapon_id)


## Everyone `attacker` could hit, each moved back to where `attacker` saw them:
## [id, feet, height, facing yaw]. Target dummies stand still: no rewind needed.
func _rewound_bodies(attacker: int, view_times: Dictionary) -> Array:
	var bodies := []
	for id in Net.players:
		if id == attacker or not is_alive(id) or Teams.same_team(attacker, id):
			continue   # (shots pass through teammates)
		var target: Player = Net.arena.get_player(id)
		if target == null:
			continue
		var when := _clamped_view_time(target, view_times.get(id, -1.0))
		bodies.append([id, target.position_at(when), Player.height_for_pose(target.pose_at(when)), target.yaw_at(when)])  # shorter when crouched
	for d in Net.arena.dummies:
		if not (d as TargetDummy).is_down():
			bodies.append([dummy_id(d.index), d.global_position, Player.CAPSULE_HEIGHT, d.rotation.y])
	return bodies


# ---------------------------------------------------------------------------
# Melee

## Called by the local player when a swing lands: from the eyes, toward where it
## looks. Like a shot, it says when it was seeing each opponent. `charge`: how wound
## up the swing was, 0 (a tap) to 1 (a full wind-up).
func request_melee(origin: Vector3, direction: Vector3, view_times: Dictionary, charge: float, attacker: int = 0) -> void:
	if Net.is_host():
		_host_melee(attacker if attacker != 0 else Net.my_id(), origin, direction, view_times, charge)
	else:
		_melee_request.rpc_id(1, origin, direction, view_times, charge)


@rpc("any_peer", "call_remote", "reliable")
func _melee_request(origin: Vector3, direction: Vector3, view_times: Dictionary, charge: float) -> void:
	if Net.is_host():
		_host_melee(multiplayer.get_remote_sender_id(), origin, direction, view_times, charge)


func _host_melee(attacker: int, origin: Vector3, direction: Vector3, view_times: Dictionary, charge: float) -> void:
	if not running or not is_alive(attacker) or not Net.arena or Race.active:
		return
	if Net.player_weapon(attacker) == "none":
		return
	var weapon := WeaponData.by_id(Net.player_weapon(attacker))
	if not weapon.is_melee() or direction.length_squared() < 0.0001:
		return
	var now := Net.now()
	var since: float = (now - _last_shot_time.get(attacker, -10.0)) * Engine.time_scale
	if since < weapon.fire_interval * 0.7:
		return
	_last_shot_time[attacker] = now
	var who: Player = Net.arena.get_player(attacker)
	if who == null or origin.distance_to(who.latest_position() + Vector3(0, CameraRig.EYE_HEIGHT, 0)) > 3.0:
		return
	# Nobody can have wound up for longer than it has been since their last swing.
	charge = clampf(charge, 0.0, weapon.charge_of(since)) if is_finite(charge) else 0.0
	var blow := weapon.melee_damage(charge)
	var push: Array = weapon.melee_knockback(charge)
	direction = direction.normalized()
	var space := (Net.arena as Node3D).get_world_3d().direct_space_state
	var points := PackedVector3Array()
	var hits := []   # [id, damage, shove]
	for b in _rewound_bodies(attacker, view_times):
		var feet: Vector3 = b[1]
		var height: float = b[2]
		var a := feet + Vector3(0, Player.CAPSULE_RADIUS, 0)
		var top := feet + Vector3(0, height - Player.CAPSULE_RADIUS, 0)
		var near := Geometry3D.get_closest_point_to_segment(origin, a, top)
		var to := near - origin
		var reach := maxf(to.length() - Player.CAPSULE_RADIUS, 0.0)
		if reach > weapon.max_range:
			continue
		# In front: within the arc of where you look (anyone touching you counts too).
		if to.length() > Player.CAPSULE_RADIUS * 2.0 and rad_to_deg(direction.angle_to(to)) > weapon.arc_degrees:
			continue
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, near, 1)).is_empty():
			continue   # a wall in the way
		var dmg := blow
		var flat := Vector3(to.x, 0.0, to.z)
		flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3(direction.x, 0.0, direction.z).normalized()
		# From behind: the blow goes the same way they face.
		var facing := Vector3.FORWARD.rotated(Vector3.UP, b[3])
		if weapon.backstab_multiplier > 1.0 and facing.dot(flat) > 0.5:
			dmg *= weapon.backstab_multiplier
		hits.append([b[0], dmg, flat * push[0] + Vector3.UP * push[1], flat])
		points.append(near.lerp(origin, Player.CAPSULE_RADIUS / maxf(to.length(), 0.01)))
	if DevArgs.sync_log:
		print("MELEE %d %s %d charge %.2f" % [attacker, weapon.id, hits.size(), charge])
		# Also a SHOT line like a gun's, so the tests count blows as shots and hits.
		print("SHOT %d %s" % [attacker, ("hit %d at melee" % hits[0][0]) if not hits.is_empty() else "miss"])
	_melee_effect.rpc(attacker, weapon.id, points)
	# The blow also lands on a breakable wall or floor right in front.
	var breaks := _breakables()
	if breaks:
		var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + direction * (weapon.max_range + 0.5), 1))
		if wall:
			breaks.damage(breaks.cell_at(wall.collider, wall.position, wall.normal), blow * weapon.structure_damage)
			_flush_breaks()
	for h in hits:
		if is_dummy(h[0]):
			_host_dummy_damage(attacker, h[0], h[1], false)
		else:
			_host_damage(attacker, h[0], h[1], false, "", {"with": weapon.id, "push": h[2], "dir": h[3]})
			_host_shove(attacker, h[0], h[2], weapon.id)


# ---------------------------------------------------------------------------
# Ground slams (see GroundSlam)

## Called by the local player (or a bot) when its ground slam lands at `at` (its feet),
## wound up `charge` 0..1 and having fallen `fell` metres.
func request_ground_slam(at: Vector3, view_times: Dictionary, charge: float, fell: float, attacker: int = 0) -> void:
	if Net.is_host():
		_host_ground_slam(attacker if attacker != 0 else Net.my_id(), at, view_times, charge, fell)
	else:
		_ground_slam_request.rpc_id(1, at, view_times, charge, fell)


@rpc("any_peer", "call_remote", "reliable")
func _ground_slam_request(at: Vector3, view_times: Dictionary, charge: float, fell: float) -> void:
	if Net.is_host():
		_host_ground_slam(multiplayer.get_remote_sender_id(), at, view_times, charge, fell)


func _host_ground_slam(attacker: int, at: Vector3, view_times: Dictionary, charge: float, fell: float) -> void:
	if not running or not is_alive(attacker) or not Net.arena or Race.active:
		return
	if Net.player_weapon(attacker) == "none":
		return
	var weapon := WeaponData.by_id(Net.player_weapon(attacker))
	if not weapon.is_melee() or not at.is_finite():
		return
	var now := Net.now()
	if (now - _last_ground_slam.get(attacker, -10.0)) * Engine.time_scale < GroundSlam.COOLDOWN * 0.7:
		return
	var who: Player = Net.arena.get_player(attacker)
	if who == null or at.distance_to(who.latest_position()) > 4.0:
		return
	# Nobody can have wound up for longer than it has been since their last swing.
	var since: float = (now - _last_shot_time.get(attacker, -10.0)) * Engine.time_scale
	charge = clampf(charge, 0.0, weapon.charge_of(since)) if is_finite(charge) else 0.0
	fell = clampf(fell, 0.0, 60.0) if is_finite(fell) else 0.0
	_last_ground_slam[attacker] = now
	_last_shot_time[attacker] = now
	var blow := GroundSlam.damage(weapon, charge, fell)
	var centre := at + Vector3(0, 0.6, 0)
	var facing := Vector3.FORWARD.rotated(Vector3.UP, who.yaw_at(now))
	var space := (Net.arena as Node3D).get_world_3d().direct_space_state
	var points := PackedVector3Array()
	var hits := []   # [id, damage, shove]
	for b in _rewound_bodies(attacker, view_times):
		var feet: Vector3 = b[1]
		var height: float = b[2]
		if feet.y - at.y > GroundSlam.ABOVE:
			continue
		var low := feet + Vector3(0, Player.CAPSULE_RADIUS, 0)
		var near := Geometry3D.get_closest_point_to_segment(centre, low, feet + Vector3(0, height - Player.CAPSULE_RADIUS, 0))
		var part := GroundSlam.share(maxf(centre.distance_to(near) - Player.CAPSULE_RADIUS, 0.0))
		if part <= 0.0:
			continue
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(centre, near, 1)).is_empty():
			continue   # a wall in the way
		var away := Vector3(feet.x - at.x, 0.0, feet.z - at.z)
		away = away.normalized() if away.length_squared() > 0.04 else facing   # right under you: the way you face
		var push := GroundSlam.shove(weapon, charge, fell, part)
		hits.append([b[0], blow * part, away * push[0] + Vector3.UP * push[1], away])
		points.append(near)
	if DevArgs.sync_log:
		print("GROUND_SLAM %d %s %d charge %.2f fell %.1f" % [attacker, weapon.id, hits.size(), charge, fell])
	_ground_slam_effect.rpc(attacker, weapon.id, at, GroundSlam.power(weapon, charge, fell), points)
	# Wound up enough, it goes through a floor that can break.
	var breaks := _breakables()
	if breaks and GroundSlam.breaks_floor(weapon, charge):
		var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.5, 0), at - Vector3(0, 0.6, 0), 1))
		if floor_hit:
			breaks.damage(breaks.cell_at(floor_hit.collider, floor_hit.position, floor_hit.normal), 100000.0)
			_flush_breaks()
	for h in hits:
		if is_dummy(h[0]):
			_host_dummy_damage(attacker, h[0], h[1], false)
		else:
			_host_damage(attacker, h[0], h[1], false, "", {"with": weapon.id, "push": h[2], "dir": h[3]})
			_host_shove(attacker, h[0], h[2], weapon.id)


@rpc("authority", "call_local", "unreliable")
func _ground_slam_effect(attacker: int, weapon_id: String, at: Vector3, power: float, points: PackedVector3Array) -> void:
	ground_slammed.emit(attacker, weapon_id, at, power, points)


# ---------------------------------------------------------------------------
# Kicks (see Kick): everyone has one, whatever they carry

## Called by the local player (or a bot) when a kick lands: from the eyes, toward
## where it looks (a flying kick: toward who it is flying at).
func request_kick(origin: Vector3, direction: Vector3, view_times: Dictionary, flying: bool, attacker: int = 0) -> void:
	if Net.is_host():
		_host_kick(attacker if attacker != 0 else Net.my_id(), origin, direction, view_times, flying)
	else:
		_kick_request.rpc_id(1, origin, direction, view_times, flying)


@rpc("any_peer", "call_remote", "reliable")
func _kick_request(origin: Vector3, direction: Vector3, view_times: Dictionary, flying: bool) -> void:
	if Net.is_host():
		_host_kick(multiplayer.get_remote_sender_id(), origin, direction, view_times, flying)


func _host_kick(attacker: int, origin: Vector3, direction: Vector3, view_times: Dictionary, flying: bool) -> void:
	if not running or not is_alive(attacker) or not Net.arena or Race.active or direction.length_squared() < 0.0001:
		return
	var now := Net.now()
	if (now - _last_kick_time.get(attacker, -10.0)) * Engine.time_scale < Kick.COOLDOWN * 0.7:
		return
	if flying:
		# Only straight after hooking someone.
		var tether: Array = _tethers.get(attacker, [])
		if tether.is_empty() or now - float(tether[1]) > Kick.FLYING_WINDOW:
			flying = false
		else:
			_tethers.erase(attacker)
	_last_kick_time[attacker] = now
	var who: Player = Net.arena.get_player(attacker)
	if who == null or origin.distance_to(who.latest_position() + Vector3(0, CameraRig.EYE_HEIGHT, 0)) > (6.0 if flying else 3.0):
		return
	direction = direction.normalized()
	var reach := Kick.FLYING_REACH if flying else Kick.REACH
	var arc := Kick.FLYING_ARC if flying else Kick.ARC
	var space := (Net.arena as Node3D).get_world_3d().direct_space_state
	var points := PackedVector3Array()
	var hits := []   # [id, damage, shove]
	for b in _rewound_bodies(attacker, view_times):
		var feet: Vector3 = b[1]
		var height: float = b[2]
		var near := Geometry3D.get_closest_point_to_segment(origin,
			feet + Vector3(0, Player.CAPSULE_RADIUS, 0), feet + Vector3(0, height - Player.CAPSULE_RADIUS, 0))
		var to := near - origin
		if maxf(to.length() - Player.CAPSULE_RADIUS, 0.0) > reach:
			continue
		if to.length() > Player.CAPSULE_RADIUS * 2.0 and rad_to_deg(direction.angle_to(to)) > arc:
			continue
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, near, 1)).is_empty():
			continue   # a wall in the way
		var flat := Vector3(direction.x, 0.0, direction.z) if flying else Vector3(to.x, 0.0, to.z)
		flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3(direction.x, 0.0, direction.z).normalized()
		# Faster into them than they are moving away = a harder shove.
		var victim: Player = Net.arena.get_player(b[0])
		var their_vel := victim.latest_velocity() if victim else Vector3.ZERO
		var closing := maxf((who.latest_velocity() - their_vel).dot(flat), 0.0)
		var boost := minf(1.0 + closing * Kick.SPEED_KNOCKBACK, Kick.SPEED_MAX)
		var shove := flat * (Kick.FLYING_KNOCKBACK if flying else Kick.KNOCKBACK) * boost \
			+ Vector3.UP * (Kick.FLYING_KNOCKBACK_UP if flying else Kick.KNOCKBACK_UP)
		hits.append([b[0], Kick.FLYING_DAMAGE if flying else Kick.DAMAGE, shove, flat])
		points.append(near.lerp(origin, Player.CAPSULE_RADIUS / maxf(to.length(), 0.01)))
	if DevArgs.sync_log:
		print("KICK %d %s %d" % [attacker, "flying" if flying else "front", hits.size()])
	var kind := "flying_kick" if flying else "kick"
	_melee_effect.rpc(attacker, kind, points)
	var breaks := _breakables()
	if breaks:
		var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + direction * (reach + 0.5), 1))
		if wall:
			var dmg := (Kick.FLYING_DAMAGE if flying else Kick.DAMAGE) * Kick.STRUCTURE
			breaks.damage(breaks.cell_at(wall.collider, wall.position, wall.normal), dmg)
			_flush_breaks()
	_blow_flying = flying
	for h in hits:
		if is_dummy(h[0]):
			_host_dummy_damage(attacker, h[0], h[1], false)
		else:
			_host_damage(attacker, h[0], h[1], false, "kick", {"with": kind, "push": h[2], "dir": h[3]})
			_host_shove(attacker, h[0], h[2], kind)
	_blow_flying = false


# ---------------------------------------------------------------------------
# Hooking another player: the rope reels you both together

## Called by the local player (or a bot) when its hook catches player `target`
## (on = true) or lets go of them (on = false).
func request_tether(target: int, on: bool, by: int = 0) -> void:
	if Net.is_host():
		_host_tether(by if by != 0 else Net.my_id(), target, on)
	else:
		_tether_request.rpc_id(1, target, on)


@rpc("any_peer", "call_remote", "reliable")
func _tether_request(target: int, on: bool) -> void:
	if Net.is_host():
		_host_tether(multiplayer.get_remote_sender_id(), target, on)


func _host_tether(by: int, target: int, on: bool) -> void:
	if not Net.players.has(target) or target == by or not Net.arena:
		return
	if on:
		if not running or Race.active or not is_alive(by) or not is_alive(target) or Teams.same_team(by, target):
			return
		var a: Player = Net.arena.get_player(by)
		var b: Player = Net.arena.get_player(target)
		if a == null or b == null or a.latest_position().distance_to(b.latest_position()) > 60.0:
			return
		_tethers[by] = [target, Net.now()]
		_last_shove[target] = [by, Net.now(), "rope"]   # reeled into a wall: that's their doing
	if DevArgs.sync_log:
		print("TUG %d %d %s" % [by, target, "on" if on else "off"])
	if target == Net.my_id() or Net.is_bot(target):
		_apply_tug(target, by, on)
	else:
		_tug.rpc_id(target, target, by, on)


@rpc("authority", "call_remote", "reliable")
func _tug(target: int, by: int, on: bool) -> void:
	_apply_tug(target, by, on)


func _apply_tug(target: int, by: int, on: bool) -> void:
	var p: Player = Net.arena.get_player(target) if Net.arena else null
	if p and p.is_local:
		if on and target == Net.my_id() and Cheats.god_mode():
			return
		p.tug(by, on)


@rpc("authority", "call_local", "unreliable")
func _melee_effect(attacker: int, weapon_id: String, points: PackedVector3Array) -> void:
	melee_landed.emit(attacker, weapon_id, points)


# ---------------------------------------------------------------------------
# Breakable walls and floors (see MapDestruction). The host damages them; everyone
# is told which pieces cracked or broke.

func _breakables() -> MapDestruction:
	if Net.arena == null or Race.active:
		return null
	var layout: MapRoot = Net.arena.get("layout")
	return layout.destruction if layout else null


func _flush_breaks() -> void:
	var d := _breakables()
	if d == null:
		return
	var changed := d.flush()
	if changed.is_empty():
		return
	_breaks.rpc(changed[0], changed[1])
	if DevArgs.sync_log:
		var broke := 0
		for s in (changed[1] as PackedByteArray):
			if s >= MapDestruction.BROKEN:
				broke += 1
		print("BREAK %d cells changed, %d broken" % [(changed[0] as PackedInt32Array).size(), broke])


@rpc("authority", "call_local", "reliable")
func _breaks(cells: PackedInt32Array, stages: PackedByteArray) -> void:
	var d := _breakables()
	if d:
		d.apply(cells, stages)
		if DevArgs.sync_log:
			print("BROKEN_STATE %s" % d.state_key())


## A copy that has just built the arena asks the host what is already broken.
func request_breaks() -> void:
	if not Net.is_host():
		_breaks_request.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _breaks_request() -> void:
	var d := _breakables()
	if Net.is_host() and d:
		var all := d.snapshot()
		_breaks.rpc_id(multiplayer.get_remote_sender_id(), all[0], all[1])


# ---------------------------------------------------------------------------
# Knockback and crashing into walls

## Push `target` (a player, not a dummy). Movement is run by whoever plays that
## player, so the push goes to them: you, a friend, or one of the host's bots.
## `with`: what did the shove (see death_fx), so a crash it causes is credited to it.
func _host_shove(attacker: int, target: int, push: Vector3, with: String = "") -> void:
	if push.length_squared() < 0.01 or not is_alive(target) or not Net.players.has(target) or Teams.same_team(attacker, target):
		return
	if target == Net.my_id() and Cheats.god_mode():
		return
	_last_shove[target] = [attacker, Net.now(), with]
	if target == Net.my_id() or Net.is_bot(target):
		_apply_shove(target, push)
	else:
		_shove.rpc_id(target, target, push)


@rpc("authority", "call_remote", "reliable")
func _shove(target: int, push: Vector3) -> void:
	_apply_shove(target, push)


func _apply_shove(target: int, push: Vector3) -> void:
	var p: Player = Net.arena.get_player(target) if Net.arena else null
	if p and p.is_local and p.alive:
		p.knock(push)


## The local player (or a bot) hit a wall at `speed` m/s.
func request_slam(speed: float, where: Vector3, id: int = 0) -> void:
	if Net.is_host():
		_host_slam(id if id != 0 else Net.my_id(), speed, where)
	else:
		_slam_request.rpc_id(1, speed, where)


@rpc("any_peer", "call_remote", "reliable")
func _slam_request(speed: float, where: Vector3) -> void:
	if Net.is_host():
		_host_slam(multiplayer.get_remote_sender_id(), speed, where)


func _host_slam(id: int, speed: float, where: Vector3) -> void:
	if not running or not is_alive(id) or Race.active or speed < SLAM_SPEED:
		return
	var now := Net.now()
	if now - _last_slam_time.get(id, -10.0) < 0.5:
		return
	_last_slam_time[id] = now
	var amount := minf((minf(speed, 90.0) - SLAM_SPEED) * SLAM_DAMAGE, SLAM_MAX)
	# Shoved into it? Then whoever shoved you gets the hit (and the kill).
	var by := id
	var with := ""   # what threw them into it (see death_fx)
	var shove: Array = _last_shove.get(id, [])
	if not shove.is_empty() and now - float(shove[1]) <= SHOVE_CREDIT and Net.players.has(shove[0]):
		by = shove[0]
		with = str(shove[2]) if shove.size() > 2 else ""
	_slam_effect.rpc(id, where, speed)
	if DevArgs.sync_log:
		print("SLAM %d %.1f m/s %.0f damage by %d" % [id, speed, amount, by])
	if amount >= 1.0:
		_host_damage(by, id, amount, false, "slam", {"with": with})


@rpc("authority", "call_local", "unreliable")
func _slam_effect(id: int, where: Vector3, speed: float) -> void:
	slammed.emit(id, where, speed)


## Keeps the rewind within limits so a slow or dishonest client cannot shoot far into the past.
func _clamped_view_time(target: Player, t: float) -> float:
	var newest := target.latest_time()
	if t < 0.0:
		return newest
	return clamp(t, newest - MAX_REWIND, newest)


@rpc("authority", "call_local", "unreliable")
func _shot_effect(shooter: int, muzzle: Vector3, ends: PackedVector3Array, hit_mask: int, aim: Vector3, vias: Array) -> void:
	shot_aimed.emit(shooter, muzzle, aim)
	var hits := []
	for i in ends.size():
		hits.append(hit_mask & (1 << i) != 0)
	shot_fired.emit(shooter, muzzle, ends, hits, vias)


# ---------------------------------------------------------------------------
# Damage, death, respawn (host decides, everyone is told)

## `blow`: what the hit was, for death_fx if it kills: {with, push, dir, blast 0..1, at}
## (all optional; see _death_fx).
func _host_damage(shooter: int, target: int, amount: float, headshot: bool = false, cause: String = "", blow: Dictionary = {}) -> void:
	if not is_alive(target) or Teams.same_team(shooter, target):
		return   # (no friendly fire)
	if target == Net.my_id() and Cheats.god_mode():
		return
	if shooter != 0 and shooter != target and cause != "fell":
		amount *= damage_multiplier(shooter)
	var left: float = health[target]
	health[target] = max(health[target] - amount, 0.0)
	_hit.rpc(shooter, target, amount, health[target], headshot)
	if health[target] <= 0.0:
		_host_kill(target, shooter, cause, headshot, _death_fx(shooter, target, cause, headshot, amount - left, blow))


## Host: death_fx for a killing blow that did `overkill` more damage than was left.
func _death_fx(killer: int, victim: int, cause: String, headshot: bool, overkill: float, blow: Dictionary) -> Dictionary:
	var with := str(blow.get("with", ""))
	if killer == 0 or killer == victim:
		with = ""   # a crash on your own
	elif with == "" and cause != "slam":
		with = Net.player_weapon(killer)
	var fx := {"with": with, "head": headshot,
		"gib": float(blow.get("blast", 0.0)) >= GIB_BLAST or overkill >= GIB_OVERKILL,
		"push": blow.get("push", Vector3.ZERO), "dir": blow.get("dir", Vector3.ZERO)}
	if blow.has("at"):
		fx["at"] = blow.at
	return fx


@rpc("authority", "call_local", "reliable")
func _hit(shooter: int, target: int, amount: float, new_health: float, headshot: bool) -> void:
	health[target] = new_health
	player_hit.emit(shooter, target, amount, headshot)
	state_changed.emit()


# ---------------------------------------------------------------------------
# Target dummies (see TargetDummy). They take part in hits under negative ids,
# -1 for the first, so they never clash with a player's id.

static func dummy_id(index: int) -> int:
	return -1 - index


static func is_dummy(id: int) -> bool:
	return id < 0


func _host_dummy_damage(shooter: int, id: int, amount: float, headshot: bool) -> void:
	var index := -1 - id
	if not Net.arena or index >= Net.arena.dummies.size():
		return
	var dummy: TargetDummy = Net.arena.dummies[index]
	if dummy.is_down():
		return
	amount *= damage_multiplier(shooter)
	_dummy_hit.rpc(shooter, index, amount, maxf(dummy.health - amount, 0.0), headshot)


@rpc("authority", "call_local", "reliable")
func _dummy_hit(shooter: int, index: int, amount: float, new_health: float, headshot: bool) -> void:
	if not Net.arena or index >= Net.arena.dummies.size():
		return
	var dummy: TargetDummy = Net.arena.dummies[index]
	var who: Player = Net.arena.get_player(shooter)
	var distance := who.global_position.distance_to(dummy.global_position) if who else -1.0
	dummy.show_hit(amount, headshot, new_health, distance)
	player_hit.emit(shooter, dummy_id(index), amount, headshot)
	dummy_hit.emit(shooter, index, amount, headshot, new_health <= 0.0)


## Practice and offline only (the debug menu): back to full health now.
func host_heal(id: int) -> void:
	if Net.is_host() and running and is_alive(id):
		health[id] = MAX_HEALTH
		_broadcast_state()


## The local player fell out of the arena.
func request_fell(id: int = 0) -> void:
	if Net.is_host():
		_host_fell(id if id != 0 else Net.my_id())
	else:
		_fell_request.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _fell_request() -> void:
	if Net.is_host():
		_host_fell(multiplayer.get_remote_sender_id())


func _host_fell(id: int) -> void:
	if Race.active:
		return   # in a race you go back to your checkpoint instead (see Race)
	if running and is_alive(id):
		health[id] = 0.0
		_host_kill(id, 0, "fell")


## `fx`: see death_fx (from _death_fx; a death without one tells nothing more).
func _host_kill(victim: int, killer: int, cause: String = "", headshot: bool = false, fx: Dictionary = {}) -> void:
	if cause == "bomb":
		fx = {"with": "", "head": false, "gib": true, "push": Vector3.ZERO, "dir": Vector3.ZERO}
	var scored := _host_score_kill(victim, killer, cause, headshot, str(fx.get("with", "")))
	if scores.has(victim):
		scores[victim].deaths += 1
	if killer != 0 and killer != victim and scores.has(killer):
		scores[killer].kills += 1
	if not Teams.no_respawn():
		respawn_timers[victim] = RESPAWN_DELAY   # (Search and Destroy: out until the next round)
	respawn_asked.erase(victim)
	_last_shove.erase(victim)
	var finished := false
	var moves := []   # Gun Game: [id, new level]
	if GunGame.active() and killer != 0 and killer != victim and scores.has(killer):
		var up: int = int(scores[killer].get("level", 0)) + 1
		scores[killer]["level"] = up
		if up >= GunGame.steps():
			finished = true
		else:
			moves.append([killer, up])
		if cause == "kick" and scores.has(victim) and int(scores[victim].get("level", 0)) > 0:
			scores[victim]["level"] = int(scores[victim].level) - 1   # kicked to death: back one weapon
			moves.append([victim, scores[victim].level])
	if scored.size() >= 2 and scores.has(killer):
		# Every kill adds its killcam score (KillScore, the same number sent with it) to the
		# killer's points, shown on the scoreboard in every mode. In Killcam they win.
		scores[killer]["points"] = points(killer) + int(scored[1])
		if KillcamMode.active():
			finished = points(killer) >= KillcamMode.target()
	if GoldenGun.active():
		_host_golden_on_death(victim, killer)   # (before the death goes out: dying sends your own pick)
	_died.rpc(victim, killer, scores, cause, scored, fx)
	for m in moves:
		Net.host_set_weapon(m[0], GunGame.weapon_at(m[1]))
		_gun_game_level.rpc(m[0], m[1])
	if Net.is_deathmatch():
		Net.host_clear_inventory(victim)   # what you picked up is gone with you
	Teams.host_on_death(victim, cause)   # the bomb or a flag drops where they fell
	if finished:
		host_end_match()
	elif killer != 0 and kill_target > 0 and kills(killer) >= kill_target:
		host_end_match()


@rpc("authority", "call_local", "reliable")
func _gun_game_level(id: int, level: int) -> void:
	if DevArgs.sync_log:
		print("GUNGAME %d %d %s" % [id, level, GunGame.weapon_at(level)])
	gun_game_level.emit(id, level)


## Killcam: a player's points (their kills' killcam scores, plus the best-killcam bonus at the end).
func points(id: int) -> int:
	return int(scores[id].get("points", 0)) if scores.has(id) else 0


# ---------------------------------------------------------------------------
# Golden Gun (see GoldenGun). Who holds it is whose weapon it is (Net.players); the
# host hands it over.

var _golden_own := {}      # host: id -> the weapon a player had before they got the Golden Gun
var _golden_busy := false  # host: handing it over (the players change twice on the way)


## Host: the holder `victim` died (or someone else did, with it). Killed by another
## player: the Golden Gun goes to them. Nobody to credit: to someone at random. And a
## kill with the Golden Gun loads its next round at once.
func _host_golden_on_death(victim: int, killer: int) -> void:
	var by_other := killer != 0 and killer != victim and Net.players.has(killer)
	if by_other and Net.player_weapon(killer) == GoldenGun.WEAPON:
		_golden_reload.rpc(killer)
	if Net.player_weapon(victim) != GoldenGun.WEAPON:
		return
	_host_give_golden(killer if by_other else GoldenGun.pick_next(victim), victim)


## Host: `to` gets the Golden Gun; `from` (if any) gets back the weapon they had.
func _host_give_golden(to: int, from: int) -> void:
	if to == 0 or not Net.players.has(to):
		return
	_golden_busy = true
	var own := Net.player_weapon(to)
	if own != GoldenGun.WEAPON:
		_golden_own[to] = own
	Net.host_set_weapon(to, GoldenGun.WEAPON)   # (the new holder first: there is never nobody)
	if from != 0 and from != to and Net.players.has(from):
		Net.host_set_weapon(from, LobbySettings.fit_weapon(str(_golden_own.get(from, Net.player_loadout_weapon(from)))))
	_golden_busy = false
	_golden_passed.rpc(to, from)


@rpc("authority", "call_local", "reliable")
func _golden_passed(to: int, from: int) -> void:
	if DevArgs.sync_log:
		print("GOLDEN %d %d %d" % [Net.my_id(), to, from])
	golden_gun_passed.emit(to, from)


## A kill with the Golden Gun: its next round, on the copy that runs that player.
@rpc("authority", "call_local", "reliable")
func _golden_reload(id: int) -> void:
	var p: Player = Net.arena.get_player(id) if Net.arena else null
	if p and p.is_local and p.weapon and p.weapon.data.id == GoldenGun.WEAPON:
		p.weapon.reset()
		if DevArgs.sync_log:
			print("GOLDEN_RELOAD %d %d" % [Net.my_id(), id])


## Gun Game: how far along the ladder a player is (0 = the first weapon).
func level(id: int) -> int:
	return int(scores[id].get("level", 0)) if scores.has(id) else 0


## Host: how good this kill looks on a killcam (see KillScore), as the few numbers
## that travel with the death: [seq, score, tag bits, streak, distance in decimetres,
## weapon, killer's and victim's speed in decimetres a second, the flick in degrees].
## Empty when nobody else got the kill (a fall, a crash on your own).
func _host_score_kill(victim: int, killer: int, cause: String, headshot: bool, with: String = "") -> Array:
	if killer == 0 or killer == victim or not Net.players.has(killer) or Net.arena == null or Race.active:
		return []
	var a: Player = Net.arena.get_player(killer)
	var b: Player = Net.arena.get_player(victim)
	var now := Net.now()
	var recent: Array = _recent_kills.get(killer, []).filter(func(t): return (now - float(t)) * Engine.time_scale <= KillScore.MULTI_WINDOW)
	var weapon := Net.player_weapon(killer)
	var facts := {
		"distance": a.latest_position().distance_to(b.latest_position()) if a and b else 0.0,
		"headshot": headshot,
		"killer_state": Player.pose_state(a.pose_at(a.latest_time())) if a else 0,
		"victim_state": Player.pose_state(b.pose_at(b.latest_time())) if b else 0,
		"cause": "flying_kick" if cause == "kick" and _blow_flying else cause,
		"melee": cause == "" and WeaponData.melee(weapon),
		"streak": recent.size(),
		"killer_hp": health.get(killer, MAX_HEALTH),
		"killer_speed": a.buffer.speed() if a else 0.0,
		"victim_speed": b.buffer.speed() if b else 0.0,
		"flick": a.buffer.aim_travel(KillScore.FLICK_WINDOW) if a else 0.0,
	}
	recent.append(now)
	_recent_kills[killer] = recent
	_kill_seq += 1
	# Scored from the numbers as they travel (see kill_info), so every copy's breakdown
	# of the points (KillScore.breakdown) adds up to the same score.
	var dm := roundi(float(facts.distance) * 10.0)
	var speed_dm := roundi(float(facts.killer_speed) * 10.0)
	var target_dm := roundi(float(facts.victim_speed) * 10.0)
	var flick := roundi(float(facts.flick))
	facts.distance = float(dm) / 10.0
	facts.killer_speed = float(speed_dm) / 10.0
	facts.victim_speed = float(target_dm) / 10.0
	facts.flick = float(flick)
	var result := KillScore.score(facts)
	var kicked := cause == "kick" or (cause == "slam" and with in ["kick", "flying_kick"])   # (kicked into a wall too)
	return [_kill_seq, result[0], result[1], recent.size() - 1, dm,
		"kick" if kicked else weapon, speed_dm, target_dm, flick]


@rpc("authority", "call_local", "reliable")
func _died(victim: int, killer: int, new_scores: Dictionary, cause: String, scored: Array = [], fx: Dictionary = {}) -> void:
	if _late_respawns.has(victim):
		_respawn_late(victim, _late_respawns[victim])   # --delay-respawn: messages from the host still arrive in order
	health[victim] = 0.0
	damage_boost.erase(victim)   # power-ups end with you
	death_cause[victim] = cause
	death_fx[victim] = fx
	scores = new_scores
	if scored.size() >= 9:
		var info := kill_info(scored, killer, victim)
		kill_log.append(info)
		if DevArgs.sync_log:
			print("KILL_SCORE %d %d %d %d %s" % [info.seq, killer, victim, info.score, ",".join(KillScore.words(info))])
			print("POINTS %d %d" % [killer, points(killer)])   # the scoreboard's SCORE column
		kill_scored.emit(info)
	player_died.emit(victim, killer)
	state_changed.emit()


## Host (Teams): `id` is out, by something other than a player (the bomb).
func host_team_kill(id: int, cause: String) -> void:
	if not running or not is_alive(id):
		return
	health[id] = 0.0
	_host_kill(id, 0, cause)


## Host (Teams, Search and Destroy): a new round, everyone back at full health on their side.
func host_new_round() -> void:
	if not running:
		return
	respawn_timers.clear()
	respawn_asked.clear()
	_last_shove.clear()
	_tethers.clear()
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		_host_respawn(id)


func _host_respawn(id: int) -> void:
	if not running or not Net.players.has(id):
		return
	health[id] = MAX_HEALTH
	_respawn_counter += 1
	_respawned.rpc(id, _respawn_counter)


## Whether this player comes back only when they ask (a person in a match), or on
## their own when the wait is over (a bot, or Practice).
func respawn_needs_press(id: int) -> bool:
	return not (Net.is_bot(id) or Game.mode == Game.Mode.PRACTICE or Race.active)


## You are dead and want to come back: as soon as the wait is over, or now if it is.
## A press well before the end of the wait is ignored (press again).
func request_respawn() -> void:
	if not running:
		return
	if Net.is_host():
		_host_ask_respawn(Net.my_id())
	else:
		_ask_respawn.rpc_id(1)


@rpc("any_peer", "reliable")
func _ask_respawn() -> void:
	_host_ask_respawn(multiplayer.get_remote_sender_id())


func _host_ask_respawn(id: int) -> void:
	if not Net.is_host() or not running or not respawn_timers.has(id):
		return
	var early: bool = respawn_timers[id] > RESPAWN_EARLY
	if DevArgs.sync_log:
		print("RESPAWN_ASK %d %.2f %s" % [id, respawn_timers[id], "early" if early else "ok"])
	if not early:
		respawn_asked[id] = true


@rpc("authority", "call_local", "reliable")
func _respawned(id: int, spawn_index: int) -> void:
	if DevArgs.delay_respawn > 0.0 and not Net.is_host() and id != Net.my_id():
		# --delay-respawn (tests): as if this message were held up on the way, so the
		# player's first snapshot from their new life gets here before it does.
		_late_respawns[id] = spawn_index
		get_tree().create_timer(DevArgs.delay_respawn / 1000.0).timeout.connect(_respawn_late.bind(id, spawn_index))
		return
	_apply_respawn(id, spawn_index)


## --delay-respawn: the held-up respawn arrives (or sooner, if a death for them comes first).
func _respawn_late(id: int, spawn_index: int) -> void:
	if _late_respawns.get(id, -1) != spawn_index:
		return   # already applied
	_late_respawns.erase(id)
	if running and Net.players.has(id):
		_apply_respawn(id, spawn_index)


func _apply_respawn(id: int, spawn_index: int) -> void:
	if DevArgs.sync_log:
		print("RESPAWNED %d" % id)
	health[id] = MAX_HEALTH
	player_respawned.emit(id, spawn_index)
	state_changed.emit()


# ---------------------------------------------------------------------------
# Ending

func host_end_match() -> void:
	if not Net.is_host() or not running:
		return
	var best := []
	for k in KillScore.best(kill_log, 3):
		best.append(pack_kill(k))
	if KillcamMode.active() and not best.is_empty():
		# Killcam: the match's #1 killcam earns its killer a bonus, which can change the winner.
		var top := kill_info(best[0])
		if scores.has(top.killer):
			scores[top.killer]["points"] = points(top.killer) + KillcamMode.BEST_BONUS
			scores[top.killer]["bonus"] = KillcamMode.BEST_BONUS
			if DevArgs.sync_log:
				print("KILLCAM_BONUS %d %d %d" % [top.killer, top.seq, points(top.killer)])
	_match_over.rpc(build_results(), best)


## A kill info as the numbers that travel: [seq, score, tags, streak, decimetres, weapon,
## killer's speed, victim's speed (decimetres a second), flick (degrees), killer, victim].
static func pack_kill(k: Dictionary) -> Array:
	return [k.seq, k.score, k.tags, k.streak, roundi(k.distance * 10.0), k.weapon,
		roundi(k.speed * 10.0), roundi(k.target_speed * 10.0), roundi(k.flick), k.killer, k.victim]


## ...and back (killer and victim given, or from the end of the array).
static func kill_info(p: Array, killer: int = 0, victim: int = 0) -> Dictionary:
	return {"seq": int(p[0]), "score": int(p[1]), "tags": int(p[2]), "streak": int(p[3]),
		"distance": float(p[4]) / 10.0, "weapon": str(p[5]),
		"speed": float(p[6]) / 10.0, "target_speed": float(p[7]) / 10.0, "flick": float(p[8]),
		"killer": killer if killer != 0 else (int(p[9]) if p.size() > 9 else 0),
		"victim": victim if victim != 0 else (int(p[10]) if p.size() > 10 else 0)}


## Rankings: most kills first, then fewest deaths (Gun Game: furthest along the ladder;
## Killcam: most points). In a race: the race standings.
func build_results() -> Array:
	if Race.active:
		return Race.standings()
	var rows: Array = []
	var gun_game := GunGame.active()
	var killcam := KillcamMode.active()
	var teams := Teams.active()
	var ahead := Teams.leader()
	for id in scores:
		rows.append({"id": id, "name": Net.player_name(id), "kills": scores[id].kills, "deaths": scores[id].deaths,
			"level": int(scores[id].get("level", 0)), "points": points(id), "bonus": int(scores[id].get("bonus", 0)),
			"killcam": killcam})
		if teams:   # team modes: which team, its score, and the mode
			var t := Teams.team_of(id)
			rows[-1].merge({"team": t, "team_score": Teams.score[t] if t >= 0 else 0, "team_won": t >= 0 and t == ahead,
				"teams": Teams.mode(), "scores": Teams.score.duplicate()})
	rows.sort_custom(func(a, b):
		if teams and a.team != b.team:   # the team ahead first, each team together
			if a.team_won != b.team_won:
				return a.team_won
			return a.team < b.team
		if gun_game and a.level != b.level:
			return a.level > b.level
		if killcam and a.points != b.points:
			return a.points > b.points
		if a.kills != b.kills:
			return a.kills > b.kills
		return a.deaths < b.deaths)
	return rows


@rpc("authority", "call_local", "reliable")
func _match_over(results: Array, best: Array = []) -> void:
	running = false
	last_results = results
	respawn_timers.clear()
	respawn_asked.clear()
	highlights.clear()
	for p in best:
		highlights.append(kill_info(p))
	if DevArgs.sync_log:
		print("HIGHLIGHTS %s" % " ".join(highlights.map(func(h): return "%d:%d:%d>%d" % [h.seq, h.score, h.killer, h.victim])))
		print("MATCH_OVER %s" % JSON.stringify(results))
	match_over.emit(results)
