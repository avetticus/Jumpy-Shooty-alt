extends SceneTree
## Flicker check: no two surfaces of different colours lie in the same plane where
## both can be seen. The renderer cannot tell which of two such surfaces is in front,
## so the spot flickers between the two colours as the camera moves ("z-fighting").
##
## It looks at every drawn face of every block (boxes at any angle, cylinders, tubes
## and cones, every side, not only floors), pairs up the ones that face the same way
## in the same plane, and fails if two of different kind or tint overlap somewhere
## that no other block covers. It also fails if a sign (Label3D) lies in the surface
## of the wall behind it.
##
## Run: godot --headless --path . --script tests/map_flicker_test.gd
## Other maps: FLICKER_MAPS="office,halcyon" (or "all"); FLICKER_LIST=40 prints more
## of what it found; FLICKER_GAP=0.02 also reports surfaces closer than 2 cm (they
## can still flicker far away on the Compatibility renderer).

## The maps this test holds to it.
const MAPS := ["castle", "castle_v2", "rail_yard", "lost_temple", "neon_arcade", "sky_island", "haunted_house"]

const SAME_PLANE := 0.004    ## metres: closer than this is the same plane
const MIN_AREA := 0.0015     ## m2: a smaller overlap than this is not seen
const MIN_WIDTH := 0.012     ## metres: nor a thinner sliver
const LOOK_FROM := 0.012     ## metres in front of the surface the "is it covered" probes sit

var failures := 0
var _gap := SAME_PLANE
var _list := 12


func _initialize() -> void:
	print("Map flicker checks")
	var only := OS.get_environment("FLICKER_MAPS")
	var ids: Array = MAPS
	if only == "all":
		ids = Maps.ids()
	elif only != "":
		ids = Array(only.split(","))
	if OS.get_environment("FLICKER_GAP") != "":
		_gap = maxf(float(OS.get_environment("FLICKER_GAP")), SAME_PLANE)
	if OS.get_environment("FLICKER_LIST") != "":
		_list = int(OS.get_environment("FLICKER_LIST"))
	for id in ids:
		_check(id)
	print("FAIL: %d checks failed" % failures if failures else "PASS: every check passed")
	quit(1 if failures else 0)


func _check(id: String) -> void:
	var map := Maps.make(id)
	root.add_child(map)
	var solids := []     # every drawn piece that hides what is inside it
	var faces := {}      # normal (rounded) -> [face]
	var count := 0
	var pieces := map.collect_pieces()
	for spinner in map.find_children("*", "", true, false):
		if spinner is MapSpinner:
			pass   # turning scenery: it moves, so it is never in one plane for long
	for index in pieces.size():
		var piece: Dictionary = pieces[index]
		if piece.get("hidden", false):
			continue
		var look := "%s %s" % [piece.kind, piece.get("tint", Color.WHITE)]
		var see_through: bool = map.palette != null and map.palette.colors.get(piece.kind, Color.WHITE).a < 0.999
		var solid_index := -1
		if not see_through:
			solid_index = solids.size()
			solids.append(_solid(piece))
		for f in _faces(piece):
			f.look = look
			f.kind = piece.kind
			f.piece = solid_index
			var n: Vector3 = f.n
			var key := Vector3i((n * 500.0).round())
			if not faces.has(key):
				faces[key] = []
			faces[key].append(f)
			count += 1
	var grid := _grid(solids)
	var clashes := []
	var near := []
	for key in faces:
		var list: Array = faces[key]
		list.sort_custom(func(a, b): return a.d < b.d)
		for i in list.size():
			var a: Dictionary = list[i]
			for j in range(i + 1, list.size()):
				var b: Dictionary = list[j]
				if b.d - a.d > _gap:
					break
				if a.look == b.look or a.piece == b.piece and a.piece >= 0:
					continue
				if not (a.box as AABB).grow(0.01).intersects(b.box):
					continue
				var at: Variant = _seen_overlap(a, b, solids, grid)
				if at == null:
					continue
				var line := "%s and %s at %s facing %s" % [a.kind, b.kind, (at as Vector3).snappedf(0.01), (a.n as Vector3).snappedf(0.01)]
				if b.d - a.d <= SAME_PLANE:
					clashes.append(line)
				else:
					near.append("%s (%.0f mm apart)" % [line, (b.d - a.d) * 1000.0])
	# Signs lying in a wall's surface.
	var signs := 0
	for label in map.find_children("*", "Label3D", true, false):
		var l := label as Label3D
		if not l.is_visible_in_tree() or l.no_depth_test or l.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
			continue
		signs += 1
		var xf := _map_xf(l, map)
		for n in [xf.basis.z.normalized(), -xf.basis.z.normalized()]:
			if n == -xf.basis.z.normalized() and not l.double_sided:
				continue
			var key := Vector3i(((n as Vector3) * 500.0).round())
			for f in faces.get(key, []):
				if absf(f.d - (n as Vector3).dot(xf.origin)) > SAME_PLANE:
					continue
				if _inside_polygon(f, xf.origin) and not _covered(xf.origin + (n as Vector3) * LOOK_FROM, f.piece, -1, solids, grid):
					clashes.append("the sign \"%s\" lies in the surface of %s at %s" % [l.text.left(18), f.kind, xf.origin.snappedf(0.01)])
	print("  %s: %d surfaces, %d signs" % [Maps.name_of(id), count, signs])
	_expect(clashes.is_empty(), "no two surfaces of different colours share a plane where both show (%d found) %s" % [clashes.size(), _some(clashes)])
	if _gap > SAME_PLANE:
		print("    note %d pairs closer than %.0f mm %s" % [near.size(), _gap * 1000.0, _some(near)])
	map.free()


