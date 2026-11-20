@tool
extends RefCounted
## The Vertex tool: reshape hull blocks (MapBlock.Shape.HULL; Map > Make Editable
## turns any block into them) by their corners, edges and faces.
##
## The selected hull blocks show their edges and corners. Click a corner, an edge or a
## face to pick it (an edge or a face is its corners; Shift: add it, or take it away),
## or drag a box round several corners. Corners of different blocks in the same place
## are picked, and move, together.
##  - Drag a picked corner or edge to move what is picked, on the grid: level in the 3D
##    view (hold Shift for up and down), in the view's plane in a top, front or side
##    view. A corner lands on the grid; an edge moves by whole grid squares.
##  - Drag a face to push or pull it straight out from itself, by whole grid squares,
##    while every other face stays in its plane (they grow or shrink to meet it).
##  - The arrow keys move the picked corners a grid square across the view, Page Up
##    and Page Down up and down; Delete takes them away.
##  - Double-click an edge to add a corner in its middle, or a face to add one in its
##    middle; then drag it out.
##
## A hull is always convex: a move that would dent it (a corner sunk inside), flatten
## it, or push a face out until its neighbours close over it, is refused (drawn red).
## A corner another one's move leaves inside the shape is dropped. A click on no
## selected hull selects a block as usual. Each drag, nudge, add or delete is one undo
## step.

const MapOps := preload("res://addons/map_tools/map_ops.gd")
const MapEdit := preload("res://addons/map_tools/map_edit.gd")

const CORNER := Color(1.0, 0.6, 0.15)
const PICKED := Color(1.0, 1.0, 0.35)
const EDGE := Color(1.0, 0.75, 0.35, 0.85)
const BAD := Color(1.0, 0.25, 0.2)
const REACH := 8.0        # how near a corner a click must be (pixels)
const EDGE_REACH := 6.0   # and an edge
const CLICK := 4.0        # a press that moves less than this (pixels) is a click
const SAME := 0.001       # corners this close (metres) are in the same place

enum Phase { IDLE, PRESS, DRAG, BAND }
## What a press was on.
enum Grab { NONE, CORNER, EDGE, FACE }

var ctx: RefCounted   # MapContext
var phase := Phase.IDLE
## The picked corners: [[block, index into its points], ...].
var picked := []

var _press := Vector2.ZERO
var _now := Vector2.ZERO
var _adding := false        # Shift was held at the press
var _grab_kind := Grab.NONE
var _grabbed := []          # the corners pressed on (a corner, an edge's, a face's)
var _grab := Vector3.ZERO   # where the press was on them, in the map
var _view_axis := -1        # the axis the view looks along (-1: a 3D view)
var _face_block: MapBlock   # a face pressed on: its block,
var _face := -1             # its index (MapMesher.hull_planes), as the drag began,
var _face_local := Vector3.ZERO   # which way it looks in the block's own frame,
var _face_normal := Vector3.ZERO  # and in the map,
var _face_scale := 1.0      # and the block's own units per metre along it
var _start := {}            # block -> [points, position] before the drag
var _moved := Vector3.ZERO  # how far the shape shown has been moved (the last allowed move)
var _pushed := 0.0          # a face drag: how far the face shown has been pushed (metres)
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
					if _grab_kind == Grab.NONE:
						phase = Phase.BAND
					elif not _all_picked(_grabbed):
						phase = Phase.IDLE   # Shift-clicked off: nothing to drag
					elif _grab_kind == Grab.FACE:
						_start_face_drag()
						_drag_face(view, mm.position)
					else:
						_start_drag()
						_drag(view, mm.position, mm.shift_pressed)
				return true
			if mb and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				if _grab_kind == Grab.NONE:
					_click_select(view, mb.position, _adding)
				phase = Phase.IDLE
				return true
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				phase = Phase.IDLE
				return true
		Phase.DRAG:
			if mm:
				if _grab_kind == Grab.FACE:
					_drag_face(view, mm.position)
				else:
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
# Picking corners, edges and faces

