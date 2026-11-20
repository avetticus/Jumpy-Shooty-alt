class_name BotBrain
extends RefCounted
## The computer player's decisions. Each physics frame it fills in the bot's
## PlayerInput, exactly like the keyboard and mouse do for you, so a bot moves and
## shoots by the same rules as a person: same speeds, same gun, same hit checks.
##
## What it does:
##  - Notices you fairly: it sees you only when you are in front of it and nothing
##    is in the way (no seeing through walls). It hears gunfire, a bullet going past
##    and someone running nearby, and when you shoot it, it knows roughly where from.
##    A sound gives it a rough spot, not your exact position.
##  - Picks who to fight: in a free-for-all with several bots it goes for whoever
##    it knows about that is nearest, favouring someone it can see, whoever just
##    shot it, and whoever it is already fighting (so it does not flick between
##    targets). Bots fight each other as well as you.
##  - Finds you: walks the map's navigation mesh (ramps, decks, tower) to where it
##    last saw or heard you (the better bots guess where you were running), then
##    searches round there. When it gives up, or knows of nobody, it roams the map.
##  - Fights: strafes side to side at a comfortable range, jumps, and turns its aim
##    toward you at a limited speed. It sees you with a delay (its reaction time)
##    and its aim wobbles; it leads moving targets and goes for headshots more on
##    higher difficulties.
##  - Uses the movement set: sprints, slides and bunny-hops while chasing, dives to
##    close distance, flips to dodge when hit, grapples toward high ground.
##  - Uses whatever is on its mobility button (see Mobility): the grapple as above, or
##    blink to close in on you, to reach higher ground and to dodge when hit. Like
##    everyone it has the jetpack (Space held in mid-air): short bursts up to higher
##    ground, over cover as it closes in, and a hop out of the way when hit.
##  - Kicks anyone right in front of it, hooks you with the grapple to reel you in
##    and finishes with a flying kick, and fires its rocket boots to close in, to
##    dodge when hit and to whip round faster on a grapple swing.
##  - Uses a map's terminal now and then (Halcyon's low gravity): only when one is
##    ready and close, and it has nobody in sight. It walks up, presses interact, and
##    drops the idea the moment it sees someone. Harder bots try a little more often.
##  - Team modes (see Teams): never goes after its own team, and plays the objective
##    (Teams.bot_goal): carries the bomb to a site and plants it, picks up a dropped
##    bomb, defuses, guards the sites; takes the other team's flag and runs it home,
##    sends its own dropped flag home, covers a teammate's carry, and one bot in three
##    stays back on defence. With nobody in sight it heads for the objective; some
##    jobs (planting, defusing, a flag run home) it does even under fire.
##  - Copes with low gravity (WorldGravity): jumps carry further, so it looks further
##    ahead for floor before it jumps, hops, dives, flips or boosts.
##  - Copes with a map that moves (Cirrus's islands): it stands still while the map's
##    parts are on the move (or runs for the fixed end of a walkway that is being drawn
##    in), and where walking will not get it somewhere it uses the map's MapJumpLinks:
##    it grapples across, or runs off an edge to the floor below. On a map of islands
##    over a drop it leaves the free swinging and the long bursts alone.
## How good it is at each of these comes from BotDifficulty.

const ENGAGE_RANGE := 45.0
## The distances each gun likes to fight at: [closer than this it backs off a little,
## further than this it closes in, it does not shoot beyond this]. The shotgun rushes
## in, the sniper rifle keeps its distance.
## Melee weapons run straight in, winding the swing up on the way (harder bots wind
## up further), and let go once in reach and facing you.
const RANGES := {"pistol": [7.0, 18.0, 999.0], "shotgun": [2.5, 7.0, 20.0], "rifle": [8.0, 22.0, 999.0],
	"sniper": [16.0, 36.0, 999.0], "sword": [0.0, 1.8, 3.3], "hammer": [0.0, 1.8, 3.3], "dagger": [0.0, 1.3, 2.6],
	"revolver": [8.0, 20.0, 999.0], "machine_pistol": [3.0, 9.0, 30.0], "akimbo": [4.0, 11.0, 40.0], "break_action": [2.0, 6.0, 16.0],
	"smg": [3.5, 11.0, 40.0], "burst_rifle": [9.0, 24.0, 999.0], "lmg": [8.0, 22.0, 999.0],
	"lever_action": [10.0, 26.0, 999.0], "bolt_action": [14.0, 32.0, 999.0], "railgun": [14.0, 34.0, 999.0],
	"rocket_launcher": [8.0, 18.0, 60.0], "grenade_launcher": [7.0, 15.0, 35.0],
	"brass_knuckles": [0.0, 1.1, 2.1], "spear": [0.0, 2.6, 4.1], "axe": [0.0, 1.7, 3.0], "bat": [0.0, 1.7, 3.0],
	"derringer": [2.5, 8.0, 20.0], "air_cannon": [1.5, 5.0, 12.0],
	"minigun": [6.0, 18.0, 60.0], "battle_rifle": [10.0, 26.0, 999.0], "laser_rifle": [8.0, 22.0, 999.0],
	"nail_gun": [5.0, 14.0, 45.0], "crossbow": [12.0, 28.0, 120.0], "anti_materiel": [16.0, 38.0, 999.0],
	"plasma_cannon": [7.0, 15.0, 40.0],
	"scythe": [0.0, 2.4, 3.9], "mace": [0.0, 1.5, 2.7], "machete": [0.0, 1.4, 2.6],
	"wrench": [0.0, 1.4, 2.5], "energy_sword": [0.0, 1.7, 3.0],
	"karate": [0.0, 1.3, 2.4]}
const CHEST := 1.05        ## aim heights above the feet
const HEAD := 1.6
const PRONE_AIM := 0.4     ## aim height at someone belly-sliding (they are lying flat)
const SEARCH_RADIUS := 8.0 ## how far round the spot it lost you it looks
const SENSE_RATE := 30.0   ## times a second it looks and listens (see update): its reactions are far slower than this
const SOUND_GAP := 0.4     ## seconds between updating where it heard someone (so its goal does not jitter)
const WHIZZ := 4.0         ## a shot ending this close is heard, however far away the shooter is
const LOOK_TIME := 1.2     ## it looks toward a fresh sighting or sound for this long, then where it runs
const WALLBANG_TIME := 1.0 ## Hard and Expert, with the railgun: it fires through cover at where it saw or heard you this recently
const GRAPPLE_HEADROOM := 6.0  ## it only swings with this much open air above its head
const LEVEL_GAP := 2.5     ## you are this much higher or lower: it comes to your floor instead of fighting from where it is
const WIND_FROM := 6.0     ## melee: it starts winding its swing up this far outside its reach
const RETARGET := 0.25     ## seconds between choosing who to fight (straight away if the target dies)
const SEEN_BIAS := 0.5     ## someone it can see counts as this much closer...
const KEEP_BIAS := 0.7     ## ...its current target as this much closer...
const REVENGE_BIAS := 0.5  ## ...and whoever shot it in the last REVENGE_TIME seconds as this much closer
const REVENGE_TIME := 2.0
const TERMINAL_RANGE := 40.0     ## it only bothers with a terminal this close
const TERMINAL_THINK := 5.0      ## seconds between thinking about going for one...
const TERMINAL_CHANCE := [0.04, 0.06, 0.08, 0.1]   ## ...and the chance it does each time (Easy to Expert)
const TERMINAL_GIVE_UP := 14.0   ## seconds it spends getting there before it drops the idea
const NAV_SEARCH_POLYGONS := 32768  ## how much of the navigation mesh one path search may look through (see _nav_path)
const NO_LINK_WAIT := 1.5           ## seconds before a bot that found no crossing looks for one again
const ROAM_TRIES := 4            ## random places it tries, with nobody to go after, for one it can walk to (indoors)
const LINK_SHORT := 3.0          ## a path that ends this far (metres) from where it is going does not get there...
const LIFT_WORTH := 12.0         ## a goal this far above it (metres) is worth a tractor-beam lift, if one is near
const LIFT_NEAR := 45.0          ## ...whose foot is no further off than this, on its own floor
const LINK_SHORT_UP := 4.0       ## ...nor one that ends this far above or below it: time to look for a MapJumpLink
const LINK_GIVE_UP := 6.0        ## seconds a crossing may take before it stops trying

var me: Player
var d: BotDifficulty
var input: PlayerInput

var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _target: Player
var _retarget := 0.0
var _attacker := 0               # peer id of whoever last shot it
var _attacked_time := -99.0
var _seen: Array = []            # [time, aim point, velocity] of the target, oldest first
var _last_seen_time := -99.0
var _known := {}                 # peer id -> [time, position]: where it last saw or heard each player
var _in_view := {}               # peer id -> true for players it can see right now
var _goal := Vector3.INF         # where it is walking when it cannot see its target
var _goal_time := 0.0            # seconds it has been walking to _goal
var _goal_from := -1.0           # the time of the sighting or sound _goal is based on
var _path := PackedVector3Array()
var _path_index := 0
var _path_goal := Vector3.INF
var _repath := 0.0
var _corner_ahead := false       # the path turns sharply within the next few metres
var _strafe_dir := 1.0
var _strafe_timer := 0.0
var _error := Vector3.ZERO       # aim wobble, a slow random walk
var _go_head := false
var _head_timer := 0.0
var _fire_wait := 0.0
var _burst := 0.0                # automatic gun: seconds left of the burst it is firing
var NEAR := 7.0
var FAR := 18.0
var _reach := 999.0
var _lob := Vector3.INF          # rockets and grenades: the point it is really aiming at (led, low, lobbed)
var _melee := false              # carrying a blade or hammer: rush in instead of keeping distance
var _wind_goal := 0.6            # how far it means to wind this swing up, 0..1
var _stuck_time := 0.0
var _escape_dir := Vector3.ZERO
var _escape_time := 0.0
var _slide_time := 0.0
var _belly_time := 0.0           # holding dive: lands a dive on its belly and slides
var _hop_time := 0.0
var _trick_wait := 0.0
var _dodge_side := 0.0           # a flip dodge in progress: which way (-1 left, 1 right)
var _dodge_time := 0.0
var _grapple_time := 0.0
var _grapple_start := Vector3.ZERO
var _log_time := 0.0
var _hook_frame := false         # it has just aimed the hook at someone: don't turn away this frame
var _boost_side := 0.0           # it was just hit: boost this way (-1 left, 1 right, 0 no)
var _last_state := -1
var _state_seen := {}
var _terminal: MapTerminal       # the map terminal it is walking to or holding, or null
var _terminal_think := 0.0
var _terminal_time := 0.0
var _link: MapJumpLink           # the crossing it is walking to or making, or null
var _link_flying := false        # it has taken off
var _link_time := 0.0
var _link_hooked := false        # grapple crossing: the hook has caught
var _link_left := false          # it has left the floor
var _link_jumped := 0.0          # hop or boost crossing: when (into the crossing) it jumped
var _link_boosted := false       # boost crossing: the boots have fired
var _link_gliding := false       # boost crossing: it has started its glide
var _flee := false               # it stands on an island that is about to go down: off, by the nearest crossing
var _link_wait := 0.0            # seconds before it thinks of a crossing again (after one failed)
var _no_link := 0.0              # seconds before it looks for a crossing again (after finding none)
var _query: NavigationPathQueryParameters3D   # one path search's question and answer, used again each time
var _answer: NavigationPathQueryResult3D
var _open_map := -1              # 1: a map of islands over a drop (see _open()), 0: not, -1: not looked yet
var _ground_map := -1            # 1: many moving parts, routes worked out part by part (see _by_ground()), 0: not, -1: not looked yet
var _link_places := {}           # a crossing's instance id -> [the part it sets off from, the part it comes down on]
var _blink_side := 0.0           # it was just hit: blink this way (-1 left, 1 right, 0 no)
var _jet_time := 0.0             # seconds left of a jetpack burst it is holding (Space, in mid-air)
var _guarding := false           # team modes: inside the radius of the spot it is guarding
var _wander := Vector3.INF       # ...and the spot near it it is strolling to
var _wander_time := 0.0
var _ray := PhysicsRayQueryParameters3D.new()   # the one query every ray it casts reuses (see _cast)
var _nav_map := -1               # 1: the navigation mesh rides a moving part here (see _nav_rides), 0: not, -1: not looked yet
var _step := 0                   # physics steps it has been asked for input (counted from its peer id: see _init)
var _sense_every := 1            # it looks and listens on every this-many-th step (SENSE_RATE)

