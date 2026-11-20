class_name MovementController
extends RefCounted
## The player's movement rules. One controller with a small set of states that all
## share one velocity, so speed carries from one move into the next by design.
##
##   GROUND    running and sprinting
##   AIR       jumping and falling (bunny-hops and air-strafing live here)
##   GRAPPLE   reeled in and swinging on the rope, once the hook has flown there,
##             bitten and pulled tight (see grapple.gd)
##   CROUCH    crouched on the ground: lower and slower
##   SLIDE     crouch while moving fast: keeps momentum, speeds up downhill
##   WALL_RUN  run along a wall with little gravity; jump to kick off it
##   MANTLE    vaulting a low obstacle or climbing up a ledge
##   DIVE      a forward lunge toward where you look (from the ground or once per jump).
##             If the grappling hook's rope pulls tight while you are in one you
##             have dived into the rope: it becomes GRAPPLE, with the rope's own
##             steering and jump off, until you let go short of the hook, when the
##             dive carries on (see dove_in)
##   ROLL      landing from a dive: a short roll that keeps your speed
##   BELLY_SLIDE  keep holding dive as you land: slide along on your front instead
##             of rolling. Lower than a crouch. Let go (or jump) to get up; once
##             the slide runs out you can crawl until you let go.
##   FLIP      press jump again in mid-air: a flip toward your WASD direction with a
##             small burst, once per jump (a dodge)
##   GLIDE     the bullet glide: hold Alt in mid-air (pressed there). Your rise or
##             fall eases out in a moment and you fly on along a locked track: the
##             way you were going, at the speed you had, with no steering and none
##             of it lost, free to look and aim anywhere. Hold it as long as you
##             like, but it weakens: you hardly sink at first, then the fall builds
##             until, glide_fade_time seconds in, it is a plain fall (still on the
##             track). The seconds add up over one time in the air, so letting go
##             and pressing again carries on where it was (no fresh float); landing,
##             a wall run or the grapple start it afresh. Let go to stop. Any other
##             move takes over from it (flip, dive, grapple, a wall). Rocket boots
##             do not end it: they send the track off the way you press instead
##             (see _glide_boost).
##   SLAM      a ground slam (melee): you drive straight down and nothing stops it
##             but the floor (see start_slam; Player decides when, GroundSlam what it does)
##   WALL_SIT  (tuning.wall_sit_time > 0, Variant B) push into a wall in mid-air: you
##             stick to it for wall_sit_time, then slide slowly down it while you keep
##             pushing. Let go to drop off; jump to kick off it (a wall jump).
##
## The jetpack (everyone's, see Jetpack): Space held in mid-air flies it, once held
## tuning.space_hold_time there, counted from the press or from the jump it made (see
## space_jet). A tap is still a jump, a wall jump or a flip.
##
## MovementTuning's mechanic switches change some of this (Variant B, for A/B testing):
## legs tucked in the air without a key; Ctrl (or Q) dives forward, slides on your back
## going backward, and crouches otherwise; a stronger brake in the air; a sideways speed
## limit. (space_boost, mid-air Space firing the rocket boots, is there but off.)
## Winding a melee swing up in a plain fall hangs you in the air for a moment (see
## _hang): hang_time seconds per time in the air, refilled like the glide.
##
## Rocket boots (E): a burst of speed toward your WASD direction as seen from
## where you look (straight where you look if you hold no direction), so you can
## boost up, down, sideways or back, on the ground, in the air or mid-swing. It
## adds to the speed you have, so a burst along a grapple swing whips you round
## much faster. It recharges over boost_cooldown seconds.
##
## Crouching in the air tucks your legs up (head stays put), which helps you clear
## edges. Wall jumps work from a wall run or any wall you are touching in the air.

const TUCK_SETTLE_SPEED := 3.0   ## metres per second
const DIVE_IN_SLOW := 3.0        ## ...and you have arrived once you close on the hook slower than this (metres per second)...
const DIVE_IN_SLOW_TIME := 0.2   ## ...for this long (seconds), wherever you are
const DIVE_IN_MIN := 3.0         ## metres: a dive into a rope with less than this to go before its pull fades is just a swing (see dove_in)
const BELLY_SLOPE := 0.985       ## floor normal's y below this (about 10 degrees): a belly slide never slows to a crawl

## New states go on the end: the numbers travel in snapshots (Player.make_pose).
enum State { GROUND, AIR, GRAPPLE, CROUCH, SLIDE, WALL_RUN, MANTLE, DIVE, ROLL, FLIP, BELLY_SLIDE, GLIDE, SLAM, WALL_SIT }

var tuning: MovementTuning
var state: State = State.AIR
var grapple: Grapple
var crouched := false
var prone := false   ## lying on your front (belly slide): shorter still than crouched; crouched stays true
var eye_height := MovementTuning.EYE_HEIGHT  ## eyes above the feet right now (eases when crouching)
var wall_normal := Vector3.ZERO              ## the wall being run on
## How far the feet are lifted by tucking the legs up in the air (0 or up to
## stand_height - crouch_height). The head stays put when you tuck. Others are sent
## your feet minus this, which never jumps; on the ground it settles back to 0
## smoothly. See Player._sent_position().
var tuck := 0.0
## Direction of the current flip, relative to where you face (x = right, y = forward).
var flip_dir := Vector2.ZERO
## Wall jumps so far, and the wall last kicked off. For animation.
var wall_jumps := 0
var kick_wall := Vector3.ZERO
## The hardest hit against a wall, ceiling or prop in the last step: speed straight
## into it (m/s) and where. Landing on the floor does not count. See Player._check_slam().
var impact_speed := 0.0
var impact_point := Vector3.ZERO
## Rocket-boot bursts so far (for the flame and sound others see), and seconds since the last.
var boosts := 0
var since_boost := 99.0

## This body's gravity right now, as a share of normal: the map-wide WorldGravity.scale
## (a map event) times the gravity of the zone it is in (see MapGravityZone), which
## eases from one zone's to the next over WorldGravity.BLEND_TIME. Worked out at the
## start of every step; everything here that uses gravity multiplies by it.
var gravity_scale := 1.0
## The zone's share on its own (1.0 on a map with no zones), eased.
var zone_scale := 1.0

var _zone_from := 1.0
var _zone_to := -1.0         # the zone it is easing to (below 0: not known yet, take the first one as it is)
var _zone_t := 1.0

var _knock := Vector3.ZERO   # knockback waiting to be added on the next step
## Set when the body was just moved somewhere new (a jetpack lift-off): the next step
## does not count the floor it was standing on before.
var warped := false

