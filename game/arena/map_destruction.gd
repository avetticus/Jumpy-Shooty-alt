class_name MapDestruction
extends Node3D
## Walls and floors you can shoot or smash through (arena maps only, never races).
##
## Which pieces break: solid, drawn blocks whose Breakable is ticked. Health is the
## block's own Break Health, else its Break Settings' health, else its kind's toughness
## in the palette's `breakable` list. Two ways to break:
##  - Per cell (the usual): only a thin wall or floor (a box, one side at most
##    MAX_THICKNESS, the face at least MIN_AREA square metres). Each such "panel" is
##    cut into cells of about CELL metres (glass and other weak kinds break as one
##    pane), each with that health.
##  - Whole block: any block, one "panel" of one cell that has all the health and
##    goes at once. What rests on it stays where it is.
## A cell takes damage,
## cracks (darkens) at two thirds and one third left, then breaks: its collision and
## drawing go, rubble falls and a crash plays. It stays broken until the match ends.
##
## Some cells never break, so the map stays playable:
##  - near a spawn point (the floor under it and the walls round it);
##  - anything else rests on, hangs from or goes through: the floor under a desk, a
##    wall or a stair, a slab a column passes through, a wall with a beam on top.
## Thin drawn-only pieces lying flat on a panel (a ceiling under a floor, a rug on it,
## a lamp strip, the frosting on a glass wall) are its "skins": they are cut and break
## with the cells they cover.
##
## The host decides every hit (see Match) and tells everyone which cells changed and
## how damaged they are; each copy then rebuilds that panel's collision and mesh. A
## panel's collision is the fewest boxes that cover what is left, so walking over an
## intact floor feels exactly like before.

signal cells_changed(cells: PackedInt32Array, stages: PackedByteArray)

const CELL := 2.0            ## metres: about how big a piece breaks off
const MAX_THICKNESS := 0.6   ## a wall or floor this thin or thinner can break
const MIN_AREA := 7.0        ## ...and at least this big (small landings and steps stay)
const ONE_PIECE_BELOW := 50.0  ## kinds weaker than this (glass) shatter as one pane
const SPAWN_GUARD := 3.0     ## metres round a spawn point nothing breaks
const BROKEN := 3            ## stages: 0 whole, 1 cracked, 2 badly cracked, 3 broken
const CRACK_SHADE := [1.0, 0.8, 0.62]
const MAX_DEBRIS := 140

## Every panel: {xf, size, kind, tint, n: Vector3i, cell: Vector3, first: int (first
## cell index), body: StaticBody3D, meshes: Node3D, skins: [{kind, tint, box: AABB}], thin: int,
## frame: Node3D or null}. A panel that rides a mover (an island's glass walls) has that
## mover's body as its frame: its xf is in that frame, and its body and meshes are the
## frame's children, so they go where it goes.
var panels: Array = []
## Every cell: {panel, ijk: Vector3i, hp, max_hp, stage, protected}
var cells: Array = []
var root: MapRoot

var _pending := {}   # host: cell -> new stage, sent by flush()
var _debris := 0
# Killcams (see MapReplay): what a replay draws in place of the live damage.
var _revision := 0          # goes up whenever a cell changes stage
var _captured_rev := -1
var _captured: Array = []
var _replaying := false
var _replay := {}           # cell -> the stage a replay draws it at (cells not in it: whole)
var _replay_of: Variant = null   # ...from this replay_capture() (the same one again: nothing to do)


## Takes the pieces that will break out of `pieces` (they are built here instead)
## and returns the rest, for MapRoot to build as usual.
func setup(map: MapRoot, pieces: Array, spawn_points: Array) -> Array:
	root = map
	name = "Breakables"
	var rest := _take(pieces, spawn_points, null)
	if not panels.is_empty():
		add_to_group(MapReplay.GROUP)
	return rest


## The same for the blocks of a mover (MapRoot calls it for each): `pieces` and
## `spawn_points` are in the mover's own frame, and `frame` is its moving body.
func add_riding(frame: Node3D, pieces: Array, spawn_points: Array) -> Array:
	var rest := _take(pieces, spawn_points, frame)
	if not panels.is_empty():
		add_to_group(MapReplay.GROUP)
	return rest


