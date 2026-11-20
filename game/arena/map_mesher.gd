class_name MapMesher
extends RefCounted
## Turns a map's pieces into meshes: one mesh per kind (material), with every piece
## of that kind merged into it, so a map of a few thousand pieces draws in a handful
## of calls. Faces are flat-shaded; a piece's tint goes into the vertex colours.
##
## `shade` darkens faces by the way they point, baked into the vertex colours:
## (faces looking along x, faces looking along z, faces looking down); tops stay
## at 1. It gives plain boxes some form even in flat light. Vector3.ONE = off.
## `shade_basis` turns the normals before shading: the editor builds each block's
## mesh in the block's own frame, but shades it by the way its faces point in the map.

static var _shade := Vector3.ONE
static var _shade_basis := Basis()

const BOX_FACES := [   # normal, then the two in-plane axes (u, v) with u x v = normal
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
]


## kind -> ArrayMesh
static func build(pieces: Array, shade: Vector3 = Vector3.ONE, shade_basis: Basis = Basis()) -> Dictionary:
	_shade = shade
	_shade_basis = shade_basis
	var by_kind := {}
	for piece in pieces:
		if piece.get("hidden", false):
			continue
		if not by_kind.has(piece.kind):
			by_kind[piece.kind] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
		var buf: Array = by_kind[piece.kind]
		match piece.shape:
			"cyl": _prism(buf, piece, 0.0)
			"tube": _prism(buf, piece, piece.get("inner", 0.0))
			"cone": _cone(buf, piece)
			"wedge", "bevel", "dome", "arch", "hull": _hulls(buf, piece)
			_: _box(buf, piece)
	var result := {}
	for kind in by_kind:
		var buf: Array = by_kind[kind]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = buf[0]
		arrays[Mesh.ARRAY_NORMAL] = buf[1]
		arrays[Mesh.ARRAY_COLOR] = buf[2]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result[kind] = mesh
	return result


## The same mesh, marked as part of something that moves (a MapMover's body): its
## second UV says "measure my pattern from my own frame, not the map's", which the
## surface shader reads (map_surface.gdshader). A pattern measured from the map stays
## where it is while the block moves through it, and that shimmers.
static func riding(mesh: ArrayMesh) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var mark := PackedVector2Array()
	mark.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	mark.fill(Vector2(1, 0))
	arrays[Mesh.ARRAY_TEX_UV2] = mark
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


static func _quad(buf: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, color: Color) -> void:
	# a, b, c, d go counter-clockwise seen from the front (the side `n` points to).
	var verts: PackedVector3Array = buf[0]
	var normals: PackedVector3Array = buf[1]
	var colors: PackedColorArray = buf[2]
	color = _shaded(color, n)
	for v in [a, c, b, a, d, c]:   # Godot's front faces are clockwise
		verts.append(v)
		normals.append(n)
		colors.append(color)


static func _box(buf: Array, piece: Dictionary) -> void:
	var xf: Transform3D = piece.xf
	var h: Vector3 = piece.size * 0.5
	var color: Color = piece.get("tint", Color.WHITE)
	for face in BOX_FACES:
		var n: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var c: Vector3 = n * h
		var du: Vector3 = u * h
		var dv: Vector3 = v * h
		_quad(buf, xf * (c - du - dv), xf * (c + du - dv), xf * (c + du + dv), xf * (c - du + dv), xf.basis * n, color)


