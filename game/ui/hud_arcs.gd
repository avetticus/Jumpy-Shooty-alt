class_name HudArcs
extends RefCounted
## "Twin arcs" HUD layout: everything about you sits around the crosshair, so you
## never look away from the middle of the screen while moving fast.
## Left gauge: health in ten blocks (fills from the bottom; a red chunk shows what
## you just lost), with the number beside it.
## Right gauge: one tick per round in the magazine (fills orange while reloading; a
## shotgun's fills shell by shell), the count and the weapon's name.
## Each gauge has a hairline outside it with a tick at either end and a soft glow
## under the lit part.
## Under the crosshair: a short arc each for grapple, dive, flip, glide, slide boost, rocket boots and kick,
## then your speed and what you are doing (Settings → HUD can leave out either).

const R := 92.0           ## radius of the health and ammo arcs
const SPAN := 70.0        ## degrees each of them covers
const WIDTH := 7.0
const MOVES_R := 50.0
const BLOCKS := 10        ## health blocks


static func draw(ci: CanvasItem, c: Vector2, v: Hud.View) -> void:
	if not v.race:   # a race has no health or ammo
		_draw_health(ci, c, v)
		_draw_ammo(ci, c, v)
	_draw_moves(ci, c, v)


## The hairline outside a gauge, with a tick at either end.
static func _rail(ci: CanvasItem, c: Vector2, from: float, to: float) -> void:
	var col := Color(1, 1, 1, 0.4)
	HudStyle.arc(ci, c, R + 11.0, from - 3.0, to + 3.0, Color(0, 0, 0, 0.3), 3.0)
	HudStyle.arc(ci, c, R + 11.0, from - 3.0, to + 3.0, col, 1.5)
	for a in [from - 3.0, to + 3.0]:
		HudStyle.tick(ci, c, R + 6.0, R + 17.0, a, Color(1, 1, 1, 0.7), 2.0)


static func _draw_health(ci: CanvasItem, c: Vector2, v: Hud.View) -> void:
	# From 145 deg (lower left) up to 215 deg (upper left).
	var lo := 180.0 - SPAN * 0.5
	var hp_col := HudStyle.health_color(v.hp)
	var glow := HudStyle.RED if v.hp <= HudStyle.LOW_HEALTH else HudStyle.CYAN
	var blocks_hp := clampf(v.hp / Match.MAX_HEALTH, 0.0, 1.0) * BLOCKS
	var blocks_trail := clampf(v.hp_trail / Match.MAX_HEALTH, 0.0, 1.0) * BLOCKS
	_rail(ci, c, lo, lo + SPAN)
	if blocks_hp > 0.0:
		HudStyle.arc(ci, c, R, lo, lo + SPAN * blocks_hp / BLOCKS, Color(glow, 0.2), WIDTH + 9.0)
	var step := SPAN / BLOCKS
	var gap := 1.8
	for i in BLOCKS:
		var a0 := lo + i * step + gap * 0.5
		var a1 := a0 + step - gap
		HudStyle.edged_arc(ci, c, R, a0, a1, HudStyle.DIM, WIDTH)
		var f := clampf(blocks_hp - i, 0.0, 1.0)
		var tf := clampf(blocks_trail - i, 0.0, 1.0)
		if tf > f:
			HudStyle.arc(ci, c, R, lerpf(a0, a1, f), lerpf(a0, a1, tf), Color(HudStyle.RED, 0.9), WIDTH)
		if f > 0.0:
			HudStyle.arc(ci, c, R, a0, lerpf(a0, a1, f), hp_col, WIDTH)
	HudStyle.text(ci, c + Vector2(-R - 30.0, -5.0), str(ceili(v.hp)), 26, hp_col, HORIZONTAL_ALIGNMENT_RIGHT)
	HudStyle.label(ci, c + Vector2(-R - 30.0, 15.0), "HEALTH", 10, Color(glow.lerp(Color.WHITE, 0.3), 0.85), HORIZONTAL_ALIGNMENT_RIGHT)


