extends Node3D
## The arena scene: builds the level, spawns one Player per connected peer,
## and hosts the HUD, the pause menu and (offline) the debug menu.

var layout: MapRoot
var players_root: Node3D
var local_player: Player
## While you spectate (Net.spectating): the free-flying camera you watch through.
var spectator_cam: SpectatorCamera
## Search and Destroy, out for the round: the camera watching a player still in it.
var follow_cam: FollowCamera
var _out_for := 0.0   # how long you have been dead in a round you cannot come back to
const FOLLOW_AFTER := 3.0   ## seconds of the death screen before you watch someone
var hud: Hud
var pause_menu: PauseMenu
var debug_menu: DebugMenu
## The map's target dummies (TargetDummy), in the order of their index.
var dummies: Array = []
## Race maps: the drawn checkpoint gates, in the order racers pass them.
var gates: Array = []
## Deathmatch: the map's floating weapons (WeaponPickup), in the order of their index.
var pickups: Array = []
## Deathmatch: the map's power-ups (ItemPickup), in the order of their index.
var items: Array = []
## Team modes: the flags, bomb sites and bomb (see Teams), or null.
var objectives: ObjectiveProps
## Seconds until the bots' navigation mesh is redone after walls or floors broke.
var _nav_rebake := 0.0
var _nav_baking := false
const NAV_REBAKE_DELAY := 0.6
## A map with two layouts (see LayoutEvent): the navigation mesh baked for each, so
## going back to one already seen takes no baking. Emptied when something breaks.
var _nav_by_layout := {}
var _nav_serial := 0   # goes up every time the map's parts start moving: a bake begun before is out of date


func _ready() -> void:
	WorldGravity.reset()   # whatever the last match's map event left behind
	WorldGravity.clear_zones()   # ...and the last map's gravity zones (this map's build() sets its own)
	layout = Maps.make(Net.map_id())
	layout.name = "Level"
	add_child(layout)
	layout.destructible = not Race.active and Maps.game_of(Net.map_id()) != "race"
	layout.build()
	if layout.destruction:
		layout.destruction.cells_changed.connect(_on_cells_changed)
	layout.parts_moving.connect(_on_parts_moving)
	layout.parts_settled.connect(_on_parts_settled)
	if Race.active:
		layout.clock_source = func(): return Race.time + Race.COUNTDOWN   # moving parts in step on every copy
		_build_gates()
	elif Net.has_bots() and Net.is_host():   # (the host runs the bots)
		ensure_navigation()   # only when bots play: it takes a moment (racing bots follow the map's route instead)
	_spawn_dummies()
	if Teams.active():
		Teams.setup_map(layout)   # the bases, each side's spawn points and the bomb sites
		objectives = ObjectiveProps.new()
		add_child(objectives)
		Teams.event.connect(_on_team_event)
	if Net.is_deathmatch():
		_spawn_pickups()
		if Net.powerups_on():
			_spawn_items()
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)
	hud = Hud.new()
	add_child(hud)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.visibility_changed.connect(_on_pause_toggled)
	debug_menu = DebugMenu.new()
	add_child(debug_menu)
	debug_menu.toggled.connect(_on_pause_toggled)
	Net.arena = self
	Net.players_changed.connect(_sync_players)
	Match.player_died.connect(_on_player_died)
	Match.player_respawned.connect(_on_player_respawned)
	Match.shot_fired.connect(_on_shot_fired)
	Match.projectile_fired.connect(_on_projectile_fired)
	Match.exploded.connect(_on_exploded)
	Match.projectile_stuck.connect(_on_projectile_stuck)
	Match.projectile_armed.connect(_on_projectile_armed)
	Match.projectile_gone.connect(_on_projectile_gone)
	Match.pickup_changed.connect(_on_pickup_changed)
	Match.item_changed.connect(_on_item_changed)
	_sync_players()
	_capture_mouse(true)
	if layout.destruction:
		Match.request_breaks()   # joining a match in progress: what is broken already
	Net.request_map_state()      # ...and where the map's terminals and events are
	Match.request_stickies()     # ...and the sticky grenades stuck about