## A cylinder with flat sides (inner = 0), or a pipe you can see through (inner > 0).
static func _prism(buf: Array, piece: Dictionary, inner: float) -> void:
	var xf: Transform3D = piece.xf
	var color: Color = piece.get("tint", Color.WHITE)
	var sides: int = piece.get("sides", 12)
	var r: float = piece.size.x * 0.5
	var ri: float = inner * 0.5
	var hy: float = piece.size.y * 0.5
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var am := (a0 + a1) * 0.5
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n := Vector3(cos(am), 0, sin(am))
		var up := Vector3(0, hy, 0)
		# outside wall
		_quad(buf, xf * (d1 * r - up), xf * (d0 * r - up), xf * (d0 * r + up), xf * (d1 * r + up), xf.basis * n, color)
		if ri > 0.0:
			_quad(buf, xf * (d0 * ri - up), xf * (d1 * ri - up), xf * (d1 * ri + up), xf * (d0 * ri + up), xf.basis * -n, color)
			_quad(buf, xf * (d0 * ri + up), xf * (d1 * ri + up), xf * (d1 * r + up), xf * (d0 * r + up), xf.basis * Vector3.UP, color)
			_quad(buf, xf * (d1 * ri - up), xf * (d0 * ri - up), xf * (d0 * r - up), xf * (d1 * r - up), xf.basis * Vector3.DOWN, color)
		else:
			_tri(buf, xf * up, xf * (d1 * r + up), xf * (d0 * r + up), xf.basis * Vector3.UP, color)
			_tri(buf, xf * -up, xf * (d0 * r - up), xf * (d1 * r - up), xf.basis * Vector3.DOWN, color)


## A cone with flat sides, coming to a point (top = 0) or cut off flat at the top.
## Its corners: cone_points() (the collision shape is built from the same points).
static func _cone(buf: Array, piece: Dictionary) -> void:
	var xf: Transform3D = piece.xf
	var color: Color = piece.get("tint", Color.WHITE)
	var sides: int = piece.get("sides", 12)
	var r: float = piece.size.x * 0.5
	var rt: float = minf(piece.get("top", 0.0) * 0.5, r)
	var up := Vector3(0, piece.size.y * 0.5, 0)
	for i in sides:
		var d0 := Vector3(cos(TAU * i / sides), 0, sin(TAU * i / sides))
		var d1 := Vector3(cos(TAU * (i + 1) / sides), 0, sin(TAU * (i + 1) / sides))
		var b0 := d0 * r - up
		var b1 := d1 * r - up
		var n := cone_side_normal(d0, d1, r, rt, piece.size.y)
		if rt > 0.0:
			_quad(buf, xf * b1, xf * b0, xf * (d0 * rt + up), xf * (d1 * rt + up), xf.basis * n, color)
			_tri(buf, xf * up, xf * (d1 * rt + up), xf * (d0 * rt + up), xf.basis * Vector3.UP, color)
		else:
			_tri(buf, xf * b1, xf * b0, xf * up, xf.basis * n, color)
		_tri(buf, xf * -up, xf * b0, xf * b1, xf.basis * Vector3.DOWN, color)


## The outward normal of the cone's side between the corners `d0` and `d1` (unit
## directions round its axis), for a foot radius `r`, top radius `rt` and `height`.
static func cone_side_normal(d0: Vector3, d1: Vector3, r: float, rt: float, height: float) -> Vector3:
	var mid := (d0 + d1) * 0.5           # the middle of that side, at radius 1 (flat part)
	var flat := mid.length()
	return (mid / flat * height + Vector3.UP * (r - rt) * flat).normalized()


## A cone's corners in its own frame: the foot's ring, then the top's ring (or the tip).
static func cone_points(piece: Dictionary) -> PackedVector3Array:
	var sides: int = piece.get("sides", 12)
	var r: float = piece.size.x * 0.5
	var rt: float = minf(piece.get("top", 0.0) * 0.5, r)
	var hy: float = piece.size.y * 0.5
	var pts := PackedVector3Array()
	for i in sides:
		pts.append(Vector3(cos(TAU * i / sides) * r, -hy, sin(TAU * i / sides) * r))
	if rt > 0.0:
		for i in sides:
			pts.append(Vector3(cos(TAU * i / sides) * rt, hy, sin(TAU * i / sides) * rt))
	else:
		pts.append(Vector3(0, hy, 0))
	return pts


