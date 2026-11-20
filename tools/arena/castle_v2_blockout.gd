extends SceneTree
## RETIRED: game/maps/castle_v2.tscn is edited by hand now (blocks were moved in the
## editor), and this script would overwrite that work, so it refuses to run unless
## CASTLE_V2_REBUILD=1 is set. It is kept as a record of how the map was laid out.
##
## Builds game/maps/castle_v2.tscn: a grey block-out of the refreshed Castle.
##
##   godot --headless --path . --script tools/arena/castle_v2_blockout.gd
##
## It starts from game/maps/castle.tscn and keeps its sky, sun, palette and the world
## outside the walls (the lake, causeway and mountains), then lays out the new plan:
##  - a 72 m square (walls at plus or minus 36, outer faces at 37.5), up from 60 m,
##    its outer corners rounded off by the corner bastions (4.5 m radius);
##  - a wall walk you can run all the way round: the corner bastions are flush with it;
##  - a stair up each wall, along its inner face, at the clockwise end ("pinwheel"),
##    with a landing from its head into the corner bastion;
##  - the keep in the middle with a door on every side on both floors, a ramp inside
##    from the hall to the upper floor and another up to the roof;
##  - four bridges at 6 m from the keep's upper floor to the middle of each wall;
##  - in each quarter, a chain of blocks (2.2 m, then 4.2 m) you can climb onto a
##    bridge without the grapple, a wall to wall-run, low cover, and a placeholder for
##    what the quarter will be (market, stables, training yard, well);
##  - 20 spawn points across the three heights, and the 17 weapon spawns moved over.
## Run it again after changing the numbers below; it overwrites castle_v2.tscn, so
## run tools/arena/castle_v2_dressing.gd after it to put the detail back. Once
## the layout settles and the scene is edited by hand, stop running it.

const SOURCE := "res://game/maps/castle.tscn"
const OUT := "res://game/maps/castle_v2.tscn"

const FACE := 37.5        ## the walls' outer faces
const INNER := 34.5       ## the walls' inner faces
const WALK := 6.0         ## the wall walk, bridges and keep upper floor
const KEEP := 9.0         ## the keep's outer faces
const KEEP_TOP := 12.0    ## the keep's roof
const BASTION := 33.0     ## the corner bastions' centres (on both axes)
const ANGLE := 60.0       ## the shore's slope

var scn: Node3D
var block_script: Script
var spawn_script: Script
var errors := []


func _init() -> void:
	# The scene is edited by hand now: a run would throw those edits away.
	if OS.get_environment("CASTLE_V2_REBUILD") != "1":
		printerr("castle_v2.tscn is edited by hand now and this script would overwrite that work. " +
			"It is kept as a record of how the map was laid out. To run it anyway, set CASTLE_V2_REBUILD=1.")
		quit(1)
		return
	block_script = load("res://game/arena/map_block.gd")
	spawn_script = load("res://game/arena/map_spawn.gd")
	scn = (load(SOURCE) as PackedScene).instantiate()
	scn.name = "CastleV2"
	scn.scene_file_path = ""
	build()
	if not errors.is_empty():
		for e in errors:
			printerr("BLOCKOUT: ", e)
		quit(1)
		return
	var ps := PackedScene.new()
	var err := ps.pack(scn)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
	print("BLOCKOUT: saved %s (%s): %d blocks, %d spawns" % [OUT, error_string(err),
		scn.find_children("*", "MapBlock", true, false).size(), scn.get_node("Spawns").get_child_count()])
	quit(0 if err == OK else 1)


# -- helpers -------------------------------------------------------------------------
func group(parent: Node, name: String, lock := false) -> Node3D:
	var g := parent.get_node_or_null(name) as Node3D
	if g == null:
		g = Node3D.new()
		g.name = name
		parent.add_child(g)
		g.owner = scn
	if lock:
		g.set_meta("_edit_group_", true)
	return g


func remove(x: Node) -> void:
	if x:
		x.get_parent().remove_child(x)
		x.free()


