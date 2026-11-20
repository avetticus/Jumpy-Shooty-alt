extends SceneTree
## The map tools (addons/map_tools/map_ops.gd) and the parametric pieces (MapStairs,
## MapRow, MapRing), without the editor:
##  - the grid steps and snaps;
##  - Hollow keeps a box's outside and makes six walls that do not overlap;
##  - Clip's two halves add up to the block, and only shapes that can be cut are;
##  - a mirror twice over is where it started, never scales by -1, and carries a group;
##  - hulls: any block made editable keeps its corners where they were (a shape of
##    several lumps becomes a group), draws and collides as itself, stretches with its
##    Size, keeps its corners centred, mirrors as its mirror image, and knows its top;
##  - arrays in a line and round a circle;
##  - face snapping picks the nearest face of a neighbour square to the block;
##  - each piece makes the blocks its numbers say, and makes them again when they change;
##  - a prefab saved and placed is plain blocks with no tie to its file, and builds;
##  - the tools, driven by made-up mouse events through a camera: Draw (on the ground,
##    on a block, in a top view), Clip and Place; the handles on stairs and rows;
##  - the Vertex tool: pick, drag (level and up/down), refuse a dent, nudge, delete,
##    box-select, move corners two blocks share, add a corner, click to select; edges
##    and faces; pushing a face, and a hull's face handles;
##  - clipping at an angle: a box cut square stays boxes, any other cut makes hulls; a
##    line dragged in a top view, or across a face in 3D (with a third point), what is
##    kept, giving up;
##  - CSG: a doorway subtracted from a wall leaves three boxes of the right volume and
##    takes the cutter away; merge (convex, as TrenchBroom's) and intersect; hollowing a
##    wedge and an open-topped cube;
##  - the commands: Hollow, Mirror, Array, the toggles, Paint, Snap, Bake.
## Run: godot --headless --path . --script tests/map_tools_test.gd

const MapOps := preload("res://addons/map_tools/map_ops.gd")
const MapContext := preload("res://addons/map_tools/map_context.gd")
const MapView := preload("res://addons/map_tools/map_view.gd")
const MapCommands := preload("res://addons/map_tools/map_commands.gd")
const ToolDraw := preload("res://addons/map_tools/tool_draw.gd")
const ToolClip := preload("res://addons/map_tools/tool_clip.gd")
const PieceGizmo := preload("res://addons/map_tools/piece_gizmo.gd")
const ToolPlace := preload("res://addons/map_tools/tool_place.gd")
const ToolVertex := preload("res://addons/map_tools/tool_vertex.gd")

var failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame   # the cameras the tool checks use must be in the running scene
	print("Map tools checks")
	_check_grid()
	_check_hollow()
	_check_clip()
	_check_mirror()
	_check_hulls()
	_check_array()
	_check_snapping()
	_check_pieces()
	_check_prefab()
	_check_tools()
	_check_vertex_tool()
	_check_angled_clip()
	_check_csg()
	_check_commands()
	print("FAIL: %d checks failed" % failures if failures else "PASS: every check passed")
	quit(1 if failures else 0)


