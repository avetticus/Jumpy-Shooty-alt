class_name RobotModel
extends Node3D
## One character on screen: the model from a .glb file (or, for a character from the
## Character Creator, put together from several), coloured for its player.
## RobotAnimator poses its skeleton every frame.

const VIEW_SHADER := "res://game/player/robot/viewmodel.gdshader"
const VISOR_ENERGY := 1.6
const GUN_GLOW_ENERGY := 1.4   ## a gun's glowing strips and cells ("<gun>.glow"), as bright as the melee weapons' edges
const GOLD := Color(1.0, 0.76, 0.22)   ## the Golden Gun
## Left out of the body you see in first person: the camera sits inside the head,
## and the arms and gun are drawn by ViewModel.
const VIEW_HIDDEN := ["head", "upper_arm_l", "forearm_l", "hand_l", "grapple", "upper_arm_r",
	"forearm_r", "hand_r", "pistol", "pistol_slide", "pistol_mag", "pistol_vent", "muzzle",
	"pistol_l", "pistol_l_slide", "pistol_l_mag", "pistol_l_vent",
	"index_l", "index_l2", "fingers_l", "fingers_l2", "thumb_l", "thumb_l2",
	"index_r", "index_r2", "fingers_r", "fingers_r2", "thumb_r", "thumb_r2"]

## What a surface's material kind (see material_kind) means for a character:
## which of a character's colours it takes (CustomCharacter.BODY_COLORS: 0 the main
## colour, which is also what a team's colour repaints; 1 the second colour; 2 the
## detail colour; 3 the skin tone). A robot's own materials are read through
## Characters.material_role first ("joint" is "trim_joint").
const CHANNELS := {"armor": 0, "extra": 0, "trim": 1, "mark": 2, "hair": 2, "skin": 3, "flesh": 3}
const NO_COLORS: Array[Color] = [Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]
## ...and for measuring a body for its accessories: a head's shell (not its ears, horns
## or antennas), its eyes, and what to leave out of the chest and the waist.
const SHELL := ["armor", "steel", "cloth", "mail", "visor", "skin", "hair", "shell"]
const EYES := ["visor", "eye"]
const UNMEASURED := ["visor", "extra", "flesh"]
## The first-person arms: these bones' triangles (a kit's are thinned: Characters.KIT_FP_SLIM).
const ARM_BONES := ["upper_arm_l", "forearm_l", "hand_l", "upper_arm_r", "forearm_r", "hand_r",
	"index_l", "index_l2", "fingers_l", "fingers_l2", "thumb_l", "thumb_l2",
	"index_r", "index_r2", "fingers_r", "fingers_r2", "thumb_r", "thumb_r2"]
const SLIM_BONES := {"forearm_l": -1.0, "forearm_r": 1.0}   # (not the hands: their fingers have to meet a gun's grip)
const ARM_X := 0.215                         ## how far out the arms hang (rig.py: forearm_l)
## A custom character's cape and tail have bones of their own (see Accessories.RIGGED),
## added after the body's, in this order, on these bones. settle_sway() poses them.
const SWAY := ["cape", "tail"]
const SWAY_PARENT := {"cape": "hips", "tail": "hips"}
const CAPE_BAND := 0.08       ## the cape bends over this far either side of its bone
const CAPE_LEAN := deg_to_rad(30.0)   ## the most a cape's hem leans out from hanging straight down
const SWAY_FLOOR := 0.04      ## the lowest a cape's hem or a tail's tip goes (above the feet)
const CAPE_STREAM := deg_to_rad(72.0)   ## streaming behind a body on a rope, a cape's hem leans out this far at most...
const TAIL_STREAM := deg_to_rad(38.0)   ## ...and a tail's tip turns this far toward the way it streams

static var _view_meshes := {}     # body mesh -> the mesh without VIEW_HIDDEN
static var _gun_meshes := {}      # [model file, gun] -> [the mesh with only that gun, which surface of the full mesh each surface was]
static var _custom_meshes := {}   # custom character's parts + gun -> its mesh (see _custom_mesh)
static var _sources := {}         # model file -> [its full mesh, its skin]
static var _shown := {}           # "part id|region|channel" -> whether that part has anything of that colour
static var _roles := {}           # [material, role name] -> the material under its role's name
static var _arm_meshes := {}      # kit + gun -> a kit's first-person arms (see _kit_arms_mesh)

