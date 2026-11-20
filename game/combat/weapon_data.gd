class_name WeaponData
extends Resource
## Describes one weapon. New weapons are new WeaponData values, not new code,
## unless they need a new kind of behaviour (for example projectiles).
##
## Every player picks one weapon before the match (in the lobby, or on the Practice and
## Vs Bots pages) and can swap it while waiting to respawn. All numbers are first
## guesses for playtesting. Damage is per pellet; a full-health player has 100.
##
## Melee weapons (Kind.MELEE) swing instead of shooting, and every swing is charged:
## hold the button to wind up (the body coils; there is no meter), let go to swing.
## The blow hits everyone within `max_range` metres and `arc_degrees` of where you
## look. A tap is weak (`damage`, `knockback`); a full wind-up of `charge_time`
## seconds hits for `charge_damage` and shoves far harder (`charge_knockback`).
## No blow kills a healthy player by itself: the kill is the wall you knock them
## into (see Match: a hard enough shove into a wall hurts). They have no ammo.
## Every hit, gun or blade, shoves the target.

enum Kind { HITSCAN, MELEE, PROJECTILE }

## The weapons in groups, as the pickers show them (and the number keys pick them while
## you wait to respawn: 1 for sidearms, 2 for shotguns... pressing again goes through the group).
const GROUPS := [
	["Sidearms", ["pistol", "revolver", "machine_pistol", "akimbo", "derringer"]],
	["Shotguns", ["shotgun", "break_action", "air_cannon"]],
	["Rifles", ["smg", "rifle", "burst_rifle", "lmg", "minigun", "battle_rifle", "laser_rifle", "nail_gun"]],
	["Marksman", ["lever_action", "bolt_action", "sniper", "railgun", "crossbow", "anti_materiel"]],
	["Explosives", ["rocket_launcher", "grenade_launcher", "plasma_cannon"]],
	["Melee", ["sword", "hammer", "dagger", "brass_knuckles", "spear", "axe", "bat",
		"scythe", "mace", "machete", "wrench", "energy_sword", "karate"]],
]
## Every weapon a player can pick, in the order the pickers show them.
const IDS := ["pistol", "revolver", "machine_pistol", "akimbo", "derringer",
	"shotgun", "break_action", "air_cannon",
	"smg", "rifle", "burst_rifle", "lmg", "minigun", "battle_rifle", "laser_rifle", "nail_gun",
	"lever_action", "bolt_action", "sniper", "railgun", "crossbow", "anti_materiel",
	"rocket_launcher", "grenade_launcher", "plasma_cannon",
	"sword", "hammer", "dagger", "brass_knuckles", "spear", "axe", "bat",
	"scythe", "mace", "machete", "wrench", "energy_sword", "karate"]
const MELEE := ["sword", "hammer", "dagger", "brass_knuckles", "spear", "axe", "bat",
	"scythe", "mace", "machete", "wrench", "energy_sword", "karate"]
const GUNS := ["pistol", "revolver", "machine_pistol", "akimbo", "derringer",
	"shotgun", "break_action", "air_cannon",
	"smg", "rifle", "burst_rifle", "lmg", "minigun", "battle_rifle", "laser_rifle", "nail_gun",
	"lever_action", "bolt_action", "sniper", "railgun", "crossbow", "anti_materiel",
	"rocket_launcher", "grenade_launcher", "plasma_cannon"]
## The third batch of weapons: see the bottom of this file.
const BATCH_3 := ["derringer", "air_cannon",
	"minigun", "battle_rifle", "laser_rifle", "nail_gun", "crossbow", "anti_materiel",
	"plasma_cannon", "scythe", "mace", "machete", "wrench", "energy_sword"]
## Weapons nobody picks: a mode hands them out (the Golden Gun, see GoldenGun). Real
## weapons all the same (has(), by_id()), but never in IDS, so no picker shows them.
const HIDDEN := ["golden_gun"]
## Guns held like the pistol (in both hands round the grip, no stock): they use the
## pistol's poses, with their own reload and firing clips.
const SIDEARMS := ["pistol", "revolver", "machine_pistol", "derringer", "golden_gun"]

