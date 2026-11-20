@tool
extends RefCounted
## The Clip tool: cut the selected blocks.
##
## Straight cuts: point at a selected block: a line shows where it would be cut,
## snapped to the grid, across the longest side of the face you point at (the "next
## cut direction" key turns it). Click to cut. Every selected block the cut passes
## through (and that lies square to it) is cut with it.
##
## Cuts at any angle: drag a line instead of clicking.
##  - In a top, front or side view, the cut runs through the line, straight into the
##    view. Drag anywhere.
##  - In the 3D view, start on a face of a selected block: the cut runs through the
##    line drawn across that face, square to it (a diagonal across a box's side cuts
##    it into two slopes). Then click a third point on any block to tilt the cut
##    through all three.
## The ends snap to the grid. The parts are shown, kept ones yellow and the others
## red; the "next cut direction" key chooses what to keep (both, the part in front of
## the cut, the part behind it), Enter cuts, Esc or a right click gives up. Every
## selected block the cut passes through is cut. A box cut square to its sides stays
## boxes; anything else becomes hull blocks (MapBlock.Shape.HULL). Tubes, arches and
## hollow domes are only cut straight.
##
## A click that is not on a selected block is an ordinary click, so you can pick
## another block without leaving the tool.

const MapOps := preload("res://addons/map_tools/map_ops.gd")
const MapEdit := preload("res://addons/map_tools/map_edit.gd")

const COLOR := Color(1.0, 0.9, 0.2)
const DROPPED := Color(1.0, 0.3, 0.25, 0.8)
const CLICK := 4.0   # a press that moves less than this (pixels) is a click, not a drag

enum Phase { IDLE, PRESS, LINE, PENDING }
## What a cut at an angle keeps.
enum Keep { BOTH, FRONT, BACK }

var ctx: RefCounted   # MapContext
var turn := 0         # how many times the straight cut's direction has been turned
var phase := Phase.IDLE
var keep := Keep.BOTH

var _cuts := []       # straight cuts: [block, axis, at (the block's own units), xf, half, at (metres)]
var _last_view: RefCounted
var _last_pos := Vector2.ZERO

var _press := Vector2.ZERO
var _press_view: RefCounted
var _ortho := -1                     # the axis a top, front or side view looks along; -1: 3D
var _face := Plane()                 # 3D: the face the line is drawn on (in the map)
var _a := Vector3.ZERO               # the line's ends and the third point (in the map)
var _b := Vector3.ZERO
var _c := Vector3.ZERO
var _has_c := false
var _pending := []                   # [[block, [behind, in front]], ...]


func busy() -> bool:
	return phase != Phase.IDLE


func cancel() -> void:
	_cuts = []
	_drop_pending()
	phase = Phase.IDLE


## Lets go of the parts a pending cut made (they are not in the scene).
func _drop_pending() -> void:
	for entry in _pending:
		for part in entry[1]:
			if part and is_instance_valid(part) and not (part as Node).is_inside_tree():
				(part as Node).free()
	_pending = []


## Straight cuts: turn the cut to run the other way across the face. A cut at an
## angle: keep the next choice of parts (both, in front, behind).
func next_direction() -> void:
	if phase == Phase.PENDING:
		keep = ((keep + 1) % 3) as Keep
		return
	turn += 1
	if _last_view:
		_find(_last_view, _last_pos)