func _expect(ok: bool, what: String) -> void:
	print("    %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func _block(parent: Node, at: Vector3, size: Vector3, kind := "concrete") -> MapBlock:
	var b := MapBlock.new()
	b.kind = kind
	b.size = size
	b.position = at
	parent.add_child(b)
	return b


func _volume(blocks: Array) -> float:
	var v := 0.0
	for b: MapBlock in blocks:
		v += b.size.x * b.size.y * b.size.z
	return v


func _check_grid() -> void:
	print("  grid")
	_expect(is_equal_approx(MapOps.snap(1.26, 0.25), 1.25) and is_equal_approx(MapOps.snap(-0.44, 0.1), -0.4), "a length snaps to the nearest grid line")
	_expect(is_equal_approx(MapOps.grid_step(0.5, 1), 1.0) and is_equal_approx(MapOps.grid_step(0.5, -1), 0.25), "] and [ step the grid up and down")
	_expect(is_equal_approx(MapOps.grid_step(4.0, 1), 4.0) and is_equal_approx(MapOps.grid_step(0.1, -1), 0.1), "the grid stops at its largest and smallest size")
	var box := MapOps.box_between(Vector3(2, 0, 3), Vector3(-1, 0, 5), 0.5)
	_expect((box[1] as Vector3).is_equal_approx(Vector3(3, 0.5, 2)) and (box[0] as Vector3).is_equal_approx(Vector3(0.5, 0.25, 4)), "a box drawn between two corners is never flat")


func _check_hollow() -> void:
	print("  hollow")
	var map := MapRoot.new()
	root.add_child(map)
	var b := _block(map, Vector3(3, 2, -4), Vector3(8, 4, 6), "drywall")
	b.rotation.y = 0.5
	b.tint = Color(0.9, 0.9, 0.9)
	var room := MapOps.hollow(b, 0.5)
	_expect(room != null and room.get_child_count() == 6, "a box becomes six walls")
	if room:
		map.add_child(room)
		var walls := MapOps.blocks_in(room)
		_expect(room.transform.is_equal_approx(b.transform) and room.get_meta("_edit_group_", false), "the room is a selection group where the block was")
		var inside := 7.0 * 3.0 * 5.0
		_expect(is_equal_approx(_volume(walls), 8.0 * 4.0 * 6.0 - inside), "the walls fill the box less the room inside (no overlaps)")
		var bounds := MapOps.bounds_of([room])
		var before := MapOps.bounds_of([b])
		_expect(bounds.position.is_equal_approx(before.position) and bounds.size.is_equal_approx(before.size), "the outside is the same size")
		_expect(walls.all(func(w: MapBlock) -> bool: return w.kind == "drywall" and w.tint == b.tint), "every wall keeps the block's kind and tint")
		var open := MapOps.hollow(b, 0.5, true, true)
		_expect(open.get_child_count() == 4 and MapOps.blocks_in(open).all(func(w: MapBlock) -> bool: return is_equal_approx(w.size.y, 4.0)),
			"with no floor and an open top, four walls the full height")
		open.free()
	_expect(MapOps.hollow(b, 2.0) == null, "walls too thick for the box are refused")
	b.shape = MapBlock.Shape.CYLINDER
	_expect(MapOps.hollow(b, 0.5) == null, "only boxes are hollowed")
	map.free()


func _check_clip() -> void:
	print("  clip")
	var map := MapRoot.new()
	root.add_child(map)
	var b := _block(map, Vector3(10, 1, 0), Vector3(6, 2, 4), "steel")
	b.rotation.y = PI / 2.0
	b.solid = false
	var parts := MapOps.clip(b, 0, 1.0)
	_expect(parts.size() == 2, "a box is cut in two")
	if parts.size() == 2:
		_expect(is_equal_approx(parts[0].size.x, 4.0) and is_equal_approx(parts[1].size.x, 2.0), "the halves' lengths add up (4 m + 2 m of 6 m)")
		for p in parts:
			map.add_child(p)
		var far_before: Vector3 = b.transform * Vector3(-3, 0, 0)
		var far_after: Vector3 = parts[0].transform * Vector3(-2, 0, 0)
		var cut_a: Vector3 = parts[0].transform * Vector3(2, 0, 0)
		var cut_b: Vector3 = parts[1].transform * Vector3(-1, 0, 0)
		_expect(far_before.is_equal_approx(far_after) and cut_a.is_equal_approx(cut_b) and cut_a.is_equal_approx(b.transform * Vector3(1, 0, 0)),
			"the outer faces stay put and the halves meet at the cut")
		_expect(parts.all(func(p: MapBlock) -> bool: return p.kind == "steel" and not p.solid), "both halves keep the block's settings")
	_expect(MapOps.clip(b, 0, 3.0).is_empty() and MapOps.clip(b, 0, -5.0).is_empty(), "a cut that misses the block does nothing")
	b.shape = MapBlock.Shape.CYLINDER
	var discs := MapOps.clip(b, 1, 0.0)
	_expect(MapOps.clip(b, 0, 0.0).is_empty() and discs.size() == 2, "a cylinder is only cut across its height")
	for p in discs:
		p.free()
	b.shape = MapBlock.Shape.CONE
	_expect(MapOps.clip(b, 1, 0.0).is_empty(), "a cone is not cut")
	map.free()


func _check_mirror() -> void:
	print("  mirror")
	var map := MapRoot.new()
	root.add_child(map)
	var group := Node3D.new()
	group.position = Vector3(8, 0, 3)
	group.rotation.y = 0.4
	map.add_child(group)
	var wedge := _block(group, Vector3(1, 1, 2), Vector3(2, 2, 4))
	wedge.shape = MapBlock.Shape.WEDGE
	wedge.rotation.y = 0.3
	var copy := MapOps.mirrored_copy(group, 0, Vector3.ZERO)
	map.add_child(copy)
	var cw := MapOps.blocks_in(copy)[0]
	var want: Vector3 = MapOps.global_of(wedge).origin * Vector3(-1, 1, 1)
	_expect(MapOps.global_of(cw).origin.is_equal_approx(want), "a block in a mirrored group lands at the mirror of where it was")
	# The wedge's tall side is its -z: mirrored across x, that direction's x flips.
	var back: Vector3 = MapOps.global_of(wedge).basis * Vector3(0, 0, -1)
	var back_copy: Vector3 = MapOps.global_of(cw).basis * Vector3(0, 0, -1)
	_expect(back_copy.is_equal_approx(back * Vector3(-1, 1, 1)), "and faces the mirrored way")
	_expect(MapOps.global_of(cw).basis.determinant() > 0.0 and copy.transform.basis.determinant() > 0.0, "nothing is scaled by -1")
	var twice := MapOps.mirrored_copy(copy, 0, Vector3.ZERO)
	map.add_child(twice)
	_expect(MapOps.global_of(MapOps.blocks_in(twice)[0]).is_equal_approx(MapOps.global_of(wedge)), "mirrored twice it is back where it started")
	var plan := MapOps.mirror_plan(group, 2, Vector3(0, 0, 10))
	for step in plan:
		(step[0] as Node3D).transform = step[1]
	_expect(is_equal_approx(MapOps.global_of(group).origin.z, 17.0) and plan.size() == 2, "mirroring in place across z = 10 moves the group and what is in it")
	map.free()


## The corners of a block's shape in the map, every lump's together.
func _corners(block: MapBlock) -> Array:
	var xf := MapOps.global_of(block)
	var out := []
	for lump in block.shape_lumps():
		for p in MapMesher.hull_corners(lump):
			out.append(xf * p)
	return out


func _corners_of(blocks: Array) -> Array:
	var out := []
	for b: MapBlock in blocks:
		out.append_array(_corners(b))
	return out


## The same points (within a millimetre), in any order.
func _same_points(a: Array, b: Array) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	for p: Vector3 in a:
		if not b.any(func(q: Vector3) -> bool: return q.distance_to(p) < 0.001):
			return false
	return true


func _check_hulls() -> void:
	print("  hulls")
	var map := MapRoot.new()
	root.add_child(map)

	# A box made editable is the same box, as eight corners.
	var box := _block(map, Vector3(4, 1, -2), Vector3(4, 2, 6), "steel")
	box.rotation.y = 0.7
	box.tint = Color(0.8, 0.8, 0.8)
	var hull := MapOps.make_editable(box) as MapBlock
	_expect(hull != null and hull.shape == MapBlock.Shape.HULL and hull.points.size() == 8, "a box made editable is a hull of 8 corners")
	if hull:
		map.add_child(hull)
		_expect(hull.size.is_equal_approx(box.size) and hull.transform.is_equal_approx(box.transform), "of the same size, where the box was")
		_expect(_same_points(_corners(hull), _corners(box)), "with the box's corners")
		_expect(hull.kind == "steel" and hull.tint == box.tint, "and the box's kind and tint")
		var piece := hull.to_piece(MapOps.global_of(hull))
		_expect(piece.shape == "hull" and (piece.planes as Array).size() == 6, "its piece is a hull with six faces")
		var mesh: ArrayMesh = MapMesher.build([piece]).get("steel")
		_expect(mesh != null and mesh.surface_get_array_len(0) == 36, "drawn as 12 triangles, as the box is")
		var shapes := map.collision_shapes(piece)
		_expect(shapes.size() == 1 and shapes[0] is ConvexPolygonShape3D and (shapes[0] as ConvexPolygonShape3D).points.size() == 8,
			"and bumped into as one convex shape of its corners")
		hull.size = Vector3(8, 2, 3)
		_expect(MapBlock.points_bounds(hull.points).size.is_equal_approx(Vector3(8, 2, 3)), "a new Size stretches the corners to fit")
		hull.size = box.size
		_expect(_same_points(_corners(hull), _corners(box)), "and back again")
		var moved := hull.points
		moved[0] += Vector3(-1, 0, 0)   # the corner at -x -y -z, pulled out a metre
		hull.points = moved
		_expect(MapBlock.points_bounds(hull.points).get_center().is_zero_approx() and is_equal_approx(hull.size.x, 5.0),
			"its corners are kept centred, and Size is the box round them")
		var flat := MapBlock.new()
		flat.shape = MapBlock.Shape.HULL
		flat.points = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)])
		map.add_child(flat)
		_expect(flat.to_piece(Transform3D.IDENTITY).shape == "box" and " ".join(flat._get_configuration_warnings()).contains("four corners"),
			"a hull with no volume stands in as a box, and warns")
		flat.free()
		_expect(MapOps.make_editable(hull) == null, "a hull is not made editable again")

	# Shapes off their own middle, scaled and tilted, keep every corner where it was.
	var cone := _block(map, Vector3(-6, 2, 3), Vector3(3, 4, 3))
	cone.shape = MapBlock.Shape.CONE
	cone.sides = 5
	cone.rotation = Vector3(0.2, 1.1, 0.0)
	cone.scale = Vector3(1, 2, 1)
	var stub := MapBlock.new()   # something standing under the cone
	stub.position = Vector3(0, 3, 0)
	cone.add_child(stub)
	var cone_hull := MapOps.make_editable(cone) as MapBlock
	if cone_hull:
		map.add_child(cone_hull)
	_expect(cone_hull != null and cone_hull.points.size() == 6 and _same_points(_corners(cone_hull), _corners(cone)),
		"a five-sided cone (not centred on its own axis), tilted and scaled, keeps its corners where they were")
	_expect(cone_hull != null and cone_hull.get_child_count() == 1 and MapOps.global_of(cone_hull.get_child(0)).origin.is_equal_approx(MapOps.global_of(stub).origin),
		"and what stands under it stays where it was")
	var pipe := _block(map, Vector3(0, 0, 9), Vector3(2, 3, 2))
	pipe.shape = MapBlock.Shape.CYLINDER
	var pipe_hull := MapOps.make_editable(pipe) as MapBlock
	_expect(pipe_hull != null and pipe_hull.points.size() == 24, "a 12-sided cylinder is a hull of 24 corners")
	if pipe_hull:
		pipe_hull.free()
	pipe.sides = 20
	_expect(MapOps.make_editable(pipe) == null, "one of 40 corners is too many (at most %d)" % MapMesher.MAX_HULL_CORNERS)
	var stored := func(b: MapBlock) -> bool:
		for p in b.get_property_list():
			if p.name == "points":
				return p.usage & PROPERTY_USAGE_STORAGE != 0
		return false
	_expect(not stored.call(pipe) and cone_hull != null and stored.call(cone_hull), "only a hull saves its Points (no empty list in every block of a map)")
	pipe.shape = MapBlock.Shape.TUBE
	pipe.sides = 8
	pipe.inner = 1.0
	var tube := MapOps.make_editable(pipe)
	if tube:
		map.add_child(tube)
	_expect(tube != null and not (tube is MapBlock) and tube.get_child_count() == 8 and tube.get_meta("_edit_group_", false),
		"a tube is a group of hull blocks, one for each side, so its hole stays")
	_expect(tube != null and _same_points(_corners_of(MapOps.blocks_in(tube)), _corners(pipe)), "with all the tube's corners where they were")

	# A mirror turns a hull's corners inside out, as a mirror image.
	var group := Node3D.new()
	group.position = Vector3(5, 0, 5)
	group.rotation.y = 0.6
	map.add_child(group)
	var spike := MapBlock.new()   # a lopsided corner piece: not the same either side of its own x
	spike.shape = MapBlock.Shape.HULL
	spike.points = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(0, 0, 2), Vector3(0, 1, 0)])
	spike.position = Vector3(1, 0, 2)
	spike.rotation.y = 0.3
	group.add_child(spike)
	var want := []
	for p: Vector3 in _corners(spike):
		want.append(p * Vector3(-1, 1, 1))
	var copy := MapOps.mirrored_copy(group, 0, Vector3.ZERO)
	map.add_child(copy)
	var mirrored := MapOps.blocks_in(copy)[0]
	_expect(_same_points(_corners(mirrored), want), "a mirrored copy of a lopsided hull is its mirror image")
	var ctx := _context(map)
	_picked = [group]
	var start := _corners(spike)
	ctx.commit.call(MapCommands.mirror(ctx, 0, Vector3.ZERO, false))
	_expect(_same_points(_corners(spike), want), "mirrored in place, too")
	ctx.commit.call(MapCommands.mirror(ctx, 0, Vector3.ZERO, false))
	_expect(_same_points(_corners(spike), start), "and twice over it is as it was")

	# Make Editable, the command.
	var crate := _block(map, Vector3(-10, 0.5, -10), Vector3(1, 1, 1), "wood")
	var made := _block(map, Vector3(-12, 0.5, -10), Vector3(1, 1, 1), "wood")
	made.set_meta(MapPiece.GENERATED, true)
	_picked = [crate, made]
	ctx.commit.call(MapCommands.make_editable(ctx))
	_expect(_picked.size() == 1 and (_picked[0] as MapBlock).shape == MapBlock.Shape.HULL and not crate.is_inside_tree() and made.shape == MapBlock.Shape.BOX,
		"Make Editable replaces the selected box with a hull, and leaves a block a piece made")
	_release(ctx)
	crate.free()

	# Where its top is, for standing on it and for hazards.
	var planes := MapMesher.hull_planes(MapMesher.wedge_points({"size": Vector3(4, 2, 4)}))
	_expect(is_equal_approx(MapMesher.hull_top(planes, 0, 0), 0.0) and is_equal_approx(MapMesher.hull_top(planes, 1, -2), 1.0),
		"a slope's top is half way up in its middle and at the top at its back")
	_expect(MapMesher.hull_top(planes, 3, 0) == -INF and is_equal_approx(MapMesher.hull_top(planes, 3, 0, 1.5), 0.0),
		"off its side there is no top, unless there is a margin to spare")
	_expect(MapMesher.hull_has(planes, Vector3(0, -0.5, 0)) and not MapMesher.hull_has(planes, Vector3(0, 0, 0.5)),
		"a point under the slope is inside it, one over it is not")
	map.free()
	_check_extrude()


## The index of the face of `points` that looks most nearly along `dir`.
func _face_toward(points: PackedVector3Array, dir: Vector3) -> int:
	var planes := MapMesher.hull_planes(points)
	var best := -1
	for i in planes.size():
		if best < 0 or planes[i].normal.dot(dir) > planes[best].normal.dot(dir):
			best = i
	return best