var _since_ground := 0.0   # seconds since we last stood on the floor
var _jump_buffer := 0.0    # seconds left on a buffered jump press
var _since_slide_boost := 99.0
var _wall_time := 0.0      # seconds into the current wall run
var _used_wall := Vector3.ZERO   # last wall run or jumped off; can't reuse it until you land or touch another
var _recent_wall := Vector3.ZERO # last wall touched in the air (for late wall jumps)
var _since_wall := 99.0
var _mantle := {}          # the vault or climb in progress
var _shape: CollisionShape3D
var _since_dive := 99.0
## Dove into the rope: you were in a dive when the grappling hook's rope pulled tight,
## with further to go than DIVE_IN_MIN past where its pull fades. The dive gives way to
## the rope (its steering, its jump off) and the body shows it (RopeSwing's zip) until
## you arrive: within grapple_pull_stop of the hook, or no longer closing on it (see
## DIVE_IN_SLOW). Let go before that and the dive carries on (and lands in its roll).
var dove_in := false
## ...and the way you were steering as it pulled tight: -1 left, 1 right, 0 neither.
var dove_side := 0
var _dove_slow := 0.0   # seconds it has not been closing on the hook
var _air_dive_used := false   # one dive per jump
var _flip_used := false       # one flip per jump
var _roll_left := 0.0
var _flip_left := 0.0
var _glide_used := 0.0        # seconds glided this time in the air (the glide weakens with them)
var _glide_wanted := false    # the glide key was pressed in the air and is still held
var _glide_on := false        # a glide is under way (to notice another move taking over from it)
var hang := false             ## set every step by the player: winding a melee swing up (the fall slows in mid-air, see _hang)
var hanging := false          ## the fall is being slowed right now
var _hang_left := 0.0         # seconds of that left for this time in the air
var _slam_used := false       # a ground slam has been done this time in the air
var _slam_time := 0.0         # seconds this slam has lasted
var _slam_from := 0.0         # the height it started at
var _slam_landing := -1.0     # a slam just landed, from this many metres up (taken by take_slam_landing), or -1
var has_jetpack := false      ## set every step by the player: it has the jetpack (everyone does, but not in a race)
## The jetpack is wanted now (Player flies it): Space held in mid-air for
## tuning.space_hold_time, counted from the press or from the jump or wall jump it made
## (so a plain jump, a wall jump or a flip burns no fuel unless you keep holding), and
## only in a plain jump, fall, flip or dive: not on the rope, on a wall, in a glide, a
## vault or a slam.
var space_jet := false
var _space_tap := -1.0        # tuning.space_boost: seconds a mid-air Space press has been held (a tap boosts), or -1
var _jet_hold := 0.0          # seconds Space has been held in mid-air since it was pressed (or since its jump)
var _auto_tuck := false       # tuning.always_tuck: tucked by itself this step (not by the crouch key)
var _sit_left := 0.0          # seconds of sticking left on this wall sit (then it slides)
var _sat_wall := Vector3.ZERO # the last wall sat on this time in the air (one sit per wall)


func _init(t: MovementTuning = null) -> void:
	tuning = t if t else MovementTuning.new()
	grapple = Grapple.new(tuning)