## What a tube is to bump into: its wall, one convex lump per flat side (the four
## corners of that side's stretch of ring, at the top and at the foot), in its own
## frame. The corners are where _prism draws them: corner i at TAU * i / sides round
## from +x toward +z, outside at the diameter (x) and inside at Inner. A tube with no
## hole (Inner 0 or less) has no wall to give: it is drawn as a cylinder and is bumped
## into as one, so this gives nothing for it. A hole as wide as the tube or wider
## leaves the thinnest wall a hollow dome is allowed (1 cm), at the outside diameter,
## so what you see from outside is never something you walk through.
static func tube_hulls(piece: Dictionary) -> Array:
	var inner: float = piece.get("inner", 0.0)
	if inner <= 0.0:
		return []
	var sides: int = piece.get("sides", 12)
	var r: float = piece.size.x * 0.5
	var ri: float = maxf(minf(inner * 0.5, r - 0.01), 0.0)
	var hy: float = piece.size.y * 0.5
	var hulls := []
	for i in sides:
		var d0 := Vector3(cos(TAU * i / sides), 0, sin(TAU * i / sides))
		var d1 := Vector3(cos(TAU * (i + 1) / sides), 0, sin(TAU * (i + 1) / sides))
		var lump := PackedVector3Array()
		for reach in [ri, r]:
			for y in [-hy, hy]:
				lump.append(d0 * reach + Vector3(0, y, 0))
				lump.append(d1 * reach + Vector3(0, y, 0))
		hulls.append(lump)
	return hulls


# ---------------------------------------------------------------------------
# Wedges, bevelled boxes, domes and arches. Each is one or more convex lumps, given
# by their corners (hull_points); what you see and what you bump into are both made
# from those same corners, so they always agree.

## The convex lumps a piece is made of, each a list of corners in the piece's own
## frame. A wedge, a bevelled box, a whole solid dome and a hull are one lump; a
## hollow or cut-open dome and an arch are several.
static func hull_points(piece: Dictionary) -> Array:
	match piece.shape:
		"wedge": return [wedge_points(piece)]
		"bevel": return [bevel_points(piece)]
		"dome": return dome_hulls(piece)
		"arch": return arch_hulls(piece)
		"hull": return [piece.points]
	return []


# ---------------------------------------------------------------------------
# Hulls: blocks of any convex shape, given by their corners (MapBlock.Shape.HULL).

## A hull block has at most this many corners: finding a hull's faces gets slow past
## it, and the map is built from every block's faces when it loads.
const MAX_HULL_CORNERS := 32


## The corners of the convex lump round `pts`: the points that are a corner of one
## of its faces, in the order given, each once. Points inside it, or in the middle
## of a face or an edge, are left out. Empty if `pts` are all in one plane.
static func hull_corners(pts: PackedVector3Array) -> PackedVector3Array:
	var planes := hull_planes(pts)
	var out := PackedVector3Array()
	for p in pts:
		# A corner lies on three faces or more; a point in the middle of an edge on two,
		# in the middle of a face on one, inside on none.
		var on := 0
		for plane in planes:
			if absf(plane.distance_to(p)) <= 0.0005:
				on += 1
		if on < 3:
			continue
		var seen := false
		for q in out:
			if q.distance_to(p) <= 0.0005:
				seen = true
				break
		if not seen:
			out.append(p)
	return out


## The faces of the convex lump round `pts` as planes, each facing out (a point is
## inside the lump when it is behind every one of them). Fewer than 4 when the
## points are all in one plane (or there are too few): no solid shape.
static func hull_planes(pts: PackedVector3Array) -> Array[Plane]:
	var out: Array[Plane] = []
	for face in hull_faces(pts):
		var n: Vector3 = face[0]
		var d := 0.0
		for p: Vector3 in face[1]:
			d += n.dot(p)
		out.append(Plane(n, d / (face[1] as Array).size()))   # (through the middle of its corners)
	return out


## Is `p` (in the hull's own frame) inside the hull with these `planes`, or no more
## than `margin` metres outside it?
static func hull_has(planes: Array, p: Vector3, margin: float = 0.0) -> bool:
	for plane: Plane in planes:
		if plane.distance_to(p) > margin:
			return false
	return true


## How high the top of the hull with these `planes` is at (`x`, `z`) in its own
## frame: the y of its upper surface straight above or below that point. -INF if
## the point is not over the hull, with `margin` metres to spare round its sides.
static func hull_top(planes: Array, x: float, z: float, margin: float = 0.0) -> float:
	var top := INF
	var bottom := -INF
	for plane: Plane in planes:
		var n := plane.normal
		var level := plane.d - n.x * x - n.z * z
		if n.y > 0.001:
			top = minf(top, level / n.y)       # under this face
		elif n.y < -0.001:
			bottom = maxf(bottom, level / n.y)  # over this face
		elif -level > margin * Vector2(n.x, n.z).length():
			return -INF                         # outside an upright side
	if top == INF or bottom > top + margin:
		return -INF
	return top


