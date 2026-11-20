@tool
extends RefCounted
## What the map tools share: the map being edited, the grid size, the kind new
## blocks get, and ways to ask what is selected and to make a change. The plugin
## fills in `selection`, `commit` and `select`; the tests fill in their own, so the
## tools run without the editor.

const MapOps := preload("res://addons/map_tools/map_ops.gd")

## The grid size, the kind or the map changed (the toolbar and the dock redraw).
signal changed

## The map being edited (the open scene's root), or null.
var map: MapRoot:
	set(v):
		map = v
		has_last = false
		touch()
		changed.emit()

## The grid everything snaps to (metres).
var grid := 0.5:
	set(v):
		grid = v
		changed.emit()

## The kind a drawn block gets.
var kind := "concrete":
	set(v):
		kind = v
		changed.emit()

## Editor view: leave out blocks that are drawn only (set with the plugin's switch).
var solid_only := false

## The Vertex tool is on: blocks show no face handles (block_gizmo.gd).
var editing_corners := false

## () -> Array of the selected nodes.
var selection := Callable()
## (MapEdit): make this change (as one undo step, in the editor).
var commit := Callable()
## (Array of nodes): select these, outside any undo step.
var select := Callable()

## The last block drawn: a view from the side gives the next one the same depth.
var last_box := AABB()
var has_last := false

var _cache := []      # [{block, xf, half}]: every block you can see
var _cache_ok := false


## Something in the scene changed: look the blocks up again next time.
func touch() -> void:
	_cache_ok = false


func selected() -> Array:
	return selection.call() if selection.is_valid() else []


## The selected nodes with nothing that is inside another selected node, and never
## the map itself.
func selected_tops() -> Array[Node3D]:
	var tops := MapOps.top_level(selected())
	tops.erase(map)
	return tops


## Every block that is selected or inside something selected.
func selected_blocks() -> Array[MapBlock]:
	var out: Array[MapBlock] = []
	for n in selected_tops():
		out.append_array(MapOps.blocks_in(n))
	return out


## Every block the editor is showing: [{block, xf, half}] (see MapOps.box_of).
func blocks() -> Array:
	if not _cache_ok:
		_cache = []
		if map:
			_gather(map)
		_cache_ok = true
	return _cache


func _gather(node: Node) -> void:
	for c in node.get_children():
		if c is Node3D and not (c as Node3D).visible:
			continue
		if c is MapBlock:
			var b := c as MapBlock
			if (b.drawn or map.show_invisible_blocks) and (b.solid or not solid_only):
				var box := MapOps.box_of(b)
				_cache.append({"block": b, "xf": box[0], "half": box[1]})
		_gather(c)


## The nearest block a ray hits: {block, xf, half, point, normal (which way the face
## hit looks, in the map), axis, side}. Empty if none. `among`: only these blocks.
func pick(origin: Vector3, dir: Vector3, among: Array = []) -> Dictionary:
	var best := {}
	var best_t := INF
	for e in blocks():
		if not among.is_empty() and e.block not in among:
			continue
		var hit := MapOps.ray_box(origin, dir, e.xf, e.half)
		if hit.is_empty() or hit[0] >= best_t:
			continue
		best_t = hit[0]
		var n := Vector3.ZERO
		n[hit[1]] = hit[2]
		best = {"block": e.block, "xf": e.xf, "half": e.half, "point": origin + dir * best_t,
			"normal": (e.xf as Transform3D).basis * n, "axis": hit[1], "side": hit[2]}
	return best


## The node a click on `node` selects, as the editor's own pick would choose: the
## top of a selection group, the whole of a scene placed in the map; null if locked.
func selectable(node: Node) -> Node:
	if map == null or not map.is_ancestor_of(node):
		return null
	var result := node
	var it := node
	while it.owner and it.owner != map:
		if not map.is_editable_instance(it.owner):
			result = it.owner
		it = it.owner
	var up := result
	while up and up != map:
		if up.get_meta("_edit_group_", false):
			result = up
		up = up.get_parent()
	if result.get_meta("_edit_lock_", false):
		return null
	return result


## A click that a tool took for itself but that was only a click: select the block
## under it as the editor's own click would (`adding`, Shift: add it to the
## selection). Nothing under it: select nothing.
func click_select(origin: Vector3, dir: Vector3, adding: bool) -> void:
	var hit := pick(origin, dir)
	if hit.is_empty():
		if not adding:
			select.call([])
		return
	var node := selectable(hit.block)
	if node == null:
		return
	var chosen: Array = selected() if adding else []
	if node not in chosen:
		chosen.append(node)
	select.call(chosen)


## Where a new block goes: beside the first selected node, else under the map.
func new_parent() -> Node:
	var sel := selected()
	if map and not sel.is_empty() and sel[0] != map and map.is_ancestor_of(sel[0]):
		var p: Node = (sel[0] as Node).get_parent()
		while p != map and (p is MapBlock or p is MapPiece or p.has_meta(MapPiece.GENERATED)):
			p = p.get_parent()
		return p
	return map


## How deep a block drawn in a top, front or side view is, and where: [from, to]
## along the axis the view looks along. Taken from the selection, else from the last
## block drawn, else one grid square standing on zero.
func depth(axis: int) -> Vector2:
	var blocks_now := selected_blocks()
	if not blocks_now.is_empty():
		var box := MapOps.bounds_of(blocks_now)
		return Vector2(box.position[axis], box.end[axis])
	if has_last:
		return Vector2(last_box.position[axis], last_box.end[axis])
	return Vector2(0.0, maxf(grid, 1.0))
