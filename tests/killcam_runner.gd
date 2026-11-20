extends Node
## Killcam checks (started by tests/killcam_test.gd):
##  - kill scores: a plain kill scores the base; headshots, range, the rope, a wall run,
##    a glide, an air shot, kicks, crashes, multikills, a clutch, the killer's and the
##    victim's speed and a flick of the aim each add their bit,
##    with the right words; the best kills are the highest scores, the earlier kill
##    first on a tie, never more than three;
##  - the numbers sent with a death and with the end of the match turn back into the
##    same kill;
##  - recording: a player's frames blend smoothly between samples, hold at either end,
##    never blend across a death, and old frames are dropped; a clip keeps only its
##    own few seconds, and shows each player as late as the killer saw them;
##  - offline, nobody is seen late (the host runs the bots), so nothing is shifted;
##  - playback: the camera is the killer's eyes, looking where they looked; the victim
##    is drawn where the clip says; the shot plays; the kill moment and the end are
##    announced once; the results screen's slow motion makes the kill last longer;
##  - after a match the three best kills play fullscreen, counting down to the best,
##    from this copy's clips (saying so for one it did not see), then the results page
##    shows; it still fits a 1600 x 900 window without scrolling and has a button to
##    watch each kill again (fullscreen) and one for all three;
##  - a killcam saved as a video: a Motion JPEG AVI with every frame and an index, the
##    clip's length in slow motion plus a held last frame, 1280x720, named after the kill, on Halcyon, whose terminal and events must not mind
##    being built outside a match.

var _fails: Array[String] = []


func run() -> void:
	await get_tree().process_frame
	print("Killcam checks")
	_scores()
	_mode()
	_packing()
	_tracks()
	_clips()
	_offline_timing()
	await _playback()
	await _results_page()
	_sound_mix()
	await _video()
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


const S := MovementController.State


