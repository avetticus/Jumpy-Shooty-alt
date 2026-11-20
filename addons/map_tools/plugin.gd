@tool
extends EditorPlugin
## The map tools: everything the editor adds for building maps out of MapBlocks.
##
##  - Gizmos: click a block to select it, drag a face handle to resize it (it snaps to
##    the grid and to neighbours' faces), the map's bounds, and handles on stairs, ramps
##    and rows (block_gizmo.gd, map_gizmo.gd, piece_gizmo.gd).
##  - A strip in the 3D toolbar, shown while a map is open (map_toolbar.gd): the
##    Draw and Clip tools, the grid size, quick toggles and the Map menu (Hollow,
##    Mirror, Array, Snap to Neighbours, the pieces, prefabs, view switches).
##  - The Map dock (map_dock.gd): the palette's kinds and the prefabs.
##  - Rebuild and Bake buttons on a MapPiece's inspector (piece_inspector.gd).
##
## What the tools do is in files with no editor in them, so tests/map_tools_test.gd
## can run them: map_ops.gd (the geometry), tool_*.gd (what the mouse does),
## map_commands.gd (the one-shot commands). They hand back a MapEdit; apply_edit()
## here makes it one undo step.

const MapOps := preload("res://addons/map_tools/map_ops.gd")
const MapEdit := preload("res://addons/map_tools/map_edit.gd")
const MapContext := preload("res://addons/map_tools/map_context.gd")
const MapView := preload("res://addons/map_tools/map_view.gd")
const MapCommands := preload("res://addons/map_tools/map_commands.gd")
const MapToolbar := preload("res://addons/map_tools/map_toolbar.gd")
const MapDialogs := preload("res://addons/map_tools/map_dialogs.gd")
const MapDock := preload("res://addons/map_tools/map_dock.gd")
const PieceInspector := preload("res://addons/map_tools/piece_inspector.gd")

## The tools. Draw, Clip and Vertex have a button in the strip (in this order: the
## strip counts them from 1); SELECT is none of them: the editor's own select, move,
## rotate and scale.
enum Tool { SELECT, DRAW, CLIP, VERTEX, PLACE }

## Editor shortcuts (Editor Settings > Shortcuts > Map Tools): [name, title, key, with Alt].
const SHORTCUTS := [
	["grid_down", "Finer Grid", KEY_BRACKETLEFT, false],
	["grid_up", "Coarser Grid", KEY_BRACKETRIGHT, false],
	["tool_draw", "Draw Tool", KEY_B, false],
	["tool_clip", "Clip Tool", KEY_K, false],
	["clip_turn", "Clip: Next Cut Direction", KEY_X, false],
	["tool_vertex", "Vertex Tool", KEY_V, false],
	["solid", "Toggle Solid", KEY_S, true],
	["drawn", "Toggle Drawn", KEY_D, true],
	["breakable", "Toggle Breakable", KEY_B, true],
	["hollow", "Hollow", KEY_H, true],
	["snap", "Snap to Neighbours", KEY_N, true],
]

var ctx: RefCounted        # MapContext
var tool := Tool.SELECT

