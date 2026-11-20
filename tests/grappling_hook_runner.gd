extends Node
## The body of tests/grappling_hook_test.gd (a separate file: it uses the game's autoloads).

const STEP := 1.0 / 120.0   # the game's physics step

var _ok := true
var _me: Player
var _log: Array = []   # one shot, every physics step: [clock, look, packed, chest, hand]
var _shot: HookLine    # that shot's record, once it is over


func run() -> void:
	Settings.mobility = Mobility.GRAPPLE   # (not saved: the test never calls save_settings)
	Game.start_practice("testing_grounds")
	await _frames(30)
	var arena = Net.arena
	_me = arena.local_player
	var me := _me
	_check(Mobility.name_of(Mobility.GRAPPLE) == "Grappling Hook" and Mobility.default_id() == Mobility.GRAPPLE, "the Grappling Hook is a mobility tool, and the default")
	_check(Mobility.IDS == [Mobility.GRAPPLE, Mobility.BLINK], "there is only one grappling hook")
	_check(not Mobility.has("grapple2") and Mobility.valid("grapple2") == Mobility.GRAPPLE, "a saved choice of the old Grappling Hook 2 id is the Grappling Hook")
	_check(LobbySettings.normalized_mobility(["grapple2"]) == [Mobility.GRAPPLE], "a lobby's saved list of allowed tools keeps it, as the Grappling Hook")
	_check(LobbySettings.normalized_mobility(["grapple", "grapple2", "blink"]) == [], "...and a list of every tool is still every tool")
	_check(me.mobility == Mobility.GRAPPLE, "you have the grappling hook you picked")
	_check(Net.player_mobility(Net.my_id()) == Mobility.GRAPPLE, "the lobby has it on record")
	var g := me.motor.grapple
	var range_m: float = me.motor.tuning.grapple_range

	# --- A shot at a wall: flight, bite, the slack coming in, then the pull.
	var spot := _wall_spot(me, 14.0, 34.0)
	_check(not spot.is_empty(), "found a wall 14 to 34 m away to shoot at")
	if spot.is_empty():
		_finish()
		return
	var dist: float = spot[2]
	me.teleport(spot[0], 0.0)
	await _physics(30)
	_aim(me, spot[1])
	var start := me.global_position
	_hold(true)
	for i in 4:   # (the press is read on the next step)
		await _physics(1)
		_record(me, g)
		if g.flying:
			break
	var t0 := g.line.t_launch
	_check(g.flying and not g.attached and g.busy(), "firing sends the hook out: nothing is hooked at once")
	_check(me.velocity.length() < 0.5 and me.motor.state != MovementController.State.GRAPPLE, "nothing pulls while it flies (%.2f m/s)" % me.velocity.length())
	_check(me._hook_look.size() == 5 and int(me._hook_look[0]) == HookLine.FLYING or me._hook_look.is_empty(), "the hook is drawn in flight")
	var eye := me.eye_position()
	var bite_at := -1.0
	var taut_at := -1.0
	var slack_seen := 0.0
	var longest_spare := 0.0
	var pts := PackedVector3Array()
	pts.resize(HookRope.SEGMENTS + 1)
	var mid_flight := Vector3.INF
	for i in 200:
		await _physics(1)
		_record(me, g)
		var look := g.line.look(g.clock, me.rope_origin(), g.rope_origin(me))
		if g.flying:
			if i == 12:
				mid_flight = g.rope_end()
			_check(me.velocity.length() < 0.5, "still nothing pulls in flight") if i == 5 else null
		if look.size() == 5 and float(look[2]) > 0.0:
			HookRope.curve(me.rope_origin(), look[1], look[2], look[3], look[4], pts)
			longest_spare = maxf(longest_spare, HookRope.length_of(pts) - me.rope_origin().distance_to(look[1]))
		if g.biting and bite_at < 0.0:
			bite_at = g.line.t_stop - t0
			slack_seen = float(look[2])
			_check(not g.attached and int(look[0]) == HookLine.BITING, "the hook bites, and the rope is still slack")
			_check(me.velocity.length() < 0.5, "...so nothing pulls yet (%.2f m/s)" % me.velocity.length())
		if g.attached:
			if bite_at < 0.0:
				bite_at = g.line.t_stop - t0
			taut_at = g.clock - t0
			break
	_check(mid_flight != Vector3.INF and absf((mid_flight - eye).normalized().dot(spot[1]) - 1.0) < 0.001,
		"the hook flies straight along the aim")
	_check(bite_at > 0.0, "the hook reaches the wall")
	var flight := (dist - 0.2) / HookLine.SPEED
	_check(absf(bite_at - flight) < 0.03, "a wall %.1f m away takes the hook %.2f s to reach (%.3f s)" % [dist, flight, bite_at])
	_check(slack_seen > 0.5, "there is slack in the rope when it bites (%.2f m)" % slack_seen)
	_check(longest_spare > 0.5, "the rope drawn is longer than the straight line while it is slack (%.2f m more)" % longest_spare)
	_check(taut_at > bite_at + 0.03 and taut_at < bite_at + 0.3, "the winch takes the slack in, then the rope pulls tight (%.3f s after the bite)" % (taut_at - bite_at))
	var toward := (g.anchor - g.rope_origin(me)).normalized()
	await _physics(1)
	_record(me, g)
	_check(me.velocity.dot(toward) > me.motor.tuning.grapple_yank, "pulling tight yanks you toward the hook (%.1f m/s)" % me.velocity.dot(toward))
	_check(g.anchor.distance_to(eye + spot[1] * dist) < 1.0, "it is hooked where you aimed (%.2f m off)" % g.anchor.distance_to(eye + spot[1] * dist))
	var tight := g.line.look(g.clock, me.rope_origin(), g.rope_origin(me))
	_check(int(tight[0]) == HookLine.TAUT and float(tight[2]) == 0.0 and float(tight[4]) >= 0.0, "the rope is drawn tight, and twanging")
	for i in 40:
		await _physics(1)
		_record(me, g)
	HookRope.curve(me.rope_origin(), g.anchor, 0.0, 1.0, 0.6, pts)
	_check(HookRope.length_of(pts) - me.rope_origin().distance_to(g.anchor) < 0.01, "once the twang dies away the rope is a straight line")
	_check(me.motor.state == MovementController.State.GRAPPLE and me.global_position.distance_to(start) > 1.5,
		"then it pulls you in (%.1f m so far)" % me.global_position.distance_to(start))
	var frame := me.shown_state()
	_check(frame.size() > 12 and frame[12] != null and (frame[12] as Array).size() == 4 and bool(frame[6]),
		"the killcam's frame holds the rope as it was drawn")
	_hold(false)
	await _physics(2)
	_record(me, g)
	_check(not g.attached and g.cooldown_left > 0.0, "letting go lets go, and the cooldown starts")
	var back := g.line.look(g.clock, me.rope_origin(), g.rope_origin(me))
	_check(back.size() == 5 and int(back[0]) == HookLine.RETRACT and g.returning, "the hook comes back")
	_check(g.rope_out() and bool(me.shown_state()[6]), "...with the rope still on your arm, which stays out for it")
	_check(g.line.back_time >= HookLine.BACK_MIN and g.line.back_time <= HookLine.BACK_MAX, "...in a time that fits how far it has to come (%.2f s)" % g.line.back_time)
	for i in int(g.line.back_time / STEP) + 3:
		await _physics(1)
		_record(me, g)
	_check(g.line.look(g.clock, me.rope_origin(), g.rope_origin(me)).is_empty() and not g.returning and not g.rope_out(),
		"...and is back at the wrist %.2f s later" % g.line.back_time)
	await _frames(3)
	_check(me.shown_state()[12] == null and not bool(me.shown_state()[6]), "the killcam's frame has no rope once it is gone")

	_shot = g.line
	_check_network([g.line], "")
	_check_replay()

	# --- A miss: at the sky.
	await get_tree().create_timer(me.motor.tuning.grapple_cooldown + 0.1).timeout
	me.teleport(spot[0], 0.0)
	await _physics(20)
	_aim(me, Vector3(0.05, 1.0, 0.05).normalized())
	var clear := me.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(me.eye_position(), me.eye_position() + Vector3(0.05, 1.0, 0.05).normalized() * (range_m + 2.0), 1)).is_empty()
	_hold(true)
	await _physics(1)
	var fired := g.clock
	var ever := false
	var out_for := 0.0
	for i in 200:
		await _physics(1)
		ever = ever or g.attached or g.biting
		if not g.flying:
			out_for = g.clock - fired
			break
	_hold(false)
	if clear:
		_check(not ever and absf(out_for - range_m / HookLine.SPEED) < 0.03, "shot at the sky it flies its %d m of rope, catches nothing (%.2f s)" % [int(range_m), out_for])
		_check(g.cooldown_left > 0.0 and not g.ready_to_fire(), "...and the cooldown starts")
	await _physics(2)

	# --- Called back in flight.
	await get_tree().create_timer(me.motor.tuning.grapple_cooldown + 0.1).timeout
	me.teleport(spot[0], 0.0)
	await _physics(20)
	_aim(me, spot[1])
	_hold(true)
	await _physics(4)
	_check(g.flying, "fired again")
	_hold(false)
	await _physics(2)
	_check(not g.flying and not g.biting and not g.attached, "letting go while it flies calls the hook back")
	await _physics(int(dist / HookLine.SPEED / STEP) + 30)
	_check(not g.attached and me.global_position.distance_to(spot[0]) < 0.5, "...and it never catches")

	# --- The way back: the hook catches the first surface in its way, while you hold on.
	await get_tree().create_timer(me.motor.tuning.grapple_cooldown + 0.1).timeout
	var sky := _sky_spot(me, range_m + 8.0)
	_check(sky != Vector3.INF, "found a floor with open sky over it")
	if sky != Vector3.INF:
		var up := Vector3(0.02, 1.0, 0.02).normalized()
		var slab_at := sky + Vector3(0, 15.0, 0)
		# Let go of the button: the hook comes back through whatever has got in its way.
		me.teleport(sky, 0.0)
		await _physics(20)
		_aim(me, up)
		_hold(true)
		for i in 100:
			await _physics(1)
			if g.flying and g.line.travel(g.clock) > 30.0:
				break
		_hold(false)
		await _physics(2)
		_check(g.returning and not g.flying, "let go of in flight, the hook comes back")
		var slab := _slab(slab_at)
		var caught_any := false
		for i in 80:
			await _physics(1)
			caught_any = caught_any or g.biting or g.attached
			if not g.returning:
				break
		_check(not caught_any and not g.returning, "with the button up it catches nothing on its way back")
		slab.free()
		await _physics(2)
		# Press again as it comes back, and hold: it catches.
		await get_tree().create_timer(me.motor.tuning.grapple_cooldown + 0.1).timeout
		me.teleport(sky, 0.0)
		await _physics(20)
		_aim(me, up)
		_hold(true)
		for i in 100:
			await _physics(1)
			if g.flying and g.line.travel(g.clock) > 30.0:
				break
		_hold(false)
		await _physics(2)
		slab = _slab(slab_at)
		_hold(true)
		caught_any = false
		for i in 80:
			await _physics(1)
			caught_any = caught_any or g.biting or g.attached
			if g.attached or not (g.returning or g.biting):
				break
		_check(caught_any and g.attached and absf(g.anchor.y - (slab_at.y + 0.25)) < 0.05,
			"pressed again and held as it comes back, it catches the surface in its way")
		g.held = true
		g.release()   # (as a jump off the rope does: the button is still down)
		_check(g.returning and not g._snag, "a jump off the rope is not holding on: the hook just comes back")
		_hold(false)
		await _physics(int(HookLine.BACK_MAX / STEP) + 4)
		slab.free()
		await _physics(2)
		# A miss with the button held: the same, and every copy sees it the same.
		await get_tree().create_timer(me.motor.tuning.grapple_cooldown + 0.1).timeout
		me.teleport(sky, 0.0)
		await _physics(20)
		_aim(me, up)
		_log.clear()
		_hold(true)
		for i in 200:
			await _physics(1)
			_record(me, g)
			if g.returning:
				break
		var missed := g.line
		_check(g.returning and not g.attached and not g.biting, "a miss: the hook starts back")
		slab = _slab(slab_at)
		var bit := false
		for i in 120:
			await _physics(1)
			_record(me, g)
			bit = bit or g.biting
			if g.attached or not (g.returning or g.biting):
				break
		_check(bit and g.attached, "held after a miss, the hook catches the first surface on its way back, slack first")
		_check(absf(g.anchor.y - (slab_at.y + 0.25)) < 0.05 and Vector2(g.anchor.x - sky.x, g.anchor.z - sky.z).length() < 1.5,
			"...where its way back met it (%.2f m over you)" % (g.anchor.y - sky.y))
		_check(g.line != missed and g.line.back and g.line.seq != missed.seq and is_equal_approx(g.line.t_launch, missed.t_release),
			"...and that is a new shot on the record, begun as the hook set off back")
		await _physics(1)
		_record(me, g)
		_check(me.velocity.y > me.motor.tuning.grapple_yank * 0.8, "then the rope pulls tight and yanks you up to it (%.1f m/s)" % me.velocity.y)
		# In first person the rope leaves the arm where the arm is drawn this frame, moving
		# and turning: not where it was a frame ago. (The camera has not moved since the
		# frame was drawn, so the arm's wrist now is the wrist that was drawn.)
		me.input.yaw += 0.4
		await _frames(2)
		var drawn: Vector3 = me._hook_rope._points[0]
		_check(me._first_person() and me.velocity.length() > 5.0 and drawn.distance_to(me.view.marker("grapple")) < 0.002,
			"at %.0f m/s and turning, the rope starts on your first-person arm's wrist as drawn (%.1f cm off)"
			% [me.velocity.length(), drawn.distance_to(me.view.marker("grapple")) * 100.0])
		for i in 12:
			await _physics(1)
			_record(me, g)
		_hold(false)
		for i in int(HookLine.BACK_MAX / STEP) + 6:
			await _physics(1)
			_record(me, g)
		_check(not g.returning and not g.rope_out(), "let go, it comes back and is gone")
		_check_network([missed, g.line], "a catch on the way back, ")
		slab.free()
		await _physics(2)

	# --- Hooking a player: the hook flies to them, bites, pulls tight, and they are reeled in.
	await get_tree().create_timer(me.motor.tuning.grapple_cooldown + 0.1).timeout
	var open := _open_spot(me, 16.0)
	_check(not open.is_empty(), "found an open stretch of floor")
	if not open.is_empty():
		Cheats.freeze_bots = true
		var id: int = Net.add_bot(BotDifficulty.EXPERT, "", "grapple2")
		await _frames(10)
		var bot: Player = arena.get_player(id)
		_check(bot != null and bot.mobility == Mobility.GRAPPLE, "a bot asked for the old Grappling Hook 2 id carries the grappling hook")
		var feet: Vector3 = open[0]
		var along: Vector3 = open[2]
		me.teleport(feet, open[1])
		bot.teleport(feet + along * 14.0, 0.0)
		await _physics(30)
		_aim(me, (Grapple.target_point(bot) - me.eye_position()).normalized())
		_hold(true)
		var caught := false
		var was_biting := false
		for i in 120:
			await _physics(1)
			was_biting = was_biting or (g.biting and g.target == bot)
			if g.hooked_player():
				caught = true
				break
		_check(was_biting, "the hook bites a player in its way")
		_check(caught and g.target == bot, "then the rope pulls tight on them")
		_check(g.line.target_id == id, "the shot's record says who it is hooked on (so every copy ends the rope on them)")
		await _physics(20)
		_check(bot.velocity.dot(-along) > 1.0 or bot.global_position.distance_to(feet + along * 14.0) > 0.3, "and they are reeled in toward you")
		_hold(false)
		await _physics(3)
		Net.remove_bot(id)
		Cheats.freeze_bots = false
		await _frames(5)

	# --- A race always has the grappling hook: the same one.
	Game.start_practice("rooftop_run", "race")
	await _frames(40)
	arena = Net.arena
	_check(arena != null and arena.local_player != null and arena.local_player.mobility == Mobility.GRAPPLE, "a race always has the grappling hook")
	_finish()


