@tool
class_name MapRoot
extends Node3D
## The root node of a map scene (game/maps/*.tscn). Under it go:
##  - MapBlock nodes: everything you stand on, hide behind or look at. Group them
##    under plain Node3D nodes as you like (the maps group each object, so a click
##    selects the whole container or staircase; see docs/DEVELOPMENT.md).
##  - MapSpawn nodes: where players appear.
##  - MapDummy nodes: target dummies to shoot at (test maps).
##  - MapWeaponSpawn nodes (under "WeaponSpawns"): Deathmatch weapon pickups.
##  - MapGrapplePoint nodes: glowing spots the grappling hook snaps to when you aim
##    near them (any map, any mode).
##  - MapItemSpawn nodes (under "ItemSpawns"): Deathmatch power-ups (health, damage).
##  - MapHazard blocks: touch one and, in a race, you go back to your checkpoint; in
##    an arena it is a death, the same as falling out of the map.
##  - Race maps only: MapCheckpoint gates (numbered, the last one the finish), MapMover
##    groups (blocks that slide or spin) and, under "BotRoute", the MapRoutePoint
##    steps bots follow round the course.
##  - MapGravityZone volumes: places with their own gravity (see WorldGravity).
##  - MapSpinner groups: scenery that turns (drawn, never solid); MapTerminal consoles
##    players press interact at, and the MapEvent (GravityEvent, LayoutEvent) each one
##    sets off.
##  - Maps with two layouts (Cirrus): MapIsland groups (a MapMover a LayoutEvent moves
##    between two places, carrying whoever stands on it; spawn points, pickups, signs
##    and grapple points inside one ride along), MapSpan walkways that extend and
##    retract, and MapJumpLink markers telling bots where to grapple or leap across.
##  - Label3D nodes: signs and painted numbers.
##  - A WorldEnvironment (sky, ambient light, fog) and a DirectionalLight3D (the sun).
##
## When a match starts, the arena calls build(): every visible MapBlock becomes part
## of one collision body and of one merged mesh per kind, and the spawn list is read.

## Colours for every block kind.
@export var palette: MapPalette:
	set(v):
		if palette and palette.changed.is_connected(_palette_changed):
			palette.changed.disconnect(_palette_changed)
		palette = v
		if palette:
			palette.changed.connect(_palette_changed)
		_palette_changed()

## Darkens faces by the way they point, so plain boxes have some form even in flat
## light: (faces looking along x, faces looking along z, faces looking down).
## Tops stay at full brightness. (1, 1, 1) = off.
@export var face_shade := Vector3.ONE:
	set(v):
		face_shade = v
		_palette_changed()

## Draws a 1 m / 4 m grid on every surface, to judge distance (test maps).
@export var grid_texture := false:
	set(v):
		grid_texture = v
		_palette_changed()

## Editor only: show blocks that are solid but not drawn, as faint blue boxes.
@export var show_invisible_blocks := true:
	set(v):
		show_invisible_blocks = v
		_palette_changed()

@export_group("Drawing")
## Do blocks that are drawn only (not solid: decoration) cast shadows? Off saves drawing
## them again for every shadow, and thin things make shadows that shimmer. For a map
## with a great deal of decoration.
@export var decor_shadows := true
## Drawn-only blocks no bigger than Detail Size are small decoration. From farther than
## this many metres they are not drawn (0: always drawn, as on most maps).
@export var detail_range := 0.0
## The biggest a block can be (its longest side, metres) and still count as small.
@export var detail_size := 1.5
## The small decoration's meshes are cut into cubes this many metres across, and it is
## each cube's middle that Detail Range is measured to.
@export var detail_chunk := 30.0

@export_group("Rules")
## Falling below this height counts as falling out of the map.
@export var kill_height := -25.0
## Leaving this area (x, z) also counts as falling out. Zero size = no limit.
@export var bounds := Rect2():
	set(v):
		bounds = v
		update_gizmos()
## Tick this if a walkable floor winds up over itself, like a spiral stair in a tower
## (Cirrus's clock tower): the bots' navigation mesh is then cut up a way that keeps
## such a stair. Leave it off otherwise: the usual way makes tidier paths in the open.
@export var winding_floors := false
## Tick this on a map bots can only get round with the grapple (Cirrus: islands with
## open sky between them, crossed at MapJumpLinks): every bot then carries the grapple
## here, whatever tool it was dealt.
@export var bots_grapple := false
## Gravity wherever no MapGravityZone covers, as a share of normal (see WorldGravity).
## 1 = normal. Empyrean Tower: 0.4, with a zone of 1.0 filling the tower.
@export_range(0.05, 2.0) var gravity_outside := 1.0
## A high point near the middle that scripted test players swing from.
@export var swing_point := Vector3(0, 5.5, 0):
	set(v):
		swing_point = v
		update_gizmos()

const FALLBACK_PALETTE := "res://game/maps/palettes/construction_site.tres"

## [position, yaw] of every spawn point; filled in by build().
var spawns: Array = []
## [position, yaw, MapDummy] of every target dummy; filled in by build().
var dummies: Array = []
## [position, weapon id] of every Deathmatch weapon pickup (MapWeaponSpawn); filled in by build().
var weapon_spawns: Array = []
## [position, item kind] of every Deathmatch power-up (MapItemSpawn); filled in by build().
var item_spawns: Array = []
## Race maps, filled in by build(). Checkpoints: {number, finish, xf, opening},
## sorted by number. Hazards: {xf, size, shape, mover} (mover = index into movers,
## or -1). Movers: {node: MapMover, base: Transform3D, body: AnimatableBody3D}.
## Route: {pos, action, aim, radius, boost} in running order.
var checkpoints: Array = []
var hazards: Array = []
var movers: Array = []
var route: Array = []
## The map's MapSpinner nodes (scenery that turns), filled in by build().
var spinners: Array = []
## The map's MapGravityZone volumes, as WorldGravity takes them; filled in by build().
var gravity_zones: Array = []
## The map's MapSpan walkways (they extend and retract), filled in by build():
## {node: MapSpan, base: Transform3D (in its mover's frame, or the map's), mover: int}.
var spans: Array = []
## The map's parts are on the move between two layouts (a LayoutEvent says so):
## bots stand still until they have settled.
var shifting := false:
	set(v):
		if v == shifting:
			return
		shifting = v
		if v:
			parts_moving.emit()
		else:
			parts_settled.emit()
