class_name HudStyle
extends RefCounted
## Colours, font and small drawing helpers shared by every part of the in-game HUD.
## Everything is drawn in code (no textures), with a dark edge under each shape
## and each line of text so it reads on bright and dark backgrounds alike.
## The look: plates with two corners cut off, thin lines, gauges with a soft glow.

const WHITE := Color(1, 1, 1, 0.95)
const DIM := Color(1, 1, 1, 0.25)
const EDGE := Color(0, 0, 0, 0.45)
const PANEL := Color(0.03, 0.045, 0.07, 0.62)
const LINE := Color(0.55, 0.85, 1.0, 0.35)   ## thin lines round plates
const CYAN := Color(0.4, 0.9, 1.0)
const ORANGE := Color(1.0, 0.54, 0.24)
const RED := Color(1.0, 0.29, 0.24)
const YELLOW := Color(1.0, 0.85, 0.29)

const LOW_HEALTH := 30.0   ## at or below this the health readouts turn red

static var _fonts := {}


## Chakra Petch (SIL Open Font License, see fonts/OFL.txt).
static func font(bold: bool = true) -> Font:
	var key := "Bold" if bold else "SemiBold"
	if not _fonts.has(key):
		_fonts[key] = load("res://game/ui/fonts/ChakraPetch-%s.ttf" % key)
	return _fonts[key]


## Text with a soft dark outline. `pos` is the anchor point: its x is the left
## edge, centre or right edge (by `align`), and its y is the vertical middle.
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, color: Color = WHITE,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, bold: bool = true) -> float:
	var f := font(bold)
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	var baseline := pos.y + (f.get_ascent(size) - f.get_descent(size)) * 0.5
	var edge := Color(0, 0, 0, 0.6 * color.a)
	ci.draw_string_outline(f, Vector2(x, baseline), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 2 if size < 16 else max(3, size / 6), edge)
	ci.draw_string(f, Vector2(x, baseline), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return w


## The bold face with extra space between letters, for small capitals.
static func font_spaced(extra: int = 2) -> Font:
	var key := "Spaced%d" % extra
	if not _fonts.has(key):
		var v := FontVariation.new()
		v.base_font = font(true)
		v.spacing_glyph = extra
		_fonts[key] = v
	return _fonts[key]


static func text_width(s: String, size: int, bold: bool = true) -> float:
	return font(bold).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## An arc between two angles in degrees (0 = right, 90 = down, clockwise).
static func arc(ci: CanvasItem, c: Vector2, r: float, from_deg: float, to_deg: float, color: Color, width: float) -> void:
	if absf(to_deg - from_deg) < 0.05:
		return
	var points := maxi(4, int(absf(to_deg - from_deg) / 3.0))
	ci.draw_arc(c, r, deg_to_rad(from_deg), deg_to_rad(to_deg), points, color, width, true)


## An arc with a dark edge under it.
static func edged_arc(ci: CanvasItem, c: Vector2, r: float, from_deg: float, to_deg: float, color: Color, width: float) -> void:
	arc(ci, c, r, from_deg, to_deg, Color(0, 0, 0, EDGE.a * minf(color.a / 0.95, 1.0)), width + 3.0)
	arc(ci, c, r, from_deg, to_deg, color, width)


static func edged_rect(ci: CanvasItem, r: Rect2, color: Color) -> void:
	ci.draw_rect(r.grow(1.5), EDGE)
	ci.draw_rect(r, color)


## A dark plate behind text, with two corners cut off (top left and bottom right).
## `radius` is the size of the cut.
static func plate(ci: CanvasItem, r: Rect2, radius: float = 4.0, color: Color = PANEL) -> void:
	ci.draw_colored_polygon(cut_points(r, minf(radius, 9.0)), color)


## The outline of a rectangle with its top-left and bottom-right corners cut off.
static func cut_points(r: Rect2, cut: float) -> PackedVector2Array:
	cut = minf(cut, minf(r.size.x, r.size.y) * 0.5)
	return PackedVector2Array([
		r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y - cut),
		r.end - Vector2(cut, 0), Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut)])


## A cut-corner plate with a thin line round it.
static func framed_plate(ci: CanvasItem, r: Rect2, cut: float, fill: Color, line: Color, width: float = 1.0) -> void:
	var pts := cut_points(r, cut)
	ci.draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	ci.draw_polyline(pts, line, width, true)