## The gun this robot holds (an id from WeaponData). Every model file holds every
## gun; their surfaces' materials are named "<gun>.<kind>", and the others are left out.
var weapon := ""
## The clip this character stands still in: its torso's own idle ("idle_<torso>", with
## that robot's habit in it: see animations.py), or the plain "idle" if it has none.
var idle := "idle"
var rig: RobotRig
var skeleton: Skeleton3D
var mesh: MeshInstance3D
var view_mesh: MeshInstance3D     ## the same body without head and arms (first person only)
var chest_front := 0.12           ## how far the chest sticks out in front of the neck (set by add_view_mesh)
var melee: Node3D                 ## the sword, hammer or spear in the fist (see MeleeModel), if any
var melee_left: Node3D            ## the left fist's brass knuckles, if any

var _glow_materials: Array = []   # [material, is_shader]
var _gun_glow: Array = []         # [material, its colour]: the gun's lit parts (see set_gun_glow)
var _glow_color := Color.WHITE
var _sway: Array = []             # {bone, parent, rest (its rest, on the parent), tip, kind}: see settle_sway


## The colour used on a robot's trim and visor: the player colour, made more vivid.
static func trim_color(player_color: Color) -> Color:
	return Color.from_hsv(player_color.h, minf(player_color.s * 1.35, 1.0), player_color.v)


## Any character (a robot's id, or a custom one's; see Characters): its model,
## put together from its parts if it is a custom character. arms: the first-person
## arms model instead of the full body. team_paint: the armour all in this colour (the
## team modes paint everyone in their team's colour; alpha 0 leaves it as it is).
func build(character: String, player_color: Color, viewmodel: bool = false, gun: String = "pistol", arms: bool = false,
		team_paint: Color = Color(0, 0, 0, 0)) -> RobotModel:
	var custom: CustomCharacter = CustomCharacter.parse(character) if Characters.is_custom(character) else null
	var path := Characters.arms(character) if arms else Characters.body(character)
	var colors: Array[Color] = custom.channel_colors() if custom else NO_COLORS.duplicate()
	if team_paint.a > 0.0:
		colors[0] = team_paint
	_setup(path, player_color, viewmodel, gun, custom, colors, arms)
	var habit := "idle_" + (custom.torso if custom else Characters.valid(character))
	idle = habit if rig.has_clip(habit) else "idle"
	return self


## viewmodel: draw with the first-person shader (own field of view, never clips into walls).
## gun: which gun it holds (an id from WeaponData).
func setup(path: String, player_color: Color, viewmodel: bool = false, gun: String = "pistol") -> RobotModel:
	return _setup(path, player_color, viewmodel, gun)