## The bots' navigation mesh is being redone for where the parts now are (the arena
## says so): bots keep standing still.
var nav_pending := false
## The parts are about to move (a LayoutEvent's bell has gone): an island that is about
## to go down (MapIsland.doomed) is no place to be. Bots get off it and keep off.
var warning := false
## Which layout the map is in (a LayoutEvent's present arrangement, as a number: 0
## until one says otherwise). The arena keeps a navigation mesh for each.
var layout_state := 0

signal parts_moving
signal parts_settled
## Seconds the map's moving parts have been running (the same on every copy of the
## game: the arena starts it when the match starts).
var clock := 0.0
## If set, the moving parts follow this clock (seconds) instead of counting their own.
var clock_source: Callable
## Set before build(): walls and floors of the palette's breakable kinds can be broken
## (arena matches; never races). Then `destruction` holds them (see MapDestruction).
var destructible := false
var destruction: MapDestruction
## build() made meshes (false in the movement tests).
var has_meshes := true

var _materials := {}
var _riding_materials := {}   # kind -> the grid material laid out from a mover's body (see riding_material_for)
# Spawn points and pickup spots inside a mover: {list: 0 spawns / 1 weapons / 2 items,
# index, mover, xf (in the mover's frame)}. update_movers() keeps them where the mover is.
var _riders: Array = []
# Where the movers were over the last half second, newest last: [time, [Transform3D]].
# Only kept while something moves (see carried()).
var _trail: Array = []
var _trail_time := 0.0
var _trail_still := 0.0
const TRAIL_SECONDS := 0.6
static var _fallback := {}
static var _ghost: StandardMaterial3D


func _ready() -> void:
	# Run on its own (F6 in the editor): play it in practice mode.
	if not Engine.is_editor_hint() and get_tree().current_scene == self:
		var id := scene_file_path
		for m in Maps.LIST:
			if m.scene == id:
				id = m.id
		get_node("/root/Game").call_deferred("start_practice", id)


## The MapRoot a node belongs to, or null.
static func of(node: Node) -> MapRoot:
	while node != null and not node is MapRoot:
		node = node.get_parent()
	return node as MapRoot


## Makes the playable level: collision for every solid block and (unless
## `with_meshes` is false, as in the movement tests) one mesh per kind.
func build(with_meshes: bool = true) -> void:
	# The player's ambient occlusion and glow picks (Settings is missing in tools and tests).
	var tree := Engine.get_main_loop() as SceneTree
	var settings := tree.root.get_node_or_null("Settings") if tree else null
	if settings:
		GraphicsQuality.apply_environments(self, settings.graphics())
	var pieces := []
	spawns = []
	checkpoints = []
	hazards = []
	movers = []
	route = []
	weapon_spawns = []
	item_spawns = []
	spinners = []
	spans = []
	gravity_zones = []
	_riders = []
	_nav_poses = []
	_trail = []
	_collect(self, Transform3D.IDENTITY, pieces, spawns)
	# Gravity by place (none on most maps: then it is 1.0 everywhere, whatever the
	# last map said).
	WorldGravity.set_zones(gravity_zones, gravity_outside)
	for s in spinners:
		(s as MapSpinner).build(self, with_meshes)
	checkpoints.sort_custom(func(a, b): return a.number < b.number)
	dummies = []
	_collect_dummies(self, Transform3D.IDENTITY)
	has_meshes = with_meshes
	_index_surfaces(pieces)
	_index_decor(pieces)
	current = self
	if destructible:
		destruction = MapDestruction.new()
		add_child(destruction)
		pieces = destruction.setup(self, pieces, spawns)
	for i in movers.size():
		_build_mover(i, with_meshes)   # (after the breakables: a mover's own ride on it)
	if movers.is_empty():
		remove_from_group(MapReplay.GROUP)
	else:
		add_to_group(MapReplay.GROUP)   # killcams replay where they were (see MapReplay)
	for s in spans:
		var on: Node3D = movers[s.mover].body if s.mover >= 0 else self
		(s.node as MapSpan).build(self, on, s.base, with_meshes)
	var body := StaticBody3D.new()
	body.name = "Collision"
	for piece in pieces:
		if piece.solid:
			for lump in collision_shapes(piece):
				var shape := CollisionShape3D.new()
				shape.shape = lump
				shape.transform = piece.xf
				body.add_child(shape)
	# (Into the world only once it has all its shapes: added one at a time to a body that
	# is already there, each makes the physics engine put the whole body together again,
	# which on a map of thousands of solid blocks took ten seconds.)
	add_child(body)
	if not with_meshes:
		return
	# One mesh for each kind. A big map can say more (see Drawing): its decoration (the
	# blocks that are drawn only) apart from its structure, so that it casts no shadow,
	# and its small decoration cut into cubes, so that the far ones are left out.
	var lots := {}      # [cube, 0 structure / 1 decoration / 2 small decoration] -> pieces
	for piece in pieces:
		if piece.get("hidden", false):
			continue
		var size: Vector3 = piece.size
		var lot := 0
		var cube := Vector3i.ZERO
		if not piece.solid and detail_range > 0.0 and maxf(size.x, maxf(size.y, size.z)) <= detail_size:
			lot = 2
			cube = Vector3i(((piece.xf as Transform3D).origin / maxf(detail_chunk, 1.0)).floor())
		elif not piece.solid and not decor_shadows:
			lot = 1
		var key := [cube, lot]
		if not lots.has(key):
			lots[key] = []
		lots[key].append(piece)
	for key: Array in lots:
		var meshes := MapMesher.build(lots[key], face_shade)
		for kind in meshes:
			var mesh := MeshInstance3D.new()
			mesh.name = ["Mesh_%s", "Mesh_%s_decor", "Mesh_%s_detail"][key[1]] % kind
			if key[1] == 2:
				mesh.name = "Mesh_%s_detail_%d_%d_%d" % [kind, key[0].x, key[0].y, key[0].z]
				mesh.visibility_range_end = detail_range
				mesh.visibility_range_end_margin = detail_range * 0.1
			if key[1] > 0 and not decor_shadows:
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.mesh = meshes[kind]
			mesh.material_override = material_for(kind)
			# Glass lets the sun through: a see-through kind casts no shadow.
			var base := mesh.material_override as BaseMaterial3D
			if base and base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mesh)


