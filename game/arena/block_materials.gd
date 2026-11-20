class_name BlockMaterials
## What a block is made of, for its sounds and effects: the footsteps on it and the
## rubble, dust and crash when it breaks. Every MapBlock has a Material Type; left
## blank it comes from its kind (the palette's `material` list, else a guess from
## the kind's name).
##
## To add a material: add a row to TABLE. Until it has its own sounds, it borrows
## the nearest one (`step` and `break` name a sound in game/audio/sfx/) and changes
## its pitch. Real sounds can replace them later without touching any map.

const DEFAULT := "concrete"

## material -> its sounds and effects:
##   step: footstep sound, step_pitch / step_db: how it is played
##   break: crash sound, break_pitch: how it is played
##   debris: [count, colour of the dust], shards: true = flat pieces (glass)
const TABLE := {
	"concrete": {"step": "step", "step_pitch": 1.0, "step_db": 0.0,
		"break": "break_concrete", "break_pitch": 1.0, "debris": 10, "dust": Color(0.72, 0.68, 0.62, 0.4), "shards": false},
	"metal": {"step": "step", "step_pitch": 1.25, "step_db": 2.0,
		"break": "break_concrete", "break_pitch": 1.45, "debris": 8, "dust": Color(0.55, 0.55, 0.58, 0.25), "shards": false},
	"wood": {"step": "step", "step_pitch": 0.85, "step_db": -1.0,
		"break": "break_wood", "break_pitch": 1.0, "debris": 12, "dust": Color(0.62, 0.5, 0.36, 0.35), "shards": false},
	"glass": {"step": "step", "step_pitch": 1.4, "step_db": -2.0,
		"break": "break_glass", "break_pitch": 1.0, "debris": 8, "dust": Color(0.8, 0.9, 1.0, 0.35), "shards": true},
	"dirt": {"step": "crawl", "step_pitch": 0.8, "step_db": 0.0,
		"break": "break_concrete", "break_pitch": 0.75, "debris": 14, "dust": Color(0.55, 0.45, 0.33, 0.5), "shards": false},
	"rubber": {"step": "step", "step_pitch": 0.7, "step_db": -6.0,
		"break": "break_wood", "break_pitch": 0.7, "debris": 6, "dust": Color(0.3, 0.3, 0.3, 0.2), "shards": false},
}


static func names() -> PackedStringArray:
	return PackedStringArray(TABLE.keys())


static func info(material: String) -> Dictionary:
	return TABLE.get(material, TABLE[DEFAULT])


## The material of a block of `kind`: the palette's choice, else a guess from the name.
static func for_kind(kind: String, palette: MapPalette) -> String:
	if palette and palette.material.has(kind) and TABLE.has(palette.material[kind]):
		return palette.material[kind]
	return guess(kind)


static func guess(kind: String) -> String:
	if "glass" in kind or "window" in kind:
		return "glass"
	for w in ["plank", "ply", "partition", "board", "wood", "desk", "crate", "pallet"]:
		if w in kind:
			return "wood"
	for w in ["steel", "metal", "iron", "girder", "rail", "grate", "pipe", "beam", "hull", "copper", "rust"]:
		if w in kind:
			return "metal"
	for w in ["dirt", "sand", "grass", "earth", "soil", "gravel", "mud", "puddle", "water"]:
		if w in kind:
			return "dirt"
	for w in ["rubber", "mat", "carpet", "rug", "foam"]:
		if w in kind:
			return "rubber"
	return DEFAULT


## Words in a kind's name that say it is stone, brick or concrete (the default
## material, so guess() cannot tell them from a name it does not know).
const STONY := ["stone", "concrete", "brick", "tile", "paving", "path", "slab", "rock", "marble", "cobble", "flag"]


## Is it known what a kind is made of: its palette says, or its name does? (Footsteps
## let walk-through decoration on a floor change what is heard only when it is: a rug,
## a grate, a patch of dirt; not a glowing strip or a painted sign.)
static func known(kind: String, palette: MapPalette) -> bool:
	if palette and palette.material.has(kind) and TABLE.has(palette.material[kind]):
		return true
	if guess(kind) != DEFAULT:
		return true
	for w in STONY:
		if w in kind:
			return true
	return false