func _exit_tree() -> void:
	if Net.arena == self:
		Net.arena = null
	Match.pickups_taken.clear()
	WorldGravity.reset()      # a map event never outlives the map
	Match.items_taken.clear()
	Engine.time_scale = 1.0   # the debug menu's slow motion ends with the match
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		pause_menu.visible = not pause_menu.visible
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not _menu_open():
		_capture_mouse(true)


func _physics_process(_delta: float) -> void:
	# Falling out of the map, or getting outside its fence, counts as a death. So does
	# touching a MapHazard in an arena (Empyrean Tower's engine core): the same death as
	# a fall. In a race a hazard sends you back to your checkpoint instead (see Race).
	var floor_y := layout.kill_height
	var area := layout.bounds
	var deadly := not Race.active and not layout.hazards.is_empty()
	for p in players_root.get_children():
		if not (p as Player).is_local or (p == local_player and Cheats.flying()):
			continue
		var pos: Vector3 = p.global_position
		if pos.y < floor_y or (area.has_area() and not area.has_point(Vector2(pos.x, pos.z))):
			(p as Player).report_fell_once()
		elif deadly and (p as Player).alive and layout.body_in_hazard(pos):
			(p as Player).report_fell_once()
	if layout.has_riders():
		# Pickups on an island (see MapIsland) stay over their spots as it moves.
		for i in pickups.size():
			(pickups[i] as WeaponPickup).move_to(layout.weapon_spawns[i][0])
		for i in items.size():
			(items[i] as ItemPickup).move_to(layout.item_spawns[i][0])


func _process(delta: float) -> void:
	if _nav_rebake > 0.0:
		_nav_rebake -= delta
		if _nav_rebake <= 0.0:
			_rebake_navigation()
	if spectator_cam:
		if follow_cam and follow_cam.target == 0 and FollowCamera.candidates().is_empty():
			spectator_free()   # nobody left to watch
		hud.follow_name = follow_cam.target_name() if follow_cam else ""
		hud.update_spectator()
	elif local_player:
		_update_round_spectate(delta)
		hud.update_local(local_player)
		if Race.active:
			var passed := Race.gates_passed(local_player.peer_id)
			for i in gates.size():
				RaceGate.set_state(gates[i], i == passed, i < passed)


## Search and Destroy: out for the round (once the killcam and a few seconds of the
## death screen are over), watch a player still in it from behind; back to your own
## view when the next round brings you back.
func _update_round_spectate(delta: float) -> void:
	var out := Teams.no_respawn() and not local_player.alive and not Match.is_alive(local_player.peer_id) \
		and not Killcam.watching()
	_out_for = _out_for + delta if out else 0.0
	if out and follow_cam == null and _out_for >= FOLLOW_AFTER and not FollowCamera.candidates().is_empty():
		follow_cam = FollowCamera.new()
		add_child(follow_cam)
		follow_cam.cycle(1)
		if DevArgs.sync_log:
			print("FOLLOW %s" % follow_cam.target_name())
	elif follow_cam and (not out or (follow_cam.target == 0 and FollowCamera.candidates().is_empty())):
		follow_cam.queue_free()
		follow_cam = null
		if local_player.rig and local_player.rig.camera:
			local_player.rig.camera.make_current()
	hud.follow_name = follow_cam.target_name() if follow_cam else ""


func _build_gates() -> void:
	var root := Node3D.new()
	root.name = "Gates"
	add_child(root)
	for c in layout.checkpoints:
		var g := RaceGate.make(c.opening, c.finish, c.number)
		g.transform = c.xf
		root.add_child(g)
		gates.append(g)


func get_player(id: int) -> Player:
	return players_root.get_node_or_null("Player_%d" % id) as Player


## Called by Net for every movement snapshot from another player.
func on_snapshot(sender: int, remote_time: float, data: PackedFloat32Array) -> void:
	var p := get_player(sender)
	if p and not p.is_local:
		p.apply_snapshot(remote_time, data)


func _on_player_died(victim: int, _killer: int) -> void:
	var p := get_player(victim)
	if p:
		var shown := p.visual.visible
		p.set_dead()
		if shown and Remains.spawn(p, Match.death_fx.get(victim, {})):
			p.hide_for_remains()   # a ragdoll or giblets in its place (back when they respawn)
		if DevArgs.swap_on_death and p == local_player and not p.racing:
			p.dev_swap_after_death()