## Advance the body by one physics step.
func step(body: CharacterBody3D, input: PlayerInput, delta: float) -> void:
	var t := tuning
	_bind_shape(body)
	_update_gravity(body, delta)
	var vel := body.velocity
	var grounded := body.is_on_floor() and not warped
	warped = false

	if grounded:
		_since_ground = 0.0
		_used_wall = Vector3.ZERO
		_air_dive_used = false
		_flip_used = false
		_flip_left = 0.0
		_glide_used = 0.0
		_hang_left = t.hang_time
		_slam_used = false
		_sat_wall = Vector3.ZERO
	else:
		_since_ground += delta
	hanging = false
	if input.jump_pressed:
		_jump_buffer = t.jump_buffer
	else:
		_jump_buffer = max(_jump_buffer - delta, 0.0)
	# The jetpack's hold (see space_jet): a fresh press, letting go or the floor start it again.
	if input.jump_pressed or not input.jump_held or grounded:
		_jet_hold = 0.0
	else:
		_jet_hold += delta
	var jetting := space_jet   # (the jetpack is flying this step: the boots do not tip up for a held Space)
	space_jet = false          # (worked out again at the end of the step)
	_since_slide_boost += delta
	_since_wall += delta
	_since_dive += delta
	_flip_left = max(_flip_left - delta, 0.0)
	since_boost += delta
	grapple.held = input.grapple
	grapple.update(delta)
	grapple.follow_target(body, delta)

	if state == State.MANTLE:
		_step_mantle(body, delta)
		_ease_eye(delta)
		return
	if state == State.SLAM:
		_step_slam(body, delta)
		_ease_eye(delta)
		return

	var wish := _wish_dir(input)
	var wish_speed: float = (t.sprint_speed if input.sprint else t.run_speed) * min(input.move.length(), 1.0)
	var forward := input.move.y > 0.3

	# The crouch and dive keys. With tuning.ctrl_moves (Variant B) either key is one
	# key: pressed going forward it dives (held, it lands you on your belly and you
	# crawl once the slide runs out); pressed going backward it slides you on your back
	# (a crouch once it runs out); otherwise it crouches. It never starts a crouch-slide.
	var crouch_held := input.crouch
	var crouch_pressed := input.crouch_pressed
	var dive_held := input.dive
	var dive_pressed := input.dive_pressed
	var back_slide := false
	if t.ctrl_moves:
		var ctrl := input.crouch or input.dive
		var ctrl_pressed := input.crouch_pressed or input.dive_pressed
		crouch_held = ctrl
		crouch_pressed = false
		dive_held = ctrl
		dive_pressed = ctrl_pressed and forward
		back_slide = ctrl_pressed and input.move.y < -0.3 and grounded

	# --- Grapple: hold to stay on the rope, let go to fly off with your momentum,
	# or jump to let go with an upward kick.
	if input.grapple_pressed and not grapple.attached:
		grapple.fire(body, input)
	var hooked_now := grapple.take_hooked()   # fired a moment ago, its rope has just pulled tight
	if (grapple.attached or grapple.busy()) and not input.grapple:
		grapple.release()   # (a hook still in flight is called back)
	var rope_jump := false
	if grapple.attached and _jump_buffer > 0.0 and not grounded:
		grapple.release()
		_jump_buffer = 0.0
		rope_jump = true
	if dove_in:
		if not grapple.attached:
			dove_in = false
			if state == State.GRAPPLE and not grounded and not rope_jump:
				state = State.DIVE   # let go before arriving: the dive carries on
		elif grounded:
			# Down on the floor still on the rope: as the dive would have landed (the rope
			# takes a roll over again at once, below; on your belly it drags you).
			dove_in = false
			if dive_held:
				vel = _start_belly_slide(vel)
		else:
			# Arrived (from here it is a plain swing): where the pull fades, or no longer
			# closing on the hook (swinging round it, or held up against something).
			var to_hook := grapple.anchor - grapple.rope_origin(body)
			_dove_slow = _dove_slow + delta if vel.dot(to_hook.normalized()) < DIVE_IN_SLOW else 0.0
			if to_hook.length() <= t.grapple_pull_stop or _dove_slow >= DIVE_IN_SLOW_TIME:
				dove_in = false

	if grapple.attached or state == State.WALL_RUN or state == State.WALL_SIT:
		_flip_used = false   # swinging or wall-running gives your flip back
		_glide_used = 0.0           # ...and starts your glide afresh
		_hang_left = t.hang_time    # ...and your hang

	# --- Glide: the glide key held in the air, having been pressed there. Letting go,
	# landing or catching the rope ends it. Every other move below simply takes
	# over from it, and then it needs a fresh press to start again.
	if _glide_on and state != State.GLIDE:
		_glide_on = false
		_glide_wanted = false
	if not input.glide or grounded or state == State.WALL_RUN:
		_glide_wanted = false
	elif input.glide_pressed:
		_glide_wanted = true
	if state == State.GLIDE:
		if grounded or grapple.attached or not _glide_wanted:
			state = State.AIR
			_glide_on = false
	elif _glide_wanted and _can_glide(body, grounded):
		vel = _start_glide(vel)

	# --- Dive (and the roll when you land from one)
	var diving_now := false
	if dive_pressed and _can_dive(grounded):
		vel = _start_dive(vel, input, grounded)
		diving_now = true
	if state == State.DIVE and grounded and not diving_now:
		if dive_held:
			vel = _start_belly_slide(vel)   # still holding dive: land on your belly
		else:
			state = State.ROLL
			_roll_left = tuning.roll_time
	if state == State.BELLY_SLIDE and not grounded:
		state = State.AIR   # slid off an edge
	if state == State.ROLL:
		_roll_left -= delta
		if not grounded:
			state = State.AIR   # rolled off an edge
		elif _roll_left <= 0.0:
			state = State.GROUND
			if crouch_held and not t.ctrl_moves and Vector2(vel.x, vel.z).length() >= t.slide_start_speed:
				vel = _start_slide(vel)   # roll straight into a slide
	if state == State.DIVE and grapple.attached and not grounded and not diving_now:
		# The rope has pulled tight in a dive: it is the rope's move now (see dove_in).
		state = State.GRAPPLE
		if grapple.rope_origin(body).distance_to(grapple.anchor) > t.grapple_pull_stop + DIVE_IN_MIN:
			dove_in = true
			_dove_slow = 0.0
			dove_side = 1 if input.move.x > 0.3 else (-1 if input.move.x < -0.3 else 0)
	var low_move := state in [State.DIVE, State.ROLL, State.BELLY_SLIDE]

	# --- Crouch (or tuck your legs in the air). Diving and rolling are low too, and
	# a belly slide is lower still. Let go of dive (or jump) to get up from your belly.
	# With tuning.always_tuck the legs tuck by themselves a moment after you leave the
	# floor (not on a wall, where they come down to run or sit).
	var want_prone := state == State.BELLY_SLIDE and dive_held and _jump_buffer <= 0.0
	_auto_tuck = t.always_tuck and not grounded and _since_ground > t.coyote_time and not crouch_held \
		and state not in [State.WALL_RUN, State.WALL_SIT, State.MANTLE]
	_update_crouch(body, crouch_held or low_move or _auto_tuck, want_prone, grounded, delta)
	if state == State.BELLY_SLIDE and not prone:
		state = State.GROUND   # up on your feet (or crouched, if there is no room to stand)
		low_move = false
		if crouch_held and not t.ctrl_moves and Vector2(vel.x, vel.z).length() >= t.slide_start_speed:
			vel = _start_slide(vel)   # up from your belly straight into a slide

	# --- Vault over low obstacles; grab and climb higher ledges while in the air
	if forward and not low_move and not grapple.attached and not rope_jump and vel.y < t.jump_velocity:
		var ledge := SurfaceProbe.find_ledge(body, _facing(input), t, t.crouch_height)
		if not ledge.is_empty() and _start_mantle(ledge, grounded, vel):
			_step_mantle(body, delta)
			_ease_eye(delta)
			return

	# --- Walls
	var wall := Vector3.ZERO
	if not grounded and not grapple.attached:
		wall = SurfaceProbe.find_wall(body, vel, wall_normal, eye_height - 0.6, t.wall_reach)
		if wall != Vector3.ZERO:
			_recent_wall = wall
			_since_wall = 0.0
	if state == State.WALL_RUN and not _keep_wall_running(wall, vel, forward, grounded):
		_end_wall_run()
	if state == State.WALL_SIT and not _keep_wall_sitting(wall, wish, grounded):
		_end_wall_sit()

	var jumping := _jump_buffer > 0.0 and _since_ground <= t.coyote_time and not prone
	var wall_jump := false
	if not jumping and _jump_buffer > 0.0 and not grounded and not grapple.attached:
		var kick := wall if wall != Vector3.ZERO else (_recent_wall if _since_wall <= t.wall_jump_grace else Vector3.ZERO)
		if kick != Vector3.ZERO and (state == State.WALL_RUN or state == State.WALL_SIT or _wall_is_fresh(kick)):
			wall_jump = true
			_jump_buffer = 0.0
			vel = _wall_jump(vel, kick)

	if not wall_jump and state != State.WALL_RUN and state != State.WALL_SIT and _can_start_wall_run(body, wall, vel, forward, grounded):
		_start_wall_run(wall)
		vel.y = clamp(vel.y, -1.0, t.wall_run_max_rise)
	elif not wall_jump and state != State.WALL_RUN and state != State.WALL_SIT:
		var sit_on := _wall_to_sit_on(body, wall, wish, vel, grounded)
		if sit_on != Vector3.ZERO:
			_start_wall_sit(sit_on)

	# A mid-air jump that isn't a wall jump is a flip: a small lift upward (no push
	# along, so no speed to keep), once per jump. Pressed close above the floor, it is kept
	# as a buffered jump for when you land instead (so bunny-hops still work).
	# With tuning.space_boost it fires the rocket boots instead (see _space_boost).
	var mid_air_jump: bool = input.jump_pressed and not jumping and not wall_jump and not rope_jump and not grounded \
			and not grapple.attached and state != State.MANTLE \
			and not SurfaceProbe.floor_within(body, max(1.0, -vel.y * t.jump_buffer + 0.3))
	var flipping := false
	if mid_air_jump and t.flips_on and not t.space_boost and not _flip_used:
		flipping = true
		_flip_used = true
		_jump_buffer = 0.0
	var space_boost := _space_boost(mid_air_jump, input, grounded, delta)

	var hspeed := Vector2(vel.x, vel.z).length()
	if wall_jump:
		state = State.AIR
		vel.y = max(vel.y - t.gravity * gravity_scale * delta, -t.max_fall_speed)
	elif state == State.WALL_RUN:
		vel = _wall_run(vel, delta)
	elif state == State.WALL_SIT:
		vel = _wall_sit(vel, delta)
	elif state == State.GLIDE:
		vel = _glide(vel, delta)
	elif state == State.DIVE:
		if not diving_now:
			vel = _accelerate(vel, wish, min(wish_speed, t.air_speed), t.dive_air_accel, delta)
			vel.y = max(vel.y - t.gravity * gravity_scale * delta, -t.max_fall_speed)
	elif state == State.ROLL:
		vel = _roll(vel, wish, delta)
	elif state == State.BELLY_SLIDE:
		vel = _belly_slide(body, vel, wish, input, delta)
	elif grapple.attached and not grounded:
		# Swinging: gravity plus stronger air steering (to pump the swing), then
		# the rope removes any motion that would stretch it.
		state = State.GRAPPLE
		vel = _accelerate(vel, wish, min(wish_speed, t.air_speed), t.grapple_air_accel, delta)
		vel.y = max(vel.y - t.gravity * gravity_scale * delta, -t.max_fall_speed)
	elif grounded and not jumping:
		var just_landed := state not in [State.GROUND, State.CROUCH, State.SLIDE]
		if state == State.SLIDE and (not crouched or hspeed < t.slide_end_speed):
			state = State.GROUND
		elif state != State.SLIDE and crouched and not t.ctrl_moves and hspeed >= t.slide_start_speed and (crouch_pressed or just_landed):
			vel = _start_slide(vel)
		elif back_slide and crouched and hspeed >= t.slide_end_speed:
			vel = _start_slide(vel)   # Variant B: onto your back (too slow for that, it is just a crouch)
		if state == State.SLIDE:
			vel = _slide(body, vel, wish, delta)
		else:
			state = State.CROUCH if crouched else State.GROUND
			var top: float = t.crouch_speed * min(input.move.length(), 1.0) if crouched else wish_speed
			vel = _apply_friction(vel, top, delta)
			vel = _accelerate(vel, wish, top, t.ground_accel, delta)
			vel.y = min(vel.y, 0.0)
	else:
		# In the air, and also on the exact frame a well-timed jump leaves the ground:
		# no friction that frame, so a jump pressed just before landing keeps all
		# your speed (bunny-hopping). Air steering can add speed when you strafe
		# and turn together (air-strafing), but never takes speed away.
		state = State.FLIP if _flip_left > 0.0 else State.AIR
		if not grounded:
			vel = _air_brake(vel, wish, delta)
		vel = _accelerate(vel, wish, min(wish_speed, t.air_speed), t.air_accel, delta)
		if not grounded:
			if hang and state == State.AIR and _hang_left > 0.0 and since_boost > 0.3 and not jumping:
				vel = _hang(vel, delta)
			else:
				vel.y = max(vel.y - t.gravity * gravity_scale * delta, -t.max_fall_speed)

	if jumping or wall_jump or rope_jump:
		_jet_hold = 0.0   # (a jump pressed a moment ago, buffered: the jetpack's hold starts from the jump)
	if jumping:
		vel.y = t.jump_velocity
		_jump_buffer = 0.0
		_since_ground = t.coyote_time + 1.0  # spend the coyote window
		state = State.AIR
	if rope_jump:
		vel.y = max(vel.y, 0.0) + t.grapple_jump_boost
		state = State.AIR
	if flipping:
		vel = _flip(vel, wish, input)
	if space_boost and since_boost >= t.boost_cooldown:
		vel = _boost(vel, input, grounded, false)

	if grapple.attached:
		# Reel in: a yank when the hook catches, then a steady pull toward it.
		if hooked_now:
			vel = grapple.yank(body, vel)
			vel = grapple.yank_lift(body, vel)
			if grounded and (grapple.target != null or grapple.anchor.y > grapple.rope_origin(body).y):
				vel.y = max(vel.y, t.grapple_hop)   # pop off the floor instead of dragging along it
		vel = grapple.pull(body, vel, delta)
		vel = grapple.lift(body, vel, delta)
		vel = grapple.constrain_velocity(body, vel, delta)
		if grounded and state != State.BELLY_SLIDE:
			state = State.GRAPPLE if vel.y > 0.1 else State.GROUND
			if vel.y > 0.1:
				_since_ground = t.coyote_time + 1.0   # pulled off the floor

	if input.boost_pressed and since_boost >= t.boost_cooldown:
		vel = _boost(vel, input, grounded, not jetting)   # (flying the jetpack, a held Space is its, not a tip up)

	if _knock != Vector3.ZERO:
		if state == State.GLIDE:
			if _knock.y > 0.5:
				state = State.AIR   # a real shove knocks you out of a glide
			else:
				_knock.y = 0.0      # a nudge (a bullet, your own lunge) pushes you along, no lift
		if state == State.WALL_SIT and _knock.length() > 2.0:
			_end_wall_sit()   # shoved off the wall
		vel += _knock
		if _knock.y > 0.5 and state in [State.GROUND, State.CROUCH, State.SLIDE, State.ROLL, State.BELLY_SLIDE]:
			state = State.AIR   # knocked off your feet
			_since_ground = t.coyote_time + 1.0
		_knock = Vector3.ZERO
	vel = _cap_speed(vel)
	body.velocity = vel
	body.move_and_slide()
	_measure_impact(body, vel)
	if grapple.attached:
		grapple.correct_position(body)
	_ease_eye(delta)
	space_jet = has_jetpack and input.jump_held and _jet_hold >= t.space_hold_time and not body.is_on_floor() \
		and not grapple.attached and state in [State.AIR, State.FLIP, State.DIVE]