## A plate leaning over: `slant` pixels further right at the top than at the bottom
## (negative leans the other way).
static func slant_plate(ci: CanvasItem, r: Rect2, slant: float, color: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([
		r.position + Vector2(slant, 0), Vector2(r.end.x + slant, r.position.y),
		r.end, Vector2(r.position.x, r.end.y)]), color)


## Four corner brackets round a rectangle (a targeting frame).
static func brackets(ci: CanvasItem, r: Rect2, arm: float, color: Color, width: float = 2.0) -> void:
	for corner in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)],
			[r.end, Vector2(-1, -1)], [Vector2(r.position.x, r.end.y), Vector2(1, -1)]]:
		var p: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		ci.draw_polyline(PackedVector2Array([p + Vector2(arm * d.x, 0), p, p + Vector2(0, arm * d.y)]), color, width, true)


## An arc with a soft halo of its own colour under it, and a dark edge under that.
static func glow_arc(ci: CanvasItem, c: Vector2, r: float, from_deg: float, to_deg: float, color: Color, width: float,
		glow: Color = Color(0, 0, 0, 0)) -> void:
	if absf(to_deg - from_deg) < 0.05:
		return
	if glow.a <= 0.0:
		glow = color
	arc(ci, c, r, from_deg, to_deg, Color(glow, 0.16 * color.a), width + 8.0)
	arc(ci, c, r, from_deg, to_deg, Color(0, 0, 0, EDGE.a * minf(color.a / 0.95, 1.0)), width + 3.0)
	arc(ci, c, r, from_deg, to_deg, color, width)


## A short line across an arc at `deg` (the ends of a gauge).
static func tick(ci: CanvasItem, c: Vector2, r0: float, r1: float, deg: float, color: Color, width: float = 1.5) -> void:
	var d := Vector2.from_angle(deg_to_rad(deg))
	ci.draw_line(c + d * r0, c + d * r1, color, width, true)