func _on_player_respawned(id: int, spawn_index: int) -> void:
	var p := get_player(id)
	if p == null:
		return
	if p.is_local:
		var s: Array = _team_spawn(p)
		if s.is_empty():
			s = _safest_spawn(p)
		p.respawn_at(layout.clear_feet(s[0]), s[1], spawn_index)   # (never in the ground)
	else:
		p.expect_respawn(spawn_index)


## A rocket or grenade is on its way: draw it (and, for someone else's, their gun firing).
func _on_projectile_fired(id: int, shooter: int, weapon_id: String, origin: Vector3, direction: Vector3, sticky: bool) -> void:
	var p := get_player(shooter)
	var muzzle := Vector3.INF
	var color := Color(1.0, 0.6, 0.3)
	if p:
		muzzle = p.muzzle_position()
		color = RobotModel.trim_color(Net.player_color(shooter))
		if shooter != Net.my_id() and not p.is_local:
			p.show_shot()
	add_child(Projectile.make(id, WeaponData.by_id(weapon_id), origin, direction, muzzle, color, sticky))


## A sticky grenade stuck (see Match._host_stick): on a player it rides their body, on
## a moving part of the map that part. A thunk where it landed. One we never saw fly
## (we joined after it stuck) is made here.
func _on_projectile_stuck(id: int, how: Dictionary) -> void:
	var node := get_node_or_null("Projectile_%d" % id) as Projectile
	if node == null:
		var color := RobotModel.trim_color(Net.player_color(int(how.get("who", 0))))
		node = Projectile.make(id, WeaponData.by_id(str(how.get("weapon", ""))), how.at, Vector3.DOWN, Vector3.INF, color, true)
		add_child(node)
	var ride: Node3D = null
	var on := int(how.get("on", 0))
	if on > 0:
		var p := get_player(on)
		ride = p.visual if p else null
	else:
		ride = Projectile.frame_in(layout, how)
		if ride and (ride.global_transform * (how.get("local", Vector3.ZERO) as Vector3)).distance_to(how.at) > 2.0:
			ride = null   # (not the part the host meant: it stays where the host said)
	node.stick(how, ride)
	Sound.play_at("grenade_in", node.global_position, "move", 2.0, 0.05)
	if DevArgs.sync_log:
		var at := node.global_position
		print("STICKY_SEEN %d stuck %d on %d %s at %.2f,%.2f,%.2f" % [Net.my_id(), id, on, "riding" if ride else "still", at.x, at.y, at.z])


## ...armed: a tick, and its light blinks faster.
func _on_projectile_armed(id: int) -> void:
	var node := get_node_or_null("Projectile_%d" % id) as Projectile
	if node:
		node.arm()
		Sound.play_at("ui_tick", node.global_position, "move", 10.0)
	if DevArgs.sync_log:
		print("STICKY_SEEN %d armed %d" % [Net.my_id(), id])


## ...gone without going off.
func _on_projectile_gone(id: int) -> void:
	var node := get_node_or_null("Projectile_%d" % id)
	if node:
		node.queue_free()
	if DevArgs.sync_log:
		print("STICKY_SEEN %d gone %d" % [Net.my_id(), id])


func _on_exploded(id: int, at: Vector3, weapon_id: String) -> void:
	var node := get_node_or_null("Projectile_%d" % id)
	if node:
		if DevArgs.sync_log and node is Projectile and (node as Projectile).sticky:
			print("STICKY_SEEN %d boom %d" % [Net.my_id(), id])
		node.queue_free()
	var w := WeaponData.by_id(weapon_id)
	ShotFx.landed(self, at, w)
	Sound.play_at(ShotFx.landed_sound(w), at, "fire", 0.0, 0.05)
	if not w.explosive:
		return   # a nail or a bolt: no blast, no shake
	var d := at.distance_to(Sound.listener_position())
	if d > 40.0 and d < INF:
		Sound.play_at("explosion_far", at, "far", 0.0, 0.05)
	if local_player and local_player.rig:
		local_player.shake(clampf(1.0 - d / (w.splash_radius * 5.0), 0.0, 1.0))


