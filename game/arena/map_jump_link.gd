@tool
class_name MapJumpLink
extends Marker3D
## Tells bots how to cross a gap the navigation mesh cannot join: where to stand (this
## node), what to do, and where they come down. Cirrus uses them between its quad and
## its islands, which have open sky between them: a bot that wants to be over there
## walks to the nearest link, hooks the grapple point the link names and lets the
## rope carry it over.
##
## A link set to Lift is a one-way trip up a MapLiftWell: put it at the beam's foot
## (as the lift's child, say) with Landing on the floor to get off at; one link for
## each floor. Bots take a lift when where they are going is well above them.
##
## Put one on the floor where the crossing starts, a little back from the edge.
## Inside a MapIsland it rides the island, like its hook and landing if they are
## inside one too. Bots only use a link when walking will not get them where they
## are going (see BotBrain). People need none of this: it is the route a person would
## take anyway.

enum How {
	GRAPPLE,   ## aim at Hook, fire the grapple, ride the rope, let go and steer to Landing
	LEAP,      ## run at Landing and off the edge, steering in the air (a drop to somewhere lower)
	HOP,       ## sprint at Landing and jump at the edge (a gap a running jump clears; a step up it climbs)
	BOOST,     ## sprint at Landing, jump at the edge, fire the rocket boots and glide on (a gap too wide to jump)
	LIFT,      ## walk into the tractor beam here (a MapLiftWell), ride it up, steer out to Landing
}

const GROUP := "map_jump_links"

@export var how := How.GRAPPLE
## What to hook (a MapGrapplePoint, or any Node3D on something solid). Grapple only.
@export_node_path("Node3D") var hook: NodePath
## Or: hook whichever node of this group is nearest the takeoff (masts round a quad,
## when the island this link is on may stand at different places). A hook found this
## way may have a child called "Land": that is then the landing.
@export var hook_group := &""
## Where the bot comes down: a Node3D on the floor over there. Empty: this node itself
## (a link that sits where you arrive, with Round From saying where you set off).
@export_node_path("Node3D") var landing: NodePath
## For a crossing that sets off from a round floor (a quad) toward wherever the
## landing is right now: the middle of that floor, and how far from the middle to
## stand. Empty: the takeoff is where this node is.
@export_node_path("Node3D") var round_from: NodePath
@export var round_radius := 0.0
## It leads off the island it is on: bots may still take it when that island is about
## to go down (it is their way out), where every other crossing there is closed.
@export var leaves := false
@export_group("Timing")
## Between parts that keep moving (Sky Island's bobbing islands and pads): set off only
## when the landing will be between Rise Min and Rise Max metres above the takeoff
## (negative: below) when you come down, Flight seconds from now. Both zero: any time.
@export var rise_min := 0.0
@export var rise_max := 0.0
@export var flight := 0.8


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)


## The island it is on (it rides it), or null.
func island() -> MapIsland:
	var node := get_parent()
	while node != null and not node is MapIsland:
		node = node.get_parent()
	return node as MapIsland


## Can it be used right now? Not while the map is moving; not when its island is down
## or on its way; and when its island is about to go down, only if it leads off it.
func usable() -> bool:
	var map := MapRoot.of(self)
	if map == null:
		return true
	if map.shifting:
		return false
	var on := island()
	if on == null:
		return true
	if not on.up:
		return false
	return leaves or not on.doomed


## Is this a good moment to set off (see Rise Min and Rise Max)?
func ready_now() -> bool:
	if rise_min == 0.0 and rise_max == 0.0:
		return true
	return rise_at_landing() >= rise_min and rise_at_landing() <= rise_max


## How far above the takeoff (now) the landing will be by the time you come down.
func rise_at_landing() -> float:
	var land := landing_point()
	var map := MapRoot.of(self)
	if map != null and is_inside_tree():
		land = map.ahead(land, flight)
	return land.y - takeoff().y


func takeoff() -> Vector3:
	var middle := get_node_or_null(round_from) as Node3D
	if middle == null:
		return global_position
	var to := landing_point() - middle.global_position
	to.y = 0.0
	return middle.global_position + (to.normalized() * round_radius if to.length() > 0.01 else Vector3.ZERO)


func _hook_node() -> Node3D:
	var node := get_node_or_null(hook) as Node3D
	if node != null or hook_group == &"" or not is_inside_tree():
		return node
	var from := global_position
	var best: Node3D = null
	for n in get_tree().get_nodes_in_group(hook_group):
		var candidate := n as Node3D
		if candidate != null and (best == null or candidate.global_position.distance_to(from) < best.global_position.distance_to(from)):
			best = candidate
	return best


func hook_point() -> Vector3:
	var node := _hook_node()
	return node.global_position if node else Vector3.INF


func landing_point() -> Vector3:
	var node := get_node_or_null(landing) as Node3D
	if node != null:
		return node.global_position
	if hook_group != &"":
		var at := _hook_node()
		var land := at.get_node_or_null("Land") as Node3D if at else null
		if land != null:
			return land.global_position
	return global_position
