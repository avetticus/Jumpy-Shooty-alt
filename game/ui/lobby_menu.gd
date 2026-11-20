extends Control
## Multiplayer lobby (and Vs Bots, the same page offline: see Game.open_bot_lobby):
## shows who is connected and who is hosting, and lets each player pick their robot
## and their gun. The host can add bots (each at its own difficulty, which a click on
## it changes) and take them out again. Everyone else readies up (Ready); the host
## starts the match once they all have, can kick a player, and sets the lobby size.
## Anyone can leave.
## Three columns in a MenuFrame: the players; the match (mode, loadout rules, map,
## win condition); your loadout (robot, weapon). Leave and Start stay on
## screen at any window size.
##
## Each choice with many options shows only what is picked, as a button; pressing it
## opens a FloatingPanel with every option (the game mode for the host, and your
## robot and weapon), so the page stays tidy however many modes,
## robots and weapons there are.
##
## Each player's row shows their level. Point at a row for a close look at them (their
## loadout and the cosmetics they wear, the ones you have not unlocked in red: see
## PlayerCardView) while the stage on the right shows their robot; click the row to
## keep it open in a window, where a red cosmetic's tooltip says how to unlock it.

var _frame: MenuFrame
var _col: VBoxContainer          # the middle column: mode, loadout rules, map, win condition
var _list: VBoxContainer
var _list_scroll: ScrollContainer
var _watching: Label     # who is spectating
var _spectate: Button    # watch instead of play, or play again
var _start: Button
var _ready_button: Button   # everyone but the host: ready up (press again to take it back)
var _size_box: HBoxContainer   # the host's lobby size
var _size: SpinBox
var _waiting: Label
var _info: Label
var _code: Label    # the host's lobby code, big
var _copy: Button   # copies the lobby code
var _rules_label: Label
var _host_rules: HBoxContainer
var _mode_pick: OptionButton
var _amount: SpinBox
var _killcam_rules: HBoxContainer   # Killcam mode: first to [points] or [minutes] (host only)
var _killcam_points: SpinBox
var _killcam_minutes: SpinBox
var _amount_unit: Label
var _powerups: CheckButton   # Deathmatch: power-ups on the map or not
var _allowed: AllowedWeaponsPicker   # shoot-out: the weapons the host allows (see LobbySettings)
var _jetpack: CheckButton   # every fight: everyone has the jetpack or not (see LobbySettings.jetpack)
var _rules_head: Control   # the "Loadout rules" heading over the lobby settings
var _map_label: Label
var _map_button: Button   # the host: the map picked (or Random); opens the map window
var _map_window: FloatingPanel
var _map_pool: MapPoolPicker   # a random map: the maps it may pick from (the host ticks them)
var _song_box: HBoxContainer   # the lobby song: the host's pick, or what it is for everyone else
var _song_button: Button   # the host: the song playing; opens the song window
var _song_window: FloatingPanel
var _song_label: Label
var _character: CharacterPicker
var _weapon: WeaponPicker
var _weapon_box: VBoxContainer   # the right column: your weapon, or a note when the mode has none to pick
var _no_weapon_note: Label
var _game_row: Container   # the host's mode switch (in the mode window)
var _mode_button: Button   # the mode picked; the host presses it for the mode window
var _mode_blurb: Label     # in the mode window: about the mode under the mouse
var _mode_panel: FloatingPanel
var _robot_panel: FloatingPanel
var _creator_panel: FloatingPanel   # the Character Creator, while it is open (made each time)
var _weapon_card: WeaponPicker.Card   # your weapon; opens the weapon window
var _weapon_panel: FloatingPanel
var _updating := false   # true while we fill the controls from settings (ignore their signals)
var _rows := {}           # player id -> their row in the list (for the hover card)
var _hover_card: PanelContainer   # the close look at the player under the mouse
var _hover_id := 0
var _player_panel: FloatingPanel  # a player kept open (clicked)
var _pinned_id := 0
var _hover_sig := ""
var _pinned_sig := ""
var _bot_row: HBoxContainer   # the host: Add bot, at this difficulty
var _add_bot: Button
var _bot_level: OptionButton
var _bot_note: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame = MenuFrame.new(1460)
	add_child(_frame)
	if Net.is_online:
		_frame.title("Lobby", "Multiplayer")
	else:
		_frame.title("Vs Bots", "Play")
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 12)
	_frame.header.add_child(info_row)
	_info = UiKit.label(info_row, "", true, 16)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_code = UiKit.label(info_row, "", false, 26)
	_code.autowrap_mode = TextServer.AUTOWRAP_OFF
	_code.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_copy = UiKit.button(info_row, "Copy code", func():
		DisplayServer.clipboard_set(Net.lobby_code())
		_copy.text = "Copied")
	_copy.custom_minimum_size = Vector2(0, 38)
	_copy.theme_type_variation = "Chip"
	# The host: how many players the lobby takes (see LobbySettings.max_players).
	_size_box = HBoxContainer.new()
	_size_box.add_theme_constant_override("separation", 8)
	info_row.add_child(_size_box)
	var size_label := UiKit.label(_size_box, "Lobby size", true, 15)
	size_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	size_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_size = SpinBox.new()
	_size.min_value = LobbySettings.MIN_PLAYERS
	_size.max_value = Net.MAX_PLAYERS
	_size.custom_minimum_size = Vector2(96, 38)
	_size_box.add_child(_size)
	_size.value_changed.connect(func(v: float):
		if _updating:
			return
		var s := Net.match_settings.duplicate()
		s["max_players"] = int(v)
		if s != Net.match_settings:
			Net.set_match_settings(s))
	# Three columns: the players, the match, your loadout.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 26)
	_frame.body.add_child(columns)
	var players_col := VBoxContainer.new()
	players_col.add_theme_constant_override("separation", 10)
	players_col.custom_minimum_size = Vector2(430, 0)
	columns.add_child(players_col)
	_list_scroll = ScrollContainer.new()   # the list takes the column's height and scrolls past it
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.custom_minimum_size = Vector2(0, 120)
	players_col.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 5)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_list)
	var watch_row := HBoxContainer.new()
	watch_row.add_theme_constant_override("separation", 10)
	players_col.add_child(watch_row)
	_watching = UiKit.label(watch_row, "", true, 14)
	_watching.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_watching.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spectate = UiKit.button(watch_row, "Spectate", func(): Net.set_spectating(not Net.spectating()))
	_spectate.custom_minimum_size = Vector2(0, 38)
	_spectate.theme_type_variation = "Chip"
	watch_row.visible = Net.is_online   # (Vs Bots: nobody to watch)
	# The host: add a bot, at the difficulty picked beside it.
	_bot_row = HBoxContainer.new()
	_bot_row.name = "bots"
	_bot_row.add_theme_constant_override("separation", 10)
	players_col.add_child(_bot_row)
	_add_bot = UiKit.button(_bot_row, "+  Add bot", _on_add_bot)
	_add_bot.name = "add_bot"
	_add_bot.theme_type_variation = "Chip"
	_add_bot.custom_minimum_size = Vector2(140, 38)
	_bot_level = OptionButton.new()
	_bot_level.name = "bot_level"
	for i in BotDifficulty.NAMES.size():
		_bot_level.add_item(BotDifficulty.NAMES[i], i)
		_bot_level.set_item_tooltip(i, BotDifficulty.BLURBS[i])
	_bot_level.select(clampi(int(Game.last_bot.get("difficulty", 1)), 0, BotDifficulty.NAMES.size() - 1))
	_bot_level.custom_minimum_size = Vector2(130, 38)
	_bot_level.tooltip_text = "How well the next bot plays"
	_bot_row.add_child(_bot_level)
	_bot_note = UiKit.label(_bot_row, "", true, 13)
	_bot_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bot_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_divider(columns)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 10)
	_col.custom_minimum_size = Vector2(400, 0)
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(_col)
	_build_mode()
	_build_lobby_settings()
	_build_map()
	_build_rules()
	_divider(columns)
	_build_character(columns)
	_frame.back_button("Leave lobby" if Net.is_online else "Back", Game.leave_to_menu)
	_build_song()
	_waiting = UiKit.label(_frame.footer, "Waiting for the host to start...", true, 17)
	_waiting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_waiting.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ready_button = _frame.main_button("Ready", func(): Net.set_my_ready(not Net.is_ready(Net.my_id())))
	_start = _frame.main_button("Start match", func():
		if Net.is_online:
			Net.host_start_match()
		else:
			Game.start_bot_lobby())
	Net.players_changed.connect(_refresh)
	Net.internet_changed.connect(_refresh)
	_hover_card = PanelContainer.new()
	var hover_box := UiKit.panel_box(18)
	hover_box.border_color = Color(UiKit.CYAN, 0.45)
	hover_box.shadow_size = 14
	_hover_card.add_theme_stylebox_override("panel", hover_box)
	_hover_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_card.visible = false
	_frame.add_child(_hover_card)
	_player_panel = _floating(null, "right")
	_player_panel.closed.connect(func():
		_pinned_id = 0
		_peek_at(0))
	_refresh()
	Net.send_my_level()
	_dev_lobby_steps()
	# Dev/test: the host starts the next match on its own.
	if DevArgs.autostart > 0 and Net.is_host() and Net.players.size() >= DevArgs.autostart:
		get_tree().create_timer(3.0).timeout.connect(func():
			if is_inside_tree() and not Net.in_match:
				Net.host_start_match(true))