## Small capitals with wide letter spacing (labels on gauges and panels).
static func label(ci: CanvasItem, pos: Vector2, s: String, size: int = 10, color: Color = Color(1, 1, 1, 0.7),
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> float:
	var f := font_spaced()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	var baseline := pos.y + (f.get_ascent(size) - f.get_descent(size)) * 0.5
	ci.draw_string_outline(f, Vector2(x, baseline), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, 0.55 * color.a))
	ci.draw_string(f, Vector2(x, baseline), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return w


## A small pistol silhouette (kill feed).
static func pistol(ci: CanvasItem, at: Vector2, color: Color, s: float = 1.0) -> void:
	var pts := PackedVector2Array([
		Vector2(0, 0), Vector2(19, 0), Vector2(19, 4), Vector2(10, 4), Vector2(9, 9),
		Vector2(5, 9), Vector2(6, 4), Vector2(0, 4)])
	for i in pts.size():
		pts[i] = at + pts[i] * s
	ci.draw_colored_polygon(pts, color)


## A headshot (kill feed, death screen): a robot's head, visor slit across it, with a
## hit bursting on its left side (the gun's side in the feed) and a crack running in
## from it. Both places draw it white, like the feed's weapon icons; its dark edge
## keeps it readable on light backgrounds. `at` is the top left; it is
## headshot_width() across and 16 tall at size 1. Returns its width.
static func headshot_icon(ci: CanvasItem, at: Vector2, color: Color, s: float = 1.0) -> float:
	var edge := Color(0, 0, 0, 0.6 * color.a)
	var cut := Color(0, 0, 0, 0.8 * color.a)   # holes in the head: the visor and the crack
	var head := [Vector2(9, 3), Vector2(19, 3), Vector2(21, 5), Vector2(21, 14), Vector2(19, 16),
		Vector2(9, 16), Vector2(7, 14), Vector2(7, 5)]
	var antenna := [Vector2(13.3, 0.5), Vector2(14.7, 0.5), Vector2(14.7, 3.5), Vector2(13.3, 3.5)]
	var visor := [Vector2(11, 7), Vector2(19.5, 7), Vector2(19.5, 9.5), Vector2(11, 9.5)]
	var crack := [Vector2(9.5, 10), Vector2(12.5, 11.5), Vector2(12, 12.5), Vector2(14.5, 14.8), Vector2(11.2, 12.8),
		Vector2(11.6, 11.9), Vector2(9.2, 10.8)]
	var burst := []   # a fat star: thin sparks blur into a smudge at 14 px, a solid star still reads
	for i in 14:
		var r: float = (5.4 if i % 4 == 0 else 4.4) if i % 2 == 0 else 2.5
		burst.append(Vector2(5.2, 9.5) + Vector2.from_angle(TAU * i / 14.0 + PI) * r)
	# Edges under fills, so no edge covers the head's own fill.
	for shape in [head, antenna]:
		_edged_shape(ci, at, shape, s, color, edge, true)
	for shape in [head, antenna]:
		_edged_shape(ci, at, shape, s, color, edge, false)
	for shape in [visor, crack]:
		ci.draw_colored_polygon(_placed(at, shape, s), cut)
	# The burst's own edge cuts it out of the head behind it.
	_edged_shape(ci, at, burst, s, color, edge, true)
	_edged_shape(ci, at, burst, s, color, edge, false)
	return headshot_width() * s


## How wide the headshot icon is at size 1 (it is 16 tall).
static func headshot_width() -> float:
	return 21.0


## An icon's shape (points at size 1) scaled by `s` and moved to `at`.
static func _placed(at: Vector2, shape: Array, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in shape:
		pts.append(at + p * s)
	return pts


## One shape of an icon: its dark edge (grown 1.5 px all round) or its fill.
static func _edged_shape(ci: CanvasItem, at: Vector2, shape: Array, s: float, color: Color, edge: Color, under: bool) -> void:
	var pts := _placed(at, shape, s)
	if not under:
		ci.draw_colored_polygon(pts, color)
		return
	for grown in Geometry2D.offset_polygon(pts, 1.5, Geometry2D.JOIN_MITER):
		ci.draw_colored_polygon(grown, edge)


## A small silhouette of a gun, barrel to the right (kill feed, death screen). Returns its width.
static func weapon_icon(ci: CanvasItem, id: String, at: Vector2, color: Color, s: float = 1.0) -> float:
	id = WeaponData.look_of(id)   # (the Golden Gun: the revolver)
	var shapes := []
	match id:
		"shotgun":
			shapes = [[Vector2(0, 1), Vector2(9, 0), Vector2(36, 0), Vector2(36, 3), Vector2(13, 4), Vector2(11, 9),
				Vector2(8, 9), Vector2(9, 4), Vector2(0, 6)], [Vector2(18, 4), Vector2(28, 4), Vector2(28, 7), Vector2(18, 7)]]
		"rifle":
			shapes = [[Vector2(0, 1), Vector2(8, 0), Vector2(34, 0), Vector2(34, 2.5), Vector2(28, 3), Vector2(28, 5),
				Vector2(18, 5), Vector2(17, 11), Vector2(14, 11), Vector2(14, 5), Vector2(11, 5), Vector2(10, 9),
				Vector2(7, 9), Vector2(8, 5), Vector2(0, 6)]]
		"sword":   # blade to the right, the guard's wings swept toward the point
			shapes = [[Vector2(0, 3), Vector2(9, 3), Vector2(9, 5), Vector2(0, 5)],
				[Vector2(-2, 2.4), Vector2(0, 2.4), Vector2(0, 5.6), Vector2(-2, 5.6)],
				[Vector2(8, 2.5), Vector2(9, -1.5), Vector2(12.5, -3), Vector2(11, 0), Vector2(10.5, 2.5)],
				[Vector2(8, 5.5), Vector2(10.5, 5.5), Vector2(11, 8), Vector2(12.5, 11), Vector2(9, 9.5)],
				[Vector2(10.5, 2), Vector2(13, 1.2), Vector2(34, 1.8), Vector2(40, 4), Vector2(34, 6.2), Vector2(13, 6.8), Vector2(10.5, 6)]]
		"hammer":   # a block of a head with a strike face at each end
			shapes = [[Vector2(0, 3), Vector2(24, 3), Vector2(24, 5), Vector2(0, 5)],
				[Vector2(-1.5, 2.2), Vector2(0, 2.2), Vector2(0, 5.8), Vector2(-1.5, 5.8)],
				[Vector2(23, -1), Vector2(31, -1), Vector2(31, 9), Vector2(23, 9)],
				[Vector2(22, -4.5), Vector2(32, -4.5), Vector2(32, -1.8), Vector2(22, -1.8)],
				[Vector2(22, 9.8), Vector2(32, 9.8), Vector2(32, 12.5), Vector2(22, 12.5)]]
		"revolver":
			shapes = [[Vector2(0, 1), Vector2(26, 1), Vector2(26, 3.5), Vector2(11, 3.5), Vector2(10, 5),
				Vector2(5, 10), Vector2(1, 10), Vector2(3, 4), Vector2(0, 4)], [Vector2(6, 0), Vector2(12, 0), Vector2(12, 5), Vector2(6, 5)]]
		"machine_pistol":
			shapes = [[Vector2(0, 0), Vector2(21, 0), Vector2(21, 4), Vector2(9, 4), Vector2(8, 15), Vector2(5, 15),
				Vector2(5, 4), Vector2(0, 4)], [Vector2(15, 4), Vector2(17, 4), Vector2(17, 8), Vector2(15, 8)]]
		"akimbo":   # two pistols, one behind and above the other
			for off in [Vector2(6, -5), Vector2(0, 0)]:
				shapes.append([Vector2(0, 0) + off, Vector2(18, 0) + off, Vector2(18, 4) + off, Vector2(9.5, 4) + off,
					Vector2(8.5, 9) + off, Vector2(5, 9) + off, Vector2(5.5, 4) + off, Vector2(0, 4) + off])
		"break_action":
			shapes = [[Vector2(0, 2), Vector2(10, 1), Vector2(40, 0), Vector2(40, 3.5), Vector2(14, 4), Vector2(12, 9),
				Vector2(9, 9), Vector2(10, 4.5), Vector2(0, 7)], [Vector2(15, 3.5), Vector2(28, 3.5), Vector2(28, 6), Vector2(15, 6)]]
		"burst_rifle":
			shapes = [[Vector2(0, 1), Vector2(8, 0), Vector2(36, 0), Vector2(38, 2), Vector2(36, 4.5), Vector2(19, 5),
				Vector2(18, 10), Vector2(15, 10), Vector2(15, 5), Vector2(11, 5), Vector2(10, 9), Vector2(7, 9),
				Vector2(8, 5), Vector2(0, 6)], [Vector2(12, -3), Vector2(22, -3), Vector2(22, 0), Vector2(12, 0)]]
		"lmg":
			shapes = [[Vector2(0, 1), Vector2(8, 0), Vector2(46, 0.5), Vector2(46, 3), Vector2(28, 3.5), Vector2(28, 5),
				Vector2(12, 5), Vector2(11, 9), Vector2(8, 9), Vector2(9, 5), Vector2(0, 6)],
				[Vector2(13, 5), Vector2(23, 5), Vector2(23, 12), Vector2(13, 12)], [Vector2(14, -3), Vector2(24, -3), Vector2(24, -1), Vector2(14, -1)]]
		"lever_action":
			shapes = [[Vector2(0, 2), Vector2(9, 1), Vector2(42, 0.5), Vector2(42, 2.5), Vector2(14, 3.5), Vector2(12, 5),
				Vector2(0, 6.5)], [Vector2(9, 4.5), Vector2(15, 4.5), Vector2(15, 9), Vector2(9, 9)], [Vector2(16, 3), Vector2(30, 3), Vector2(30, 5), Vector2(16, 5)]]
		"railgun":
			shapes = [[Vector2(0, 1), Vector2(10, -1), Vector2(44, -1), Vector2(44, 1), Vector2(18, 1), Vector2(18, 3),
				Vector2(44, 3), Vector2(44, 5), Vector2(15, 5), Vector2(14, 10), Vector2(11, 10), Vector2(11, 5), Vector2(0, 6)]]
		"rocket_launcher":
			shapes = [[Vector2(0, -1), Vector2(44, -1), Vector2(46, 0), Vector2(46, 5), Vector2(44, 6), Vector2(0, 6), Vector2(-2, 7), Vector2(-2, -2)],
				[Vector2(14, 6), Vector2(17, 6), Vector2(17, 11), Vector2(14, 11)], [Vector2(26, 6), Vector2(29, 6), Vector2(29, 10), Vector2(26, 10)]]
		"grenade_launcher":
			shapes = [[Vector2(0, 2), Vector2(8, 1), Vector2(14, 1), Vector2(14, 5), Vector2(11, 5), Vector2(10, 10),
				Vector2(7, 10), Vector2(8, 5), Vector2(0, 6)], [Vector2(13, -2), Vector2(23, -2), Vector2(23, 8), Vector2(13, 8)],
				[Vector2(23, 0), Vector2(36, 0), Vector2(36, 5), Vector2(23, 5)]]
		"brass_knuckles":
			shapes = [[Vector2(0, 0), Vector2(18, 0), Vector2(18, 4), Vector2(0, 4)], [Vector2(1, 4), Vector2(17, 4), Vector2(14, 9), Vector2(4, 9)],
				[Vector2(1, -3), Vector2(4, -3), Vector2(4, 0), Vector2(1, 0)], [Vector2(5.5, -3), Vector2(8.5, -3), Vector2(8.5, 0), Vector2(5.5, 0)],
				[Vector2(10, -3), Vector2(13, -3), Vector2(13, 0), Vector2(10, 0)], [Vector2(14.5, -3), Vector2(17.5, -3), Vector2(17.5, 0), Vector2(14.5, 0)]]
		"spear":   # a leaf of a head, two fins swept back under it
			shapes = [[Vector2(0, 3.2), Vector2(41, 3.2), Vector2(41, 4.8), Vector2(0, 4.8)],
				[Vector2(-3, 4), Vector2(0, 2.6), Vector2(0, 5.4)],
				[Vector2(41.5, 3.2), Vector2(37, 1.8), Vector2(32.5, -1), Vector2(36, 0), Vector2(40, 2)],
				[Vector2(41.5, 4.8), Vector2(40, 6), Vector2(36, 8), Vector2(32.5, 9), Vector2(37, 6.2)],
				[Vector2(41, 3), Vector2(45, 0.8), Vector2(47.5, 1.2), Vector2(54, 4), Vector2(47.5, 6.8), Vector2(45, 7.2), Vector2(41, 5)]]
		"bat":
			shapes = [[Vector2(0, 3), Vector2(10, 3), Vector2(34, 1.5), Vector2(38, 2.5), Vector2(38, 5.5), Vector2(34, 6.5),
				Vector2(10, 5), Vector2(0, 5)], [Vector2(-1.5, 2), Vector2(0.5, 2), Vector2(0.5, 6), Vector2(-1.5, 6)]]

		# The third batch
		"air_cannon":   # a wide barrel flaring into a bell, the tank underneath
			shapes = [[Vector2(0, 1), Vector2(8, 0), Vector2(30, -1), Vector2(36, -4), Vector2(36, 8), Vector2(30, 5),
				Vector2(12, 5), Vector2(11, 10), Vector2(8, 10), Vector2(9, 5), Vector2(0, 6)],
				[Vector2(13, 6), Vector2(28, 6), Vector2(28, 9), Vector2(13, 9)]]
		"minigun":   # a bundle of barrels out of a big housing
			shapes = [[Vector2(0, 0), Vector2(18, -2), Vector2(18, 8), Vector2(12, 8), Vector2(11, 12), Vector2(8, 12),
				Vector2(9, 8), Vector2(0, 6)], [Vector2(18, -1), Vector2(48, -1), Vector2(48, 1), Vector2(18, 1)],
				[Vector2(18, 2), Vector2(48, 2), Vector2(48, 4), Vector2(18, 4)], [Vector2(18, 5), Vector2(48, 5), Vector2(48, 7), Vector2(18, 7)],
				[Vector2(24, -2), Vector2(27, -2), Vector2(27, 8), Vector2(24, 8)], [Vector2(40, -2), Vector2(42, -2), Vector2(42, 8), Vector2(40, 8)]]
		"battle_rifle":
			shapes = [[Vector2(0, 1), Vector2(8, 0), Vector2(40, 0), Vector2(40, 2.5), Vector2(30, 3), Vector2(30, 5),
				Vector2(17, 5), Vector2(17, 11), Vector2(14, 11), Vector2(14, 5), Vector2(11, 5), Vector2(10, 9),
				Vector2(7, 9), Vector2(8, 5), Vector2(0, 6)], [Vector2(11, -3.5), Vector2(21, -3.5), Vector2(21, -0.5), Vector2(11, -0.5)]]
		"crossbow":   # the stock, and the bow seen across the front
			shapes = [[Vector2(0, 2), Vector2(8, 1), Vector2(34, 1), Vector2(34, 4), Vector2(12, 4), Vector2(11, 9),
				Vector2(8, 9), Vector2(9, 4), Vector2(0, 7)], [Vector2(31, -6), Vector2(34, -6), Vector2(36, 2.5), Vector2(34, 11),
				Vector2(31, 11), Vector2(33, 2.5)], [Vector2(12, 0), Vector2(40, 0), Vector2(40, 1), Vector2(12, 1)]]
		"anti_materiel":   # very long, a muzzle brake, a big scope
			shapes = [[Vector2(0, 2), Vector2(8, 1), Vector2(28, 1), Vector2(50, 1.5), Vector2(50, 0), Vector2(54, 0),
				Vector2(54, 4.5), Vector2(50, 4.5), Vector2(50, 3), Vector2(28, 3.5), Vector2(26, 5), Vector2(19, 5),
				Vector2(19, 10), Vector2(15, 10), Vector2(15, 5), Vector2(12, 5), Vector2(11, 9), Vector2(8, 9), Vector2(9, 5), Vector2(0, 7)],
				[Vector2(10, -4), Vector2(25, -4), Vector2(25, 0), Vector2(10, 0)]]
		"energy_sword":   # a hilt and a long, even blade of light
			shapes = [[Vector2(0, 2.5), Vector2(10, 2.5), Vector2(10, 5.5), Vector2(0, 5.5)],
				[Vector2(10, 1.5), Vector2(12, 1.5), Vector2(12, 6.5), Vector2(10, 6.5)],
				[Vector2(12, 2.6), Vector2(39, 2.6), Vector2(42, 4), Vector2(39, 5.4), Vector2(12, 5.4)]]

		"none":   # a boot (Deathmatch: killed with a kick, or a crash, before finding a weapon)
			shapes = [[Vector2(2, -2), Vector2(9, -2), Vector2(9, 5), Vector2(19, 6), Vector2(21, 10), Vector2(2, 10)]]
		_:
			pistol(ci, at, color, s)
			return 19.0 * s
	var width := 0.0
	for shape in shapes:
		var pts := PackedVector2Array()
		for p in shape:
			pts.append(at + p * s)
			width = maxf(width, p.x * s)
		ci.draw_colored_polygon(pts, color)
	return width


## How wide a weapon's icon is at size 1 (to centre it).
static func weapon_width(id: String) -> float:
	id = WeaponData.look_of(id)
	return {"shotgun": 40.0, "rifle": 38.0, "sword": 40.0, "hammer": 32.0,
		"revolver": 26.0, "machine_pistol": 21.0, "akimbo": 24.0, "break_action": 40.0, "burst_rifle": 38.0, "lmg": 46.0,
		"lever_action": 42.0, "railgun": 44.0, "rocket_launcher": 46.0, "grenade_launcher": 36.0,
		"brass_knuckles": 18.0, "spear": 54.0, "bat": 38.0,
		"air_cannon": 36.0, "minigun": 48.0, "battle_rifle": 40.0, "crossbow": 40.0,
		"anti_materiel": 54.0, "energy_sword": 42.0}.get(id, 22.0)


## Widths at size 1 of the icons below.
const FLYING_KICK_W := 35.0
const HOOK_W := 33.0
const WALL_W := 22.0


## What made a kill (Match.death_fx "with": a WeaponData id, "kick", "flying_kick",
## "rope" or "none"), as a kill feed icon. Returns its width.
static func kill_icon(ci: CanvasItem, with: String, at: Vector2, color: Color, s: float = 1.0) -> float:
	match with:
		"kick":
			return weapon_icon(ci, "none", at, color, s)   # the boot
		"flying_kick":
			return flying_kick(ci, at, color, s)
		"rope":
			return grapple_hook(ci, at, color, s)
	return weapon_icon(ci, with, at, color, s)


## How wide kill_icon is at size 1.
static func kill_icon_width(with: String) -> float:
	match with:
		"kick":
			return weapon_width("none")
		"flying_kick":
			return FLYING_KICK_W
		"rope":
			return HOOK_W
	return weapon_width(with)


## The kick's boot tipped up into a flying kick, speed lines trailing behind it.
static func flying_kick(ci: CanvasItem, at: Vector2, color: Color, s: float = 1.0) -> float:
	var boot := []
	for p in [Vector2(2, -2), Vector2(9, -2), Vector2(9, 5), Vector2(19, 6), Vector2(21, 10), Vector2(2, 10)]:   # (weapon_icon's "none")
		boot.append((p - Vector2(11.5, 4)).rotated(deg_to_rad(-15.0)) + Vector2(24, 3.5))
	return _polygons(ci, [boot,
		[Vector2(0, 0.5), Vector2(8, 0.5), Vector2(9, 2), Vector2(1, 2)],
		[Vector2(2, 4.2), Vector2(11, 4.2), Vector2(12, 5.7), Vector2(3, 5.7)],
		[Vector2(1, 7.9), Vector2(9, 7.9), Vector2(10, 9.4), Vector2(2, 9.4)]], at, color, s)


## A grappling hook on the end of its rope, points to the right (reeled in by a grapple).
static func grapple_hook(ci: CanvasItem, at: Vector2, color: Color, s: float = 1.0) -> float:
	var rope := []
	for i in 7:   # a slack, wavy rope
		rope.append(Vector2(i * 2.0, 4.0 + (1.2 if i % 2 == 1 else -0.2)))
	for i in range(6, -1, -1):
		rope.append(Vector2(i * 2.0, 5.4 + (1.2 if i % 2 == 1 else -0.2)))
	return _polygons(ci, [rope,
		[Vector2(12, 2), Vector2(16, 2), Vector2(16, 7), Vector2(12, 7)],   # the eye
		[Vector2(16, 3.2), Vector2(28, 3.2), Vector2(28, 5.8), Vector2(16, 5.8)],   # the shank
		[Vector2(26, 3.4), Vector2(29, 1.5), Vector2(29.5, -2), Vector2(27.5, -4.5), Vector2(24, -5), Vector2(26.5, -2.5),
			Vector2(26.5, 0.5), Vector2(24.5, 3.4)],   # the prongs, bent back
		[Vector2(26, 5.6), Vector2(29, 7.5), Vector2(29.5, 11), Vector2(27.5, 13.5), Vector2(24, 14), Vector2(26.5, 11.5),
			Vector2(26.5, 8.5), Vector2(24.5, 5.6)],
		[Vector2(28, 3), Vector2(33, 4.5), Vector2(28, 6)]], at, color, s)


## A slab of wall split by cracks, a burst where something hit it from the left
## (killed by a crash into a wall).
static func wall_impact(ci: CanvasItem, at: Vector2, color: Color, s: float = 1.0) -> float:
	# The slab, cut along cracks that run out from where the blow landed, each
	# piece pulled in a little so the cracks show as gaps.
	var hit := Vector2(9, 4)
	var pieces := [
		[Vector2(9, -4), Vector2(15, -4), hit],
		[Vector2(15, -4), Vector2(22, -4), Vector2(22, 1.5), hit],
		[hit, Vector2(22, 1.5), Vector2(22, 7.5)],
		[hit, Vector2(22, 7.5), Vector2(22, 12), Vector2(16, 12)],
		[hit, Vector2(16, 12), Vector2(9, 12)]]
	var shapes := []
	for piece in pieces:
		var mid := Vector2.ZERO
		for p in piece:
			mid += p
		mid /= piece.size()
		var shrunk := []
		for p in piece:
			shrunk.append(p + (mid - p).normalized() * 0.9)
		shapes.append(shrunk)
	# The burst: an eight-pointed star against the wall's face.
	var star := []
	for i in 16:
		var a := TAU * i / 16.0
		star.append(Vector2(4.5, 4) + Vector2(cos(a), sin(a)) * (4.5 if i % 2 == 0 else 1.7))
	shapes.append(star)
	return _polygons(ci, shapes, at, color, s)


## Fill each shape (a list of points, at size 1) at `at`, scaled by `s`. Returns
## how far right they reach.
static func _polygons(ci: CanvasItem, shapes: Array, at: Vector2, color: Color, s: float) -> float:
	var width := 0.0
	for shape in shapes:
		var pts := PackedVector2Array()
		for p in shape:
			pts.append(at + p * s)
			width = maxf(width, p.x * s)
		ci.draw_colored_polygon(pts, color)
	return width


static func health_color(hp: float) -> Color:
	return RED if hp <= LOW_HEALTH else WHITE


## The crosshair at `c`, as the player set it (see HudConfig). `kind` is the weapon's
## own (WeaponData.crosshair: "spread" brackets on the shotgun's cone, a launcher's
## "ring", the marksman rifles' "dot" with ticks round it, otherwise a cross), used unless the
## options pick one shape for every weapon. `spread_px`: how far the gun's spread
## reaches on screen. At the defaults each weapon's crosshair is drawn as it always was.
static func crosshair(ci: CanvasItem, c: Vector2, kind: String, spread_px: float, cfg: HudConfig) -> void:
	var style := cfg.crosshair if cfg.crosshair != "weapon" else kind
	var col := cfg.color()
	var k := cfg.crosshair_size
	var t := cfg.crosshair_thickness
	var shift := cfg.crosshair_gap - 5.0   # further out (or in) than the weapon's own shape
	var dark := cfg.crosshair_outline
	match style:
		"spread":   # four brackets on the edge of the cone
			var r := maxf(spread_px, 12.0) + shift
			for i in 4:
				var a := 45.0 + i * 90.0
				if dark:
					arc(ci, c, r, a - 15.0 * k - 1.0, a + 15.0 * k + 1.0, Color(0, 0, 0, 0.5), t + 2.0)
				arc(ci, c, r, a - 15.0 * k, a + 15.0 * k, col, t)
		"ring":     # a circle where it will land, with a gap at the bottom
			var r := maxf(11.0 * k + shift, 3.0)
			if dark:
				arc(ci, c, r, 110.0, 430.0, Color(0, 0, 0, 0.5), t + 2.0)
			arc(ci, c, r, 110.0, 430.0, col, t)
			ci.draw_line(c + Vector2(0, r + 3.0 * k), c + Vector2(0, r + 11.0 * k), col, t)
		"dot":      # the marksman rifles: short ticks well clear of a precise dot
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				if dark:
					ci.draw_line(c + d * (9.0 + shift), c + d * (9.0 + shift + 6.0 * k), Color(0, 0, 0, 0.55), t + 2.0)
				ci.draw_line(c + d * (9.0 + shift), c + d * (9.0 + shift + 6.0 * k), col, t)
		"point":    # a dot and nothing else (drawn below)
			pass
		"circle":
			var r := maxf(cfg.crosshair_gap + 5.0 * k + spread_px * 0.6, 3.0)
			if dark:
				arc(ci, c, r, 0.0, 360.0, Color(0, 0, 0, 0.5), t + 2.0)
			arc(ci, c, r, 0.0, 360.0, col, t)
		_:          # a cross that opens up with the spread ("t": no top arm)
			var gap := cfg.crosshair_gap + spread_px * 0.6
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				if style == "t" and d == Vector2.UP:
					continue
				if dark:
					ci.draw_line(c + d * gap, c + d * (gap + 8.0 * k), Color(0, 0, 0, 0.55), t + 2.0)
				ci.draw_line(c + d * gap, c + d * (gap + 8.0 * k), col, t)
	if style == "point":
		var r := 1.25 * t * k
		if dark:
			ci.draw_circle(c, r + 1.0, Color(0, 0, 0, 0.5))
		ci.draw_circle(c, r, col)
	elif cfg.crosshair_dot:
		if style == "dot":   # the marksman dot sits on a dark disc
			if dark:
				ci.draw_circle(c, t, Color(0, 0, 0, 0.5))
			ci.draw_circle(c, 0.7 * t, col)
		else:
			ci.draw_circle(c, 0.75 * t, col)


## Lines out from the crosshair when your shot lands: white for a hit, yellow for a
## headshot, red and longer for a kill ("hit", "head", "kill").
static func hit_marker(ci: CanvasItem, c: Vector2, kind: String) -> void:
	var kill := kind == "kill"
	var col := RED if kill else (YELLOW if kind == "head" else Color.WHITE)
	var reach := 24.0 if kill else (20.0 if kind == "head" else 17.0)
	var w := 4.0 if kill else 3.0
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var n: Vector2 = d.normalized()
		ci.draw_line(c + n * 9.0, c + n * reach, Color(0, 0, 0, 0.5), w + 2.0)
		ci.draw_line(c + n * 9.0, c + n * reach, col, w)
