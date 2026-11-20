extends Node
## The body of tests/empyrean_play_test.gd. A separate file because it uses the game's
## autoloads (Net, Match, Game), which only exist once the test's SceneTree is running.

const TIER := 30.5

var _ok := true
var arena: Node
var me: Player


static func at(r: float, deg: float, y: float) -> Vector3:
	return Vector3(r * sin(deg_to_rad(deg)), y, r * cos(deg_to_rad(deg)))


func run() -> void:
	Game.start_practice("empyrean")
	await _frames(40)
	arena = Net.arena
	_check(arena != null and arena.layout != null and arena.layout.name == "Level", "practice starts on Empyrean Tower")
	me = arena.local_player
	_check(not arena.layout.bounds.has_area() and WorldGravity.zones.size() >= 1 and is_equal_approx(WorldGravity.outside, 0.4), "no bounds; gravity zones set, 0.4 outside")
	await _gravity()
	await _lift()
	await _magic()
	await _gates()
	await _deaths()
	print("PASS" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)


func _settle(pos: Vector3, yaw: float = 0.0, frames: int = 30) -> void:
	me.teleport(pos, yaw)
	await _frames(frames)


func _gravity() -> void:
	print("gravity")
	await _settle(at(12.0, 75.0, TIER + 0.1))
	_check(is_equal_approx(me.motor.gravity_scale, 1.0), "standing in the Grand Library: 1.0 (%.2f)" % me.motor.gravity_scale)
	await _settle(at(33.0, 120.0, TIER * 3 + 0.1))
	_check(is_equal_approx(me.motor.gravity_scale, 0.4), "standing on the docking ring: 0.4 (%.2f)" % me.motor.gravity_scale)
	# Out through the Library's great arch: the field does not stop you, and gravity eases.
	var wall_r := 30.5 - 10.5 * (TIER / 183.0)
	await _settle(at(wall_r - 4.0, 75.0, TIER + 0.1))
	var out := at(1.0, 75.0, 0.0).normalized()
	var seen := []
	var crossed := -1
	for i in 150:
		me.velocity = Vector3(out.x * 8.0, me.velocity.y, out.z * 8.0)
		await get_tree().physics_frame
		var r := Vector2(me.global_position.x, me.global_position.z).length()
		if crossed < 0 and r > wall_r - 0.4:
			crossed = i
		if crossed >= 0:
			seen.append(me.motor.gravity_scale)
		if r > wall_r + 4.0:
			break
	var r_end := Vector2(me.global_position.x, me.global_position.z).length()
	_check(r_end > wall_r + 2.0, "walking at the force field takes you straight through it, onto the balcony (%.1f m out)" % (r_end - wall_r))
	_check(seen.size() > 10 and seen[5] > 0.9 and seen[seen.size() - 1] < 1.0, "gravity is still near 1.0 a few steps past the field and easing down after (%.2f, then %.2f)" % [seen[5] if seen.size() > 5 else -1.0, seen[-1] if seen.size() else -1.0])
	me.velocity = Vector3.ZERO
	await _frames(150)
	_check(is_equal_approx(me.motor.gravity_scale, 0.4), "a second or so later it is 0.4 (%.2f)" % me.motor.gravity_scale)


func _lift() -> void:
	print("tractor-beam lift")
	var lifts := get_tree().get_nodes_in_group(MapLiftWell.GROUP)
	var lift := lifts[0] as MapLiftWell
	await _settle(lift.global_position + Vector3(0, 0.1, 0), 0.0, 5)
	var y0 := me.global_position.y
	var t0 := Time.get_ticks_msec()
	var speeds := []
	for i in 240:
		await get_tree().physics_frame
		if i > 40:
			speeds.append(me.velocity.y)
	var rose := me.global_position.y - y0
	_check(rose > 12.0, "standing in %s you are carried up (%.1f m in 2 s of game time)" % [lift.get_parent().name, rose])
	_check(speeds.min() > 8.5 and speeds.max() < 9.5, "at about 9 m/s (%.2f to %.2f)" % [speeds.min(), speeds.max()])
	_check(me.motor.state == MovementController.State.AIR and me.weapon != null, "riding it you are simply in the air, gun in hand")


