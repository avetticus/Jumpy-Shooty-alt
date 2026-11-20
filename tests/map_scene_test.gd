extends SceneTree
## Checks the map scenes and the pieces they are made of:
##  - every map in the list loads, builds collision and meshes, has enough spawn
##    points inside its bounds, and every block's kind has a colour in the palette;
##  - a block's scale is folded into its size, and a hidden block is left out;
##  - the resize handles' face moves keep the opposite face in place;
##  - a cone's mesh points outward and comes to its top, and its collision matches it;
##  - no map scene sets a packed array on a node whose script does not run in the
##    editor: an export drops those, so the exported game would play without them;
##  - race maps: numbered gates ending in one finish, a bot route, hazards, and
##    their moving parts build; race maps are only offered for races, arenas only
##    for shoot-outs.
## Run: godot --headless --path . --script tests/map_scene_test.gd

var failures := 0


func _initialize() -> void:
	print("Map scene checks")
	for id in Maps.ids():
		_check_map(id)
	_check_export()
	_check_modes()
	_check_blocks()
	_check_hulls()
	_check_face_moves()
	print("FAIL: %d checks failed" % failures if failures else "PASS: every check passed")
	quit(1 if failures else 0)


func _check_map(id: String) -> void:
	print("  %s" % Maps.name_of(id))
	var map := Maps.make(id)
	_expect(map != null, "loads as a MapRoot")
	if map == null:
		return
	root.add_child(map)
	var pieces := map.collect_pieces()
	var unknown := {}
	for p in pieces:
		if not map.palette.colors.has(p.kind):
			unknown[p.kind] = true
	_expect(unknown.is_empty(), "every block kind has a colour in the palette%s" % ("" if unknown.is_empty() else " (missing: %s)" % ", ".join(unknown.keys())))
	map.build()
	var shapes := map.get_node("Collision").get_child_count()
	var meshes := map.find_children("Mesh_*", "MeshInstance3D", false, false).size()
	# A map can be all moving parts (Sky Island: every island and pad is a MapMover),
	# so what its movers built counts too.
	for m in map.movers:
		if m.body:
			shapes += (m.body as Node).find_children("*", "CollisionShape3D", true, false).size()
			meshes += (m.body as Node).find_children("*", "MeshInstance3D", true, false).size()
	_expect(shapes > 0 and meshes > 0, "builds %d collision shapes and %d merged meshes from %d blocks" % [shapes, meshes, pieces.size()])
	var race := Maps.game_of(id) == "race"
	if race:
		_expect(map.spawns.size() >= 5, "%d spawn points on the start line (a race needs 5)" % map.spawns.size())
		_check_race(map)
	else:
		_expect(map.spawns.size() >= 8, "%d spawn points (the arena needs at least 8)" % map.spawns.size())
	var outside := 0
	for s in map.spawns:
		if map.bounds.has_area() and not map.bounds.has_point(Vector2(s[0].x, s[0].z)):
			outside += 1
	_expect(outside == 0, "every spawn point is inside the map's bounds")
	_expect(map.find_children("*", "WorldEnvironment", true, false).size() == 1, "has one WorldEnvironment (sky and ambient light)")
	map.free()


## What an export keeps. Godot's export drops a packed array (PackedFloat32Array,
## PackedStringArray...) that a scene sets on a node whose script is not a @tool
## script: the setting is there when you play from the editor and gone in the exported
## game (v0.1.48's crane had lost its stops this way; Cirrus its lit windows). A typed
## array (Array[float], Array[String]) is kept, so a map script's lists must be those.
func _check_export() -> void:
	print("  what an export keeps")
	var lost := []
	var dir := "res://game/maps"
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".tscn"):
			continue
		var state := (load(dir.path_join(file)) as PackedScene).get_state()
		for i in state.get_node_count():
			var script: Script = null
			var packed := []
			for p in state.get_node_property_count(i):
				var value: Variant = state.get_node_property_value(i, p)
				if value is Script:
					script = value
				elif typeof(value) >= TYPE_PACKED_BYTE_ARRAY:
					packed.append(String(state.get_node_property_name(i, p)))
			if not packed.is_empty() and (script == null or not script.is_tool()) and state.get_node_instance(i) == null:
				lost.append("%s %s: %s" % [file, state.get_node_path(i), ", ".join(packed)])
	_expect(lost.is_empty(), "no map scene sets a packed array on a node whose script does not run in the editor%s" % ("" if lost.is_empty() else " (an export would drop: %s)" % "; ".join(lost)))


