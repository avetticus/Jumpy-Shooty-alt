class_name SpentCell
extends Node3D
## A spent power cell (or magazine, or shell) thrown out of a gun by a reload: it tumbles
## off, bounces on the level and shrinks away. Looks only: nothing can touch it, pick it
## up or be blocked by it, and every copy of the game throws its own (see ReloadFx).

const LIFE := 1.7        ## seconds it lasts...
const FADE := 0.35       ## ...shrinking away over the last of them
const GRAVITY := 20.0
const BOUNCE := 0.36     ## how much of its speed into the floor it keeps
const GRIP := 0.6        ## how much of its speed along the floor it keeps at a bounce
const LEVEL := 1         ## physics layer 1: the level

var velocity := Vector3.ZERO
var spin := Vector3.ZERO   # radians a second about its own axes
var _age := 0.0
var _resting := false
var _clinked := false


static func spawn(parent: Node, mesh: Mesh, at: Transform3D, velocity_: Vector3, spin_: Vector3) -> SpentCell:
	var cell := SpentCell.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cell.add_child(mi)
	cell.velocity = velocity_
	cell.spin = spin_
	parent.add_child(cell)
	cell.global_transform = at
	return cell


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	if _age > LIFE - FADE:
		scale = Vector3.ONE * maxf((LIFE - _age) / FADE, 0.01)
	if _resting:
		return
	velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + velocity * delta
	var hit := {}
	if is_inside_tree() and get_world_3d() != null and get_world_3d().direct_space_state != null:
		var query := PhysicsRayQueryParameters3D.create(from, to + velocity.normalized() * 0.02, LEVEL)
		hit = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = to
	else:
		var n: Vector3 = hit.normal
		global_position = (hit.position as Vector3) + n * 0.02
		var into := velocity.dot(n)
		if not _clinked and absf(into) > 1.5:   # its first knock on the level
			_clinked = true
			var sound := get_node_or_null("/root/Sound")   # (looked up, not named: a test run as a script has no autoloads)
			if sound != null:
				sound.play_at("cell_clink", global_position, "move", 0.0, 0.12)
		velocity = (velocity - n * into) * GRIP - n * into * BOUNCE
		spin *= 0.45
		if absf(into) < 1.2 and n.y > 0.6:
			_resting = true   # too slow to bounce again: it lies where it is
			return
	var turn := spin * delta
	if turn.length_squared() > 0.0:
		basis = (basis * Basis.from_euler(turn)).orthonormalized() * Basis.from_scale(scale)
