class_name ReloadFx
extends RefCounted
## The game's side of a gun's reload, for the things a clip cannot do: the spent cell
## that flies off and bounces (SpentCell), the gun's lit parts dying as the cell leaves
## and surging back as the new one goes home, and not drawing the gun's own cell between
## the throw and the new one coming up in the hand. RobotAnimator (the body, for every
## player) and ViewModel (your own arms) both call update() every frame.
##
## Timed to each gun's reload clip (tools/robot/animations.py and weapon_anims.py): change
## a clip's keys and these go with them. A gun not listed here reloads as its clip alone.

## Per gun (by the weapon it looks like), in seconds into the reload:
##   eject: what the gun spent leaves it            seat: the new cell (or rounds) is home
##   hide:  [from, to] the gun's own cell is not drawn (left out: it always is)
##   throw: how the spent cell leaves, m/s in gun space (x right, y up, -z forward)
##   spin:  its tumble, radians a second, about its own axes
##   lift:  m/s upward it gets as well, so it arcs (left out: LIFT)
##   shells: this many spent casings fly out, not the cell itself (a revolver's cylinder stays);
##          shell: [radius, length, colour] of each, if not a pistol's
##   spare: [from, to] the gun's vent part is a second cell, drawn only between these (the
##          new one, in the left hand, while the old one is still in the gun)
##   hot:   the spent cell leaves still glowing
##   charge: seconds the lit parts take to build back up once the new cell is home (left out: at once)
##   both:  a gun in each hand, and both do it
##   heat:  no reload at all: the gun has overheated at this time, glows hot and cools
##          until `seat`; steam: [from, to] it steams from `steam_at` (gun space)
const GUNS := {
	"pistol": {"eject": 0.10, "hide": [0.115, 0.29], "seat": 0.62, "throw": Vector3(0.2, -3.0, 0.5), "spin": Vector3(10.0, 3.0, 16.0)},
	"machine_pistol": {"eject": 0.10, "hide": [0.115, 0.33], "seat": 0.655, "throw": Vector3(0.0, -1.8, 0.5),
		"spin": Vector3(5.0, 1.0, 3.0), "lift": 0.0},
	"revolver": {"eject": 0.38, "seat": 0.94, "shells": 6, "throw": Vector3(-1.3, 0.3, 0.7), "spin": Vector3(9.0, 4.0, 12.0), "lift": 0.9},
	"shotgun": {"hide": [0.34, 0.47], "seat": 0.27},
	"break_action": {"eject": 0.17, "hide": [0.18, 0.46], "seat": 0.77, "shells": 2, "shell": [0.012, 0.058, Color(0.8, 0.2, 0.12)],
		"throw": Vector3(0.3, 1.6, 2.4), "spin": Vector3(12.0, 2.0, 5.0), "lift": 1.4},
	"air_cannon": {"eject": 0.37, "hide": [0.38, 0.6], "seat": 1.22, "throw": Vector3(-0.7, -0.9, 0.2), "spin": Vector3(1.0, 0.5, 12.0), "lift": 0.2,
		"steam": [1.26, 1.5], "steam_at": Vector3(-0.04, 0.08, -0.04)},
	"rifle": {"eject": 0.14, "hide": [0.15, 0.42], "seat": 1.10, "throw": Vector3(0.0, -1.8, 0.3), "spin": Vector3(5.0, 1.0, 2.0), "lift": 0.0},
	"burst_rifle": {"eject": 0.61, "hide": [0.62, 0.84], "spare": [0.30, 0.84], "seat": 0.84, "throw": Vector3(1.8, -1.4, 0.0),
		"spin": Vector3(4.0, 2.0, 12.0), "lift": 0.4},
	"battle_rifle": {"eject": 0.38, "hide": [0.39, 0.64], "seat": 1.11, "throw": Vector3(-2.2, -0.4, 0.5), "spin": Vector3(6.0, 2.0, 8.0), "lift": 0.6},
	"lmg": {"eject": 0.98, "hide": [0.99, 1.37], "seat": 1.8, "throw": Vector3(-2.0, -0.3, 0.4), "spin": Vector3(3.0, 2.0, 5.0), "lift": 0.6},
	"minigun": {"eject": 1.10, "hide": [1.11, 1.52], "seat": 2.2, "throw": Vector3(-2.0, -0.3, 0.4), "spin": Vector3(3.0, 2.0, 5.0), "lift": 0.6},
	"lever_action": {"hide": [0.37, 0.45], "seat": 0.26},
	"anti_materiel": {"eject": 0.32, "hide": [0.33, 0.62], "seat": 1.30, "throw": Vector3(0.0, -1.0, 0.2), "spin": Vector3(2.0, 0.5, 1.0), "lift": 0.0},
	"railgun": {"eject": 0.30, "hide": [0.31, 0.82], "seat": 1.60, "hot": true, "throw": Vector3(-0.4, -1.4, 1.4), "spin": Vector3(9.0, 3.0, 6.0),
		"lift": 1.0, "steam": [0.42, 1.8], "steam_at": Vector3(0.0, 0.11, -0.5)},
	"crossbow": {"hide": [0.0, 0.28], "seat": 0.56},
	"rocket_launcher": {"hide": [0.0, 0.2], "seat": 0.96},
	"grenade_launcher": {"seat": 0.3},
	"akimbo": {"eject": 0.14, "hide": [0.155, 0.58], "seat": 0.71, "throw": Vector3(0.3, -2.8, 0.5), "spin": Vector3(10.0, 3.0, 16.0), "both": true},
	"dual_machine_pistol": {"eject": 0.14, "hide": [0.155, 0.58], "seat": 0.71, "throw": Vector3(0.3, -1.8, 0.5),
		"spin": Vector3(5.0, 1.0, 3.0), "lift": 0.0, "both": true},
	"dual_revolver": {"eject": 0.38, "seat": 1.05, "shells": 6, "throw": Vector3(-1.3, 0.3, 0.7), "spin": Vector3(9.0, 4.0, 12.0), "lift": 0.9,
		"both": true},
}
const GUN_REST := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))   ## gun space to the grip bone's (rig.py: GUN_REST)
const GRIP := Vector3(0.215, 0.835, 0.0)   ## where the gun bones are in a model file (rig.py: the right fist's grip)
const LIFT := 1.4      ## m/s upward a spent cell gets as well, so it arcs
const FLARE := 2.2     ## the lit parts, as the cell leaves (a last flash)...
const DEAD := 0.18     ## ...with no cell in...
const SURGE := 2.0     ## ...and as the new one goes home
const HOT := 2.8       ## the lit parts of a gun that has just overheated
const PUFF_EVERY := 0.045   ## seconds between puffs of steam