## A hull in a built map: what you touch is the hull, not the box round it.
func _check_hulls() -> void:
	print("  hulls")
	var map := MapRoot.new()
	root.add_child(map)
	var slope := MapHazard.new()   # a slope of something deadly: 4 m square, 2 m tall at the back (-z)
	slope.shape = MapBlock.Shape.HULL
	slope.points = MapMesher.wedge_points({"size": Vector3(4, 2, 4)})
	slope.position = Vector3(0, 1, 0)
	slope.solid = false
	map.add_child(slope)
	map.build()
	_expect(map.hazards.size() == 1 and map.hazards[0].shape == "hull", "a hull hazard is a hull to the map")
	_expect(map.hazard_at(Vector3(0, 0.5, 0)), "under the slope, you touch it")
	_expect(not map.hazard_at(Vector3(0, 1.5, 0.5)), "over the slope, inside the box round it, you do not")
	map.free()


func _check_blocks() -> void:
	print("  blocks")
	var map := MapRoot.new()
	var group := Node3D.new()
	group.position = Vector3(10, 0, 0)
	group.rotation.y = PI / 2.0
	map.add_child(group)
	var block := MapBlock.new()
	block.size = Vector3(2, 1, 4)
	block.position = Vector3(0, 0.5, 3)
	block.scale = Vector3(2, 1, 1)
	group.add_child(block)
	var hidden := MapBlock.new()
	hidden.visible = false
	group.add_child(hidden)
	var spawn := MapSpawn.new()
	spawn.position = Vector3(5, 0, 5)
	spawn.rotation.y = 1.0
	map.add_child(spawn)
	var pieces := map.collect_pieces()
	_expect(pieces.size() == 1, "a hidden block is left out (%d pieces)" % pieces.size())
	if pieces.size() == 1:
		var p: Dictionary = pieces[0]
		_expect(p.size.is_equal_approx(Vector3(4, 1, 4)), "scale is folded into the size (%s)" % p.size)
		_expect(p.xf.origin.is_equal_approx(Vector3(13, 0.5, 0)), "placed through its group (at %s)" % p.xf.origin)
		_expect(p.xf.basis.get_scale().is_equal_approx(Vector3.ONE), "the piece's frame is unscaled")
	map.build(false)
	_expect(map.spawns.size() == 1 and absf(map.spawns[0][1] - 1.0) < 0.001 and is_equal_approx(map.spawns[0][0].y, 0.2),
		"a spawn point gives its position (lifted 0.2 m) and the way it faces")
	map.free()


func _check_race(map: MapRoot) -> void:
	var n := map.checkpoints.size()
	var numbered := true
	for i in n:
		numbered = numbered and int(map.checkpoints[i].number) == i + 1
	_expect(n >= 5 and numbered, "%d gates, numbered 1 to %d in order" % [n, n])
	var finishes := map.checkpoints.filter(func(c): return c.finish)
	_expect(finishes.size() == 1 and n > 0 and map.checkpoints[n - 1].finish, "exactly one finish, and it is the last gate")
	_expect(map.route.size() >= 20, "a bot route of %d points" % map.route.size())
	_expect(map.hazards.size() > 0, "%d hazards (touch one: back to your checkpoint)" % map.hazards.size())
	_expect(map.movers.size() > 0 and map.movers.all(func(m): return m.body != null), "%d moving parts, each built as a moving body" % map.movers.size())
	var lowest := INF
	for c in map.checkpoints:
		lowest = minf(lowest, (c.xf as Transform3D).origin.y)
	_expect(map.kill_height < lowest - 4.0, "falling off (below %.0f m) is well under every gate" % map.kill_height)
	var t := 1.234
	var moved := map.movers.any(func(m): return not (m.node as MapMover).offset_at(t).is_equal_approx((m.node as MapMover).offset_at(t + 1.0)))
	_expect(moved, "the moving parts move")


func _check_modes() -> void:
	print("  race maps and arena maps")
	var race := Maps.ids_for("race")
	var ffa := Maps.ids_for("ffa")
	_expect(race.size() >= 3, "%d race maps" % race.size())
	_expect(race.all(func(id): return not ffa.has(id)), "no map is both a race map and an arena")
	_expect(not Maps.fits(race[0], "ffa") and not Maps.fits(ffa[0], "race"), "a race map does not fit a shoot-out, an arena does not fit a race")
	var pick := OptionButton.new()
	Maps.fill(pick, ffa[0], "race")
	_expect(pick.item_count == race.size() and Maps.picked(pick) == race[0], "the race map list shows only race maps (and falls back to the first)")
	pick.free()


