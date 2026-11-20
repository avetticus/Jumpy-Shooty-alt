@tool
class_name MapBlock
extends Node3D
## One piece of a map: a box, a cylinder, a tube, a cone, a wedge (a slope), a bevelled
## box, a dome, an arch, or a hull (any convex shape, given by its corners), painted
## with a "kind" from the map's palette. Move and turn it like any node; resize it with the inspector's
## Size or by dragging the orange handles on its faces (see addons/map_tools).
##
## In the game, MapRoot.build() merges every block into one mesh per kind and one
## collision body, so a map of thousands of blocks still draws in a few calls. A
## block (or a group of them) hidden with the eye icon is left out of the game.

enum Shape { BOX, CYLINDER, TUBE, CONE, WEDGE, BEVEL, DOME, ARCH, HULL }

## Hull: any convex shape, the smallest one round its Points. Picking Hull here turns
## the block's present shape into its corners (a tube, an arch or a hollow dome is
## filled in: Map > Make Editable keeps their holes, as several hull blocks).
@export var shape := Shape.BOX:
	set(v):
		var corners := PackedVector3Array()
		if v == Shape.HULL and shape != Shape.HULL and Engine.is_editor_hint() and is_inside_tree():
			# Picked in the inspector: start from the shape it was.
			var all := PackedVector3Array()
			for lump in shape_lumps():
				all.append_array(lump)
			corners = MapMesher.hull_corners(all)
		shape = v
		if not corners.is_empty():
			points = corners
		notify_property_list_changed()
		_changed()

## Box: width (x), height (y), depth (z). Cylinder and tube: diameter (x) and
## height (y), standing along the block's own y axis; z is not used. Cone: the
## diameter at its foot (x) and its height (y), narrowing to Top at the top.
## Wedge: a slope filling the box, its tall side at the back (-z), running down to
## nothing at the front (+z). Bevel: a box with every edge cut off by Bevel. Dome: half
## a ball standing on its flat side, x and z across (they can differ) and y high;
## with Inner it is a shell you can stand inside, with Arc under 360 a slice is left
## open (toward +z). Arch: a box (x wide, y high, z thick) with an arched opening cut
## up into it from below, Inner wide (0 = the whole width) and leaving Top at the crown.
## Hull: the box round its corners; changing it stretches the corners to fit.
@export var size := Vector3.ONE:
	set(v):
		v = v.max(Vector3(0.01, 0.01, 0.01))
		if shape == Shape.HULL and not _fitting and not points.is_empty():
			var was := points_bounds(points).size
			var stretched := PackedVector3Array()
			for p in points:
				for axis in 3:
					if was[axis] > 0.0001:
						p[axis] *= v[axis] / was[axis]
				stretched.append(p)
			_fitting = true
			points = stretched
			_fitting = false
		size = v
		_changed()

## Which colour from the map's palette.
@export var kind := "concrete":
	set(v):
		kind = v
		_changed()

## You bump into it and stand on it. Off: drawn only (paint on the floor, thin rods).
@export var solid := true

## You can see it. Off: an invisible wall, often a plain box under finer drawn parts.
@export var drawn := true:
	set(v):
		drawn = v
		_changed()

## What it is made of: its footsteps and how it breaks (see BlockMaterials).
## Blank = from its kind (the palette's Material list, else guessed from the name).
@export var material_type := "":
	set(v):
		material_type = v
		_changed()

@export_group("Breaking")
## On: it can be shot or smashed through. Off (the usual): it never breaks.
## Only in arena matches, never races.
## (Left without a type on purpose: maps saved when this was Default / Yes / No hold
## a number, 1 for Yes and 2 for No, which the setter reads. Default used to mean
## "if the palette lists its kind"; tools/arena/migrate_breakable.gd ticks those.)
@export var breakable = false:
	set(v):
		breakable = (v == 1) if v is int else bool(v)
		notify_property_list_changed()
		_changed()

## How it breaks, one of the ready-made choices in BlockBreakable.PRESETS: per cell
## (shots punch holes in a thin wall or floor) or the whole block at once, and how
## tough. The plain ones take their toughness from the kind, in the palette.
@export var break_settings := BlockBreakable.DEFAULT:
	set(v):
		break_settings = v
		_changed()