func _take(pieces: Array, spawn_points: Array, frame: Node3D) -> Array:
	var map := root
	var first_panel := panels.size()
	var first_cell := cells.size()
	var table: Dictionary = map.palette.breakable if map.palette else {}
	var keep := []
	var panel_pieces := []
	var whole_pieces := []
	var seen := {}
	for piece in pieces:
		if _can_break(piece, table):
			var key := "%s|%s" % [piece.xf, piece.size]
			if seen.has(key):
				continue   # the same block twice: break it once
			seen[key] = true
			panel_pieces.append(piece)
		else:
			keep.append(piece)
	if panel_pieces.is_empty():
		return pieces
	# Thin drawn-only pieces lying flat on a panel go with it (cut cell by cell).
	var skin_of := {}   # index in keep -> panel index
	for piece in panel_pieces:
		var whole: bool = piece.get("break_mode", "cell") == "whole"
		_add_panel(piece, health_of(piece, table), whole, frame)
		if whole:
			whole_pieces.append(piece)
	for k in keep.size():
		var p: Dictionary = keep[k]
		if p.solid or p.get("hidden", false) or p.shape != "box":
			continue
		for i in range(first_panel, panels.size()):
			if panels[i].whole:
				continue
			var box := _skin_box(panels[i], p)
			if box.has_volume():
				panels[i].skins.append({"kind": p.kind, "tint": p.get("tint", Color.WHITE), "box": box})
				skin_of[k] = i
				break
	var rest := []
	for k in keep.size():
		if not skin_of.has(k):
			rest.append(keep[k])
	# Whole blocks count as things resting on a floor: a floor under a crate holds.
	_protect(rest + whole_pieces, spawn_points, first_cell)
	for i in range(first_panel, panels.size()):
		_rebuild_panel(i)
	return rest


func _can_break(piece: Dictionary, table: Dictionary) -> bool:
	if not piece.solid or piece.get("hidden", false):
		return false
	if not piece.get("breakable", false):
		return false
	if piece.get("break_mode", "cell") == "whole":
		return true
	return thin_enough_piece(piece)


static func thin_enough_piece(piece: Dictionary) -> bool:
	return piece.shape == "box" and _thin(piece.size)


## Can a block of this shape and size break per cell? (MapBlock's warning asks.)
static func thin_enough(shape: int, size: Vector3) -> bool:
	return shape == MapBlock.Shape.BOX and _thin(size)


static func _thin(s: Vector3) -> bool:
	var dims := [s.x, s.y, s.z]
	dims.sort()
	return dims[0] <= MAX_THICKNESS and dims[1] * dims[2] >= MIN_AREA


## How much damage a cell of this piece takes: its own health, else its kind's
## toughness from the palette, else BlockBreakable.DEFAULT_HEALTH.
static func health_of(piece: Dictionary, table: Dictionary) -> float:
	var own: float = piece.get("health", 0.0)
	if own > 0.0:
		return own
	var kind_health: float = float(table.get(piece.kind, 0.0))
	return kind_health if kind_health > 0.0 else BlockBreakable.DEFAULT_HEALTH


