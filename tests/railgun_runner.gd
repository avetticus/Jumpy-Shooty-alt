extends Node
## The body of tests/railgun_test.gd (a separate file: it uses the game's autoloads).

var _ok := true
var _hits: Array = []
var _shots: Array = []
var _player_hits: Array = []


func run() -> void:
	var game = Game
	var net = Net
	var match_state = Match
	game.start_practice("testing_grounds")
	await _frames(30)
	var arena = net.arena
	var me: Player = arena.local_player
	var my_id: int = net.my_id()
	match_state.dummy_hit.connect(func(s, dm, dmg, h, k): _hits.append([s, dm, dmg, h, k]))
	match_state.shot_fired.connect(func(s, m, ends, hits, vias): _shots.append([ends, hits, vias]))
	match_state.player_hit.connect(func(s, t, dmg, h): if t == net.my_id(): _player_hits.append([s, t, dmg]))   # (dummies are told about as players too)
	var dummy: TargetDummy = arena.dummies[1]   # 10 m out, nothing in front of it
	var d: Vector3 = dummy.global_position
	var rail := WeaponData.by_id("railgun")

	# Stand 8 m short of the dummy, with a thick wall half way.
	me.teleport(d - Vector3(8.0, 0, 0), -PI / 2)
	var wall := StaticBody3D.new()
	wall.name = "TestWall"
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 8.0, 8.0)
	shape.shape = box
	wall.add_child(shape)
	arena.add_child(wall)
	wall.global_position = d - Vector3(4.0, 0, 0)
	await _frames(3)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var eye := me.eye_position()
	var dir := (d + Vector3(0, 1.0, 0) - eye).normalized()
	var space := me.get_world_3d().direct_space_state
	_check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + dir * 20.0, 1)).is_empty(),
		"the wall stands between you and the dummy")

	# A pistol round stops at the wall.
	net.host_set_weapon(my_id, "pistol")
	match_state.request_shot(eye, PackedVector3Array([dir]), {}, "pistol", my_id)
	await _frames(3)
	_check(_hits.is_empty(), "a pistol round stops at the wall (%s)" % str(_hits))
	_check(not _shots.is_empty() and eye.distance_to(_shots[-1][0][0]) < 4.0, "...and its shot ends there")

	# The railgun's slug goes through it, kills the dummy, and runs its whole range.
	match_state._last_shot_time.erase(my_id)   # (the host spaces shots out by real time; this runs on a fixed clock)
	net.host_set_weapon(my_id, "railgun")
	_check(net.player_weapon(my_id) == "railgun", "you hold the railgun")
	var hp_before: float = match_state.health.get(my_id, -1.0)
	match_state.request_shot(eye, PackedVector3Array([dir]), {}, "railgun", my_id)
	await _frames(3)
	_check(_hits.size() == 1 and int(_hits[0][1]) == 1, "the railgun hits the dummy through the wall (%s)" % str(_hits))
	_check(_hits.size() == 1 and absf(float(_hits[0][2]) - rail.damage) < 0.5 and bool(_hits[0][4]),
		"...for %.0f, and it goes down (%s)" % [rail.damage, str(_hits)])
	var end: Vector3 = _shots[-1][0][0] if _shots else eye
	_check(absf(eye.distance_to(end) - rail.max_range) < 0.5,
		"its shot effect runs its whole range (%.1f m, want %.0f)" % [eye.distance_to(end), rail.max_range])
	_check(_player_hits.is_empty() and float(match_state.health.get(my_id, -1.0)) == hp_before,
		"it never hurts the one who fired it (%s, %.0f to %.0f)" % [str(_player_hits), hp_before, float(match_state.health.get(my_id, -1.0))])
	wall.queue_free()

	# A breakable piece of wall anywhere on its line takes the hit.
	var dest: MapDestruction = arena.layout.destruction if arena.layout else null
	var cell := -1
	if dest:
		var best := INF
		for c in dest.cells.size():
			var info: Dictionary = dest.cells[c]
			if info.protected or info.stage != 0:
				continue
			var far := eye.distance_to(dest.cell_center(c))
			if far > 6.0 and far < rail.max_range * 0.8 and far < best:
				best = far
				cell = c
	if cell < 0:
		print("(no breakable piece on this map: the slug's damage to walls is checked in destruction_test)")
	else:
		match_state._last_shot_time.erase(my_id)
		var at := dest.cell_center(cell)
		var hp: float = dest.cells[cell].hp
		_check(not dest.cells_along(eye, eye + (at - eye).normalized() * rail.max_range).filter(func(x): return x[0] == cell).is_empty(),
			"the piece is on the line")
		match_state.request_shot(eye, PackedVector3Array([(at - eye).normalized()]), {}, "railgun", my_id)
		await _frames(3)
		_check(float(dest.cells[cell].hp) <= hp - rail.damage * rail.structure_damage + 0.5 or int(dest.cells[cell].stage) >= MapDestruction.BROKEN,
			"a breakable piece %.0f m away on its line takes its damage (%.0f to %.0f)" % [eye.distance_to(at), hp, float(dest.cells[cell].hp)])

	print("railgun: %s" % ("all passed" if _ok else "FAILED"))
	get_tree().quit(0 if _ok else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		_ok = false
