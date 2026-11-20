class_name MovementTuning
extends Resource
## Every number that shapes how movement feels lives here, in one place.
## Distances are metres, speeds metres/second, times seconds.
## Values are first guesses to be tuned by playtesting.

const EYE_HEIGHT := 1.6  ## eyes above the feet, standing
const BODY_RADIUS := 0.4

## Movement variants, for A/B testing how movement feels. The host picks one in the
## lobby (LobbySettings.movement) and every player in the match runs it. There is one
## variant today: "b" (the numbers below with the changes in _apply_b). Classic (the
## plain numbers, with Shift-glide and the crouch-slide on C) is retired: an old
## "classic" choice (saved settings, an older host) now means "b". The A/B setup is kept
## so a new variant can be tried later: add its id to VARIANTS, give each mechanic it
## changes a switch here (an @export bool), have MovementController check the switch,
## and turn it on in an _apply_ function. Prefer a switch per mechanic over checking
## `variant` in the controller. (While there is only one variant there is nothing to
## pick, so the menus show no movement switch.)
const VARIANTS := ["b"]
const DEFAULT_VARIANT := "b"

var variant := DEFAULT_VARIANT   ## which variant built these numbers (see for_variant)


## `id` if it is a known variant, otherwise the default.
static func valid_variant(id) -> String:
	return str(id) if str(id) in VARIANTS else DEFAULT_VARIANT


## The variant's name for menus and the HUD.
static func variant_name(id) -> String:
	return "Variant B" if valid_variant(id) == "b" else str(id)


## Fresh tuning for a variant. Each player gets their own copy: Player changes some
## speeds in place for its weapon's speed bonus, so a shared one would leak between players.
static func for_variant(id) -> MovementTuning:
	var t := MovementTuning.new()
	t.variant = valid_variant(id)
	if t.variant == "b":
		t._apply_b()
	return t


## Variant B: its numbers and mechanic switches, set over the plain ones.
##  - Space in mid-air flips, once per jump (boots stay on E);
##  - legs tucked whenever you are in the air, so edges clear without a key (your own
##    body does not show it in first person);
##  - Ctrl (or Q) does crouch, slide and dive: forward dives (then a belly slide, then a
##    crawl while held), back slides on your back (then a crouch while held), otherwise
##    a crouch;
##  - stick to a wall you push into in mid-air for 2.5 seconds, then slide slowly down it;
##  - in a jump or fall, pressing WASD against the way you are moving brakes you much
##    harder (air_brake), so momentum is easy to stop;
##  - sideways speed never goes past 27 m/s, whatever got you there (max_speed);
##  - the glide is on Alt (the bullet glide: see MovementController's GLIDE).
## Run and sprint speeds are the plain ones.
func _apply_b() -> void:
	always_tuck = true
	ctrl_moves = true
	wall_sit_time = 2.5
	air_brake = 30.0
	max_speed = 27.0

@export_group("Ground")
@export var run_speed := 8.0          ## top speed you accelerate to while running
@export var sprint_speed := 11.5      ## top speed while holding sprint
@export var ground_accel := 11.0      ## how quickly you reach top speed
@export var friction := 7.0           ## how quickly you stop when you let go
@export var stop_speed := 3.0         ## below this speed, friction acts as if you were at this speed (crisp stops)
@export var overspeed_friction := 1.6 ## gentler friction when above top speed, so momentum from jumps and swings carries

@export_group("Air")
@export var air_accel := 3.0          ## steering strength in the air
@export var air_speed := 8.0          ## air steering can push you up to this speed, never slows you down
@export var gravity := 22.0             ## (a map event can scale this for a while: see WorldGravity)
@export var max_fall_speed := 55.0

@export_group("Jump")
@export var jump_velocity := 7.2
@export var coyote_time := 0.12       ## you can still jump this long after running off a ledge
@export var jump_buffer := 0.12       ## a jump pressed this long before landing still happens

