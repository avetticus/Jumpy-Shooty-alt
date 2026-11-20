@tool
extends HBoxContainer
## The map tools' strip in the 3D editor's toolbar: the tool buttons, the grid size,
## the quick toggles and the Map menu. It only says what was pressed; plugin.gd acts.

const MapCommands := preload("res://addons/map_tools/map_commands.gd")

## A tool button was pressed: 1 = Draw, 2 = Clip (the plugin.s Tool numbers). Pressing
## the one that is on turns it off, back to the editor.s own select and move.
signal tool_chosen(tool: int)
## A grid button was pressed: 1 = bigger, -1 = smaller.
signal grid_stepped(dir: int)
## A toggle or a menu item was chosen (see the names below).
signal command(what: String)

const TOOLS := [
	["Draw", "Drag out a new block. In the 3D view: drag its footprint on a face or the ground, let go, pull it out and click. In a top, front or side view: drag a rectangle."],
	["Clip", "Cut the selected blocks in two where you click. Drag a line to cut at an angle (in 3D, across a face; click a third point to tilt it), then Enter; X chooses which parts to keep."],
	["Vertex", "Move the corners of the selected hull blocks: click or drag a box to pick corners, drag them (Shift: up and down), arrow keys to nudge, Delete to remove, double-click an edge or face to add one."],
]
const MENU := [
	["Hollow...", "hollow"],
	["Mirror...", "mirror"],
	["Array...", "array"],
	["Snap to Neighbours", "snap"],
	["Make Editable (Hull)", "make_editable"],
	[],
	["CSG: Subtract", "csg_subtract"],
	["CSG: Merge", "csg_merge"],
	["CSG: Intersect", "csg_intersect"],
	[],
	["Add Stairs or Ramp", "piece:Stairs"],
	["Add Row", "piece:Row"],
	["Add Ring", "piece:Ring"],
	[],
	["Save Selection as Prefab...", "prefab"],
	[],
	["Show Invisible Blocks", "view:invisible"],
	["Show Solid Blocks Only", "view:solid"],
]

var _tool_buttons: Array[Button] = []
var _grid_label: Label
var _menu: PopupMenu


func _init() -> void:
	add_child(VSeparator.new())

	for i in TOOLS.size():
		var b := Button.new()
		b.text = TOOLS[i][0]
		b.tooltip_text = TOOLS[i][1]
		b.toggle_mode = true

		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: tool_chosen.emit(i + 1))
		add_child(b)
		_tool_buttons.append(b)
	add_child(VSeparator.new())
	_add_button("[", "A finer grid.", func() -> void: grid_stepped.emit(-1))
	_grid_label = Label.new()
	_grid_label.tooltip_text = "The grid the map tools snap to."
	_grid_label.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_grid_label)
	_add_button("]", "A coarser grid.", func() -> void: grid_stepped.emit(1))
	add_child(VSeparator.new())
	_add_button("Solid", "Selected blocks: turn Solid on or off (off = drawn only).", func() -> void: command.emit("solid"))
	_add_button("Drawn", "Selected blocks: turn Drawn on or off (off = an invisible wall).", func() -> void: command.emit("drawn"))
	_add_button("Breakable", "Selected blocks: turn Breakable on or off.", func() -> void: command.emit("breakable"))
	var menu_button := MenuButton.new()
	menu_button.text = "Map"
	menu_button.flat = true
	menu_button.tooltip_text = "More map tools."
	add_child(menu_button)
	_menu = menu_button.get_popup()
	for i in MENU.size():
		if MENU[i].is_empty():
			_menu.add_separator()
		elif (MENU[i][1] as String).begins_with("view:"):
			_menu.add_check_item(MENU[i][0], i)
		else:
			_menu.add_item(MENU[i][0], i)
	_menu.id_pressed.connect(func(id: int) -> void: command.emit(MENU[id][1]))


func _add_button(text: String, tip: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(pressed)
	add_child(b)
	return b


## Shows which tool is on (0 = none) and the grid size. A tool the strip has no button for
## (placing a prefab) leaves none pressed.
func show_state(tool: int, grid: float) -> void:
	for i in _tool_buttons.size():
		_tool_buttons[i].set_pressed_no_signal(i + 1 == tool)
	_grid_label.text = "Grid %s m" % String.num(grid, 2)


## Ticks or unticks one of the menu's view switches.
func show_view(what: String, on: bool) -> void:
	for i in MENU.size():
		if not MENU[i].is_empty() and MENU[i][1] == what:
			_menu.set_item_checked(_menu.get_item_index(i), on)


## Adds the key each thing is bound to, to its tooltip.
func show_keys(keys: Dictionary) -> void:
	for i in _tool_buttons.size():
		var key: String = keys.get("tool_%s" % (TOOLS[i][0] as String).to_lower(), "")
		if key != "":
			_tool_buttons[i].tooltip_text = "%s (%s)" % [TOOLS[i][1], key]
