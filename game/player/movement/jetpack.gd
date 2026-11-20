class_name Jetpack
extends RefCounted
## Jetpack: everyone has one. Hold Space in mid-air to fly (after a jump or a fall:
## MovementController.space_jet says when). It lifts you up to RISE_SPEED and pushes
## you a little toward WASD, burning fuel as it goes. Fuel comes back when you let go:
## slowly in the air, fast once you stand on the ground. Run dry and it cuts out until
## it has refilled a little (RESTART). None in a race.

const THRUST := 42.0        ## upward push, m/s² (gravity is 22, so a net climb)
const RISE_SPEED := 7.5     ## it stops adding upward speed past this
const STEER := 9.0          ## push toward WASD while flying, m/s²
const STEER_SPEED := 11.0   ## ...up to this much speed that way
const BURN := 0.4           ## fuel per second while flying (full tank: 2.5 s)
const REFILL_AIR := 0.12    ## fuel per second while not flying, in the air
const REFILL_GROUND := 0.5  ## ...and on the ground
const RESTART := 0.25       ## after running dry, it needs this much fuel to light again

var fuel := 1.0
var on := false             ## flying this frame
var _dry := false


func reset() -> void:
	fuel = 1.0
	on = false
	_dry = false


func readiness() -> float:
	return fuel


## One physics step. `held`: Space is held in mid-air (MovementController.space_jet).
## Returns the new velocity.
func step(vel: Vector3, held: bool, grounded: bool, wish: Vector3, delta: float) -> Vector3:
	if _dry and fuel >= RESTART:
		_dry = false
	on = held and not _dry and fuel > 0.0
	if not on:
		fuel = minf(fuel + (REFILL_GROUND if grounded else REFILL_AIR) * delta, 1.0)
		return vel
	fuel = maxf(fuel - BURN * delta, 0.0)
	if fuel <= 0.0:
		_dry = true
	if vel.y < RISE_SPEED:
		vel.y = minf(vel.y + THRUST * delta, maxf(RISE_SPEED, vel.y))
	if wish != Vector3.ZERO:
		var along := Vector3(vel.x, 0.0, vel.z).dot(wish)
		if along < STEER_SPEED:
			vel += wish * minf(STEER * delta, STEER_SPEED - along)
	return vel
