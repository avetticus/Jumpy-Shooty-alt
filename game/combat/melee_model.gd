class_name MeleeModel
extends RefCounted
## The melee weapons' looks (longsword, hammer, dagger, brass knuckles, spear, axe, bat):
## made in the same factory as the robots. Gunmetal bodies, armour-plate panels, solid
## steel blades and heads, and glowing parts in the player's trim colour (set_glow
## dims or brightens them). Built here from MeleeKit's faceted shapes, so they need
## no model files, and carried in the robot's fist on its "pistol" bone (the grip).
##
## Built in weapon space: the right hand's grip at the origin, the blade or shaft up
## +Y, the edge (or the hammer's face) toward -Z. The two-handed ones have handle
## below the origin for the left hand (the spear: above it). MeleeSwing says where
## the weapon is and bends the arms to hold it.

const STEEL := Color(0.78, 0.8, 0.83)
const DARK := Color(0.17, 0.18, 0.21)       ## gunmetal, as on the guns
const PLATE := Color(0.90, 0.91, 0.93)      ## the robots' armour plate
const DETAIL := Color(0.36, 0.38, 0.42)
const GRIP := Color(0.1, 0.1, 0.11)
const VIEW_SHADER := "res://game/player/robot/viewmodel.gdshader"
## From weapon space to the grip bone's space: its -Z is up and -Y forward in the aim pose.
const TO_BONE := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
## The blade leans forward a little in the fist.
const READY_TILT := -0.45
## From weapon space to the grip bone's space, lean and all.
const HOLD := TO_BONE * Basis(Vector3.RIGHT, READY_TILT)
## Weapons shown lying flat (a pickup, a preview) are turned this far about their length, to show their broad side.
const SHOW_TURN := {"sword": PI * 0.5}
## How far up the weapon its cutting edge runs (from, to), in metres from the grip.
const EDGES := {"sword": [0.36, 1.48], "hammer": [0.62, 0.92], "dagger": [0.12, 0.56],
	"brass_knuckles": [0.0, 0.1], "spear": [1.3, 2.04], "axe": [0.47, 0.93], "bat": [0.4, 1.0],
	"energy_sword": [0.16, 1.06]}
## Worn on both fists (the left one on the akimbo pistol's grip bone, see attach_left).
const BOTH_FISTS := ["brass_knuckles"]


## Each material kind: [colour, roughness, metallic]. "edge" is the glow, in the player's trim colour.
const KINDS := {
	"steel": [STEEL, 0.3, 0.55],
	"dark": [DARK, 0.45, 0.4],
	"grip": [GRIP, 0.75, 0.05],
	"plate": [PLATE, 0.55, 0.1],
	"detail": [DETAIL, 0.5, 0.3],
}
const GLOW_ENERGY := 1.4   ## how brightly the glowing parts shine at rest


## Adds the weapon to `model` (a RobotModel). `viewmodel`: first-person arms (own shader).
static func attach(model: RobotModel, id: String, trim: Color, viewmodel: bool) -> Node3D:
	var at := BoneAttachment3D.new()
	at.name = "Melee"
	at.bone_name = "pistol"
	model.skeleton.add_child(at)
	var holder := build(id, trim, viewmodel)
	holder.transform = Transform3D(HOLD, Vector3.ZERO)
	at.add_child(holder)
	return at


## The brass knuckles go on both fists: the left one, on the left hand's
## own grip bone (the akimbo pistol's). Null for any other weapon.
static func attach_left(model: RobotModel, id: String, trim: Color, viewmodel: bool) -> Node3D:
	if not id in BOTH_FISTS or model.skeleton.find_bone("pistol_l") < 0:
		return null
	var at := BoneAttachment3D.new()
	at.name = "MeleeLeft"
	at.bone_name = "pistol_l"
	model.skeleton.add_child(at)
	var holder := build(id, trim, viewmodel)
	holder.transform = Transform3D(HOLD, Vector3.ZERO)
	at.add_child(holder)
	return at


