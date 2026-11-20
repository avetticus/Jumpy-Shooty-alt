extends SceneTree
## Builds game/maps/sky_island.tscn: seven floating islands at mixed heights, three of
## them carrying the ruins of a castle of warm sandstone, over a sea of cloud, in bright
## colours under a deep blue sky. Each island is vivid grass on top (the turf overhangs
## a band of earth) and rock hanging underneath in jagged cones, with bits of it
## floating beside. On it grow pines in clumps and trees in pink blossom, over patches
## of darker and sunnier meadow, with boulders near the edge. The grass is kept clean:
## no small flowers, no blades of grass, and nothing hangs from the rims.
## game/maps/sky_island_layout.tscn keeps the grey block-out this started from.
##
## Colour: things take their colour from the palette's kind; a block's tint shades one
## thing off the next (each clump of pines, each ball of blossom, each boulder).
##
## Grouped the way the castle maps are: by object, each holding its own dressing (a
## wall piece's footing, loose stones and ivy are in its Wall group, a banner's pole
## and cloth in its Banner group), and the small things you would move as one are
## selection groups, so a click in the viewport picks the whole thing (a pad, a wall
## piece, a column, a tree, a patch of meadow, a lobe of an island with its rocks).
##
##   godot --headless --path . --script tools/arena/sky_island_blockout.gd
##
## It writes the scene FROM SCRATCH, so a run overwrites hand edits. Change the numbers
## below and run it again while the layout is still moving; once the scene is edited by
## hand, stop running it.
##
## The seven islands. The Hearth, in the middle, is the lowest; the six stand round it
## about a sixth of a turn apart, at mixed heights (going round from the east):
##   Shelf     3 m   a formal garden: clipped hedges with stone gate posts, a fountain
##                   of two bowls in the middle
##   Bluff     8 m   a big round hole right through its middle (falling in is death)
##                   and a tall wooden crane whose rope and hook hang down into it;
##                   crates and barrels; a low dry-stone fence round the edge
##   Spire     4 m   open and small: two blocks of cover
##   Citadel   7 m   the Gate and its curtain wall (a wall walk, a gate arch, a drum
##                   flying a blue pennant), blue banners
##   Garden    2 m   open: a ring of grey standing stones, nothing in the middle
##   Terrace   6 m   the Broken Tower (an eight-sided shell, a lookout 6 m up inside),
##                   purple banners
##   Hearth   -3 m   the biggest, with the ruined Keep (broken walls, a piece of its
##                   upper floor on timber joists, two corner drums, one flying a red
##                   pennant), red banners
## No island is round: each is a handful of overlapping many-sided slabs ("lobes") of
## different sizes, so its edge runs in and out, with a cone of rock hung under each.
##
## There is NO path you can walk from one island to another, and no grapple points:
##  - stepping pads (a few big rocks 4.5 to 9 m across, each a step higher or lower than
##    the last, well scattered either side of the straight line) join the six outer
##    islands into a ring: each to the next (see STONES below);
##  - nothing joins the Hearth to the outer islands: about 24 m of open sky each, the
##    Hearth 4 to 11 m below on average (each comes within 7 m of it at some moment). Rocket boots, or a long jump down, get you across.
##
## Everything floats up and down. Each island is a MapMover with its own rise and its
## own moment in the cycle (see BOB), all on one period, and whatever stands on it
## rides along: ruins, cover, spawn points. Each pad is a MapMover too, timed to the
## two islands it lies between, so the rows of pads flex with them. The heights above
## are the middle of each island's bob. In the editor (and in this file) a mover sits at
## the bottom of its bob, so the scene looks a little uneven until the game runs it.
## Every gap is open sky, and falling is death.

const OUT := "res://game/maps/sky_island.tscn"
const PALETTE := "res://game/maps/palettes/sky_island.tres"
const SKY := "res://game/maps/sky/sky_island_sky.gdshader"

const DECK := 1.4          ## how thick an island's deck is
const TURF := 0.3          ## the grass on top of it (the rest is earth)
const LOBE_SIDES := 16     ## the sides of every slab of island ground (the rock under it keeps its own few, blocky)
const PAD_SIDES := 9       ## the least sides a pad's top has (the rock under it keeps its own, blocky)

const THICK := 0.8         ## the ruins' walls
const CLEAR := 0.8         ## the least open sky between a pad and an island, or the next pad

## name: [centre (y = the deck's top), lobes]. A lobe: [x, z (from the centre), diameter,
## sides, turn in degrees]. The first lobe is the island's main body.
const ISLANDS := {
	"Shelf": [Vector3(-4, 3, 66), [[0, 0, 30, 8, 20], [11, -6, 20, 7, 0], [-10, 8, 20, 6, 30], [4, 12, 16, 7, 10]]],
	"Bluff": [Vector3(-57, 8, 32), [[0, 0, 30, 8, 15], [9, -8, 20, 7, 0], [-9, 7, 20, 6, 20], [5, 11, 16, 7, 35]]],
	"Spire": [Vector3(-63, 4, -31), [[0, 0, 22, 7, 10], [8, 6, 16, 6, 0], [-7, -6, 14, 7, 30]]],
	"Citadel": [Vector3(-4, 7, -62), [[0, 0, 36, 9, 0], [14, 4, 26, 7, 30], [-14, 3, 26, 8, 10], [0, -13, 22, 6, 20]]],
	"Garden": [Vector3(57, 2, -38), [[0, 0, 28, 7, 15], [-10, 7, 20, 8, 0], [8, -10, 18, 6, 25], [9, 9, 16, 7, 5]]],
	"Terrace": [Vector3(71, 6, 33), [[0, 0, 32, 8, 5], [-11, -9, 22, 7, 30], [10, 10, 22, 6, 0], [11, -9, 18, 7, 20]]],
	"Hearth": [Vector3(0, -3, 0), [[0, 0, 42, 9, 10], [15, 9, 28, 7, 40], [-16, -6, 26, 8, 0], [-5, 17, 24, 7, 25], [9, -16, 24, 6, 15]]],
}

## Crossings by stepping pads: every gap round the ring of outer islands.
const STONES := [["Terrace", "Shelf"], ["Shelf", "Bluff"], ["Bluff", "Spire"], ["Spire", "Citadel"],
	["Citadel", "Garden"], ["Garden", "Terrace"]]

## Seconds for one bob, down to up and back: the same for every island, which is what
## lets a pad follow two islands at once exactly (see pad_bob()).
const PERIOD := 14.0
## name: [rise in metres from the bottom of its bob to the top, phase (0..1: where in
## the cycle it starts)]. Round the ring each island is a sixth of a cycle after the
## last, so the bob travels round it like a slow wave.
const BOB := {
	"Terrace": [5.5, 0.0], "Shelf": [6.5, 0.1667], "Bluff": [8.0, 0.3333], "Spire": [4.8, 0.5],
	"Citadel": [7.0, 0.6667], "Garden": [7.2, 0.8333], "Hearth": [4.0, 0.8333],   # with the Garden, the lowest outer island, so it never rises past it
}

## Bots' crossings (MapJumpLink). Across the pads: a hop each way between each pad and
## the next (a running jump, or a ledge climb for a step up), at any moment, since the
## pads keep every step to about 2 m. To and from the Hearth: the rocket boots, timed
## to the bob. Going down, at any moment. Going up, only while the landing will be at
## most HEARTH_CLIMB metres above the takeoff when the bot comes down. A sprint, a jump
## and the boots, then a glide, top out at about 7.5 m over 24 m of open sky. An outer
## island that never comes that low gets no way up from the Hearth: bots go round by
## the pads instead.
const HEARTH_CLIMB := 6.0
const RUN_UP := 2.5        ## a hop's takeoff stands this far back from the edge
const BOOST_RUN := 6.0     ## a boost's takeoff stands this far back
const BOOST_FLIGHT := 1.6  ## about how long a boost crossing takes (seconds)

## Weapon pickups for Deathmatch: island -> [[weapon, x, y, z], ...] in the island's
## frame (y = 0 is its deck). The big guns sit up high: the rocket launcher on the
## Keep's upper floor, the bolt-action rifle on the Citadel's wall walk, the railgun on the
## Broken Tower's lookout.
const PICKUPS := {
	"Hearth": [["rocket_launcher", -8.0, 3.0, -4.0], ["shotgun", -1.5, 0.0, 0.5], ["rifle", 15.0, 0.0, 12.0], ["sword", -14.0, 0.0, -12.0]],
	"Shelf": [["rifle", 4.0, 0.0, 4.0], ["sword", -12.0, 0.0, 3.0]],
	"Bluff": [["burst_rifle", 0.0, 0.0, -6.6],["grenade_launcher", -4.0, 0.0, 10.0]],
	"Spire": [["akimbo", 3.0, 0.0, -3.0]],
	"Citadel": [["bolt_action", -15.3, 5.0, -2.9], ["machine_pistol", 0.0, 0.0, 3.0]],
	"Garden": [["spear", 0.0, 0.0, -3.5], ["lever_action", 4.0, 0.0, 12.0]],
	"Terrace": [["railgun", 4.5, 6.0, -1.4], ["hammer", -6.0, 0.0, 12.0]],
}

var scn: Node3D
var block_script: Script
var spawn_script: Script
var mover_script: Script
var link_script: Script
var weapon_script: Script
var rng := RandomNumberGenerator.new()
## island -> its moving group; island -> [[x, z, radius], ...]: what stands on its deck
## (filled in once the islands are built), for keeping crossings and pickups clear.
var island_nodes := {}
var obstacles := {}
var links := 0
## The dressing's own random numbers, apart from `rng` (which lays the pads), so adding
## or changing dressing never moves a pad.
var deco := RandomNumberGenerator.new()
## mover -> where its middle is half way up its bob (in the map).
var mid_of := {}
## [x, z (in the map), radius]: spots the foliage keeps off (spawn points, pickups,
## where bots set off and land, and their run-ups).
var keep_clear := []
## [a group directly inside an island (or the island), Rect2 (x, z)]: paved floors, which grow no grass.
var paved := []
var pads_drawn := []   # [middle of its top (half way up), diameter, sides, turn]: every pad, for pad_clearance()


func _init() -> void:
	block_script = load("res://game/arena/map_block.gd")
	spawn_script = load("res://game/arena/map_spawn.gd")
	mover_script = load("res://game/arena/map_mover.gd")
	link_script = load("res://game/arena/map_jump_link.gd")
	weapon_script = load("res://game/arena/map_weapon_spawn.gd")
	scn = (load("res://game/arena/map_root.gd") as Script).new()
	rng.seed = 7007
	deco.seed = 4242
	scn.name = "SkyIsland"
	scn.set_meta("breakable_migrated", true)   # (tools/arena/migrate_breakable.gd has nothing to do here: nothing breaks)
	scn.set("palette", load(PALETTE))
	scn.set("grid_texture", false)
	scn.set("face_shade", Vector3(0.9, 0.8, 0.65))
	scn.set("kill_height", -36.0)      # the deepest rock (the Hearth's, at the bottom of its bob) ends at about -26
	scn.set("bounds", Rect2(-150, -150, 300, 300))
	scn.set("swing_point", centre("Hearth") + Vector3(11, 10.5, -8))   # over the Keep's tall drum
	sky()
	var islands := group(scn, "Islands")
	var crossings := group(scn, "Crossings")
	for name in ISLANDS:
		island(islands, name)
	shelf(islands.get_node("Shelf"))
	bluff(islands.get_node("Bluff"))
	hearth(islands.get_node("Hearth"))
	terrace(islands.get_node("Terrace"))
	garden(islands.get_node("Garden"))
	citadel(islands.get_node("Citadel"))
	spire(islands.get_node("Spire"))
	for name in ISLANDS:
		island_nodes[name] = islands.get_node(name)
		obstacles[name] = what_stands_on(island_nodes[name])
		if HOLES.has(name):
			obstacles[name].append([0.0, 0.0, float(HOLES[name]) * 0.5 + 1.0])   # (nothing stands, lands or runs up within a metre of the hole)
	for name in PICKUPS:
		for p in PICKUPS[name]:
			pickup(island_nodes[name], p[0], V(p[1], p[2], p[3]))
	for pair in STONES:
		stepping_stones(crossings, pair[0], pair[1])
	hearth_gaps()
	pad_clearance()
	fences("Bluff")
	for name in ISLANDS:
		trees(name)
	for name in ISLANDS:
		boulders(name)
	# Last, so it keeps off everything above: the green on and round each island.
	for name in ISLANDS:
		foliage(name)
		fragments(name)
	var ps := PackedScene.new()
	var err := ps.pack(scn)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
	print("BLOCKOUT: saved %s (%s): %d blocks, %d spawns, %d movers, %d weapon pickups, %d bot crossings" % [OUT, error_string(err),
		scn.find_children("*", "MapBlock", true, false).size(), scn.find_children("*", "MapSpawn", true, false).size(),
		scn.find_children("*", "MapMover", true, false).size(), scn.find_children("*", "MapWeaponSpawn", true, false).size(), links])
	scn.free()
	quit(0 if err == OK else 1)


# -- helpers -------------------------------------------------------------------------
func V(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z)


func centre(name: String) -> Vector3:
	return ISLANDS[name][0]


## Is the point `p` (x and z from the island's centre) on the island's deck?
func on_island(name: String, p: Vector2) -> bool:
	for l in ISLANDS[name][1]:
		var sides: int = l[3]
		var local := (p - Vector2(l[0], l[1])).rotated(deg_to_rad(l[4]))   # undo the lobe's turn
		var half := PI / sides
		var a := fposmod(local.angle(), 2.0 * half) - half
		if local.length() * cos(a) <= l[2] * 0.5 * cos(half):
			return true
	return false


## The same, exactly as the deck is drawn. (on_island takes each slab's flat sides to
## lie where the drawn slab has its corners, so it is up to a metre off at the rim.
## The pads were laid out with it and the layout is settled, so it stays for them;
## everything placed since goes by this.)
func on_deck(name: String, p: Vector2) -> bool:
	for l in ISLANDS[name][1]:
		var sides := LOBE_SIDES
		var local := (p - Vector2(l[0], l[1])).rotated(deg_to_rad(l[4]))
		var half := PI / sides
		var a := fposmod(local.angle() - half, 2.0 * half) - half   # (a corner at angle 0, as MapMesher draws it)
		if local.length() * cos(a) <= l[2] * 0.5 * cos(half):
			return true
	return false


