class_name Projectile
extends Node3D
## A rocket, grenade or crossbow bolt in flight, as everyone sees it. The host follows its own copy
## of the same flight in Match and decides where it blows up; this one is the look:
## a body with a glowing tail and a trail of smoke (a bolt: a streak, BoltTrail), flying the same path (the same
## start, speed and drop), drawn out of the muzzle and onto the real path in a moment.
##
## A sticky grenade (the grenade launcher's alt fire, WeaponData.alt "sticky") flies the
## same arc but sticks to the first thing it touches instead of going off. The host says
## where (stick: a spot in the map, on a moving part of it, or on a player, whom it then
## rides), when it is armed (arm), and when it goes off (Match.exploded) or just goes
## (Match.projectile_gone). It looks different: a dark puck with a light that blinks,
## faster once armed. The numbers the host plays it by are here too.

const BLEND := 0.12   ## seconds to slide from the muzzle onto the real flight path
## Sticky grenades: seconds from sticking until it is armed...
const STICKY_ARM := 0.5
## ...then it goes off when an enemy (never its owner or a teammate) comes this close
## (metres to the outside of their body, in sight of it); stuck on an enemy, at once.
const STICKY_REACH := 3.0
## A player has at most this many out; firing another takes their oldest away (no blast).
const STICKY_MAX := 3
const BLINK_SLOW := 0.9   ## seconds between a sticky's blinks before it is armed...
const BLINK_FAST := 0.22  ## ...and once it is
const BLINK_ON := 0.07    ## how long each blink is lit

var id := 0
var weapon: WeaponData
var _pos := Vector3.ZERO      # on the real path (from the eyes)
var _vel := Vector3.ZERO
var _offset := Vector3.ZERO   # muzzle minus eyes, shrinking to nothing
var _t := 0.0
var _smoke_t := 0.0
var _color := Color.WHITE
var _trail: BoltTrail          # a bolt's streak (beside it, in the same parent, so it can outlast it)
var sticky := false            ## a sticky grenade (see STICKY_ARM)
var stuck := false             ## ...that has stuck to something (it flies no more)
var armed := false             ## ...and is armed
var _ride: Node3D              # stuck on this (a player's body, a moving part of the map), or null: it stays put
var _on := Transform3D.IDENTITY   # where it sits on _ride (in _ride's frame), its +Y out of the surface
var _blink_t := 0.0
var _blink: Array = []         # the blinking light: its ball and its lamp


static func make(projectile_id: int, data: WeaponData, origin: Vector3, direction: Vector3, muzzle: Vector3, color: Color, is_sticky: bool = false) -> Projectile:
	var p := Projectile.new()
	p.id = projectile_id
	p.weapon = data
	p.sticky = is_sticky
	p.name = "Projectile_%d" % projectile_id
	p._pos = origin
	p._vel = direction.normalized() * data.projectile_speed
	p._offset = muzzle - origin if muzzle != Vector3.INF else Vector3.ZERO
	p._color = color
	p._build(color)
	return p


## How it looks: the weapon's (WeaponData.look()), or "sticky" for a sticky grenade.
func look() -> String:
	return "sticky" if sticky else weapon.look()


func _ready() -> void:
	if look() == "bolt":
		_add_trail.call_deferred()   # (the parent may still be busy adding us)


## A bolt's streak, made only once the bolt is in the world (so none is left behind
## by a bolt that never was).
func _add_trail() -> void:
	var parent := get_parent()
	if parent == null or not is_inside_tree() or is_queued_for_deletion():
		return
	var tint := weapon.tracer_color if weapon.tracer_color.a > 0.0 else _color
	_trail = BoltTrail.new().setup(tint)
	parent.add_child(_trail)
	if _t > 0.0:   # (before its first step it is not where it flies yet)
		_trail.follow(_tail(), 0.0)


func _exit_tree() -> void:
	if is_instance_valid(_trail):
		_trail.release()   # landed or gone: the streak fades out on its own


## The back end of the body (the nose points along -Z).
func _tail() -> Vector3:
	return global_position + global_basis.z * 0.25


func _build(color: Color) -> void:
	match look():
		"rocket":
			_rocket(color)
		"bolt":
			_dart(0.012, 0.55, color, 0.07)
		"sticky":
			_sticky(color)
		_:
			_shell(color, 0.07)


func _metal(color: Color, glow: float = 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.32, 0.35)
	m.metallic = 0.6
	m.roughness = 0.4
	m.emission_enabled = glow > 0.0
	m.emission = color
	m.emission_energy_multiplier = glow
	return m


func _light_ball(radius: float, color: Color, energy: float, at: Vector3 = Vector3.ZERO) -> void:
	var glow := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 8
	s.rings = 4
	glow.mesh = s
	var g := StandardMaterial3D.new()
	g.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	g.albedo_color = color
	g.emission_enabled = true
	g.emission = color
	g.emission_energy_multiplier = energy
	glow.material_override = g
	glow.position = at
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)


func _lamp(color: Color, energy: float, reach: float, at: Vector3 = Vector3.ZERO) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.position = at
	add_child(light)


## A rocket: a tapered body with a glowing tail.
func _rocket(color: Color) -> void:
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.045
	cyl.height = 0.42
	cyl.radial_segments = 8
	body.mesh = cyl
	body.rotation = Vector3(-PI / 2.0, 0.0, 0.0)   # the nose along -Z
	body.material_override = _metal(color)
	add_child(body)
	_light_ball(0.09, Color(1.0, 0.6, 0.2), 4.0, Vector3(0, 0, 0.24))
	_lamp(Color(1.0, 0.6, 0.25), 1.6, 4.0, Vector3(0, 0, 0.24))