## A thin upright line between two columns.
func _divider(row: Node) -> void:
	var line := ColorRect.new()
	line.color = Color(UiKit.LINE, 0.12)
	line.custom_minimum_size = Vector2(1, 0)
	row.add_child(line)


func _refresh() -> void:
	UiKit.clear(_list)
	var ids := Net.players.keys()
	ids.sort()
	_rows.clear()
	for id in ids:
		_rows[id] = _player_row(id)
		_list.add_child(_rows[id])
	# A player looked at closely: up to date (rebuilt only if they changed), or gone.
	if _hover_id != 0:
		if not _rows.has(_hover_id):
			_hover_id = 0
			_show_hover_card(0)
		elif _hover_sig != PlayerCardView.signature(_hover_id):
			_show_hover_card(_hover_id)
		else:
			_place_hover_card.call_deferred(_hover_id)
	if _pinned_id != 0:
		if not _rows.has(_pinned_id):
			_player_panel.close()
		elif _pinned_sig != PlayerCardView.signature(_pinned_id):
			_fill_player_panel(_pinned_id)
	var watchers := Net.spectator_ids().map(func(id): return Net.spectator_name(id) + (" (you)" if id == Net.my_id() else ""))
	_watching.text = "Spectating: %s" % ", ".join(watchers) if not watchers.is_empty() else "Nobody is spectating."
	if not Net.spectating():
		Net.moved_by_host = false   # playing again
	_spectate.text = ("Play" if Net.player_slot_free() else "Play (lobby full)") if Net.spectating() else "Spectate"
	_spectate.disabled = Net.spectating() and not Net.player_slot_free()
	_start.visible = Net.is_host()
	_ready_button.visible = not Net.is_host()
	_waiting.visible = not Net.is_host()
	var waiting_for := Net.not_ready().size()
	_start.disabled = Net.players.size() < 1 or waiting_for > 0 or (not Net.is_online and Net.bot_ids().is_empty())
	_start.text = "START MATCH" if waiting_for == 0 else ("WAITING FOR %d TO READY UP" % waiting_for)
	if not Net.is_online and Net.bot_ids().is_empty():
		_start.text = "ADD A BOT TO PLAY"
	_bot_row.visible = Net.is_host() and not Net.spectating()
	var room := _bot_room()
	_add_bot.disabled = room <= 0
	_bot_note.text = ("Full" if Net.is_online else "Up to %d bots in this mode" % _most_bots()) if room <= 0 else ""
	var me_ready := Net.is_ready(Net.my_id())
	_ready_button.text = "READY  ·  PRESS TO UNDO" if me_ready else "READY UP"
	_waiting.text = "Waiting for the host to start..." if me_ready else "Ready up when you have picked your loadout."
	_size_box.visible = Net.is_host() and Net.is_online
	_updating = true
	_size.min_value = maxi(LobbySettings.MIN_PLAYERS, Net.players.size())   # never below who is already here
	_size.set_value_no_signal(LobbySettings.max_players())
	_updating = false
	var where := ""
	var code := Net.lobby_code() if Net.is_host() else ""
	_code.text = code
	_code.visible = code != ""
	_copy.visible = code != ""
	if not Net.is_online:
		var n := Net.bot_ids().size()
		where = "You and %d bot%s. Add bots on the left (click one's difficulty to change it), set up the match, then Start." % [n, "" if n == 1 else "s"]
	elif Net.is_host():
		match Net.internet_state:
			"open":
				where = "Friends anywhere join with the lobby code (or at %s)." % _address(Net.join_ip())
			"checking":
				where = "Opening your router for internet play..."
			_:
				where = "Your router would not open port %d, so only friends on your network can join, with the lobby code (or at %s)." % [Net.port, _address(Net.join_ip())]
	else:
		where = "The host picks the map and rules and starts the match."
	_info.text = ("%d of %d players.  %s" % [Net.players.size(), LobbySettings.max_players(), where]) if Net.is_online else where
	if Net.spectating():
		_info.text = "You are spectating: you will watch the match with a free camera.  " + _info.text
		if Net.moved_by_host:
			_info.text = "The host moved you to the spectators. Press Play to join back in when there is room.  " + _info.text
	_refresh_rules()
	if Net.players.has(Net.my_id()):   # show what the host has on record for us
		_character.select(Net.player_character(Net.my_id()))
		_character.set_color(Net.player_color(Net.my_id()))
		_character.offer_colors(Teams.mode() == "")   # a team mode dresses you in your team's colour
		_weapon.select(Net.player_weapon(Net.my_id()))
		_show_weapon_card(Net.player_weapon(Net.my_id()))
		_character.set_weapon(Net.player_weapon(Net.my_id()))


