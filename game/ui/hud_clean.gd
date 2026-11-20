class_name HudClean
extends RefCounted
## "Clean" HUD layout: the classic corners, kept small.
## Bottom left: your moves (grapple, dive, flip, glide, slide boost, rocket boots, kick) above your health.
## Bottom right: ammo with one tick per round. Each sits on a dark plate with two
## corners cut off and a coloured edge. Under the crosshair: speed and what you are
## doing, small and faint. (Settings → HUD can leave out the moves or the speed.)

const MARGIN := 28.0
const PLATE := Vector2(336.0, 96.0)


static func draw(ci: CanvasItem, c: Vector2, v: Hud.View) -> void:
	var size := c * 2.0
	var bottom := size.y - MARGIN

	if v.race:   # a race has no health or ammo: just the moves, a little lower
		bottom += 72.0
	# Health: big number, robot name, ten segments.
	var hp_col := HudStyle.health_color(v.hp)
	if not v.race:
		_draw_health(ci, v, bottom, hp_col)
	_draw_rest(ci, c, v, size, bottom)


## The dark plate a corner readout sits on, with a coloured edge down one side.
static func _plate(ci: CanvasItem, r: Rect2, edge: Color, edge_on_right: bool) -> void:
	HudStyle.framed_plate(ci, r, 14.0, HudStyle.PANEL, Color(HudStyle.LINE, 0.3))
	if edge_on_right:
		ci.draw_rect(Rect2(r.end.x - 3.0, r.position.y, 3.0, r.size.y - 14.0), edge)
	else:
		ci.draw_rect(Rect2(r.position.x, r.position.y + 14.0, 3.0, r.size.y - 14.0), edge)


static func _draw_health(ci: CanvasItem, v: Hud.View, bottom: float, hp_col: Color) -> void:
	var r := Rect2(MARGIN - 12.0, bottom - PLATE.y + 12.0, PLATE.x, PLATE.y)
	_plate(ci, r, hp_col if v.hp <= HudStyle.LOW_HEALTH else HudStyle.CYAN, false)
	var w := HudStyle.text(ci, Vector2(MARGIN + 6.0, bottom - 46.0), str(ceili(v.hp)), 52, hp_col)
	HudStyle.label(ci, Vector2(MARGIN + w + 18.0, bottom - 58.0), "HEALTH", 10, Color(HudStyle.CYAN.lerp(Color.WHITE, 0.3), 0.85))
	HudStyle.text(ci, Vector2(MARGIN + w + 18.0, bottom - 38.0), v.character.to_upper(), 14, Color(1, 1, 1, 0.8))
	for i in 10:
		var seg_hp := (i + 1) * Match.MAX_HEALTH / 10.0
		var col := HudStyle.DIM
		if v.hp >= seg_hp - 5.0:
			col = hp_col
		elif v.hp_trail >= seg_hp - 5.0:
			col = HudStyle.RED
		var seg := Rect2(MARGIN + 6.0 + i * 30.0, bottom - 10.0, 26.0, 8.0)
		HudStyle.slant_plate(ci, seg.grow(1.5), 4.0, HudStyle.EDGE)
		HudStyle.slant_plate(ci, seg, 4.0, col)