## A slope: tall at the back (-z), down to nothing at the front (+z).
static func wedge_points(piece: Dictionary) -> PackedVector3Array:
	var h: Vector3 = piece.size * 0.5
	return PackedVector3Array([
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)])


## A box with every edge cut off: three corners where each of the box's was.
static func bevel_points(piece: Dictionary) -> PackedVector3Array:
	var h: Vector3 = piece.size * 0.5
	var c: float = clampf(piece.get("bevel", 0.1), 0.0, minf(h.x, minf(h.y, h.z)) * 0.98)
	var pts := PackedVector3Array()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				pts.append(Vector3(sx * h.x, sy * (h.y - c), sz * (h.z - c)))
				pts.append(Vector3(sx * (h.x - c), sy * h.y, sz * (h.z - c)))
				pts.append(Vector3(sx * (h.x - c), sy * (h.y - c), sz * h.z))
	return pts


## How many rings a dome has from its foot to its top.
static func dome_rings(piece: Dictionary) -> int:
	return maxi(2, int(piece.get("sides", 12)) / 4)


## A point on a dome's skin (`shrink` metres inside it): `i` of `sides` steps round,
## ring `j` of dome_rings() up.
static func _dome_point(piece: Dictionary, i: int, j: int, shrink: float) -> Vector3:
	var sides: int = piece.get("sides", 12)
	var arc: float = deg_to_rad(piece.get("arc", 360.0))
	var a := PI * 0.5 + (TAU - arc) * 0.5 + arc * i / sides   # the open slice faces +z
	var up := PI * 0.5 * j / dome_rings(piece)
	var rx: float = maxf(piece.size.x * 0.5 - shrink, 0.0)
	var rz: float = maxf(piece.size.z * 0.5 - shrink, 0.0)
	var height: float = maxf(piece.size.y - shrink, 0.0)
	return Vector3(cos(a) * cos(up) * rx, sin(up) * height - piece.size.y * 0.5, sin(a) * cos(up) * rz)


static func _dome_wall(piece: Dictionary) -> float:
	var inner: float = piece.get("inner", 0.0)
	return clampf((piece.size.x - inner) * 0.5, 0.01, piece.size.x * 0.5) if inner > 0.0 else 0.0


static func dome_hulls(piece: Dictionary) -> Array:
	var sides: int = piece.get("sides", 12)
	var rings := dome_rings(piece)
	var wall := _dome_wall(piece)
	var whole: bool = piece.get("arc", 360.0) >= 359.9
	var foot := Vector3(0, -piece.size.y * 0.5, 0)
	var hulls := []
	if wall <= 0.0 and whole:
		var all := PackedVector3Array()
		for i in sides:
			for j in rings:
				all.append(_dome_point(piece, i, j, 0.0))
		all.append(_dome_point(piece, 0, rings, 0.0))
		return [all]
	for i in sides:
		if wall <= 0.0:   # solid, with a slice out: one lump per side, from the middle out
			var lump := PackedVector3Array([foot])
			for j in rings + 1:
				lump.append(_dome_point(piece, i, j, 0.0))
				if j < rings:
					lump.append(_dome_point(piece, i + 1, j, 0.0))
			hulls.append(lump)
			continue
		for j in rings:     # a shell: one lump per panel
			var lump := PackedVector3Array()
			for shrink in [0.0, wall]:
				lump.append(_dome_point(piece, i, j, shrink))
				lump.append(_dome_point(piece, i + 1, j, shrink))
				lump.append(_dome_point(piece, i, j + 1, shrink))
				if j + 1 < rings:
					lump.append(_dome_point(piece, i + 1, j + 1, shrink))
			hulls.append(lump)
	return hulls


## An arch's opening: half its width and its height.
static func arch_opening(piece: Dictionary) -> Vector2:
	var inner: float = piece.get("inner", 0.0)
	var half: float = piece.size.x * 0.5
	return Vector2(minf(inner * 0.5, half) if inner > 0.0 else half, clampf(piece.size.y - piece.get("top", 0.0), 0.01, piece.size.y))


