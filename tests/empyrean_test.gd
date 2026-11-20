extends SceneTree
## Empyrean Tower checks (game/maps/empyrean.tscn), on the map itself with no match running:
##  - listed for free-for-all (and so Gun Game) and Deathmatch; no bounds at all (leaving
##    sideways or upward is never a death); the kill height is the burn layer, about 46 m
##    (150 ft) below the root rock's lowest point, with nothing to land on in between;
##  - it is a tower: about 183 m to the eaves, more than four times Halcyon's tallest room;
##  - gravity zones: 1.0 inside the wall line on every tier, 0.4 on the balconies, the
##    docking ring, the debris and everywhere else outside;
##  - force-field doorways: drawn, never solid (a player's path and a shot's both go
##    straight through), standing on the gravity zone's edge;
##  - 20 or more spawn points, each clear and on a floor, on all six tiers, the docking
##    ring and the still islands, none that can see the rune altar;
##  - about 20 weapon pickups of 10 or more kinds, none near the altar, the heavy ones
##    outside or in the Observatory, those on orbiting chunks riding them;
##  - the rune altar and the eight ring gates are scenery: no terminal;
##  - three or four tractor-beam lifts at 9 m/s, each several tiers tall, each with a
##    bots' link to every floor it passes;
##  - the Engine's core is a hazard; the stained glass is the only thing that breaks;
##  - the shaft's grapple anchors are never more than 35 m apart; drones are scenery;
##  - routes, on the bots' navigation mesh: every tier from the one below and the one
##    above, every storey of a tier, the balconies, the docking ring, the gallery; the
##    altar from five different directions; every indoor spawn point.
## Run: godot --headless --path . --script tests/empyrean_test.gd

const ID := "empyrean"
const TIER := 30.5
const TOP := 183.0
const ALTAR := Vector3(13.523, 122.0, 3.623)     # P(14, 75 degrees) on the Summoning Chamber's floor
const NAMES := ["Arcane Engine", "Grand Library", "Alchemy Labs", "Menagerie", "Summoning Chamber", "Observatory"]

var failures := 0
var map: MapRoot
var space: PhysicsDirectSpaceState3D


func _initialize() -> void:
	print("Empyrean Tower checks")
	_run.call_deferred()


## A point `r` metres from the tower's axis at angle `deg` (0 = south, 90 = east), `y` up.
static func at(r: float, deg: float, y: float) -> Vector3:
	return Vector3(r * sin(deg_to_rad(deg)), y, r * cos(deg_to_rad(deg)))


## The wall's outer face at height y.
static func wall(y: float) -> float:
	return 30.5 - 10.5 * (clampf(y, 0.0, TOP) / TOP)


func _run() -> void:
	_expect(Maps.fits(ID, "ffa") and Maps.fits(ID, "dm") and Maps.game_of(ID) == "ffa", "listed for free-for-all (and so Gun Game) and Deathmatch")
	_expect(Maps.name_of(ID) == "Empyrean Tower", "it is called Empyrean Tower")
	map = Maps.make(ID)
	map.destructible = true
	root.add_child(map)
	var started := Time.get_ticks_msec()
	map.build(false)
	var blocks := map.find_children("*", "Node3D", true, false).filter(func(n): return n is MapBlock).size()
	print("    built in %d ms: %d blocks" % [Time.get_ticks_msec() - started, blocks])
	for i in 3:
		await physics_frame
	space = root.get_world_3d().direct_space_state
	_rules()
	_gravity()
	_fields()
	_spawns()
	_pickups()
	_objects()
	_breaks()
	_planes()
	_river()
	await _routes()
	_drawing()      # (last: it builds the map a second time, and taking that copy away clears the gravity zones)
	print("FAIL: %d checks failed" % failures if failures else "PASS: every check passed")
	quit(1 if failures else 0)


