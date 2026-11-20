extends SceneTree
## Renders robot models to PNG files, for checking looks and animation poses
## without opening the editor. Used by tools/robot/preview.sh.
##
##   godot --path . --script tools/robot/preview.gd -- --job=JOB.json
##
## JOB.json: {"shots": [{"out": "a.png", "camera": {"pos": [x,y,z], "look": [x,y,z],
##   "ortho": height or 0, "fov": 40}, "items": [{"glb": "path.glb", "clip": "run",
##   "time": 0.2, "pos": [x,y,z], "yaw": 30, "colors": {"accent": [r,g,b]},
##   "label": "text"}]}]}
## An item can instead be driven by the game's own animator, to check blending and
## aiming: {"puppet": {"state": 0, "velocity": [x,y,z], "pitch": 20, "flags": 0,
##   "crouched": false, "grapple": [x,y,z], "alive": true, "seconds": 1.0,
##   "fire_at": 0.9, "fire_left_at": 0.9 (a gun in each hand), "wind": 0.5, "side": 0 (a melee swing wound up for 0.5 s then
##   let go, a tap from the right), "feet": [0.15, 0.0] (the ground under the left and right foot, above the floor: see
##   RobotAnimInput.feet), "then": {...same keys, applied after "seconds"..., "seconds": 0.1}}}
## A shot can also draw plain boxes, for steps and ledges: "blocks": [{"pos": [x, y, z], "size": [x, y, z]}].
## A puppet can hold any weapon: "weapon": "akimbo" (next to "puppet").
## A puppet with "first_person": {"pitch": -40, "eye": 1.6, "fov": 95} is seen through
## its own eyes (the shot's camera is ignored): the body as you see it in first person.

const BODY_LAYER := 2        # CameraRig's layers (that script needs the whole game loaded)
const VIEW_BODY_LAYER := 4

var _job := {}
var _shot := -1
var _wait := 0
var _root: Node3D
var _camera: Camera3D
var _cache := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--job="):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(arg.substr(6)))
			if parsed is Dictionary:
				_job = parsed
	if not _job.has("shots"):
		push_error("preview: no job file, or it has no shots")
		quit(1)
		return
	_build_stage()


func _process(_delta: float) -> bool:
	if not _job.has("shots"):
		return true
	if _wait > 0:
		_wait -= 1
		return false
	if _shot >= 0:
		var out: String = _job.shots[_shot].out
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
	_shot += 1
	if _shot >= _job.shots.size():
		return true
	_set_up(_job.shots[_shot])
	_wait = 4
	return false


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.60, 0.64, 0.70)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.90)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -150, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	root.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.50, 0.53, 0.58)
	mat.roughness = 0.9
	plane.material = mat
	floor_mesh.mesh = plane
	root.add_child(floor_mesh)
	_camera = Camera3D.new()
	root.add_child(_camera)
	_camera.make_current()
	_root = Node3D.new()
	root.add_child(_root)


func _set_up(shot: Dictionary) -> void:
	for c in _root.get_children():
		c.queue_free()
	var size: Array = shot.get("size", [1600, 900])
	root.size = Vector2i(size[0], size[1])
	DisplayServer.window_set_size(Vector2i(size[0], size[1]))
	var cam: Dictionary = shot.camera
	_camera.near = 0.05
	_camera.set_cull_mask_value(BODY_LAYER, true)
	_camera.position = _v(cam.pos)
	_camera.look_at(_v(cam.look))
	if cam.get("ortho", 0.0) > 0.0:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = cam.ortho
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = cam.get("fov", 40.0)
	for block in shot.get("blocks", []):   # plain boxes: {"pos": [x, y, z] (its middle), "size": [x, y, z]}
		var box_mesh := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = _v(block.size)
		var block_mat := StandardMaterial3D.new()
		block_mat.albedo_color = Color(0.42, 0.45, 0.50)
		block_mat.roughness = 0.9
		shape.material = block_mat
		box_mesh.mesh = shape
		box_mesh.position = _v(block.pos)
		_root.add_child(box_mesh)
	for item in shot.items:
		if item.has("puppet"):
			_puppet(item)
			continue
		var node := _load(item.glb)
		if node == null:
			continue
		_root.add_child(node)
		node.position = _v(item.get("pos", [0, 0, 0]))
		node.rotation_degrees.y = item.get("yaw", 0.0)
		_recolor(node, item.get("colors", {}))
		var clip: String = item.get("clip", "")
		var player: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
		if clip != "" and player and player.has_animation(clip):
			player.play(clip)
			player.seek(item.get("time", 0.0), true)
			player.pause()
		elif clip != "":
			push_error("no clip %s" % clip)
		if item.has("label"):
			var tag := Label3D.new()
			tag.text = item.label
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.no_depth_test = true
			tag.pixel_size = 0.004
			tag.font_size = 48
			tag.outline_size = 12
			tag.position = _v(item.get("pos", [0, 0, 0])) + _v(item.get("label_at", [0, 2.05, 0]))
			_root.add_child(tag)