func _add_panel(piece: Dictionary, toughness: float, whole: bool = false, frame: Node3D = null) -> void:
	var s: Vector3 = piece.size
	var thin := 0
	for a in 3:
		if s[a] < s[thin]:
			thin = a
	var n := Vector3i.ONE
	if toughness >= ONE_PIECE_BELOW and not whole:
		for a in 3:
			if a != thin:
				n[a] = maxi(1, roundi(s[a] / CELL))
	var mat: String = piece.get("material", "")
	if not BlockMaterials.TABLE.has(mat):
		mat = BlockMaterials.for_kind(piece.kind, root.palette)
	var panel := {"xf": piece.xf, "size": s, "kind": piece.kind, "tint": piece.get("tint", Color.WHITE),
		"n": n, "cell": Vector3(s.x / n.x, s.y / n.y, s.z / n.z), "first": cells.size(), "thin": thin,
		"skins": [], "body": null, "meshes": null, "whole": whole, "piece": piece, "material": mat, "frame": frame}
	var index := panels.size()
	panels.append(panel)
	for k in n.z:
		for j in n.y:
			for i in n.x:
				cells.append({"panel": index, "ijk": Vector3i(i, j, k), "hp": toughness, "max_hp": toughness,
					"stage": 0, "protected": false})
	var body: StaticBody3D
	if frame:
		var moving := AnimatableBody3D.new()   # it moves with its frame, a step at a time like it
		moving.sync_to_physics = false
		body = moving
	else:
		body = StaticBody3D.new()
	body.name = "Panel_%d" % index
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = piece.xf
	body.set_meta("panel", index)
	(frame if frame else self).add_child(body)
	panel.body = body
	var meshes := Node3D.new()
	meshes.name = "Mesh_%d" % index
	(frame if frame else self).add_child(meshes)
	panel.meshes = meshes


## `piece` as a box in the panel's frame, if it is a skin of that panel: thin, lying
## flat against one of its big faces, square to it, and within its outline.
func _skin_box(panel: Dictionary, piece: Dictionary) -> AABB:
	var to_local: Transform3D = (panel.xf as Transform3D).affine_inverse() * (piece.xf as Transform3D)
	for a in 3:   # square to the panel (any quarter turn)
		var col: Vector3 = to_local.basis[a].abs()
		if maxf(col.x, maxf(col.y, col.z)) < 0.999:
			return AABB()
	var box: AABB = to_local * AABB(-(piece.size as Vector3) * 0.5, piece.size)
	var half: Vector3 = panel.size * 0.5
	var thin: int = panel.thin
	if box.size[thin] > 0.15:
		return AABB()
	for a in 3:
		if a != thin and (box.position[a] < -half[a] - 0.05 or box.end[a] > half[a] + 0.05):
			return AABB()
	var gap_above: float = box.position[thin] - half[thin]
	var gap_below: float = -half[thin] - box.end[thin]
	if absf(gap_above) > 0.05 and absf(gap_below) > 0.05:
		return AABB()   # not touching either face
	return box


## Marks the cells that must not break: near spawns, and under or round other things.
func _protect(others: Array, spawn_points: Array, first_cell: int = 0) -> void:
	# A coarse grid of the other pieces' boxes, so each cell only checks its neighbours.
	var bucket := 4.0
	var grid := {}
	for p in others:
		if p.get("hidden", false) and not p.solid:
			continue
		var box: AABB = (p.xf as Transform3D) * AABB(-(p.size as Vector3) * 0.5, p.size)
		if box.size.y < 0.15 and not p.solid:
			continue   # paint and decals hold nothing up
		var lo := Vector3i((box.position / bucket).floor())
		var hi := Vector3i((box.end / bucket).floor())
		if Vector3(hi - lo).length() > 40.0:
			continue   # the ground, the sky box: too big to be resting on a panel
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var key := Vector3i(x, y, z)
					if not grid.has(key):
						grid[key] = []
					grid[key].append(box)
	for c in range(first_cell, cells.size()):
		var box := _frame_box(c)
		var cell: Dictionary = cells[c]
		for s in spawn_points:
			var at: Vector3 = s[0]
			var flat := Vector2(clampf(at.x, box.position.x, box.end.x) - at.x, clampf(at.z, box.position.z, box.end.z) - at.z)
			if flat.length() < SPAWN_GUARD and box.end.y > at.y - 1.5 and box.position.y < at.y + 3.0:
				cell.protected = true
		if cell.protected or panels[cell.panel].whole:
			continue   # (a whole block breaks even with things on it: they stay put)
		var lo := Vector3i((box.position / bucket).floor())
		var hi := Vector3i((box.end / bucket).floor())
		var floor_panel: bool = panels[cell.panel].thin == 1
		var checked := {}
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					for other in grid.get(Vector3i(x, y, z), []):
						if checked.has(other):
							continue
						checked[other] = true
						if _holds(box, other, floor_panel):
							cell.protected = true
							break