static func _draw_rest(ci: CanvasItem, c: Vector2, v: Hud.View, size: Vector2, bottom: float) -> void:
	# Moves: a chip each, with a ring that refills as the move recharges. Settings → HUD:
	# compact leaves out those ready to use (the rest close up), off all of them.
	var moves := Settings.hud.moves
	var x := MARGIN - 12.0
	var y := bottom - 108.0
	for i in (v.moves.size() if moves != "off" else 0):
		var m: Array = v.moves[i]
		var ready: float = m[2]
		var label: String = m[0]
		if moves == "compact" and ready >= 1.0 and not m[3]:
			continue
		var cw := 36.0 + HudStyle.text_width(label, 11)
		HudStyle.plate(ci, Rect2(x, y - 15.0, cw, 30.0), 7.0, Color(HudStyle.ORANGE, 0.3) if m[3] else HudStyle.PANEL)
		var ring_c := Vector2(x + 16.0, y)
		var col := HudStyle.WHITE
		if m[3]:
			col = HudStyle.ORANGE
		elif i == 0 and ready >= 1.0:
			col = HudStyle.CYAN
		HudStyle.arc(ci, ring_c, 10.0, 0, 360, Color(1, 1, 1, 0.18), 3.0)
		HudStyle.arc(ci, ring_c, 10.0, -90, -90 + 360.0 * ready, col, 3.0)
		var text_col := Color(1, 1, 1, 0.95 if ready >= 1.0 else 0.5)
		HudStyle.text(ci, Vector2(x + 31.0, y), label, 11, text_col)
		x += cw + 6.0

	if Settings.hud.speed:
		var speed := "%s  ·  %.1f M/S" % [v.move_state, v.speed]
		HudStyle.label(ci, c + Vector2(0, 40), speed, 11, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	if v.race:
		return
	# Ammo: count, magazine, a tick per round, weapon. Melee: the weapon and a swing bar.
	var right := size.x - MARGIN
	var r := Rect2(right + 12.0 - PLATE.x, bottom - PLATE.y + 12.0, PLATE.x, PLATE.y)
	_plate(ci, r, HudStyle.ORANGE if v.reloading else HudStyle.CYAN, true)
	right -= 8.0
	if v.melee:
		HudStyle.text(ci, Vector2(right, bottom - 52.0), v.weapon.to_upper(), 34, HudStyle.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		var bar := Rect2(right - 150.0, bottom - 28.0, 150.0, 8.0)
		HudStyle.edged_rect(ci, bar, HudStyle.DIM)
		ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(v.swing, 0.0, 1.0), bar.size.y)), HudStyle.WHITE if v.swing >= 1.0 else HudStyle.ORANGE)
		HudStyle.label(ci, Vector2(right, bottom - 6.0), "F  KICK" if v.gun == "none" else "LMB  SWING", 10, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_RIGHT)
	elif v.blast:   # the air cannon: no ammo, a charge bar (orange as it refills after a blast)
		var charging := v.charge >= 0.0
		HudStyle.text(ci, Vector2(right, bottom - 52.0), ("%d%%" % roundi(v.charge * 100.0)) if charging else v.weapon.to_upper(), 34,
			HudStyle.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		var bar := Rect2(right - 150.0, bottom - 28.0, 150.0, 8.0)
		HudStyle.edged_rect(ci, bar, HudStyle.DIM)
		var fill := v.charge if charging else (clampf(v.swing, 0.0, 1.0) if v.swing < 1.0 else 0.0)
		var col := (HudStyle.WHITE if v.charge >= 1.0 else HudStyle.CYAN) if charging else HudStyle.ORANGE
		ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), col)
		HudStyle.label(ci, Vector2(right, bottom - 6.0), v.weapon.to_upper() + "  ·  HOLD LMB, LET GO", 10, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		_draw_ammo(ci, v, right, bottom)


static func _draw_ammo(ci: CanvasItem, v: Hud.View, right: float, bottom: float) -> void:
	var ticks := clampi(v.magazine, 1, 30)
	var lit := v.ammo if v.magazine <= 30 else ceili(float(v.ammo) / v.magazine * ticks)   # a big magazine shares the ticks out
	for i in ticks:
		var col := HudStyle.WHITE if i < lit and not v.reloading else HudStyle.DIM
		if v.reloading and i < int(ticks * v.reload):
			col = HudStyle.ORANGE
		var pitch := 9.0 if ticks <= 15 else 6.0   # a 30-round magazine packs its ticks closer
		HudStyle.edged_rect(ci, Rect2(right - (ticks - i) * pitch + 3.0, bottom - 32.0, pitch - 3.0, 14.0), col)
	if v.reloading:
		HudStyle.text(ci, Vector2(right, bottom - 58.0), "RELOADING", 24, HudStyle.ORANGE, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		var mw := HudStyle.text(ci, Vector2(right, bottom - 54.0), "/ %d" % v.magazine, 20, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
		HudStyle.text(ci, Vector2(right - mw - 8.0, bottom - 60.0), str(v.ammo), 44, HudStyle.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	HudStyle.label(ci, Vector2(right, bottom - 6.0), v.weapon.to_upper() + "  ·  R RELOAD", 10, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_RIGHT)
