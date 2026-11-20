extends SceneTree
## Halcyon checks (game/maps/halcyon.tscn):
##  - listed for free-for-all (which Gun Game is played on) and Deathmatch; about
##    140 x 140 m; the kill height is far below every floor;
##  - 16 or more spawn points, each clear, on a floor and inside the bounds, none in
##    the Control Room and none with a line of sight to the terminal's dais;
##  - weapon pickups: about 16 of 10 or more kinds, none in the Control Room, the
##    heavy ones high up;
##  - the terminal stands on the dais and fires the low gravity event; the
##    centrifuge is a spinner (never solid);
##  - routes, on the bots' navigation mesh: every spoke room (both its levels) can be
##    walked to from the hub and back, the two decks connect, the Control Room can
##    be entered by each of its six doorways, and every spawn point reaches every other;
##  - the dome and the floor glass cannot break (other glass can), and they hold:
##    nothing gets out of the hull, however high low gravity lets you jump;
##  - the reactor pit kills: nothing in it to land on above the kill height.
## Run: godot --headless --path . --script tests/halcyon_test.gd

const ID := "halcyon"
const LOW := -6.0
const DAIS := Vector3(0, 1.2, 0)
const HUB_RADIUS := 15.0

## Places a bot must be able to walk to from the dais, and back.
const GOALS := {
	"hangar deck": Vector3(0, -6, -48), "hangar balcony": Vector3(10, 0, -36), "hangar booth": Vector3(0, 7, -37),
	"engineering floor": Vector3(-16, -6, 45), "engineering balcony": Vector3(21, 0, 50), "reactor catwalk": Vector3(6.5, 0, 49),
	"engineering 8 m ledge": Vector3(22, 8, 45),
	"cargo floor": Vector3(-41, -6, 0), "cargo balcony": Vector3(-35, 0, -10), "cargo 8 m catwalk": Vector3(-64, 8, 10),
	"hydroponics floor": Vector3(44, -6, 0), "hydroponics balcony": Vector3(35, 0, 10), "first terrace": Vector3(57, 6, 0),
	"hydroponics undercroft": Vector3(60, -6, 0),
	"cryo pod bay": Vector3(-50.5, 0, 45), "crew mess": Vector3(-31, 0, 55),
	"ring north-east": Vector3(61, 0, -61), "ring north-west": Vector3(-61, 0, -61), "ring south-east": Vector3(61, 0, 61),
	"ring south-west": Vector3(-63, 0, 57),
	"lower ring north-east": Vector3(59, -6, -59), "lower ring south-west": Vector3(-63, -6, 63),
	"passage under the control room": Vector3(0, -6, -14.5),
}
## A point just outside each of the Control Room's six doorways (four spokes and the
## two stairwell lobbies), and how far a walk from there to the dais may be.
const DOORS := {
	"north spoke": Vector3(0, 0, -22), "east spoke": Vector3(22, 0, 0), "south spoke": Vector3(0, 0, 22),
	"west spoke": Vector3(-22, 0, 0), "north-east stairwell": Vector3(15.0, 0, -18.0), "south-west stairwell": Vector3(-15.0, 0, 18.0),
}
## Pairs across the two decks that must connect: [lower deck, main deck].
const DECK_LINKS := [
	[Vector3(0, -6, -26), Vector3(0, 0, -20)], [Vector3(59, -6, -40), Vector3(61, 0, -40)],
	[Vector3(-63, -6, 40), Vector3(-63, 0, 40)], [Vector3(14.5, -6, 0), Vector3(12, 0, 0)],
]

var failures := 0
var map: MapRoot
var space: PhysicsDirectSpaceState3D


func _initialize() -> void:
	print("Halcyon checks")
	_run.call_deferred()