var _blocks: EditorNode3DGizmoPlugin
var _maps: EditorNode3DGizmoPlugin
var _pieces: EditorNode3DGizmoPlugin
var _tools := {}           # Tool -> the tool's object (none for SELECT)
var _held := {}            # mouse button -> a tool used its press
var _toolbar: HBoxContainer
var _dialogs: Node
var _dock: EditorDock
var _inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	ctx = MapContext.new()
	ctx.selection = _selected
	ctx.commit = apply_edit
	ctx.select = _select
	ctx.grid = EditorInterface.get_editor_settings().get_project_metadata("map_tools", "grid", 0.5)
	for t: Array in [[Tool.DRAW, "tool_draw.gd"], [Tool.CLIP, "tool_clip.gd"], [Tool.VERTEX, "tool_vertex.gd"], [Tool.PLACE, "tool_place.gd"]]:
		var made: RefCounted = load("res://addons/map_tools/" + t[1]).new()
		made.ctx = ctx
		_tools[t[0]] = made
	_tools[Tool.PLACE].done = func() -> void: set_tool(Tool.SELECT)

	_blocks = preload("res://addons/map_tools/block_gizmo.gd").new()
	_blocks.ctx = ctx
	_maps = preload("res://addons/map_tools/map_gizmo.gd").new()
	add_node_3d_gizmo_plugin(_blocks)
	add_node_3d_gizmo_plugin(_maps)
	_pieces = preload("res://addons/map_tools/piece_gizmo.gd").new()
	_pieces.ctx = ctx
	add_node_3d_gizmo_plugin(_pieces)

	_register_shortcuts()
	_toolbar = MapToolbar.new()
	_toolbar.tool_chosen.connect(func(t: int) -> void: set_tool(Tool.SELECT if tool == t else t))
	_toolbar.grid_stepped.connect(step_grid)
	_toolbar.command.connect(run)
	_toolbar.show_keys(_shortcut_keys())
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_dialogs = MapDialogs.new()
	EditorInterface.get_base_control().add_child(_dialogs)
	_dock = MapDock.new()
	_dock.ctx = ctx
	_dock.kind_chosen.connect(_on_kind_chosen)
	_dock.kind_selected.connect(_on_kind_selected)
	_dock.add_kind_pressed.connect(func() -> void: _dialogs.ask_kind(_add_kind))
	_dock.prefab_chosen.connect(place_prefab)
	_dock.save_prefab_pressed.connect(func() -> void: run("prefab"))
	add_dock(_dock)
	_inspector = PieceInspector.new()
	_inspector.bake = func(piece: MapPiece) -> void: apply_edit(MapCommands.bake(piece))
	add_inspector_plugin(_inspector)

	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	scene_changed.connect(_on_scene_changed)
	get_undo_redo().version_changed.connect(_on_edited)
	get_undo_redo().history_changed.connect(_on_edited)   # this one fires when a step is first done
	ctx.changed.connect(_on_context_changed)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_dock.refresh_prefabs)
	_dock.refresh_prefabs()
	_on_scene_changed(EditorInterface.get_edited_scene_root())


func _exit_tree() -> void:
	scene_changed.disconnect(_on_scene_changed)
	get_undo_redo().version_changed.disconnect(_on_edited)
	get_undo_redo().history_changed.disconnect(_on_edited)
	EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(_dock.refresh_prefabs)
	remove_node_3d_gizmo_plugin(_blocks)
	remove_node_3d_gizmo_plugin(_maps)
	remove_node_3d_gizmo_plugin(_pieces)
	remove_inspector_plugin(_inspector)
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.queue_free()
	remove_dock(_dock)
	_dock.queue_free()
	_dialogs.queue_free()
	_set_solid_only(false)
	# The context and the things that hold it hold each other: let go.
	_tools[Tool.PLACE].done = Callable()
	_inspector.bake = Callable()
	ctx.selection = Callable()
	ctx.commit = Callable()
	ctx.select = Callable()
	_tools.clear()


# ---------------------------------------------------------------------------
# The map being edited

func _on_scene_changed(root: Node) -> void:
	for t in _tools.values():
		t.cancel()
	tool = Tool.SELECT
	ctx.editing_corners = false
	ctx.map = root as MapRoot
	_toolbar.visible = ctx.map != null
	if ctx.map and ctx.map.palette and not ctx.map.palette.colors.has(ctx.kind) and not ctx.map.palette.colors.is_empty():
		ctx.kind = ctx.map.palette.colors.keys()[0]
	if ctx.map:
		_toolbar.show_view("view:invisible", ctx.map.show_invisible_blocks)
	_on_context_changed()


## Something was done, undone or redone.
func _on_edited() -> void:
	if ctx.map == null or not is_instance_valid(ctx.map):
		return
	ctx.touch()
	for piece in get_tree().get_nodes_in_group(MapPiece.GROUP):
		if piece.has_method("refresh_if_changed") and ctx.map.is_ancestor_of(piece):
			piece.refresh_if_changed()
	_dock.queue_refresh()
	update_overlays()


func _on_context_changed() -> void:
	_toolbar.show_state(tool, ctx.grid)
	_dock.queue_refresh()


func _selected() -> Array:
	return EditorInterface.get_selection().get_selected_nodes()


func _select(nodes: Array) -> void:
	var selection := EditorInterface.get_selection()
	selection.clear()
	var last: Node = null
	for n in nodes:
		if is_instance_valid(n) and (n as Node).is_inside_tree():
			selection.add_node(n)
			last = n
	if last and selection.get_selected_nodes().size() == 1:
		EditorInterface.edit_node(last)


# ---------------------------------------------------------------------------
# Changes, as undo steps