## The shot recorded above, rebuilt the way another copy of the game does it: from the
## snapshots' records, a little late, with packets lost. At every moment of the shot
## it must put the hook and the rope where the player's own game had them.
## shots: the player's own records of what the log holds, in order (one, or a miss
## and the catch on its way back).
func _check_network(shots: Array, what: String) -> void:
	var shift := 1234.5   # the two clocks are not the same clock
	for plan in [["every snapshot (40 a second), 70 ms late", 3, 0.07, 0.0], ["a third of the packets lost, 110 ms late", 3, 0.11, 0.34],
			["two thirds lost, 200 ms late", 3, 0.2, 0.67]]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var theirs: HookLine = null   # (as Player keeps them: the latest shot, and the one before)
		var before: HookLine = null
		var next := 0
		var worst := 0.0
		var worst_slack := 0.0
		var stages_off := 0
		var compared := 0
		var pts_a := PackedVector3Array()
		var pts_b := PackedVector3Array()
		pts_a.resize(HookRope.SEGMENTS + 1)
		pts_b.resize(HookRope.SEGMENTS + 1)
		var worst_rope := 0.0
		for k in _log.size():
			# A moment between two steps (the other copy draws at its own frames, not on our steps).
			var now: float = float(_log[k][0]) + STEP * 0.37
			# Everything sent up to (now + how late we draw) has arrived.
			while next < _log.size() and float(_log[next][0]) <= now + float(plan[2]):
				if next % int(plan[1]) == 0 and rng.randf() >= float(plan[3]):
					var packed: PackedFloat32Array = _log[next][2]
					if not packed.is_empty():
						if theirs == null or HookLine.packed_seq(packed, 0) != theirs.seq:
							before = theirs
							theirs = HookLine.new()
						theirs.absorb(float(_log[next][0]) + shift, packed, 0, before)
				next += 1
			var own: HookLine = shots[0]   # (the player's own record of the shot on at that moment)
			for one in shots:
				if now >= (one as HookLine).t_launch:
					own = one
			var mine: Array = own.look(now, _log[k][4], _log[k][3])
			var showing := theirs if theirs != null and now + shift >= theirs.t_launch else before
			var seen: Array = showing.look(now + shift, _log[k][4], _log[k][3]) if showing != null else []
			if mine.is_empty() and seen.is_empty():
				continue
			compared += 1
			if mine.is_empty() != seen.is_empty() or int(mine[0]) != int(seen[0]):
				stages_off += 1
				continue
			worst = maxf(worst, (mine[1] as Vector3).distance_to(seen[1]))
			worst_slack = maxf(worst_slack, absf(float(mine[2]) - float(seen[2])))
			HookRope.curve(_log[k][4], mine[1], mine[2], mine[3], mine[4], pts_a)
			HookRope.curve(_log[k][4], seen[1], seen[2], seen[3], seen[4], pts_b)
			for i in pts_a.size():
				worst_rope = maxf(worst_rope, pts_a[i].distance_to(pts_b[i]))
		_check(compared > 60 and stages_off == 0 and worst < 0.02 and worst_slack < 0.02 and worst_rope < 0.03,
			"%sanother copy, %s: the hook is never more than %.1f cm off, the slack %.1f cm, any point of the rope %.1f cm (%d moments, %d in another stage)"
			% [what, plan[0], worst * 100.0, worst_slack * 100.0, worst_rope * 100.0, compared, stages_off])