static func arch_hulls(piece: Dictionary) -> Array:
	var h: Vector3 = piece.size * 0.5
	var open := arch_opening(piece)
	var sides: int = maxi(int(piece.get("sides", 12)), 2)
	var hulls := []
	for k in sides:
		var lump := PackedVector3Array()
		for t in [k, k + 1]:
			var a: float = PI * t / sides
			var x: float = cos(a) * open.x
			for z in [-h.z, h.z]:
				lump.append(Vector3(x, -h.y + sin(a) * open.y, z))
				lump.append(Vector3(x, h.y, z))
		hulls.append(lump)
	if open.x < h.x - 0.001:   # a leg either side of the opening
		for s in [-1.0, 1.0]:
			var leg := PackedVector3Array()
			for x in [s * open.x, s * h.x]:
				for y in [-h.y, h.y]:
					for z in [-h.z, h.z]:
						leg.append(Vector3(x, y, z))
			hulls.append(leg)
	return hulls


## Draws each lump's faces (its convex hull), leaving out the faces two lumps share.
static func _hulls(buf: Array, piece: Dictionary) -> void:
	var xf: Transform3D = piece.xf
	var color: Color = piece.get("tint", Color.WHITE)
	if piece.shape == "dome" and _dome_wall(piece) <= 0.0 and piece.get("arc", 360.0) >= 359.9:
		# A whole solid dome is one lump of many corners: its panels are known, no need to look for them.
		var sides: int = piece.get("sides", 12)
		var rings := dome_rings(piece)
		var foot := PackedVector3Array()
		for i in sides:
			foot.append(_dome_point(piece, sides - i, 0, 0.0))
			for j in rings:
				var a := _dome_point(piece, i, j, 0.0)
				var b := _dome_point(piece, i + 1, j, 0.0)
				var c := _dome_point(piece, i + 1, j + 1, 0.0)
				var d := _dome_point(piece, i, j + 1, 0.0)
				var n := (c - a).cross(b - a) if j + 1 == rings else (c - a).cross(b - d)
				n = n.normalized()
				if n.dot(a + c) < 0.0:
					n = -n
				_flat(buf, xf, [a, b, c] if j + 1 == rings else [a, b, c, d], n, color)
		_flat(buf, xf, Array(foot), Vector3.DOWN, color)
		return
	# Every face of every lump; a face two lumps share (the same place, looking opposite
	# ways) is inside the piece and is left out.
	var faces := []   # [normal, corners in order, a key for where its middle is]
	var count := {}
	for pts in hull_points(piece):
		for face in hull_surface(pts):
			var mid := Vector3.ZERO
			for p in face[1]:
				mid += p
			mid /= face[1].size()
			var key := Vector3i((mid * 200.0).round())
			face.append(key)
			count[key] = count.get(key, 0) + 1
			faces.append(face)
	for face in faces:
		if count[face[2]] == 1:
			_flat(buf, xf, face[1], face[0], color)


## One flat face with these corners (in the piece's own frame, in order round it,
## either way), facing along `n`.
static func _flat(buf: Array, xf: Transform3D, corners: Array, n: Vector3, color: Color) -> void:
	if corners.size() < 3:
		return
	var turn: Vector3 = ((corners[1] as Vector3) - corners[0]).cross((corners[2] as Vector3) - corners[0])
	if turn.dot(n) < 0.0:
		corners = corners.duplicate()
		corners.reverse()
	var out: Vector3 = xf.basis * n
	for k in range(1, corners.size() - 1):
		_tri(buf, xf * corners[0], xf * corners[k], xf * corners[k + 1], out, color)


