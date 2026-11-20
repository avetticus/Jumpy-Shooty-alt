extends Node
## The body of tests/debug_test.gd. A separate file because it uses the game's
## autoloads (Net, Match, Game), which only exist once the test's SceneTree is running.

var _ok := true
var _hits: Array = []


func run() -> void:
	var game = Game
	var net = Net
	var match_state = Match
	game.start_practice("testing_grounds")
	await _frames(30)
	var arena = net.arena
	_check(arena != null, "practice starts")
	_check(arena.dummies.size() >= 3, "Testing Grounds has target dummies (%d)" % arena.dummies.size())
	match_state.player_hit.connect(func(s, t, d, h): _hits.append([s, t, d, h]))
	var me: Player = arena.local_player
	var dummy: TargetDummy = arena.dummies[1]   # 10 m, nothing in front of it
	var pistol := WeaponData.by_id("pistol")

	# Body shot from the firing line.
	var eye := Vector3(dummy.global_position.x - 8.0, 1.6, dummy.global_position.z)
	me.teleport(eye - Vector3(0, 1.6, 0), -PI / 2)
	await _frames(3)
	eye = me.eye_position()
	_shoot(match_state, me, eye, dummy.global_position + Vector3(0, 1.0, 0))
	await _frames(3)
	_check(_hits.size() == 1 and _hits[0][1] == match_state.dummy_id(1) and not _hits[0][3],
		"a body shot on a dummy is a hit, not a headshot: %s" % str(_hits))
	_check(is_equal_approx(dummy.health, 100.0 - pistol.damage), "the dummy loses a pistol shot's damage (%.1f)" % dummy.health)

	# Headshot.
	await _wait_fire(pistol)
	_shoot(match_state, me, eye, dummy.global_position + Vector3(0, 1.65, 0))
	await _frames(3)
	_check(_hits.size() == 2 and _hits[1][3], "a shot at the head is a headshot")
	_check(is_equal_approx(_hits[1][2], pistol.damage * pistol.headshot_multiplier), "headshot damage is multiplied")

	# Keep shooting until it goes down, then it gets back up.
	for i in 6:
		if dummy.is_down():
			break
		await _wait_fire(pistol)
		_shoot(match_state, me, eye, dummy.global_position + Vector3(0, 1.0, 0))
		await _frames(2)
	_check(dummy.is_down(), "enough damage knocks the dummy down")
	var before := _hits.size()
	await _wait_fire(pistol)
	_shoot(match_state, me, eye, dummy.global_position + Vector3(0, 1.0, 0))
	await _frames(3)
	_check(_hits.size() == before, "a dummy that is down cannot be hit")
	await get_tree().create_timer(TargetDummy.DOWN_TIME + 0.3).timeout
	_check(not dummy.is_down() and dummy.health == 100.0, "it gets back up with full health")

	# God mode: a bot's shot does not hurt you.
	Cheats.god = true
	match_state._host_damage(9001, net.my_id(), 40.0)
	_check(match_state.health[net.my_id()] == 100.0, "god mode: no damage")
	Cheats.god = false
	match_state._host_damage(9001, net.my_id(), 40.0)
	_check(match_state.health[net.my_id()] == 60.0, "god mode off: damage again")
	match_state.host_heal(net.my_id())
	_check(match_state.health[net.my_id()] == 100.0, "full health button")

	# Infinite ammo.
	Cheats.infinite_ammo = true
	me.weapon.ammo = 1
	await _frames(3)
	_check(me.weapon.ammo == me.weapon.data.magazine, "infinite ammo keeps the magazine full")
	Cheats.infinite_ammo = false

	# No cooldowns.
	Cheats.no_cooldowns = true
	me.motor.grapple.cooldown_left = 0.5
	await _frames(3)
	_check(me.motor.grapple.cooldown_left == 0.0 and me.motor.dive_readiness() == 1.0, "no cooldowns: the grapple and dive are ready")
	Cheats.no_cooldowns = false

	# Noclip: hold jump to rise, through the air, and you never "fall out" of the map.
	DevArgs.drives_keys = true
	Cheats.noclip = true
	var start_y := me.global_position.y
	Input.action_press("jump")
	await get_tree().create_timer(0.5).timeout
	Input.action_release("jump")
	_check(me.global_position.y > start_y + 3.0, "noclip: Space flies up (%.1f m)" % (me.global_position.y - start_y))
	await get_tree().create_timer(0.5).timeout
	_check(me.global_position.y > start_y + 3.0, "noclip: no gravity")
	Cheats.noclip = false
	DevArgs.drives_keys = false
	await get_tree().create_timer(1.5).timeout
	_check(me.is_on_floor(), "noclip off: you fall back down")

	# Bots.
	var menu: DebugMenu = arena.debug_menu
	menu._add_bot()
	menu._add_bot()
	await _frames(10)
	_check(menu._bots().size() == 2 and arena.get_player(menu._bots()[0]) != null, "two bots added mid-match")
	_check(arena.has_node("Navigation"), "the navigation mesh is baked for them")
	menu._remove_bots(1)
	await _frames(5)
	_check(menu._bots().size() == 1, "one bot removed")
	menu._remove_bots(4)
	await _frames(5)
	_check(menu._bots().size() == 0 and arena.players_root.get_child_count() == 1, "every bot removed")

	# Robot and gun.
	var spot := me.global_position
	menu._set_loadout("weapon", "lever_action")
	menu._set_loadout("character", "orbit")
	await _frames(5)
	me = arena.local_player
	_check(me.weapon.data.id == "lever_action" and net.player_character(net.my_id()) == "orbit", "robot and gun changed")
	_check(me.global_position.distance_to(spot) < 0.5, "you stay where you were")

	# Melee swings are charged: a tap is weak, holding the button winds the swing up
	# (the body coils) and letting go hits much harder.
	menu._set_loadout("weapon", "hammer")
	await _frames(5)
	me = arena.local_player
	var hammer := WeaponData.by_id("hammer")
	dummy = arena.dummies[1]
	me.teleport(dummy.global_position - Vector3(2.0, 0, 0), -PI / 2)
	await _frames(5)
	_hits.clear()
	var health := dummy.health
	DevArgs.drives_keys = true   # the player listens to the keys without the mouse captured
	Input.action_press("fire")
	await _frames(3)
	Input.action_release("fire")
	await get_tree().create_timer(hammer.windup + 0.4).timeout
	_check(_hits.size() == 1 and absf(health - dummy.health - hammer.damage) < 1.0,
		"a tap of the hammer is a weak blow (%.1f damage, %d hits)" % [health - dummy.health, _hits.size()])
	await get_tree().create_timer(hammer.fire_interval).timeout
	health = dummy.health
	Input.action_press("fire")
	await get_tree().create_timer(hammer.charge_time * 0.5).timeout
	var half := me.melee_charge()
	_check(_hits.size() == 1, "holding the button does not swing")
	await get_tree().create_timer(hammer.charge_time * 0.5 + 0.3).timeout
	_check(half > 0.3 and half < 0.7 and me.melee_charge() == 1.0 and me.winding_up(), "holding it winds the swing up (%.2f, then %.2f)" % [half, me.melee_charge()])
	_check(me.animator._swing.winding() and me.animator._swing.coil() < -0.9, "and the body coils with it (%.2f)" % me.animator._swing.coil())
	Input.action_release("fire")
	await get_tree().create_timer(0.4).timeout
	_check(_hits.size() == 2 and is_equal_approx(health - dummy.health, hammer.charge_damage),
		"letting go of a full wind-up hits much harder (%.1f damage)" % (health - dummy.health))
	_check(not me.winding_up() and me.melee_charge() == 0.0, "and the wind-up is spent")
	# Gliding: hold Shift in the air (through the real key), and guns scatter less while you do.
	me.teleport(dummy.global_position + Vector3(-8, 6.0, 0), -PI / 2)
	await _frames(2)
	var usual := me.spread_scale()
	Input.action_press("glide")
	await _frames(6)
	var glided := me.motor.state == MovementController.State.GLIDE
	var tight := me.spread_scale()
	Input.action_release("glide")
	await _frames(4)
	_check(glided, "holding Shift in the air glides")
	_check(is_equal_approx(usual, 1.0) and is_equal_approx(tight, Player.GLIDE_SPREAD), "spread is tighter while gliding (%.2f of the usual)" % tight)
	_check(me.motor.state != MovementController.State.GLIDE, "letting go stops the glide")
	await get_tree().create_timer(1.0).timeout   # back on the floor
	DevArgs.drives_keys = false

	# The menu opens offline (and builds every control without errors).
	menu.set_open(true)
	await _frames(2)
	_check(menu.is_open(), "the debug menu opens in Practice")
	var reset: Button = menu.find_child("reset", true, false)
	_check(menu.find_child("account", true, false) != null and reset != null, "it has the achievement and unlock options")
	if reset:
		var done_before: int = Achievements.done_count()
		reset.pressed.emit()
		_check(reset.text != DebugMenu.RESET_TEXT and Achievements.done_count() == done_before, "resetting the account asks first: one press wipes nothing")
	menu.set_open(false)

	# Slow motion, and the host still accepts shots at double speed.
	Cheats.time_scale = 0.25
	await _frames(2)
	_check(is_equal_approx(Engine.time_scale, 0.25), "game speed follows the menu")
	Cheats.time_scale = 1.0

	# Online: no cheats, no menu.
	Cheats.god = true
	Cheats.time_scale = 0.5
	_check(Cheats.god_mode(), "god mode works offline")
	game.mode = game.Mode.ONLINE
	_check(not Cheats.allowed() and not Cheats.god_mode(), "no cheats in an online match")
	menu.set_open(true)
	_check(not menu.is_open(), "the debug menu does not open online")
	await _frames(2)
	_check(Engine.time_scale == 1.0, "normal game speed online")
	Cheats.reset()

	print("PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)


func _shoot(match_state, me: Player, from: Vector3, at: Vector3) -> void:
	match_state.request_shot(from, PackedVector3Array([(at - from).normalized()]), {}, "pistol", me.peer_id)


func _wait_fire(w: WeaponData) -> void:
	await get_tree().create_timer(w.fire_interval + 0.02).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		_ok = false