func _run() -> void:
	_expect(Maps.fits(ID, "ffa") and Maps.fits(ID, "dm") and Maps.game_of(ID) == "ffa",
		"listed for free-for-all (and so Gun Game) and Deathmatch")
	map = Maps.make(ID)
	map.destructible = true
	root.add_child(map)
	var started := Time.get_ticks_msec()
	map.build(false)
	print("    built in %d ms" % (Time.get_ticks_msec() - started))
	for i in 3:
		await physics_frame
	space = root.get_world_3d().direct_space_state
	_rules()
	_spawns()
	_pickups()
	_objects()
	_glass()
	_strips()
	_flicker()
	_pit()
	_sealed()
	await _routes()
	print("FAIL: %d checks failed" % failures if failures else "PASS: every check passed")
	quit(1 if failures else 0)


func _rules() -> void:
	print("  size and rules")
	var b := map.bounds
	_expect(absf(b.size.x - 140.0) <= 6.0 and absf(b.size.y - 140.0) <= 6.0, "about 140 x 140 m (%.0f x %.0f)" % [b.size.x, b.size.y])
	_expect(map.kill_height < LOW - 6.0, "the kill height (%.0f m) is far below the lower deck (%.0f m)" % [map.kill_height, LOW])
	var low := INF
	for s in map.spawns:
		low = minf(low, (s[0] as Vector3).y)
	for w in map.weapon_spawns:
		low = minf(low, (w[0] as Vector3).y)
	_expect(low > map.kill_height + 6.0, "every spawn point and pickup is well above it (lowest %.1f m)" % low)


func _spawns() -> void:
	print("  spawn points")
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	var bad := []
	var in_hub := []
	var sees := []
	var decks := {"lower": 0, "main": 0}
	for s in map.spawns:
		var pos: Vector3 = s[0]
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.transform = Transform3D(Basis(), pos + Vector3(0, 0.95, 0))
		var below := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos - Vector3(0, 1.0, 0)))
		if not space.intersect_shape(q, 1).is_empty() or below.is_empty() or not map.bounds.has_point(Vector2(pos.x, pos.z)):
			bad.append(pos)
		if Vector2(pos.x, pos.z).length() < HUB_RADIUS + 4.0 and pos.y > -1.0:
			in_hub.append(pos)
		decks["lower" if pos.y < -3.0 else "main"] += 1
		# Line of sight to the dais: from the eyes to points on it and on the console.
		for target in [DAIS + Vector3(0, 0.2, 0), DAIS + Vector3(0, 1.7, 0), DAIS + Vector3(3.5, 0.9, 0), DAIS + Vector3(-3.5, 0.9, 0),
				DAIS + Vector3(0, 0.9, 3.5), DAIS + Vector3(0, 0.9, -3.5)]:
			if _clear(pos + Vector3(0, 1.6, 0), target):
				sees.append(pos)
				break
	_expect(map.spawns.size() >= 16, "%d spawn points (16 or more)" % map.spawns.size())
	_expect(bad.is_empty(), "every spawn point is clear, on a floor and inside the bounds %s" % [bad])
	_expect(in_hub.is_empty(), "none in the Control Room %s" % [in_hub])
	_expect(sees.is_empty(), "none can see the terminal's dais %s" % [sees])
	_expect(decks.lower >= 4 and decks.main >= 8, "both decks have them (%d lower, %d main)" % [decks.lower, decks.main])