func _on_shot_fired(shooter: int, muzzle: Vector3, ends: PackedVector3Array, hits: Array) -> void:
	var p := get_player(shooter)
	if shooter == Net.my_id() or (p and p.is_local):
		return  # we (or our bot) already drew this shot the moment it was fired
	if p:
		p.show_shot()
	ShotFx.spawn(self, p.muzzle_position() if p else muzzle, ends, hits, Net.player_weapon(shooter))
	Sound.shot_landed(p.muzzle_position() if p else muzzle, ends, hits, false)


## Team modes: where `who` comes back, on their team's side ([] otherwise).
func _team_spawn(who: Player) -> Array:
	if not Teams.active() or not Teams.map_ready:
		return []
	return Teams.spawn_for(who, who.peer_id, players_root.get_children())


## Team modes: the bomb going off (the blast, its sound and a shake).
func _on_team_event(kind: String, _team: int, _who: int) -> void:
	if kind != "bomb_exploded" or objectives == null:
		return
	var at := Teams.bomb_pos
	if at == Vector3.INF:
		return
	objectives.blast(at)
	Sound.play_at("explosion_1", at, "fire", 6.0)
	var d := at.distance_to(Sound.listener_position())
	if d > 40.0 and d < INF:
		Sound.play_at("explosion_far", at, "far", 3.0)
	if local_player and local_player.rig:
		local_player.shake(clampf(1.2 - d / 40.0, 0.0, 1.0))


## The spawn point furthest from every living opponent of `who`.
func _safest_spawn(who: Player) -> Array:
	var open := layout.open_spawns()   # (on a map of islands: only where there is an island to stand on)
	var best: Array = open[0]
	var best_score := -1.0
	for s in open:
		var nearest := INF
		for p in players_root.get_children():
			if p != who and (p as Player).alive and not Teams.same_team(who.peer_id, (p as Player).peer_id):
				nearest = min(nearest, (s[0] as Vector3).distance_to(p.global_position))
		if nearest > best_score:
			best_score = nearest
			best = s
	return best


func _sync_players() -> void:
	for id in Net.players:
		if not players_root.has_node("Player_%d" % id):
			_spawn(id)
		else:
			var p := get_player(id)
			if p.mobility != Net.player_mobility(id):
				p.set_mobility(Net.player_mobility(id))   # picked while waiting to respawn
			if p.character != Net.player_character(id):
				rebuild_player(id)   # a new robot from the loadout (picked while waiting to respawn)
			elif not p.racing and p.robot.weapon != Net.player_weapon(id):
				if Net.is_deathmatch():
					p.equip(Net.player_weapon(id))   # switched weapons (or picked one up); a dead body waits for its respawn
				elif p.alive and Match.is_alive(id):
					p.change_weapon(Net.player_weapon(id))   # Gun Game: a kill hands you the next weapon now
				else:
					rebuild_player(id)   # swapped weapons while waiting to respawn: rebuilt holding the new one
	for p in players_root.get_children():
		if not Net.players.has((p as Player).peer_id):
			if p == local_player:
				local_player = null   # you went to spectate
			p.queue_free()
		elif not Match.is_alive((p as Player).peer_id) and (p as Player).alive:
			(p as Player).set_dead()  # joined while they were dead
	_sync_spectator()
	hud.set_players(Net.players)


## Spectating: fly a camera with no body (it starts where you were looking from, or high
## over the first spawn point). Playing again: it goes, and your robot's camera takes over.
## Spectating: lock onto a player (step 1 the next, -1 the one before) and watch them
## in third person. Nothing happens when nobody is playing.
func spectator_follow(step: int) -> void:
	if spectator_cam == null or follow_cam != null or FollowCamera.candidates().is_empty():
		return
	follow_cam = FollowCamera.new()
	add_child(follow_cam)
	follow_cam.cycle(step)
	if DevArgs.sync_log:
		print("FOLLOW %s" % follow_cam.target_name())


## Spectating: stop watching a player and fly free again, from where the view was.
func spectator_free() -> void:
	if follow_cam == null:
		return
	if spectator_cam:
		spectator_cam.place_like(follow_cam)
		spectator_cam.make_current()
	follow_cam.queue_free()
	follow_cam = null