## One player: colour stripe, name, HOST and YOU tags, robot and gun.
func _player_row(id: int) -> PanelContainer:
	var card := PanelContainer.new()
	var box := UiKit.cut_box(Color(1, 1, 1, 0.05) if id != Net.my_id() else Color(UiKit.ACCENT, 0.14), 8, 12, 7)
	box.border_width_left = 4
	box.border_color = Net.player_color(id)
	card.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	row.add_child(CallingCardView.of_player(id, Vector2(64, 28)))   # their calling card and icon
	if Net.player_level(id) > 0:
		var lv := UiKit.tag(row, "LV %d" % Net.player_level(id), UiKit.CYAN)
		lv.name = "level"
		lv.tooltip_text = "Level %d" % Net.player_level(id)
	var name_label := UiKit.label(row, Net.player_name(id), false, 18)
	name_label.add_theme_font_override("font", HudStyle.font(true))
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if id == Net.host_id():
		UiKit.tag(row, "HOST", UiKit.ACCENT)
	if id == Net.my_id():
		UiKit.tag(row, "YOU", Color(1, 1, 1, 0.85))
	if Net.is_bot(id) and Net.is_host():
		# The host's bot: its difficulty (a click goes to the next) and a way out.
		var d := int(Net.players[id].get("difficulty", 1))
		var level := UiKit.button(row, BotDifficulty.NAMES[d].to_upper(), func():
			Net.set_bot_difficulty(id, (d + 1) % BotDifficulty.NAMES.size()))
		level.name = "level_button"
		level.theme_type_variation = "Chip"
		level.custom_minimum_size = Vector2(0, 28)
		level.add_theme_font_size_override("font_size", 13)
		level.tooltip_text = "%s: %s\nClick for the next difficulty" % [BotDifficulty.NAMES[d], BotDifficulty.BLURBS[d]]
		var out := UiKit.button(row, "Remove", func(): Net.remove_bot(id))
		out.name = "remove"
		out.theme_type_variation = "Chip"
		out.custom_minimum_size = Vector2(0, 28)
		out.add_theme_font_size_override("font_size", 13)
		out.tooltip_text = "Take %s out" % Net.player_name(id)
	elif Net.is_bot(id):
		UiKit.tag(row, "BOT", Color(1, 1, 1, 0.6))
	elif id != Net.host_id():   # the host is ready when it presses Start
		var ready := Net.is_ready(id)
		UiKit.tag(row, "READY" if ready else "NOT READY", Color(0.45, 0.95, 0.5) if ready else Color(1, 1, 1, 0.45))
	var who := UiKit.label(row, "%s  ·  %s" % [Characters.name_of(Net.player_character(id)), WeaponData.by_id(Net.player_weapon(id)).short_name], true, 14)
	who.autowrap_mode = TextServer.AUTOWRAP_OFF
	who.clip_text = true
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.custom_minimum_size = Vector2(60, 0)
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_pin_player(id))
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if Net.is_host() and Net.is_online and id != Net.my_id() and not Net.is_bot(id):
		# The host's buttons need the room (what they picked is in the hover card).
		who.visible = false
		var kick := UiKit.button(row, "Kick", func(): Net.host_kick(id))
		kick.theme_type_variation = "Chip"
		kick.custom_minimum_size = Vector2(0, 28)
		kick.add_theme_font_size_override("font_size", 13)
		kick.tooltip_text = "Remove %s from the lobby" % Net.player_name(id)
		var watch := UiKit.button(row, "Spectate", func(): Net.host_move_to_spectators(id))
		watch.theme_type_variation = "Chip"
		watch.custom_minimum_size = Vector2(0, 28)
		watch.add_theme_font_size_override("font_size", 13)
		watch.tooltip_text = "Move %s to the spectators (they can come back when there is room)" % Net.player_name(id)
	return card