@export var id := "pistol"
@export var display_name := "Pistol"
@export var short_name := "Pistol"       ## for the pickers' buttons
@export var blurb := ""
@export var kind: Kind = Kind.HITSCAN
@export var damage := 25.0           ## per pellet
@export var pellets := 1             ## shots per trigger pull (the shotgun's spread of pellets)
@export var fire_interval := 0.17    ## seconds between shots, at least
@export var automatic := false       ## false = one shot per click
@export var magazine := 12
@export var reload_time := 1.3       ## the whole magazine, or one round when reload_per_round
@export var reload_per_round := false   ## loads a round at a time (shotgun); firing stops the reload
@export var max_range := 200.0
@export var spread_degrees := 0.25   ## random aim wobble per shot (the pellets' cone for a shotgun)
@export var falloff_start := 1000.0  ## metres: full damage up to here...
@export var falloff_end := 1000.0    ## ...then less and less, down to falloff_min x damage from here on
@export var falloff_min := 1.0
@export var headshot_multiplier := 1.5
@export var muzzle_bone := "muzzle"  ## the marker bone in the robot model where shots leave the barrel
@export var crosshair := "cross"     ## cross, spread (a ring the size of the cone), dot
@export var kick := 1.0              ## how hard the gun kicks in the hands when it fires
## Knockback: metres per second added to the target's speed, along the shot (per
## pellet) or away from the swing, plus a little lift so it carries off the ground.
@export var knockback := 1.5
@export var knockback_up := 0.0
## Damage to breakable walls and floors, times the weapon's damage (see MapDestruction).
@export var structure_damage := 1.0
## Burst fire: each pull fires `burst` rounds, `burst_gap` seconds apart (fire_interval is between bursts).
@export var burst := 1
@export var burst_gap := 0.0
## A shot that goes through everything in its path for its whole max_range (the
## railgun): every player and dummy along the line, and walls, floors and anything else
## in the level, damaging every breakable piece it passes through.
@export var pierce := false
## Akimbo: a gun in each hand. The shots take turns, right then left; the left gun's
## leave from this marker bone (and kick the left arm).
@export var muzzle_bone_left := ""
## Spin-up (the minigun): holding the trigger spins the barrels up over this many
## seconds; the first shots come SPIN_START times slower than fire_interval.
@export var spin_up := 0.0
## Energy weapons: the magazine is a battery that refills itself, `recharge` rounds a
## second once you have not fired for `recharge_delay` seconds. No reloading; empty it
## and it overheats for `reload_time` seconds.
@export var recharge := 0.0
@export var recharge_delay := 0.5
## The colour of the tracer (alpha 0: the usual warm yellow).
@export var tracer_color := Color(0, 0, 0, 0)
## Looks, sounds and moves like this weapon (its model, clips and sounds): "" for its own.
@export var looks_like := ""
## Drawn in gold (the Golden Gun).
@export var golden := false
@export_group("Projectile")
## Kind.PROJECTILE: a rocket or grenade that flies (the host follows it) and blows up
## where it lands: full `damage` within `splash_inner` metres, falling to nothing at
## `splash_radius`. Your own blast hurts you `self_damage` times as much, and shoves you
## just as hard (rocket jumps).
@export var projectile_speed := 30.0
@export var projectile_gravity := 0.0
@export var splash_radius := 4.0
@export var splash_inner := 1.0
@export var self_damage := 0.4
@export var fuse := 6.0               ## seconds before it blows up in mid-air anyway
## How it looks in flight: rocket, grenade, orb, nail or bolt (see look()).
@export var projectile_look := ""
## False for a dart (a nail, a bolt): it only hurts whoever it hits, with no blast.
@export var explosive := true
@export_group("Melee")
@export var windup := 0.0            ## the shortest wind-up: a tap still draws back this long before it swings
@export var charge_time := 0.64       ## seconds of holding the button for a full wind-up
@export var charge_damage := 0.0     ## damage of a fully wound-up blow (`damage` is a tap's)
@export var charge_knockback := 0.0  ## knockback of a fully wound-up blow (`knockback` is a tap's)
@export var charge_knockback_up := 0.0
@export var two_handed := false      ## both hands on the grip (everything but the dagger and the knuckles)
@export var arc_degrees := 0.0       ## hits anyone within this angle of where you look
@export var lunge := 0.0             ## forward speed a fully wound-up swing gives you (a tap: 40% of it)
@export var backstab_multiplier := 1.0  ## damage from behind
@export var move_bonus := 1.0        ## running speed while carrying it (light blades are quicker)


static func pistol() -> WeaponData:
	var w := WeaponData.new()
	w.blurb = "Semi-auto sidearm. Accurate, quick to reload, 4 body shots."
	w.knockback = 2.0
	return w


## Pump-action: ten pellets in a wide cone. A kill in one shot up close, weak beyond
## about 15 m. Loads a shell at a time; shooting stops the reload.
static func shotgun() -> WeaponData:
	var w := WeaponData.new()
	w.id = "shotgun"
	w.display_name = "Shotgun"
	w.short_name = "Shotgun"
	w.blurb = "Pump-action. One shot up close, weak past 15 m. Loads a shell at a time."
	w.damage = 11.0
	w.pellets = 10
	w.fire_interval = 0.8
	w.magazine = 6
	w.reload_time = 0.5
	w.reload_per_round = true
	w.max_range = 60.0
	w.spread_degrees = 4.5
	w.falloff_start = 9.0
	w.falloff_end = 22.0
	w.falloff_min = 0.25
	w.headshot_multiplier = 1.25
	w.muzzle_bone = "muzzle_shotgun"
	w.crosshair = "spread"
	w.kick = 2.2
	w.knockback = 1.3      # per pellet: a full blast up close is a real shove
	w.knockback_up = 0.25
	return w


## Fully automatic: ten shots a second, 30 rounds, a little wobble.
static func rifle() -> WeaponData:
	var w := WeaponData.new()
	w.id = "rifle"
	w.display_name = "Assault Rifle"
	w.short_name = "Rifle"
	w.blurb = "Full-auto, 10 shots a second. Good at every range, 30 rounds."
	w.damage = 13.0
	w.fire_interval = 0.1
	w.automatic = true
	w.magazine = 30
	w.reload_time = 1.9
	w.spread_degrees = 0.9
	w.falloff_start = 35.0
	w.falloff_end = 70.0
	w.falloff_min = 0.7
	w.muzzle_bone = "muzzle_rifle"
	w.kick = 0.55
	w.knockback = 0.9
	return w


## Bolt-action: a headshot kills, two body shots do. Slow to work the bolt.
static func sniper() -> WeaponData:
	var w := WeaponData.new()
	w.id = "sniper"
	w.display_name = "Sniper Rifle"
	w.short_name = "Sniper"
	w.blurb = "Bolt-action. A headshot kills, two body shots do. Pinpoint, slow."
	w.damage = 75.0
	w.structure_damage = 1.5
	w.fire_interval = 1.25
	w.magazine = 5
	w.reload_time = 2.4
	w.max_range = 300.0
	w.spread_degrees = 0.0
	w.headshot_multiplier = 2.0
	w.muzzle_bone = "muzzle_sniper"
	w.crosshair = "dot"
	w.kick = 2.6
	w.knockback = 9.0
	w.knockback_up = 2.0
	return w