func _sync_spectator() -> void:
	if Net.spectating() and spectator_cam == null:
		var from := get_viewport().get_camera_3d()
		spectator_cam = SpectatorCamera.new()
		add_child(spectator_cam)
		if from and from != spectator_cam:
			spectator_cam.place_like(from)
		elif not layout.spawns.is_empty():
			var s: Array = layout.spawns[0]
			spectator_cam.place(s[0] + Vector3(0, 6.0, 0), s[1], deg_to_rad(-20.0))
		hud.set_spectating(true)
	elif not Net.spectating() and spectator_cam != null:
		if follow_cam:
			follow_cam.queue_free()
			follow_cam = null
		spectator_cam.queue_free()
		spectator_cam = null
		hud.set_spectating(false)


func _spawn(id: int) -> void:
	var p := Player.new()
	var bot := Net.is_bot(id) and Net.is_host()   # the host runs the bots
	var local := id == Net.my_id() or bot
	p.setup(id, local, bot)
	players_root.add_child(p)
	if local:
		if not bot:
			local_player = p
		_respawn(p)


func _respawn(p: Player) -> void:
	var ids := Net.players.keys()
	ids.sort()
	var index: int = max(ids.find(p.peer_id), 0)
	var open := layout.open_spawns()
	var s: Array = open[(index + randi() % 2 * (open.size() / 2)) % open.size()]
	if Race.active:
		s = layout.spawns[index % layout.spawns.size()]   # everyone has their own place on the start line
	var team_spot := _team_spawn(p)
	if not team_spot.is_empty():
		s = team_spot   # team modes: on your team's side
	if not DevArgs.spawn.is_empty() and not p.is_bot:
		s = DevArgs.spawn
	p.teleport(layout.clear_feet(s[0]), s[1])   # (never in the ground)
	if s.size() > 2:
		p.input.pitch = s[2]


func _on_pause_toggled() -> void:
	Sound.play("ui_click" if _menu_open() else "ui_back")
	_capture_mouse(not _menu_open())


func _menu_open() -> bool:
	return pause_menu.visible or debug_menu.is_open()


## The pause or debug menu is open (keys and clicks are for it, not the game).
func menu_open() -> bool:
	return _menu_open()


## The navigation mesh bots walk on. Baked when the match starts with bots, or
## when the debug menu adds the first one.
func ensure_navigation() -> void:
	if not has_node("Navigation"):
		var region := MapScenery.bake_navigation(layout)
		add_child(region)
		if not layout.shifting:
			_nav_by_layout[layout.layout_state] = region.navigation_mesh


## The map's parts have started moving (a LayoutEvent): the navigation mesh is no
## good until they stop, and bots stand still meanwhile (see BotBrain).
func _on_parts_moving() -> void:
	_nav_serial += 1
	if has_node("Navigation"):
		layout.nav_pending = true


## ...and have stopped: use the mesh baked for this layout before, or bake one now.
func _on_parts_settled() -> void:
	var region := get_node_or_null("Navigation") as NavigationRegion3D
	if region == null:
		layout.nav_pending = false
		return
	var ready: NavigationMesh = _nav_by_layout.get(layout.layout_state)
	if ready == null:
		_nav_rebake = 0.1   # (a moment, so every part is in its last place when it is read)
		return
	region.navigation_mesh = ready
	var serial := _nav_serial
	get_tree().create_timer(0.15).timeout.connect(func():
		if serial == _nav_serial and not layout.shifting:
			layout.nav_pending = false)   # (the navigation server has taken it in by now)


## Walls or floors cracked or broke: let go of ropes hooked onto the broken bits, and
## (host, with bots) redo the bots' map of where they can walk.
func _on_cells_changed(cells: PackedInt32Array, stages: PackedByteArray) -> void:
	var gone: Array = []
	for i in cells.size():
		if stages[i] >= MapDestruction.BROKEN:
			gone.append(layout.destruction.cell_box(cells[i]).grow(0.15))
	if gone.is_empty():
		return
	for p in players_root.get_children():
		var player := p as Player
		if not player.is_local or player.motor == null or not player.motor.grapple.attached:
			continue
		for box in gone:
			if (box as AABB).has_point(player.motor.grapple.anchor):
				player.motor.grapple.release()
				break
	if Net.is_host() and has_node("Navigation"):
		_nav_by_layout.clear()   # what was baked for either layout no longer fits
		_nav_rebake = NAV_REBAKE_DELAY   # a burst of breaks is redone once