## How far the drawn deck runs from the island's centre in the flat direction `dir`.
func deck_reach(name: String, dir: Vector3) -> float:
	var far := 0.0
	var t := 0.0
	while t < 60.0:
		if on_deck(name, Vector2(dir.x, dir.z) * t):
			far = t
		t += 0.02
	return far


## How far the island's deck runs from its centre in the flat direction `dir`, along a
## line `aside` metres to one side of the centre.
func reach(name: String, dir: Vector3, aside := 0.0) -> float:
	var across := Vector2(-dir.z, dir.x) * aside
	var far := 0.0
	var t := 0.0
	while t < 60.0:
		if on_island(name, Vector2(dir.x, dir.z) * t + across):
			far = t
		t += 0.02
	return far


func group(parent: Node, name: String, at := Transform3D.IDENTITY) -> Node3D:
	var g := Node3D.new()
	g.name = name
	parent.add_child(g, true)
	g.owner = scn
	g.transform = at
	return g


## A group that bobs: a MapMover whose blocks ride `rise` metres up and back every
## PERIOD seconds, starting `phase` of the way through the cycle. `at` is where it is
## half way up; the node itself sits at the bottom of the bob.
func mover(parent: Node, name: String, at: Vector3, rise: float, phase: float) -> Node3D:
	var m: Node3D = mover_script.new()
	m.name = name
	m.set("travel", Vector3(0, rise, 0))
	m.set("period", PERIOD)
	m.set("phase", phase)
	parent.add_child(m, true)
	m.owner = scn
	m.position = at - Vector3(0, rise * 0.5, 0)
	mid_of[m] = at
	return m


## A block in its parent's own frame: `at` is its centre.
func put(parent: Node, name: String, kind: String, size: Vector3, at: Vector3, rot := Basis.IDENTITY, shape := MapBlock.Shape.BOX) -> MapBlock:
	var b: MapBlock = block_script.new()
	b.name = name
	b.shape = shape
	b.size = size
	b.kind = kind
	parent.add_child(b, true)
	b.owner = scn
	b.transform = Transform3D(rot, at)
	return b


## An upright box from `lo` to `hi`, in its parent's frame.
func box(parent: Node, name: String, kind: String, lo: Vector3, hi: Vector3) -> MapBlock:
	return put(parent, name, kind, (hi - lo).abs(), (lo + hi) * 0.5)


## An upright cylinder standing on `base`.
func cyl(parent: Node, name: String, kind: String, base: Vector3, diameter: float, height: float, sides := 16, turn := 0.0) -> MapBlock:
	var b := put(parent, name, kind, Vector3(diameter, height, diameter), base + Vector3(0, height * 0.5, 0), Basis(Vector3.UP, turn), MapBlock.Shape.CYLINDER)
	b.sides = sides
	return b


## A slab whose top runs from `a` to `b` (the middle of each end), `width` across.
func ramp(parent: Node, name: String, kind: String, a: Vector3, b: Vector3, width: float, thick := 0.4) -> MapBlock:
	var along := (b - a).normalized()
	var across := Vector3.UP.cross(along).normalized()
	var up := along.cross(across)
	return put(parent, name, kind, Vector3(width, thick, (b - a).length()), (a + b) * 0.5 - up * thick * 0.5, Basis(across, up, along))


## A spawn point on an island: `at` and `toward` (the way it faces) are in the island's
## frame. It goes inside the island, so it rides the island's bob.
func spawn(island: Node, name: String, at: Vector3, toward: Vector3) -> void:
	var holder := island.get_node_or_null("Spawns")
	if holder == null:
		holder = group(island, "Spawns")
	var m: Marker3D = spawn_script.new()
	m.name = name
	holder.add_child(m, true)
	m.owner = scn
	var away := at - toward
	m.transform = Transform3D(Basis(Vector3.UP, atan2(away.x, away.z)), at)
	clear_of(island, at, 2.5)


## Keeps the foliage `radius` off a spot `at` in a mover's frame.
func clear_of(mover_node: Node3D, at: Vector3, radius: float) -> void:
	var p: Vector3 = mid_of[mover_node] + at
	keep_clear.append([p.x, p.z, radius])


## A bright late morning over a sea of cloud (the sky is a shader:
## game/maps/sky/sky_island_sky.gdshader): a warm, strong sun from the south-east and
## cool blue light in the shade, so every colour stays deep and every shape has a
## bright side and a dark one. Only a breath of haze, for the far islands.
func sky() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(SKY)
	var sun_turn := Basis.from_euler(Vector3(deg_to_rad(-44), deg_to_rad(38), 0))
	mat.set_shader_parameter("sun_dir", sun_turn * Vector3.BACK)   # (toward the sun: the light shines down -z of the Sun node)
	mat.set_shader_parameter("cloud_height", -30.0)   # above the kill height (-36), below the deepest rock (about -26)
	var s := Sky.new()
	s.sky_material = mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = s
	# The shade is lit by one colour, not by the sky: the sky's light comes mostly off
	# the white cloud below, which washed every colour out.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.74, 1.0)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 2.6
	env.background_energy_multiplier = 1.1
	env.ssao_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.78, 1.0)
	env.fog_density = 0.0005
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	scn.add_child(we)
	we.owner = scn
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.94, 0.8)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	scn.add_child(sun)
	sun.owner = scn
	sun.transform = Transform3D(sun_turn, Vector3.ZERO)


# -- islands ---------------------------------------------------------------------------
const LIP := 0.5   ## how much narrower the earth is than the grass on it: the turf overhangs

## island -> the diameter of a round hole right through it, at its centre (the middle
## of its first lobe): you see the cloud through it, and falling in is death. See
## island() for how the ground is built round it.
const HOLES := {"Bluff": 7.6}
const HOLE_BACK := 1.2     ## the other lobes are cut back this far from a hole's edge
const SHAFT := 6.5         ## how far a hole's rock lining hangs below the deck

## An island: a group standing at its centre (so y = 0 inside it is the deck's top),
## holding, for each of its lobes, a slab of turf, a narrower band of earth under it
## (the turf overhangs it) and rock hung underneath: one big cone and a cluster of
## crags round it, some darker, each its own shade.
##
## An island with a hole (HOLES): a slab cannot have a hole cut in it anywhere but its
## own middle (and a ring-shaped block cannot be cut back along a straight line), so
## the turf and earth of the first lobe are rings of flat slabs round the hole, and any
## other lobe that reaches the hole is built as a flat many-sided slab cut back from it
## along a straight line (see slab(): its outline outside the first lobe is unchanged,
## and the cut is hidden inside the first lobe's ring). Under the first lobe, in place
## of one big cone, panels of rock line the hole and a ring of cones hangs round it;
## the other lobes' rock is kept narrow enough to stay out of the hole, as are the crags.
func island(parent: Node, name: String) -> void:
	var g := mover(parent, name, centre(name), BOB[name][0], BOB[name][1])
	var ground := group(g, "Ground")
	var hole: float = float(HOLES.get(name, 0.0)) * 0.5   # its radius (0 = none)
	var i := 0
	for l in ISLANDS[name][1]:
		i += 1
		var d: float = l[2]
		var turn := deg_to_rad(l[4])
		var off := Vector2(l[0], l[1])
		# Each lobe is one selection group: its grass, its earth and the rock under it.
		var lobe := group(ground, "Lobe%d" % i, Transform3D(Basis.IDENTITY, V(l[0], 0, l[1])))
		lobe.set_meta("_edit_group_", true)
		var depth := d * 0.45
		var rock_wide := (d - LIP) * 0.96
		if hole > 0.0 and i == 1:
			# Rings of turf and earth round the hole, rock lining it, cones round that.
			# (Each ring is sixteen four-cornered slabs, and the lining sixteen flat panels
			# of rock. Not tube blocks: when this was built a tube collided as a solid box,
			# a lid on the hole. It collides as its ring now (MapMesher.tube_hulls), but the
			# lobes that overlap the hole are cut back along straight lines, which a tube
			# cannot be, so they need slabs either way.)
			for layer in [["Turf", "grass", d, hole * 2.0, -TURF, 0.0], ["Earth", "earth", d - LIP, hole * 2.0 + LIP, -DECK, -TURF]]:
				var outer_r := float(layer[2]) * 0.5
				var inner_r := float(layer[3]) * 0.5
				for k in LOBE_SIDES:
					var a0 := Vector2.from_angle(TAU * k / LOBE_SIDES - turn)
					var a1 := Vector2.from_angle(TAU * (k + 1) / LOBE_SIDES - turn)
					slab(lobe, layer[0], layer[1], [a0 * outer_r, a1 * outer_r, a1 * inner_r, a0 * inner_r], layer[4], layer[5])
			var face := hole + LIP * 0.5 + 0.15   # (how far the panels' inner faces are from the middle: the earth overhangs them)
			var thick := 1.0
			for k in LOBE_SIDES:
				var a := TAU * (k + 0.5) / LOBE_SIDES - turn
				put(lobe, "Shaft", "rock_dark", Vector3(2.0 * (face + thick) * tan(PI / LOBE_SIDES), SHAFT, thick),
					V(cos(a), 0, sin(a)) * (face + thick * 0.5) + V(0, -DECK - SHAFT * 0.5, 0), Basis(Vector3.UP, -a + PI * 0.5))
			var inner := hole + 1.0
			var outer := rock_wide * 0.5
			for k in 7:
				var a := TAU * k / 7.0 + deco.randf_range(-0.15, 0.15)
				var at := V(cos(a), 0, sin(a)) * (inner + outer) * 0.5 + V(0, -DECK, 0)
				var cone := hung_cone(lobe, "Rock", "rock", at, outer - inner, depth * deco.randf_range(0.65, 1.0), (outer - inner) * 0.1, int(l[3]), deco.randf_range(0.0, TAU))
				cone.solid = true
				cone.tint = grey(deco.randf_range(0.85, 1.0))
		else:
			var reach := off.length() - d * 0.5   # how near this lobe comes to the island's centre
			if hole > 0.0 and reach < hole + 0.3:
				# Cut back from the hole: the same outline, less the part toward the hole.
				var toward := off.normalized()   # (from the hole to this lobe's middle)
				for layer in [["Turf", "grass", d, -TURF, 0.0], ["Earth", "earth", d - LIP, -DECK, -TURF]]:
					var points := []
					for k in LOBE_SIDES:
						points.append(Vector2.from_angle(TAU * k / LOBE_SIDES - turn) * float(layer[2]) * 0.5)
					slab(lobe, layer[0], layer[1], cut_off(points, toward, hole + HOLE_BACK - off.length()), layer[3], layer[4])
			else:
				cyl(lobe, "Turf", "grass", V(0, -TURF, 0), d, TURF, LOBE_SIDES, turn)
				cyl(lobe, "Earth", "earth", V(0, -DECK, 0), d - LIP, DECK - TURF, LOBE_SIDES, turn)
			# The rock: a cone hung point down (turned over about x), a little narrower than its deck.
			if hole > 0.0:
				rock_wide = minf(rock_wide, 2.0 * (off.length() - hole - 1.6))
			var rock := hung_cone(lobe, "Rock", "rock", V(0, -DECK, 0), rock_wide, depth, d * 0.12, l[3], turn)
			rock.solid = true
		# Crags: smaller cones hung round it, so the underside is jagged, not one smooth point.
		for k in deco.randi_range(5, 7):
			var a := deco.randf_range(0.0, TAU)
			var w := deco.randf_range(0.18, 0.36) * d
			var out := minf(deco.randf_range(0.12, 0.34) * d, 0.45 * d - w * 0.5)   # (wholly under the main rock, so its flat top never shows)
			var at := V(cos(a) * out, -DECK - deco.randf_range(0.3, 1.2), sin(a) * out)
			var long := minf(w * deco.randf_range(1.0, 1.9), d * 0.44)
			var shade := grey(deco.randf_range(0.72, 1.0))
			var crag_sides := deco.randi_range(5, 7)
			var crag_turn := deco.randf_range(0.0, TAU)
			if hole > 0.0 and (off + Vector2(at.x, at.z)).length() < hole + 1.6 + w * 0.5:
				continue   # (it would hang in the hole)
			var crag := hung_cone(lobe, "Crag", "rock_dark" if k % 2 == 0 else "rock", at, w, long, w * 0.08, crag_sides, crag_turn)
			crag.tint = shade


## A many-sided outline (`points`, in order round it) less everything on the near side
## of a straight line: what is left has `along` . p >= `at`.
func cut_off(points: Array, along: Vector2, at: float) -> Array:
	var out := []
	for k in points.size():
		var a: Vector2 = points[k]
		var b: Vector2 = points[(k + 1) % points.size()]
		var da := along.dot(a) - at
		var db := along.dot(b) - at
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out


## A flat slab in the shape of `points` (x and z in the parent's frame, in order round
## it, no dents) from `y0` up to `y1`. There is no block of that shape, so it is made
## of wedges lying on their sides: a wedge is a right-angled triangle drawn out, and any
## triangle is two of those side by side.
func slab(parent: Node, name: String, kind: String, points: Array, y0: float, y1: float) -> void:
	for k in range(1, points.size() - 1):
		var tri := [points[0], points[k], points[k + 1]]
		# The longest side, and the foot of the height dropped on it from the third corner.
		var longest := 0
		for s in 3:
			if (tri[(s + 1) % 3] - tri[s]).length() > (tri[(longest + 1) % 3] - tri[longest]).length():
				longest = s
		var p: Vector2 = tri[longest]
		var q: Vector2 = tri[(longest + 1) % 3]
		var r: Vector2 = tri[(longest + 2) % 3]
		var foot := p + (q - p) * ((r - p).dot(q - p) / (q - p).length_squared())
		for end in [p, q]:
			# A right-angled triangle: the right angle at `foot`, legs to `end` and to `r`.
			var u: Vector2 = end - foot
			var v := r - foot
			if u.length() < 0.01 or v.length() < 0.01:
				continue
			# A wedge's legs run along its own y and z, and z is y turned a quarter turn one way only.
			var e1 := u.normalized()
			var leg1 := u.length()
			var leg2 := v.length()
			if Vector2(e1.y, -e1.x).dot(v) < 0.0:
				e1 = v.normalized()
				leg1 = v.length()
				leg2 = u.length()
			var e2 := Vector2(e1.y, -e1.x)
			var mid := foot + e1 * leg1 * 0.5 + e2 * leg2 * 0.5
			put(parent, name, kind, Vector3(y1 - y0, leg1, leg2), V(mid.x, (y0 + y1) * 0.5, mid.y),
				Basis(Vector3.UP, Vector3(e1.x, 0, e1.y), Vector3(e2.x, 0, e2.y)), MapBlock.Shape.WEDGE)


