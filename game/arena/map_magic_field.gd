class_name MapMagicField
extends Node
## Makes a map's magic answer to the players in it (Empyrean Tower). One per map,
## anywhere in it. It is the only part of the magic that runs any code while you play:
##
##  - A few times a second it finds every MapMagic box with Reacts ticked that has a
##    player within Reach (4 m, 13 ft) in plain sight, and tells the box who (the box
##    does the rest: motes scatter, books and spirits flee, candles gutter). In plain
##    sight means nothing solid stands between the player's chest and the box: walls,
##    floors and furniture block it, glass does not.
##  - It tells the map's rune surfaces (the "masonry", "ring_flags" and "arcane_plates"
##    patterns) where those players are, and the runes within Reach that face them
##    glow brighter. (A wall's far side faces away, so it never shows through a wall.)
##  - While the map's event runs (Event: a node with level_at(), running and elapsed)
##    it tells every box, stream and rune how far along it is, and they liven up.
##
## Who counts: every living player and bot, yours included, on every copy of the game
## by itself (nothing is sent). Not the dead, not spectators, and not anyone moving
## crouched at walking pace: sneaking is how you pass without setting it off.

const REACH := 4.0             ## metres (13 ft)
const CHECK := 0.1             ## seconds between looks
const CHEST := 0.9             ## metres above the feet
const BAND := 8.0              ## metres: the height of one band (see _gather)
const SNEAK := 1.25            ## crouched and no faster than this x the crouch-walk speed: unnoticed
const CROUCH_SPEED := 4.0      ## (MovementTuning.crouch_speed)
const GLASS := "glass"
const RUNE_SLOTS := 4
const STATE_GROUND := 0        ## (MovementController.State.GROUND and .CROUCH: on your feet)
const STATE_CROUCH := 3

## The map event that livens the magic up while it runs.
@export var event: NodePath

## Tests: stand-ins for the match's players, [{"id": 1, "pos": chest in the world}, ...].
var test_actors = null

var boxes: Array[MapMagic] = []
var streams: Array[MapMagicStream] = []
var surge := 0.0
var _map: MapRoot
var _event: Node
var _clock := 0.0
var _busy := {}                 # MapMagic -> true: answering or settling
var _bands := {}                # height band -> the answering boxes that reach into it
var _info := {}                 # MapMagic -> [its middle (world), (its reach from there) squared]
var _rune_mats: Array[ShaderMaterial] = []
var _rune_level := {}           # player id -> 0..1
var _rune_want := {}            # player id -> still near
var _rune_where := {}           # player id -> chest (world)
var _sent_surge := -1.0
var _seen := []                 # the players noticed at the last look
var _looked := false            # there has been a look since the last frame
var _runes_lit := false


func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		set_process(false)
		return
	_gather.call_deferred()


func _gather() -> void:
	_map = MapRoot.of(self)
	if _map == null:
		return
	boxes.clear()
	streams.clear()
	for n in _map.find_children("*", "Node3D", true, false):
		if n is MapMagic:
			boxes.append(n)
		elif n is MapMagicStream:
			streams.append(n)
	# Where each answering box is, sorted into bands of height so a player is only ever
	# compared with the few boxes level with them.
	_bands.clear()
	_info.clear()
	for box in boxes:
		if not box.reacts:
			continue
		var bounds := box.box().grow(REACH)
		_info[box] = [box.global_position, pow(box.size.length() * 0.5 + REACH, 2.0)]
		for band in range(floori(bounds.position.y / BAND), floori(bounds.end.y / BAND) + 1):
			if not _bands.has(band):
				_bands[band] = []
			_bands[band].append(box)
	_event = get_node_or_null(event) if not event.is_empty() else null
	_rune_mats.clear()
	if _map.palette != null:
		for kind in _map.palette.surface:
			var mat := _map.material_for(kind) as ShaderMaterial
			if mat != null and int(mat.get_shader_parameter("style")) in [19, 20, 21] and not _rune_mats.has(mat):
				_rune_mats.append(mat)


func _physics_process(delta: float) -> void:
	if _map == null:
		return
	_clock += delta
	if _clock >= CHECK:        # (here, not in _process: it asks the physics world what is in the way)
		_clock = 0.0
		_seen = _actors()
		_looked = true
		_look(_seen)


