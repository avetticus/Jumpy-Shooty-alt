extends SceneTree
## The mobility slot (see Mobility): blink, picking a tool, and everyone's jetpack, in a
## real Practice match on the Testing Grounds.
## Run: godot --headless --path . --script tests/mobility_test.gd
##
## Blink: goes where you aim, stops short of a wall, keeps you moving, uses a charge
## and the charges come back. Picking: the pick is refused while alive and taken while
## dead, the player then has that tool; the tools are the grapple and blink, and an
## old pick of a tool that is gone is the grapple. Jetpack: everyone has it; a tap of
## Space is a plain jump and burns no fuel, nor does holding it through the jump for
## less than the hold time; held on in mid-air it fires, lifts you and burns fuel,
## which refills when you let go; held in a fall it catches you. Bots take a tool and
## have the jetpack; a race always has the grapple and no jetpack.

func _init() -> void:
	_start.call_deferred()


func _start() -> void:
	var runner: Node = load("res://tests/mobility_runner.gd").new()
	root.add_child(runner)
	runner.call("run")