func _rebake_navigation() -> void:
	if _nav_baking:
		_nav_rebake = NAV_REBAKE_DELAY   # still busy with the last one: go again after
		return
	var region := get_node_or_null("Navigation") as NavigationRegion3D
	if region == null:
		return
	if layout.shifting:
		return   # the parts are moving: it is redone when they stop
	_nav_baking = true
	var serial := _nav_serial
	var state := layout.layout_state
	MapScenery.rebake_navigation(region, layout, func(info: String):
		_nav_baking = false
		if serial != _nav_serial or layout.shifting:
			if not layout.shifting:
				_nav_rebake = 0.1   # the parts moved while it baked: again, for where they are now
		elif is_instance_valid(region):
			_nav_by_layout[state] = region.navigation_mesh
			layout.nav_pending = false
		if DevArgs.sync_log:
			print("NAV_REBAKE " + info))


## Debug menu: rebuilds a player from Net.players (after changing their robot or
## gun), keeping where they stand and look.
func rebuild_player(id: int) -> void:
	var old := get_player(id)
	if old == null:
		return
	var pos := old.global_position
	var yaw := old.input.yaw
	var pitch := old.input.pitch
	var respawns := old.respawn_count()
	players_root.remove_child(old)
	old.queue_free()
	_spawn(id)
	var p := get_player(id)
	if p == null:
		return
	p.set_respawn_count(respawns)   # so the next respawn still reads as one everywhere
	p.carry_life_from(old)   # (still waiting to see them back, too)
	if p.is_local:
		p.teleport(pos, yaw)
		p.input.pitch = pitch
	if not Match.is_alive(id):
		p.set_dead()
		if not p.is_local:
			p.expect_dead()


func _spawn_dummies() -> void:
	var root := Node3D.new()
	root.name = "Dummies"
	add_child(root)
	for d in layout.dummies:
		var marker: MapDummy = d[2]
		var dummy := TargetDummy.new().setup(dummies.size(), d[0], d[1], marker.character, marker.gun, marker.caption)
		root.add_child(dummy)
		dummies.append(dummy)


func _spawn_pickups() -> void:
	var root := Node3D.new()
	root.name = "Pickups"
	add_child(root)
	for w in layout.weapon_spawns:
		var p := WeaponPickup.make(pickups.size(), w[0], w[1])
		root.add_child(p)
		pickups.append(p)


func _spawn_items() -> void:
	var root := Node3D.new()
	root.name = "Items"
	add_child(root)
	for it in layout.item_spawns:
		var p := ItemPickup.make(items.size(), it[0], it[1])
		root.add_child(p)
		items.append(p)


## The host says a power-up was taken (by `by`) or is back.
func _on_item_changed(index: int, taken: bool, by: int) -> void:
	if index < 0 or index >= items.size():
		return
	var item: ItemPickup = items[index]
	item.set_taken(taken)
	if not taken:
		Sound.play_at("ui_click", item.spot, "move", -6.0)
	elif by == Net.my_id():
		Sound.play("ui_confirm")
	elif by != 0:
		Sound.play_at("ui_confirm", item.spot, "move")


## The host says a weapon was taken (by `by`) or is back.
func _on_pickup_changed(index: int, taken: bool, by: int, weapon: String) -> void:
	if index < 0 or index >= pickups.size():
		return
	var pickup: WeaponPickup = pickups[index]
	pickup.set_taken(taken)
	if not taken:
		Sound.play_at("ui_click", pickup.spot, "move", -6.0)
		return
	if by == 0:
		return   # just catching up on what is gone (joined mid-match)
	var p := get_player(by)
	if p and p.is_local:
		p.picked_up(weapon)   # a full magazine, whether it is new or one you carry
		if p == local_player:
			Sound.play("equip_" + weapon)
			return
	Sound.play_at("equip_" + weapon, pickup.spot, "move")


func _capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
