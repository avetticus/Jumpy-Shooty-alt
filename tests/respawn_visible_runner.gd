extends Node
## The body of tests/respawn_visible_test.gd. A separate file because it uses the
## game's autoloads (Net, Match, Game), which only exist once the test's SceneTree is running.

const ID := 777       # the remote player (nobody else in Practice has this id)
const PLAYERS := 1 << 1

var _fails: Array[String] = []
var _arena: Node
var _t := 100.0       # the remote player's clock (snapshot times)
var _count := 0       # their respawn count, as they would send it
var _base := Vector3.ZERO


func run() -> void:
	Game.start_practice("testing_grounds")
	await _frames(30)
	_arena = Net.arena
	_expect(_arena != null and _arena.local_player != null, "practice starts")
	_base = _arena.local_player.global_position
	var p := Player.new()
	p.setup(ID, false)
	_arena.players_root.add_child(p)
	await _feed(p, 0, Vector3(3, 0, 0), 5)
	_expect(_shown(p), "a remote player is drawn from their snapshots")

	print("  respawn, then snapshot (the usual order)")
	_die(p)
	await _feed(p, 0, Vector3(3, 0, 0), 3)   # (a dead player's game keeps sending)
	_respawn(p, 5)
	_expect(not p.visual.visible and p._awaiting_respawn and p.collision_layer == 0, "hidden until a snapshot from the new life comes")
	await _feed(p, 5, Vector3(10, 0, 0), 1, true)
	_expect(_shown(p), "shown when it does")
	_expect(_only_after(p, Vector3(10, 0, 0)), "nothing from before the respawn to blend from")

	print("  snapshot, then respawn (the respawn held up on the way)")
	_die(p)
	p.visual.visible = false   # a ragdoll took the body's place (Arena does this when there are remains)
	await _feed(p, 6, Vector3(-6, 0, 2), 4, true)
	_expect(not p.alive and not p.visual.visible, "the new life's snapshots alone do not bring them back")
	_respawn(p, 6)
	_expect(_shown(p), "shown the moment the respawn arrives")
	_expect(_only_after(p, Vector3(-6, 0, 2)), "...from the new life's snapshots only")
	await _frames(3)
	_expect(p.global_position.distance_to(_base + Vector3(-6, 0, 2)) < 0.5, "...drawn where they are now (%.2f m off)" % p.global_position.distance_to(_base + Vector3(-6, 0, 2)))

	print("  the same with the body left showing at death (no remains)")
	var gore := Settings.gore
	Settings.gore = "off"   # (no ragdoll takes the body's place)
	_die(p)
	Settings.gore = gore
	_expect(p.visual.visible, "the body stays where it fell")
	await _feed(p, 7, Vector3(4, 0, -4), 3, true)
	_expect(not p.visual.visible, "a snapshot from a new life hides it (not dragged to the new spot)")
	_respawn(p, 7)
	_expect(_shown(p), "shown the moment the respawn arrives")

	print("  killed again before any snapshot from the new life")
	_die(p)
	_respawn(p, 8)
	_expect(p._awaiting_respawn and not p.visual.visible, "waiting for the new life")
	_die(p)
	_expect(not p.alive and not p._awaiting_respawn and not p.visual.visible, "down again, never seen")
	await _feed(p, 8, Vector3(1, 0, 6), 3, true)
	_expect(not p.alive and not p.visual.visible, "that life's snapshots, arriving now, do not show them")
	_respawn(p, 9)
	_expect(not _shown(p) and p._awaiting_respawn, "the next respawn waits: what is here is from the life they died in")
	await _feed(p, 9, Vector3(-2, 0, -6), 1, true)
	_expect(_shown(p), "shown once the next life's snapshot comes")
	_expect(_only_after(p, Vector3(-2, 0, -6)), "...with nothing older to blend from")

	print("  killed again with the snapshot first, the respawn still on its way")
	_die(p)
	await _feed(p, 10, Vector3(5, 0, 5), 2, true)
	_respawn(p, 10)
	_expect(_shown(p), "the held-up respawn shows them")
	_die(p)
	_expect(not p.alive and p.collision_layer == 0, "and the next death takes them down")
	_respawn(p, 11)
	_expect(p._awaiting_respawn and not p.visual.visible, "the respawn after waits for its own snapshot")
	await _feed(p, 11, Vector3(5, 0, -5), 1, true)
	_expect(_shown(p), "shown")

	print("  a snapshot arriving late, out of order")
	var count := p.respawn_count()
	p.apply_snapshot(_t - 0.5, _snap(Vector3(5, 0, 5), count - 1, 10))
	_expect(p.respawn_count() == count and p._seen_life == 11 and _shown(p), "ignored: the respawn stands")
	_expect(_only_after(p, Vector3(5, 0, -5)), "...and is not drawn")

	print("  a new robot or gun while waiting to see them back")
	_die(p)
	_respawn(p, 12)
	_arena.rebuild_player(ID)
	p = _arena.get_player(ID)
	_expect(p.alive and p._awaiting_respawn and not p.visual.visible and p.collision_layer == 0, "rebuilt: still hidden (and not solid), still waiting")
	await _feed(p, 12, Vector3(0, 0, 8), 1, true)
	_expect(_shown(p), "rebuilt: shown when the snapshot comes")
	_die(p)
	_respawn(p, 13)
	p.change_weapon("shotgun" if p.robot.weapon != "shotgun" else "pistol")   # Gun Game: a kill hands you the next gun
	_expect(p._awaiting_respawn and not p.visual.visible, "a Gun Game swap: still hidden, still waiting")
	await _feed(p, 13, Vector3(8, 0, 0), 1, true)
	_expect(_shown(p), "a Gun Game swap: shown when the snapshot comes")
	p.change_weapon("lever_action")
	_expect(_shown(p), "a swap while shown keeps them shown")

	print("  rebuilt while dead, the snapshot first")
	_die(p)
	_arena.rebuild_player(ID)
	p = _arena.get_player(ID)
	_expect(not p.alive and not p.visual.visible, "rebuilt dead: hidden")
	await _feed(p, 14, Vector3(-8, 0, 0), 3, true)
	_respawn(p, 14)
	_expect(_shown(p), "shown the moment the respawn arrives")

	print("  a respawn while alive (a new round), the snapshot first")
	await _feed(p, 15, Vector3(-8, 0, 4), 2, true)
	_expect(_shown(p), "still shown")
	_respawn(p, 15)
	_expect(_shown(p) and _only_after(p, Vector3(-8, 0, 4)), "shown at once, from the new round's snapshots")

	print("  the safety net")
	_die(p)
	_respawn(p, 16)
	await _feed(p, 15, Vector3(2, 0, 2), 30)   # snapshots keep coming, none from the new life (something went wrong)
	_expect(p._awaiting_respawn and not p.visual.visible, "half a second on: still waiting")
	await _feed(p, 15, Vector3(2, 0, 2), 50)
	_expect(_shown(p), "over a second on, alive by the host's word, snapshots coming: shown anyway")
	_die(p)
	_respawn(p, 17)
	await _frames(90)   # nothing comes at all (their game stalled)
	_expect(p._awaiting_respawn and not p.visual.visible, "no snapshots at all: nothing to draw them with, still waiting")
	await _feed(p, 17, Vector3(2, 0, -2), 1, true)
	_expect(_shown(p), "shown when one comes")

	Net.leave()
	if _fails.is_empty():
		print("PASS: every check passed")
	else:
		print("FAIL:\n  " + "\n  ".join(_fails))
	get_tree().quit(1 if not _fails.is_empty() else 0)