## No two drawn faces of different kinds lie in one plane, facing the same way and
## overlapping: there the graphics card cannot tell which is in front and the two
## colours flicker. (The generator settles these itself: tools/arena/empyrean_planes.py.)
func _planes() -> void:
	print("  no flicker")
	var faces := {}     # normal -> [[plane's distance, centre, u, v, half u, half v, kind, block]]
	for n in map.find_children("*", "Node3D", true, false):
		var b := n as MapBlock
		if b == null or not b.drawn:
			continue
		var xf := b.global_transform
		var half := b.size * 0.5
		var rounded := b.shape in [MapBlock.Shape.CYLINDER, MapBlock.Shape.TUBE, MapBlock.Shape.CONE, MapBlock.Shape.DOME]
		for axis in 3:
			if rounded and axis != 1:
				continue
			for way: float in [-1.0, 1.0]:
				if b.shape == MapBlock.Shape.DOME or (b.shape == MapBlock.Shape.CONE and way > 0.0 and b.top <= 0.01):
					continue
				var nrm := (xf.basis[axis] * way).normalized()
				var c := xf.origin + xf.basis[axis] * half[axis] * way
				var shrink := 0.7 if rounded else 1.0
				var key := Vector3i(roundi(nrm.x * 300), roundi(nrm.y * 300), roundi(nrm.z * 300))
				if not faces.has(key):
					faces[key] = []
				faces[key].append([nrm.dot(c), c, xf.basis[(axis + 1) % 3].normalized(), xf.basis[(axis + 2) % 3].normalized(),
					half[(axis + 1) % 3] * shrink, half[(axis + 2) % 3] * shrink, String(b.kind), b])
	var clashes := []
	for key in faces:
		var list: Array = faces[key]
		list.sort_custom(func(a, b): return a[0] < b[0])
		for i in list.size():
			var j := i + 1
			while j < list.size() and list[j][0] - list[i][0] < 0.0015:
				var A: Array = list[i]
				var B: Array = list[j]
				j += 1
				if A[6] != B[6] and A[7] != B[7] and _covers(A, B) and _covers(B, A) and clashes.size() < 8:
					clashes.append("%s and %s at %s" % [A[7].name, B[7].name, (A[1] as Vector3).snappedf(0.1)])
	_expect(clashes.is_empty(), "no two faces of different kinds share a plane %s" % [clashes])


func _covers(A: Array, B: Array) -> bool:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for su: float in [-1.0, 1.0]:
		for sv: float in [-1.0, 1.0]:
			var p: Vector3 = B[1] + B[2] * B[4] * su + B[3] * B[5] * sv - A[1]
			var q := Vector2(p.dot(A[2]), p.dot(A[3]))
			lo = lo.min(q)
			hi = hi.max(q)
	var w := minf(hi.x, A[4]) - maxf(lo.x, -A[4])
	var h := minf(hi.y, A[5]) - maxf(lo.y, -A[5])
	return w > 0.03 and h > 0.03 and w * h > 0.01


## The river of magic and the threads off it run clear of everything solid in the shaft:
## no point of any of them is inside a bridge, a rail or a floating stone, or nearer one
## than the stream is thick.
func _river() -> void:
	print("  the river")
	var worst := INF
	var where := ""
	for n in map.find_children("*", "Node3D", true, false):
		var s := n as MapMagicStream
		if s == null:
			continue
		var reach := s.width * 0.5 * 1.35 + 0.1
		var total := 0.0
		for i in range(1, s.path.size()):
			total += s.path[i].distance_to(s.path[i - 1])
		var run := 0.0
		for i in range(1, s.path.size()):
			run += s.path[i].distance_to(s.path[i - 1])
			if run < s.taper.x + 1.0 or run > total - s.taper.y - 1.0:
				continue        # (its two ends: it rises out of the core crystal's tip and pours into the pool under the Observatory, and a thread ends in its intake)
			for u: float in [0.0, 0.5]:
				var p: Vector3 = s.global_transform * s.path[i - 1].lerp(s.path[i], u)
				for dir: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
					var hit := _ray(p, p + dir * 3.0)
					var gap: float = 3.0 if hit.is_empty() else p.distance_to(hit.position)
					if hit.is_empty() and not _ray(p + dir * 3.0, p).is_empty():
						gap = 0.0       # (it started inside something: only the way back in finds the wall)
					if gap - reach < worst:
						worst = gap - reach
						where = "%s at %s" % [s.name, p.snappedf(0.1)]
	_expect(worst >= 0.0, "the river and its threads touch nothing solid (closest: %.2f m to spare, %s)" % [worst, where])