func input(view: RefCounted, event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	var key := event as InputEventKey
	if key and key.pressed:
		if busy() and (key.keycode == KEY_ESCAPE):
			cancel()
			return true
		if phase == Phase.PENDING and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER):
			_apply()
			return true
		return false
	if busy() and mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		cancel()
		return true
	match phase:
		Phase.IDLE:
			if mm:
				_find(view, mm.position)
				return false
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not mb.alt_pressed \
					and not mb.shift_pressed and not mb.is_command_or_control_pressed():
				return _begin(view, mb.position)
		Phase.PRESS:
			if mm:
				if mm.position.distance_to(_press) >= CLICK:
					phase = Phase.LINE
					_b = _line_point(view, mm.position)
				return true
			if mb and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				phase = Phase.IDLE
				_find(view, mb.position)   # only a click: the straight cut
				if not _cuts.is_empty():
					_cut()
				else:
					ctx.click_select(view.origin(mb.position), view.normal(mb.position), false)
				return true
		Phase.LINE:
			if mm:
				_b = _line_point(view, mm.position)
				return true
			if mb and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				_b = _line_point(view, mb.position)
				if _a.distance_to(_b) < MapOps.SLIVER:
					cancel()
				else:
					_has_c = false
					keep = Keep.BOTH
					phase = Phase.PENDING
					_update_pending()
				return true
		Phase.PENDING:
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				if _ortho < 0:
					var hit: Dictionary = ctx.pick(view.origin(mb.position), view.normal(mb.position))
					if not hit.is_empty():
						_c = MapOps.snap_v(hit.point, ctx.grid)
						_has_c = true
						_update_pending()
				return true
			if mb and mb.button_index == MOUSE_BUTTON_LEFT:
				return true
	return false


# ---------------------------------------------------------------------------
# Straight cuts

func _find(view: RefCounted, pos: Vector2) -> void:
	_last_view = view
	_last_pos = pos
	_cuts = []
	var blocks: Array = ctx.selected_blocks().filter(func(b: MapBlock) -> bool: return not MapOps.clip_axes(b).is_empty())
	if blocks.is_empty():
		return
	var hit: Dictionary = ctx.pick(view.origin(pos), view.normal(pos), blocks)
	if hit.is_empty():
		return
	var block: MapBlock = hit.block
	var xf: Transform3D = hit.xf
	var half: Vector3 = hit.half
	# Cut across a side of the face pointed at, the longest first.
	var ways: Array = MapOps.clip_axes(block).filter(func(a: int) -> bool: return a != hit.axis)
	if ways.is_empty():
		return
	ways.sort_custom(func(a: int, b: int) -> bool:
		return half[a] > half[b] + 0.001 or (absf(half[a] - half[b]) <= 0.001 and a < b))   # a square face: always the same way first
	var axis: int = ways[turn % ways.size()]
	var at: float = (xf.affine_inverse() * (hit.point as Vector3))[axis]
	var n := xf.basis[axis]
	var world := n.abs().max_axis_index()
	if absf(n[world]) > 0.999:
		# Square to the map: the cut lands on the map's grid.
		var where: float = (hit.point as Vector3)[world]
		at += (MapOps.snap(where, ctx.grid) - where) * signf(n[world])
	else:
		at = MapOps.snap(at + half[axis], ctx.grid) - half[axis]
	var along := Vector3.ZERO
	along[axis] = at
	var through := xf * along   # a point on the cut, in the map
	for b: MapBlock in blocks:
		var box := MapOps.box_of(b)
		var bxf: Transform3D = box[0]
		var bhalf: Vector3 = box[1]
		for j in MapOps.clip_axes(b):
			if absf(bxf.basis[j].dot(n)) < 0.999:
				continue
			var m: float = (bxf.affine_inverse() * through)[j]
			if absf(m) < bhalf[j] - MapOps.SLIVER:
				_cuts.append([b, j, m * (b.size[j] * 0.5) / bhalf[j], bxf, bhalf, m])
			break


func _cut() -> void:
	var edit := MapEdit.new()
	edit.name = "Clip map block"
	var chosen: Array = ctx.selected()
	for c in _cuts:
		var block: MapBlock = c[0]
		var halves := MapOps.clip(block, c[1], c[2])
		if halves.size() != 2:
			continue
		var index := block.get_index()
		edit.removes.append(block)
		edit.adds.append([block.get_parent(), halves[0], index])
		edit.adds.append([block.get_parent(), halves[1], index + 1])
		chosen.erase(block)
		chosen.append_array(halves)
	_cuts = []
	edit.select = chosen
	edit.reselect = true
	if not edit.is_empty():
		ctx.commit.call(edit)