func _scores() -> void:
	print("  kill scores")
	var plain := KillScore.score({"distance": 6.0})
	_expect(plain == [KillScore.BASE, 0], "a plain kill close by on the ground scores the base and no tags (%s)" % [plain])
	var head := KillScore.score({"distance": 6.0, "headshot": true})
	_expect(head[0] == KillScore.BASE + KillScore.HEADSHOT and head[1] & KillScore.T_HEADSHOT, "a headshot adds %d" % KillScore.HEADSHOT)
	var far := KillScore.score({"distance": 40.0})
	_expect(far[0] == KillScore.BASE + 75 and far[1] & KillScore.T_LONG, "40 m adds 3 a metre past 15 m, and the range tag (%d)" % far[0])
	var very_far := KillScore.score({"distance": 300.0})
	_expect(very_far[0] == KillScore.BASE + KillScore.RANGE_MAX, "range points stop at %d" % KillScore.RANGE_MAX)
	var rope := KillScore.score({"killer_state": S.GRAPPLE})
	_expect(rope[0] == KillScore.BASE + KillScore.MID_AIR + KillScore.ON_ROPE and rope[1] & KillScore.T_ROPE and rope[1] & KillScore.T_MID_AIR,
		"on the rope counts as mid-air plus the rope (%d)" % rope[0])
	_expect(KillScore.score({"killer_state": S.WALL_RUN})[1] & KillScore.T_WALL, "off a wall is tagged")
	_expect(KillScore.score({"killer_state": S.GLIDE})[1] & KillScore.T_GLIDE, "gliding is tagged")
	_expect(KillScore.score({"killer_state": S.SLIDE})[0] == KillScore.BASE, "a slide is on the ground: no bonus")
	_expect(KillScore.score({"victim_state": S.AIR})[1] & KillScore.T_AIR_SHOT, "a victim in the air makes an air shot")
	var kick: int = KillScore.score({"cause": "kick"})[0]
	var flying: int = KillScore.score({"cause": "flying_kick"})[0]
	_expect(flying > kick and kick > KillScore.BASE, "a flying kick beats a kick, which beats a plain kill (%d, %d)" % [flying, kick])
	_expect(KillScore.score({"cause": "slam"})[1] & KillScore.T_SMASHED, "a crash into a wall is tagged")
	_expect(KillScore.score({"melee": true})[1] & KillScore.T_MELEE, "a blade kill is tagged")
	_expect(KillScore.score({"melee": true, "cause": "kick"})[1] & KillScore.T_MELEE == 0, "a kick with a blade in hand is a kick, not a cut")
	var triple := KillScore.score({"streak": 2})
	_expect(triple[0] == KillScore.BASE + 2 * KillScore.MULTI, "a third kill in a row adds two multikill bonuses")
	_expect(KillScore.score({"killer_hp": 10.0})[1] & KillScore.T_CLUTCH, "a kill on 10 HP is a clutch")
	print("  momentum: both players' speeds together")
	var still_victim := KillScore.score({"killer_speed": 30.0, "victim_speed": 0.0})
	_expect(still_victim[0] == KillScore.BASE and still_victim[1] & KillScore.T_FAST, "flying past a target standing still: no momentum points (%d)" % still_victim[0])
	_expect(KillScore.score({"killer_speed": 0.0, "victim_speed": 30.0})[0] == KillScore.BASE, "standing still and hitting a fast target: none either")
	var slow: int = KillScore.score({"killer_speed": 30.0, "victim_speed": 1.5})[0] - KillScore.BASE
	_expect(slow > 0 and slow <= 30, "one of them barely moving: very little (%d)" % slow)
	var both := KillScore.score({"killer_speed": 20.0, "victim_speed": 20.0})
	_expect(both[0] == KillScore.BASE + 140 and both[1] & KillScore.T_FAST and both[1] & KillScore.T_TARGET_FAST,
		"both going 20 m/s: 10 a m/s past 6, and both speed tags (%d)" % both[0])
	_expect(KillScore.score({"killer_speed": 24.0, "victim_speed": 24.0})[0] > KillScore.score({"killer_speed": 40.0, "victim_speed": 10.0})[0],
		"two players both moving fast beats one very fast and one slow")
	_expect(KillScore.score({"killer_speed": 11.5, "victim_speed": 11.5})[0] == KillScore.BASE + 55, "both sprinting: a little")
	_expect(KillScore.score({"killer_speed": 60.0, "victim_speed": 60.0})[0] == KillScore.BASE + KillScore.MOTION_MAX, "momentum points stop at %d" % KillScore.MOTION_MAX)
	_expect(KillScore.motion_points(169.0, 20.0) == KillScore.motion_points(KillScore.SPEED_CAP, 20.0), "a body flung by a blow counts as at most %d m/s" % KillScore.SPEED_CAP)
	print("  trickshots")
	var air: int = KillScore.score({"killer_state": S.AIR})[0]
	var air_flick := KillScore.score({"killer_state": S.AIR, "flick": 95.0})
	_expect(air_flick[0] == air + 75 + KillScore.TRICK, "in the air with a flick: two tricks, one combo bonus (%d)" % air_flick[0])
	var four := KillScore.score({"killer_state": S.AIR, "victim_state": S.AIR, "flick": 95.0, "distance": 40.0})
	_expect(KillScore.trick_count(four[1]) == 4 and "TRICKSHOT" in KillScore.words({"tags": four[1]}), "four tricks at once is a trickshot")
	_expect(KillScore.parts(four[1], 0, 40.0, 0.0, 0.0, 95.0).has(["TRICKSHOT ×4", 3 * KillScore.TRICK]), "...worth %d on top" % (3 * KillScore.TRICK))
	_expect(KillScore.trick_count(KillScore.score({"headshot": true, "distance": 6.0})[1]) == 0, "a headshot on the ground close by is no trick")
	print("  blows (kicks, crashes, blades) against shots")
	# Grapple in and flying-kick them: on the rope, both fast (the reel, then the kick's
	# fling), the target in the air, a turn to face them. Playtesters found this won every match.
	var grapple_kick := {"distance": 2.5, "killer_state": S.GRAPPLE, "victim_state": S.AIR, "cause": "flying_kick",
		"killer_speed": 26.0, "victim_speed": 40.0, "flick": 90.0}
	var gk := KillScore.score(grapple_kick)
	var gk_parts := KillScore.parts(gk[1], 0, 2.5, 26.0, 40.0, 90.0)
	_expect(KillScore.is_blow(gk[1]) and KillScore.trick_count(gk[1]) == 0, "a flying kick is a blow: no trickshot")
	_expect(not gk_parts.any(func(p): return str(p[0]).begins_with("FLICK") or p[0] == "AIR SHOT"),
		"...and no flick or air shot points (%s)" % [gk_parts])
	var gk_motion: Array = gk_parts.filter(func(p): return str(p[0]).begins_with("MOMENTUM"))
	_expect(gk_motion.size() == 1 and int(gk_motion[0][1]) == int(KillScore.motion_points(26.0, 40.0) * KillScore.BLOW_MOTION),
		"...and momentum at %d%% (%s)" % [roundi(KillScore.BLOW_MOTION * 100.0), gk_motion])
	var words_gk := KillScore.words({"tags": gk[1], "speed": 26.0, "target_speed": 40.0, "flick": 90.0})
	_expect(not words_gk.any(func(w): return str(w).begins_with("FLICK") or str(w).begins_with("TARGET AT") or w == "AIR SHOT" or w == "TRICKSHOT"),
		"its tags leave out what the blow did on its own (%s)" % [words_gk])
	# An anti-materiel trickshot: off a rope swing, a flick onto a target in the air, 40 m off, both moving.
	var snipe := KillScore.score({"distance": 40.0, "headshot": true, "killer_state": S.GRAPPLE, "victim_state": S.AIR,
		"killer_speed": 24.0, "victim_speed": 14.0, "flick": 90.0})
	_expect(snipe[0] > gk[0] + 200, "an anti-materiel trickshot beats grapple-and-kick by a long way (%d against %d)" % [snipe[0], gk[0]])
	var shot_from_rope := KillScore.score({"distance": 25.0, "killer_state": S.GRAPPLE, "killer_speed": 22.0, "victim_speed": 9.0})
	_expect(shot_from_rope[0] >= gk[0] - 60, "even a plain shot off the rope at a moving target is in the same league (%d against %d)" % [shot_from_rope[0], gk[0]])
	_expect(gk[0] > KillScore.score({"distance": 2.0, "cause": "kick"})[0] + 150, "grapple-and-kick still beats a kick on the ground (it is a good killcam, just not the best every time)")
	var flick := KillScore.score({"flick": 95.0})
	_expect(flick[0] == KillScore.BASE + 75 and flick[1] & KillScore.T_FLICK, "a 95° flick adds a point a degree past 20, and a tag (%d)" % flick[0])
	_expect(KillScore.score({"flick": 15.0}) == [KillScore.BASE, 0], "steady aim is no bonus")
	_expect(KillScore.score({"flick": 400.0})[0] == KillScore.BASE + KillScore.FLICK_MAX, "flick points stop at %d" % KillScore.FLICK_MAX)
	var words := KillScore.tag_words(rope[1] | KillScore.T_HEADSHOT | KillScore.T_LONG | KillScore.T_FLICK | KillScore.T_FAST | KillScore.T_TARGET_FAST,
		2, 42.4, 24.2, 19.6, 95.4)
	_expect(words == ["TRIPLE KILL", "TRICKSHOT", "ON THE ROPE", "HEADSHOT", "FLICK 95°", "24 M/S", "TARGET AT 20 M/S", "42 M"], "the words come most telling first (%s)" % [words])
	print("  where a kill's points came from")
	var facts := {"distance": 42.4, "headshot": true, "killer_state": S.GRAPPLE, "victim_state": S.AIR, "streak": 1,
		"killer_hp": 20.0, "killer_speed": 24.2, "victim_speed": 19.6, "flick": 95.0}
	var scored := KillScore.score(facts)
	var parts := KillScore.parts(scored[1], 1, 42.4, 24.2, 19.6, 95.0)
	var sum := 0
	for p in parts:
		sum += int(p[1])
	_expect(sum == scored[0], "the parts add up to the score (%d of %d: %s)" % [sum, scored[0], parts])
	_expect(parts[0] == ["KILL", KillScore.BASE] and parts.size() == 11, "the base first, then one part per bonus (%d parts)" % parts.size())
	_expect(["HEADSHOT", KillScore.HEADSHOT] in parts and ["DOUBLE KILL", KillScore.MULTI] in parts and ["FLICK 95°", 75] in parts,
		"a part has its words and its points")
	_expect(KillScore.parts(0, 0, 6.0) == [["KILL", KillScore.BASE]], "a plain kill is the base alone")
	for i in 200:   # every copy's breakdown, from the numbers sent, adds up to the host's score
		var f := {"distance": randf_range(0.0, 80.0), "headshot": randf() < 0.5, "killer_state": [S.GROUND, S.AIR, S.GRAPPLE, S.WALL_RUN, S.GLIDE].pick_random(),
			"victim_state": [S.GROUND, S.AIR].pick_random(), "cause": ["", "kick", "flying_kick", "slam"].pick_random(), "melee": randf() < 0.3,
			"streak": randi_range(0, 3), "killer_hp": randf_range(1.0, 100.0), "killer_speed": randf_range(0.0, 40.0),
			"victim_speed": randf_range(0.0, 40.0), "flick": float(randi_range(0, 200))}
		f.distance = float(roundi(f.distance * 10.0)) / 10.0
		f.killer_speed = float(roundi(f.killer_speed * 10.0)) / 10.0
		f.victim_speed = float(roundi(f.victim_speed * 10.0)) / 10.0
		var s := KillScore.score(f)
		var info := {"tags": s[1], "streak": f.streak, "distance": f.distance, "speed": f.killer_speed, "target_speed": f.victim_speed, "flick": f.flick}
		var total := 0
		for p in KillScore.breakdown(info):
			total += int(p[1])
		if total != s[0]:
			_expect(false, "the breakdown of %s adds up to %d, not %d" % [f, total, s[0]])
			break
		if i == 199:
			_expect(true, "200 random kills: every breakdown adds up to the score")
	print("  speed and aim from a player's recent states")
	var buf := SnapshotBuffer.new()
	for i in 41:   # one second at 40 a second: turning 90° over the last half, ending at 25 m/s
		var t := i / 40.0
		buf.push(t, t, Vector3.ZERO, Vector3(0, 0, -25.0 if i == 40 else -10.0), deg_to_rad(90.0) * clampf((t - 0.5) / 0.5, 0.0, 1.0), 0.0, 0)
	_expect(is_equal_approx(buf.speed(), 25.0), "speed is from the newest state (%.1f)" % buf.speed())
	_expect(absf(buf.aim_travel(KillScore.FLICK_WINDOW) - 90.0) < 0.5, "the aim swung 90° in the window (%.1f)" % buf.aim_travel(KillScore.FLICK_WINDOW))
	_expect(absf(buf.aim_travel(0.25) - 45.0) < 0.5, "...45° in the last quarter second (%.1f)" % buf.aim_travel(0.25))
	var kills := [
		{"seq": 1, "score": 150}, {"seq": 2, "score": 300}, {"seq": 3, "score": 150},
		{"seq": 4, "score": 290}, {"seq": 5, "score": 300}, {"seq": 6, "score": 100}]
	var best := KillScore.best(kills, 3).map(func(k): return k.seq)
	_expect(best == [2, 5, 4], "the best three are the highest scores, the earlier kill first on a tie (%s)" % [best])
	kills.shuffle()
	_expect(KillScore.best(kills, 3).map(func(k): return k.seq) == [2, 5, 4], "whatever order the kills are in")
	_expect(KillScore.best(kills.slice(0, 2), 3).size() == 2, "fewer kills than three: all of them")


