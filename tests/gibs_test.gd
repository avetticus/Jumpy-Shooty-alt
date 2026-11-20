extends SceneTree
## Headless checks on giblets (Gibs): a robot blown apart.
## Run: godot --headless --fixed-fps 60 --path . --script tests/gibs_test.gd
##
## Every character's body (the robots, a creature, a mix with accessories) cuts into
## its eleven pieces plus its gun (two for a gun in each hand, none for a blade): every triangle in
## exactly one piece, no empty meshes, and the cut made once per body. Spawned through
## Remains for a rocket kill, the pieces start where the posed body was, fly apart
## without falling through the floor or going NaN, burn away (Dissolve) at the end
## and are gone LIFETIME after the death.

func _init() -> void:
	_start.call_deferred()


func _start() -> void:
	var runner: Node = load("res://tests/gibs_runner.gd").new()
	root.add_child(runner)
