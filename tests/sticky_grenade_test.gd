extends SceneTree
## The grenade launcher's sticky proximity grenade (its alt fire), in real Vs Bots
## matches with the bots frozen. The checks are in tests/sticky_grenade_runner.gd (a
## Node, so it can use the autoloads).
## Run: godot --headless --fixed-fps 60 --path . --script tests/sticky_grenade_test.gd

func _init() -> void:
	_start.call_deferred()


func _start() -> void:
	var runner: Node = load("res://tests/sticky_grenade_runner.gd").new()
	root.add_child(runner)
	runner.call("run")