## The weapon on its own, in weapon space: its pieces, and the two markers the swing
## trail is drawn between (where the cutting edge starts and ends).
static func build(id: String, glow: Color, viewmodel: bool = false) -> Node3D:
	var holder := Node3D.new()
	var lit := []
	for part in parts(id):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = part[1]
		mi.material_override = material(part[2], glow, viewmodel)
		if part[2] == "edge":
			lit.append(mi.material_override)
		if viewmodel:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 10.0
		holder.add_child(mi)
	holder.set_meta("glow", lit)
	holder.set_meta("glow_color", glow)
	var edge: Array = EDGES.get(id, EDGES.sword)
	for i in 2:
		var marker := Node3D.new()
		marker.name = "EdgeBase" if i == 0 else "EdgeTip"
		marker.position = Vector3(0, edge[i], 0)
		holder.add_child(marker)
	return holder


## The material of one kind of piece.
static func material(kind: String, glow: Color, viewmodel: bool = false) -> Material:
	var look: Array = KINDS.get(kind, KINDS.dark)
	var color: Color = glow if kind == "edge" else look[0]
	var energy := GLOW_ENERGY if kind == "edge" else 0.0
	if viewmodel:
		var sm := ShaderMaterial.new()
		sm.shader = load(VIEW_SHADER)
		sm.set_shader_parameter("albedo", color)
		sm.set_shader_parameter("roughness", look[1])
		sm.set_shader_parameter("metallic", look[2])
		sm.set_shader_parameter("emission", color * energy)
		return sm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = look[1]
	m.metallic = look[2]
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
	return m


## How brightly the weapon's glowing parts shine: 1 = as at rest. `melee` is what
## attach() returned. (Nothing drives this yet: it is here for the swing to use.)
static func set_glow(melee: Node3D, amount: float) -> void:
	var holder := melee.get_child(0)
	var color: Color = holder.get_meta("glow_color", Color.WHITE)
	for m in holder.get_meta("glow", []):
		if m is ShaderMaterial:
			m.set_shader_parameter("emission", color * GLOW_ENERGY * amount)
		else:
			(m as StandardMaterial3D).emission_energy_multiplier = GLOW_ENERGY * amount


## The edge's base and tip in the world right now.
static func edge(melee: Node3D) -> Array:
	var holder := melee.get_child(0)
	return [(holder.get_node("EdgeBase") as Node3D).global_position, (holder.get_node("EdgeTip") as Node3D).global_position]


## A kick's "edge" (see MeleeSwing.kicking): the striking shin and foot of `robot`
## (a RobotModel), from just below the knee to past the ankle, in the world right now.
static func kick_edge(robot: Node3D, limb: String) -> Array:
	var side := "_l" if limb.ends_with("_l") else "_r"
	var knee: Vector3 = robot.call("marker", "shin" + side)
	var ankle: Vector3 = robot.call("marker", "foot" + side)
	return [knee.lerp(ankle, 0.45), ankle + (ankle - knee) * 0.25]


## [mesh, transform, material kind] for each piece of a weapon.
static func parts(id: String) -> Array:
	match id:
		"hammer":
			return _hammer()
		"axe":
			return _axe()
		"bat":
			return _bat()
		"spear":
			return _spear()
		"dagger":
			return _dagger()
		"brass_knuckles":
			return _knuckles()
		"energy_sword":
			return _energy_sword()
	return _longsword()