## Is there nothing solid between two points? (Glass counts as nothing: you see through it.)
func _clear(from: Vector3, to: Vector3) -> bool:
	var exclude: Array[RID] = []
	for i in 8:
		var q := PhysicsRayQueryParameters3D.create(from, to, 1, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		if not (hit.collider as Node).has_meta("panel"):
			return false   # (the dome and floor glass are part of the level's one body: no spawn is near enough for that to matter)
		exclude.append(hit.rid)   # a pane that can break: look past it
	return false


func _pickups() -> void:
	print("  weapon pickups")
	var kinds := {}
	var in_hub := []
	var high := {}
	for w in map.weapon_spawns:
		var pos: Vector3 = w[0]
		kinds[w[1]] = true
		if Vector2(pos.x, pos.z).length() < HUB_RADIUS + 1.0 and pos.y > -1.0:
			in_hub.append(w[1])
		if pos.y >= 9.0:
			high[w[1]] = pos.y
	_expect(map.weapon_spawns.size() >= 14 and map.weapon_spawns.size() <= 18, "about 16 pickups (%d)" % map.weapon_spawns.size())
	_expect(kinds.size() >= 10, "10 or more different weapons (%d)" % kinds.size())
	_expect(in_hub.is_empty(), "none in the Control Room %s" % [in_hub])
	for heavy in ["rocket_launcher", "railgun", "lever_action", "grenade_launcher"]:
		_expect(high.has(heavy), "the %s is up high (grapple only)" % heavy.replace("_", " "))


func _objects() -> void:
	print("  terminal, event and centrifuge")
	var terminals := map.find_children("*", "MapTerminal", true, false)
	_expect(terminals.size() == 1, "one terminal")
	if terminals.size() == 1:
		var t := terminals[0] as MapTerminal
		var at := t.global_position
		_expect(Vector2(at.x, at.z).length() < 1.0 and at.y > 1.0 and at.y < 1.5, "it stands on the raised dais in the middle (%s)" % at)
		_expect(is_zero_approx(t.channel_time) and is_equal_approx(t.range, 2.0), "one press within 2 m (no hold)")
		var event := t.get_node_or_null(t.event) as GravityEvent
		_expect(event != null, "it fires a low gravity event")
		if event:
			_expect(is_equal_approx(event.gravity_scale, 0.3) and is_equal_approx(event.duration, 30.0) and is_equal_approx(event.ease_time, 2.0)
				and is_equal_approx(event.cooldown, 60.0), "30% gravity for 30 s, 2 s eases, 60 s cooldown")
			_expect(event.mote_volumes.size() >= 5, "motes drift in the Control Room and the four big rooms")
		# The dais is 1 to 1.5 m up and can be stood on all round the console.
		var top := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(2.5, 4, 0), Vector3(2.5, -1, 0)))
		_expect(not top.is_empty() and top.position.y > 1.0 and top.position.y < 1.5, "the dais is %.1f m high" % (top.position.y if top else -1.0))
	_expect(map.spinners.size() == 1, "one spinner: the centrifuge ring")
	if map.spinners.size() == 1:
		var ring := map.spinners[0] as MapSpinner
		_expect(absf(ring.speed) > 1.0, "it turns (%.0f degrees a second)" % ring.speed)
		# Nothing of it is solid: a ray through where it passes over the dome hits nothing.
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 60, 0), Vector3(0, 120, 0)))
		_expect(hit.is_empty(), "it is not solid")


func _glass() -> void:
	print("  glass")
	var d := map.destruction
	_expect(d != null, "the map has breakable pieces")
	if d == null:
		return
	var kinds := {}
	var open := 0
	for c in d.cells.size():
		kinds[d.panels[d.cells[c].panel].kind] = true
		if not d.cells[c].protected:
			open += 1
	_expect(kinds.keys() == ["glass_pane"], "only the glass partitions break (%s)" % [kinds.keys()])
	_expect(open >= 10, "%d panes can be shot out" % open)
	_expect(not map.palette.breakable.has("glass_hull"), "the dome's glass is not a breakable kind")
	# The dome, from the dais looking up and out all round: always something solid that
	# is not a breakable panel. The floor glass, from above it looking down: the same.
	var holds := true
	for i in 24:
		var a := TAU * i / 24.0
		for pitch in [20.0, 45.0, 70.0, 89.0]:
			var dir := Vector3(sin(a) * cos(deg_to_rad(pitch)), sin(deg_to_rad(pitch)), cos(a) * cos(deg_to_rad(pitch)))
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 3.5, 0), Vector3(0, 3.5, 0) + dir * 40.0))
			if hit.is_empty() or (hit.collider as Node).has_meta("panel") or hit.position.y > 15.5:
				holds = false
		var over := Vector3(sin(a) * 8.0, 1.0, cos(a) * 8.0)
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(over, over - Vector3(0, 4, 0)))
		if down.is_empty() or (down.collider as Node).has_meta("panel") or absf(down.position.y) > 0.1:
			holds = false
	_expect(holds, "the dome and the floor glass are solid all round and cannot break")
	# Under the floor glass the shaft is open: the centrifuge shows through.
	var shaft := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(8, -0.5, 0), Vector3(8, -60, 0)))
	_expect(shaft.is_empty(), "the shaft under the floor glass is open all the way down")


