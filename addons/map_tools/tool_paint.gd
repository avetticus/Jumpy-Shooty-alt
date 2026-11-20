@tool
extends RefCounted
## The Paint tool: give single faces of blocks their own kind, and move, turn or scale
## the pattern on them (MapBlock.face_kinds, face_patterns): the map tools' answer to
## TrenchBroom's texturing, for this game's patterns drawn from the palette.
##
## Click a face of any block to pick it (Shift-click: pick more, or take one back); a
## click on no block picks nothing. With faces picked:
##  - a kind clicked in the Map dock paints them (instead of the whole blocks);
##  - the arrow keys slide their pattern a grid square across or up the face, Page Up
##    and Page Down turn it 15 degrees, + and - make it bigger or smaller;
##  - Delete puts them back as the block (its kind, the pattern as it was);
##  - Ctrl+C takes the first picked face's paint and pattern, Ctrl+V gives it to them all.
## Alt+click paints the face under the mouse with the kind chosen in the Map dock.
## Each change is one undo step. What a block is made of (footsteps, breaking) stays its
## own kind's; a block that breaks cell by cell is drawn in its own kind once broken.

const MapOps := preload("res://addons/map_tools/map_ops.gd")
const MapEdit := preload("res://addons/map_tools/map_edit.gd")

const PICKED := Color(0.4, 1.0, 0.6)
const TURN := 15.0     # degrees a Page Up or Page Down turns a pattern
const GROW := 1.25     # how much + or - scales it

var ctx: RefCounted   # MapContext
## The picked faces: [[block, its name (MapBlock.face_key), its corners in the block's own frame], ...].
var picked := []
## What Ctrl+C took: [kind ("" = the block's own), pattern], or [].
var copied := []


func busy() -> bool:
	return false


func cancel() -> void:
	pass


func input(view: RefCounted, event: InputEvent) -> bool:
	_tidy()
	var mb := event as InputEventMouseButton
	var key := event as InputEventKey
	if key and key.pressed:
		return _key(key)
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not mb.is_command_or_control_pressed():
		var face := face_at(view.origin(mb.position), view.normal(mb.position))
		if mb.alt_pressed:
			if not face.is_empty():
				paint([face], ctx.kind)
			return true
		if face.is_empty():
			if not mb.shift_pressed:
				picked = []
			ctx.click_select(view.origin(mb.position), view.normal(mb.position), mb.shift_pressed)
			return true
		var at := _index_of(face[0], face[1])
		if mb.shift_pressed:
			if at >= 0:
				picked.remove_at(at)
			else:
				picked.append(face)
		else:
			picked = [face]
		return true
	return false


# ---------------------------------------------------------------------------
# Finding faces

## The face of a block the ray first meets (`origin`, `dir` in the map): [block, its
## name, its corners in the block's own frame], or [] if none. By the blocks' real
## shapes (each lump of a tube, an arch or a dome), not the boxes round them.
func face_at(origin: Vector3, dir: Vector3) -> Array:
	var near := []   # [box distance, block]
	for e in ctx.blocks():
		var hit := MapOps.ray_box(origin, dir, e.xf, e.half)
		if not hit.is_empty():
			near.append([hit[0], e.block])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var best := []
	var best_far := INF
	for n in near:
		if n[0] > best_far:
			break   # (its box starts further away than a face already found)
		var block: MapBlock = n[1]
		var xf := MapOps.global_of(block)
		var inv := xf.affine_inverse()
		var o := inv * origin
		var d := inv.basis * dir
		for lump in block.shape_lumps():
			var hit := MapOps.ray_hull(o, d, lump)
			if hit.is_empty():
				continue
			var far := origin.distance_to(xf * (o + d * (hit[0] as float)))
			if far < best_far:
				best_far = far
				best = [block, MapBlock.face_key(hit[2]), hit[1]]
	return best


func _index_of(block: MapBlock, key: String) -> int:
	for i in picked.size():
		if picked[i][0] == block and picked[i][1] == key:
			return i
	return -1


## Leaves out picked faces of blocks that are gone.
func _tidy() -> void:
	picked = picked.filter(func(f: Array) -> bool: return is_instance_valid(f[0]) and (f[0] as Node).is_inside_tree())


# ---------------------------------------------------------------------------
# Changing faces

## Paints `faces` with `kind` (the block's own kind: back to it).
func paint(faces: Array, kind: String) -> void:
	_change("Paint faces %s" % kind, faces, func(b: MapBlock, key: String, kinds: Dictionary, _patterns: Dictionary) -> void:
		if kind == b.kind:
			kinds.erase(key)
		else:
			kinds[key] = kind)


## Moves, turns and scales the pattern on the picked faces: `slide` metres across and
## up, `turn` degrees, the scale times `grow`.
func shift_pattern(slide: Vector2, turn: float, grow: float) -> void:
	_change("Move face patterns", picked, func(_b: MapBlock, key: String, _kinds: Dictionary, patterns: Dictionary) -> void:
		var p: Vector4 = patterns.get(key, Vector4(0, 0, 0, 1))
		p = Vector4(p.x + slide.x, p.y + slide.y, wrapf(p.z + turn, -180.0, 180.0), clampf(p.w * grow, 0.05, 20.0))
		if p.is_equal_approx(Vector4(0, 0, 0, 1)):
			patterns.erase(key)
		else:
			patterns[key] = p)