## Does `other` rest on this cell, hang from it, or go through it? (What a wall
## stands on does not count: the wall rests on that, not the other way round.)
static func _holds(cell: AABB, other: AABB, floor_panel: bool) -> bool:
	var eps := 0.05
	var grown := cell.grow(eps)
	if not grown.intersects(other):
		return false
	var overlap := grown.intersection(other)
	# Resting on top or hanging underneath (with some real footprint on it).
	var footprint := overlap.size.x > 0.1 and overlap.size.z > 0.1
	if footprint and absf(other.position.y - cell.end.y) <= eps:
		return true
	if floor_panel and footprint and absf(other.end.y - cell.position.y) <= eps:
		return true
	# Through it: the two really overlap (not just touching side by side).
	var inside := cell.intersection(other)
	return inside.size.x > eps and inside.size.y > eps and inside.size.z > eps


## A cell's box in the map's frame (around its panel's box: rough for a turned panel),
## where it is right now if it rides a mover.
func cell_box(c: int) -> AABB:
	var cell: Dictionary = cells[c]
	var panel: Dictionary = panels[cell.panel]
	return _panel_xf(panel) * _local_box(panel, cell.ijk)


## The same in its panel's frame: the map's, or its mover's.
func _frame_box(c: int) -> AABB:
	var cell: Dictionary = cells[c]
	var panel: Dictionary = panels[cell.panel]
	return (panel.xf as Transform3D) * _local_box(panel, cell.ijk)


## Where a panel is in the map right now.
func _panel_xf(panel: Dictionary) -> Transform3D:
	var frame := panel.get("frame") as Node3D
	if frame and is_instance_valid(frame):
		return frame.transform * (panel.xf as Transform3D)
	return panel.xf


func cell_center(c: int) -> Vector3:
	return cell_box(c).get_center()


func _local_box(panel: Dictionary, ijk: Vector3i) -> AABB:
	var half: Vector3 = panel.size * 0.5
	var step: Vector3 = panel.cell
	return AABB(-half + Vector3(ijk) * step, step)


## The cell a shot or a blow landed on: `body` is the collider it hit.
func cell_at(body: Object, point: Vector3, normal: Vector3) -> int:
	if body == null or not body.has_meta("panel"):
		return -1
	var panel: Dictionary = panels[int(body.get_meta("panel"))]
	var local: Vector3 = _panel_xf(panel).affine_inverse() * (point - normal * 0.03)
	var ijk: Vector3 = ((local + panel.size * 0.5) / panel.cell).floor()
	var n: Vector3i = panel.n
	var i := Vector3i(clampi(int(ijk.x), 0, n.x - 1), clampi(int(ijk.y), 0, n.y - 1), clampi(int(ijk.z), 0, n.z - 1))
	return panel.first + i.x + n.x * (i.y + n.y * i.z)


## Every cell a straight line from `a` to `b` passes through that can still take damage,
## as [cell, metres from `a` to where the line goes into it]: what a shot that goes
## through everything (the railgun) hits. Found from the cells' boxes, not the physics,
## so a cell counts wherever it is on its panel (and wherever its mover has taken it).
func cells_along(a: Vector3, b: Vector3) -> Array:
	var found := []
	for panel: Dictionary in panels:
		var xf := _panel_xf(panel)
		var to_local := xf.affine_inverse()
		var la := to_local * a
		var lb := to_local * b
		var size: Vector3 = panel.size
		if AABB(-size * 0.5, size).intersects_segment(la, lb) == null:
			continue
		var n: Vector3i = panel.n
		for k in n.z:
			for j in n.y:
				for i in n.x:
					var c: int = panel.first + i + n.x * (j + n.y * k)
					var cell: Dictionary = cells[c]
					if cell.protected or cell.stage >= BROKEN:
						continue
					var into: Variant = _local_box(panel, Vector3i(i, j, k)).intersects_segment(la, lb)
					if into != null:
						found.append([c, a.distance_to(xf * (into as Vector3))])
	return found


