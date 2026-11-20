extends Node
## Scoreboard checks (started by tests/scoreboard_test.gd): the columns in a shoot-out
## and in Killcam, the score and ping each player gets, offline and "online".

var _fails: Array[String] = []


func run() -> void:
	await get_tree().process_frame
	print("Scoreboard checks")
	Net.start_offline("Host", "needle", "pistol")
	Net.players[2] = {"name": "Client", "color": 1, "character": "orbit", "weapon": "rifle", "mobility": "grapple"}
	Net.players[3] = {"name": "Far", "color": 2, "character": "rivet", "weapon": "lmg", "mobility": "grapple"}
	var bot := Net.add_bot(1)
	Match.scores = {1: {"kills": 3, "deaths": 1, "level": 0, "points": 1234},
		2: {"kills": 2, "deaths": 2, "level": 0, "points": 2500}, 3: {"kills": 0, "deaths": 3, "level": 0, "points": 0},
		bot: {"kills": 1, "deaths": 0, "level": 0, "points": 300}}
	var hud := Hud.new()
	add_child(hud)
	await get_tree().process_frame

	print("  offline shoot-out")
	hud._refresh_scoreboard()
	var rows := _rows(hud)
	_expect(rows[0] == ["#", "PLAYER", "ROBOT  ·  WEAPON", "KILLS", "SCORE", "DEATHS"], "the heading has a SCORE column and no PING offline (%s)" % [rows[0]])
	_expect(_row_of(rows, "Host")[4] == KillcamMode.format(1234) and _row_of(rows, "Client")[4] == KillcamMode.format(2500),
		"each player's score is their points (%s)" % [_row_of(rows, "Host")])
	_expect(_row_of(rows, "Host")[3] == "3", "kills stay the main column in a shoot-out")

	print("  online")
	Net.is_online = true
	Net.pings = {2: 48, 3: 260}
	hud._refresh_scoreboard()
	rows = _rows(hud)
	_expect(rows[0][-1] == "PING", "online, the heading ends with PING")
	_expect(_row_of(rows, "Host")[-1] == "HOST", "the host's ping reads HOST")
	_expect(_row_of(rows, "Client")[-1] == "48" and _row_of(rows, "Far")[-1] == "260", "each client's ping is the one the host measured")
	_expect(_row_of(rows, "(bot)")[-1] == "-", "a bot has no ping")
	_expect(Net.player_ping(9999) == -1, "nobody, no ping")

	print("  Killcam")
	var s := Net.match_settings.duplicate()
	s["mode"] = "killcam"
	Net.match_settings = s
	hud._refresh_scoreboard()
	rows = _rows(hud)
	_expect(rows[0].slice(3, 5) == ["POINTS", "KILLS"], "Killcam: points are the main column, kills beside them (%s)" % [rows[0]])
	_expect(_row_of(rows, "Client")[3] == KillcamMode.format(2500) and _row_of(rows, "Client")[4] == "2", "Killcam: the client's points and kills")

	Net.is_online = false
	hud.queue_free()
	Net.leave()
	if _fails.is_empty():
		print("PASS: every check passed")
	else:
		print("FAIL:\n  " + "\n  ".join(_fails))
	get_tree().quit(1 if not _fails.is_empty() else 0)


func _expect(ok: bool, what: String) -> void:
	print("    %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


## The scoreboard's rows as lists of cell texts (the heading first).
func _rows(hud: Hud) -> Array:
	var out := []
	for plate in hud._score_rows.get_children():
		if plate.is_queued_for_deletion():
			continue
		var row: Node = plate.get_child(0)
		out.append(row.get_children().map(func(l): return (l as Label).text))
	return out


func _row_of(rows: Array, name_part: String) -> Array:
	for r in rows.slice(1):
		if name_part in str(r[1]):
			return r
	return ["?", "?", "?", "?", "?", "?", "?"]