## How the map asks to be drawn: its decoration casts no shadow, and its small pieces
## are in their own meshes, a cube at a time, left out from far off.
func _drawing() -> void:
	print("  drawing")
	_expect(not map.decor_shadows and map.detail_range >= 60.0 and map.detail_chunk >= 20.0, "decoration casts no shadow; small pieces are left out beyond %d m" % int(map.detail_range))
	var built: MapRoot = Maps.make(ID)
	root.add_child(built)
	built.build(true)
	var whole := 0
	var decor := 0
	var detail := 0
	var shadowed := 0
	for c in built.get_children():
		var mesh := c as MeshInstance3D
		if mesh == null or not String(mesh.name).begins_with("Mesh_"):
			continue
		if String(mesh.name).contains("_detail_"):
			detail += 1
			if mesh.visibility_range_end <= 0.0 or mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadowed += 1
		elif String(mesh.name).ends_with("_decor"):
			decor += 1
			if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadowed += 1
		else:
			whole += 1
	_expect(whole >= 20 and decor >= 20 and detail >= 100 and shadowed == 0, "%d meshes of structure, %d of decoration, %d cubes of small pieces" % [whole, decor, detail])
	root.remove_child(built)
	built.free()
	MapRoot.current = map


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))


func _rules() -> void:
	print("  rules and size")
	_expect(not map.bounds.has_area(), "no bounds: leaving sideways or upward is never a death")
	_expect(map.winding_floors and map.bots_grapple, "its ramps wind up over themselves, and bots carry the grapple")
	# The eaves: the highest wall, and the roof's peak above it.
	var eaves := _ray(at(19.5, 10.0, 400.0), at(19.5, 10.0, 0.0))
	_expect(not eaves.is_empty() and eaves.position.y > TOP and eaves.position.y < TOP + 6.0, "the eaves are about 183 m up (%.1f m)" % (eaves.position.y if eaves else 0.0))
	_expect(TOP > 4.0 * 36.0, "more than four times the height of Halcyon's tallest room (36 m)")
	var foot := _ray(at(60.0, 5.0, 1.0), at(0.0, 5.0, 1.0))
	var top := _ray(at(60.0, 5.0, TOP - 2.0), at(0.0, 5.0, TOP - 2.0))
	_expect(absf(foot.position.distance_to(Vector3(0, 1, 0)) * 2.0 - 61.0) < 1.5 and absf(top.position.distance_to(Vector3(0, TOP - 2.0, 0)) * 2.0 - 40.0) < 2.5,
		"round, about 61 m across at its foot and 40 m at the top (%.1f, %.1f)" % [foot.position.distance_to(Vector3(0, 1, 0)) * 2.0, top.position.distance_to(Vector3(0, TOP - 2.0, 0)) * 2.0])
	# The burn layer: the kill height is 46 m (150 ft) under the root's lowest rock, with nothing between.
	var lowest := INF
	for deg in range(0, 360, 15):
		for r in [0.5, 6.0, 12.0, 18.0, 24.0, 29.0]:
			var hit := _ray(at(r, deg, map.kill_height - 5.0), at(r, deg, -1.0))
			if not hit.is_empty():
				lowest = minf(lowest, hit.position.y)
	_expect(absf((lowest - map.kill_height) - 46.0) < 4.0, "the burn layer is about 46 m (150 ft) below the root rock (%.1f m: rock %.1f, kill height %.1f)" % [lowest - map.kill_height, lowest, map.kill_height])
	var landed := []
	for deg in range(0, 360, 30):
		for r in [35.0, 60.0, 110.0, 200.0]:
			var hit := _ray(at(r, deg, lowest - 1.0), at(r, deg, map.kill_height))
			if not hit.is_empty():
				landed.append(hit.position.snapped(Vector3(0.1, 0.1, 0.1)))
	_expect(landed.is_empty(), "nothing to land on between the rock's tip and the burn layer %s" % [landed])
	var haze := map.find_children("Burn*", "Node3D", true, false).filter(func(n): return n is MapBlock)
	_expect(haze.size() >= 3 and haze.all(func(b): return not b.solid and absf(b.global_position.y - map.kill_height) < 30.0), "the burn layer is drawn there (%d glowing layers, none solid)" % haze.size())


