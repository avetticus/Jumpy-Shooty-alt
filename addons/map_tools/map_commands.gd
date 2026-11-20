@tool
extends RefCounted
## The map tools' one-shot commands (the Map menu, the dock, the quick toggles): each
## looks at what is selected and returns the change to make as a MapEdit, which may
## be empty if there is nothing to do.

const MapOps := preload("res://addons/map_tools/map_ops.gd")
const MapEdit := preload("res://addons/map_tools/map_edit.gd")

const PIECES := ["Stairs", "Row", "Ring"]


## Each selected box becomes a room of walls `thickness` thick.
static func hollow(ctx: RefCounted, thickness: float, open_top: bool, no_floor: bool) -> RefCounted:
	var edit := MapEdit.new()
	edit.name = "Hollow map block"
	for n in ctx.selected():
		if not (n is MapBlock):
			continue
		var room := MapOps.hollow(n, thickness, open_top, no_floor)
		if room == null:
			continue
		edit.removes.append(n)
		edit.adds.append([(n as Node).get_parent(), room, (n as Node).get_index()])
		edit.select.append(room)
	edit.reselect = not edit.select.is_empty()
	return edit


## How many of the selected nodes Hollow would change.
static func hollowable(ctx: RefCounted, thickness: float) -> int:
	var count := 0
	for n in ctx.selected():
		if n is MapBlock and MapOps.can_hollow(n, thickness):
			count += 1
	return count


## Mirrors the selection across the plane through `pivot` facing along `axis` (0 x,
## 2 z). `copy`: leave the originals and add mirrored copies beside them.
static func mirror(ctx: RefCounted, axis: int, pivot: Vector3, copy: bool) -> RefCounted:
	var edit := MapEdit.new()
	edit.name = "Mirror map blocks"
	for n in ctx.selected_tops():
		if copy:
			var dup := MapOps.mirrored_copy(n, axis, pivot)
			edit.adds.append([n.get_parent(), dup, -1])
			edit.select.append(dup)
		else:
			for step in MapOps.mirror_plan(n, axis, pivot):
				edit.sets.append([step[0], "transform", step[1], (step[0] as Node3D).transform])
			for hull in MapOps.hulls_in(n):
				edit.sets.append([hull, "points", MapOps.mirrored_points(hull), hull.points])
	edit.reselect = copy and not edit.select.is_empty()
	return edit


## Each selected block becomes hull blocks of the same shape, whose corners can be
## edited (MapOps.make_editable). Blocks already hulls, blocks a piece made, and
## shapes with too many corners are left as they are.
static func make_editable(ctx: RefCounted) -> RefCounted:
	var edit := MapEdit.new()
	edit.name = "Make map blocks editable"
	for b: MapBlock in ctx.selected_blocks():
		if b.has_meta(MapPiece.GENERATED):
			continue
		var made := MapOps.make_editable(b)
		if made == null:
			continue
		edit.removes.append(b)
		edit.adds.append([b.get_parent(), made, b.get_index()])
		edit.select.append(made)
	edit.reselect = not edit.select.is_empty()
	return edit


## The middle of the selection (for a mirror about itself).
static func selection_centre(ctx: RefCounted) -> Vector3:
	return MapOps.bounds_of(ctx.selected_tops()).get_center()


## `copies` copies of the selection in a line, `offset` apart.
static func array_line(ctx: RefCounted, copies: int, offset: Vector3) -> RefCounted:
	var edit := MapEdit.new()
	edit.name = "Array map blocks"
	for n in ctx.selected_tops():
		for dup in MapOps.array_line(n, copies, offset):
			edit.adds.append([n.get_parent(), dup, -1])
			edit.select.append(dup)
	edit.select.append_array(ctx.selected_tops())
	edit.reselect = not edit.adds.is_empty()
	return edit


## Copies of the selection round the upright line through `pivot`, `total` in all.
static func array_ring(ctx: RefCounted, total: int, pivot: Vector3) -> RefCounted:
	var edit := MapEdit.new()
	edit.name = "Array map blocks round a circle"
	for n in ctx.selected_tops():
		for dup in MapOps.array_ring(n, total, pivot):
			edit.adds.append([n.get_parent(), dup, -1])
			edit.select.append(dup)
	edit.select.append_array(ctx.selected_tops())
	edit.reselect = not edit.adds.is_empty()
	return edit