static var _cells := {}   # gun -> [mesh, its middle in the magazine bone's space]
static var _casings := {}   # radius (0: a pistol's) -> mesh


## How brightly the gun's lit parts shine `t` seconds into its reload (1 = as at rest).
static func glow(look: String, t: float) -> float:
	if t < 0.0 or not GUNS.has(look):
		return 1.0
	var g: Dictionary = GUNS[look]
	var home: float = g.seat
	if g.has("heat"):
		var hot: float = g.heat
		if t < hot:
			return 1.0
		if t < home:   # white hot, cooling as it vents
			return lerpf(HOT, DEAD, smoothstep(0.1, home - hot - 0.15, t - hot)) if t > hot + 0.05 else lerpf(1.0, HOT, (t - hot) / 0.05)
	else:
		var out: float = g.get("eject", home)   # (a shell at a time: nothing leaves, each one in is a small surge)
		if t < out:
			return 1.0
		if t < home:
			return lerpf(FLARE, DEAD, smoothstep(0.0, 0.16, t - out))
	var build: float = g.get("charge", 0.03)
	if t < home + build:
		return lerpf(DEAD, SURGE, pow((t - home) / build, 2.0))
	return lerpf(SURGE, 1.0, smoothstep(0.06, 0.4, t - home - build + 0.03))


