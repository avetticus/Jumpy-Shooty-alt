@tool
extends RefCounted
## What the Map dock's Problems list finds in a map, each with what to select to fix
## it. No editor in it, so tests/map_tools_test.gd can check it.
##
##  - every block's own warnings (the ones the Scene dock shows with a yellow sign): a
##    kind missing from the palette, a hull with no volume or too many corners, a block
##    too thick to break per cell, a material or break setting that does not exist;
##  - blocks smaller than a centimetre (left over from a cut or a drag);
##  - too few spawn points, and spawn points outside the map's bounds;
##  - terminals whose event cannot be found;
##  - (when asked: it takes a while on a big map) surfaces that flicker, two colours in
##    one plane where both show (MapFlicker).

const MapOps := preload("res://addons/map_tools/map_ops.gd")
const MapFlicker := preload("res://addons/map_tools/map_flicker.gd")

const TINY := 0.01            # metres: a block this thin anywhere is a leftover
const FEWEST_SPAWNS := 8      # an arena needs this many (a race 5)


## The problems in `map` (in the scene tree): [{text, nodes: what to select}], the
## worst first. `flicker`: also look for flickering surfaces.
static func find(map: MapRoot, flicker := false) -> Array:
	var out := []
	var root_path := func(n: Node) -> String: return String(map.get_path_to(n))
	for b: MapBlock in MapOps.blocks_in(map):
		for w in b._get_configuration_warnings():
			out.append({"text": "%s: %s" % [root_path.call(b), w], "nodes": [b]})
		var size := b.size * MapOps.global_of(b).basis.get_scale().abs()
		if minf(size.x, minf(size.y, size.z)) < TINY:
			out.append({"text": "%s: smaller than a centimetre (%s m); a leftover from a cut or a drag?" % [root_path.call(b), size.snappedf(0.001)], "nodes": [b]})
	var spawns := map.find_children("*", "MapSpawn", true, false)
	if spawns.size() < FEWEST_SPAWNS:
		out.append({"text": "Only %d spawn points: an arena needs %d (a race 5)." % [spawns.size(), FEWEST_SPAWNS], "nodes": spawns})
	if map.bounds.has_area():
		for s in spawns:
			var at := MapOps.global_of(s).origin
			if not map.bounds.has_point(Vector2(at.x, at.z)):
				out.append({"text": "%s: outside the map's bounds." % root_path.call(s), "nodes": [s]})
	for t in map.find_children("*", "MapTerminal", true, false):
		var terminal := t as MapTerminal
		if terminal.event.is_empty() or terminal.get_node_or_null(terminal.event) == null:
			out.append({"text": "%s: its event (\"%s\") cannot be found." % [root_path.call(terminal), terminal.event], "nodes": [terminal]})
	if flicker:
		for clash in MapFlicker.check(map).clashes:
			out.append({"text": "Flickers: " + clash.text, "nodes": _near(map, clash.at, clash.kinds)})
	return out


## The blocks of these kinds whose box takes in `at` (in the map's frame).
static func _near(map: MapRoot, at: Vector3, kinds: Array) -> Array:
	var out := []
	var to_map := MapOps.global_of(map).affine_inverse()
	for b: MapBlock in MapOps.blocks_in(map):
		if b.kind in kinds:
			var box := MapOps.bounds_of([b])
			if AABB(to_map * box.position, box.size).grow(0.02).has_point(at):
				out.append(b)
	return out
