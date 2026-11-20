extends SceneTree
## Haunted House checks (game/maps/haunted_house.tscn), and the systems it brought:
## HauntEvent, HauntProp and MapGhost.
##  - listed for free-for-all (and so Gun Game) and Deathmatch; very small (inside a
##    30 x 22 m house, two floors); a Haunting event with four layouts; 60 or more
##    floating props, ten or more doorways that come and go, five or more ghosts (all Shades), the
##    lights it flickers;
##  - the clock: what layout comes next is worked out from the event's state alone
##    (the same on every copy of the game), starts at layout 0, never repeats a layout
##    twice running and goes through all of them; where every prop is depends only on
##    the clock and the state; a new match puts everything home;
##  - in every layout: every spawn point is clear and on a floor, every weapon pickup
##    is clear, and a bot can walk from the first spawn point to every other spawn
##    point and every pickup (every room on both floors);
##  - while the house shifts the map says so (bots stand still) and a doorway on its
##    way in or out is never solid;
##  - someone standing in a doorway when it closes is put out of it, on the nearer
##    side; someone that furniture comes to rest on is put somewhere free beside it.
## Run: godot --headless --path . --script tests/haunted_house_test.gd

const ID := "haunted_house"
const SEED := 4242

var failures := 0
var map: MapRoot
var event: HauntEvent
var space: PhysicsDirectSpaceState3D
var props: Array = []


func _initialize() -> void:
	print("Haunted House checks")
	_run.call_deferred()


func _run() -> void:
	_expect(Maps.fits(ID, "ffa") and Maps.fits(ID, "dm") and Maps.game_of(ID) == "ffa", "listed for free-for-all (and so Gun Game) and Deathmatch")
	_expect(Maps.name_of(ID) == "Haunted House", "it is called Haunted House")
	map = Maps.make(ID)
	map.destructible = true
	root.add_child(map)
	var started := Time.get_ticks_msec()
	map.build(false)
	print("    built in %d ms" % (Time.get_ticks_msec() - started))
	event = map.get_node_or_null("Haunting") as HauntEvent
	for i in 4:
		await physics_frame
	space = root.get_world_3d().direct_space_state
	_rules()
	if event == null:
		_finish()
		return
	event.process_mode = Node.PROCESS_MODE_DISABLED   # the test sets the clock itself
	props = map.find_children("*", "", true, false).filter(func(n): return n is HauntProp)
	_clock()
	await _positions()
	for layout in event.layouts:
		await _set_layout(layout)
		_spawns(layout)
		_pickups(layout)
		await _routes(layout)
	await _mid_move()
	await _door_rescue()
	await _furniture_rescue()
	await _new_match()
	_finish()


func _finish() -> void:
	print("FAIL: %d checks failed" % failures if failures else "PASS: every check passed")
	quit(1 if failures else 0)


# ---------------------------------------------------------------------------
# What the map is