## Rocket boots: a burst toward where you push (see the top of this file).
## tip_up: holding jump tips it upward (not for a burst fired by the jump key itself, nor
## while a held jump flies the jetpack).
func _boost(vel: Vector3, input: PlayerInput, grounded: bool, tip_up: bool = true) -> Vector3:
	var t := tuning
	if state == State.GLIDE:
		return _glide_boost(vel, input)
	var dir := input.boost_dir
	if dir == Vector3.ZERO:
		var look := Basis.from_euler(Vector3(input.pitch, input.yaw, 0.0))
		dir = look * Vector3(input.move.x, 0.0, -input.move.y) if input.move.length() > 0.2 else look * Vector3.FORWARD
		if input.jump_held and tip_up:
			dir += Vector3.UP * 0.6   # holding jump tips the burst upward
	if dir.length_squared() < 0.0001:
		return vel
	dir = dir.normalized()
	# Fighting your own momentum? The burst first cancels what you have the other way.
	var against := vel.dot(dir)
	if against < 0.0:
		vel -= dir * maxf(against, -t.boost_speed * 0.5)
	vel += dir * t.boost_speed
	since_boost = 0.0
	boosts += 1
	if state in [State.MANTLE, State.ROLL, State.BELLY_SLIDE, State.WALL_RUN, State.WALL_SIT]:
		_leave_wall()
		state = State.AIR
	if grounded:
		vel.y = maxf(vel.y, t.boost_ground_lift)   # off the floor, so friction doesn't eat it
		state = State.AIR
		_since_ground = t.coyote_time + 1.0
	return vel


func boost_readiness() -> float:
	return clampf(since_boost / tuning.boost_cooldown, 0.0, 1.0)


## A hit or a shove: added to your speed on the next step (and lifts you off the
## ground if it pushes upward at all), so it carries through every move.
func knock(push: Vector3) -> void:
	_knock += push


func _measure_impact(body: CharacterBody3D, vel: Vector3) -> void:
	impact_speed = 0.0
	for i in body.get_slide_collision_count():
		var c := body.get_slide_collision(i)
		var normal := c.get_normal()
		if normal.y > 0.7 or c.get_collider() is CharacterBody3D:
			continue   # a floor (landing), or another player
		if grapple.attached and c.get_position().distance_to(grapple.anchor) < 2.5:
			continue   # reeled into your own hook point: that's arriving, not a crash
		var into := -vel.dot(normal)
		if into > impact_speed:
			impact_speed = into
			impact_point = c.get_position()


