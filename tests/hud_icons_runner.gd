extends Node
## HUD icons (see tests/hud_icons_test.gd). Polygons that fail to draw print an
## error, which tests/run_all.sh counts as a failure too.
## Started by tests/hud_icons_test.gd (this is a Node, so it can use the autoloads).

const SCALES := [0.8, 1.0, 1.1, 2.0, 4.0]   # the death screen chip, the feed, and bigger

var _fails: Array[String] = []
var _drawn := 0


func run() -> void:
	await _check_icon()
	await _check_feed_and_death_screen()
	if _fails.is_empty():
		print("PASS hud icons: headshot icon drawn at %d sizes, a headshot laid out in the feed and on the death screen" % _drawn)
	else:
		print("FAIL:\n  " + "\n  ".join(_fails))
	get_tree().quit(1 if not _fails.is_empty() else 0)


## The icon draws into a Control at every size, and says it is as wide as it is.
func _check_icon() -> void:
	var c := Control.new()
	c.size = Vector2(400, 200)
	add_child(c)
	c.draw.connect(func():
		var x := 4.0
		for s in SCALES:
			var w := HudStyle.headshot_icon(c, Vector2(x, 4), Color(1, 1, 1, 0.9), s)
			if not is_equal_approx(w, HudStyle.headshot_width() * s):
				_fails.append("headshot_icon at size %s says it is %s wide, headshot_width() says %s" % [s, w, HudStyle.headshot_width() * s])
			x += w + 4.0
			_drawn += 1)
	if HudStyle.headshot_width() < 12.0 or HudStyle.headshot_width() > 32.0:
		_fails.append("headshot icon is %s wide at size 1: about as wide as it is tall (16) is expected" % HudStyle.headshot_width())
	c.queue_redraw()
	await _frames(3)
	if _drawn != SCALES.size():
		_fails.append("the headshot icon's Control drew %d icons, expected %d" % [_drawn, SCALES.size()])
	c.queue_free()


## A kill feed with a headshot and a plain kill, and the death screen's HEADSHOT chip.
func _check_feed_and_death_screen() -> void:
	var me := Net.my_id()
	Net.players[me] = {"name": "You", "color": 0, "weapon": "rifle"}
	Net.players[2] = {"name": "Sprocket", "color": 1, "weapon": "anti_materiel"}
	Net.players[3] = {"name": "Gizmo", "color": 2, "weapon": "shotgun"}
	var hud := Hud.new()
	add_child(hud)
	await _frames(2)
	# The host's word wins over the last hit seen here, either way.
	hud.set("_last_head", {3: false, 2: true})
	Match.death_fx[3] = {"with": "anti_materiel", "head": true, "gib": false, "push": Vector3.ZERO, "dir": Vector3.ZERO}
	hud.call("_on_died", 3, 2)
	Match.death_fx[2] = {"with": "shotgun", "head": false, "gib": false, "push": Vector3.ZERO, "dir": Vector3.ZERO}
	hud.call("_on_died", 2, 3)
	# No word from the host (an older one): the last hit decides.
	Match.death_fx[3] = {}
	hud.set("_last_head", {3: true})
	hud.call("_on_died", 3, 2)
	var feed: Array = hud.get("_feed")
	var heads := feed.map(func(e): return e.head)
	if heads != [true, false, true]:
		_fails.append("feed headshots %s, expected [true, false, true] (death_fx first, the last hit when it is empty)" % [heads])
	# The death screen, killed by a headshot.
	Match.death_fx[me] = {"with": "anti_materiel", "head": true, "gib": false, "push": Vector3.ZERO, "dir": Vector3.ZERO}
	hud.set("_last_head", {me: false})
	hud.call("_on_died", me, 2)
	if not hud.get("_killed_by_head"):
		_fails.append("death screen: killed by a headshot (death_fx) but no HEADSHOT chip")
	hud.get("_overlay").queue_redraw()
	await _frames(3)
	Match.death_fx.clear()
	hud.queue_free()
	await _frames(1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