func _mode() -> void:
	print("  the Killcam mode")
	var ffa := {"game": "ffa", "mode": "kills", "map": Maps.default_id()}
	var on := GunGame.with_mode(ffa, "killcam", Maps.default_id())
	_expect(on.mode == "killcam" and on.game == "ffa" and GunGame.mode_of(on) == "killcam", "the mode switch sets it up as a free-for-all with its own rules (%s)" % [on])
	_expect(GunGame.mode_of(GunGame.with_mode(on, "ffa", Maps.default_id())) == "ffa" and GunGame.with_mode(on, "ffa", Maps.default_id()).mode == "kills",
		"...and switching back gives an ordinary shoot-out")
	_expect(GunGame.mode_of(GunGame.with_mode(on, "gungame", Maps.default_id())) == "gungame", "Gun Game still switches as before")
	_expect(KillcamMode.format(10000) == "10,000" and KillcamMode.format(1500) == "1,500" and KillcamMode.format(999) == "999" 		and KillcamMode.format(1234567) == "1,234,567", "points read with commas")
	var defaults := LobbySettings.clean({})
	_expect(defaults.killcam_points == 5000 and defaults.killcam_minutes == 5, "by default: first to 5,000 points or the most after 5 minutes (%s)" % [defaults])
	_expect(LobbySettings.clean({"killcam_points": 12345, "killcam_minutes": 7}).killcam_points == 12500, "points are picked in steps of %d" % KillcamMode.POINTS_STEP)
	var wild := LobbySettings.clean({"killcam_points": 99999999, "killcam_minutes": -4})
	_expect(wild.killcam_points == KillcamMode.POINTS_MAX and wild.killcam_minutes == KillcamMode.MINUTES_MIN, "out of range is brought back in (%s)" % [wild])
	_expect(LobbySettings.clean({"killcam_points": "lots", "killcam_minutes": null}).killcam_minutes == KillcamMode.MINUTES,
		"nonsense falls back to the defaults")
	var was := Net.match_settings
	Net.match_settings = LobbySettings.clean({"game": "ffa", "mode": "killcam", "map": Maps.default_id(), "killcam_points": 8000, "killcam_minutes": 12})
	_expect(KillcamMode.target() == 8000 and KillcamMode.minutes() == 12, "the match goes by the host's settings (%d, %d)" % [KillcamMode.target(), KillcamMode.minutes()])
	Net.match_settings = was