## Guns that wait for a clean shot (see _fire).
const STEADY_GUNS := ["sniper", "bolt_action", "railgun"]
## How often it thinks of using blink and the jetpack, a second (Easy to Expert).
const BLINK_RATE := [0.15, 0.5, 1.0, 1.4]
const JETPACK_RATE := [0.2, 0.5, 0.9, 1.2]


func _init(player: Player, level: int) -> void:
	me = player
	d = BotDifficulty.make(level)
	input = player.input
	_ray.collision_mask = 1         # (the level)
	_ray.exclude = [me.get_rid()]   # (its own body never stops its rays)
	_sense_every = maxi(roundi(Engine.physics_ticks_per_second / SENSE_RATE), 1)
	_step = me.peer_id   # (so the bots look on different steps, not all on the same one)
	weapon_changed()
	_rng.randomize()
	Match.player_hit.connect(_on_hit)
	Match.shot_fired.connect(_on_shot)


## Fight the way the weapon in its hands likes (Gun Game swaps it mid-match; a
## Deathmatch pickup or switch too). Empty hands fight like a blade: run in and kick.
func weapon_changed() -> void:
	var r: Array = RANGES.get(WeaponData.look_of(me.weapon.data.id) if me.weapon else "dagger", RANGES.pistol)
	NEAR = r[0]
	FAR = r[1]
	_reach = r[2]
	_melee = me.weapon == null or me.weapon.data.is_melee()
	_burst = 0.0


## Deathmatch, empty hands: the nearest weapon lying about (INF if none is there).
func _nearest_pickup() -> Vector3:
	if Net.arena == null:
		return Vector3.INF
	var best := Vector3.INF
	var best_d := INF
	for p in Net.arena.pickups:
		var pickup := p as WeaponPickup
		if pickup.is_taken():
			continue
		var dist := me.global_position.distance_to(pickup.global_position)
		if dist < best_d:
			best_d = dist
			best = pickup.global_position
	return best


## Fill in this frame's input.
func update(delta: float) -> void:
	_time += delta
	_step += 1   # (while it is dead too, so the bots stay on different steps)
	input.move = Vector2.ZERO
	input.sprint = false
	input.fire = false
	input.interact = false
	input.aim_origin = Vector3.ZERO
	input.aim_dir = Vector3.ZERO
	if not me.alive:
		_reset()
		return
	# Looking and listening is the dearest thing it does (two rays at everyone), and it
	# reacts in tenths of a second: SENSE_RATE times a second is plenty. Between looks it
	# goes on what it last saw; where its target is, it still reads on every step (below).
	if _step % _sense_every == 0:
		_sense()
	_retarget -= delta
	if not is_instance_valid(_target):
		_target = null
	if _target == null or not _target.alive or not _known.has(_target.peer_id) or _retarget <= 0.0:
		_retarget = RETARGET
		var picked := _pick_target()
		if picked != _target:
			_target = picked
			_seen.clear()   # what it saw of the old target says nothing about this one
			_goal = Vector3.INF
			_goal_from = -1.0
	var visible := _target != null and _in_view.has(_target.peer_id)
	if visible:
		_seen.append([_time, _aim_point(_target), _target.velocity])
		_last_seen_time = _time
	while not _seen.is_empty() and _seen[0][0] < _time - 2.0:
		_seen.pop_front()
	var perceived := _perceived() if visible else _wallbang()

	_link_wait = maxf(_link_wait - delta, 0.0)
	_no_link = maxf(_no_link - delta, 0.0)
	if _link_flying:
		_fly_link(delta)   # crossing a gap: nothing else until it is down
		return
	var hold := _map_moving()
	var world_dir := _choose_direction(delta, visible)
	_hook_frame = false
	var map := MapRoot.current
	var flee := not hold and map != null and is_instance_valid(map) and map.warning and map.doomed_at(me.global_position)
	if flee != _flee:
		_flee = flee
		_repath = 0.0
		_link_wait = 0.0
		_no_link = 0.0
		if not flee and not _link_flying:
			_link = null
	if _flee:
		# The bell has gone and this island is about to go down: make for the crossing that
		# leads off it, whatever else is going on.
		world_dir = _follow_path(Vector3(0.0, me.global_position.y, 0.0), delta)
		input.sprint = true
		_hop_time = 0.0
		_dodge_time = 0.0
	elif not hold and map != null and is_instance_valid(map) and map.warning:
		# The bell has gone: off a walkway that is about to be drawn in, and not onto one.
		var off := _hold_spot()
		if off != Vector3.ZERO:
			world_dir = off
			input.grapple = false
			_link = null
		elif _span_ahead(world_dir):
			world_dir = Vector3.ZERO
	if hold:
		# The map's parts are moving: stay put (or get off a walkway that is going), no tricks.
		world_dir = _hold_spot()
		input.grapple = false
		input.jump_pressed = false
		input.dive_pressed = false
		input.dive = false
		input.crouch = false
		input.crouch_pressed = false
		input.interact = false
		_hop_time = 0.0
		_dodge_time = 0.0
		_boost_side = 0.0
		_blink_side = 0.0
		_jet_time = 0.0
		input.jump_held = false
		_link = null
		_repath = 0.0
	elif _terminal != null or _link != null:
		input.grapple = false   # no swinging off while it is at (or on its way to) a terminal or a crossing
	if _open() and not hold:
		world_dir = _mind_the_edge(world_dir)
	elif me.mobility == Mobility.BLINK:
		_blink(delta, visible)
	else:
		_grapple(delta, visible)
	if not hold:
		_jetpack(delta, visible, not _open())   # (over a drop: only its hop out of the way when hit)
	_dodge(delta)
	_set_move(world_dir)
	if not _hook_frame:
		_aim(delta, perceived, world_dir)
	_fire(delta, perceived)
	_kick(delta, visible)
	if _terminal == null and _link == null and not hold:
		_boost(delta, visible)
	if _link != null and not hold:
		_start_link()
	if DevArgs.sync_log:
		if me.motor.state != _last_state:
			_last_state = me.motor.state
			if _time - float(_state_seen.get(_last_state, -9.0)) > 0.5 and _last_state in [MovementController.State.DIVE, MovementController.State.FLIP,
					MovementController.State.GRAPPLE, MovementController.State.SLIDE, MovementController.State.BELLY_SLIDE,
					MovementController.State.WALL_RUN, MovementController.State.MANTLE]:
				print("BOT_MOVE %d %s" % [me.peer_id, MovementController.State.keys()[_last_state]])
			_state_seen[_last_state] = _time
		_log_time -= delta
		if _log_time <= 0.0:
			_log_time = 1.0
			var p := me.global_position
			print("BOT %d %.1f %.1f %.1f %s see=%s dist=%.1f path=%d/%d" % [me.peer_id, p.x, p.y, p.z,
				MovementController.State.keys()[me.motor.state], visible,
				p.distance_to(_target.global_position) if _target else -1.0, _path_index, _path.size()])


func _reset() -> void:
	_seen.clear()
	_in_view.clear()
	_goal = Vector3.INF
	_path = PackedVector3Array()
	_path_goal = Vector3.INF
	input.grapple = false
	input.crouch = false
	_slide_time = 0.0
	_belly_time = 0.0
	input.dive = false
	_hop_time = 0.0
	_dodge_time = 0.0
	_grapple_time = 0.0
	_terminal = null
	_link = null
	_link_flying = false
	_blink_side = 0.0
	input.glide = false
	_jet_time = 0.0
	input.jump_held = false


# ---------------------------------------------------------------------------
# Seeing

## Look and listen: update what it knows about where everyone is. Run SENSE_RATE times
## a second, not on every step (see update).
func _sense() -> void:
	# (Where it looks from and which way are the same for everyone it looks at.)
	var eye := me.eye_position()
	var facing := me.aim_forward()
	var view := deg_to_rad(d.view_angle)
	for other in _others():
		var id := other.peer_id
		if not other.alive:
			_known.erase(id)
			_in_view.erase(id)
			continue
		if _can_see(other, eye, facing, view):
			_known[id] = [_time, other.global_position]
			_in_view[id] = true
			continue
		if _in_view.has(id):
			# Just lost sight: it saw which way you were going.
			_in_view.erase(id)
			var v := Vector3(other.velocity.x, 0.0, other.velocity.z)
			_known[id] = [_time, other.global_position + v * d.predict]
			continue
		# Footsteps: someone running close by (walking or crouching is quieter).
		var speed := Vector2(other.velocity.x, other.velocity.z).length()
		var dist := me.global_position.distance_to(other.global_position)
		if speed > 2.5 and dist < d.step_range * (1.0 if speed > 6.0 else 0.5):
			_hear(id, other.global_position, false)
	for id in _known.keys():
		if _time - float(_known[id][0]) > d.memory:
			_known.erase(id)


## It heard player `id` at `where`: it knows roughly where, worse from further away.
## A player it can see needs no guessing, and a fresh sound is not replaced by
## another straight away unless `force` (it was shot).
func _hear(id: int, where: Vector3, force: bool) -> void:
	if _in_view.has(id):
		return
	if not force and _known.has(id) and _time - float(_known[id][0]) < SOUND_GAP:
		return
	var off := me.global_position.distance_to(where) * d.sound_error
	var miss := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).limit_length(1.0)
	_known[id] = [_time, where + miss * off]