## Longsword: a wide blade in two halves with a glowing channel between them, an
## armour-plate crossguard swept toward the point, a grip for two hands (the right
## at the origin, the left 14 cm below) and a power cell for a pommel.
static func _longsword() -> Array:
	var k := MeleeKit.new()
	# The blade's two halves. Each: the channel's wall, a flat, and a bevel down to the edge.
	var gap := 0.009          # half the channel's width
	var thick := 0.012        # half the blade's thickness
	var bevel := 0.026        # how wide the ground edge is
	var shape := [[0.3, 0.04], [0.36, 0.04], [0.43, 0.068], [1.2, 0.056]]   # [height, half width]
	for side in [-1.0, 1.0]:
		var rings := []
		for s in shape:
			var w: float = s[1]
			rings.append(PackedVector3Array([Vector3(gap * side, s[0], thick), Vector3((w - bevel) * side, s[0], thick),
				Vector3(w * side, s[0], 0), Vector3((w - bevel) * side, s[0], -thick), Vector3(gap * side, s[0], -thick)]))
		k.loft("steel", rings)
	# The point: one piece, the halves joined.
	var tip := []
	for s in [[1.2, 0.056], [1.48, 0.0]]:
		var w: float = s[1]
		var b := minf(bevel, w)
		var t := thick if w > 0.0 else 0.0
		tip.append(PackedVector3Array([Vector3(-w, s[0], 0), Vector3(-w + b, s[0], t), Vector3(w - b, s[0], t),
			Vector3(w, s[0], 0), Vector3(w - b, s[0], -t), Vector3(-w + b, s[0], -t)]))
	k.loft("steel", tip)
	# The channel: a glowing core set a little below the faces, and clamps across it.
	k.box("edge", Vector3(0, 0.76, 0), Vector3(gap * 2.0 + 0.004, 0.9, 0.014))
	for y in [0.6, 0.9, 1.185]:
		k.plate("detail", PackedVector2Array([Vector2(-0.03, y - 0.016), Vector2(0.03, y - 0.016), Vector2(0.036, y),
			Vector2(0.03, y + 0.016), Vector2(-0.03, y + 0.016), Vector2(-0.036, y)]), -0.017, 0.017)
	# The housing the blade comes out of, with an armour plate on each face.
	k.plate("dark", PackedVector2Array([Vector2(-0.055, 0.15), Vector2(0.055, 0.15), Vector2(0.074, 0.215), Vector2(0.052, 0.335),
		Vector2(0.02, 0.36), Vector2(-0.02, 0.36), Vector2(-0.052, 0.335), Vector2(-0.074, 0.215)]), -0.026, 0.026)
	for z in [-1.0, 1.0]:
		k.plate_pair("plate", PackedVector2Array([Vector2(0.016, 0.175), Vector2(0.048, 0.175), Vector2(0.06, 0.218),
			Vector2(0.044, 0.318), Vector2(0.016, 0.335)]), 0.02 * z, 0.032 * z)
	# The crossguard: two wings swept toward the point, armour on top, a light at each tip.
	k.plate("dark", PackedVector2Array([Vector2(0, 0.092), Vector2(0.07, 0.098), Vector2(0.179, 0.148), Vector2(0.206, 0.235),
		Vector2(0.171, 0.208), Vector2(0.144, 0.178), Vector2(0.06, 0.165), Vector2(-0.06, 0.165), Vector2(-0.144, 0.178),
		Vector2(-0.171, 0.208), Vector2(-0.206, 0.235), Vector2(-0.179, 0.148), Vector2(-0.07, 0.098)]), -0.03, 0.03)
	for z in [-1.0, 1.0]:
		k.plate_pair("plate", PackedVector2Array([Vector2(0.076, 0.113), Vector2(0.168, 0.155), Vector2(0.146, 0.166),
			Vector2(0.074, 0.152)]), 0.024 * z, 0.037 * z)
	k.plate_pair("edge", PackedVector2Array([Vector2(0.182, 0.168), Vector2(0.203, 0.226), Vector2(0.176, 0.203)]), -0.033, 0.033)
	# The grip, with a collar under the guard, one between the hands and one at the end.
	k.bar("grip", [[-0.245, 0.023], [0.095, 0.023]], 8)
	k.bar("detail", [[0.07, 0.027], [0.078, 0.032], [0.094, 0.032]], 8)
	k.bar("detail", [[-0.078, 0.027], [-0.07, 0.029], [-0.062, 0.027]], 8)
	# The pommel: a power cell held between two caps.
	k.bar("dark", [[-0.262, 0.03], [-0.254, 0.038], [-0.236, 0.038], [-0.228, 0.027]], 6)
	k.bar("edge", [[-0.318, 0.026], [-0.262, 0.026]], 6)
	k.bar("detail", [[-0.296, 0.031], [-0.284, 0.031]], 6)
	k.bar("dark", [[-0.372, 0.014], [-0.35, 0.036], [-0.326, 0.038], [-0.318, 0.03]], 6)
	# Drawn with its flat to the front; in the fist the edge leads (-Z), like every weapon's.
	return k.parts(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO))


