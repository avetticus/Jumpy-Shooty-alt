@tool
extends RefCounted
## The Vertex tool: move the corners of hull blocks (MapBlock.Shape.HULL; Map > Make
## Editable turns any block into them).
##
## The selected hull blocks show their edges and corners. Click a corner to pick it
## (Shift: add it, or take it away), or drag a box round several. Corners of
## different blocks in the same place are picked, and move, together. Drag a picked
## corner to move them all, snapped to the grid: level in the 3D view (hold Shift for
## up and down), in the view's plane in a top, front or side view. The arrow keys
## move them a grid square across the view, Page Up and Page Down up and down. Delete
## takes them away. Double-click an edge to add a corner in its middle, or a face to
## add one in its middle; then drag it out.
##
## A hull is always convex: a move that would dent it (a corner sunk inside), or
## flatten it, is refused (drawn red). A corner another one's move leaves inside the
## shape is dropped. A click away from every corner selects a block as usual. Each
## drag, nudge, add or delete is one undo step.

const MapOps := preload("res://addons/map_tools/map_ops.gd")
const MapEdit := preload("res://addons/map_tools/map_edit.gd")

const CORNER := Color(1.0, 0.6, 0.15)
const PICKED := Color(1.0, 1.0, 0.35)
const EDGE := Color(1.0, 0.75, 0.35, 0.85)
const BAD := Color(1.0, 0.25, 0.2)
const REACH := 8.0        # how near a corner a click must be (pixels)
const EDGE_REACH := 6.0   # and an edge, for a double-click
const CLICK := 4.0        # a press that moves less than this (pixels) is a click
const SAME := 0.001       # corners this close (metres) are in the same place

enum Phase { IDLE, PRESS, DRAG, BAND }

var ctx: RefCounted   # MapContext
var phase := Phase.IDLE
## The picked corners: [[block, index into its points], ...].
var picked := []

var _press := Vector2.ZERO
var _now := Vector2.ZERO
var _adding := false       # Shift was held at the press
var _press_hit := []       # the corner pressed on: [block, index], or empty
var _grab := Vector3.ZERO  # where that corner was, in the map
var _view_axis := -1       # the axis the view looks along (-1: a 3D view)
var _start := {}           # block -> [points, position] before the drag
var _moved := Vector3.ZERO # how far the shape shown has been moved (the last allowed move)
var _refused := false


func busy() -> bool:
	return phase != Phase.IDLE


func cancel() -> void:
	if phase == Phase.DRAG:
		_restore()
	phase = Phase.IDLE
	_refused = false


## The selected hull blocks.
func hulls() -> Array[MapBlock]:
	return ctx.selected_blocks().filter(func(b: MapBlock) -> bool: return b.shape == MapBlock.Shape.HULL)


func input(view: RefCounted, event: InputEvent) -> bool:
	_tidy()
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	var key := event as InputEventKey
	if key and key.pressed:
		return _key(view, key)
	match phase:
		Phase.IDLE:
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not mb.alt_pressed and not mb.is_command_or_control_pressed():
				if mb.double_click and _add_point(view, mb.position):
					return true
				return _begin(view, mb.position, mb.shift_pressed)
		Phase.PRESS:
			if mm:
				_now = mm.position
				if _now.distance_to(_press) >= CLICK:
					if _press_hit.is_empty():
						phase = Phase.BAND
					elif _is_picked(_press_hit[0], _press_hit[1]):
						_start_drag()
						_drag(view, mm.position, mm.shift_pressed)
					else:
						phase = Phase.IDLE   # Shift-clicked off: nothing to drag
				return true
			if mb and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				if _press_hit.is_empty():
					_click_select(view, mb.position, _adding)
				phase = Phase.IDLE
				return true
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				phase = Phase.IDLE
				return true
		Phase.DRAG:
			if mm:
				_drag(view, mm.position, mm.shift_pressed)
				return true
			if mb and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				_finish_drag()
				return true
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				cancel()
				return true
		Phase.BAND:
			if mm:
				_now = mm.position
				return true
			if mb and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				_now = mb.position
				_band_select(view)
				phase = Phase.IDLE
				return true
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				phase = Phase.IDLE
				return true
	return false


# ---------------------------------------------------------------------------
# Picking corners