const SURFACE_BUCKET := 4.0

## The map being played (set by build()), for things that ask about the ground,
## like footsteps. Null between matches.
static var current: MapRoot

var _surfaces := {}   # Vector2i bucket -> [{inv: Transform3D, half: Vector3, round: bool, top: float, material}]


## Files every solid block by where it is (flat, on the ground plan) with what it
## is made of, so material_at() only looks at the blocks near a point.
func _index_surfaces(pieces: Array) -> void:
	_surfaces = {}
	for p in pieces:
		if not p.solid:
			continue
		var xf: Transform3D = p.xf
		var half: Vector3 = p.size * 0.5
		var box: AABB = xf * AABB(-half, p.size)
		var lo := Vector2i(floori(box.position.x / SURFACE_BUCKET), floori(box.position.z / SURFACE_BUCKET))
		var hi := Vector2i(floori(box.end.x / SURFACE_BUCKET), floori(box.end.z / SURFACE_BUCKET))
		if (hi - lo).length() > 30:
			continue   # the ground or a sky box: answered by the fallback below
		var mat: String = p.get("material", "")
		if not BlockMaterials.TABLE.has(mat):
			mat = BlockMaterials.for_kind(p.kind, palette)
		# (A hull is looked up as the box round it: close enough for footsteps.)
		var entry := {"inv": xf.affine_inverse(), "half": half, "round": p.shape != "box" and p.shape != "hull", "top": box.end.y, "material": mat}
		for x in range(lo.x, hi.x + 1):
			for z in range(lo.y, hi.y + 1):
				var key := Vector2i(x, z)
				if not _surfaces.has(key):
					_surfaces[key] = []
				_surfaces[key].append(entry)
	_ground_material = ""
	var biggest := 0.0
	for p in pieces:   # the biggest flat solid block is "the ground"
		if p.solid and p.size.x * p.size.z > biggest:
			biggest = p.size.x * p.size.z
			var m: String = p.get("material", "")
			_ground_material = m if BlockMaterials.TABLE.has(m) else BlockMaterials.for_kind(p.kind, palette)


var _ground_material := ""

var _decor := {}   # Vector2i bucket -> [{xf: Transform3D, half: Vector3}]: the blocks that are drawn but not solid


## Files the map's decoration (blocks that are drawn but not solid: a container's ribs,
## a sign on a wall, trim) by where it is, for decor_relief().
func _index_decor(pieces: Array) -> void:
	_decor = {}
	for p in pieces:
		if p.solid or p.get("hidden", false):
			continue
		var xf: Transform3D = p.xf
		var half: Vector3 = p.size * 0.5
		var box: AABB = xf * AABB(-half, p.size)
		var lo := Vector2i(floori(box.position.x / SURFACE_BUCKET), floori(box.position.z / SURFACE_BUCKET))
		var hi := Vector2i(floori(box.end.x / SURFACE_BUCKET), floori(box.end.z / SURFACE_BUCKET))
		if (hi - lo).length() > 30:
			continue   # a backdrop: nothing a portal sits on
		var entry := {"xf": xf, "half": half}
		for x in range(lo.x, hi.x + 1):
			for z in range(lo.y, hi.y + 1):
				var key := Vector2i(x, z)
				if not _decor.has(key):
					_decor[key] = []
				_decor[key].append(entry)


## How far the map's decoration sticks out of a surface under an oval: `frame` is the
## oval's (x right, y up, z out of the surface, its origin on the surface), `half_w` and
## `half_h` its half size. The furthest any decoration lying on the surface there
## reaches in front of it (metres), leaving out what reaches further than `reach` (a
## lamp on a bracket, a banner: not part of the surface). 0 if there is none. Rays do
## not find decoration (it has no collision): a portal asks this to stand clear of it
## (see PortalFit).
func decor_relief(frame: Transform3D, half_w: float, half_h: float, reach: float) -> float:
	var out := 0.0
	var to_map := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	var local := to_map * frame
	var inv := local.affine_inverse()
	var r := maxf(half_w, half_h) + reach
	var lo := Vector2i(floori((local.origin.x - r) / SURFACE_BUCKET), floori((local.origin.z - r) / SURFACE_BUCKET))
	var hi := Vector2i(floori((local.origin.x + r) / SURFACE_BUCKET), floori((local.origin.z + r) / SURFACE_BUCKET))
	var seen := {}
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			for e: Dictionary in _decor.get(Vector2i(bx, bz), []):
				if seen.has(e):
					continue
				seen[e] = true
				out = maxf(out, _relief_of(inv * (e.xf as Transform3D), e.half, half_w, half_h, reach))
	# The moving parts' own decoration, where they are now.
	for m in movers:
		var body: Node3D = m.body
		if body == null or not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var in_body := (to_map * body.global_transform).affine_inverse() * local
		if not (m.bounds as AABB).grow(r + 1.0).has_point(in_body.origin):
			continue
		var body_inv := in_body.affine_inverse()
		for piece in m.pieces:
			if not piece.solid and not piece.get("hidden", false):
				out = maxf(out, _relief_of(body_inv * (piece.xf as Transform3D), (piece.size as Vector3) * 0.5, half_w, half_h, reach))
	return out


## One block (`xf` in the oval's frame, `half` its half size): how far it reaches in
## front of the oval's plane, if it lies on the surface under the oval; else 0.
static func _relief_of(xf: Transform3D, half: Vector3, half_w: float, half_h: float, reach: float) -> float:
	var b := xf.basis
	var c := xf.origin
	var ez := absf(b.x.z) * half.x + absf(b.y.z) * half.y + absf(b.z.z) * half.z
	var top := c.z + ez
	if top <= 0.004 or top > reach or c.z - ez > 0.12:
		return 0.0   # behind the surface, standing too far out, or hanging in front of it
	var ex := absf(b.x.x) * half.x + absf(b.y.x) * half.y + absf(b.z.x) * half.z
	var ey := absf(b.x.y) * half.x + absf(b.y.y) * half.y + absf(b.z.y) * half.z
	# The point of the block's outline (seen straight on) nearest the oval's middle.
	var px := clampf(0.0, c.x - ex, c.x + ex) / half_w
	var py := clampf(0.0, c.y - ey, c.y + ey) / half_h
	return top if px * px + py * py <= 1.0 else 0.0


