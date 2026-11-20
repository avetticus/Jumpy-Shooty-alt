extends Node
## The body of tests/gibs_test.gd. A separate file because it uses the game's
## autoloads (Net, Match, Settings), which only exist once the test's SceneTree is running.

const SIMULATE := 2.0   ## seconds of flight checked for NaN and the floor

var failures := 0
var _frame := 0
var _arena: Node3D
var _player: Player
var _gibs: Node3D
var _t := 0.0
var _phase := 0
var _done := false


func _process(delta: float) -> void:
	if _done:
		return
	_frame += 1
	if _frame == 1:
		_cut_checks()
		_spawn_checks()
		return
	if _phase < 0:
		_finish()
		return
	_t += delta
	if _phase == 0 and _t >= SIMULATE:
		_phase = 1
		_flight_checks()
	elif _phase == 1 and _t >= Remains.LIFETIME - Remains.DISSOLVE_TIME * 0.5:
		_phase = 2
		_expect("burning away near the end (dissolve shader on its pieces)", _dissolving(_gibs))
	elif _phase == 2 and _t >= Remains.LIFETIME + 0.5:
		_expect("gone LIFETIME after the death", not is_instance_valid(_gibs) and Remains.count() == 0)
		_finish()


func _finish() -> void:
	_done = true
	if is_instance_valid(_player):
		_free_model(_player.robot)
	if is_instance_valid(_arena):
		_arena.free()
	Net.arena = null
	print("GIBS TEST PASSED" if failures == 0 else "GIBS TEST FAILED: %d" % failures)
	get_tree().quit(1 if failures else 0)


func _cut_checks() -> void:
	print("Cutting every body into pieces")
	var ids: Array = Characters.ids()
	var frog := CustomCharacter.new()
	frog.legs = "frog"
	frog.torso = "frog"
	frog.head = "frog"
	ids.append(frog.to_id())
	var mix := CustomCharacter.new()
	mix.legs = "kestrel"
	mix.torso = "human"
	mix.head = "rivet"
	mix.accessories = {"hat": "top_hat", "face": "shades", "neck": "gold_chain", "back": "cape"}
	ids.append(mix.to_id())
	for id in ids:
		_check_cut(id, "rifle", 1)
	for gun in WeaponData.GUNS.filter(func(g): return WeaponData.by_id(g).is_akimbo()):   # a gun in each hand: two guns
		_check_cut(Characters.default_id(), gun, 2)
		_check_cut(mix.to_id(), gun, 2)
	_check_cut("templar", "sword", 0)
	_check_cut("vanguard", "none", 0)