func _check_face_moves() -> void:
	print("  resize handles")
	var b := MapBlock.new()
	b.size = Vector3(2, 2, 2)
	b.move_face(0, 3.0, 0.1)   # +x face out to 3 m from the centre
	_expect(b.size.is_equal_approx(Vector3(4, 2, 2)) and b.position.is_equal_approx(Vector3(1, 0, 0)),
		"dragging the +x face grows the box that way only (size %s, centre %s)" % [b.size, b.position])
	b.move_face(3, 0.5, 0.1)   # bottom face up to 0.5 m below the centre
	_expect(is_equal_approx(b.size.y, 1.5) and is_equal_approx(b.position.y, 0.25),
		"dragging the bottom face up keeps the top in place (height %.2f, centre %.2f)" % [b.size.y, b.position.y])
	b.move_face(1, 2.04, 0.1)
	_expect(is_equal_approx(b.size.x, 4.0), "sizes snap to the step (width %.2f)" % b.size.x)
	b.rotation.y = PI / 2.0
	b.position = Vector3.ZERO
	b.move_face(4, 2.0, 0.1)   # +z face of a turned box moves along world x
	_expect(is_equal_approx(b.size.z, 3.0) and b.position.is_equal_approx(Vector3(0.5, 0, 0)),
		"a turned box grows along its own axis (centre %s)" % b.position)
	var c := MapBlock.new()
	c.shape = MapBlock.Shape.CYLINDER
	c.move_face(0, 1.5, 0.1)
	_expect(c.size.is_equal_approx(Vector3(3, 1, 3)) and c.position == Vector3.ZERO, "a cylinder's side handle sets its diameter")
	b.free()
	c.free()
	_check_cone()
	_check_hull_shapes()


## Wedges, bevelled boxes, domes and arches: each fills its box, is closed all round
## with every face seen from outside, and is bumped into as the same corners.
func _check_hull_shapes() -> void:
	print("  wedges, bevelled boxes, domes and arches")
	var map := MapRoot.new()
	var cases := [
		["a wedge", MapBlock.Shape.WEDGE, Vector3(4, 2, 6), {}, 1],
		["a bevelled box", MapBlock.Shape.BEVEL, Vector3(3, 1, 2), {"bevel": 0.2}, 1],
		["a dome", MapBlock.Shape.DOME, Vector3(8, 4, 8), {"sides": 16}, 1],
		["a hollow dome", MapBlock.Shape.DOME, Vector3(8, 4, 8), {"sides": 16, "inner": 7.0}, 64],
		["a hollow dome with a slit", MapBlock.Shape.DOME, Vector3(8, 4, 8), {"sides": 15, "inner": 7.0, "arc": 337.5}, 45],
		["a solid dome with a slice out", MapBlock.Shape.DOME, Vector3(8, 4, 8), {"sides": 12, "arc": 270.0}, 12],
		["an arch", MapBlock.Shape.ARCH, Vector3(4, 2.5, 0.6), {"sides": 10, "top": 0.5}, 10],
		["an arch with legs", MapBlock.Shape.ARCH, Vector3(4, 3, 0.6), {"sides": 8, "inner": 3.0, "top": 0.4}, 10],
	]
	for case in cases:
		var b := MapBlock.new()
		b.shape = case[1]
		b.size = case[2]
		for key in case[3]:
			b.set(key, case[3][key])
		var piece := b.to_piece(Transform3D.IDENTITY)
		var mesh: ArrayMesh = MapMesher.build([piece])[b.kind]
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		var box := AABB(verts[0], Vector3.ZERO)
		var wound := true
		var edges := {}
		for t in range(0, verts.size(), 3):
			for k in 3:
				box = box.expand(verts[t + k])
				var from := verts[t + k].snappedf(0.001)
				var to := verts[t + (k + 1) % 3].snappedf(0.001)
				if from != to:
					edges[[from, to]] = edges.get([from, to], 0) + 1
			if (verts[t + 2] - verts[t]).cross(verts[t + 1] - verts[t]).dot(normals[t]) < -0.0001:
				wound = false
		var open_edges := 0
		for edge in edges:
			if edges.get([edge[1], edge[0]], 0) != edges[edge]:
				open_edges += 1
		if not case[3].has("arc"):   # (with a slice out it stops short on that side)
			_expect(box.size.is_equal_approx(case[2]) and box.get_center().length() < 0.001, "%s fills its box (%s)" % [case[0], box.size])
		_expect(wound, "%s: every face is wound to be seen from the side its normal points" % case[0])
		_expect(open_edges == 0, "%s is closed all round (%d open edges)" % [case[0], open_edges])
		var shapes := map.collision_shapes(piece)
		var convex := true
		for shape in shapes:
			convex = convex and shape is ConvexPolygonShape3D
		_expect(shapes.size() == case[4] and convex, "%s is bumped into as %d convex lump(s) (%d)" % [case[0], case[4], shapes.size()])
		b.free()
	# What they are for: a wedge's slope, a dome's top, the way through an arch.
	var w := MapBlock.new()
	w.shape = MapBlock.Shape.WEDGE
	w.size = Vector3(4, 2, 6)
	var pts := MapMesher.wedge_points(w.to_piece(Transform3D.IDENTITY))
	var top_z := -INF
	var foot_z := -INF
	for p in pts:
		if p.y > 0.0:
			top_z = maxf(top_z, p.z)
		else:
			foot_z = maxf(foot_z, p.z)
	_expect(is_equal_approx(top_z, -3.0) and is_equal_approx(foot_z, 3.0), "a wedge is tall at the back (-z) and runs down to its front edge (+z)")
	w.free()
	var arch := MapBlock.new()
	arch.shape = MapBlock.Shape.ARCH
	arch.size = Vector3(4, 3, 0.6)
	arch.inner = 3.0
	arch.top = 0.4
	var open := MapMesher.arch_opening(arch.to_piece(Transform3D.IDENTITY))
	_expect(open.is_equal_approx(Vector2(1.5, 2.6)), "an arch's opening is Inner wide and stops Top short of the block's top (%s)" % open)
	_expect(not arch.is_round() and MapBlock.SHAPE_NAMES.size() == MapBlock.Shape.size(), "every shape has a name, and only cylinders, tubes and cones have one diameter")
	arch.free()
	map.free()