## What the block at `point` (or just under it, within `below` metres) is made of:
## a BlockMaterials name. The highest such block wins. Feet on the ground: pass
## the player's position.
func material_at(point: Vector3, below: float = 0.25) -> String:
	var best := ""
	var best_top := -INF
	var key := Vector2i(floori(point.x / SURFACE_BUCKET), floori(point.z / SURFACE_BUCKET))
	for e in _surfaces.get(key, []):
		var local: Vector3 = (e.inv as Transform3D) * point
		var half: Vector3 = e.half
		if local.y < -half.y or local.y > half.y + below:
			continue
		if e.round:
			if Vector2(local.x, local.z).length() > half.x:
				continue
		elif absf(local.x) > half.x or absf(local.z) > half.z:
			continue
		if e.top > best_top:
			best_top = e.top
			best = e.material
	if best == "" and not movers.is_empty():
		best = _mover_material_at(point, below)
	if best == "":
		best = _ground_material if _ground_material != "" else BlockMaterials.DEFAULT
	return best


## The same, for a block of a mover (an island's lawn, a deck) wherever it is now.
func _mover_material_at(point: Vector3, below: float) -> String:
	var index := mover_under(point)
	if index < 0:
		return ""
	var m: Dictionary = movers[index]
	var local: Vector3 = (m.body as AnimatableBody3D).transform.affine_inverse() * point
	var best := ""
	var best_top := -INF
	for p in m.pieces:
		if not p.solid:
			continue
		var at: Vector3 = (p.xf as Transform3D).affine_inverse() * local
		var half: Vector3 = (p.size as Vector3) * 0.5
		if at.y < -half.y or at.y > half.y + below:
			continue
		if p.shape != "box" and p.shape != "hull":   # (a hull: the box round it, as in material_at)
			if Vector2(at.x, at.z).length() > half.x:
				continue
		elif absf(at.x) > half.x or absf(at.z) > half.z:
			continue
		var top: float = ((p.xf as Transform3D) * Vector3(0, half.y, 0)).y
		if top > best_top:
			best_top = top
			var mat: String = p.get("material", "")
			best = mat if BlockMaterials.TABLE.has(mat) else BlockMaterials.for_kind(p.kind, palette)
	return best


## Every visible block as a piece (see MapBlock.to_piece), in the map's frame. Blocks
## inside a mover or a span are given where they sit in the scene.
func collect_pieces() -> Array:
	var pieces := []
	var keep := [movers, spans, _riders, weapon_spawns, item_spawns, checkpoints, hazards, route]
	movers = []
	spans = []
	_riders = []
	weapon_spawns = []
	item_spawns = []
	checkpoints = []
	hazards = []
	route = []
	_collect(self, Transform3D.IDENTITY, pieces, [])
	for m in movers:
		for piece in m.pieces:
			var placed: Dictionary = (piece as Dictionary).duplicate()
			placed.xf = (m.base as Transform3D) * (piece.xf as Transform3D)
			pieces.append(placed)
	for s in spans:
		var base: Transform3D = s.base if s.mover < 0 else (movers[s.mover].base as Transform3D) * (s.base as Transform3D)
		for piece in (s.node as MapSpan).collect_pieces():
			piece.xf = base * (piece.xf as Transform3D)
			pieces.append(piece)
	movers = keep[0]
	spans = keep[1]
	_riders = keep[2]
	weapon_spawns = keep[3]
	item_spawns = keep[4]
	checkpoints = keep[5]
	hazards = keep[6]
	route = keep[7]
	return pieces


func _collect(node: Node, xf: Transform3D, pieces: Array, spawn_list: Array, mover: int = -1) -> void:
	for child in node.get_children():
		var at := xf
		if child is Node3D:
			if not (child as Node3D).visible:
				continue   # hidden in the editor: left out of the game
			at = xf * (child as Node3D).transform
		if child is MapGravityZone:
			if mover < 0 and not gravity_zones.any(func(z): return z.node == child):
				var zone := (child as MapGravityZone).to_zone(at)
				zone["node"] = child
				gravity_zones.append(zone)
			continue
		if child is MapSpinner:
			if not spinners.has(child):
				spinners.append(child)   # scenery that turns: it draws its own blocks, none of them solid
			continue
		if child is MapSpan:
			spans.append({"node": child, "base": at, "mover": mover})   # it builds its own pieces, a body for each
			continue
		if child is MapMover and mover == -1:
			# Its blocks are built into a moving body of their own (see _build_mover),
			# in the mover's own frame.
			# The scene's node goes along with the body when it carries jump links (bots
			# read where those are from the nodes), or when it says so (a MapIsland).
			var m := {"node": child, "base": at, "pieces": [], "body": null, "bounds": AABB(),
				"parent": xf.affine_inverse(), "moves_node": child.get("carries_nodes") == true \
					or not child.find_children("*", "MapJumpLink", true, false).is_empty()}
			movers.append(m)
			_collect(child, Transform3D.IDENTITY, m.pieces, spawn_list, movers.size() - 1)
			continue
		if child is MapBlock:
			var piece := (child as MapBlock).to_piece(at)
			pieces.append(piece)
			if child is MapHazard:
				hazards.append({"xf": piece.xf, "size": piece.size, "shape": piece.shape,
					"planes": piece.get("planes", []), "mover": mover})
		elif child is MapSpawn:
			# (Inside a mover `at` is in the mover's frame: it is put in the map's here,
			# and kept there as the mover moves.)
			var placed: Transform3D = at if mover < 0 else (movers[mover].base as Transform3D) * at
			spawn_list.append([placed.origin + Vector3(0, 0.2, 0), atan2(placed.basis.z.x, placed.basis.z.z)])
			if mover >= 0:
				_riders.append({"list": 0, "index": spawn_list.size() - 1, "mover": mover, "xf": at})
		elif child is MapWeaponSpawn:
			weapon_spawns.append([at.origin if mover < 0 else (movers[mover].base as Transform3D) * at.origin, (child as MapWeaponSpawn).weapon])
			if mover >= 0:
				_riders.append({"list": 1, "index": weapon_spawns.size() - 1, "mover": mover, "xf": at})
		elif child is MapItemSpawn:
			item_spawns.append([at.origin if mover < 0 else (movers[mover].base as Transform3D) * at.origin, (child as MapItemSpawn).item])
			if mover >= 0:
				_riders.append({"list": 2, "index": item_spawns.size() - 1, "mover": mover, "xf": at})
		elif child is MapCheckpoint:
			var c := child as MapCheckpoint
			checkpoints.append({"number": c.number, "finish": c.finish, "opening": c.opening,
				"xf": Transform3D(at.basis.orthonormalized(), at.origin)})
		elif child is MapRoutePoint:
			var r := child as MapRoutePoint
			route.append({"pos": at.origin, "action": r.action, "aim": r.aim, "radius": r.radius, "boost": r.boost})
		_collect(child, at, pieces, spawn_list, mover)