## A melee weapon: no ammo, no spread, full damage within reach.
static func _melee(id: String, display: String) -> WeaponData:
	var w := WeaponData.new()
	w.id = id
	w.display_name = display
	w.short_name = display
	w.kind = Kind.MELEE
	w.automatic = true       # hold the button to keep swinging
	w.magazine = 0
	w.reload_time = 0.0
	w.spread_degrees = 0.0
	w.headshot_multiplier = 1.0
	w.muzzle_bone = "pistol"   # the fist: the blade rides on the grip bone
	w.crosshair = "melee"
	return w


## The longsword: both hands, a long flat cut from the side. The all-rounder.
static func sword() -> WeaponData:
	var w := _melee("sword", "Longsword")
	w.short_name = "Sword"
	w.blurb = "Two-handed. Hold to wind up, let go to cut: a full swing hits hard and throws them at the nearest wall."
	w.two_handed = true
	w.damage = 16.0
	w.charge_damage = 50.0
	w.structure_damage = 1.5
	w.fire_interval = 0.6
	w.windup = 0.1
	w.charge_time = 0.64
	w.max_range = 3.3
	w.arc_degrees = 60.0
	w.lunge = 5.0
	w.knockback = 4.0
	w.knockback_up = 1.5
	w.charge_knockback = 30.0
	w.charge_knockback_up = 6.0
	w.kick = 1.2
	w.move_bonus = 1.04
	return w


## Slow and brutal: the longest wind-up, and it sends people flying into walls.
static func hammer() -> WeaponData:
	var w := _melee("hammer", "Hammer")
	w.blurb = "Two-handed, the slowest wind-up and the biggest shove. Smash people into walls, or smash through them."
	w.two_handed = true
	w.damage = 15.0
	w.charge_damage = 45.0
	w.structure_damage = 4.0   # a full swing knocks a hole in a wall
	w.fire_interval = 0.9
	w.windup = 0.14
	w.charge_time = 0.96
	w.max_range = 3.1
	w.arc_degrees = 65.0
	w.lunge = 3.0
	w.knockback = 6.0
	w.knockback_up = 2.0
	w.charge_knockback = 37.0
	w.charge_knockback_up = 7.5
	w.kick = 2.0
	w.move_bonus = 1.0
	return w


## Quick slashes, and a wound-up stab in the back all but kills.
static func dagger() -> WeaponData:
	var w := _melee("dagger", "Dagger")
	w.blurb = "One hand, quick to wind up, fastest on your feet. Triple damage in the back."
	w.damage = 10.0
	w.charge_damage = 30.0
	w.fire_interval = 0.3
	w.windup = 0.06
	w.charge_time = 0.36
	w.max_range = 2.4
	w.arc_degrees = 40.0
	w.lunge = 4.0
	w.knockback = 2.0
	w.knockback_up = 1.0
	w.charge_knockback = 12.0
	w.charge_knockback_up = 3.0
	w.backstab_multiplier = 3.0
	w.kick = 0.6
	w.move_bonus = 1.15
	return w


# ---------------------------------------------------------------------------
# The fifteen newer weapons

static func _gun(id: String, display: String, short: String, muzzle: String = "") -> WeaponData:
	var w := WeaponData.new()
	w.id = id
	w.display_name = display
	w.short_name = short
	w.muzzle_bone = muzzle if muzzle != "" else "muzzle_" + id
	return w


## Six heavy rounds: two body shots and a headshot kill. Loads all six at once.
static func revolver() -> WeaponData:
	var w := _gun("revolver", "Revolver", "Revolver")
	w.blurb = "Six heavy rounds. Two to the body and one to the head kill. Slow to reload."
	w.damage = 45.0
	w.fire_interval = 0.42
	w.magazine = 6
	w.reload_time = 2.0
	w.spread_degrees = 0.15
	w.falloff_start = 30.0
	w.falloff_end = 60.0
	w.falloff_min = 0.7
	w.headshot_multiplier = 1.6
	w.kick = 2.2
	w.knockback = 4.0
	w.knockback_up = 0.5
	return w


## The Golden Gun (see GoldenGun): the revolver, in gold, with one round that kills
## whoever it hits. A kill loads the next round at once (GoldenGun); a miss means a
## slow reload.
static func golden_gun() -> WeaponData:
	var w := revolver()
	w.id = "golden_gun"
	w.display_name = "Golden Gun"
	w.short_name = "Golden Gun"
	w.blurb = "One round. Whoever it hits dies. A kill loads the next one; a miss, a slow reload."
	w.looks_like = "revolver"
	w.golden = true
	w.damage = 1000.0
	w.magazine = 1
	w.reload_time = 3.0
	w.fire_interval = 0.5
	w.falloff_start = 1000.0
	w.falloff_end = 1000.0
	w.falloff_min = 1.0
	w.headshot_multiplier = 1.0
	w.tracer_color = Color(1.0, 0.8, 0.25)
	return w


## A sidearm that sprays: sixteen rounds a second, all over the place past 12 m.
static func machine_pistol() -> WeaponData:
	var w := _gun("machine_pistol", "Machine Pistol", "Mach. Pistol")
	w.blurb = "Full-auto sidearm, 16 rounds a second. Wild past 12 m, quick on your feet."
	w.damage = 9.0
	w.fire_interval = 0.062
	w.automatic = true
	w.magazine = 24
	w.reload_time = 1.4
	w.spread_degrees = 1.7
	w.falloff_start = 12.0
	w.falloff_end = 30.0
	w.falloff_min = 0.5
	w.kick = 0.35
	w.knockback = 0.6
	w.move_bonus = 1.05
	return w