## A tint that darkens a block: 1 = the kind's own colour.
func grey(v: float) -> Color:
	return Color(v, v, v)


## A cone of rock hung point down from `top` (the middle of its wide end).
func hung_cone(parent: Node, name: String, kind: String, top: Vector3, width: float, depth: float, tip: float, sides: int, turn: float) -> MapBlock:
	var b := put(parent, name, kind, Vector3(width, depth, width), top - V(0, depth * 0.5, 0),
		Basis(Vector3.UP, turn) * Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)), MapBlock.Shape.CONE)
	b.sides = sides
	b.top = tip
	b.solid = false
	return b


## A ball of leaves (or blossom) `d` across with its middle at `at`: two domes, one
## turned over under the other. `squash` under 1 flattens it.
func ball(parent: Node, name: String, kind: String, at: Vector3, d: float, squash := 1.0, sides := 8) -> void:
	var h := d * 0.5 * squash
	var turn := Basis(Vector3.UP, deco.randf_range(0.0, TAU))
	var up := put(parent, name, kind, Vector3(d, h, d), at + V(0, h * 0.5, 0), turn, MapBlock.Shape.DOME)
	var down := put(parent, name, kind, Vector3(d, h, d), at - V(0, h * 0.5, 0), turn * Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)), MapBlock.Shape.DOME)
	var shade := grey(deco.randf_range(0.8, 1.0))
	for b in [up, down]:
		b.sides = sides
		b.solid = false
		b.tint = shade


# -- the Shelf's garden ------------------------------------------------------------------
## The Shelf: a formal garden. Clipped hedges round a square GARDEN * 2 m across, a
## way in through the middle of each side between stone gate posts, flagged paths
## crossing to a fountain in the middle and a clipped cone at each corner.
const GARDEN := 6.0


func shelf(g: Node3D) -> void:
	var garden := group(g, "Garden")
	paved.append([garden, Rect2(-GARDEN - 1.0, -GARDEN - 1.0, GARDEN * 2.0 + 2.0, GARDEN * 2.0 + 2.0)])   # (no trees or meadow in it)
	var hedges := group(garden, "Hedges")
	var t := 0.9   # thick
	var h := 1.0   # high
	for s in [-1.0, 1.0]:
		# North and south sides run the whole width, corners and all; east and west fit between.
		hedge(hedges, V(-GARDEN - t * 0.5, 0, s * GARDEN - t * 0.5), V(-1.5, h, s * GARDEN + t * 0.5))
		hedge(hedges, V(1.5, 0, s * GARDEN - t * 0.5), V(GARDEN + t * 0.5, h, s * GARDEN + t * 0.5))
		hedge(hedges, V(s * GARDEN - t * 0.5, 0, -GARDEN + t * 0.5), V(s * GARDEN + t * 0.5, h, -1.5))
		hedge(hedges, V(s * GARDEN - t * 0.5, 0, 1.5), V(s * GARDEN + t * 0.5, h, GARDEN - t * 0.5))
	var cones := group(garden, "Topiary")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var cone := put(cones, "Cone", "leaf", Vector3(1.5, 2.3, 1.5), V(sx * GARDEN, 0.7 + 1.15, sz * GARDEN), Basis(Vector3.UP, 0.4), MapBlock.Shape.CONE)
			cone.sides = 8
			cone.top = 0.0
			cone.tint = grey(0.86)
	var posts := group(garden, "GatePosts")
	for s in [-1.0, 1.0]:
		for e in [-1.0, 1.0]:
			gate_post(posts, V(e * 1.75, 0, s * GARDEN), false)
			gate_post(posts, V(s * GARDEN, 0, e * 1.75), true)
	paving(garden, "PathEastWest", Vector2(-GARDEN - 0.8, -1.2), Vector2(GARDEN + 0.8, 1.2))
	paving(garden, "PathNorthSouth", Vector2(-1.2, -GARDEN - 0.8), Vector2(1.2, GARDEN + 0.8))
	var round := cyl(garden, "PathRound", "paving", V(0, 0, 0), 8.4, 0.03, 16)
	round.solid = false
	fountain(garden)
	for at in [V(-10, 0, -3), V(3.5, 0, -3.5), V(4, 0, 14), V(13, 0, -3)]:
		spawn(g, "Shelf", at, Vector3.ZERO)


## A clipped hedge from `lo` to `hi`: the hedge itself and a rounded top, a shade lighter.
func hedge(parent: Node, lo: Vector3, hi: Vector3) -> void:
	var mid := (lo + hi) * 0.5
	var size := (hi - lo).abs()
	var g := group(parent, "Hedge", Transform3D(Basis.IDENTITY, V(mid.x, lo.y, mid.z)))
	g.set_meta("_edit_group_", true)
	var body := box(g, "Leaves", "leaf", V(-size.x * 0.5, 0, -size.z * 0.5), V(size.x * 0.5, size.y, size.z * 0.5))
	body.tint = grey(0.8)
	var top := put(g, "Top", "leaf", Vector3(size.x + 0.14, 0.4, size.z + 0.14), V(0, size.y - 0.04, 0), Basis.IDENTITY, MapBlock.Shape.BEVEL)
	top.bevel = 0.17
	top.solid = false


## A stone post at the end of a hedge, with a cap and a stone ball on it. `turned`: the
## hedge it ends runs north-south.
func gate_post(parent: Node, at: Vector3, turned: bool) -> void:
	var g := group(parent, "GatePost", Transform3D(Basis(Vector3.UP, PI * 0.5 if turned else 0.0), at))
	g.set_meta("_edit_group_", true)
	box(g, "Post", "trim", V(-0.35, 0, -0.56), V(0.35, 1.5, 0.56))
	var cap := box(g, "Cap", "stone_dark", V(-0.43, 1.5, -0.64), V(0.43, 1.64, 0.64))
	cap.solid = false
	ball(g, "Ball", "trim", V(0, 1.64 + 0.27, 0), 0.6, 1.0, 8)


## A fountain of two bowls: a broad stone step, a basin of water waist high, and out
## of it a pedestal carrying a wide bowl and, on a slimmer stem, a small one, each
## spilling a ring of water into the one below, with a jet on top.
func fountain(parent: Node) -> void:
	var f := group(parent, "Fountain")
	f.set_meta("_edit_group_", true)
	cyl(f, "Step", "trim", V(0, 0, 0), 6.0, 0.16, 16)
	tube(f, "Basin", "stone", V(0, 0.16, 0), 5.0, 4.2, 0.6, true)
	tube(f, "Rim", "trim", V(0, 0.76, 0), 5.24, 3.96, 0.14, false)
	var pool := cyl(f, "Pool", "water", V(0, 0.16, 0), 4.22, 0.5, 16)   # (its side just inside the basin's wall)
	pool.solid = false
	cyl(f, "Pedestal", "stone_dark", V(0, 0.16, 0), 0.9, 1.6, 10)
	var collar := cyl(f, "Collar", "trim", V(0, 0.66, 0), 1.3, 0.2, 10)
	collar.solid = false
	var bowl := hung_cone(f, "Bowl", "trim", V(0, 2.3, 0), 2.7, 0.55, 0.9, 16, 0.0)
	bowl.solid = true
	var water := cyl(f, "BowlWater", "water", V(0, 2.3, 0), 2.3, 0.02, 16)
	water.solid = false
	for k in 8:
		var a := TAU * k / 8.0
		var stream := cyl(f, "Spill", "water", V(cos(a) * 1.33, 0.64, sin(a) * 1.33), 0.11, 1.69, 5)   # (water running off the lip of the bowl)
		stream.solid = false
	cyl(f, "Stem", "stone_dark", V(0, 2.3, 0), 0.46, 0.95, 8)
	var small := hung_cone(f, "SmallBowl", "trim", V(0, 3.4, 0), 1.4, 0.4, 0.46, 12, 0.0)
	small.solid = true
	var small_water := cyl(f, "SmallBowlWater", "water", V(0, 3.4, 0), 1.1, 0.02, 12)
	small_water.solid = false
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var stream := cyl(f, "SmallSpill", "water", V(cos(a) * 0.68, 2.31, sin(a) * 0.68), 0.09, 1.12, 5)
		stream.solid = false
	var jet := put(f, "Jet", "water", Vector3(0.3, 0.8, 0.3), V(0, 3.4 + 0.4, 0), Basis.IDENTITY, MapBlock.Shape.CONE)
	jet.sides = 8
	jet.top = 0.0
	jet.solid = false


## A round tube standing on `base`, `outer` and `inner` across, `height` high.
func tube(parent: Node, name: String, kind: String, base: Vector3, outer: float, inner: float, height: float, solid: bool) -> MapBlock:
	var b := put(parent, name, kind, Vector3(outer, height, outer), base + V(0, height * 0.5, 0), Basis.IDENTITY, MapBlock.Shape.TUBE)
	b.sides = 16
	b.inner = inner
	b.solid = solid
	return b


# -- the Bluff's hole and crane -----------------------------------------------------------
## The Bluff: a big round hole right through the middle of the island (see HOLES and
## island()), a timber kerb round its edge on a ring of worn earth, and beside it a
## tall wooden crane whose jib reaches out over the hole, a rope from its winch running
## up over the jib's end and down through the hole, an iron hook on the end of it
## hanging below the island. Crates and barrels stand by the winch. A low dry-stone
## fence runs round the island's edge (see fences()).
const CRANE_AT := Vector3(7.6, 0, 0)   ## the foot of the mast of the crane (the hole is at 0, 0)
const APRON := 2.2                     ## how wide the ring of worn earth round the hole is


func bluff(g: Node3D) -> void:
	var hole: float = HOLES["Bluff"]
	var pit := group(g, "Hole")
	pit.set_meta("_edit_group_", true)
	var worn := tube(pit, "WornGround", "earth", V(0, 0, 0), hole + APRON * 2.0, hole + 0.5, 0.026, false)   # (a hair above any patch of meadow, which keeps off it anyway)
	worn.tint = grey(0.8)
	var kerb := tube(pit, "Kerb", "wood", V(0, 0, 0), hole + 1.1, hole + 0.04, 0.14, false)
	kerb.tint = grey(0.9)
	for ring in [worn, kerb]:
		ring.transform.basis = Basis(Vector3.UP, deg_to_rad(ISLANDS["Bluff"][1][0][4]))   # (turned as the hole is)
	crane(g, CRANE_AT, Vector3.ZERO, 3.2)
	var things := group(g, "Stores")
	crate(things, V(10.2, 0, 3.4), 1.1, 0.2)
	crate(things, V(8.9, 0, 3.9), 1.0, -0.15)
	crate(things, V(10.1, 1.1, 3.5), 0.8, 0.6)
	barrel(things, V(10.6, 0, -2.6))
	barrel(things, V(9.5, 0, -3.1))
	for at in [V(-9, 0, -3), V(6, 0, -5), V(3, 0, 11), V(-10, 0, 4)]:
		spawn(g, "Bluff", at, Vector3.ZERO)


## A beam (or a rope) `thick` square from `a` to `b`.
func beam(parent: Node, name: String, kind: String, a: Vector3, b: Vector3, thick: float, solid := true) -> MapBlock:
	var along := (b - a).normalized()
	var side := Vector3.UP.cross(along)
	side = Vector3.RIGHT if side.length() < 0.01 else side.normalized()
	var block := put(parent, name, kind, Vector3(thick, thick, (b - a).length()), (a + b) * 0.5, Basis(side, along.cross(side), along))
	block.solid = solid
	return block


## A wooden crane, its mast standing on `at`, its jib reaching out over `over` (both in
## the parent's frame), the hook hanging `drop` metres below the ground. A mast on
## crossed sills with braces to it; the jib, held up by two stay ropes from the top of
## the mast; behind the mast a winch (a drum between two posts, a crank at each end);
## the hoist rope from the drum up to a pulley on the jib's end, and down to the hook.
func crane(parent: Node, at: Vector3, over: Vector3, drop: float) -> void:
	var flat := Vector3(over.x - at.x, 0, over.z - at.z)
	var reach := flat.length()
	# In the crane's own frame z runs from the mast toward the hole and x across.
	var g := group(parent, "Crane", Transform3D(Basis(Vector3.UP, atan2(flat.x, flat.z)), at))
	var frame := group(g, "Frame")
	frame.set_meta("_edit_group_", true)
	box(frame, "Sill", "wood_dark", V(-1.9, 0, -0.22), V(1.9, 0.3, 0.22))
	box(frame, "Sill", "wood_dark", V(-0.22, 0, -3.4), V(0.22, 0.3, 1.3))
	var mast_top := 10.0
	box(frame, "Mast", "wood", V(-0.26, 0, -0.26), V(0.26, mast_top, 0.26))
	var head := box(frame, "MastCap", "wood_dark", V(-0.34, mast_top, -0.34), V(0.34, mast_top + 0.16, 0.34))
	head.solid = false
	for s in [-1.0, 1.0]:
		beam(frame, "Brace", "wood_dark", V(s * 1.75, 0.3, 0), V(s * 0.1, 3.4, 0), 0.22)
	beam(frame, "BackBrace", "wood_dark", V(0, 0.3, -3.2), V(0, 5.2, -0.1), 0.26)
	var tip := V(0, 8.8, reach)
	beam(frame, "Jib", "wood", V(0, 4.6, 0.1), tip, 0.4)
	beam(frame, "JibStrut", "wood_dark", V(0, 2.4, 0.2), V(0, 4.6 + (tip.y - 4.6) * 0.42, reach * 0.42), 0.24)
	for s in [-1.0, 1.0]:
		beam(frame, "Stay", "rope", V(s * 0.14, mast_top - 0.2, 0.2), tip + V(s * 0.14, 0.15, -0.3), 0.08, false)
	# The winch, behind the mast.
	var winch := group(g, "Winch")
	winch.set_meta("_edit_group_", true)
	var across := Basis(Vector3.BACK, PI * 0.5)   # (a cylinder lying along x)
	for s in [-1.0, 1.0]:
		box(winch, "Post", "wood", V(s * 0.95 - 0.14, 0, -1.84), V(s * 0.95 + 0.14, 1.8, -1.56))
		var arm := box(winch, "Crank", "wood_dark", V(s * 1.24 - 0.06, 0.85, -1.76), V(s * 1.24 + 0.06, 1.4, -1.64))
		arm.solid = false
		var grip := put(winch, "Grip", "wood", Vector3(0.1, 0.45, 0.1), V(s * 1.5, 0.9, -1.7), across, MapBlock.Shape.CYLINDER)
		grip.solid = false
	var drum := put(winch, "Drum", "wood_dark", Vector3(0.6, 2.52, 0.6), V(0, 1.3, -1.7), across, MapBlock.Shape.CYLINDER)
	drum.sides = 10
	var coil := put(winch, "Coil", "rope", Vector3(0.74, 0.7, 0.74), V(0.42, 1.3, -1.7), across, MapBlock.Shape.CYLINDER)
	coil.sides = 10
	coil.solid = false
	# The hoist rope: up beside the mast and the jib to the pulley, then straight down.
	var hoist := group(g, "Hoist")
	hoist.set_meta("_edit_group_", true)
	var side := 0.42
	var pulley_at := tip + V(side, -0.35, 0)
	var pulley := put(hoist, "Pulley", "wood_dark", Vector3(0.6, 0.2, 0.6), pulley_at, across, MapBlock.Shape.CYLINDER)
	pulley.sides = 10
	pulley.solid = false
	var axle := put(hoist, "PulleyPin", "iron", Vector3(0.12, 0.7, 0.12), tip + V(side * 0.5, -0.35, 0), across, MapBlock.Shape.CYLINDER)
	axle.sides = 6
	axle.solid = false
	beam(hoist, "Rope", "rope", V(side, 1.62, -1.7), pulley_at + V(0, 0.28, 0), 0.09, false)
	var hang := tip.y - 0.35 + drop   # how long the hanging rope is
	var rope := cyl(hoist, "Rope", "rope", pulley_at + V(0, -hang, 0.3), 0.1, hang, 6)
	rope.solid = false
	# The hook: an iron weight on the rope, and under it a shank, a bend and a point.
	var foot := pulley_at + V(0, -hang, 0.3)
	var weight := cyl(hoist, "Weight", "iron", foot + V(0, -0.5, 0), 0.5, 0.56, 8)
	weight.solid = false
	for part in [[V(0, -1.05, 0), Vector3(0.14, 1.1, 0.14)], [V(0, -1.67, 0.3), Vector3(0.14, 0.14, 0.74)], [V(0, -1.37, 0.6), Vector3(0.14, 0.46, 0.14)]]:
		var iron := put(hoist, "Hook", "iron", part[1], foot + part[0])
		iron.solid = false