func _gravity() -> void:
	print("  gravity zones")
	_expect(is_equal_approx(map.gravity_outside, 0.4) and map.gravity_zones.size() >= 1, "0.4 outside, with a zone filling the tower")
	var wrong := []
	for i in 6:
		for spot in [[12.0, 100.0, 1.0], [18.0, 250.0, 7.0], [wall(TIER * i + 20.0) - 2.0, 40.0, 20.0], [9.0, 180.0, 29.0]]:
			var p := at(spot[0], spot[1], TIER * i + spot[2])
			if not is_equal_approx(WorldGravity.zone_at(p), 1.0):
				wrong.append(p.snapped(Vector3(0.1, 0.1, 0.1)))
	_expect(wrong.is_empty(), "inside the tower, on every tier: 1.0 %s" % [wrong])
	wrong = []
	for p in [at(wall(0) + 3.0, 75.0, 1.0), at(wall(61) + 3.0, 213.75, 62.0), at(34.0, 100.0, 92.5), at(52.0, 255.0, 93.0), at(78.0, 75.0, 47.0),
			at(62.0, 20.0, 29.0), at(0, 0, 230.0), at(10, 0, -20.0), at(500.0, 10.0, 900.0), at(23.0, 0.0, TOP + 4.0)]:
		if not is_equal_approx(WorldGravity.zone_at(p), 0.4):
			wrong.append(p.snapped(Vector3(0.1, 0.1, 0.1)))
	_expect(wrong.is_empty(), "on the balconies, the docking ring, the pad, the debris, over the roof, under the root and far off: 0.4 %s" % [wrong])


func _fields() -> void:
	print("  force-field doorways")
	var fields := map.find_children("Field*", "Node3D", true, false).filter(func(n): return n is MapBlock and n.kind == "field")
	_expect(fields.size() >= 20, "the main openings have a force field (%d pieces)" % fields.size())
	_expect(fields.all(func(b): return not b.solid), "none of them is solid")
	var off := []
	var blocked := []
	for b in fields:
		var p: Vector3 = (b as MapBlock).global_position
		var r := Vector2(p.x, p.z).length()
		var out := Vector3(p.x, 0, p.z).normalized()
		if absf(r - (wall(p.y) - 0.2)) > 0.6:
			off.append(p.snapped(Vector3(0.1, 0.1, 0.1)))
		# The gravity changes within a pace of the field, one way and the other.
		if not (is_equal_approx(WorldGravity.zone_at(p - out * 1.2), 1.0) and is_equal_approx(WorldGravity.zone_at(p + out * 1.2), 0.4)):
			off.append(p.snapped(Vector3(0.1, 0.1, 0.1)))
		# A walk (and a shot) straight through it, at chest height, meets nothing.
		var low := Vector3(p.x, p.y - (b as MapBlock).size.y * 0.5 + 1.2, p.z)
		if not _ray(low - out * 2.5, low + out * 2.5).is_empty():
			blocked.append(p.snapped(Vector3(0.1, 0.1, 0.1)))
	_expect(off.is_empty(), "each stands in the wall line, where gravity changes: 1.0 a pace inside, 0.4 a pace outside %s" % [off])
	_expect(blocked.is_empty(), "players and projectiles pass straight through every one %s" % [blocked])