## custom: a custom character to put together (`path` is its base robot's file: the
## skeleton, the animations and the guns); colors: its main, second and detail
## colours and its skin tone (see CHANNELS; alpha 0 leaves one as built). arms: `path`
## is the first-person arms' file.
func _setup(path: String, player_color: Color, viewmodel: bool, gun: String, custom: CustomCharacter = null,
		colors: Array[Color] = NO_COLORS, arms: bool = false) -> RobotModel:
	rig = RobotRig.open(path)
	var node := rig.scene.instantiate()
	add_child(node)
	skeleton = node.find_child("Skeleton3D", true, false)
	var player := node.find_child("AnimationPlayer", true, false)
	if player:
		player.free()   # RobotAnimator plays the clips itself
	for c in skeleton.get_children():
		if c is MeshInstance3D:
			mesh = c
	weapon = gun if gun == "none" else WeaponData.valid(gun)   # "none": empty hands (races)
	# A melee weapon is not in the model file: empty hands, then the blade in the fist.
	var shown_gun := "none" if WeaponData.melee(weapon) else WeaponData.look_of(weapon)   # (the Golden Gun: the revolver)
	var golden := weapon != "none" and WeaponData.by_id(weapon).golden
	if custom and not arms:
		mesh.mesh = _custom_mesh(custom, path, mesh.skin, shown_gun)
		_add_sway(mesh.mesh.get_meta("sway", []))
	elif custom and Characters.is_kit(custom.torso):
		mesh.mesh = _kit_arms_mesh(custom.torso, path, mesh, shown_gun)   # a robot's guns in the kit's own hands
	else:
		mesh.mesh = _with_gun(path, mesh.mesh, shown_gun)
	var trim := trim_color(player_color)
	if WeaponData.melee(weapon):
		melee = MeleeModel.attach(self, weapon, trim, viewmodel)
		melee_left = MeleeModel.attach_left(self, weapon, trim, viewmodel)
	_glow_color = trim
	# A mesh straight from a robot's file still has the robot's own material names (a
	# custom character's body was renamed as it was put together, and a kit's arms
	# already go by role).
	var plain := "" if custom and (not arms or Characters.is_kit(custom.torso)) else path.get_file().get_basename().trim_suffix("_arms")
	for i in mesh.mesh.get_surface_count():
		var base: StandardMaterial3D = mesh.mesh.surface_get_material(i)
		var kind := material_kind(Characters.material_role(plain, base.resource_name) if plain != "" else base.resource_name)
		var gun_glow := kind == "glow" and "." in base.resource_name   # a gun's lit parts, in the player's trim colour
		var lit := kind in Accessories.LIGHTS   # an accessory's lights: the player's trim colour, like the visor
		var color := Color(trim, base.albedo_color.a) if kind == "accent" or gun_glow or lit else base.albedo_color
		var channel: int = CHANNELS.get(kind, -1)
		var painted := channel >= 0 and colors[channel].a > 0.0
		if painted:
			color = colors[channel]
		var gilded := golden and base.resource_name.begins_with(shown_gun + ".")   # the gun's own surfaces
		if gilded:
			color = GOLD if kind != "accent" else GOLD.darkened(0.25)
		if viewmodel:
			var sm := ShaderMaterial.new()
			sm.shader = load(VIEW_SHADER)
			sm.set_shader_parameter("albedo", color)
			sm.set_shader_parameter("roughness", 0.25 if gilded else base.roughness)
			sm.set_shader_parameter("metallic", 0.9 if gilded else base.metallic)
			if kind == "visor" or lit:
				sm.set_shader_parameter("emission", trim * VISOR_ENERGY)
				_glow_materials.append([sm, true])
			elif gun_glow:
				sm.set_shader_parameter("emission", color * GUN_GLOW_ENERGY)
				_gun_glow.append([sm, color])
			mesh.set_surface_override_material(i, sm)
		elif kind == "accent" or kind == "visor" or gun_glow or painted or gilded or lit:
			var m: StandardMaterial3D = base.duplicate()
			if lit:
				m.albedo_color = color
			if kind == "visor" or lit:
				m.emission_enabled = true
				m.emission = trim
				m.emission_energy_multiplier = VISOR_ENERGY
				_glow_materials.append([m, false])
			else:
				m.albedo_color = color
				if gilded:
					m.metallic = 0.9
					m.roughness = 0.25
				if gun_glow:
					m.emission_enabled = true
					m.emission = color
					m.emission_energy_multiplier = GUN_GLOW_ENERGY
					_gun_glow.append([m, color])
			mesh.set_surface_override_material(i, m)
	if viewmodel:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.extra_cull_margin = 10.0   # the shader moves it on screen; never cull it
	return self


