@tool
extends EditorPlugin
## Click-select in the 3D editor by mesh triangles instead of bounding boxes,
## box select that skips hidden objects, and Shift+right click to take things
## back out of the selection.
##
## A plain left click (no drag) casts a ray through every visible mesh in the
## edited scene and selects the one whose surface is nearest the camera. Shift
## click adds it to (or removes it from) the selection, like the built-in pick.
## A click on empty space inside a mesh's bounding box selects nothing.
##
## Box select (left drag, or Shift+left drag to add) leaves out objects that are
## completely hidden behind other meshes; any part showing is enough to keep one.
##
## Shift+right click removes the clicked object from the selection. Shift+right
## drag draws a red box and removes every visible selected object that sits
## wholly inside it (the same rule box select uses to add). Esc cancels. To fly
## fast with freelook, hold right mouse first, then Shift.
##
## Picks the same node the built-in pick would: the nearest node you can see in
## the Scene dock (so a click on an imported model selects the model, unless it
## has Editable Children), the top of a selection group, and never a locked node.
## Skinned meshes are tested in their current pose, not their rest pose.
##
## Leaves the click to Godot's own pick when only Alt or Ctrl is held, when the
## click lands on the move/rotate/scale gizmo of the current selection, and when
## the built-in pick chose a node with its own gizmo (light, camera, collision
## shape, sound, ...) instead of a mesh.

## A click that moves further than this (in pixels) is a drag, not a pick.
const DRAG_THRESHOLD := 4.0
## How close (in pixels) a Shift+right click must be to a light, camera or
## other icon-style node to remove it.
const ICON_RADIUS := 20.0
const REMOVE_FILL := Color(1.0, 0.3, 0.3, 0.15)
const REMOVE_EDGE := Color(1.0, 0.35, 0.35, 0.9)

var _press_pos := Vector2.INF
var _press_on_gizmo := false
## The selection as it was when the mouse went down.
var _before: Array[Node] = []
## Mesh instance id -> [TriangleMesh, its "changed" callback]. Built on first
## pick, dropped when the mesh changes.
var _tri_cache := {}

## At most this many rays are cast across a box to see what's visible in it.
const BOX_SAMPLES := 3000
## Rays aimed at each object that the box's grid of rays missed.
const OBJECT_SAMPLES := 24

## Shift+right remove click/drag in progress.
var _removing := false
var _remove_from := Vector2.ZERO
var _remove_to := Vector2.ZERO
var _remove_view: Node = null   # the editor viewport it started in


func _enter_tree() -> void:
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	scene_changed.connect(_on_scene_changed)


func _exit_tree() -> void:
	scene_changed.disconnect(_on_scene_changed)
	for id in _tri_cache:
		var mesh := instance_from_id(id) as Mesh
		var forget: Callable = _tri_cache[id][1]
		if mesh and mesh.changed.is_connected(forget):
			mesh.changed.disconnect(forget)
	_tri_cache.clear()


func _on_scene_changed(_root: Node) -> void:
	_cancel_remove()
	# Drop triangles of meshes that no longer exist.
	for id in _tri_cache.keys():
		if not is_instance_id_valid(id):
			_tri_cache.erase(id)


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	var mb := event as InputEventMouseButton
	if _removing:
		var handled := _remove_input(camera, event)
		if handled:
			return AFTER_GUI_INPUT_STOP
	if mb and mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and mb.shift_pressed \
			and not mb.alt_pressed and not mb.is_command_or_control_pressed():
		# Start a remove click/drag; keep it from freelook entirely.
		_press_pos = Vector2.INF
		_removing = true
		_remove_from = mb.position
		_remove_to = mb.position
		_remove_view = _editor_viewport_of(camera)
		return AFTER_GUI_INPUT_STOP
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return AFTER_GUI_INPUT_PASS
	if mb.pressed:
		_press_pos = mb.position
		_before = EditorInterface.get_selection().get_selected_nodes()
		_press_on_gizmo = _near_selection_gizmo(camera, mb.position)
		return AFTER_GUI_INPUT_PASS
	var press := _press_pos
	_press_pos = Vector2.INF
	if press == Vector2.INF:
		return AFTER_GUI_INPUT_PASS
	if press.distance_to(mb.position) > DRAG_THRESHOLD:
		# A drag: if it was a box select, drop what the box can't see. (A drag
		# that moved something instead leaves the selection alone, and
		# _drop_hidden() skips it.)
		if not mb.alt_pressed:
			var rect := Rect2(press, Vector2.ZERO).expand(mb.position)
			_drop_hidden.call_deferred(camera, rect, mb.shift_pressed, _before.duplicate())
		return AFTER_GUI_INPUT_PASS
	if mb.alt_pressed or mb.ctrl_pressed or mb.meta_pressed or _press_on_gizmo:
		return AFTER_GUI_INPUT_PASS
	var candidates := {}
	var target := _pick(camera, mb.position, candidates)
	# Let the built-in pick run first, then correct its choice.
	_settle.call_deferred(target, candidates, mb.shift_pressed, _before.duplicate())
	return AFTER_GUI_INPUT_PASS


