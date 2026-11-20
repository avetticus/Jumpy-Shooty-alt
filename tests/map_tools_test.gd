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
	_expect(clip.input(view, _press(view, Vector3(4.1, 3, 3.8), true)), "a click cuts it")
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
	pipe.shape = MapBlock.Shape.CYLINDER
	_picked = [box, pipe]
	_expect(MapCommands.hollowable(ctx, 0.25) == 1, "Hollow: of a box and a cylinder, one can be hollowed")
	ctx.commit.call(MapCommands.hollow(ctx, 0.25, false, false))
	var room := _picked[0] as Node3D if _picked.size() == 1 else null
	_expect(room != null and not (room is MapBlock) and room.get_child_count() == 6 and pipe.is_inside_tree() and not box.is_inside_tree(),
		"the box is replaced by a room, the cylinder left alone")
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