## What a cell is made of, for sounds and rubble (a BlockMaterials name).
func material_of(c: int) -> String:
	return panels[cells[c].panel].material


# ---------------------------------------------------------------------------
# Damage (host)

## Host: `amount` of damage on cell `c`. Changes go out with the next flush().
func damage(c: int, amount: float) -> void:
	if c < 0 or c >= cells.size():
		return
	var cell: Dictionary = cells[c]
	if cell.protected or cell.stage >= BROKEN:
		return
	cell.hp = maxf(cell.hp - amount, 0.0)
	var stage := _stage_for(cell)
	if stage != cell.stage:
		_pending[c] = stage


static func _stage_for(cell: Dictionary) -> int:
	if cell.hp <= 0.0:
		return BROKEN
	var left: float = cell.hp / cell.max_hp
	return 0 if left > 0.66 else (1 if left > 0.33 else 2)


## Host: the cells that changed since the last flush, as [cells, stages] (empty if none).
func flush() -> Array:
	if _pending.is_empty():
		return []
	var ids := PackedInt32Array()
	var stages := PackedByteArray()
	for c in _pending:
		ids.append(c)
		stages.append(_pending[c])
	_pending.clear()
	return [ids, stages]


## Host: every cell that is not whole, as [cells, stages] (for someone joining late).
func snapshot() -> Array:
	var ids := PackedInt32Array()
	var stages := PackedByteArray()
	for c in cells.size():
		if cells[c].stage != 0:
			ids.append(c)
			stages.append(cells[c].stage)
	return [ids, stages]


# ---------------------------------------------------------------------------
# Every copy: show what the host decided

## Sets cells to the given stages and rebuilds their panels. Returns the cells that
## broke just now (for rubble and sounds).
func apply(ids: PackedInt32Array, stages: PackedByteArray) -> PackedInt32Array:
	var broke := PackedInt32Array()
	var touched := {}
	for i in mini(ids.size(), stages.size()):
		var c := ids[i]
		if c < 0 or c >= cells.size():
			continue
		var cell: Dictionary = cells[c]
		var stage := int(stages[i])
		if stage == cell.stage:
			continue
		if stage >= BROKEN:
			broke.append(c)
			cell.hp = 0.0
		cell.stage = stage
		touched[cell.panel] = true
	for p in touched:
		_rebuild_panel(p)
	if not touched.is_empty():
		_revision += 1
	if not ids.is_empty():
		cells_changed.emit(ids, stages)
	if not broke.is_empty() and not _replaying:   # (a killcam playing shows the wall as it was: no rubble from it)
		_break_effects(broke)
	return broke


## "cracked/broken checksum": the same on every copy that shows the same damage (tests).
func state_key() -> String:
	var snap := snapshot()
	var broken := 0
	for st in (snap[1] as PackedByteArray):
		if st >= BROKEN:
			broken += 1
	return "%d/%d %08x" % [(snap[0] as PackedInt32Array).size() - broken, broken, hash([snap[0], snap[1]])]


func is_broken(c: int) -> bool:
	return cells[c].stage >= BROKEN


func broken_count() -> int:
	var count := 0
	for cell in cells:
		if cell.stage >= BROKEN:
			count += 1
	return count


func breakable_count() -> int:
	var count := 0
	for cell in cells:
		if not cell.protected:
			count += 1
	return count


## Rebuilds one panel's collision (the fewest boxes covering what is left) and its
## meshes (cracked cells darker, skins cut to match).
func _rebuild_panel(index: int) -> void:
	var panel: Dictionary = panels[index]
	var body: StaticBody3D = panel.body
	for child in body.get_children():
		body.remove_child(child)
		child.free()
	var first: int = panel.first
	if panel.whole:
		_rebuild_whole(panel)
		return
	var solid := func(c: int) -> int: return 0 if cells[first + c].stage >= BROKEN else 1
	for box in _merge(panel.n, solid):
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var local := _boxes_extent(panel, box)
		bs.size = local.size
		shape.shape = bs
		shape.position = local.get_center()
		body.add_child(shape)
	_rebuild_meshes(index)