func _spawns() -> void:
	print("  spawn points")
	_expect(map.spawns.size() >= 20, "20 or more (%d)" % map.spawns.size())
	var tiers := {}
	var outside := 0
	var bad := []
	var see := []
	for i in map.spawns.size():
		var p: Vector3 = map.spawns[i][0]
		var r := Vector2(p.x, p.z).length()
		if r < wall(p.y) - 1.0 and p.y >= 0.0 and p.y < TOP:
			tiers[int(p.y / TIER)] = true
		else:
			outside += 1
		var floor_hit := _ray(p + Vector3(0, 0.5, 0), p - Vector3(0, 1.2, 0))
		var shape := PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.8
		shape.shape = capsule
		shape.transform = Transform3D(Basis(), p + Vector3(0, 1.0, 0))
		shape.collision_mask = 1
		var touching := space.intersect_shape(shape, 1)
		if floor_hit.is_empty() or not touching.is_empty():
			bad.append("spawn %d %s%s" % [i + 1, p.snapped(Vector3(0.1, 0.1, 0.1)), " no floor" if floor_hit.is_empty() else " in %s" % (touching[0].collider as Node).name])
		for target in [ALTAR + Vector3(0, 1.3, 0), ALTAR + Vector3(1.5, 1.0, 0), ALTAR + Vector3(-1.5, 1.0, 0.5)]:
			if p.distance_to(ALTAR) < 120.0 and _ray(p + Vector3(0, 1.6, 0), target).is_empty():
				see.append("spawn %d %s" % [i + 1, p.snapped(Vector3(0.1, 0.1, 0.1))])
				break
	_expect(tiers.size() == 6, "inside, on all six tiers (%s)" % [tiers.keys()])
	_expect(outside >= 4 and outside <= map.spawns.size() / 3, "a few outside, on the docking ring and the still islands (%d)" % outside)
	_expect(bad.is_empty(), "each is on a floor with room to stand %s" % [bad])
	_expect(see.is_empty(), "none can see the altar %s" % [see])
	_expect(map.open_spawns().size() == map.spawns.size(), "none rides an orbiting chunk")


func _pickups() -> void:
	print("  weapon pickups")
	var kinds := {}
	var near := []
	var bad := []
	for w in map.weapon_spawns:
		kinds[w[1]] = true
		var p: Vector3 = w[0]
		if p.distance_to(ALTAR) < 12.0:
			near.append(w[1])
		if _ray(p + Vector3(0, 0.6, 0), p - Vector3(0, 1.5, 0)).is_empty() or not _ray(p + Vector3(0, 0.3, 0), p + Vector3(0, 2.0, 0)).is_empty():
			bad.append("%s %s" % [w[1], p.snapped(Vector3(0.1, 0.1, 0.1))])
	_expect(map.weapon_spawns.size() >= 18 and map.weapon_spawns.size() <= 24, "about 20 (%d)" % map.weapon_spawns.size())
	_expect(kinds.size() >= 10, "10 or more kinds (%d)" % kinds.size())
	_expect(near.is_empty(), "none on or near the altar %s" % [near])
	_expect(bad.is_empty(), "each over a floor with room to stand %s" % [bad])
	var misplaced := []
	for w in map.weapon_spawns:
		if w[1] in ["railgun", "rocket_launcher", "anti_materiel", "plasma_cannon", "grenade_launcher", "sniper"]:
			var p: Vector3 = w[0]
			var out := is_equal_approx(WorldGravity.zone_at(p), 0.4)
			if not out and p.y < TIER * 5:
				misplaced.append(w[1])
	_expect(misplaced.is_empty(), "the power weapons are outside or in the Observatory %s" % [misplaced])
	var riding := 0
	for w in map.weapon_spawns:
		if map.mover_under(w[0]) >= 0:
			riding += 1
	_expect(riding == 3 and map.has_riders(), "three ride the orbiting chunks (%d)" % riding)