## The killcam: frames of the rope as drawn, 30 a second, blended back to any moment
## between them, give the rope that was drawn at that moment.
func _check_replay() -> void:
	var track := KillClip.Track.new()
	var every := 4   # 120 steps a second: every 4th is 30 frames a second
	for k in range(0, _log.size(), every):
		track.push(float(_log[k][0]), _frame_of(_log[k]))
	var worst := 0.0
	var worst_back := 0.0
	var worst_slack := 0.0
	var worst_twang := 0.0
	var compared := 0
	for k in _log.size():
		var mine: Array = _log[k][1]
		var f := track.sample(float(_log[k][0]))
		if mine.is_empty() or f[12] == null:
			continue
		var k0 := k - k % every
		if k0 + every >= _log.size() or (_log[k0][1] as Array).is_empty() or (_log[k0 + every][1] as Array).is_empty() \
				or int(_log[k0][1][0]) != int(_log[k0 + every][1][0]):
			continue   # (the frames either side are in different stages: the blend crosses a bite or a release)
		compared += 1
		var r: Array = f[12]
		if int(mine[0]) == HookLine.RETRACT:   # (the whip back speeds up: its path curves between two frames)
			worst_back = maxf(worst_back, (mine[1] as Vector3).distance_to(r[0]))
			continue
		worst = maxf(worst, (mine[1] as Vector3).distance_to(r[0]))
		worst_slack = maxf(worst_slack, absf(float(mine[2]) - float(r[1])))
		if float(mine[4]) >= 0.0:
			worst_twang = maxf(worst_twang, absf(float(mine[4]) - float(r[3])))
	_check(compared > 40 and worst < 0.05 and worst_slack < 0.05 and worst_twang < 0.002,
		"a replay puts the hook within %.1f cm, the slack within %.1f cm and the twang within %.1f ms of what was drawn (%d moments)"
		% [worst * 100.0, worst_slack * 100.0, worst_twang * 1000.0, compared])
	_check(worst_back < 0.3, "...and within %.0f cm as it whips back" % (worst_back * 100.0))