## Hammer: a blocky head like a piston, a glowing strike face at each end, vents
## glowing along the top, armour on its sides, and a ribbed haft.
static func _hammer() -> Array:
	var k := MeleeKit.new()
	var mid := Vector2(0, 0.78)   # the middle of the head, seen end on
	k.bar("dark", [[-0.36, 0.025], [0.7, 0.025]])
	k.bar("grip", [[-0.3, 0.0285], [0.08, 0.0285]])
	for y in [0.2, 0.32, 0.44, 0.56]:
		k.bar("detail", [[y - 0.012, 0.027], [y - 0.006, 0.033], [y + 0.006, 0.033], [y + 0.012, 0.027]])
	k.bar("dark", [[0.6, 0.03], [0.625, 0.046], [0.68, 0.046]])
	k.bar("dark", [[-0.43, 0.022], [-0.41, 0.04], [-0.375, 0.04], [-0.36, 0.03]], 6)
	k.bar("edge", [[-0.4, 0.043], [-0.388, 0.043]], 6)
	k.plate("dark", MeleeKit.cut_rect(0.1, 0.105, 0.03, mid), -0.15, 0.15)
	for side in [-1.0, 1.0]:
		k.plate("detail", MeleeKit.cut_rect(0.078, 0.08, 0.024, mid), 0.15 * side, 0.19 * side)
		k.plate("steel", MeleeKit.cut_rect(0.112, 0.115, 0.034, mid), 0.19 * side, 0.255 * side)
		k.plate("edge", MeleeKit.cut_rect(0.084, 0.087, 0.026, mid), 0.25 * side, 0.264 * side)
		k.plate("plate", MeleeKit.cut_rect(0.115, 0.07, 0.025, mid), 0.096 * side, 0.112 * side, MeleeKit.SIDE)
	k.box("edge", Vector3(0, 0.886, 0), Vector3(0.1, 0.008, 0.2))
	for z in [-0.075, -0.025, 0.025, 0.075]:
		k.box("detail", Vector3(0, 0.893, z), Vector3(0.13, 0.016, 0.026))
	return k.parts()