## A robot posed by RobotAnimator from made-up movement, stepped at 60 frames a second.
func _puppet(item: Dictionary) -> void:
	var c: Array = item.get("color", [0.95, 0.35, 0.25])
	var robot := RobotModel.new().build(item.get("character", ""), Color(c[0], c[1], c[2]), false, item.get("weapon", "pistol"))
	_root.add_child(robot)
	robot.position = _v(item.get("pos", [0, 0, 0]))
	robot.rotation_degrees.y = item.get("yaw", 0.0)
	var animator := RobotAnimator.new(robot)
	var inp := RobotAnimInput.new()
	var step: Dictionary = item.puppet
	var first: Dictionary = item.get("first_person", {})
	var holder := Node3D.new()   # the first-person body is moved about inside this
	if not first.is_empty():
		holder.transform = robot.transform
		robot.transform = Transform3D.IDENTITY
		_root.remove_child(robot)
		_root.add_child(holder)
		holder.add_child(robot)
		robot.set_layer(BODY_LAYER)
		robot.add_view_mesh(VIEW_BODY_LAYER)
		animator.first_person = true
	while not step.is_empty():
		inp.state = int(step.get("state", inp.state))
		inp.crouched = step.get("crouched", inp.crouched)
		if step.has("velocity"):
			inp.velocity = _v(step.velocity).rotated(Vector3.UP, robot.global_rotation.y)
		inp.yaw = robot.global_rotation.y
		inp.pitch = deg_to_rad(step.get("pitch", rad_to_deg(inp.pitch)))
		inp.flags = int(step.get("flags", inp.flags))
		inp.alive = step.get("alive", inp.alive)
		inp.grapple_on = step.has("grapple")
		if step.has("feet"):   # the ground under the left and the right foot, above (+) or below (-) the floor
			inp.feet = Vector2(step.feet[0], step.feet[1])
		if step.has("grapple"):
			inp.grapple_anchor = robot.global_transform * _v(step.grapple)
		var t := 0.0
		var fired := false
		var fired_left := false
		while t < float(step.get("seconds", 1.0)):
			if step.has("fire_at") and not fired and t >= float(step.fire_at):
				animator.fire()
				fired = true
			if step.has("fire_left_at") and not fired_left and t >= float(step.fire_left_at):
				animator.fire(true)
				fired_left = true
			if step.has("wind"):   # a melee swing: wound up for "wind" seconds, then let go
				var data := WeaponData.by_id(robot.weapon)
				if t < float(step.wind):
					animator.wind(data.charge_of(t), int(step.get("side", 0)))
				elif not fired:
					animator.swing(data.charge_of(float(step.wind)), int(step.get("side", 0)))
					fired = true
			animator.update(1.0 / 60.0, inp, robot.global_transform)
			if not first.is_empty():
				animator.place_for_view(1.0, first.get("eye", 1.6), deg_to_rad(first.get("pitch", 0.0)))
			t += 1.0 / 60.0
		step = step.get("then", {})
	if not first.is_empty() and not first.get("outside", false):   # "outside": keep the shot's camera
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = first.get("fov", 95.0)
		_camera.near = 0.05
		_camera.set_cull_mask_value(BODY_LAYER, false)
		_camera.global_transform = holder.global_transform * Transform3D(
			Basis.from_euler(Vector3(deg_to_rad(first.get("pitch", 0.0)), 0.0, deg_to_rad(first.get("roll", 0.0)))),
			Vector3(0.0, first.get("eye", 1.6), 0.0))
	if item.has("label"):
		var tag := Label3D.new()
		tag.text = item.label
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.pixel_size = 0.004
		tag.font_size = 32
		tag.outline_size = 10
		tag.position = (robot.position + Vector3(0, 2.1, 0)) if first.is_empty() else _camera.global_transform * Vector3(0.0, 0.85, -1.0)
		_root.add_child(tag)


func _load(path: String) -> Node3D:
	if path.begins_with("res://"):
		var packed: PackedScene = load(path)
		return packed.instantiate() if packed else null
	if not _cache.has(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			push_error("cannot read %s" % path)
			return null
		_cache[path] = [doc, state]
	return _cache[path][0].generate_scene(_cache[path][1])


func _recolor(node: Node, colors: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		for i in mesh.get_surface_count():
			var base: StandardMaterial3D = mesh.surface_get_material(i)
			var mat_name := base.resource_name
			if colors.has(mat_name):
				var m: StandardMaterial3D = base.duplicate()
				var c := Color(colors[mat_name][0], colors[mat_name][1], colors[mat_name][2])
				if mat_name == "visor":
					m.emission_enabled = true
					m.emission = c
					m.emission_energy_multiplier = 1.5
				else:
					m.albedo_color = c
				node.set_surface_override_material(i, m)
			elif mat_name == "visor":
				var m2: StandardMaterial3D = base.duplicate()
				m2.emission_energy_multiplier = 1.5
				node.set_surface_override_material(i, m2)
	for c in node.get_children():
		_recolor(c, colors)


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