## A mover's blocks as one moving body (collision for the solid ones) and meshes.
func _build_mover(index: int, with_meshes: bool) -> void:
	var m: Dictionary = movers[index]
	var body := AnimatableBody3D.new()
	body.name = "Mover_%d" % index
	body.sync_to_physics = false   # moved in _physics_process; it still carries whoever stands on it
	body.transform = m.base
	body.set_meta("mover", index)
	add_child(body)
	m.body = body
	if m.node is MapIsland:
		(m.node as MapIsland).built(body)
	var built: Array = m.pieces
	if destruction:
		# Its breakable walls ride with it: their spawn guard is worked out in its frame.
		var near := []
		for r in _riders:
			if r.list == 0 and r.mover == index:
				near.append([(r.xf as Transform3D).origin, 0.0])
		built = destruction.add_riding(body, built, near)
	var bounds := AABB()
	var any := false
	for piece in m.pieces:
		if not piece.solid:
			continue
		var box: AABB = (piece.xf as Transform3D) * AABB(-(piece.size as Vector3) * 0.5, piece.size)
		bounds = bounds.merge(box) if any else box
		any = true
	m.bounds = bounds
	for piece in built:
		if piece.solid:
			for lump in collision_shapes(piece):
				var shape := CollisionShape3D.new()
				shape.shape = lump
				shape.transform = piece.xf
				body.add_child(shape)
	if not with_meshes:
		return
	var meshes := MapMesher.build(built, face_shade)
	for kind in meshes:
		var mesh := MeshInstance3D.new()
		# Its patterns ride with it (measured from the body, not the map), or they would
		# stand still while it moves through them, and shimmer.
		mesh.mesh = MapMesher.riding(meshes[kind])
		mesh.material_override = riding_material_for(kind)
		mesh.set_meta("kind", kind)
		body.add_child(mesh)


## Moves the moving parts to where they are at `clock` seconds.
func update_movers(delta: float) -> void:
	clock = clock_source.call() if clock_source.is_valid() else clock + delta
	var moved := false
	for m in movers:
		if m.body:
			var to: Transform3D = m.base * (m.node as MapMover).offset_at(clock)
			var body := m.body as AnimatableBody3D
			if not moved and not body.transform.is_equal_approx(to):
				moved = true
			body.transform = to
			if m.moves_node:
				# The scene's own node goes along, so signs, grapple points and markers
				# inside it ride too.
				(m.node as Node3D).transform = (m.parent as Transform3D) * to
	if _riders.is_empty() and _trail.is_empty() and not moved:
		return
	if moved or not _trail.is_empty():
		_follow_riders()
		_remember(delta, moved)


## Spawn points and pickup spots inside a mover go where it has gone.
func _follow_riders() -> void:
	for r in _riders:
		var body: AnimatableBody3D = movers[r.mover].body
		if body == null:
			continue
		var at: Transform3D = body.transform * (r.xf as Transform3D)
		match int(r.list):
			0:
				spawns[r.index][0] = at.origin + Vector3(0, 0.2, 0)
				spawns[r.index][1] = atan2(at.basis.z.x, at.basis.z.z)
			1:
				weapon_spawns[r.index][0] = at.origin
			2:
				item_spawns[r.index][0] = at.origin


## Have the spawn points or pickup spots moved since the match began? (The arena asks,
## to keep its floating weapons over their spots.)
func has_riders() -> bool:
	return not _riders.is_empty()


func _remember(delta: float, moved: bool) -> void:
	_trail_time += delta
	_trail_still = 0.0 if moved else _trail_still + delta
	if _trail_still > TRAIL_SECONDS:
		_trail = []   # everything has stood still long enough: nothing to make up for
		return
	var now := []
	for m in movers:
		now.append((m.body as AnimatableBody3D).transform if m.body else m.base)
	_trail.append([_trail_time, now])
	while _trail.size() > 2 and _trail[0][0] < _trail_time - TRAIL_SECONDS:
		_trail.pop_front()


## Where something that was at `point` `ago` seconds back is now, if it was riding a
## mover then: the point, carried along by how far that mover has gone since. Players
## you see over the network are drawn a moment late, which on an island under way
## would leave them trailing behind it; this puts them back on it. Anything not on a
## mover (and everything, while nothing moves) comes back unchanged.
func carried(point: Vector3, ago: float) -> Vector3:
	if _trail.is_empty() or ago <= 0.0:
		return point
	var then: Array = _trail[0]
	var want := _trail_time - ago
	for i in range(_trail.size() - 1, -1, -1):
		if _trail[i][0] <= want:
			then = _trail[i]
			break
	var index := mover_under(point, then[1])
	if index < 0:
		return point
	var was: Transform3D = then[1][index]
	var body: AnimatableBody3D = movers[index].body
	return body.transform * (was.affine_inverse() * point)