## The magic answers to players within 4 m in plain sight, not to the dead or to anyone
## sneaking, and never through a wall.
func _magic() -> void:
	print("the magic answering to players")
	var field: MapMagicField = null
	for n in arena.layout.find_children("*", "Node", true, false):
		if n is MapMagicField:
			field = n
	_check(field != null and field.boxes.size() > 100 and field.streams.size() >= 6, "the map has a magic field that knows its boxes (%d) and streams (%d)" % [field.boxes.size() if field else 0, field.streams.size() if field else 0])
	if field == null:
		return
	var library: Node = arena.layout.get_node("GrandLibrary/Magic")
	var room: MapMagic = null
	var corridor: MapMagic = null
	for n in library.get_children():
		if n is MapMagic and n.name.begins_with("RoomMotes") and room == null:
			room = n
		elif n is MapMagic and n.name.begins_with("CorridorMotes") and corridor == null:
			corridor = n
	# Far away: at rest.
	await _settle(at(12.0, 75.0, 0.1))
	await _wait(0.8)
	_check(is_zero_approx(room.stir()) and is_zero_approx(corridor.stir()), "nobody near: the Library's motes are at rest")
	# Standing among them: they scatter, and the runes flare.
	var among := room.global_position
	among.y = TIER + 0.1
	await _settle(among)
	await _wait(0.8)
	_check(room.stir() > 0.9, "standing among the motes: they are stirred (%.2f)" % room.stir())
	_check(field.rune_level(me.peer_id) > 0.9, "and the runes near you flare (%.2f)" % field.rune_level(me.peer_id))
	_check(is_zero_approx(corridor.stir()), "the corridor's motes, out of reach, are not")
	# Sneaking: crouched and still, nothing answers.
	DevArgs.drives_keys = true       # (as --hold does: the player reads the keys with no mouse captured)
	Input.action_press("crouch")
	await _wait(1.6)
	_check(me.motor.crouched and not MapMagicField.noticed(me), "crouched: you are not noticed")
	_check(room.stir() < 0.05 and field.rune_level(me.peer_id) < 0.05, "they settle while you sneak (%.2f, runes %.2f)" % [room.stir(), field.rune_level(me.peer_id)])
	Input.action_release("crouch")
	await _wait(0.8)
	DevArgs.drives_keys = false
	_check(room.stir() > 0.9, "standing up again stirs them (%.2f)" % room.stir())
	# Not through a wall: in the room behind the corridor's wall, 2 m from the corridor's motes.
	var r := Vector2(corridor.global_position.x, corridor.global_position.z).length()
	var deg := rad_to_deg(atan2(corridor.global_position.x, corridor.global_position.z))
	var behind := at(r - 3.0, deg, TIER + 0.1)
	await _settle(behind)
	await _wait(0.8)
	var gap := corridor.nearest(behind + Vector3(0, MapMagicField.CHEST, 0)).distance_to(behind + Vector3(0, MapMagicField.CHEST, 0))
	_check(gap < MapMagicField.REACH and is_zero_approx(corridor.stir()), "behind the corridor's wall, %.1f m from its motes: they do not answer" % gap)
	await _settle(at(r, deg, TIER + 0.1))
	await _wait(0.8)
	_check(corridor.stir() > 0.9, "in the corridor itself: they do (%.2f)" % corridor.stir())
	# Glass does not block it; stone does. (The stained glass at 180 degrees, 6.35 m up.)
	var y := TIER + 6.35 + 3.0
	var wall_r := Vector2(arena.layout.get_node("GrandLibrary/Shell").get_child(0).get_child(0).global_position.x, arena.layout.get_node("GrandLibrary/Shell").get_child(0).get_child(0).global_position.z).length()
	_check(field.in_sight(at(wall_r - 2.0, 180.0, y), at(wall_r + 2.5, 180.0, y)), "through a stained-glass window: in sight")
	_check(not field.in_sight(at(wall_r - 2.0, 200.0, y), at(wall_r + 2.5, 200.0, y)), "through the stone beside it: not")


## The ring gates are scenery: walking at one walks through the ring and out the back.
func _gates() -> void:
	print("the ring gates")
	var ring := arena.layout.get_node_or_null("Gates/GateEngine") as Node3D
	_check(ring != null and arena.layout.get_node("Gates").get_child_count() == 8, "eight ring gates stand, the Engine's among them")
	if ring == null:
		return
	var middle := ring.global_position + Vector3(0, 1.87, 0)   # (the middle of the ring's opening)
	var front := ring.global_transform.basis.z
	await _settle(middle + front * 2.0 - Vector3(0, 1.6, 0), 0.0, 20)
	for i in 110:
		me.velocity = Vector3(-front.x * 6.0, me.velocity.y, -front.z * 6.0)
		await get_tree().physics_frame
	_check(me.global_position.y < 10.0 and (me.global_position - middle).dot(front) < -1.0,
		"walking into the Engine's ring gate takes you through the ring and out the back")


func _deaths() -> void:
	print("the core, the burn layer, flying off")
	var died := []
	Match.player_died.connect(func(victim, _killer): died.append(victim))
	# Off sideways and upward: not a death.
	await _settle(Vector3(900.0, 400.0, -700.0), 0.0, 20)
	_check(me.alive and Match.is_alive(me.peer_id), "900 m out and 400 m up: still alive (no bounds)")
	# Below the burn layer: a death.
	me.teleport(Vector3(120.0, arena.layout.kill_height - 3.0, 40.0), 0.0)
	await _frames(20)
	_check(not Match.is_alive(me.peer_id) and died.has(me.peer_id) and Match.death_cause.get(me.peer_id, "") == "fell", "below the burn layer: a death (a fall)")
	await _back()
	# The Engine's core: a death, the same kind.
	died.clear()
	await _settle(Vector3(6.5, 0.1, 0.0), 0.0, 10)
	_check(Match.is_alive(me.peer_id), "6.5 m from the core, on the Engine's floor: safe")
	me.teleport(Vector3(1.5, 1.0, 0.0), 0.0)
	await _frames(12)
	_check(not Match.is_alive(me.peer_id) and died.has(me.peer_id) and Match.death_cause.get(me.peer_id, "") == "fell", "touching the Engine's core: a death, handled like a fall")
	_check(not MapMagicField.noticed(me), "(the dead do not stir the magic)")
	await _back()
	me.teleport(Vector3(2.0, 12.0, 2.0), 0.0)     # falling into it from the shaft
	await _frames(90)
	_check(not Match.is_alive(me.peer_id), "falling down the shaft onto the core: a death")


## Waits out the respawn delay and comes back.
func _back() -> void:
	for i in 600:
		await get_tree().process_frame
		if Match.is_alive(me.peer_id) and me.alive:
			break
	await _frames(5)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		_ok = false