## Makes a MapEdit one step in the editor's undo history.
func apply_edit(edit: RefCounted) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if edit == null or edit.is_empty() or root == null:
		return
	var undo := get_undo_redo()
	var before := _selected()
	undo.create_action(edit.name, UndoRedo.MERGE_DISABLE, root)
	for r: Node in edit.removes:
		var parent := r.get_parent()
		undo.add_do_method(parent, "remove_child", r)
		undo.add_undo_method(parent, "add_child", r, true)
		undo.add_undo_method(parent, "move_child", r, r.get_index())
		undo.add_undo_method(self, "_adopt", r, root)
		undo.add_undo_reference(r)
	for a in edit.adds:
		var parent: Node = a[0]
		var node: Node = a[1]
		undo.add_do_method(parent, "add_child", node, true)
		if a[2] >= 0:
			undo.add_do_method(parent, "move_child", node, a[2])
		undo.add_do_method(self, "_adopt", node, root)
		undo.add_do_reference(node)
		undo.add_undo_method(parent, "remove_child", node)
	for s in edit.sets:
		undo.add_do_property(s[0], s[1], s[2])
		undo.add_undo_property(s[0], s[1], s[3])
	for c in edit.do_calls:
		undo.callv("add_do_method", c)
	for c in edit.undo_calls:
		undo.callv("add_undo_method", c)
	if edit.reselect:
		undo.add_do_method(self, "_select", edit.select)
		undo.add_undo_method(self, "_select", before)
	undo.commit_action()


func _adopt(node: Node, root: Node) -> void:
	if is_instance_valid(node) and is_instance_valid(root) and root.is_ancestor_of(node):
		MapPiece.adopt(node, root)


# ---------------------------------------------------------------------------
# Tools and the mouse

func set_tool(to: int) -> void:
	if _tools.has(tool):
		_tools[tool].cancel()
	tool = to as Tool
	_toolbar.show_state(tool, ctx.grid)
	# The vertex tool takes the clicks: the face handles are put away while it is on.
	ctx.editing_corners = tool == Tool.VERTEX
	for n in _selected():
		if n is Node3D:
			for b in MapOps.blocks_in(n):
				b.update_gizmos()
	update_overlays()


func step_grid(dir: int) -> void:
	ctx.grid = MapOps.grid_step(ctx.grid, dir)
	EditorInterface.get_editor_settings().set_project_metadata("map_tools", "grid", ctx.grid)
	update_overlays()


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if ctx.map == null or not is_instance_valid(ctx.map):
		return AFTER_GUI_INPUT_PASS
	var view := _view_of(camera)
	var used := false
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		ctx.touch()   # a click always works from the scene as it is now
	if _tools.has(tool):
		used = _tools[tool].input(view, event)
		if event is InputEventMouse or used:
			update_overlays()
	var key := event as InputEventKey
	if not used and key and key.pressed and not key.echo and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		used = _key(key)
	# A button whose press a tool used: its release is the tool's too, whatever the tool
	# says, so the editor never sees half a click.
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		_held[mb.button_index] = used
	elif mb and _held.get(mb.button_index, false):
		_held.erase(mb.button_index)
		used = true
	if used:
		# Tell mesh_pick (which sees every click too) that this one was ours.
		Engine.set_meta(&"map_tools_claimed", Engine.get_process_frames())
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _key(key: InputEventKey) -> bool:
	var settings := EditorInterface.get_editor_settings()
	for s in SHORTCUTS:
		if not settings.is_shortcut("map_tools/" + s[0], key):
			continue
		match s[0]:
			"grid_down": step_grid(-1)
			"grid_up": step_grid(1)
			"tool_draw": set_tool(Tool.SELECT if tool == Tool.DRAW else Tool.DRAW)
			"tool_clip": set_tool(Tool.SELECT if tool == Tool.CLIP else Tool.CLIP)
			"tool_vertex": set_tool(Tool.SELECT if tool == Tool.VERTEX else Tool.VERTEX)
			"clip_turn":
				if tool != Tool.CLIP:
					return false
				_tools[Tool.CLIP].next_direction()
				update_overlays()
			_: run(s[0])
		return true
	if key.keycode == KEY_ESCAPE and tool != Tool.SELECT:
		set_tool(Tool.SELECT)
		return true
	return false


func _forward_3d_force_draw_over_viewport(overlay: Control) -> void:
	if ctx.map == null or not _tools.has(tool):
		return
	var camera := _camera_for(overlay)
	if camera:
		_tools[tool].draw(_view_of(camera), overlay)