## Which mover is `point` on or in (its number in `movers`), or -1? `poses`: where the
## movers are taken to be (default: where they are now).
func mover_under(point: Vector3, poses: Array = []) -> int:
	for i in movers.size():
		var m: Dictionary = movers[i]
		if m.body == null or not (m.bounds as AABB).has_volume():
			continue
		var at: Transform3D = poses[i] if i < poses.size() else (m.body as AnimatableBody3D).transform
		var local := at.affine_inverse() * point
		var box: AABB = m.bounds
		if local.x >= box.position.x - 0.6 and local.x <= box.end.x + 0.6 and local.z >= box.position.z - 0.6 and local.z <= box.end.z + 0.6 \
				and local.y >= box.position.y - 0.5 and local.y <= box.end.y + 2.5:
			return i
	return -1


## The island `point` is on or over, or null.
func island_at(point: Vector3) -> MapIsland:
	var on := mover_under(point)
	return movers[on].node as MapIsland if on >= 0 else null


# -- Bots on parts that never stop (Sky Island's bobbing islands and pads) -----------
# The bots' navigation mesh is worked out once, from where everything stood at that
# moment. A plain MapMover keeps moving after that, so a bot asks its way in the
# mesh's frame: where it is and where it is going are put back to where the mover
# they stand on stood then (to_nav), and the path's points are carried forward to
# where that mover is now (from_nav). A MapIsland is left out: it stands still
# between a LayoutEvent's moves and its mesh is redone (or swapped) for each layout.
var _nav_poses: Array = []


## The navigation mesh is about to be worked out from where everything stands now.
func remember_nav_poses() -> void:
	_nav_poses = []
	for m in movers:
		_nav_poses.append((m.body as AnimatableBody3D).transform if m.body else m.base)


## `point` (in the map) as it was in the navigation mesh's frame.
func to_nav(point: Vector3) -> Vector3:
	if _nav_poses.size() != movers.size():
		return point   # (no mesh made yet)
	var i := _standing_on(point, false)
	if i < 0:
		return point
	return (_nav_poses[i] as Transform3D) * ((movers[i].body as AnimatableBody3D).transform.affine_inverse() * point)


## A point of the navigation mesh, carried to where its mover is now.
func from_nav(point: Vector3) -> Vector3:
	var i := _standing_on(point, true)
	if i < 0:
		return point
	return (movers[i].body as AnimatableBody3D).transform * ((_nav_poses[i] as Transform3D).affine_inverse() * point)


## Where `point`, riding whatever mover it stands on, will be `seconds` from now.
func ahead(point: Vector3, seconds: float) -> Vector3:
	var i := _standing_on(point, false)
	if i < 0:
		return point
	var m: Dictionary = movers[i]
	var then: Transform3D = m.base * (m.node as MapMover).offset_at(clock + seconds)
	return then * ((m.body as AnimatableBody3D).transform.affine_inverse() * point)


## Which plain mover `point` stands on (or over, by up to 8 m), or -1: the ground a bot
## is on, for working out a route across many moving parts (see BotBrain).
func standing_on(point: Vector3) -> int:
	return _standing_on(point, false)


## The plain mover (never a MapIsland) whose solid top is under `point`, at most 8 m
## below it (the highest such), or -1. `at_nav`: where the movers stood for the
## navigation mesh rather than where they are now.
func _standing_on(point: Vector3, at_nav: bool) -> int:
	if at_nav and _nav_poses.size() != movers.size():
		return -1
	var best := -1
	var best_gap := INF
	for i in movers.size():
		var m: Dictionary = movers[i]
		if m.body == null or m.node is MapIsland:
			continue
		var pose: Transform3D = _nav_poses[i] if at_nav else (m.body as AnimatableBody3D).transform
		var local := pose.affine_inverse() * point
		var box: AABB = m.bounds
		if local.x < box.position.x - 1.0 or local.x > box.end.x + 1.0 or local.z < box.position.z - 1.0 or local.z > box.end.z + 1.0 \
				or local.y < box.position.y - 1.0 or local.y > box.end.y + 8.0:
			continue
		for piece in m.pieces:
			if not piece.solid:
				continue
			var p: Vector3 = (piece.xf as Transform3D).affine_inverse() * local
			var half: Vector3 = piece.size * 0.5
			var inside := false
			var gap := p.y - half.y
			var up: float = (piece.xf as Transform3D).basis.x.y
			if piece.shape == "box":
				inside = absf(p.x) <= half.x + 0.3 and absf(p.z) <= half.z + 0.3
			elif piece.shape == "hull":
				var top := MapMesher.hull_top(piece.planes, p.x, p.z, 0.3)
				inside = top > -INF
				gap = p.y - top
			elif piece.shape == "wedge" and absf(up) > 0.99:
				# A wedge lying on its side is a three-cornered slab of ground (Sky Island's
				# deck round its hole is made of them): its own x is up, and it covers the
				# triangle with the right angle at its low back corner.
				# (how far past its long side the point is, in metres)
				var past := ((p.y + half.y) / (2.0 * half.y) + (p.z + half.z) / (2.0 * half.z) - 1.0) \
					/ Vector2(0.5 / half.y, 0.5 / half.z).length()
				inside = p.y >= -half.y - 0.3 and p.z >= -half.z - 0.3 and past <= 0.3
				gap = p.x * signf(up) - half.x
			else:
				var reach := Vector2(p.x, p.z).length()
				inside = reach <= half.x + 0.3 and (piece.shape != "tube" or reach >= float(piece.get("inner", 0.0)) * 0.5 - 0.3)
			if inside and gap >= -1.0 and gap <= 8.0 and gap < best_gap:
				best = i
				best_gap = gap
	return best


## Is `point` on an island that is about to go down?
func doomed_at(point: Vector3) -> bool:
	var island := island_at(point)
	return island != null and island.doomed


## A spawn point at `point`: 1 if it is on an island that is up and staying up, -1 if on
## one that is down, on its way or about to go, 0 if it is on no island at all (or beside
## an island marked Over Ground: a crane, a haunted wardrobe, which is no island).
func spawn_open(point: Vector3) -> int:
	var island := island_at(point)
	if island == null or island.over_ground:
		return 0
	return 1 if island.up and not island.doomed else -1