func _packing() -> void:
	print("  what travels with a death")
	var info := {"seq": 7, "score": 345, "tags": KillScore.T_ROPE | KillScore.T_MID_AIR, "streak": 1,
		"distance": 23.4, "weapon": "anti_materiel", "speed": 21.7, "target_speed": 9.3, "flick": 84.0, "killer": 2, "victim": 9001}
	var packed := Match.pack_kill(info)
	_expect(packed.size() == 11 and packed.all(func(v): return v is int or v is String), "a kill travels as ten plain numbers and a word (%s)" % [packed])
	_expect(Match.kill_info(packed) == info, "...and turns back into the same kill")
	_expect(Match.kill_info(packed.slice(0, 9), 2, 9001) == info, "the death message carries the killer and victim already")
	var bytes := var_to_bytes(packed.slice(0, 9)).size()
	_expect(bytes <= 100, "about %d bytes a kill" % bytes)


func _frame(pos: Vector3, yaw: float = 0.0, pitch: float = 0.0, alive: bool = true, weapon: String = "pistol") -> Array:
	return [pos, Vector3.ZERO, yaw, pitch, 0, 0, false, Vector3.ZERO, alive, true, 1.6, weapon]


func _tracks() -> void:
	print("  recording a player")
	var t := KillClip.Track.new()
	for i in 31:
		t.push(i / 30.0, _frame(Vector3(i / 3.0, 0, 0), i * 0.01))
	var mid := t.sample(0.55)
	_expect(absf((mid[0] as Vector3).x - 5.5) < 0.01, "between frames the position blends (%.3f)" % (mid[0] as Vector3).x)
	_expect(absf(float(mid[2]) - 0.165) < 0.001, "...and so does the aim")
	_expect(t.sample(-1.0)[0] == Vector3.ZERO and t.sample(9.0)[0] == Vector3(10, 0, 0), "before and after the track it holds the first and last frames")
	t.push(1.0, _frame(Vector3(10, 0, 0)))
	_expect(t.times[-1] > t.times[-2], "a frame stamped no later than the last still goes after it")
	var d := KillClip.Track.new()
	d.push(0.0, _frame(Vector3.ZERO, 0.0, 0.0, true))
	d.push(0.1, _frame(Vector3(1, 0, 0), 0.0, 0.0, false))
	_expect(d.sample(0.04)[8] == true and d.sample(0.04)[0] == Vector3.ZERO, "no blending across a death")
	var part := t.slice(0.4, 0.6)
	_expect(part.first_time() <= 0.4 and part.last_time() >= 0.6 and part.times.size() <= 9, "a slice keeps its stretch and a frame either side (%d frames)" % part.times.size())
	t.trim(0.5)
	_expect(t.first_time() >= 0.49 and t.first_time() <= 0.5, "old frames are dropped (%.3f)" % t.first_time())


