extends SceneTree
## Breakable walls and floors (MapDestruction), on the real maps.
## Run: godot --headless --path . --script tests/destruction_test.gd
##
## Arena maps have breakable walls and floors and race maps none; every spawn point
## stands on floor that cannot break; a broken cell lets a shot (a ray) through where
## it was blocked, its neighbours stay; an intact panel's collision is one box (so it
## walks exactly like before); a cell under a desk or a column never breaks; enough
## damage cracks a cell, then breaks it; the hit is found from where a shot landed;
## a line through walls (the railgun's slug) finds every cell it passes through.

var failures := 0


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		failures += 1


func _make(id: String) -> MapRoot:
	var map: MapRoot = Maps.make(id)
	map.destructible = Maps.game_of(id) != "race"
	root.add_child(map)
	var started := Time.get_ticks_msec()
	map.build()
	print("%s: built in %d ms" % [id, Time.get_ticks_msec() - started])
	return map


func _run() -> void:
	await process_frame
	for id in ["construction_site", "office", "rail_yard", "lost_temple", "neon_arcade"]:
		var map := _make(id)
		var d := map.destruction
		_check(d != null and d.panels.size() > 10, "%s has breakable panels (%d)" % [id, d.panels.size() if d else 0])
		if d == null:
			map.queue_free()
			continue
		var open := d.breakable_count()
		print("  %d cells, %d can break" % [d.cells.size(), open])
		_check(open > 50 and open < d.cells.size(), "%s: many cells can break, some are held" % id)
		var intact_one_box := true
		for p in d.panels:
			if (p.body as StaticBody3D).get_child_count() != 1:
				intact_one_box = false
		_check(intact_one_box, "%s: every intact panel collides as one box" % id)
		# Spawn points: the floor under each stays.
		var space := map.get_world_3d().direct_space_state
		await physics_frame
		var spawn_ok := true
		for s in map.spawns:
			var at: Vector3 = s[0]
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3(0, 1, 0), at - Vector3(0, 2, 0), 1))
			if hit and hit.collider.has_meta("panel"):
				var c := d.cell_at(hit.collider, hit.position, hit.normal)
				if not d.cells[c].protected:
					spawn_ok = false
		_check(spawn_ok, "%s: no spawn point stands on floor that can break" % id)
		# Break one cell of a floor and one of a wall, through the same path as a shot.
		for want_floor in [true, false]:
			var c := _open_cell(d, want_floor)
			_check(c >= 0, "%s: found a breakable %s cell" % [id, "floor" if want_floor else "wall"])
			if c < 0:
				continue
			var box := d.cell_box(c)
			var panel: Dictionary = d.panels[d.cells[c].panel]
			var normal: Vector3 = (panel.xf as Transform3D).basis[panel.thin].normalized()
			var centre := box.get_center()
			var from := centre + normal * 1.5
			var to := centre - normal * 1.5
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
			_check(not hit.is_empty() and d.cell_at(hit.collider, hit.position, hit.normal) == c, "  a shot at it lands on that cell")
			# The railgun's slug goes through everything: the cells on its line are found from their boxes.
			var on_line := d.cells_along(from + normal * 40.0, to - normal * 40.0).filter(func(x): return x[0] == c)
			var into := 41.5 - float((panel.size as Vector3)[panel.thin]) * 0.5
			_check(on_line.size() == 1 and absf(float(on_line[0][1]) - into) < 0.05,
				"  a line right through it (the railgun's) finds it, where it goes in (%s, want %.2f m)" % [str(on_line), into])
			_check(d.cells_along(from + Vector3(0, 30, 0), to + Vector3(0, 30, 0)).filter(func(x): return x[0] == c).is_empty(),
				"  ...and a line well clear of it does not")
			var hp: float = d.cells[c].max_hp
			d.damage(c, hp * 0.5)
			var change := d.flush()
			_check(not change.is_empty() and change[1][0] == 1, "  half its strength cracks it")
			d.apply(change[0], change[1])
			d.damage(c, hp)
			change = d.flush()
			_check(not change.is_empty() and change[1][0] == MapDestruction.BROKEN, "  the rest breaks it")
			d.apply(change[0], change[1])
			await physics_frame
			await physics_frame
			hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
			var through: bool = hit.is_empty() or not hit.collider.has_meta("panel") or int(hit.collider.get_meta("panel")) != d.cells[c].panel
			_check(through, "  a shot now goes through the hole")
			_check(d.cells_along(from, to).filter(func(x): return x[0] == c).is_empty(), "  a broken cell is no longer on any line")
			_check((panel.body as StaticBody3D).get_child_count() >= 1 or panel.n.x * panel.n.y * panel.n.z == 1, "  the rest of the panel still stands")
			d.damage(c, 999.0)
			_check(d.flush().is_empty(), "  a broken cell takes no more damage")
		# A protected cell ignores damage.
		var held := -1
		for c in d.cells.size():
			if d.cells[c].protected:
				held = c
				break
		d.damage(held, 99999.0)
		_check(d.flush().is_empty(), "%s: a held cell never breaks" % id)
		# Late joiners: the snapshot lists what is broken.
		var snap := d.snapshot()
		_check((snap[0] as PackedInt32Array).size() >= 2, "%s: the snapshot for late joiners lists the broken cells" % id)
		map.queue_free()
		await process_frame
	for id in ["rooftop_run", "foundry", "sky_ruins", "summit_plunge"]:
		var map := _make(id)
		_check(map.destruction == null, "%s (race): nothing breaks" % id)
		map.queue_free()
	await process_frame
	# Melee weapons break walls faster than their damage alone.
	_check(WeaponData.by_id("hammer").structure_damage > 1.0, "the hammer hits walls extra hard")
	print("PASS" if failures == 0 else "FAILED: %d" % failures)
	quit(1 if failures else 0)


## A cell that can break, on a floor (thin along y) or a wall, away from the panel edges if it can.
func _open_cell(d: MapDestruction, floor_panel: bool) -> int:
	var fallback := -1
	for c in d.cells.size():
		var cell: Dictionary = d.cells[c]
		var panel: Dictionary = d.panels[cell.panel]
		if cell.protected or cell.stage != 0 or (panel.thin == 1) != floor_panel or panel.kind.contains("glass"):
			continue
		var n: Vector3i = panel.n
		if n.x * n.y * n.z >= 4:
			return c
		fallback = c
	return fallback
