extends SceneTree
## Flicker check: no two surfaces of different colours lie in the same plane where
## both can be seen. The renderer cannot tell which of two such surfaces is in front,
## so the spot flickers between the two colours as the camera moves ("z-fighting").
##
## It looks at every drawn face of every block (boxes at any angle, cylinders, tubes
## and cones, every side, not only floors), pairs up the ones that face the same way
## in the same plane, and fails if two of different kind or tint overlap somewhere
## that no other block covers. It also fails if a sign (Label3D) lies in the surface
## of the wall behind it. (The check itself is addons/map_tools/map_flicker.gd, which
## the Map dock's Problems list also uses.)
##
## Run: godot --headless --path . --script tests/map_flicker_test.gd
## Other maps: FLICKER_MAPS="office,halcyon" (or "all"); FLICKER_LIST=40 prints more
## of what it found; FLICKER_GAP=0.02 also reports surfaces closer than 2 cm (they
## can still flicker far away on the Compatibility renderer).

const MapFlicker := preload("res://addons/map_tools/map_flicker.gd")

## The maps this test holds to it.
const MAPS := ["castle", "castle_v2", "rail_yard", "lost_temple", "neon_arcade", "sky_island", "haunted_house"]

var failures := 0
var _gap := MapFlicker.SAME_PLANE
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
		_gap = maxf(float(OS.get_environment("FLICKER_GAP")), MapFlicker.SAME_PLANE)
	if OS.get_environment("FLICKER_LIST") != "":
		_list = int(OS.get_environment("FLICKER_LIST"))
	for id in ids:
		_check(id)
	print("FAIL: %d checks failed" % failures if failures else "PASS: every check passed")
	quit(1 if failures else 0)


func _check(id: String) -> void:
	var map := Maps.make(id)
	root.add_child(map)
	var found := MapFlicker.check(map, _gap)
	var clashes: Array = found.clashes.map(func(c: Dictionary) -> String: return c.text)
	print("  %s: %d surfaces, %d signs" % [Maps.name_of(id), found.surfaces, found.signs])
	_expect(clashes.is_empty(), "no two surfaces of different colours share a plane where both show (%d found) %s" % [clashes.size(), _some(clashes)])
	if _gap > MapFlicker.SAME_PLANE:
		var near: Array = found.near.map(func(c: Dictionary) -> String: return c.text)
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


func _expect(ok: bool, what: String) -> void:
	print("    %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1
