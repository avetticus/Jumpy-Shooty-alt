extends Node
## Sticky grenade checks (the grenade launcher's alt fire; see Match._host_stick and
## Projectile), started by tests/sticky_grenade_test.gd. Played out in real Vs Bots
## matches with the bots frozen, on a slab of floor the test puts high over the map:
##  - the numbers and the weapon data;
##  - alt fire fires one by the trigger's rules: a round from the drum, the time between
##    shots, nothing when empty (a reload starts), it stops a shell-by-shell reload, and
##    nothing with a gun whose alt fire is not "sticky";
##  - it sticks to the floor where it lands and to a player it hits (riding them as they
##    move, on the host and as drawn), never goes off on impact, and is drawn as a
##    sticky that blinks faster once armed;
##  - armed STICKY_ARM after it sticks, not before; then an enemy within STICKY_REACH
##    (and in sight) sets it off, its owner never does, one behind a wall does not, and
##    one stuck on an enemy goes off as soon as it is armed; the blast hurts the enemy
##    and is credited to the owner with the grenade launcher (even after a gun change);
##  - at most STICKY_MAX each: a fourth takes the oldest away without a blast;
##  - it goes without a blast when its owner dies, when the player it is on dies, when
##    the breakable piece it is on breaks, and when the match ends;
##  - the killcam records it stuck again every second, and a clip cut from the recording
##    keeps one stuck before the clip starts, and drops one that went off before;
##  - Search and Destroy: a teammate within reach never sets it off, an enemy does.

const Y0 := 150.0   # the top of the test's slab of floor

var _fails: Array[String] = []
var _fired: Array = []    # [id, shooter, sticky]
var _stuck: Array = []    # [id, how]
var _armed: Array = []    # ids
var _gone: Array = []     # ids
var _booms: Array = []    # [id, at]
var _hits: Array = []     # [shooter, target, damage]
var _scored: Array = []   # kill infos
var _center := Vector3.ZERO
var _slab: StaticBody3D


func run() -> void:
	await get_tree().process_frame
	print("Sticky grenade checks")
	Match.projectile_fired.connect(func(id, shooter, _w, _o, _d, sticky): _fired.append([id, shooter, sticky]))
	Match.projectile_stuck.connect(func(id, how): _stuck.append([id, how]))
	Match.projectile_armed.connect(func(id): _armed.append(id))
	Match.projectile_gone.connect(func(id): _gone.append(id))
	Match.exploded.connect(func(id, at, _w): _booms.append([id, at]))
	Match.player_hit.connect(func(s, t, dmg, _h): _hits.append([s, t, dmg]))
	Match.kill_scored.connect(func(info): _scored.append(info))
	_data()
	await _ffa()
	await _teams()
	Cheats.freeze_bots = false
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


func _data() -> void:
	print("  the numbers")
	var gl := WeaponData.by_id("grenade_launcher")
	_expect(gl.alt == "sticky" and not gl.alt_is_hold() and gl.is_projectile(), "the grenade launcher's alt fire is the sticky grenade, a press")
	_expect(Projectile.STICKY_ARM == 0.5 and Projectile.STICKY_REACH == 3.0 and Projectile.STICKY_MAX == 3,
		"armed after 0.5 s, 3 m reach, 3 out at once")
	var shell := Projectile.make(1, gl, Vector3.ZERO, Vector3.FORWARD, Vector3.INF, Color.WHITE)
	var sticky := Projectile.make(2, gl, Vector3.ZERO, Vector3.FORWARD, Vector3.INF, Color.WHITE, true)
	_expect(shell.look() == "grenade" and sticky.look() == "sticky" and sticky.get_child_count() != shell.get_child_count(),
		"a sticky is drawn its own way (%s, %s)" % [shell.look(), sticky.look()])
	shell.free()
	sticky.free()


# ---------------------------------------------------------------------------
# Free-for-all: you and two frozen bots