func _clips() -> void:
	print("  clips")
	var clip := KillClip.new()
	clip.killer = 1
	clip.victim = 2
	clip.kill_time = 5.0
	clip.start = 3.0
	clip.end = 5.5
	clip.offsets = {1: 0.0, 2: -0.2}
	clip.event_offsets = {1: 0.0, 2: 0.2}
	for id in [1, 2]:
		var t := KillClip.Track.new()
		for i in 300:
			t.push(i / 30.0, _frame(Vector3(id, 0, i)))
		clip.tracks[id] = t
	clip.events = [{"t": 1.0, "who": 1}, {"t": 4.9, "who": 1}, {"t": 5.4, "who": 2}, {"t": 6.5, "who": 1}]
	_expect(is_equal_approx(clip.time_for(2, 4.0), 3.8), "the victim is sampled as late as the killer saw them")
	_expect(is_equal_approx(clip.event_time(clip.events[2]), 5.6), "...and so are the victim's shots")
	_expect(clip.has_killer(1.0), "the killer's track covers the kill")
	var early := KillClip.new()
	early.killer = 1
	early.kill_time = 0.5
	early.start = -2.0
	early.end = 1.0
	early.tracks = {1: clip.tracks[1]}
	_expect(not early.has_killer(1.0), "a kill less than a second into the recording has no killcam")
	early.kill_time = 1.5
	_expect(early.has_killer(1.0) and early.start == 0.0, "...and a short one starts at the killer's first frame")
	var cut := clip.cut(0.5)
	_expect(cut.events.size() == 2, "a kept clip keeps only the events in its stretch (%d)" % cut.events.size())
	var tk: KillClip.Track = cut.tracks[1]
	_expect(tk.first_time() <= 2.5 and tk.last_time() >= 6.0 and tk.times.size() < 120, "...and only the frames it needs (%d)" % tk.times.size())
	var tv: KillClip.Track = cut.tracks[2]
	_expect(tv.first_time() <= 2.3, "the victim's frames start earlier, by how late the killer saw them")


func _offline_timing() -> void:
	print("  timing offline")
	Net.start_offline("Tester", "needle", "pistol")
	var bot := Net.add_bot(1, "rifle")
	_expect(Killcam._seen_late(1, bot) == 0.0 and Killcam._seen_late(bot, 1) == 0.0, "the host runs the bots: nobody is seen late")
	_expect(Killcam._delay(bot) == 0.0, "and nothing reaches us late")


## A clip of the killer at (0, 0, 0) turning to face the victim 10 m north (-z),
## who drops when the shot lands at 2.0 s.
func _test_clip() -> KillClip:
	var clip := KillClip.new()
	clip.killer = 1
	clip.victim = 9001
	clip.kill_time = 2.0
	clip.start = 0.0
	clip.end = 2.5
	clip.info = {"seq": 1, "score": 160, "tags": KillScore.T_HEADSHOT, "streak": 0, "distance": 10.0, "weapon": "pistol", "killer": 1, "victim": 9001}
	var killer := KillClip.Track.new()
	var victim := KillClip.Track.new()
	killer.name = "Tester"
	victim.name = "Gizmo"
	for i in 91:
		var t := i / 30.0
		killer.push(t, _frame(Vector3(0, 0, 0), lerpf(1.2, 0.0, minf(t / 1.5, 1.0)), 0.0))
		victim.push(t, _frame(Vector3(0, 0, -10), PI, 0.0, t < 2.05))
	clip.tracks = {1: killer, 9001: victim}
	clip.events = [{"t": 1.95, "who": 1, "kind": "shot", "muzzle": Vector3(0, 1.5, 0),
		"ends": PackedVector3Array([Vector3(0, 1.6, -10)]), "hits": [true], "weapon": "pistol"}]
	return clip


func _playback() -> void:
	print("  playback")
	var world := Node3D.new()
	add_child(world)
	var view := KillcamView.new().setup(_test_clip(), false)
	view.world_sound = false
	world.add_child(view)
	view.set_process(false)   # stepped by hand, so the test does not depend on the frame rate
	var moments := [0]
	var ends := [0]
	view.kill_moment.connect(func(): moments[0] += 1)
	view.finished.connect(func(): ends[0] += 1)
	var step := 1.0 / 60.0
	var steps := 0
	while view.time < 1.8:
		view._process(step)
		steps += 1
	var cam := view.camera.global_transform
	_expect(cam.origin.distance_to(Vector3(0, 1.6, 0)) < 0.01, "the camera is at the killer's eyes (%s)" % [cam.origin])
	var ahead := -cam.basis.z
	_expect(ahead.dot(Vector3(0, 0, -1)) > 0.99, "...looking where they looked: at the victim (%s)" % [ahead])
	var ghost := view.get_node_or_null("Ghost_9001") as Node3D
	_expect(ghost != null and ghost.visible and ghost.global_position.distance_to(Vector3(0, 0, -10)) < 0.01, "the victim is drawn where the clip says")
	_expect(view.get_node_or_null("Ghost_1") == null, "the killer has no body of their own in the way, only arms")
	_expect(view.camera.get_child_count() > 0 and view.camera.get_child(0) is ViewModel, "the killer's first-person arms are on the camera")
	_expect(moments[0] == 0, "no kill before the kill")
	while not view.done and steps < 10000:
		view._process(step)
		steps += 1
	_expect(view._next == 1, "the killing shot played")
	_expect(moments[0] == 1 and ends[0] == 1, "the kill moment and the end are announced once each (%d, %d)" % [moments[0], ends[0]])
	_expect(absf(steps * step - 2.5) < 0.05, "at normal speed the clip lasts as long as it is (%.2f s)" % (steps * step))
	view._process(step)
	_expect(ends[0] == 1 and view.time == 2.5, "then it holds the last frame")
	view.queue_free()
	var slow := KillcamView.new().setup(_test_clip(), true)
	slow.world_sound = false
	world.add_child(slow)
	slow.set_process(false)
	var slow_steps := 0
	while not slow.done and slow_steps < 10000:
		slow._process(step)
		slow_steps += 1
	var expect := 2.5 + (KillcamView.SLOW_FROM + KillcamView.SLOW_UNTIL) * (1.0 / KillcamView.SLOW - 1.0)
	_expect(absf(slow_steps * step - expect) < 0.1, "slow motion round the kill makes it last longer (%.2f s, about %.2f)" % [slow_steps * step, expect])
	slow.queue_free()
	print("  a blow plays in third person")
	var kick_clip := _test_clip()
	kick_clip.info.tags = KillScore.T_KICK
	kick_clip.info.weapon = "kick"
	var near := KillClip.Track.new()   # the victim, kicked from close by
	near.name = "Gizmo"
	for i in 91:
		near.push(i / 30.0, _frame(Vector3(0, 0, -3), PI, 0.0, i / 30.0 < 2.05))
	kick_clip.tracks[9001] = near
	kick_clip.events = []
	var third := KillcamView.new().setup(kick_clip, false)
	third.world_sound = false
	world.add_child(third)
	third.set_process(false)
	_expect(third.third_person, "a kick kill is watched in third person")
	_expect(not KillcamView.new().setup(_test_clip(), false).third_person, "...a shot through the killer's eyes")
	var t_steps := 0
	while third.time < 1.95 and t_steps < 10000:
		third._process(step)
		t_steps += 1
	var killer_body := third.get_node_or_null("Ghost_1") as Node3D
	_expect(killer_body != null and killer_body.visible, "the killer is a body, in view")
	_expect(third.camera.get_child_count() == 0, "...with no first-person arms")
	var eye := third.camera.global_position
	var head := Vector3(0, 1.6, 0)
	_expect(eye.z > head.z + 2.0 and eye.y > head.y and eye.distance_to(head) < 5.0,
		"the camera follows close behind and above the killer (%s)" % [eye])
	var to_victim := (Vector3(0, 1.1, -3) - eye).normalized()
	_expect((-third.camera.global_transform.basis.z).dot(to_victim) > 0.9, "...turned towards the victim")
	third.queue_free()
	world.queue_free()
	await get_tree().process_frame