func _check_extrude() -> void:
	print("  pushing faces")
	var cube := PackedVector3Array()
	for i in 8:
		cube.append(Vector3(1 if i & 1 else -1, 1 if i & 2 else -1, 1 if i & 4 else -1))
	var taller := MapOps.extruded(cube, _face_toward(cube, Vector3.UP), 1.0)
	_expect(taller.size() == 8 and MapBlock.points_bounds(taller).is_equal_approx(AABB(Vector3(-1, -1, -1), Vector3(2, 3, 2))),
		"a cube's top pushed up 1 m: 3 m tall, the rest where it was")
	_expect(MapOps.extruded(cube, _face_toward(cube, Vector3.UP), -2.5).is_empty(), "pulled in through the bottom, it is refused")

	var wedge := MapMesher.wedge_points({"size": Vector3(4, 2, 4)})
	var slope := _face_toward(wedge, Vector3(0, 1, 1))
	var slope_plane: Plane = MapMesher.hull_planes(wedge)[slope]
	var fuller := MapOps.extruded(wedge, slope, 0.5)
	var after := MapMesher.hull_planes(fuller)
	var has_plane := func(n: Vector3, d: float) -> bool:
		return after.any(func(p: Plane) -> bool: return p.normal.dot(n) > 0.9999 and absf(p.d - d) < 0.001)
	_expect(has_plane.call(slope_plane.normal, slope_plane.d + 0.5), "a wedge's slope pushed out 0.5 m lies 0.5 m further out")
	_expect(has_plane.call(Vector3.DOWN, 1.0) and has_plane.call(Vector3.BACK * -1.0, 2.0) and has_plane.call(Vector3.RIGHT, 2.0),
		"and the bottom, back and sides keep their planes")

	# A cube with one corner cut off: the small slanted face pulled out past the corner
	# it cut would vanish.
	var chamfered := PackedVector3Array()
	for p in cube:
		if p != Vector3.ONE:
			chamfered.append(p)
	chamfered.append_array([Vector3(0.5, 1, 1), Vector3(1, 0.5, 1), Vector3(1, 1, 0.5)])
	var cut := _face_toward(chamfered, Vector3.ONE)
	_expect(not MapOps.extruded(chamfered, cut, 0.1).is_empty(), "a corner cut, pulled out a little, is a smaller cut")
	_expect(MapOps.extruded(chamfered, cut, 1.0).is_empty(), "pulled out past the corner it cut, it would vanish: refused")

	# Over and over: a five-sided cone with a flat top (its slanted faces do not lie on
	# the grid), each face pushed out and back again and the whole stretched and shrunk,
	# forty times. It must stay 10 corners and 7 faces: a face whose corners drift a hair
	# out of one plane used to be found twice, and each push then made stray corners
	# (until the editor ran out of room).
	var cone_map := MapRoot.new()
	root.add_child(cone_map)
	var cone := _block(cone_map, Vector3.ZERO, Vector3(3, 2, 3))
	cone.shape = MapBlock.Shape.CONE
	cone.sides = 5
	cone.top = 1.0
	var spun := MapOps.make_editable(cone) as MapBlock
	cone_map.add_child(spun)
	var counts := {}
	for round in 40:
		for by in [0.37, -0.37]:
			var face := round % MapMesher.hull_planes(spun.points).size()
			var pts := MapOps.extruded(spun.points, face, by)
			if not pts.is_empty():
				var placed := MapOps.hull_placement(spun, pts, spun.position)
				spun.points = placed[0]
				spun.position = placed[1]
		spun.size = spun.size * 1.37
		spun.size = spun.size / 1.37
		counts["%d corners, %d faces" % [MapMesher.hull_corners(spun.points).size(), MapMesher.hull_planes(spun.points).size()]] = true
	_expect(counts.keys() == ["10 corners, 7 faces"],
		"a hull pushed and stretched forty times keeps its corners and faces (%s)" % ", ".join(counts.keys()))
	cone_map.free()

	# Messy corners, a few millimetres apart (two hulls an editor session left behind,
	# drawn with faces missing): what is drawn must close up all the same, every edge
	# shared by two faces and nothing left open.
	var messy := [
		PackedVector3Array([Vector3(1.9475, -0.1507, -0.5004), Vector3(2.0462, -1.3498, -1.2499), Vector3(-1.9497, -1.3499, -1.25),
			Vector3(2.05, -0.1639, 1.2201), Vector3(2.05, -0.1496, 1.25), Vector3(2.05, -1.3498, -1.186), Vector3(2.05, -1.35, 1.25),
			Vector3(2.0193, 0.108, 1.25), Vector3(2.0498, -0.1481, 1.25), Vector3(1.8665, 1.35, 1.1656), Vector3(1.8602, 1.35, 1.0581),
			Vector3(1.9076, 1.0463, 1.25), Vector3(1.8802, 1.0059, 0.7083), Vector3(1.8808, 0.9992, 0.7016), Vector3(1.8714, 1.35, 1.25),
			Vector3(0.3253, 1.35, 1.25), Vector3(-2.05, -0.15, 0.0), Vector3(-1.95, 1.0742, 1.25), Vector3(-1.95, -1.35, 1.25)]),
		PackedVector3Array([Vector3(-4.6136, -3.25, -6.1578), Vector3(-3.8024, 3.25, -6.19), Vector3(-4.1124, -3.25, 6.4775),
			Vector3(-3.2981, 3.25, 6.5222), Vector3(-3.5906, 0.9092, 6.5238), Vector3(4.6136, -3.25, -6.5239),
			Vector3(4.6136, 3.25, -6.5239), Vector3(4.6136, -3.25, 6.4775), Vector3(4.6136, 3.25, 6.4775)]),
	]
	for pts in messy:
		var edges := {}
		var total := Vector3.ZERO
		for face in MapMesher.hull_surface(pts):
			var ring: Array = face[1]
			for k in ring.size():
				var p: Vector3 = ring[k]
				var q: Vector3 = ring[(k + 1) % ring.size()]
				total += p.cross(q) * 0.5
				var key := "%s|%s" % ([p, q] if str(p) < str(q) else [q, p])
				edges[key] = edges.get(key, 0) + 1
		_expect(edges.values().all(func(c: int) -> bool: return c == 2) and total.length() < 0.001,
			"messy corners still draw closed: every edge shared by two faces (%d edges), nothing open (%.4f m²)" % [edges.size(), total.length()])

	# A face handle: a cube block, turned and stretched to 4 m tall, its top dragged up
	# by a ray passing 1.1 m over it.
	var map := MapRoot.new()
	root.add_child(map)
	var block := _hull_box(map, Vector3(3, 2, 0), Vector3(2, 2, 2))
	block.rotation.y = 0.5
	block.scale = Vector3(1, 2, 1)   # 2 m of its own is 4 m in the map: it stands from y = 0 to y = 4
	var top := _face_toward(block.points, Vector3.UP)
	var placed := MapOps.pushed_face(block, block.points, block.position, top, Vector3(20, 5.1, 0), Vector3(-1, 0, 0), 0.5)
	_expect(not placed.is_empty(), "a hull's face handle, dragged, gives a new shape")
	if not placed.is_empty():
		block.points = placed[0]
		block.position = placed[1]
		var box := MapOps.bounds_of([block])
		_expect(is_equal_approx(box.end.y, 5.0) and is_equal_approx(box.position.y, 0.0),
			"its top goes up 1 m in the map (on the grid), its foot stays on the ground (%s to %s)" % [box.position.y, box.end.y])
	map.free()


func _check_array() -> void:
	print("  array")
	var map := MapRoot.new()
	root.add_child(map)
	var holder := Node3D.new()
	holder.position = Vector3(0, 5, 0)
	map.add_child(holder)
	var b := _block(holder, Vector3(10, 0, 0), Vector3(1, 3, 1))
	var line := MapOps.array_line(b, 3, Vector3(0, 0, 2))
	_expect(line.size() == 3 and line[2].position.is_equal_approx(Vector3(10, 0, 6)), "three copies in a line, 2 m apart")
	for n in line:
		n.free()
	var ring := MapOps.array_ring(b, 4, Vector3(0, 0, 0))
	_expect(ring.size() == 3, "four round a circle is three copies")
	if ring.size() == 3:
		holder.add_child(ring[1])
		_expect(MapOps.global_of(ring[1]).origin.is_equal_approx(Vector3(-10, 5, 0)), "the one opposite is across the pivot, at the same height")
		var facing: Vector3 = MapOps.global_of(ring[1]).basis.x
		_expect(facing.is_equal_approx(Vector3(-1, 0, 0)), "and is turned half way round")
		ring[0].free()
		ring[2].free()
	map.free()


func _check_snapping() -> void:
	print("  face snapping")
	var map := MapRoot.new()
	root.add_child(map)
	var wall := _block(map, Vector3(5, 1.5, 0), Vector3(1, 3, 8))        # its near face is at x = 4.5
	var turned := _block(map, Vector3(3.3, 1, 0), Vector3(1, 2, 1))
	turned.rotation.y = 0.5                                              # not square: never snapped to
	var far := _block(map, Vector3(4.4, 1, 30), Vector3(1, 2, 1))        # square, but nowhere near
	var mover := _block(map, Vector3(3.37, 1, 1), Vector3(2, 2, 2))      # its far face is at x = 4.37
	var frame: Transform3D = MapOps.box_of(mover)[0]
	var others := MapOps.boxes_in_frame(frame, [wall, turned, far])
	_expect(others.size() == 2, "a block turned another way is left out")
	var box: AABB = MapOps.boxes_in_frame(frame, [mover])[0]
	var result := MapOps.snap_move(box, others, 0.25)
	var move: Vector3 = result[0]
	_expect(is_equal_approx(move.x, 0.13) and result[1].x == 1, "a block 0.13 m short of a wall snaps against it (moved %.2f)" % move.x)
	_expect(is_zero_approx(move.z) and result[1].z == 0, "and is not pulled toward a block that is not beside it")
	_expect(MapOps.snap_move(box, others, 0.1)[1] == Vector3i.ZERO, "nothing within reach: no snap")
	var quarter := _block(map, Vector3(-6, 1, 0), Vector3(2, 2, 6))
	quarter.rotation.y = PI / 2.0                                        # a quarter turn is still square: 6 m along x
	var seen := MapOps.boxes_in_frame(frame, [quarter])
	_expect(seen.size() == 1 and seen[0].size.is_equal_approx(Vector3(6, 2, 2)), "a block a quarter turn round still counts, measured the way it lies")
	var d := MapOps.snap_face(box, 0, 1.0, others, 0.25)
	_expect(is_equal_approx(d, 0.13), "a dragged face snaps to the wall's face")
	_expect(MapOps.snap_face(box, 0, -1.0, others, 0.25) == INF, "the face on the other side has nothing to snap to")
	map.free()


