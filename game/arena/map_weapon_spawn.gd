@tool
class_name MapWeaponSpawn
extends Marker3D
## Deathmatch: a place a weapon floats, waiting to be picked up (see WeaponPickup).
## Stand it on a floor; the weapon hovers about a metre above it. Walk through it and
## the weapon is yours until you die; it comes back Match.PICKUP_RESPAWN seconds after
## it was taken. In other games the spot is empty. The orange ghost is editor-only.

@export_enum("pistol", "revolver", "machine_pistol", "akimbo", "derringer",
	"shotgun", "break_action", "air_cannon",
	"smg", "rifle", "burst_rifle", "lmg", "minigun", "battle_rifle", "laser_rifle", "nail_gun",
	"lever_action", "bolt_action", "sniper", "railgun", "crossbow", "anti_materiel",
	"rocket_launcher", "grenade_launcher", "plasma_cannon",
	"sword", "hammer", "dagger", "brass_knuckles", "spear", "axe", "bat",
	"scythe", "mace", "machete", "wrench", "energy_sword", "karate") var weapon := "pistol":   ## (WeaponData.IDS)
	set(v):
		weapon = v
		if _label:
			_label.text = v.to_upper()

const HOVER := 1.0   ## the same as WeaponPickup.HOVER (kept apart so map scenes need no game code)

var _ghost: MeshInstance3D
var _label: Label3D


func _enter_tree() -> void:
	if not Engine.is_editor_hint() or _ghost != null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.15, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.25, 0.25)
	_ghost = MeshInstance3D.new()
	_ghost.mesh = box
	_ghost.position.y = HOVER
	_ghost.material_override = mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost, false, Node.INTERNAL_MODE_FRONT)
	var pad := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.6
	disc.bottom_radius = 0.6
	disc.height = 0.04
	pad.mesh = disc
	pad.position.y = 0.03
	pad.material_override = mat
	_ghost.add_child(pad)
	pad.position.y = 0.03 - HOVER
	_label = Label3D.new()
	_label.text = weapon.to_upper()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 48
	_label.pixel_size = 0.006
	_label.modulate = Color(1.0, 0.75, 0.4)
	_label.position.y = 0.45
	_ghost.add_child(_label)