## A killcam frame with only what the blend looks at filled in.
func _frame_of(entry: Array) -> Array:
	var look: Array = entry[1]
	return [entry[3], Vector3.ZERO, 0.0, 0.0, 0, 0, not look.is_empty(), look[1] if not look.is_empty() else Vector3.ZERO,
		true, true, 1.6, "none", look.slice(1) if not look.is_empty() else null]


func _record(me: Player, g: Grapple) -> void:
	var packed := g.line.pack(g.clock) if g.line.sending(g.clock) else PackedFloat32Array()
	_log.append([g.clock, g.line.look(g.clock, me.rope_origin(), g.rope_origin(me)), packed, g.rope_origin(me), me.rope_origin()])


func _aim(me: Player, dir: Vector3) -> void:
	me.input.yaw = atan2(-dir.x, -dir.z)
	me.input.pitch = asin(clampf(dir.y, -1.0, 1.0))


## Presses (or lets go of) the mobility button, read even though the mouse is not captured.
func _hold(down: bool) -> void:
	DevArgs.drives_keys = down
	if down:
		Input.action_press("grapple")
	else:
		Input.action_release("grapple")
		_me.input.grapple = false


## A wall `from` to `to` metres in front of a floor spot, square to the shot at eye
## height and above: [feet, direction, distance from the eyes].
func _wall_spot(me: Player, from: float, to: float) -> Array:
	var space := me.get_world_3d().direct_space_state
	for s in Net.arena.layout.spawns:
		var base: Vector3 = s[0]
		var down := PhysicsRayQueryParameters3D.create(base + Vector3(0, 1, 0), base + Vector3(0, -5, 0), 1)
		var floor_hit := space.intersect_ray(down)
		if floor_hit.is_empty():
			continue
		var feet: Vector3 = floor_hit.position
		var eye := feet + Vector3(0, MovementTuning.EYE_HEIGHT, 0)
		for k in 32:
			var flat := Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 32.0)
			var dir := (flat + Vector3(0, 0.25, 0)).normalized()
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + dir * to, 1))
			if hit.is_empty() or eye.distance_to(hit.position) < from or (hit.normal as Vector3).dot(flat) > -0.9:
				continue
			if hit.collider is AnimatableBody3D:
				continue
			return [feet, dir, eye.distance_to(hit.position)]
	return []