func _ffa() -> void:
	print("  free-for-all")
	await _start("kills", "testing_grounds", 2)
	var me: Player = Net.arena.local_player
	var my_id := Net.my_id()
	var bots: Array = Net.bot_ids()
	_expect(me != null and bots.size() == 2, "a Vs Bots match with two bots")
	if me == null or bots.size() < 2:
		return
	var a: int = bots[0]
	var b: int = bots[1]
	_put(my_id, Vector3(0, 0, 0))
	_put(a, Vector3(12, 0, 12))
	_put(b, Vector3(-12, 0, 12))
	Net.host_set_weapon(my_id, "grenade_launcher")
	await _frames(10)
	_expect(me.weapon != null and me.weapon.data.id == "grenade_launcher", "you hold the grenade launcher")

	# Alt fire: the trigger's rules.
	var ws: WeaponState = me.weapon
	ws.reset()
	me.input.pitch = -0.6   # (at the floor in front of you)
	_reset_logs()
	me.input.alt_fire_pressed = true
	await _frames(2)
	var fired_sticky := _fired.filter(func(f): return f[1] == my_id and f[2])
	_expect(fired_sticky.size() == 1 and ws.ammo == ws.data.magazine - 1, "alt fire fires a sticky grenade, a round from the drum (%d fired, %d left)" % [fired_sticky.size(), ws.ammo])
	me.input.alt_fire_pressed = true
	await _frames(2)
	_expect(_fired.size() == 1 and ws.ammo == ws.data.magazine - 1, "not again before the time between shots (%d fired)" % _fired.size())
	await _secs(ws.data.fire_interval + 0.1)
	Match._last_shot_time.erase(my_id)
	ws.ammo = 0
	ws._reload_left = 0.0
	me.input.alt_fire_pressed = true
	await _frames(2)
	_expect(_fired.size() == 1 and ws.is_reloading(), "empty: nothing, and it reloads")
	ws._reload_left = ws.data.reload_time * 0.5
	ws.ammo = 2
	ws._cooldown = 0.0
	Match._last_shot_time.erase(my_id)
	me.input.alt_fire_pressed = true
	await _frames(2)
	_expect(_fired.size() == 2 and ws.ammo == 1 and not ws.is_reloading(), "a press stops the shell-by-shell reload to fire (%d fired, %d left)" % [_fired.size(), ws.ammo])
	Net.host_set_weapon(my_id, "rocket_launcher")
	await _frames(4)
	Match._last_shot_time.erase(my_id)
	var rockets := me.weapon.ammo if me.weapon else -1
	me.input.alt_fire_pressed = true
	await _frames(2)
	_expect(_fired.size() == 2 and me.weapon and me.weapon.ammo == rockets, "nothing from a gun without a sticky alt fire")
	Net.host_set_weapon(my_id, "grenade_launcher")
	await _frames(4)
	me.input.pitch = 0.0
	await _secs(0.6)
	Match._host_clear_projectiles()
	await _frames(2)
	_expect(Match.sticky_ids(my_id).is_empty() and _no_drawn_stickies(), "cleared away on every copy")

	# Sticking to the floor; armed after STICKY_ARM; who sets it off.
	_reset_logs()
	var id := await _sticky_at(Vector3(4, 0, 0))
	var p: Dictionary = Match._projectiles.get(id, {})
	_expect(not p.is_empty() and p.get("stuck", false) and int(p.on) == 0 and absf((p.pos as Vector3).y - Y0) < 0.2,
		"a sticky sticks to the floor where it lands (%s)" % [p.get("pos", "?")])
	_expect(_booms.is_empty(), "...and does not go off on impact")
	var drawn := Net.arena.get_node_or_null("Projectile_%d" % id) as Projectile
	_expect(drawn != null and drawn.sticky and drawn.stuck and drawn.global_position.distance_to(p.get("pos", Vector3.INF)) < 0.05,
		"...drawn stuck there, as a sticky")
	await _secs(Projectile.STICKY_ARM - 0.2)
	_expect(not _armed.has(id) and not p.get("armed", true) and not drawn.armed, "not armed before %.1f s" % Projectile.STICKY_ARM)
	await _secs(0.3)
	_expect(_armed.has(id) and drawn.armed, "armed by %.1f s, and drawn armed (blinking faster)" % Projectile.STICKY_ARM)
	_put(my_id, _floor_of(p.pos) + Vector3(0.6, 0, 0))   # its owner, right beside it
	await _secs(0.4)
	_expect(_booms.is_empty() and Match._projectiles.has(id), "its owner never sets it off")
	_put(my_id, Vector3(0, 0, 0))
	var wall := _wall(_floor_of(p.pos) + Vector3(0, 0, 1.2))
	await _frames(2)
	_put(b, _floor_of(p.pos) + Vector3(0, 0, 2.2))   # 2.2 m away (1.8 m to the outside of the body), behind a wall
	await _secs(0.4)
	_expect(_booms.is_empty() and Match._projectiles.has(id), "an enemy within reach behind a wall does not (%s)" % [_booms])
	wall.queue_free()
	await _secs(0.2)
	_expect(_booms.size() == 1 and int(_booms[0][0]) == id and not Match._projectiles.has(id), "an enemy within reach in sight sets it off")
	var hit_b := _hits.filter(func(h): return h[0] == my_id and h[1] == b)
	_expect(not hit_b.is_empty() and Match.health.get(b, 100.0) < Match.MAX_HEALTH, "...and the blast hurts them, from its owner (%s)" % [hit_b])
	_expect(Net.arena.get_node_or_null("Projectile_%d" % id) == null or Net.arena.get_node("Projectile_%d" % id).is_queued_for_deletion(), "...and it is drawn gone")
	_put(b, Vector3(-12, 0, 12))
	Match.host_heal(b)
	Match.host_heal(my_id)

	# Sticking to a player: it rides them, and goes off once armed.
	_reset_logs()
	Match.host_heal(a)
	_put(a, Vector3(3.5, 0, 0))
	await _frames(8)
	id = await _sticky_at(Vector3(3.5, 1.1, 0))
	p = Match._projectiles.get(id, {})
	_expect(not p.is_empty() and int(p.get("on", 0)) == a, "a sticky that hits a player sticks to them (on %s)" % [p.get("on", "?")])
	_expect(_booms.is_empty(), "...without going off")
	var rider: Player = Net.arena.get_player(a)
	_put(a, Vector3(3.5, 0, -4.0))
	await _frames(6)
	p = Match._projectiles.get(id, {})
	drawn = Net.arena.get_node_or_null("Projectile_%d" % id) as Projectile
	var feet := rider.latest_position()
	_expect(not p.is_empty() and (p.pos as Vector3).distance_to(feet + Vector3(0, 1.0, 0)) < 1.2,
		"...rides them as they move, on the host (%.2f m from their middle)" % [(p.get("pos", Vector3.INF) as Vector3).distance_to(feet + Vector3(0, 1.0, 0))])
	_expect(drawn != null and drawn.global_position.distance_to(rider.global_position + Vector3(0, 1.0, 0)) < 1.2,
		"...and as drawn")
	await _secs(Projectile.STICKY_ARM + 0.1)
	_expect(_booms.size() == 1 and int(_booms[0][0]) == id, "one stuck on an enemy goes off as soon as it is armed")
	_expect(not _hits.filter(func(h): return h[0] == my_id and h[1] == a).is_empty(), "...hurting them")
	Match.host_heal(a)
	Match.host_heal(my_id)

	# The player it is on dies: it goes, no blast.
	_reset_logs()
	_put(a, Vector3(3.5, 0, 0))
	await _frames(8)
	id = await _sticky_at(Vector3(3.5, 1.1, 0))
	_expect(int(Match._projectiles.get(id, {}).get("on", 0)) == a, "another on the bot")
	Match._host_damage(b, a, 500.0)
	await _frames(3)
	_expect(_gone.has(id) and not Match._projectiles.has(id) and _booms.is_empty(), "the player it is on dies: it goes without a blast")
	await _frames(2)
	_expect(_no_drawn_stickies(), "...and is drawn gone")
	await _wait_alive(a)

	# At most STICKY_MAX: a fourth takes the oldest away.
	_reset_logs()
	var ids := []
	for i in Projectile.STICKY_MAX + 1:
		ids.append(await _sticky_at(Vector3(4, 0, -3 + 2 * i)))
	_expect(Match.sticky_ids(my_id) == ids.slice(1), "a fourth takes the oldest away (%s of %s)" % [Match.sticky_ids(my_id), ids])
	_expect(_gone == [ids[0]] and _booms.is_empty(), "...without a blast (%s)" % [_gone])
	await _frames(2)
	_expect(Net.arena.get_node_or_null("Projectile_%d" % ids[0]) == null, "...and it is drawn gone")
	_expect(Net.arena.get_node_or_null("Projectile_%d" % ids[1]) != null, "...the others are still drawn")

	# The killcam: recorded stuck again every second; a clip keeps one stuck before it.
	await _secs(Killcam.STICK_AGAIN + 0.2)
	var newest := -INF
	for e in Killcam._events:
		if str(e.kind) == "stick" and int(e.id) == ids[1]:
			newest = maxf(newest, float(e.t))
	_expect(Killcam._clock - newest <= Killcam.STICK_AGAIN + 0.1, "the killcam records a stuck sticky again every second (%.2f s ago)" % (Killcam._clock - newest))
	_clip_cut()

	# Its owner dies: all of theirs go, no blast.
	_reset_logs()
	Match._host_damage(a, my_id, 500.0)
	await _frames(3)
	_expect(Match.sticky_ids(my_id).is_empty() and _gone.size() == 3 and _booms.is_empty(), "its owner dies: all of theirs go without a blast (%s)" % [_gone])
	await _frames(2)
	_expect(_no_drawn_stickies(), "...and are drawn gone")
	await _secs(Match.RESPAWN_DELAY + 0.2)
	Match.request_respawn()
	await _wait_alive(my_id)
	Net.host_set_weapon(my_id, "grenade_launcher")
	_put(my_id, Vector3(0, 0, 0))
	await _frames(8)

	# A kill with it is the grenade launcher's, even after a change of gun.
	_reset_logs()
	id = await _sticky_at(Vector3(4, 0, 0))
	p = Match._projectiles.get(id, {})
	Net.host_set_weapon(my_id, "pistol")
	await _secs(Projectile.STICKY_ARM + 0.1)
	Match.health[b] = 10.0
	_put(b, _floor_of(p.get("pos", Vector3.ZERO)) + Vector3(0, 0, 1.5))
	await _secs(0.3)
	var info: Dictionary = _scored[-1] if not _scored.is_empty() else {}
	_expect(_booms.size() == 1 and int(info.get("victim", 0)) == b and int(info.get("killer", 0)) == my_id and str(info.get("weapon", "")) == "grenade_launcher",
		"a sticky kill is its owner's, with the grenade launcher, after a change of gun (%s)" % [info])
	_expect(str((Match.death_fx.get(b, {}) as Dictionary).get("with", "")) == "grenade_launcher", "...in the kill feed too")
	Net.host_set_weapon(my_id, "grenade_launcher")
	await _frames(4)

	# The match ends: they go.
	_reset_logs()
	id = await _sticky_at(Vector3(4, 0, 0))
	Match.host_end_match()
	await _frames(4)
	_expect(_gone.has(id) and Match._projectiles.is_empty(), "the match ends: they go")


