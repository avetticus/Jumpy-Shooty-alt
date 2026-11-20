extends SceneTree
## The mobility slot (see Mobility) and the lobby's jetpack, in a real Practice match on
## the Testing Grounds.
## Run: godot --headless --path . --script tests/mobility_test.gd
##
## The grappling hook is the only tool, and an old pick of one that is gone (blink, the
## portal gun, the jetpack) is the hook. Jetpack: nobody has it unless the host turns it
## on (holding Space in mid-air is then just a jump); turned on, a tap of Space is a
## plain jump and burns no fuel, nor does holding it through the jump for less than the
## hold time; held on in mid-air it fires, lifts you and burns fuel, which refills when
## you let go; held in a fall it catches you. Bots have it while it is on; a race never
## has it.

func _init() -> void:
	_start.call_deferred()


func _start() -> void:
	var runner: Node = load("res://tests/mobility_runner.gd").new()
	root.add_child(runner)
	runner.call("run")
