class_name Blink
extends RefCounted
## Blink: a short teleport where you look (or, for bots, a direction they choose).
##
## You keep the speed you had, and get at least BLINK_PUSH along the blink so it
## feels like a dash; falling speed is cancelled. The body is swept along the way
## first, so a blink stops short of a wall instead of going through it. One
## charge, back RECHARGE seconds after you use it.

const RANGE := 11.0
const CHARGES := 1
const RECHARGE := 2.4     ## seconds per charge
const GAP := 0.22         ## seconds between two blinks
const MIN_DISTANCE := 1.2 ## a blink that would go less far than this (a wall in your face) is refused
const BLINK_PUSH := 6.0   ## at least this much speed along the blink afterwards
const COLOR := Color(0.25, 0.7, 1.0)   ## its flash, its trail and its HUD marks

var charges := CHARGES
var _recharge := 0.0
var _gap := 0.0


func update(delta: float) -> void:
	_gap = maxf(_gap - delta, 0.0)
	if charges < CHARGES:
		_recharge += delta
		if _recharge >= RECHARGE:
			_recharge -= RECHARGE
			charges += 1
	else:
		_recharge = 0.0


func ready() -> bool:
	return charges > 0 and _gap <= 0.0


## 0..1: charges, with the one coming back counted in part (the HUD's bar).
func readiness() -> float:
	if charges >= CHARGES:
		return 1.0
	return (charges + _recharge / RECHARGE) / float(CHARGES)


## How far the next charge has come back, 0..1 (1 when full).
func recharge_progress() -> float:
	return 1.0 if charges >= CHARGES else _recharge / RECHARGE


func reset() -> void:
	charges = CHARGES
	_recharge = 0.0
	_gap = 0.0


## Where a blink along `dir` from the body's feet ends: the body's own shape swept
## through the level (other players are passed through). Returns INF when there is
## no room to go.
static func destination(body: CharacterBody3D, shape: CollisionShape3D, dir: Vector3) -> Vector3:
	if dir.length_squared() < 0.0001:
		return Vector3.INF
	dir = dir.normalized()
	var space := body.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape.shape
	q.transform = shape.global_transform.translated(Vector3(0, 0.06, 0))   # clear of the floor it stands on
	q.motion = dir * RANGE
	q.collision_mask = 1
	q.exclude = [body.get_rid()]
	q.margin = 0.02
	var parts := space.cast_motion(q)
	var safe: float = parts[0] if parts.size() > 0 else 1.0
	var dist := maxf(safe * RANGE - 0.08, 0.0)
	# The sweep misses anything the body already touches when it sets off (a wall
	# you are pressed against): rays through the middle of the body catch those.
	var r := (shape.shape as CapsuleShape3D).radius if shape.shape is CapsuleShape3D else 0.4
	for h in [0.35, 0.5, 0.65]:
		var height := (shape.shape as CapsuleShape3D).height if shape.shape is CapsuleShape3D else 1.8
		var from := body.global_position + Vector3(0, height * h, 0)
		var ray := PhysicsRayQueryParameters3D.create(from, from + dir * (dist + r), 1, [body.get_rid()])
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			dist = minf(dist, from.distance_to(hit.position) - r - 0.1)
	# Never end inside something: back off until the body fits.
	var fit := PhysicsShapeQueryParameters3D.new()
	fit.shape = shape.shape
	fit.collision_mask = 1
	fit.exclude = [body.get_rid()]
	while dist >= MIN_DISTANCE:
		fit.transform = q.transform.translated(dir * dist)
		if space.intersect_shape(fit, 1).is_empty():
			break
		dist -= 0.4
	if dist < MIN_DISTANCE:
		return Vector3.INF
	return body.global_position + dir * dist


## Velocity after a blink along `dir`.
static func carry(vel: Vector3, dir: Vector3) -> Vector3:
	dir = dir.normalized()
	if vel.y < 0.0:
		vel.y = 0.0
	var along := vel.dot(dir)
	if along < BLINK_PUSH:
		vel += dir * (BLINK_PUSH - along)
	return vel


## A quick burst of light where someone blinked from, and where they arrived (visual only).
static func flash(parent: Node, at: Vector3) -> void:
	if parent == null:
		return
	var m := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.7
	sphere.height = 1.8
	sphere.radial_segments = 12
	sphere.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(COLOR, 0.7)
	sphere.material = mat
	m.mesh = sphere
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.top_level = true
	parent.add_child(m)
	m.global_position = at
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3(0.15, 1.4, 0.15), 0.28)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.28)
	tw.chain().tween_callback(m.queue_free)


## A stream of sparks that flies from where you set off to where you land, leaving a
## fading trail along the way (visual only).
static func trail(parent: Node, from: Vector3, to: Vector3) -> void:
	if parent == null:
		return
	const TRAVEL := 0.16   # seconds for the sparks to reach where you land
	var fx := CPUParticles3D.new()
	fx.name = "BlinkTrail"
	fx.top_level = true
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	fx.mesh = mesh
	fx.amount = 90
	fx.lifetime = 0.45
	fx.explosiveness = 0.0
	fx.local_coords = false   # sparks stay where they were dropped as the emitter flies on
	fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fx.emission_sphere_radius = 0.35
	fx.direction = Vector3.UP
	fx.spread = 180.0
	fx.gravity = Vector3.ZERO
	fx.initial_velocity_min = 0.3
	fx.initial_velocity_max = 1.2
	fx.damping_min = 1.0
	fx.damping_max = 2.0
	fx.scale_amount_min = 0.6
	fx.scale_amount_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(COLOR.lightened(0.6), 1.0))
	fade.set_color(1, Color(COLOR, 0.0))
	fx.color_ramp = fade
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))
	fx.scale_amount_curve = shrink
	parent.add_child(fx)
	fx.global_position = from
	fx.emitting = true
	var tw := fx.create_tween()
	tw.tween_property(fx, "global_position", to, TRAVEL).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func(): fx.emitting = false)
	tw.tween_interval(fx.lifetime + 0.1)
	tw.tween_callback(fx.queue_free)