## A clip cut from a recording keeps a sticky stuck before it starts (armed by then),
## and drops one that went off before it.
func _clip_cut() -> void:
	var clip := KillClip.new()
	clip.killer = 1
	clip.start = 10.0
	clip.end = 13.0
	var how := {"at": Vector3.ZERO, "normal": Vector3.UP, "on": 0, "frame": "", "who": 1, "weapon": "grenade_launcher"}
	clip.events = [
		{"t": 2.0, "kind": "stick", "who": 1, "id": 5, "how": how, "armed": false},
		{"t": 2.5, "kind": "armed", "who": 1, "id": 5},
		{"t": 3.0, "kind": "stick", "who": 1, "id": 6, "how": how, "armed": false},
		{"t": 4.0, "kind": "boom", "who": 1, "id": 6, "at": Vector3.ZERO, "weapon": "grenade_launcher"},
		{"t": 11.0, "kind": "shot", "who": 1, "muzzle": Vector3.ZERO, "ends": PackedVector3Array(), "hits": [], "weapon": "pistol"},
	]
	var cut := clip.cut()
	var kept: Array = cut.events.filter(func(e): return str(e.kind) == "stick")
	_expect(kept.size() == 1 and int(kept[0].id) == 5 and bool(kept[0].armed), "a clip keeps a sticky stuck before it starts, armed (%s)" % [kept])
	_expect(cut.events.size() == 2, "...and drops one that went off before it")


