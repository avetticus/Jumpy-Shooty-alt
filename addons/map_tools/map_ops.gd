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