func _some(lines: Array) -> String:
	if lines.is_empty():
		return ""
	var text := ""
	for l in lines.slice(0, _list):
		text += "\n        " + l
	if lines.size() > _list:
		text += "\n        ... and %d more" % (lines.size() - _list)
	return text


## A node's place in the map's frame.
func _map_xf(node: Node3D, map: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != map:
		if at is Node3D:
			xf = (at as Node3D).transform * xf
		at = at.get_parent()
	return xf


# ---------------------------------------------------------------------------
# Faces

## A piece's drawn faces: {n, d, pts (corners in the map's frame, in order), box}.
func _faces(piece: Dictionary) -> Array:
	var xf: Transform3D = piece.xf
	var out := []
	if piece.shape == "box":
		var h: Vector3 = piece.size * 0.5
		for face in MapMesher.BOX_FACES:
			var c: Vector3 = face[0] * h
			var du: Vector3 = face[1] * h
			var dv: Vector3 = face[2] * h
			out.append(_face([xf * (c - du - dv), xf * (c + du - dv), xf * (c + du + dv), xf * (c - du + dv)], xf.basis * face[0]))
		return out
	if piece.shape == "cone":
		return _cone_faces(piece)
	if piece.shape == "dome":
		return out   # curved all over: no flat face to share a plane with
	if piece.shape in ["wedge", "bevel", "arch", "hull"]:
		for lump in MapMesher.hull_points(piece):
			for face in MapMesher.hull_faces(lump):
				var pts := []
				for corner in face[1]:
					pts.append(xf * (corner as Vector3))
				out.append(_face(pts, xf.basis * (face[0] as Vector3)))
		return out
	var sides: int = piece.get("sides", 12)
	var r: float = piece.size.x * 0.5
	var ri: float = piece.get("inner", 0.0) * 0.5 if piece.shape == "tube" else 0.0
	var up := Vector3(0, piece.size.y * 0.5, 0)
	var top := []
	var bottom := []
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var am := (a0 + a1) * 0.5
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n := Vector3(cos(am), 0, sin(am))
		out.append(_face([xf * (d1 * r - up), xf * (d0 * r - up), xf * (d0 * r + up), xf * (d1 * r + up)], xf.basis * n))
		if ri > 0.0:
			out.append(_face([xf * (d0 * ri - up), xf * (d1 * ri - up), xf * (d1 * ri + up), xf * (d0 * ri + up)], xf.basis * -n))
			out.append(_face([xf * (d0 * ri + up), xf * (d1 * ri + up), xf * (d1 * r + up), xf * (d0 * r + up)], xf.basis * Vector3.UP))
			out.append(_face([xf * (d1 * ri - up), xf * (d0 * ri - up), xf * (d0 * r - up), xf * (d1 * r - up)], xf.basis * Vector3.DOWN))
		else:
			top.append(xf * (d0 * r + up))
			bottom.append(xf * (d0 * r - up))
	if ri <= 0.0:
		out.append(_face(top, xf.basis * Vector3.UP))
		out.append(_face(bottom, xf.basis * Vector3.DOWN))
	return out


func _cone_faces(piece: Dictionary) -> Array:
	var xf: Transform3D = piece.xf
	var out := []
	var sides: int = piece.get("sides", 12)
	var r: float = piece.size.x * 0.5
	var rt: float = minf(piece.get("top", 0.0) * 0.5, r)
	var up := Vector3(0, piece.size.y * 0.5, 0)
	var top := []
	var bottom := []
	for i in sides:
		var d0 := Vector3(cos(TAU * i / sides), 0, sin(TAU * i / sides))
		var d1 := Vector3(cos(TAU * (i + 1) / sides), 0, sin(TAU * (i + 1) / sides))
		var n := MapMesher.cone_side_normal(d0, d1, r, rt, piece.size.y)
		var pts := [xf * (d1 * r - up), xf * (d0 * r - up)]
		if rt > 0.0:
			pts.append_array([xf * (d0 * rt + up), xf * (d1 * rt + up)])
			top.append(xf * (d0 * rt + up))
		else:
			pts.append(xf * up)
		out.append(_face(pts, xf.basis * n))
		bottom.append(xf * (d0 * r - up))
	if rt > 0.0:
		out.append(_face(top, xf.basis * Vector3.UP))
	out.append(_face(bottom, xf.basis * Vector3.DOWN))
	return out


func _face(pts: Array, n: Vector3) -> Dictionary:
	n = n.normalized()
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	# Two axes in the plane, the same for every face with this normal.
	var u := (Vector3.UP.cross(n) if absf(n.y) < 0.9 else Vector3.RIGHT.cross(n)).normalized()
	var v := n.cross(u)
	var flat := PackedVector2Array()
	for p in pts:
		flat.append(Vector2(u.dot(p), v.dot(p)))
	if not Geometry2D.is_polygon_clockwise(flat):
		flat.reverse()
	return {"n": n, "d": n.dot(pts[0]), "box": box, "flat": flat, "u": u, "v": v}


func _inside_polygon(f: Dictionary, point: Vector3) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2((f.u as Vector3).dot(point), (f.v as Vector3).dot(point)), f.flat)


