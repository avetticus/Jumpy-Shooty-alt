class_name FollowCamera
extends Camera3D
## Search and Destroy: once you are out for the round, you watch a player still in it
## from behind them, in third person (see Arena._update_round_spectate). Fire moves on
## to the next player, Mobility (middle mouse) back to the one before; teammates come first.
## The camera stays out of walls: it comes in closer when one is behind the player.

const DISTANCE := 3.4    ## metres behind the player
const HEIGHT := 0.7      ## over their head-height pivot
const PIVOT := 1.45      ## the point it looks at, above their feet
const FOLLOW := 9.0      ## how quickly it swings round after them (higher is snappier)

var target := 0
var _yaw := 0.0
var _placed := false


func _init() -> void:
	name = "FollowCamera"
	near = 0.05
	far = 800.0
	set_cull_mask_value(CameraRig.VIEW_BODY_LAYER, false)
	set_cull_mask_value(Player.VIEWMODEL_LAYER, false)


func _ready() -> void:
	fov = Settings.field_of_view
	make_current()


## Everyone you can watch now, in order: your living teammates, then the rest.
static func candidates() -> Array:
	var me := Net.my_id()
	var mine := []
	var theirs := []
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		if id == me or not Match.is_alive(id) or Net.arena == null or Net.arena.get_player(id) == null:
			continue
		(mine if Teams.same_team(me, id) else theirs).append(id)
	return mine + theirs


## Moves on through candidates() (step 1 next, -1 back). False: nobody to watch.
func cycle(step: int) -> bool:
	var list := candidates()
	if list.is_empty():
		target = 0
		return false
	var at := list.find(target)
	var next: int = list[0] if at < 0 and step >= 0 else list[posmod(at + step, list.size())]
	if next != target:
		target = next
		_placed = false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or (Net.arena and Net.arena.menu_open()):
		return
	if event.is_action_pressed("fire"):
		cycle(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("grapple"):
		cycle(-1)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	fov = Settings.field_of_view
	if target == 0 or not Match.is_alive(target):
		if not cycle(1):
			return
	var p: Player = Net.arena.get_player(target) if Net.arena else null
	if p == null:
		return
	var yaw := p.visual.global_rotation.y
	_yaw = yaw if not _placed else lerp_angle(_yaw, yaw, clampf(FOLLOW * delta, 0.0, 1.0))
	var pivot := p.global_position + Vector3(0, PIVOT, 0)
	var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var want := pivot + back * DISTANCE + Vector3(0, HEIGHT, 0)
	var ray := PhysicsRayQueryParameters3D.create(pivot, want, 1)   # the map only
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		want = hit.position + (pivot - want).normalized() * 0.25
	global_position = want if not _placed else global_position.lerp(want, clampf(14.0 * delta, 0.0, 1.0))
	_placed = true
	var look := pivot - back * 2.0
	if global_position.distance_to(look) > 0.01:
		look_at(look, Vector3.UP)


func target_name() -> String:
	return Net.player_name(target) if target != 0 else ""