func _view_of(camera: Camera3D) -> RefCounted:
	var container := camera.get_viewport().get_parent() as SubViewportContainer
	return MapView.new(camera, float(container.stretch_shrink) if container and container.stretch else 1.0)


## The camera of the split view an overlay belongs to.
func _camera_for(overlay: Control) -> Camera3D:
	var mine := _split_of(overlay)
	for i in 4:
		var viewport := EditorInterface.get_editor_viewport_3d(i)
		if viewport and _split_of(viewport) == mine:
			return viewport.get_camera_3d()
	return null


func _split_of(node: Node) -> Node:
	while node and node.get_class() != "Node3DEditorViewport":
		node = node.get_parent()
	return node


# ---------------------------------------------------------------------------
# Commands

## Runs a command from the strip, the menu or a shortcut.
func run(what: String) -> void:
	if ctx.map == null:
		return
	if what.begins_with("piece:"):
		var sort := what.trim_prefix("piece:")
		_tools[Tool.PLACE].start(func() -> Node3D: return MapCommands.new_piece(sort, ctx.kind), sort.to_lower())
		set_tool(Tool.PLACE)
		return
	match what:
		"solid", "drawn", "breakable":
			apply_edit(MapCommands.toggle(ctx, what))
		"snap":
			apply_edit(MapCommands.snap_to_neighbours(ctx))
		"csg_subtract":
			var edit := MapCommands.subtract(ctx)
			if edit.is_empty():
				_dialogs.tell("Select the blocks to carve out of the others. They are taken out of every block they overlap, and then removed. (Tubes, arches and hollow domes cannot be cut: Make Editable them first.)")
			else:
				apply_edit(edit)
		"csg_merge", "csg_intersect":
			var edit: RefCounted = MapCommands.merge(ctx) if what == "csg_merge" else MapCommands.intersect(ctx)
			if edit.is_empty():
				_dialogs.tell("Select two or more blocks to %s. Each must be one solid lump (not a tube, an arch or a hollow dome), only the first may have things standing under it, and the result can have at most %d corners.%s" % [
					"merge into one" if what == "csg_merge" else "turn into the part they share",
					MapMesher.MAX_HULL_CORNERS,
					"" if what == "csg_merge" else " They must overlap."])
			else:
				apply_edit(edit)
		"make_editable":
			var edit := MapCommands.make_editable(ctx)
			if edit.is_empty():
				_dialogs.tell("Select one or more MapBlocks to make into hull blocks. Blocks that already are hulls, blocks a Stairs, Row or Ring piece made, and shapes of more than %d corners (lower their Sides) are left as they are." % MapMesher.MAX_HULL_CORNERS)
			else:
				apply_edit(edit)
		"hollow":
			var thickness := maxf(ctx.grid, 0.1) if ctx.grid <= 0.5 else 0.25
			if MapCommands.hollowable(ctx, 0.05) == 0:
				_dialogs.tell("Select one or more MapBlocks to hollow (any one-lump shape: not a tube, an arch or a hollow dome). (A group is not hollowed: pick the block itself in the Scene dock.)")
				return
			_dialogs.ask_hollow(thickness, func(t: float, open_top: bool, no_floor: bool) -> void:
				if MapCommands.hollowable(ctx, t) == 0:
					_dialogs.tell("Walls %s m thick do not fit inside the selected blocks." % String.num(t, 2))
				else:
					apply_edit(MapCommands.hollow(ctx, t, open_top, no_floor)))
		"mirror":
			if ctx.selected_tops().is_empty():
				_dialogs.tell("Select the blocks or groups to mirror.")
				return
			_dialogs.ask_mirror(func(axis: int, about_selection: bool, copy: bool) -> void:
				var pivot := MapCommands.selection_centre(ctx) if about_selection else MapOps.global_of(ctx.map).origin
				apply_edit(MapCommands.mirror(ctx, axis, pivot, copy)))
		"array":
			if ctx.selected_tops().is_empty():
				_dialogs.tell("Select the blocks or groups to copy.")
				return
			_dialogs.ask_array(maxf(ctx.grid, 1.0), func(ring: bool, count: int, vec: Vector3) -> void:
				if ring:
					apply_edit(MapCommands.array_ring(ctx, maxi(count, 2), Vector3(vec.x, 0, vec.z)))
				else:
					apply_edit(MapCommands.array_line(ctx, count, vec)))
		"prefab":
			if ctx.selected_tops().is_empty():
				_dialogs.tell("Select the blocks or groups to save as a prefab.")
				return
			_dialogs.ask_name(_save_prefab)
		"view:invisible":
			ctx.map.show_invisible_blocks = not ctx.map.show_invisible_blocks
			_toolbar.show_view(what, ctx.map.show_invisible_blocks)
			ctx.touch()
		"view:solid":
			_set_solid_only(not ctx.solid_only)
			_toolbar.show_view(what, ctx.solid_only)