func _results_page() -> void:
	print("  results page")
	Net.start_offline("Tester", "needle", "pistol")
	var bot := Net.add_bot(1, "rifle")
	Net.match_settings["map"] = "halcyon"   # the busiest map: terminals, events, low gravity
	Match.last_results = [
		{"id": 1, "name": "Tester", "kills": 3, "deaths": 1, "level": 0},
		{"id": bot, "name": Net.player_name(bot), "kills": 1, "deaths": 3, "level": 0}]
	Match.highlights = [
		{"seq": 4, "score": 345, "tags": KillScore.T_ROPE | KillScore.T_MID_AIR | KillScore.T_HEADSHOT, "streak": 1, "distance": 31.0, "weapon": "pistol", "killer": 1, "victim": bot},
		{"seq": 2, "score": 160, "tags": KillScore.T_HEADSHOT, "streak": 0, "distance": 8.0, "weapon": "rifle", "killer": bot, "victim": 1},
		{"seq": 1, "score": 100, "tags": 0, "streak": 0, "distance": 4.0, "weapon": "pistol", "killer": 1, "victim": bot}]
	Killcam.clips.clear()
	var clip := _test_clip()
	clip.info = Match.highlights[0]
	Killcam.clips[4] = clip
	var holder := SubViewportContainer.new()
	add_child(holder)
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 900)
	holder.add_child(vp)
	var page: Control = load("res://game/ui/results_menu.tscn").instantiate()
	vp.add_child(page)
	for i in 8:
		await get_tree().process_frame
	var frame := page.find_children("*", "MenuFrame", true, false)[0] as MenuFrame
	_expect(not frame.scrolling(), "with the best kills on it the page still fits 1600 x 900 without scrolling")
	var screens := page.find_children("*", "KillcamScreen", true, false)
	_expect(screens.size() == 1, "the best kills play first, over the page")
	var whole := Rect2(Vector2.ZERO, Vector2(vp.size))
	if screens.size() == 1:
		var ks := screens[0] as KillcamScreen
		_expect(ks.get_global_rect().is_equal_approx(whole), "...fullscreen (%s)" % [ks.get_global_rect()])
		_expect(ks.index == 2 and ks.find_children("*", "KillcamView", true, false).is_empty(),
			"counting down from #3, which this copy did not see: no replay, it says so (#%d)" % (ks.index + 1))
		ks.next()
		_expect(ks.index == 1, "next: #2")
		ks.next()
		await get_tree().process_frame
		_expect(ks.index == 0 and ks.find_children("*", "KillcamView", true, false).size() == 1, "and last the best, from this copy's clip")
		ks.next()
		await get_tree().process_frame
		_expect(not is_instance_valid(ks) or ks.is_queued_for_deletion(), "after the best the page shows")
	var buttons := page.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text.begins_with("#"))
	_expect(buttons.size() == 3, "the page lists the best kills, a button each (%d)" % buttons.size())
	var all := page.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text.begins_with("Watch"))
	var screen := whole.grow(0.5)
	_expect(all.size() == 1 and (buttons + all).all(func(b): return screen.encloses((b as Control).get_global_rect())),
		"...and one to watch them all, all on the screen")
	if buttons.size() == 3:
		(buttons[0] as Button).pressed.emit()
		await get_tree().process_frame
		var again := page.find_children("*", "KillcamScreen", true, false)
		_expect(again.size() == 1 and (again[0] as KillcamScreen).index == 0 and (again[0] as KillcamScreen).order.is_empty(),
			"a button plays its kill again, fullscreen, on its own")
		if again.size() == 1:
			(again[0] as KillcamScreen).skip_all()
			await get_tree().process_frame
			_expect(page.find_children("*", "KillcamScreen", true, false).all(func(n): return n.is_queued_for_deletion()), "Esc closes it")
	holder.queue_free()
	Match.highlights = []
	Match.last_results = []
	Killcam.clips.clear()
	await get_tree().process_frame