## A wooden crate `size` across standing on `base`, turned `turn` radians: pale planks
## with a dark frame round its top and its foot.
func crate(parent: Node, base: Vector3, size: float, turn: float) -> void:
	var g := group(parent, "Crate", Transform3D(Basis(Vector3.UP, turn), base))
	g.set_meta("_edit_group_", true)
	box(g, "Box", "wood", V(-size * 0.5, 0, -size * 0.5), V(size * 0.5, size, size * 0.5))
	for y in [0.03, size - 0.15]:
		var band := box(g, "Band", "wood_dark", V(-size * 0.5 - 0.03, y, -size * 0.5 - 0.03), V(size * 0.5 + 0.03, y + 0.12, size * 0.5 + 0.03))
		band.solid = false


## A barrel standing on `base`: staves with two dark hoops.
func barrel(parent: Node, base: Vector3) -> void:
	var g := group(parent, "Barrel", Transform3D(Basis.IDENTITY, base))
	g.set_meta("_edit_group_", true)
	cyl(g, "Staves", "wood", V(0, 0, 0), 0.9, 1.1, 10)
	for y in [0.18, 0.8]:
		var hoop := cyl(g, "Hoop", "wood_dark", V(0, y, 0), 0.98, 0.1, 10)
		hoop.solid = false


## A low dry-stone fence round an island's edge, FENCE_IN metres in from it: short runs
## (waist high, a capped post at each end) with a gap after each, and none near a spawn
## point, a pickup or anywhere bots set off or land, so it never shuts a way onto the
## island.
const FENCE_IN := 1.7
const FENCE_RUN := 3.6     ## each run's length
const FENCE_GAP := 1.6     ## the gap after it


func fences(name: String) -> void:
	var island: Node3D = island_nodes[name]
	var c := centre(name)
	var g := group(island, "Fence")
	var a := 0.0
	var made := 0
	while a < TAU:
		var r0 := deck_reach(name, Vector3(cos(a), 0, sin(a))) - FENCE_IN
		var step := FENCE_RUN / maxf(r0, 4.0)
		var a1 := a + step
		var p0 := Vector2(cos(a), sin(a)) * r0
		var p1 := Vector2(cos(a1), sin(a1)) * (deck_reach(name, Vector3(cos(a1), 0, sin(a1))) - FENCE_IN)
		var ok := p0.distance_to(p1) < FENCE_RUN * 1.4
		for k in 5:
			var p := p0.lerp(p1, k / 4.0)
			if not ok or not clear_spot(name, p, 0.6):
				ok = false
				break
			var m := Vector2(c.x + p.x, c.z + p.y)
			for kc in keep_clear:
				if m.distance_to(Vector2(kc[0], kc[1])) < float(kc[2]) + 1.0:
					ok = false
					break
		if ok:
			var dir := (p1 - p0).normalized()
			var mid := (p0 + p1) * 0.5
			var length := p0.distance_to(p1)
			var run := group(g, "Run", Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), V(mid.x, 0, mid.y)))
			run.set_meta("_edit_group_", true)
			box(run, "Stones", "drystone", V(-length * 0.5, 0, -0.25), V(length * 0.5, 0.7, 0.25))
			var cap := put(run, "Cap", "stone_dark", Vector3(length - 0.5, 0.18, 0.62), V(0, 0.7 + 0.07, 0), Basis.IDENTITY, MapBlock.Shape.BEVEL)
			cap.bevel = 0.07
			cap.solid = false
			for s in [-0.5, 0.5]:
				box(run, "Post", "stone", V(s * length - 0.36, 0, -0.36), V(s * length + 0.36, 1.0, 0.36))
				var top := put(run, "PostCap", "trim", Vector3(1.16, 0.34, 1.16), V(s * length, 1.0 + 0.17, 0), Basis(Vector3.UP, PI * 0.25), MapBlock.Shape.CONE)
				top.sides = 4
				top.top = 0.0
				top.solid = false
			obstacles[name].append([mid.x, mid.y, length * 0.5 + 0.4])
			made += 1
		a = a1 + FENCE_GAP / maxf(r0, 4.0)
	print("  %s: %d runs of fence" % [name, made])


# -- the Garden's stones and the Spire ---------------------------------------------------
## The Garden: a ring of standing stones (rough, tapering, none quite upright), open in
## the middle, and a block of fallen masonry off to one side.
func garden(g: Node3D) -> void:
	var ring := group(g, "StandingStones")
	var heights := [4.2, 3.0, 4.2, 1.4, 4.2, 2.2, 3.6]
	for i in heights.size():
		var a := TAU * i / heights.size() + 0.3
		var h: float = heights[i]
		var stone := group(ring, "Stone", Transform3D(Basis(Vector3.UP, deco.randf_range(0.0, TAU)), V(cos(a) * 7.0, 0, sin(a) * 7.0)))
		stone.set_meta("_edit_group_", true)
		var block := put(stone, "Block", "menhir", Vector3(1.6, h + 0.3, 1.6), V(0, (h + 0.3) * 0.5 - 0.3, 0), Basis(Vector3.RIGHT, deco.randf_range(-0.07, 0.07)), MapBlock.Shape.CONE)
		block.sides = 5
		block.top = 0.95
		block.tint = grey(deco.randf_range(0.8, 1.0))
		var moss := put(stone, "Moss", "leaf", Vector3(0.9, 0.16, 0.9), V(0.08, h - 0.02, 0.05), Basis(Vector3.UP, 0.5), MapBlock.Shape.BEVEL)
		moss.bevel = 0.07
		moss.solid = false
		moss.tint = grey(0.75)
	var cover := group(g, "Cover")
	masonry(cover, "Block", V(-12, 0, 6), V(-10, 1.2, 8.5))
	for at in [V(-2, 0, -10.5), V(10, 0, 4), V(-11, 0, 3)]:
		spawn(g, "Garden", at, Vector3.ZERO)


## The Spire: small, with two blocks of fallen masonry.
func spire(g: Node3D) -> void:
	masonry(g, "Cover", V(2, 0, 3), V(5, 1.2, 4))
	masonry(g, "Cover", V(7, 0, 5), V(8.2, 1.2, 7.5))
	spawn(g, "Spire", V(-4, 0, 4.5), Vector3.ZERO)
	spawn(g, "Spire", V(8, 0, 2), Vector3.ZERO)


# -- stonework -------------------------------------------------------------------------
## A block of fallen masonry from `lo` to `hi` (cover): weathered stone with a cushion
## of moss on part of its top and a chip of stone lying by it.
func masonry(parent: Node, name: String, lo: Vector3, hi: Vector3) -> Node3D:
	var mid := (lo + hi) * 0.5
	var size := (hi - lo).abs()
	var g := group(parent, name, Transform3D(Basis.IDENTITY, V(mid.x, lo.y, mid.z)))
	g.set_meta("_edit_group_", true)
	box(g, "Stone", "stone", V(-size.x * 0.5, 0, -size.z * 0.5), V(size.x * 0.5, size.y, size.z * 0.5))
	var mx := size.x * deco.randf_range(0.4, 0.75)
	var mz := size.z * deco.randf_range(0.4, 0.75)
	var ox := (size.x - mx) * 0.5 * (1.0 if deco.randf() < 0.5 else -1.0)
	var oz := (size.z - mz) * 0.5 * (1.0 if deco.randf() < 0.5 else -1.0)
	var moss := put(g, "Moss", "leaf", Vector3(mx + 0.1, 0.2, mz + 0.1), V(ox, size.y + 0.04, oz), Basis.IDENTITY, MapBlock.Shape.BEVEL)
	moss.bevel = 0.08
	moss.solid = false
	moss.tint = grey(0.78)
	var chip := put(g, "Chip", "stone", Vector3(0.6, 0.4, 0.5), V(size.x * 0.5 + 0.45, 0.14, deco.randf_range(-0.3, 0.3) * size.z), Basis(Vector3.UP, deco.randf_range(0.0, TAU)), MapBlock.Shape.BEVEL)
	chip.bevel = 0.1
	chip.solid = false
	return g


## One piece of a stone wall: a group holding the block itself, a darker course at its
## foot (on pieces 2 m tall or more), a dark arrow slit through the tall ones now and
## then, something along its top (`cap`) and, now and then (`ivy_chance`), ivy climbing
## one face. `size`, `at` (its middle) and `rot` as for put(): the block's x runs along
## the wall, z through it. `cap`: "broken" (loose stones standing on a broken top, moss
## on a low one), "coping" (a dressed course, on a wall that was built that high),
## "moss" (a cushion of moss) or "" (bare).
func wall_piece(parent: Node, kind: String, size: Vector3, at: Vector3, rot: Basis, ivy_chance := 0.3, cap := "broken") -> Node3D:
	var g := group(parent, "Wall", Transform3D(rot, at))
	g.set_meta("_edit_group_", true)
	put(g, "Stone", kind, size, Vector3.ZERO)
	var top := size.y * 0.5
	if size.y >= 2.0:
		var foot := put(g, "Footing", "stone_dark", Vector3(size.x + 0.16, 0.55, size.z + 0.16), V(0, -top + 0.275, 0))
		foot.solid = false
	var slitted := size.y >= 4.8 and size.x >= 1.5 and deco.randf() < 0.5
	if slitted:
		var slit := put(g, "Slit", "shadow", Vector3(0.18, 1.1, size.z + 0.03), V(0, top - 1.9, 0))
		slit.solid = false
	if cap == "broken" and size.y <= 1.4:
		cap = "moss" if deco.randf() < 0.6 else ""
	match cap:
		"coping":
			var c := put(g, "Coping", "trim", Vector3(size.x + 0.04, 0.16, size.z + 0.16), V(0, top + 0.08, 0))
			c.solid = false
		"moss":
			var mx := size.x * deco.randf_range(0.45, 0.8)
			var moss := put(g, "Moss", "leaf", Vector3(mx, 0.2, size.z - 0.12), V((size.x - mx) * 0.5 * deco.randf_range(-1.0, 1.0), top + 0.04, 0), Basis.IDENTITY, MapBlock.Shape.BEVEL)
			moss.bevel = 0.08
			moss.solid = false
			moss.tint = grey(0.78)
		"broken":
			# Loose stones left standing along the break, of odd widths and heights.
			var x := -size.x * 0.5
			while x < size.x * 0.5 - 0.3:
				var w := minf(deco.randf_range(0.5, 1.1), size.x * 0.5 - x)
				if deco.randf() < 0.6:
					var th := snappedf(deco.randf_range(0.2, 0.6), 0.05)
					var tooth := put(g, "Stones", kind, Vector3(w, th, size.z), V(x + w * 0.5, top + th * 0.5, 0))
					tooth.solid = false
				x += w
	if size.y > 1.0 and not slitted and deco.randf() < ivy_chance:
		ivy(g, size, 1.0 if deco.randf() < 0.5 else -1.0)
	return g


## Ivy climbing the `face` side (1 or -1: +z or -z) of a wall `size` big whose middle is
## the middle of `g`: small pads of dark leaves from the foot up, three abreast low
## down and one at the top, wandering to one side as it climbs. The shade of green is
## the same all over one plant (`shade`), so pads that share a plane never differ; and
## every pad's top and foot is 1.7 cm off the 5 cm steps that wall tops and loose
## stones keep to, so a pad is never level with stonework beside it.
func ivy(g: Node3D, size: Vector3, face: float, shade := -1.0) -> void:
	if shade < 0.0:
		shade = deco.randf_range(0.3, 0.6)
	var foot := -size.y * 0.5
	var limit := size.y - 0.033   # (as high as a pad may reach above the foot)
	var reach := size.y * deco.randf_range(0.55, 0.95)
	var x := size.x * deco.randf_range(-0.3, 0.3)
	var y := 0.0   # (above the foot)
	var k := deco.randi_range(0, 4)
	while y < reach:
		var climb := y / size.y
		for j in (3 if climb < 0.3 else (2 if climb < 0.65 else 1)):
			var w := minf(deco.randf_range(0.4, 0.7), size.x - 0.06)
			var low := snappedf(y + deco.randf_range(0.0, 0.2), 0.05) + 0.017
			var h := minf(snappedf(deco.randf_range(0.45, 0.75), 0.05), limit - low)
			if h < 0.2:
				break
			var px := clampf(x + deco.randf_range(-0.6, 0.6) * (1.0 - climb * 0.5), -size.x * 0.5 + w * 0.5 + 0.03, size.x * 0.5 - w * 0.5 - 0.03)
			var thick := 0.13 + (k % 5) * 0.016
			var pad := put(g, "Ivy", "leaf", Vector3(w, h, thick), V(px, foot + low + h * 0.5, face * (size.z * 0.5 + thick * 0.5 - 0.02)))
			pad.solid = false
			pad.tint = grey(shade)
			k += 1
		x = clampf(x + deco.randf_range(-0.3, 0.3), -size.x * 0.4, size.x * 0.4)
		y += deco.randf_range(0.35, 0.55)