## Whether any of this character's parts has something of this colour (a CHANNELS
## number): bare skin for a skin tone, a second colour to paint...
static func shows(c: CustomCharacter, channel: int) -> bool:
	for part in ["legs", "torso", "head"]:
		var id := c.part(part)
		var key := "%s|%s|%d" % [id, part, channel]
		if not _shown.has(key):
			_shown[key] = false
			var path := Characters.part_file(id)
			var source: Mesh = _source(path)[0]
			var names := _bind_list(_source(path)[1])
			for s in source.get_surface_count():
				var mat := source.surface_get_material(s)
				if mat == null or CHANNELS.get(material_kind(Characters.material_role(id, mat.resource_name)), -1) != channel:
					continue
				var arrays := source.surface_get_arrays(s)
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var per := bones.size() / (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				for v in range(0, bones.size(), per):
					if CustomCharacter.region_of(names[bones[v]]) == part:
						_shown[key] = true
						break
		if _shown[key]:
			return true
	return false


static func shows_skin(c: CustomCharacter) -> bool:
	return shows(c, 3)


## A material under the name of its role (see Characters.material_role), so the
## colours find it: the same material, renamed, made once.
static func _in_role(mat: Material, role: String) -> Material:
	if mat == null or mat.resource_name == role:
		return mat
	var key := [mat, role]
	if not _roles.has(key):
		var copy: Material = mat.duplicate()
		copy.resource_name = role
		_roles[key] = copy
	return _roles[key]


## A custom character's mesh: each body region's triangles from the body it comes
## from (see CustomCharacter.region_of), a gun from its base robot's file (`host`),
## then its accessories (see Accessories), fitted to that head, chest and waist.
## Every body shares one skeleton and one list of skin binds, so the parts go onto
## the base robot's skeleton as they are.
static func _custom_mesh(c: CustomCharacter, host: String, skin: Skin, gun: String) -> Mesh:
	var picked := []
	for slot in CustomCharacter.SLOTS:
		picked.append("%s.%s" % [c.accessories.get(slot, ""), c.color_of(slot)])
	var key := "%s|%s|%s|%s|%s" % [c.legs, c.torso, c.head, ",".join(picked), gun]
	if _custom_meshes.has(key):
		return _custom_meshes[key]
	var bind_of := _bind_names(skin)   # bone name -> skin bind
	var out := ArrayMesh.new()
	var head_shell := AABB()
	var visor := AABB()
	var chest := AABB()
	var waist := AABB()
	var seen := {"shell": false, "visor": false, "chest": false, "waist": false}
	# What the accessories take the place of (the thin bits on a head under a hat,
	# a tail under a tail): left out, and not measured.
	var hidden := Accessories.hidden(c.accessories, c.head, c.legs)
	for part in ["legs", "torso", "head"]:
		var path := Characters.part_file(c.part(part))
		var source: Mesh = _source(path)[0]
		var names := _bind_list(_source(path)[1])   # this file's skin bind -> bone name
		for s in source.get_surface_count():
			var mat := source.surface_get_material(s)
			if mat and "." in mat.resource_name:
				continue   # a gun: from the base robot, below
			var arrays := source.surface_get_arrays(s)
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var per := bones.size() / verts.size()
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
			var kind := material_kind(mat.resource_name) if mat else ""
			var kept := PackedInt32Array()
			for t in range(0, index.size(), 3):
				var v := index[t]
				var best := 0
				for k in per:
					if weights[v * per + k] > weights[v * per + best]:
						best = k
				var bone_name: String = names[bones[v * per + best]]
				if CustomCharacter.region_of(bone_name) != part:
					continue
				if not (hidden.get(part, []) as Array).is_empty() and mat and Accessories.hides(hidden[part], mat.resource_name,
						(verts[index[t]] + verts[index[t + 1]] + verts[index[t + 2]]) / 3.0):
					continue
				kept.append_array([index[t], index[t + 1], index[t + 2]])
				# Measure the head, chest and waist, for fitting the accessories.
				for corner in 3:
					var p := verts[index[t + corner]]
					if bone_name == "head" and p.y > 1.48 and kind in SHELL:
						head_shell = head_shell.expand(p) if seen.shell else AABB(p, Vector3.ZERO)
						seen.shell = true
					if bone_name == "head" and kind in EYES:
						visor = visor.expand(p) if seen.visor else AABB(p, Vector3.ZERO)
						seen.visor = true
					if bone_name == "chest" and kind not in UNMEASURED:
						chest = chest.expand(p) if seen.chest else AABB(p, Vector3.ZERO)
						seen.chest = true
					if bone_name == "hips" and kind not in UNMEASURED and p.y > 0.93:
						waist = waist.expand(p) if seen.waist else AABB(p, Vector3.ZERO)
						seen.waist = true
			if kept.is_empty():
				continue
			arrays[Mesh.ARRAY_INDEX] = kept
			arrays[Mesh.ARRAY_BONES] = _rebind(bones, names, bind_of)
			var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
			out.surface_set_material(out.get_surface_count() - 1, _in_role(mat, Characters.material_role(c.part(part), mat.resource_name)) if mat else mat)
	_add_gun(out, host, gun, bind_of)
	if not seen.shell:
		head_shell = AABB(Vector3(-0.12, 1.5, -0.14), Vector3(0.24, 0.3, 0.27))
	if not seen.chest:
		chest = AABB(Vector3(-0.2, 1.18, -0.14), Vector3(0.4, 0.32, 0.28))
	if not seen.waist:
		waist = AABB(Vector3(-0.14, 0.93, -0.1), Vector3(0.28, 0.12, 0.2))
	# How far forward the chest is just below the neck: the second measurement
	# needs the chest's height first.
	var collar := chest.position.z
	var collar_set := false
	var torso_path := Characters.part_file(c.torso)
	var torso_src: Mesh = _source(torso_path)[0]
	var torso_names := _bind_list(_source(torso_path)[1])
	for s in torso_src.get_surface_count():
		var mat := torso_src.surface_get_material(s)
		if mat and ("." in mat.resource_name or material_kind(mat.resource_name) in UNMEASURED):
			continue
		var arrays := torso_src.surface_get_arrays(s)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var per := bones.size() / verts.size()
		for i in verts.size():
			if torso_names[bones[i * per]] == "chest" and verts[i].y > chest.end.y - 0.07:
				collar = verts[i].z if not collar_set else minf(collar, verts[i].z)
				collar_set = true
	var fit := Accessories.fit(head_shell, visor, chest, collar, waist)
	# The cape's and the tail's own bones: skin binds after the body's, in SWAY's order.
	var rigged := {}   # accessory bone -> true
	for slot in CustomCharacter.SLOTS:
		var id: String = c.accessories.get(slot, "")
		if id != "":
			rigged["tail" if slot == "tail" else Accessories.RIGGED.get(id, "")] = true
	var sway := []   # {name, parent, pivot, tip}: see _add_sway
	for bone in SWAY:
		if rigged.has(bone):
			bind_of[bone] = skin.get_bind_count() + sway.size()
			sway.append({"name": bone, "parent": SWAY_PARENT[bone], "pivot": Accessories.pivot(bone, fit), "tip": Vector3.ZERO})
	var tints := {}
	for slot in CustomCharacter.SLOTS:
		if c.color_of(slot) != "":
			tints[slot] = CustomCharacter.paint_color(c.color_of(slot))
	for piece in Accessories.build(c.accessories, fit, tints, c.head):
		var pts: PackedVector3Array = piece.points
		if pts.is_empty():
			continue
		var normals := PackedVector3Array()
		normals.resize(pts.size())
		var bones := PackedInt32Array()
		bones.resize(pts.size() * 4)
		var weights := PackedFloat32Array()
		weights.resize(pts.size() * 4)
		var bind: int = bind_of.get(piece.bone, 0)
		var rig_of: Dictionary = {}   # the cape's or the tail's entry in `sway`
		for entry in sway:
			if entry.name == piece.bone:
				rig_of = entry
		for t in range(0, pts.size(), 3):
			# Godot's front faces wind clockwise: the triangles come out counter-clockwise.
			var a := pts[t]
			pts[t] = pts[t + 2]
			pts[t + 2] = a
			var n := (pts[t + 2] - pts[t]).cross(pts[t + 1] - pts[t]).normalized()
			for k in 3:
				normals[t + k] = n
		for i in pts.size():
			bones[i * 4] = bind
			weights[i * 4] = 1.0
			if piece.bone == "skirt":
				_skirt_weights(pts[i], fit, bind_of, bones, weights, i * 4)
			elif piece.bone == "cape":
				# The top on the chest, the bottom on the cape's bone, bending between.
				var low := clampf((rig_of.pivot.y + CAPE_BAND - pts[i].y) / (2.0 * CAPE_BAND), 0.0, 1.0)
				bones[i * 4] = bind_of["chest"]
				weights[i * 4] = 1.0 - low
				bones[i * 4 + 1] = bind
				weights[i * 4 + 1] = low
			if not rig_of.is_empty():
				# The point furthest from the bone (a cape's hem, a tail's tip): what
				# settle_sway keeps off the floor.
				var off: Vector3 = pts[i] - rig_of.pivot
				if off.length_squared() > (rig_of.tip as Vector3).length_squared() and (piece.bone != "cape" or off.y < 0.0):
					rig_of.tip = off
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, Accessories.material(piece.material, piece.get("tint", Color(0, 0, 0, 0))))
	if not sway.is_empty():
		out.set_meta("sway", sway)
	if _custom_meshes.size() > 64:
		_custom_meshes.clear()
	_custom_meshes[key] = out
	return out


