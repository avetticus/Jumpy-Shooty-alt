class_name HudConfig
extends RefCounted
## How the in-game HUD is tuned on top of its layout (Settings → HUD): its size and
## opacity, the crosshair, and which parts show. Settings owns one (Settings.hud) and
## keeps it in the [hud] section of settings.cfg, beside the layout for each view.
## The defaults are the HUD exactly as it was before any of this could be changed.

## Crosshair styles: the weapon's own (each gun's: a cross, the shotgun's brackets,
## a launcher's ring, the marksman rifles' ticks) or one shape for every weapon.
const CROSSHAIRS := {"weapon": "Weapon's own", "cross": "Cross", "t": "T (no top arm)", "point": "Dot", "circle": "Circle"}
const COLOR_NAMES := {"white": "White", "green": "Green", "yellow": "Yellow", "cyan": "Cyan", "pink": "Pink", "red": "Red"}
const COLORS := {
	"white": HudStyle.WHITE, "green": Color(0.35, 1.0, 0.45, 0.95), "yellow": Color(1.0, 0.92, 0.3, 0.95),
	"cyan": Color(0.4, 0.9, 1.0, 0.95), "pink": Color(1.0, 0.45, 0.85, 0.95), "red": Color(1.0, 0.3, 0.28, 0.95),
}
const FEED_CORNERS := {"right": "Top right", "left": "Top left"}
## Moves: every one; only those recharging or in use; none.
const MOVES := {"full": "Full", "compact": "Compact (only recharging or in use)", "off": "Off"}

## Each option: [default] for a switch, [default, choices] for a pick, [default, low,
## high] for a number (an int default makes it a whole number). A saved value of the
## wrong kind, or out of range, falls back to the default.
const SPEC := {
	"scale": [1.0, 0.75, 1.25],
	"opacity": [1.0, 0.3, 1.0],
	"crosshair": ["weapon", CROSSHAIRS],
	"crosshair_color": ["white", COLORS],
	"crosshair_size": [1.0, 0.5, 2.0],
	"crosshair_gap": [5.0, 0.0, 20.0],          ## pixels from the middle to the arms (before the gun's spread)
	"crosshair_thickness": [2.0, 1.0, 4.0],
	"crosshair_outline": [true],
	"crosshair_dot": [true],
	"hit_markers": [true],
	"damage_numbers": [true],
	"feed_corner": ["right", FEED_CORNERS],
	"feed_lines": [5, 3, 8],
	"moves": ["full", MOVES],
	"speed": [true],                            ## the speed and movement-state readout
	"killcam_points": [true],                   ## your kill's killcam score, by the crosshair and bottom left
}

var scale := 1.0
var opacity := 1.0
var crosshair := "weapon"
var crosshair_color := "white"
var crosshair_size := 1.0
var crosshair_gap := 5.0
var crosshair_thickness := 2.0
var crosshair_outline := true
var crosshair_dot := true
var hit_markers := true
var damage_numbers := true
var feed_corner := "right"
var feed_lines := 5
var moves := "full"
var speed := true
var killcam_points := true


## Everything back to the defaults.
func reset() -> void:
	for key in SPEC:
		set(key, SPEC[key][0])


## Reads the [hud] section; anything missing or bad keeps (or gets) its default.
func load_from(cfg: ConfigFile) -> void:
	for key in SPEC:
		set(key, valid(key, cfg.get_value("hud", key, SPEC[key][0])))


func save_to(cfg: ConfigFile) -> void:
	for key in SPEC:
		cfg.set_value("hud", key, get(key))


## `value` if it is right for option `key`, otherwise the option's default.
static func valid(key: String, value: Variant) -> Variant:
	var spec: Array = SPEC[key]
	var fallback: Variant = spec[0]
	if spec.size() == 1:   # a switch
		return value if value is bool else fallback
	if spec.size() == 2:   # a pick
		return str(value) if value is String and (spec[1] as Dictionary).has(value) else fallback
	if not (value is float or value is int) or is_nan(float(value)):
		return fallback
	if float(value) < spec[1] or float(value) > spec[2]:
		return fallback
	return int(round(float(value))) if fallback is int else float(value)


func is_default() -> bool:
	for key in SPEC:
		if get(key) != SPEC[key][0]:
			return false
	return true


func color() -> Color:
	return COLORS.get(crosshair_color, HudStyle.WHITE)