# Character: everyone picks their own robot. Saved as your choice for next time too.
func _build_character(columns: Node) -> void:
	Net.confirm_my_character()
	var loadout := VBoxContainer.new()
	loadout.add_theme_constant_override("separation", 10)
	columns.add_child(loadout)
	# Your robot: the stage, and its name under it, which opens the robot window.
	_character = CharacterPicker.new(Net.player_character(Net.my_id()), Net.player_color(Net.my_id()),
		Net.player_weapon(Net.my_id()), true)
	loadout.add_child(_character)
	_robot_panel = _floating(_character.list)
	_character.list_requested.connect(func(): _robot_panel.open(_character._name_button))
	_character.create_requested.connect(_open_creator)
	# Your colour: saved as the one you like, and yours here if nobody else has it.
	_character.color_picked.connect(func(index: int):
		Settings.player_color = index
		Settings.save_settings()
		Net.set_my_color(index))
	# Your weapon: its card, which opens the weapon window; or (in a race, Gun Game,
	# Killcam, a Deathmatch, or with one gun for everyone) a note saying why there is
	# none to pick.
	_weapon_box = VBoxContainer.new()
	_weapon_box.add_theme_constant_override("separation", 8)
	loadout.add_child(_weapon_box)
	UiKit.section(_weapon_box, "Weapon")
	_weapon_card = WeaponPicker.Card.new(Net.player_weapon(Net.my_id()))
	_weapon_card.custom_minimum_size = Vector2(150, WeaponPicker.CARD_HEIGHT + 4)
	_weapon_card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_weapon_card.button_pressed = true
	_weapon_card.tooltip_text = "Pick your weapon"
	_weapon_card.set_meta("sfx", "select")
	_weapon_box.add_child(_weapon_card)
	_no_weapon_note = UiKit.label(_weapon_box, "", true, 15)
	_weapon = WeaponPicker.new(Net.player_weapon(Net.my_id()))
	_weapon_panel = _floating(_weapon)
	_weapon_card.pressed.connect(func():
		_weapon_card.set_pressed_no_signal(true)
		_weapon_panel.open(_weapon_card))
	_weapon.picked.connect(func(id: String):
		Settings.weapon = id
		Settings.save_settings()
		_character.set_weapon(id)
		_show_weapon_card(id)
		_weapon_panel.close()
		Net.set_my_weapon(id))
	if DevArgs.switch_weapon and not Match.last_results.is_empty():
		get_tree().create_timer(1.2).timeout.connect(func():
			if is_inside_tree() and not Net.in_match:
				var ids := WeaponData.IDS
				Net.set_my_weapon(ids[(ids.find(Net.player_weapon(Net.my_id())) + 1) % ids.size()]))
	_character.picked.connect(func(id: String):
		Settings.character = id
		Settings.save_settings()
		_robot_panel.close()
		Net.set_my_character(id))


## A floating window over the page with `what` in it (see FloatingPanel). Beside its
## button, it starts level with the top of the columns.
func _floating(what: Control = null, side: String = "left") -> FloatingPanel:
	var p := FloatingPanel.new(side)
	p.top_of = _col
	if what:
		p.content.add_child(what)
	_frame.add_child(p)   # last: drawn over the page, in the menu's theme
	return p


## Fill `window` with a heading and a button for each choice ([id, text] pairs), the
## `current` one lit, then open it beside `anchor`. Pressing one closes the window and
## calls on_pick with its id.
func _open_choices(window: FloatingPanel, anchor: Control, title: String, choices: Array, current: String,
		columns: int, on_pick: Callable) -> void:
	UiKit.clear(window.content)
	UiKit.section(window.content, title)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	window.content.add_child(grid)
	for c in choices:
		var b := Button.new()
		b.theme_type_variation = "Chip"
		b.toggle_mode = true
		b.text = str(c[1])
		b.custom_minimum_size = Vector2(200, 40)
		b.add_theme_font_size_override("font_size", 15)
		b.set_pressed_no_signal(str(c[0]) == current)
		b.pressed.connect(func():
			window.close()
			on_pick.call(str(c[0])))
		grid.add_child(b)
	window.open(anchor)


## A button that shows a pick in the lobby (lit, like a picked chip).
func _pick_button(parent: Node, height: float = 44.0) -> Button:
	var b := Button.new()
	b.theme_type_variation = "Chip"
	b.toggle_mode = true
	b.button_pressed = true
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", 17)
	parent.add_child(b)
	b.pressed.connect(func(): b.set_pressed_no_signal(true))
	return b


## The Character Creator in a window of its own, from the robot window's "Make new
## character": a new character starts from the body of the robot you have (a blank
## name), and "Save and play as this" saves it and makes it yours; Save keeps it for
## later (it joins the robot list either way). Cancel, a click outside or Esc closes
## it without saving.
func _open_creator() -> void:
	_robot_panel.close()
	if _creator_panel:
		_creator_panel.queue_free()
	var mine := Net.player_character(Net.my_id())
	var creator := CharacterCreator.new("" if Characters.is_custom(mine) else mine)
	var window := VBoxContainer.new()
	window.add_theme_constant_override("separation", 12)
	UiKit.label(window, "CHARACTER CREATOR", false, 24).add_theme_font_override("font", HudStyle.font(true))
	window.add_child(creator)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	window.add_child(buttons)
	_creator_panel = _floating(window)
	var panel := _creator_panel
	panel.closed.connect(func():
		panel.queue_free()
		if _creator_panel == panel:
			_creator_panel = null)
	UiKit.button(buttons, "Cancel", panel.close).custom_minimum_size = Vector2(160, 50)
	var keep := UiKit.button(buttons, "Save", func():
		creator.save()
		_character.refresh_custom())
	keep.custom_minimum_size = Vector2(160, 50)
	var play := UiKit.primary_button(buttons, "Save and play as this", func():
		var id := creator.save()
		if id == "":
			return   # it wears something still locked (the creator says what)
		_character.refresh_custom()
		Settings.character = id
		Settings.save_settings()
		_character.select(id)
		Net.set_my_character(id)
		panel.close())
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lock := func():   # something locked on it: it can be looked at, not saved
		keep.disabled = not creator.can_save()
		play.disabled = keep.disabled
	creator.changed.connect(lock)
	lock.call()
	panel.open(_character._name_button)