func _begin(view: RefCounted, pos: Vector2, adding: bool) -> bool:
	_press = pos
	_now = pos
	_adding = adding
	_press_hit = _corner_at(view, pos)
	_view_axis = view.ortho_axis()
	if not _press_hit.is_empty():
		var b: MapBlock = _press_hit[0]
		_grab = MapOps.global_of(b) * b.points[_press_hit[1]]
		var together := _at(_grab)
		if adding:
			if _is_picked(b, _press_hit[1]):
				picked = picked.filter(func(c: Array) -> bool: return not together.any(func(t: Array) -> bool: return t[0] == c[0] and t[1] == c[1]))
			else:
				picked.append_array(together)
		elif not _is_picked(b, _press_hit[1]):
			picked = together
	phase = Phase.PRESS
	return true


## The corner nearest the mouse (on screen, within REACH), nearest the camera if
## several are: [block, index], or [].
func _corner_at(view: RefCounted, pos: Vector2) -> Array:
	var best := []
	var best_d := REACH
	var best_far := INF
	for b in hulls():
		var xf := MapOps.global_of(b)
		for i in b.points.size():
			var w := xf * b.points[i]
			if view.behind(w):
				continue
			var d: float = (view.screen(w) as Vector2).distance_to(pos)
			var far: float = (view.camera as Camera3D).global_position.distance_to(w)
			if d < best_d - 0.5 or (d <= best_d + 0.5 and far < best_far):
				best = [b, i]
				best_d = minf(d, best_d)
				best_far = far
	return best


## Every corner of the selected hull blocks at `world` (in the map).
func _at(world: Vector3) -> Array:
	var out := []
	for b in hulls():
		var xf := MapOps.global_of(b)
		for i in b.points.size():
			if (xf * b.points[i]).distance_to(world) <= SAME:
				out.append([b, i])
	return out


func _is_picked(b: MapBlock, i: int) -> bool:
	return picked.any(func(c: Array) -> bool: return c[0] == b and c[1] == i)


## Leaves out picked corners of blocks no longer selected (or gone).
func _tidy() -> void:
	if picked.is_empty():
		return
	var mine := hulls()
	picked = picked.filter(func(c: Array) -> bool:
		return is_instance_valid(c[0]) and c[0] in mine and c[1] < (c[0] as MapBlock).points.size())


func _band_select(view: RefCounted) -> void:
	var rect := Rect2(_press, _now - _press).abs()
	if not _adding:
		picked = []
	for b in hulls():
		var xf := MapOps.global_of(b)
		for i in b.points.size():
			var w := xf * b.points[i]
			if not view.behind(w) and rect.has_point(view.screen(w)) and not _is_picked(b, i):
				picked.append([b, i])


## A click away from the corners: select the block under it, as the editor would
## (Shift: add it to the selection). Nothing under it: select nothing.
func _click_select(view: RefCounted, pos: Vector2, adding: bool) -> void:
	var hit: Dictionary = ctx.pick(view.origin(pos), view.normal(pos))
	if not adding:
		picked = []
	if hit.is_empty():
		if not adding:
			ctx.select.call([])
		return
	var node: Node = ctx.selectable(hit.block)
	if node == null:
		return
	var chosen: Array = ctx.selected() if adding else []
	if node not in chosen:
		chosen.append(node)
	ctx.select.call(chosen)


# ---------------------------------------------------------------------------
# Moving corners

func _start_drag() -> void:
	_start = _snapshot()
	_moved = Vector3.ZERO
	_refused = false
	phase = Phase.DRAG


## [points, position] of every block with a picked corner.
func _snapshot() -> Dictionary:
	var out := {}
	for c in picked:
		var b: MapBlock = c[0]
		if not out.has(b):
			out[b] = [b.points.duplicate(), b.position]
	return out


func _drag(view: RefCounted, pos: Vector2, vertical: bool) -> void:
	var target := _grab
	var grid: float = ctx.grid
	if _view_axis >= 0:
		var p: Variant = view.on_plane(pos, _view_axis, _grab[_view_axis])
		if p == null:
			return
		target = MapOps.snap_v(p, grid)
		target[_view_axis] = _grab[_view_axis]
	elif vertical:
		target.y = MapOps.snap(_grab.y + view.along_line(pos, _grab, Vector3.UP), grid)
	else:
		var p: Variant = view.on_plane(pos, 1, _grab.y)
		if p == null:
			return
		target = MapOps.snap_v(p, grid)
		target.y = _grab.y
	var shapes := _shapes(target - _grab, _start)
	_refused = shapes.is_empty()
	if _refused:
		return   # the shape stays at the last move that was allowed
	_moved = target - _grab
	for b: MapBlock in shapes:
		b.points = shapes[b][0]
		b.position = shapes[b][1]
	ctx.touch()