func _on_shot(shooter: int, muzzle: Vector3, ends: PackedVector3Array, _hits: Array) -> void:
	if shooter == me.peer_id or not me.alive:
		return
	var eye := me.eye_position()
	var close := eye.distance_to(muzzle) <= d.hear_range
	if not close:
		for e in ends:   # a bullet cracking past
			if Geometry3D.get_closest_point_to_segment(eye, muzzle, e).distance_to(eye) < WHIZZ:
				close = true
				break
	if close:
		_hear(shooter, muzzle, false)


func _others() -> Array[Player]:
	var list: Array[Player] = []
	# (Asked once, not for each player: with no team mode on, nobody is a teammate. This
	# runs for every bot on every physics step.)
	var teams := Teams.active()
	for p in me.get_parent().get_children():
		var other := p as Player
		if other != null and other != me and not (teams and Teams.same_team(me.peer_id, other.peer_id)):
			list.append(other)   # (teammates are not targets)
	return list


func _pick_target() -> Player:
	var best: Player = null
	var best_score := INF
	var revenge := _time - _attacked_time < REVENGE_TIME
	for other in _others():
		if not other.alive or not _known.has(other.peer_id):
			continue   # it only goes after players it has seen or heard
		var score := me.global_position.distance_to(_known[other.peer_id][1])
		if _in_view.has(other.peer_id):
			score *= SEEN_BIAS
		if other == _target:
			score *= KEEP_BIAS
		if revenge and other.peer_id == _attacker:
			score *= REVENGE_BIAS
		if score < best_score:
			best_score = score
			best = other
	return best


## In front of it (or right next to it) and not behind a wall. `eye`: where it looks
## from, `facing`: the way it looks, `view`: how far to the side it sees (radians).
func _can_see(p: Player, eye: Vector3, facing: Vector3, view: float) -> bool:
	var feet := p.global_position
	var to := feet + Vector3(0, CHEST, 0) - eye
	if to.length() > 3.0 and facing.angle_to(to) > view:
		return false
	return _cast(eye, feet + Vector3(0, HEAD, 0)).is_empty() or _cast(eye, feet + Vector3(0, CHEST, 0)).is_empty()


## A ray from `from` to `to`: what it hits first ({} if nothing). It hits the level,
## never players. Every ray the bot casts comes through here and reuses one query:
## making a new one for each ray cost more than the ray.
func _cast(from: Vector3, to: Vector3) -> Dictionary:
	_ray.from = from
	_ray.to = to
	return me.get_world_3d().direct_space_state.intersect_ray(_ray)


## Where it thinks its target is: where it really is when it can see it, otherwise
## where it last saw or heard it.
func _target_spot() -> Vector3:
	if _target == null:
		return Vector3.INF
	if _in_view.has(_target.peer_id):
		return _target.global_position
	return _known[_target.peer_id][1] if _known.has(_target.peer_id) else Vector3.INF


## Where it aims on a target: chest, or head when it is going for headshots.
func _aim_point(p: Player) -> Vector3:
	var pose := p.pose_at(p.latest_time()) if not p.motor else 0
	var low: bool = p.motor.crouched if p.motor else Player.pose_crouched(pose)
	var prone: bool = p.motor.prone if p.motor else Player.pose_state(pose) == MovementController.State.BELLY_SLIDE
	var h := (HEAD - 0.6 if low else HEAD) if _go_head else (CHEST - 0.3 if low else CHEST)
	if prone:
		h = PRONE_AIM
	return p.global_position + Vector3(0, h, 0)


## What the bot "knows" right now: where the target was one reaction time ago.
## Empty until it has been watching that long (it has only just spotted you).
func _perceived() -> Array:
	var when := _time - d.reaction_time
	# The newest sighting that is old enough. Looked for from the newest end: _seen is in
	# time order and holds two seconds of them (a couple of hundred), and the one wanted
	# is one reaction time back from its end.
	for i in range(_seen.size() - 1, -1, -1):
		if _seen[i][0] <= when:
			return _seen[i]
	return []


## The railgun goes through walls: a Hard or Expert bot holding it, its target out of
## sight, aims and fires at where it saw or heard them a moment ago (as _perceived, or
## empty). Nothing it could not know: only the spot it already has, and only briefly.
func _wallbang() -> Array:
	if d.level < BotDifficulty.HARD or _target == null or me.weapon == null or not me.weapon.data.pierce:
		return []
	var known: Array = _known.get(_target.peer_id, [])
	if known.is_empty() or _time - float(known[0]) > WALLBANG_TIME:
		return []
	return [known[0], (known[1] as Vector3) + Vector3(0, CHEST, 0), Vector3.ZERO]


# ---------------------------------------------------------------------------
# Moving

func _choose_direction(delta: float, visible: bool) -> Vector3:
	var pos := me.global_position
	var grounded := me.is_on_floor()
	var speed := Vector2(me.velocity.x, me.velocity.z).length()
	input.crouch = false
	_belly_time = maxf(_belly_time - delta, 0.0)
	input.dive = _belly_time > 0.0
	if _escape_time > 0.0:
		_escape_time -= delta
		_unstick(delta, _escape_dir)
		return _escape_dir
	var dist := pos.distance_to(_target.global_position) if visible else INF
	var dir := Vector3.ZERO
	var goal := Teams.bot_goal(me.peer_id, pos) if Teams.active() else {}
	var room := float(goal.get("radius", 0.0))
	# Inside the spot's radius it stays until well outside it (so it does not dither on the edge).
	var off: bool = not goal.is_empty() and (goal.hold or _flat(pos, goal.spot) > (room * 1.6 if _guarding else room) + 0.5 \
			or absf(pos.y - goal.spot.y) > LEVEL_GAP)
	_guarding = not goal.is_empty() and not off and room > 0.0
	if _guarding and not visible and (_target == null or not _known.has(_target.peer_id)):
		# Guarding a spot (a site, the bomb, a flag, a teammate) with nobody about: wander round it.
		var spot := _guard_point(goal.spot, room, delta)
		dir = _follow_path(spot, delta)
		if dir == Vector3.ZERO:
			dir = Vector3(spot.x - pos.x, 0.0, spot.z - pos.z).limit_length(1.0)
		_unstick(delta, dir)
		return dir
	if off and (goal.urgent or not visible):
		# The objective (team modes): plant, defuse, take or return a flag, or get to its spot.
		if goal.hold:
			input.interact = true
			return Vector3.ZERO
		var spot: Vector3 = goal.spot
		dir = _follow_path(spot, delta)
		if dir == Vector3.ZERO or _flat(pos, spot) < 2.5:
			dir = Vector3(spot.x - pos.x, 0.0, spot.z - pos.z).normalized()   # the last step, straight onto it
		input.sprint = d.sprint and not _corner_ahead
		_chase_tricks(delta, dir, grounded, speed)
		_unstick(delta, dir)
		return dir
	var pickup := _nearest_pickup() if me.weapon == null else Vector3.INF
	var console := _terminal_spot(delta, visible) if pickup == Vector3.INF else Vector3.INF
	if console != Vector3.INF:
		# A map terminal: walk up to it and press interact (or hold it, if the terminal asks for a hold).
		if _terminal.reaches(pos) and _flat(pos, _terminal.global_position) < _terminal.range * 0.75:
			input.interact = true
			return Vector3.ZERO
		dir = _follow_path(console, delta)
		if dir == Vector3.ZERO:
			dir = Vector3(console.x - pos.x, 0.0, console.z - pos.z).normalized()   # the last step
		input.sprint = d.sprint and not _corner_ahead and _flat(pos, console) > 8.0
		_unstick(delta, dir)
		return dir
	if pickup != Vector3.INF and dist > 4.0:
		# Deathmatch with empty hands: arm up first (kicking anyone who gets close).
		dir = _follow_path(pickup, delta)
		if _flat(pos, pickup) < 2.5:
			dir = Vector3(pickup.x - pos.x, 0.0, pickup.z - pos.z).normalized()   # the last step, straight over it
		input.sprint = d.sprint and not _corner_ahead
		_chase_tricks(delta, dir, grounded, speed)
	elif visible and dist < maxf(ENGAGE_RANGE, FAR + 10.0):
		# Fight: strafe side to side, keeping a comfortable distance.
		var to := _target.global_position - pos
		to.y = 0.0
		var f := to.normalized()
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_timer = _rng.randf_range(0.35, 1.3)
			if _rng.randf() < 0.75:
				_strafe_dir = -_strafe_dir
		var approach := 1.0 if dist > FAR else (-0.6 if dist < NEAR else 0.0)
		if _melee and dist > FAR:
			approach = 2.5   # straight at you, weaving a little
		dir = f.cross(Vector3.UP) * _strafe_dir * d.strafe + f * approach
		var edge := 3.0 if _open() else 1.5   # (islands over a drop: a low rail is no wall, so look past it)
		if _blocked(dir) or not _ground_ahead(dir, edge):
			_strafe_dir = -_strafe_dir
			dir = f.cross(Vector3.UP) * _strafe_dir * d.strafe + f * approach
			if not _ground_ahead(dir, edge):
				# A drop on both sides (it is on stairs or a walkway): keep to the path
				dir = _follow_path(_target.global_position, delta)
		# You are on another floor: no strafing about underneath, take the stairs to
		# your level (still shooting on the way).
		if absf(_target.global_position.y - pos.y) > LEVEL_GAP:
			var route := _follow_path(_target.global_position, delta)
			if route != Vector3.ZERO:
				dir = route
		input.sprint = d.sprint and dist > FAR and not _corner_ahead
		if grounded and _rng.randf() < d.jumpiness * delta * 2.5 and (not (_light() or _open()) or _ground_ahead(dir, (5.0 if _open() else 3.0) * _air())):
			input.jump_pressed = true
		# At the top of a jump, flip sideways to throw off your aim.
		if not grounded and absf(me.velocity.y) < 2.0 and _dodge_time <= 0.0 \
				and (not _open() or _ground_ahead(f.cross(Vector3.UP) * _strafe_dir, 8.0)) \
				and _rng.randf() < d.jumpiness * d.dodge_chance * delta * 6.0:
			_dodge_side = _strafe_dir
			_dodge_time = 0.3
		# Close the gap fast with a dive (it dives where it looks: at you).
		var dive_room := (14.0 if _open() else 8.0) * _air()
		if d.grapples and grounded and dist > FAR + 4.0 and _rng.randf() < delta * 0.5 and _ground_ahead(f, dive_room):
			_dive(f)
		elif _melee and grounded and dist > 5.0 and dist < 12.0 and _rng.randf() < delta * 1.2 and _ground_ahead(f, dive_room):
			_dive(f)   # a blade has to get close: dive in
	else:
		# Chase to where it last saw or heard you and search round there, or roam.
		dir = _follow_path(_hunt_goal(delta), delta)
		input.sprint = d.sprint and not _corner_ahead   # sprinting round a sharp corner overshoots it
		_chase_tricks(delta, dir, grounded, speed)
	if _hop_time > 0.0:
		_hop_time -= delta
		if not _ground_ahead(dir, (9.0 if _open() else 6.0) * _air()):
			_hop_time = 0.0             # a drop is coming up: stop hopping
		elif grounded:
			input.jump_pressed = true   # bunny-hop: jump again the moment it lands
	if _slide_time > 0.0:
		_slide_time -= delta
		input.crouch = true
	_unstick(delta, dir)
	return dir


