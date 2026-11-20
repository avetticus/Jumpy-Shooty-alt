class_name AirBlast
## The air cannon's blast (WeaponData.Kind.BLAST): who it shoves and how hard, and how
## it looks. The host decides who it shoves (Match._host_blast); nothing here needs the
## game's autoloads, so the headless checks (tests/air_cannon_test.gd) run it as it is.
##
## The blast reaches everyone in a cone in front of the shooter (WeaponData.max_range
## metres, cone_degrees either side of where they look) whom the level does not hide,
## and pushes each one away along the line from the shooter to them, with a lift that
## takes them off their feet (WeaponData.blast_knockback: harder the more it was charged,
## and the closer they are). It does no damage at all: only the wall they hit does.

const BODY_RADIUS := 0.4    ## Player.CAPSULE_RADIUS (copied, so this loads without the game)
const DOWN_LIMIT := -0.2    ## blasting down at someone pushes them along the floor, not into it (the lift still wins)
const STREAKS := 8          ## streaks of air drawn round the cone (and one down the middle)
const AIR := Color(0.85, 0.95, 1.0)


## Who a blast from `origin` along `direction` charged `charge` (0..1) shoves:
## [{id, push, at, dist}] for each of `bodies` ([id, feet, height, ...], as
## Match._rewound_bodies gives them) inside the cone and in sight. `clear` is
## Callable(from, to) -> bool: true when nothing of the level is in between.
static func hits(origin: Vector3, direction: Vector3, bodies: Array, w: WeaponData, charge: float, clear: Callable) -> Array:
	direction = direction.normalized()
	var out := []
	for b in bodies:
		var feet: Vector3 = b[1]
		var height: float = b[2]
		var low := feet + Vector3(0, BODY_RADIUS, 0)
		var top := feet + Vector3(0, height - BODY_RADIUS, 0)
		# The part of the body nearest the middle of the cone.
		var at: Vector3 = Geometry3D.get_closest_points_between_segments(origin, origin + direction * w.max_range, low, top)[1]
		var to := at - origin
		var length := to.length()
		var dist := maxf(length - BODY_RADIUS, 0.0)
		if dist > w.max_range:
			continue
		if length > 0.001:
			var edge := rad_to_deg(asin(clampf(BODY_RADIUS / length, 0.0, 1.0)))   # (the side of the body counts)
			if rad_to_deg(direction.angle_to(to)) > w.cone_degrees + edge:
				continue
		# Behind a wall: if the air can reach none of them (that part, the middle, the head).
		if not (clear.call(origin, at) or clear.call(origin, feet + Vector3(0, height * 0.5, 0)) or clear.call(origin, top)):
			continue
		var way := to / length if length > 0.001 else direction
		way.y = maxf(way.y, DOWN_LIMIT)
		way = way.normalized()
		var push: Array = w.blast_knockback(charge, dist)
		out.append({"id": b[0], "push": way * float(push[0]) + Vector3.UP * float(push[1]), "at": at, "dist": dist})
	return out


## Where the blast's streaks of air end, for the effect everyone sees: the first down the
## middle, then STREAKS round the cone, out to a reach that grows with the charge and
## stopped by the level.
static func fan(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3, w: WeaponData, charge: float,
		exclude: Array[RID] = []) -> PackedVector3Array:
	direction = direction.normalized()
	var reach := w.max_range * lerpf(0.45, 1.0, clampf(charge, 0.0, 1.0))
	var side := direction.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
	var up := side.cross(direction).normalized()
	var tilt := deg_to_rad(w.cone_degrees * 0.75)
	var ends := PackedVector3Array()
	for i in STREAKS + 1:
		var dir := direction
		if i > 0:
			var around := TAU * float(i - 1) / STREAKS
			dir = (direction * cos(tilt) + (side * cos(around) + up * sin(around)) * sin(tilt)).normalized()
		var end := origin + dir * reach
		if space:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, end, 1, exclude))
			if hit:
				end = hit.position
		ends.append(end)
	return ends


## The blast going off (ShotFx draws its streaks): rings of air that rush out along the
## cone, widening as they go, as far as the middle streak (`ends[0]`) went.
static func burst(parent: Node, muzzle: Vector3, ends: PackedVector3Array, w: WeaponData) -> void:
	if DisplayServer.get_name() == "headless" or not is_instance_valid(parent) or ends.is_empty():
		return
	var to := ends[0] - muzzle
	var reach := to.length()
	if reach < 0.3:
		return
	var dir := to / reach
	var x := (Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT).cross(dir).normalized()
	var basis := Basis(x, dir, x.cross(dir).normalized())   # (a torus lies round its Y axis)
	var widen := tan(deg_to_rad(w.cone_degrees))
	for k in 3:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.82
		torus.outer_radius = 1.0
		torus.rings = 24
		torus.ring_segments = 6
		ring.mesh = torus
		ring.material_override = ShotFx._glow(Color(AIR, 0.55 - 0.12 * k))
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(ring)
		ring.global_transform = Transform3D(basis, muzzle + dir * 0.3)
		ring.scale = Vector3.ONE * 0.12
		var far := reach * (0.5 + 0.25 * k)
		var life := 0.16 + 0.07 * k
		var tw := ring.create_tween().set_parallel()
		tw.tween_property(ring, "global_position", muzzle + dir * far, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(ring, "scale", Vector3.ONE * maxf(widen * far, 0.3), life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(ring, "transparency", 1.0, life)
		tw.chain().tween_callback(ring.queue_free)


## The glow that swells at the muzzle while a blast charges (each Player keeps one).
static func make_glow() -> MeshInstance3D:
	var glow := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 12
	s.rings = 6
	glow.mesh = s
	glow.material_override = ShotFx._glow(AIR)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.top_level = true
	glow.visible = false
	return glow


## Puts `glow` at `at`, charged `charge` 0..1 (below 0: not charging, hidden). Fully
## charged, it throbs. `small`: your own, in first person (it sits right before your eyes).
static func show_glow(glow: MeshInstance3D, at: Vector3, charge: float, small: bool) -> void:
	glow.visible = charge >= 0.0
	if not glow.visible:
		return
	var throb := 1.0 + (0.15 * sin(Time.get_ticks_msec() * 0.025) if charge >= 1.0 else 0.0)
	glow.global_position = at
	glow.scale = Vector3.ONE * lerpf(0.03, 0.17, charge) * (0.4 if small else 1.0) * throb
	glow.transparency = lerpf(0.75, 0.2, charge)