## Axe: a big crescent blade with a glowing cutting edge, held in a mechanical collar,
## with a spike on the back to balance it.
static func _axe() -> Array:
	var k := MeleeKit.new()
	var side := MeleeKit.SIDE
	k.bar("dark", [[-0.3, 0.023], [0.87, 0.023]])
	k.bar("grip", [[-0.27, 0.026], [0.07, 0.026]])
	k.bar("detail", [[-0.088, 0.027], [-0.08, 0.031], [-0.072, 0.027]])
	k.bar("dark", [[-0.36, 0.018], [-0.34, 0.036], [-0.31, 0.036], [-0.295, 0.027]], 6)
	k.bar("edge", [[-0.332, 0.039], [-0.32, 0.039]], 6)
	k.bar("dark", [[0.56, 0.03], [0.585, 0.05], [0.815, 0.05], [0.84, 0.03]], 8, Vector2(0.8, 1.1))
	for y in [0.61, 0.79]:
		k.bar("detail", [[y - 0.01, 0.054], [y + 0.01, 0.054]], 8, Vector2(0.8, 1.1))
	k.bar("steel", [[0.86, 0.027], [0.885, 0.027], [0.96, 0.0]], 6)
	# The blade, in side view: the cutting edge is part of a circle, with a horn at each end.
	var body := PackedVector2Array()
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 9:
		var a := deg_to_rad(66.0 - 16.5 * i)
		var dir := Vector2(cos(a), sin(a))
		body.append(Vector2(0.04, 0.7) + dir * 0.25)
		outer.append(Vector2(0.04, 0.7) + dir * 0.264)
		inner.append(Vector2(0.04, 0.7) + dir * 0.234)
	body.append_array([Vector2(0.115, 0.585), Vector2(0.03, 0.61), Vector2(0.03, 0.79), Vector2(0.115, 0.815)])
	k.plate("steel", body, -0.011, 0.011, side)
	inner.reverse()
	outer.append_array(inner)
	k.plate("edge", outer, -0.005, 0.005, side)
	for x in [-1.0, 1.0]:
		k.plate("plate", PackedVector2Array([Vector2(0.045, 0.63), Vector2(0.115, 0.625), Vector2(0.185, 0.7), Vector2(0.115, 0.775),
			Vector2(0.045, 0.77)]), 0.009 * x, 0.018 * x, side)
	k.plate("steel", PackedVector2Array([Vector2(-0.03, 0.765), Vector2(-0.085, 0.735), Vector2(-0.175, 0.7),
		Vector2(-0.085, 0.665), Vector2(-0.03, 0.635)]), -0.012, 0.012, side)
	return k.parts()


## Bat: a bat in metal, its fat barrel wrapped in three glowing bands, rails between them.
static func _bat() -> Array:
	var k := MeleeKit.new()
	k.bar("steel", [[0.12, 0.022], [0.22, 0.024], [0.46, 0.05], [0.54, 0.058], [0.95, 0.058]], 10)
	k.bar("grip", [[-0.23, 0.0235], [0.13, 0.0235]], 10)
	k.bar("detail", [[0.115, 0.026], [0.125, 0.03], [0.14, 0.03], [0.15, 0.026]], 10)
	k.bar("dark", [[-0.275, 0.026], [-0.265, 0.038], [-0.245, 0.038], [-0.23, 0.026]], 10)
	k.bar("edge", [[-0.282, 0.021], [-0.274, 0.021]], 10)
	for y in [0.6, 0.74, 0.88]:
		k.bar("dark", [[y - 0.03, 0.058], [y - 0.024, 0.066], [y + 0.024, 0.066], [y + 0.03, 0.058]], 10)
		k.bar("edge", [[y - 0.008, 0.069], [y + 0.008, 0.069]], 10)
	for x in [-0.06, 0.06]:
		k.box("detail", Vector3(x, 0.745, 0), Vector3(0.012, 0.42, 0.016))
		k.box("detail", Vector3(0, 0.745, x), Vector3(0.016, 0.42, 0.012))
	k.bar("dark", [[0.94, 0.06], [0.955, 0.064], [0.99, 0.064], [1.005, 0.05], [1.012, 0.03]], 10)
	return k.parts()


