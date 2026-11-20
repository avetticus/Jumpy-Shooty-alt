class_name Projectile
extends Node3D
## A rocket, grenade, flare, mortar shell, ball of plasma, nail or crossbow bolt in flight, as everyone sees it. The host follows its own copy
## of the same flight in Match and decides where it blows up; this one is the look:
## a body with a glowing tail and a trail of smoke (a bolt: a streak, BoltTrail), flying the same path (the same
## start, speed and drop), drawn out of the muzzle and onto the real path in a moment.

const BLEND := 0.12   ## seconds to slide from the muzzle onto the real flight path
const SHOT_EXIT := 0.03   ## Portals.SHOT_EXIT: out of a portal this far in front of it

var id := 0
var weapon: WeaponData
var _pos := Vector3.ZERO      # on the real path (from the eyes)
var _vel := Vector3.ZERO
var _offset := Vector3.ZERO   # muzzle minus eyes, shrinking to nothing
var _t := 0.0
var _smoke_t := 0.0
var _color := Color.WHITE
var _trail: BoltTrail          # a bolt's streak (beside it, in the same parent, so it can outlast it)


static func make(projectile_id: int, data: WeaponData, origin: Vector3, direction: Vector3, muzzle: Vector3, color: Color) -> Projectile:
	var p := Projectile.new()
	p.id = projectile_id
	p.weapon = data
	p.name = "Projectile_%d" % projectile_id
	p._pos = origin
	p._vel = direction.normalized() * data.projectile_speed
	p._offset = muzzle - origin if muzzle != Vector3.INF else Vector3.ZERO
	p._color = color
	p._build(color)
	return p


func _ready() -> void:
	if weapon.look() == "bolt":
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
	match weapon.look():
		"rocket":
			_rocket(color)
		"flare":
			_glowing(0.06, Color(1.0, 0.35, 0.2), 6.0, Color(1.0, 0.4, 0.25), 3.0, 9.0)
		"orb":
			_glowing(0.16, Color(0.45, 0.7, 1.0), 4.0, Color(0.5, 0.75, 1.0), 2.0, 5.0)
		"nail":
			_dart(0.006, 0.16, color, 0.0)
		"bolt":
			_dart(0.012, 0.55, color, 0.07)
		"shell":
			_shell(color, 0.11)
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


## A grenade (or a mortar shell): a ball in the player's colour.
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


## A flare or a ball of plasma: all light, and it lights up what it passes.
func _glowing(radius: float, color: Color, energy: float, light: Color, light_energy: float, reach: float) -> void:
	_light_ball(radius, color, energy)
	_light_ball(radius * 1.8, Color(color, 0.35), energy * 0.5)
	_lamp(light, light_energy, reach)


## A nail or a crossbow bolt: a thin shaft along -Z, fletched (a bolt) in the player's colour.
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


## A step from `from` to `to` (moving at `vel`) that goes into a portal (`gate`, from
## Portals.crossing): where it ends up and how it is moving, [position, velocity], out
## of the other portal with the rest of the step. Host and look use the same sum.
static func through_portal(gate: Dictionary, from: Vector3, to: Vector3, vel: Vector3) -> Array:
	# (Untyped, and SHOT_EXIT by value: Portal and Portals need the game's autoloads, and
	# tests load this script without them.)
	var into = gate.from
	var out = gate.to
	var rest: Vector3 = (to - from) * (1.0 - float(gate.t))
	var v: Vector3 = into.carry(out, vel)
	var at: Vector3 = into.carry_point(out, gate.at) + out.normal * SHOT_EXIT + into.carry(out, rest)
	return [at, v]


## Where the host's copy would be after `t` seconds (the same sum, step by step).
func _physics_process(delta: float) -> void:
	_t += delta
	_vel.y -= weapon.projectile_gravity * delta
	var to := _pos + _vel * delta
	var gate := {}
	# (Net by its path, not its name: tests load this script without the game's autoloads.)
	var net := get_node_or_null("/root/Net")
	var arena: Node = net.arena if net else null
	var portals = arena.get("portals") if arena and is_instance_valid(arena) else null
	if portals and arena.is_ancestor_of(self):
		gate = portals.crossing(_pos, to)
	if gate:
		gate.from.ripple()
		gate.to.ripple()
		var through := through_portal(gate, _pos, to, _vel)
		_pos = through[0]
		_vel = through[1]
		_offset = Vector3.ZERO   # (no more drawing it out of the muzzle)
		if is_instance_valid(_trail):
			_trail.cut()
	else:
		_pos = to
	var k := clampf(1.0 - _t / BLEND, 0.0, 1.0)
	global_position = _pos + _offset * k
	if _vel.length_squared() > 0.01:
		# Nose along the way it is going: a falling bolt tips nose down as it drops.
		look_at(global_position + _vel, Vector3.UP if absf(_vel.normalized().y) < 0.99 else Vector3.RIGHT)
	if is_instance_valid(_trail):
		_trail.follow(_tail(), delta)
	_smoke_t -= delta
	if _smoke_t <= 0.0 and DisplayServer.get_name() != "headless" and weapon.explosive and weapon.look() != "orb":
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
