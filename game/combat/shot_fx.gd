class_name ShotFx
## Placeholder shot effects: tracer line, muzzle flash and impact puff.
## Simple shapes for now; real effects come with the art pass.


## One shot: a tracer and an impact for each pellet (`ends`, `hits`: one per pellet),
## and a muzzle flash sized for the gun. `vias`: per pellet, where it went into and came
## out of portals ([in, out, ...]; see Portals.path_bends): its tracer goes through them.
static func spawn(parent: Node, muzzle: Vector3, ends: PackedVector3Array, hits: Array, weapon: String = "pistol", vias: Array = []) -> void:
	if DisplayServer.get_name() == "headless" or not is_instance_valid(parent):
		return
	weapon = WeaponData.look_of(weapon)
	var flash: float = {"shotgun": 0.2, "rifle": 0.11, "sniper": 0.22, "break_action": 0.24, "revolver": 0.16,
		"lever_action": 0.16, "bolt_action": 0.2, "railgun": 0.26, "lmg": 0.13, "smg": 0.09, "machine_pistol": 0.08, "akimbo": 0.1,
		"derringer": 0.14, "air_cannon": 0.05, "minigun": 0.12, "battle_rifle": 0.14,
		"laser_rifle": 0.05, "anti_materiel": 0.32}.get(weapon, 0.12)
	var width: float = {"shotgun": 0.009, "break_action": 0.009, "sniper": 0.028, "bolt_action": 0.022,
		"railgun": 0.05, "air_cannon": 0.03, "laser_rifle": 0.012,
		"anti_materiel": 0.035}.get(weapon, 0.015)
	var color := Color(1.0, 0.85, 0.5)
	if weapon in ["sniper", "bolt_action"]:
		color = Color(0.75, 0.9, 1.0)
	elif weapon == "railgun":
		color = Color(0.35, 0.95, 1.0)
	var data := WeaponData.by_id(weapon)
	if data.tracer_color.a > 0.0:
		color = data.tracer_color
	elif weapon == "anti_materiel":
		color = Color(0.75, 0.9, 1.0)
	var life: float = {"sniper": 0.16, "bolt_action": 0.14, "railgun": 0.45, "anti_materiel": 0.22, "laser_rifle": 0.06,
		"air_cannon": 0.12}.get(weapon, 0.07)
	_flash(parent, muzzle, Color(1.0, 0.8, 0.4), flash, 0.05)
	for i in ends.size():
		var hit: bool = hits[i] if i < hits.size() else false
		var via: PackedVector3Array = vias[i] if i < vias.size() else PackedVector3Array()
		var from := muzzle
		for k in range(0, via.size() - 1, 2):
			_tracer(parent, from, via[k], width, color, life)
			from = via[k + 1]
		_tracer(parent, from, ends[i], width, color, life)
		_flash(parent, ends[i], Color(1.0, 0.3, 0.2) if hit else Color(0.9, 0.9, 0.8), 0.15 if ends.size() == 1 else 0.07, 0.12)


static func _tracer(parent: Node, a: Vector3, b: Vector3, width: float = 0.015, color: Color = Color(1.0, 0.85, 0.5), life: float = 0.07) -> void:
	var length := a.distance_to(b)
	if length < 0.05:
		return
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = width
	cyl.bottom_radius = width
	cyl.height = length
	cyl.radial_segments = 4
	mesh.mesh = cyl
	mesh.material_override = _glow(color)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	var dir := (b - a) / length
	var up := Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	# Cylinders point along Y; build a basis whose Y axis follows the shot.
	var x := up.cross(dir).normalized()
	var z := x.cross(dir).normalized()
	mesh.global_transform = Transform3D(Basis(x, dir, z), (a + b) * 0.5)
	_fade_and_free(mesh, life)


static func _flash(parent: Node, at: Vector3, color: Color, size: float, life: float) -> void:
	var mesh := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = size
	s.height = size * 2.0
	s.radial_segments = 8
	s.rings = 4
	mesh.mesh = s
	mesh.material_override = _glow(color)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	mesh.global_position = at
	_fade_and_free(mesh, life)


static func _glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 3.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _fade_and_free(node: Node3D, life: float) -> void:
	var tween := node.create_tween()
	tween.tween_property(node, "transparency", 1.0, life)
	tween.tween_callback(node.queue_free)


## A projectile came down at `at`: a blast, or (a nail, a bolt) a small puff where it struck.
static func landed(parent: Node, at: Vector3, data: WeaponData) -> void:
	if not data.explosive:
		if DisplayServer.get_name() != "headless" and is_instance_valid(parent):
			_flash(parent, at, Color(0.9, 0.9, 0.8), 0.1, 0.12)
		return
	explosion(parent, at, data.splash_radius)


## The sound a projectile makes coming down.
static func landed_sound(data: WeaponData) -> String:
	return "explosion" if data.explosive else "impact_wall"


## A rocket or grenade going off: a bright fireball that swells and fades, a shock
## ring, a flash of light and a puff of smoke.
static func explosion(parent: Node, at: Vector3, radius: float) -> void:
	if DisplayServer.get_name() == "headless" or not is_instance_valid(parent):
		return
	var core := _ball(parent, at, radius * 0.35, Color(1.0, 0.75, 0.3))
	var tw := core.create_tween().set_parallel()
	tw.tween_property(core, "scale", Vector3.ONE * 2.6, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(core, "transparency", 1.0, 0.32)
	tw.chain().tween_callback(core.queue_free)
	var fire := _ball(parent, at, radius * 0.5, Color(1.0, 0.4, 0.12))
	var tw2 := fire.create_tween().set_parallel()
	tw2.tween_property(fire, "scale", Vector3.ONE * 1.8, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw2.tween_property(fire, "transparency", 1.0, 0.5)
	tw2.chain().tween_callback(fire.queue_free)
	var smoke := _ball(parent, at + Vector3(0, 0.3, 0), radius * 0.6, Color(0.25, 0.24, 0.23), false)
	smoke.transparency = 0.35
	var tw3 := smoke.create_tween().set_parallel()
	tw3.tween_property(smoke, "scale", Vector3.ONE * 1.9, 1.4).set_ease(Tween.EASE_OUT)
	tw3.tween_property(smoke, "position", smoke.position + Vector3(0, 1.6, 0), 1.4)
	tw3.tween_property(smoke, "transparency", 1.0, 1.4)
	tw3.chain().tween_callback(smoke.queue_free)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.3)
	light.light_energy = 9.0
	light.omni_range = radius * 3.0
	parent.add_child(light)
	light.global_position = at
	var tw4 := light.create_tween()
	tw4.tween_property(light, "light_energy", 0.0, 0.4)
	tw4.tween_callback(light.queue_free)


static func _ball(parent: Node, at: Vector3, r: float, color: Color, glow: bool = true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	mesh.mesh = s
	if glow:
		mesh.material_override = _glow(color)
	else:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = m
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	mesh.global_position = at
	return mesh
