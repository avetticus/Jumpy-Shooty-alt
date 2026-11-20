extends Node
## Player colour checks (started by tests/player_color_test.gd).

var _fails: Array[String] = []


func run() -> void:
	await get_tree().process_frame
	print("Player colour checks")
	var saved := Settings.player_color
	Settings.player_color = -1
	Net.start_offline("Host", "needle", "pistol")
	_expect(Net.color_index(1) == 0, "with no colour picked you get the first one")

	Settings.player_color = 4
	Net.start_offline("Host", "needle", "pistol")
	_expect(Net.color_index(1) == 4 and Net.player_color(1) == Net.PLAYER_COLORS[4], "the colour you picked is yours when you host")
	_expect(Net.menu_color() == Net.PLAYER_COLORS[4], "and the menus show you in it")
	var bot := Net.add_bot(1)
	_expect(Net.color_index(bot) == 0, "a bot takes a colour nobody has (%d)" % Net.color_index(bot))

	print("  joining")
	Net.host_add_player(2, "Same", "orbit", "rifle", "grapple", 4)
	_expect(Net.color_index(2) != 4 and Net.color_index(2) != 0, "someone who wants the host's colour gets a free one instead (%d)" % Net.color_index(2))
	Net.host_add_player(3, "Seven", "rivet", "lmg", "grapple", 7)
	_expect(Net.color_index(3) == 7, "someone who wants a free colour gets it")
	Net.host_add_player(4, "Bot's", "rivet", "lmg", "grapple", 0)
	_expect(Net.color_index(4) == 0 and Net.color_index(bot) != 0, "a bot hands its colour to a player who wants it (the bot: %d)" % Net.color_index(bot))
	Net.host_add_player(5, "Odd", "rivet", "lmg", "grapple", 99)
	_expect(Net.color_index(5) >= 0 and Net.color_index(5) < Net.PLAYER_COLORS.size(), "a made-up colour number gets a real one")
	_expect(_all_different(), "everyone's colour is different (%s)" % [_colors()])

	print("  changing in the lobby")
	Net._apply_color(2, 7)
	_expect(Net.color_index(2) != 7 and Net.color_index(3) == 7, "you can't take another player's colour")
	Net._apply_color(2, 12)
	_expect(Net.color_index(2) == 12, "you can take a free one")
	var before := Net.color_index(1)
	Net.set_my_color(Net.color_index(bot))
	_expect(Net.color_index(1) != before and Net.color_index(bot) == before, "taking a bot's colour swaps with it")
	_expect(Net.color_taken(7) and not Net.color_taken(Net.color_index(bot)) and not Net.color_taken(Net.color_index(1)),
		"taken: another player's colour, not a bot's and not your own")
	Net.in_match = true
	Net._apply_color(2, 13)
	_expect(Net.color_index(2) == 12, "nobody changes colour mid-match")
	Net.in_match = false
	_expect(_all_different(), "everyone's colour is still different (%s)" % [_colors()])

	print("  the swatch on the robot stage")
	var picker := CharacterPicker.new("needle", Net.player_color(1), "pistol")
	add_child(picker)
	var button: Button = picker.find_child("color", true, false)
	_expect(button != null and not button.visible, "no swatch unless the page offers colours")
	picker.offer_colors(true)
	_expect(button.visible, "offered: a swatch on the stage")
	picker.open_colors()
	var grid: GridContainer = picker._palette.grid
	_expect(grid.get_child_count() == Net.PLAYER_COLORS.size(), "it opens every colour (%d)" % grid.get_child_count())
	_expect((grid.find_child("pick_7", false, false) as Button).disabled and not (grid.find_child("pick_13", false, false) as Button).disabled,
		"another player's colour can't be picked")
	var got := [-1]
	picker.color_picked.connect(func(i: int): got[0] = i)
	(grid.find_child("pick_13", false, false) as Button).pressed.emit()
	_expect(got[0] == 13 and not picker._palette.visible, "picking one reports it and closes the palette")
	picker.queue_free()

	Settings.player_color = saved
	Net.leave()
	if _fails.is_empty():
		print("PASS: every check passed")
	else:
		print("FAIL:\n  " + "\n  ".join(_fails))
	get_tree().quit(1 if not _fails.is_empty() else 0)


func _colors() -> Array:
	return Net.players.values().map(func(p): return p.color)


func _all_different() -> bool:
	var seen := {}
	for c in _colors():
		if seen.has(c):
			return false
		seen[c] = true
	return true


func _expect(ok: bool, what: String) -> void:
	print("    %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)