## A grenade: a ball in the player's colour.
func _shell(color: Color, radius: float) -> void:
	var body := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = radius
	ball.height = radius * 2.0
	ball.radial_segments = 10
	ball.rings = 5
	body.mesh = ball
	body.material_override = _metal(color)
	add_child(body)
	_light_ball(radius * 0.7, color, 4.0)


## A sticky grenade: a dark, squat puck with a band in the player's colour and a red
## light on top (its +Y, which faces out of whatever it sticks to) that blinks.
func _sticky(color: Color) -> void:
	var body := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.075
	ball.height = 0.09
	ball.radial_segments = 10
	ball.rings = 5
	body.mesh = ball
	var dark := _metal(color, 0.15)
	dark.albedo_color = Color(0.12, 0.13, 0.14)
	body.material_override = dark
	add_child(body)
	var band := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.068
	ring.outer_radius = 0.084
	ring.rings = 12
	ring.ring_segments = 4
	band.mesh = ring
	band.material_override = _metal(color, 1.2)
	add_child(band)
	var red := Color(1.0, 0.12, 0.08)
	_light_ball(0.018, red, 6.0, Vector3(0, 0.045, 0))
	_lamp(red, 0.8, 1.6, Vector3(0, 0.08, 0))
	_blink = [get_child(get_child_count() - 2), get_child(get_child_count() - 1)]
	_show_blink(false)


func _show_blink(on: bool) -> void:
	for node in _blink:
		(node as Node3D).visible = on


## The host says it stuck. `how` is what Match sends (see Match._host_stick): `at` and
## `normal` in the world and, when it rides something, `local` and `up` in that thing's
## frame. `ride` is that thing on this copy (a player's body, turned with their yaw; a
## moving part of the map), or null to stay at `at`.
func stick(how: Dictionary, ride: Node3D = null) -> void:
	stuck = true
	_vel = Vector3.ZERO
	_offset = Vector3.ZERO
	_ride = ride
	if ride:
		_on = Transform3D(_facing(how.get("up", Vector3.UP)), how.get("local", Vector3.ZERO))
		global_transform = ride.global_transform * _on
	else:
		global_transform = Transform3D(_facing(how.get("normal", Vector3.UP)), how.get("at", global_position))
	_pos = global_position


## Armed (the host says): it blinks faster.
func arm() -> void:
	armed = true
	_blink_t = 0.0


## A basis with its +Y along `up`.
static func _facing(up: Vector3) -> Basis:
	up = up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
	var side := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := up.cross(side).normalized()
	return Basis(x, up, x.cross(up))


## The part of `map` a sticky stuck to, which it rides (the host names it by its path
## in the map, `how.frame`), or null if there is none or this copy has no such part.
static func frame_in(map: Node, how: Dictionary) -> Node3D:
	var path := str(how.get("frame", ""))
	if path == "" or map == null:
		return null
	return map.get_node_or_null(NodePath(path)) as Node3D


## A crossbow bolt: a thin shaft along -Z, fletched in the player's colour.
func _dart(radius: float, length: float, color: Color, fletch: float) -> void:
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.3
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 6
	body.mesh = cyl
	body.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	body.material_override = _metal(color, 0.2)
	add_child(body)
	if fletch > 0.0:
		for i in 3:
			var fin := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.002, fletch * 0.6, fletch)
			fin.mesh = b
			var m := StandardMaterial3D.new()
			m.albedo_color = color
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = 0.8
			fin.material_override = m
			fin.rotation = Vector3(0, 0, TAU * i / 3.0)
			fin.position = Vector3(0, 0, length * 0.5 - fletch * 0.5)
			add_child(fin)


## Where the host's copy would be after `t` seconds (the same sum, step by step).
func _physics_process(delta: float) -> void:
	if sticky:
		_blink_t += delta
		_show_blink(fmod(_blink_t, BLINK_FAST if armed else BLINK_SLOW) < BLINK_ON)
	if stuck:
		if _ride and is_instance_valid(_ride) and _ride.is_inside_tree():
			global_transform = _ride.global_transform * _on   # (riding a player, or a part of the map that moves)
		return   # no fuse once it is stuck: it waits for the host
	_t += delta
	_vel.y -= weapon.projectile_gravity * delta
	_pos += _vel * delta
	var k := clampf(1.0 - _t / BLEND, 0.0, 1.0)
	global_position = _pos + _offset * k
	if _vel.length_squared() > 0.01:
		# Nose along the way it is going: a falling bolt tips nose down as it drops.
		look_at(global_position + _vel, Vector3.UP if absf(_vel.normalized().y) < 0.99 else Vector3.RIGHT)
	if is_instance_valid(_trail):
		_trail.follow(_tail(), delta)
	_smoke_t -= delta
	if _smoke_t <= 0.0 and DisplayServer.get_name() != "headless" and weapon.explosive and not sticky:
		_smoke_t = 0.025 if weapon.projectile_gravity <= 0.0 else 0.05
		_puff()
	if _t > weapon.fuse + 1.0:
		queue_free()   # the host never said: give up


func _puff() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var mesh := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.09
	s.height = 0.18
	s.radial_segments = 6
	s.rings = 3
	mesh.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.8, 0.8, 0.8, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = m
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	mesh.global_position = global_position - _vel.normalized() * 0.25
	var tw := mesh.create_tween().set_parallel()
	tw.tween_property(mesh, "scale", Vector3.ONE * 3.0, 0.6)
	tw.tween_property(mesh, "transparency", 1.0, 0.6)
	tw.chain().tween_callback(mesh.queue_free)