## Turns Solid, Drawn or Breakable on or off for every selected block: off if they are all on,
## else on.
static func toggle(ctx: RefCounted, property: String) -> RefCounted:
	var edit := MapEdit.new()
	edit.name = "Toggle map block %s" % property
	var blocks: Array[MapBlock] = ctx.selected_blocks()
	var all_on := not blocks.is_empty()
	for b in blocks:
		all_on = all_on and b.get(property)
	for b in blocks:
		if b.get(property) == all_on:
			edit.sets.append([b, property, not all_on, all_on])
			edit.do_calls.append([b, "refresh_preview"])
			edit.undo_calls.append([b, "refresh_preview"])
	return edit


## Gives every selected block this kind.
static func paint(ctx: RefCounted, kind: String) -> RefCounted:
	var edit := MapEdit.new()
	edit.name = "Paint map blocks %s" % kind
	for b: MapBlock in ctx.selected_blocks():
		if b.kind != kind and not b.has_meta(MapPiece.GENERATED):
			edit.sets.append([b, "kind", kind, b.kind])
	return edit


## Nudges each selected thing (up to one grid square) so its faces meet its
## neighbours'.
static func snap_to_neighbours(ctx: RefCounted) -> RefCounted:
	var edit := MapEdit.new()
	edit.name = "Snap map blocks to neighbours"
	var tops: Array[Node3D] = ctx.selected_tops()
	var moving: Array[MapBlock] = ctx.selected_blocks()
	var rest := []
	for e in ctx.blocks():
		if e.block not in moving:
			rest.append(e.block)
	for n in tops:
		var mine := MapOps.blocks_in(n)
		if mine.is_empty():
			continue
		var frame := Transform3D((MapOps.box_of(mine[0])[0] as Transform3D).basis, Vector3.ZERO)
		var boxes := MapOps.boxes_in_frame(frame, mine)
		var box := boxes[0]
		for b in boxes:
			box = box.merge(b)
		var move: Vector3 = MapOps.snap_move(box, MapOps.boxes_in_frame(frame, rest), ctx.grid)[0]
		if move.is_zero_approx():
			continue
		var to: Vector3 = n.position + MapOps.parent_global(n).basis.inverse() * (frame.basis * move)
		edit.sets.append([n, "position", to, n.position])
	return edit


## A new piece of the given sort ("Stairs": stairs or a ramp; "Row"; "Ring") with its blocks
## made, not yet in the scene.
static func new_piece(sort: String, kind: String) -> MapPiece:
	var piece: MapPiece
	match sort:
		"Stairs":
			piece = MapStairs.new()
			piece.kind = kind
		"Row":
			piece = MapRow.new()
			piece.add_child(_first(kind, Vector3(0.3, 1.2, 0.3), Vector3(0, 0.6, 0), "Post"))
		"Ring":
			piece = MapRing.new()
			piece.add_child(_first(kind, Vector3(1, 3, 1), Vector3(0, 1.5, -4), "Pillar"))
		_:
			return null
	piece.name = sort
	piece.set_meta("_edit_group_", true)
	piece.rebuild()
	return piece


static func _first(kind: String, size: Vector3, at: Vector3, block_name: String) -> MapBlock:
	var b := MapBlock.new()
	b.name = block_name
	b.kind = kind
	b.size = size
	b.position = at
	return b


## Turns a piece into a plain group of blocks you can edit by hand.
static func bake(piece: MapPiece) -> RefCounted:
	var edit := MapEdit.new()
	edit.name = "Bake %s" % piece.name
	var script: Script = piece.get_script()
	edit.undo_calls.append([piece, "set_script", script])
	for p in piece.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_STORAGE:
			edit.undo_calls.append([piece, "set", p.name, piece.get(p.name)])
	edit.undo_calls.append([piece, "set", "_live", true])
	for c in piece.generated():
		edit.do_calls.append([c, "remove_meta", MapPiece.GENERATED])
		edit.undo_calls.append([c, "set_meta", MapPiece.GENERATED, true])
	edit.do_calls.append([piece, "set_script", null])
	return edit
