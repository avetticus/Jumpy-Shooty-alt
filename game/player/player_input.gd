class_name PlayerInput
extends RefCounted
## One frame of player intent. Filled from the keyboard and mouse for the local
## player, from the AI for bots, and from scripts in tests. The movement code only
## ever reads this, so humans, bots and tests all move by the same rules.

var move := Vector2.ZERO   ## x = right, y = forward, length 0..1
var yaw := 0.0             ## look direction around the vertical axis, radians
var pitch := 0.0           ## look up/down, radians
var jump_held := false
var jump_pressed := false  ## true only on the frame the jump was pressed
var sprint := false
var crouch := false
var crouch_pressed := false  ## crouch pressed this frame (starts a slide when fast)
var dive := false             ## dive button held (keep holding through the landing to belly-slide)
var dive_pressed := false
var grapple := false          ## grapple button held
var grapple_pressed := false  ## grapple button pressed this frame
var fire := false          ## trigger held (automatic weapons)
var fire_pressed := false  ## trigger pulled this frame (semi-automatic weapons)
var alt_fire := false          ## alt fire held (see WeaponData.alt: the pistols' tilt)
var alt_fire_pressed := false  ## alt fire pressed this frame (the grenade launcher's sticky grenade)
var kick_pressed := false  ## kick pressed this frame (any weapon; a flying kick while you have a player hooked)
var boost_pressed := false ## rocket boots fired this frame
var glide := false         ## glide held (Shift in mid-air)
var glide_pressed := false ## glide pressed this frame (a glide needs a press in the air, not sprint held from the ground)
var interact := false      ## interact is down (a MapTerminal takes the press; some ask for a hold)
## Optional: which way the rocket boots push (bots aim them). Left at zero, they push
## toward your WASD direction as seen from where you look, or straight where you look.
var boost_dir := Vector3.ZERO
## Optional crosshair ray (third person aims from the camera, not the eyes).
## Left at zero, aiming uses the eyes plus yaw and pitch.
var aim_origin := Vector3.ZERO
var aim_dir := Vector3.ZERO


func clear_edges() -> void:
	jump_pressed = false
	dive_pressed = false
	fire_pressed = false
	alt_fire_pressed = false
	grapple_pressed = false
	crouch_pressed = false
	kick_pressed = false
	boost_pressed = false
	glide_pressed = false
	boost_dir = Vector3.ZERO