## The weapon card shows this weapon.
func _show_weapon_card(id: String) -> void:
	_weapon_card.id = WeaponData.valid(id)
	_weapon_card.tooltip_text = "%s  ·  pick your weapon" % WeaponData.name_of(id)
	_weapon_card.queue_redraw()
	# Dev/test: after a match, come back as the other robot (checks the choice syncs).
	if DevArgs.switch_character and not Match.last_results.is_empty():
		get_tree().create_timer(1.0).timeout.connect(func():
			if is_inside_tree() and not Net.in_match:
				Net.set_my_character(Characters.next(Net.player_character(Net.my_id()))))


# Mode: one button with the mode picked. The host presses it for the mode window (every
# mode, and a line about the one under the mouse); everyone else just sees it. Mode
# first: race maps only show up for a race, arena maps only for a shoot-out.
func _build_mode() -> void:
	UiKit.section(_col, "Mode")
	_mode_button = Button.new()
	_mode_button.theme_type_variation = "Chip"
	_mode_button.toggle_mode = true
	_mode_button.button_pressed = true
	_mode_button.custom_minimum_size = Vector2(170, 44)
	_mode_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mode_button.add_theme_font_size_override("font_size", 17)
	_col.add_child(_mode_button)
	var window := VBoxContainer.new()
	window.add_theme_constant_override("separation", 10)
	window.custom_minimum_size = Vector2(560, 0)
	UiKit.section(window, "Mode")
	_game_row = UiKit.segmented(window, GunGame.MODE_LABELS, GunGame.MODES.find(GunGame.mode_of(Net.match_settings)), func(i: int):
		if _updating:
			return
		_mode_panel.close()
		var m: String = GunGame.MODES[i]
		var g := GunGame.game_of_mode(m)
		Net.set_match_settings(GunGame.with_mode(Net.match_settings, m, Game.last_map.get(g, Maps.default_id(g)))), 4)
	_mode_blurb = UiKit.label(window, "", true, 15)
	_mode_blurb.custom_minimum_size = Vector2(560, 44)   # (a wrapped line needs its width set to know its height)
	for i in _game_row.get_child_count():
		var b := _game_row.get_child(i) as Button
		b.add_theme_font_size_override("font_size", 16)
		var short: String = {"Search & Destroy": "S&D", "Capture the Flag": "CTF"}.get(b.text, "")
		if short != "":   # the team modes, by their usual short names (the full name in the tooltip and the rules)
			b.tooltip_text = b.text
			b.text = short
		b.mouse_entered.connect(func(): _mode_blurb.text = "%s: %s" % [GunGame.MODE_LABELS[i], GunGame.MODE_BLURBS[i]])
		b.mouse_exited.connect(_show_mode_blurb)
	_mode_panel = _floating(window, "below")
	_mode_button.pressed.connect(func():
		_mode_button.set_pressed_no_signal(true)
		if Net.is_host():
			_show_mode_blurb()
			_mode_panel.open(_mode_button))


## The mode window's line: about the mode picked.
func _show_mode_blurb() -> void:
	var i := GunGame.MODES.find(GunGame.mode_of(Net.match_settings))
	if i >= 0:
		_mode_blurb.text = "%s: %s" % [GunGame.MODE_LABELS[i], GunGame.MODE_BLURBS[i]]


# Map: the host picks; everyone else sees it.
func _build_map() -> void:
	UiKit.section(_col, "Map")
	_map_label = UiKit.label(_col, "")
	# The host: a button with the map (or Random map); it opens a window with every map
	# of the game set up, and Random.
	_map_button = _pick_button(_col)
	_map_button.tooltip_text = "Change the map"
	_map_window = _floating()
	_map_button.pressed.connect(func():
		var choices := Maps.ids_for(Net.game_kind()).map(func(id): return [id, Maps.label(id)])
		choices.append([Maps.RANDOM, "Random map"])
		_open_choices(_map_window, _map_button, "Map", choices, _map_choice(), 2, func(picked: String):
			var s := Net.match_settings.duplicate()
			s["random_map"] = picked == Maps.RANDOM   # the map is picked from the pool as the match starts
			if picked != Maps.RANDOM:
				s["map"] = picked
				Game.last_map[Net.game_kind()] = picked
			Net.set_match_settings(s)))
	# Random map: the maps it may pick from (only this game's; one always stays ticked),
	# in a window of their own.
	_map_pool = MapPoolPicker.new(Net.match_settings.get("map_pool", []), Net.game_kind(), Net.is_host())
	var pool_window := _floating()
	pool_window.panel.custom_minimum_size.x = 480
	_map_pool.use_window(pool_window, "Random map pool")
	_col.add_child(_map_pool)
	_map_pool.changed.connect(func(ids: Array):
		if _updating:
			return
		var s := Net.match_settings.duplicate()
		s["map_pool"] = ids
		Net.set_match_settings(s))


## What the map drop-down shows: the map, or Random.
func _map_choice() -> String:
	return Maps.RANDOM if bool(Net.match_settings.get("random_map", false)) else Net.map_id()


# The lobby song (see Music): the host picks it, any time; everyone hears it, in step.
# In the footer, beside Leave, so the columns keep their room.
func _build_song() -> void:
	_song_box = HBoxContainer.new()
	_song_box.add_theme_constant_override("separation", 8)
	_frame.footer.add_child(_song_box)
	var head := UiKit.label(_song_box, "Lobby song", true, 15)
	head.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The host: a button with the song; it opens a window with every song (and Shuffle).
	_song_button = _pick_button(_song_box, 0.0)
	_song_button.custom_minimum_size.x = 230
	_song_button.add_theme_font_size_override("font_size", 16)
	_song_button.tooltip_text = "Change the lobby song"
	_song_window = _floating(null, "above")
	_song_button.pressed.connect(func():
		var choices := [["", Music.title_of("")]]
		for song in Music.song_names():
			choices.append([song, Music.title_of(song)])
		_open_choices(_song_window, _song_button, "Lobby song", choices, str(Net.match_settings.get("song", "")), 2, func(song: String):
			var s := Net.match_settings.duplicate()
			s["song"] = song
			if s != Net.match_settings:
				Net.set_match_settings(s)))
	_song_label = UiKit.label(_song_box, "", false, 15)
	_song_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_song_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER


# Win condition: the host picks; everyone else sees it.
func _build_rules() -> void:
	UiKit.section(_col, "Win condition")
	_rules_label = UiKit.label(_col, "")
	_host_rules = HBoxContainer.new()
	_host_rules.add_theme_constant_override("separation", 10)
	_col.add_child(_host_rules)
	_mode_pick = OptionButton.new()
	_mode_pick.add_item("First to", 0)
	_mode_pick.add_item("Time limit", 1)
	_mode_pick.custom_minimum_size = Vector2(170, 44)
	_host_rules.add_child(_mode_pick)
	_amount = SpinBox.new()
	_amount.custom_minimum_size = Vector2(110, 44)
	_host_rules.add_child(_amount)
	_amount_unit = UiKit.label(_host_rules, "kills")
	_amount_unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_amount_unit.autowrap_mode = TextServer.AUTOWRAP_OFF
	_mode_pick.item_selected.connect(func(i: int):
		if _updating:
			return
		var s := Net.match_settings.duplicate()
		s.mode = "kills" if i == 0 else "time"
		Net.set_match_settings(s))
	_amount.value_changed.connect(func(v: float):
		if _updating:
			return
		var s := Net.match_settings.duplicate()
		if Net.game_kind() == "race":
			s.race_minutes = int(v)
		elif s.mode != "time":   # ("kills", or a mode played to a kill target: Golden Gun)
			s.kills = int(v)
		else:
			s.minutes = int(v)
		if s != Net.match_settings:
			Net.set_match_settings(s))
	# Killcam mode: the points to win and the time limit (see KillcamMode).
	_killcam_rules = HBoxContainer.new()
	_killcam_rules.add_theme_constant_override("separation", 10)
	_col.add_child(_killcam_rules)
	var first := UiKit.label(_killcam_rules, "First to")
	first.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	first.autowrap_mode = TextServer.AUTOWRAP_OFF
	_killcam_points = SpinBox.new()
	_killcam_points.min_value = KillcamMode.POINTS_MIN
	_killcam_points.max_value = KillcamMode.POINTS_MAX
	_killcam_points.step = KillcamMode.POINTS_STEP
	_killcam_points.custom_minimum_size = Vector2(130, 44)
	_killcam_rules.add_child(_killcam_points)
	var or_label := UiKit.label(_killcam_rules, "points, or")
	or_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	or_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_killcam_minutes = SpinBox.new()
	_killcam_minutes.min_value = KillcamMode.MINUTES_MIN
	_killcam_minutes.max_value = KillcamMode.MINUTES_MAX
	_killcam_minutes.custom_minimum_size = Vector2(90, 44)
	_killcam_rules.add_child(_killcam_minutes)
	var mins := UiKit.label(_killcam_rules, "minutes")
	mins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mins.autowrap_mode = TextServer.AUTOWRAP_OFF
	var set_killcam := func(key: String, v: float):
		if _updating:
			return
		var ks := Net.match_settings.duplicate()
		ks[key] = int(v)
		ks = LobbySettings.clean(ks)
		if ks != Net.match_settings:
			Net.set_match_settings(ks)
	_killcam_points.value_changed.connect(func(v: float): set_killcam.call("killcam_points", v))
	_killcam_minutes.value_changed.connect(func(v: float): set_killcam.call("killcam_minutes", v))
	# Deathmatch only: power-ups (health, uber health, double damage) on the map or not.
	_powerups = CheckButton.new()
	_powerups.text = "Power-ups (health, uber, double damage)"
	_powerups.custom_minimum_size = Vector2(0, 44)
	_col.add_child(_powerups)
	_powerups.toggled.connect(func(on: bool):
		if _updating:
			return
		var s := Net.match_settings.duplicate()
		s["powerups"] = on
		Net.set_match_settings(s))


# Lobby settings (see LobbySettings): the host picks; everyone else sees them. New
# settings get their control here.
func _build_lobby_settings() -> void:
	_rules_head = UiKit.section(_col, "Loadout rules").get_parent()
	# Every fight: everyone has the jetpack (Space held in mid-air) or nobody does.
	_jetpack = CheckButton.new()
	_jetpack.text = "Jetpack (hold Space in mid-air)"
	_jetpack.custom_minimum_size = Vector2(0, 44)
	_col.add_child(_jetpack)
	_jetpack.toggled.connect(func(on: bool):
		if _updating:
			return
		var s := Net.match_settings.duplicate()
		s["jetpack"] = on
		Net.set_match_settings(s))
	_allowed = AllowedWeaponsPicker.new(Net.match_settings.get("weapons", []), Net.is_host(), false)
	var weapons_window := _floating()
	weapons_window.panel.custom_minimum_size.x = 620
	_allowed.use_window(weapons_window, "Weapons allowed")
	_col.add_child(_allowed)
	_allowed.changed.connect(func(ids: Array):
		if _updating:
			return
		var s := Net.match_settings.duplicate()
		s["weapons"] = ids
		Net.set_match_settings(s))