## The stage cell `c` is drawn at: its own, or what a killcam playing says it was.
func _shown(c: int) -> int:
	return int(_replay.get(c, 0)) if _replaying else int(cells[c].stage)


## Rebuilds one panel's meshes from the stages its cells are drawn at (see _shown).
func _rebuild_meshes(index: int) -> void:
	var panel: Dictionary = panels[index]
	if panel.whole:
		_rebuild_whole_meshes(panel)
		return
	var first: int = panel.first
	var holder: Node3D = panel.meshes
	for child in holder.get_children():
		holder.remove_child(child)
		child.free()
	if DisplayServer.get_name() == "headless" and not root.has_meshes:
		return
	var by_stage := func(c: int) -> int: return 0 if _shown(first + c) >= BROKEN else _shown(first + c) + 1
	var pieces := []
	for box in _merge(panel.n, by_stage):
		var local := _boxes_extent(panel, box)
		var shade: float = CRACK_SHADE[box[2] - 1]
		var tint: Color = panel.tint
		pieces.append({"xf": (panel.xf as Transform3D) * Transform3D(Basis(), local.get_center()), "size": local.size,
			"kind": panel.kind, "shape": "box", "tint": Color(tint.r * shade, tint.g * shade, tint.b * shade, tint.a)})
		for skin in panel.skins:
			var clipped := _clip_skin(panel, skin.box, local)
			if clipped.has_volume():
				pieces.append({"xf": (panel.xf as Transform3D) * Transform3D(Basis(), clipped.get_center()), "size": clipped.size,
					"kind": skin.kind, "shape": "box", "tint": skin.tint})
	var meshes := MapMesher.build(pieces, root.face_shade)
	for kind in meshes:
		var mesh := MeshInstance3D.new()
		mesh.mesh = meshes[kind]
		mesh.material_override = root.material_for(kind)
		holder.add_child(mesh)


## A whole-block panel: its own shape while it stands (darker as it cracks), nothing
## once broken. (Its children were cleared by _rebuild_panel.)
func _rebuild_whole(panel: Dictionary) -> void:
	var cell: Dictionary = cells[panel.first]
	if cell.stage < BROKEN:
		var piece: Dictionary = (panel.piece as Dictionary).duplicate()
		piece.xf = Transform3D.IDENTITY   # the body sits where the block does
		for lump in root.collision_shapes(piece):
			var shape := CollisionShape3D.new()
			shape.shape = lump
			(panel.body as StaticBody3D).add_child(shape)
	_rebuild_whole_meshes(panel)


func _rebuild_whole_meshes(panel: Dictionary) -> void:
	var holder: Node3D = panel.meshes
	for child in holder.get_children():
		holder.remove_child(child)
		child.free()
	var stage := _shown(panel.first)
	if stage >= BROKEN:
		return
	if DisplayServer.get_name() == "headless" and not root.has_meshes:
		return
	var piece: Dictionary = (panel.piece as Dictionary).duplicate()
	var shade: float = CRACK_SHADE[stage]
	var tint: Color = panel.tint
	piece.xf = panel.xf
	piece.tint = Color(tint.r * shade, tint.g * shade, tint.b * shade, tint.a)
	var meshes := MapMesher.build([piece], root.face_shade)
	for kind in meshes:
		var mesh := MeshInstance3D.new()
		mesh.mesh = meshes[kind]
		mesh.material_override = root.material_for(kind)
		holder.add_child(mesh)


## The part of a skin over these cells: cut along the panel's face, whole across it.
func _clip_skin(panel: Dictionary, skin: AABB, cells_box: AABB) -> AABB:
	var lo := skin.position
	var hi := skin.end
	var half: Vector3 = panel.size * 0.5
	for a in 3:
		if a == panel.thin:
			continue
		# A skin edge on the panel's own edge stays where it is; inside, it follows the cells.
		var c_lo: float = cells_box.position[a] if cells_box.position[a] > -half[a] + 0.001 else -INF
		var c_hi: float = cells_box.end[a] if cells_box.end[a] < half[a] - 0.001 else INF
		lo[a] = maxf(lo[a], c_lo)
		hi[a] = minf(hi[a], c_hi)
		if hi[a] <= lo[a]:
			return AABB()
	return AABB(lo, hi - lo)