# -- castle ruins ----------------------------------------------------------------------
## A broken wall from `a` to `b` (x and z in the parent's frame), cut into as many
## equal lengths as `heights` has numbers; each stands that high (0 = a breach).
func broken_wall(parent: Node, a: Vector2, b: Vector2, heights: Array, thick := THICK) -> void:
	var n := heights.size()
	var dir := (b - a).normalized()
	var rot := Basis(Vector3.UP, atan2(-dir.y, dir.x))   # the block's x along the wall
	var piece := (b - a).length() / n
	for i in n:
		var h: float = heights[i]
		if h <= 0.0:
			continue
		var mid := a.lerp(b, (i + 0.5) / n)
		wall_piece(parent, "stone", Vector3(piece, h, thick), V(mid.x, h * 0.5, mid.y), rot)


## Fallen stones: [x, z, length, height, depth, turn in degrees] each, a smaller one
## lying by each.
func rubble(parent: Node, stones: Array) -> void:
	var g := group(parent, "Rubble")
	for s in stones:
		var stone := put(g, "Stone", "stone", Vector3(s[2], s[3], s[4]), V(s[0], s[3] * 0.5, s[1]), Basis(Vector3.UP, deg_to_rad(s[5])))
		stone.shape = MapBlock.Shape.BEVEL
		stone.bevel = 0.18
		stone.tint = grey(deco.randf_range(0.82, 0.95))
		var a := deco.randf_range(0.0, TAU)
		var far := maxf(float(s[2]), float(s[4])) * 0.5 + 0.55
		var chip := put(g, "Chip", "stone", Vector3(0.65, 0.42, 0.5), V(s[0] + cos(a) * far, 0.15, s[1] + sin(a) * far), Basis(Vector3.UP, deco.randf_range(0.0, TAU)), MapBlock.Shape.BEVEL)
		chip.bevel = 0.1
		chip.solid = false
		chip.tint = grey(deco.randf_range(0.82, 0.95))


## A round tower (a drum) standing on `base`: a darker plinth at its foot, arrow slits
## half way up, and round its top either a ring of capped merlons on a corbelled course
## (a whole one) or grass, where a broken stump has grown over.
func drum(parent: Node, name: String, base: Vector3, diameter: float, height: float, sides: int, merlons: bool) -> Node3D:
	var g := group(parent, name, Transform3D(Basis.IDENTITY, base))
	g.set_meta("_edit_group_", true)
	cyl(g, "Stone", "stone", V(0, 0, 0), diameter, height, sides)
	var plinth := cyl(g, "Plinth", "stone_dark", V(0, 0, 0), diameter + 0.36, 0.9, sides)
	plinth.solid = false
	var face := diameter * 0.5 * cos(PI / sides)   # (how far a flat side is from the middle)
	if height >= 5.0:
		for k in range(1, sides, 3):
			var a := TAU * (k + 0.5) / sides
			var slit := put(g, "Slit", "shadow", Vector3(0.2, 1.3, 0.06), V(cos(a) * face, height * 0.55, sin(a) * face), Basis(Vector3.UP, -a + PI * 0.5))
			slit.solid = false
	if merlons:
		var corbel := cyl(g, "Corbel", "stone_dark", V(0, height - 0.98, 0), diameter + 0.3, 0.3, sides)
		corbel.solid = false
		var course := cyl(g, "Course", "trim", V(0, height - 0.7, 0), diameter + 0.6, 0.34, sides)   # (its top below the drum's, not in the same plane)
		course.solid = false
		for k in sides:
			if k % 2 == 1:
				continue
			var a := TAU * (k + 0.5) / sides
			var r := face - 0.25
			var turn := Basis(Vector3.UP, -a + PI * 0.5)
			put(g, "Merlon", "stone", Vector3(0.9, 0.9, 0.5), V(cos(a) * r, height + 0.45, sin(a) * r), turn)
			var cap := put(g, "MerlonCap", "trim", Vector3(1.02, 0.12, 0.62), V(cos(a) * r, height + 0.96, sin(a) * r), turn)
			cap.solid = false
	else:
		var turf := cyl(g, "Overgrown", "grass", V(0, height, 0), diameter - 1.0, 0.05, sides)
		turf.solid = false
		turf.tint = GRASS_DARK
	return g


## A pennant on a tall pole standing on `foot` (the top of a tower).
func flag(parent: Node, foot: Vector3, kind: String) -> void:
	var g := group(parent, "Flag", Transform3D(Basis(Vector3.UP, -0.5), foot))
	g.set_meta("_edit_group_", true)
	var pole := cyl(g, "Pole", "wood", V(0, 0, 0), 0.14, 4.6, 8)
	pole.solid = false
	var knob := cyl(g, "Knob", "banner_gold", V(0, 4.6, 0), 0.26, 0.22, 8)
	knob.solid = false
	# A wedge on its side: tall at the pole, running out to a point.
	var cloth := put(g, "Cloth", kind, Vector3(0.05, 1.2, 2.4), V(1.27, 3.85, 0), Basis(Vector3.UP, PI * 0.5), MapBlock.Shape.WEDGE)
	cloth.solid = false


## A banner hanging on a pole set out from a wall: `at` is the top of the pole (in the
## parent's frame) and `out` the way the wall faces. A rod, the cloth with a gold band
## near its top and a gold lozenge on it, and two tails cut into its foot.
func banner(parent: Node, at: Vector3, out: Vector3, kind: String, drop := 3.2) -> void:
	var g := group(parent, "Banner", Transform3D(Basis(Vector3.UP, atan2(out.x, out.z)), at))
	g.set_meta("_edit_group_", true)
	var pole := put(g, "Pole", "wood", Vector3(0.12, 0.12, 0.9), V(0, 0, 0.45))
	pole.solid = false
	var rod := put(g, "Rod", "wood_dark", Vector3(1.8, 0.1, 0.1), V(0, -0.1, 0.8))
	rod.solid = false
	var cloth := put(g, "Cloth", kind, Vector3(1.5, drop, 0.05), V(0, -0.14 - drop * 0.5, 0.8))
	cloth.solid = false
	var flip := Basis(Vector3.BACK, PI)   # (a wedge turned over: its flat side up)
	for s in [-1.0, 1.0]:
		var tail := put(g, "Tail", kind, Vector3(0.05, 0.7, 0.75), V(s * 0.375, -0.14 - drop - 0.35, 0.8), Basis(Vector3.UP, -s * PI * 0.5) * flip, MapBlock.Shape.WEDGE)
		tail.solid = false
	var band := put(g, "Band", "banner_gold", Vector3(1.54, 0.18, 0.09), V(0, -0.14 - 0.35, 0.8))
	band.solid = false
	var mark := put(g, "Mark", "banner_gold", Vector3(0.6, 0.6, 0.09), V(0, -0.14 - drop * 0.52, 0.8), Basis(Vector3.BACK, PI * 0.25))
	mark.solid = false


## A paved floor (paint on the ground, 3 cm thick) from `lo` to `hi` (x and z), with
## `weeds` patches of grass grown over it.
func paving(parent: Node, name: String, lo: Vector2, hi: Vector2, y := 0.0, weeds := 0) -> void:
	var p := box(parent, name, "paving", V(lo.x, y, lo.y), V(hi.x, y + 0.03, hi.y))
	p.solid = false
	paved.append([parent, Rect2(lo, hi - lo)])
	for k in weeds:
		var d := deco.randf_range(1.0, 2.6)
		var at := V(deco.randf_range(lo.x + d * 0.5, hi.x - d * 0.5), y, deco.randf_range(lo.y + d * 0.5, hi.y - d * 0.5))
		var patch := cyl(parent, "Weeds", "grass", at, d, 0.05, deco.randi_range(5, 7), deco.randf_range(0.0, TAU))
		patch.solid = false
		patch.tint = GRASS_DARK


## A column standing on `base`: a pale shaft on a stepped base, with (if it still
## stands to full height, 3.5 m or more) a capital on top, or a broken end.
func column(parent: Node, base: Vector3, diameter: float, height: float) -> void:
	var g := group(parent, "Column", Transform3D(Basis.IDENTITY, base))
	g.set_meta("_edit_group_", true)
	cyl(g, "Shaft", "trim", V(0, 0, 0), diameter, height, 10)
	var foot := cyl(g, "Base", "stone_dark", V(0, 0, 0), diameter + 0.5, 0.25, 10)
	foot.solid = false
	var torus := cyl(g, "BaseRing", "stone", V(0, 0.25, 0), diameter + 0.24, 0.18, 10)
	torus.solid = false
	if height >= 3.5:
		var neck := cyl(g, "Neck", "stone", V(0, height - 0.2, 0), diameter + 0.2, 0.2, 10)
		neck.solid = false
		var cap := put(g, "Capital", "stone_dark", Vector3(diameter + 0.5, 0.35, diameter + 0.5), V(0, height + 0.175, 0))
		cap.solid = false
	else:
		var stub := cyl(g, "Break", "trim", V(diameter * 0.14, height, diameter * 0.08), diameter * 0.62, 0.22, 6, 0.4)
		stub.solid = false


## The Hearth: the ruined Keep, 22 by 16 m. Its walls stand between nothing and 7.2 m;
## the gate in the south wall still has its lintel; a corner of the upper floor is left
## (3 m up, on timber joists and two piers, a fallen slab for a ramp); a tall drum flying
## a red pennant stands at the north-east corner and the grown-over stump of another at
## the south-west. Red banners hang on the tall walls.
func hearth(g: Node3D) -> void:
	var k := group(g, "Keep")
	var walls := group(k, "Walls")
	broken_wall(walls, Vector2(-11, 8), Vector2(11, 8), [6.0, 4.8, 3.6, 3.6, 0, 0, 3.6, 4.8, 6.0, 7.2, 4.8])
	box(walls, "GateLintel", "stone_dark", V(-3, 2.9, 8 - THICK * 0.5), V(1, 3.6, 8 + THICK * 0.5))
	broken_wall(walls, Vector2(-11, -8), Vector2(11, -8), [7.2, 7.2, 6.0, 4.8, 2.4, 1.2, 0, 1.2, 3.6, 6.0, 6.0])
	broken_wall(walls, Vector2(-11, -8), Vector2(-11, 8), [7.2, 6.0, 4.8, 0, 0, 2.4, 4.8, 6.0])
	broken_wall(walls, Vector2(11, -8), Vector2(11, 8), [6.0, 3.6, 1.2, 1.2, 2.4, 0, 3.6, 4.8])
	banner(walls, V(8, 6.6, 8 + THICK * 0.5 - 0.02), Vector3(0, 0, 1), "banner_red", 3.4)
	banner(walls, V(-8, 6.6, -8 - THICK * 0.5 + 0.02), Vector3(0, 0, -1), "banner_red", 3.4)
	var tall := drum(k, "TallDrum", V(11, 0, -8), 6.0, 9.0, 12, true)
	banner(tall, V(2.85, 8.0, 0), Vector3(1, 0, 0), "banner_red", 3.6)
	flag(tall, V(0, 9.0, 0), "banner_red")
	drum(k, "DrumStump", V(-11, 0, 8), 6.0, 2.4, 12, false)
	paving(k, "Paving", Vector2(-10.6, -7.6), Vector2(10.6, 7.6), 0.0, 9)
	var upper := group(k, "UpperFloor")
	box(upper, "Slab", "paving", V(-10.6, 2.7, -7.6), V(-1, 3.0, -1.5))
	for x in [-2.0, -6.5]:
		cyl(upper, "Pier", "trim", V(x, 0, -2.2), 0.9, 2.7, 10)
	for x in [-9.0, -7.5, -5.0, -3.5]:
		var joist := box(upper, "Joist", "wood", V(x - 0.13, 2.42, -7.6), V(x + 0.13, 2.7, -1.2))
		joist.solid = false
	var beam := box(upper, "Beam", "wood_dark", V(-10.6, 2.14, -2.38), V(-0.7, 2.42, -2.02))
	beam.solid = false
	ramp(upper, "FallenSlab", "slab", V(5.5, 0, -4.5), V(-1, 3.0, -4.5), 2.6, 0.35)
	rubble(k, [[3, 2, 2.2, 1.0, 1.4, 20], [-5, 4, 1.6, 1.2, 1.6, 50], [6.5, -1, 2.6, 0.8, 1.2, -15],
		[-1, 11.5, 2.0, 1.2, 1.2, 35], [14.5, 3, 2.4, 1.2, 1.4, 70], [-14.5, -1, 1.8, 1.0, 1.8, 10], [1, -11, 2.8, 1.2, 1.2, -25]])
	for at in [V(0, 0, -14), V(16, 0, 6), V(-16, 0, -6), V(4, 0, 15), V(-8, 0, 16), V(3, 0, 0)]:
		spawn(g, "Hearth", at, Vector3.ZERO)
	spawn(g, "KeepUpper", V(-6, 3.0, -5), V(0, 3.0, 4))