func _rules() -> void:
	print("  size and rules")
	_expect(event != null, "has a Haunting event")
	if event == null:
		return
	_expect(event.layouts == 4, "four layouts")
	var all := map.find_children("*", "", true, false)
	var haunted := all.filter(func(n): return n is HauntProp)
	var doors := haunted.filter(func(n): return (n as HauntProp).door)
	var ghosts := all.filter(func(n): return n is MapGhost)
	_expect(haunted.size() >= 60, "60 or more props that float, shift or vanish (%d)" % haunted.size())
	_expect(doors.size() >= 10, "ten or more doorways that come and go (%d)" % doors.size())
	var movers := haunted.filter(func(n): return not (n as HauntProp).door and not (n as HauntProp).moves.is_empty()).size()
	var floaters := haunted.filter(func(n): return (n as HauntProp).bob != 0.0 or (n as HauntProp).twirl != 0.0).size()
	_expect(movers >= 15 and floaters >= 30, "furniture on the move: %d pieces go somewhere new when the house shifts, %d float" % [movers, floaters])
	_expect(ghosts.size() >= 5, "five or more ghosts (%d)" % ghosts.size())
	_expect(ghosts.all(func(n): return (n as MapGhost).look == 3), "every ghost is a Shade (the faceless silhouette)")
	for look in 5:
		var g := MapGhost.new()
		g.look = look
		root.add_child(g)
		g._build()  # headless skips the body in _ready
		_expect(not g.find_children("*", "MeshInstance3D", true, false).is_empty(), "ghost look %d builds a body" % look)
		g.free()
	var lights := event.get_node_or_null(event.lights)
	_expect(lights != null and not lights.find_children("*", "OmniLight3D", true, false).is_empty(), "lights for the haunting to flicker")
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in map.spawns:
		lo = lo.min(p[0])
		hi = hi.max(p[0])
	_expect(hi.x - lo.x <= 30.0 and hi.z - lo.z <= 22.0 and hi.y - lo.y <= 4.5, "a very small map: every spawn point inside the 30 x 22 m house, on two floors")
	_expect(map.spawns.size() >= 12, "12 or more spawn points (%d)" % map.spawns.size())
	var kinds := {}
	for w in map.weapon_spawns:
		kinds[w[1]] = true
	_expect(map.weapon_spawns.size() >= 10 and kinds.size() >= 10, "10 or more weapon pickups of 10 or more kinds (%d, %d kinds)" % [map.weapon_spawns.size(), kinds.size()])
	_expect(kinds.has("shotgun") and (kinds.has("sword") or kinds.has("hammer")), "close quarters weapons: shotguns and blades")


# ---------------------------------------------------------------------------
# The clock

func _clock() -> void:
	print("  the clock")
	event.state = SEED
	var first := []
	for i in 40:
		first.append(event.layout_of_turn(i))
	event.state = SEED + 1
	var other := []
	for i in 40:
		other.append(event.layout_of_turn(i))
	event.state = SEED
	var again := []
	for i in 40:
		again.append(event.layout_of_turn(i))
	_expect(first == again, "the order of layouts comes from the state alone (the same on every copy)")
	_expect(first != other, "a different state, a different order")
	_expect(first[0] == 0, "it starts in layout 0")
	var repeats := 0
	var seen := {}
	for i in first.size():
		seen[first[i]] = true
		if i > 0 and first[i] == first[i - 1]:
			repeats += 1
	_expect(repeats == 0, "never the same layout twice running")
	_expect(seen.size() == event.layouts, "every layout comes up (%s)" % [first.slice(0, 12)])
	_expect(is_equal_approx(event.turn_length(), event.hold_time + event.warn_time + event.move_time) and event.hold_time >= 15.0 and event.move_time <= 4.0,
		"each turn: %.0f s quiet, %.0f s warning, a %.1f s shift" % [event.hold_time, event.warn_time, event.move_time])


## Where every prop is depends only on the clock and the state.
func _positions() -> void:
	event.state = SEED
	event.running = true
	var t := event.turn_length() * 3.0 + event.hold_time + event.warn_time + 1.0   # mid-shift
	event.elapsed = t
	event._place()
	var then := props.map(func(p): return (p as HauntProp).haunt)
	event.elapsed = 7.3
	event._place()
	event.elapsed = t
	event._place()
	var now := props.map(func(p): return (p as HauntProp).haunt)
	var same := true
	for i in props.size():
		same = same and (then[i] as Transform3D).is_equal_approx(now[i])
	_expect(same, "every prop is in the same place at the same moment, however the clock got there")
	await physics_frame


## Sets the clock to the quiet of a turn in layout `layout`.
func _set_layout(layout: int) -> void:
	event.state = SEED
	event.running = true
	var n := 0
	while event.layout_of_turn(n) != layout:
		n += 1
	event.elapsed = event.turn_length() * n + 1.0
	event._place()
	for i in 3:
		await physics_frame
	print("  layout %d (turn %d)" % [layout, n])