## A spot on the floor with nothing over it for `height` metres, nor round it (INF: none).
func _sky_spot(me: Player, height: float) -> Vector3:
	var space := me.get_world_3d().direct_space_state
	for s in Net.arena.layout.spawns:
		var base: Vector3 = s[0]
		var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(base + Vector3(0, 1, 0), base + Vector3(0, -5, 0), 1))
		if floor_hit.is_empty():
			continue
		var feet: Vector3 = floor_hit.position
		var clear := true
		for off in [Vector3.ZERO, Vector3(3, 0, 0), Vector3(-3, 0, 0), Vector3(0, 0, 3), Vector3(0, 0, -3)]:
			var from: Vector3 = feet + off + Vector3(0, 0.5, 0)
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, height, 0), 1)).is_empty():
				clear = false
		if clear:
			return feet
	return Vector3.INF


## A slab of level, 6 m square and half a metre thick, in mid-air (the test puts it in
## the way of a hook coming back).
func _slab(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 0.5, 6.0)
	shape.shape = box
	body.add_child(shape)
	body.collision_layer = 1
	body.collision_mask = 0
	Net.arena.add_child(body)
	body.global_position = at
	return body


## A spot on the floor with `length` metres of clear, flat floor ahead: [feet, yaw, direction].
func _open_spot(me: Player, length: float) -> Array:
	var space := me.get_world_3d().direct_space_state
	for s in Net.arena.layout.spawns:
		var base: Vector3 = s[0]
		var down := PhysicsRayQueryParameters3D.create(base + Vector3(0, 1, 0), base + Vector3(0, -5, 0), 1)
		var floor_hit := space.intersect_ray(down)
		if floor_hit.is_empty():
			continue
		var feet: Vector3 = floor_hit.position
		for k in 16:
			var yaw := k * TAU / 16.0
			var dir := Vector3.FORWARD.rotated(Vector3.UP, yaw)
			var ok := true
			for h in [0.3, 1.0, 1.7]:
				var q := PhysicsRayQueryParameters3D.create(feet + Vector3(0, h, 0), feet + Vector3(0, h, 0) + dir * (length + 1.0), 1)
				if not space.intersect_ray(q).is_empty():
					ok = false
			for step in [4.0, 8.0, length]:
				var p: Vector3 = feet + dir * step
				var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.5, 0), p + Vector3(0, -0.5, 0), 1)
				var hit := space.intersect_ray(q)
				if hit.is_empty() or (hit.normal as Vector3).y < 0.95:
					ok = false
			if ok:
				return [feet, yaw, dir]
	return []


func _finish() -> void:
	print("PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		_ok = false