## Guarding: a spot to walk to near `spot`, a new one every few seconds or once there.
func _guard_point(spot: Vector3, room: float, delta: float) -> Vector3:
	_wander_time -= delta
	var pos := me.global_position
	if _wander == Vector3.INF or _wander_time <= 0.0 or _flat(pos, _wander) < 1.2 or _flat(_wander, spot) > room * 1.3:
		_wander_time = _rng.randf_range(2.5, 5.0)
		var offset := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).limit_length(1.0) * room * 0.8
		var nav := me.get_world_3d().navigation_map
		_wander = _from_nav(NavigationServer3D.map_get_closest_point(nav, _to_nav(spot) + offset)) if NavigationServer3D.map_get_iteration_id(nav) > 0 else spot
	return _wander


## Where to walk when it cannot see its target: the spot it last saw or heard it,
## then other places close to that spot. With nobody to go after, anywhere on the map.
## (_goal is kept in the navigation mesh's frame, so it rides whatever it is on.)
func _hunt_goal(delta: float) -> Vector3:
	var nav := me.get_world_3d().navigation_map
	_goal_time += delta
	var info: Array = _known[_target.peer_id] if _target != null and _known.has(_target.peer_id) else []
	var pos := _to_nav(me.global_position)
	if not info.is_empty() and float(info[0]) != _goal_from:
		_goal_from = info[0]   # a new sighting or sound: go there
		_goal = _walk_end(pos, _to_nav(info[1]))
		_goal_time = 0.0
	var arrived := _goal != Vector3.INF and _flat(pos, _goal) < 1.5 and absf(_goal.y - pos.y) < 2.5
	if _goal == Vector3.INF or arrived or _goal_time > 12.0:
		_goal_time = 0.0
		if not info.is_empty():
			var spot: Vector3 = _to_nav(info[1])
			var off := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized() * _rng.randf_range(3.0, SEARCH_RADIUS)
			_goal = _walk_end(pos, NavigationServer3D.map_get_closest_point(nav, spot + off))
		else:
			_goal_from = -1.0
			for i in ROAM_TRIES:
				var pick := NavigationServer3D.map_get_random_point(nav, 1, true)
				_goal = _walk_end(pos, pick)
				if _goal == pick:
					break   # (one it can walk to: not a table top, nor a room whose doors are shut)
	return _from_nav(_goal)


## Indoors (a map with no islands and no crossings to jump), where walking toward
## `goal` from `pos` ends, if it ends short of it: a goal on a table top or a bookcase,
## or in a room whose doorways have gone (Haunted House), becomes the nearest place it
## can walk to, so the bot does not stand at a dead end until it gives up. Elsewhere,
## and when it gets there, `goal` itself. (Both in the navigation mesh's frame.)
func _walk_end(pos: Vector3, goal: Vector3) -> Vector3:
	if _open() or not me.get_tree().get_nodes_in_group(MapJumpLink.GROUP).is_empty():
		return goal
	var path := _nav_path(pos, goal)
	if path.is_empty():
		return goal
	var end := path[path.size() - 1]
	return end if _flat(end, goal) > 1.0 or absf(end.y - goal.y) > 1.5 else goal


## Once it is running fast it mixes in movement tricks: slides, bunny-hops, dives.
func _chase_tricks(delta: float, dir: Vector3, grounded: bool, speed: float) -> void:
	_trick_wait -= delta
	if not d.slides or not grounded or speed < 9.0 or _trick_wait > 0.0 or dir.length() < 0.1:
		return
	_trick_wait = _rng.randf_range(0.6, 1.6)
	if not _ground_ahead(dir, (14.0 if _open() else 9.0) * _air()):
		return   # up on a floor or a stair with an edge ahead: no tricks that carry it over
	var facing := Vector3(me.aim_forward().x, 0.0, me.aim_forward().z).normalized()
	var straight := facing.angle_to(dir) < deg_to_rad(15.0) and _straight_ahead(dir) > 8.0
	var roll := _rng.randf()
	if d.grapples and straight and roll < 0.3 and me.motor.state != MovementController.State.SLIDE:
		_dive(dir)   # dives go where it looks, so only when looking where it runs
	elif roll < 0.6:
		_slide_time = 0.8
		input.crouch_pressed = true
	elif d.jumpiness >= 0.15:
		_hop_time = _rng.randf_range(0.8, 2.0)


## Low gravity (a map event): everything that leaves the floor carries further.
func _light() -> bool:
	return _gravity() < 0.9


## How much further ahead to look for floor before leaving it: 1 normally, up to
## 2.5 times as far in low gravity.
func _air() -> float:
	return clampf(1.0 / maxf(_gravity(), 0.01), 1.0, 3.4)


## Its own body's gravity, as a share of normal: the map event's times the zone it
## stands in (low outside Empyrean Tower's walls).
func _gravity() -> float:
	return me.motor.gravity_scale if me != null and me.motor != null else WorldGravity.scale


## Where to walk to use a map terminal, or INF when it is not going for one. It
## only thinks of it now and then, with nobody in sight, when a terminal is ready
## and close; it drops the idea when it sees someone, when someone else gets
## there first, or when getting there takes too long.
func _terminal_spot(delta: float, visible: bool) -> Vector3:
	if _terminal != null:
		var mine := is_instance_valid(_terminal) and _terminal.phase == MapTerminal.Phase.CHANNEL and _terminal.channeler == me.peer_id
		if not mine:
			_terminal_time += delta
		if not is_instance_valid(_terminal) or visible or (not mine and not _terminal.ready_to_use()) or _terminal_time > TERMINAL_GIVE_UP:
			_terminal = null
	else:
		_terminal_think -= delta
		if _terminal_think <= 0.0:
			_terminal_think = TERMINAL_THINK * _rng.randf_range(0.7, 1.3)
			if not visible and _in_view.is_empty() and Match.running and (DevArgs.eager_terminal or _rng.randf() < TERMINAL_CHANCE[d.level]):
				for t in me.get_tree().get_nodes_in_group(MapTerminal.GROUP):
					var terminal := t as MapTerminal
					if terminal.bots and terminal.ready_to_use() and me.global_position.distance_to(terminal.global_position) < TERMINAL_RANGE \
							and (_terminal == null or me.global_position.distance_to(terminal.global_position) < me.global_position.distance_to(_terminal.global_position)):
						_terminal = terminal
				_terminal_time = 0.0
	if _terminal == null:
		return Vector3.INF
	if NavigationServer3D.map_get_iteration_id(me.get_world_3d().navigation_map) == 0:
		return Vector3.INF   # (the navigation map is not ready in the match's first frames)
	# A spot beside the console, on the side it is coming from.
	var at := _terminal.global_position
	var from := Vector3(me.global_position.x - at.x, 0.0, me.global_position.z - at.z)
	var beside := at + (from.normalized() if from.length() > 0.2 else Vector3.FORWARD) * 1.2
	return _from_nav(NavigationServer3D.map_get_closest_point(me.get_world_3d().navigation_map, _to_nav(beside)))


## Dive, and the better bots usually keep the button held to land in a belly slide
## (a smaller target, and it keeps shooting) when there is room ahead to slide.
func _dive(dir: Vector3) -> void:
	input.dive_pressed = true
	if d.belly_slides and _rng.randf() < 0.7 and _straight_ahead(dir) > 8.0:
		_belly_time = _rng.randf_range(0.9, 1.6)
		input.dive = true


## How far it can run in this direction before hitting something (up to 12 m).
func _straight_ahead(dir: Vector3) -> float:
	var from := me.global_position + Vector3(0, 1.0, 0)
	var hit := _cast(from, from + dir.normalized() * 12.0)
	return 12.0 if hit.is_empty() else from.distance_to(hit.position)


## The way to `goal`, one step at a time: which way to walk now. The path is kept in
## the navigation mesh's frame (see _to_nav), and so is everything it is compared with.
func _follow_path(goal_at: Vector3, delta: float) -> Vector3:
	var world_pos := me.global_position
	var pos := _to_nav(world_pos)
	var goal := _to_nav(goal_at)
	_repath -= delta
	if _repath <= 0.0 or _path_goal.distance_to(goal_at) > 2.5 or _path_index >= _path.size():
		_repath = 0.6
		_path_goal = goal_at
		_path = _nav_path(pos, goal)
		_path_index = 1 if _path.size() > 1 else 0
		if _flee:
			_link = _escape_link(world_pos)
		else:
			_link = _pick_link(world_pos, goal_at) if _stops_short(goal) else null
			if _link == null:
				_link = _pick_lift(world_pos, goal_at)   # well above it: a tractor beam is quicker than the stairs
		if _link != null:
			# Walking does not get there: walk to the crossing instead.
			_path = _nav_path(pos, _to_nav(_link.takeoff()))
			_path_index = 1 if _path.size() > 1 else 0
	if _link != null:
		goal = _to_nav(_link.takeoff())
	while _path_index < _path.size() and _reached(pos, _path_index):
		_path_index += 1
	if _path_index >= _path.size() and _link == null and _open() and not _path.is_empty() \
			and (_flat(_path[_path.size() - 1], goal) > LINK_SHORT or absf(_path[_path.size() - 1].y - goal.y) > LINK_SHORT_UP):
		# Islands over a drop: the path ends where walking ends (a roof, a stepping stone, the
		# far side of a gap). Stop there, and think of somewhere else to go.
		_goal_time = 99.0
		return Vector3.ZERO
	var next := goal if _path_index >= _path.size() else _path[_path_index]
	_corner_ahead = _path_index < _path.size() and _flat(pos, next) < 4.0 and _is_corner(_path_index)
	var to := next - pos
	to.y = 0.0
	return to.normalized() if to.length() > 0.3 else Vector3.ZERO


## A path from `a` to `b`, both in the navigation mesh's frame (and so is the path).
func _nav_path(a: Vector3, b: Vector3) -> PackedVector3Array:
	# (Asked this way, not with map_get_path, to lift the server's limit on how much of
	# the mesh one search may look through: 4096 polygons by default, and Empyrean
	# Tower's mesh is twice that. Past the limit a search gives up and hands back a
	# path that stops short, which a bot takes for "walking does not get there" and
	# then tries every crossing on the map, at many searches each.)
	if _query == null:
		_query = NavigationPathQueryParameters3D.new()
		_query.path_search_max_polygons = NAV_SEARCH_POLYGONS
		_answer = NavigationPathQueryResult3D.new()
	_query.map = me.get_world_3d().navigation_map
	_query.start_position = a
	_query.target_position = b
	NavigationServer3D.query_path(_query, _answer)
	var found := _answer.path
	var path := PackedVector3Array()
	for point in found:   # the server repeats points where the path changes height
		if path.is_empty() or path[path.size() - 1].distance_to(point) > 0.05:
			path.append(point)
	return path


