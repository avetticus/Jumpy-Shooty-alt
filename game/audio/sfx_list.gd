class_name SfxList
## Tables for the sound effects, kept apart from the code that plays them so they are
## easy to tune (and the tests can read them without the game running).
## The sounds themselves: game/audio/sfx/, made by tools/audio/make_sfx.py.

## How loud each sound plays, in dB (every file is normalised to the same peak).
const VOLUME := {
	"fire_pistol": -5.0, "fire_rifle": -6.5, "fire_shotgun": -3.5, "fire_sniper": -2.5,
	"far_pistol": -9.0, "far_rifle": -10.0, "far_shotgun": -7.0, "far_sniper": -5.0,
	"equip_pistol": -10.0, "equip_rifle": -10.0, "equip_shotgun": -10.0, "equip_sniper": -10.0,
	"fire_pistol_fp": -5.0, "fire_rifle_fp": -6.5, "fire_shotgun_fp": -3.5, "fire_sniper_fp": -2.5, "dry_click": -10.0,
	"mag_out": -12.0, "mag_in": -11.0, "mag_out_rifle": -12.0, "mag_in_rifle": -11.0,
	"slide_back": -12.0, "slide_fwd": -10.0, "charge_back": -12.0, "charge_fwd": -10.0,
	"pump_back": -9.0, "pump_fwd": -8.0, "shell_in": -11.0,
	"bolt_up": -12.0, "bolt_back": -11.0, "bolt_fwd": -10.0, "bolt_down": -11.0,
	"impact_wall": -11.0, "ricochet": -16.0, "impact_body": -8.0, "whiz": -9.0,
	"hitmarker": -9.0, "hitmarker_head": -7.0, "kill": -5.0, "kill_head": -4.0,
	"hurt": -6.0, "hurt_head": -5.0, "death": -6.0, "respawn": -11.0,
	"step": -15.0, "crawl": -17.0, "jump": -13.0, "land": -11.0, "land_hard": -8.0,
	"flip": -12.0, "dive": -11.0, "roll": -11.0, "slide": -11.0, "belly_slide": -10.0,
	"wall_run": -12.0, "wall_jump": -10.0, "vault": -12.0, "ledge_climb": -11.0,
	"crouch": -18.0, "stand": -18.0,
	"grapple_fire": -10.0, "grapple_attach": -10.0, "grapple_release": -12.0, "grapple_miss": -12.0, "grapple_taut": -8.0,
	"blink": -9.0,
	"ui_hover": -20.0, "ui_click": -12.0, "ui_confirm": -10.0, "ui_back": -12.0,
	"ui_toggle": -13.0, "ui_tick": -20.0, "ui_select": -12.0,
	"ui_materialize": -21.0,   # (quiet: stepping through the robots plays it again and again)
	"match_start": -6.0, "match_end": -6.0,
	"swing_sword": -8.0, "swing_hammer": -7.0, "swing_dagger": -10.0,
	"equip_sword": -10.0, "equip_hammer": -10.0, "equip_dagger": -10.0,
	"melee_hit": -5.0, "hammer_hit": -4.0, "heavy_hit": -3.0, "ground_slam": -1.0, "slam": -5.0,
	"kick": -9.0, "flying_kick": -6.0, "rocket_boost": -7.0, "glide": -10.0,
	"break_concrete": -4.0, "break_wood": -5.0, "break_glass": -6.0,
	# The newer weapons
	"fire_akimbo": -5.5, "far_akimbo": -9.5, "fire_akimbo_fp": -5.5, "equip_akimbo": -10.0,
	"fire_revolver": -3.5, "fire_machine_pistol": -6.5, "fire_break_action": -3.0, "fire_smg": -7.0,
	"fire_burst_rifle": -6.0, "fire_lmg": -6.0, "fire_lever_action": -3.5, "fire_bolt_action": -3.0,
	"fire_railgun": -3.0, "fire_rocket_launcher": -3.0, "fire_grenade_launcher": -4.0,
	"far_revolver": -7.0, "far_machine_pistol": -10.0, "far_break_action": -6.5, "far_smg": -10.5,
	"far_burst_rifle": -9.5, "far_lmg": -9.0, "far_lever_action": -6.5, "far_bolt_action": -5.5,
	"far_railgun": -6.0, "far_rocket_launcher": -6.0, "far_grenade_launcher": -8.0,
	"fire_revolver_fp": -3.5, "fire_machine_pistol_fp": -6.5, "fire_break_action_fp": -3.0, "fire_smg_fp": -7.0,
	"fire_burst_rifle_fp": -6.0, "fire_lmg_fp": -6.0, "fire_lever_action_fp": -3.5, "fire_bolt_action_fp": -3.0,
	"fire_railgun_fp": -3.0, "fire_rocket_launcher_fp": -3.0, "fire_grenade_launcher_fp": -4.0,
	"equip_revolver": -10.0, "equip_machine_pistol": -10.0, "equip_break_action": -10.0, "equip_smg": -10.0,
	"equip_burst_rifle": -10.0, "equip_lmg": -10.0, "equip_lever_action": -10.0, "equip_bolt_action": -10.0,
	"equip_railgun": -10.0, "equip_rocket_launcher": -10.0, "equip_grenade_launcher": -10.0,
	"equip_brass_knuckles": -10.0, "equip_spear": -10.0, "equip_axe": -10.0, "equip_bat": -10.0,
	"swing_brass_knuckles": -10.0, "swing_spear": -9.0, "swing_axe": -7.5, "swing_bat": -7.0,
	"bat_hit": -4.0, "punch_hit": -5.0, "explosion": -1.0, "explosion_far": -4.0,
	"cylinder_open": -12.0, "cylinder_close": -10.0, "empties_out": -14.0, "speedloader": -11.0,
	"break_open": -10.0, "break_close": -9.0, "shells_in": -11.0, "lever_down": -10.0, "lever_up": -9.0,
	"cover_open": -11.0, "cover_close": -9.0, "box_out": -11.0, "box_in": -10.0, "cell_out": -11.0,
	"cell_in": -10.0, "rocket_in": -9.0, "drum_turn": -11.0, "grenade_in": -11.0, "rail_vent": -11.0,
	"gun_spin": -14.0, "gun_toss": -17.0, "cell_clink": -15.0, "vent_hiss": -13.0, "charge_hum": -11.0, "barrel_spin": -12.0,
	# The third batch
	"fire_derringer": -4.0, "fire_derringer_fp": -4.0, "far_derringer": -7.5, "equip_derringer": -10.0,
	"fire_air_cannon": -4.0, "fire_air_cannon_fp": -4.0, "far_air_cannon": -7.5, "equip_air_cannon": -10.0,
	"fire_minigun": -7.5, "fire_minigun_fp": -7.5, "far_minigun": -11.0, "equip_minigun": -10.0,
	"fire_battle_rifle": -4.5, "fire_battle_rifle_fp": -4.5, "far_battle_rifle": -8.0, "equip_battle_rifle": -10.0,
	"fire_laser_rifle": -8.0, "fire_laser_rifle_fp": -8.0, "far_laser_rifle": -11.5, "equip_laser_rifle": -10.0,
	"fire_nail_gun": -7.0, "fire_nail_gun_fp": -7.0, "far_nail_gun": -10.5, "equip_nail_gun": -10.0,
	"fire_crossbow": -5.0, "fire_crossbow_fp": -5.0, "far_crossbow": -8.5, "equip_crossbow": -10.0,
	"fire_anti_materiel": -1.5, "fire_anti_materiel_fp": -1.5, "far_anti_materiel": -5.0, "equip_anti_materiel": -10.0,
	"fire_plasma_cannon": -5.0, "fire_plasma_cannon_fp": -5.0, "far_plasma_cannon": -8.5, "equip_plasma_cannon": -10.0,
	"swing_scythe": -8.5, "equip_scythe": -10.0,
	"swing_mace": -8.5, "equip_mace": -10.0,
	"swing_machete": -8.5, "equip_machete": -10.0,
	"swing_wrench": -8.5, "equip_wrench": -10.0,
	"swing_energy_sword": -8.5, "equip_energy_sword": -10.0,
	"swing_karate": -9.0, "equip_karate": -10.0,
	# Map events (both loop; MapTerminal and GravityEvent play and fade them). The chord
	# is heard all over the map and is kept well under the fighting.
	"terminal_hum": -9.0, "gravity_pad": -15.0,
	# Cirrus's clock, its bell and the move that follows (LayoutEvent plays them). The
	# tick is the quietest thing in the game: there all match, never in the way. The bell
	# is meant to be heard over a fight; the build-up and the move sit under it.
	"clock_tick": -27.0, "clock_tock": -27.0, "bell_toll": -4.0, "layout_rise": -11.0, "island_move": -13.0, "bridge_lock": -7.0,
	# The Construction Site's crane (MapLever plays the lever's clack in the cab; CraneEvent
	# plays the rest from the top of the mast, heard all over the site: the motor loops).
	"lever_pull": -8.0, "crane_start": -9.0, "crane_motor": -13.0, "crane_stop": -8.0,
	# The Haunted House (HauntEvent: the warning, the shift and the house settling; MapGhost: a moan).
	"haunt_warn": -10.0, "haunt_shift": -12.0, "haunt_settle": -11.0, "ghost_moan": -12.0,
	# Empyrean Tower: the quiet sound of each of its tiers (MapAmbientSound loops them in the
	# room: magic heard from next door, far under everything else).
	"magic_engine": -21.0, "magic_library": -23.0, "magic_labs": -22.0, "magic_menagerie": -24.0, "magic_summoning": -20.0,
	"magic_observatory": -24.0,
}