## A skirt (Accessories.RIGGED): on the hips at the waist, more and more on the thigh
## on its side further down (half on each in the middle), so the legs carry it with
## them instead of going through it.
static func _skirt_weights(p: Vector3, fit: Dictionary, bind_of: Dictionary, bones: PackedInt32Array,
		weights: PackedFloat32Array, at: int) -> void:
	var down := clampf((fit.waist_y - 0.02 - p.y) / 0.2, 0.0, 1.0) * 0.9
	var right := clampf(0.5 + p.x / (maxf(fit.waist_w, 0.1) * 1.2), 0.0, 1.0)   # thigh_r is on +x
	bones[at] = bind_of["hips"]
	weights[at] = 1.0 - down
	bones[at + 1] = bind_of["thigh_r"]
	weights[at + 1] = down * right
	bones[at + 2] = bind_of["thigh_l"]
	weights[at + 2] = down * (1.0 - right)


## The cape's and the tail's bones (see SWAY), on this model's own skeleton and skin.
func _add_sway(list: Array) -> void:
	if list.is_empty():
		return
	var skin: Skin = mesh.skin.duplicate()
	for entry in list:
		var parent := skeleton.find_bone(entry.parent)
		var i := skeleton.get_bone_count()
		skeleton.add_bone(entry.name)
		skeleton.set_bone_parent(i, parent)
		var rest := skeleton.get_bone_global_rest(parent).affine_inverse() * Transform3D(Basis.IDENTITY, entry.pivot)
		skeleton.set_bone_rest(i, rest)
		skeleton.set_bone_pose_position(i, rest.origin)
		skeleton.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion())
		skin.add_named_bind(entry.name, Transform3D(Basis.IDENTITY, -entry.pivot))
		_sway.append({"bone": i, "parent": parent, "rest": rest, "tip": entry.tip, "kind": entry.name})
	mesh.skin = skin