## A point in the map as it was in the navigation mesh's frame, and back: on a map whose
## parts keep moving (Sky Island) the mesh was worked out from where they stood at one
## moment (see MapRoot.to_nav). Elsewhere these change nothing.
func _to_nav(point: Vector3) -> Vector3:
	var map := MapRoot.current
	return map.to_nav(point) if point != Vector3.INF and map != null and is_instance_valid(map) and _nav_rides(map) else point


func _from_nav(point: Vector3) -> Vector3:
	var map := MapRoot.current
	return map.from_nav(point) if point != Vector3.INF and map != null and is_instance_valid(map) and _nav_rides(map) else point


## Does any of this map's navigation mesh ride a moving part? Only a plain mover carries
## it (MapRoot.to_nav and from_nav pass islands by): on a map with none, both give the
## point back unchanged, and the bot asks for them several times a physics step.
func _nav_rides(map: MapRoot) -> bool:
	if map.movers.is_empty():
		return false
	if _nav_map < 0:
		_nav_map = 0
		for m in map.movers:
			if not m.node is MapIsland:
				_nav_map = 1
	return _nav_map == 1


## Has it got to this point of the path? Close is enough on a straight stretch, but
## it has to go right round a sharp corner (the foot of a staircase, a doorway)
## or it cuts the corner and runs into what the path was going around. A point on
## the floor above or below does not count.
func _reached(pos: Vector3, index: int) -> bool:
	var point := _path[index]
	if absf(point.y - pos.y) > 1.5:
		return false
	var away := _flat(pos, point)
	if not _is_corner(index):
		return away < 0.9
	# Right on it, or level with it and past it (so a fast runner does not circle it)
	var along := point - _path[index - 1]
	var past := pos - point
	along.y = 0.0
	past.y = 0.0
	return away < 0.35 or (away < 1.2 and past.dot(along) > 0.0)


## Does the path turn sharply at this point?
func _is_corner(index: int) -> bool:
	if index < 1 or index + 1 >= _path.size():
		return false
	var before := _path[index] - _path[index - 1]
	var after := _path[index + 1] - _path[index]
	before.y = 0.0
	after.y = 0.0
	return before.length() > 0.05 and after.length() > 0.05 and before.angle_to(after) > deg_to_rad(50.0)


## Is there floor to run on for the next `reach` metres this way: no drop, and not a
## staircase either (tricks and stairs do not mix)?
func _ground_ahead(dir: Vector3, reach: float) -> bool:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.1:
		return true
	flat = flat.normalized()
	var pos := me.global_position
	var step := 1.0
	while step <= reach:
		var from := pos + flat * step + Vector3(0, 0.6, 0)
		var drop := minf(1.0 + 0.45 * step, 3.6)   # a slope down is fine, the floor below is not
		if _cast(from, from - Vector3(0, 0.6 + drop, 0)).is_empty():
			return false
		step += 1.0
	return true


## Is there a wall right in the way in this direction?
func _blocked(dir: Vector3) -> bool:
	if dir.length() < 0.1:
		return false
	var from := me.global_position + Vector3(0, 1.0, 0)
	return not _cast(from, from + dir.normalized() * 1.4).is_empty()


## Not getting anywhere? Jump (vaults handle low stuff), then try another way.
func _unstick(delta: float, dir: Vector3) -> void:
	var speed := Vector2(me.velocity.x, me.velocity.z).length()
	if dir.length() > 0.1 and speed < 1.0 and me.motor.state != MovementController.State.MANTLE:
		_stuck_time += delta
	else:
		_stuck_time = max(_stuck_time - delta, 0.0)
	if _stuck_time > 0.5 and me.is_on_floor():
		input.jump_pressed = true
	if _stuck_time > 1.2:
		_stuck_time = 0.0
		_escape_dir = Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU)
		_escape_time = 0.7
		_repath = 0.0


func _set_move(world_dir: Vector3) -> void:
	if _dodge_time > 0.0:
		input.move = Vector2(_dodge_side, 0.0)
		return
	var local := world_dir.rotated(Vector3.UP, -input.yaw)
	input.move = Vector2(local.x, -local.z).limit_length(1.0)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------------------
# Maps that move, and gaps only a MapJumpLink crosses

## Are the map's parts on the move (a LayoutEvent), or is the navigation mesh still
## being redone for where they have got to?
func _map_moving() -> bool:
	var map := MapRoot.current
	return map != null and is_instance_valid(map) and (map.shifting or map.nav_pending)


## A map of islands over a drop (it has MapIslands): one where a free swing or a long
## burst is likelier to end in a fall than on a map with walls round it.
func _open() -> bool:
	if _open_map < 0:
		var map := MapRoot.current
		_open_map = 0
		if map != null and is_instance_valid(map):
			for m in map.movers:
				# (moves_node: a part that carries crossings, as on Sky Island. An island
				# marked Over Ground is a machine on solid ground: the Construction Site's crane.)
				var island := m.node as MapIsland
				if (island != null and not island.over_ground) or (island == null and m.moves_node):
					_open_map = 1
	return _open_map == 1


## Is `point` on the same piece of ground as the bot (the same island, or both on none)?
func _same_ground(point: Vector3) -> bool:
	var map := MapRoot.current
	if map == null or not is_instance_valid(map):
		return true
	return map.mover_under(me.global_position) == map.mover_under(point)


## Islands over a drop: if the way it is going runs out of floor within the next
## half second (it came off a vault too fast, an unstick sent it somewhere silly),
## it stops pushing that way and brakes, and drops whatever trick it was about to do.
func _mind_the_edge(world_dir: Vector3) -> Vector3:
	var flat := Vector3(me.velocity.x, 0.0, me.velocity.z)
	var speed := flat.length()
	var heading := flat / speed if speed > 2.0 else Vector3(world_dir.x, 0.0, world_dir.z).normalized()
	if heading.length() < 0.5 or me.motor.grapple.attached:
		return world_dir
	if _floor_ahead(heading, clampf(speed * 0.5, 2.0, 6.0)):
		return world_dir
	input.jump_pressed = false
	input.dive_pressed = false
	input.dive = false
	input.crouch_pressed = false
	input.crouch = false
	input.sprint = false
	_hop_time = 0.0
	_slide_time = 0.0
	_belly_time = 0.0
	_dodge_time = 0.0
	_boost_side = 0.0
	_escape_time = 0.0
	_stuck_time = 0.0
	return -heading if speed > 2.0 else Vector3.ZERO


## Is there something to stand on for the next `reach` metres this way? Unlike
## _ground_ahead this counts a staircase, up or down, as floor: it only says no to a
## real drop.
func _floor_ahead(dir: Vector3, reach: float) -> bool:
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var pos := me.global_position
	var step := 1.0
	while step <= reach:
		var at := pos + flat * step
		if _cast(at + Vector3(0, 0.7 + 0.8 * step, 0), at - Vector3(0, 1.2 + 0.8 * step, 0)).is_empty():
			return false
		step += 1.0
	return true


## Is there a walkway that comes and goes (a MapSpan) underfoot a few steps that way?
func _span_ahead(dir: Vector3) -> bool:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.1:
		return false
	flat = flat.normalized()
	for step in [1.5, 3.0, 4.5]:
		var from: Vector3 = me.global_position + flat * step + Vector3(0, 1.0, 0)
		var hit := _cast(from, from - Vector3(0, 2.5, 0))
		if not hit.is_empty() and (hit.collider as Object).has_meta("span"):
			return true
	return false


## While the map moves: nowhere, unless it stands on a walkway that is being drawn in
## (a MapSpan): then toward that walkway's fixed end, which goes last.
func _hold_spot() -> Vector3:
	var from := me.global_position + Vector3(0, 0.5, 0)
	var hit := _cast(from, from - Vector3(0, 1.5, 0))
	if hit.is_empty() or not (hit.collider as Object).has_meta("span"):
		return Vector3.ZERO
	var span := (hit.collider as Object).get_meta("span") as MapSpan
	if span == null or not is_instance_valid(span):
		return Vector3.ZERO
	var to := span.global_transform * Vector3(0, 0, -2.0) - me.global_position
	to.y = 0.0
	input.sprint = true
	return to.normalized() if to.length() > 0.3 else Vector3.ZERO


## Does the path it has just found stop short of `goal` (somewhere walking cannot reach)?
func _stops_short(goal: Vector3) -> bool:
	if _link_wait > 0.0 or me.get_tree().get_nodes_in_group(MapJumpLink.GROUP).is_empty():
		return false
	if _path.is_empty():
		return true
	var end := _path[_path.size() - 1]
	return _flat(end, goal) > LINK_SHORT or absf(end.y - goal.y) > LINK_SHORT_UP


## Does walking get from `a` to `b` (both in the map)?
func _walkable(a: Vector3, b: Vector3) -> bool:
	var to := _to_nav(b)
	var path := _nav_path(_to_nav(a), to)
	if path.is_empty():
		return false
	var end := path[path.size() - 1]
	return _flat(end, to) < 1.5 and absf(end.y - to.y) < 2.0


## The crossing to take to get from `pos` to `goal`: one it can walk to, that comes
## down somewhere it can walk on from. The nearest such, or null.
func _pick_link(pos: Vector3, goal: Vector3) -> MapJumpLink:
	var best: MapJumpLink = null
	var best_cost := INF
	var nav := me.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(nav) == 0:
		return null   # (the navigation mesh is not there yet: the first moments of a match)
	var links := _links()
	if _by_ground():
		return _route_link(pos, goal, links)
	if _no_link > 0.0:
		return null   # (it looked a moment ago and there was none: every look costs path searches)
	# Lifts are short cuts, never the only way: _pick_lift chooses those, cheaply. Here
	# they would only be more searches.
	links = links.filter(func(l): return l.how != MapJumpLink.How.LIFT)
	# Each question below is a path worked out by the navigation server, the dear part of
	# this, so each is asked once: where a crossing comes down, and whether walking on
	# from there gets to the goal, are the same whether it is taken first or second.
	var downs := {}    # crossing -> where it comes down, on the floor
	var arrives := {}  # crossing -> walking on from there gets to the goal
	var here_to_goal := _flat(pos, goal)
	for l in links:
		var link := l as MapJumpLink
		var from := link.takeoff()
		var cost: float = pos.distance_to(from) + link.landing_point().distance_to(goal)
		var down := _comes_down(link, nav, downs)
		if _flat(down, goal) > here_to_goal + 60.0 or not _walkable(pos, from):
			continue
		if not _arrives(link, goal, nav, downs, arrives):
			# Not there yet: is there a second crossing from where this one lands (island
			# to quad, then quad to the other island)?
			var onward := INF
			for l2 in links:
				var second := l2 as MapJumpLink
				if second == link or not _arrives(second, goal, nav, downs, arrives) or not _walkable(down, second.takeoff()):
					continue
				onward = minf(onward, down.distance_to(second.takeoff()) + second.landing_point().distance_to(goal))
			if onward == INF:
				continue
			cost = pos.distance_to(from) + 30.0 + onward
		if cost < best_cost:
			best = link
			best_cost = cost
	if best == null:
		_no_link = NO_LINK_WAIT
	return best