## The flat faces of the convex lump with these corners, as the map tools work with
## them (its planes, its edges, which face is which): [[normal, corners going
## counter-clockwise seen from outside], ...]. Corners that lie in one plane make one
## face, its outline: a point inside a face, or in the middle of one of its edges, is
## not one of its corners. Points within half a millimetre of a plane count as on it,
## and faces in all but the same plane are one face, so a slanted face stays one face
## however often its corners are rounded. (For drawing, see hull_surface: on points
## that have drifted badly these faces may not quite close up.)
static func hull_faces(pts: PackedVector3Array) -> Array:
	var n := pts.size()
	var groups := []   # one per face: [normal (out), how far out its plane is, {index of a point on it: true}]
	for a in n:
		for b in range(a + 1, n):
			for c in range(b + 1, n):
				var ab := pts[b] - pts[a]
				var ac := pts[c] - pts[a]
				var normal := ab.cross(ac)
				if normal.length() < 0.001 * ab.length() * ac.length():
					continue   # (all but in a line: the plane through them could lean any way)
				normal = normal.normalized()
				var d := normal.dot(pts[a])
				var above := false
				var below := false
				var on := []
				for i in n:
					var s := normal.dot(pts[i]) - d
					if s > 0.0005:
						above = true
					elif s < -0.0005:
						below = true
					else:
						on.append(i)
					if above and below:
						break   # points on both sides: not a face
				if above and below:
					continue
				if above:
					normal = -normal
				# Other threes on the same face find it again, perhaps with a few points
				# more or less on it (when they have drifted a hair out of one plane): all
				# of them go to one face, never two all but the same (cutting with both
				# would make stray corners).
				d = normal.dot(pts[a])
				var group: Array = []
				for g in groups:
					if (g[0] as Vector3).dot(normal) > 0.9999 and absf(float(g[1]) - d) < 0.001:
						group = g
						break
				if group.is_empty():
					group = [normal, d, {}]
					groups.append(group)
				for i in on:
					group[2][i] = true
	var faces := []
	for g in groups:
		var on_points := []
		for i in (g[2] as Dictionary):
			on_points.append(pts[i])
		var corners := _outline(on_points, g[0], 0.0005)
		if corners.size() < 3:
			continue
		# The face's own way out, from all its corners, not just the three it was found
		# by; a face with next to no area is no face.
		var fit := _twice_area(corners)
		if fit.length() < 2e-6:
			continue
		fit = fit.normalized()
		faces.append([fit if fit.dot(g[0]) > 0.0 else -fit, corners])
	return faces


## The faces of the convex lump with these corners as they are drawn ([[normal,
## corners going counter-clockwise seen from outside], ...]): always a closed surface,
## with no face missing, overlapping or folded over, even for points that have drifted
## or were dragged a few millimetres apart.
##
## These are the lump's faces as they are, to within a fiftieth of a millimetre: points
## truly in one plane (a box's side) make one face, points a hair out of one plane make
## several flat ones, side by side, which look the same. Together they always cover the
## lump with no gap or overlap. (The map tools use hull_faces, where a face whose
## corners are a little out of one plane is still one face.)
static func hull_surface(pts: PackedVector3Array) -> Array:
	# On a plane means on it, to a nanometre: any looser and three points of a face a
	# hair out of one plane can call it one face where another three call it two, and the
	# surface gets a face twice in one place and none in another. The sums are done in
	# 64-bit numbers (Godot's vectors are 32-bit, and a face only millimetres wide would
	# come out leaning the wrong way); 32-bit points truly in one plane, as a box's side
	# is, still come out exactly on it.
	const EXACT := 1e-9
	var n := pts.size()
	var x := PackedFloat64Array()
	var y := PackedFloat64Array()
	var z := PackedFloat64Array()
	for p in pts:
		x.append(p.x)
		y.append(p.y)
		z.append(p.z)
	var faces := []   # [normal (out), its corners in order]
	var seen := {}
	for a in n:
		for b in range(a + 1, n):
			var ux := x[b] - x[a]
			var uy := y[b] - y[a]
			var uz := z[b] - z[a]
			for c in range(b + 1, n):
				var vx := x[c] - x[a]
				var vy := y[c] - y[a]
				var vz := z[c] - z[a]
				var nx := uy * vz - uz * vy
				var ny := uz * vx - ux * vz
				var nz := ux * vy - uy * vx
				var length := sqrt(nx * nx + ny * ny + nz * nz)
				if length < 1e-12:
					continue   # (in a line)
				var above := false
				var below := false
				var on := []
				for i in n:
					# How far in front of the plane the point is (from a point on it, so
					# that a point truly in it comes out as nothing at all).
					var s := ((x[i] - x[a]) * nx + (y[i] - y[a]) * ny + (z[i] - z[a]) * nz) / length
					if s > EXACT:
						above = true
					elif s < -EXACT:
						below = true
					else:
						on.append(i)
					if above and below:
						break   # points on both sides: not a face
				if above and below:
					continue
				var normal := Vector3(nx / length, ny / length, nz / length)
				if above:
					normal = -normal
				var key := str(on)   # (other threes on the same face find it again)
				if seen.has(key):
					continue
				seen[key] = true
				var on_points := []
				for i in on:
					on_points.append(pts[i])
				var ring := _outline(on_points, normal, 0.0)
				if ring.size() >= 3 and _twice_area(ring).length() > 1e-12:
					faces.append([normal, ring])
	if faces.size() < 4:
		return []   # all in one plane (or too few points): no solid
	return faces