## No lit strip hangs in mid-air: every drawn-only block of a glowing kind (the light
## bars and the rooms' colour bands) has something solid right behind it along its
## whole length. One that runs across a doorway shows up here.
func _strips() -> void:
	print("  light strips")
	var ball := SphereShape3D.new()
	ball.radius = 0.45
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ball
	var loose := []
	var checked := 0
	for piece in map.collect_pieces():
		if piece.solid or piece.get("hidden", false) or map.palette.glow.get(piece.kind, 0.0) <= 0.0:
			continue
		var xf: Transform3D = piece.xf
		var points: Array[Vector3] = []
		if piece.shape == "box":
			var axis: int = (piece.size as Vector3).max_axis_index()
			var length: float = piece.size[axis]
			if length < 1.0:
				continue
			var n := maxi(2, int(length / 0.3))
			for i in n + 1:
				var q := Vector3.ZERO
				q[axis] = -length * 0.5 + length * i / n
				points.append(xf * q)
		elif piece.shape == "tube":
			var r: float = (piece.size.x + piece.get("inner", 0.0)) * 0.25
			var n := maxi(24, int(TAU * r / 0.3))
			for i in n:
				points.append(xf * Vector3(cos(TAU * i / n) * r, 0.0, sin(TAU * i / n) * r))
		else:
			continue
		checked += 1
		var hanging := 0
		var where := Vector3.ZERO
		for p in points:
			if p.y < map.kill_height:
				continue   # (the glow at the bottom of the reactor pit)
			query.transform = Transform3D(Basis(), p)
			if space.intersect_shape(query, 1).is_empty():
				hanging += 1
				where = p
		if hanging >= 2:
			loose.append("%s near %s" % [piece.kind, where.snappedf(0.1)])
	_expect(loose.is_empty(), "none of the %d lit strips hangs across a doorway or in mid-air %s" % [checked, loose.slice(0, 6)])