## The spawn points to use right now: those on islands that are up, staying and still;
## if there is none, those on ground that never moves; then those on islands gliding to
## their next place (someone put over one is in the air as it moves into them); failing
## that, all of them.
func open_spawns() -> Array:
	if movers.is_empty():
		return spawns
	var on_islands := []
	var fixed := []
	var gliding := []
	for s in spawns:
		var open := spawn_open(s[0])
		if open > 0:
			if island_at(s[0]).gliding:
				gliding.append(s)
			else:
				on_islands.append(s)
		elif open == 0:
			fixed.append(s)
	for tier in [on_islands, fixed, gliding]:
		if not tier.is_empty():
			return tier
	return spawns


## Room for a standing player (SPAWN_RADIUS, SPAWN_HEIGHT: Player's capsule) with their
## feet at `feet`: nothing of the level there, moving parts included.
const SPAWN_RADIUS := 0.4
const SPAWN_HEIGHT := 1.8
## How far clear_feet lifts a player to get them out of the ground.
const SPAWN_LIFT_REACH := 2.5


func room_at(feet: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var cap := CapsuleShape3D.new()
	cap.radius = SPAWN_RADIUS - 0.02   # (touching the floor is not being in it)
	cap.height = SPAWN_HEIGHT - 0.04
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 1
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0, SPAWN_HEIGHT * 0.5, 0))
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Where to put the feet of a player (re)spawning at `feet` so they are not stuck in
## the ground: `feet` itself when there is room, or lifted (by up to SPAWN_LIFT_REACH)
## to just over whatever it is in: a spawn point a moving part has come up through, a
## floor raised since the marker was placed. With no room anywhere above, `feet`.
func clear_feet(feet: Vector3) -> Vector3:
	if room_at(feet):
		return feet
	var lift := 0.05
	while lift <= SPAWN_LIFT_REACH:
		var up := feet + Vector3(0, lift, 0)
		if room_at(up):
			# A little more, as a spawn point has, if there is room for it.
			var over := up + Vector3(0, 0.1, 0)
			return over if room_at(over) else up
		lift += 0.05
	return feet


func _physics_process(delta: float) -> void:
	if not Engine.is_editor_hint() and not movers.is_empty():
		update_movers(delta)


func _exit_tree() -> void:
	replay_clear()
	# The map's gravity zones go with it (the next map sets its own in build()).
	if not Engine.is_editor_hint() and current == self:
		WorldGravity.clear_zones()


# ---------------------------------------------------------------------------
# Killcams (see MapReplay): the moving parts as they were. A replay draws each
# mover's meshes, and the signs and lamps riding it, where the recording says, and
# leaves the bodies themselves (what people stand on) where the match has them.

var _replay_poses: Array = []    # per mover: where a replay draws it (in the map's frame), or null
var _replay_drawn: Array = []    # per mover: what is drawn riding it
var _replay_frames := 0


## Where every mover is: one Transform3D each (in the map's frame), in `movers` order,
## then which of them are not drawn (bits: a parked island).
func replay_capture() -> Variant:
	var out := []
	var hidden := 0
	for i in movers.size():
		var body: Node3D = movers[i].body
		out.append(body.transform if body else movers[i].base)
		if body and not body.visible and i < 62:
			hidden |= 1 << i
	out.append(hidden)
	return out


func replay_show(state: Variant, next: Variant, u: float, _holder: Node3D) -> void:
	if not state is Array:
		return
	if _replay_poses.is_empty():
		_replay_frames = 0
		RenderingServer.frame_pre_draw.connect(_replay_draw)
	if _replay_frames % 10 == 0:   # (now and then: a wall riding it may have been rebuilt)
		_replay_drawn = []
		for m in movers:
			_replay_drawn.append(_riding_drawn(m))
	_replay_frames += 1
	_replay_poses = []
	var hidden := int(state[-1]) if (state as Array).size() > movers.size() and state[-1] is int else 0
	for i in movers.size():
		var a = state[i] if i < (state as Array).size() else null
		var b = next[i] if next is Array and i < (next as Array).size() else null
		_replay_poses.append((a as Transform3D).interpolate_with(b, u) if a is Transform3D and b is Transform3D else a)
		var body: Node3D = movers[i].body
		if body and i < 62:
			body.visible = hidden & (1 << i) == 0   # (only drawn or not: a parked island's collision is off anyway)
	_replay_draw()


func replay_clear() -> void:
	if _replay_poses.is_empty():
		return
	_replay_poses = []
	for m in movers:
		if m.body and is_instance_valid(m.body):
			(m.body as Node3D).visible = not (m.node is MapIsland and (m.node as MapIsland).is_parked())
	if RenderingServer.frame_pre_draw.is_connected(_replay_draw):
		RenderingServer.frame_pre_draw.disconnect(_replay_draw)
	for list in _replay_drawn:
		for v in list:
			MapReplay.draw_live(v)
	_replay_drawn = []


## What is drawn riding mover `m`: its body's meshes (and its walls'), and, when the
## scene's own node goes along with it, the signs and lamps in that.
func _riding_drawn(m: Dictionary) -> Array:
	var out := []
	if m.body and is_instance_valid(m.body):
		out.append_array(MapReplay.drawn_under(m.body))
	if m.moves_node and is_instance_valid(m.node):
		out.append_array(MapReplay.drawn_under(m.node))
	return out


## Draws each mover's riders where the replay has it, just before the frame is drawn
## (after anything this frame moved them back).
func _replay_draw() -> void:
	if not is_inside_tree():
		return
	for i in mini(_replay_poses.size(), mini(movers.size(), _replay_drawn.size())):
		var pose = _replay_poses[i]
		var body: Node3D = movers[i].body
		if not pose is Transform3D or body == null or not is_instance_valid(body):
			continue
		var shift: Transform3D = (global_transform * (pose as Transform3D)) * body.global_transform.affine_inverse()
		for v in _replay_drawn[i]:
			if is_instance_valid(v):
				MapReplay.draw_at(v, shift * (v as Node3D).global_transform)


## Where a hazard is right now (it may be riding a mover).
func hazard_xf(h: Dictionary) -> Transform3D:
	if h.mover < 0:
		return h.xf
	var m: Dictionary = movers[h.mover]
	return (m.body.transform if m.body else m.base) * h.xf