func _check_pieces() -> void:
	print("  pieces")
	var map := MapRoot.new()
	root.add_child(map)
	var stairs := MapStairs.new()
	stairs.rise = 3.0
	stairs.run = 6.0
	stairs.step_height = 0.25
	map.add_child(stairs)
	stairs.rebuild()
	var made := stairs.generated()
	_expect(stairs.steps() == 12 and made.size() == 13, "3 m of stairs with 0.25 m steps: 12 steps and the ramp you walk on")
	var walk := made.back() as MapBlock
	_expect(walk.shape == MapBlock.Shape.WEDGE and not walk.drawn and walk.solid and made.slice(0, 12).all(func(s: MapBlock) -> bool: return not s.solid),
		"smooth: the steps are drawn only, an invisible wedge is solid")
	var top := made[11] as MapBlock
	_expect(is_equal_approx(top.position.y + top.size.y * 0.5, 3.0) and is_equal_approx(top.position.z - top.size.z * 0.5, -6.0), "the top step ends 3 m up, 6 m along")
	# The wedge's surface passes through each step's front top edge.
	var first := made[0] as MapBlock
	var nose := Vector3(0, first.size.y, 0.0)
	var along := (walk.position.z + walk.size.z * 0.5 - nose.z) / walk.size.z   # 0 at its low end, 1 at its high end
	_expect(is_equal_approx(along * walk.size.y, nose.y), "the ramp lies on the steps' front edges")
	stairs.smooth = false
	stairs.rebuild()
	_expect(stairs.generated().size() == 12 and stairs.generated().all(func(s: MapBlock) -> bool: return s.solid), "not smooth: solid steps and no ramp")
	stairs.step_height = 0.5
	stairs.rebuild()
	_expect(stairs.generated().size() == 6, "taller steps: fewer of them, the old ones gone")

	var ramp := MapStairs.new()
	ramp.style = MapStairs.Style.RAMP
	ramp.filled = false
	ramp.rise = 3.0
	ramp.run = 4.0
	ramp.thickness = 0.2
	map.add_child(ramp)
	ramp.rebuild()
	var slab := ramp.generated()[0] as MapBlock
	_expect(is_equal_approx(slab.size.z, 5.0) and is_equal_approx(ramp.slope, rad_to_deg(atan2(3.0, 4.0))), "a 3 m by 4 m ramp is a slab 5 m long at 36.9 degrees")
	var top_low: Vector3 = slab.transform * Vector3(0, 0.1, 2.5)
	var top_high: Vector3 = slab.transform * Vector3(0, 0.1, -2.5)
	_expect(top_low.is_equal_approx(Vector3.ZERO) and top_high.is_equal_approx(Vector3(0, 3, -4)), "its top runs from the origin to 3 m up, 4 m along")
	ramp.filled = true
	ramp.rebuild()
	_expect((ramp.generated()[0] as MapBlock).shape == MapBlock.Shape.WEDGE, "filled: one wedge")
	ramp.style = MapStairs.Style.STEPS
	ramp.rebuild()
	_expect(ramp.generated().size() == ramp.steps() + 1, "switched to Steps, the same piece is stairs")
	var shown := {}
	for p in ramp.get_property_list():
		shown[p.name] = p.usage & PROPERTY_USAGE_EDITOR
	ramp.style = MapStairs.Style.RAMP
	ramp.rebuild()
	var as_ramp := {}
	for p in ramp.get_property_list():
		as_ramp[p.name] = p.usage & PROPERTY_USAGE_EDITOR
	_expect(shown.step_height and shown.smooth and not shown.thickness and not as_ramp.step_height and not as_ramp.smooth,
		"the inspector shows the steps' settings only for Steps")

	# The handles: Rise at the top, Run at the far end, Width at the side.
	var handles := PieceGizmo.handles_of(ramp)
	_expect(handles.size() == 3 and (handles[0][1] as Vector3).is_equal_approx(Vector3(0, 3, -4)) and (handles[1][1] as Vector3).is_equal_approx(Vector3(0, 0, -4))
		and (handles[2][1] as Vector3).is_equal_approx(Vector3(ramp.width * 0.5, 0, 0)), "stairs and ramps have Rise, Run and Width handles where those end")
	_expect(is_equal_approx(PieceGizmo.value_for(ramp, handles[0], 4.2, 0.5), 4.0) and is_equal_approx(PieceGizmo.value_for(ramp, handles[2], 1.6, 0.5), 3.0),
		"a handle slid 4.2 m up gives a 4 m rise on a 0.5 m grid; the side handle 1.6 m out, a 3 m width")
	_expect(is_equal_approx(PieceGizmo.value_for(ramp, handles[1], -2.0, 0.5), 0.5), "a handle never goes below one grid square")

	var row := MapRow.new()
	row.count = 5
	row.spacing = Vector3(1.5, 0, 0)
	map.add_child(row)
	var post := _block(row, Vector3(0, 1, 0), Vector3(0.2, 2, 0.2), "steel")
	row.rebuild()
	_expect(row.generated().size() == 4 and (row.generated()[3] as Node3D).position.is_equal_approx(Vector3(6, 1, 0)), "a row of 5: four copies, the last 6 m along")
	post.size = Vector3(0.4, 2, 0.4)
	row.refresh_if_changed()
	_expect((row.generated()[0] as MapBlock).size.is_equal_approx(Vector3(0.4, 2, 0.4)), "the copies follow a change to the first")
	var row_handles := PieceGizmo.handles_of(row)
	_expect(row_handles.size() == 1 and (row_handles[0][1] as Vector3).is_equal_approx(Vector3(6, 1, 0)), "a row has one handle, at its last copy")
	var spaced: Vector3 = PieceGizmo.value_for(row, row_handles[0], 8.1, 0.5)
	_expect(spaced.is_equal_approx(Vector3(2, 0, 0)), "slid to 8.1 m along, the 5 are 2 m apart")

	var ring := MapRing.new()
	ring.count = 4
	map.add_child(ring)
	var pillar := _block(ring, Vector3(0, 1, -5), Vector3(1, 2, 1))
	ring.rebuild()
	var across := ring.generated()[1] as Node3D
	_expect(ring.generated().size() == 3 and across.position.is_equal_approx(Vector3(0, 1, 5)), "a ring of 4: three copies, one straight across")
	ring.arc = 90.0
	ring.rebuild()
	var last := ring.generated()[2] as Node3D
	_expect(last.position.is_equal_approx(Basis(Vector3.UP, PI / 2.0) * pillar.position), "over a 90 degree arc the last one is a quarter turn round")
	var empty := MapRow.new()
	map.add_child(empty)
	empty.rebuild()
	_expect(empty.generated().is_empty() and empty._get_configuration_warnings().size() == 1, "a row with nothing to repeat makes nothing and says why")

	var pieces := map.collect_pieces()
	_expect(pieces.size() == 6 + 1 + 5 + 4, "the game sees a piece's blocks like any others (%d pieces)" % pieces.size())
	map.free()


func _check_prefab() -> void:
	print("  prefabs")
	var map := MapRoot.new()
	var palette := MapPalette.new()
	palette.colors = {"concrete": Color.GRAY, "plank": Color.BROWN}
	map.palette = palette
	root.add_child(map)
	var group := Node3D.new()
	group.name = "Crates"
	group.position = Vector3(20, 2, 10)
	map.add_child(group)
	var low := _block(group, Vector3(0, 0.5, 0), Vector3(2, 1, 2), "plank")
	var high := _block(group, Vector3(0, 1.5, 0), Vector3(1, 1, 1), "rust")
	var prefab := MapOps.make_prefab([group, low], "CrateStack")
	_expect(prefab.get_child_count() == 1 and MapOps.blocks_in(prefab).size() == 2, "a block picked along with its group is saved once")
	var foot := MapOps.bounds_of([prefab])
	_expect(is_zero_approx(foot.position.y) and is_zero_approx(foot.get_center().x) and is_zero_approx(foot.get_center().z), "the prefab stands on its own origin, centred")
	var scene := PackedScene.new()
	_expect(scene.pack(prefab) == OK, "it packs as a scene")
	prefab.free()
	var placed := MapOps.place_prefab(scene)
	placed.position = Vector3(-5, 0, 0)
	map.add_child(placed)
	MapPiece.adopt(placed, map)
	var blocks := MapOps.blocks_in(placed)
	_expect(blocks.size() == 2 and placed.scene_file_path == "" and blocks.all(func(b: MapBlock) -> bool: return b.owner == map and b.scene_file_path == ""),
		"placed, it is plain blocks owned by the map with no tie to the file")
	_expect(placed.get_meta("_edit_group_", false), "and one selection group")
	_expect(MapOps.missing_kinds(placed, palette) == PackedStringArray(["rust"]), "a kind the map's palette lacks is named")
	high.kind = "plank"
	_expect(MapOps.blocks_in(placed).any(func(b: MapBlock) -> bool: return b.kind == "rust"), "changing the original does not change the copy")
	map.build(false)
	_expect(map.get_node("Collision").get_child_count() == 4, "the map builds collision for the original and the copy")
	map.free()