## Whether the gun's own cell is drawn `t` seconds into its reload.
static func cell_shown(look: String, t: float) -> bool:
	if t < 0.0 or not GUNS.has(look) or not GUNS[look].has("hide"):
		return true
	var hide: Array = GUNS[look].hide
	return t < hide[0] or t >= hide[1]


## Every frame: `t` is how far into its reload `model`'s gun is, in seconds (-1: not
## reloading), `prev` what it was last frame. parent: where a spent cell is put (null:
## none is thrown: your own body in first person, a replay's puppet). inherit: the
## player's own velocity. on_screen: for the first-person arms, which are drawn with
## their own field of view: turns a place on them into where that is in the world.
static func update(model: RobotModel, look: String, prev: float, t: float, parent: Node, inherit: Vector3 = Vector3.ZERO,
		on_screen: Callable = Callable()) -> void:
	model.set_gun_glow(glow(look, t))
	var shown := cell_shown(look, t)
	var both: bool = GUNS.has(look) and GUNS[look].get("both", false)
	for bone_name in ["pistol_mag", "pistol_l_mag"]:
		var b: int = model.rig.bones.get(bone_name, -1)
		if b >= 0:
			model.skeleton.set_bone_pose_scale(b, Vector3.ONE if shown or (bone_name == "pistol_l_mag" and not both) else Vector3.ONE * 0.001)
	if GUNS.has(look) and GUNS[look].has("spare") and model.rig.bones.has("pistol_vent"):
		var spare: Array = GUNS[look].spare
		model.skeleton.set_bone_pose_scale(model.rig.bones["pistol_vent"], Vector3.ONE if t >= spare[0] and t < spare[1] else Vector3.ONE * 0.001)
	if parent == null or not GUNS.has(look) or t < 0.0 or not model.rig.bones.has("pistol_mag"):
		return
	var g: Dictionary = GUNS[look]
	if g.has("eject") and prev < g.eject and t >= g.eject and t - maxf(prev, 0.0) < 0.3:
		_throw(model, look, g, "", parent, inherit, on_screen)
		if both:
			_throw(model, look, g, "_l", parent, inherit, on_screen)
	if g.has("steam") and t >= g.steam[0] and t < g.steam[1] and floorf(t / PUFF_EVERY) != floorf(maxf(prev, 0.0) / PUFF_EVERY):
		var gun := _bone(model, "pistol")
		var at := gun * (GUN_REST * (g.steam_at as Vector3))
		if on_screen.is_valid():
			at = on_screen.call(at)
		var away := gun.basis * (GUN_REST * Vector3(randf_range(-0.25, 0.25), 0.9, 0.5))
		ReloadPuff.spawn(parent, at, away * randf_range(0.5, 0.9) + Vector3.UP * 0.35 + inherit * 0.5, Color(0.92, 0.95, 1.0, 0.42), 0.014, 0.5)


static func _bone(model: RobotModel, bone: String) -> Transform3D:
	return (model.skeleton.global_transform * model.skeleton.get_bone_global_pose(model.rig.bones[bone])).orthonormalized()