## Reads the parts of an AVI that players' video apps rely on.
func _read_avi(bytes: PackedByteArray) -> Dictionary:
	var out := {"riff": bytes.slice(0, 4).get_string_from_ascii(), "kind": bytes.slice(8, 12).get_string_from_ascii(),
		"size_ok": bytes.decode_u32(4) == bytes.size() - 8, "frames": [], "index": 0}
	var avih := _find(bytes, "avih")
	if avih >= 0:
		out["fps"] = roundi(1000000.0 / bytes.decode_u32(avih + 8))
		out["total"] = bytes.decode_u32(avih + 8 + 16)
		out["w"] = bytes.decode_u32(avih + 8 + 32)
		out["h"] = bytes.decode_u32(avih + 8 + 36)
	out["codec"] = bytes.slice(_find(bytes, "strh") + 12, _find(bytes, "strh") + 16).get_string_from_ascii()
	var movi := _find(bytes, "movi")
	var at := movi + 4
	while at + 8 <= bytes.size() and bytes.slice(at, at + 4).get_string_from_ascii() == "00dc":
		var n := bytes.decode_u32(at + 4)
		(out.frames as Array).append(bytes[at + 8] == 0xFF and bytes[at + 9] == 0xD8)   # a JPEG starts FF D8
		at += 8 + n + (n % 2)
	var idx := _find(bytes, "idx1")
	if idx >= 0:
		out["index"] = bytes.decode_u32(idx + 4) / 16
		out["index_ok"] = bytes.decode_u32(idx + 8 + 8) + movi == movi + 4   # the first entry points just past 'movi'
	return out


func _find(bytes: PackedByteArray, tag: String) -> int:
	var t := tag.to_ascii_buffer()
	for i in bytes.size() - 3:
		if bytes[i] == t[0] and bytes[i + 1] == t[1] and bytes[i + 2] == t[2] and bytes[i + 3] == t[3]:
			return i
	return -1


## What an MP4 says about itself: its codec, size, frame count and frame rate, from the
## video track's boxes (moov > trak > mdia > minf > stbl).
func _read_mp4(b: PackedByteArray) -> Dictionary:
	var out := {"codec": "", "w": 0, "h": 0, "total": 0, "fps": 0, "scale": 0}
	if b.size() < 12 or b.slice(4, 8).get_string_from_ascii() != "ftyp":
		return out
	_mp4_boxes(b, 0, b.size(), out)
	return out


func _mp4_boxes(b: PackedByteArray, from: int, to: int, out: Dictionary) -> void:
	var at := from
	while at + 8 <= to:
		var size := b.decode_u32(at)
		size = ((size & 0xff) << 24) | ((size & 0xff00) << 8) | ((size >> 8) & 0xff00) | ((size >> 24) & 0xff)   # (big-endian)
		var kind := b.slice(at + 4, at + 8).get_string_from_ascii()
		var head := 8
		if size == 1:   # a 64-bit size follows
			size = 0
			for k in 8:
				size = (size << 8) | b[at + 8 + k]
			head = 16
		elif size == 0:
			size = to - at
		if size < head or at + size > to:
			return
		var body := at + head
		match kind:
			"trak":   # one track: the picture's fills `out`; the sound's codec goes in out.audio
				var track := {"codec": "", "w": 0, "h": 0, "total": 0, "fps": 0, "scale": 0, "kind": ""}
				_mp4_boxes(b, body, at + size, track)
				if track.kind == "vide":
					for key in ["codec", "w", "h", "total", "fps"]:
						out[key] = track[key]
				elif track.kind == "soun":
					out["audio"] = track.codec
			"moov", "mdia", "minf", "stbl":
				_mp4_boxes(b, body, at + size, out)
			"hdlr":
				out["kind"] = b.slice(body + 8, body + 12).get_string_from_ascii()
			"mdhd":
				if b[body] == 0:
					out.scale = _be32(b, body + 12)
			"stsd":
				out.codec = b.slice(body + 12, body + 16).get_string_from_ascii()
				out.w = (b[body + 40] << 8) | b[body + 41]
				out.h = (b[body + 42] << 8) | b[body + 43]
			"stsz":
				out.total = _be32(b, body + 8)
			"stts":
				var delta := _be32(b, body + 12)
				if int(out.scale) > 0 and delta > 0:
					out.fps = roundi(int(out.scale) / float(delta))
		at += size


func _be32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]