func _objects() -> void:
	print("  the altar, the gates, the lifts, the core")
	# (The altar and the ring gates are scenery: nothing is started there, nothing opens in them.)
	_expect(get_nodes_in_group(MapTerminal.GROUP).is_empty(), "no terminal: the altar and the ring gates are scenery")
	var gate_rings := map.get_node_or_null("Gates")
	_expect(gate_rings != null and gate_rings.get_child_count() == 8, "the eight ring gates still stand (%d)" % (gate_rings.get_child_count() if gate_rings else 0))
	var lifts := get_nodes_in_group(MapLiftWell.GROUP)
	_expect(lifts.size() >= 3 and lifts.size() <= 4, "three or four tractor-beam lifts (%d)" % lifts.size())
	var reach := [INF, -INF]
	for l in lifts:
		var lift := l as MapLiftWell
		_expect(is_equal_approx(lift.speed, 9.0) and lift.height > TIER * 1.9, "%s: 9 m/s, %.0f m tall (%.1f tiers)" % [lift.get_parent().name, lift.height, lift.height / TIER])
		reach[0] = minf(reach[0], lift.global_position.y)
		reach[1] = maxf(reach[1], lift.global_position.y + lift.height)
	_expect(reach[0] < 1.0 and reach[1] > TIER * 5, "between them they go from the Engine's floor to the Observatory's")
	_expect(map.hazards.size() >= 2 and map.body_in_hazard(Vector3(0, -0.8, 0)) and map.body_in_hazard(Vector3(2.5, 0.5, 0)) and not map.body_in_hazard(Vector3(6.0, 0.0, 0.0)),
		"the Engine's core and its basin are a hazard; 6 m from the middle is safe floor")
	var islands := get_nodes_in_group(MapIsland.GROUP)
	_expect(islands.size() == 3 and islands.all(func(n): return (n as MapIsland).orbit != 0.0), "three chunks of debris orbit")
	# The debris field is kept thin: the sky round the tower is for swinging through.
	var debris := map.get_node_or_null("Debris")
	var pieces := debris.get_child_count() if debris else 0
	_expect(pieces >= 20 and pieces <= 30, "20 to 30 pieces of debris float round the tower (%d)" % pieces)
	# The magic: looks only. A field, the river and a thread off it at every tier, boxes
	# of living magic everywhere, and not one of them (nor a phantom) solid.
	var fields := map.find_children("*", "Node", true, false).filter(func(n): return n is MapMagicField)
	var boxes := map.find_children("*", "Node3D", true, false).filter(func(n): return n is MapMagic)
	var streams := map.find_children("*", "Node3D", true, false).filter(func(n): return n is MapMagicStream)
	_expect(fields.size() == 1, "one magic field")
	_expect(boxes.size() >= 200 and streams.size() == 6, "%d boxes of living magic, the river and five threads off it (%d)" % [boxes.size(), streams.size()])
	var kinds := {}
	for b: MapMagic in boxes:
		kinds[b.kind] = true
	_expect(kinds.size() == MapMagic.Kind.size(), "every kind of magic is somewhere on it (%d of %d)" % [kinds.size(), MapMagic.Kind.size()])
	var stray := (boxes + streams).filter(func(n): return not n.find_children("*", "CollisionObject3D", true, false).is_empty())
	_expect(stray.is_empty(), "none of it is solid")
	var ghosts := map.find_children("*", "Node3D", true, false).filter(func(n): return n is MapBlock and String(n.kind).begins_with("phantom"))
	_expect(ghosts.size() >= 60 and ghosts.all(func(n): return not (n as MapBlock).solid), "%d phantom pieces outside, none solid" % ghosts.size())
	var sounds := map.find_children("*", "Node3D", true, false).filter(func(n): return n is MapAmbientSound)
	_expect(sounds.size() == 6 and sounds.all(func(n): return SfxList.VOLUME.has((n as MapAmbientSound).sound)), "a quiet sound of its own in each of the six tiers")
	# No floating label text anywhere on this map (a rule from the team).
	var labels := map.find_children("*", "Label3D", true, false).size()
	_expect(labels == 0, "no signs or floating text (%d)" % labels)
	# The shaft's grapple anchors: from the Engine's floor to the Observatory, never more than 35 m to the next.
	var heights := [1.5]
	for n in get_nodes_in_group(MapGrapplePoint.GROUP):
		var p := (n as MapGrapplePoint).global_position
		if Vector2(p.x, p.z).length() < 8.0:
			heights.append(p.y)
	heights.sort()
	var gap := 0.0
	for i in range(1, heights.size()):
		gap = maxf(gap, heights[i] - heights[i - 1])
	_expect(heights.size() >= 7 and gap <= 35.0 and heights[-1] > TIER * 5, "anchors up the shaft, at most %.0f m apart" % gap)
	var drones := map.find_children("*", "Node3D", true, false).filter(func(n): return n is MapDrone)
	_expect(drones.size() >= 6 and drones.all(func(d): return d.find_children("*", "CollisionObject3D", true, false).is_empty()), "%d drones, none of them solid" % drones.size())
	_expect(map.spinners.size() >= 8, "the orrery, the containment rings, the hologram and the rune rings turn (%d spinners)" % map.spinners.size())


