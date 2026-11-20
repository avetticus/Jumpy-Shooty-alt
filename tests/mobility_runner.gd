extends Node
## The body of tests/mobility_test.gd (a separate file: it uses the game's autoloads).

var _ok := true


func run() -> void:
	var game = Game
	var net = Net
	Settings.mobility = "blink"   # an old saved pick of a tool that is gone (not saved: the test never calls save_settings)
	DevArgs.jetpack = false
	game.start_practice("testing_grounds")
	await _frames(30)
	var arena = net.arena
	_check(arena != null, "practice starts")
	var me: Player = arena.local_player
	_check(Mobility.IDS == [Mobility.GRAPPLE] and Mobility.valid("blink") == Mobility.GRAPPLE and Mobility.valid("portal") == Mobility.GRAPPLE
		and Mobility.valid("jetpack") == Mobility.GRAPPLE, "the grappling hook is the only tool; an old pick of one that is gone is the hook")
	_check(me.mobility == Mobility.GRAPPLE and net.player_mobility(net.my_id()) == Mobility.GRAPPLE, "you have the grappling hook, and the lobby has it on record")

	# --- No jetpack unless the host turns it on.
	_check(not LobbySettings.jetpack() and me.jetpack == null and not me.motor.has_jetpack, "by default nobody has the jetpack")
	var hold_frames := int(me.motor.tuning.space_hold_time * Engine.physics_ticks_per_second)
	var j := _open_spot(me, 6.0)
	_check(not j.is_empty(), "found an open stretch of floor")
	me.teleport(j[0], j[1])
	await _physics(20)
	var ground_y := me.global_position.y
	DevArgs.drives_keys = true   # read the keys even though the mouse is not captured
	Input.action_press("jump")
	var peak := ground_y
	for i in 84:
		await get_tree().physics_frame
		peak = maxf(peak, me.global_position.y)
	Input.action_release("jump")
	DevArgs.drives_keys = false
	_check(peak - ground_y < 2.3, "holding Space in mid-air without it is just a jump (%.2f m up)" % (peak - ground_y))
	await _physics(120)

	# --- Turned on (the lobby setting): everyone has it, on Space held in mid-air.
	DevArgs.jetpack = true
	game.start_practice("testing_grounds")
	await _frames(30)
	arena = net.arena
	me = arena.local_player
	_check(LobbySettings.jetpack() and me.jetpack != null and me.motor.has_jetpack, "with the lobby's jetpack on, you have it")
	j = _open_spot(me, 6.0)
	me.teleport(j[0], j[1])
	await _physics(20)
	ground_y = me.global_position.y
	DevArgs.drives_keys = true
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

	# --- Bots have it too while it is on; a bot asked for a tool that is gone gets the hook.
	var id: int = net.add_bot(BotDifficulty.EXPERT, "", "blink")
	await _frames(10)
	var bot: Player = arena.get_player(id)
	_check(bot != null and bot.mobility == Mobility.GRAPPLE and bot.jetpack != null, "a bot has the grappling hook, and the jetpack while it is on")
	net.remove_bot(id)
	await _frames(5)
	# --- A race never has it, even with the setting on: the courses are the grapple's.
	game.start_practice("rooftop_run", "race")
	await _frames(40)
	arena = net.arena
	_check(arena != null and arena.local_player != null and arena.local_player.mobility == Mobility.GRAPPLE,
		"a race has the grapple (picked: %s)" % net.player_loadout_mobility(net.my_id()))
	_check(arena != null and arena.local_player != null and arena.local_player.jetpack == null and not arena.local_player.motor.has_jetpack,
		"and no jetpack, even with the setting on")
	DevArgs.jetpack = false

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