## Twice a flat ring's area, facing the way its corners turn counter-clockwise
## (Newell's method).
static func _twice_area(ring: Array) -> Vector3:
	var out := Vector3.ZERO
	for k in ring.size():
		var p: Vector3 = ring[k]
		var q: Vector3 = ring[(k + 1) % ring.size()]
		out += Vector3((p.y - q.y) * (p.z + q.z), (p.z - q.z) * (p.x + q.x), (p.x - q.x) * (p.y + q.y))
	return out


## The outline of `points` (all in one plane facing along `normal`): its corners in
## order, counter-clockwise seen from the side it faces. A point inside the outline, in
## the middle of one of its sides or on top of another (within `slack` metres) is left out.
static func _outline(points: Array, normal: Vector3, slack := 0.0005) -> Array:
	var u := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := normal.cross(u)   # (u, v, normal) turn the right way: counter-clockwise in u, v is seen from outside
	var flat := []
	for p: Vector3 in points:
		flat.append([Vector2(p.dot(u), p.dot(v)), p])
	flat.sort_custom(func(p: Array, q: Array) -> bool:
		return p[0].x < q[0].x or (p[0].x == q[0].x and p[0].y < q[0].y))
	# Andrew's monotone chain: the lower side left to right, then the upper side back.
	var chain := []
	for pass_ in 2:
		var start := chain.size()
		var order := flat if pass_ == 0 else flat.duplicate()
		if pass_ == 1:
			order.reverse()
		for p in order:
			while chain.size() - start >= 2 and _bends_back(chain[-2][0], chain[-1][0], p[0], slack):
				chain.pop_back()
			if chain.size() - start >= 1 and (chain[-1][0] as Vector2).distance_to(p[0]) <= slack:
				continue
			chain.append(p)
		chain.pop_back()   # (the last of each side is the first of the next)
	var out := []
	for c in chain:
		if out.is_empty() or (out[-1] as Vector3).distance_to(c[1]) > slack:
			out.append(c[1])
	if out.size() > 1 and (out[0] as Vector3).distance_to(out[-1]) <= slack:
		out.pop_back()
	return out


## Going from `o` to `a` and on to `b`, does the way turn clockwise, or run straight on
## (within `slack` metres)? Then `a` is not a corner of a counter-clockwise outline.
static func _bends_back(o: Vector2, a: Vector2, b: Vector2, slack: float) -> bool:
	var turn := (a - o).cross(b - o)
	return turn <= slack * maxf((a - o).length(), (b - o).length())


static func _tri(buf: Array, a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color) -> void:
	var verts: PackedVector3Array = buf[0]
	var normals: PackedVector3Array = buf[1]
	var colors: PackedColorArray = buf[2]
	color = _shaded(color, n)
	for v in [a, c, b]:
		verts.append(v)
		normals.append(n)
		colors.append(color)


static func _shaded(color: Color, n: Vector3) -> Color:
	if _shade == Vector3.ONE:
		return color
	n = _shade_basis * n
	var flat := n.x * n.x + n.z * n.z
	var side: float = lerpf(_shade.x, _shade.y, n.z * n.z / flat) if flat > 0.0001 else 1.0
	var k: float = lerpf(side, 1.0, n.y) if n.y >= 0.0 else lerpf(side, _shade.z, -n.y)
	return Color(color.r * k, color.g * k, color.b * k, color.a)