## Puts the picked faces back as their blocks.
func reset() -> void:
	_change("Reset faces", picked, func(_b: MapBlock, key: String, kinds: Dictionary, patterns: Dictionary) -> void:
		kinds.erase(key)
		patterns.erase(key))


## Gives the picked faces `given` ([kind or "", pattern]: see paint_of).
func paste(given: Array) -> void:
	_change("Paste face paint", picked, func(b: MapBlock, key: String, kinds: Dictionary, patterns: Dictionary) -> void:
		var kind: String = given[0]
		if kind == "" or kind == b.kind:
			kinds.erase(key)
		else:
			kinds[key] = kind
		var p: Vector4 = given[1]
		if p.is_equal_approx(Vector4(0, 0, 0, 1)):
			patterns.erase(key)
		else:
			patterns[key] = p)


## [kind or "" (the block's own), pattern] of a face.
static func paint_of(face: Array) -> Array:
	var b: MapBlock = face[0]
	return [b.face_kinds.get(face[1], ""), b.face_patterns.get(face[1], Vector4(0, 0, 0, 1))]


## One undo step: `how` (block, face name, its face_kinds, its face_patterns: copies to
## change) for each face, the blocks then given the changed lists.
func _change(title: String, faces: Array, how: Callable) -> void:
	var after := {}   # block -> [kinds, patterns]
	for f in faces:
		var b: MapBlock = f[0]
		if not after.has(b):
			after[b] = [b.face_kinds.duplicate(), b.face_patterns.duplicate()]
		how.call(b, f[1], after[b][0], after[b][1])
	var edit := MapEdit.new()
	edit.name = title
	for b: MapBlock in after:
		if after[b][0] != b.face_kinds:
			edit.sets.append([b, "face_kinds", after[b][0], b.face_kinds])
		if after[b][1] != b.face_patterns:
			edit.sets.append([b, "face_patterns", after[b][1], b.face_patterns])
	if not edit.is_empty():
		ctx.commit.call(edit)


# ---------------------------------------------------------------------------
# Keys

func _key(key: InputEventKey) -> bool:
	if picked.is_empty() or key.alt_pressed:
		return false
	var grid: float = ctx.grid
	if key.is_command_or_control_pressed():
		match key.keycode:
			KEY_C:
				copied = paint_of(picked[0])
				return true
			KEY_V:
				if not copied.is_empty():
					paste(copied)
				return true
		return false
	match key.keycode:
		KEY_LEFT: shift_pattern(Vector2(-grid, 0), 0.0, 1.0)
		KEY_RIGHT: shift_pattern(Vector2(grid, 0), 0.0, 1.0)
		KEY_UP: shift_pattern(Vector2(0, grid), 0.0, 1.0)
		KEY_DOWN: shift_pattern(Vector2(0, -grid), 0.0, 1.0)
		KEY_PAGEUP: shift_pattern(Vector2.ZERO, TURN, 1.0)
		KEY_PAGEDOWN: shift_pattern(Vector2.ZERO, -TURN, 1.0)
		KEY_EQUAL, KEY_KP_ADD, KEY_PLUS: shift_pattern(Vector2.ZERO, 0.0, GROW)
		KEY_MINUS, KEY_KP_SUBTRACT: shift_pattern(Vector2.ZERO, 0.0, 1.0 / GROW)
		KEY_DELETE, KEY_BACKSPACE: reset()
		_: return false
	return true


# ---------------------------------------------------------------------------
# Drawing

func draw(view: RefCounted, overlay: Control) -> void:
	_tidy()
	var font := overlay.get_theme_default_font()
	var size := overlay.get_theme_default_font_size()
	if picked.is_empty():
		overlay.draw_string(font, Vector2(16, 48), "Paint: click a face to pick it (Shift: more); Alt+click paints it with the chosen kind.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, PICKED)
		return
	for f in picked:
		var xf := MapOps.global_of(f[0])
		var ring: Array = f[2]
		for i in ring.size():
			view.draw_line(overlay, xf * (ring[i] as Vector3), xf * (ring[(i + 1) % ring.size()] as Vector3), PICKED, 3.0)
	var first: Array = paint_of(picked[0])
	var p: Vector4 = first[1]
	overlay.draw_string(font, Vector2(16, 48), "%d face%s: %s; pattern moved %s, %s m, turned %s°, scale %s.   Arrows, Page Up/Down, +/-, Delete, Ctrl+C/V; a kind in the Map dock paints them." % [
		picked.size(), "" if picked.size() == 1 else "s", first[0] if first[0] != "" else (picked[0][0] as MapBlock).kind,
		String.num(p.x, 2), String.num(p.y, 2), String.num(p.z, 0), String.num(p.w, 2)], HORIZONTAL_ALIGNMENT_LEFT, -1, size, PICKED)