func horizontal_speed(body: CharacterBody3D) -> float:
	return Vector2(body.velocity.x, body.velocity.z).length()


## Crouching, sliding, or legs tucked in the air: the short body shape.
func is_low() -> bool:
	return crouched



## Forget everything in progress (respawn, teleport).
## The body's gravity for this step: the zone it stands in, eased over a second
## when that changes (walking out through a doorway), times the map event's.
## After reset() (a respawn, a teleport) the zone it finds itself in counts at once.
func _update_gravity(body: Node3D, delta: float) -> void:
	var here := WorldGravity.zone_at(body.global_position + Vector3(0, tuning.stand_height * 0.5, 0))
	if _zone_to < 0.0:
		_zone_from = here
		_zone_to = here
		_zone_t = 1.0
	elif not is_equal_approx(here, _zone_to):
		_zone_from = zone_scale
		_zone_to = here
		_zone_t = 0.0
	if _zone_t < 1.0:
		_zone_t = minf(_zone_t + delta / WorldGravity.BLEND_TIME, 1.0)
	zone_scale = lerpf(_zone_from, _zone_to, smoothstep(0.0, 1.0, _zone_t))
	gravity_scale = WorldGravity.scale * zone_scale
	grapple.gravity_scale = gravity_scale


func reset() -> void:
	grapple.reset()
	_zone_to = -1.0
	_knock = Vector3.ZERO
	impact_speed = 0.0
	state = State.AIR
	wall_normal = Vector3.ZERO
	_used_wall = Vector3.ZERO
	_mantle = {}
	_jump_buffer = 0.0
	_since_dive = 99.0
	dove_in = false
	since_boost = 99.0
	_air_dive_used = false
	_flip_used = false
	_roll_left = 0.0
	_flip_left = 0.0
	_glide_used = 0.0
	_glide_wanted = false
	_glide_on = false
	hang = false
	hanging = false
	_hang_left = tuning.hang_time
	_slam_used = false
	_slam_landing = -1.0
	space_jet = false
	_space_tap = -1.0
	_jet_hold = 0.0
	_auto_tuck = false
	_sit_left = 0.0
	_sat_wall = Vector3.ZERO
	if crouched and _shape:
		_set_height(tuning.stand_height)
	crouched = false
	prone = false
	tuck = 0.0
	eye_height = MovementTuning.EYE_HEIGHT


# ---------------------------------------------------------------------------
# Crouch

func _bind_shape(body: CharacterBody3D) -> void:
	if _shape:
		return
	for c in body.get_children():
		if c is CollisionShape3D and c.shape is CapsuleShape3D:
			_shape = c
			return


func _set_height(h: float) -> void:
	(_shape.shape as CapsuleShape3D).height = h
	_shape.position.y = h * 0.5


func _update_crouch(body: CharacterBody3D, want: bool, want_prone: bool, grounded: bool, delta: float) -> void:
	var t := tuning
	var diff := t.stand_height - t.crouch_height
	if grounded:
		tuck = move_toward(tuck, 0.0, TUCK_SETTLE_SPEED * delta)
	if want_prone and not prone:
		# Down on your belly: the feet stay on the floor, the top of the body drops.
		_set_height(t.prone_height)
		prone = true
		crouched = true
		return
	if prone:
		if want_prone:
			return
		# Up to a crouch, if there is room above; otherwise stay down (and crawl).
		if body.test_move(body.global_transform, Vector3(0, t.crouch_height - t.prone_height, 0)):
			return
		_set_height(t.crouch_height)
		prone = false
	if want and not crouched:
		_set_height(t.crouch_height)
		crouched = true
		if not grounded:
			# Tuck the legs up: the head stays where it was.
			body.global_position.y += diff
			eye_height -= diff
			tuck = diff
	elif not want and crouched:
		if grounded:
			if not body.test_move(body.global_transform, Vector3(0, diff, 0)):
				_set_height(t.stand_height)
				crouched = false
		elif tuck < diff * 0.5 and not body.test_move(body.global_transform, Vector3(0, diff, 0)):
			# Crouched since the ground (not a tuck): stand up, feet stay where they are.
			_set_height(t.stand_height)
			crouched = false
		elif not body.test_move(body.global_transform, Vector3(0, -diff, 0)):
			# Legs back down; the head stays where it was.
			body.global_position.y -= diff
			eye_height += diff
			_set_height(t.stand_height)
			crouched = false
			tuck = 0.0
		elif not body.test_move(body.global_transform, Vector3(0, diff, 0)):
			_set_height(t.stand_height)
			crouched = false


func _ease_eye(delta: float) -> void:
	var target := tuning.crouch_eye_height if crouched else MovementTuning.EYE_HEIGHT
	if prone:
		target = tuning.prone_eye_height
	eye_height = move_toward(eye_height, target, tuning.eye_move_speed * delta)


# ---------------------------------------------------------------------------
# Slide

func _start_slide(vel: Vector3) -> Vector3:
	var t := tuning
	state = State.SLIDE
	var h := Vector3(vel.x, 0, vel.z)
	var speed := h.length()
	if _since_slide_boost >= t.slide_boost_cooldown and speed < t.slide_boost_max_speed:
		_since_slide_boost = 0.0
		var boosted: float = min(speed + t.slide_boost, t.slide_boost_max_speed)
		h = h / speed * boosted
	return Vector3(h.x, vel.y, h.z)


## Little friction, a little steering, and gravity pulls you along slopes.
func _slide(body: CharacterBody3D, vel: Vector3, wish: Vector3, delta: float) -> Vector3:
	var t := tuning
	var n := body.get_floor_normal()
	# Gravity along the floor: zero on flat ground, speeds you up downhill.
	var downhill := Vector3(0, -t.gravity * gravity_scale, 0)
	downhill -= n * downhill.dot(n)
	vel += downhill * delta
	var h := Vector3(vel.x, 0, vel.z)
	var speed := h.length()
	if speed > 0.01:
		var dir := h / speed
		if wish != Vector3.ZERO:
			var angle := dir.signed_angle_to(wish, Vector3.UP)
			dir = dir.rotated(Vector3.UP, clamp(angle, -t.slide_turn_rate * delta, t.slide_turn_rate * delta))
		speed = max(speed - t.slide_decel * delta, 0.0)
		h = dir * speed
	return Vector3(h.x, min(vel.y, 0.0), h.z)


# ---------------------------------------------------------------------------
# Walls

## In the air, touching (or just off) a wall that a jump would kick off now. For bots.
func can_wall_jump() -> bool:
	return _since_wall <= tuning.wall_jump_grace * 0.7 and _recent_wall != Vector3.ZERO and _wall_is_fresh(_recent_wall) \
		and state != State.GROUND


## The wall last touched in the air (its normal), for bots.
func last_wall() -> Vector3:
	return _recent_wall


func _wall_is_fresh(n: Vector3) -> bool:
	return _used_wall == Vector3.ZERO or n.dot(_used_wall) < 0.9


