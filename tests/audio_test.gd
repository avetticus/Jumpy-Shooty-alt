extends SceneTree
## Headless checks on the sound effects.
## Run: godot --headless --path . --script tests/audio_test.gd
##
## Every sound the code asks for exists and loads; every sound file has a volume;
## every gun has its shot (near, first-person and distant) and its equip sound; the
## reload and pump/bolt steps fit inside each gun's timings.

const DIR := "res://game/audio/sfx/"

var _ok := true
var _files := {}   # name -> true


func _init() -> void:
	for f in DirAccess.get_files_at(DIR):
		f = f.trim_suffix(".import")
		if f.ends_with(".wav"):
			_files[f.get_basename()] = true
	_check(_files.size() > 60, "the sound folder holds the generated sounds (%d)" % _files.size())
	for sound in _files:
		_check(load(DIR + sound + ".wav") is AudioStream, "%s loads" % sound)

	var volume: Dictionary = SfxList.VOLUME
	for key in volume:
		_check(_exists(key), "volume table: %s is a sound" % key)
	for sound in _files:
		var base: String = sound.rsplit("_", true, 1)[0]
		_check(volume.has(sound) or volume.has(base),
			"%s has a volume" % sound)

	for id in WeaponData.GUNS:
		for sound in ["fire_" + id, "fire_%s_fp" % id, "far_" + id, "equip_" + id]:
			_check(_files.has(sound), "%s: %s exists" % [id, sound])
	for id in WeaponData.MELEE:
		for sound in ["swing_" + id, "equip_" + id]:
			_check(_files.has(sound), "%s: %s exists" % [id, sound])
	for sound in ["melee_hit", "slam"]:
		_check(_exists(sound), "%s has variants" % sound)
	_check(_exists("hammer_hit"), "hammer_hit exists")

	var steps: Dictionary = SfxList.RELOAD_STEPS
	var fire_steps: Dictionary = SfxList.FIRE_STEPS
	for id in WeaponData.GUNS:
		var w := WeaponData.by_id(id)
		if w.is_blast():
			_check(not steps.has(id), "%s: no reload, so no reload sounds" % id)   # (the air cannon)
			continue
		_check(steps.has(id), "%s: has reload sounds" % id)
		for step in steps.get(id, []):
			_check(_exists(step[1]), "%s reload: %s exists" % [id, step[1]])
			_check(step[0] < w.reload_time, "%s reload: %s plays before the reload ends" % [id, step[1]])
		for step in fire_steps.get(id, []):
			_check(_exists(step[1]), "%s fire: %s exists" % [id, step[1]])
			_check(step[0] < w.fire_interval, "%s fire: %s plays before the next shot is ready" % [id, step[1]])

	for sound in ["step", "crawl", "impact_wall", "impact_body", "ricochet", "whiz"]:
		_check(_exists(sound), "%s has variants" % sound)
	for sound in ["jump", "land", "land_hard", "flip", "glide", "dive", "roll", "slide", "belly_slide", "wall_run",
			"wall_jump", "vault", "ledge_climb", "crouch", "stand", "grapple_fire", "grapple_attach",
			"grapple_release", "grapple_miss", "grapple_taut", "dry_click", "hitmarker", "hitmarker_head", "kill", "kill_head",
			"hurt", "hurt_head", "death", "respawn", "ui_hover", "ui_click", "ui_confirm", "ui_back",
			"ui_toggle", "ui_tick", "ui_select", "match_start", "match_end"]:
		_check(_exists(sound), "%s exists" % sound)


	print("PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _exists(sound: String) -> bool:
	return _files.has(sound) or _files.has(sound + "_1")


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("FAIL: " + what)