# ---------------------------------------------------------------------------
# Cuts at any angle

## A press: maybe the start of a line. In a top, front or side view anywhere (with
## something selected); in the 3D view on a face of a selected block.
func _begin(view: RefCounted, pos: Vector2) -> bool:
	var blocks: Array = ctx.selected_blocks()
	if blocks.is_empty():
		return false
	_ortho = view.ortho_axis()
	_press = pos
	_press_view = view
	if _ortho >= 0:
		var p: Variant = view.on_plane(pos, _ortho, 0.0)
		if p == null:
			return false
		_a = _on_grid(p)
	else:
		var hit := _face_hit(view, pos, blocks)
		if hit.is_empty():
			return false
		_face = Plane(hit[1], hit[0])
		_a = _on_grid(hit[0])
	_b = _a
	phase = Phase.PRESS
	return true


## Where the ray under the mouse first meets a selected block's surface (a hull's
## own faces, not the box round it): [point, the face's outward normal], in the map.
func _face_hit(view: RefCounted, pos: Vector2, blocks: Array) -> Array:
	var origin: Vector3 = view.origin(pos)
	var dir: Vector3 = view.normal(pos)
	var best := []
	var best_far := INF
	for b: MapBlock in blocks:
		if b.shape == MapBlock.Shape.HULL:
			var xf := MapOps.global_of(b)
			var inv := xf.affine_inverse()
			var hit := MapOps.ray_hull(inv * origin, inv.basis * dir, b.points)
			if hit.is_empty():
				continue
			var at: Vector3 = xf * (inv * origin + inv.basis * dir * (hit[0] as float))
			var far := origin.distance_to(at)
			if far < best_far:
				best_far = far
				best = [at, (xf.basis.inverse().transposed() * (hit[2] as Vector3)).normalized()]
		else:
			var hit: Dictionary = ctx.pick(origin, dir, [b])
			if hit.is_empty():
				continue
			var far := origin.distance_to(hit.point)
			if far < best_far:
				best_far = far
				best = [hit.point, hit.normal]
	return best


## The point under the mouse on the line's plane (the view's, or the face's), on the grid.
func _line_point(view: RefCounted, pos: Vector2) -> Vector3:
	if _ortho >= 0:
		var p: Variant = view.on_plane(pos, _ortho, 0.0)
		return _b if p == null else _on_grid(p)
	var o: Vector3 = view.origin(pos)
	var d: Vector3 = view.normal(pos)
	var hit: Variant = _face.intersects_ray(o, d)
	if hit == null:
		hit = _face.intersects_ray(o, -d) if (view.camera as Camera3D).projection == Camera3D.PROJECTION_ORTHOGONAL else null
	return _b if hit == null else _on_grid(hit)


## `p` on the grid: in a top, front or side view across the view; in 3D, then put
## back onto the face drawn on.
func _on_grid(p: Vector3) -> Vector3:
	var s := MapOps.snap_v(p, ctx.grid)
	if _ortho >= 0:
		s[_ortho] = 0.0
		return s
	return s - _face.normal * _face.distance_to(s)


## The plane of the cut (in the map), or a Plane with a zero normal if there is none.
func cut_plane() -> Plane:
	var along := _b - _a
	var normal := Vector3.ZERO
	if _has_c:
		normal = along.cross(_c - _a)
	if normal.length_squared() < 1e-8:
		var into := Vector3.ZERO
		if _ortho >= 0:
			into[_ortho] = 1.0
		else:
			into = _face.normal
		normal = along.cross(into)
	if normal.length_squared() < 1e-8:
		return Plane(Vector3.ZERO, 0.0)
	return Plane(normal.normalized(), _a)


