@tool
extends RefCounted
## What the map tools do to blocks, as plain functions with no editor in them, so
## tests/map_tools_test.gd can check them: the grid, hollow, clip, mirror, array, face
## snapping and prefabs. Functions that make nodes return them not yet in the scene;
## the plugin adds them (and takes the old ones out) as one undo step.

## The grid sizes [ and ] step through (metres).
const GRID_STEPS: Array[float] = [0.1, 0.25, 0.5, 1.0, 2.0, 4.0]

## Turns a node's own x about: what a mirror does to it, without scaling by -1.
const FLIP_X := Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3.ZERO)

const SLIVER := 0.005   # nothing thinner than this is made (metres)


# ---------------------------------------------------------------------------
# Grid

static func snap(v: float, step: float) -> float:
	return roundf(v / step) * step


static func snap_v(v: Vector3, step: float) -> Vector3:
	return Vector3(snap(v.x, step), snap(v.y, step), snap(v.z, step))


## The grid size one notch up (dir 1) or down (dir -1) from `current`.
static func grid_step(current: float, dir: int) -> float:
	var at := 0
	for i in GRID_STEPS.size():
		if absf(GRID_STEPS[i] - current) < absf(GRID_STEPS[at] - current):
			at = i
	return GRID_STEPS[clampi(at + dir, 0, GRID_STEPS.size() - 1)]


## The box with opposite corners `a` and `b`, at least `least` along every axis:
## [centre, size].
static func box_between(a: Vector3, b: Vector3, least: float) -> Array:
	var lo := a.min(b)
	var hi := a.max(b)
	for axis in 3:
		if hi[axis] - lo[axis] < least:
			hi[axis] = lo[axis] + least
	return [(lo + hi) * 0.5, hi - lo]


# ---------------------------------------------------------------------------
# Where things are

## Where a node is in the map. Unlike global_transform this works before the node is
## in the scene tree.
static func global_of(node: Node3D) -> Transform3D:
	return parent_global(node) * node.transform


