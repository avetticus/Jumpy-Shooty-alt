extends Node
## The body of tests/mobility_test.gd (a separate file: it uses the game's autoloads).

var _ok := true


func run() -> void:
	var game = Game
	var net = Net
	var match_state = Match
	Settings.mobility = Mobility.BLINK   # (not saved: the test never calls save_settings)
	game.start_practice("testing_grounds")
	await _frames(30)
	var arena = net.arena
	_check(arena != null, "practice starts")
	var me: Player = arena.local_player
	_check(me.mobility == Mobility.BLINK and me.blink != null, "you have the blink you picked")
	_check(net.player_mobility(net.my_id()) == Mobility.BLINK, "the lobby has it on record")

	# --- Blink in the open.
	var open := _open_spot(me, 16.0)
	_check(not open.is_empty(), "found an open stretch of floor to blink along")
	me.teleport(open[0], open[1])
	await _physics(20)
	var from := me.global_position
	me.input.mobility_dir = open[2]
	me.input.grapple_pressed = true
	await _physics(2)
	var went := Vector2(me.global_position.x - from.x, me.global_position.z - from.z).length()
	_check(went > Blink.RANGE - 1.5, "a blink goes about its range (%.1f m)" % went)
	_check(Blink.CHARGES == 1 and me.blink.charges == 0, "it uses its one charge (%d left)" % me.blink.charges)
	_check(Net.arena.get_node_or_null("BlinkTrail") != null, "a trail of sparks follows you to where you land")
	_check(me.velocity.dot(open[2]) >= Blink.BLINK_PUSH - 0.5, "you keep moving the way you blinked (%.1f m/s)" % me.velocity.dot(open[2]))
	me.input.mobility_dir = open[2]
	me.input.grapple_pressed = true
	await _physics(1)
	_check(me.blink.charges == Blink.CHARGES - 1, "no second blink straight away (a short gap)")
	await get_tree().create_timer(Blink.RECHARGE + 0.4).timeout
	_check(me.blink.charges == Blink.CHARGES, "the charge comes back")

	# --- Blink at a wall: stops short of it.
	var wall := _wall_spot(me)
	_check(not wall.is_empty(), "found a wall to blink at")
	if not wall.is_empty():
		me.teleport(wall[0], 0.0)
		await _physics(20)
		me.input.mobility_dir = wall[1]
		me.input.grapple_pressed = true
		await _physics(2)
		var to_wall: float = wall[2]
		var gone := Vector2(me.global_position.x - wall[0].x, me.global_position.z - wall[0].z).length()
		_check(gone < to_wall and gone > to_wall - 1.6, "a blink at a wall %.1f m away stops short of it (%.1f m)" % [to_wall, gone])
		var space := me.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(wall[0] + Vector3(0, 1, 0), me.global_position + Vector3(0, 1, 0), 1, [me.get_rid()])
		_check(space.intersect_ray(q).is_empty(), "...and on this side of it")

	# --- Picking: refused while alive, taken while dead.
	net.set_my_mobility(Mobility.GRAPPLE)
	await _frames(3)
	_check(net.player_loadout_mobility(net.my_id()) == Mobility.BLINK, "a pick while alive waits")
	match_state._host_damage(9001, net.my_id(), 500.0)
	await _frames(5)
	_check(not match_state.is_alive(net.my_id()), "you died")
	await _frames(5)
	_check(net.player_loadout_mobility(net.my_id()) == Mobility.GRAPPLE, "dead: the pick made while alive is taken (%s)" % net.player_loadout_mobility(net.my_id()))
	_check(me.mobility == Mobility.GRAPPLE and me.blink == null, "you now have the grappling hook")
	await get_tree().create_timer(Match.RESPAWN_DELAY + 0.5).timeout
	me = arena.local_player
	_check(match_state.is_alive(net.my_id()) and me.mobility == Mobility.GRAPPLE, "and come back with it")
	_check(Mobility.IDS == [Mobility.GRAPPLE, Mobility.BLINK] and Mobility.valid("portal") == Mobility.GRAPPLE and Mobility.valid("jetpack") == Mobility.GRAPPLE,
		"two tools to pick from; an old pick of a tool that is gone is the grappling hook")

	# --- The jetpack: everyone has it, on Space held in mid-air.
	_check(me.jetpack != null and me.motor.has_jetpack, "you have the jetpack as well as your mobility tool")
	var hold_frames := int(me.motor.tuning.space_hold_time * Engine.physics_ticks_per_second)
	var j := _open_spot(me, 6.0)
	me.teleport(j[0], j[1])
	await _physics(20)
	var ground_y := me.global_position.y
	DevArgs.drives_keys = true   # read the keys even though the mouse is not captured
	# A tap of Space: a plain jump, no fuel burnt.
	Input.action_press("jump")
	await _physics(12)
	Input.action_release("jump")
	var top := await _top_over(120)
	_check(top - ground_y > 0.8 and top - ground_y < 2.3, "a tap of Space is a plain jump (%.2f m up, the legs tucked)" % (top - ground_y))
	_check(me.jetpack.fuel >= 0.999, "...and burns no fuel (%.2f)" % me.jetpack.fuel)
	# Held through the jump but let go before the hold time: still a plain jump.
	await _physics(30)
	Input.action_press("jump")
	await _physics(hold_frames - 6)
	Input.action_release("jump")
	top = await _top_over(120)
	_check(me.jetpack.fuel >= 0.999 and top - ground_y < 2.3,
		"held through the jump for under %.2f s: no fuel burnt (%.2f m up)" % [me.motor.tuning.space_hold_time, top - ground_y])
	# Held on: the jetpack lights and carries you well above a jump.
	await _physics(30)
	Input.action_press("jump")
	var lit := false
	top = ground_y
	for i in 84:
		await get_tree().physics_frame
		top = maxf(top, me.global_position.y)
		if i < hold_frames - 4:
			lit = lit or me.jetpack.on
	_check(not lit, "the jetpack waits out the hold time after the jump")
	_check(me.jetpack.on, "then, still holding Space in mid-air, it fires")
	Input.action_release("jump")
	await _physics(2)
	_check(top - ground_y > 3.0, "and lifts you well above a jump (%.1f m up)" % (top - ground_y))
	_check(me.jetpack.fuel < 0.9, "burning fuel (%.2f left)" % me.jetpack.fuel)
	_check(RobotAnimInput.jetpack_of(me._my_anim_flags()) == false, "others are told when it stops")
	var low := me.jetpack.fuel
	await get_tree().create_timer(1.5).timeout
	_check(me.jetpack.fuel > low, "the fuel refills when you let go (%.2f)" % me.jetpack.fuel)
	# Falling: a fresh press in mid-air (a flip), held on, flies it too.
	await get_tree().create_timer(1.0).timeout
	me.teleport(j[0] + Vector3(0, 12.0, 0), j[1])
	await _physics(4)
	Input.action_press("jump")
	await _physics(hold_frames + 36)
	var rising := me.velocity.y
	var fell_jet := me.jetpack.on
	Input.action_release("jump")
	DevArgs.drives_keys = false
	_check(fell_jet and rising > 0.0, "falling, hold Space: the jetpack catches you (rising at %.1f m/s)" % rising)
	await _physics(240)

	# --- Bots take a tool (and have the jetpack), and a race always has the grapple (and no jetpack).
	var id: int = net.add_bot(BotDifficulty.EXPERT, "", Mobility.GRAPPLE)
	await _frames(10)
	var bot: Player = arena.get_player(id)
	_check(bot != null and bot.mobility == Mobility.GRAPPLE and bot.jetpack != null, "a bot can carry the grappling hook, and has the jetpack")
	var id2: int = net.add_bot(BotDifficulty.EXPERT, "", Mobility.BLINK)
	await _frames(10)
	var bot2: Player = arena.get_player(id2)
	_check(bot2 != null and bot2.mobility == Mobility.BLINK and bot2.blink != null and bot2.jetpack != null, "a bot can carry blink, and has the jetpack")
	var id3: int = net.add_bot(BotDifficulty.EXPERT, "", "portal")
	await _frames(10)
	var bot3: Player = arena.get_player(id3)
	_check(bot3 != null and Mobility.has(bot3.mobility), "a bot asked for a tool that is gone gets one there is (%s)" % (bot3.mobility if bot3 else "none"))
	net.remove_bot(id)
	net.remove_bot(id2)
	net.remove_bot(id3)
	await _frames(5)
	game.start_practice("rooftop_run", "race")
	await _frames(40)
	arena = net.arena
	_check(arena != null and arena.local_player != null and arena.local_player.mobility == Mobility.GRAPPLE,
		"a race always has the grapple (picked: %s)" % net.player_loadout_mobility(net.my_id()))
	_check(arena != null and arena.local_player != null and arena.local_player.jetpack == null and not arena.local_player.motor.has_jetpack,
		"and no jetpack: the courses are the grapple's")

	print("PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)


## The highest the local player's feet get over the next `n` physics steps.
func _top_over(n: int) -> float:
	var me: Player = Net.arena.local_player
	var top := me.global_position.y
	for i in n:
		await get_tree().physics_frame
		top = maxf(top, me.global_position.y)
	return top


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


## A wall 5 to 9 m in front of a floor spot: [feet, direction, distance].
func _wall_spot(me: Player) -> Array:
	var space := me.get_world_3d().direct_space_state
	for s in Net.arena.layout.spawns:
		var base: Vector3 = s[0]
		var down := PhysicsRayQueryParameters3D.create(base + Vector3(0, 1, 0), base + Vector3(0, -5, 0), 1)
		var floor_hit := space.intersect_ray(down)
		if floor_hit.is_empty():
			continue
		var feet: Vector3 = floor_hit.position
		for k in 16:
			var dir := Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 16.0)
			var hits := []
			for h in [0.3, 1.0, 1.7, 2.6]:
				var q := PhysicsRayQueryParameters3D.create(feet + Vector3(0, h, 0), feet + Vector3(0, h, 0) + dir * 9.0, 1)
				hits.append(space.intersect_ray(q))
			var first: Dictionary = hits[1]
			if first.is_empty() or absf((first.normal as Vector3).y) > 0.1 or (first.normal as Vector3).dot(dir) > -0.9:
				continue
			var dist := Vector2(first.position.x - feet.x, first.position.z - feet.z).length()
			if dist < 5.0:
				continue
			var flat := true
			for hh in hits:
				if hh.is_empty() or absf(Vector2(hh.position.x - feet.x, hh.position.z - feet.z).length() - dist) > 0.3:
					flat = false
			if flat:
				return [feet, dir, dist]
	return []


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