## A pistol in each hand: one trigger, and the shots alternate right, left, right...
## Twice the pistol's rate of fire, a little less damage and a lot less accuracy.
static func akimbo() -> WeaponData:
	var w := _gun("akimbo", "Akimbo Pistols", "Akimbo")
	w.blurb = "A pistol in each hand. Click as fast as you like: the shots alternate left and right. 24 rounds, wild at range."
	w.damage = 20.0
	w.fire_interval = 0.11
	w.magazine = 24
	w.reload_time = 2.0
	w.spread_degrees = 0.9
	w.falloff_start = 18.0
	w.falloff_end = 40.0
	w.falloff_min = 0.6
	w.headshot_multiplier = 1.5
	w.muzzle_bone_left = "muzzle_akimbo_l"
	w.kick = 1.1
	w.knockback = 1.6
	w.move_bonus = 1.03
	return w


## Two barrels, two shots close together, then break it open for two more.
static func break_action() -> WeaponData:
	var w := _gun("break_action", "Break-Action Shotgun", "Double Barrel")
	w.blurb = "Two barrels, two quick blasts, the widest spread there is. Breaks open to reload both."
	w.damage = 11.0
	w.pellets = 12
	w.fire_interval = 0.28
	w.magazine = 2
	w.reload_time = 1.7
	w.max_range = 50.0
	w.spread_degrees = 6.0
	w.falloff_start = 6.0
	w.falloff_end = 16.0
	w.falloff_min = 0.2
	w.headshot_multiplier = 1.25
	w.crosshair = "spread"
	w.kick = 3.0
	w.knockback = 1.8
	w.knockback_up = 0.35
	return w


## Small, fast and light: deadly up close, weak far away.
static func smg() -> WeaponData:
	var w := _gun("smg", "Submachine Gun", "SMG")
	w.blurb = "Full-auto, 14 rounds a second. Deadly up close, fades past 15 m. Light to carry."
	w.damage = 10.0
	w.fire_interval = 0.07
	w.automatic = true
	w.magazine = 32
	w.reload_time = 1.6
	w.spread_degrees = 1.3
	w.falloff_start = 15.0
	w.falloff_end = 35.0
	w.falloff_min = 0.55
	w.kick = 0.4
	w.knockback = 0.7
	w.move_bonus = 1.06
	return w


## Three rounds per pull, tight together: two bursts to the body kill.
static func burst_rifle() -> WeaponData:
	var w := _gun("burst_rifle", "Burst Rifle", "Burst")
	w.blurb = "Three-round bursts, tight and accurate. Two full bursts kill at any range."
	w.damage = 17.0
	w.burst = 3
	w.burst_gap = 0.065
	w.fire_interval = 0.4
	w.magazine = 30
	w.reload_time = 2.0
	w.spread_degrees = 0.4
	w.falloff_start = 40.0
	w.falloff_end = 80.0
	w.falloff_min = 0.75
	w.kick = 0.6
	w.knockback = 1.0
	return w


## A hundred-round belt: hold the trigger and keep holding it. Heavy to carry.
static func lmg() -> WeaponData:
	var w := _gun("lmg", "Light Machine Gun", "LMG")
	w.blurb = "A 100-round belt at 12 a second. Never stops, but slows you down and takes ages to reload."
	w.damage = 13.0
	w.fire_interval = 0.085
	w.automatic = true
	w.magazine = 100
	w.reload_time = 3.6
	w.spread_degrees = 1.4
	w.falloff_start = 35.0
	w.falloff_end = 70.0
	w.falloff_min = 0.7
	w.structure_damage = 1.3
	w.kick = 0.7
	w.knockback = 1.2
	w.move_bonus = 0.9
	return w


## Work the lever between shots; loads a round at a time.
static func lever_action() -> WeaponData:
	var w := _gun("lever_action", "Lever-Action Rifle", "Lever")
	w.blurb = "Hard-hitting and quick to cycle: a headshot and a body shot kill. Loads a round at a time."
	w.damage = 55.0
	w.fire_interval = 0.72
	w.magazine = 7
	w.reload_time = 0.45
	w.reload_per_round = true
	w.spread_degrees = 0.1
	w.falloff_start = 50.0
	w.falloff_end = 100.0
	w.falloff_min = 0.8
	w.headshot_multiplier = 1.8
	w.kick = 2.2
	w.knockback = 5.0
	w.knockback_up = 1.0
	return w


## The sniper's lighter cousin: iron sights, quicker bolt, a round at a time.
static func bolt_action() -> WeaponData:
	var w := _gun("bolt_action", "Bolt-Action Rifle", "Bolt Action")
	w.blurb = "Iron sights and a quick bolt. A headshot kills, so do two to the body. Loads a round at a time."
	w.damage = 70.0
	w.fire_interval = 1.0
	w.magazine = 5
	w.reload_time = 0.5
	w.reload_per_round = true
	w.max_range = 250.0
	w.spread_degrees = 0.0
	w.headshot_multiplier = 1.6
	w.structure_damage = 1.4
	w.crosshair = "dot"
	w.kick = 2.4
	w.knockback = 7.0
	w.knockback_up = 1.5
	return w


## A slug that goes through everything in a line, walls included, and kills whoever it
## touches (200: as much as anyone can have, overhealed). One shot, then a reload.
static func railgun() -> WeaponData:
	var w := _gun("railgun", "Railgun", "Railgun")
	w.blurb = "A magnetic slug that kills whoever it touches and goes through everything: every player, wall and floor in its path. Reloads after every shot."
	w.damage = 200.0
	w.pierce = true
	w.fire_interval = 1.0   # under reload_time: the reload sets the pace
	w.magazine = 1
	w.reload_time = 1.5
	w.max_range = 300.0
	w.spread_degrees = 0.0
	w.headshot_multiplier = 1.0   # a body shot already kills (a headshot still counts as one)
	w.structure_damage = 1.0   # 200 to every piece on the line: breaks most walls, cracks the toughest
	w.crosshair = "dot"
	w.kick = 3.0
	w.knockback = 12.0
	w.knockback_up = 2.5
	return w