## Where a crossing comes down, on the floor (kept in `known` for the rest of one _pick_link).
func _comes_down(link: MapJumpLink, nav: RID, known: Dictionary) -> Vector3:
	if not known.has(link):
		known[link] = _from_nav(NavigationServer3D.map_get_closest_point(nav, _to_nav(link.landing_point())))
	return known[link]


## Does walking on from where a crossing comes down get to `goal` (kept in `known` for
## the rest of one _pick_link)?
func _arrives(link: MapJumpLink, goal: Vector3, nav: RID, downs: Dictionary, known: Dictionary) -> bool:
	if not known.has(link):
		known[link] = _gets_to(_comes_down(link, nav, downs), goal)
	return known[link]


## The tractor-beam lift (a MapJumpLink set to Lift) to ride toward `goal`, or null:
## only when the goal is well above it, the beam's foot is on its own floor and the
## link gets off near the goal's height. Walking would get there too; this is quicker.
func _pick_lift(pos: Vector3, goal: Vector3) -> MapJumpLink:
	if _link_wait > 0.0 or goal.y - pos.y < LIFT_WORTH:
		return null
	var best: MapJumpLink = null
	var best_cost := INF
	for l in _links():
		var link := l as MapJumpLink
		if link.how != MapJumpLink.How.LIFT:
			continue
		var foot := link.takeoff()
		var land := link.landing_point()
		if absf(foot.y - pos.y) > 3.0 or land.y - pos.y < LIFT_WORTH * 0.5 or land.y > goal.y + 6.0 or _flat(pos, foot) > LIFT_NEAR:
			continue
		var cost := _flat(pos, foot) + absf(goal.y - land.y) * 3.0 + _flat(land, goal) * 0.5
		if cost < best_cost:
			best = link
			best_cost = cost
	if best == null or NavigationServer3D.map_get_iteration_id(me.get_world_3d().navigation_map) == 0:
		return null
	return best if _walkable(pos, best.takeoff()) else null


## The crossings it could take right now.
func _links() -> Array:
	var out := []
	for n in me.get_tree().get_nodes_in_group(MapJumpLink.GROUP):
		var link := n as MapJumpLink
		if link == null or not link.usable():
			continue
		if link.how == MapJumpLink.How.GRAPPLE and (me.mobility != Mobility.GRAPPLE or link.hook_point() == Vector3.INF):
			continue
		out.append(link)
	return out


## Does walking from `from` end at `goal` (near enough)? Both in the map.
func _gets_to(from: Vector3, goal_at: Vector3) -> bool:
	var goal := _to_nav(goal_at)
	var end := _nav_path(_to_nav(from), goal)
	return not end.is_empty() and _flat(end[end.size() - 1], goal) <= LINK_SHORT and absf(end[end.size() - 1].y - goal.y) <= LINK_SHORT_UP


## A map of many small moving parts joined by crossings (Sky Island: islands and
## stepping pads that bob): routes are worked out part by part (see _route_link)
## rather than by trying every crossing against every other.
func _by_ground() -> bool:
	if _ground_map < 0:
		_ground_map = 0
		var map := MapRoot.current
		if map != null and is_instance_valid(map):
			for m in map.movers:
				if m.moves_node and not m.node is MapIsland:
					_ground_map = 1
	return _ground_map == 1


## Which crossing to take first, on a map of many moving parts: every part is a place
## (the fixed ground is -1), every crossing a way from the part its takeoff is on to the
## part its landing is on. The shortest way, by distance, from the part it stands on to
## the part the goal is on; null if they are the same part, or nothing joins them.
## A crossing that has to wait for its moment (MapJumpLink.ready_now) still counts:
## the bot walks to it and waits there.
func _route_link(pos: Vector3, goal: Vector3, links: Array) -> MapJumpLink:
	var map := MapRoot.current
	if map == null or not is_instance_valid(map):
		return null
	var start := map.standing_on(pos)
	var end := map.standing_on(goal)
	if start == end or end < 0:
		return null
	# Dijkstra over the crossings: the cost of one is the walk to its takeoff (from where
	# the last one came down) plus the jump.
	var cost := {}
	var first := {}
	var at := {}
	var open := []
	for l in links:
		var link := l as MapJumpLink
		var places := _places_of(link, map)
		if places[0] == start:
			cost[link] = pos.distance_to(link.takeoff()) + link.takeoff().distance_to(link.landing_point())
			first[link] = link
			open.append(link)
	var done := {}
	while not open.is_empty():
		var best_i := 0
		for i in open.size():
			if cost[open[i]] < cost[open[best_i]]:
				best_i = i
		var link: MapJumpLink = open[best_i]
		open.remove_at(best_i)
		if done.has(link):
			continue
		done[link] = true
		var lands: int = _places_of(link, map)[1]
		if lands == end:
			return first[link]
		for l2 in links:
			var next := l2 as MapJumpLink
			if done.has(next) or _places_of(next, map)[0] != lands:
				continue
			var c: float = cost[link] + link.landing_point().distance_to(next.takeoff()) + next.takeoff().distance_to(next.landing_point())
			if c < float(cost.get(next, INF)):
				cost[next] = c
				first[next] = first[link]
				open.append(next)
	return null


## [the part a crossing sets off from, the part it comes down on] (see _route_link).
## They never change: a crossing rides the part it sets off from.
func _places_of(link: MapJumpLink, map: MapRoot) -> Array:
	var key := link.get_instance_id()
	if not _link_places.has(key):
		_link_places[key] = [map.standing_on(link.takeoff()), map.standing_on(link.landing_point())]
	return _link_places[key]


## The nearest crossing that leads off the island it is on (which is about to go down).
func _escape_link(pos: Vector3) -> MapJumpLink:
	var map := MapRoot.current
	var here := map.island_at(pos) if map != null and is_instance_valid(map) else null
	var best: MapJumpLink = null
	if NavigationServer3D.map_get_iteration_id(me.get_world_3d().navigation_map) == 0:
		return null
	for l in _links():
		var link := l as MapJumpLink
		if not link.leaves or link.island() != here or not _walkable(pos, link.takeoff()):
			continue
		if best == null or pos.distance_to(link.takeoff()) < pos.distance_to(best.takeoff()):
			best = link
	return best


## At the crossing it was walking to? Then go.
func _start_link() -> void:
	if not is_instance_valid(_link) or not _link.usable():
		_link = null
		return
	if _link.how == MapJumpLink.How.LIFT:
		# A tractor beam: it has it as soon as it walks in (and lifts it off the floor).
		if _flat(me.global_position, _link.takeoff()) > 1.2 or absf(me.global_position.y - _link.takeoff().y) > 2.5:
			return
	elif not me.is_on_floor() or _flat(me.global_position, _link.takeoff()) > 0.9 or absf(me.global_position.y - _link.takeoff().y) > 1.5:
		return
	if _link.how == MapJumpLink.How.GRAPPLE and not me.motor.grapple.ready_to_fire():
		input.move = Vector2.ZERO   # wait for the hook
		return
	if not _link.ready_now() or (_link.how == MapJumpLink.How.BOOST and me.motor.boost_readiness() < 1.0):
		input.move = Vector2.ZERO   # wait for the moment (the far side comes round), or for the boots
		return
	_link_flying = true
	_link_time = 0.0
	_link_hooked = false
	_link_left = false
	_link_boosted = false
	_link_gliding = false
	if DevArgs.sync_log:
		print("BOT_LINK %d %s start" % [me.peer_id, MapJumpLink.How.keys()[_link.how].to_lower()])


## One frame of a crossing: aim and hold the rope, or run off the edge, then steer
## for the landing until it is down.
func _fly_link(delta: float) -> void:
	_link_time += delta
	if is_instance_valid(_link) and _link.how == MapJumpLink.How.LIFT:
		_ride_lift()
		return
	if not is_instance_valid(_link) or _link_time > LINK_GIVE_UP:
		_end_link(false)
		return
	var pos := me.global_position
	var land := _link.landing_point()
	var g := me.motor.grapple
	var to := Vector3(land.x - pos.x, 0.0, land.z - pos.z)
	if not me.is_on_floor():
		_link_left = true
	elif _link_left and _link_time > 0.4 and not g.attached:
		_end_link(_flat(pos, land) < 8.0)   # down again
		return
	input.grapple = false
	if _link.how == MapJumpLink.How.GRAPPLE:
		var hook := _link.hook_point()
		var eye := me.eye_position()
		var aim := (hook - eye).normalized()
		if not _link_hooked:
			if g.attached:
				_link_hooked = true
			elif _link_time > 0.5 and not g.busy():
				_end_link(false)   # the hook did not catch
				return
			else:
				input.yaw = atan2(-aim.x, -aim.z)
				input.pitch = asin(clampf(aim.y, -1.0, 1.0))
				input.grapple = true
				input.grapple_pressed = true
				return
		if g.attached:
			# Ride the rope until close under the hook, or level with it and over the landing.
			var close := g.rope_origin(me).distance_to(g.anchor) < g.tuning.grapple_pull_stop + 1.5
			var over := pos.y > land.y + 1.0 and to.length() < 2.5
			input.grapple = not (close or over)
			input.yaw = atan2(-aim.x, -aim.z)
			input.pitch = asin(clampf(aim.y, -1.0, 1.0))
	elif _link.how == MapJumpLink.How.HOP or _link.how == MapJumpLink.How.BOOST:
		if not _link_left:
			# The run-up: sprint at the landing and jump where the floor runs out.
			input.sprint = true
			var ahead := pos + to.normalized() * 0.5 + Vector3(0, 0.3, 0)
			if _cast(ahead, ahead - Vector3(0, 1.2, 0)).is_empty():
				input.jump_pressed = true
			_link_jumped = _link_time
		elif _link.how == MapJumpLink.How.BOOST:
			input.sprint = false
			if not _link_boosted and _link_time - _link_jumped >= 0.03:
				# The boots, toward the landing and up: the higher the landing, the steeper
				# (about 25 degrees for one level with the takeoff, 60 for one 6 m up).
				var lift := deg_to_rad(clampf((_link.rise_at_landing() + 2.5) * 7.0, 10.0, 60.0))
				input.boost_pressed = true
				input.boost_dir = to.normalized() * cos(lift) + Vector3.UP * sin(lift)
				_link_boosted = true
			# Past the top of the climb: glide on (it holds its height) until the landing is
			# close enough to drop onto.
			var speed := Vector2(me.velocity.x, me.velocity.z).length()
			var above := pos.y - land.y
			var drop_reach := speed * sqrt(2.0 * maxf(above, 0.1) / 22.0) + 1.0
			if _link_boosted and me.velocity.y < 0.5 and above > 0.3 and to.length() > drop_reach:
				input.glide = true
				input.glide_pressed = not _link_gliding
				_link_gliding = true
			else:
				input.glide = false
		else:
			input.sprint = false
	else:
		input.sprint = false
	# Steer for the landing; ease off (push back against the speed) when about to overshoot.
	var dir := to.normalized() if to.length() > 0.4 else Vector3.ZERO
	var flat_speed := Vector3(me.velocity.x, 0.0, me.velocity.z)
	if _link_left and not g.attached and flat_speed.length() > 1.0 and to.length() < flat_speed.length() * 0.55:
		dir = -flat_speed.normalized()
	if _link.how == MapJumpLink.How.LEAP or not g.attached:
		var face := to if to.length() > 0.5 else Vector3.FORWARD.rotated(Vector3.UP, input.yaw)
		input.yaw = atan2(-face.x, -face.z)
		input.pitch = 0.0
	_set_move(dir)