func _begin(view: RefCounted, pos: Vector2, adding: bool) -> bool:
	_press = pos
	_now = pos
	_adding = adding
	_view_axis = view.ortho_axis()
	_grab_kind = Grab.NONE
	_grabbed = []
	var corner := _corner_at(view, pos)
	if not corner.is_empty():
		var b: MapBlock = corner[0]
		_grab = MapOps.global_of(b) * b.points[corner[1]]
		_grab_kind = Grab.CORNER
		_grabbed = _at(_grab)
	else:
		var edge := _edge_at(view, pos)
		if not edge.is_empty():
			var b: MapBlock = edge[0]
			var xf := MapOps.global_of(b)
			_grab = edge[3]
			_grab_kind = Grab.EDGE
			_grabbed = _at(xf * (edge[1] as Vector3))
			for c in _at(xf * (edge[2] as Vector3)):
				_grabbed.append(c)
		else:
			var face := _face_at(view, pos)
			if not face.is_empty():
				var b: MapBlock = face[0]
				var xf := MapOps.global_of(b)
				_grab = face[2]
				_grab_kind = Grab.FACE
				_face_block = b
				_face = face[1]
				_face_local = face[3]
				var across := xf.basis.inverse().transposed() * _face_local
				_face_scale = across.length()
				_face_normal = across / _face_scale
				for p: Vector3 in face[4]:
					for c in _at(xf * p):
						if not _grabbed.any(func(g: Array) -> bool: return g[0] == c[0] and g[1] == c[1]):
							_grabbed.append(c)
	if _grab_kind != Grab.NONE:
		_choose(_grabbed, adding)
	phase = Phase.PRESS
	return true


## Picks `corners` (Shift: adds them, or takes them away if they all are picked).
func _choose(corners: Array, adding: bool) -> void:
	var all_in := _all_picked(corners)
	if adding and all_in:
		picked = picked.filter(func(c: Array) -> bool:
			return not corners.any(func(t: Array) -> bool: return t[0] == c[0] and t[1] == c[1]))
	elif adding:
		for c in corners:
			if not _is_picked(c[0], c[1]):
				picked.append(c)
	elif not all_in:
		picked = corners.duplicate()


func _all_picked(corners: Array) -> bool:
	return not corners.is_empty() and corners.all(func(c: Array) -> bool: return _is_picked(c[0], c[1]))


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


## The edge nearest the mouse on screen, within EDGE_REACH: [block, one end, the
## other (both in its own frame), the point on it under the mouse (in the map)], or [].
func _edge_at(view: RefCounted, pos: Vector2) -> Array:
	var best := []
	var best_d := EDGE_REACH
	var origin: Vector3 = view.origin(pos)
	var dir: Vector3 = view.normal(pos)
	for b in hulls():
		var xf := MapOps.global_of(b)
		for e in MapOps.hull_edges(b.points):
			var a: Vector3 = xf * (e[0] as Vector3)
			var c: Vector3 = xf * (e[1] as Vector3)
			if view.behind(a) or view.behind(c):
				continue
			var d := pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, view.screen(a), view.screen(c)))
			if d < best_d:
				best_d = d
				var on := Geometry3D.get_closest_points_between_segments(a, c, origin, origin + dir * 4096.0)
				best = [b, e[0], e[1], on[0]]
	return best


## The face of a selected hull under the mouse, the nearest: [block, its index
## (MapMesher.hull_planes), the point hit (in the map), which way it looks (in the
## block's own frame), its corners (in the block's own frame)], or [].
func _face_at(view: RefCounted, pos: Vector2) -> Array:
	var best := []
	var best_far := INF
	var origin: Vector3 = view.origin(pos)
	var dir: Vector3 = view.normal(pos)
	for b in hulls():
		var xf := MapOps.global_of(b)
		var inv := xf.affine_inverse()
		var o := inv * origin
		var d := inv.basis * dir
		var hit := MapOps.ray_hull(o, d, b.points)
		if hit.is_empty():
			continue
		var at := xf * (o + d * (hit[0] as float))
		var far := origin.distance_to(at)
		if far < best_far:
			best_far = far
			best = [b, hit[3], at, hit[2], hit[1]]
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