## Poses the cape's and the tail's bones for the pose the body is in now (call after
## posing the skeleton): a cape hangs from the small of the back, leaning out no more
## than CAPE_LEAN, and neither a cape's hem nor a tail's tip goes below SWAY_FLOOR.
## stream: on a rope (RopeSwing), the way everything loose streams out behind the body,
## in the model's space, as long as it is strong (0..1): the cape and the tail go with it.
func settle_sway(stream: Vector3 = Vector3.ZERO) -> void:
	var blow := minf(stream.length(), 1.0)
	var blown := stream / stream.length() if blow > 0.001 else Vector3.DOWN
	for s in _sway:
		var parent := skeleton.get_bone_global_pose(s.parent) * (s.rest as Transform3D)
		var turn := parent.basis.get_rotation_quaternion()
		var tip: Vector3 = turn * (s.tip as Vector3)
		var q := Quaternion.IDENTITY   # the turn to make, in the skeleton's space
		# The way the body faces, level, and its left-right axis.
		var ahead := turn * Vector3.FORWARD
		ahead.y = 0.0
		ahead = ahead.normalized() if ahead.length_squared() > 1e-6 else Vector3.FORWARD
		var side := Vector3.UP.cross(ahead).normalized()
		if s.kind == "cape" and tip.length_squared() > 1e-6:
			# Hang: never forward of straight down (under the body, through the legs),
			# and leaning back out no more than CAPE_LEAN.
			var d := tip.normalized()
			if blow > 0.001 and d.dot(blown) > -0.99:
				d = d.slerp(blown, blow * 0.85)
			var fwd := d.dot(ahead)
			if fwd > 0.0:
				d = (d - ahead * fwd).normalized() if (d - ahead * fwd).length_squared() > 1e-6 else Vector3.DOWN
			var lean := d.angle_to(Vector3.DOWN)
			var most := lerpf(CAPE_LEAN, CAPE_STREAM, blow)
			if lean > most:
				var axis := d.cross(Vector3.DOWN)
				if axis.length_squared() > 1e-8:
					d = Quaternion(axis.normalized(), lean - most) * d
			q = Quaternion(tip.normalized(), d)
		elif blow > 0.001 and tip.length_squared() > 1e-6:
			# A tail: its tip turns toward the way it streams.
			var d := tip.normalized()
			var axis := d.cross(blown)
			if axis.length_squared() > 1e-8:
				q = Quaternion(axis.normalized(), minf(d.angle_to(blown), TAIL_STREAM * blow))
		if parent.origin.y + (q * tip).y < SWAY_FLOOR:
			# Swung back and up, about the left-right axis, just far enough.
			var back := 1.0 if (Quaternion(side, 0.1) * (q * tip)).dot(ahead) < (q * tip).dot(ahead) else -1.0
			for k in range(1, 19):
				var r := Quaternion(side, back * k * PI / 36.0) * q
				q = r
				if parent.origin.y + (r * tip).y >= SWAY_FLOOR:
					break
		skeleton.set_bone_pose_rotation(s.bone, (s.rest as Transform3D).basis.get_rotation_quaternion() * turn.inverse() * q * turn)