func _process(delta: float) -> void:
	if _map == null:
		return
	var level := 0.0
	if _event != null and is_instance_valid(_event) and _event.get("running") == true:
		level = float(_event.call("level_at", _event.get("elapsed")))
	surge = level
	var moving := surge > 0.001 or absf(surge - _sent_surge) > 0.001
	for box: MapMagic in (boxes if moving else _busy.keys()):
		box.ease(delta, surge)
		if not box.stirred():
			_busy.erase(box)
	if moving:
		for s in streams:
			s.surge = surge
	_runes(delta, _seen, _looked, moving)
	_looked = false
	_sent_surge = surge


## Is `player` (a Player) setting the magic off? Alive, in the world, and not sneaking.
static func noticed(player: Node) -> bool:
	if not player.get("alive") or (player.has_method("visible_in_world") and not player.visible_in_world()):
		return false
	var motor = player.get("motor")
	var state: int
	var crouched: bool
	if motor != null:
		state = int(motor.state)
		crouched = motor.crouched
	else:
		var pose: int = player.pose_at(player.latest_time())
		state = pose % 100
		crouched = (pose / 100) % 10 == 1
	if not crouched or not (state == STATE_GROUND or state == STATE_CROUCH):
		return true
	var v: Vector3 = player.latest_velocity()
	return Vector2(v.x, v.z).length() > CROUCH_SPEED * SNEAK


func _actors() -> Array:
	if test_actors != null:
		return test_actors
	var out := []
	var net := get_node_or_null("/root/Net")
	var arena: Node = net.get("arena") if net != null else null
	if arena == null or not is_instance_valid(arena) or arena.get("players_root") == null:
		return out
	for p in arena.players_root.get_children():
		if noticed(p):
			out.append({"id": int(p.peer_id), "pos": (p as Node3D).global_position + Vector3(0, CHEST, 0)})
	return out


func _look(actors: Array) -> void:
	var found := {}       # MapMagic -> {player id: where}
	for a: Dictionary in actors:
		var pos: Vector3 = a.pos
		for box: MapMagic in _bands.get(floori(pos.y / BAND), []):
			var info: Array = _info[box]
			if pos.distance_squared_to(info[0]) > info[1]:
				continue       # (not even near its box)
			var near := box.nearest(pos)
			if near.distance_to(pos) <= REACH and (in_sight(pos, near) or in_sight(pos, info[0])):
				if not found.has(box):
					found[box] = {}
				found[box][a.id] = pos
	for box: MapMagic in found:
		box.seen(found[box])
		_busy[box] = true
	for box: MapMagic in _busy:
		if not found.has(box):
			box.seen({})


## Is there nothing solid between two points? Glass does not count.
func in_sight(from: Vector3, to: Vector3) -> bool:
	var space := _map.get_world_3d().direct_space_state if _map.is_inside_tree() else null
	if space == null:
		return true
	var at := from
	for i in 4:
		if at.distance_to(to) < 0.05:
			return true
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, to, 1))
		if hit.is_empty():
			return true
		var inside: Vector3 = hit.position - hit.normal * 0.04
		if _map.material_at(_map.global_transform.affine_inverse() * inside, 0.0) != GLASS:
			return false
		at = hit.position + (to - at).normalized() * 0.35      # through the pane and on
	return false


func _runes(delta: float, actors: Array, looked: bool, moving: bool) -> void:
	if _rune_mats.is_empty():
		return
	if looked:
		for id in _rune_want:
			_rune_want[id] = false
		for a: Dictionary in actors:
			_rune_want[a.id] = true
			_rune_where[a.id] = a.pos
			if not _rune_level.has(a.id):
				_rune_level[a.id] = 0.0
	var list := []
	for id in _rune_level.keys():
		var want := 1.0 if _rune_want.get(id, false) else 0.0
		var level: float = move_toward(_rune_level[id], want, delta * (MapMagic.RISE if want > _rune_level[id] else MapMagic.FALL))
		if level <= 0.0 and want <= 0.0:
			_rune_level.erase(id)
			_rune_want.erase(id)
			_rune_where.erase(id)
			continue
		_rune_level[id] = level
		list.append([level, _rune_where[id]])
	if list.is_empty() and not _runes_lit and not moving:
		return
	list.sort_custom(func(a, b): return a[0] > b[0])
	var near := PackedVector4Array()
	for i in RUNE_SLOTS:
		if i < list.size():
			var p: Vector3 = list[i][1]
			near.append(Vector4(p.x, p.y, p.z, list[i][0]))
		else:
			near.append(Vector4.ZERO)
	for mat in _rune_mats:
		mat.set_shader_parameter("near", near)
		mat.set_shader_parameter("stir", surge)
	_runes_lit = not list.is_empty()


## How brightly the runes near player `id` are lit by them: 0..1 (tests).
func rune_level(id: int) -> float:
	return _rune_level.get(id, 0.0)