func _refresh_rules() -> void:
	var s: Dictionary = Net.match_settings
	var race := Net.game_kind() == "race"
	var gun_game := GunGame.active()
	var killcam := KillcamMode.active()
	var team_mode := Teams.mode()   # "snd", "ctf" or ""
	var own_rules := gun_game or killcam or team_mode != ""   # a mode with rules of its own: no kills/time choice
	var golden := GoldenGun.active()   # (first to a kill target the host sets, never a time limit)
	var kills_mode: bool = s.mode != "time"
	_rules_label.text = ("First to %d kills" % s.kills) if kills_mode else ("Most kills after %d minutes" % s.minutes)
	if race:
		_rules_label.text = "First to the finish  ·  %d minute limit" % int(s.get("race_minutes", 10))
	if gun_game:
		_rules_label.text = "Every kill moves you to the next of %d weapons. First to get a kill with the last one (brass knuckles) wins. Kicked to death: back one weapon." % GunGame.steps()
	if killcam:
		_rules_label.text = "Snipers only. Every kill scores its killcam points: range, headshots, momentum (both of you moving), flicks, trickshots. First to %s points, or the most after %d minutes. The match's #1 killcam earns +%s at the end." \
			% [KillcamMode.format(KillcamMode.target()), KillcamMode.minutes(), KillcamMode.format(KillcamMode.BEST_BONUS)]
		if Net.is_host():   # (the host's boxes below show the points and minutes)
			_rules_label.text = "Snipers only. Every kill scores its killcam points. The match's #1 killcam earns +%s at the end." \
				% KillcamMode.format(KillcamMode.BEST_BONUS)
	if golden:
		_rules_label.text = "One player has the Golden Gun: one round, and whoever it hits dies. Kill them to take it. Everyone else has their own weapon. First to %d kills." % s.kills
	if team_mode == "snd":
		_rules_label.text = "Two teams, Red and Blue, no respawns in a round. The attackers carry a bomb: hold %s on site A or B to plant it. Defenders: hold %s on it to defuse. Blow a site, defuse, or knock the other team out to win the round. Sides swap after %d rounds; first to %d rounds wins." \
			% [Settings.action_text("interact"), Settings.action_text("interact"), Teams.HALF, Teams.ROUNDS_TO_WIN]
	elif team_mode == "ctf":
		_rules_label.text = "Two teams, Red and Blue. Walk over the other team's flag to take it and bring it to your own flag (it must be home) to score. Walk over your own dropped flag to send it home. First to %d captures, or the most after %d minutes." \
			% [Teams.CAPTURES_TO_WIN, int(Teams.CTF_TIME / 60.0)]
	_mode_button.text = GunGame.MODE_LABELS[maxi(GunGame.MODES.find(GunGame.mode_of(s)), 0)]   # as the mode window names it
	_mode_button.tooltip_text = "Change the game mode" if Net.is_host() else "The host picks the game mode"
	_mode_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if Net.is_host() else Control.CURSOR_ARROW
	if not Net.is_host():
		_mode_panel.close()
	_show_mode_blurb()
	_mode_pick.visible = not race and not golden
	var only := LobbySettings.only_weapon()
	if _weapon:
		# No guns in a race; Gun Game hands them out; Killcam is snipers only; a Deathmatch
		# finds them on the map; the host may have set one gun for everyone.
		_weapon.set_allowed(LobbySettings.allowed_weapons())
		var pick_weapon := not race and not gun_game and not killcam and not Net.is_deathmatch() and only == ""
		_weapon_card.disabled = not pick_weapon
		_weapon_card.visible = not race and not Net.is_deathmatch()   # (a race has none; a Deathmatch finds them)
		_no_weapon_note.visible = not pick_weapon
		if not pick_weapon:
			_weapon_panel.close()
		_no_weapon_note.text = "A race has no weapons: it is you, the course and the clock." if race \
			else ("Killcam is snipers only: every kill scores its killcam points." if killcam \
			else ("Gun Game hands out the weapons: every kill moves you to the next one." if gun_game \
			else ("Deathmatch: everyone starts unarmed. Weapons float about the map; walk over one to pick it up." if Net.is_deathmatch() \
			else "One gun for everyone: the %s. The host picked it for this match." % WeaponData.name_of(only))))
	if _allowed:
		_allowed.visible = LobbySettings.weapons_apply()   # a shoot-out: everyone picks their own weapon
		_allowed.set_editable(Net.is_host())
		_allowed.preferred = Net.player_loadout_weapon(Net.my_id())
	_rules_label.visible = not Net.is_host() or own_rules or golden
	_host_rules.visible = Net.is_host() and not own_rules
	_killcam_rules.visible = Net.is_host() and killcam
	var random := bool(s.get("random_map", false))
	_map_label.text = Maps.label(Net.map_id())
	if random:   # everyone else sees the pool below; after a match, what it picked last
		_map_label.text = "Random map" + ("  ·  last: %s" % Maps.name_of(Net.map_id()) if not Match.last_results.is_empty() else "")
	_map_label.visible = not Net.is_host()
	_map_button.visible = Net.is_host()
	_map_button.text = "Random map" if random else Maps.label(Net.map_id())
	if not Net.is_host():
		_map_window.close()
		_song_window.close()
	_map_pool.visible = random
	_map_pool.set_editable(Net.is_host())
	_map_pool.set_value(s.get("map_pool", []), Net.game_kind())
	var song := str(s.get("song", ""))
	_song_button.visible = Net.is_host()
	_song_button.text = Music.title_of(song)
	_song_label.visible = not Net.is_host()
	_song_label.text = Music.title_of(song)
	_updating = true
	for i in _game_row.get_child_count():
		(_game_row.get_child(i) as Button).set_pressed_no_signal(GunGame.MODES[i] == GunGame.mode_of(s))
	_mode_pick.select(0 if kills_mode else 1)
	_killcam_points.set_value_no_signal(KillcamMode.clean_points(s.get("killcam_points")))
	_killcam_minutes.set_value_no_signal(KillcamMode.clean_minutes(s.get("killcam_minutes")))
	_powerups.visible = Net.is_deathmatch()
	_powerups.disabled = not Net.is_host()   # everyone else just sees the host's choice
	_powerups.set_pressed_no_signal(Net.powerups_on())
	if _allowed:
		_allowed.set_value(s.get("weapons", []))
	if _jetpack:
		_jetpack.visible = LobbySettings.jetpack_apply()   # a race never has the jetpack
		_rules_head.visible = _jetpack.visible   # a race has no loadout rules
		_jetpack.disabled = not Net.is_host()   # everyone else just sees the host's choice
		_jetpack.set_pressed_no_signal(s.get("jetpack", false) == true)
	if race:
		_amount.min_value = 2
		_amount.max_value = 30
		_amount.set_value_no_signal(int(s.get("race_minutes", 10)))
		_amount_unit.text = "minute limit"
	elif kills_mode:
		_amount.min_value = 1
		_amount.max_value = 100
		_amount.set_value_no_signal(s.kills)
		_amount_unit.text = "kills"
	else:
		_amount.min_value = 1
		_amount.max_value = 60
		_amount.set_value_no_signal(s.minutes)
		_amount_unit.text = "minutes"
	_updating = false