# --- Box select ----------------------------------------------------------------

## After the built-in box select: deselect what it added that can't be seen.
func _drop_hidden(camera: Camera3D, rect: Rect2, additive: bool, before: Array[Node]) -> void:
	if not is_instance_valid(camera) or _claimed():
		return
	var selection := EditorInterface.get_selection()
	var now := selection.get_selected_nodes()
	if now == before:
		return   # a gizmo or object drag, not a box select
	var added: Array[Node] = []
	for node in now:
		if not additive or node not in before:
			added.append(node)
	var root := EditorInterface.get_edited_scene_root()
	if root == null or added.is_empty():
		return
	var info := _scene_info(camera, root)
	var hidden: Array[Node] = []
	for node in added:
		if not _visible_in_rect(camera, node, rect, info):
			hidden.append(node)
	_deselect(hidden)


## What a box needs to know about the scene: which object each visible mesh
## belongs to, which meshes each object has, and which objects show in the box.
func _scene_info(camera: Camera3D, root: Node) -> Dictionary:
	var owner_of := {}   # MeshInstance3D id -> selectable node
	var meshes := {}     # selectable node -> Array of MeshInstance3D
	for mi in _visible_meshes(root, camera.get_world_3d()):
		var target := _selectable_for(mi, root)
		if target == null:
			continue
		owner_of[mi.get_instance_id()] = target
		if not meshes.has(target):
			meshes[target] = []
		meshes[target].append(mi)
	return {"owner_of": owner_of, "meshes": meshes, "seen": {}}


## Whether any part of `node` shows (isn't hidden behind other meshes) inside
## `rect`. Objects without meshes (lights, cameras, ...) always count as shown.
func _visible_in_rect(camera: Camera3D, node: Node, rect: Rect2, info: Dictionary) -> bool:
	if not info.meshes.has(node) or _has_own_gizmo(node):
		return true
	var seen: Dictionary = info.seen
	if not seen.has(rect):
		seen[rect] = _seen_in_rect(camera, rect, info)
	if seen[rect].has(node):
		return true
	# Small objects can slip between the grid's rays: aim at the middle of a
	# spread of the object's own triangles too.
	for mi: MeshInstance3D in info.meshes[node]:
		var tris := _triangles_for(mi, _is_skinned(mi))
		if tris == null:
			continue
		var faces := tris.get_faces()
		var count := faces.size() / 3
		var stride := maxi(1, count / OBJECT_SAMPLES)
		var xform := mi.global_transform
		for t in range(0, count, stride):
			var p := xform * ((faces[t * 3] + faces[t * 3 + 1] + faces[t * 3 + 2]) / 3.0)
			if camera.is_position_behind(p):
				continue
			var s := _to_screen(camera, p)
			if rect.has_point(s) and node in _seen_at(camera, s, info):
				return true
	return false


## The objects hit first by a grid of rays across `rect`.
func _seen_in_rect(camera: Camera3D, rect: Rect2, info: Dictionary) -> Dictionary:
	var seen := {}
	var step := maxf(3.0, sqrt(rect.get_area() / BOX_SAMPLES))
	var y := rect.position.y + step * 0.5
	while y < rect.end.y:
		var x := rect.position.x + step * 0.5
		while x < rect.end.x:
			for node in _seen_at(camera, Vector2(x, y), info):
				seen[node] = true
			x += step
		y += step
	return seen


## The objects you can see at screen point `pos`: the nearest solid mesh, plus
## any see-through ones (like ghost blocks) in front of it.
func _seen_at(camera: Camera3D, pos: Vector2, info: Dictionary) -> Array[Node]:
	var vp_pos := _to_viewport(camera, pos)
	var origin := camera.project_ray_origin(vp_pos)
	var dir := camera.project_ray_normal(vp_pos)
	var ids := RenderingServer.instances_cull_ray(origin, origin + dir * camera.far,
			camera.get_world_3d().scenario)
	var hits := []   # [distance, node, see-through]
	for id in ids:
		var target: Node = info.owner_of.get(id)
		if target == null:
			continue
		var mi := instance_from_id(id) as MeshInstance3D
		var d := _hit_distance(mi, origin, dir)
		if is_nan(d) or d == INF:
			continue
		hits.append([d, target, _is_see_through(mi)])
	hits.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var seen: Array[Node] = []
	for hit in hits:
		seen.append(hit[1])
		if not hit[2]:
			break   # solid: nothing behind it shows
	return seen