## The first-person arms of a character whose torso is a kit: the kit's own arms
## (thinned, if they are bulky), holding the gun from the base robot's arms file.
## Kits have no arms files of their own.
static func _kit_arms_mesh(kit: String, arms_path: String, full: MeshInstance3D, gun: String) -> Mesh:
	var key := "%s|%s|%s" % [kit, arms_path, gun]
	if _arm_meshes.has(key):
		return _arm_meshes[key]
	var bind_of := _bind_names(full.skin)
	var out := ArrayMesh.new()
	var source: Mesh = _source(Characters.part_file(kit))[0]
	var names := _bind_list(_source(Characters.part_file(kit))[1])
	var slim: float = Characters.KIT_FP_SLIM.get(kit, 1.0)
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var per := bones.size() / verts.size()
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
		var kept := PackedInt32Array()
		for t in range(0, index.size(), 3):
			if names[bones[index[t] * per]] in ARM_BONES:   # (every triangle follows one bone)
				kept.append_array([index[t], index[t + 1], index[t + 2]])
		if kept.is_empty():
			continue
		if slim != 1.0:
			for i in verts.size():
				var side: float = SLIM_BONES.get(names[bones[i * per]], 0.0)
				if side != 0.0:
					verts[i] = Vector3(side * ARM_X + (verts[i].x - side * ARM_X) * slim, verts[i].y, verts[i].z * slim)
			arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_INDEX] = kept
		arrays[Mesh.ARRAY_BONES] = _rebind(bones, names, bind_of)
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		out.surface_set_material(out.get_surface_count() - 1, source.surface_get_material(s))
	_add_gun(out, arms_path, gun, bind_of)
	if _arm_meshes.size() > 64:
		_arm_meshes.clear()
	_arm_meshes[key] = out
	return out


## Adds one gun's surfaces from a robot's model file to `out`.
static func _add_gun(out: ArrayMesh, path: String, gun: String, bind_of: Dictionary) -> void:
	var source := _with_gun(path, _source(path)[0], gun)
	var names := _bind_list(_source(path)[1])
	for s in source.get_surface_count():
		var mat := source.surface_get_material(s)
		if mat == null or not "." in mat.resource_name:
			continue
		var arrays := source.surface_get_arrays(s)
		arrays[Mesh.ARRAY_BONES] = _rebind(arrays[Mesh.ARRAY_BONES], names, bind_of)
		var flags: int = source.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		out.surface_set_material(out.get_surface_count() - 1, mat)


## A skin's binds: bone name -> bind number.
static func _bind_names(skin: Skin) -> Dictionary:
	var out := {}
	for b in skin.get_bind_count():
		out[String(skin.get_bind_name(b))] = b
	return out


## A skin's binds: bind number -> bone name.
static func _bind_list(skin: Skin) -> PackedStringArray:
	var out := PackedStringArray()
	for b in skin.get_bind_count():
		out.append(String(skin.get_bind_name(b)))
	return out


## Bone numbers from one model file's skin, as another skin numbers the same bones.
## Every file is built on one skeleton, so they almost always already agree.
static func _rebind(bones: PackedInt32Array, names: PackedStringArray, bind_of: Dictionary) -> PackedInt32Array:
	var same := true
	for b in names.size():
		if bind_of.get(names[b], -1) != b:
			same = false
			break
	if same:
		return bones
	var out := PackedInt32Array()
	out.resize(bones.size())
	for i in bones.size():
		out[i] = bind_of.get(names[bones[i]], 0) if bones[i] < names.size() else 0
	return out


## A model file's full mesh (every gun, if it has any) and its skin, loaded once.
static func _source(path: String) -> Array:
	if not _sources.has(path):
		var node: Node = (load(path) as PackedScene).instantiate()
		var skeleton: Skeleton3D = node.find_child("Skeleton3D", true, false)
		for c in skeleton.get_children():
			if c is MeshInstance3D:
				_sources[path] = [c.mesh, c.skin]
		node.free()
	return _sources[path]


## What kind of surface a material is, from its name: "rifle.accent" -> "accent";
## "armor" -> "armor"; "armor_frog" -> "armor" (the kits' materials each have their
## own colour, and say their kind before the "_").
static func material_kind(material_name: String) -> String:
	var kind := material_name.get_slice(".", 1) if "." in material_name else material_name
	return kind.get_slice("_", 0)


## The model's mesh with only one gun's surfaces (made once per model file and gun).
static func _with_gun(path: String, full: Mesh, gun: String) -> Mesh:
	var key := path + "|" + gun
	if _gun_meshes.has(key):
		return _gun_meshes[key]
	var out := ArrayMesh.new()
	for s in full.get_surface_count():
		var mat := full.surface_get_material(s)
		var mname := mat.resource_name if mat else ""
		if "." in mname and mname.get_slice(".", 0) != gun:
			continue
		var flags: int = full.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, full.surface_get_arrays(s), [], {}, flags)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	_gun_meshes[key] = out
	return out