## How much damage it takes, for this block only. 0 = what Break Settings says.
## A pistol shot does 25, a rifle round 13.
@export_range(0.0, 5000.0, 1.0, "or_greater") var break_health := 0.0:
	set(v):
		break_health = maxf(v, 0.0)
		_changed()
@export_group("")

## Multiplied into the kind's colour, to make one block a little lighter or darker.
@export var tint := Color.WHITE:
	set(v):
		tint = v
		_changed()

## Cylinders, tubes, cones and domes: how many flat sides round. Arches: how many
## pieces the curve is made of.
@export_range(3, 48) var sides := 12:
	set(v):
		sides = v
		_changed()

## Tubes: the inside diameter. Domes: the same, for a hollow one (0 = solid).
## Arches: how wide the opening is (0 = as wide as the block).
@export var inner := 0.0:
	set(v):
		inner = v
		_changed()

## Cones: the diameter at the top. 0 comes to a point; more cuts the tip off flat.
## Arches: how thick it is left over the top of the opening.
@export var top := 0.0:
	set(v):
		top = maxf(v, 0.0)
		_changed()

## Bevelled boxes: how much is cut off every edge (metres).
@export var bevel := 0.1:
	set(v):
		bevel = maxf(v, 0.0)
		_changed()

## Domes: how much of the way round it goes, in degrees. Under 360 leaves a slice
## open, facing +z (an observatory's slit).
@export_range(10.0, 360.0) var arc := 360.0:
	set(v):
		arc = v
		_changed()

## Hulls: the corners, in the block's own frame (metres, before any scale). The block
## is the smallest convex shape round them; a point inside it does nothing. They are
## kept centred on the block's origin, so typing one in moves the shape to stay
## centred, and Size is the box round them. At most MapMesher.MAX_HULL_CORNERS.
@export var points := PackedVector3Array():
	set(v):
		if shape == Shape.HULL and not v.is_empty():
			# Centred, and to a tenth of a millimetre: stretching and pushing a hull over
			# and over must not let its corners drift out of their faces' planes.
			var middle := points_bounds(v).get_center()
			v = v.duplicate()   # (a packed array is passed by reference: leave the caller's alone)
			for i in v.size():
				v[i] = (v[i] - middle).snappedf(0.0001)
		points = v
		if shape == Shape.HULL and not _fitting and not v.is_empty():
			_fitting = true
			size = points_bounds(v).size
			_fitting = false
		_changed()

const SHAPE_NAMES := ["box", "cyl", "tube", "cone", "wedge", "bevel", "dome", "arch", "hull"]

var _fitting := false   # Size and Points are being matched to each other
var _preview: MeshInstance3D
var _triangles: TriangleMesh
var _shaded_for := Basis()   # the world orientation the preview's face shading was made for


## This block as a piece for MapMesher and the collision builder. `xf` is where it
## sits (from MapRoot); any scale in it is folded into the size.
func to_piece(xf: Transform3D) -> Dictionary:
	var scale := xf.basis.get_scale().abs()
	var piece := {
		"xf": Transform3D(xf.basis.orthonormalized(), xf.origin),
		"size": size * scale, "kind": kind, "solid": solid, "shape": SHAPE_NAMES[shape],
	}
	if not drawn:
		piece["hidden"] = true
	if tint != Color.WHITE:
		piece["tint"] = tint
	if breakable:
		piece["breakable"] = true
		piece["break_mode"] = BlockBreakable.mode_of(break_settings)
		var health := break_health if break_health > 0.0 else BlockBreakable.health_of(break_settings)
		if health > 0.0:
			piece["health"] = health
	if material_type != "":
		piece["material"] = material_type
	if shape != Shape.BOX:
		piece["sides"] = sides
	if shape == Shape.TUBE or shape == Shape.DOME or shape == Shape.ARCH:
		piece["inner"] = inner * scale.x
	if shape == Shape.CONE:
		piece["top"] = top * scale.x
	if shape == Shape.ARCH:
		piece["top"] = top * scale.y
	if shape == Shape.BEVEL:
		piece["bevel"] = bevel * minf(scale.x, minf(scale.y, scale.z))
	if shape == Shape.DOME and arc < 360.0:
		piece["arc"] = arc
	if shape == Shape.HULL:
		var pts := PackedVector3Array()
		for p in points:
			pts.append(p * scale)
		var planes := MapMesher.hull_planes(pts)
		if planes.size() >= 4:
			piece["points"] = pts
			piece["planes"] = planes
		else:
			piece["shape"] = "box"   # not a solid shape (yet): the box round its corners stands in
	return piece