## Two surfaces of different colours in exactly the same plane flicker (the renderer
## cannot tell which is in front). This looks at every flat top in the map, floors and
## the paint on them: no two of different kind or tint may share a height where they
## overlap, unless something covers the spot or it is out on the roof.
func _flicker() -> void:
	print("  flicker")
	var tops := []   # [top height, Rect2 (x, z), look, lowest point, index]
	var boxes := []  # every drawn upright box as an AABB, to tell what is covered
	for piece in map.collect_pieces():
		if piece.get("hidden", false) or piece.shape != "box":
			continue
		var xf: Transform3D = piece.xf
		if not xf.basis.y.is_equal_approx(Vector3.UP):
			continue
		var bx := xf.basis.x
		var along_x := absf(absf(bx.x) - 1.0) < 0.001
		if not along_x and absf(absf(bx.z) - 1.0) > 0.001:
			continue   # turned to some other angle (the round rooms' pieces)
		var size: Vector3 = piece.size
		var half := Vector3(size.x if along_x else size.z, size.y, size.z if along_x else size.x) * 0.5
		var box := AABB(xf.origin - half, half * 2.0)
		boxes.append(box)
		tops.append([box.end.y, Rect2(box.position.x, box.position.z, box.size.x, box.size.z),
			"%s %s" % [piece.kind, piece.get("tint", Color.WHITE)], boxes.size() - 1])
	tops.sort_custom(func(a, b): return a[0] < b[0])
	var probe := PhysicsPointQueryParameters3D.new()
	var clashes := []
	for i in tops.size():
		var a: Array = tops[i]
		for j in range(i + 1, tops.size()):
			var b: Array = tops[j]
			if b[0] - a[0] > 0.004:
				break
			if a[2] == b[2]:
				continue
			var both: Rect2 = (a[1] as Rect2).intersection(b[1])
			if both.size.x < 0.05 or both.size.y < 0.05 or both.get_area() < 0.05:
				continue
			# Can it be seen? Look at a few spots just above it.
			for f in [Vector2(0.5, 0.5), Vector2(0.15, 0.15), Vector2(0.85, 0.85), Vector2(0.15, 0.85), Vector2(0.85, 0.15)]:
				var at := Vector3(both.position.x + both.size.x * f.x, a[0] + 0.03, both.position.y + both.size.y * f.y)
				var covered := false
				for k in boxes.size():
					if k != a[3] and k != b[3] and (boxes[k] as AABB).has_point(at):
						covered = true
						break
				probe.position = at
				if covered or not space.intersect_point(probe, 1).is_empty():
					continue
				var up := PhysicsRayQueryParameters3D.create(at, at + Vector3.UP * 60.0)
				if space.intersect_ray(up).is_empty():
					continue   # nothing overhead: on a roof, outside the ship
				clashes.append("%s and %s at %s" % [(a[2] as String).get_slice(" ", 0), (b[2] as String).get_slice(" ", 0), at.snappedf(0.1)])
				break
	_expect(clashes.is_empty(), "no two floors or floor markings of different colours share a height where they overlap (%d tops) %s" % [tops.size(), clashes.slice(0, 6)])


func _pit() -> void:
	print("  reactor pit")
	var falls := true
	for at in [Vector3(-6, 0, 43), Vector3(6, 0, 55), Vector3(-5.5, 0, 53), Vector3(5, 0, 44), Vector3(0, 0, 54.5), Vector3(-6.5, 0, 49)]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, LOW + 0.5, at.z), Vector3(at.x, map.kill_height - 4.0, at.z)))
		if not hit.is_empty():
			falls = false
	_expect(falls, "nothing to land on in the pit above the kill height: falling in kills")
	# ...and it really is a hole in an otherwise whole floor.
	var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-15, LOW + 1, 49), Vector3(-15, LOW - 2, 49)))
	_expect(not floor_hit.is_empty(), "the floor round it is solid")


## Nothing gets out: from points all over the inside, rays in every direction hit
## something. A gap in the hull, a ceiling or the dome would let one through.
func _sealed() -> void:
	print("  hull")
	var points: Array = []
	for s in map.spawns:
		points.append((s[0] as Vector3) + Vector3(0, 1.0, 0))
	for w in map.weapon_spawns:
		points.append((w[0] as Vector3) + Vector3(0, 1.0, 0))
	for p in [Vector3(0, 3, 0), Vector3(0, 12, 0), Vector3(9, 5, 9), Vector3(0, 20, -50), Vector3(20, 25, -60), Vector3(0, 20, 60),
			Vector3(-18, 22, 40), Vector3(-45, 22, 0), Vector3(-60, 20, 18), Vector3(45, 24, 0), Vector3(40, 10, -20), Vector3(60, 3, -60),
			Vector3(-60, 3, -60), Vector3(60, 3, 60), Vector3(-63, 3, 63), Vector3(15, 3, -19), Vector3(-15, 3, 19), Vector3(0, -3, 15)]:
		points.append(p)
	var dirs: Array = []
	for i in 16:
		for j in range(-4, 5):
			var pitch := deg_to_rad(j * 21.0)
			var yaw := TAU * (i + 0.37 * j) / 16.0
			dirs.append(Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)))
	dirs.append(Vector3.UP)
	var escaped := []
	for p in points:
		for dir in dirs:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + (dir as Vector3) * 300.0))
			if hit.is_empty() and not _in_pit_or_shaft(p, dir):
				escaped.append([p, dir])
				break
	_expect(escaped.is_empty(), "nothing gets out of the hull: %d points, %d rays each %s" % [points.size(), dirs.size(), escaped.slice(0, 3)])