## A cone: its mesh and its collision are the same flat-sided shape, narrowing to its
## top, and you stand on it only where it is gentle enough.
func _check_cone() -> void:
	print("  cones")
	var k := MapBlock.new()
	k.shape = MapBlock.Shape.CONE
	k.size = Vector3(4, 2, 4)
	k.sides = 16
	k.move_face(0, 3.0, 0.1)
	_expect(k.size.is_equal_approx(Vector3(6, 2, 6)), "a cone's side handle sets the diameter of its foot (%s)" % k.size)
	k.size = Vector3(4, 2, 4)
	var piece := k.to_piece(Transform3D.IDENTITY)
	_expect(piece.shape == "cone" and piece.top == 0.0, "a cone's piece says cone, with its top (%s)" % piece.get("top"))
	var mesh: ArrayMesh = MapMesher.build([piece])[k.kind]
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var hi := -INF
	var widest_at_top := 0.0
	var outward := true
	for i in verts.size():
		hi = maxf(hi, verts[i].y)
		if is_equal_approx(verts[i].y, 1.0):
			widest_at_top = maxf(widest_at_top, Vector2(verts[i].x, verts[i].z).length())
	for t in range(0, verts.size(), 3):
		var mid := (verts[t] + verts[t + 1] + verts[t + 2]) / 3.0
		var n := normals[t]
		# The triangle's own winding must agree with its normal (Godot: clockwise is the front).
		var wound := (verts[t + 2] - verts[t]).cross(verts[t + 1] - verts[t])
		if wound.dot(n) <= 0.0 or (n.y > -0.99 and Vector2(n.x, n.z).dot(Vector2(mid.x, mid.z)) < 0.0):
			outward = false
	_expect(is_equal_approx(hi, 1.0) and widest_at_top < 0.001, "it comes to a point at the top (%.3f m wide there)" % widest_at_top)
	_expect(outward, "every face points outward and is wound to be seen from outside")
	var map := MapRoot.new()
	var shape := map._collision_shape(piece) as ConvexPolygonShape3D
	_expect(shape != null and shape.points.size() == 17, "its collision is a convex hull of the same 17 corners (%s)" % [shape.points.size() if shape else "none"])
	k.top = 1.0
	var cut := k.to_piece(Transform3D.IDENTITY)
	var cut_shape := map._collision_shape(cut) as ConvexPolygonShape3D
	_expect(cut_shape != null and cut_shape.points.size() == 32, "with a top it is cut off flat (%d corners)" % (cut_shape.points.size() if cut_shape else 0))
	# A steep cone sheds you; a low one you can stand on.
	var side := MapMesher.cone_side_normal(Vector3(1, 0, 0), Vector3(cos(TAU / 16), 0, sin(TAU / 16)), 2.0, 0.0, 2.0)
	_expect(absf(rad_to_deg(acos(side.y)) - 45.0) < 1.5, "the side of a cone as tall as it is wide-at-the-foot-halved slopes about 45 degrees (%.1f)" % rad_to_deg(acos(side.y)))
	map.free()
	k.free()


func _expect(ok: bool, what: String) -> void:
	print("    %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1
