class_name MobilityPicker
extends VBoxContainer
## "Mobility" chooser for the menus: a button for each tool on the mobility button
## (the grappling hook, blink) and a line about the one picked (or the one under the
## mouse). Like WeaponPicker it only reports the choice. Only the tools the
## host allows can be picked (set_allowed); the others are greyed out.

signal picked(id: String)

var current := ""

var _buttons := {}   # mobility id -> Button
var _blurb: Label
var _allowed: Array = Mobility.IDS.duplicate()


func _init(start: String = "", allowed: Array = []) -> void:
	add_theme_constant_override("separation", 8)
	UiKit.section(self, "Mobility")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var group := ButtonGroup.new()
	for id in Mobility.IDS:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "Chip"
		b.set_meta("sfx", "none")   # picking plays its own sound
		b.text = Mobility.short_name(id)
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_pressed.bind(id))
		b.mouse_entered.connect(_show.bind(id))
		b.mouse_exited.connect(func(): _show(current))
		row.add_child(b)
		_buttons[id] = b
	_blurb = UiKit.label(self, "", true, 14)
	_blurb.custom_minimum_size = Vector2(0, 36)
	set_allowed(allowed)
	select(Mobility.valid(start))


## Which tools can be picked ([] for every one). Does not change the pick: the screen
## passes an allowed one to select().
func set_allowed(ids: Array) -> void:
	_allowed = LobbySettings.mobility_from(ids)
	for key in _buttons:
		_buttons[key].disabled = not key in _allowed


## The tools that can be picked.
func allowed() -> Array:
	return _allowed.duplicate()


## Show `id` as the pick without reporting it.
func select(id: String) -> void:
	current = Mobility.valid(id)
	for key in _buttons:
		_buttons[key].set_pressed_no_signal(key == current)
	_show(current)


func _show(id: String) -> void:
	_blurb.text = Mobility.blurb(id)


func _on_pressed(id: String) -> void:
	if not id in _allowed:
		return
	Sound.play("ui_select")
	if id == current:
		_buttons[id].set_pressed_no_signal(true)
		return
	select(id)
	picked.emit(id)
