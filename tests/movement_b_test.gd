extends SceneTree
## Variant B's movement (see MovementTuning._apply_b), driven with scripted input on a
## flat floor beside a tall wall, next to a classic body for comparison.
## Run: godot --headless --path . --fixed-fps 60 --script tests/movement_b_test.gd
##
## Checks (against the plain MovementTuning numbers, which were Classic's): the same
## running speed and jump height; pressing against your motion in the air brakes it far
## harder; legs tucked in the air with no key; a glide gives way to a flip (the glide
## itself: tests/glide_test.gd); Space in mid-air flips once per jump and E fires the boots;
## with the jetpack, holding Space in mid-air asks for it once held space_hold_time (not
## at once on a jump); sideways speed capped at 27 m/s; Ctrl forward dives onto your
## belly and crawls, Ctrl back slides on your back and ends in a crouch, Ctrl standing
## still crouches; pushing into a wall in mid-air sits on it for 2.5 s, then slides
## down, and a jump kicks off it. Classic still flips.

const S := MovementController.State
const WALL_Z := -3.0   ## the wall's face (it stands beyond, toward -z)

var _fails := 0
var input := PlayerInput.new()


func _initialize() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(400, 1, 400))           # the floor
	_box(Vector3(100, 6, WALL_Z - 0.5), Vector3(20, 12, 1))  # a tall wall, no ledge to climb
	_box(Vector3(130, 6, 50), Vector3(1, 12, 20))          # another, facing -x (face at x = 129.5)
	_run.call_deferred()