## One frame of a ride up a tractor beam: keep to the middle of the beam until just
## under the floor to get off at, then steer out over it and come down. It goes on
## looking where it was (it can fight on the way up).
func _ride_lift() -> void:
	var pos := me.global_position
	var foot := _link.takeoff()
	var land := _link.landing_point()
	var rise := maxf(land.y - foot.y, 1.0)
	if _link_time > rise / 6.0 + 8.0:
		_end_link(false)   # (it should have been up long ago)
		return
	if not me.is_on_floor():
		_link_left = true
	elif _link_left and _link_time > 0.6:
		if DevArgs.sync_log:
			print("BOT_LIFT %d down at %.1f,%.1f,%.1f wanted %.1f,%.1f,%.1f after %.1f s" % [me.peer_id, pos.x, pos.y, pos.z, land.x, land.y, land.z, _link_time])
		_end_link(absf(pos.y - land.y) < 3.0 and _flat(pos, land) < 8.0)   # down again: on the floor it wanted?
		return
	input.grapple = false
	input.sprint = false
	var out := pos.y > land.y - 1.0
	if out and not _link_left:
		out = false
	if _link_left and not out and _flat(pos, foot) > 3.5:
		if DevArgs.sync_log:
			print("BOT_LIFT %d out of the beam at %.1f,%.1f,%.1f" % [me.peer_id, pos.x, pos.y, pos.z])
		_end_link(false)   # knocked out of the beam on the way up
		return
	var to := (land if out else foot) - pos
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.25 else Vector3.ZERO
	if out:
		# Over the landing already? Push back against the speed, so it drops onto it.
		var flat_speed := Vector3(me.velocity.x, 0.0, me.velocity.z)
		if flat_speed.length() > 1.0 and to.length() < flat_speed.length() * 0.45:
			dir = -flat_speed.normalized()
	if _target == null and to.length() > 0.5:
		input.yaw = atan2(-to.x, -to.z)
		input.pitch = 0.0
	_set_move(dir)


func _end_link(made_it: bool) -> void:
	if DevArgs.sync_log:
		print("BOT_LINK %d %s" % [me.peer_id, "landed" if made_it else "failed"])
	_link = null
	_link_flying = false
	input.grapple = false
	input.glide = false
	_repath = 0.0
	_path_goal = Vector3.INF
	if not made_it:
		_link_wait = 4.0


# ---------------------------------------------------------------------------
# Movement tricks

func _on_hit(shooter: int, target: int, _damage: float, _head: bool) -> void:
	if target != me.peer_id or not me.alive:
		return
	if shooter != me.peer_id:
		_attacker = shooter
		_attacked_time = _time
		_retarget = 0.0   # think again about who to fight
		for other in _others():
			if other.peer_id == shooter:
				_hear(shooter, other.global_position, true)   # it knows roughly where that came from
	if _dodge_time > 0.0:
		return
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	if _light() and not _ground_ahead(Vector3.RIGHT.rotated(Vector3.UP, input.yaw) * side, 6.0 * _air()):
		return   # low gravity: a dodge that way would float it off an edge
	if _open():
		# Islands over a drop: only dodge toward a side with floor under it (a boost or a blink goes far).
		if not _ground_ahead(Vector3.RIGHT.rotated(Vector3.UP, input.yaw) * side, 6.0):
			side = -side
			if not _ground_ahead(Vector3.RIGHT.rotated(Vector3.UP, input.yaw) * side, 6.0):
				return
		if me.jetpack and me.jetpack.fuel > 0.5 and _rng.randf() < d.dodge_chance * 0.7:
			_start_jet(0.35)
			return
		if _rng.randf() < d.dodge_chance and _ground_ahead(Vector3.RIGHT.rotated(Vector3.UP, input.yaw) * side, 8.0):
			_dodge_side = side
			_dodge_time = 0.45
			if me.is_on_floor():
				input.jump_pressed = true
		return
	if me.jetpack and me.jetpack.fuel > 0.5 and _rng.randf() < d.dodge_chance * 0.7:
		_start_jet(0.35)   # hop up out of the line of fire
	if me.blink and me.blink.ready() and _rng.randf() < d.dodge_chance * 0.7:
		_blink_side = side   # a sideways blink
		return
	if _rng.randf() < d.dodge_chance * 0.5 and me.motor.boost_readiness() >= 1.0:
		_boost_side = side   # a sideways rocket burst
		return
	if _rng.randf() < d.dodge_chance:
		# Flip dodge: jump, then jump again in the air toward a side.
		_dodge_side = side
		_dodge_time = 0.45
		if me.is_on_floor():
			input.jump_pressed = true


func _dodge(delta: float) -> void:
	if _dodge_time <= 0.0:
		return
	_dodge_time -= delta
	if not me.is_on_floor() and me.motor.state == MovementController.State.AIR and me.velocity.y < 4.0:
		input.jump_pressed = true   # mid-air jump = flip toward _dodge_side
		_dodge_time = min(_dodge_time, 0.1)


## Grapple toward high ground or a far-away target (Hard and Expert).
func _grapple(delta: float, visible: bool) -> void:
	var g := me.motor.grapple
	if g.hooked_player():
		# Reeling someone in: hold on, and flying-kick them once close.
		_grapple_time += delta
		input.grapple = true
		input.jump_pressed = false   # a jump would let go of the rope
		var t := g.target as Player
		if t and me.global_position.distance_to(t.global_position) < 9.0 and _rng.randf() < delta * 12.0:
			input.kick_pressed = true
		return
	if g.busy():
		input.grapple = true   # the hook is on its way (letting go would call it back)
		input.jump_pressed = false
		return
	if g.attached:
		_grapple_time += delta
		input.grapple = true
		# Let go once past the anchor and rising, once reeled in close (so the pull's
		# speed flings it on instead of pinning it to the wall), or after a while.
		var passed := _flat(me.global_position, _grapple_start) > _flat(g.anchor, _grapple_start)
		var close := g.rope_origin(me).distance_to(g.anchor) < g.tuning.grapple_pull_stop + 1.0
		if (passed and me.velocity.y > 0.0) or close or _grapple_time > 1.6:
			input.grapple = false
		return
	input.grapple = false
	if visible and _hook_player(delta):
		return
	if _open():
		return   # islands over a drop: a free swing ends in the clouds (crossings go by MapJumpLink)
	# Toward its target when it can see it, otherwise toward where it is walking.
	var spot := _target_spot() if visible or _goal == Vector3.INF else _from_nav(_goal)
	if not d.grapples or spot == Vector3.INF or not g.ready_to_fire():
		return
	var dist := me.global_position.distance_to(spot)
	var higher := spot.y - me.global_position.y > 2.5
	if not (higher or (dist > 25.0 and not visible)) or _rng.randf() > delta * 1.5:
		return
	# Aim up and ahead, toward the target, and hook whatever is there. Not indoors,
	# though: under a ceiling a swing only throws it off the stairs it is climbing.
	var eye := me.eye_position()
	if not _cast(eye, eye + Vector3(0, GRAPPLE_HEADROOM, 0)).is_empty():
		return
	var to := spot - me.global_position
	to.y = 0.0
	var point := me.global_position + to.normalized() * minf(dist, 18.0) + Vector3(0, 9.0, 0)
	var dir := (point - eye).normalized()
	var hit := _cast(eye, eye + dir * g.tuning.grapple_range)
	if hit.is_empty() or hit.position.y < me.global_position.y + 3.0:
		return
	input.yaw = atan2(-dir.x, -dir.z)
	input.pitch = asin(clamp(dir.y, -1.0, 1.0))
	input.grapple = true
	input.grapple_pressed = true
	_grapple_time = 0.0
	_grapple_start = me.global_position


## Blink: sideways when just hit, toward its target when it is out of range, or up
## to higher ground it is heading for. Easy bots hardly use it.
func _blink(delta: float, visible: bool) -> void:
	input.grapple = false
	var b := me.blink
	if b == null or not b.ready():
		return
	var dir := Vector3.ZERO
	if _blink_side != 0.0:
		dir = Vector3.RIGHT.rotated(Vector3.UP, input.yaw) * _blink_side
		_blink_side = 0.0
	else:
		var spot := _target_spot() if visible or _goal == Vector3.INF else _from_nav(_goal)
		if spot == Vector3.INF:
			return
		var rate: float = BLINK_RATE[d.level]
		if _rng.randf() > delta * rate:
			return
		var to := spot - me.global_position
		var flat := Vector3(to.x, 0.0, to.z)
		var dist := flat.length()
		var higher := to.y > 2.5 and dist < Blink.RANGE * 1.5
		var close_in := dist > (FAR + 6.0 if not _melee else 4.0) and (visible or dist > 20.0)
		if not (higher or close_in) or dist < 0.5:
			return
		dir = flat.normalized()
		if higher:
			dir = (dir + Vector3(0, clampf(to.y / maxf(dist, 1.0), 0.3, 1.2), 0)).normalized()
		elif not _ground_ahead(dir, Blink.RANGE):
			return   # nothing to land on that way
		else:
			dir = (dir + Vector3(0, 0.12, 0)).normalized()
	if (_light() or _open()) and not _ground_ahead(Vector3(dir.x, 0, dir.z).normalized(), Blink.RANGE):
		return
	input.mobility_dir = dir
	input.grapple_pressed = true


## Jetpack (everyone has one: Space held in mid-air): short bursts to reach higher
## ground, to hop over whatever is in the way as it closes in on someone far off, and to
## hop out of the way when hit. Like a player it jumps first if it is on the floor and
## keeps Space down: the jetpack lights a moment into the air (see
## MovementController.space_jet). It keeps some fuel back. `plan`: it may think of a
## burst of its own (over a drop it only takes the hop out of the way, see _dodge).
func _jetpack(delta: float, visible: bool, plan: bool) -> void:
	var jet := me.jetpack
	if jet == null or _link != null or _terminal != null:
		if _jet_time > 0.0:
			input.jump_held = false   # (a crossing or a terminal takes over: let go)
		_jet_time = 0.0
		return
	if _jet_time > 0.0:
		_jet_time -= delta
		input.jump_held = _jet_time > 0.0 and jet.fuel > 0.1
		if not input.jump_held:
			_jet_time = 0.0
		return
	if not plan or jet.fuel < 0.6:
		return
	var spot := _target_spot() if visible or _goal == Vector3.INF else _from_nav(_goal)
	if spot == Vector3.INF:
		return
	var rate: float = JETPACK_RATE[d.level]
	if _rng.randf() > delta * rate:
		return
	var to := spot - me.global_position
	var dist := Vector2(to.x, to.z).length()
	if to.y > 2.5 and dist < 25.0:
		_start_jet(clampf(to.y / 6.0 + 0.3, 0.4, 1.4))   # up to their level
	elif visible and dist > FAR + 6.0 and not _light():
		_start_jet(0.5)   # a hop over whatever is in the way as it closes in