## A rocket that blows up where it hits: splash damage, huge knockback, rocket jumps.
static func rocket_launcher() -> WeaponData:
	var w := _gun("rocket_launcher", "Rocket Launcher", "Rockets")
	w.kind = Kind.PROJECTILE
	w.blurb = "Rockets: a direct hit kills, the blast knocks everyone flying. Fire at your feet to rocket jump."
	w.damage = 105.0
	w.fire_interval = 0.9
	w.magazine = 1
	w.reload_time = 1.5
	w.max_range = 400.0
	w.spread_degrees = 0.0
	w.headshot_multiplier = 1.0
	w.structure_damage = 2.5
	w.projectile_speed = 34.0
	w.splash_radius = 4.5
	w.splash_inner = 1.0
	w.self_damage = 0.35
	w.crosshair = "ring"
	w.kick = 2.8
	w.knockback = 17.0
	w.knockback_up = 7.0
	w.move_bonus = 0.95
	return w


## Grenades in an arc that burst on contact.
static func grenade_launcher() -> WeaponData:
	var w := _gun("grenade_launcher", "Grenade Launcher", "Grenades")
	w.kind = Kind.PROJECTILE
	w.blurb = "Lobs grenades in an arc that burst on contact. Six in the drum, loaded one at a time."
	w.damage = 85.0
	w.fire_interval = 0.6
	w.magazine = 6
	w.reload_time = 0.55
	w.reload_per_round = true
	w.max_range = 300.0
	w.spread_degrees = 0.0
	w.headshot_multiplier = 1.0
	w.structure_damage = 2.0
	w.projectile_speed = 26.0
	w.projectile_gravity = 16.0
	w.splash_radius = 3.6
	w.splash_inner = 0.8
	w.self_damage = 0.35
	w.crosshair = "ring"
	w.kick = 1.8
	w.knockback = 12.0
	w.knockback_up = 5.0
	return w


## Fists with brass on: the quickest wind-up there is, a hook from the side.
static func brass_knuckles() -> WeaponData:
	var w := _melee("brass_knuckles", "Brass Knuckles")
	w.short_name = "Knuckles"
	w.blurb = "Hooks from the side with the quickest wind-up. Fastest on your feet of anything."
	w.damage = 12.0
	w.charge_damage = 32.0
	w.fire_interval = 0.3
	w.windup = 0.05
	w.charge_time = 0.32
	w.max_range = 2.2
	w.arc_degrees = 45.0
	w.lunge = 4.5
	w.knockback = 3.0
	w.knockback_up = 1.0
	w.charge_knockback = 17.0
	w.charge_knockback_up = 3.5
	w.kick = 0.7
	w.move_bonus = 1.18
	return w


## The longest reach: a two-handed thrust, drawn back at the hip, that carries you with it.
static func spear() -> WeaponData:
	var w := _melee("spear", "Spear")
	w.blurb = "Two-handed, the longest reach. Draw it back and thrust: it lunges you a long way. Narrow: aim it."
	w.two_handed = true
	w.damage = 15.0
	w.charge_damage = 45.0
	w.fire_interval = 0.7
	w.windup = 0.1
	w.charge_time = 0.64
	w.max_range = 4.2
	w.arc_degrees = 22.0
	w.lunge = 8.0
	w.knockback = 5.0
	w.knockback_up = 1.0
	w.charge_knockback = 27.0
	w.charge_knockback_up = 4.0
	w.kick = 1.2
	w.move_bonus = 1.04
	return w


## The most damage, and it chops through walls.
static func axe() -> WeaponData:
	var w := _melee("axe", "Axe")
	w.blurb = "Two-handed. The most damage of any blade, and it bites through walls."
	w.two_handed = true
	w.damage = 18.0
	w.charge_damage = 58.0
	w.structure_damage = 3.5
	w.fire_interval = 0.8
	w.windup = 0.12
	w.charge_time = 0.8
	w.max_range = 3.0
	w.arc_degrees = 55.0
	w.lunge = 3.5
	w.knockback = 5.0
	w.knockback_up = 2.0
	w.charge_knockback = 25.0
	w.charge_knockback_up = 5.5
	w.kick = 1.6
	return w


## A wide swing that sends people further than anything else.
static func bat() -> WeaponData:
	var w := _melee("bat", "Bat")
	w.blurb = "Two-handed, a wide flat swing. Light damage, but a full wind-up is a home run into the wall."
	w.two_handed = true
	w.damage = 10.0
	w.charge_damage = 30.0
	w.fire_interval = 0.75
	w.windup = 0.12
	w.charge_time = 0.72
	w.max_range = 3.0
	w.arc_degrees = 75.0
	w.lunge = 3.0
	w.knockback = 8.0
	w.knockback_up = 3.0
	w.charge_knockback = 41.0
	w.charge_knockback_up = 10.0
	w.kick = 1.8
	return w


## How much slower than full speed a spun-down minigun fires.
const SPIN_START := 3.0


## Seconds between shots with the barrels spun up `spin` (0..1) of the way.
func interval_at(spin: float) -> float:
	if spin_up <= 0.0:
		return fire_interval
	return fire_interval * lerpf(SPIN_START, 1.0, clampf(spin, 0.0, 1.0))


## A projectile's look: rocket (flies straight) or grenade (drops) unless it says.
func look() -> String:
	if projectile_look != "":
		return projectile_look
	return "rocket" if projectile_gravity <= 0.0 else "grenade"


func is_melee() -> bool:
	return kind == Kind.MELEE


## Melee: how wound up a swing is after holding the button for `held` seconds, 0..1.
## The first `windup` seconds are the draw-back every swing has, so a tap is 0.
func charge_of(held: float) -> float:
	return clampf((held - windup) / maxf(charge_time - windup, 0.01), 0.0, 1.0)