## Where the gun's shots leave its barrel, in the world.
func muzzle() -> Vector3:
	return marker(WeaponData.by_id(weapon).muzzle_bone)


## Where a marker bone ("muzzle", "grapple") is in the world right now.
func marker(bone: String) -> Vector3:
	var i: int = rig.bones.get(bone, -1)
	if i < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin


## How brightly the visor and lights glow: 1 = on, 0 = powered down (dead).
func set_power(power: float) -> void:
	for entry in _glow_materials:
		if entry[1]:
			(entry[0] as ShaderMaterial).set_shader_parameter("emission", _glow_color * VISOR_ENERGY * power)
		else:
			(entry[0] as StandardMaterial3D).emission_energy_multiplier = VISOR_ENERGY * power


## How brightly the gun's glowing parts shine: 1 = as at rest. (Nothing drives this
## yet: it is here for the reloads to use.)
func set_gun_glow(amount: float) -> void:
	for entry in _gun_glow:
		if entry[0] is ShaderMaterial:
			(entry[0] as ShaderMaterial).set_shader_parameter("emission", (entry[1] as Color) * GUN_GLOW_ENERGY * amount)
		else:
			(entry[0] as StandardMaterial3D).emission_energy_multiplier = GUN_GLOW_ENERGY * amount


func set_layer(layer: int) -> void:
	mesh.layers = 1 << (layer - 1)
	for held in [melee, melee_left]:
		if held:
			for c in held.get_child(0).get_children():
				if c is MeshInstance3D:
					c.layers = mesh.layers


## Where a bone is in the model's own space (x right, y up, -z forward).
func bone_position(bone: String) -> Vector3:
	return global_transform.affine_inverse() * marker(bone)


## Your own robot in first person: a second copy of the mesh on the same skeleton,
## without the head and arms, on its own render layer. It casts no shadow (the
## full mesh, hidden from the camera, already casts the whole robot's).
func add_view_mesh(layer: int) -> void:
	if view_mesh:
		return
	view_mesh = MeshInstance3D.new()
	view_mesh.name = "ViewBody"
	var cut: Array = _view_mesh_for(rig, mesh)   # [mesh, which surface of the full mesh each surface was, chest depth]
	view_mesh.mesh = cut[0]
	chest_front = cut[2]
	view_mesh.skin = mesh.skin
	view_mesh.layers = 1 << (layer - 1)
	view_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view_mesh.extra_cull_margin = 2.0
	for i in cut[1].size():
		view_mesh.set_surface_override_material(i, mesh.get_surface_override_material(cut[1][i]))
	skeleton.add_child(view_mesh)
	view_mesh.skeleton = view_mesh.get_path_to(skeleton)


## The model's mesh with the triangles of VIEW_HIDDEN bones removed. Every triangle
## follows one bone, so this is a clean cut at the neck and shoulders.
static func _view_mesh_for(model_rig: RobotRig, full: MeshInstance3D) -> Array:
	if _view_meshes.has(full.mesh):
		return _view_meshes[full.mesh]
	var skin := full.skin
	var hidden := {}   # bone number as the mesh knows it -> true
	var chest := -1
	for b in skin.get_bind_count():
		var bone_name := String(skin.get_bind_name(b))
		if bone_name == "":
			bone_name = model_rig.bone_names[skin.get_bind_bone(b)]
		if bone_name in VIEW_HIDDEN:
			hidden[b] = true
		elif bone_name == "chest":
			chest = b
	var front := 0.0   # the chest's most forward point (-z), in the standing pose
	var source := full.mesh
	var out := ArrayMesh.new()
	var surfaces := PackedInt32Array()
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var per := bones.size() / verts.size()   # 4 or 8 bones per vertex
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
		var kept := PackedInt32Array()
		for t in range(0, index.size(), 3):
			var v := index[t]
			var best := 0
			for k in per:
				if weights[v * per + k] > weights[v * per + best]:
					best = k
			if not hidden.has(bones[v * per + best]):
				kept.append_array([index[t], index[t + 1], index[t + 2]])
			if bones[v * per + best] == chest:
				front = maxf(front, maxf(-verts[index[t]].z, maxf(-verts[index[t + 1]].z, -verts[index[t + 2]].z)))
		if kept.is_empty():
			continue   # a material only the head or arms use (the visor, the gun)
		arrays[Mesh.ARRAY_INDEX] = kept
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		out.surface_set_material(surfaces.size(), source.surface_get_material(s))
		surfaces.append(s)
	_view_meshes[full.mesh] = [out, surfaces, front]
	return _view_meshes[full.mesh]
