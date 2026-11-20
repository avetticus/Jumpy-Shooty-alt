class_name ReloadPuff
extends MeshInstance3D
## A puff of steam from a reload (a gun venting): it drifts off,
## swells and fades. Looks only, like SpentCell: every copy of the game makes its own.

var velocity := Vector3.ZERO
var life := 0.5
var _age := 0.0
var _color := Color.WHITE
var _mat: StandardMaterial3D

static var _ball: SphereMesh


static func spawn(parent: Node, at: Vector3, velocity_: Vector3, color: Color, radius: float, life_: float) -> ReloadPuff:
	if parent == null:
		return null
	if _ball == null:
		_ball = SphereMesh.new()
		_ball.radius = 1.0
		_ball.height = 2.0
		_ball.radial_segments = 8
		_ball.rings = 4
	var puff := ReloadPuff.new()
	puff.mesh = _ball
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puff._mat = StandardMaterial3D.new()
	puff._mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff._mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff._mat.albedo_color = color
	puff.material_override = puff._mat
	puff._color = color
	puff.velocity = velocity_
	puff.life = life_
	parent.add_child(puff)
	puff.global_position = at
	puff.scale = Vector3.ONE * radius
	puff.set_meta("radius", radius)
	return puff


func _process(delta: float) -> void:
	_age += delta
	if _age >= life:
		queue_free()
		return
	var u := _age / life
	velocity = velocity.lerp(Vector3.UP * 0.25, minf(delta * 3.0, 1.0))
	global_position += velocity * delta
	scale = Vector3.ONE * float(get_meta("radius")) * lerpf(0.7, 2.6, sqrt(u))
	_mat.albedo_color = Color(_color.r, _color.g, _color.b, _color.a * (1.0 - u) * (1.0 - u))
