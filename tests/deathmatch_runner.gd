extends Node
## Deathmatch checks:
##  - the map lists: Deathmatch is a game of its own, played on the Construction Site
##    and the Office (and only there);
##  - every Deathmatch map has weapon pickups, each over a floor with room to stand;
##  - the inventory rules the host keeps: you start empty-handed, a pickup goes in your
##    inventory (and in your hands if they were empty), you can only switch to what you
##    carry, a death empties it, and the lobby weapon choice is left alone;
##  - the pause menu's Loadout offers the robot and weapon in a free-for-all, and only
##    the robot in a Deathmatch.
## Started by tests/deathmatch_test.gd.

var _fails: Array[String] = []


func run() -> void:
	await get_tree().process_frame
	print("Deathmatch checks")
	_maps()
	await _pickup_spots()
	_inventory()
	_items()
	await _loadout_menu()
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


func _maps() -> void:
	print("  map lists")
	_expect("dm" in Maps.GAMES, "Deathmatch is one of the games")
	_expect(Maps.ids_for("dm") == ["construction_site", "office", "kilnworks", "rail_yard", "lost_temple", "neon_arcade", "castle", "halcyon", "cirrus", "empyrean", "haunted_house", "sky_island"], "Deathmatch is played on every arena (%s)" % [Maps.ids_for("dm")])
	_expect(Maps.fits("office", "dm") and Maps.fits("office", "ffa"), "the Office hosts both a free-for-all and a Deathmatch")
	_expect(not Maps.fits("rooftop_run", "dm") and not Maps.fits("testing_grounds", "dm"), "race maps and the test map do not host a Deathmatch")
	_expect(Maps.game_of("office") == "ffa", "an arena's own game is still the free-for-all")


func _pickup_spots() -> void:
	print("  weapon pickups")
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	var found := {}
	for id in Maps.ids_for("dm"):
		var map := Maps.make(id)
		get_tree().root.add_child(map)
		map.build(false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var space := get_tree().root.get_world_3d().direct_space_state
		var kinds := {}
		var bad: Array = []
		for w in map.weapon_spawns:
			var pos: Vector3 = w[0]
			kinds[w[1]] = true
			var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -0.5, 0), 1))
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cap
			q.collision_mask = 1
			q.transform = Transform3D(Basis(), pos + Vector3(0, 1.0, 0))
			if not down or not space.intersect_shape(q, 1).is_empty():
				bad.append(pos)
		_expect(map.weapon_spawns.size() >= 8, "%s: %d weapon pickups (8 or more)" % [id, map.weapon_spawns.size()])
		_expect(kinds.keys().all(func(k): return WeaponData.has(k)), "%s: every pickup is a real weapon (%s)" % [id, kinds.keys()])
		_expect(kinds.size() >= 10, "%s: at least 10 different weapons (%d)" % [id, kinds.size()])
		for k in kinds:
			found[k] = true
		_expect(bad.is_empty(), "%s: every pickup is over a floor with room to stand %s" % [id, bad])
		var items := {}
		var bad_items: Array = []
		for it in map.item_spawns:
			var pos: Vector3 = it[0]
			items[it[1]] = true
			var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -0.5, 0), 1))
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cap
			q.collision_mask = 1
			q.transform = Transform3D(Basis(), pos + Vector3(0, 1.0, 0))
			if not down or not space.intersect_shape(q, 1).is_empty():
				bad_items.append(pos)
		if not map.item_spawns.is_empty():   # (maps without power-ups yet are skipped)
			_expect(items.size() == ItemPickup.KINDS.size(),"%s: every power-up can be found (%s)" % [id, items.keys()])
		_expect(bad_items.is_empty(), "%s: every power-up is over a floor with room to stand %s" % [id, bad_items])
		map.queue_free()
		await get_tree().process_frame
	var missing := WeaponData.IDS.filter(func(w): return not found.has(w))
	_expect(missing.is_empty(), "every weapon can be found on one of the Deathmatch maps (missing: %s)" % [missing])


