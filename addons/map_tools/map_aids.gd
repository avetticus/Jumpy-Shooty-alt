@tool
extends RefCounted
## What the map tools draw over the 3D view to help, whatever tool is on (each can be
## turned off in the Map menu):
##  - the grid at its current size on the surface under the mouse (or the ground),
##    fading out round the cursor;
##  - the edges of the selected blocks, over everything, so a block behind another or
##    inside one can be seen;
##  - from every terminal (and lever) a line to the event it sets off, or, when the
##    event has no place in the map, its name beside the terminal (red if it is missing).

const MapOps := preload("res://addons/map_tools/map_ops.gd")

const GRID := Color(1.0, 1.0, 1.0, 0.55)
const EDGES := Color(1.0, 0.55, 0.2, 0.9)
const LINK := Color(0.45, 0.85, 1.0, 0.9)
const BROKEN := Color(1.0, 0.3, 0.25, 0.95)
const GRID_CELLS := 6         # how many grid squares the patch reaches each way
const MOST_EDGES := 400       # selected blocks past this many are not outlined (too slow)

static var _edge_cache := {}  # block instance id -> [its points as they were, its edges]


## The grid lines on the surface through `point` facing `normal`, around `point`:
## [[from, to, how strong 0..1], ...]. On a surface square to the map they lie on the
## map's grid; on any other, on a grid in the surface's own directions through `point`.
static func grid_lines(point: Vector3, normal: Vector3, step: float, cells: int = GRID_CELLS) -> Array:
	var out := []
	if step <= 0.0:
		return out
	var axis := normal.abs().max_axis_index()
	var u := Vector3.ZERO
	var v := Vector3.ZERO
	var origin := point
	if absf(normal[axis]) > 0.999:
		u[(axis + 1) % 3] = 1.0
		v[(axis + 2) % 3] = 1.0
		origin = MapOps.snap_v(point, step)
		origin[axis] = point[axis]
	else:
		u = normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
		v = normal.cross(u)
	var reach := step * cells
	for i in range(-cells, cells + 1):
		var strength := 1.0 - absf(float(i)) / float(cells + 1)
		for pair in [[u, v], [v, u]]:
			var across: Vector3 = pair[0]
			var along: Vector3 = pair[1]
			var at := origin + across * (i * step)
			out.append([at - along * reach, at + along * reach, strength])
	return out


## The edges of a block in the map: [[from, to], ...] (a hull's own edges, else the
## box round it).
static func block_edges(block: MapBlock) -> Array:
	var xf := MapOps.global_of(block)
	var out := []
	if block.shape == MapBlock.Shape.HULL:
		var id := block.get_instance_id()
		var cached: Array = _edge_cache.get(id, [])
		if cached.is_empty() or cached[0] != block.points:
			cached = [block.points.duplicate(), MapOps.hull_edges(block.points)]
			_edge_cache[id] = cached
		for e in cached[1]:
			out.append([xf * (e[0] as Vector3), xf * (e[1] as Vector3)])
		return out
	var box := MapOps.box_of(block)
	var bxf: Transform3D = box[0]
	var h: Vector3 = box[1]
	var c := []
	for i in 8:
		c.append(bxf * Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	for pair in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		out.append([c[pair[0]], c[pair[1]]])
	return out


## Every terminal in the map and what it sets off: [{terminal, to (a place in the map,
## or null), name, missing: true if its event cannot be found}].
static func links(map: Node) -> Array:
	var out := []
	for t in map.find_children("*", "MapTerminal", true, false):
		var terminal := t as MapTerminal
		var path: NodePath = terminal.event
		var event: Node = terminal.get_node_or_null(path) if not path.is_empty() else null
		out.append({"terminal": terminal, "to": MapOps.global_of(event).origin if event is Node3D else null,
			"name": String(event.name) if event else String(path), "missing": event == null})
	return out


static func draw_grid(view: RefCounted, overlay: Control, ctx: RefCounted, mouse: Variant) -> void:
	if mouse == null:
		return
	var origin: Vector3 = view.origin(mouse)
	var dir: Vector3 = view.normal(mouse)
	var hit: Dictionary = ctx.pick(origin, dir)
	var point: Variant = null
	var normal := Vector3.UP
	if hit.is_empty():
		point = view.on_plane(mouse, 1, 0.0)
	else:
		point = hit.point
		normal = hit.normal
	if point == null:
		return
	var lift: Vector3 = (normal as Vector3) * 0.003   # (just off the surface)
	for line in grid_lines(point, normal, ctx.grid):
		view.draw_line(overlay, (line[0] as Vector3) + lift, (line[1] as Vector3) + lift, Color(GRID, GRID.a * float(line[2])), 1.0)


static func draw_selected_edges(view: RefCounted, overlay: Control, ctx: RefCounted) -> void:
	var blocks: Array = ctx.selected_blocks()
	if blocks.size() > MOST_EDGES:
		return
	for b: MapBlock in blocks:
		for e in block_edges(b):
			view.draw_line(overlay, e[0], e[1], EDGES, 1.5)


static func draw_links(view: RefCounted, overlay: Control, map: Node) -> void:
	var font := overlay.get_theme_default_font()
	var size := overlay.get_theme_default_font_size()
	for link in links(map):
		var from: Vector3 = MapOps.global_of(link.terminal).origin + Vector3(0, 1.0, 0)
		if view.behind(from):
			continue
		if link.to != null:
			view.draw_line(overlay, from, link.to, LINK, 2.0)
		else:
			overlay.draw_string(font, view.screen(from) + Vector2(10, -6), ("▶ missing: %s" if link.missing else "▶ %s") % link.name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, BROKEN if link.missing else LINK)