func _boxes_extent(panel: Dictionary, box: Array) -> AABB:
	var a: Vector3i = box[0]
	var b: Vector3i = box[1]
	var from := _local_box(panel, a)
	var to := _local_box(panel, b)
	return from.merge(to)


## Greedy merge of a grid of cells into boxes of cells with the same non-zero key:
## [first ijk, last ijk, key] for each box.
static func _merge(n: Vector3i, key_of: Callable) -> Array:
	var count := n.x * n.y * n.z
	var keys := PackedInt32Array()
	keys.resize(count)
	for c in count:
		keys[c] = key_of.call(c)
	var used := PackedByteArray()
	used.resize(count)
	var at := func(i: int, j: int, k: int) -> int: return i + n.x * (j + n.y * k)
	var boxes := []
	for k in n.z:
		for j in n.y:
			for i in n.x:
				var c: int = at.call(i, j, k)
				var key := keys[c]
				if key == 0 or used[c] == 1:
					continue
				var i2 := i
				while i2 + 1 < n.x and keys[at.call(i2 + 1, j, k)] == key and used[at.call(i2 + 1, j, k)] == 0:
					i2 += 1
				var j2 := j
				while j2 + 1 < n.y:
					var ok := true
					for x in range(i, i2 + 1):
						var cc: int = at.call(x, j2 + 1, k)
						if keys[cc] != key or used[cc] == 1:
							ok = false
							break
					if not ok:
						break
					j2 += 1
				var k2 := k
				while k2 + 1 < n.z:
					var ok := true
					for y in range(j, j2 + 1):
						for x in range(i, i2 + 1):
							var cc: int = at.call(x, y, k2 + 1)
							if keys[cc] != key or used[cc] == 1:
								ok = false
								break
						if not ok:
							break
					if not ok:
						break
					k2 += 1
				for z in range(k, k2 + 1):
					for y in range(j, j2 + 1):
						for x in range(i, i2 + 1):
							used[at.call(x, y, z)] = 1
				boxes.append([Vector3i(i, j, k), Vector3i(i2, j2, k2), key])
	return boxes


# ---------------------------------------------------------------------------
# Killcams (see MapReplay): the walls as they were. Only what is drawn changes: the
# collision stays the live one (the match goes on round a death killcam).

## Every cell that is not whole, as [cells, stages]: the same array until one changes.
func replay_capture() -> Variant:
	if _captured_rev != _revision:
		_captured = snapshot()
		_captured_rev = _revision
	return _captured


## Draws the cells as `state` (a replay_capture()) has them. A cell that breaks as the
## replay plays on crashes and drops its rubble, as it did in the match.
func replay_show(state: Variant, _next: Variant, _u: float, _holder: Node3D) -> void:
	if not state is Array or (state as Array).size() < 2 or (_replaying and is_same(state, _replay_of)):
		return
	_replay_of = state
	var want := {}
	var ids: PackedInt32Array = state[0]
	var stages: PackedByteArray = state[1]
	for i in mini(ids.size(), stages.size()):
		if ids[i] >= 0 and ids[i] < cells.size():
			want[ids[i]] = int(stages[i])
	var before := _replay if _replaying else _live_damage()
	var touched := {}
	var broke := PackedInt32Array()
	for c in want:
		var was := int(before.get(c, 0))
		if int(want[c]) != was:
			touched[cells[c].panel] = true
			if _replaying and int(want[c]) >= BROKEN and was < BROKEN:
				broke.append(c)
	for c in before:
		if not want.has(c):
			touched[cells[c].panel] = true
	if _replaying and touched.is_empty():
		return
	_replaying = true
	_replay = want
	for p in touched:
		_rebuild_meshes(p)
	if not broke.is_empty():
		_break_effects(broke)