## The two places a ray may leave by: down the reactor pit, and down the shaft under
## the floor glass (nobody can get into that one).
func _in_pit_or_shaft(from: Vector3, dir: Vector3) -> bool:
	if dir.y > -0.01:
		return false
	var p := from + dir * ((-12.0 - from.y) / dir.y)   # where it passes below the lower deck
	return (absf(p.x) < 8.5 and p.z > 40.5 and p.z < 57.5) or Vector2(p.x, p.z).length() < 10.6


func _routes() -> void:
	print("  routes (bot navigation)")
	var started := Time.get_ticks_msec()
	var region := MapScenery.bake_navigation(map)
	root.add_child(region)
	print("    navigation baked in %d ms" % (Time.get_ticks_msec() - started))
	var nav := root.get_world_3d().navigation_map
	var probe: Vector3 = map.spawns[0][0]
	for i in 240:
		await physics_frame
		if NavigationServer3D.map_get_iteration_id(nav) > 0 and NavigationServer3D.map_get_closest_point(nav, probe).distance_to(probe) < 1.0:
			break
	var hub := NavigationServer3D.map_get_closest_point(nav, DAIS + Vector3(1.3, 0, 0))
	_expect(hub.distance_to(DAIS + Vector3(1.3, 0, 0)) < 0.6, "a bot can stand beside the terminal")
	var missed := []
	for goal_name in GOALS:
		var miss := _walk(nav, hub, GOALS[goal_name])
		if miss > 1.0:
			missed.append("%s (%.1f m short)" % [goal_name, miss])
	_expect(missed.is_empty(), "from the dais a bot can walk to every room, on every level, and back %s" % [missed])
	missed = []
	for i in map.spawns.size():
		var miss := _walk(nav, hub, map.spawns[i][0])
		if miss > 1.0:
			missed.append("spawn %d (%.1f m short)" % [i + 1, miss])
	_expect(missed.is_empty(), "every spawn point connects to the dais (and so to every other) %s" % [missed])
	missed = []
	for pair in DECK_LINKS:
		var miss := _walk(nav, pair[0], pair[1])
		if miss > 1.0:
			missed.append("%s to %s (%.1f m short)" % [pair[0], pair[1], miss])
	_expect(missed.is_empty(), "the lower deck and the main deck connect %s" % [missed])
	# Each doorway: the walk from just outside it to the dais is short, so it goes
	# through that doorway and not round by another.
	for door_name in DOORS:
		var from: Vector3 = DOORS[door_name]
		var path := NavigationServer3D.map_get_path(nav, from, hub, true)
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		var ok := not path.is_empty() and path[path.size() - 1].distance_to(hub) < 1.0 and path[0].distance_to(from) < 1.0 \
			and length < from.distance_to(hub) * 1.35 + 2.0
		_expect(ok, "the Control Room can be entered from the %s (%.0f m walk)" % [door_name, length])
	region.queue_free()
	map.queue_free()
	await process_frame


## How far short a walk from a to b, or back, ends (0 = it gets there both ways).
func _walk(nav: RID, a: Vector3, b: Vector3) -> float:
	var there := NavigationServer3D.map_get_path(nav, a, b, true)
	var back := NavigationServer3D.map_get_path(nav, b, a, true)
	var miss := 99.0 if there.is_empty() else there[there.size() - 1].distance_to(b)
	var miss_back := 99.0 if back.is_empty() else back[back.size() - 1].distance_to(a)
	return maxf(miss, miss_back)


func _expect(ok: bool, what: String) -> void:
	print("    %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1