## Melee: damage of a blow wound up to `charge` (0 = a tap, 1 = a full wind-up).
func melee_damage(charge: float) -> float:
	return lerpf(damage, maxf(charge_damage, damage), clampf(charge, 0.0, 1.0))


## Melee: the shove of a blow wound up to `charge`: [along the blow, upward].
## It grows faster than the damage toward the end of the wind-up: the last of the
## charge is what sends people into walls.
func melee_knockback(charge: float) -> Array:
	var u := clampf(charge, 0.0, 1.0)
	u = u * (0.6 + 0.4 * u)
	return [lerpf(knockback, maxf(charge_knockback, knockback), u), lerpf(knockback_up, maxf(charge_knockback_up, knockback_up), u)]


## A gun in each hand, firing in turn.
func is_akimbo() -> bool:
	return muzzle_bone_left != ""


func is_projectile() -> bool:
	return kind == Kind.PROJECTILE


## The shortest time between two rounds (inside a burst, for a burst rifle).
func shot_gap() -> float:
	return minf(burst_gap, fire_interval) if burst > 1 else fire_interval


## Which group of the pickers the weapon is in (0 = sidearms).
static func group_of(weapon_id: String) -> int:
	for i in GROUPS.size():
		if weapon_id in GROUPS[i][1]:
			return i
	return 0


## Held in both hands round the grip, like the pistol.
static func sidearm(weapon_id: String) -> bool:
	return weapon_id in SIDEARMS


static var _cache := {}


static func _make(weapon_id: String) -> WeaponData:
	match weapon_id:
		"shotgun": return shotgun()
		"rifle": return rifle()
		"sniper": return sniper()
		"sword": return sword()
		"hammer": return hammer()
		"dagger": return dagger()
		"revolver": return revolver()
		"golden_gun": return golden_gun()
		"machine_pistol": return machine_pistol()
		"akimbo": return akimbo()
		"break_action": return break_action()
		"smg": return smg()
		"burst_rifle": return burst_rifle()
		"lmg": return lmg()
		"lever_action": return lever_action()
		"bolt_action": return bolt_action()
		"railgun": return railgun()
		"rocket_launcher": return rocket_launcher()
		"grenade_launcher": return grenade_launcher()
		"brass_knuckles": return brass_knuckles()
		"spear": return spear()
		"axe": return axe()
		"bat": return bat()
		"derringer": return derringer()
		"air_cannon": return air_cannon()
		"minigun": return minigun()
		"battle_rifle": return battle_rifle()
		"laser_rifle": return laser_rifle()
		"nail_gun": return nail_gun()
		"crossbow": return crossbow()
		"anti_materiel": return anti_materiel()
		"plasma_cannon": return plasma_cannon()
		"scythe": return scythe()
		"mace": return mace()
		"machete": return machete()
		"wrench": return wrench()
		"energy_sword": return energy_sword()
		"karate": return karate()
	return pistol()


static func by_id(weapon_id: String) -> WeaponData:
	weapon_id = valid(weapon_id)
	if not _cache.has(weapon_id):
		_cache[weapon_id] = _make(weapon_id)
	return _cache[weapon_id]


static func default_id() -> String:
	return IDS[0]


static func has(weapon_id: String) -> bool:
	return weapon_id in IDS or weapon_id in HIDDEN


## The weapon whose model, animations and sounds `weapon_id` uses (see `looks_like`).
static func look_of(weapon_id: String) -> String:
	if not has(weapon_id):
		return weapon_id   # ("none", empty hands)
	var l := by_id(weapon_id).looks_like
	return l if l != "" else weapon_id


## `weapon_id` if it is a real weapon, otherwise the default one.
static func valid(weapon_id: String) -> String:
	return weapon_id if has(weapon_id) else default_id()


static func melee(weapon_id: String) -> bool:
	return weapon_id in MELEE


static func name_of(weapon_id: String) -> String:
	return by_id(weapon_id).display_name


## Damage of one pellet that hit at `distance` metres, before headshots.
func damage_at(distance: float) -> float:
	if distance <= falloff_start or falloff_end <= falloff_start:
		return damage if distance <= falloff_end else damage * falloff_min
	var u := clampf((distance - falloff_start) / (falloff_end - falloff_start), 0.0, 1.0)
	return damage * lerpf(1.0, falloff_min, u)


# ---------------------------------------------------------------------------
# The third batch: fourteen more (BATCH_3). Each plays its own way: a new rhythm
# (the minigun's spin-up, the laser rifle's self-filling battery), a new kind of hit
# (the air cannon's shove), a new projectile (nails, bolts, plasma) or a new blade.

## Two barrels in the palm of your hand: both rounds to the body kill, up close.
static func derringer() -> WeaponData:
	var w := _gun("derringer", "Derringer", "Derringer")
	w.blurb = "Two shots in your palm: both to the body kill up close. Light and quick on your feet, useless past 20 m."
	w.damage = 52.0
	w.fire_interval = 0.22
	w.magazine = 2
	w.reload_time = 1.4
	w.spread_degrees = 0.5
	w.falloff_start = 8.0
	w.falloff_end = 22.0
	w.falloff_min = 0.4
	w.headshot_multiplier = 1.5
	w.kick = 2.4
	w.knockback = 3.5
	w.knockback_up = 0.5
	w.move_bonus = 1.1
	return w


