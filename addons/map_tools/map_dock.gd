@tool
extends EditorDock
## The Map dock. Kinds: the map's palette as swatches. Click one to make it the kind
## new blocks get, and to paint the selected blocks with it; right-click one to
## select every block of that kind. Prefabs: groups of blocks saved under
## game/maps/prefabs; pick one and click in the map to put a copy down (Place Linked:
## the prefab itself, which changes when the prefab does). Layers: the map's top-level
## groups, each with switches for in view (editor only), locked, and in the game.
##
## It only shows things and says what was pressed; plugin.gd acts.

const MapOps := preload("res://addons/map_tools/map_ops.gd")

const PREFAB_DIR := "res://game/maps/prefabs"

## A swatch was clicked.
signal kind_chosen(kind: String)
## A swatch was right-clicked.
signal kind_selected(kind: String)
signal add_kind_pressed
## Place was pressed (or a prefab double-clicked): the prefab's file.
signal prefab_chosen(path: String)
## Place Linked was pressed: the prefab's file.
signal prefab_linked(path: String)
signal save_prefab_pressed
## A layer's switch: `what` is "view", "lock" or "game".
signal layer_toggled(node: Node3D, what: String, on: bool)
## The Problems list's Check was pressed (`flicker`: look for flickering too).
signal check_requested(flicker: bool)
## A problem was picked in the list: its index.
signal problem_chosen(index: int)

var ctx: RefCounted   # MapContext

var _kinds: VBoxContainer
var _no_map: Label
var _add_kind: Button
var _prefabs: ItemList
var _place: Button
var _missing: Label
var _layers: VBoxContainer
var _problems: ItemList
var _problems_note: Label
var _dirty := true
var _palette: MapPalette


func _init() -> void:
	title = "Map"
	default_slot = EditorDock.DOCK_SLOT_LEFT_BR
	var tabs := TabContainer.new()
	add_child(tabs)

	var kinds_tab := VBoxContainer.new()
	kinds_tab.name = "Kinds"
	tabs.add_child(kinds_tab)
	_no_map = Label.new()
	_no_map.text = "Open a map (a scene whose root is a MapRoot) to see its palette."
	_no_map.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kinds_tab.add_child(_no_map)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	kinds_tab.add_child(scroll)
	_kinds = VBoxContainer.new()
	_kinds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_kinds)
	_add_kind = Button.new()
	_add_kind.text = "Add Kind..."
	_add_kind.tooltip_text = "Add a colour to this map's palette."
	_add_kind.pressed.connect(func() -> void: add_kind_pressed.emit())
	kinds_tab.add_child(_add_kind)

	var prefabs_tab := VBoxContainer.new()
	prefabs_tab.name = "Prefabs"
	tabs.add_child(prefabs_tab)
	_prefabs = ItemList.new()
	_prefabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_prefabs.item_selected.connect(func(_i: int) -> void: _show_missing())
	_prefabs.item_activated.connect(func(i: int) -> void: prefab_chosen.emit(_prefabs.get_item_metadata(i)))
	prefabs_tab.add_child(_prefabs)
	_missing = Label.new()
	_missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prefabs_tab.add_child(_missing)
	var row := HBoxContainer.new()
	prefabs_tab.add_child(row)
	_place = Button.new()
	_place.text = "Place"
	_place.tooltip_text = "Then click in the map: each click puts down a copy. Esc to stop."
	_place.pressed.connect(func() -> void:
		var picked := _prefabs.get_selected_items()
		if not picked.is_empty():
			prefab_chosen.emit(_prefabs.get_item_metadata(picked[0])))
	row.add_child(_place)
	var linked := Button.new()
	linked.text = "Place Linked"
	linked.tooltip_text = "Then click in the map: each click puts down the prefab itself, linked to its file, so every linked copy changes when you change the prefab. (To change one copy alone, right-click it in the Scene dock and Make Local.) Esc to stop."
	linked.pressed.connect(func() -> void:
		var picked := _prefabs.get_selected_items()
		if not picked.is_empty():
			prefab_linked.emit(_prefabs.get_item_metadata(picked[0])))
	row.add_child(linked)
	var save := Button.new()
	save.text = "Save Selection..."
	save.tooltip_text = "Save the selected blocks and groups as a prefab."
	save.pressed.connect(func() -> void: save_prefab_pressed.emit())
	row.add_child(save)

	var layers_tab := VBoxContainer.new()
	layers_tab.name = "Layers"
	tabs.add_child(layers_tab)
	var key := Label.new()
	key.text = "View: shown in the editor.  Lock: clicks in the 3D view pass it by.  Game: in the game (off: left out, as the eye icon does)."
	key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layers_tab.add_child(key)
	var layer_scroll := ScrollContainer.new()
	layer_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layers_tab.add_child(layer_scroll)
	_layers = VBoxContainer.new()
	_layers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer_scroll.add_child(_layers)

	var problems_tab := VBoxContainer.new()
	problems_tab.name = "Problems"
	tabs.add_child(problems_tab)
	var check_row := HBoxContainer.new()
	problems_tab.add_child(check_row)
	var flicker := CheckBox.new()
	flicker.text = "Flickering too (slow)"
	flicker.tooltip_text = "Also look for two colours in one plane where both show (they flicker as the camera moves). Takes a while on a big map."
	var check := Button.new()
	check.text = "Check Map"
	check.tooltip_text = "Look the open map over: block warnings, leftover slivers, spawn points, terminals without their event."
	check.pressed.connect(func() -> void: check_requested.emit(flicker.button_pressed))
	check_row.add_child(check)
	check_row.add_child(flicker)
	_problems_note = Label.new()
	_problems_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems_note.text = "Press Check Map. Click a problem to select what it is about."
	problems_tab.add_child(_problems_note)
	_problems = ItemList.new()
	_problems.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_problems.item_selected.connect(func(i: int) -> void: problem_chosen.emit(i))
	problems_tab.add_child(_problems)
	set_process(true)