func gx(x: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while x != null and x != scn:
		if x is Node3D:
			t = (x as Node3D).transform * t
		x = x.get_parent()
	return t


## A block in the map's frame: `xf` is its centre and turn.
func put(parent: Node, name: String, kind: String, size: Vector3, xf: Transform3D, solid := true) -> MapBlock:
	var b: MapBlock = block_script.new()
	b.name = name
	b.size = size
	b.kind = kind
	b.solid = solid
	parent.add_child(b, true)
	b.owner = scn
	b.transform = gx(parent).affine_inverse() * xf
	return b


## An upright box from `lo` to `hi` (map frame).
func box(parent: Node, name: String, kind: String, lo: Vector3, hi: Vector3, solid := true) -> MapBlock:
	return put(parent, name, kind, (hi - lo).abs(), Transform3D(Basis.IDENTITY, (lo + hi) * 0.5), solid)


func cyl(parent: Node, name: String, kind: String, at: Vector3, diameter: float, height: float, sides := 24) -> MapBlock:
	var b := put(parent, name, kind, Vector3(diameter, height, diameter), Transform3D(Basis.IDENTITY, at + Vector3(0, height * 0.5, 0)))
	b.shape = MapBlock.Shape.CYLINDER
	b.sides = sides
	return b


## A slab whose top runs from `a` to `b` (the middle of each end), `width` across.
func ramp(parent: Node, name: String, kind: String, a: Vector3, b: Vector3, width: float, thick := 0.5) -> MapBlock:
	var along := (b - a).normalized()
	var across := Vector3.UP.cross(along).normalized()
	var up := along.cross(across)
	var c := (a + b) * 0.5 - up * thick * 0.5
	return put(parent, name, kind, Vector3(width, thick, (b - a).length()), Transform3D(Basis(across, up, along), c))


## Turns a point or a box corner a quarter at a time, clockwise seen from above
## (north to east to south to west).
func turn(p: Vector3, quarters: int) -> Vector3:
	for i in quarters:
		p = Vector3(-p.z, p.y, p.x)
	return p


## An upright box given in the north-east quarter's frame, turned into quarter `q`.
func qbox(parent: Node, name: String, kind: String, q: int, lo: Vector3, hi: Vector3, solid := true) -> MapBlock:
	var a := turn(lo, q)
	var b := turn(hi, q)
	return box(parent, name, kind, a.min(b), a.max(b), solid)


# -- the castle --------------------------------------------------------------------------
func build() -> void:
	for old in ["Ground", "Walls", "Towers", "Gatehouse", "Keep", "Walkways", "Bailey"]:
		remove(scn.get_node_or_null(old))
	scn.set("kill_height", -5.0)
	scn.set("bounds", Rect2(-400, -400, 800, 800))
	scn.set("swing_point", Vector3(0, KEEP_TOP + 1.6, -4))
	var order := ["Environment", "Sun", "Ground", "Walls", "Bastions", "Gatehouse", "Keep", "Bridges", "Quarters",
		"Outside", "Spawns", "WeaponSpawns"]
	ground()
	walls()
	bastions()
	gatehouse()
	keep()
	bridges()
	quarters()
	outside()
	spawns()
	for i in order.size():
		var x := scn.get_node_or_null(order[i])
		if x == null:
			errors.append("missing " + order[i])
		else:
			scn.move_child(x, i)


func ground() -> void:
	var g := group(scn, "Ground")
	# A plus shape out to the outer faces; the bastions (which reach down to its foot)
	# fill the rounded corners.
	box(g, "FloorNorthSouth", "cobble", Vector3(-BASTION, -1, -FACE), Vector3(BASTION, 0, FACE))
	box(g, "FloorEastWest", "cobble", Vector3(-FACE, -1, -BASTION), Vector3(FACE, 0, BASTION))


func walls() -> void:
	var w := group(scn, "Walls")
	var names := ["North", "East", "South", "West"]
	for q in 4:
		var side := group(w, "Curtain" + names[q])
		# The wall (north, turned): the full length, so the corners are filled.
		# The wall (north, turned) stops where the corner bastions round the corners off.
		qbox(side, "Wall", "stone", q, Vector3(-BASTION, 0, -FACE), Vector3(BASTION, WALK, -INNER))
		# Merlons along the outer edge, clear of the bastions and the gatehouse.
		var bat := group(side, "Battlements")
		var u := -30.0
		while u <= 30.0:
			if not (q == 2 and absf(u) < 7.0):
				qbox(bat, "Merlon", "stone", q, Vector3(u - 0.7, WALK, -FACE), Vector3(u + 0.7, WALK + 1.2, -FACE + 0.6))
			u += 3.0
		# The stair up from the bailey, along the inner face, rising clockwise.
		var a := turn(Vector3(12, 0, -INNER + 1.5), q)
		var b := turn(Vector3(26, WALK, -INNER + 1.5), q)
		ramp(side, "Stair", "stone_dark", a, b, 3.0, 0.6)
		# A landing from the stair's head into the corner bastion, level with the wall
		# walk, so the stair arrives at the tower instead of stopping short of it. The
		# same kind as the wall and the bastion: their tops are one surface.
		qbox(side, "Landing", "stone", q, Vector3(26, WALK - 0.6, -INNER), Vector3(29.5, WALK, -INNER + 3.03))   # 3 cm past the stair's side, so the two side faces never share a plane


func bastions() -> void:
	var g := group(scn, "Bastions")
	var names := ["NorthEast", "SouthEast", "SouthWest", "NorthWest"]
	for q in 4:
		var bst := group(g, names[q])
		var c := turn(Vector3(BASTION, 0, -BASTION), q)
		# Flush with the wall walk: the walk runs straight across the top.
		# Its outer half is the castle's rounded corner (as many sides as the shore's cone below).
		cyl(bst, "Body", "stone", c - Vector3(0, 1, 0), 2 * (FACE - BASTION), WALK + 1, 48)


func gatehouse() -> void:
	var g := group(scn, "Gatehouse")
	var z0 := INNER - 1.0
	box(g, "Front", "stone", Vector3(-6, 0, z0), Vector3(6, WALK, INNER))
	box(g, "UpperWest", "stone", Vector3(-6, WALK, z0), Vector3(-1.5, WALK + 3, FACE))
	box(g, "UpperEast", "stone", Vector3(1.5, WALK, z0), Vector3(6, WALK + 3, FACE))
	box(g, "Roof", "slate", Vector3(-6.3, WALK + 3, z0 - 0.2), Vector3(6.3, WALK + 3.5, FACE))
	box(g, "Gate", "door", Vector3(-2, 0, z0 - 0.1), Vector3(2, 4.5, z0), false)


func keep() -> void:
	var k := group(scn, "Keep")
	var t := 1.0         # wall thickness
	var wall_top := KEEP_TOP - 0.5
	var door := 1.5      # half a door's width
	var names := ["North", "East", "South", "West"]
	for q in 4:
		var f := group(k, names[q] + "Face")
		# Built facing north, turned. The north and south walls run the full width, the
		# east and west ones between them.
		var reach := KEEP if q % 2 == 0 else KEEP - t
		qbox(f, "WallLeft", "stone", q, Vector3(-reach, 0, -KEEP), Vector3(-door, wall_top, -KEEP + t))
		qbox(f, "WallRight", "stone", q, Vector3(door, 0, -KEEP), Vector3(reach, wall_top, -KEEP + t))
		qbox(f, "BetweenDoors", "stone", q, Vector3(-door, 3.5, -KEEP), Vector3(door, WALK, -KEEP + t))
		qbox(f, "OverUpperDoor", "stone", q, Vector3(-door, WALK + 3, -KEEP), Vector3(door, wall_top, -KEEP + t))
		var bat := group(f, "Battlements")
		var u := -7.5
		while u <= 7.6:
			qbox(bat, "Merlon", "stone", q, Vector3(u - 0.6, KEEP_TOP, -KEEP), Vector3(u + 0.6, KEEP_TOP + 1.0, -KEEP + 0.5))
			u += 2.5
	var inside := KEEP - t
	# Two free-standing ramps inside, clear of every door (a ramp along a wall would
	# cross that wall's door): hall to upper floor rising west, upper floor to roof
	# rising east, each 11 m long (29 degrees) with room at both ends.
	var r0 := 5.5            # the ramps run from x = -5.5 to 5.5
	var lane := [-4.25, -1.75]   # the hall ramp's strip (z); the roof ramp's is mirrored
	var hall := group(k, "Hall")
	ramp(hall, "RampUp", "stone_dark", Vector3(r0, 0, -3), Vector3(-r0, WALK, -3), 2.5, 0.4)
	var up := group(k, "UpperFloor")
	var fy := WALK - 0.4
	box(up, "FloorNorth", "stone_dark", Vector3(-inside, fy, -inside), Vector3(inside, WALK, lane[0]))
	box(up, "FloorSouth", "stone_dark", Vector3(-inside, fy, lane[1]), Vector3(inside, WALK, inside))
	box(up, "LandingWest", "stone_dark", Vector3(-inside, fy, lane[0]), Vector3(-r0, WALK, lane[1]))
	box(up, "LandingEast", "stone_dark", Vector3(r0, fy, lane[0]), Vector3(inside, WALK, lane[1]))
	ramp(up, "RampToRoof", "stone_dark", Vector3(-r0, WALK, 3), Vector3(r0, KEEP_TOP, 3), 2.5, 0.4)
	# The roof deck, open over the roof ramp.
	var roof := group(k, "Roof")
	var deck := KEEP_TOP - 0.5
	box(roof, "DeckNorth", "slate", Vector3(-KEEP, deck, -KEEP), Vector3(KEEP, KEEP_TOP, -lane[1]))
	box(roof, "DeckSouth", "slate", Vector3(-KEEP, deck, -lane[0]), Vector3(KEEP, KEEP_TOP, KEEP))
	box(roof, "DeckWest", "slate", Vector3(-KEEP, deck, -lane[1]), Vector3(-r0, KEEP_TOP, -lane[0]))
	box(roof, "DeckEast", "slate", Vector3(r0, deck, -lane[1]), Vector3(KEEP, KEEP_TOP, -lane[0]))
	box(roof, "Turret", "stone", Vector3(-1.5, KEEP_TOP, -5.5), Vector3(1.5, KEEP_TOP + 1.6, -2.5))


func bridges() -> void:
	var g := group(scn, "Bridges")
	var names := ["North", "East", "South", "West"]
	for q in 4:
		var b := group(g, names[q])
		var end := INNER - (1.0 if q == 2 else 0.0)   # the south one meets the gatehouse
		qbox(b, "Deck", "wood", q, Vector3(-1.5, WALK - 0.3, -end), Vector3(1.5, WALK, -KEEP))
		var mid := (end + KEEP) * 0.5
		qbox(b, "Pier", "stone", q, Vector3(-0.5, 0, -mid - 0.5), Vector3(0.5, WALK - 0.3, -mid + 0.5))


func quarters() -> void:
	var g := group(scn, "Quarters")
	var names := ["NorthEast", "SouthEast", "SouthWest", "NorthWest"]
	var themes := ["Stables", "TrainingYard", "Well", "Market"]
	for q in 4:
		var quarter := group(g, names[q] + themes[q])
		# Climb chain beside the bridge (clockwise side): 2.2 m, then 4.2 m, then onto
		# the bridge 1.8 m above (a ledge climb reaches 2.3 m).
		var chain := group(quarter, "ClimbChain")
		qbox(chain, "Low", "wood_light", q, Vector3(4.6, 0, -25), Vector3(8.6, 2.2, -20))
		qbox(chain, "High", "wood_light", q, Vector3(1.6, 0, -24), Vector3(4.6, 4.2, -21))
		# A wall to run along, and low cover you can vault (1.2 m).
		qbox(quarter, "WallRun", "stone", q, Vector3(21.6, 0, -22), Vector3(22.4, 4.5, -12))
		var cover := group(quarter, "Cover")
		qbox(cover, "LowWall", "stone", q, Vector3(13, 0, -13.8), Vector3(17, 1.2, -13.2))
		qbox(cover, "LowWall", "stone", q, Vector3(26.7, 0, -10), Vector3(27.3, 1.2, -6))
		qbox(cover, "Crate", "wood", q, Vector3(26.4, 0, -27.6), Vector3(27.6, 1.2, -26.4))
		qbox(cover, "Crate", "wood", q, Vector3(27.8, 0, -27.2), Vector3(28.9, 1.1, -26.1))
		# What the quarter will be (a placeholder each).
		var theme := group(quarter, themes[q])
		match themes[q]:
			"Stables":
				qbox(theme, "Cart", "wood", q, Vector3(16, 0, -28.5), Vector3(19.2, 1.1, -26.9))
				qbox(theme, "Hay", "hay", q, Vector3(20.5, 0, -29), Vector3(22.5, 1.1, -27.8))
				qbox(theme, "Hay", "hay", q, Vector3(20.6, 1.1, -28.9), Vector3(22.4, 2.1, -27.9))
			"TrainingYard":
				qbox(theme, "Hoarding", "hoarding", q, Vector3(15.5, 0, -27.65), Vector3(19.1, 3.2, -27.35))
				qbox(theme, "Hoarding", "hoarding", q, Vector3(20.5, 0, -25.15), Vector3(24.1, 3.2, -24.85))
			"Well":
				cyl(theme, "Well", "stone_light", turn(Vector3(19, 0, -27), q), 2.8, 1.1, 20)
			"Market":
				for c in [Vector3(16.2, 0, -28.8), Vector3(20.2, 0, -28.8), Vector3(16.2, 0, -25.6), Vector3(20.2, 0, -25.6)]:
					qbox(theme, "Post", "wood", q, c - Vector3(0.1, 0, 0.1), c + Vector3(0.1, 2.04, 0.1))
				qbox(theme, "Roof", "cloth", q, Vector3(15.8, 2.04, -29.2), Vector3(20.6, 2.2, -25.2))
				qbox(theme, "Counter", "wood", q, Vector3(16.4, 0, -26.2), Vector3(20, 1.0, -25.6))


## The world outside, from the old castle, moved out to the new walls.
func outside() -> void:
	var o := scn.get_node("Outside") as Node3D
	var rock: MapBlock = o.get_node("Rock")
	# Under the castle, the same plus shape (the shore's corner cones fill the corners).
	rock.size = Vector3(2 * BASTION, rock.size.y, 2 * FACE)
	var rock2 := put(o, "RockEastWest", rock.kind, Vector3(2 * FACE, rock.size.y, 2 * BASTION), Transform3D(Basis.IDENTITY, gx(rock).origin))
	o.move_child(rock2, rock.get_index() + 1)
	var shore := o.get_node("Shore")
	for c in shore.get_children():
		remove(c)
	var a := deg_to_rad(ANGLE)
	var drop := 6.5
	var s1 := drop / sin(a)
	for side in [["North", Vector3(0, 0, -1)], ["South", Vector3(0, 0, 1)], ["West", Vector3(-1, 0, 0)], ["East", Vector3(1, 0, 0)]]:
		var out: Vector3 = side[1]
		var d := out * cos(a) + Vector3.DOWN * sin(a)
		var up := out * sin(a) + Vector3.UP * cos(a)
		var along := up.cross(d).normalized()
		var c := out * FACE + d * (s1 - 0.35) * 0.5 - up * 1.25
		put(shore, String(side[0]), "rock", Vector3(2 * BASTION - 0.02, 2.5, s1 + 0.35), Transform3D(Basis(along, up, along.cross(up)), c))
	# The rounded corners: a cone cut off flat at the corner's curve, with the same slope.
	var foot := drop / tan(a)
	var curve := FACE - BASTION
	for corner in [["NorthWest", -1, -1], ["NorthEast", 1, -1], ["SouthWest", -1, 1], ["SouthEast", 1, 1]]:
		var cone := put(shore, String(corner[0]) + "Corner", "rock", Vector3(2 * (curve + foot), drop, 2 * (curve + foot)),
			Transform3D(Basis.IDENTITY, Vector3(corner[1] * BASTION, -drop * 0.5, corner[2] * BASTION)))
		cone.shape = MapBlock.Shape.CONE
		cone.sides = 48
		cone.top = 2 * curve
	var grow := FACE - 30.0
	for b in o.get_node("Boulders").get_children():
		var p: Vector3 = b.transform.origin
		if absf(p.x) > absf(p.z):
			p.x += signf(p.x) * grow
		else:
			p.z += signf(p.z) * grow
		b.transform.origin = p
	# The causeway still starts 40 m out from the gate.
	var cw := o.get_node("Causeway")
	var start := FACE + 40.0
	var end := 190.0
	for name in ["Deck", "Parapet", "Parapet2"]:
		var b: MapBlock = cw.get_node(name)
		b.size.z = end - start
		b.transform.origin.z = (start + end) * 0.5
	var road: MapBlock = cw.get_node("Road")
	road.size.z = end - (start + 0.9)
	road.transform.origin.z = (start + 0.9 + end) * 0.5
	for gp in ["GatepostWest", "GatepostEast"]:
		(cw.get_node(gp) as Node3D).transform.origin.z += grow
	for pier in cw.get_node("Piers").get_children():
		pier.transform.origin.z += grow
		if pier.transform.origin.z > end - 2.0:
			remove(pier)


func spawn(parent: Node, name: String, at: Vector3, outward := false) -> void:
	var m: Marker3D = spawn_script.new()
	m.name = name
	parent.add_child(m, true)
	m.owner = scn
	var yaw := atan2(at.x, at.z) + (PI if outward else 0.0)   # face the middle (or away from it)
	m.transform = Transform3D(Basis(Vector3.UP, yaw), at)


func spawns() -> void:
	var sp := scn.get_node("Spawns")
	for c in sp.get_children():
		remove(c)
	var names := ["NorthEast", "SouthEast", "SouthWest", "NorthWest"]
	var walls := ["North", "East", "South", "West"]
	for q in 4:
		spawn(sp, "Ground" + names[q] + "A", turn(Vector3(12, 0, -19), q))
		spawn(sp, "Ground" + names[q] + "B", turn(Vector3(28, 0, -14), q))
		spawn(sp, "Wall" + walls[q], turn(Vector3(10, WALK, -INNER - 1.1), q))
	spawn(sp, "BastionNorthEast", turn(Vector3(BASTION + 0.5, WALK, -BASTION - 0.5), 0))
	spawn(sp, "BastionSouthWest", turn(Vector3(BASTION + 0.5, WALK, -BASTION - 0.5), 2))
	spawn(sp, "GatehouseRoof", Vector3(-3.5, WALK + 3.5, FACE - 1.5))
	spawn(sp, "KeepHall", Vector3(-4, 0, 3), true)
	spawn(sp, "KeepUpperA", Vector3(-5, WALK, 6.5), true)
	spawn(sp, "KeepUpperB", Vector3(5, WALK, -6.5), true)
	spawn(sp, "KeepRoofA", Vector3(5, KEEP_TOP, -5), true)
	spawn(sp, "KeepRoofB", Vector3(-5, KEEP_TOP, -3), true)
	# The weapon pickups, moved to the new places.
	var at := {
		"Akimbo": turn(Vector3(10, 0, -14), 0), "Pistol": turn(Vector3(10, 0, -14), 1),
		"Shotgun": turn(Vector3(10, 0, -14), 2), "Rifle2": turn(Vector3(10, 0, -14), 3),
		"Revolver": turn(Vector3(-10, WALK, -INNER - 1.1), 0), "BurstRifle": turn(Vector3(-10, WALK, -INNER - 1.1), 1),
		"Spear": turn(Vector3(-10, WALK, -INNER - 1.1), 2), "LeverAction": turn(Vector3(-10, WALK, -INNER - 1.1), 3),
		"Sword": Vector3(0, 0, 2), "Hammer2": turn(Vector3(3.1, 4.2, -22.5), 1), "Hammer": turn(Vector3(3.1, 4.2, -22.5), 3),
		"MachinePistol": Vector3(2, WALK, 6.5), "Rifle": Vector3(-2, WALK, -6.5),
		"LeverAction2": Vector3(7, KEEP_TOP, 3), "GrenadeLauncher": Vector3(-5, KEEP_TOP, -6.5),
		"Railgun": turn(Vector3(BASTION + 0.5, WALK, -BASTION - 0.5), 3),
		"RocketLauncher": turn(Vector3(BASTION + 0.5, WALK, -BASTION - 0.5), 1),
	}
	var ws := scn.get_node("WeaponSpawns")
	for w in ws.get_children():
		if not at.has(String(w.name)):
			errors.append("no place for the weapon spawn " + w.name)
			continue
		(w as Node3D).transform = Transform3D(Basis.IDENTITY, at[String(w.name)])
	if ws.get_child_count() != at.size():
		errors.append("weapon spawns: %d in the scene, %d places" % [ws.get_child_count(), at.size()])
