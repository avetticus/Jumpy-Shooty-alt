class_name MapPoolPicker
extends VBoxContainer
## The maps a "Random map" may pick from (lobby, Vs Bots and Practice pages; see
## LobbySettings.pool_for): a line saying which and, for whoever picks, a Change button
## that opens a chip for each map of the game set up, to tick on or off (one always
## stays ticked). Laid out like AllowedWeaponsPicker. Everyone else just sees the line.
##
## It only reports the choice (changed, with the stored form: [] for every map); the
## screen sends it on.

signal changed(ids: Array)

const COLUMNS := 2

var _ids: Array = []          # as stored: [] = every map, maps of any game
var _game := "ffa"
var _summary: Label
var _edit: Button
var _grid: GridContainer
var _chips := {}              # map id -> Button
var _window: FloatingPanel    # the chips' floating window (see use_window), or null: they open under the line


func _init(ids: Array = [], game: String = "ffa", editable: bool = true) -> void:
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	add_child(head)
	_summary = UiKit.label(head, "", true, 15)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_edit = UiKit.button(head, "Change", func(): _open(not (_window.is_open() if _window else _grid.visible)))
	_edit.theme_type_variation = "Chip"
	_edit.custom_minimum_size = Vector2(110, 38)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.visible = false
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	add_child(_grid)
	set_editable(editable)
	set_value(ids, game)


## Show the pool (as stored) for a kind of game without reporting it.
func set_value(ids: Array, game: String) -> void:
	_ids = LobbySettings.normalized_pool(ids)
	if Maps.valid_game(game) != _game or _chips.is_empty():
		_game = Maps.valid_game(game)
		_build_chips()
	_sync()


## Whoever picks can change it; everyone else only sees the line.
func set_editable(on: bool) -> void:
	_edit.visible = on
	if not on:
		_open(false)


func value() -> Array:
	return _ids.duplicate()


## The kind of game whose maps it shows.
func game() -> String:
	return _game


func _open(on: bool) -> void:
	if _window:
		if on:
			_window.open(_edit)
		else:
			_window.close()
		return
	_grid.visible = on
	_edit.text = "Done" if on else "Change"

## Show the chips in a floating window (opened by Change) instead of under the line
## (the lobby; see FloatingPanel). `title` heads the window. Call it before the
## picker is in the tree, so its chips enter the tree only once (in the window).
func use_window(window: FloatingPanel, title: String) -> void:
	_window = window
	_grid.get_parent().remove_child(_grid)
	UiKit.section(window.content, title)
	window.content.add_child(_grid)
	_grid.visible = true
	_edit.text = "Change"


## The floating window, if the chips are in one (see use_window).
func window() -> FloatingPanel:
	return _window



func _build_chips() -> void:
	UiKit.clear(_grid)
	_chips.clear()
	for id in Maps.random_ids(_game):
		var b := Button.new()
		b.toggle_mode = true
		b.theme_type_variation = "Chip"
		b.text = Maps.name_of(id)
		b.tooltip_text = Maps.name_of(id)
		b.custom_minimum_size = Vector2(0, 34)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_on_chip.bind(id))
		_grid.add_child(b)
		_chips[id] = b


func _on_chip(id: String) -> void:
	var next := LobbySettings.pool_toggled(_ids, _game, id)
	var was := _ids
	_ids = next
	_sync()   # (the last map ticked stays ticked)
	if next != was:
		changed.emit(next.duplicate())


func _sync() -> void:
	_summary.text = LobbySettings.pool_summary(_ids, _game)
	var pool := LobbySettings.pool_for(_ids, _game)
	for id in _chips:
		_chips[id].set_pressed_no_signal(id in pool)