## Every block with a picked corner, those corners moved `delta` (in the map) from
## where they are in `from` (block -> [points, position]): block -> [centred points,
## position]. Empty if any block refuses the move.
func _shapes(delta: Vector3, from: Dictionary) -> Dictionary:
	var moves := {}   # block -> {index: where it goes, in the block's own frame}
	for c in picked:
		var b: MapBlock = c[0]
		if not from.has(b):
			continue
		var xf := _frame(b, from[b][1])
		if not moves.has(b):
			moves[b] = {}
		moves[b][c[1]] = xf.affine_inverse() * (xf * (from[b][0] as PackedVector3Array)[c[1]] + delta)
	var out := {}
	for b: MapBlock in moves:
		var pts := MapOps.reshaped(from[b][0], moves[b])
		if pts.is_empty():
			return {}
		out[b] = MapOps.hull_placement(b, pts, from[b][1])
	return out


## Where a block's own frame is in the map with the block at `at`.
func _frame(b: MapBlock, at: Vector3) -> Transform3D:
	return MapOps.parent_global(b) * Transform3D(b.transform.basis, at)


func _restore() -> void:
	for b: MapBlock in _start:
		if is_instance_valid(b):
			b.points = _start[b][0]
			b.position = _start[b][1]
	ctx.touch()


func _finish_drag() -> void:
	phase = Phase.IDLE
	_refused = false
	if _moved.is_zero_approx():
		_restore()
		return
	var now := _snapshot()
	var wanted := _picked_places(_start, _moved)
	_commit("Move hull corners", now, _start)
	_repick(wanted)


## Where the picked corners are (in the map, from the state `from`), plus `delta`.
func _picked_places(from: Dictionary, delta: Vector3) -> Array:
	var out := []
	for c in picked:
		var b: MapBlock = c[0]
		if from.has(b):
			out.append(_frame(b, from[b][1]) * (from[b][0] as PackedVector3Array)[c[1]] + delta)
	return out


func _repick(places: Array) -> void:
	picked = []
	for w: Vector3 in places:
		for c in _at(w):
			if not _is_picked(c[0], c[1]):
				picked.append(c)


## Makes the change from `before` to `after` (block -> [points, position]) one step.
func _commit(title: String, after: Dictionary, before: Dictionary) -> void:
	var edit := MapEdit.new()
	edit.name = title
	for b: MapBlock in after:
		edit.sets.append([b, "points", after[b][0], before[b][0]])
		edit.sets.append([b, "position", after[b][1], before[b][1]])
	ctx.commit.call(edit)


# ---------------------------------------------------------------------------
# Keys: nudge, delete

func _key(view: RefCounted, key: InputEventKey) -> bool:
	if busy():
		if key.keycode == KEY_ESCAPE:
			cancel()
			return true
		return false
	if picked.is_empty() or key.alt_pressed or key.is_command_or_control_pressed():
		return false
	match key.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			_delete()
			return true
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN:
			_nudge(_arrow(view, key.keycode) * ctx.grid)
			return true
	return false


## Which way an arrow key moves corners in this view: the map axis nearest to the
## view's right (or up, or forward), so they always move along the grid.
func _arrow(view: RefCounted, keycode: int) -> Vector3:
	match keycode:
		KEY_PAGEUP:
			return Vector3.UP
		KEY_PAGEDOWN:
			return Vector3.DOWN
	var basis: Basis = (view.camera as Camera3D).global_basis
	var axis: int = view.ortho_axis()
	var skip := axis if axis >= 0 else 1
	var right := _nearest_axis(basis.x, skip)
	var up := _nearest_axis(basis.y if axis >= 0 else -basis.z, skip)
	match keycode:
		KEY_RIGHT: return right
		KEY_LEFT: return -right
		KEY_UP: return up
	return -up


static func _nearest_axis(v: Vector3, skip: int) -> Vector3:
	v[skip] = 0.0
	if v.is_zero_approx():
		return Vector3.ZERO
	var a := v.abs().max_axis_index()
	var out := Vector3.ZERO
	out[a] = signf(v[a])
	return out


func _nudge(delta: Vector3) -> void:
	if delta.is_zero_approx():
		return
	var before := _snapshot()
	var wanted := _picked_places(before, delta)
	var shapes := _shapes(delta, before)
	if shapes.is_empty():
		return   # refused: it would not be convex
	_commit("Nudge hull corners", shapes, before)
	_repick(wanted)