func _can_start_wall_run(body: CharacterBody3D, wall: Vector3, vel: Vector3, forward: bool, grounded: bool) -> bool:
	var t := tuning
	if grounded or wall == Vector3.ZERO or not forward or grapple.attached or (crouched and not t.always_tuck):
		return false
	if not _wall_is_fresh(wall):
		return false
	var h := Vector3(vel.x, 0, vel.z)
	var along := h - wall * h.dot(wall)
	if along.length() < t.wall_run_min_speed:
		return false
	return not SurfaceProbe.floor_within(body, t.wall_run_min_height)


func _start_wall_run(wall: Vector3) -> void:
	state = State.WALL_RUN
	wall_normal = wall
	_wall_time = 0.0


func _keep_wall_running(wall: Vector3, vel: Vector3, forward: bool, grounded: bool) -> bool:
	if grounded or not forward or grapple.attached or (crouched and not tuning.always_tuck):
		return false
	if wall == Vector3.ZERO or wall.dot(wall_normal) < 0.7:
		return false
	if _wall_time > tuning.wall_run_max_time:
		return false
	var h := Vector3(vel.x, 0, vel.z)
	return (h - wall * h.dot(wall)).length() >= tuning.wall_run_min_speed * 0.8


func _end_wall_run() -> void:
	_used_wall = wall_normal
	wall_normal = Vector3.ZERO
	state = State.AIR


func _wall_run(vel: Vector3, delta: float) -> Vector3:
	var t := tuning
	_wall_time += delta
	var n := wall_normal
	var h := Vector3(vel.x, 0, vel.z)
	var along := h - n * h.dot(n)
	var speed := along.length()
	var dir := along / speed if speed > 0.01 else Vector3.ZERO
	if speed < t.wall_run_speed:
		speed = min(speed + t.wall_run_accel * delta, t.wall_run_speed)
	h = dir * speed - n * t.wall_stick
	var y: float = max(vel.y - t.wall_run_gravity * gravity_scale * delta, -t.max_fall_speed)
	return Vector3(h.x, y, h.z)


func _wall_jump(vel: Vector3, n: Vector3) -> Vector3:
	var t := tuning
	_leave_wall()
	_used_wall = n
	kick_wall = n
	wall_jumps += 1
	var h := Vector3(vel.x, 0, vel.z)
	var into := h.dot(n)
	if into < 0.0:
		h -= n * into
	# Carry on the way you were running, a little faster (chained kicks don't stack
	# past wall_jump_forward_max).
	var along := h - n * h.dot(n)
	var speed := along.length()
	if speed > 1.0:
		var faster := maxf(speed, minf(speed + t.wall_jump_forward, t.wall_jump_forward_max))
		h += along / speed * (faster - speed)
	h += n * t.wall_jump_push
	return Vector3(h.x, max(vel.y, t.wall_jump_up), h.z)


## Off a wall run or a wall sit, whichever you are on (a move taking over from it).
func _leave_wall() -> void:
	if state == State.WALL_RUN:
		_end_wall_run()
	elif state == State.WALL_SIT:
		_end_wall_sit()


## Wall sit (tuning.wall_sit_time > 0): in a plain fall or near the top of a jump,
## pushing into a wall you have not sat on yet this time in the air, high enough up.
## Returns that wall's normal, or ZERO for no sit.
func _wall_to_sit_on(body: CharacterBody3D, wall: Vector3, wish: Vector3, vel: Vector3, grounded: bool) -> Vector3:
	var t := tuning
	if t.wall_sit_time <= 0.0 or grounded or grapple.attached or wish == Vector3.ZERO or vel.y > 1.0:
		return Vector3.ZERO
	if state not in [State.AIR, State.FLIP, State.GLIDE]:
		return Vector3.ZERO
	if wall == Vector3.ZERO:
		# Stopped against it, you have no speed to look along: look the way you push.
		wall = SurfaceProbe.find_wall(body, wish, Vector3.ZERO, eye_height - 0.6, t.wall_reach)
	if wall == Vector3.ZERO or wish.dot(-wall) < 0.5:
		return Vector3.ZERO
	if _sat_wall != Vector3.ZERO and wall.dot(_sat_wall) > 0.9:
		return Vector3.ZERO   # one sit per wall until you land
	if SurfaceProbe.floor_within(body, t.wall_run_min_height):
		return Vector3.ZERO
	return wall


func _start_wall_sit(wall: Vector3) -> void:
	state = State.WALL_SIT
	wall_normal = wall
	_sat_wall = wall
	_sit_left = tuning.wall_sit_time


func _keep_wall_sitting(wall: Vector3, wish: Vector3, grounded: bool) -> bool:
	if grounded or grapple.attached:
		return false
	if wall == Vector3.ZERO or wall.dot(wall_normal) < 0.7:
		return false
	return wish.dot(-wall_normal) >= 0.3   # still pushing into it


func _end_wall_sit() -> void:
	wall_normal = Vector3.ZERO
	state = State.AIR


## Stuck to the wall for wall_sit_time, then sliding slowly down it.
func _wall_sit(vel: Vector3, delta: float) -> Vector3:
	var t := tuning
	_sit_left = maxf(_sit_left - delta, 0.0)
	var y := 0.0 if _sit_left > 0.0 else -t.wall_sit_slide_speed * WorldGravity.scale
	return -wall_normal * t.wall_stick + Vector3(0.0, y, 0.0)


## tuning.space_boost: does Space fire the rocket boots this step? A mid-air press
## does at once; with the jetpack, only a tap does (let go within space_hold_time,
## still in the air), since holding it flies the jetpack (space_jet).
func _space_boost(mid_air_jump: bool, input: PlayerInput, grounded: bool, delta: float) -> bool:
	var t := tuning
	if not t.space_boost:
		return false
	var fire := false
	if _space_tap >= 0.0:
		_space_tap += delta
		if not input.jump_held:
			fire = not grounded and _space_tap <= t.space_hold_time
			_space_tap = -1.0
		elif _space_tap > t.space_hold_time:
			_space_tap = -1.0   # a hold: the jetpack's
	if mid_air_jump:
		_jump_buffer = 0.0
		if has_jetpack:
			_space_tap = 0.0
		else:
			fire = true
	return fire


# ---------------------------------------------------------------------------
# Dive, roll and flip

## Debug menu ("No cooldowns"): the grapple, dive and slide boost are ready again.
func clear_cooldowns() -> void:
	grapple.cooldown_left = 0.0
	since_boost = 99.0
	_since_dive = 99.0
	_since_slide_boost = 99.0


## HUD readouts: how ready each move is, from 0 (just used) to 1 (ready).
func dive_readiness() -> float:
	if _air_dive_used:
		return 0.0   # already dived on this jump
	return clampf(_since_dive / tuning.dive_cooldown, 0.0, 1.0)


func flip_readiness() -> float:
	return 0.0 if _flip_used else 1.0


func slide_boost_readiness() -> float:
	return clampf(_since_slide_boost / tuning.slide_boost_cooldown, 0.0, 1.0)


## Winding a melee swing up in mid-air: the fall is braked to a slow sink, and a
## rise loses most of gravity, for hang_time seconds per time in the air. Sideways
## speed is kept. Any other move takes over from it (it only works in a plain fall).
func _hang(vel: Vector3, delta: float) -> Vector3:
	var t := tuning
	_hang_left = maxf(_hang_left - delta, 0.0)
	hanging = true
	if vel.y > -t.hang_fall_speed:
		vel.y = maxf(vel.y - t.gravity * t.hang_gravity * gravity_scale * delta, -t.hang_fall_speed)
	else:
		vel.y = minf(vel.y + t.hang_brake * delta, -t.hang_fall_speed)
	return vel