## `id` holding `gun`: its pieces cover the body exactly, with `guns` gun pieces.
func _check_cut(id: String, gun: String, guns: int) -> void:
	var model := RobotModel.new().build(id, Color(0.9, 0.3, 0.2), false, gun)
	var pieces := Gibs.cut(model)
	var source: Mesh = model.mesh.mesh
	var covered := {}   # body surface -> triangles in pieces
	var empty := 0
	var names := []
	for piece in pieces:
		names.append(piece.name)
		for part in piece.parts:
			var mesh: ArrayMesh = part.mesh
			if mesh.get_surface_count() == 0 or part.triangles == 0:
				empty += 1
			for i in mesh.get_surface_count():
				var s: int = part.surfaces[i]
				var n := (mesh.surface_get_arrays(i)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				if n == 0:
					empty += 1
				covered[s] = covered.get(s, 0) + n
	var exact := true
	var total := 0
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		var n: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if arrays[Mesh.ARRAY_INDEX] != null \
			else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		total += n
		if covered.get(s, 0) != n:
			exact = false
	var body := names.filter(func(n): return n in Gibs.BODY_PIECES).size()
	var gun_pieces := names.filter(func(n): return n in ["gun", "gun_l"]).size()
	var label := "%s with %s" % [id.get_slice("|", 1) + "|" + id.get_slice("|", 2) + "|" + id.get_slice("|", 3) if Characters.is_custom(id) else id, gun]
	_expect("%s: every triangle in exactly one piece (%d)" % [label, total], exact and total > 0)
	_expect("%s: %d body pieces and %d gun pieces, none empty" % [label, body, gun_pieces],
		body == Gibs.BODY_PIECES.size() and gun_pieces == guns and empty == 0)
	_expect("%s: cut once (the second time comes from the cache)" % label, is_same(Gibs.cut(model), pieces))
	_free_model(model)


func _spawn_checks() -> void:
	print("A rocket kill")
	_arena = Node3D.new()
	_arena.name = "TestArena"
	get_tree().root.add_child(_arena)
	Net.arena = _arena
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(60, 1, 60)
	floor_shape.shape = slab
	floor_shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(floor_shape)
	_arena.add_child(floor_body)
	_player = Player.new()
	_player.peer_id = 7
	_player.set_process(false)
	_player.set_physics_process(false)
	_player.set_process_input(false)
	_player.set_process_unhandled_input(false)
	_player.visual = Node3D.new()
	_player.add_child(_player.visual)
	_player.robot = RobotModel.new().build("templar", Color(0.2, 0.5, 0.9), false, "rocket_launcher")
	_player.visual.add_child(_player.robot)
	_arena.add_child(_player)
	_player.global_position = Vector3(2, 0, -3)
	_player.rotation.y = 0.7
	# Strike a pose, so the pieces have something to match.
	var sk := _player.robot.skeleton
	sk.set_bone_pose_rotation(sk.find_bone("upper_arm_r"), Quaternion(Vector3.RIGHT, -1.1))
	sk.set_bone_pose_rotation(sk.find_bone("forearm_l"), Quaternion(Vector3.FORWARD, 0.8))
	sk.set_bone_pose_rotation(sk.find_bone("head"), Quaternion(Vector3.UP, 0.6))
	sk.set_bone_pose_rotation(sk.find_bone("thigh_l"), Quaternion(Vector3.RIGHT, 0.9))
	var feet := _player.global_position
	var fx := {"with": "rocket_launcher", "head": false, "gib": true, "push": Vector3(0, 6, -11),
		"dir": Vector3(0, 0, -1), "at": feet + Vector3(0.3, 0.8, 0.9)}
	_expect("Remains takes the body (giblets)", Remains.spawn(_player, fx))
	_expect("as one set of remains", Remains.count() == 1)
	for c in _arena.get_children():
		if c is Gibs:
			_gibs = c
	_expect("a Gibs node in the arena", _gibs != null)
	if _gibs == null:
		_phase = -1
		return
	var bodies := _gibs.get_children().filter(func(b): return b is RigidBody3D)
	var pieces := bodies.filter(func(b): return not String(b.name).begins_with("scrap")).size()
	var scrap := bodies.size() - pieces
	_expect("12 pieces (body and rocket launcher), %d" % pieces, pieces == 12)
	_expect("10 to 20 bits of scrap (%d), %d bodies in all (at most 30)" % [scrap, bodies.size()],
		scrap >= 10 and scrap <= 20 and bodies.size() <= 30)
	var layers := bodies.all(func(b): return b.collision_layer == Remains.DEBRIS_LAYER and b.collision_mask == 1)
	_expect("every piece on the debris layer, hitting only the level", layers)
	_expect("each piece moving", bodies.all(func(b): return b.linear_velocity.length() > 0.5))
	_expect("none faster than the cap", bodies.all(func(b): return b.linear_velocity.length() <= Gibs.MAX_SPEED + 0.01))
	var miss := _worst_miss()
	_expect("the pieces start where the posed body was (largest miss %.4f m)" % miss, miss < 0.002)
	var bare := Player.new()
	_expect("a player without a model makes no giblets", Gibs.spawn(bare, fx) == null)
	bare.free()


## How far the first vertex of each piece's meshes is from where the skinned body has
## it (the nearest vertex of the body, put through its skeleton by hand).
func _worst_miss() -> float:
	var model := _player.robot
	var sk := model.skeleton
	var skin := model.mesh.skin
	var source: Mesh = model.mesh.mesh
	var world := PackedVector3Array()
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var per := bones.size() / verts.size()
		for v in verts.size():
			var bind := bones[v * per]
			var bone := sk.find_bone(skin.get_bind_name(bind))
			world.append(sk.global_transform * sk.get_bone_global_pose(bone) * skin.get_bind_pose(bind) * verts[v])
	var worst := 0.0
	for body in _gibs.get_children():
		if not body is RigidBody3D or String(body.name).begins_with("scrap"):
			continue
		for mi in body.get_children():
			if not mi is MeshInstance3D:
				continue
			var p: Vector3 = mi.global_transform * (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0]
			var best := INF
			for w in world:
				best = minf(best, w.distance_squared_to(p))
			worst = maxf(worst, sqrt(best))
	return worst


func _flight_checks() -> void:
	print("After %.0f s of flight" % SIMULATE)
	var bodies := _gibs.get_children().filter(func(b): return b is RigidBody3D)
	var finite := bodies.all(func(b): return b.global_position.is_finite() and b.linear_velocity.is_finite())
	_expect("no NaN in any piece", finite)
	var lowest := INF
	var spread := 0.0
	for b in bodies:
		lowest = minf(lowest, b.global_position.y)
		spread = maxf(spread, b.global_position.distance_to(_player.global_position))
	_expect("none fell through the floor (lowest %.2f m)" % lowest, lowest > -0.3)
	_expect("blown apart (furthest %.1f m away)" % spread, spread > 2.0)


func _dissolving(g: Node) -> bool:
	if not is_instance_valid(g):
		return false
	for body in g.get_children():
		for mi in body.get_children():
			if mi is MeshInstance3D and mi.get_surface_override_material(0) is ShaderMaterial:
				return true
	return false


## Let go of the materials first (headless Godot grumbles otherwise), then free.
func _free_model(model: RobotModel) -> void:
	if not is_instance_valid(model):
		return
	for i in model.mesh.mesh.get_surface_count():
		model.mesh.set_surface_override_material(i, null)
	model.free()


func _expect(what: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1