## A click on no selected hull: select the block under it, as the editor would
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
# Moving corners and edges

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
	var raw := _grab
	if _view_axis >= 0:
		var p: Variant = view.on_plane(pos, _view_axis, _grab[_view_axis])
		if p == null:
			return
		raw = p
		raw[_view_axis] = _grab[_view_axis]
	elif vertical:
		raw.y = _grab.y + view.along_line(pos, _grab, Vector3.UP)
	else:
		var p: Variant = view.on_plane(pos, 1, _grab.y)
		if p == null:
			return
		raw = p
		raw.y = _grab.y
	var delta: Vector3
	if _grab_kind == Grab.CORNER:
		# A corner lands on the grid (along the axes it moves on).
		var target := MapOps.snap_v(raw, ctx.grid)
		for axis in 3:
			if is_equal_approx(raw[axis], _grab[axis]):
				target[axis] = _grab[axis]
		delta = target - _grab
	else:
		delta = MapOps.snap_v(raw - _grab, ctx.grid)   # an edge moves by whole grid squares
	var shapes := _shapes(delta, _start)
	_refused = shapes.is_empty()
	if _refused:
		return   # the shape stays at the last move that was allowed
	_moved = delta
	_show(shapes)


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


## Shows blocks as `shapes` says (block -> [points, position]), outside any undo step.
func _show(shapes: Dictionary) -> void:
	for b: MapBlock in shapes:
		b.points = shapes[b][0]
		b.position = shapes[b][1]
	ctx.touch()


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
	if _grab_kind == Grab.FACE:
		if is_zero_approx(_pushed):
			_restore()
			return
		_commit("Push hull face", _snapshot_of(_face_block), _start)
		_pick_face(_face_block, _face_local)
		return
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
# Pushing and pulling a face

func _start_face_drag() -> void:
	_start = _snapshot_of(_face_block)
	_pushed = 0.0
	_refused = false
	phase = Phase.DRAG


func _snapshot_of(b: MapBlock) -> Dictionary:
	return {b: [b.points.duplicate(), b.position]}


func _drag_face(view: RefCounted, pos: Vector2) -> void:
	var b := _face_block
	if b == null or not is_instance_valid(b) or not _start.has(b):
		return
	var metres := MapOps.snap(view.along_line(pos, _grab, _face_normal), ctx.grid)
	if is_equal_approx(metres, _pushed):
		return
	var pts := MapOps.extruded(_start[b][0], _face, metres * _face_scale)
	_refused = pts.is_empty() and not is_zero_approx(metres)
	if pts.is_empty():
		if is_zero_approx(metres):   # back where it started
			_pushed = 0.0
			_show({b: _start[b]})
		return
	_pushed = metres
	_show({b: MapOps.hull_placement(b, pts, _start[b][1])})


## Picks the corners of `b`'s face that looks along `local` (in its own frame).
func _pick_face(b: MapBlock, local: Vector3) -> void:
	picked = []
	var xf := MapOps.global_of(b)
	for face in MapMesher.hull_faces(b.points):
		if (face[0] as Vector3).dot(local) > 0.9999:
			for p: Vector3 in face[1]:
				for c in _at(xf * p):
					if not _is_picked(c[0], c[1]):
						picked.append(c)
			return


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
	var edge := _edge_at(view, pos)
	if not edge.is_empty():
		best_b = edge[0]
		best_p = ((edge[1] as Vector3) + (edge[2] as Vector3)) * 0.5
	else:
		var face := _face_at(view, pos)
		if face.is_empty():
			return false
		best_b = face[0]
		for p: Vector3 in face[4]:
			best_p += p
		best_p /= (face[4] as Array).size()
	var before := _snapshot_of(best_b)
	var pts := best_b.points.duplicate()
	pts.append(best_p)
	if pts.size() > MapMesher.MAX_HULL_CORNERS:
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
			var on := _is_picked_at(b, e[0]) and _is_picked_at(b, e[1])
			var color := BAD if _refused else (PICKED if on else EDGE)
			view.draw_line(overlay, xf * (e[0] as Vector3), xf * (e[1] as Vector3), color, 2.5 if on else 1.5)
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
	if phase != Phase.DRAG:
		return
	var text := ""
	if _refused:
		text = "It would not be convex" if _grab_kind != Grab.FACE else "The face would vanish"
	elif _grab_kind == Grab.FACE:
		text = "%s m" % String.num(_pushed, 2)
	else:
		text = "%s, %s, %s m" % [String.num(_moved.x, 2), String.num(_moved.y, 2), String.num(_moved.z, 2)]
	overlay.draw_string(font, _now + Vector2(14, -14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, BAD if _refused else PICKED)


## Is the corner of `b` at `local` (in its own frame) picked?
func _is_picked_at(b: MapBlock, local: Vector3) -> bool:
	for c in picked:
		if c[0] == b and (b.points[c[1]] as Vector3).is_equal_approx(local):
			return true
	return false