## Gun handling, in seconds from the start of the clip, matched to the animations
## in tools/robot/weapon_anims.py (each sound's own click lands on the key frame).
const RELOAD_STEPS := {
	"pistol": [[0.07, "mag_out"], [0.44, "gun_toss"], [0.585, "mag_in"], [0.78, "gun_spin"], [1.115, "slide_fwd"]],
	"rifle": [[0.12, "mag_out_rifle"], [0.62, "gun_toss"], [1.08, "mag_in_rifle"], [1.455, "charge_back"], [1.57, "charge_fwd"]],
	"sniper": [[0.12, "mag_out_rifle"], [0.84, "mag_in_rifle"], [1.24, "bolt_up"], [1.40, "bolt_back"],
		[1.70, "bolt_fwd"], [1.80, "bolt_down"]],
	"shotgun": [[0.25, "shell_in"]],   # one shell; repeats until the tube is full
	"revolver": [[0.13, "cylinder_open"], [0.38, "empties_out"], [0.92, "speedloader"], [1.165, "cylinder_close"], [1.3, "gun_spin"]],
	"akimbo": [[0.11, "mag_out"], [0.14, "mag_out"], [0.68, "mag_in"], [0.7, "mag_in"], [1, "gun_spin"], [1.515, "slide_fwd"]],
	"machine_pistol": [[0.07, "mag_out"], [0.62, "mag_in"], [0.78, "gun_spin"], [1.115, "slide_fwd"]],
	"break_action": [[0.12, "break_open"], [0.745, "shells_in"], [1.05, "break_close"]],
	"smg": [[0.09, "mag_out_rifle"], [0.68, "mag_in_rifle"], [0.95, "gun_spin"]],
	"burst_rifle": [[0.59, "mag_out_rifle"], [0.82, "mag_in_rifle"], [1.175, "charge_back"], [1.29, "charge_fwd"]],
	"lmg": [[0.30, "cover_open"], [0.88, "box_out"], [1.78, "box_in"], [2.54, "cover_close"]],
	"lever_action": [[0.25, "shell_in"]],
	"bolt_action": [[0.28, "shell_in"]],
	"railgun": [[0.16, "cell_out"], [0.23, "rail_vent"], [0.91, "cell_in"]],   # its 2.6 s clip played in its 1.5 s reload
	"rocket_launcher": [[0.42, "gun_toss"], [0.94, "rocket_in"]],
	"grenade_launcher": [[0.28, "grenade_in"], [0.40, "drum_turn"]],
	"derringer": [[0.11, "break_open"], [0.62, "gun_toss"], [0.77, "shells_in"], [1, "break_close"]],
	"minigun": [[0.46, "cover_open"], [0.98, "box_out"], [2.18, "box_in"], [2.72, "cover_close"], [2.9, "barrel_spin"]],
	"battle_rifle": [[0.29, "mag_out_rifle"], [1.09, "mag_in_rifle"], [1.535, "charge_back"], [1.65, "charge_fwd"]],
	"laser_rifle": [[0.04, "vent_hiss"], [0.56, "gun_spin"], [1.22, "gun_spin"], [1.83, "cell_in"]],
	"nail_gun": [[0.10, "mag_out_rifle"], [1.14, "mag_in_rifle"]],
	"crossbow": [[0.54, "grenade_in"], [0.74, "charge_back"]],
	"anti_materiel": [[0.30, "mag_out_rifle"], [1.28, "mag_in_rifle"], [1.80, "bolt_up"], [2.06, "bolt_back"],
		[2.50, "bolt_fwd"], [2.66, "bolt_down"]],
	"plasma_cannon": [[0.28, "cell_out"], [0.33, "vent_hiss"], [1.58, "cell_in"], [1.62, "charge_hum"]],
}
## After each shot: the shotgun's pump and the sniper's bolt.
## What ends a shell-at-a-time reload once the gun is full (the "reload_end" clips in
## tools/robot/long_reloads.py): the pump racked by the flourish.
const RELOAD_END_STEPS := {
	"shotgun": [[0.14, "gun_spin"], [0.245, "pump_back"], [0.455, "pump_fwd"]],
	"lever_action": [[0.14, "gun_spin"], [0.2, "lever_down"], [0.44, "lever_up"]],
	"bolt_action": [[0.19, "bolt_fwd"], [0.27, "bolt_down"]],
	"grenade_launcher": [[0.12, "drum_turn"], [0.42, "cylinder_close"]],
}
const FIRE_STEPS := {
	"shotgun": [[0.17, "pump_back"], [0.315, "pump_fwd"]],
	"sniper": [[0.40, "bolt_up"], [0.44, "bolt_back"], [0.60, "bolt_fwd"], [0.77, "bolt_down"]],
	"lever_action": [[0.10, "lever_down"], [0.30, "lever_up"]],
	"bolt_action": [[0.345, "bolt_up"], [0.38, "bolt_back"], [0.518, "bolt_fwd"], [0.665, "bolt_down"]],
	"railgun": [[0.05, "rail_vent"]],
	"anti_materiel": [[0.65, "bolt_up"], [0.72, "bolt_back"], [0.98, "bolt_fwd"], [1.26, "bolt_down"]],
}