# ---------------------------------------------------------------------------
# The tools and commands, with a stand-in for the editor

var _picked := []   # what is "selected"


func _context(map: MapRoot) -> RefCounted:
	var ctx := MapContext.new()
	_picked = []
	ctx.selection = func() -> Array: return _picked
	ctx.select = func(nodes: Array) -> void: _picked = nodes.duplicate()
	ctx.commit = func(edit: RefCounted) -> void:
		edit.apply(map)
		if edit.reselect:
			_picked = edit.select.duplicate()
		ctx.touch()
	ctx.map = map
	ctx.grid = 0.5
	return ctx


## The stand-in's functions hold the context and it holds them: let go, or it leaks.
func _release(ctx: RefCounted) -> void:
	ctx.selection = Callable()
	ctx.select = Callable()
	ctx.commit = Callable()
	_picked = []


func _press(view: RefCounted, at: Vector3, down: bool, button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	e.position = view.screen(at)
	return e


func _motion(view: RefCounted, at: Vector3, shift := false) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = view.screen(at)
	e.shift_pressed = shift
	return e


## A hull block of a box's shape, `size` big, its middle at `at`.
func _hull_box(parent: Node, at: Vector3, size: Vector3) -> MapBlock:
	var b := _block(parent, at, size)
	var h := MapOps.make_editable(b) as MapBlock
	parent.add_child(h)
	b.free()
	return h


func _has_point(points: Array, p: Vector3) -> bool:
	return points.any(func(q: Vector3) -> bool: return q.distance_to(p) < 0.001)


func _key_event(keycode: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	return e


## A press at `from`, a drag to `to` and a release there, through the tool.
func _drag_with(tool: RefCounted, view: RefCounted, from: Vector3, to: Vector3, shift := false) -> void:
	tool.input(view, _press(view, from, true))
	tool.input(view, _motion(view, from.lerp(to, 0.5), shift))
	tool.input(view, _motion(view, to, shift))
	tool.input(view, _press(view, to, false))


func _check_vertex_tool() -> void:
	print("  vertex tool")
	var map := MapRoot.new()
	root.add_child(map)
	var ctx := _context(map)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(4, 14, 16), Vector3(1, 0, 1))
	var view := MapView.new(cam)
	var tool := ToolVertex.new()
	tool.ctx = ctx

	# A 2 m cube standing on the ground: corners at x, z = -1 or 1, y = 0 or 2.
	var cube := _hull_box(map, Vector3(0, 1, 0), Vector3(2, 2, 2))
	_picked = [cube]
	tool.input(view, _press(view, Vector3(1, 2, 1), true))
	tool.input(view, _press(view, Vector3(1, 2, 1), false))
	_expect(tool.picked.size() == 1 and tool.picked[0][0] == cube, "Vertex: a click on a corner picks it")
	_expect(_picked == [cube], "and leaves the selection alone")

	# Drag it out level, to x = z = 2 (on the grid).
	_drag_with(tool, view, Vector3(1, 2, 1), Vector3(2.1, 2, 1.9))
	var now := _corners(cube)
	_expect(_has_point(now, Vector3(2, 2, 2)) and not _has_point(now, Vector3(1, 2, 1)), "dragged, the corner lands on the grid at (2, 2, 2)")
	_expect(_has_point(now, Vector3(-1, 0, -1)) and _has_point(now, Vector3(1, 0, 1)) and now.size() == 8, "and every other corner stays where it was")
	_expect(MapBlock.points_bounds(cube.points).get_center().is_zero_approx() and not cube.position.is_equal_approx(Vector3(0, 1, 0)),
		"the block moved to keep its corners centred (%s)" % cube.position)
	_expect(tool.picked.size() == 1 and (MapOps.global_of(cube) * cube.points[tool.picked[0][1]]).is_equal_approx(Vector3(2, 2, 2)),
		"the moved corner is still picked")

	# Up and down: Shift.
	_drag_with(tool, view, Vector3(2, 2, 2), Vector3(2, 3.1, 2), true)
	_expect(_has_point(_corners(cube), Vector3(2, 3, 2)), "with Shift it moves straight up, to y = 3")

	# The arrow keys: right is +x from this camera; Page Down is down.
	tool.input(view, _key_event(KEY_RIGHT))
	tool.input(view, _key_event(KEY_PAGEDOWN))
	_expect(_has_point(_corners(cube), Vector3(2.5, 2.5, 2)), "Right and Page Down nudge it a grid square each (to 2.5, 2.5, 2)")

	# Delete takes it away; the cube is left with 7 corners.
	_expect(tool.input(view, _key_event(KEY_DELETE)) and cube.points.size() == 7 and tool.picked.is_empty(), "Delete takes the picked corner away")
	_expect(not _has_point(_corners(cube), Vector3(2.5, 2.5, 2)) and _has_point(_corners(cube), Vector3(-1, 0, -1)), "and the rest stay put")
	_expect(not tool.input(view, _key_event(KEY_DELETE)), "with nothing picked, Delete is left to the editor")
	cube.free()

	# A dent is refused: a house (a box with a roof point), the roof point pushed down
	# into the box.
	var house := MapBlock.new()
	house.shape = MapBlock.Shape.HULL
	house.points = PackedVector3Array([Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1),
		Vector3(-1, 2, -1), Vector3(1, 2, -1), Vector3(-1, 2, 1), Vector3(1, 2, 1), Vector3(0, 3, 0)])
	map.add_child(house)
	house.position = Vector3(0, 1.5, 0)   # its corners are centred on it: the house stands on the ground
	var roof := Vector3(0, 3, 0)
	_expect(_has_point(_corners(house), roof), "(a house stands on the ground, its roof at (0, 3, 0))")
	_picked = [house]
	var before := house.points.duplicate()
	tool.input(view, _press(view, roof, true))
	tool.input(view, _motion(view, roof + Vector3(0, -0.6, 0), true))
	tool.input(view, _motion(view, roof + Vector3(0, -2, 0), true))
	_expect(tool._refused and _has_point(_corners(house), roof + Vector3(0, -0.5, 0)), "a move that would sink a corner inside is refused; the shape stays at the last one allowed")
	tool.input(view, _press(view, roof + Vector3(0, -2, 0), false))
	_expect(house.points.size() == 9 and _has_point(_corners(house), roof + Vector3(0, -0.5, 0)), "letting go keeps the last allowed move")
	var esc := _key_event(KEY_ESCAPE)
	tool.input(view, _press(view, roof + Vector3(0, -0.5, 0), true))
	tool.input(view, _motion(view, roof + Vector3(0, 0.6, 0), true))
	tool.input(view, _motion(view, roof + Vector3(0, 1.1, 0), true))
	tool.input(view, esc)
	_expect(_has_point(_corners(house), roof + Vector3(0, -0.5, 0)) and not tool.busy(), "Esc puts a drag back")
	house.points = before
	house.free()

	# A box drawn round every corner in a top view picks them all.
	var top_cam := Camera3D.new()
	root.add_child(top_cam)
	top_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	top_cam.size = 40.0
	top_cam.position = Vector3(0, 50, 0)
	top_cam.rotation_degrees = Vector3(-90, 0, 0)
	var top := MapView.new(top_cam)
	var left := _hull_box(map, Vector3(1, 1, 0), Vector3(2, 2, 2))    # x 0..2
	var right := _hull_box(map, Vector3(3, 1, 0), Vector3(2, 2, 2))   # x 2..4: they share a face
	_picked = [left, right]
	_drag_with(tool, top, Vector3(-0.5, 0, -1.5), Vector3(2.5, 0, 1.5))
	_expect(tool.picked.size() == 8 + 4, "dragging a box in a top view picks every corner inside it (all of one cube, the shared face of the other)")

	# Corners two blocks share move together. (A click on a corner already picked keeps
	# the others, to drag them all: start afresh.)
	tool.picked = []
	tool.input(view, _press(view, Vector3(2, 2, 1), true))
	tool.input(view, _press(view, Vector3(2, 2, 1), false))
	_expect(tool.picked.size() == 2, "a click on a corner two blocks share picks it in both")
	_drag_with(tool, view, Vector3(2, 2, 1), Vector3(2, 2, 2.1))
	_expect(_has_point(_corners(left), Vector3(2, 2, 2)) and _has_point(_corners(right), Vector3(2, 2, 2)), "and dragging it moves it in both")

	# A double-click on an edge adds a corner in its middle.
	var mid := Vector3(1, 2, -1)   # the middle of the left cube's top back edge
	var dbl := _press(view, mid, true)
	dbl.double_click = true
	tool.input(view, dbl)
	tool.input(view, _press(view, mid, false))
	var left_points := []   # (all its points: one in the middle of an edge is not yet a corner)
	for pt in left.points:
		left_points.append(MapOps.global_of(left) * pt)
	_expect(left.points.size() == 9 and _has_point(left_points, mid) and tool.picked.size() == 1, "a double-click on an edge adds a corner in its middle, picked")
	_drag_with(tool, view, mid, Vector3(1, 2, -2.1))
	_expect(_has_point(_corners(left), Vector3(1, 2, -2)), "which can then be pulled out")
	var face_mid := Vector3(3.5, 2, -0.5)   # on the right cube's top, well away from its edges
	var on_face := _press(view, face_mid, true)
	on_face.double_click = true
	var count := right.points.size()
	tool.input(view, on_face)
	tool.input(view, _press(view, face_mid, false))
	_expect(right.points.size() == count + 1 and tool.picked.size() == 1 and \
		is_equal_approx((MapOps.global_of(right) * right.points[tool.picked[0][1]]).y, 2.0),
		"a double-click on a face adds a corner in the face's middle")

	# Delete never leaves a flat shape: a four-cornered hull keeps its corners.
	var tetra := MapBlock.new()
	tetra.shape = MapBlock.Shape.HULL
	tetra.points = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(0, 0, 2), Vector3(0, 2, 0)])
	tetra.position = Vector3(-8, 0, -8)
	map.add_child(tetra)
	_picked = [tetra]
	tool.picked = [[tetra, 3]]
	tool.input(view, _key_event(KEY_DELETE))
	_expect(tetra.points.size() == 4, "Delete is refused when what is left would be flat")

	# Edges and faces: a cube standing at z = 5..7.
	var edgy := _hull_box(map, Vector3(0, 1, 6), Vector3(2, 2, 2))
	_picked = [edgy]
	tool.picked = []
	var edge_mid := Vector3(0, 2, 7)   # the middle of its top front edge
	tool.input(view, _press(view, edge_mid, true))
	tool.input(view, _press(view, edge_mid, false))
	_expect(tool.picked.size() == 2, "a click on an edge picks its two corners")
	_drag_with(tool, view, edge_mid, Vector3(0.2, 2, 8.1))
	_expect(_has_point(_corners(edgy), Vector3(-1, 2, 8)) and _has_point(_corners(edgy), Vector3(1, 2, 8)) and _has_point(_corners(edgy), Vector3(-1, 0, 7)),
		"dragged, the edge moves by whole grid squares (1 m out), the corners under it stay")
	tool.picked = []
	var on_top := Vector3(0, 2, 6.4)
	tool.input(view, _press(view, on_top, true))
	tool.input(view, _press(view, on_top, false))
	_expect(tool.picked.size() == 4, "a click on a face picks its corners")
	_drag_with(tool, view, on_top, Vector3(0, 3.1, 6.4))
	var pushed := _corners(edgy)
	# (The front slopes out 1 m over its 2 m of height: carried on up to y = 3 it reaches z = 8.5.)
	_expect(_has_point(pushed, Vector3(-1, 3, 5)) and _has_point(pushed, Vector3(1, 3, 8.5)) and _has_point(pushed, Vector3(-1, 0, 5)) and _has_point(pushed, Vector3(1, 0, 7)),
		"dragged, the top is pushed straight up 1 m; the sloping front carries on up to meet it, the foot stays")
	_expect(tool.picked.size() == 4, "and the face is still picked")

	# A click away from every corner selects the block under it.
	var other := _block(map, Vector3(-6, 0.5, 4), Vector3(2, 1, 2))
	tool.input(view, _press(view, Vector3(-6, 1, 4), true))
	tool.input(view, _press(view, Vector3(-6, 1, 4), false))
	_expect(_picked == [other] and tool.picked.is_empty(), "a click away from the corners selects the block under it")
	_release(ctx)
	map.free()
	cam.free()
	top_cam.free()