func _expect(ok: bool, what: String) -> void:
	print("    %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


## Alive, drawn, solid, not waiting.
func _shown(p: Player) -> bool:
	return p.alive and p.visual.visible and p.collision_layer == PLAYERS and not p._awaiting_respawn


## Every snapshot in their buffer is from where they are in this life.
func _only_after(p: Player, at: Vector3) -> bool:
	if not p.buffer.has_data():
		return false
	for s in p.buffer.snaps:
		if s.pos.distance_to(_base + at) > 0.01:
			return false
	return true


## As the host's death message does on this copy.
func _die(p: Player) -> void:
	Match.health[ID] = 0.0
	_arena._on_player_died(ID, 1)


## As the host's respawn message does on this copy (`life` is its spawn index).
func _respawn(_p: Player, life: int) -> void:
	Match.health[ID] = Match.MAX_HEALTH
	_arena._on_player_respawned(ID, life)


## `n` snapshots from their game, one a frame, standing at `at`, in `life`. `new_life`:
## the first one is from a fresh respawn (their respawn count goes up).
func _feed(p: Player, life: int, at: Vector3, n: int, new_life: bool = false) -> void:
	if new_life:
		_count += 1
	for i in n:
		_t += 1.0 / Player.SEND_RATE
		p.apply_snapshot(_t, _snap(at, _count, life))
		await get_tree().process_frame


func _snap(at: Vector3, count: int, life: int) -> PackedFloat32Array:
	var pos := _base + at
	return PackedFloat32Array([pos.x, pos.y, pos.z, 0, 0, 0, 0, 0, 0, count, 0, life])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
