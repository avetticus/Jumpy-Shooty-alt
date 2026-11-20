@tool
extends EditorNode3DGizmoPlugin
## Map blocks in the 3D editor: click one to select it, then drag the orange
## handle on a face to move that face (the opposite face stays put). A cylinder
## has a handle for its diameter and one at each end. A hull has a handle in the
## middle of every face, slanted ones too: drag it to push or pull that face straight
## out from itself, every other face staying in its plane (MapOps.extruded).
##
## Sizes snap to the map tools' grid ([ and ] change it); hold Ctrl to snap to whole
## metres. A dragged face also snaps flush to a nearby face of another block that
## lies square to this one (not while Ctrl is held).

const MapOps := preload("res://addons/map_tools/map_ops.gd")

const NAMES := ["Right (+x)", "Left (-x)", "Top (+y)", "Bottom (-y)", "Back (+z)", "Front (-z)"]

## The map tools' shared state (plugin.gd sets it): the grid, the blocks to snap to.
var ctx: RefCounted

var _frame := Transform3D.IDENTITY   # the dragged block's own axes, at the map's origin
var _others: Array[AABB] = []        # the other blocks' boxes in that frame
var _snapping := false
var _hull_points := PackedVector3Array()   # a hull being reshaped: its points as the drag began
var _hull_at := Vector3.ZERO               # and where it stood


func _init() -> void:
	create_handle_material("handles")


func _get_gizmo_name() -> String:
	return "MapBlock"


func _has_gizmo(node: Node3D) -> bool:
	return node is MapBlock


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var block := gizmo.get_node_3d() as MapBlock
	var triangles := block.preview_triangles()
	if triangles:
		gizmo.add_collision_triangles(triangles)
	if ctx and ctx.editing_corners:
		return   # the Vertex tool is on: it draws the corners instead
	if block.shape == MapBlock.Shape.HULL:
		var middles := MapOps.face_middles(block.points)
		var face_ids := PackedInt32Array()
		for i in middles.size():
			face_ids.append(i)
		if not middles.is_empty():
			gizmo.add_handles(middles, get_material("handles", gizmo), face_ids)
		return
	var h := block.size * 0.5
	var handles := PackedVector3Array()
	var ids := PackedInt32Array()
	for id in 6:
		if block.is_round() and id in [1, 4, 5]:
			continue   # round: one handle for the diameter
		var axis := id / 2
		var p := Vector3.ZERO
		p[axis] = h[axis] * (1.0 if id % 2 == 0 else -1.0)
		handles.append(p)
		ids.append(id)
	gizmo.add_handles(handles, get_material("handles", gizmo), ids)


func _get_handle_name(gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> String:
	var block := gizmo.get_node_3d() as MapBlock
	if block.shape == MapBlock.Shape.HULL:
		return "Face %d" % (id + 1)
	return "Diameter" if block.is_round() and id == 0 else NAMES[id]


func _get_handle_value(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool) -> Variant:
	var block := gizmo.get_node_3d() as MapBlock
	if block.shape == MapBlock.Shape.HULL:
		return [block.points.duplicate(), block.position]
	return [block.size, block.position]


## A drag starts: note what the dragged face could snap to.
func _begin_handle_action(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool) -> void:
	_snapping = false
	var block := gizmo.get_node_3d() as MapBlock
	if block.shape == MapBlock.Shape.HULL:
		_hull_points = block.points.duplicate()
		_hull_at = block.position
		return
	if ctx == null or ctx.map == null or not ctx.map.is_ancestor_of(block):
		return
	_frame = Transform3D((MapOps.box_of(block)[0] as Transform3D).basis, Vector3.ZERO)
	var rest := []
	for e in ctx.blocks():
		if e.block != block:
			rest.append(e.block)
	_others = MapOps.boxes_in_frame(_frame, rest)
	_snapping = true


func _set_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var block := gizmo.get_node_3d() as MapBlock
	if block.shape == MapBlock.Shape.HULL:
		var step: float = 1.0 if Input.is_key_pressed(KEY_CTRL) else (ctx.grid if ctx else 0.1)
		var placed := MapOps.pushed_face(block, _hull_points, _hull_at, id,
			camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos), step)
		if not placed.is_empty():
			block.points = placed[0]
			block.position = placed[1]
		return
	var to_local := block.global_transform.affine_inverse()
	var from := camera.project_ray_origin(screen_pos)
	var ray := camera.project_ray_normal(screen_pos)
	var a := to_local * from
	var b := to_local * (from + ray * 4096.0)
	var axis := id / 2
	var dir := 1.0 if id % 2 == 0 else -1.0
	var line := Vector3.ZERO
	line[axis] = 4096.0
	var closest := Geometry3D.get_closest_points_between_segments(-line, line, a, b)
	var reach: float = closest[0][axis] * dir   # how far out the dragged face is, from the centre
	var whole := Input.is_key_pressed(KEY_CTRL)
	var step: float = 1.0 if whole else (ctx.grid if ctx else 0.1)
	if _snapping and not whole and not (block.is_round() and axis != 1):
		# Where the face would be, in metres, among the other blocks.
		var boxes := MapOps.boxes_in_frame(_frame, [block])
		if boxes.size() == 1:
			var box := boxes[0]
			var per_unit: float = box.size[axis] / block.size[axis]   # the block's scale along this axis
			var face := box.get_center()[axis] + reach * per_unit * dir
			if dir > 0.0:
				box.size[axis] = maxf(face - box.position[axis], 0.01)
			else:
				var far := box.end[axis]
				box.position[axis] = minf(face, far - 0.01)
				box.size[axis] = far - box.position[axis]
			var nudge := MapOps.snap_face(box, axis, dir, _others, step * 0.5)
			if nudge != INF:
				block.move_face(id, reach + nudge * dir / per_unit, 0.001)
				return
	block.move_face(id, reach, step)


func _commit_handle(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	_snapping = false
	var block := gizmo.get_node_3d() as MapBlock
	if block.shape == MapBlock.Shape.HULL:
		if cancel:
			block.points = restore[0]
			block.position = restore[1]
			return
		var hull_undo := EditorInterface.get_editor_undo_redo()
		hull_undo.create_action("Push hull face")
		hull_undo.add_do_property(block, "points", block.points)
		hull_undo.add_do_property(block, "position", block.position)
		hull_undo.add_undo_property(block, "points", restore[0])
		hull_undo.add_undo_property(block, "position", restore[1])
		hull_undo.commit_action()
		return
	if cancel:
		block.size = restore[0]
		block.position = restore[1]
		return
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("Resize map block")
	undo.add_do_property(block, "size", block.size)
	undo.add_do_property(block, "position", block.position)
	undo.add_undo_property(block, "size", restore[0])
	undo.add_undo_property(block, "position", restore[1])
	undo.commit_action()