func _breaks() -> void:
	print("  what breaks")
	var d := map.destruction
	_expect(d != null and d.breakable_count() > 0, "the map has breakable pieces")
	if d == null:
		return
	var kinds := {}
	for panel in d.panels:
		kinds[panel.kind] = true
	_expect(kinds.keys() == ["glass_stained"], "only the stained glass breaks (%s)" % [kinds.keys()])
	_expect(d.breakable_count() >= 6, "several windows (%d pieces)" % d.breakable_count())


func _walk(nav: RID, from: Vector3, to: Vector3) -> float:
	var path := NavigationServer3D.map_get_path(nav, from, to, true)
	return INF if path.is_empty() else path[path.size() - 1].distance_to(to)


func _routes() -> void:
	print("  routes (bot navigation)")
	var started := Time.get_ticks_msec()
	var region := MapScenery.bake_navigation(map)
	root.add_child(region)
	print("    navigation baked in %d ms" % (Time.get_ticks_msec() - started))
	var nav := root.get_world_3d().navigation_map
	var probe := at(9.3, 285.0, 0.0)
	for i in 600:
		await physics_frame
		if NavigationServer3D.map_get_iteration_id(nav) > 0 and NavigationServer3D.map_get_closest_point(nav, probe).distance_to(probe) < 1.0:
			break
	var floors := []
	for i in 6:
		floors.append(at(9.3, 285.0, TIER * i))
	var missed := []
	for i in 5:
		for pair in [[floors[i], floors[i + 1]], [floors[i + 1], floors[i]]]:
			var miss := _walk(nav, pair[0], pair[1])
			if miss > 1.5:
				missed.append("%s to %s (%.1f m short)" % [NAMES[i] if pair[0] == floors[i] else NAMES[i + 1], NAMES[i + 1] if pair[0] == floors[i] else NAMES[i], miss])
	_expect(missed.is_empty(), "every tier can be walked to from the one below and from the one above, so from the Engine and from the Observatory %s" % [missed])
	missed = []
	for i in 5:
		var y := TIER * i
		var goals := {"corridor 6 m": at(wall(y + 30.5) - 5.0, 262.0, y + 6.35), "corridor 13 m": at(wall(y + 30.5) - 5.0, 262.0, y + 12.7),
			"rooms 6 m": at(13.0, 320.0, y + 6.35), "rooms 13 m": at(13.0, 200.0, y + 12.7), "upper hall": at(14.0, 60.0, y + 19.0),
			"balcony 6 m": at(wall(y + 30.5) - 3.0, 70.0, y + 6.35), "high balcony": at(wall(y + 30.5) - 3.0, 20.0, y + 12.7)}
		if i != 3:
			goals["outside the great arch"] = at(wall(y) + 2.5, 75.0, y)
			goals["north balcony"] = at(wall(y) + 2.0, 213.75, y)
		for goal in goals:
			var miss := _walk(nav, floors[i], goals[goal])
			if miss > 1.5:
				missed.append("%s: %s (%.1f m short)" % [NAMES[i], goal, miss])
	_expect(missed.is_empty(), "every storey, balcony and upper hall of every tier %s" % [missed])
	missed = []
	for goal in [["the docking ring", floors[3], at(33.0, 120.0, 91.5)], ["the landing pad", floors[3], at(44.0, 240.0, 91.5)],
			["the Observatory's gallery", floors[5], at(17.5, 60.0, 161.5)], ["the Observatory's balcony", floors[5], at(wall(152.5) + 2.5, 75.0, 152.5)],
			["the apron at the tower's foot", floors[0], at(32.5, 160.0, 0.0)]]:
		var miss := _walk(nav, goal[1], goal[2])
		if miss > 1.5:
			missed.append("%s (%.1f m short)" % [goal[0], miss])
	_expect(missed.is_empty(), "the docking ring, the pad, the gallery, the balconies %s" % [missed])
	# The altar: reached from every side.
	var beside := NavigationServer3D.map_get_closest_point(nav, ALTAR + Vector3(0, 0.2, 2.0))
	_expect(beside.distance_to(ALTAR + Vector3(0, 0.2, 2.0)) < 0.8, "a bot can stand beside the altar")
	var ways := {"the corridor's south end": at(18.0, 160.0, 122.0), "the corridor's north end": at(18.0, 350.0, 122.0), "the balcony outside the arch": at(wall(122.0) + 2.5, 75.0, 122.0),
		"the Menagerie below": floors[3], "the Observatory above": floors[5], "the balcony over it": at(wall(152.5) - 3.0, 75.0, 128.35)}
	missed = []
	for way in ways:
		var miss := _walk(nav, ways[way], beside)
		if miss > 1.5:
			missed.append("%s (%.1f m short)" % [way, miss])
	_expect(missed.is_empty(), "the altar can be walked to from %d directions %s" % [ways.size(), missed])
	missed = []
	for i in map.spawns.size():
		var p: Vector3 = map.spawns[i][0]
		if is_equal_approx(WorldGravity.zone_at(p + Vector3(0, 1, 0)), 0.4) and Vector2(p.x, p.z).length() > 40.0:
			continue      # (the still islands: a grapple swing away, by a jump link)
		var tier_floor: Vector3 = floors[clampi(int(p.y / TIER), 0, 5)]
		var miss := _walk(nav, tier_floor, p)
		if miss > 1.5:
			missed.append("spawn %d %s (%.1f m short)" % [i + 1, p.snapped(Vector3(0.1, 0.1, 0.1)), miss])
	_expect(missed.is_empty(), "every spawn point on the tower connects to its tier's floor %s" % [missed])
	# The bots' links: lifts to every floor they pass, gates, and the ways back from the spawn islands.
	var kinds := {}
	missed = []
	for n in get_nodes_in_group(MapJumpLink.GROUP):
		var link := n as MapJumpLink
		kinds[link.how] = kinds.get(link.how, 0) + 1
		for p in [link.takeoff(), link.landing_point()]:
			if NavigationServer3D.map_get_closest_point(nav, p).distance_to(p) > 1.2:
				missed.append("%s/%s %s" % [link.get_parent().name, link.name, p.snapped(Vector3(0.1, 0.1, 0.1))])
	_expect(kinds.get(MapJumpLink.How.LIFT, 0) >= 8 and kinds.get(MapJumpLink.How.GRAPPLE, 0) == 3 and kinds.size() == 2,
		"bots are told about the lifts (%d stops) and the three ways back from the spawn islands" % kinds.get(MapJumpLink.How.LIFT, 0))
	_expect(missed.is_empty(), "every link starts and ends on floor a bot can stand on %s" % [missed])


func _expect(ok: bool, what: String) -> void:
	print("    %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1