## Shows what a check found (the texts, worst first).
func show_problems(texts: Array) -> void:
	if _problems == null:
		return
	_problems.clear()
	for t: String in texts:
		var i := _problems.add_item(t)
		_problems.set_item_tooltip(i, t)
	_problems_note.text = "Nothing found." if texts.is_empty() else "%d found. Click one to select what it is about." % texts.size()


## Something it shows may have changed: redraw soon (once, however often this is called).
func queue_refresh() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty and is_visible_in_tree():
		_dirty = false
		_refresh_kinds()
		_refresh_layers()


## The map's layers: its top-level groups that hold blocks.
func _refresh_layers() -> void:
	for c in _layers.get_children():
		_layers.remove_child(c)
		c.queue_free()
	if ctx == null or ctx.map == null:
		return
	var hidden: Dictionary = Engine.get_meta(&"map_tools_view_hidden", {})
	for node in ctx.map.get_children():
		if not (node is Node3D) or node is MapBlock:
			continue
		var count := MapOps.blocks_in(node).size()
		if count == 0:
			continue
		var layer := node as Node3D
		var row := HBoxContainer.new()
		for spec in [["view", "View", not hidden.has(layer.get_instance_id()), "Shown in the editor (the scene is not changed)."],
				["lock", "Lock", layer.get_meta("_edit_lock_", false), "Locked: clicks in the 3D view pass it by."],
				["game", "Game", layer.visible, "In the game. Off: left out of the game (the eye icon)."]]:
			var box := CheckBox.new()
			box.text = spec[1]
			box.button_pressed = spec[2]
			box.tooltip_text = spec[3]
			box.focus_mode = Control.FOCUS_NONE
			box.toggled.connect(func(on: bool) -> void: layer_toggled.emit(layer, spec[0], on))
			row.add_child(box)
		var label := Label.new()
		label.text = "%s   %d" % [layer.name, count]
		label.tooltip_text = "%d blocks." % count
		label.clip_text = true
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		_layers.add_child(row)


func _refresh_kinds() -> void:
	for c in _kinds.get_children():
		_kinds.remove_child(c)
		c.queue_free()
	var palette: MapPalette = ctx.map.palette if ctx and ctx.map else null
	if palette != _palette:
		if _palette and _palette.changed.is_connected(queue_refresh):
			_palette.changed.disconnect(queue_refresh)
		_palette = palette
		if _palette:
			_palette.changed.connect(queue_refresh)
	_no_map.visible = palette == null
	_add_kind.disabled = palette == null
	if palette == null:
		return
	var counts := {}
	for b in MapOps.blocks_in(ctx.map):
		counts[b.kind] = counts.get(b.kind, 0) + 1
	var names: Array = palette.colors.keys()
	for k in counts:
		if k not in names:
			names.append(k)   # used by a block, but not in the palette
	for k: String in names:
		var known := palette.colors.has(k)
		var b := Button.new()
		# (Not a toggle: a click on the kind already chosen must still paint the selection.)
		b.text = "%s%s   %d" % ["> " if k == ctx.kind else "", k, counts.get(k, 0)]
		b.icon = _swatch(palette.colors[k] if known else Color.MAGENTA)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.flat = k != ctx.kind
		b.focus_mode = Control.FOCUS_NONE
		var tip := "%d blocks." % counts.get(k, 0)
		if not known:
			tip = "Not in the palette: blocks of this kind are drawn magenta. " + tip
		elif palette.surface.has(k):
			tip = "Pattern: %s. %s" % [palette.surface[k], tip]
		b.tooltip_text = tip + "\nClick: new blocks get this kind, and the selected blocks are painted with it.\nRight-click: select every block of this kind."
		b.pressed.connect(func() -> void: kind_chosen.emit(k))
		b.gui_input.connect(func(event: InputEvent) -> void:
			var mb := event as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				kind_selected.emit(k))
		_kinds.add_child(b)


func _swatch(color: Color) -> Texture2D:
	var size := int(16 * EditorInterface.get_editor_scale())
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(color.r, color.g, color.b, 1.0))
	return ImageTexture.create_from_image(image)


## Lists the prefab files again.
func refresh_prefabs() -> void:
	var was := ""
	var picked := _prefabs.get_selected_items()
	if not picked.is_empty():
		was = _prefabs.get_item_metadata(picked[0])
	_prefabs.clear()
	if DirAccess.dir_exists_absolute(PREFAB_DIR):
		var files := DirAccess.get_files_at(PREFAB_DIR)
		files.sort()
		for f in files:
			if f.get_extension() == "tscn":
				var i := _prefabs.add_item(f.get_basename())
				_prefabs.set_item_metadata(i, PREFAB_DIR.path_join(f))
				if PREFAB_DIR.path_join(f) == was:
					_prefabs.select(i)
	_show_missing()


## Says which kinds the picked prefab uses that this map's palette lacks.
func _show_missing() -> void:
	_missing.text = ""
	var picked := _prefabs.get_selected_items()
	if picked.is_empty() or ctx == null or ctx.map == null:
		return
	var scene := load(_prefabs.get_item_metadata(picked[0])) as PackedScene
	if scene == null:
		return
	var sample := scene.instantiate()
	var missing := MapOps.missing_kinds(sample, ctx.map.palette)
	sample.free()
	if not missing.is_empty():
		_missing.text = "This map's palette has no colour for: %s" % ", ".join(missing)