@export_group("Grapple")
@export var grapple_range := 45.0         ## how far the hook reaches
@export var grapple_cooldown := 0.6       ## seconds after letting go before it can fire again
@export var grapple_min_length := 2.0     ## the rope never gets shorter than this
@export var grapple_attach_height := 1.2  ## where the rope meets the body (chest height)
@export var grapple_air_accel := 6.0      ## steering strength while swinging (lets you pump the swing)
@export var grapple_reel_speed := 0.0     ## metres per second the rope shortens on its own (0 = never)
@export var grapple_jump_boost := 5.5     ## upward kick when you jump off the rope
@export var grapple_pull_accel := 34.0    ## how hard the rope reels you in (gravity is 22, so it lifts you)
@export var grapple_pull_speed := 16.0    ## the pull speeds you toward the hook up to this, never past it
@export var grapple_yank := 9.8           ## instant speed toward the hook when the rope pulls tight
@export var grapple_hop := 4.0            ## hooking from the ground pops you off the floor this fast
@export var grapple_pull_stop := 4.0      ## the pull stops this close to the hook, so you coast in or fly past
@export var grapple_yank_lift := 2.5      ## extra upward speed when the hook catches above you
@export var grapple_pull_lift := 9.0      ## extra upward pull while the hook is above you (fades near the hook)
@export var grapple_lift_max := 14.0      ## the extra lift stops once you rise this fast
## Hooking another player: the rope reels you both together (they get pulled too,
## see Player.tug), harder than a wall hook, and lets go once you meet.
@export var tether_pull_accel := 46.0
@export var tether_pull_speed := 20.0
@export var tether_meet := 2.2            ## let go once this close (chest to chest)
@export var tether_time := 1.6            ## the longest a player stays hooked
@export var player_magnet := 3.0          ## aim this many degrees off another player and the hook still catches them (0 = exact hits only)
@export var tug_accel := 30.0             ## how hard the hooked player is dragged toward you
@export var tug_speed := 11.0             ## up to this speed toward you
@export var tug_lift := 4.0               ## lifts them off their feet when the hook catches

@export_group("Rocket boots")
@export var boost_speed := 14.0           ## speed a burst adds, in the direction you push
@export var boost_ground_lift := 3.5      ## fired on the ground, you leave the floor at least this fast
@export var boost_cooldown := 2.5         ## seconds between bursts

@export_group("Crouch and slide")
@export var stand_height := 1.8           ## body height standing
@export var crouch_height := 1.1          ## body height crouched or sliding
@export var crouch_eye_height := 1.0      ## eyes above the feet while crouched
@export var crouch_speed := 4.0           ## top speed walking crouched
@export var eye_move_speed := 6.0         ## how fast the view moves down/up when you crouch/stand
@export var slide_start_speed := 7.0      ## you need at least this speed to start a slide
@export var slide_end_speed := 4.5        ## the slide ends below this speed
@export var slide_boost := 2.5            ## extra speed when a slide starts...
@export var slide_boost_cooldown := 1.2   ## ...at most once per this many seconds
@export var slide_boost_max_speed := 15.0 ## no boost if you are already this fast
@export var slide_decel := 3.5            ## speed lost per second sliding on flat ground
@export var slide_turn_rate := 1.0        ## how quickly you can steer a slide (radians per second)

@export_group("Walls")
@export var wall_reach := 0.35            ## how close a wall must be (beyond your body) to count
@export var wall_run_min_speed := 6.0     ## you need this much speed along the wall to wall-run
@export var wall_run_speed := 10.5        ## wall-running speeds you up to this (never slows you)
@export var wall_run_accel := 4.0
@export var wall_run_gravity := 4.0       ## gravity while wall-running (normal gravity is 22)
@export var wall_run_max_time := 1.6      ## after this, normal gravity returns and you drop off
@export var wall_run_min_height := 0.8    ## must be this high off the floor to start a wall run
@export var wall_run_max_rise := 4.0      ## upward speed is capped to this when a wall run starts
@export var wall_stick := 1.0             ## small push into the wall so you stay on it
@export var wall_jump_push := 7.0         ## sideways push off the wall
@export var wall_jump_up := 8.2           ## upward speed of a wall jump
@export var wall_jump_forward := 2.5      ## extra speed the way you were running along the wall...
@export var wall_jump_forward_max := 13.0 ## ...but never past this along the wall (so chained kicks don't stack)
@export var wall_jump_grace := 0.15       ## you can still wall-jump this long after leaving a wall

@export_group("Vault and ledges")
@export var mantle_reach := 0.45          ## how far in front of you a ledge is looked for
@export var vault_min_height := 0.45      ## lower than this is just a step
@export var vault_max_height := 1.25      ## up to this height you vault straight over, keeping speed
@export var ledge_max_height := 2.3       ## up to this height (above your feet) you can grab and climb, while in the air
@export var vault_up_speed := 7.5
@export var ledge_up_speed := 4.5
@export var ledge_exit_speed := 5.0       ## speed you leave a ledge climb with