## How much of this air time's hang is left, 1..0.
func hang_readiness() -> float:
	return clampf(_hang_left / tuning.hang_time, 0.0, 1.0)


## A ground slam can start: in the air, not yet done this time in the air, with
## room to fall, and not in a move that has you tied up.
func can_slam(body: CharacterBody3D) -> bool:
	if body.is_on_floor() or _slam_used or state in [State.SLAM, State.MANTLE, State.WALL_RUN, State.BELLY_SLIDE, State.ROLL]:
		return false
	return not SurfaceProbe.floor_within(body, tuning.slam_min_height)


## Drive straight down (see _step_slam). Nothing stops it but the floor.
func start_slam(body: CharacterBody3D) -> void:
	if grapple.attached or grapple.busy():
		grapple.release()
	_leave_wall()
	state = State.SLAM
	_slam_used = true
	_slam_time = 0.0
	_slam_from = body.global_position.y
	_slam_landing = -1.0
	_glide_on = false
	_glide_wanted = false
	_flip_left = 0.0
	_knock = Vector3.ZERO
	body.velocity = Vector3(body.velocity.x * 0.25, minf(body.velocity.y, 0.0), body.velocity.z * 0.25)


## A ground slam: straight down at slam_speed, whatever gravity is doing, with the
## sideways speed bled away. No move, shove or key changes it; it ends on the floor
## (take_slam_landing then says from how high), or after slam_timeout with none found.
func _step_slam(body: CharacterBody3D, delta: float) -> void:
	var t := tuning
	_slam_time += delta
	_knock = Vector3.ZERO
	var vel := body.velocity
	var bleed := exp(-8.0 * delta)
	vel = Vector3(vel.x * bleed, maxf(vel.y - t.slam_accel * delta, -t.slam_speed), vel.z * bleed)
	body.velocity = vel
	body.move_and_slide()
	if body.is_on_floor():
		_slam_landing = maxf(_slam_from - body.global_position.y, 0.0)
		state = State.GROUND
		_since_ground = 0.0
		body.velocity = Vector3.ZERO
	elif _slam_time >= t.slam_timeout:
		state = State.AIR


## Has a ground slam just landed? Returns how far it fell (metres) once, then -1.
func take_slam_landing() -> float:
	var fell := _slam_landing
	_slam_landing = -1.0
	return fell


## How strong the glide still is this time in the air: 1 = fresh, 0 = it has
## weakened into a plain fall (until you land, run a wall or catch the rope).
func glide_readiness() -> float:
	return clampf(1.0 - _glide_used / tuning.glide_fade_time, 0.0, 1.0)


func _can_dive(grounded: bool) -> bool:
	if _since_dive < tuning.dive_cooldown or grapple.attached:
		return false
	if state in [State.MANTLE, State.DIVE, State.ROLL, State.BELLY_SLIDE]:
		return false
	return grounded or not _air_dive_used


func _start_dive(vel: Vector3, input: PlayerInput, grounded: bool) -> Vector3:
	var t := tuning
	_leave_wall()
	var dir := _facing(input)
	var h := Vector3(vel.x, 0, vel.z)
	var along := h.dot(dir)
	if along < t.dive_max_speed:
		h += dir * min(t.dive_boost, t.dive_max_speed - max(along, 0.0))
	if h.dot(dir) < t.run_speed:
		h += dir * (t.run_speed - h.dot(dir))   # a dive always carries you forward
	state = State.DIVE
	_since_dive = 0.0
	if not grounded:
		_air_dive_used = true
	var y: float = t.dive_hop if grounded else max(vel.y, t.dive_air_up)
	return Vector3(h.x, y, h.z)


## Rolling: keeps your speed, with a little steering.
func _roll(vel: Vector3, wish: Vector3, delta: float) -> Vector3:
	var h := Vector3(vel.x, 0, vel.z)
	var speed := h.length()
	if speed > 0.01 and wish != Vector3.ZERO:
		var dir := h / speed
		var angle := dir.signed_angle_to(wish, Vector3.UP)
		var turn := tuning.roll_turn_rate * delta
		h = dir.rotated(Vector3.UP, clamp(angle, -turn, turn)) * speed
	return Vector3(h.x, min(vel.y, 0.0), h.z)


## Landing from a dive with the dive button still held: onto your belly, with a
## small push forward.
func _start_belly_slide(vel: Vector3) -> Vector3:
	var t := tuning
	state = State.BELLY_SLIDE
	var h := Vector3(vel.x, 0, vel.z)
	var speed := h.length()
	if speed > 0.01 and speed < t.dive_max_speed:
		h = h / speed * min(speed + t.belly_boost, t.dive_max_speed)
	return Vector3(h.x, vel.y, h.z)


## Sliding on your front: like a slide (little friction, gravity pulls you down
## slopes) but harder to steer. Once it slows to a crawl, you crawl.
func _belly_slide(body: CharacterBody3D, vel: Vector3, wish: Vector3, input: PlayerInput, delta: float) -> Vector3:
	var t := tuning
	var h := Vector3(vel.x, 0, vel.z)
	var speed := h.length()
	var n := body.get_floor_normal()
	# Crawling, unless the floor is steep enough to slide you off again (a belly slide
	# down a chute that slowed to a crawl picks up speed, rather than crawling on down).
	if speed <= t.belly_crawl_speed + 0.05 and n.y > BELLY_SLOPE:
		var top: float = t.belly_crawl_speed * min(input.move.length(), 1.0)
		vel = _apply_friction(vel, top, delta)
		vel = _accelerate(vel, wish, top, t.ground_accel, delta)
		return Vector3(vel.x, min(vel.y, 0.0), vel.z)
	var downhill := Vector3(0, -t.gravity * gravity_scale, 0)
	downhill -= n * downhill.dot(n)
	vel += downhill * delta
	h = Vector3(vel.x, 0, vel.z)
	speed = h.length()
	var dir := h / speed
	if wish != Vector3.ZERO:
		var angle := dir.signed_angle_to(wish, Vector3.UP)
		dir = dir.rotated(Vector3.UP, clamp(angle, -t.belly_turn_rate * delta, t.belly_turn_rate * delta))
	speed = max(speed - t.belly_decel * delta, t.belly_crawl_speed)
	h = dir * speed
	return Vector3(h.x, min(vel.y, 0.0), h.z)


func _flip(vel: Vector3, wish: Vector3, input: PlayerInput) -> Vector3:
	var t := tuning
	state = State.FLIP
	_flip_left = t.flip_time
	flip_dir = input.move.limit_length(1.0).normalized() if wish != Vector3.ZERO else Vector2(0, -1)  # no direction: backflip
	# Only a lift, to bridge a longer gap: the way you are going and your speed along
	# it stay as they were (WASD only picks which way the body turns over).
	return Vector3(vel.x, max(vel.y, t.flip_up), vel.z)


# ---------------------------------------------------------------------------
# Glide

