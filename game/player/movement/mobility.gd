class_name Mobility
extends RefCounted
## The mobility slot: the tool on your mobility button (middle mouse), picked like
## your weapon before a match and while you wait to respawn.
##
##  - grapple: the grappling hook (see Grapple): the hook is shot out and takes a
##             moment to fly there, trailing a slack line that pulls tight once it
##             has bitten. Swing, reel in, hook players (lead what you aim at).
##  - blink:   a short teleport where you look (see Blink), one charge that
##             comes back a couple of seconds after you use it.
##
## The jetpack is not on this slot: everyone has it, on Space held in mid-air (see
## Jetpack and MovementController.space_jet). A race always uses the grapple: the
## courses are built around it.

const GRAPPLE := "grapple"
const BLINK := "blink"
const IDS := [GRAPPLE, BLINK]
## Ids that are no longer tools, and the tool a saved choice of one becomes: the
## projectile hook was "grapple2" (Grappling Hook 2) until it replaced the first
## grappling hook. (A saved pick of a tool that has since left the slot, such as the
## jetpack, which everyone has now, is no tool at all: valid() makes it the default.)
const RENAMED := {"grapple2": GRAPPLE}

const NAMES := {GRAPPLE: "Grappling Hook", BLINK: "Blink"}
const SHORT := {GRAPPLE: "Grapple", BLINK: "Blink"}
const BLURBS := {
	GRAPPLE: "Shoot the hook out: it bites, the slack snaps tight and you swing. Hook a player to kick.",
	BLINK: "Teleport a few metres where you look, keeping your speed. A trail of sparks follows you there.",
}


static func default_id() -> String:
	return GRAPPLE


## Is this tool the rope? Blink takes the mobility button for itself.
static func is_grapple(id: String) -> bool:
	return canonical(id) == GRAPPLE


## What the HUD calls it, under the crosshair.
static func hud_label(id: String) -> String:
	return valid(id).to_upper()


## A stored id as it is called today (see RENAMED); anything else as it is.
static func canonical(id: String) -> String:
	return RENAMED.get(id, id)


static func has(id: String) -> bool:
	return id in IDS


static func valid(id: String) -> String:
	id = canonical(id)
	return id if has(id) else default_id()


static func name_of(id: String) -> String:
	return NAMES[valid(id)]


static func short_name(id: String) -> String:
	return SHORT[valid(id)]


static func blurb(id: String) -> String:
	return BLURBS[valid(id)]


static func next(id: String) -> String:
	return IDS[(IDS.find(valid(id)) + 1) % IDS.size()]
