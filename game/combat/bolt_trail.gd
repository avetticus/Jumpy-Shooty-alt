class_name BoltTrail
extends MeshInstance3D
## The streak a crossbow bolt leaves behind it: a thin ribbon through the places the
## bolt has just been, so everyone sees the arc it flies as it drops. Its flat side
## turns to the camera, it is white-hot at the bolt and fades to the shooter's trim
## colour (or the weapon's tracer_color) behind, and it narrows and fades as it ages.
##
## It lives beside the bolt (in the same parent, drawn in the world), not under it, so
## that it outlasts it: Projectile moves it along each step (follow) and lets it go when
## the bolt lands or runs out (release); then it stops growing, fades out where it was
## and frees itself. One small ImmediateMesh each, a point every metre or so: cheap.

const LIFE := 0.4           ## seconds each bit of the streak lasts
const SPACING := 1.0        ## metres between the points it keeps (a bolt step is about half that)
const WIDTH := 0.022        ## half its width at the bolt, in metres...
const MIN_WIDTH := 0.002    ## ...and never thinner than this per metre away from the camera (so it reads far off)

var _points: Array = []     # [position, time, starts a new piece (out of a portal)]
var _head := Vector3.INF    # where the bolt is now: the streak's newest end
var _head_t := 0.0
var _clock := 0.0           # the bolt's own time while it flies (a killcam steps it), then ours
var _released := false
var _cut := false
var _mesh := ImmediateMesh.new()
var _color := Color.WHITE
var _hot := Color.WHITE


func setup(color: Color) -> BoltTrail:
	name = "BoltTrail"
	_color = color.lightened(0.1)
	_hot = color.lerp(Color.WHITE, 0.8)
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0   # (the mesh is rebuilt in world space every frame: never cull it)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	material_override = m
	return self


## The bolt is now at `at` (its tail), `delta` seconds on from the last step.
func follow(at: Vector3, delta: float) -> void:
	if _released:
		return
	_clock += delta
	_head = at
	_head_t = _clock
	if _cut or _points.is_empty() or (_points[-1][0] as Vector3).distance_squared_to(at) >= SPACING * SPACING:
		_points.append([at, _clock, _cut])
		_cut = false


## The bolt went into a portal: the streak picks up again from where it comes out
## (no line across the gap).
func cut() -> void:
	_cut = true


## The bolt has landed or gone: stop growing and fade out where it is.
func release() -> void:
	if not _released and _head != Vector3.INF and (_points.is_empty() or _points[-1][1] < _head_t):
		_points.append([_head, _head_t, _cut])   # (keep its very end)
	_released = true


func is_released() -> bool:
	return _released


## How many points of the streak are still showing.
func points() -> int:
	return _points.size()


func _process(delta: float) -> void:
	if _released:
		_clock += delta
	while not _points.is_empty() and _clock - float(_points[0][1]) > LIFE:
		_points.pop_front()
	if _released and _points.is_empty():
		queue_free()
		return
	if DisplayServer.get_name() != "headless":
		_redraw()


func _redraw() -> void:
	_mesh.clear_surfaces()
	var line: Array = _points.duplicate()
	if not _released and _head != Vector3.INF and (line.is_empty() or (line[-1][0] as Vector3) != _head):
		line.append([_head, _head_t, _cut])
	var n := line.size()
	if n < 2:
		return
	global_transform = Transform3D.IDENTITY
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	var eye: Vector3 = cam.global_position if cam else line[-1][0] + Vector3.UP * 10.0
	var open := false
	for i in n:
		var p: Vector3 = line[i][0]
		if i > 0 and line[i][2]:   # out of a portal: a new piece
			if open:
				_mesh.surface_end()
				open = false
		if not open:
			if i + 1 >= n or line[i + 1][2]:
				continue   # (a piece one point long draws nothing)
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			open = true
		var back: Vector3 = line[i - 1][0] if i > 0 and not line[i][2] else p
		var ahead: Vector3 = line[i + 1][0] if i + 1 < n and not line[i + 1][2] else p
		var along := ahead - back
		var side := along.cross(eye - p)
		if side.length_squared() < 0.000001:
			side = along.cross(Vector3.UP)
		side = side.normalized()
		var age := clampf((_clock - float(line[i][1])) / LIFE, 0.0, 1.0)
		var fade := 1.0 - age
		var half := maxf(WIDTH, MIN_WIDTH * p.distance_to(eye)) * lerpf(0.35, 1.0, fade)
		var col := _hot.lerp(_color, minf(age * 4.0, 1.0))
		col.a = 0.9 * fade
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(p - side * half)
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(p + side * half)
	if open:
		_mesh.surface_end()