func _delete() -> void:
	var before := _snapshot()
	var after := {}
	for b: MapBlock in before:
		var gone := []
		for c in picked:
			if c[0] == b:
				gone.append(c[1])
		var rest := MapOps.without_points(before[b][0], gone)
		if rest.is_empty():
			return   # too few corners left for a solid shape: nothing is taken away
		after[b] = MapOps.hull_placement(b, rest, before[b][1])
	picked = []
	_commit("Delete hull corners", after, before)


# ---------------------------------------------------------------------------
# Adding a corner

## A double-click on an edge adds a corner in its middle; on a face, in the
## face's middle. False if it was on neither.
func _add_point(view: RefCounted, pos: Vector2) -> bool:
	var best_b: MapBlock = null
	var best_p := Vector3.ZERO   # in the block's own frame
	var best_d := EDGE_REACH
	for b in hulls():
		var xf := MapOps.global_of(b)
		for e in MapOps.hull_edges(b.points):
			var a: Vector3 = xf * (e[0] as Vector3)
			var c: Vector3 = xf * (e[1] as Vector3)
			if view.behind(a) or view.behind(c):
				continue
			var sa: Vector2 = view.screen(a)
			var sc: Vector2 = view.screen(c)
			var d := pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, sa, sc))
			if d < best_d:
				best_d = d
				best_b = b
				best_p = ((e[0] as Vector3) + (e[1] as Vector3)) * 0.5
	if best_b == null:
		var best_far := INF
		var origin: Vector3 = view.origin(pos)
		var dir: Vector3 = view.normal(pos)
		for b in hulls():
			var inv := MapOps.global_of(b).affine_inverse()
			var hit := MapOps.ray_hull(inv * origin, (inv.basis * dir), b.points)
			if hit.is_empty():
				continue
			var middle := Vector3.ZERO
			for p: Vector3 in hit[1]:
				middle += p
			middle /= (hit[1] as Array).size()
			var far := origin.distance_to(MapOps.global_of(b) * middle)
			if far < best_far:
				best_far = far
				best_b = b
				best_p = middle
	if best_b == null:
		return false
	var before := {best_b: [best_b.points.duplicate(), best_b.position]}
	var pts := best_b.points.duplicate()
	pts.append(best_p)
	if MapMesher.hull_corners(pts).size() > MapMesher.MAX_HULL_CORNERS or pts.size() > MapMesher.MAX_HULL_CORNERS:
		return true   # (used: it was on the shape, but there is no room for another corner)
	var world := MapOps.global_of(best_b) * best_p
	_commit("Add hull corner", {best_b: MapOps.hull_placement(best_b, pts, best_b.position)}, before)
	picked = []
	_repick([world])
	return true


# ---------------------------------------------------------------------------
# Drawing

func draw(view: RefCounted, overlay: Control) -> void:
	_tidy()
	var font := overlay.get_theme_default_font()
	var font_size := overlay.get_theme_default_font_size()
	var mine := hulls()
	if mine.is_empty():
		overlay.draw_string(font, Vector2(16, 48), "Vertex: select a hull block (Map > Make Editable turns any block into one).",
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, CORNER)
		return
	for b in mine:
		var xf := MapOps.global_of(b)
		for e in MapOps.hull_edges(b.points):
			view.draw_line(overlay, xf * (e[0] as Vector3), xf * (e[1] as Vector3), BAD if _refused else EDGE, 1.5)
		for i in b.points.size():
			var w := xf * b.points[i]
			if view.behind(w):
				continue
			var on := _is_picked(b, i)
			var r := 5.0 if on else 3.5
			var s: Vector2 = view.screen(w)
			overlay.draw_rect(Rect2(s - Vector2(r, r), Vector2(r, r) * 2.0), PICKED if on else CORNER)
	if phase == Phase.BAND:
		var rect := Rect2(_press, _now - _press).abs()
		overlay.draw_rect(rect, Color(PICKED, 0.12))
		overlay.draw_rect(rect, PICKED, false, 1.0)
	if phase == Phase.DRAG and _refused:
		overlay.draw_string(font, _now + Vector2(14, -14), "It would not be convex", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, BAD)
	elif phase == Phase.DRAG:
		overlay.draw_string(font, _now + Vector2(14, -14), "%s, %s, %s m" % [String.num(_moved.x, 2), String.num(_moved.y, 2), String.num(_moved.z, 2)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, PICKED)