## The address the lobby code stands for, for LAN and development use (the port only
## if it isn't the usual one).
func _address(ip: String) -> String:
	return ip if Net.port == Net.DEFAULT_PORT else "%s:%d" % [ip, Net.port]


## Dev/test: ready up, kick a player and start once everyone is ready, on their own
## (--ready-at, --kick-at, --start-when-ready), the first time the lobby opens.
func _dev_lobby_steps() -> void:
	if not Match.last_results.is_empty():
		return
	if DevArgs.song_at >= 0.0 and Net.is_host():
		get_tree().create_timer(DevArgs.song_at).timeout.connect(func():
			if is_inside_tree() and not Net.in_match:
				var s := Net.match_settings.duplicate()
				s["song"] = DevArgs.song_later
				Net.set_match_settings(s))
	if DevArgs.ready_at >= 0.0 and not Net.is_host():
		get_tree().create_timer(DevArgs.ready_at).timeout.connect(func():
			if is_inside_tree() and not Net.in_match:
				Net.set_my_ready(true))
	if DevArgs.kick_at >= 0.0 and Net.is_host():
		get_tree().create_timer(DevArgs.kick_at).timeout.connect(func():
			for id in Net.players:
				if is_inside_tree() and Net.player_name(id) == DevArgs.kick_name:
					Net.host_kick(id)
					return)
	if DevArgs.move_at >= 0.0 and Net.is_host():
		get_tree().create_timer(DevArgs.move_at).timeout.connect(func():
			for id in Net.players:
				if is_inside_tree() and Net.player_name(id) == DevArgs.move_name:
					Net.host_move_to_spectators(id)
					return)
	for t in DevArgs.play_at:
		get_tree().create_timer(float(t)).timeout.connect(func():
			if is_inside_tree() and Net.spectating():
				print("PLAY_PRESSED")
				Net.set_spectating(false))
	if DevArgs.start_when_ready and Net.is_host():
		Net.players_changed.connect(func():
			if is_inside_tree() and not Net.in_match and Net.players.size() >= 2 and Net.all_ready():
				Net.host_start_match())


# ---------------------------------------------------------------------------
# A close look at a player: on hover, and kept open on a click

func _process(_delta: float) -> void:
	if _pinned_id != 0:
		return
	var id := 0
	var mouse := get_global_mouse_position()
	if not _any_window_open():
		for pid in _rows:
			var row: Control = _rows[pid]
			if is_instance_valid(row) and row.is_visible_in_tree() and row.get_global_rect().has_point(mouse) and _list_scroll.get_global_rect().has_point(mouse):
				id = pid
				break
		# Still on the way to (or over) their card: keep it, so its cosmetics can be pointed at.
		if id == 0 and _hover_id != 0 and _hover_card.visible and _hover_card.get_global_rect().grow(FloatingPanel.GAP + 4.0).has_point(mouse):
			id = _hover_id
	if id != _hover_id:
		_hover_id = id
		_show_hover_card(id)
	_peek_at(id)


## Show the hover card for `id` beside their row (0: hide it).
func _show_hover_card(id: int) -> void:
	for c in _hover_card.get_children():
		c.queue_free()
	_hover_card.visible = id != 0
	if id == 0:
		return
	_hover_sig = PlayerCardView.signature(id)
	var view := PlayerCardView.new(id)
	_hover_card.add_child(view)
	_hover_card.reset_size()
	_place_hover_card.call_deferred(id)


func _place_hover_card(id: int) -> void:
	if id != _hover_id or not _rows.has(id) or not is_instance_valid(_rows[id]):
		return
	var a: Rect2 = (_rows[id] as Control).get_global_rect()
	var s := _hover_card.get_combined_minimum_size()
	_hover_card.size = s
	var view := get_global_rect()
	var at := Vector2(a.end.x + FloatingPanel.GAP, a.position.y)
	at.y = clampf(at.y, view.position.y + FloatingPanel.EDGE, maxf(view.end.y - s.y - FloatingPanel.EDGE, view.position.y))
	at.x = minf(at.x, view.end.x - s.x - FloatingPanel.EDGE)
	_hover_card.global_position = at


## Keep a player open in a window (a click on their row): there, a cosmetic you have
## not unlocked says in its tooltip what unlocks it.
func _pin_player(id: int) -> void:
	_hover_id = 0
	_hover_card.visible = false
	_pinned_id = id
	_fill_player_panel(id)
	_peek_at(id)
	_player_panel.open(_rows[id])


func _fill_player_panel(id: int) -> void:
	UiKit.clear(_player_panel.content)
	_pinned_sig = PlayerCardView.signature(id)
	var view := PlayerCardView.new(id)
	view.name = "player_card"
	_player_panel.content.add_child(view)
	view.pinned()


## The stage on the right shows this player's robot (0, or you: your own again).
func _peek_at(id: int) -> void:
	if not _character:
		return
	if id == 0 or id == Net.my_id() or not Net.players.has(id):
		_character.unpeek()
	else:
		_character.peek(Net.player_character(id), Net.player_color(id), Net.player_weapon(id), Net.player_name(id))


## A window over the page (a pick, the creator, a player kept open): no hover card.
func _any_window_open() -> bool:
	for p in [_mode_panel, _robot_panel, _creator_panel, _weapon_panel, _map_window, _song_window, _player_panel]:
		if p and is_instance_valid(p) and p.is_open():
			return true
	return false


# ---------------------------------------------------------------------------
# Bots (the host)

func _on_add_bot() -> void:
	if _bot_room() <= 0:
		return
	var d := _bot_level.get_selected_id()
	Game.last_bot["difficulty"] = d
	Net.add_bot(d, DevArgs.bot_weapon, DevArgs.bot_mobility)


## How many more bots fit: online, the lobby's free places; Vs Bots, as many as the
## mode takes (more in the team modes).
func _bot_room() -> int:
	if Net.is_online:
		return LobbySettings.max_players() - Net.players.size()
	return _most_bots() - Net.bot_ids().size()


func _most_bots() -> int:
	return Game.max_bots(GunGame.mode_of(Net.match_settings))