## The Terrace: the Broken Tower. Eight wall panels in a ring (14 m across), from
## nothing (the way in, on the south-west) up to 10.8 m. Inside, a lookout 6 m up
## against the tall north-east walls, on two columns, and a ramp straight up to it from
## the doorway: from it you see and shoot over the low west and north-west walls (and
## over the south one, chest high), with the tall walls at your back. Purple banners
## hang outside on the tall walls. A stub of curtain wall runs off east.
func terrace(g: Node3D) -> void:
	var t := group(g, "BrokenTower")
	var shell := group(t, "Shell")
	var apothem := 7.0
	var panel := 2.0 * apothem * tan(PI / 8.0) + THICK * 0.8   # a little long, so the corners close
	var heights := [10.8, 9.6, 7.2, 0.0, 3.6, 6.0, 8.4, 10.8]
	for i in 8:
		var h: float = heights[i]
		if h <= 0.0:
			continue
		var a: float = TAU * i / 8.0
		# The panel's x runs along the ring (the tangent).
		wall_piece(shell, "stone", Vector3(panel, h, THICK), V(cos(a) * apothem, h * 0.5, sin(a) * apothem), Basis(Vector3.UP, atan2(-cos(a), -sin(a))), 0.5)
	var inside := group(t, "Inside")
	var floor := cyl(inside, "Paving", "paving", V(0, 0, 0), 13.0, 0.03, 16)   # (round, to stay inside the eight walls)
	floor.solid = false
	paved.append([inside, Rect2(-6.5, -6.5, 13.0, 13.0)])
	lookout(inside)
	for i in [1, 2, 6, 7]:
		var a: float = TAU * i / 8.0
		banner(shell, V(cos(a) * (apothem + THICK * 0.5 - 0.05), minf(float(heights[i]) - 1.0, 8.2), sin(a) * (apothem + THICK * 0.5 - 0.05)), Vector3(cos(a), 0, sin(a)), "banner_purple", 4.0)
	broken_wall(t, Vector2(7.6, -0.5), Vector2(15.6, -3.5), [6.0, 4.8, 2.4, 1.2])
	rubble(t, [[-8.5, 8.5, 2.0, 1.2, 1.4, 40], [10, 8, 2.4, 1.0, 1.4, -20], [-5, -12.5, 2.2, 1.2, 1.2, 15], [9, -10, 1.6, 1.2, 1.6, 60]])
	for at in [V(12, 0, 4), V(0, 0, 12.5), V(-13, 0, -3), V(6, 0, -11)]:
		spawn(g, "Terrace", at, Vector3.ZERO)
	spawn(g, "Lookout", ne(5.0, 0.0, LOOKOUT), ne(-6.0, 0.0, LOOKOUT))


## The Broken Tower's lookout is laid out along the line from its doorway (south-west)
## to its tallest corner (north-east): `u` metres along that line from the tower's
## middle (toward the north-east), `v` across it (toward the south-east), `y` up.
const LOOKOUT := 6.0       ## how high its top is
const LOOKOUT_FROM := 3.0  ## its front edge, `u` metres from the middle (it runs back to the wall, 6.6)
const LOOKOUT_WIDE := 7.2  ## across


func ne(u: float, v: float, y: float) -> Vector3:
	return V((u + v) * 0.7071, y, (v - u) * 0.7071)


## The lookout: a stone floor on two columns, and a ramp up to its front edge from
## inside the doorway (34 degrees: a run you can sprint up).
func lookout(inside: Node3D) -> void:
	var g := group(inside, "Lookout")
	var turn := Basis(Vector3.UP, deg_to_rad(-45.0))   # (the block's x across the line, its z along it)
	var deep := 6.6 - LOOKOUT_FROM
	var floor := put(g, "Floor", "paving", Vector3(LOOKOUT_WIDE, 0.4, deep), ne(LOOKOUT_FROM + deep * 0.5, 0, LOOKOUT - 0.2), turn)
	var lip := put(g, "Edge", "trim", Vector3(LOOKOUT_WIDE + 0.06, 0.16, 0.5), ne(LOOKOUT_FROM + 0.22, 0, LOOKOUT - 0.47), turn)   # (a band under its front edge)
	lip.solid = false
	for v in [-2.6, 2.6]:
		column(g, ne(LOOKOUT_FROM + 0.5, v, 0), 0.7, LOOKOUT - 0.75)   # (its capital just under the floor)
	ramp(g, "Ramp", "slab", ne(-5.8, 0, 0), ne(LOOKOUT_FROM, 0, LOOKOUT), 2.6, 0.4)


## The Citadel: the Gate and its curtain wall, 2 m thick and 5 m high with a wall walk
## on top. West to east: a long run with a stair up its inner face, a breach, the gate
## (a 4 m arch, the walk carried over it), a second run with a low breach in it, and a
## drum flying a blue pennant at the east end. The wall has a darker footing, a pale
## course under its merlons, arrow slits, ivy and blue banners on its outer face. A row
## of column stumps stands in front.
func citadel(g: Node3D) -> void:
	var w := group(g, "CurtainWall")
	var z0 := -4.0   # the outer face
	var z1 := -2.0   # the inner face
	var top := 5.0
	# The wall itself, stone all through (no copings: the walk runs along its top).
	for run in [[-17.0, -6.0], [-3.5, -2.0], [2.0, 7.0], [9.0, 12.0]]:
		box(w, "Wall", "stone", V(run[0], 0, z0), V(run[1], top, z1))
		var foot := box(w, "Footing", "stone_dark", V(run[0] - 0.08, 0, z0 - 0.1), V(run[1] + 0.08, 0.7, z1 + 0.1))
		foot.solid = false
		var course := box(w, "Course", "trim", V(run[0] - 0.06, top - 0.62, z0 - 0.12), V(run[1] + 0.06, top - 0.36, z0 + 0.1))
		course.solid = false
	box(w, "GateLintel", "stone_dark", V(-2, 3.6, z0), V(2, top, z1))
	put(w, "GateArch", "trim", Vector3(4.0, 1.3, z1 - z0 + 0.16), V(0, 3.6 - 0.65, (z0 + z1) * 0.5), Basis.IDENTITY, MapBlock.Shape.ARCH).top = 0.12
	wall_piece(w, "stone", Vector3(2, 2.4, z1 - z0), V(8, 1.2, (z0 + z1) * 0.5), Basis.IDENTITY, 0.0, "coping")   # the low breach: it has a coping
	for x in [-12.5, -9.5, -7.2, 3.0, 6.2]:
		var slit := box(w, "Slit", "shadow", V(x - 0.09, 2.0, z0 - 0.02), V(x + 0.09, 3.2, z0 + 0.02))
		slit.solid = false
	# Banners down its outer face either side of the gate, and the ivy on it.
	for x in [-2.75, 4.5]:
		banner(w, V(x, top - 0.7, z0 + 0.05), Vector3(0, 0, -1), "banner_blue", 3.0)
	for patch in [[-14.5, 4.0], [10.5, 2.6]]:
		var holder := group(w, "Ivy", Transform3D(Basis.IDENTITY, V(patch[0], (top - 0.7) * 0.5, (z0 + z1) * 0.5)))
		holder.set_meta("_edit_group_", true)
		var shade := deco.randf_range(0.3, 0.6)
		for strand in 3:
			ivy(holder, Vector3(patch[1], top - 0.7, z1 - z0), -1.0, shade)
	var merlons := group(w, "Merlons")
	for x in [-16.3, -14.3, -12.3, -10.3, -8.3, -2.9, -0.7, 1.3, 3.3, 5.3, 9.7, 11.3]:
		var m := group(merlons, "Merlon", Transform3D(Basis.IDENTITY, V(x, top, z0 + 0.25)))
		m.set_meta("_edit_group_", true)
		box(m, "Stone", "stone", V(-0.5, 0, -0.25), V(0.5, 0.9, 0.25))
		var cap := box(m, "Coping", "trim", V(-0.56, 0.9, -0.31), V(0.56, 1.02, 0.31))
		cap.solid = false
	ramp(w, "Stair", "slab", V(-6.5, 0, z1 + 1.0), V(-16, top, z1 + 1.0), 2.0, 0.4)
	box(w, "StairLanding", "paving", V(-18.5, top - 0.4, z1), V(-16, top, z1 + 2.03))   # level with the wall walk, to step across from
	var tower := drum(w, "Drum", V(14, 0, -3), 6.0, 7.2, 12, true)
	banner(tower, V(0, 6.2, -2.85), Vector3(0, 0, -1), "banner_blue", 3.4)
	flag(tower, V(0, 7.2, 0), "banner_blue")
	paving(g, "Courtyard", Vector2(-12, -2), Vector2(12, 9), 0.0, 7)
	var columns := group(g, "Colonnade")
	var heights := [4.0, 1.2, 3.0, 4.0, 0.8]
	for i in heights.size():
		column(columns, V(-9 + i * 4.5, 0, 6), 1.0, heights[i])
	rubble(g, [[-4.8, -3, 1.8, 1.2, 1.6, 20], [-5.2, 0.5, 1.4, 0.8, 1.2, 60], [8, -0.5, 2.0, 1.0, 1.2, -30],
		[-12, 10, 2.2, 1.2, 1.4, 15], [13, 8, 1.8, 1.2, 1.8, 45], [0, -12, 2.4, 1.2, 1.2, -10]])
	for at in [V(0, 0, 11), V(-13, 0, 6), V(13, 0, 4), V(-4, 0, -12)]:
		spawn(g, "Citadel", at, Vector3.ZERO)
	spawn(g, "WallWalk", V(-11, top, -3), V(-11, top, 6))


# -- crossings between islands ---------------------------------------------------------
## Stepping pads across the gap between two islands: few and big. As few as keep every
## step about 2 m or less in height (a ledge climb reaches 2.3 m) and every jump about
## 4.5 m or less across, each 5 to 8 m across to fill the gap, and then
## scattered: the row swings to one side and back in an S of its own, and each pad is
## thrown off it sideways (up to 2 m), along (up to 1 m) and up or down (up to 0.15 m),
## with its own size (4.5 to 9 m), number of sides (5 to 9) and turn. About one pad in
## four has a smaller one beside it, as another way round. The numbers come from a
## seeded generator, so every run lays the same pads. The longest hop between two pads
## in a row stays well inside a sprinting jump (7.5 m).
##
## Every pad is a MapMover of its own, timed to its two islands: a pad `part` of the
## way across rides at that share of the far island's bob and the rest of the near
## one's, so the row stays a staircase from one deck to the other as they rise and fall
## (see pad_bob()).
func stepping_stones(parent: Node, from: String, to: String) -> void:
	var a := centre(from)
	var b := centre(to)
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	var dist := flat.length()
	flat = flat.normalized()
	var across := Vector3.UP.cross(flat)
	var out := reach(from, flat)
	var gap := dist - out - reach(to, -flat)
	# The two islands bob out of step, so the climb between them swings either side of its
	# average by `swing` (half the gap between their two arrows: see pad_bob()). The pads
	# are counted for the climb at its greatest.
	var swing: float = (Vector2.from_angle(TAU * BOB[from][1]) * BOB[from][0] - Vector2.from_angle(TAU * BOB[to][1]) * BOB[to][0]).length() * 0.5
	var count := maxi(1, ceili((absf(b.y - a.y) + swing) / 2.0) - 1)
	while (gap - count * 6.5) / (count + 1) > 4.5:
		count += 1
	var size := clampf((gap - (count + 1) * 2.5) / count, 5.0, 8.0)
	var space := (gap - size * count) / (count + 1)
	var bow := rng.randf_range(2.0, 4.5) * (1.0 if rng.randf() < 0.5 else -1.0)
	var wave := rng.randf_range(-3.0, 3.0)
	var g := group(parent, from + "To" + to)
	var extras := 0
	var hop := 0.0          # the longest gap between one pad's edge and the next's
	var last := Vector3.ZERO
	var last_d := 0.0
	var row := [[a.y, BOB[from][0], BOB[from][1]]]   # [mean height, rise, phase] of each stop along the row
	var stops := []         # the pads in the row, in order: [their mover, the middle of their top (half way up), diameter]
	var slid := 0           # pads moved along the row to clear an island
	for i in count:
		var part := (i + 1.0) / (count + 1)
		var along := out + space * (i + 1) + size * (i + 0.5) + rng.randf_range(-1.0, 1.0)
		var aside := sin(PI * part) * bow + sin(TAU * part) * wave + rng.randf_range(-2.0, 2.0)
		var lift := rng.randf_range(-0.15, 0.15)
		var d := clampf(size * rng.randf_range(0.8, 1.2), 4.5, 9.0)
		var spot := Vector3(a.x, 0, a.z) + flat * along + across * aside
		# No pad may stand in an island. The gap was measured down the middle of the row,
		# but an island's rim runs in and out and the pad is thrown to one side, so it can
		# land on a deck: slide it along the row, toward the middle of the gap, until it
		# is clear (with CLEAR to spare).
		var inward := 1.0 if along < out + gap * 0.5 else -1.0
		var tries := 0
		while touches_island(spot, d * 0.5) and tries < 60:
			along += 0.25 * inward
			spot = Vector3(a.x, 0, a.z) + flat * along + across * aside
			tries += 1
		if tries > 0:
			slid += 1
		# Nor in the pad before it: it gives way by being smaller.
		if i > 0:
			var room := Vector2(spot.x - last.x, spot.z - last.z).length() - last_d * 0.5 - CLEAR
			d = clampf(minf(d, room * 2.0), 3.0, 9.0)
		# (Its height and its bob still go by its number in the row, so the steps stay even.)
		var top := lerpf(a.y, b.y, part) + lift
		var at := Vector3(spot.x, top, spot.z)
		var bob := pad_bob(from, to, part)
		stops.append([pad(g, at, d, bob), at, d])
		row.append([top, bob[0], bob[1]])
		if i > 0:
			hop = maxf(hop, Vector2(at.x - last.x, at.z - last.z).length() - (d + last_d) * 0.5)
		last = at
		last_d = d
		if rng.randf() < 0.25:
			# A smaller pad off to one side, a little higher or lower, moving with its
			# neighbour: on whichever side is clear of the islands, or not at all.
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var reach_out := d * 0.5 + rng.randf_range(2.8, 4.0)
			var shift := rng.randf_range(-1.5, 1.5)
			var small := rng.randf_range(3.0, 4.2)
			var drop := rng.randf_range(-0.6, 0.6)
			for s in [side, -side]:
				var beside: Vector3 = at + across * reach_out * s + flat * shift + V(0, drop, 0)
				if not touches_island(beside, small * 0.5):
					pad(g, beside, small, bob)
					extras += 1
					break
	row.append([b.y, BOB[to][0], BOB[to][1]])
	# The tallest step in the row at any moment of the cycle.
	var step := 0.0
	for k in 96:
		var t := PERIOD * k / 96.0
		for i in row.size() - 1:
			step = maxf(step, absf(height_at(row[i], t) - height_at(row[i + 1], t)))
	print("  %s to %s: %.1f m of open sky, %+.1f m, %d pads (%d slid clear of an island, %d beside them); longest hop %.1f m; tallest step at any moment %.2f m" % [from, to, gap,
		b.y - a.y, count, slid, extras, hop, step])
	# The bots' way along the row: a hop each way between each stop and the next.
	hop_links(from, stops[0])
	for i in stops.size() - 1:
		pad_links(stops[i], stops[i + 1])
	hop_links(to, stops[stops.size() - 1])