## Editor view: show only the blocks you can bump into.
func _set_solid_only(on: bool) -> void:
	ctx.solid_only = on
	Engine.set_meta(&"map_tools_solid_only", on)
	ctx.touch()
	if ctx.map and is_instance_valid(ctx.map):
		for b in MapOps.blocks_in(ctx.map):
			b.refresh_preview()


func _on_kind_chosen(kind: String) -> void:
	ctx.kind = kind
	apply_edit(MapCommands.paint(ctx, kind))


func _on_kind_selected(kind: String) -> void:
	if ctx.map == null:
		return
	var same := []
	for b in MapOps.blocks_in(ctx.map):
		if b.kind == kind and b.is_visible_in_tree():
			same.append(b)
	_select(same)


func _add_kind(kind: String, color: Color) -> void:
	var palette: MapPalette = ctx.map.palette if ctx.map else null
	if palette == null or kind == "":
		return
	if palette.colors.has(kind):
		_dialogs.tell("The palette already has a kind called \"%s\"." % kind)
		return
	var colors := palette.colors.duplicate()
	colors[kind] = color
	var undo := get_undo_redo()
	undo.create_action("Add kind %s to the palette" % kind, UndoRedo.MERGE_DISABLE, ctx.map)
	undo.add_do_method(self, "_set_colors", palette, colors)
	undo.add_undo_method(self, "_set_colors", palette, palette.colors.duplicate())
	undo.commit_action()
	ctx.kind = kind


## Sets a palette's colours and, if it is a file of its own, saves it (a palette is
## shared by every block of the map, so it is not left for the scene's save to catch).
func _set_colors(palette: MapPalette, colors: Dictionary) -> void:
	palette.colors.assign(colors)
	palette.emit_changed()
	if palette.resource_path != "" and not palette.resource_path.contains("::"):
		ResourceSaver.save(palette, palette.resource_path)


# ---------------------------------------------------------------------------
# Prefabs

func _save_prefab(prefab_name: String) -> void:
	var file := prefab_name.validate_filename().to_snake_case()
	if file == "":
		_dialogs.tell("Give the prefab a name.")
		return
	var path: String = MapDock.PREFAB_DIR.path_join(file + ".tscn")
	if FileAccess.file_exists(path):
		_dialogs.tell("There is already a prefab called \"%s\". Pick another name, or delete that one in the FileSystem dock first." % file)
		return
	DirAccess.make_dir_recursive_absolute(MapDock.PREFAB_DIR)
	var root := MapOps.make_prefab(ctx.selected_tops(), prefab_name.to_pascal_case())
	var scene := PackedScene.new()
	var result := scene.pack(root)
	root.free()
	if result == OK:
		result = ResourceSaver.save(scene, path)
	if result != OK:
		_dialogs.tell("Could not save %s (error %d)." % [path, result])
		return
	EditorInterface.get_resource_filesystem().update_file(path)
	_dock.refresh_prefabs()


## Starts placing copies of a prefab with clicks in the map.
func place_prefab(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null or ctx.map == null:
		return
	_tools[Tool.PLACE].start(func() -> Node3D: return MapOps.place_prefab(scene), path.get_file().get_basename())
	set_tool(Tool.PLACE)


# ---------------------------------------------------------------------------
# Shortcuts

func _register_shortcuts() -> void:
	var settings := EditorInterface.get_editor_settings()
	for s in SHORTCUTS:
		var path: String = "map_tools/" + s[0]
		if settings.has_shortcut(path):
			continue
		var event := InputEventKey.new()
		event.keycode = s[2]
		event.alt_pressed = s[3]
		var shortcut := Shortcut.new()
		shortcut.resource_name = s[1]
		shortcut.events = [event]
		settings.add_shortcut(path, shortcut)


## name -> the key it is bound to, as text.
func _shortcut_keys() -> Dictionary:
	var settings := EditorInterface.get_editor_settings()
	var keys := {}
	for s in SHORTCUTS:
		var shortcut := settings.get_shortcut("map_tools/" + s[0])
		if shortcut:
			keys[s[0]] = shortcut.get_as_text()
	return keys