## Throws what one gun spent (side: "" the right hand's, "_l" the left's).
static func _throw(model: RobotModel, look: String, g: Dictionary, side: String, parent: Node, inherit: Vector3, on_screen: Callable) -> void:
	var cell := cell_of(model, look)
	if cell.is_empty() or not model.rig.bones.has("pistol%s_mag" % side):
		return
	var bone := _bone(model, "pistol%s_mag" % side)
	var at := bone * (cell[1] as Vector3)
	if on_screen.is_valid():
		at = on_screen.call(at)
	var gun := _bone(model, "pistol" + side).basis
	var throw: Vector3 = g.throw
	if side == "_l":
		throw.x = -throw.x   # the left gun throws to the left
	var lift: float = g.get("lift", LIFT)
	if not g.has("shells"):
		SpentCell.spawn(parent, cell[0], Transform3D(bone.basis, at), gun * (GUN_REST * throw) + Vector3.UP * lift + inherit, g.spin)
		return
	for i in int(g.shells):
		var jitter := Vector3(randf_range(-0.5, 0.5), randf_range(-0.4, 0.4), randf_range(-0.4, 0.5))
		var spot := at + gun * (GUN_REST * Vector3(randf_range(-0.018, 0.018), randf_range(-0.018, 0.018), 0.045))   # behind the breech
		var spin: Vector3 = (g.spin as Vector3) * randf_range(0.5, 1.4)
		SpentCell.spawn(parent, _casing_mesh(g.get("shell", [])), Transform3D(bone.basis * Basis(Vector3.RIGHT, PI * 0.5), spot),
			gun * (GUN_REST * (throw + jitter)) + Vector3.UP * lift + inherit, spin)


## A spent casing: a short dull tube with a dead primer.
static func _casing_mesh(shell: Array = []) -> Mesh:
	var key := 0.0 if shell.is_empty() else float(shell[0])
	if not _casings.has(key):
		var tube := CylinderMesh.new()
		tube.top_radius = 0.0075 if shell.is_empty() else float(shell[0])
		tube.bottom_radius = tube.top_radius + 0.001
		tube.height = 0.03 if shell.is_empty() else float(shell[1])
		tube.radial_segments = 8
		tube.rings = 1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.56, 0.5, 0.4) if shell.is_empty() else (shell[2] as Color)
		mat.metallic = 0.7 if shell.is_empty() else 0.1
		mat.roughness = 0.38 if shell.is_empty() else 0.6
		tube.material = mat
		_casings[key] = tube
	return _casings[key]


## A gun's cell on its own: [mesh (about its own middle), that middle in the magazine
## bone's space]. Cut out of the robot's model file: the triangles that ride on the
## magazine bone. Made once per gun.
static func cell_of(model: RobotModel, look: String) -> Array:
	if _cells.has(look):
		return _cells[look]
	var full: Mesh = RobotModel._source(Characters.body(Characters.default_id()))[0]
	var bone: int = model.rig.bones.get("pistol_mag", -1)   # (every robot's skeleton is the same)
	var grip := GRIP
	var kinds := {}   # material -> [vertices, normals]
	var total := Vector3.ZERO
	var count := 0
	for s in full.get_surface_count():
		var mat := full.surface_get_material(s) as StandardMaterial3D
		if mat == null or mat.resource_name.get_slice(".", 0) != look or not "." in mat.resource_name:
			continue
		var arrays := full.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var per := bones.size() / verts.size()
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var n := index.size() if not index.is_empty() else verts.size()
		var v_out := PackedVector3Array()
		var n_out := PackedVector3Array()
		for k in n:
			var i := index[k] if not index.is_empty() else k
			if bones[i * per] != bone:
				continue
			v_out.append(verts[i] - grip)
			n_out.append(normals[i])
			total += verts[i] - grip
			count += 1
		if not v_out.is_empty():
			kinds[mat] = [v_out, n_out]
	if count == 0:
		_cells[look] = []
		return []
	var middle := total / count
	var mesh := ArrayMesh.new()
	for mat in kinds:
		var verts: PackedVector3Array = kinds[mat][0]
		for i in verts.size():
			verts[i] -= middle
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = kinds[mat][1]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var m: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
		if RobotModel.material_kind(m.resource_name) == "glow" and not GUNS.get(look, {}).get("hot", false):
			# Spent: its light all but out.
			m.albedo_color = m.albedo_color.darkened(0.55)
			m.emission_enabled = true
			m.emission_energy_multiplier = 0.25
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)
	_cells[look] = [mesh, middle]
	return _cells[look]