## Where a node's parent is in the map.
static func parent_global(node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p := node.get_parent()
	while p:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## Half a block's width, height and depth in its own frame (a round block is as deep
## as it is wide).
static func half_of(block: MapBlock) -> Vector3:
	if block.is_round():
		return Vector3(block.size.x, block.size.y, block.size.x) * 0.5
	return block.size * 0.5


## A block as the box round it: [where its middle is and which way it is turned
## (never scaled), half its size in metres].
static func box_of(block: MapBlock) -> Array:
	var xf := global_of(block)
	var scale := xf.basis.get_scale().abs()
	return [Transform3D(xf.basis.orthonormalized(), xf.origin), half_of(block) * scale]


## Every MapBlock that is `node` or under it.
static func blocks_in(node: Node) -> Array[MapBlock]:
	var out: Array[MapBlock] = []
	_blocks_in(node, out)
	return out


static func _blocks_in(node: Node, out: Array[MapBlock]) -> void:
	if node is MapBlock:
		out.append(node)
	for c in node.get_children():
		_blocks_in(c, out)


## Leaves out every node that is under another one in the list.
static func top_level(nodes: Array) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in nodes:
		if not (n is Node3D):
			continue
		var inside := false
		var p: Node = (n as Node).get_parent()
		while p and not inside:
			for other in nodes:   # (not "p in nodes": a typed list refuses to be asked about a node of another type)
				inside = inside or other == p
			p = p.get_parent()
		if not inside:
			out.append(n)
	return out


## The box round `nodes` and all their blocks, square to the map. A node with no
## blocks counts as the point it is at.
static func bounds_of(nodes: Array) -> AABB:
	var box := AABB()
	var first := true
	for n in nodes:
		var points := PackedVector3Array()
		var blocks := blocks_in(n)
		if blocks.is_empty() and n is Node3D:
			points.append(global_of(n).origin)
		for b in blocks:
			var ob := box_of(b)
			var xf: Transform3D = ob[0]
			var h: Vector3 = ob[1]
			for i in 8:
				points.append(xf * Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
		for p in points:
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box


# ---------------------------------------------------------------------------
# Hollow and clip

## Can this block be hollowed with walls this thick?
static func can_hollow(block: MapBlock, thickness: float) -> bool:
	if block.shape != MapBlock.Shape.BOX or thickness < SLIVER:
		return false
	var s := block.size
	return thickness * 2.0 < minf(s.x, minf(s.y, s.z)) - SLIVER


## A box as a room: a group of walls `thickness` thick that together fill the same
## outside as the block (a floor, a ceiling and four walls between them, none
## overlapping). Each wall is a copy of the block, so it keeps its kind and settings.
## Null if the block is not a box or is too small.
static func hollow(block: MapBlock, thickness: float, open_top := false, no_floor := false) -> Node3D:
	if not can_hollow(block, thickness):
		return null
	var s := block.size
	var t := thickness
	var group := Node3D.new()
	group.name = block.name
	group.transform = block.transform
	group.visible = block.visible
	group.set_meta("_edit_group_", true)
	var low := -s.y * 0.5 + (0.0 if no_floor else t)    # the walls stand from here
	var high := s.y * 0.5 - (0.0 if open_top else t)    # to here
	var walls := []   # [name, size, middle]
	if not no_floor:
		walls.append(["Floor", Vector3(s.x, t, s.z), Vector3(0, -s.y * 0.5 + t * 0.5, 0)])
	if not open_top:
		walls.append(["Ceiling", Vector3(s.x, t, s.z), Vector3(0, s.y * 0.5 - t * 0.5, 0)])
	var mid := (low + high) * 0.5
	var tall := high - low
	walls.append(["WallLeft", Vector3(t, tall, s.z), Vector3(-s.x * 0.5 + t * 0.5, mid, 0)])
	walls.append(["WallRight", Vector3(t, tall, s.z), Vector3(s.x * 0.5 - t * 0.5, mid, 0)])
	walls.append(["WallFront", Vector3(s.x - t * 2.0, tall, t), Vector3(0, mid, -s.z * 0.5 + t * 0.5)])
	walls.append(["WallBack", Vector3(s.x - t * 2.0, tall, t), Vector3(0, mid, s.z * 0.5 - t * 0.5)])
	for w in walls:
		var wall := MapPiece.copy(block) as MapBlock
		for c in wall.get_children():   # what stood under the block stays with the group, once
			wall.remove_child(c)
			c.free()
		wall.name = w[0]
		wall.transform = Transform3D(Basis.IDENTITY, w[2])
		wall.visible = true
		wall.size = w[1]
		group.add_child(wall)
	for c in block.get_children():
		group.add_child(MapPiece.copy(c))
	return group


## Which of a block's own axes (0 x, 1 y, 2 z) it can be cut across.
static func clip_axes(block: MapBlock) -> Array[int]:
	match block.shape:
		MapBlock.Shape.BOX, MapBlock.Shape.BEVEL:
			return [0, 1, 2]
		MapBlock.Shape.CYLINDER, MapBlock.Shape.TUBE:
			return [1]
	return []


## Cuts a block in two across one of its own axes, `at` metres from its middle (in
## its own units). Returns the two halves, the lower one first (each a copy with
## every setting kept), or nothing if the shape cannot be cut that way or the cut
## misses it.
static func clip(block: MapBlock, axis: int, at: float) -> Array[MapBlock]:
	var out: Array[MapBlock] = []
	if axis not in clip_axes(block):
		return out
	var h := block.size[axis] * 0.5
	if at <= -h + SLIVER or at >= h - SLIVER:
		return out
	var along := Vector3.ZERO
	along[axis] = 1.0
	for side in 2:
		var part := MapPiece.copy(block) as MapBlock
		var length := (at + h) if side == 0 else (h - at)
		var middle := (at - h) * 0.5 if side == 0 else (at + h) * 0.5
		var size := block.size
		size[axis] = length
		part.size = size
		part.position = block.position + block.transform.basis * (along * middle)
		part.name = String(block.name) if side == 0 else String(block.name) + "B"
		out.append(part)
	return out


# ---------------------------------------------------------------------------
# Moving, turning and selecting

## Which way an arrow key moves things in a view: the map axis nearest the view's
## right (Left and Right), up in a top, front or side view or forward in 3D (Up and
## Down); Page Up and Page Down are always up and down. `ortho_axis`: the axis a top,
## front or side view looks along (-1 for 3D). Zero for any other key.
static func arrow_direction(camera_basis: Basis, ortho_axis: int, keycode: int) -> Vector3:
	match keycode:
		KEY_PAGEUP:
			return Vector3.UP
		KEY_PAGEDOWN:
			return Vector3.DOWN
	var skip := ortho_axis if ortho_axis >= 0 else 1
	var right := _nearest_axis(camera_basis.x, skip)
	var up := _nearest_axis(camera_basis.y if ortho_axis >= 0 else -camera_basis.z, skip)
	match keycode:
		KEY_RIGHT: return right
		KEY_LEFT: return -right
		KEY_UP: return up
		KEY_DOWN: return -up
	return Vector3.ZERO


static func _nearest_axis(v: Vector3, skip: int) -> Vector3:
	v[skip] = 0.0
	if v.is_zero_approx():
		return Vector3.ZERO
	var a := v.abs().max_axis_index()
	var out := Vector3.ZERO
	out[a] = signf(v[a])
	return out


## Where a node at `global` goes when turned a quarter turn (`dir` 1 or -1) about the
## map's axis `axis` (0 x, 1 y, 2 z) through `pivot`: the turn is exact (no 0.9999s
## creeping in) and the place is kept to a tenth of a millimetre.
static func quarter_turned(global: Transform3D, axis: int, dir: int, pivot: Vector3) -> Transform3D:
	var along := Vector3.ZERO
	along[axis] = 1.0
	var turn := Basis(along, dir * PI * 0.5)
	for col in 3:
		turn[col] = turn[col].round()
	var basis := turn * global.basis
	for col in 3:
		basis[col] = basis[col].snappedf(0.000001)
	var origin := pivot + turn * (global.origin - pivot)
	return Transform3D(basis, origin.snappedf(0.0001))


## The box round a block, square to the map.
static func box_in_map(block: MapBlock) -> AABB:
	return bounds_of([block])


## Of `others`, the blocks that touch or overlap any of `chosen` (by the boxes round
## them, square to the map).
static func touching(chosen: Array, others: Array) -> Array:
	var boxes := chosen.map(func(b: MapBlock) -> AABB: return box_in_map(b).grow(0.001))
	return others.filter(func(o: MapBlock) -> bool:
		var box := box_in_map(o)
		return boxes.any(func(c: AABB) -> bool: return c.intersects(box)))


## Of `others`, the blocks wholly inside one of `chosen` (by the boxes round them).
static func inside(chosen: Array, others: Array) -> Array:
	var boxes := chosen.map(func(b: MapBlock) -> AABB: return box_in_map(b).grow(0.001))
	return others.filter(func(o: MapBlock) -> bool:
		var box := box_in_map(o)
		return boxes.any(func(c: AABB) -> bool: return c.encloses(box)))


## Of `others`, the blocks standing within the ground plan of `chosen` (seen from
## above, however high or low: a top view's "select tall").
static func tall(chosen: Array, others: Array) -> Array:
	var plans := chosen.map(func(b: MapBlock) -> Rect2:
		var box := box_in_map(b).grow(0.001)
		return Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
	return others.filter(func(o: MapBlock) -> bool:
		var box := box_in_map(o)
		var plan := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		return plans.any(func(c: Rect2) -> bool: return c.encloses(plan)))


# ---------------------------------------------------------------------------
# Hulls

## The corners of each convex lump a block is made of (see MapBlock.shape_lumps),
## as they would be for hull blocks. Empty if the block cannot be made of hull
## blocks: a lump with more than MapMesher.MAX_HULL_CORNERS corners, or a flat one.
static func editable_lumps(block: MapBlock) -> Array:
	var out := []
	for lump in block.shape_lumps():
		var corners := MapMesher.hull_corners(lump)
		if corners.size() < 4 or corners.size() > MapMesher.MAX_HULL_CORNERS:
			return []
		out.append(corners)
	return out


## The block made into hull blocks of the same shape, standing where it stands,
## to put in its place: one hull block, or for a shape of several lumps (a tube, an
## arch, a hollow dome) a group of them. Each keeps the block's kind and settings.
## Null if it cannot be (see editable_lumps) or already is a hull.
static func make_editable(block: MapBlock) -> Node3D:
	if block.shape == MapBlock.Shape.HULL:
		return null
	var lumps := editable_lumps(block)
	if lumps.is_empty():
		return null
	if lumps.size() == 1:
		var hull := _hull_copy(block, lumps[0])
		# Its corners are kept centred: move it by the lump's middle so the shape stays
		# put, and what stands under it back by as much.
		var middle := MapBlock.points_bounds(lumps[0]).get_center()
		hull.position = block.position + block.transform.basis * middle
		for c in hull.get_children():
			if c is Node3D:
				(c as Node3D).position -= middle
		return hull
	var group := Node3D.new()
	group.name = block.name
	group.transform = block.transform
	group.visible = block.visible
	group.set_meta("_edit_group_", true)
	for i in lumps.size():
		var part := _hull_copy(block, lumps[i])
		for c in part.get_children():   # what stood under the block goes to the group, once
			part.remove_child(c)
			c.free()
		part.name = "%s%d" % [block.name, i + 1]
		part.transform = Transform3D(Basis.IDENTITY, MapBlock.points_bounds(lumps[i]).get_center())
		part.visible = true
		group.add_child(part)
	for c in block.get_children():
		group.add_child(MapPiece.copy(c))
	return group


static func _hull_copy(block: MapBlock, corners: PackedVector3Array) -> MapBlock:
	var hull := MapPiece.copy(block) as MapBlock
	hull.shape = MapBlock.Shape.HULL
	hull.points = corners
	return hull


## A hull block's corners as a mirror leaves them. A mirror turns a block's own x
## back rather than scaling it by -1 (see mirrored_global), which is exact for every
## other shape, as each is the same either side of its own x; a hull need not be, so
## its corners are mirrored across its own x instead.
static func mirrored_points(block: MapBlock) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in block.points:
		out.append(Vector3(-p.x, p.y, p.z))
	return out


## Every hull block that is `node` or under it.
static func hulls_in(node: Node) -> Array[MapBlock]:
	return blocks_in(node).filter(func(b: MapBlock) -> bool: return b.shape == MapBlock.Shape.HULL)


## A hull's points with some of them moved (`moved`: index -> where it goes, in the
## block's own frame), as the vertex tool leaves them: a point that ends up inside
## the new shape is dropped, and points that end up together are one. Empty if the
## move is refused: the shape would be flat, a moved point would sink inside it (the
## shape would have to be concave), or it would have too many corners.
static func reshaped(points: PackedVector3Array, moved: Dictionary) -> PackedVector3Array:
	var pts := points.duplicate()
	for i: int in moved:
		pts[i] = moved[i]
	var planes := MapMesher.hull_planes(pts)
	if planes.size() < 4:
		return PackedVector3Array()
	for i: int in moved:
		if _sunk(planes, pts[i]):
			return PackedVector3Array()
	var out := PackedVector3Array()
	for p in pts:
		if _sunk(planes, p):
			continue
		var again := false
		for q in out:
			again = again or q.distance_to(p) <= 0.0005
		if not again:
			out.append(p)
	if MapMesher.hull_corners(out).size() > MapMesher.MAX_HULL_CORNERS:
		return PackedVector3Array()
	return out


## A hull's points with one face (`face`: its index in MapMesher.hull_planes) pushed
## out `by` (in the block's own units; less than 0 pulls it in), every other face
## staying in its plane: the face's neighbours grow or shrink to meet it. Empty if
## that is refused: the face would vanish (its neighbours meet before it), or the
## shape would be flat or have too many corners.
static func extruded(points: PackedVector3Array, face: int, by: float) -> PackedVector3Array:
	var planes := MapMesher.hull_planes(points)
	if face < 0 or face >= planes.size():
		return PackedVector3Array()
	var moved: Array[Plane] = planes.duplicate()
	var plane: Plane = planes[face]
	moved[face] = Plane(plane.normal, plane.d + by)
	var pts := corners_of(moved)
	if pts.size() > MapMesher.MAX_HULL_CORNERS:
		return PackedVector3Array()
	var after := MapMesher.hull_planes(pts)
	if after.size() < 4:
		return PackedVector3Array()
	var kept := false
	for p in after:
		kept = kept or (p.normal.dot(plane.normal) > 0.9999 and absf(p.d - plane.d - by) < 0.001)
	return pts if kept else PackedVector3Array()


## A hull block's face handle dragged: face `face` of the shape it had (`from`, with
## the block at `at`) pushed out to where the line straight out from the face's middle
## comes nearest the ray (`origin`, `dir`, in the map), by whole steps of `step`
## metres. [centred points, position] for the block, or [] if refused (see extruded).
static func pushed_face(block: MapBlock, from: PackedVector3Array, at: Vector3, face: int,
		origin: Vector3, dir: Vector3, step: float) -> Array:
	var planes := MapMesher.hull_planes(from)
	if face < 0 or face >= planes.size():
		return []
	var frame := parent_global(block) * Transform3D(block.transform.basis, at)
	var inv := frame.affine_inverse()
	var n: Vector3 = planes[face].normal
	var middle: Vector3 = face_middles(from)[face]
	var a := inv * origin
	var b := inv * (origin + dir * 4096.0)
	var closest := Geometry3D.get_closest_points_between_segments(middle - n * 4096.0, middle + n * 4096.0, a, b)
	var reach := (closest[0] - middle).dot(n)   # in the block's own units
	var per_metre := (frame.basis.inverse().transposed() * n).length()   # its own units per metre, along the face's normal
	var by := snap(reach / per_metre, step) * per_metre
	var pts := extruded(from, face, by)
	if pts.is_empty():
		return []
	return hull_placement(block, pts, at)


## The middle of each face of a hull (in its own frame), in the order of
## MapMesher.hull_planes.
static func face_middles(points: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for face in MapMesher.hull_faces(points):
		var middle := Vector3.ZERO
		for p: Vector3 in face[1]:
			middle += p
		out.append(middle / (face[1] as Array).size())
	return out


## A hull's points without some of them (`gone`: their indices). Empty if what is
## left is not a solid shape.
static func without_points(points: PackedVector3Array, gone: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in points.size():
		if i not in gone:
			out.append(points[i])
	return out if MapMesher.hull_planes(out).size() >= 4 else PackedVector3Array()


## Is `p` well inside the hull with these planes (not on its surface)?
static func _sunk(planes: Array, p: Vector3) -> bool:
	for plane: Plane in planes:
		if plane.distance_to(p) > -0.0005:
			return false
	return true


## Where a hull block's points go and where the block goes, so that `pts` (in the
## block's own frame with the block at `at`, not centred) are where the shape is:
## the block keeps its points centred, so it moves by their middle instead.
## [centred points, new position].
static func hull_placement(block: MapBlock, pts: PackedVector3Array, at: Vector3) -> Array:
	var middle := MapBlock.points_bounds(pts).get_center()
	var centred := pts.duplicate()
	for i in centred.size():
		centred[i] -= middle
	return [centred, at + block.transform.basis * middle]


## A hull block's edges, in its own frame: [[a, b], ...], each once.
static func hull_edges(points: PackedVector3Array) -> Array:
	var out := []
	for face in MapMesher.hull_faces(points):
		var ring: Array = face[1]
		for i in ring.size():
			var a: Vector3 = ring[i]
			var b: Vector3 = ring[(i + 1) % ring.size()]
			var seen := false
			for e in out:
				seen = seen or ((e[0] as Vector3).is_equal_approx(b) and (e[1] as Vector3).is_equal_approx(a)) \
					or ((e[0] as Vector3).is_equal_approx(a) and (e[1] as Vector3).is_equal_approx(b))
			if not seen:
				out.append([a, b])
	return out


## Where a ray (in the block's own frame) first meets a hull's surface: [distance,
## the face's corners (ring), its outward normal, its index in MapMesher.hull_planes],
## or [] if it misses.
static func ray_hull(origin: Vector3, dir: Vector3, points: PackedVector3Array) -> Array:
	var faces := MapMesher.hull_faces(points)
	var planes := MapMesher.hull_planes(points)
	var best := []
	for index in faces.size():
		var face: Array = faces[index]
		var n: Vector3 = face[0]
		var facing := n.dot(dir)
		if facing >= -1e-6:
			continue   # seen from behind, or edge on
		var d := n.dot((face[1] as Array)[0])
		var t := (d - n.dot(origin)) / facing
		if t < 0.0 or (not best.is_empty() and t >= best[0]):
			continue
		if MapMesher.hull_has(planes, origin + dir * t, 0.001):
			best = [t, face[1], n, index]
	return best


## Cuts a block along a plane (in the map). [behind, in front]: the part on the side
## the plane faces away from, and the part on the side it faces, each a copy of the
## block with every setting kept, or null if the plane leaves nothing that side.
## A box cut square to its own sides gives boxes (as clip() does); anything else gives
## hull blocks. [] if the plane misses the block or it cannot be cut that way (a
## shape of several lumps, such as a tube or an arch, or one whose parts would have
## too many corners).
static func clip_plane(block: MapBlock, plane: Plane) -> Array:
	var xf := global_of(block)
	# The plane in the block's own frame: n . (B p + o) = d  ->  (Bt n) . p = d - n . o
	var n := xf.basis.transposed() * plane.normal
	var d := plane.d - plane.normal.dot(xf.origin)
	var length := n.length()
	if length < 1e-9:
		return []
	n /= length
	d /= length
	if block.shape == MapBlock.Shape.BOX:
		for axis in 3:
			if absf(n[axis]) > 0.9999:
				var halves := clip(block, axis, d / n[axis])
				if halves.size() != 2:
					return []
				return [halves[0], halves[1]] if n[axis] > 0.0 else [halves[1], halves[0]]
	var lumps := editable_lumps(block)
	if lumps.size() != 1:
		return []
	var pts: PackedVector3Array = lumps[0]
	var ahead := false
	var behind := false
	for p in pts:
		var s := n.dot(p) - d
		ahead = ahead or s > SLIVER
		behind = behind or s < -SLIVER
	if not (ahead and behind):
		return []
	var planes := MapMesher.hull_planes(pts)
	var out := []
	var children_kept := false   # what stood under the block goes with the first part, once
	for side: Plane in [Plane(n, d), Plane(-n, -d)]:
		var cut: Array[Plane] = planes.duplicate()
		cut.append(side)
		var corners := corners_of(cut)
		if corners.size() > MapMesher.MAX_HULL_CORNERS:
			return []
		if MapMesher.hull_planes(corners).size() < 4:
			out.append(null)
			continue
		var part := _hull_copy(block, corners)
		var middle := MapBlock.points_bounds(corners).get_center()
		part.position = block.position + block.transform.basis * middle
		for c in part.get_children():
			if children_kept:
				part.remove_child(c)
				c.free()
			elif c is Node3D:
				(c as Node3D).position -= middle
		children_kept = true
		part.name = String(block.name) if out.is_empty() else String(block.name) + "B"
		out.append(part)
	return out


## The corners of the convex shape closed by `planes` (each facing out). Godot gives
## a corner once for every three planes that meet there, so where several meet (the
## top of a pyramid, two shapes sharing a face) the same corner comes many times over:
## each is kept once, as finding a lump's faces takes far longer the more points there
## are. Rounded to a tenth of a millimetre, so corners worked out from planes stay where
## they belong.
static func corners_of(planes: Array[Plane]) -> PackedVector3Array:
	var unique := {}
	for p in Geometry3D.compute_convex_mesh_points(planes):
		unique[p.snappedf(0.0001)] = true
	return MapMesher.hull_corners(PackedVector3Array(unique.keys()))


# ---------------------------------------------------------------------------
# CSG: subtract, merge, intersect, and hollow for any shape

## The solid that `planes` (each facing out) close round: its corners, or empty if
## they close round nothing thicker than a sliver.
static func solid_of(planes: Array[Plane]) -> PackedVector3Array:
	var corners := corners_of(planes)
	if MapMesher.hull_planes(corners).size() < 4:
		return PackedVector3Array()
	var size := MapBlock.points_bounds(corners).size
	if minf(size.x, minf(size.y, size.z)) < SLIVER:
		return PackedVector3Array()
	return corners


## A block's shape as planes in the map (each facing out). Empty if it is not one
## convex lump (a tube, an arch, a hollow dome) or has too many corners.
static func world_planes(block: MapBlock) -> Array[Plane]:
	var out: Array[Plane] = []
	var lumps := editable_lumps(block)
	if lumps.size() != 1:
		return out
	var xf := global_of(block)
	for p in MapMesher.hull_planes(lumps[0]):
		out.append(xf * p)
	return out


## `planes` (in the map) as seen from a block's own frame.
static func planes_in(block: MapBlock, planes: Array[Plane]) -> Array[Plane]:
	var inv := global_of(block).affine_inverse()
	var out: Array[Plane] = []
	for p in planes:
		out.append(inv * p)
	return out


## What is left of the convex shape with corners `pts` when the convex shape closed
## by `cutter` (planes in the same frame) is taken out of it: the pieces outside the
## cutter, each its corners, none overlapping. Null if the two do not overlap.
static func subtract_points(pts: PackedVector3Array, cutter: Array[Plane]) -> Variant:
	var planes := MapMesher.hull_planes(pts)
	var both: Array[Plane] = planes.duplicate()
	both.append_array(cutter)
	if solid_of(both).is_empty():
		return null
	var out := []
	var rest: Array[Plane] = planes.duplicate()
	for c in cutter:
		# The part of what is left that lies outside this face of the cutter is a piece;
		# go on with the part inside it.
		var outside: Array[Plane] = rest.duplicate()
		outside.append(Plane(-c.normal, -c.d))
		var piece := solid_of(outside)
		if not piece.is_empty():
			out.append(piece)
		rest.append(c)
	return out


## A copy of `block` (every setting kept) of the shape with corners `pts` (in the
## block's own frame), placed where those corners are when its frame is `frame`
## (a transform under the block's parent; null: the block's own). A shape that is a box
## square to the block's frame is a box block; anything else a hull block.
static func shaped_like(block: MapBlock, pts: PackedVector3Array, frame: Variant = null) -> MapBlock:
	var part := MapPiece.copy(block) as MapBlock
	for c in part.get_children():
		part.remove_child(c)
		c.free()
	var box := MapBlock.points_bounds(pts)
	var square := pts.size() == 8
	for p in pts:
		for axis in 3:
			square = square and (is_equal_approx(p[axis], box.position[axis]) or is_equal_approx(p[axis], box.end[axis]))
	var at: Transform3D = block.transform if frame == null else frame
	if square:
		part.shape = MapBlock.Shape.BOX
		part.points = PackedVector3Array()
		part.size = box.size
	else:
		part.shape = MapBlock.Shape.HULL
		part.points = pts
	part.transform = at
	part.position = at.origin + at.basis * box.get_center()
	return part


## Subtract: `block` with the shapes of `cutters` (each an Array[Plane] in the map, see
## world_planes) taken out: a group of the pieces left, standing where the block stood
## (each piece a copy of it with every setting kept), to put in its place. Null if no
## cutter overlaps it or the block cannot be cut (several lumps). An empty group if
## nothing is left.
static func subtracted(block: MapBlock, cutters: Array) -> Node3D:
	var lumps := editable_lumps(block)
	if lumps.size() != 1:
		return null
	var pieces := [lumps[0]]
	var touched := false
	for cutter: Array[Plane] in cutters:
		var mine := planes_in(block, cutter)
		var next := []
		for p: PackedVector3Array in pieces:
			var left: Variant = subtract_points(p, mine)
			if left == null:
				next.append(p)
			else:
				touched = true
				next.append_array(left)
		pieces = next
	if not touched:
		return null
	return _group_of(block, pieces, String(block.name))


## A group standing where `block` stood, of copies of it shaped as `pieces` (each its
## corners in the block's own frame), named `prefix` 1, 2... What stood under the block
## goes into the group, once.
static func _group_of(block: MapBlock, pieces: Array, prefix: String) -> Node3D:
	var group := Node3D.new()
	group.name = block.name
	group.transform = block.transform
	group.visible = block.visible
	group.set_meta("_edit_group_", true)
	for i in pieces.size():
		var part := shaped_like(block, pieces[i], Transform3D.IDENTITY)
		part.name = "%s%d" % [prefix, i + 1]
		part.visible = true
		group.add_child(part)
	for c in block.get_children():
		group.add_child(MapPiece.copy(c))
	return group


## Merge, as TrenchBroom's convex merge does: the smallest convex block round all of
## `blocks` (a copy of the first, with its settings), in the first one's frame, to put
## in place of the first. Any gap or inside corner between them is filled in (a block
## cannot be L-shaped). Null if any is not one lump, or the result would have too many
## corners.
static func merged(blocks: Array) -> MapBlock:
	if blocks.is_empty():
		return null
	var first: MapBlock = blocks[0]
	var inv := global_of(first).affine_inverse()
	var all := PackedVector3Array()
	for b: MapBlock in blocks:
		var lumps := editable_lumps(b)
		if lumps.size() != 1:
			return null
		var xf := inv * global_of(b)
		for p in lumps[0]:
			all.append((xf * p).snappedf(0.0001))
	var corners := MapMesher.hull_corners(all)
	if corners.size() > MapMesher.MAX_HULL_CORNERS or MapMesher.hull_planes(corners).size() < 4:
		return null
	return shaped_like(first, corners)


## Intersect: what all of `blocks` share, as one block (a copy of the first), in the
## first one's frame. Null if they share nothing, or any is not one lump.
static func intersected(blocks: Array) -> MapBlock:
	if blocks.size() < 2:
		return null
	var first: MapBlock = blocks[0]
	var planes: Array[Plane] = []
	for b: MapBlock in blocks:
		var mine := world_planes(b)
		if mine.is_empty():
			return null
		planes.append_array(mine)
	var pts := solid_of(planes_in(first, planes))
	if pts.is_empty() or pts.size() > MapMesher.MAX_HULL_CORNERS:
		return null
	return shaped_like(first, pts)


## Hollow for any one-lump shape: walls `thickness` thick (measured square to each
## face) that fill the same outside, as a group of blocks. `open_top` leaves out the
## walls of faces that look up, `no_floor` those that look down. Null if the shape is
## not one lump or the walls do not fit.
static func hollowed(block: MapBlock, thickness: float, open_top := false, no_floor := false) -> Node3D:
	var lumps := editable_lumps(block)
	if lumps.size() != 1 or thickness < SLIVER:
		return null
	var scale := global_of(block).basis.get_scale().abs()
	var inner: Array[Plane] = []
	for p in MapMesher.hull_planes(lumps[0]):
		# In the block's own units, so a scaled block's walls are still `thickness` metres.
		var t := thickness * (Basis.from_scale(scale).inverse() * p.normal).length()
		if (open_top and p.normal.y > 0.7) or (no_floor and p.normal.y < -0.7):
			inner.append(Plane(p.normal, p.d + 1.0))   # out past the face: no wall there
		else:
			inner.append(Plane(p.normal, p.d - t))
	if solid_of(inner).is_empty():
		return null
	var pieces: Variant = subtract_points(lumps[0], inner)
	if pieces == null or (pieces as Array).is_empty():
		return null
	return _group_of(block, pieces, "Wall")


## Where a block not yet in the scene would be in the map, if it stood beside
## `beside` (under the same parent).
static func global_beside(node: Node3D, beside: Node) -> Transform3D:
	return parent_global(beside) * node.transform


# ---------------------------------------------------------------------------
# Mirror and array

## The mirror across the plane through `pivot` that faces along `axis` (0 = x: left
## becomes right; 2 = z: front becomes back), for places in the map.
static func reflection(axis: int, pivot: Vector3) -> Transform3D:
	var b := Basis.IDENTITY
	b[axis] = -b[axis]
	return Transform3D(b, pivot - b * pivot)


## Where a node at `global` goes when mirrored. Its position and the way it is turned
## are mirrored, then its own x is turned back, so it is never scaled by -1 (every
## block shape is the same either side of its own x, so this is exact).
static func mirrored_global(global: Transform3D, axis: int, pivot: Vector3) -> Transform3D:
	return reflection(axis, pivot) * global * FLIP_X


## Mirroring `node` in place: [node, its new transform] for it and for every Node3D
## under it. (Under a mirrored node, each child's own transform has its x turned about.)
static func mirror_plan(node: Node3D, axis: int, pivot: Vector3) -> Array:
	var plan := [[node, parent_global(node).affine_inverse() * mirrored_global(global_of(node), axis, pivot)]]
	_plan_inside(node, plan)
	return plan


static func _plan_inside(node: Node, plan: Array) -> void:
	for c in node.get_children():
		if c is Node3D:
			plan.append([c, FLIP_X * (c as Node3D).transform * FLIP_X])
		_plan_inside(c, plan)


## A mirrored copy of `node`, to add beside it (under the same parent).
static func mirrored_copy(node: Node3D, axis: int, pivot: Vector3) -> Node3D:
	var dup := MapPiece.copy(node) as Node3D
	dup.transform = parent_global(node).affine_inverse() * mirrored_global(global_of(node), axis, pivot)
	var inside := []
	_plan_inside(dup, inside)
	for step in inside:
		(step[0] as Node3D).transform = step[1]
	for hull in hulls_in(dup):
		hull.points = mirrored_points(hull)
	return dup


## `copies` copies of `node` in a line, each `offset` (metres, in the map) from the
## one before, to add beside it.
static func array_line(node: Node3D, copies: int, offset: Vector3) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var to_parent := parent_global(node).affine_inverse()
	var global := global_of(node)
	for i in range(1, copies + 1):
		var dup := MapPiece.copy(node) as Node3D
		dup.transform = to_parent * Transform3D(global.basis, global.origin + offset * i)
		out.append(dup)
	return out


## Copies of `node` turned about the upright line through `pivot` so that, with the
## node itself, `total` of them stand evenly round the circle (4 = the four sides of a
## square map). Returns the total - 1 copies, to add beside it.
static func array_ring(node: Node3D, total: int, pivot: Vector3) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var to_parent := parent_global(node).affine_inverse()
	var global := global_of(node)
	for i in range(1, total):
		var turn := Transform3D(Basis(Vector3.UP, TAU * i / total), Vector3.ZERO)
		var dup := MapPiece.copy(node) as Node3D
		dup.transform = to_parent * (Transform3D(Basis.IDENTITY, pivot) * turn * Transform3D(Basis.IDENTITY, -pivot) * global)
		out.append(dup)
	return out


# ---------------------------------------------------------------------------
# Face snapping

## A box (`xf` unscaled, `half` its half size) as seen from a frame (`to_frame` =
## that frame's inverse), if its sides are square to the frame's axes: its AABB there.
## Null if it is turned some other way; such a box is never snapped to.
static func aligned_box(to_frame: Transform3D, xf: Transform3D, half: Vector3) -> Variant:
	var rel := to_frame * xf
	var b := rel.basis
	for col in [b.x, b.y, b.z]:
		var a: Vector3 = (col as Vector3).abs()
		if a.x + a.y + a.z - a[a.max_axis_index()] > 0.002:
			return null
	var ext := Vector3(
		absf(b.x.x) * half.x + absf(b.y.x) * half.y + absf(b.z.x) * half.z,
		absf(b.x.y) * half.x + absf(b.y.y) * half.y + absf(b.z.y) * half.z,
		absf(b.x.z) * half.x + absf(b.y.z) * half.y + absf(b.z.z) * half.z)
	return AABB(rel.origin - ext, ext * 2.0)


## The boxes of `blocks` as seen from `frame`, leaving out any not square to it.
static func boxes_in_frame(frame: Transform3D, blocks: Array) -> Array[AABB]:
	var out: Array[AABB] = []
	var to_frame := frame.affine_inverse()
	for b in blocks:
		var ob := box_of(b)
		var box: Variant = aligned_box(to_frame, ob[0], ob[1])
		if box != null:
			out.append(box)
	return out


## Do two boxes face each other across `axis`: overlapping, or within `reach`, on the
## other two axes?
static func _beside(a: AABB, b: AABB, axis: int, reach: float) -> bool:
	for other in 3:
		if other == axis:
			continue
		if a.position[other] > b.end[other] + reach or b.position[other] > a.end[other] + reach:
			return false
	return true


## How far to move `box` so its faces meet those of the nearest of `others` (all in
## one frame): up to `reach` along each axis, to stand against a neighbour's face or
## flush with it. Returns [the move, which axes snapped (1 or 0 each)].
static func snap_move(box: AABB, others: Array[AABB], reach: float) -> Array:
	var move := Vector3.ZERO
	var snapped := Vector3i.ZERO
	for axis in 3:
		var best := INF
		for o in others:
			if not _beside(box, o, axis, reach):
				continue
			for d: float in [o.position[axis] - box.end[axis], o.end[axis] - box.position[axis],
					o.position[axis] - box.position[axis], o.end[axis] - box.end[axis]]:
				if absf(d) < absf(best):
					best = d
		if absf(best) <= reach:
			move[axis] = best
			snapped[axis] = 1
	return [move, snapped]


## How far to move one face of `box` (the one facing `dir` = 1 or -1 along `axis`) to
## meet a face of the nearest of `others`, if one is within `reach`; else INF.
static func snap_face(box: AABB, axis: int, dir: float, others: Array[AABB], reach: float) -> float:
	var face := box.end[axis] if dir > 0.0 else box.position[axis]
	var best := INF
	for o in others:
		if not _beside(box, o, axis, reach):
			continue
		for d: float in [o.position[axis] - face, o.end[axis] - face]:
			if absf(d) < absf(best):
				best = d
	return best if absf(best) <= reach else INF


# ---------------------------------------------------------------------------
# Prefabs

## The selected nodes as a scene of their own: copies under one root, placed round
## the middle of their foot (so the prefab stands on whatever it is put on).
static func make_prefab(nodes: Array, prefab_name: String) -> Node3D:
	var tops := top_level(nodes)
	var box := bounds_of(tops)
	var foot := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var root := Node3D.new()
	root.name = prefab_name
	for n in tops:
		var dup := MapPiece.copy(n) as Node3D
		dup.transform = Transform3D(Basis.IDENTITY, -foot) * global_of(n)
		root.add_child(dup, true)
		MapPiece.adopt(dup, root)
	return root


## A prefab as plain nodes to add to a map: nothing ties them to the prefab's file,
## so changing the prefab later does not change the map. One selection group.
static func place_prefab(scene: PackedScene) -> Node3D:
	var node := scene.instantiate() as Node3D
	if node == null:
		return null
	node.scene_file_path = ""
	node.set_meta("_edit_group_", true)
	return node


## A prefab as a linked copy to add to a map: the scene itself, placed in the map, so
## the map saves a link to its file and every linked copy changes when the prefab does.
## (Its blocks are the prefab's: change them by opening the prefab, or turn the copy
## into plain blocks with the Scene dock's Make Local.)
static func place_prefab_linked(scene: PackedScene) -> Node3D:
	return scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D


## The block kinds `node` uses that `palette` has no colour for.
static func missing_kinds(node: Node, palette: MapPalette) -> PackedStringArray:
	var missing := PackedStringArray()
	for b in blocks_in(node):
		if (palette == null or not palette.colors.has(b.kind)) and b.kind not in missing:
			missing.append(b.kind)
	return missing


# ---------------------------------------------------------------------------
# Picking

## Where a ray first meets a box (`xf` unscaled, `half` its half size): [how far
## along the ray, which of the box's own axes the face hit looks along (0 to 2), which
## way (1 or -1)]. Empty if it misses, or starts inside the box.
static func ray_box(origin: Vector3, dir: Vector3, xf: Transform3D, half: Vector3) -> Array:
	var inv := xf.affine_inverse()
	var o := inv * origin
	var d := inv.basis * dir
	var near := -INF
	var far := INF
	var axis := -1
	var side := 1.0
	for a in 3:
		if absf(d[a]) < 1e-9:
			if absf(o[a]) > half[a]:
				return []
			continue
		var t1 := (-half[a] - o[a]) / d[a]
		var t2 := (half[a] - o[a]) / d[a]
		var s := -1.0
		if t1 > t2:
			var swap := t1
			t1 = t2
			t2 = swap
			s = 1.0
		if t1 > near:
			near = t1
			axis = a
			side = s
		far = minf(far, t2)
		if near > far:
			return []
	if axis < 0 or near < 0.0:
		return []
	return [near, axis, side]