## Compressed air: barely scratches, but throws people across the room (and into walls).
static func air_cannon() -> WeaponData:
	var w := _gun("air_cannon", "Air Cannon", "Air Cannon")
	w.blurb = "A blast of compressed air: barely scratches, but throws anyone within 15 m across the room. Into a wall, it kills."
	w.damage = 2.5
	w.pellets = 8
	w.fire_interval = 1.0
	w.magazine = 4
	w.reload_time = 1.8
	w.max_range = 18.0
	w.spread_degrees = 5.0
	w.falloff_start = 6.0
	w.falloff_end = 16.0
	w.falloff_min = 0.2
	w.headshot_multiplier = 1.0
	w.structure_damage = 0.3
	w.crosshair = "spread"
	w.kick = 2.0
	w.knockback = 4.5      # per pellet: all eight is a 36 m/s shove
	w.knockback_up = 1.0
	w.tracer_color = Color(0.85, 0.95, 1.0)
	return w


## Six barrels: slow to start, then twenty rounds a second for as long as you hold on.
static func minigun() -> WeaponData:
	var w := _gun("minigun", "Minigun", "Minigun")
	w.blurb = "Six spinning barrels: hold the trigger and they wind up to 20 rounds a second. 200 rounds, wild, and heavy to carry."
	w.damage = 11.0
	w.fire_interval = 0.05
	w.spin_up = 0.9
	w.automatic = true
	w.magazine = 200
	w.reload_time = 4.5
	w.spread_degrees = 2.2
	w.falloff_start = 25.0
	w.falloff_end = 55.0
	w.falloff_min = 0.6
	w.structure_damage = 1.2
	w.kick = 0.5
	w.knockback = 0.6
	w.move_bonus = 0.82
	return w


## Semi-automatic and hard-hitting: three body shots at any range.
static func battle_rifle() -> WeaponData:
	var w := _gun("battle_rifle", "Battle Rifle", "Battle Rifle")
	w.blurb = "Semi-auto, hard-hitting and accurate: three body shots kill at any range. 20 rounds."
	w.damage = 34.0
	w.fire_interval = 0.2
	w.magazine = 20
	w.reload_time = 2.1
	w.spread_degrees = 0.2
	w.falloff_start = 50.0
	w.falloff_end = 100.0
	w.falloff_min = 0.8
	w.headshot_multiplier = 1.6
	w.kick = 1.3
	w.knockback = 2.0
	w.knockback_up = 0.3
	return w


## A beam: no spread, no falloff, and it overheats instead of reloading.
static func laser_rifle() -> WeaponData:
	var w := _gun("laser_rifle", "Laser Rifle", "Laser")
	w.blurb = "A pinpoint beam: no spread and no falloff. Never reloads, but hold it too long and it overheats."
	w.damage = 6.5
	w.fire_interval = 0.05
	w.automatic = true
	w.magazine = 40
	w.reload_time = 2.5
	w.recharge = 14.0
	w.recharge_delay = 0.35
	w.spread_degrees = 0.0
	w.headshot_multiplier = 1.25
	w.kick = 0.15
	w.knockback = 0.25
	w.tracer_color = Color(1.0, 0.2, 0.3)
	return w


## A stream of heavy nails: fast, but they drop a little.
static func nail_gun() -> WeaponData:
	var w := _gun("nail_gun", "Nail Gun", "Nail Gun")
	w.kind = Kind.PROJECTILE
	w.projectile_look = "nail"
	w.explosive = false
	w.blurb = "Pins people with a stream of heavy nails. Each one flies fast and drops a little: lead your target. 40 nails."
	w.damage = 16.0
	w.fire_interval = 0.09
	w.automatic = true
	w.magazine = 40
	w.reload_time = 2.0
	w.max_range = 300.0
	w.spread_degrees = 0.0
	w.headshot_multiplier = 1.5
	w.structure_damage = 0.6
	w.projectile_speed = 70.0
	w.projectile_gravity = 4.0
	w.splash_radius = 0.3
	w.splash_inner = 0.3
	w.self_damage = 0.0
	w.fuse = 2.5
	w.kick = 0.4
	w.knockback = 1.0
	return w


## A heavy bolt that drops with distance: a headshot kills.
static func crossbow() -> WeaponData:
	var w := _gun("crossbow", "Crossbow", "Crossbow")
	w.kind = Kind.PROJECTILE
	w.projectile_look = "bolt"
	w.explosive = false
	w.blurb = "A heavy bolt that drops over distance. A headshot kills, a body shot nearly does. Reloads after every shot."
	w.damage = 80.0
	w.fire_interval = 0.4
	w.magazine = 1
	w.reload_time = 1.3
	w.max_range = 400.0
	w.spread_degrees = 0.0
	w.headshot_multiplier = 1.5
	w.structure_damage = 0.8
	w.projectile_speed = 75.0
	w.projectile_gravity = 9.0
	w.splash_radius = 0.3
	w.splash_inner = 0.3
	w.self_damage = 0.0
	w.fuse = 4.0
	w.crosshair = "dot"
	w.kick = 1.6
	w.knockback = 6.0
	w.knockback_up = 1.0
	return w


## The biggest rifle: 95 to the body, and one round breaks a wall.
static func anti_materiel() -> WeaponData:
	var w := _gun("anti_materiel", "Anti-Materiel Rifle", "Anti-Materiel")
	w.blurb = "A huge .50 rifle: 95 to the body, a headshot kills, one round breaks a wall. Three rounds, slow, heavy to carry."
	w.damage = 95.0
	w.fire_interval = 2.0
	w.magazine = 3
	w.reload_time = 3.2
	w.max_range = 400.0
	w.spread_degrees = 0.0
	w.headshot_multiplier = 2.0
	w.structure_damage = 5.0
	w.crosshair = "dot"
	w.kick = 4.0
	w.knockback = 14.0
	w.knockback_up = 3.0
	w.move_bonus = 0.85
	return w