## Fly the jetpack for `seconds`: Space down (and a jump first, from the floor), held for
## as long as it takes the jetpack to light as well.
func _start_jet(seconds: float) -> void:
	if me.jetpack == null:
		return
	_jet_time = seconds + me.motor.tuning.space_hold_time + 0.05
	input.jump_held = true
	if me.is_on_floor():
		input.jump_pressed = true


## Hook the target it is fighting, now and then, to reel them in for a flying kick.
func _hook_player(delta: float) -> bool:
	var g := me.motor.grapple
	if _target == null or not g.ready_to_fire() or not g.hook_players or not Match.running or me.kick_readiness() < 1.0:
		return false
	var dist := me.global_position.distance_to(_target.global_position)
	if dist < 7.0 or dist > minf(32.0, g.tuning.grapple_range - 4.0):
		return false
	if _open() and not _same_ground(_target.global_position):
		return false   # across a drop: reeling in would pull them both off
	if _rng.randf() > delta * (0.45 if d.grapples else 0.15):
		return false
	var eye := me.eye_position()
	var lead := 0.08 + dist / HookLine.SPEED   # (the hook takes a moment to get there)
	var point := Grapple.target_point(_target) + _target.velocity * lead
	point += Vector3(_rng.randfn(), _rng.randfn() * 0.5, _rng.randfn()) * dist * tan(deg_to_rad(d.aim_error)) * 0.5
	var dir := (point - eye).normalized()
	# They are not there yet: all it can ask is a clear flight to where they will be.
	if not _cast(eye, point).is_empty():
		return false
	input.yaw = atan2(-dir.x, -dir.z)
	input.pitch = asin(clamp(dir.y, -1.0, 1.0))
	input.grapple = true
	input.grapple_pressed = true
	_grapple_time = 0.0
	_grapple_start = me.global_position
	_hook_frame = true
	return true


## Someone right in front of it: kick them.
func _kick(delta: float, visible: bool) -> void:
	if not visible or _target == null or me.kick_readiness() < 1.0 or me.motor.grapple.hooked_player() or not Match.running:
		return
	var to := _target.global_position + Vector3(0, CHEST, 0) - me.eye_position()
	if to.length() > Kick.REACH + Player.CAPSULE_RADIUS - 0.1:
		return
	if me.aim_forward().angle_to(to) > deg_to_rad(Kick.ARC * 0.7):
		return
	if _rng.randf() < delta * (5.0 if not _melee else 2.0):
		input.kick_pressed = true


## Rocket boots: to dodge when hit, to close in on someone far off, and mid-swing to
## whip round the hook faster. Easier bots use them less.
func _boost(delta: float, visible: bool) -> void:
	var m := me.motor
	if m.boost_readiness() < 1.0:
		_boost_side = 0.0
		return
	var keen := 1.0 if d.grapples else 0.4
	var right := Vector3.RIGHT.rotated(Vector3.UP, input.yaw)
	if _boost_side != 0.0:
		input.boost_pressed = true
		input.boost_dir = right * _boost_side + Vector3.UP * 0.35
		_boost_side = 0.0
		return
	var g := m.grapple
	var speed := me.velocity.length()
	if g.attached and not g.hooked_player() and _grapple_time > 0.3 and _grapple_time < 1.0 and speed > 8.0 \
			and _rng.randf() < delta * 2.5 * keen:
		input.boost_pressed = true   # along the swing: faster round the hook
		input.boost_dir = me.velocity.normalized()
		return
	if visible and _target != null and not g.attached:
		var to := _target.global_position - me.global_position
		var far := 6.0 if _melee else FAR + 6.0
		if to.length() > far and to.length() < 40.0 and _rng.randf() < delta * 0.35 * keen and _ground_ahead(to, (16.0 if _open() else 6.0) * _air()):
			input.boost_pressed = true   # close in
			input.boost_dir = Vector3(to.x, 0.0, to.z).normalized() + Vector3.UP * 0.25


# ---------------------------------------------------------------------------
# Aiming and shooting

func _aim(delta: float, perceived: Array, move_dir: Vector3) -> void:
	if me.motor.grapple.attached and _grapple_time < 0.05:
		return   # just hooked: keep looking at the hook point this frame
	var eye := me.eye_position()
	var target := Vector3.INF
	if not perceived.is_empty():
		_head_timer -= delta
		if _head_timer <= 0.0:
			_head_timer = _rng.randf_range(0.8, 2.0)
			_go_head = _rng.randf() < d.head_chance
		var point: Vector3 = perceived[1]
		var vel: Vector3 = perceived[2]
		point += vel * d.reaction_time * d.lead   # guess where you are now
		var dist := eye.distance_to(point)
		var w: WeaponData = me.weapon.data if me.weapon else null
		if w and w.is_projectile():
			# Rockets and grenades: lead by the flight time, aim low (the blast does the rest), and lob grenades.
			# A bolt has no blast: it aims at the body, high enough for its arc.
			var flight := dist / w.projectile_speed
			point += vel * flight * d.lead
			if w.explosive:
				point.y -= 0.7 if point.y - 0.7 > me.global_position.y - 1.0 else 0.0
			if w.projectile_gravity > 0.0:
				# The low arc through the point, above or below (out of reach: 45 degrees, as far as it goes).
				var g := w.projectile_gravity
				var s2 := w.projectile_speed * w.projectile_speed
				var flat := Vector2(point.x - eye.x, point.z - eye.z).length()
				var under := s2 * s2 - g * (g * flat * flat + 2.0 * (point.y - eye.y) * s2)
				if flat > 0.01:
					point.y = eye.y + flat * ((s2 - sqrt(under)) / (g * flat) if under >= 0.0 else 1.0)
			dist = eye.distance_to(point)
			_lob = point
		_error += Vector3(_rng.randfn(), _rng.randfn() * 0.6, _rng.randfn()) * delta * 2.0
		_error = _error.limit_length(1.0)
		target = point + _error * dist * tan(deg_to_rad(d.aim_error))
	elif _target != null and _known.has(_target.peer_id) and _time - float(_known[_target.peer_id][0]) < LOOK_TIME:
		target = _known[_target.peer_id][1] + Vector3(0, CHEST, 0)   # look toward what it just saw or heard
	elif move_dir.length() > 0.1:
		target = eye + move_dir * 10.0
	if target == Vector3.INF:
		return
	var to := target - eye
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	var step := deg_to_rad(d.turn_speed) * delta
	input.yaw += clamp(wrapf(want_yaw - input.yaw, -PI, PI), -step, step)
	input.pitch = clamp(input.pitch + clamp(want_pitch - input.pitch, -step, step), deg_to_rad(-89.0), deg_to_rad(89.0))


func _fire(delta: float, perceived: Array) -> void:
	_fire_wait -= delta
	var w := me.weapon
	if w == null:
		_burst = 0.0
		return   # Deathmatch, empty hands: it can only kick (see _kick)
	if _melee and me.winding_up():
		input.fire = true   # a wound-up swing is held (through losing sight of you) until there is someone to hit
	if w.ammo == 0 and not w.is_reloading():
		w.start_reload()
	# Top up a half-empty gun when nobody is in sight.
	if perceived.is_empty() and not w.is_reloading() and w.ammo < w.data.magazine / 2 and _rng.randf() < delta:
		w.start_reload()
	if perceived.is_empty() or not Match.running:
		_burst = 0.0
		return
	# Shoot when the view is close enough to where it wants to aim.
	var eye := me.eye_position()
	var want: Vector3 = (perceived[1] as Vector3) - eye
	var dist := want.length()
	if dist > _reach + (WIND_FROM if _melee else 0.0):
		return   # a shotgun does not waste shells at long range
	if w.data.is_projectile() and dist < w.data.splash_radius * 0.9:
		return   # too close: it would blow itself up
	if w.data.is_projectile() and _lob != Vector3.INF:
		want = _lob - eye   # it aims off you on purpose: judge the aim against that point
	var off := me.aim_forward().angle_to(want)
	if w.data.is_melee():
		# Hold the swing (wind it up), and let go once in reach, roughly facing you and
		# wound up as far as it meant to: not setting input.fire is letting go.
		var facing := off < deg_to_rad(w.data.arc_degrees * 0.7)
		if me.winding_up():
			# Hard and Expert bots, above you with a swing wound up: they drive it into the
			# floor beside you instead (a ground slam: crouch held as the swing is let go).
			if d.level >= 2 and me.can_ground_slam() and eye.y - (perceived[1] as Vector3).y > 1.5 \
					and Vector2(want.x, want.z).length() < GroundSlam.RADIUS * 0.7 and me.melee_charge() >= minf(_wind_goal, 0.4):
				input.crouch = true
				input.fire = false
				_fire_wait = d.fire_gap * _rng.randf_range(0.3, 0.7)
			elif dist <= _reach and facing and me.melee_charge() >= _wind_goal:
				input.fire = false
				_fire_wait = d.fire_gap * _rng.randf_range(0.3, 0.7)
		elif w.can_fire() and _fire_wait <= 0.0:
			input.fire_pressed = true
			input.fire = true
			# Easy bots mostly tap; Expert ones wind right up.
			_wind_goal = clampf(_rng.randf_range(0.15, 0.6) + 0.15 * d.level, 0.0, 1.0)
		return
	var allowed: float = max(atan(0.35 / max(dist, 0.1)), deg_to_rad(1.0))
	if w.data.id in STEADY_GUNS:
		allowed *= 0.6   # waits for a clean shot
	var on_target := off < allowed + deg_to_rad(d.aim_error) * 0.5
	if w.data.automatic:
		# Bursts: hold the trigger for a moment, then pause (longer on easier levels).
		if _burst > 0.0:
			_burst -= delta
			input.fire = on_target or _burst > 0.1
			if _burst <= 0.0:
				_fire_wait = d.fire_gap * _rng.randf_range(1.5, 2.6)
			return
		if on_target and _fire_wait <= 0.0:
			_burst = _rng.randf_range(0.35, 0.9)
			input.fire_pressed = true
			input.fire = true
		return
	if _fire_wait > 0.0:
		return
	if on_target:
		input.fire_pressed = true
		input.fire = true
		_fire_wait = maxf(d.fire_gap, w.data.fire_interval) * _rng.randf_range(0.85, 1.25)