func _is_see_through(mi: MeshInstance3D) -> bool:
	var mat := mi.get_active_material(0) as BaseMaterial3D
	return mat != null and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED


func _deselect(nodes: Array[Node]) -> void:
	if nodes.is_empty():
		return
	var selection := EditorInterface.get_selection()
	# Don't call EditorInterface.edit_node() here: it re-selects just that one
	# node and would drop the rest of the selection.
	for node in nodes:
		selection.remove_node(node)


# --- Shift+right remove --------------------------------------------------------

## Handles input during a remove drag. Returns true if it used the event.
func _remove_input(camera: Camera3D, event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		_remove_to = (event as InputEventMouseMotion).position
		update_overlays()
		return true
	var key := event as InputEventKey
	if key and key.pressed and key.keycode == KEY_ESCAPE:
		_cancel_remove()
		return true
	var mb := event as InputEventMouseButton
	if mb == null:
		return false
	if mb.button_index != MOUSE_BUTTON_RIGHT or mb.pressed:
		_cancel_remove()   # another button, or we missed the release: give up
		return false
	_remove_to = mb.position
	var from := _remove_from
	_cancel_remove()
	_remove_from_selection(camera, from, mb.position)
	return true


func _cancel_remove() -> void:
	if _removing:
		_removing = false
		update_overlays()


## With force-draw-over on, Godot calls this one (not _forward_3d_draw_over_viewport).
func _forward_3d_force_draw_over_viewport(overlay: Control) -> void:
	if not _removing or _remove_from.distance_to(_remove_to) <= DRAG_THRESHOLD:
		return
	if _editor_viewport_of(overlay) != _remove_view:
		return   # another split view
	var rect := Rect2(_remove_from, Vector2.ZERO).expand(_remove_to)
	overlay.draw_rect(rect, REMOVE_FILL)
	overlay.draw_rect(rect, REMOVE_EDGE, false, 1.0)


func _remove_from_selection(camera: Camera3D, from: Vector2, to: Vector2) -> void:
	var selection := EditorInterface.get_selection()
	var selected := selection.get_selected_nodes()
	var root := EditorInterface.get_edited_scene_root()
	if selected.is_empty() or root == null:
		return
	if from.distance_to(to) <= DRAG_THRESHOLD:
		var target := _pick(camera, to, {})
		if target == null or target not in selected:
			target = _icon_under(camera, to, selected)
		if target:
			var one: Array[Node] = [target]
			_deselect(one)
		return
	var rect := Rect2(from, Vector2.ZERO).expand(to)
	var info := _scene_info(camera, root)
	var gone: Array[Node] = []
	for node in _selected_in_rect(camera, rect, selected, info):
		if _visible_in_rect(camera, node, rect, info):
			gone.append(node)
	_deselect(gone)


## The selected light/camera/etc. whose icon is under `pos`, if any.
func _icon_under(camera: Camera3D, pos: Vector2, selected: Array[Node]) -> Node:
	var best: Node = null
	var best_d := ICON_RADIUS * EditorInterface.get_editor_scale()
	for node in selected:
		if not (node is Node3D) or not _has_own_gizmo(node):
			continue
		var p := (node as Node3D).global_position
		if camera.is_position_behind(p):
			continue
		var d := _to_screen(camera, p).distance_to(pos)
		if d <= best_d:
			best_d = d
			best = node
	return best


## The selected nodes that sit wholly inside `rect`: every vertex of every
## visible mesh they own, or their origin if they have no mesh.
func _selected_in_rect(camera: Camera3D, rect: Rect2, selected: Array[Node], info: Dictionary) -> Array[Node]:
	var inside: Array[Node] = []
	for node in selected:
		if not (node is Node3D) or not node.is_inside_tree():
			continue
		var own: Array = info.meshes.get(node, [])
		if own.is_empty():
			if _screen_point_in(camera, (node as Node3D).global_position, rect):
				inside.append(node)
			continue
		var all_in := true
		for mi in own:
			if not _mesh_inside_rect(camera, mi, rect):
				all_in = false
				break
		if all_in:
			inside.append(node)
	return inside


func _mesh_inside_rect(camera: Camera3D, mi: MeshInstance3D, rect: Rect2) -> bool:
	var xform := mi.global_transform
	var skinned := _is_skinned(mi)
	if not skinned:
		# Whole bounding box inside: no need to look at vertices.
		var box := mi.get_aabb()
		var corners_in := true
		for i in 8:
			if not _screen_point_in(camera, xform * box.get_endpoint(i), rect):
				corners_in = false
				break
		if corners_in:
			return true
	var tris := _triangles_for(mi, skinned)
	if tris == null:
		return false
	for v in tris.get_faces():
		if not _screen_point_in(camera, xform * v, rect):
			return false
	return true


func _screen_point_in(camera: Camera3D, p: Vector3, rect: Rect2) -> bool:
	return not camera.is_position_behind(p) and rect.has_point(_to_screen(camera, p))


# --- Click pick ----------------------------------------------------------------

## `target` is the node our ray hit (or null); `candidates` are the nodes whose
## bounding boxes the ray went through, i.e. what the built-in pick may have
## chosen by mistake.
func _settle(target: Node, candidates: Dictionary, additive: bool, before: Array[Node]) -> void:
	if _claimed():
		return
	var selection := EditorInterface.get_selection()
	var now := selection.get_selected_nodes()
	# What the built-in pick chose: the node it selected, or for shift-click,
	# the nodes it toggled.
	var builtin: Array[Node] = []
	if additive:
		for node in now:
			if node not in before:
				builtin.append(node)
		for node in before:
			if node not in now:
				builtin.append(node)
	elif now.size() == 1:
		builtin = now.duplicate()
	for node in builtin:
		if node != target and (not candidates.has(node) or _has_own_gizmo(node)):
			return   # it chose something with a gizmo of its own (a light, a sprite, ...): trust it

	var want: Array[Node] = []
	if additive:
		want = before.duplicate()
		if target:
			if target in want:
				want.erase(target)
			else:
				want.append(target)
	elif target:
		want = [target]
	if want == now:
		return
	selection.clear()
	for node in want:
		if is_instance_valid(node) and node.is_inside_tree():
			selection.add_node(node)
	if not additive and target:
		EditorInterface.edit_node(target)


func _near_selection_gizmo(camera: Camera3D, pos: Vector2) -> bool:
	var center := Vector3.ZERO
	var count := 0
	for node in _before:
		if node is Node3D and node.is_inside_tree():
			center += (node as Node3D).global_position
			count += 1
	if count == 0:
		return false
	center /= count
	if camera.is_position_behind(center):
		return false
	var size := float(EditorInterface.get_editor_settings().get_setting("editors/3d/manipulator_gizmo_size"))
	var radius := size * EditorInterface.get_editor_scale()
	return _to_screen(camera, center).distance_to(pos) <= radius


## Nodes with gizmos of their own that the built-in pick can rightly choose.
func _has_own_gizmo(node: Node) -> bool:
	if node is MeshInstance3D or node is CollisionObject3D:
		return false
	if node is VisualInstance3D and not (node is GeometryInstance3D):
		return true   # lights, probes, decals, GI, fog volumes
	for type in [Camera3D, AudioStreamPlayer3D, AudioListener3D, CollisionShape3D,
			CollisionPolygon3D, GPUParticles3D, CPUParticles3D, SpriteBase3D, Label3D,
			CSGShape3D, MultiMeshInstance3D, Marker3D, Path3D, RayCast3D, ShapeCast3D,
			VisibleOnScreenNotifier3D, Joint3D, SpringArm3D, NavigationRegion3D]:
		if is_instance_of(node, type):
			return true
	return false


func _pick(camera: Camera3D, pos: Vector2, candidates: Dictionary) -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	var vp_pos := _to_viewport(camera, pos)
	var origin := camera.project_ray_origin(vp_pos)
	var dir := camera.project_ray_normal(vp_pos)

	var best: Node = null
	var best_dist := INF
	for mi in _visible_meshes(root, camera.get_world_3d()):
		var d := _hit_distance(mi, origin, dir)
		if is_nan(d):
			continue   # missed even the bounding box
		var target := _selectable_for(mi, root)
		if target == null:
			continue
		candidates[target] = true
		if d < best_dist:
			best_dist = d
			best = target
	return best


## Every MeshInstance3D under `root` that's drawn in `world` and not hidden.
func _visible_meshes(root: Node, world: World3D) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Node3D and not (node as Node3D).visible:
			continue   # hidden branches can't be clicked on
		if node is SubViewport:
			continue
		stack.append_array(node.get_children(true))
		var mi := node as MeshInstance3D
		if mi and mi.mesh and mi.get_world_3d() == world:
			found.append(mi)
	return found


## Distance along the ray to the mesh surface; INF if the ray goes through the
## bounding box but misses the mesh, NAN if it misses the bounding box too.
func _hit_distance(mi: MeshInstance3D, origin: Vector3, dir: Vector3) -> float:
	var xform := mi.global_transform
	if absf(xform.basis.determinant()) < 1e-8:
		return NAN   # scaled to zero
	var inv := xform.affine_inverse()
	var local_origin := inv * origin
	var local_dir := inv.basis * dir
	var skinned := _is_skinned(mi)
	if not skinned and mi.get_aabb().grow(0.001).intersects_ray(local_origin, local_dir) == null:
		return NAN
	var tris := _triangles_for(mi, skinned)
	if tris == null:
		return INF
	var hit := tris.intersect_ray(local_origin, local_dir)
	if hit.is_empty():
		return INF
	return origin.distance_to(xform * (hit["position"] as Vector3))


# --- Shared helpers ------------------------------------------------------------

## The map tools plugin (addons/map_tools) used this click for one of its own tools
## (drawing a block, cutting one, dragging one): leave the selection as it left it.
## It notes the frame it used a click in; both plugins are handed every click.
func _claimed() -> bool:
	return absi(Engine.get_process_frames() - int(Engine.get_meta(&"map_tools_claimed", -10))) <= 1

## The editor viewport's 3D image is shrunk when Half Resolution is on; mouse
## positions are not.
func _shrink(camera: Camera3D) -> float:
	var container := camera.get_viewport().get_parent() as SubViewportContainer
	return float(container.stretch_shrink) if container and container.stretch else 1.0


func _to_viewport(camera: Camera3D, pos: Vector2) -> Vector2:
	return pos / _shrink(camera)


func _to_screen(camera: Camera3D, p: Vector3) -> Vector2:
	return camera.unproject_position(p) * _shrink(camera)


## The Node3DEditorViewport (one split view) that `node` is part of.
func _editor_viewport_of(node: Node) -> Node:
	while node and node.get_class() != "Node3DEditorViewport":
		node = node.get_parent()
	return node


func _is_skinned(mi: MeshInstance3D) -> bool:
	var skeleton := mi.get_node_or_null(mi.skeleton) if not mi.skeleton.is_empty() else null
	if mi.skin == null and not (skeleton is Skeleton3D):
		return false
	var am := mi.mesh as ArrayMesh
	if am == null:
		return false
	for s in am.get_surface_count():
		if am.surface_get_format(s) & Mesh.ARRAY_FORMAT_BONES:
			return true
	return false


func _triangles_for(mi: MeshInstance3D, skinned: bool) -> TriangleMesh:
	if skinned:
		# Posed characters: test the mesh as it's drawn now, not its rest pose.
		var baked := mi.bake_mesh_from_current_skeleton_pose()
		if baked:
			return baked.generate_triangle_mesh()
	var mesh := mi.mesh
	var id := mesh.get_instance_id()
	if _tri_cache.has(id):
		return _tri_cache[id][0]
	var tris := mesh.generate_triangle_mesh()
	var forget := _forget_mesh.bind(id)
	_tri_cache[id] = [tris, forget]
	mesh.changed.connect(forget, CONNECT_ONE_SHOT)
	return tris


func _forget_mesh(id: int) -> void:
	_tri_cache.erase(id)


## The node a click on `node` should select, mirroring the built-in pick.
func _selectable_for(node: Node, root: Node) -> Node:
	# Internal helper meshes (no owner) belong to the nearest real node above.
	var n := node
	while n and n != root and n.owner == null:
		n = n.get_parent()
	if n == null:
		return null
	# Inside an instanced scene, stop at the instance unless it has Editable Children.
	var result := n
	var it := n
	while it.owner and it.owner != root:
		if not root.is_editable_instance(it.owner):
			result = it.owner
		it = it.owner
	# A selection group selects its topmost grouped ancestor.
	var up := result
	while up and up != root.get_parent():
		if up is Node3D and up.get_meta("_edit_group_", false):
			result = up
		up = up.get_parent()
	# Locked, or inside something locked (a layer locked in the Map dock): not picked.
	var held := result
	while held and held != root.get_parent():
		if held.get_meta("_edit_lock_", false):
			return null
		held = held.get_parent()
	return result
