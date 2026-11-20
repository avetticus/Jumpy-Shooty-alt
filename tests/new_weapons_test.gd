extends SceneTree
## Headless checks on the third batch of weapons (WeaponData.BATCH_3): there are 22,
## each is distinct from every other weapon and is in the pickers, the bots, the
## sounds, the HUD's icons and the robots' models; and their new ways of playing work:
## the minigun spins up, the energy guns refill themselves and overheat, the harpoon
## pulls, the darts (nails, bolts) hurt only who they hit, and Gun Game climbs through them.
## Run: godot --headless --path . --script tests/new_weapons_test.gd

var _ok := true


func _init() -> void:
	var batch: Array = WeaponData.BATCH_3
	# (BotBrain and GunGame lean on the autoloads, which a --script run does not have: read them.)
	var bot_src := FileAccess.get_file_as_string("res://game/bot/bot_brain.gd")
	var gg_src := FileAccess.get_file_as_string("res://game/match/gun_game.gd")
	var at := gg_src.find("const LADDER := [")
	var ladder: Array = JSON.parse_string(gg_src.substr(at + 16, gg_src.find("]", at) - at - 15).replace("\n", " ").replace("\t", ""))
	_check(batch.size() == 22, "22 new weapons (%d)" % batch.size())
	_check(WeaponData.IDS.size() == 46, "46 weapons in all, Karate the last (%d)" % WeaponData.IDS.size())
	var names := {}
	var looks := {}
	for id in WeaponData.IDS:
		var w := WeaponData.by_id(id)
		_check(not names.has(w.display_name), "%s: a name of its own (%s)" % [id, w.display_name])
		names[w.display_name] = id
		# No two weapons play the same: the numbers that matter differ somewhere.
		var key := "%s|%s|%.1f|%d|%.2f|%d|%.1f|%.1f|%.2f|%s|%s" % [w.kind, w.automatic, w.damage, w.pellets, w.fire_interval,
			w.magazine, w.max_range, w.charge_damage, w.spin_up + w.recharge, w.pull, w.explosive]
		_check(not looks.has(key), "%s: plays differently from %s" % [id, looks.get(key, "")])
		looks[key] = id
	for id in batch:
		_check(WeaponData.has(id) and WeaponData.by_id(id).id == id, "%s: a real weapon" % id)
		var in_groups := 0
		for g in WeaponData.GROUPS:
			if id in g[1]:
				in_groups += 1
		_check(in_groups == 1, "%s: in exactly one class of the pickers" % id)
		_check((id in WeaponData.GUNS) != (id in WeaponData.MELEE), "%s: a gun or a blade" % id)
		_check(bot_src.contains('"%s": [' % id), "%s: the bots know what range to fight it at" % id)
		_check(HudStyle.weapon_width(id) != 22.0, "%s: has an icon of its own" % id)
		var w := WeaponData.by_id(id)
		_check(w.move_bonus >= 0.8 and w.move_bonus <= 1.2, "%s: carrying it changes your speed only a little" % id)
		if w.is_melee():
			_check(MeleeModel.EDGES.has(id), "%s: a model with an edge for the swing trail" % id)
			_check(not MeleeModel.parts(id).is_empty(), "%s: builds a model" % id)
			_check(MeleeSwing.PACE.has(id) and MeleeSwing.MOVES_LIKE.has(id), "%s: swings at its own pace" % id)
	var all_parts := {}
	for id in WeaponData.MELEE:
		var tris := 0
		for part in MeleeModel.parts(id):
			tris += (part[0] as Mesh).get_faces().size()
		_check(not all_parts.has(tris), "%s: a model of its own" % id)
		all_parts[tris] = id

	# The minigun: slow until spun up, then 20 rounds a second.
	var mini := WeaponData.by_id("minigun")
	_check(mini.automatic and mini.spin_up > 0.0 and mini.interval_at(0.0) > mini.interval_at(1.0) * 2.5, "minigun: spins up")
	var s := WeaponState.new(mini)
	_check(_shots_in(s, 1.0, 0.0) < _shots_in(WeaponState.new(mini), 1.0, 1.0) / 2, "minigun: spun down, it fires far slower")
	_check(_shots_in(WeaponState.new(mini), 1.0, 1.0) >= 16, "minigun: spun up, about 20 rounds a second")

	# Energy guns: never reload while you keep the battery from running flat; flat, they overheat.
	for id in ["plasma_pistol", "laser_rifle"]:
		var w := WeaponData.by_id(id)
		s = WeaponState.new(w)
		for i in 5:
			s.fire()
			_step(s, w.fire_interval + 0.02)
		_check(s.ammo == w.magazine - 5 and not s.is_reloading(), "%s: shooting drains the battery" % id)
		_step(s, w.recharge_delay + 5.0 / w.recharge + 0.2)
		_check(s.ammo == w.magazine, "%s: and it refills by itself a moment after" % id)
		var guard := 0
		while not s.is_reloading() and guard < 500:
			s.fire()
			_step(s, w.fire_interval + 0.02)
			guard += 1
		_check(s.is_reloading() and not s.can_fire(), "%s: run it flat and it overheats" % id)
		_step(s, w.reload_time + 0.05)
		_check(s.ammo == w.magazine and s.can_fire(), "%s: cooled down, full again" % id)

	# The harpoon pulls; the air cannon hurts nobody, but a full charge shoves hard enough
	# to kill by the wall (more in tests/air_cannon_test.gd).
	var harpoon := WeaponData.by_id("harpoon_gun")
	_check(harpoon.pull and harpoon.knockback > 10.0, "harpoon: reels the target in")
	var air := WeaponData.by_id("air_cannon")
	_check(air.is_blast() and air.damage == 0.0 and air.blast_knockback(1.0, 0.0)[0] > 30.0, "air cannon: hurts nobody, a full charge shoves hard")
	# Darts: no blast; the crossbow kills with a headshot.
	for id in ["nail_gun", "crossbow"]:
		var w := WeaponData.by_id(id)
		_check(w.is_projectile() and not w.explosive and w.self_damage == 0.0, "%s: a dart, no blast" % id)
	var bow := WeaponData.by_id("crossbow")
	_check(bow.damage < 100.0 and bow.damage * bow.headshot_multiplier >= 100.0, "crossbow: a headshot kills, a body shot does not")
	for id in ["flare_gun", "mortar", "plasma_cannon"]:
		_check(WeaponData.by_id(id).is_projectile() and WeaponData.by_id(id).explosive, "%s: flies and bursts" % id)
	_check(WeaponData.by_id("mortar").splash_radius > WeaponData.by_id("rocket_launcher").splash_radius, "mortar: the biggest blast")
	var looks_of := {}
	for id in WeaponData.GUNS:
		if WeaponData.by_id(id).is_projectile():
			looks_of[WeaponData.by_id(id).look()] = true
	_check(looks_of.size() >= 7, "projectiles: seven looks (%s)" % [looks_of.keys()])
	var derringer := WeaponData.by_id("derringer")
	_check(derringer.magazine == 2 and derringer.damage * 2.0 >= 100.0 and derringer.damage_at(30.0) * 2.0 < 50.0,
		"derringer: both shots kill up close, not far away")
	var amr := WeaponData.by_id("anti_materiel")
	_check(amr.damage < 100.0 and amr.damage * amr.headshot_multiplier >= 100.0 and amr.structure_damage >= 5.0,
		"anti-materiel: 95 to the body, a headshot kills, breaks walls")
	_check(WeaponData.by_id("energy_sword").charge_damage * 2.0 >= 100.0 and WeaponData.by_id("energy_sword").charge_knockback < 17.5,
		"energy sword: two full swings kill, but it never slams anyone into a wall")
	_check(WeaponData.by_id("scythe").arc_degrees > WeaponData.by_id("bat").arc_degrees, "scythe: the widest swing")
	_check(WeaponData.by_id("claws").fire_interval < WeaponData.by_id("brass_knuckles").fire_interval, "claws: the fastest swing")

	# Gun Game: every rung a real gun, no repeats, ends on the knuckles, and the new guns are on it.
	var seen := {}
	for id in ladder:
		_check(WeaponData.has(id) and not seen.has(id), "gun game: %s is a real gun, once" % id)
		seen[id] = true
	_check(ladder[-1] == "brass_knuckles", "gun game: ends with the knuckles")
	var new_rungs := ladder.filter(func(g): return g in batch).size()
	_check(new_rungs >= 10, "gun game: climbs through the new guns too (%d)" % new_rungs)

	print("NEW WEAPONS TEST PASSED" if _ok else "NEW WEAPONS TEST FAILED")
	quit(0 if _ok else 1)


## Rounds fired holding the trigger for `seconds`, with the barrels spun up `spin`.
func _shots_in(s: WeaponState, seconds: float, spin: float) -> int:
	var n := 0
	var t := 0.0
	while t < seconds:
		s.spin = spin
		if s.fire():
			n += 1
		s.update(1.0 / 120.0)
		t += 1.0 / 120.0
	return n


func _step(s: WeaponState, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		s.update(1.0 / 60.0)
		t += 1.0 / 60.0


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("FAIL: " + what)