## Would a pad `radius` across its middle at `spot` (x and z in the map) stand in an
## island, or within CLEAR of one? Its middle and two rings of points round it are
## tried against every island's deck.
func touches_island(spot: Vector3, radius: float) -> bool:
	for name in ISLANDS:
		var c := centre(name)
		var p := Vector2(spot.x - c.x, spot.z - c.z)
		if p.length() > 45.0 + radius:
			continue
		if on_island(name, p):
			return true
		for k in 32:
			var dir := Vector2.from_angle(TAU * k / 32.0)
			if on_island(name, p + dir * (radius + CLEAR)) or on_island(name, p + dir * radius * 0.5):
				return true
	return false


## How a pad `part` of the way from one island to another must bob to stay on the line
## between them: [rise, phase] for its MapMover. A MapMover with no hold moves as one
## cosine: rise * (0.5 - 0.5 * cos(turn)), where turn = TAU * (time / PERIOD + phase).
## The pad needs (1 - part) of one island's cosine plus `part` of the other's; two
## cosines of the same period add up to one cosine, whose size and timing come from
## adding them as arrows (size = rise, direction = phase).
func pad_bob(from: String, to: String, part: float) -> Array:
	var arrow: Vector2 = Vector2.from_angle(TAU * BOB[from][1]) * BOB[from][0] * (1.0 - part) + Vector2.from_angle(TAU * BOB[to][1]) * BOB[to][0] * part
	return [arrow.length(), fposmod(arrow.angle() / TAU, 1.0)]


## Where something that bobs is at time `t`: `stop` = [mean height, rise, phase].
func height_at(stop: Array, t: float) -> float:
	return stop[0] - 0.5 * stop[1] * cos(TAU * (t / PERIOD + stop[2]))


## One pad: a mover holding a slab (its top at `at` when half way up its bob) and a
## small cone of rock under it. `bob` = [rise, phase].
func pad(parent: Node, at: Vector3, d: float, bob: Array) -> Node3D:
	var sides := rng.randi_range(5, 9)
	var turn := rng.randf_range(0.0, TAU)
	var m := mover(parent, "Pad", at, bob[0], bob[1])
	m.set_meta("_edit_group_", true)   # (one click in the viewport picks the whole pad)
	# A little island of its own: grass on top, earth, a cone of rock under it.
	var top_sides := maxi(sides, PAD_SIDES)
	pads_drawn.append([at, d, top_sides, turn])
	cyl(m, "Turf", "grass", V(0, -0.25, 0), d, 0.25, top_sides, turn)
	cyl(m, "Earth", "earth", V(0, -1.0, 0), d - 0.4, 0.75, top_sides, turn)
	var rock := hung_cone(m, "Rock", "rock", V(0, -1.0, 0), d * 0.9, d * 0.55, d * 0.2, sides, turn)
	rock.solid = true
	var crag := hung_cone(m, "Crag", "rock", V(deco.randf_range(-0.15, 0.15) * d, -1.3, deco.randf_range(-0.15, 0.15) * d),
		d * 0.45, d * 0.7, d * 0.05, 5, deco.randf_range(0.0, TAU))
	crag.tint = grey(deco.randf_range(0.72, 0.95))
	return m


## Prints the open sky between the Hearth and each outer island (nothing crosses it).
func hearth_gaps() -> void:
	var a := centre("Hearth")
	for name in ISLANDS:
		if name == "Hearth":
			continue
		var b := centre(name)
		var flat := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var least := INF
		var most := -INF
		for k in 96:
			var t := PERIOD * k / 96.0
			var up := height_at([b.y, BOB[name][0], BOB[name][1]], t) - height_at([a.y, BOB["Hearth"][0], BOB["Hearth"][1]], t)
			least = minf(least, up)
			most = maxf(most, up)
		print("  Hearth to %s: %.1f m of open sky, %+.1f m on average (from %.1f to %.1f m), nothing across" % [name,
			Vector2(b.x - a.x, b.z - a.z).length() - reach("Hearth", flat) - reach(name, -flat), b.y - a.y, least, most])
	boost_links()


# -- bots' crossings and pickups -----------------------------------------------------
## A weapon pickup on an island (`at` in its frame): it rides the island's bob.
func pickup(island: Node3D, weapon: String, at: Vector3) -> void:
	var holder := island.get_node_or_null("WeaponSpawns")
	if holder == null:
		holder = group(island, "WeaponSpawns")
	var w: Marker3D = weapon_script.new()
	w.name = weapon.to_pascal_case()
	w.set("weapon", weapon)
	holder.add_child(w, true)
	w.owner = scn
	w.position = at
	clear_of(island, at, 2.0)