## Full-auto balls of plasma: slow enough to dodge, and each one bursts.
static func plasma_cannon() -> WeaponData:
	var w := _gun("plasma_cannon", "Plasma Cannon", "Plasma Cannon")
	w.kind = Kind.PROJECTILE
	w.projectile_look = "orb"
	w.blurb = "Full-auto balls of plasma: slow enough to dodge, but each one bursts. Eight to a cell."
	w.damage = 50.0
	w.fire_interval = 0.4
	w.automatic = true
	w.magazine = 8
	w.reload_time = 2.4
	w.max_range = 300.0
	w.spread_degrees = 0.0
	w.headshot_multiplier = 1.0
	w.structure_damage = 1.5
	w.projectile_speed = 22.0
	w.projectile_gravity = 0.0
	w.splash_radius = 3.0
	w.splash_inner = 0.8
	w.self_damage = 0.3
	w.fuse = 4.0
	w.crosshair = "ring"
	w.kick = 1.5
	w.knockback = 9.0
	w.knockback_up = 3.0
	w.tracer_color = Color(0.45, 0.7, 1.0)
	return w


## The widest swing there is, on a long haft.
static func scythe() -> WeaponData:
	var w := _melee("scythe", "Scythe")
	w.blurb = "Two-handed, the widest swing of all and a long reach: one full sweep catches everyone around you."
	w.two_handed = true
	w.damage = 12.0
	w.charge_damage = 42.0
	w.fire_interval = 0.85
	w.windup = 0.12
	w.charge_time = 0.85
	w.max_range = 3.9
	w.arc_degrees = 110.0
	w.lunge = 3.0
	w.knockback = 4.0
	w.knockback_up = 1.5
	w.charge_knockback = 28.0
	w.charge_knockback_up = 5.0
	w.kick = 1.5
	return w


## One hand, a flanged head: a full swing launches people up into the air.
static func mace() -> WeaponData:
	var w := _melee("mace", "Mace")
	w.blurb = "One-handed, a flanged steel head: a full swing launches them up and away, into the ceiling or off the map."
	w.damage = 15.0
	w.charge_damage = 44.0
	w.structure_damage = 2.5
	w.fire_interval = 0.7
	w.windup = 0.1
	w.charge_time = 0.72
	w.max_range = 2.7
	w.arc_degrees = 55.0
	w.lunge = 3.5
	w.knockback = 5.0
	w.knockback_up = 2.5
	w.charge_knockback = 26.0
	w.charge_knockback_up = 14.0
	w.kick = 1.6
	w.move_bonus = 1.02
	return w


## A broad chopping blade in one hand: quick cuts, and a little extra from behind.
static func machete() -> WeaponData:
	var w := _melee("machete", "Machete")
	w.blurb = "One-handed, quick wide chops that come fast one after another. Half as much again in the back."
	w.damage = 13.0
	w.charge_damage = 38.0
	w.fire_interval = 0.4
	w.windup = 0.06
	w.charge_time = 0.45
	w.max_range = 2.6
	w.arc_degrees = 60.0
	w.lunge = 4.5
	w.knockback = 2.5
	w.knockback_up = 1.0
	w.charge_knockback = 14.0
	w.charge_knockback_up = 3.0
	w.backstab_multiplier = 1.5
	w.kick = 0.8
	w.move_bonus = 1.1
	return w


## A big robot wrench: solid, quick, and it knocks holes in walls.
static func wrench() -> WeaponData:
	var w := _melee("wrench", "Wrench")
	w.blurb = "A heavy robot wrench, one-handed: quick, solid, and a full swing knocks a hole in a wall."
	w.damage = 14.0
	w.charge_damage = 40.0
	w.structure_damage = 3.5
	w.fire_interval = 0.55
	w.windup = 0.08
	w.charge_time = 0.6
	w.max_range = 2.5
	w.arc_degrees = 50.0
	w.lunge = 3.0
	w.knockback = 4.0
	w.knockback_up = 1.5
	w.charge_knockback = 22.0
	w.charge_knockback_up = 5.0
	w.kick = 1.3
	w.move_bonus = 1.06
	return w


## A blade of light: the most damage of any swing, but it barely shoves.
static func energy_sword() -> WeaponData:
	var w := _melee("energy_sword", "Energy Sword")
	w.short_name = "Energy Sword"
	w.blurb = "A blade of light, one-handed: the most damage of any swing, but it barely shoves. Two full swings kill."
	w.damage = 18.0
	w.charge_damage = 55.0
	w.structure_damage = 2.0
	w.fire_interval = 0.5
	w.windup = 0.08
	w.charge_time = 0.55
	w.max_range = 3.0
	w.arc_degrees = 55.0
	w.lunge = 6.0
	w.knockback = 1.5
	w.knockback_up = 0.5
	w.charge_knockback = 6.0
	w.charge_knockback_up = 1.0
	w.kick = 0.6
	w.move_bonus = 1.08
	return w


## Karate: no weapon at all, just fists and feet. Every swing is the next blow of a
## combo of six (a jab, a cross, a roundhouse kick, a hook, a spinning back fist and a
## spinning hook kick; see MeleeSwing), a full wind-up is a hopping tornado kick, and in
## mid-air it is a helicopter kick. The spinning blows take longer, so the combo has a rhythm.
static func karate() -> WeaponData:
	var w := _melee("karate", "Karate")
	w.blurb = "No weapon, all style: every swing is the next move of a six-hit combo of punches, kicks and spinning kicks. Wind up for a tornado kick."
	w.damage = 11.0
	w.charge_damage = 36.0
	w.fire_interval = 0.28
	w.windup = 0.05
	w.charge_time = 0.42
	w.max_range = 2.5
	w.arc_degrees = 55.0
	w.lunge = 4.5
	w.knockback = 3.0
	w.knockback_up = 1.0
	w.charge_knockback = 26.0
	w.charge_knockback_up = 6.0
	w.kick = 0.7
	w.move_bonus = 1.12
	return w