# ---------------------------------------------------------------------------
# Each layout

func _clear(feet: Vector3, radius := 0.38, height := 1.7) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis(), feet + Vector3(0, height * 0.5 + 0.08, 0))
	q.collision_mask = 1
	return space.intersect_shape(q, 1).is_empty()


func _floored(feet: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(feet + Vector3(0, 0.3, 0), feet - Vector3(0, 0.6, 0), 1)
	return not space.intersect_ray(ray).is_empty()


func _spawns(layout: int) -> void:
	var bad := []
	for i in map.spawns.size():
		var at: Vector3 = map.spawns[i][0]
		if not _clear(at) or not _floored(at):
			bad.append("spawn %d %s" % [i + 1, at])
	_expect(bad.is_empty(), "layout %d: every spawn point is clear and on a floor %s" % [layout, bad])


func _pickups(layout: int) -> void:
	var bad := []
	for w in map.weapon_spawns:
		var at: Vector3 = w[0]
		if not _clear(at, 0.3, 1.0):
			bad.append("%s %s" % [w[1], at])
	_expect(bad.is_empty(), "layout %d: nothing stands on a weapon pickup %s" % [layout, bad])


func _short(nav: RID, from: Vector3, to: Vector3) -> float:
	var path := NavigationServer3D.map_get_path(nav, from, to, true)
	return 99.0 if path.is_empty() else path[path.size() - 1].distance_to(to)


func _routes(layout: int) -> void:
	var region := MapScenery.bake_navigation(map)
	root.add_child(region)
	var nav := root.get_world_3d().navigation_map
	var probe: Vector3 = map.spawns[0][0]
	for i in 600:
		await physics_frame
		if NavigationServer3D.map_get_iteration_id(nav) > 0 and i > 4 and NavigationServer3D.map_get_closest_point(nav, probe).distance_to(probe) < 1.0:
			break
	var goals := {}
	for i in map.spawns.size():
		goals["spawn %d" % (i + 1)] = map.spawns[i][0]
	for w in map.weapon_spawns:
		goals[w[1]] = w[0]
	var from: Vector3 = map.spawns[0][0]
	var missed := []
	for goal_name in goals:
		var miss := maxf(_short(nav, from, goals[goal_name]), _short(nav, goals[goal_name], from))
		if miss > 1.0:
			missed.append("%s (%.1f m short)" % [goal_name, miss])
	_expect(missed.is_empty(), "layout %d: a bot can walk from the first spawn point to every other one and to every pickup, on both floors %s" % [layout, missed])
	region.queue_free()
	await physics_frame
	await physics_frame


# ---------------------------------------------------------------------------
# The shift

func _mid_move() -> void:
	print("  the shift")
	event.state = SEED
	event.running = true
	var n := 0
	event.elapsed = event.hold_time + 0.5
	event._place()
	_expect(map.warning and not map.shifting, "in the warning the map says a shift is coming, and nothing has moved yet")
	event.elapsed = event.hold_time + event.warn_time + event.move_time * 0.5
	event._place()
	_expect(map.shifting and event.moving(), "during the shift the map says so (bots stand still)")
	var a := event.layout_of_turn(n)
	var b := event.layout_of_turn(n + 1)
	var changing := props.filter(func(p): return (p as HauntProp).door and (p as HauntProp).is_shown(a) != (p as HauntProp).is_shown(b))
	_expect(not changing.is_empty() and changing.all(func(p): return not (p as HauntProp).solid_now),
		"a doorway on its way in or out is never solid during the shift (%d of them)" % changing.size())
	event.elapsed = event.turn_length() + 1.0
	event._place()
	await physics_frame
	_expect(not map.shifting and map.layout_state == b, "after the shift the map is in the next layout (%d)" % b)
	_expect(changing.all(func(p): return (p as HauntProp).solid_now == (p as HauntProp).is_shown(b)), "and each doorway is solid or open as that layout has it")


func _dummy() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.7
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	body.add_child(shape)
	body.collision_layer = 2
	body.collision_mask = 1
	root.add_child(body)
	return body


func _door_rescue() -> void:
	print("  rescue")
	event.state = SEED
	event.running = true
	# A turn whose shift closes a doorway, and the panel that closes it.
	var n := 0
	var panel: HauntProp
	while panel == null and n < 40:
		var a := event.layout_of_turn(n)
		var b := event.layout_of_turn(n + 1)
		for p in props:
			var hp := p as HauntProp
			if hp.door and not hp.is_shown(a) and hp.is_shown(b):
				panel = hp
				break
		if panel == null:
			n += 1
	_expect(panel != null, "some shift closes a doorway")
	if panel == null:
		return
	event.elapsed = event.turn_length() * n + 1.0
	event._place()
	await physics_frame
	var box := panel.door_box()
	var feet := Vector3(box.get_center().x, box.position.y + 0.02, box.get_center().z)
	var body := _dummy()
	body.global_position = feet
	await physics_frame
	_expect(_clear_of(body, feet), "someone can stand in the open doorway (%s)" % panel.name)
	event.elapsed = event.turn_length() * (n + 1) + 0.5
	event._place()
	await physics_frame
	await physics_frame
	_expect(panel.solid_now, "the shift closes it")
	var moved := event.free_player(body)
	var out := body.global_position
	var thin_x := box.size.x < box.size.z
	var outside := (out.x <= box.position.x - 0.38 or out.x >= box.end.x + 0.38) if thin_x else (out.z <= box.position.z - 0.38 or out.z >= box.end.z + 0.38)
	var near := out.distance_to(feet) < 1.2
	_expect(moved and outside and near, "whoever stood in it is put just out of it, on the nearer side (%.2f m)" % out.distance_to(feet))
	await physics_frame
	_expect(_clear_of(body, out), "and is not inside anything there")
	body.queue_free()
	await physics_frame


func _clear_of(body: CharacterBody3D, feet: Vector3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis(), feet + Vector3(0, 0.92, 0))
	q.collision_mask = 1
	q.exclude = [body.get_rid()]
	return space.intersect_shape(q, 1).is_empty()


func _furniture_rescue() -> void:
	await _set_layout(1)
	var body := _dummy()
	var found := false
	for p in props:
		var hp := p as HauntProp
		if hp.door or hp.moves.is_empty() or not hp.solid_now:
			continue
		var at := (hp._body as Node3D).global_position if hp._body else hp.global_position
		var floor_y := 4.0 if at.y >= 4.0 else 0.0
		var feet := Vector3(at.x, floor_y + 0.02, at.z)
		body.global_position = feet
		if _clear_of(body, feet):
			continue
		found = true
		var moved := event.free_player(body)
		await physics_frame
		var out := body.global_position
		_expect(moved and _clear_of(body, out) and _floored(out) and out.distance_to(feet) < 3.5,
			"someone caught inside furniture (%s) is put somewhere free beside it (%.1f m away)" % [hp.name, out.distance_to(feet)])
		break
	_expect(found, "found a piece of furniture to be caught in")
	body.queue_free()
	await physics_frame


func _new_match() -> void:
	event.state = SEED
	event.running = true
	event.elapsed = event.turn_length() * 5.0 + 3.0
	event._place()
	event._on_match_started()
	await physics_frame
	var home := props.all(func(p): return (p as HauntProp).haunt.origin.distance_to((p as HauntProp).spot(0)) < 0.6 and (p as HauntProp).solid_now == (p as HauntProp).is_shown(0))
	_expect(not event.running and event.state == 0 and map.layout_state == 0 and home, "a new match puts the house back in layout 0, its clock stopped till the host starts it")


func _expect(ok: bool, what: String) -> void:
	print("    %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1