func _inventory() -> void:
	print("  inventory (two slots: keys 1 and 2)")
	Net.start_offline("Tester", "needle", "bolt_action")
	Net.match_settings = {"game": "dm", "mode": "kills", "kills": 10, "minutes": 8, "race_minutes": 10, "map": "office"}
	Net.in_match = true
	Match.health[1] = Match.MAX_HEALTH
	_expect(Net.is_deathmatch(), "the match is a Deathmatch")
	Net.host_clear_inventory(1, false)
	_expect(Net.player_weapon(1) == "none" and Net.player_inventory(1) == ["", ""], "you start with empty hands and two empty slots")
	Net.host_give_weapon(1, "shotgun")
	_expect(Net.player_weapon(1) == "shotgun" and Net.player_inventory(1) == ["shotgun", ""], "your first pickup goes in slot 1 and in your hands")
	Net.host_give_weapon(1, "pistol")
	_expect(Net.player_weapon(1) == "shotgun", "a second pickup does not change what you hold")
	_expect(Net.player_inventory(1) == ["shotgun", "pistol"], "it goes in slot 2 (%s)" % [Net.player_inventory(1)])
	_expect(not Net.host_give_weapon(1, "pistol"), "picking up one you carry only refills it")
	Net.switch_my_weapon("pistol")
	_expect(Net.player_weapon(1) == "pistol", "you can switch to a weapon you carry")
	Net.switch_my_weapon("bolt_action")
	_expect(Net.player_weapon(1) == "pistol", "you can't switch to one you don't carry")
	Net.host_give_weapon(1, "railgun")
	_expect(Net.player_inventory(1) == ["shotgun", "railgun"] and Net.player_weapon(1) == "railgun",
		"with both slots full a new weapon replaces the one in your hands (%s, holding %s)" % [Net.player_inventory(1), Net.player_weapon(1)])
	_expect(Net.player_weapons(1).size() == Net.SLOTS, "you never carry more than %d" % Net.SLOTS)
	Net.host_clear_inventory(1)
	_expect(Net.player_weapon(1) == "none" and Net.player_weapons(1).is_empty(), "dying empties your hands and both slots")
	_expect(Net.player_loadout_weapon(1) == "bolt_action", "the weapon you chose in the lobby is kept for other games")
	Net.match_settings["game"] = "ffa"
	_expect(Net.player_weapon(1) == "bolt_action", "in a free-for-all you hold your chosen weapon")
	Net.in_match = false


func _items() -> void:
	print("  power-ups")
	var apply := func(k: String) -> bool: return Match.call("_host_apply_item", 1, k)
	Match.health[1] = 60.0
	_expect(apply.call("health_small") and Match.health[1] == 85.0, "small health gives 25")
	_expect(apply.call("health_small") and Match.health[1] == 100.0, "small health stops at 100")
	_expect(not apply.call("health_medium") and Match.health[1] == 100.0, "health is left for someone who needs it at full health")
	Match.health[1] = 40.0
	_expect(apply.call("health_medium") and Match.health[1] == 90.0, "medium health gives 50")
	_expect(apply.call("uber") and Match.health[1] == 190.0, "uber health gives 100, past 100")
	_expect(apply.call("uber") and Match.health[1] == Match.MAX_OVERHEAL, "uber health stops at %d" % Match.MAX_OVERHEAL)
	_expect(not apply.call("health_small"), "no small health while overhealed")
	_expect(Match.damage_multiplier(1) == 1.0, "normal damage without the boost")
	_expect(apply.call("damage") and Match.damage_multiplier(1) == 2.0, "the damage boost doubles damage")
	_expect(is_equal_approx(Match.damage_boost[1], 30.0), "the damage boost lasts 30 seconds")
	Match.damage_boost.clear()
	Match.health[1] = Match.MAX_HEALTH


func _loadout_menu() -> void:
	print("  pause menu loadout")
	for game in ["ffa", "dm"]:
		Net.match_settings["game"] = game
		Net.in_match = true
		var menu := PauseMenu.new()
		get_tree().root.add_child(menu)
		await get_tree().process_frame
		menu.call("_show_loadout")
		await get_tree().process_frame
		var robots := menu.find_children("*", "CharacterPicker", true, false).size()
		var guns := menu.find_children("*", "WeaponPicker", true, false).size()
		if game == "ffa":
			_expect(robots == 1 and guns == 1, "free-for-all: the loadout offers a robot and a weapon")
		else:
			_expect(robots == 1 and guns == 0, "Deathmatch: the loadout offers only the robot")
		menu.queue_free()
		await get_tree().process_frame
	Net.in_match = false
