class_name Mobility
extends RefCounted
## The mobility slot: the tool on your mobility button (middle mouse). There is one:
##
##  - grapple: the grappling hook (see Grapple): the hook is shot out and takes a
##             moment to fly there, trailing a slack line that pulls tight once it
##             has bitten. Swing, reel in, hook players (lead what you aim at).
##
## The jetpack is not on this slot: when the host turns it on in the lobby, everyone
## has it, on Space held in mid-air (see LobbySettings.jetpack, Jetpack and
## MovementController.space_jet). A race never has it: the courses are built around
## the grapple.

const GRAPPLE := "grapple"
const IDS := [GRAPPLE]
## Ids that are no longer tools, and the tool a saved choice of one becomes: the
## projectile hook was "grapple2" (Grappling Hook 2) until it replaced the first
## grappling hook. (A saved pick of a tool that has since left the game, such as
## blink, the portal gun or the jetpack, is no tool at all: valid() makes it the default.)
const RENAMED := {"grapple2": GRAPPLE}

const NAMES := {GRAPPLE: "Grappling Hook"}
const SHORT := {GRAPPLE: "Grapple"}
const BLURBS := {
	GRAPPLE: "Shoot the hook out: it bites, the slack snaps tight and you swing. Hook a player to kick.",
}


static func default_id() -> String:
	return GRAPPLE


## Is this tool the rope? (Always, now: the grapple is the only one.)
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