## Back to drawing the live damage.
func replay_clear() -> void:
	if not _replaying:
		return
	var shown := _replay
	_replaying = false
	_replay = {}
	_replay_of = null
	var touched := {}
	for c in shown:
		if int(shown[c]) != int(cells[c].stage):
			touched[cells[c].panel] = true
	for c in _live_damage():
		if int(shown.get(c, 0)) != int(cells[c].stage):
			touched[cells[c].panel] = true
	for p in touched:
		_rebuild_meshes(p)


func _live_damage() -> Dictionary:
	var out := {}
	for c in cells.size():
		if cells[c].stage != 0:
			out[c] = int(cells[c].stage)
	return out


# ---------------------------------------------------------------------------
# Rubble and sound

func _break_effects(broke: PackedInt32Array) -> void:
	for c in broke:
		var at := cell_center(c)
		var mat := material_of(c)
		var sound := get_node_or_null("/root/Sound")   # (not there in map-only tests)
		var info := BlockMaterials.info(mat)
		if sound:
			var p = sound.play_at(info.break, at, "body", 0.0, 0.08)
			if p:
				p.pitch_scale *= info.break_pitch
		if DisplayServer.get_name() == "headless":
			continue
		_rubble(c, mat)


func _rubble(c: int, mat: String) -> void:
	var panel: Dictionary = panels[cells[c].panel]
	var box := cell_box(c)
	var info := BlockMaterials.info(mat)
	var shards: bool = info.shards
	# A whole block can be much bigger than a cell: more bits, up to three times.
	var count := int(info.debris * clampf(box.get_volume() / (CELL * CELL * 0.3), 1.0, 3.0))
	var material := root.material_for(panel.kind)
	for i in count:
		if _debris >= MAX_DEBRIS:
			return
		var bit := RigidBody3D.new()
		bit.collision_layer = 0
		bit.collision_mask = 1   # lands on the level, never on players
		var mesh := MeshInstance3D.new()
		var shape := BoxMesh.new()
		var thick: float = (panel.size as Vector3)[panel.thin]
		var s := randf_range(0.07, 0.2) * CELL
		shape.size = Vector3(s, s, s) * Vector3(randf_range(0.5, 1.0), randf_range(0.5, 1.0), randf_range(0.5, 1.0))
		if shards:
			shape.size.y = maxf(thick, 0.03)   # flat shards
		else:
			shape.size = shape.size.min(Vector3.ONE * maxf(thick, 0.1) * 1.5)
		mesh.mesh = shape
		mesh.material_override = material
		bit.add_child(mesh)
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = shape.size
		col.shape = bs
		bit.add_child(col)
		add_child(bit)
		bit.global_position = Vector3(randf_range(box.position.x, box.end.x), randf_range(box.position.y, box.end.y), randf_range(box.position.z, box.end.z))
		bit.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		bit.linear_velocity = Vector3(randf_range(-2.5, 2.5), randf_range(0.5, 3.5), randf_range(-2.5, 2.5))
		bit.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		_debris += 1
		var tween := bit.create_tween()
		tween.tween_interval(randf_range(2.0, 3.0))
		tween.tween_property(mesh, "scale", Vector3.ONE * 0.01, 0.4)
		tween.tween_callback(func():
			_debris -= 1
			bit.queue_free())
	_dust(box.get_center(), mat)


func _dust(at: Vector3, mat: String) -> void:
	var puff := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = CELL * 0.3
	sphere.height = CELL * 0.6
	sphere.radial_segments = 10
	sphere.rings = 5
	puff.mesh = sphere
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = BlockMaterials.info(mat).dust
	puff.material_override = m
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(puff)
	puff.global_position = at
	var tween := puff.create_tween().set_parallel()
	tween.tween_property(puff, "scale", Vector3.ONE * 1.8, 0.9)
	tween.tween_property(puff, "transparency", 1.0, 0.9)
	tween.chain().tween_callback(puff.queue_free)