## The sound track's mix: a sound in the world is panned to its side and quieter far
## away; one of your own sits in the middle at its own volume.
func _sound_mix() -> void:
	print("  a saved killcam's sound")
	var tone := AudioStreamWAV.new()
	tone.format = AudioStreamWAV.FORMAT_16_BITS
	tone.mix_rate = KillcamExport.RATE
	var pcm := PackedByteArray()
	pcm.resize(KillcamExport.RATE / 10 * 2)   # 0.1 s
	for i in pcm.size() / 2:
		pcm.encode_s16(i * 2, int(16000.0 * sin(TAU * 440.0 * i / KillcamExport.RATE)))
	tone.data = pcm
	var ears := Transform3D()   # looking down -z: +x is to the right
	var loudness := func(bytes: PackedByteArray, from: float, to: float) -> Vector2:
		var l := 0.0
		var r := 0.0
		for i in range(int(from * KillcamExport.RATE), int(to * KillcamExport.RATE)):
			l += absf(bytes.decode_s16(i * 4))
			r += absf(bytes.decode_s16(i * 4 + 2))
		return Vector2(l, r)
	var mixed := KillcamExport.mix_sound([
		{"t": 0.0, "stream": tone, "db": 0.0, "pitch": 1.0},
		{"t": 0.2, "stream": tone, "db": 0.0, "pitch": 1.0, "at": Vector3(-5, 0, 0), "range": [4.0, 60.0], "ears": ears},
		{"t": 0.4, "stream": tone, "db": 0.0, "pitch": 1.0, "at": Vector3(-40, 0, 0), "range": [4.0, 60.0], "ears": ears},
		{"t": 0.6, "stream": tone, "db": 0.0, "pitch": 1.0, "at": Vector3(0, 0, -100), "range": [4.0, 60.0], "ears": ears},
	], 0.8)
	_expect(mixed.size() == int(0.8 * KillcamExport.RATE) * 4, "16-bit stereo, as long as the video")
	var own: Vector2 = loudness.call(mixed, 0.0, 0.1)
	var near: Vector2 = loudness.call(mixed, 0.2, 0.3)
	var far: Vector2 = loudness.call(mixed, 0.4, 0.5)
	var gone: Vector2 = loudness.call(mixed, 0.6, 0.7)
	_expect(own.x > 0.0 and absf(own.x - own.y) < own.x * 0.01, "your own sound sits in the middle")
	_expect(near.x > near.y * 2.0, "a sound on your left is louder on the left (%.0f / %.0f)" % [near.x, near.y])
	_expect(far.x + far.y < (near.x + near.y) * 0.3, "and quieter further away")
	_expect(gone.x + gone.y == 0.0, "out of earshot: nothing")


func _video() -> void:
	print("  saving a killcam as a video")
	var avi := AviWriter.new(64, 36, 30)
	for i in 5:
		avi.add_frame(Image.create(80 + i, 40, false, Image.FORMAT_RGBA8))   # any size and format
	var info := _read_avi(avi.to_bytes())
	_expect(info.riff == "RIFF" and info.kind == "AVI " and info.size_ok, "the file is a RIFF AVI with the right length")
	_expect(info.codec == "MJPG" and info.fps == 30 and info.w == 64 and info.h == 36, "Motion JPEG, 30 frames a second, the video's size (%s, %s, %sx%s)" % [info.codec, info.fps, info.w, info.h])
	_expect(info.total == 5 and (info.frames as Array).size() == 5 and (info.frames as Array).all(func(j): return j),
		"every frame is there, each a JPEG (%d)" % (info.frames as Array).size())
	_expect(info.index == 5 and info.index_ok, "the index lists every frame, so players can seek")
	var dir := ProjectSettings.globalize_path("user://killcam_test_videos")
	DirAccess.make_dir_recursive_absolute(dir)
	var export := KillcamExport.new()
	export.into = dir
	add_child(export)
	var result := []
	export.finished.connect(func(path: String, error: String): result.append_array([path, error]))
	var clip := _test_clip()
	clip.map = "testing_grounds"
	export.start(clip, "BEST KILL #1")
	for i in 600:
		if not result.is_empty():
			break
		await get_tree().process_frame
	_expect(result.size() == 2 and result[1] == "", "a killcam saves without trouble (%s)" % [result])
	var mp4 := KillcamExport.encoder_path() != ""   # (Windows: an MP4; elsewhere an AVI)
	if result.size() == 2 and FileAccess.file_exists(result[0]):
		var bytes := FileAccess.get_file_as_bytes(result[0])
		var saved := _read_mp4(bytes) if mp4 else _read_avi(bytes)
		var want := roundi((clip.end - clip.start + (KillcamView.SLOW_FROM + KillcamView.SLOW_UNTIL) * (1.0 / KillcamView.SLOW - 1.0) + KillcamExport.HOLD) * KillcamExport.FPS)
		_expect(absi(int(saved.total) - want) <= 3 and saved.w == 1920 and saved.h == 1080,
			"the video is the clip in slow motion round the kill, then a second's hold: %d frames of %dx%d (about %d of 1920x1080)" % [saved.total, saved.w, saved.h, want])
		if mp4:
			_expect(saved.codec == "avc1" and saved.fps == 60, "an H.264 MP4 at 60 frames a second (%s, %s fps)" % [saved.codec, saved.fps])
			_expect(saved.get("audio", "") == "mp4a", "with an AAC sound track (%s)" % saved.get("audio", "none"))
		_expect(String(result[0]).get_file().begins_with("killcam_Tester_on_Gizmo_") and String(result[0]).ends_with(".mp4" if mp4 else ".avi"),
			"named after the killer and victim (%s)" % String(result[0]).get_file())
		DirAccess.remove_absolute(result[0])
	DirAccess.remove_absolute(dir)