func _can_glide(body: CharacterBody3D, grounded: bool) -> bool:
	if not tuning.glides_on or grounded or grapple.attached or state == State.WALL_RUN:
		return false
	# Pressed as you leave or reach the floor: no glide.
	return not SurfaceProbe.floor_within(body, tuning.glide_min_height)


## Onto the track: the way you are going, at the speed you have. (Your rise or fall
## eases out over the next moment: see _glide.)
func _start_glide(vel: Vector3) -> Vector3:
	state = State.GLIDE
	_glide_on = true
	_flip_left = 0.0   # gliding out of a flip: the flip is over
	return vel


## Gliding: no steering and no drag, so you hold your line and your speed. Up and
## down eases to the glide's sink, which is next to nothing at first and builds the
## longer you have glided this time in the air (see glide_sink), until it is a plain
## fall and gravity takes over in full.
func _glide(vel: Vector3, delta: float) -> Vector3:
	var t := tuning
	_glide_used += delta
	if _glide_used >= t.glide_fade_time:
		vel.y = maxf(vel.y - t.gravity * gravity_scale * delta, -t.max_fall_speed)
	else:
		vel.y = lerpf(vel.y, -glide_sink(_glide_used), 1.0 - exp(-t.glide_catch * delta))
	return vel


## How fast a glide `used` seconds old sinks (m/s): the speed a fall would have
## reached by then under a pull that starts at nothing and grows to full gravity at
## glide_fade_time, as (used / glide_fade_time) ^ glide_fade_curve. Flat for a while,
## then curving down.
func glide_sink(used: float) -> float:
	var t := tuning
	var f := clampf(used / t.glide_fade_time, 0.0, 1.0)
	var c := t.glide_fade_curve
	return minf(t.gravity * gravity_scale * t.glide_fade_time / (c + 1.0) * pow(f, c + 1.0), t.max_fall_speed)


## Rocket boots while gliding: the burst turns the whole glide the way you press
## (WASD as seen from the way you face; forward if you hold nothing), carrying
## all the speed you had plus the burst's. You keep gliding.
func _glide_boost(vel: Vector3, input: PlayerInput) -> Vector3:
	var t := tuning
	var dir := Vector3(input.boost_dir.x, 0.0, input.boost_dir.z)   # a bot's aim, kept level
	if dir.length_squared() < 0.0001:
		dir = _wish_dir(input)
	if dir.length_squared() < 0.0001:
		dir = _facing(input)
	dir = dir.normalized()
	var speed := Vector2(vel.x, vel.z).length() + t.boost_speed
	since_boost = 0.0
	boosts += 1
	return Vector3(dir.x * speed, vel.y, dir.z * speed)


# ---------------------------------------------------------------------------
# Vault and ledge climb

func _facing(input: PlayerInput) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, input.yaw)


func _start_mantle(ledge: Dictionary, grounded: bool, vel: Vector3) -> bool:
	var t := tuning
	var lip: float = ledge.lip
	if lip < t.vault_min_height:
		return false
	var vault: bool = lip <= t.vault_max_height
	if not vault and (grounded or lip > t.ledge_max_height):
		return false  # higher ledges are grabbed only when you jump at them
	var hspeed := Vector2(vel.x, vel.z).length()
	_mantle = {
		"top": ledge.top + 0.05,
		"dir": -(ledge.normal as Vector3),
		"up": t.vault_up_speed if vault else t.ledge_up_speed,
		# A vault keeps your speed; climbing a ledge slows you down.
		"exit": max(hspeed, t.run_speed) if vault else t.ledge_exit_speed,
		"time": 0.0,
		"vault": vault,
	}
	_leave_wall()
	state = State.MANTLE
	return true


func _step_mantle(body: CharacterBody3D, delta: float) -> void:
	_mantle.time += delta
	var dir: Vector3 = _mantle.dir
	if body.global_position.y >= _mantle.top or _mantle.time > 0.9:
		# Over the lip: carry on forward.
		state = State.AIR
		body.velocity = dir * _mantle.exit
		_mantle = {}
	else:
		body.velocity = Vector3(0, _mantle.up, 0) + dir * 0.5
	body.move_and_slide()


## True for the frame-by-frame life of a vault (not a ledge climb). For animation.
func is_vaulting() -> bool:
	return state == State.MANTLE and _mantle.get("vault", false)


# ---------------------------------------------------------------------------
# Shared helpers

func _wish_dir(input: PlayerInput) -> Vector3:
	var m := input.move.limit_length(1.0)
	var local := Vector3(m.x, 0.0, -m.y)
	return local.rotated(Vector3.UP, input.yaw).normalized() if local.length_squared() > 0.0001 else Vector3.ZERO


## tuning.max_speed (Variant B): sideways speed never goes past it, whatever got you
## there (boosts, swings, knockback, the jetpack). Falling is not limited here.
func _cap_speed(vel: Vector3) -> Vector3:
	var top := tuning.max_speed
	if top <= 0.0:
		return vel
	var h := Vector2(vel.x, vel.z)
	if h.length() <= top:
		return vel
	h = h.normalized() * top
	return Vector3(h.x, vel.y, h.y)


## True while the legs are tucked by tuning.always_tuck rather than by the crouch key
## (your own first-person body does not show that tuck).
func auto_tucked() -> bool:
	return _auto_tuck and crouched and not prone


## tuning.air_brake (Variant B): pressing against the way you are moving in a jump or
## fall brakes that motion this much harder, down to a stop and never past it (from
## there, air steering takes you the other way as usual).
func _air_brake(vel: Vector3, wish: Vector3, delta: float) -> Vector3:
	if tuning.air_brake <= 0.0 or wish == Vector3.ZERO:
		return vel
	var h := Vector3(vel.x, 0.0, vel.z)
	var speed := h.length()
	if speed < 0.01 or h.dot(wish) > -0.5 * speed:
		return vel   # not pressing against it (within 60 degrees of straight back)
	var against := -h.dot(wish)   # the speed you are pushing back on
	return vel + wish * minf(tuning.air_brake * delta, against)


## Speed up toward wish_speed along wish, never cutting speed you already have.
## This is what lets momentum from jumps, swings and slides carry through.
func _accelerate(vel: Vector3, wish: Vector3, wish_speed: float, accel: float, delta: float) -> Vector3:
	if wish == Vector3.ZERO:
		return vel
	var current := vel.dot(wish)
	var add := wish_speed - current
	if add <= 0.0:
		return vel
	var gain: float = min(accel * wish_speed * delta, add)
	return vel + wish * gain


func _apply_friction(vel: Vector3, wish_speed: float, delta: float) -> Vector3:
	var t := tuning
	var h := Vector3(vel.x, 0.0, vel.z)
	var speed := h.length()
	if speed < 0.01:
		return Vector3(0.0, vel.y, 0.0)
	var top: float = max(wish_speed, t.run_speed)
	var f: float = t.overspeed_friction if speed > top + 0.5 else t.friction
	var drop: float = max(speed, t.stop_speed) * f * delta
	var new_speed: float = max(speed - drop, 0.0)
	h *= new_speed / speed
	return Vector3(h.x, vel.y, h.z)