## A node's transform in `top`'s frame (the scene is not in a tree yet, so no globals).
func frame_in(node: Node3D, top: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != top:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## What stands on an island's deck (everything but its Ground): [x, z, radius] each, in
## its frame, the radius reaching the corners of the block's footprint.
func what_stands_on(island: Node3D) -> Array:
	var out := []
	var ground := island.get_node("Ground")
	for b in island.find_children("*", "MapBlock", true, false):
		if ground.is_ancestor_of(b) or not (b as MapBlock).solid:
			continue   # (drawn-only dressing is in nobody's way)
		var xf := frame_in(b, island)
		var size := (b as MapBlock).size
		if (b as MapBlock).shape == MapBlock.Shape.BOX and absf(xf.basis.y.y) > 0.99:
			# An upright box: a row of circles down its length (one round a long hedge
			# or wall would keep everything metres off its sides).
			var along := Vector2(xf.basis.x.x, xf.basis.x.z).normalized() * size.x
			var across := size.z
			if size.z > size.x:
				along = Vector2(xf.basis.z.x, xf.basis.z.z).normalized() * size.z
				across = size.x
			var n := maxi(1, ceili(along.length() / maxf(across, 1.0)))
			for k in n:
				var p := Vector2(xf.origin.x, xf.origin.z) + along * ((k + 0.5) / n - 0.5)
				out.append([p.x, p.y, Vector2(along.length() / n, across).length() * 0.5])
			continue
		var box := xf * AABB(-size * 0.5, size)
		out.append([box.get_center().x, box.get_center().z, Vector2(box.size.x, box.size.z).length() * 0.5])
	return out


## Room for a bot at `p` (an island's frame): nothing standing within `r`, and deck all round.
func clear_spot(name: String, p: Vector2, r: float) -> bool:
	for o in obstacles[name]:
		if p.distance_to(Vector2(o[0], o[1])) < r + float(o[2]):
			return false
	if not on_deck(name, p):
		return false
	for k in 8:
		if not on_deck(name, p + Vector2.from_angle(TAU * k / 8.0) * r):
			return false
	return true


## Nothing standing within `r` of the line from `a` to `b` (an island's frame).
func clear_run(name: String, a: Vector2, b: Vector2, r: float) -> bool:
	var steps := ceili(a.distance_to(b) / 0.5)
	for i in steps + 1:
		var p := a.lerp(b, float(i) / maxf(steps, 1))
		for o in obstacles[name]:
			if p.distance_to(Vector2(o[0], o[1])) < r + float(o[2]):
				return false
	return true


## Coming from `outside` toward `inside` (an island's frame), the first point on its deck.
func rim_toward(name: String, outside: Vector2, inside: Vector2) -> Vector2:
	var dir := (inside - outside).normalized()
	var p := outside
	var gone := 0.0
	while not on_deck(name, p) and gone < 140.0:
		p += dir * 0.05
		gone += 0.05
	return p


## The group in a mover that holds the crossings setting off from it and the spots
## landing on it.
func crossings_of(node: Node3D) -> Node3D:
	var holder := node.get_node_or_null("BotCrossings") as Node3D
	return holder if holder else group(node, "BotCrossings")


## A crossing for bots (a MapJumpLink): it sets off at `from_at` in `from_node` (a mover)
## and comes down at `land_at` in `to_node`. `land` reuses a landing spot already there.
func add_link(from_node: Node3D, from_at: Vector3, to_node: Node3D, land_at: Vector3, how: int, rise := Vector2.ZERO, flight := 0.8, land: Node3D = null) -> Node3D:
	var l: Marker3D = link_script.new()
	l.name = ("Hop" if how == MapJumpLink.How.HOP else "Boost") + "To" + str(to_node.name)
	l.set("how", how)
	l.set("rise_min", rise.x)
	l.set("rise_max", rise.y)
	l.set("flight", flight)
	crossings_of(from_node).add_child(l, true)
	l.owner = scn
	l.position = from_at
	if land == null:
		land = Marker3D.new()
		land.name = "LandFrom" + str(from_node.name)
		crossings_of(to_node).add_child(land, true)
		land.owner = scn
		land.position = land_at
	l.set("landing", l.get_path_to(land))
	# The foliage keeps off where it sets off, its run-up and where it comes down.
	var from_map: Vector3 = mid_of[from_node] + from_at
	var to_map: Vector3 = mid_of[to_node] + land.position
	var run := Vector3(to_map.x - from_map.x, 0, to_map.z - from_map.z)
	for s in range(0, int(minf(run.length(), 8.0)) + 1):
		var p := from_map + run.normalized() * s
		keep_clear.append([p.x, p.z, 2.0])
	for s in range(1, int(minf(run.length(), 8.0)) + 1):
		var p := to_map - run.normalized() * s   # (and the last stretch before it comes down)
		keep_clear.append([p.x, p.z, 2.0])
	keep_clear.append([to_map.x, to_map.z, 2.5])
	links += 1
	return land


## A pad's own landing spot (its middle), made once.
func pad_landing(stop: Array) -> Node3D:
	var holder := crossings_of(stop[0])
	var land := holder.get_node_or_null("Land") as Node3D
	if land == null:
		land = Marker3D.new()
		land.name = "Land"
		holder.add_child(land)
		land.owner = scn
	return land


## Hops both ways between two pads in a row (`stop` = [mover, middle of its top, diameter]).
func pad_links(s1: Array, s2: Array) -> void:
	var a: Vector3 = s1[1]
	var b: Vector3 = s2[1]
	var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	add_link(s1[0], dir * (float(s1[2]) * 0.5 - RUN_UP), s2[0], Vector3.ZERO, MapJumpLink.How.HOP, Vector2.ZERO, 0.8, pad_landing(s2))
	add_link(s2[0], -dir * (float(s2[2]) * 0.5 - RUN_UP), s1[0], Vector3.ZERO, MapJumpLink.How.HOP, Vector2.ZERO, 0.8, pad_landing(s1))


## Hops both ways between an island and the pad next to it: on the line from the pad
## toward the island's middle, or a line beside it if something stands in the way.
func hop_links(name: String, stop: Array) -> void:
	var c := centre(name)
	var at: Vector3 = stop[1]
	var d: float = stop[2]
	var pad_xz := Vector2(at.x - c.x, at.z - c.z)   # the pad's middle, in the island's frame
	var toward := -pad_xz.normalized()               # from the pad into the island
	var across := Vector2(-toward.y, toward.x)
	for off in [0.0, 1.5, -1.5, 3.0, -3.0, 4.5, -4.5]:
		var line: Vector2 = pad_xz + across * off
		var rim := rim_toward(name, line, line + toward * 120.0)
		var takeoff := rim + toward * RUN_UP
		var landing := rim + toward * 3.5
		var gap := rim.distance_to(pad_xz) - d * 0.5
		if gap > 5.0 or not clear_spot(name, takeoff, 0.8) or not clear_spot(name, landing, 1.2) or not clear_run(name, takeoff, rim, 0.8):
			continue
		var node: Node3D = island_nodes[name]
		var pad_dir := Vector3(toward.x, 0, toward.y)
		add_link(node, V(takeoff.x, 0, takeoff.y), stop[0], Vector3.ZERO, MapJumpLink.How.HOP, Vector2.ZERO, 0.8, pad_landing(stop))
		add_link(stop[0], pad_dir * (d * 0.5 - RUN_UP) + Vector3(across.x, 0, across.y) * off * 0.5, node, V(landing.x, 0, landing.y), MapJumpLink.How.HOP)
		return
	print("  WARNING: no clear way for bots between %s and its pad at %s" % [name, at])


## The rocket boots between the Hearth and each outer island, on the line between their
## middles (or one beside it): down onto the Hearth at any moment; up off it only while
## the landing will be at most HEARTH_CLIMB above the takeoff, and not at all to an
## island that never comes that low.
func boost_links() -> void:
	var hearth: Node3D = island_nodes["Hearth"]
	var hc := centre("Hearth")
	for name in ISLANDS:
		if name == "Hearth":
			continue
		var oc := centre(name)
		var dir := Vector2(oc.x - hc.x, oc.z - hc.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		var least := INF
		for k in 96:
			var t := PERIOD * k / 96.0
			least = minf(least, height_at([oc.y, BOB[name][0], BOB[name][1]], t) - height_at([hc.y, BOB["Hearth"][0], BOB["Hearth"][1]], t))
		var made := false
		for off in [0.0, 2.0, -2.0, 4.0, -4.0, 6.0, -6.0, 8.0, -8.0]:
			var h_rim := rim_toward("Hearth", side * float(off) + dir * 120.0, side * float(off))
			var h_spot := h_rim - dir * BOOST_RUN
			var o_line: Vector2 = Vector2(hc.x - oc.x, hc.z - oc.z) + side * off   # the Hearth's side, in the outer island's frame
			var o_rim := rim_toward(name, o_line, side * float(off))
			var o_spot := o_rim + dir * BOOST_RUN
			if not clear_spot("Hearth", h_spot, 2.0) or not clear_run("Hearth", h_spot, h_rim, 0.9) \
					or not clear_spot(name, o_spot, 2.0) or not clear_run(name, o_spot, o_rim, 0.9):
				continue
			var outer: Node3D = island_nodes[name]
			add_link(outer, V(o_spot.x, 0, o_spot.y), hearth, V(h_spot.x, 0, h_spot.y), MapJumpLink.How.BOOST, Vector2.ZERO, BOOST_FLIGHT)
			if least <= HEARTH_CLIMB:
				add_link(hearth, V(h_spot.x, 0, h_spot.y), outer, V(o_spot.x, 0, o_spot.y), MapJumpLink.How.BOOST, Vector2(-4.0, HEARTH_CLIMB), BOOST_FLIGHT)
			print("  bots: boots from %s down to the Hearth%s" % [name, "" if least > HEARTH_CLIMB else ", and back up (when it is %.1f m up or less)" % HEARTH_CLIMB])
			made = true
			break
		if not made:
			print("  WARNING: no clear way for bots between the Hearth and %s" % name)


# -- the green ----------------------------------------------------------------------------
## The tint of the darker grass: patches of meadow, weeds in the paving.
const GRASS_DARK := Color(0.5, 0.72, 0.62)

## Pines on every island, in threes kinds mixed (thick-trunked; thick trunk and thick
## leaves; full, the trunk hidden), many with a young one or two beside them, and a few
## trees in pink blossom: wherever there is room, clear of the ruins, the garden and
## other trees, and off spawn points, pickups and the bots' crossings.
const PINES := {"Hearth": 7, "Shelf": 5, "Bluff": 4, "Spire": 3, "Citadel": 5, "Garden": 4, "Terrace": 5}
const BLOSSOMS := {"Hearth": 2, "Shelf": 3, "Bluff": 1, "Spire": 1, "Citadel": 2, "Garden": 3, "Terrace": 1}


func trees(name: String) -> void:
	var g := group(island_nodes[name], "Trees")
	var reach_all := island_reach(name)
	var planted := 0
	for attempt in 800:
		if planted >= int(BLOSSOMS[name]):
			break
		var p := Vector2(deco.randf_range(-1.0, 1.0), deco.randf_range(-1.0, 1.0)) * reach_all
		if not spot_ok(name, p, 2.3, 2.0):
			continue
		blossom_tree(g, V(p.x, 0, p.y), deco.randf_range(4.8, 6.2))
		obstacles[name].append([p.x, p.y, 3.2])
		planted += 1
	var pink := planted
	planted = 0
	for attempt in 800:
		if planted >= int(PINES[name]):
			break
		var p := Vector2(deco.randf_range(-1.0, 1.0), deco.randf_range(-1.0, 1.0)) * reach_all
		if not spot_ok(name, p, 1.5, 1.6):
			continue
		var at := V(p.x, 0, p.y)
		# One green to a clump: the tree and the young ones by it (whose branches cross).
		var shade := deco.randf_range(0.7, 1.0)
		var green := Color(shade * deco.randf_range(0.8, 1.0), shade, shade * deco.randf_range(0.75, 1.0))
		match planted % 3:
			0: pine(g, at, deco.randf_range(6.0, 7.5), 0.75, 4, 3.8, 1.4, 0.3, 0.25, green)    # thick trunk
			1: pine(g, at, deco.randf_range(6.5, 8.0), 0.75, 5, 4.4, 1.6, 0.36, 0.2, green)    # thick trunk, thick leaves
			2: pine(g, at, deco.randf_range(6.5, 8.5), 0.55, 6, 4.8, 1.5, 0.34, 0.1, green)    # full, the trunk hidden
		# A young one or two beside it, so they stand in clumps.
		var young := []
		for k in deco.randi_range(0, 2):
			for attempt2 in 8:
				var q := p + Vector2.from_angle(deco.randf_range(0.0, TAU)) * deco.randf_range(2.6, 3.8)
				var crowded := false
				for y in young:
					if q.distance_to(y) < 2.2:
						crowded = true
				if crowded or not spot_ok(name, q, 1.3, 2.0):
					continue
				pine(g, V(q.x, 0, q.y), deco.randf_range(3.4, 4.8), 0.45, 4, 2.7, 1.0, 0.32, 0.18, green)
				young.append(q)
				break
		obstacles[name].append([p.x, p.y, 2.6])   # (room round it: the next tree, a flower)
		for q in young:
			obstacles[name].append([q.x, q.y, 1.7])
		planted += 1
	print("  %s: %d pines, %d trees in blossom" % [name, planted, pink])


## The furthest any of an island's lobes reaches from its centre.
func island_reach(name: String) -> float:
	var far := 0.0
	for l in ISLANDS[name][1]:
		far = maxf(far, Vector2(l[0], l[1]).length() + float(l[2]) * 0.5)
	return far


## A pine `h` tall: a trunk `trunk_d` across (solid: you can hide behind it) and `tiers`
## cones of needles from `wide` at the foot to `narrow` at the top, each `tier_h` of the
## height deep, the lowest `start` of the height up, tinted `green`.
func pine(parent: Node, at: Vector3, h: float, trunk_d: float, tiers: int, wide: float, narrow: float, tier_h: float, start: float, green: Color) -> void:
	var g := group(parent, "Pine", Transform3D(Basis(Vector3.UP, deco.randf_range(0.0, TAU)), at))
	g.set_meta("_edit_group_", true)
	cyl(g, "Trunk", "trunk", V(0, 0, 0), trunk_d, h * 0.45, 7)
	for i in tiers:
		var f := float(i) / tiers
		var w := lerpf(wide, narrow, f)
		var y := h * start + f * h * (1.0 - start - tier_h * 0.55)
		var tier := put(g, "Needles", "pine", Vector3(w, h * tier_h, w), V(0, y + h * tier_h * 0.5, 0), Basis(Vector3.UP, i * 0.4), MapBlock.Shape.CONE)
		tier.sides = 8
		tier.top = 0.0
		tier.solid = false
		tier.tint = green


## A tree in blossom, `h` tall: a short leaning trunk (solid), two boughs, a crown of
## pink balls of blossom, each its own shade.
func blossom_tree(parent: Node, at: Vector3, h: float) -> void:
	var g := group(parent, "BlossomTree", Transform3D(Basis(Vector3.UP, deco.randf_range(0.0, TAU)), at))
	g.set_meta("_edit_group_", true)
	var trunk := put(g, "Trunk", "trunk", Vector3(0.9, h * 0.6, 0.9), V(0, h * 0.3 - 0.06, 0), Basis(Vector3.RIGHT, 0.05), MapBlock.Shape.CONE)
	trunk.sides = 7
	trunk.top = 0.45
	for s in [-1.0, 1.0]:
		var lean := Basis(Vector3.BACK, s * 0.75)
		var length := h * 0.36
		var bough := put(g, "Bough", "trunk", Vector3(0.42, length, 0.42), V(0, h * 0.42, 0) + lean * Vector3.UP * length * 0.5, lean, MapBlock.Shape.CONE)
		bough.sides = 6
		bough.top = 0.2
		bough.solid = false
	var k := h / 5.4
	var c := h * 0.74
	for b in [[0.0, 0.0, 0.0, 3.7], [1.4, -0.5, 0.4, 2.7], [-1.35, -0.3, -0.5, 2.9], [0.2, 0.95, -0.3, 2.5], [-0.3, -0.55, 1.4, 2.4], [0.5, -0.4, -1.45, 2.3]]:
		ball(g, "Blossom", "blossom", V(b[0] * k, c + b[1] * k, b[2] * k), b[3] * k, 0.82, 7)


## Boulders near an island's rim, in twos and threes: rough rock half sunk in the grass
## (the big one solid), off spawn points, pickups and the bots' crossings.
func boulders(name: String) -> void:
	var g := group(island_nodes[name], "Boulders")
	var want: int = (ISLANDS[name][1] as Array).size()
	var made := 0
	for attempt in 200:
		if made >= want:
			break
		var a := deco.randf_range(0.0, TAU)
		var p := Vector2.from_angle(a) * deck_reach(name, Vector3(cos(a), 0, sin(a))) * deco.randf_range(0.7, 0.9)
		if not spot_ok(name, p, 1.6, 1.5):
			continue
		var heap := group(g, "Boulders", Transform3D(Basis(Vector3.UP, deco.randf_range(0.0, TAU)), V(p.x, 0, p.y)))
		heap.set_meta("_edit_group_", true)
		var shade := deco.randf_range(0.8, 1.0)
		for k in deco.randi_range(2, 3):
			var big := k == 0
			var size := Vector3(deco.randf_range(1.2, 1.9), deco.randf_range(0.9, 1.4), deco.randf_range(1.0, 1.6)) if big else Vector3.ONE * deco.randf_range(0.45, 0.8)
			var at := V(0, size.y * 0.5 - size.y * 0.22, 0) if big else V((1.25 if k == 1 else -0.9), size.y * 0.3, (0.5 if k == 1 else -1.1))
			var tilt := Basis(Vector3.UP, deco.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, deco.randf_range(-0.2, 0.2))
			var stone := put(heap, "Boulder", "rock", size, at, tilt, MapBlock.Shape.BEVEL)
			stone.bevel = minf(size.x, size.y) * 0.28
			stone.solid = big
			stone.tint = grey(shade * deco.randf_range(0.85, 1.0))
		obstacles[name].append([p.x, p.y, 1.9])
		made += 1


## Bits of rock floating beside and below an island, broken off it: they ride its bob.
## Clear of the pads. Drawn only.
func fragments(name: String) -> void:
	var c := centre(name)
	var g := group(island_nodes[name].get_node("Ground"), "Fragments")
	var made := 0
	for attempt in 80:
		if made >= 4:
			break
		var a := deco.randf_range(0.0, TAU)
		var w := deco.randf_range(0.6, 1.5)
		var r := deck_reach(name, Vector3(cos(a), 0, sin(a))) + deco.randf_range(0.8, 3.0)
		var at := V(cos(a) * r, deco.randf_range(-8.0, -3.0), sin(a) * r)
		var m := Vector2(c.x + at.x, c.z + at.z)
		var free := true
		for p in pads_drawn:
			if m.distance_to(Vector2(p[0].x, p[0].z)) < float(p[1]) * 0.5 + w * 0.5 + 2.5:
				free = false
				break
		if not free:
			continue
		var f := group(g, "Fragment", Transform3D(Basis(Vector3.UP, deco.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, deco.randf_range(-0.25, 0.25)), at))
		f.set_meta("_edit_group_", true)
		var sides := deco.randi_range(5, 6)
		var shade := grey(deco.randf_range(0.75, 1.0))
		var top := put(f, "Top", "rock", Vector3(w, w * 0.4, w), V(0, w * 0.2, 0), Basis.IDENTITY, MapBlock.Shape.CONE)
		top.sides = sides
		top.top = w * 0.45
		top.solid = false
		top.tint = shade
		var under := hung_cone(f, "Under", "rock", V(0, 0, 0), w, w * deco.randf_range(0.9, 1.5), w * 0.08, sides, 0.0)
		under.tint = shade
		made += 1


## An island's meadow, painted last so it keeps off everything else (see meadow()).
func foliage(name: String) -> void:
	meadow(name)


## Patches of meadow painted on an island's grass: darker ones and sunnier ones, each
## a few overlapping rounds (an odd, soft shape) wholly on the deck and off the paved
## floors. (The two sorts stand a different hair's breadth off the grass, so where
## they overlap neither flickers.)
func meadow(name: String) -> void:
	var g := group(island_nodes[name], "Meadow")
	var reach_all := island_reach(name)
	var want: int = (ISLANDS[name][1] as Array).size() * 3
	var made := 0
	for attempt in 600:
		if made >= want:
			break
		var p := Vector2(deco.randf_range(-1.0, 1.0), deco.randf_range(-1.0, 1.0)) * reach_all
		var r := deco.randf_range(1.8, 3.6)
		if not patch_fits(name, p, r):
			continue
		var sunny := made % 3 == 2
		var patch := group(g, "Patch", Transform3D(Basis.IDENTITY, V(p.x, 0, p.y)))
		patch.set_meta("_edit_group_", true)
		var rounds := [[Vector2.ZERO, r]]
		for k in 3:
			var off := Vector2.from_angle(deco.randf_range(0.0, TAU)) * r * deco.randf_range(0.55, 0.95)
			var r2 := r * deco.randf_range(0.5, 0.8)
			if patch_fits(name, p + off, r2):
				rounds.append([off, r2])
		for round in rounds:
			var off: Vector2 = round[0]
			var disc := cyl(patch, "Round", "grass_light" if sunny else "grass", V(off.x, 0, off.y), float(round[1]) * 2.0, 0.034 if sunny else 0.02, 12, deco.randf_range(0.0, TAU))
			disc.solid = false
			if not sunny:
				disc.tint = GRASS_DARK
		made += 1


## Is a round of meadow `r` across its middle at `p` (an island's frame) wholly on the
## deck and off the paved floors?
func patch_fits(name: String, p: Vector2, r: float) -> bool:
	if HOLES.has(name) and p.length() < float(HOLES[name]) * 0.5 + APRON + r + 0.2:
		return false   # (on the worn ground round the hole, or over the hole)
	if not on_deck(name, p):
		return false
	for k in 10:
		if not on_deck(name, p + Vector2.from_angle(TAU * k / 10.0) * (r + 0.4)):
			return false
	var island: Node3D = island_nodes[name]
	for pv in paved:
		var holder: Node = pv[0]
		if (holder == island or island.is_ancestor_of(holder)) and (pv[1] as Rect2).grow(r + 0.1).has_point(p):
			return false
	return true


## Room to grow something `r` across at `p` (an island's frame): on the deck, clear of
## the ruins and cover, off paved floors, and `keep` metres (or more) off the spots the
## foliage keeps clear of.
func spot_ok(name: String, p: Vector2, r: float, keep: float) -> bool:
	if not clear_spot(name, p, r):
		return false
	var island: Node3D = island_nodes[name]
	for pv in paved:
		var holder: Node = pv[0]
		if (holder == island or island.is_ancestor_of(holder)) and (pv[1] as Rect2).grow(r).has_point(p):
			return false
	if keep > 0.0:
		var c := centre(name)
		var m := Vector2(c.x + p.x, c.z + p.y)
		for k in keep_clear:
			if m.distance_to(Vector2(k[0], k[1])) < float(k[2]) + keep + r:
				return false
	return true




## Prints the least open sky between a pad's top, as drawn, and any island's deck, as
## drawn (the pads were laid out against on_island, before the decks had 16 sides: see
## on_deck), and warns of any pad closer than 0.4 m. (The closest, by the Garden, is
## 0.45 m: the parts only move up and down, so they never touch.)
func pad_clearance() -> void:
	var least := INF
	for p in pads_drawn:
		var at: Vector3 = p[0]
		var d: float = p[1]
		var sides: int = p[2]
		var turn: float = p[3]
		var half := PI / sides
		var mine := INF
		for k in 72:
			var theta := TAU * k / 72.0
			var a := fposmod(theta + turn - half, 2.0 * half) - half
			var r := d * 0.5 * cos(half) / cos(a)
			var dir := Vector2.from_angle(theta)
			var g := 0.0
			while g < 3.0:
				var q := Vector2(at.x, at.z) + dir * (r + g)
				var hit := false
				for name in ISLANDS:
					var c := centre(name)
					if on_deck(name, q - Vector2(c.x, c.z)):
						hit = true
						break
				if hit:
					break
				g += 0.05
			mine = minf(mine, g)
		least = minf(least, mine)
		if mine < 0.4:
			print("  WARNING: a pad at %s is only %.2f m from an island" % [at.snapped(Vector3.ONE * 0.1), mine])
	print("  pads: the least open sky between a pad and an island is %.2f m" % least)