## Spear: a long leaf of a head in two halves round a glowing core, two fins swept
## back under it, and a counterweight at the butt.
static func _spear() -> Array:
	var k := MeleeKit.new()
	k.bar("dark", [[-0.56, 0.019], [1.42, 0.019]])
	k.bar("grip", [[-0.1, 0.0215], [0.38, 0.0215]])
	for y in [-0.1, 0.38]:
		k.bar("detail", [[y - 0.01, 0.021], [y - 0.004, 0.026], [y + 0.004, 0.026], [y + 0.01, 0.021]])
	k.bar("dark", [[-0.69, 0.0], [-0.64, 0.03], [-0.58, 0.034], [-0.56, 0.024]], 6)
	k.bar("edge", [[-0.615, 0.037], [-0.603, 0.037]], 6)
	# The socket the head sits in, an armour plate on each face.
	k.bar("dark", [[1.4, 0.022], [1.42, 0.034], [1.54, 0.034], [1.58, 0.024]], 8, Vector2(1.0, 0.75))
	k.bar("detail", [[1.435, 0.038], [1.45, 0.038]], 8, Vector2(1.0, 0.75))
	for z in [-1.0, 1.0]:
		k.plate("plate", PackedVector2Array([Vector2(-0.02, 1.465), Vector2(0.02, 1.465), Vector2(0.014, 1.54), Vector2(-0.014, 1.54)]),
			0.018 * z, 0.029 * z)
	# The head's two halves, the point, and the core between them.
	var gap := 0.008
	var thick := 0.011
	for side in [-1.0, 1.0]:
		var rings := []
		for s in [[1.54, 0.036], [1.67, 0.084], [1.84, 0.06]]:
			var w: float = s[1]
			var flat := maxf(w - 0.028, gap + 0.004)
			rings.append(PackedVector3Array([Vector3(gap * side, s[0], thick), Vector3(flat * side, s[0], thick),
				Vector3(w * side, s[0], 0), Vector3(flat * side, s[0], -thick), Vector3(gap * side, s[0], -thick)]))
		k.loft("steel", rings)
	k.loft("steel", [PackedVector3Array([Vector3(-0.06, 1.84, 0), Vector3(-0.032, 1.84, thick), Vector3(0.032, 1.84, thick),
		Vector3(0.06, 1.84, 0), Vector3(0.032, 1.84, -thick), Vector3(-0.032, 1.84, -thick)]),
		PackedVector3Array([Vector3(0, 2.04, 0), Vector3(0, 2.04, 0), Vector3(0, 2.04, 0), Vector3(0, 2.04, 0), Vector3(0, 2.04, 0), Vector3(0, 2.04, 0)])])
	k.box("edge", Vector3(0, 1.705, 0), Vector3(gap * 2.0 + 0.004, 0.27, 0.013))
	k.plate("detail", PackedVector2Array([Vector2(-0.032, 1.81), Vector2(0.032, 1.81), Vector2(0.038, 1.825),
		Vector2(0.032, 1.84), Vector2(-0.032, 1.84), Vector2(-0.038, 1.825)]), -0.015, 0.015)
	# The fins, a light at each tip.
	k.plate_pair("steel", PackedVector2Array([Vector2(0.03, 1.51), Vector2(0.13, 1.4), Vector2(0.165, 1.27), Vector2(0.085, 1.39),
		Vector2(0.03, 1.42)]), -0.01, 0.01)
	k.plate_pair("edge", PackedVector2Array([Vector2(0.125, 1.385), Vector2(0.168, 1.26), Vector2(0.11, 1.365)]), -0.012, 0.012)
	return k.parts()