## A sticky on a breakable piece of wall goes, without a blast, when the piece breaks
## (made stuck there by hand: aiming one at a piece is down to the map).
func _breakable() -> void:
	var my_id := Net.my_id()
	_reset_logs()
	var dest: MapDestruction = Net.arena.layout.destruction
	var cell := -1
	if dest:
		for c in dest.cells.size():
			if not dest.cells[c].protected and int(dest.cells[c].stage) == 0:
				cell = c
				break
	if cell < 0:
		print("    (no breakable piece on this map)")
	else:
		var body: Node3D = dest.panels[int(dest.cells[cell].panel)].body
		Match._projectiles[9000] = {"pos": Vector3.ZERO, "vel": Vector3.ZERO, "shooter": my_id, "weapon": "grenade_launcher", "t": 0.0, "sticky": true}
		var at := dest.cell_center(cell)
		Match._host_stick(9000, at, Vector3.UP, 0, body)
		await _frames(2)
		var rec: Dictionary = Match._projectiles.get(9000, {})
		_expect(int(rec.get("cell", -1)) == cell and str((rec.get("how", {}) as Dictionary).get("frame", "")) != "",
			"a sticky on a breakable piece knows which piece, and the part of the map it is on")
		_expect(Net.arena.get_node_or_null("Projectile_9000") != null, "one never seen flying is drawn when it sticks (as for someone joining)")
		dest.damage(cell, 1.0e6)
		Match._flush_breaks()
		await _frames(3)
		_expect(_gone.has(9000) and not Match._projectiles.has(9000) and _booms.is_empty(), "the piece breaks: it goes without a blast")


