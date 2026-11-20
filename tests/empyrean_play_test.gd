extends SceneTree
## Empyrean Tower in a real Practice match: what its new systems do to a real player.
## Run: godot --headless --path . --script tests/empyrean_play_test.gd
##
## Gravity: 1.0 standing inside, 0.4 on the docking ring, and it eases over about a
## second on the way out through a force-field doorway (which does not stop you).
## Hazard: touching the Engine's core is a death (the same as a fall). Burn layer:
## falling below it is a death; flying off sideways or upward is not.
## Lift: a tractor beam carries you up at about 9 m/s and you can shoot on the way.
## Ring gates: scenery; walking into one walks through the ring and out the back.

func _init() -> void:
	_start.call_deferred()


func _start() -> void:
	var runner: Node = load("res://tests/empyrean_play_runner.gd").new()
	root.add_child(runner)
	runner.call("run")