func _update_pending() -> void:
	_drop_pending()
	var plane := cut_plane()
	if plane.normal == Vector3.ZERO:
		return
	for b in ctx.selected_blocks():
		var parts := MapOps.clip_plane(b, plane)
		if not parts.is_empty():
			_pending.append([b, parts])


## The parts of a pending cut that are kept: [behind, in front] filtered by `keep`.
func _kept(parts: Array) -> Array:
	match keep:
		Keep.FRONT:
			return [parts[1]] if parts[1] else []
		Keep.BACK:
			return [parts[0]] if parts[0] else []
	return parts.filter(func(p) -> bool: return p != null)


func _apply() -> void:
	var edit := MapEdit.new()
	edit.name = "Clip map blocks at an angle"
	var chosen: Array = ctx.selected()
	for entry in _pending:
		var block: MapBlock = entry[0]
		if not is_instance_valid(block) or not block.is_inside_tree():
			continue
		var kept := _kept(entry[1])
		var index := block.get_index()
		edit.removes.append(block)
		chosen.erase(block)
		for i in kept.size():
			edit.adds.append([block.get_parent(), kept[i], index + i])
			chosen.append(kept[i])
		for part in entry[1]:
			if part and part not in kept:
				(part as Node).free()
		entry[1] = []   # (the kept ones now belong to the edit)
	_pending = []
	phase = Phase.IDLE
	edit.select = chosen
	edit.reselect = true
	if not edit.is_empty():
		ctx.commit.call(edit)


# ---------------------------------------------------------------------------
# Drawing

func draw(view: RefCounted, overlay: Control) -> void:
	if phase == Phase.IDLE:
		_draw_straight(view, overlay)
		return
	if phase == Phase.PRESS:
		return
	view.draw_line(overlay, _a, _b, COLOR, 2.5)
	for p in ([_a, _b, _c] if _has_c else [_a, _b]):
		if not view.behind(p):
			overlay.draw_circle(view.screen(p), 4.0, COLOR)
	for entry in _pending:
		var block: MapBlock = entry[0]
		if not is_instance_valid(block):
			continue
		var kept := _kept(entry[1])
		for part in entry[1]:
			if part:
				_draw_part(view, overlay, part, block, COLOR if part in kept else DROPPED)
	if phase == Phase.PENDING:
		var font := overlay.get_theme_default_font()
		var text := "Enter: cut (keeping %s)   X: keep something else   %sEsc: give up" % [
			["both", "the part in front", "the part behind"][keep],
			"" if _ortho >= 0 else "click: a third point   "]
		if _pending.is_empty():
			text = "The cut misses the selected blocks (or cannot cut them at an angle)   Esc: give up"
		overlay.draw_string(font, Vector2(16, 48), text, HORIZONTAL_ALIGNMENT_LEFT, -1, overlay.get_theme_default_font_size(), COLOR)


func _draw_part(view: RefCounted, overlay: Control, part: MapBlock, beside: MapBlock, color: Color) -> void:
	var xf := MapOps.global_beside(part, beside)
	if part.shape == MapBlock.Shape.HULL:
		for e in MapOps.hull_edges(part.points):
			view.draw_line(overlay, xf * (e[0] as Vector3), xf * (e[1] as Vector3), color, 2.0)
	else:
		var scale := xf.basis.get_scale().abs()
		view.draw_box(overlay, Transform3D(xf.basis.orthonormalized(), xf.origin), part.size * scale * 0.5, color)


func _draw_straight(view: RefCounted, overlay: Control) -> void:
	for c in _cuts:
		var xf: Transform3D = c[3]
		var half: Vector3 = c[4]
		var axis: int = c[1]
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		var corners := PackedVector3Array()
		for s in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			var p := Vector3.ZERO
			p[axis] = c[5]
			p[u] = half[u] * s[0]
			p[v] = half[v] * s[1]
			corners.append(xf * p)
		for i in 4:
			view.draw_line(overlay, corners[i], corners[(i + 1) % 4], COLOR, 3.0)
