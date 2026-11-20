extends SceneTree
## Headless checks on the air cannon (WeaponData.Kind.BLAST, see AirBlast): it does no
## damage at all (to players or walls), it has no ammo and never reloads, only a short
## gap between blasts; hold to charge (full in 1.5 s), and a charged blast shoves far
## harder than a tap (a tap never slams anyone into a wall hard enough to hurt, a full
## charge does), still decently at the edge of the cone; the cone takes in only who is in
## front, within its angle and reach, and in sight; everyone is pushed away from the
## shooter and lifted off their feet.
## Run: godot --headless --path . --script tests/air_cannon_test.gd

const SLAM_SPEED := 17.5   ## Match.SLAM_SPEED (an autoload: not loaded in this test)
const HEIGHT := 1.8        ## Player.CAPSULE_HEIGHT

var _ok := true


func _init() -> void:
	var w := WeaponData.by_id("air_cannon")
	_check(w.is_blast() and not w.is_melee() and not w.is_projectile(), "a blast: neither a blade nor a projectile")

	# No damage, to anyone or anything.
	_check(w.damage == 0.0 and w.damage_at(0.0) == 0.0 and w.damage_at(w.max_range) == 0.0, "no damage at any range")
	_check(w.structure_damage == 0.0, "breaks no walls")
	# The host's blast only ever shoves: nothing in it hurts (a crash it causes is the wall's doing, see Match._host_slam).
	var src := FileAccess.get_file_as_string("res://game/match/match_state.gd")
	var at := src.find("func _host_blast(")
	var body := src.substr(at, src.find("\nfunc ", at + 10) - at)
	_check(at >= 0 and body.contains("_host_shove(") and not body.contains("_host_damage(") and not body.contains("_host_dummy_damage(")
		and not body.contains("breaks.damage("), "the host's blast shoves and hurts nobody")

	# No ammo, no reload: only the gap between blasts.
	_check(w.magazine == 0 and w.reload_time == 0.0, "no magazine, no reload")
	_check(w.fire_interval >= 0.3 and w.fire_interval <= 0.5, "0.3-0.5 s between blasts (%.2f)" % w.fire_interval)
	var s := WeaponState.new(w)
	var blasts := 0
	var t := 0.0
	while t < 4.0:
		if s.fire():
			blasts += 1
		s.update(1.0 / 60.0)
		t += 1.0 / 60.0
	_check(not s.is_reloading() and blasts >= int(4.0 / (w.fire_interval + 0.05)) and blasts <= int(4.0 / w.fire_interval) + 1,
		"never runs dry or reloads; tapping is held to one blast per %.1f s (%d in 4 s)" % [w.fire_interval, blasts])
	s.start_reload()
	_check(not s.is_reloading(), "nothing to reload")

	# Hold to charge: full in 1.5 s, and the more it is charged the harder it shoves.
	_check(is_equal_approx(w.charge_time, 1.5) and w.charge_of(0.0) == 0.0 and w.charge_of(0.75) > 0.45 and w.charge_of(0.75) < 0.55
		and w.charge_of(1.5) == 1.0 and w.charge_of(9.0) == 1.0, "full charge in 1.5 s")
	var tap: Array = w.blast_knockback(0.0, 2.0)
	var half: Array = w.blast_knockback(0.5, 2.0)
	var full: Array = w.blast_knockback(1.0, 2.0)
	_check(full[0] > half[0] and half[0] > tap[0] and full[0] >= tap[0] * 3.0, "a charged blast shoves far harder than a tap (%.1f, %.1f, %.1f m/s)" % [tap[0], half[0], full[0]])
	_check(full[1] > tap[1] and tap[1] > 0.5, "and lifts higher; even a tap lifts you off your feet")
	_check(Vector2(tap[0], tap[1]).length() < SLAM_SPEED, "a tap never slams anyone into a wall hard enough to hurt")
	_check(full[0] > SLAM_SPEED * 1.8, "a full charge does, hard (%.1f m/s)" % full[0])
	var edge: Array = w.blast_knockback(1.0, w.max_range)
	_check(edge[0] < full[0] and edge[0] >= full[0] * 0.5 and edge[0] > SLAM_SPEED, "weaker at the edge of the cone, but still a real shove (%.1f m/s)" % edge[0])
	_check(w.max_range >= 15.0 and w.max_range <= 18.0 and w.cone_degrees >= 25.0 and w.cone_degrees <= 30.0,
		"a cone 15-18 m long, 25-30 degrees either side (%.0f m, %.0f deg)" % [w.max_range, w.cone_degrees])

	# The cone. The shooter's eyes at the origin, looking down -Z.
	var eye := Vector3(0, 1.6, 0)
	var ahead := Vector3.FORWARD
	var hidden := Vector3(2.0, 0, -9.0)
	var bodies := [
		_body(1, Vector3(0, 0, -6)),        # straight ahead: in
		_body(2, Vector3(0, 0, 5)),         # right behind: out
		_body(3, Vector3(-1.5, 0, 0.5)),    # beside and a little behind: out
		_body(4, Vector3(-8, 0, -8)),       # 45 degrees off: out
		_body(5, Vector3(-3, 0, -11)),      # about 15 degrees off: in
		_body(6, hidden),                   # in the cone, behind a wall: out
		_body(7, Vector3(0, 0, -w.max_range - 2.0)),   # straight ahead, out of reach: out
		_body(8, Vector3(0.3, 0, -1.0)),    # right in front, touching: in
	]
	var clear := func(_a: Vector3, b: Vector3) -> bool:
		return b.distance_to(hidden) > 2.5   # (a wall hides body 6, and only it)
	var hits := AirBlast.hits(eye, ahead, bodies, w, 1.0, clear)
	var ids := hits.map(func(h): return h.id)
	ids.sort()
	_check(ids == [1, 5, 8], "the cone takes in who is in front and in sight, not behind, aside, past its reach or behind a wall (%s)" % [ids])
	for h in hits:
		var b: Array = bodies.filter(func(x): return x[0] == h.id)[0]
		var away := Vector3(b[1].x, 0, b[1].z).normalized()
		var push: Vector3 = h.push
		_check(Vector3(push.x, 0, push.z).normalized().dot(away) > 0.9, "%d: pushed away from the shooter" % h.id)
		_check(push.y > 2.0, "%d: and lifted off their feet (%.1f m/s up)" % [h.id, push.y])
		_check(not (h as Dictionary).has("damage"), "%d: no damage" % h.id)
	var taps := AirBlast.hits(eye, ahead, bodies, w, 0.0, clear)
	_check(taps.size() == hits.size(), "a tap reaches the same people")
	for i in taps.size():
		_check((hits[i].push as Vector3).length() > (taps[i].push as Vector3).length() * 2.5, "%d: a full charge shoves them far harder than a tap" % hits[i].id)
	var near: Vector3 = hits.filter(func(h): return h.id == 1)[0].push
	var far: Vector3 = hits.filter(func(h): return h.id == 5)[0].push
	_check(near.length() > far.length(), "closer is pushed harder")
	# Blasting down at someone below pushes them along the floor, not into it.
	var below := AirBlast.hits(Vector3(0, 6.0, 0), Vector3(0, -0.5, -1).normalized(), [_body(9, Vector3(0, 0, -6))], w, 1.0, clear)
	_check(below.size() == 1 and (below[0].push as Vector3).y > 0.0, "a blast from above still lifts them")
	# Teammates and the shooter never get here: Match._rewound_bodies leaves them out.

	print("AIR CANNON TEST PASSED" if _ok else "AIR CANNON TEST FAILED")
	quit(0 if _ok else 1)


## A body as Match._rewound_bodies gives them: [id, feet, height, facing yaw].
func _body(id: int, feet: Vector3) -> Array:
	return [id, feet, HEIGHT, 0.0]


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("FAIL: " + what)