## Dagger: a short, wide, angular blade with one glowing edge (toward the knuckles),
## and a guard that wraps round the front of the fist.
static func _dagger() -> Array:
	var k := MeleeKit.new()
	var side := MeleeKit.SIDE
	k.bar("grip", [[-0.075, 0.021], [0.07, 0.021]], 8, Vector2(0.85, 1.0))
	k.bar("dark", [[-0.122, 0.014], [-0.106, 0.03], [-0.086, 0.03], [-0.075, 0.022]], 6)
	k.bar("edge", [[-0.101, 0.033], [-0.092, 0.033]], 6)
	# The guard and the bow down the front of the fingers, in side view.
	k.plate("dark", PackedVector2Array([Vector2(-0.05, 0.095), Vector2(0.07, 0.095), Vector2(0.098, 0.06), Vector2(0.098, -0.055),
		Vector2(0.07, -0.1), Vector2(0.015, -0.112), Vector2(0.015, -0.094), Vector2(0.062, -0.085), Vector2(0.08, -0.05),
		Vector2(0.08, 0.05), Vector2(0.066, 0.068), Vector2(-0.05, 0.068)]), -0.013, 0.013, side)
	k.plate("plate", PackedVector2Array([Vector2(0.09, 0.045), Vector2(0.105, 0.04), Vector2(0.105, -0.04), Vector2(0.09, -0.045)]),
		-0.017, 0.017, side)
	# The blade: a straight back, a clipped point, and the edge.
	k.plate("steel", PackedVector2Array([Vector2(-0.036, 0.095), Vector2(-0.04, 0.38), Vector2(0.034, 0.56), Vector2(0.064, 0.4),
		Vector2(0.056, 0.095)]), -0.008, 0.008, side)
	k.plate("edge", PackedVector2Array([Vector2(0.048, 0.1), Vector2(0.068, 0.1), Vector2(0.077, 0.402), Vector2(0.037, 0.57),
		Vector2(0.029, 0.552), Vector2(0.055, 0.4)]), -0.0035, 0.0035, side)
	k.plate("dark", PackedVector2Array([Vector2(-0.046, 0.095), Vector2(-0.028, 0.095), Vector2(-0.031, 0.375), Vector2(-0.048, 0.385)]),
		-0.012, 0.012, side)
	for x in [-1.0, 1.0]:
		k.plate("plate", PackedVector2Array([Vector2(-0.028, 0.1), Vector2(0.044, 0.1), Vector2(0.048, 0.16), Vector2(-0.028, 0.21)]),
			0.006 * x, 0.012 * x, side)
	return k.parts()


## Brass knuckles: an armoured plate across the knuckles with four glowing studs,
## on a frame round the fist. (One for each fist: see attach_left.)
static func _knuckles() -> Array:
	var k := MeleeKit.new()
	k.box("dark", Vector3(0, 0, 0.006), Vector3(0.028, 0.104, 0.014))
	for y in [-0.066, 0.066]:
		k.box("detail", Vector3(0, y, -0.024), Vector3(0.034, 0.014, 0.076))
	k.plate("dark", MeleeKit.cut_rect(0.03, 0.077, 0.014), -0.046, -0.074)
	k.plate("plate", MeleeKit.cut_rect(0.022, 0.066, 0.01), -0.074, -0.082)
	for i in 4:
		var forward := Transform3D(MeleeKit.Z_AXIS.basis, Vector3(0, -0.045 + 0.03 * i, 0))
		k.bar("dark", [[0.08, 0.0135], [0.088, 0.0135]], 6, Vector2.ONE, forward)
		k.bar("edge", [[0.088, 0.0115], [0.104, 0.006]], 6, Vector2.ONE, forward)
	return k.parts()


# ---------------------------------------------------------------------------
# The third batch of blades

## Energy sword: a hilt with an emitter, and a blade that is all light (in the player's colour).
static func _energy_sword() -> Array:
	var k := MeleeKit.new()
	k.bar("grip", [[-0.1, 0.022], [0.08, 0.022]], 10)
	for y in [-0.06, 0.0, 0.06]:
		k.bar("detail", [[y - 0.006, 0.024], [y + 0.006, 0.024]], 10)
	k.bar("dark", [[-0.13, 0.018], [-0.115, 0.027], [-0.1, 0.025]], 10)
	k.bar("dark", [[0.08, 0.026], [0.1, 0.032], [0.15, 0.032], [0.16, 0.022]], 10)
	k.plate_pair("plate", PackedVector2Array([Vector2(0.03, 0.09), Vector2(0.05, 0.1), Vector2(0.045, 0.15), Vector2(0.03, 0.15)]),
		-0.01, 0.01)
	k.bar("edge", [[0.15, 0.015], [0.2, 0.018], [0.98, 0.018], [1.06, 0.0]], 8)
	return k.parts()