## The parts the last commit selected that are blocks.
func _picked_blocks() -> Array:
	return _picked.filter(func(n: Node) -> bool: return n is MapBlock)


func _check_angled_clip() -> void:
	print("  clip at an angle")
	var map := MapRoot.new()
	root.add_child(map)

	# MapOps.clip_plane: a 4 x 2 x 4 m box standing on the ground.
	var box := _block(map, Vector3(0, 1, 0), Vector3(4, 2, 4))
	var straight := MapOps.clip_plane(box, Plane(Vector3.RIGHT, 1.0))
	_expect(straight.size() == 2 and straight.all(func(p: MapBlock) -> bool: return p.shape == MapBlock.Shape.BOX)
		and is_equal_approx(straight[0].size.x, 3.0) and is_equal_approx(straight[1].size.x, 1.0),
		"a box cut square to its sides is two boxes, the one behind the cut first (3 m and 1 m)")
	for p in straight:
		p.free()
	var diag := MapOps.clip_plane(box, Plane(Vector3(1, 0, -1).normalized(), 0.0))   # upright, through the diagonal x = z
	_expect(diag.size() == 2 and diag.all(func(p: MapBlock) -> bool: return p.shape == MapBlock.Shape.HULL and p.points.size() == 6),
		"cut along its diagonal, it is two three-sided hulls")
	if diag.size() == 2:
		_expect(_has_point(_corners(diag[0]), Vector3(-2, 0, 2)) and _has_point(_corners(diag[1]), Vector3(2, 2, -2))
			and _has_point(_corners(diag[0]), Vector3(2, 0, 2)) and _has_point(_corners(diag[1]), Vector3(2, 0, 2)),
			"each on its side of the cut, meeting along it")
		for p in diag:
			p.free()
	_expect(MapOps.clip_plane(box, Plane(Vector3.UP, 5.0)).is_empty(), "a cut that misses the block does nothing")
	box.shape = MapBlock.Shape.WEDGE
	var wedge_parts := MapOps.clip_plane(box, Plane(Vector3(1, 0, 1).normalized(), 0.0))
	_expect(wedge_parts.size() == 2 and wedge_parts.all(func(p: MapBlock) -> bool: return p.shape == MapBlock.Shape.HULL), "a wedge cut at an angle is two hulls")
	for p in wedge_parts:
		p.free()
	box.shape = MapBlock.Shape.TUBE
	box.inner = 2.0
	_expect(MapOps.clip_plane(box, Plane(Vector3(1, 0, 1).normalized(), 0.0)).is_empty(), "a tube is not cut at an angle")
	box.free()

	var ctx := _context(map)
	var clip := ToolClip.new()
	clip.ctx = ctx
	var top_cam := Camera3D.new()
	root.add_child(top_cam)
	top_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	top_cam.size = 60.0
	top_cam.position = Vector3(0, 50, 0)
	top_cam.rotation_degrees = Vector3(-90, 0, 0)
	var top := MapView.new(top_cam)
	var enter := _key_event(KEY_ENTER)

	# A top view: drag a diagonal across a slab, then Enter.
	var slab := _block(map, Vector3(10, 0.5, 10), Vector3(4, 1, 4), "wood")   # x and z 8..12
	_picked = [slab]
	_drag_with(clip, top, Vector3(7.9, 0, 7.9), Vector3(12.1, 0, 12.1))
	_expect(clip.phase == ToolClip.Phase.PENDING and clip._pending.size() == 1, "Clip: a line dragged in a top view waits to cut the selection")
	_expect(clip.input(top, enter) and not slab.is_inside_tree() and _picked_blocks().size() == 2, "Enter cuts it in two, both selected")
	var halves := _picked_blocks()
	_expect(halves.size() == 2 and halves.all(func(p: MapBlock) -> bool: return p.shape == MapBlock.Shape.HULL and p.kind == "wood" and p.owner == map),
		"two hull blocks of the slab's kind, saved with the map")
	if halves.size() == 2:
		_expect((_has_point(_corners(halves[0]), Vector3(8, 0, 12)) and _has_point(_corners(halves[1]), Vector3(12, 1, 8)))
			or (_has_point(_corners(halves[1]), Vector3(8, 0, 12)) and _has_point(_corners(halves[0]), Vector3(12, 1, 8))),
			"cut along the diagonal from (8, 8) to (12, 12)")

	# Keep only one side.
	var slab2 := _block(map, Vector3(20, 0.5, 10), Vector3(4, 1, 4))
	_picked = [slab2]
	_drag_with(clip, top, Vector3(17.9, 0, 7.9), Vector3(22.1, 0, 12.1))
	clip.next_direction()
	_expect(clip.keep == ToolClip.Keep.FRONT, "the next-direction key keeps only the part in front")
	clip.input(top, enter)
	_expect(_picked_blocks().size() == 1 and not slab2.is_inside_tree(), "and Enter leaves just that part")

	# Giving up.
	var slab3 := _block(map, Vector3(-10, 0.5, 10), Vector3(4, 1, 4))
	_picked = [slab3]
	_drag_with(clip, top, Vector3(-12.1, 0, 7.9), Vector3(-7.9, 0, 12.1))
	clip.input(top, _press(top, Vector3(-10, 0, 10), true, MOUSE_BUTTON_RIGHT))
	_expect(not clip.busy() and slab3.is_inside_tree() and clip._pending.is_empty(), "a right click gives up the cut")

	# The 3D view: a diagonal across a block's front face cuts it into two slopes.
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(4, 14, 16), Vector3(1, 0, 1))
	var view := MapView.new(cam)
	var beam := _block(map, Vector3(0, 1, -6), Vector3(4, 2, 2))   # x -2..2, y 0..2, z -7..-5
	_picked = [beam]
	_drag_with(clip, view, Vector3(-1.9, 0.1, -5), Vector3(1.9, 1.9, -5))
	_expect(clip.phase == ToolClip.Phase.PENDING and clip._pending.size() == 1, "in 3D, a line dragged across a face waits to cut")
	clip.input(view, enter)
	var slopes := _picked_blocks()
	_expect(slopes.size() == 2 and slopes.all(func(p: MapBlock) -> bool: return p.shape == MapBlock.Shape.HULL and p.points.size() == 6),
		"cut square to the face along its diagonal: two slopes (three-sided hulls)")

	# And with a third point: on the top's back edge.
	var beam2 := _block(map, Vector3(0, 1, -12), Vector3(4, 2, 2))   # z -13..-11
	_picked = [beam2]
	_drag_with(clip, view, Vector3(-1.9, 0.1, -11), Vector3(1.9, 1.9, -11))
	clip.input(view, _press(view, Vector3(0, 2, -12.9), true))
	clip.input(view, _press(view, Vector3(0, 2, -12.9), false))
	_expect(clip._has_c and clip._pending.size() == 1, "a click sets a third point")
	clip.input(view, enter)
	var tilted := _picked_blocks()
	_expect(tilted.size() == 2 and tilted.all(func(p: MapBlock) -> bool: return _has_point(_corners(p), Vector3(0, 2, -13))),
		"the cut runs through all three points (both parts have a corner at the third)")
	for gone in [slab, slab2, beam, beam2]:   # (cut, so out of the scene; the editor's undo would keep them)
		gone.free()
	_release(ctx)
	map.free()
	cam.free()
	top_cam.free()


