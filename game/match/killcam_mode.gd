class_name KillcamMode
extends RefCounted
## Killcam: a free-for-all where style wins. Everyone has the anti-materiel rifle and nothing
## else, and every kill scores its killcam points (KillScore: range, headshots,
## momentum, flicks, trickshots...), not just 1. First to a number of points, or the
## most points when the time runs out: the host sets both in the lobby (LobbySettings
## "killcam_points" and "killcam_minutes"; POINTS_TO_WIN and MINUTES unless changed). When the match ends, whoever has the match's
## best killcam (the #1 shown on the results screen) gets BEST_BONUS on top, which
## can change the winner. Arena maps only.
##
## The host adds the points (Match.scores "points", see Match._host_kill) from the
## same score it already sends with each death, so every copy agrees.

const WEAPON := "anti_materiel"
const POINTS_TO_WIN := 5000      ## the default points to win...
const POINTS_MIN := 1000
const POINTS_MAX := 50000
const POINTS_STEP := 500          ## ...picked in steps of this
const MINUTES := 5                ## the default time limit...
const MINUTES_MIN := 1
const MINUTES_MAX := 30
const BEST_BONUS := 1500          ## for the match's #1 killcam (about three good kills)


## Is the match set up (or running) as Killcam?
static func active() -> bool:
	return str(Net.match_settings.get("mode", "")) == "killcam" and Net.game_kind() == "ffa"


## The points to win this match: the host's setting (--points=N sets it, for tests).
static func target() -> int:
	return clean_points(Net.match_settings.get("killcam_points", POINTS_TO_WIN))


## The time limit in minutes: the host's setting.
static func minutes() -> int:
	return clean_minutes(Net.match_settings.get("killcam_minutes", MINUTES))


## A points target as stored: a whole number of POINTS_STEP, POINTS_MIN to POINTS_MAX.
static func clean_points(value) -> int:
	var v := int(value) if (value is int or value is float) else POINTS_TO_WIN
	return clampi(int(roundf(float(v) / POINTS_STEP)) * POINTS_STEP, POINTS_MIN, POINTS_MAX)


## A time limit as stored: whole minutes, MINUTES_MIN to MINUTES_MAX.
static func clean_minutes(value) -> int:
	var v := int(value) if (value is int or value is float) else MINUTES
	return clampi(v, MINUTES_MIN, MINUTES_MAX)


## 12,345
static func format(points: int) -> String:
	var s := str(absi(points))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if points < 0 else "") + s + out
