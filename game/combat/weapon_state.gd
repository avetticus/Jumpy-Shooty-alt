class_name WeaponState
extends RefCounted
## The local player's copy of a weapon: ammo, fire cooldown and reloading.
## Most guns reload the whole magazine at once. The shotgun loads a shell at a time
## (WeaponData.reload_per_round) and can fire between shells, which stops the reload.
## Energy weapons (WeaponData.recharge) never reload: the battery refills itself a
## moment after the last shot, and emptying it overheats the gun (a reload, of sorts).
## The minigun (WeaponData.spin_up) fires slower until its barrels are spun up. The
## pistols fire faster while tilted on their side (WeaponData.tilt_interval).
## Blades and blasts (the air cannon) never run dry: only the time between swings or
## blasts holds them back.

var data: WeaponData
var ammo := 0
var _cooldown := 0.0
var _reload_left := 0.0
var _since_fire := 99.0   # seconds since the last shot (energy weapons start refilling after a moment)
var _refill := 0.0        # part of a round the battery has refilled
var spin := 0.0           ## the minigun: how spun up the barrels are, 0..1 (Player spins them)
var tilted := false       ## the pistols: held on their side (alt fire: Player sets it from alt_held)


func _init(d: WeaponData) -> void:
	data = d
	ammo = d.magazine


func is_reloading() -> bool:
	return _reload_left > 0.0


## How far the reload has got, 0..1: for a shell-by-shell reload, how full the magazine is.
func reload_progress() -> float:
	if not is_reloading():
		return 1.0
	var round_done := 1.0 - _reload_left / data.reload_time
	if data.reload_per_round:
		return clampf((ammo + round_done) / float(data.magazine), 0.0, 1.0)
	return round_done


## The current round (or the whole magazine) being loaded, 0..1: drives the reload animation.
func round_progress() -> float:
	return 1.0 - _reload_left / data.reload_time if is_reloading() else 0.0


func update(delta: float) -> void:
	_cooldown = max(_cooldown - delta, 0.0)
	_since_fire += delta
	if data.recharge > 0.0 and _reload_left <= 0.0 and ammo < data.magazine and _since_fire >= data.recharge_delay:
		_refill += data.recharge * delta
		while _refill >= 1.0 and ammo < data.magazine:
			_refill -= 1.0
			ammo += 1
	else:
		_refill = 0.0
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			if data.reload_per_round:
				ammo += 1
				_reload_left = data.reload_time if ammo < data.magazine else 0.0
			else:
				_reload_left = 0.0
				ammo = data.magazine


## Seconds until the gun can fire again (0 = ready).
func cooldown() -> float:
	return _cooldown


## Holds the next shot or swing off for at least `seconds` from now (a slow blow).
func hold_off(seconds: float) -> void:
	_cooldown = maxf(_cooldown, seconds)


func can_fire() -> bool:
	if data.is_melee() or data.is_blast():
		return _cooldown <= 0.0   # a blade (or the air) never runs dry
	if _cooldown > 0.0 or ammo <= 0:
		return false
	return data.reload_per_round or not is_reloading()


## Returns true if a shot was fired. Starts a reload automatically when empty.
func fire() -> bool:
	if not can_fire():
		if ammo <= 0:
			start_reload()
		return false
	if data.is_melee() or data.is_blast():
		_cooldown = data.fire_interval
		return true
	_reload_left = 0.0   # a shell-by-shell reload stops for the shot
	ammo -= 1
	_cooldown = data.interval_at(spin, tilted)
	_since_fire = 0.0
	if ammo <= 0:
		start_reload()
	return true


func start_reload() -> void:
	if data.is_melee() or data.is_blast() or is_reloading() or ammo >= data.magazine:
		return
	_reload_left = data.reload_time


func reset() -> void:
	ammo = data.magazine
	_cooldown = 0.0
	_reload_left = 0.0
	_since_fire = 99.0
	_refill = 0.0
	spin = 0.0
	tilted = false