## Is `p` (in the map) inside any block of `blocks` (by their real shapes)?
func _inside_any(blocks: Array, p: Vector3) -> bool:
	for b: MapBlock in blocks:
		var planes := MapOps.world_planes(b)
		if not planes.is_empty() and MapMesher.hull_has(planes, p, -0.001):
			return true
	return false


func _check_csg() -> void:
	print("  csg")
	var map := MapRoot.new()
	root.add_child(map)
	var ctx := _context(map)

	# Subtract: a doorway through a wall.
	var wall := _block(map, Vector3(0, 1.5, 0), Vector3(6, 3, 0.5), "brick")   # x -3..3, y 0..3
	var door := _block(map, Vector3(0, 1, 0), Vector3(1, 2, 2))                 # x -0.5..0.5, y 0..2, through it
	_picked = [door]
	ctx.commit.call(MapCommands.subtract(ctx))
	var groups := _picked.filter(func(n: Node) -> bool: return n is Node3D and not (n is MapBlock))
	var parts: Array = MapOps.blocks_in(groups[0]) if groups.size() == 1 else []
	_expect(groups.size() == 1 and not wall.is_inside_tree() and not door.is_inside_tree(), "Subtract: the wall becomes a group of what is left, and the cutter goes")
	_expect(parts.size() == 3 and parts.all(func(p: MapBlock) -> bool: return p.shape == MapBlock.Shape.BOX and p.kind == "brick"),
		"three boxes of brick (either side of the door, and over it)")
	_expect(is_equal_approx(_volume(parts), 6.0 * 3.0 * 0.5 - 1.0 * 2.0 * 0.5), "together the wall less the doorway (%s m³)" % _volume(parts))
	_expect(not _inside_any(parts, Vector3(0, 1, 0)) and _inside_any(parts, Vector3(0, 2.5, 0)) and _inside_any(parts, Vector3(-2, 1, 0)),
		"the doorway is open, the wall over it and beside it is not")
	var lone := _block(map, Vector3(30, 1, 30), Vector3(1, 1, 1))
	_picked = [lone]
	_expect(MapCommands.subtract(ctx).is_empty(), "a cutter that overlaps nothing does nothing")
	wall.free()
	door.free()

	# Merge and intersect.
	var a := _block(map, Vector3(11, 1, 0), Vector3(2, 2, 2))   # x 10..12
	var b := _block(map, Vector3(13, 1, 0), Vector3(2, 2, 2))   # x 12..14
	_picked = [a, b]
	ctx.commit.call(MapCommands.merge(ctx))
	var one := _picked[0] as MapBlock if _picked.size() == 1 else null
	_expect(one != null and one.shape == MapBlock.Shape.BOX and one.size.is_equal_approx(Vector3(4, 2, 2)) and MapOps.global_of(one).origin.is_equal_approx(Vector3(12, 1, 0))
		and not a.is_inside_tree() and not b.is_inside_tree(), "Merge: two boxes side by side become one box round both")
	var low := _block(map, Vector3(11, 0.5, 6), Vector3(2, 1, 2))
	var high := _block(map, Vector3(11, 2, 6), Vector3(0.5, 2, 0.5))   # a post on it, narrower
	_picked = [low, high]
	ctx.commit.call(MapCommands.merge(ctx))
	var tent := _picked[0] as MapBlock if _picked.size() == 1 else null
	_expect(tent != null and tent.shape == MapBlock.Shape.HULL and tent.points.size() == 12 and _has_point(_corners(tent), Vector3(11.25, 3, 6.25))
		and _has_point(_corners(tent), Vector3(10, 1, 5)),
		"a box and a narrower post on it become one hull round both (convex merge: tapering from the box's corners to the post's top)")
	var big := _block(map, Vector3(11, 2, 12), Vector3(4, 4, 4))           # x 9..13
	var beam := _block(map, Vector3(14, 3, 12), Vector3(2, 0.5, 0.5))   # sticking out of its side, to x = 15
	_picked = [big, beam]
	ctx.commit.call(MapCommands.merge(ctx))
	var wrapped := _picked[0] as MapBlock if _picked.size() == 1 else null
	_expect(wrapped != null and wrapped.shape == MapBlock.Shape.HULL and _has_point(_corners(wrapped), Vector3(15, 3.25, 12.25))
		and _has_point(_corners(wrapped), Vector3(9, 0, 10)),
		"a block and a beam sticking out of it become one hull round both, the gap between filled in")
	var base := _block(map, Vector3(11, 1, 18), Vector3(2, 2, 2))   # y 0..2
	var roof := _block(map, Vector3(11, 2.5, 18), Vector3(2, 1, 2))   # a slope on its top, as wide and deep
	roof.shape = MapBlock.Shape.WEDGE
	_picked = [base, roof]
	ctx.commit.call(MapCommands.merge(ctx))
	var house := _picked[0] as MapBlock if _picked.size() == 1 else null
	# (8 corners: the box's foot, the front of its top, the top of the slope at the back;
	# the box's top back corners are now part way up the back.)
	_expect(house != null and house.shape == MapBlock.Shape.HULL and house.points.size() == 8 and _has_point(_corners(house), Vector3(12, 3, 17))
		and _has_point(_corners(house), Vector3(10, 0, 19)) and not base.is_inside_tree(),
		"a box with a slope that fits its top merge into one hull, a box with a sloping roof (%s)" % ("refused" if house == null else "%d corners" % house.points.size()))
	var p := _block(map, Vector3(22, 1, 0), Vector3(4, 2, 2))   # x 20..24
	var q := _block(map, Vector3(24, 1, 0), Vector3(4, 2, 2))   # x 22..26
	_picked = [p, q]
	ctx.commit.call(MapCommands.intersect(ctx))
	var shared := _picked[0] as MapBlock if _picked.size() == 1 else null
	_expect(shared != null and shared.shape == MapBlock.Shape.BOX and shared.size.is_equal_approx(Vector3(2, 2, 2)) and MapOps.global_of(shared).origin.is_equal_approx(Vector3(23, 1, 0)),
		"Intersect: two overlapping boxes become the box they share")
	var far := _block(map, Vector3(40, 1, 0), Vector3(1, 1, 1))
	_picked = [shared, far]
	_expect(MapCommands.intersect(ctx).is_empty(), "blocks that share nothing are left alone")
	var holder := _block(map, Vector3(40, 1, 5), Vector3(1, 1, 1))
	var lamp := MapBlock.new()
	holder.add_child(lamp)
	_picked = [far, holder]
	_expect(MapCommands.merge(ctx).is_empty(), "a merge that would lose what stands under the second block is refused")
	for gone in [a, b, low, high, big, beam, p, q, base, roof]:
		gone.free()

	# Hollow any shape: a wedge, walls 0.25 m thick.
	var ramp := _block(map, Vector3(0, 2, 20), Vector3(6, 4, 6))
	ramp.shape = MapBlock.Shape.WEDGE
	var shell := MapOps.hollowed(ramp, 0.25)
	_expect(shell != null and shell.get_child_count() >= 4, "Hollow: a wedge becomes walls (%d)" % (shell.get_child_count() if shell else 0))
	if shell:
		map.add_child(shell)
		var walls := MapOps.blocks_in(shell)
		_expect(not _inside_any(walls, Vector3(0, 1, 19)) and _inside_any(walls, Vector3(0, 0.1, 19)) and _inside_any(walls, Vector3(2.9, 1, 19)),
			"hollow inside, with a floor and sides")
		var box := MapOps.bounds_of(walls)
		_expect(box.is_equal_approx(MapOps.bounds_of([ramp])), "filling the same outside")
	var cube := _block(map, Vector3(0, 2, 30), Vector3(4, 4, 4))
	cube.shape = MapBlock.Shape.HULL
	cube.points = MapOps.editable_lumps(_block(map, Vector3.ZERO, Vector3(4, 4, 4)))[0]
	var open := MapOps.hollowed(cube, 0.5, true)
	if open:
		map.add_child(open)
	var open_walls := MapOps.blocks_in(open) if open else []
	_expect(open != null and not _inside_any(open_walls, Vector3(0, 3.9, 30)) and _inside_any(open_walls, Vector3(0, 0.1, 30)),
		"with the top left open: no wall over it, but a floor")
	_release(ctx)
	map.free()