# ---------------------------------------------------------------------------
# Search and Destroy: teammates never set it off

func _teams() -> void:
	print("  Search and Destroy")
	await _start("snd", "construction_site", 3)
	var my_id := Net.my_id()
	var red: Array = Teams.members(0)
	var blue: Array = Teams.members(1)
	_expect(red.has(my_id) and red.size() == 2 and blue.size() == 2, "2v2 (%s / %s)" % [red, blue])
	if not red.has(my_id) or red.size() < 2 or blue.size() < 2:
		return
	var mate: int = red[0] if red[0] != my_id else red[1]
	_put(my_id, Vector3(0, 0, 0))
	_put(mate, Vector3(-10, 0, 8))
	_put(blue[0], Vector3(10, 0, 10))
	_put(blue[1], Vector3(-10, 0, -10))
	Net.host_set_weapon(my_id, "grenade_launcher")
	await _frames(10)
	_reset_logs()
	var id := await _sticky_at(Vector3(4, 0, 0))
	var p: Dictionary = Match._projectiles.get(id, {})
	_expect(p.get("stuck", false), "a sticky stuck")
	await _secs(Projectile.STICKY_ARM + 0.1)
	_put(mate, _floor_of(p.get("pos", Vector3.ZERO)) + Vector3(0, 0, 1.5))
	await _secs(0.4)
	_expect(_booms.is_empty() and Match._projectiles.has(id), "a teammate within reach never sets it off")
	_put(mate, Vector3(-10, 0, 8))
	_put(blue[0], _floor_of(p.get("pos", Vector3.ZERO)) + Vector3(0, 0, -1.5))
	await _secs(0.3)
	_expect(_booms.size() == 1 and int(_booms[0][0]) == id, "an enemy does")
	_expect(_hits.filter(func(h): return h[1] == mate).is_empty(), "...and the blast never hurts the teammate")
	await _breakable()