func _box(pos: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	b.position = pos
	root.add_child(b)


func _body(x: float) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.floor_snap_length = 0.3
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	body.add_child(cs)
	root.add_child(body)
	body.global_position = Vector3(x, 0.0, 0.0)
	return body


func _run() -> void:
	var b_body := _body(0.0)
	var b := MovementController.new(MovementTuning.for_variant("b"))
	var c_body := _body(-50.0)
	var c := MovementController.new(MovementTuning.new())   # the plain numbers (what Classic was), to compare against
	print("Variant B movement checks")

	# --- Slower running, same jump.
	var b_speed := await _run_speed(b_body, b)
	var c_speed := await _run_speed(c_body, c)
	_check(absf(b_speed - c_speed) < 0.05, "runs as fast as Classic (%.2f vs %.2f m/s)" % [b_speed, c_speed])
	var b_head := await _jump_peak(b_body, b)
	var c_head := await _jump_peak(c_body, c)
	_check(absf(b_head - c_head) < 0.05, "jumps as high (%.2f vs %.2f m)" % [b_head, c_head])

	# --- Pressing against your motion in the air: Variant B stops it far sooner.
	var b_left := await _air_brake_left(b_body, b)
	var c_left := await _air_brake_left(c_body, c)
	_check(b_left < 1.0 and c_left > 6.0, "pressing against 15 m/s in the air stops it in 0.3 s (%.1f m/s left; Classic %.1f)" % [b_left, c_left])

	# --- Tucked in the air with no key, standing again on landing.
	await _settle(b_body, b, Vector3(0, 0, 0))
	_press_jump()
	await _steps(b_body, b, 18)
	_check(b.crouched and b.state == S.AIR, "legs tucked in the air with no key")
	await _steps(b_body, b, 60)
	_check(not b.crouched and b.state == S.GROUND, "standing again after landing")

	# --- Space in mid-air: a flip (once per jump), not the boots. Shift: no glide.
	await _settle(b_body, b, Vector3(0, 0, 0))
	_press_jump()
	await _steps(b_body, b, 18)
	var boosts := b.boosts
	input.glide = true
	input.glide_pressed = true
	_press_jump()
	await _steps(b_body, b, 1)
	_check(b.state == S.FLIP and b.boosts == boosts, "Space in mid-air flips, no rocket boots")
	await _steps(b_body, b, 4)
	_press_jump()
	await _steps(b_body, b, 1)
	_check(b.flip_readiness() == 0.0 and b.boosts == boosts, "...once per jump")
	await _steps(b_body, b, 20)
	_check(b.state != S.GLIDE, "a glide pressed with the flip gives way to it (and needs a fresh press)")
	input.glide = false
	input.boost_pressed = true
	await _steps(b_body, b, 1)
	_check(b.boosts == boosts + 1, "E fires the rocket boots")

	# --- With the jetpack: a Space tap flips, holding Space flies the jetpack, but not
	# before it has been held space_hold_time in the air (a plain jump burns nothing).
	b.has_jetpack = true
	await _settle(b_body, b, Vector3(0, 0, 0))
	_press_jump()
	var early := false
	for i in int(b.tuning.space_hold_time * 60.0) - 2:
		await _steps(b_body, b, 1)
		early = early or b.space_jet
	_check(not early and b_body.global_position.y > 0.5, "Space held through a jump does not ask for the jetpack before the hold time")
	var later := false
	for i in 6:
		await _steps(b_body, b, 1)
		later = later or b.space_jet
	_check(later, "...and does once it is up")
	input.jump_held = false
	await _settle(b_body, b, Vector3(0, 0, 0))
	_press_jump()
	await _steps(b_body, b, 16)
	input.jump_held = false
	await _steps(b_body, b, 2)
	_press_jump()
	await _steps(b_body, b, 4)
	var flipped := b.state == S.FLIP
	input.jump_held = false
	await _steps(b_body, b, 1)
	_check(flipped and not b.space_jet, "with the jetpack, a Space tap flips")
	_press_jump()
	var jet := false
	for i in 24:
		await _steps(b_body, b, 1)
		jet = jet or b.space_jet
	_check(jet, "...and holding Space flies the jetpack")
	input.jump_held = false
	b.has_jetpack = false

	# --- Sideways speed is capped at 27 m/s (Classic has no cap).
	var b_fast := await _after_fling(b_body, b)
	var c_fast := await _after_fling(c_body, c)
	_check(b_fast <= 27.01 and b_fast > 26.5 and c_fast > 28.0, "flung at 30 m/s: Variant B goes 27 m/s at most (%.1f; Classic %.1f)" % [b_fast, c_fast])

	# --- Ctrl forward: dive, belly slide, crawl.
	await _settle(b_body, b, Vector3(0, 0, 0))
	input.move = Vector2(0, 1)
	await _steps(b_body, b, 60)
	input.crouch = true
	input.crouch_pressed = true
	await _steps(b_body, b, 1)
	input.crouch_pressed = false
	_check(b.state == S.DIVE, "Ctrl running forward dives")
	var belly := false
	for i in 90:
		await _steps(b_body, b, 1)
		belly = belly or b.state == S.BELLY_SLIDE
	_check(belly, "...lands on your belly while Ctrl is held")
	input.move = Vector2.ZERO
	await _steps(b_body, b, 240)
	_check(b.state == S.BELLY_SLIDE and b.prone and b.horizontal_speed(b_body) <= b.tuning.belly_crawl_speed + 0.1,
			"...and you lie there once the slide runs out (%.2f m/s)" % b.horizontal_speed(b_body))
	input.move = Vector2(0, 1)
	await _steps(b_body, b, 180)
	_check(b.state == S.BELLY_SLIDE and absf(b.horizontal_speed(b_body) - b.tuning.belly_crawl_speed) < 0.25,
			"...crawling on your stomach while Ctrl is held (%.2f m/s)" % b.horizontal_speed(b_body))
	input.move = Vector2.ZERO
	input.crouch = false
	await _steps(b_body, b, 30)
	_check(not b.prone and b.state != S.BELLY_SLIDE, "letting go gets you up")

	# --- Ctrl backward: a slide on your back, then a crouch.
	await _settle(b_body, b, Vector3(0, 0, 0))
	input.move = Vector2(0, -1)
	await _steps(b_body, b, 60)
	input.crouch = true
	input.crouch_pressed = true
	await _steps(b_body, b, 1)
	input.crouch_pressed = false
	_check(b.state == S.SLIDE, "Ctrl running backward slides on your back (%s)" % S.keys()[b.state])
	input.move = Vector2.ZERO
	await _steps(b_body, b, 180)
	_check(b.state == S.CROUCH, "...and ends in a crouch (%s)" % S.keys()[b.state])
	input.crouch = false
	await _steps(b_body, b, 10)

	# --- Ctrl standing still: a crouch, no dive or slide.
	await _settle(b_body, b, Vector3(0, 0, 0))
	input.crouch = true
	input.crouch_pressed = true
	await _steps(b_body, b, 1)
	input.crouch_pressed = false
	await _steps(b_body, b, 10)
	_check(b.state == S.CROUCH, "Ctrl standing still crouches (%s)" % S.keys()[b.state])
	input.crouch = false
	await _steps(b_body, b, 10)

	# --- Wall sit: stick a second, slide down, kick off with a jump.
	await _settle(b_body, b, Vector3(100, 0, WALL_Z + 1.2))
	input.move = Vector2(0, 1)   # into the wall
	_press_jump()
	var sat_at := -1
	for i in 60:
		await _steps(b_body, b, 1)
		if b.state == S.WALL_SIT:
			sat_at = i
			break
	_check(sat_at >= 0, "pushing into a wall in mid-air sits on it")
	var y0 := b_body.global_position.y - b.tuck   # (the legs come down onto the wall: the body stays put)
	await _steps(b_body, b, 135)
	var moved := b_body.global_position.y - b.tuck - y0
	_check(b.state == S.WALL_SIT and absf(moved) < 0.05, "...and stays put for over 2 s (moved %.2f m)" % moved)
	await _steps(b_body, b, 30)
	_check(b.state == S.WALL_SIT and b_body.velocity.y < -1.0, "...then slides down it (%.1f m/s)" % b_body.velocity.y)
	var kicks := b.wall_jumps
	_press_jump()
	await _steps(b_body, b, 1)
	_check(b.wall_jumps == kicks + 1 and b_body.velocity.z > 1.0, "a jump kicks off the wall")
	input.move = Vector2.ZERO

	# Stopped dead against a wall (no speed to look along), facing +x: still sits.
	await _settle(b_body, b, Vector3(120, 0, 50))
	b_body.global_position = Vector3(129.5 - 0.42, 3.0, 50.0)
	b_body.velocity = Vector3.ZERO
	input.yaw = -PI / 2.0
	input.move = Vector2(0, 1)
	var sat := false
	for i in 20:
		await _steps(b_body, b, 1)
		sat = sat or b.state == S.WALL_SIT
	await _steps(b_body, b, 20)
	_check(sat and b.state == S.WALL_SIT, "hanging still against a wall, pushing into it sits on it (%s)" % S.keys()[b.state])
	input.move = Vector2.ZERO
	input.yaw = 0.0

	# --- Classic is untouched: a mid-air jump still flips.
	await _settle(c_body, c, Vector3(-50, 0, 0))
	_press_jump()
	await _steps(c_body, c, 18)
	_press_jump()
	await _steps(c_body, c, 1)
	_check(c.state == S.FLIP and not c.crouched, "classic: a mid-air jump flips, legs not tucked")

	print("PASS: all Variant B checks" if _fails == 0 else "FAIL: %d Variant B checks" % _fails)
	quit(1 if _fails > 0 else 0)


## Top running speed after 3 s.
func _run_speed(body: CharacterBody3D, m: MovementController) -> float:
	await _settle(body, m, Vector3(body.global_position.x, 0, 0))
	input.move = Vector2(0, 1)
	await _steps(body, m, 180)
	input.move = Vector2.ZERO
	return m.horizontal_speed(body)


## Flung sideways at 30 m/s high in the air: the sideways speed a moment later.
func _after_fling(body: CharacterBody3D, m: MovementController) -> float:
	await _settle(body, m, Vector3(body.global_position.x, 0, 0))
	body.global_position.y = 40.0
	body.velocity = Vector3(30, 0, 0)
	await _steps(body, m, 2)
	var fast := m.horizontal_speed(body)
	await _settle(body, m, Vector3(body.global_position.x - 1.0, 0, 0))
	return fast


## Moving 15 m/s sideways high in the air, pressing the other way for 0.3 s: the
## speed still going the first way.
func _air_brake_left(body: CharacterBody3D, m: MovementController) -> float:
	await _settle(body, m, Vector3(body.global_position.x, 0, 0))
	body.global_position.y = 40.0
	body.velocity = Vector3(15, 0, 0)
	input.move = Vector2(-1, 0)   # (facing -z, so left is -x)
	await _steps(body, m, 18)
	input.move = Vector2.ZERO
	var left := body.velocity.x
	await _settle(body, m, Vector3(body.global_position.x, 0, 0))
	return left


## The highest a standing jump lifts the body (less the tuck, which lifts only the feet).
func _jump_peak(body: CharacterBody3D, m: MovementController) -> float:
	await _settle(body, m, Vector3(body.global_position.x, 0, 0))
	var top := 0.0
	_press_jump()
	for i in 70:
		await _steps(body, m, 1)
		top = maxf(top, body.global_position.y - m.tuck)
	return top


func _settle(body: CharacterBody3D, m: MovementController, at: Vector3) -> void:
	input = PlayerInput.new()
	m.reset()
	body.global_position = at
	body.velocity = Vector3.ZERO
	await _steps(body, m, 20)


func _press_jump() -> void:
	input.jump_pressed = true
	input.jump_held = true


## Steps the body `n` sixtieths of a second (the physics runs faster: every tick of it).
## Presses last one step.
func _steps(body: CharacterBody3D, m: MovementController, n: int) -> void:
	var ticks := Engine.physics_ticks_per_second
	for i in n * ticks / 60:
		await physics_frame
		m.step(body, input, 1.0 / ticks)
		input.jump_pressed = false
		input.crouch_pressed = false
		input.dive_pressed = false
		input.glide_pressed = false
		input.boost_pressed = false


func _check(cond: bool, what: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + what)
	if not cond:
		_fails += 1