## Is `point` inside a hazard (grown by `margin` metres all round)? With `at` (a
## map clock time), where the moving ones will be then rather than now.
func hazard_at(point: Vector3, margin: float = 0.0, at: float = -INF) -> bool:
	for h in hazards:
		var xf: Transform3D = hazard_xf(h)
		if at > -INF and h.mover >= 0:
			var m: Dictionary = movers[h.mover]
			xf = m.base * (m.node as MapMover).offset_at(at) * h.xf
		var local := xf.affine_inverse() * point
		var half: Vector3 = h.size * 0.5 + Vector3(margin, margin, margin)
		if absf(local.y) > half.y:
			continue
		if h.shape == "box":
			if absf(local.x) <= half.x and absf(local.z) <= half.z:
				return true
		elif h.shape == "hull":
			if MapMesher.hull_has(h.planes, local, margin):
				return true
		elif Vector2(local.x, local.z).length() <= half.x:
			return true
	return false


## Is a player standing at `feet` touching a hazard? (Feet, middle and head, as a
## race checks its racers.)
func body_in_hazard(feet: Vector3) -> bool:
	return hazard_at(feet + Vector3(0, 0.25, 0), 0.05) or hazard_at(feet + Vector3(0, 0.9, 0), 0.0) \
		or hazard_at(feet + Vector3(0, 1.5, 0), 0.0)


## Will a moving part be there to stand on at `point` at map clock `at`? -1 if no
## moving part ever passes over it (look at the ground itself then), else 0 or 1.
func mover_ground_at(point: Vector3, at: float, tolerance: float = 0.5) -> int:
	var near := false
	for m in movers:
		var mxf: Transform3D = m.base * (m.node as MapMover).offset_at(at)
		for piece in m.pieces:
			if not piece.solid:
				continue
			var local: Vector3 = (mxf * (piece.xf as Transform3D)).affine_inverse() * point
			var half: Vector3 = piece.size * 0.5
			if absf(local.x) > half.x or absf(local.z) > half.z:
				continue
			if piece.shape == "tube" and Vector2(local.x, local.z).length() < float(piece.get("inner", 0.0)) * 0.5:
				continue   # in a tube's hole: nothing there to stand on
			var top := half.y
			if piece.shape == "hull":
				top = MapMesher.hull_top(piece.planes, local.x, local.z)
				if top == -INF:
					continue   # inside the box round it, but not over the hull itself
			near = true
			if absf(local.y - top) <= tolerance:
				return 1
	return 0 if near else -1


func _collect_dummies(node: Node, xf: Transform3D) -> void:
	for child in node.get_children():
		if not child is Node3D or not (child as Node3D).visible:
			continue
		var at := xf * (child as Node3D).transform
		if child is MapDummy:
			dummies.append([at.origin, atan2(at.basis.z.x, at.basis.z.z), child])
		_collect_dummies(child, at)


## What a piece is to bump into: one shape for most, several for a hollow dome, an
## arch or a tube (each in the piece's own frame). A tube is its ring, one lump per
## flat side, so you can stand in the hole you can see through; it is not in
## hull_points() because it is drawn by _prism, not from its lumps.
func collision_shapes(piece: Dictionary) -> Array:
	var lumps := MapMesher.tube_hulls(piece) if piece.shape == "tube" else MapMesher.hull_points(piece)
	if lumps.is_empty():
		return [_collision_shape(piece)]
	var shapes := []
	for pts in lumps:
		var hull := ConvexPolygonShape3D.new()
		hull.points = pts
		shapes.append(hull)
	return shapes


func _collision_shape(piece: Dictionary) -> Shape3D:
	if piece.shape == "cyl" or piece.shape == "tube":   # (a tube here has no hole: it is drawn as a cylinder)
		var c := CylinderShape3D.new()
		c.radius = piece.size.x * 0.5
		c.height = piece.size.y
		return c
	if piece.shape == "cone":
		var cone := ConvexPolygonShape3D.new()
		cone.points = MapMesher.cone_points(piece)   # the same flat sides you see
		return cone
	var box := BoxShape3D.new()
	box.size = piece.size
	return box


## The material blocks of this kind are drawn with.
func material_for(kind: String) -> Material:
	if _materials.is_empty():
		_materials = MapScenery.materials(palette, grid_texture)
	if not _materials.has(kind):
		_materials[kind] = MapScenery.missing_material()
	return _materials[kind]


## The material for a kind on something that moves (a mover's body). The patterned
## kinds need nothing different: the surface shader reads the mark MapMesher.riding()
## puts on the mesh, so they share the one material and anything that changes it (an
## event dimming or lighting a kind) still reaches them. Only the test maps' distance
## grid does: a StandardMaterial3D lays it out from the map, so a mover gets a copy that
## lays it out from the body. (A copy does not follow later changes to the original;
## no grid map changes its materials.)
func riding_material_for(kind: String) -> Material:
	var m := material_for(kind)
	var standard := m as StandardMaterial3D
	if standard == null or not (standard.uv1_triplanar and standard.uv1_world_triplanar):
		return m
	if not _riding_materials.has(kind):
		var copy := standard.duplicate() as StandardMaterial3D
		copy.uv1_world_triplanar = false
		_riding_materials[kind] = copy
	return _riding_materials[kind]


## For blocks outside a map (a scene of its own): the Construction Site's colours.
static func fallback_material(kind: String) -> Material:
	if _fallback.is_empty():
		_fallback = MapScenery.materials(load(FALLBACK_PALETTE), false)
	return _fallback.get(kind, MapScenery.missing_material())


## Editor only: how solid-but-not-drawn blocks look.
static func ghost_material() -> Material:
	if _ghost == null:
		_ghost = StandardMaterial3D.new()
		_ghost.albedo_color = Color(0.35, 0.65, 1.0, 0.12)
		_ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _ghost


func _palette_changed() -> void:
	_materials.clear()
	_riding_materials.clear()
	if Engine.is_editor_hint() and is_inside_tree():
		propagate_call("refresh_preview")
		update_gizmos()


func _get_configuration_warnings() -> PackedStringArray:
	return [] if palette else ["Give the map a palette (the colours of its block kinds)."]