# ---------------------------------------------------------------------------

## A Vs Bots match with these rules and frozen bots, once the arena is up; then a slab
## of floor high over the middle of the map for the test.
func _start(rules: String, map: String, bots: int) -> void:
	Cheats.freeze_bots = true
	Game.start_bot(1, 50, map, bots, rules, "ffa", [])
	for i in 300:
		await get_tree().physics_frame
		if Net.arena != null and Net.arena.players_root.get_child_count() == bots + 1 and (rules != "snd" or Teams.map_ready):
			break
	for i in 10:
		await get_tree().physics_frame
	var area: Rect2 = Net.arena.layout.bounds
	var mid := area.get_center() if area.has_area() else Vector2.ZERO
	_center = Vector3(mid.x, Y0, mid.y)
	_slab = StaticBody3D.new()
	_slab.name = "StickyTestSlab"
	_slab.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	_slab.add_child(shape)
	Net.arena.add_child(_slab)
	_slab.global_position = _center - Vector3(0, 0.5, 0)


## A wall across the slab (0.4 m thick, 4 m tall, 8 m wide, along x) at `at` (from its middle).
func _wall(at: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 4.0, 0.4)
	shape.shape = box
	wall.add_child(shape)
	Net.arena.add_child(wall)
	wall.global_position = _center + at + Vector3(0, 2.0, 0)
	return wall


## Puts player `id` on the slab, `at` from its middle (y: height above it).
func _put(id: int, at: Vector3) -> void:
	var p: Player = Net.arena.get_player(id)
	if p:
		p.teleport(_center + at + Vector3(0, 0.05, 0), 0.0)
		p.velocity = Vector3.ZERO


## Where on the slab (relative to its middle) the point `pos` is, on the floor.
func _floor_of(pos: Vector3) -> Vector3:
	return Vector3(pos.x - _center.x, 0.0, pos.z - _center.z)


## Fires a sticky (as the host would for you) from your eyes at `spot` (relative to the
## slab's middle) and waits until it has stuck. Returns its id.
func _sticky_at(spot: Vector3) -> int:
	var me: Player = Net.arena.local_player
	Match._last_shot_time.erase(Net.my_id())   # (the host spaces shots by real time; this runs on a fixed clock)
	var eye := me.eye_position()
	var id: int = Match._next_projectile
	Match.request_projectile(eye, (_center + spot - eye).normalized(), Net.my_id(), true)
	for i in 90:
		await get_tree().physics_frame
		if Match._projectiles.get(id, {}).get("stuck", false) or not Match._projectiles.has(id):
			break
	return id


func _no_drawn_stickies() -> bool:
	for node in Net.arena.get_children():
		if node is Projectile and (node as Projectile).sticky and not node.is_queued_for_deletion():
			return false
	return true


func _wait_alive(id: int) -> void:
	for i in 600:
		if Match.is_alive(id):
			break
		await get_tree().physics_frame
	await _frames(4)


func _reset_logs() -> void:
	for entries in [_fired, _stuck, _armed, _gone, _booms, _hits, _scored]:
		entries.clear()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _secs(seconds: float) -> void:
	await _frames(ceili(seconds * Engine.physics_ticks_per_second))