@export_group("Dive and roll")
@export var dive_boost := 4.0             ## forward speed added by a dive (toward where you look)
@export var dive_max_speed := 17.0        ## a dive never pushes you past this speed
@export var dive_hop := 3.5               ## upward speed of a dive from the ground
@export var dive_air_up := 2.0            ## a dive in the air sets your upward speed to at least this
@export var dive_air_accel := 1.0         ## steering while diving (weak)
@export var dive_cooldown := 1.0          ## seconds between dives (and only one dive per jump)
@export var roll_time := 0.45             ## landing from a dive rolls you forward this long, keeping speed
@export var roll_turn_rate := 1.5         ## steering while rolling (radians per second)

@export_group("Belly slide")
@export var prone_height := 0.8           ## body height lying on your front (the capsule cannot be shorter)
@export var prone_eye_height := 0.55      ## eyes above the floor lying down
@export var belly_boost := 1.0            ## extra speed when you hit the ground on your belly
@export var belly_decel := 3.0            ## speed lost per second belly-sliding on flat ground
@export var belly_turn_rate := 0.7        ## how quickly you can steer a belly slide (radians per second)
@export var belly_crawl_speed := 2.0      ## once the slide runs out (dive still held), you can crawl this fast

@export_group("Glide")
## The bullet glide (hold Alt in mid-air): you hold your line and your speed, as long
## as you like, but it weakens: you hardly sink at first, then the fall builds until,
## glide_fade_time seconds in, you are falling as fast as a plain fall would by then
## (and gravity pulls in full from there). The seconds add up over one time in the air.
@export var glide_fade_time := 4.0        ## seconds of gliding (per time in the air) until it is a plain fall
@export var glide_fade_curve := 2.5       ## how long it stays flat before the fall builds (higher = flatter, then steeper)
@export var glide_catch := 15.0           ## how quickly your rise or fall eases to the glide's when you start one (per second; 15 = about 0.2 s)
@export var glide_min_height := 0.5       ## no glide this close above the floor

@export_group("Melee in the air")
@export var hang_time := 0.6              ## winding a melee swing up in mid-air slows your fall: seconds of that per time in the air
@export var hang_fall_speed := 1.5        ## ...down to sinking this fast (m/s)
@export var hang_brake := 60.0            ## ...how hard a fall is braked to that (m/s2)
@export var hang_gravity := 0.25          ## ...and how much of gravity still pulls on you while you rise
@export var slam_speed := 34.0            ## a ground slam drives you straight down this fast (m/s)
@export var slam_accel := 220.0           ## ...reaching it this quickly (m/s2)
@export var slam_min_height := 2.0        ## no slam this close above the floor
@export var slam_timeout := 3.0           ## a slam that has found no floor after this long is let go

@export_group("Jetpack")
## Everyone's jetpack (see Jetpack) flies on Space held in mid-air, once it has been held
## this long there: counted from the press, or from the jump or wall jump it made, so a
## plain jump does not burn fuel (see MovementController.space_jet).
@export var space_hold_time := 0.25

@export_group("Flip")
@export var flip_up := 4.5                ## press jump in mid-air: at least this much upward speed (and no push along)
@export var flip_time := 0.45             ## how long the flip lasts (for the animation)

## Mechanic switches. The plain numbers have every one as below; Variant B changes them (see _apply_b).
@export_group("Mechanic switches")
@export var flips_on := true              ## Space again in mid-air flips (when space_boost is off)
@export var glides_on := true             ## the glide key held in mid-air glides
@export var space_boost := false          ## Space in mid-air fires the rocket boots (with the jetpack: only a tap)
@export var always_tuck := false          ## legs tucked whenever you have been in the air a moment, no key needed
@export var ctrl_moves := false           ## Ctrl or Q: forward dives, back slides on your back, otherwise crouches (no crouch-slide)
@export var wall_sit_time := 0.0          ## push into a wall in mid-air: stick to it this long (0 = never)...
@export var wall_sit_slide_speed := 2.0   ## ...then slide down it this fast while you keep pushing
@export var air_brake := 0.0              ## in a jump or fall, pressing against your motion brakes it this much harder (m/s2, 0 = off)
@export var max_speed := 0.0              ## sideways speed never goes past this, whatever the move (m/s, 0 = no limit)