## Where two faces in one plane overlap and can both be seen (a point), or null.
func _seen_overlap(a: Dictionary, b: Dictionary, solids: Array, grid: Dictionary) -> Variant:
	for poly in Geometry2D.intersect_polygons(a.flat, b.flat):
		var area := 0.0
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var mid := Vector2.ZERO
		for k in poly.size():
			var p: Vector2 = poly[k]
			var q: Vector2 = poly[(k + 1) % poly.size()]
			area += p.x * q.y - q.x * p.y
			lo = lo.min(p)
			hi = hi.max(p)
			mid += p
		area = absf(area) * 0.5
		mid /= poly.size()
		if area < MIN_AREA or minf(hi.x - lo.x, hi.y - lo.y) < MIN_WIDTH or area / maxf(hi.x - lo.x, hi.y - lo.y) < MIN_WIDTH * 0.5:
			continue
		# Probe the middle and toward each corner; a spot counts if nothing covers it.
		var spots := [mid]
		for p in poly:
			spots.append(mid.lerp(p, 0.8))
			spots.append(mid.lerp(p, 0.45))
		for s in spots:
			var at: Vector3 = (a.u as Vector3) * s.x + (a.v as Vector3) * s.y + (a.n as Vector3) * a.d
			if not _covered(at + (a.n as Vector3) * LOOK_FROM, a.piece, b.piece, solids, grid):
				return at
	return null


# ---------------------------------------------------------------------------
# What hides a spot

func _solid(piece: Dictionary) -> Dictionary:
	var xf: Transform3D = piece.xf
	var box: AABB = xf * AABB(-(piece.size as Vector3) * 0.5, piece.size)
	if piece.shape not in ["box", "wedge", "hull"]:
		var d: float = piece.size.x
		box = xf * AABB(Vector3(-d, -piece.size.y, -d) * 0.5, Vector3(d, piece.size.y, d))
	return {"inv": xf.affine_inverse(), "half": piece.size * 0.5, "shape": piece.shape, "box": box,
		"sides": piece.get("sides", 12), "inner": piece.get("inner", 0.0) * 0.5, "top": piece.get("top", 0.0) * 0.5,
		"planes": piece.get("planes", [])}


const BUCKET := 6.0

func _grid(solids: Array) -> Dictionary:
	var grid := {}
	for i in solids.size():
		var box: AABB = solids[i].box
		var lo := Vector3i((box.position / BUCKET).floor())
		var hi := Vector3i((box.end / BUCKET).floor())
		if (hi.x - lo.x + 1) * (hi.y - lo.y + 1) * (hi.z - lo.z + 1) > 600:
			if not grid.has("big"):
				grid["big"] = []
			grid["big"].append(i)
			continue
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var key := Vector3i(x, y, z)
					if not grid.has(key):
						grid[key] = []
					grid[key].append(i)
	return grid


## Is `point` inside a drawn piece other than the two given?
func _covered(point: Vector3, skip_a: int, skip_b: int, solids: Array, grid: Dictionary) -> bool:
	for list in [grid.get(Vector3i((point / BUCKET).floor()), []), grid.get("big", [])]:
		for i in list:
			if i == skip_a or i == skip_b:
				continue
			var s: Dictionary = solids[i]
			if not (s.box as AABB).has_point(point):
				continue
			var local: Vector3 = (s.inv as Transform3D) * point
			var half: Vector3 = s.half
			if absf(local.y) > half.y:
				continue
			if s.shape == "box":
				if absf(local.x) <= half.x and absf(local.z) <= half.z:
					return true
				continue
			if s.shape == "wedge":
				# A slope: full height at the back (-z), down to nothing at the front.
				if absf(local.x) <= half.x and absf(local.z) <= half.z and local.y <= half.y - (local.z + half.z) * half.y / half.z:
					return true
				continue
			if s.shape == "hull":
				if MapMesher.hull_has(s.planes, local):
					return true
				continue
			if s.shape in ["bevel", "dome", "arch"]:
				continue   # (not worked out: such a piece is taken to hide nothing)
			var reach := Vector2(local.x, local.z).length()
			var radius: float = half.x
			if s.shape == "cone":   # narrows from the foot to the top
				radius = lerpf(half.x, minf(s.top, half.x), (local.y + half.y) / (2.0 * half.y))
			var flat_reach: float = radius * cos(PI / s.sides)   # the flat sides come in a little
			if reach <= flat_reach and (s.shape != "tube" or reach >= s.inner):
				return true
	return false


func _expect(ok: bool, what: String) -> void:
	print("    %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1
