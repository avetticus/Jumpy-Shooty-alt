extends SceneTree
## The railgun's slug goes through everything, in a real Practice match on the Testing
## Grounds. Run: godot --headless --path . --script tests/railgun_test.gd
##
## Through a wall a pistol round stops at, it hits the target dummy behind it and kills
## it outright; its shot effect runs its whole range, not to the wall; it never hurts
## the one who fired it; and it damages a breakable piece of wall it passes through, as
## far away as that is.


func _init() -> void:
	_start.call_deferred()


func _start() -> void:
	var runner: Node = load("res://tests/railgun_runner.gd").new()
	root.add_child(runner)
	runner.call("run")