func _check_tools() -> void:
	print("  tools")
	var map := MapRoot.new()
	root.add_child(map)
	var ctx := _context(map)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(4, 14, 16), Vector3(3, 0, 3))
	var view := MapView.new(cam)
	_expect(view.ortho_axis() == -1, "a perspective view is not a top, front or side view")

	# Draw on the ground: a 3 m by 2 m footprint, pulled up 3 m.
	var draw := ToolDraw.new()
	draw.ctx = ctx
	_expect(draw.input(view, _press(view, Vector3(2.1, 0, 1.9), true)) and draw.busy(), "Draw: a press on the ground starts a block")
	draw.input(view, _motion(view, Vector3(5.1, 0, 4.1)))
	draw.input(view, _press(view, Vector3(5.1, 0, 4.1), false))
	_expect(draw.phase == ToolDraw.Phase.HEIGHT and map.get_child_count() == 0, "letting go leaves it waiting for a height")
	draw.input(view, _motion(view, Vector3(3.5, 3.1, 3)))
	draw.input(view, _press(view, Vector3(3.5, 3.1, 3), true))
	var first := map.get_child(0) as MapBlock if map.get_child_count() == 1 else null
	_expect(first != null and first.size.is_equal_approx(Vector3(3, 3, 2)) and first.position.is_equal_approx(Vector3(3.5, 1.5, 3)),
		"a click sets it: 3 x 3 x 2 m, snapped to the grid, standing on the ground%s" % ("" if first == null else " (%s at %s)" % [first.size, first.position]))
	_expect(first != null and _picked == [first] and first.owner == map and first.kind == ctx.kind, "the new block is selected, saved with the map, of the chosen kind")

	# Draw on top of that block.
	draw.input(view, _press(view, Vector3(3.1, 3, 2.6), true))
	draw.input(view, _motion(view, Vector3(3.9, 3, 3.4)))
	draw.input(view, _press(view, Vector3(3.9, 3, 3.4), false))
	draw.input(view, _motion(view, Vector3(3.5, 4.1, 3)))
	draw.input(view, _press(view, Vector3(3.5, 4.1, 3), true))
	var second := map.get_child(1) as MapBlock if map.get_child_count() == 2 else null
	_expect(second != null and second.size.is_equal_approx(Vector3(1, 1, 1)) and second.position.is_equal_approx(Vector3(3.5, 3.5, 3)),
		"drawn on a block's top, the next one stands on it%s" % ("" if second == null else " (%s at %s)" % [second.size, second.position]))

	# A press and release in one place draws nothing; Esc gives up.
	draw.input(view, _press(view, Vector3(-3, 0, 0), true))
	draw.input(view, _press(view, Vector3(-3, 0, 0), false))
	draw.input(view, _press(view, Vector3(-3, 0, 0), true))
	draw.input(view, _motion(view, Vector3(-1, 0, 2)))
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	_expect(draw.input(view, esc) and not draw.busy() and map.get_child_count() == 2, "a plain click draws nothing, and Esc gives up a drag")

	# A top view: a rectangle, as deep as the selection (the block just drawn: y 3 to 4).
	var top_cam := Camera3D.new()
	root.add_child(top_cam)
	top_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	top_cam.size = 40.0
	top_cam.position = Vector3(0, 50, 0)
	top_cam.rotation_degrees = Vector3(-90, 0, 0)
	var top := MapView.new(top_cam)
	_expect(top.ortho_axis() == 1, "a view straight down is a top view")
	draw.input(top, _press(top, Vector3(-4, 0, -4), true))
	draw.input(top, _motion(top, Vector3(-2, 0, -1)))
	draw.input(top, _press(top, Vector3(-2, 0, -1), false))
	var third := map.get_child(2) as MapBlock if map.get_child_count() == 3 else null
	_expect(third != null and third.size.is_equal_approx(Vector3(2, 1, 3)) and third.position.is_equal_approx(Vector3(-3, 3.5, -2.5)),
		"in a top view a dragged rectangle is a block at the selection's height%s" % ("" if third == null else " (%s at %s)" % [third.size, third.position]))

	# Clip the first block across its length, 0.5 m past its middle.
	var clip := ToolClip.new()
	clip.ctx = ctx
	_picked = [first]
	clip.input(view, _motion(view, Vector3(4.1, 3, 3.8)))
	_expect(clip._cuts.size() == 1, "Clip: pointing at a selected block shows a cut")
	clip.input(view, _press(view, Vector3(4.1, 3, 3.8), true))
	_expect(clip.input(view, _press(view, Vector3(4.1, 3, 3.8), false)), "a click cuts it")
	var halves := _picked.filter(func(n: Node) -> bool: return n is MapBlock)
	_expect(halves.size() == 2 and not first.is_inside_tree(), "the block is replaced by two, both selected")
	if halves.size() == 2:
		var a := halves[0] as MapBlock
		var b := halves[1] as MapBlock
		_expect(is_equal_approx(a.size.x, 2.0) and is_equal_approx(b.size.x, 1.0) and is_equal_approx(a.position.x + 1.0, 4.0),
			"cut on the grid at x = 4: 2 m and 1 m (%s, %s)" % [a.size.x, b.size.x])
		_expect(a.get_index() == 0 and b.get_index() == 1, "the halves take the block's place in the scene")
	_picked = []
	_expect(not clip.input(view, _press(view, Vector3(4.1, 3, 3.8), true)), "with nothing selected a click is left to the editor")
	first.free()

	# Place: stairs on the ground.
	var place := ToolPlace.new()
	place.ctx = ctx
	_picked = []
	place.start(func() -> Node3D: return MapCommands.new_piece("Stairs", "concrete"), "stairs")
	place.input(view, _motion(view, Vector3(-6.2, 0, 5.9)))
	place.input(view, _press(view, Vector3(-6.2, 0, 5.9), true))
	var stairs := _picked[0] as MapStairs if _picked.size() == 1 else null
	_expect(stairs != null and stairs.position.is_equal_approx(Vector3(-6, 0, 6)) and stairs.generated().size() == 13,
		"Place: a click puts stairs down on the grid with their steps made")
	_expect(stairs != null and stairs.generated().all(func(n: Node) -> bool: return n.owner == map), "and their blocks are saved with the map")
	cam.free()
	top_cam.free()
	_release(ctx)
	map.free()


func _check_commands() -> void:
	print("  commands")
	var map := MapRoot.new()
	root.add_child(map)
	var ctx := _context(map)
	var box := _block(map, Vector3(0, 2, 0), Vector3(6, 4, 6), "drywall")
	var pipe := _block(map, Vector3(9, 2, 0), Vector3(2, 4, 2), "steel")
	pipe.shape = MapBlock.Shape.TUBE   # a tube is several lumps: it cannot be hollowed
	pipe.inner = 1.0
	_picked = [box, pipe]
	_expect(MapCommands.hollowable(ctx, 0.25) == 1, "Hollow: of a box and a tube, one can be hollowed")
	ctx.commit.call(MapCommands.hollow(ctx, 0.25, false, false))
	var room := _picked[0] as Node3D if _picked.size() == 1 else null
	_expect(room != null and not (room is MapBlock) and room.get_child_count() == 6 and pipe.is_inside_tree() and not box.is_inside_tree(),
		"the box is replaced by a room, the tube left alone")
	box.free()

	_picked = [pipe]
	ctx.commit.call(MapCommands.mirror(ctx, 0, Vector3.ZERO, true))
	_expect(_picked.size() == 1 and (_picked[0] as Node3D).position.is_equal_approx(Vector3(-9, 2, 0)) and pipe.position.x == 9.0, "Mirror with Copy: a copy across the map, the original left")
	_picked = [pipe]
	ctx.commit.call(MapCommands.mirror(ctx, 0, Vector3.ZERO, false))
	_expect(pipe.position.is_equal_approx(Vector3(-9, 2, 0)), "Mirror without: the original moves")
	ctx.commit.call(MapCommands.mirror(ctx, 0, Vector3.ZERO, false))

	_picked = [pipe]
	var before := map.get_child_count()
	ctx.commit.call(MapCommands.array_line(ctx, 2, Vector3(0, 0, 3)))
	_expect(map.get_child_count() == before + 2 and _picked.size() == 3, "Array: two copies in a line, all three selected")
	_picked = [pipe]
	ctx.commit.call(MapCommands.array_ring(ctx, 4, Vector3.ZERO))
	_expect(map.get_child_count() == before + 5, "Array round a circle of 4: three more")

	_picked = [room, pipe]
	ctx.commit.call(MapCommands.toggle(ctx, "solid"))
	_expect(not pipe.solid and MapOps.blocks_in(room).all(func(b: MapBlock) -> bool: return not b.solid), "Solid: all on, so all go off (blocks inside a group too)")
	pipe.solid = true
	ctx.commit.call(MapCommands.toggle(ctx, "solid"))
	_expect(pipe.solid and MapOps.blocks_in(room).all(func(b: MapBlock) -> bool: return b.solid), "some on, some off: all go on")
	ctx.commit.call(MapCommands.toggle(ctx, "breakable"))
	_expect(pipe.breakable == true and MapOps.blocks_in(room).all(func(b: MapBlock) -> bool: return b.breakable == true), "Breakable: all off, so all go on")
	ctx.commit.call(MapCommands.paint(ctx, "glass"))
	_expect(pipe.kind == "glass" and MapOps.blocks_in(room).all(func(b: MapBlock) -> bool: return b.kind == "glass"), "Paint gives every selected block the kind")
	_expect(MapCommands.paint(ctx, "glass").is_empty(), "painting them the kind they are changes nothing")

	var loose := _block(map, Vector3(3.4, 0.5, 20), Vector3(1, 1, 1))
	var post := _block(map, Vector3(4.63, 1, 20), Vector3(1, 2, 1))      # its near face is at x = 4.13
	ctx.touch()
	_picked = [loose]
	ctx.commit.call(MapCommands.snap_to_neighbours(ctx))
	_expect(is_equal_approx(loose.position.x, 3.63), "Snap to neighbours closes a 0.23 m gap (x = %.2f)" % loose.position.x)
	post.free()

	var stairs := MapCommands.new_piece("Stairs", "concrete") as MapStairs
	map.add_child(stairs)
	MapPiece.adopt(stairs, map)
	var bake := MapCommands.bake(stairs)
	bake.apply(map)
	_expect(stairs.get_script() == null and stairs.get_child_count() == 13 and not stairs.get_child(0).has_meta(MapPiece.GENERATED),
		"Bake: the stairs are a plain group of 13 blocks")
	for c in bake.undo_calls:
		(c[0] as Object).callv(c[1], c.slice(2))
	_expect(stairs is MapStairs and is_equal_approx(stairs.rise, 3.0) and stairs.generated().size() == 13, "undone, they are stairs again with their numbers")
	for sort in MapCommands.PIECES:
		var piece := MapCommands.new_piece(sort, "concrete")
		_expect(piece != null and piece.generated().size() > 0, "a new %s comes with its blocks" % sort)
		piece.free()
	_release(ctx)
	map.free()