static func _draw_ammo(ci: CanvasItem, c: Vector2, v: Hud.View) -> void:
	var bottom := SPAN * 0.5
	_rail(ci, c, -bottom, bottom)
	var name_at := c + Vector2(R + 30.0, 15.0)
	# Melee: one arc that refills after each swing, and the weapon's name.
	if v.melee:
		var ready := v.swing >= 1.0
		HudStyle.edged_arc(ci, c, R, -bottom, bottom, HudStyle.DIM, WIDTH)
		HudStyle.glow_arc(ci, c, R, bottom - SPAN * clampf(v.swing, 0.0, 1.0), bottom, HudStyle.WHITE if ready else HudStyle.ORANGE, WIDTH,
			HudStyle.CYAN if ready else HudStyle.ORANGE)
		HudStyle.text(ci, c + Vector2(R + 30.0, -5.0), v.weapon.to_upper(), 17, HudStyle.WHITE)
		HudStyle.label(ci, name_at, "READY" if ready else "SWINGING", 10, Color(HudStyle.CYAN if ready else HudStyle.ORANGE, 0.85))
		return
	# The air cannon: no ammo. The arc fills as it charges (white when full), and refills
	# in orange in the moment after a blast.
	if v.blast:
		HudStyle.edged_arc(ci, c, R, -bottom, bottom, HudStyle.DIM, WIDTH)
		var state := "HOLD TO CHARGE"
		if v.charge >= 0.0:
			var full := v.charge >= 1.0
			HudStyle.glow_arc(ci, c, R, bottom - SPAN * v.charge, bottom, HudStyle.WHITE if full else HudStyle.CYAN, WIDTH, HudStyle.CYAN)
			HudStyle.text(ci, c + Vector2(R + 30.0, -5.0), "%d%%" % roundi(v.charge * 100.0), 26, HudStyle.WHITE)
			state = "FULL: LET GO" if full else "CHARGING"
		else:
			if v.swing < 1.0:
				HudStyle.glow_arc(ci, c, R, bottom - SPAN * clampf(v.swing, 0.0, 1.0), bottom, HudStyle.ORANGE, WIDTH, HudStyle.ORANGE)
			HudStyle.text(ci, c + Vector2(R + 30.0, -5.0), v.weapon.to_upper(), 17, HudStyle.WHITE)
		HudStyle.label(ci, name_at, state, 10, Color(HudStyle.CYAN.lerp(Color.WHITE, 0.3), 0.85))
		return

	# Rounds from 35 deg (lower right) up to -35 deg (upper right). A magazine bigger
	# than 30 shares the 30 ticks out.
	var n := clampi(v.magazine, 1, 30)
	var lit := v.ammo if v.magazine <= 30 else ceili(float(v.ammo) / v.magazine * n)
	var step := SPAN / n
	var gap := minf(0.8, step * 0.18)   # thinner gaps for a 30-round magazine
	if lit > 0 and not v.reloading:
		HudStyle.arc(ci, c, R, bottom - lit * step, bottom, Color(HudStyle.CYAN, 0.2), WIDTH + 9.0)
	for i in n:
		var a0 := bottom - i * step - gap
		var a1 := a0 - step + gap * 2.0
		var on := i < lit and not v.reloading
		HudStyle.edged_arc(ci, c, R, a1, a0, HudStyle.WHITE if on else HudStyle.DIM, WIDTH)
	if v.reloading:
		HudStyle.glow_arc(ci, c, R, bottom - SPAN * v.reload, bottom, HudStyle.ORANGE, WIDTH)
		HudStyle.text(ci, c + Vector2(R + 30.0, -5.0), "RELOAD", 17, HudStyle.ORANGE)
	else:
		var low := v.magazine > 0 and v.ammo <= maxi(v.magazine / 5, 1)
		var w := HudStyle.text(ci, c + Vector2(R + 30.0, -5.0), str(v.ammo), 26, HudStyle.ORANGE if low else HudStyle.WHITE)
		HudStyle.text(ci, c + Vector2(R + 34.0 + w, -1.0), "/%d" % v.magazine, 13, Color(1, 1, 1, 0.65))
	HudStyle.label(ci, name_at, v.weapon.to_upper(), 10, Color(HudStyle.CYAN.lerp(Color.WHITE, 0.3), 0.85))


static func _draw_moves(ci: CanvasItem, c: Vector2, v: Hud.View) -> void:
	# Moves, under the crosshair: grapple, dive, flip, glide, slide, boots, kick (left to right).
	# Settings → HUD: compact leaves out those ready to use (the rest keep their places), off all of them.
	var moves := Settings.hud.moves
	for i in (v.moves.size() if moves != "off" else 0):
		var m: Array = v.moves[i]
		var ready: float = m[2]
		if moves == "compact" and ready >= 1.0 and not m[3]:
			continue
		var a0 := 90.0 + (v.moves.size() * 16.0 - 3.0) * 0.5 - i * 16.0   # centred under; angles grow clockwise, so go right to left
		var a1 := a0 - 13.0
		HudStyle.edged_arc(ci, c, MOVES_R, a1, a0, HudStyle.DIM, 4.0)
		var col := HudStyle.WHITE
		if m[3]:
			col = HudStyle.ORANGE
		elif i == 0 and ready >= 1.0:
			col = HudStyle.CYAN
		elif ready < 1.0:
			col = Color(1, 1, 1, 0.55)
		if m[3]:
			HudStyle.arc(ci, c, MOVES_R, a1, a0, Color(HudStyle.ORANGE, 0.25), 11.0)
		HudStyle.arc(ci, c, MOVES_R, a0 - 13.0 * ready, a0, col, 4.0)

	# Speed and what you are doing, between two small brackets.
	if not Settings.hud.speed:
		return
	var speed := "%.1f M/S  ·  %s" % [v.speed, v.move_state]
	var at := c + Vector2(0, 76)
	var w := HudStyle.label(ci, at, speed, 11, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
	for side in [-1.0, 1.0]:
		var x: float = at.x + side * (w * 0.5 + 9.0)
		ci.draw_polyline(PackedVector2Array([Vector2(x - side * 4.0, at.y - 6.0), Vector2(x, at.y - 6.0), Vector2(x, at.y + 6.0),
			Vector2(x - side * 4.0, at.y + 6.0)]), Color(HudStyle.CYAN, 0.7), 1.5)
