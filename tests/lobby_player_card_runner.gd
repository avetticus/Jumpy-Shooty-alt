extends Node
## The checks for tests/lobby_player_card_test.gd.

const OTHER := 5   # a made-up second player

var _fails: Array = []


func run() -> void:
	await get_tree().process_frame
	Achievements.reset_for_test()
	Achievements.add("xp", PlayerLevel.need(1) + PlayerLevel.need(2) + 10)   # level 3
	Achievements._toasts.clear()
	Net.start_offline("Host", "needle", "lever_action")
	_expect(Net.player_level(1) == 3, "your level goes in with you (%d)" % Net.player_level(1))

	# Someone in a crown and the Royal card, both locked for us.
	var c := CustomCharacter.new()
	c.name = "Big Boss"
	c.accessories["hat"] = "crown"
	var boss := Characters.valid(c.to_id())
	Net.players[OTHER] = {"name": "Other", "color": 1, "character": boss, "weapon": "shotgun", "mobility": Mobility.default_id(),
		"card": "royal", "icon": CallingCard.DEFAULT_ICON, "level": 42}
	var lobby: Control = load("res://game/ui/lobby_menu.tscn").instantiate()
	get_tree().root.add_child(lobby)
	await get_tree().process_frame
	var rows: Dictionary = lobby.get("_rows")
	var tag := (rows[OTHER] as Node).find_child("level", true, false)
	_expect(tag != null and (tag.get_child(0) as Label).text == "LV 42", "the row shows their level")

	# The hover card.
	lobby.set("_hover_id", OTHER)
	lobby.call("_show_hover_card", OTHER)
	lobby.call("_peek_at", OTHER)
	var hover: PanelContainer = lobby.get("_hover_card")
	var card := hover.get_child(hover.get_child_count() - 1) as PlayerCardView
	_expect(hover.visible and card != null and card.player_id == OTHER, "pointing at a player shows their card")
	_expect((card.find_child("level", true, false) as Label).text == "LEVEL 42", "with their level")
	_expect((card.find_child("weapon", true, false) as Label).text == WeaponData.name_of("shotgun")
		and (card.find_child("robot", true, false) as Label).text == "Big Boss", "and their loadout")
	var crown := card.find_child("hat_crown", true, false) as Control
	var royal := card.find_child("card_royal", true, false) as Control
	var visor := card.find_child("part_vanguard", true, false) as Control
	_expect(crown != null and crown.has_meta("locked") and royal != null and royal.has_meta("locked"), "what you haven't unlocked is marked locked (red)")
	_expect(visor != null and not visor.has_meta("locked"), "what everyone has is not")
	_expect(crown != null and "Warlord" in crown.tooltip_text and "0 / 500" in crown.tooltip_text,
		"a locked one says what unlocks it and how far you are (%s)" % (crown.tooltip_text if crown else ""))
	var picker: CharacterPicker = lobby.get("_character")
	_expect(picker.peeking() and picker._peek.id == boss, "the stage shows their robot")
	_expect(picker.current == "needle", "without changing your pick")

	# A click keeps it open.
	lobby.call("_pin_player", OTHER)
	await get_tree().process_frame
	var panel: FloatingPanel = lobby.get("_player_panel")
	_expect(panel.is_open() and not hover.visible and panel.content.find_child("player_card", true, false) != null, "a click keeps the card open in a window")
	await get_tree().process_frame
	_expect(picker.peeking(), "their robot stays on the stage while it is open")
	# The mouse over the crown in the window: the card says what unlocks it. (A headless
	# run has no real mouse hover, so the chip is told the mouse arrived.)
	var pinned := panel.content.find_child("player_card", true, false) as PlayerCardView
	var pinned_crown := pinned.find_child("hat_crown", true, false) as Control
	_expect(pinned_crown.mouse_filter == Control.MOUSE_FILTER_STOP, "a cosmetic takes the mouse (for its tooltip)")
	pinned_crown.mouse_entered.emit()
	var hint := pinned.find_child("locked_note", true, false) as Label
	_expect(hint != null and "Crown" in hint.text and "Warlord" in hint.text and "0 / 500" in hint.text,
		"pointing at a red one in the window says what unlocks it (%s)" % (hint.text if hint else "no hint"))
	_expect(pinned_crown.tooltip_text.contains("Warlord"), "and so does its tooltip")
	var labels_ok := true
	for k in ["robot", "weapon", "mobility"]:
		var l := pinned.find_child(k, true, false) as Label
		labels_ok = labels_ok and l != null and l.size.x > 60 and l.size.y < 40
	_expect(labels_ok, "the loadout lines are one line each, not one letter per line")
	Net.players_changed.emit()   # (anything in the lobby changing)
	await get_tree().process_frame
	_expect(panel.content.find_child("player_card", true, false) == pinned, "the open card is not rebuilt when nothing about them changed")
	panel.close()
	await get_tree().process_frame
	_expect(not picker.peeking(), "closing it puts your robot back")

	# Levelling up in the lobby.
	Achievements.add("xp", PlayerLevel.need(3))
	await get_tree().process_frame
	_expect(Net.player_level(1) == 4, "a level up reaches the lobby (%d)" % Net.player_level(1))

	lobby.queue_free()
	Net.leave()
	Achievements.reset_for_test()
	if _fails.is_empty():
		print("PASS: every check passed")
	else:
		print("FAIL:\n  " + "\n  ".join(_fails))
	get_tree().quit(1 if not _fails.is_empty() else 0)


func _expect(ok: bool, what: String) -> void:
	print("    %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)