## This block's shape as convex lumps, each the list of its corners in the block's
## own frame (before any scale): what it becomes as hull blocks (Map > Make
## Editable). A box, a cylinder, a cone, a wedge, a bevelled box and a whole solid
## dome are one lump; a tube, an arch and a hollow or cut-open dome are several.
func shape_lumps() -> Array:
	var piece := to_piece(Transform3D.IDENTITY)
	match shape:
		Shape.BOX:
			var h := size * 0.5
			var box := PackedVector3Array()
			for i in 8:
				box.append(Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
			return [box]
		Shape.CYLINDER, Shape.TUBE:
			var ring := MapMesher.tube_hulls(piece) if shape == Shape.TUBE else []
			if not ring.is_empty():
				return ring
			piece["top"] = size.x   # a cylinder is a cone as wide at the top as at the foot
			return [MapMesher.cone_points(piece)]
		Shape.CONE:
			return [MapMesher.cone_points(piece)]
		Shape.HULL:
			return [points]
	return MapMesher.hull_points(piece)


## The box round some corners.
static func points_bounds(pts: PackedVector3Array) -> AABB:
	if pts.is_empty():
		return AABB()
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	return box


## Round the y axis, with one diameter (x): a cylinder, a tube or a cone.
func is_round() -> bool:
	return shape == Shape.CYLINDER or shape == Shape.TUBE or shape == Shape.CONE


## Moves one face (0 +x, 1 -x, 2 +y, 3 -y, 4 +z, 5 -z) to `reach` from the block's
## centre (in its own units), keeping the opposite face where it is. On a cylinder,
## tube or cone, faces 0 to 1 and 4 to 5 set the diameter (a cone's foot) instead.
## Sizes snap to `step`.
## Used by the resize handles (addons/map_tools/block_gizmo.gd).
func move_face(face: int, reach: float, step: float) -> void:
	var axis := face / 2
	var dir := 1.0 if face % 2 == 0 else -1.0
	if is_round() and axis != 1:
		var d := maxf(roundf(reach * 2.0 / step) * step, step)
		size = Vector3(d, size.y, d)
		return
	var length := maxf(roundf((reach + size[axis] * 0.5) / step) * step, step)
	var shift := Vector3.ZERO
	shift[axis] = (length - size[axis]) * 0.5 * dir
	var new_size := size
	new_size[axis] = length
	size = new_size
	position += transform.basis * shift


# ---------------------------------------------------------------------------
# Editor preview (in the game the merged meshes take over)

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
		refresh_preview()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _preview != null:
		# Moving needs nothing; turning changes which faces are shaded darker.
		if not global_basis.orthonormalized().is_equal_approx(_shaded_for):
			refresh_preview()


func _changed() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		refresh_preview()
		update_configuration_warnings()


## Redraws this block in the editor (MapRoot calls it when the palette changes).
func refresh_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var root := MapRoot.of(self)
	if _preview == null:
		_preview = MeshInstance3D.new()
		add_child(_preview, false, Node.INTERNAL_MODE_FRONT)
	_shaded_for = global_basis.orthonormalized()
	var piece := to_piece(Transform3D.IDENTITY)
	piece.erase("hidden")
	var shade := root.face_shade if root else Vector3.ONE
	var meshes := MapMesher.build([piece], shade, _shaded_for)
	_preview.mesh = meshes.get(kind)
	var shown := drawn or root == null or root.show_invisible_blocks
	if not solid and Engine.get_meta(&"map_tools_solid_only", false):
		shown = false   # the map tools' "Show Solid Blocks Only" (addons/map_tools)
	_preview.visible = shown
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if drawn else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if drawn:
		_preview.material_override = root.material_for(kind) if root else MapRoot.fallback_material(kind)
	else:
		_preview.material_override = MapRoot.ghost_material()
	_triangles = _preview.mesh.generate_triangle_mesh() if shown and _preview.mesh else null
	update_gizmos()


## For the editor gizmo: what you click to select this block.
func preview_triangles() -> TriangleMesh:
	return _triangles


## Maps saved before Breakable existed say "unbreakable = true".
func _set(property: StringName, value: Variant) -> bool:
	if property == &"unbreakable":
		if value:
			breakable = false
		return true
	return false


func _validate_property(property: Dictionary) -> void:
	match property.name:
		"material_type":
			property.hint = PROPERTY_HINT_ENUM_SUGGESTION
			property.hint_string = ",".join(BlockMaterials.names())
		"break_settings":
			property.hint = PROPERTY_HINT_ENUM
			property.hint_string = ",".join(BlockBreakable.names())
			if not breakable:
				property.usage &= ~PROPERTY_USAGE_EDITOR
		"break_health":
			if not breakable:
				property.usage &= ~PROPERTY_USAGE_EDITOR
		"kind":
			var root := MapRoot.of(self) if is_inside_tree() else null
			if root and root.palette:
				property.hint = PROPERTY_HINT_ENUM_SUGGESTION
				property.hint_string = ",".join(root.palette.colors.keys())
		"sides":
			if shape == Shape.BOX or shape == Shape.WEDGE or shape == Shape.BEVEL or shape == Shape.HULL:
				property.usage &= ~PROPERTY_USAGE_EDITOR
		"points":
			if shape != Shape.HULL:
				# Not shown, and not saved either: the editor would otherwise write an
				# empty list into every block of every map it saves.
				property.usage &= ~(PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_STORAGE)
		"inner":
			if shape != Shape.TUBE and shape != Shape.DOME and shape != Shape.ARCH:
				property.usage &= ~PROPERTY_USAGE_EDITOR
		"top":
			if shape != Shape.CONE and shape != Shape.ARCH:
				property.usage &= ~PROPERTY_USAGE_EDITOR
		"bevel":
			if shape != Shape.BEVEL:
				property.usage &= ~PROPERTY_USAGE_EDITOR
		"arc":
			if shape != Shape.DOME:
				property.usage &= ~PROPERTY_USAGE_EDITOR


func _get_configuration_warnings() -> PackedStringArray:
	var root := MapRoot.of(self)
	if root == null:
		return ["A map block only shows up in the game inside a map (a scene whose root is a MapRoot)."]
	var warnings := PackedStringArray()
	if root.palette and not root.palette.colors.has(kind):
		warnings.append("The map's palette has no colour for \"%s\"." % kind)
	if material_type != "" and not BlockMaterials.TABLE.has(material_type):
		warnings.append("\"%s\" is not a material (see BlockMaterials); it will sound like %s." % [material_type, BlockMaterials.DEFAULT])
	if breakable and not BlockBreakable.PRESETS.has(break_settings):
		warnings.append("\"%s\" is not one of the Break Settings (see BlockBreakable); it will break like \"%s\"." % [break_settings, BlockBreakable.DEFAULT])
	var whole := BlockBreakable.mode_of(break_settings) == "whole"
	if shape == Shape.HULL:
		if MapMesher.hull_planes(points).size() < 4:
			warnings.append("A hull needs at least four corners that are not all in one plane. Until it has them it is the box round its corners.")
		elif points.size() > MapMesher.MAX_HULL_CORNERS:
			warnings.append("A hull of more than %d corners is slow to build; split it into two blocks." % MapMesher.MAX_HULL_CORNERS)
	if breakable and not whole and not MapDestruction.thin_enough(shape, size):
		warnings.append("Only thin walls and floors (a box at most %.1f m thick and %d m² across) break per cell. Set Break Settings to Whole Block to break this one." % [MapDestruction.MAX_THICKNESS, int(MapDestruction.MIN_AREA)])
	return warnings
