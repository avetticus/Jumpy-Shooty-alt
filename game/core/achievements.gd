extends Node
## Achievements: things you do in matches (kills, headshots, wins, races finished...)
## counted across every game you play, each unlocking something: for the Character
## Creator (a hat, a pair of wings, a whole body, a paint), or a calling card or an
## icon (the banner and badge by your name: see CallingCard).
##
## Only your own player counts, in any match with someone to play against: online,
## or against bots. The counts are kept in a file of their own (user://achievements.cfg),
## apart from the settings.
##
## An item is a key: "part:ninja" (a body for the head, torso or legs), "paint:gold",
## "<slot>:<accessory>" ("hat:crown"), or a calling card or icon ("card:sunset",
## "icon:skull": see CallingCard). Anything no achievement names is free from
## the start. Locks are about what you can make and save in the creator: a character
## someone else plays, or one you saved before a lock existed, is always drawn in full
## (whatever your saved characters wear is yours to keep).
##
##   Achievements.locked("hat:crown")            is it still locked?
##   Achievements.requirement("hat:crown")       "Warlord: 500 kills (37 / 500)"
##   Achievements.locked_in(character)           the locked items a character uses
##   Achievements.add("headshots")               count one (the game does this itself)
##
## It also keeps the numbers the Profile page shows: experience ("xp": every kill adds
## its killcam score, see KillScore and PlayerLevel), time played ("seconds_played"),
## your top speed (a best, not a count: see best()) and when each achievement was
## completed (most_recent()).

signal unlocked(id: String)   ## an achievement was just completed
signal progressed             ## a count changed

const FILE := "user://achievements.cfg"
const SAVE_EVERY := 8.0       ## seconds: counts are written at most this often mid-match
const TOAST_TIME := 4.0
const TOAST_SIZE := Vector2(340, 54)      ## the toast is never bigger than this
const TOAST_MARGIN := Vector2(16, 36)     ## from the corner: under the top edge's small print, over the death screen

## The kinds of achievement, as the page's tabs show them: id and name.
const GROUPS := [["combat", "Combat"], ["movement", "Movement"], ["matches", "Matches"], ["races", "Races"], ["misc", "Misc"]]

## Every achievement, in the order the page shows them (within its kind). group: its
## kind (an id from GROUPS); stat: what it counts (see _on_kill and the other hooks);
## goal: how many; what: the line under its name; rewards: the items it unlocks.
const LIST := [
	{"id": "first_blood", "name": "First Blood", "group": "combat", "stat": "kills", "goal": 1, "what": "Get a kill", "rewards": ["hat:party"]},
	{"id": "kills_25", "name": "Warming Up", "group": "combat", "stat": "kills", "goal": 25, "what": "Get 25 kills", "rewards": ["hat:bandana"]},
	{"id": "kills_100", "name": "Centurion", "group": "combat", "stat": "kills", "goal": 100, "what": "Get 100 kills", "rewards": ["hat:viking", "shoulder:pauldrons"]},
	{"id": "kills_250", "name": "Veteran", "group": "combat", "stat": "kills", "goal": 250, "what": "Get 250 kills", "rewards": ["shoulder:bandolier", "back:banner", "icon:skull"]},
	{"id": "kills_500", "name": "Warlord", "group": "combat", "stat": "kills", "goal": 500, "what": "Get 500 kills", "rewards": ["hat:crown", "paint:silver"]},
	{"id": "kills_1000", "name": "Legend", "group": "combat", "stat": "kills", "goal": 1000, "what": "Get 1000 kills", "rewards": ["hat:halo", "back:wings", "paint:gold", "card:royal", "icon:skull_king"]},
	{"id": "headshots_10", "name": "Sharp Eye", "group": "combat", "stat": "headshots", "goal": 10, "what": "Get 10 headshot kills", "rewards": ["face:monocle"]},
	{"id": "headshots_50", "name": "Marksman", "group": "combat", "stat": "headshots", "goal": 50, "what": "Get 50 headshot kills", "rewards": ["face:eye_patch", "face:aviators"]},
	{"id": "headshots_200", "name": "Deadeye", "group": "combat", "stat": "headshots", "goal": 200, "what": "Get 200 headshot kills", "rewards": ["face:laser_visor", "hat:cowboy", "card:bullseye", "icon:headhunter"]},
	{"id": "long_10", "name": "Long Arm", "group": "combat", "stat": "long_shots", "goal": 10, "what": "Get 10 kills from 30 m or more", "rewards": ["back:quiver"]},
	{"id": "long_50", "name": "Eagle Eye", "group": "combat", "stat": "long_shots", "goal": 50, "what": "Get 50 kills from 30 m or more", "rewards": ["shoulder:drone"]},
	{"id": "air_25", "name": "Airborne", "group": "movement", "stat": "air_kills", "goal": 25, "what": "Get 25 kills while in the air", "rewards": ["hat:propeller"]},
	{"id": "rope_25", "name": "Swinger", "group": "movement", "stat": "rope_kills", "goal": 25, "what": "Get 25 kills while on the grapple", "rewards": ["tail:monkey_tail"]},
	{"id": "wall_10", "name": "Wall Crawler", "group": "movement", "stat": "wall_kills", "goal": 10, "what": "Get 10 kills while wall-running", "rewards": ["part:ninja"]},
	{"id": "glide_10", "name": "Night Glider", "group": "movement", "stat": "glide_kills", "goal": 10, "what": "Get 10 kills while gliding", "rewards": ["back:bat_wings"]},
	{"id": "air_shot_25", "name": "Clay Pigeon", "group": "combat", "stat": "air_shots", "goal": 25, "what": "Kill 25 players who are in the air", "rewards": ["part:duck"]},
	{"id": "fast_25", "name": "Speed Demon", "group": "movement", "stat": "fast_kills", "goal": 25, "what": "Get 25 kills while moving at 18 m/s or faster", "rewards": ["back:rocket_pack"]},
	{"id": "flick_15", "name": "Flick of the Wrist", "group": "combat", "stat": "flicks", "goal": 15, "what": "Get 15 flick kills", "rewards": ["hat:wizard"]},
	{"id": "kick_10", "name": "Boot Camp", "group": "movement", "stat": "kicks", "goal": 10, "what": "Get 10 kills with a kick", "rewards": ["neck:dog_tags"]},
	{"id": "flying_kick_10", "name": "Flying Lesson", "group": "movement", "stat": "flying_kicks", "goal": 10, "what": "Get 10 kills with a flying kick", "rewards": ["part:astronaut"]},
	{"id": "smash_10", "name": "Crash Test", "group": "movement", "stat": "smashes", "goal": 10, "what": "Smash 10 players into a wall", "rewards": ["hat:traffic_cone"]},
	{"id": "melee_25", "name": "Blade Dancer", "group": "combat", "stat": "melee_kills", "goal": 25, "what": "Get 25 kills with a melee weapon", "rewards": ["back:sword", "back:shield", "icon:swords"]},
	{"id": "double_10", "name": "Double Trouble", "group": "combat", "stat": "doubles", "goal": 10, "what": "Get 10 double kills (two within 4 seconds)", "rewards": ["hat:jester"]},
	{"id": "triple_3", "name": "Hat Trick", "group": "combat", "stat": "triples", "goal": 3, "what": "Get 3 triple kills", "rewards": ["part:imp", "hat:devil_horns", "tail:devil_tail"]},
	{"id": "trick_10", "name": "Show-off", "group": "combat", "stat": "trickshots", "goal": 10, "what": "Get 10 trickshots (two tricks or more in one kill)", "rewards": ["face:heart_shades"]},
	{"id": "trick_50", "name": "Trickshot Artist", "group": "combat", "stat": "trickshots", "goal": 50, "what": "Get 50 trickshots", "rewards": ["hat:unicorn", "back:butterfly_wings"]},
	{"id": "clutch_10", "name": "By a Thread", "group": "combat", "stat": "clutches", "goal": 10, "what": "Get 10 kills with 25 health or less", "rewards": ["neck:medal"]},
	{"id": "win_1", "name": "Winner", "group": "matches", "stat": "wins", "goal": 1, "what": "Win a match", "rewards": ["neck:gold_chain"]},
	{"id": "win_10", "name": "Champion", "group": "matches", "stat": "wins", "goal": 10, "what": "Win 10 matches", "rewards": ["waist:champion_belt", "icon:laurels"]},
	{"id": "win_50", "name": "Dynasty", "group": "matches", "stat": "wins", "goal": 50, "what": "Win 50 matches", "rewards": ["neck:ruff", "shoulder:epaulettes", "icon:crown"]},
	{"id": "matches_10", "name": "Regular", "group": "misc", "stat": "matches", "goal": 10, "what": "Play 10 matches to the end", "rewards": ["hat:headphones", "shoulder:boombox"]},
	{"id": "deaths_50", "name": "Bag of Bones", "group": "misc", "stat": "deaths", "goal": 50, "what": "Die 50 times", "rewards": ["part:skeleton"]},
	{"id": "deaths_200", "name": "Back for More", "group": "misc", "stat": "deaths", "goal": 200, "what": "Die 200 times", "rewards": ["part:zombie"]},
	{"id": "race_1", "name": "Finisher", "group": "races", "stat": "races", "goal": 1, "what": "Finish a race", "rewards": ["face:goggles"]},
	{"id": "race_10", "name": "Speedrunner", "group": "races", "stat": "races", "goal": 10, "what": "Finish 10 races", "rewards": ["back:surfboard"]},
	{"id": "race_win_3", "name": "First Past the Post", "group": "races", "stat": "race_wins", "goal": 3, "what": "Win 3 races against other racers", "rewards": ["card:racing"]},
	{"id": "race_clean_3", "name": "Clean Run", "group": "races", "stat": "clean_races", "goal": 3, "what": "Finish 3 races without going back to a checkpoint", "rewards": ["icon:diamond"]},
	{"id": "race_tour", "name": "Grand Tour", "group": "races", "stat": "courses", "goal": 4, "what": "Finish 4 different race courses", "rewards": ["part:yeti"]},
	# Calling cards and icons (see CallingCard) from here on.
	{"id": "sidearm_50", "name": "Quick Draw", "group": "combat", "stat": "sidearm_kills", "goal": 50, "what": "Get 50 kills with sidearms", "rewards": ["icon:six_shooter"]},
	{"id": "shotgun_50", "name": "Close Quarters", "group": "combat", "stat": "shotgun_kills", "goal": 50, "what": "Get 50 kills with shotguns", "rewards": ["card:hazard"]},
	{"id": "rifle_100", "name": "Rifleman", "group": "combat", "stat": "rifle_kills", "goal": 100, "what": "Get 100 kills with rifles", "rewards": ["card:woodland"]},
	{"id": "marksman_50", "name": "Sharpshooter", "group": "combat", "stat": "marksman_kills", "goal": 50, "what": "Get 50 kills with marksman weapons", "rewards": ["shoulder:servo_skull", "card:arctic", "icon:reticle"]},
	{"id": "explosive_50", "name": "Demolition", "group": "combat", "stat": "explosive_kills", "goal": 50, "what": "Get 50 kills with explosives", "rewards": ["shoulder:missile_pod", "hat:hard_hat", "card:magma", "icon:grenade"]},
	{"id": "weapons_15", "name": "Gunsmith", "group": "combat", "stat": "weapons_used", "goal": 15, "what": "Get a kill with 15 different weapons", "rewards": ["card:blueprint"]},
	{"id": "weapons_30", "name": "Arsenal", "group": "combat", "stat": "weapons_used", "goal": 25, "what": "Get a kill with 25 different weapons", "rewards": ["card:chrome"]},
	{"id": "streak_5", "name": "On a Roll", "group": "combat", "stat": "streaks_5", "goal": 1, "what": "Get 5 kills without dying", "rewards": ["icon:flame"]},
	{"id": "streak_10", "name": "Unstoppable", "group": "combat", "stat": "streaks_10", "goal": 1, "what": "Get 10 kills without dying", "rewards": ["hat:cog_halo", "card:inferno"]},
	{"id": "quad_1", "name": "Four of a Kind", "group": "combat", "stat": "quads", "goal": 1, "what": "Get a quad kill (four in a row, each within 4 seconds)", "rewards": ["hat:void_crest", "icon:ace"]},
	{"id": "flawless_1", "name": "Untouchable", "group": "matches", "stat": "flawless_wins", "goal": 1, "what": "Win a match with 5 kills or more and no deaths", "rewards": ["hat:skull_crown", "card:abyss", "icon:phantom"]},
	{"id": "revenge_25", "name": "Payback", "group": "combat", "stat": "revenges", "goal": 25, "what": "Kill the player who last killed you, 25 times", "rewards": ["card:blood_moon"]},
	{"id": "opener_10", "name": "Fast Start", "group": "combat", "stat": "first_kills", "goal": 10, "what": "Get the first kill of the match 10 times", "rewards": ["icon:blitz"]},
	{"id": "close_win_3", "name": "Photo Finish", "group": "matches", "stat": "close_wins", "goal": 3, "what": "Win 3 free-for-all matches by a single kill", "rewards": ["card:sunburst"]},
	{"id": "big_kill_10", "name": "Highlight Reel", "group": "combat", "stat": "big_kills", "goal": 10, "what": "Score 400 or more with one kill, 10 times", "rewards": ["card:starfield", "icon:comet"]},
	{"id": "far_10", "name": "Out of Town", "group": "combat", "stat": "far_kills", "goal": 10, "what": "Get 10 kills from 60 m or more", "rewards": ["icon:overwatch"]},
	{"id": "far_100m", "name": "Another Postcode", "group": "combat", "stat": "very_far_kills", "goal": 1, "what": "Get a kill from 100 m or more", "rewards": ["card:skyline"]},
	{"id": "sonic_10", "name": "Sonic Boom", "group": "movement", "stat": "sonic_kills", "goal": 10, "what": "Get 10 kills while moving at 25 m/s or faster", "rewards": ["hat:mohawk", "card:storm"]},
	{"id": "air_100", "name": "Frequent Flyer", "group": "movement", "stat": "air_kills", "goal": 100, "what": "Get 100 kills while in the air", "rewards": ["back:energy_wings", "icon:wings"]},
	{"id": "rope_100", "name": "Hooked", "group": "movement", "stat": "rope_kills", "goal": 100, "what": "Get 100 kills while on the grapple", "rewards": ["icon:hook"]},
	{"id": "kick_50", "name": "Black Belt", "group": "movement", "stat": "kicks", "goal": 50, "what": "Get 50 kills with a kick", "rewards": ["icon:boot"]},
	{"id": "gun_game_3", "name": "Up the Ladder", "group": "matches", "stat": "gun_game_wins", "goal": 3, "what": "Win 3 Gun Game matches", "rewards": ["icon:sergeant"]},
	{"id": "killcam_3", "name": "Director's Cut", "group": "matches", "stat": "killcam_wins", "goal": 3, "what": "Win 3 Killcam matches", "rewards": ["face:three_d", "card:vaporwave", "icon:rec"]},
	{"id": "golden_3", "name": "Midas Touch", "group": "matches", "stat": "golden_gun_wins", "goal": 3, "what": "Win 3 Golden Gun matches", "rewards": ["card:gold_bar"]},
	{"id": "team_win_10", "name": "Team Player", "group": "matches", "stat": "team_wins", "goal": 10, "what": "Win 10 team matches", "rewards": ["card:honeycomb"]},
	{"id": "plant_10", "name": "Sapper", "group": "matches", "stat": "plants", "goal": 10, "what": "Plant the bomb 10 times in Search and Destroy", "rewards": ["icon:c4"]},
	{"id": "defuse_5", "name": "Bomb Squad", "group": "matches", "stat": "defuses", "goal": 5, "what": "Defuse the bomb 5 times in Search and Destroy", "rewards": ["icon:defuser"]},
	{"id": "capture_10", "name": "Flag Runner", "group": "matches", "stat": "captures", "goal": 10, "what": "Capture the flag 10 times", "rewards": ["icon:flag"]},
	{"id": "medal_bronze", "name": "On the Clock", "group": "races", "stat": "bronze_medals", "goal": 1, "what": "Beat the bronze time on a race course", "rewards": ["icon:stopwatch"]},
	{"id": "medal_silver", "name": "Silver Lining", "group": "races", "stat": "silver_medals", "goal": 2, "what": "Beat the silver time on 2 race courses", "rewards": ["card:chequered"]},
	{"id": "medal_gold", "name": "Gold Standard", "group": "races", "stat": "gold_medals", "goal": 1, "what": "Beat the gold time on a race course", "rewards": ["icon:medal"]},
	{"id": "medal_gold_4", "name": "Gold Rush", "group": "races", "stat": "gold_medals", "goal": 4, "what": "Beat the gold time on 4 race courses", "rewards": ["card:aurora", "icon:mach"]},
	{"id": "expert_1", "name": "Giant Slayer", "group": "matches", "stat": "expert_wins", "goal": 1, "what": "Win a match against an Expert bot", "rewards": ["tail:power_cord", "card:circuit", "icon:scrapper"]},
	{"id": "online_10", "name": "Good Company", "group": "misc", "stat": "online_matches", "goal": 10, "what": "Play 10 online matches with other people to the end", "rewards": ["card:sunset"]},
	{"id": "host_1", "name": "Party Host", "group": "misc", "stat": "hosted", "goal": 1, "what": "Host a match with 4 or more people in it", "rewards": ["icon:signal"]},
	{"id": "matches_50", "name": "Old Hand", "group": "misc", "stat": "matches", "goal": 50, "what": "Play 50 matches to the end", "rewards": ["icon:service"]},
	{"id": "falls_10", "name": "Mind the Gap", "group": "misc", "stat": "falls", "goal": 10, "what": "Fall out of the arena 10 times", "rewards": ["card:frostbite"]},
	{"id": "self_5", "name": "Own Goal", "group": "misc", "stat": "self_kills", "goal": 5, "what": "Take yourself out 5 times", "rewards": ["card:toxic", "icon:boomerang"]},
]

## Race medals: the times to beat on each course (seconds: bronze, silver, gold).
## Gold is about what an Expert bot runs (70.0, 73.3, 68.0 and 57.3 s when these were
## set); silver is a little quicker than a Normal bot; bronze is a steady run.
const MEDALS := {
	"rooftop_run": [100.0, 82.0, 71.0],
	"foundry": [105.0, 85.0, 74.0],
	"sky_ruins": [100.0, 80.0, 69.0],
	"summit_plunge": [85.0, 66.0, 58.0],
}
const MEDAL_NAMES := ["bronze", "silver", "gold"]
## A kill's weapon group (WeaponData.GROUPS) -> the count it adds to.
const GROUP_STATS := {"Sidearms": "sidearm_kills", "Shotguns": "shotgun_kills", "Rifles": "rifle_kills",
	"Marksman": "marksman_kills", "Explosives": "explosive_kills"}
## Counts that are the size of a set kept in the file (each thing counts once).
const SET_STATS := {"courses": "courses", "weapons": "weapons_used", "bronze": "bronze_medals",
	"silver": "silver_medals", "gold": "gold_medals"}
const BIG_KILL := 400         ## a kill's score from this up is a "big" one
const FAR := 60.0             ## metres
const VERY_FAR := 100.0
const SONIC := 25.0           ## m/s
const FLAWLESS_KILLS := 5     ## a win with no deaths counts from this many kills
const HOSTED_PEOPLE := 4
const MAX_TRACKED := 3        ## achievements you can track for the Profile page
const SPEED_SANE := 80.0      ## m/s: a top speed faster than this is a glitch, not a run

## --unlock-all: nothing is locked (testing, or just dressing up).
var unlock_all := false

var _stats := {}        # stat -> int
var _done := {}         # achievement id -> true: the ones already announced
var _owned := {}        # item key -> true: yours whatever the counts say (worn by a character you saved)
var _sets := {}         # set name (see SET_STATS) -> {thing: true}: courses finished, weapons with a kill, medals
var _times := {}        # race course id -> your best time (seconds)
var _best := {}         # name -> the highest it has been ("top_speed": m/s)
var _when := {}         # achievement id -> when it was completed (unix seconds; only those done since this was kept)
var _play_time := 0.0   # seconds played not yet counted in "seconds_played"
var _life_kills := 0    # kills since you last died
var _nemesis := 0       # who last killed you (this match)
var _base := {}         # stat -> its count when the file was last read or written (see save)
var _by_reward := {}    # item key -> its achievement
var _file := FILE       # "" keeps nothing (tests)
var _dirty := false
var _since_save := 0.0
var _toasts: Array = []        # achievements waiting to be shown
var _toast: Control
var _toast_left := 0.0
var _layer: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the toast shows over a paused game too
	for a in LIST:
		for key in a.rewards:
			_by_reward[key] = a
	unlock_all = DevArgs.unlock_all
	_load()
	Match.kill_scored.connect(_on_kill)
	Match.player_died.connect(_on_died)
	Match.match_over.connect(_on_match_over)
	Race.gate_passed.connect(_on_gate)
	Teams.event.connect(_on_team_event)


# ---------------------------------------------------------------------------
# Counts

func stat(name: String) -> int:
	return int(_stats.get(name, 0))


## Count `n` more of something, and announce any achievement that completes.
func add(name: String, n: int = 1) -> void:
	if n <= 0:
		return
	_stats[name] = stat(name) + n
	_dirty = true
	for a in LIST:
		if a.stat == name and not _done.has(a.id) and stat(name) >= int(a.goal):
			_done[a.id] = true
			_when[a.id] = Time.get_unix_time_from_system()
			print("[achievements] %s" % a.name)
			_toasts.append(a)
			unlocked.emit(a.id)
	progressed.emit()


func by_id(id: String) -> Dictionary:
	for a in LIST:
		if a.id == id:
			return a
	return {}


func done(id: String) -> bool:
	var a := by_id(id)
	return not a.is_empty() and stat(a.stat) >= int(a.goal)


func done_count() -> int:
	return LIST.filter(func(a): return stat(a.stat) >= int(a.goal)).size()


## How far along an achievement is, 0 to 1.
func fraction(a: Dictionary) -> float:
	return clampf(float(stat(a.stat)) / maxf(float(a.goal), 1.0), 0.0, 1.0)


## The highest a "best" has been (see _best): "top_speed".
func best(name: String) -> float:
	return float(_best.get(name, 0.0))


## Keep `value` if it beats the best so far.
func set_best(name: String, value: float) -> void:
	if value > best(name):
		_best[name] = value
		_dirty = true


## The achievement you completed last ({} if none). Ones done before the game kept
## the time count as older than any that has one; among those, the last in the list.
func most_recent() -> Dictionary:
	var out := {}
	var at := -1.0
	for a in LIST:
		if done(a.id) and float(_when.get(a.id, 0.0)) >= at:
			at = float(_when.get(a.id, 0.0))
			out = a
	return out


## The achievements you track that are still to do (see Settings.tracked_achievements).
func tracked() -> Array:
	var out := []
	for id in Settings.tracked_achievements:
		var a := by_id(str(id))
		if not a.is_empty() and not done(a.id):
			out.append(a)
	return out


func is_tracked(id: String) -> bool:
	return id in Settings.tracked_achievements


## Track an achievement, or stop tracking it. Tracking a fourth lets the oldest go.
## Done ones can't be tracked. Returns whether it is tracked now.
func toggle_tracked(id: String) -> bool:
	var list: Array = Settings.tracked_achievements.filter(func(t): return not by_id(str(t)).is_empty() and not done(str(t)))
	var on := false
	if id in list:
		list.erase(id)
	elif not by_id(id).is_empty() and not done(id):
		list.append(id)
		while list.size() > MAX_TRACKED:
			list.pop_front()
		on = true
	Settings.tracked_achievements = list
	Settings.save_settings()
	progressed.emit()
	return on


## The Profile page's list: the ones you track, then the closest to done, `count` in all.
func closest(count: int = MAX_TRACKED) -> Array:
	var out := tracked().slice(0, count)
	var rest := LIST.filter(func(a): return not done(a.id) and a not in out)
	rest.sort_custom(func(x, y): return fraction(x) > fraction(y))
	for a in rest:
		if out.size() >= count:
			break
		out.append(a)
	return out


## "37 / 200" (never past the goal).
func progress_text(a: Dictionary) -> String:
	return "%d / %d" % [mini(stat(a.stat), int(a.goal)), int(a.goal)]


# ---------------------------------------------------------------------------
# Items

## Whether an item still has to be earned.
func locked(key: String) -> bool:
	if unlock_all or _owned.has(key) or not _by_reward.has(key):
		return false
	var a: Dictionary = _by_reward[key]
	return stat(a.stat) < int(a.goal)


## The achievement that unlocks an item ({} if it is free).
func achievement_for(key: String) -> Dictionary:
	return _by_reward.get(key, {})


## What a locked item needs, with how far along you are: "Warlord: Get 500 kills (37 / 500)".
func requirement(key: String) -> String:
	var a := achievement_for(key)
	return "" if a.is_empty() else "%s: %s (%s)" % [a.name, a.what, progress_text(a)]


## Every item a character uses (see the keys above), each once.
static func keys_of(c: CustomCharacter) -> Array:
	var out := []
	for part in [c.head, c.torso, c.legs]:
		if not ("part:" + part) in out:
			out.append("part:" + part)
	for slot in CustomCharacter.SLOTS:
		if c.accessories.get(slot, "") != "":
			out.append("%s:%s" % [slot, c.accessories[slot]])
	for paint in [c.paint, c.paint2, c.paint3] + CustomCharacter.SLOTS.map(func(s): return c.color_of(s)):
		if paint != "" and not ("paint:" + paint) in out:
			out.append("paint:" + paint)
	return out


## The locked items a character uses: it can be looked at, but not saved.
func locked_in(c: CustomCharacter) -> Array:
	return keys_of(c).filter(locked)


## An item's name as the creator shows it: "Crown", "Ninja", "Gold paint".
static func item_name(key: String) -> String:
	var kind := key.get_slice(":", 0)
	var id := key.get_slice(":", 1)
	match kind:
		"part": return Characters.part_name(id)
		"paint": return "%s paint" % CustomCharacter.paint_name(id)
		"card": return "%s calling card" % CallingCard.card_name(id)
		"icon": return "%s icon" % CallingCard.icon_name(id)
	return CustomCharacter.accessory_name(kind, id)


## How many items are locked behind achievements, and how many of those you have.
func item_counts() -> Array:
	var have := 0
	for key in _by_reward:
		if not locked(key):
			have += 1
	return [have, _by_reward.size()]


# ---------------------------------------------------------------------------
# What the game tells us

func _mine(id: int) -> bool:
	return id != 0 and id == Net.my_id() and Net.players.has(id) and not Net.is_bot(id)


## Count a thing once: the first time it joins its set (see SET_STATS).
func _collect(set_name: String, thing: String) -> void:
	var have: Dictionary = _sets.get_or_add(set_name, {})
	if thing != "" and not have.has(thing):
		have[thing] = true
		add(SET_STATS[set_name])


func _on_kill(info: Dictionary) -> void:
	var first := Match.kill_log.size() == 1   # (the log starts empty each match, and this kill is in it)
	if first:
		_life_kills = 0
		_nemesis = 0
	if not _mine(int(info.killer)) or int(info.victim) == int(info.killer):
		return
	var tags := int(info.tags)
	add("kills")
	add("xp", int(info.get("score", 0)))   # experience: the kill's killcam score
	if first:
		add("first_kills")
	_life_kills += 1
	if _life_kills == 5:
		add("streaks_5")
	if _life_kills == 10:
		add("streaks_10")
	if int(info.victim) == _nemesis:
		_nemesis = 0
		add("revenges")
	var weapon := str(info.get("weapon", ""))
	if weapon in WeaponData.IDS:   # (not a kick)
		_collect("weapons", weapon)
		var group: String = WeaponData.GROUPS[WeaponData.group_of(weapon)][0]
		if GROUP_STATS.has(group):
			add(GROUP_STATS[group])
	if int(info.get("score", 0)) >= BIG_KILL:
		add("big_kills")
	if float(info.get("distance", 0.0)) >= FAR:
		add("far_kills")
	if float(info.get("distance", 0.0)) >= VERY_FAR:
		add("very_far_kills")
	if float(info.get("speed", 0.0)) >= SONIC:
		add("sonic_kills")
	if int(info.streak) == 3:
		add("quads")
	for pair in [[KillScore.T_HEADSHOT, "headshots"], [KillScore.T_LONG, "long_shots"], [KillScore.T_MID_AIR, "air_kills"],
			[KillScore.T_ROPE, "rope_kills"], [KillScore.T_WALL, "wall_kills"], [KillScore.T_GLIDE, "glide_kills"],
			[KillScore.T_AIR_SHOT, "air_shots"], [KillScore.T_KICK | KillScore.T_FLYING_KICK, "kicks"],
			[KillScore.T_FLYING_KICK, "flying_kicks"], [KillScore.T_SMASHED, "smashes"], [KillScore.T_MELEE, "melee_kills"],
			[KillScore.T_CLUTCH, "clutches"], [KillScore.T_FAST, "fast_kills"], [KillScore.T_FLICK, "flicks"]]:
		if tags & int(pair[0]):
			add(pair[1])
	if int(info.streak) == 1:   # (the second kill of a run: counted once per run)
		add("doubles")
	if int(info.streak) == 2:
		add("triples")
	if KillScore.trick_count(tags) >= 2:
		add("trickshots")


func _on_died(victim: int, killer: int) -> void:
	if not _mine(victim) or Race.active:
		return
	add("deaths")
	_life_kills = 0
	if killer == victim:
		add("self_kills")
	elif killer != 0:
		_nemesis = killer
	if str(Match.death_cause.get(victim, "")) == "fell":
		add("falls")


## Team modes: the bomb you planted or defused, the flag you brought home.
func _on_team_event(kind: String, _team: int, who: int) -> void:
	var counts := {"bomb_planted": "plants", "bomb_defused": "defuses", "flag_captured": "captures"}
	if counts.has(kind) and _mine(who):
		add(counts[kind])


## A match that ran to its end, with someone to play against. A win: top of the
## table, or on the team that won.
func _on_match_over(results: Array) -> void:
	var me := Net.my_id()
	for i in results.size():
		var row: Dictionary = results[i]
		if int(row.get("id", 0)) != me or not _mine(me) or results.size() < 2:
			continue
		add("matches")
		var people := Net.players.keys().filter(func(id): return not Net.is_bot(id)).size()
		if Net.is_online and people >= 2:
			add("online_matches")
			if Net.is_host() and people >= HOSTED_PEOPLE:
				add("hosted")
		if row.get("race", false):   # (a race's win is counted as you cross the line)
			continue
		var team := row.has("team_won")
		if not (row.team_won if team else i == 0):
			continue
		add("wins")
		if team:
			add("team_wins")
		elif GunGame.active():
			add("gun_game_wins")
		elif KillcamMode.active():
			add("killcam_wins")
		else:
			if GoldenGun.active():
				add("golden_gun_wins")
			if int(row.get("kills", 0)) - int(results[1].get("kills", 0)) == 1:
				add("close_wins")
		if int(row.get("deaths", 1)) == 0 and int(row.get("kills", 0)) >= FLAWLESS_KILLS:
			add("flawless_wins")
		for id in Net.players:   # an Expert bot you were up against
			if Net.is_bot(id) and int(Net.players[id].get("difficulty", 0)) >= 3 \
					and not (team and Teams.team_of(id) == Teams.team_of(me)):
				add("expert_wins")
				break
	save()


func _on_gate(id: int, _number: int, time: float, finished: bool) -> void:
	if not finished or not _mine(id):
		return
	add("races")
	if Race.resets(id) == 0:
		add("clean_races")
	if Race.progress.size() >= 2 and Race.place(id) == 1:
		add("race_wins")
	var course := str(Net.match_settings.get("map", ""))
	_collect("courses", course)
	_finished_in(course, time)
	save()


## A race finished in `time` seconds: your best on the course, and its medals.
func _finished_in(course: String, time: float) -> void:
	if course == "" or time <= 0.0:
		return
	if not _times.has(course) or time < float(_times[course]):
		_times[course] = time
		_dirty = true
	for tier in medal(course, time) + 1:
		_collect(MEDAL_NAMES[tier], course)


## The medal a time earns on a course: 0 bronze, 1 silver, 2 gold, -1 none.
static func medal(course: String, time: float) -> int:
	var out := -1
	if MEDALS.has(course) and time > 0.0:
		for tier in 3:
			if time <= float(MEDALS[course][tier]):
				out = tier
	return out


## Your best time on a course (0 if you have not finished it).
func best_time(course: String) -> float:
	return float(_times.get(course, 0.0))


# ---------------------------------------------------------------------------
# The file

func _load() -> void:
	_stats.clear()
	_done.clear()
	_owned.clear()
	_sets.clear()
	_times.clear()
	_best.clear()
	_when.clear()
	_read()
	_base = _stats.duplicate()
	for a in LIST:   # nothing already earned is announced again
		if stat(a.stat) >= int(a.goal):
			_done[a.id] = true
	keep_saved()


## Add what the file holds to what is in memory (items and courses: both lots).
func _read() -> void:
	var cfg := ConfigFile.new()
	if _file == "" or cfg.load(_file) != OK:
		return
	for name in cfg.get_section_keys("stats") if cfg.has_section("stats") else PackedStringArray():
		_stats[name] = stat(name) + maxi(int(cfg.get_value("stats", name, 0)), 0)
	for key in cfg.get_value("items", "owned", []):
		_owned[str(key)] = true
	for course in cfg.get_value("races", "courses", []):   # (where the courses were kept at first)
		_sets.get_or_add("courses", {})[str(course)] = true
	for set_name in SET_STATS:
		for thing in cfg.get_value("sets", set_name, []):
			_sets.get_or_add(set_name, {})[str(thing)] = true
	for name in cfg.get_section_keys("best") if cfg.has_section("best") else PackedStringArray():
		_best[name] = maxf(best(name), float(cfg.get_value("best", name, 0.0)))
	for id in cfg.get_section_keys("completed") if cfg.has_section("completed") else PackedStringArray():
		_when[id] = maxf(float(_when.get(id, 0.0)), float(cfg.get_value("completed", id, 0.0)))
	for course in cfg.get_section_keys("times") if cfg.has_section("times") else PackedStringArray():
		var time := float(cfg.get_value("times", course, 0.0))
		if time > 0.0 and (not _times.has(course) or time < float(_times[course])):
			_times[course] = time
	for set_name in SET_STATS:   # a set's count is its size, whatever the file says
		_stats[SET_STATS[set_name]] = (_sets.get(set_name, {}) as Dictionary).size()


## Whatever your saved characters (and the one you play as) wear is yours to keep:
## a lock never takes away something you already made.
func keep_saved() -> void:
	var ids: Array = Settings.custom_characters.duplicate()
	if Characters.is_custom(Settings.character):
		ids.append(Settings.character)
	for id in ids:
		for key in keys_of(CustomCharacter.parse(id)):
			if _by_reward.has(key) and not _owned.has(key):
				_owned[key] = true
				_dirty = true


## Write the counts. Two copies of the game on one PC (a host and a client, say) share
## the file, so this adds what this copy counted since it last looked to what the
## file holds now, instead of writing over it.
func save() -> void:
	_dirty = false
	_since_save = 0.0
	if _file == "":
		return
	var counted := {}
	for name in _stats:
		counted[name] = stat(name) - int(_base.get(name, 0))
	_stats = counted
	_read()
	_base = _stats.duplicate()
	var cfg := ConfigFile.new()
	for name in _stats:
		cfg.set_value("stats", name, _stats[name])
	cfg.set_value("items", "owned", _owned.keys())
	for set_name in _sets:
		cfg.set_value("sets", set_name, _sets[set_name].keys())
	for course in _times:
		cfg.set_value("times", course, _times[course])
	for name in _best:
		cfg.set_value("best", name, _best[name])
	for id in _when:
		cfg.set_value("completed", id, _when[id])
	cfg.save(_file)


# ---------------------------------------------------------------------------
# An account's cloud save (see CloudSave and Account)

## Everything this keeps, as plain data (JSON-safe).
func snapshot() -> Dictionary:
	var sets := {}
	for set_name in _sets:
		sets[set_name] = (_sets[set_name] as Dictionary).keys()
	return {"stats": _stats.duplicate(), "owned": _owned.keys(), "sets": sets,
		"times": _times.duplicate(), "best": _best.duplicate(), "completed": _when.duplicate()}


## Take in progress from the cloud: each count goes up to the bigger of the two, sets
## and unlocks are joined, best times and speeds keep the best. Achievements this
## completes are not announced (they were earned on another computer). Saved at once.
func absorb(p: Dictionary) -> void:
	var stats: Dictionary = p.get("stats", {}) if p.get("stats") is Dictionary else {}
	for name in stats:
		var n := maxi(int(stats[name]), 0)
		if not str(name) in SET_STATS.values() and n > stat(str(name)):
			_stats[str(name)] = n
	for key in p.get("owned", []) if p.get("owned") is Array else []:
		_owned[str(key)] = true
	var sets: Dictionary = p.get("sets", {}) if p.get("sets") is Dictionary else {}
	for set_name in sets:
		if SET_STATS.has(str(set_name)) and sets[set_name] is Array:
			for thing in sets[set_name]:
				_sets.get_or_add(str(set_name), {})[str(thing)] = true
	var times: Dictionary = p.get("times", {}) if p.get("times") is Dictionary else {}
	for course in times:
		var time := float(times[course])
		if time > 0.0 and (not _times.has(str(course)) or time < float(_times[str(course)])):
			_times[str(course)] = time
	var bests: Dictionary = p.get("best", {}) if p.get("best") is Dictionary else {}
	for name in bests:
		_best[str(name)] = maxf(best(str(name)), float(bests[name]))
	var when: Dictionary = p.get("completed", {}) if p.get("completed") is Dictionary else {}
	for id in when:
		var at := float(when[id])
		if at > 0.0 and (not _when.has(str(id)) or at < float(_when[str(id)])):
			_when[str(id)] = at
	for set_name in SET_STATS:
		_stats[SET_STATS[set_name]] = (_sets.get(set_name, {}) as Dictionary).size()
	for a in LIST:
		if not _done.has(a.id) and stat(a.stat) >= int(a.goal):
			_done[a.id] = true
	save()
	progressed.emit()


# ---------------------------------------------------------------------------
# The debug menu (see DebugMenu): earn things without playing for them

## Complete an achievement as if you had just earned it: the count reaches its goal,
## the toast shows and its rewards unlock. One that counts different things (courses,
## weapons, medals) is given real ones, and a medal comes with the time that earns it.
## The lower ones on the same count complete with it, without toasts of their own.
func complete(id: String) -> void:
	var waiting := _toasts.size()
	_complete(by_id(id))
	_toasts = _toasts.slice(0, waiting) + _toasts.slice(waiting).filter(func(a): return a.id == id)
	save()


## Complete every achievement (with no toasts: there would be minutes of them).
func complete_all() -> void:
	for a in LIST:
		_complete(a)
	_toasts.clear()
	save()


func _complete(a: Dictionary) -> void:
	if a.is_empty() or stat(a.stat) >= int(a.goal):
		return
	var set_name = SET_STATS.find_key(a.stat)
	if set_name == null:
		add(a.stat, int(a.goal) - stat(a.stat))
		return
	var tier := MEDAL_NAMES.find(set_name)
	for thing in (WeaponData.IDS if set_name == "weapons" else MEDALS.keys()):
		if stat(a.stat) >= int(a.goal):
			break
		if tier >= 0:
			_finished_in(thing, float(MEDALS[thing][tier]))
		else:
			_collect(set_name, thing)


## Make every reward of a kind yours without completing anything. `cards`: the calling
## cards and icons; otherwise the Character Creator's parts, accessories and paints.
func unlock_items(cards: bool) -> void:
	for key in _by_reward:
		if (str(key).get_slice(":", 0) in ["card", "icon"]) == cards:
			_owned[key] = true
	save()
	progressed.emit()


## Start the account again: every count, medal, best time and unlock is gone, from the
## file too. What your saved characters wear stays yours (see keep_saved). A calling
## card or icon you chose may be locked again: see wear_unlocked.
func reset_progress() -> void:
	_stats.clear()
	_done.clear()
	_owned.clear()
	_sets.clear()
	_times.clear()
	_base.clear()
	_toasts.clear()
	_life_kills = 0
	_nemesis = 0
	if _file != "" and FileAccess.file_exists(_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_file))
	keep_saved()
	save()
	progressed.emit()


## Swap a calling card or icon you chose that is locked (after a reset) for the free
## one. True if it changed anything: the caller saves the settings and tells the match.
func wear_unlocked() -> bool:
	var card := Settings.calling_card if not locked("card:" + Settings.calling_card) else CallingCard.DEFAULT_CARD
	var icon := Settings.icon if not locked("icon:" + Settings.icon) else CallingCard.DEFAULT_ICON
	var changed := card != Settings.calling_card or icon != Settings.icon
	Settings.calling_card = card
	Settings.icon = icon
	return changed


## Tests: start from nothing and keep nothing on disk.
func reset_for_test() -> void:
	_file = ""
	unlock_all = false
	_stats.clear()
	_done.clear()
	_owned.clear()
	_sets.clear()
	_times.clear()
	_best.clear()
	_when.clear()
	_play_time = 0.0
	_life_kills = 0
	_nemesis = 0
	_base.clear()
	_toasts.clear()
	_dirty = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _dirty:
			save()


func _process(delta: float) -> void:
	_since_save += delta
	_watch_me(delta)
	if _dirty and _since_save >= SAVE_EVERY:
		save()
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast and is_instance_valid(_toast):
			_toast.modulate.a = clampf(minf(_toast_left, TOAST_TIME - _toast_left) * 4.0, 0.0, 1.0) * 0.92
		if _toast_left <= 0.0 and _toast and is_instance_valid(_toast):
			_toast.queue_free()
			_toast = null
	elif not _toasts.is_empty():
		_show_toast(_toasts.pop_front())


## In a match: count the time you play, and keep your top speed (across the ground:
## a long fall is not a run).
func _watch_me(delta: float) -> void:
	if not Match.running or Net.arena == null or get_tree().paused:
		return
	var me: Player = Net.arena.get_player(Net.my_id())
	if me == null or not _mine(Net.my_id()) or not Match.is_alive(Net.my_id()):
		return
	_play_time += delta
	if _play_time >= 1.0:
		var whole := int(_play_time)
		_play_time -= whole
		add("seconds_played", whole)
	var speed := Vector2(me.velocity.x, me.velocity.z).length()
	if speed <= SPEED_SANE:
		set_best("top_speed", speed)


# ---------------------------------------------------------------------------
# The toast: a small see-through plate in a top corner when an achievement completes

## Which top corner the toast takes: the one the HUD leaves free. In a match that is
## the corner across from the kill feed (which is on the right while you are dead,
## wherever Settings puts it); in a race the right (the standings are down the left).
static func toast_on_left() -> bool:
	if Race.active:
		return false
	return Settings.hud.feed_corner != "left" or not Match.is_alive(Net.my_id())


## The toast for an achievement: two short lines (and the icon it unlocks, if it
## unlocks one), no bigger than TOAST_SIZE.
static func make_toast(a: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme = UiKit.make_theme()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiKit.cut_box(Color(0.04, 0.06, 0.09, 0.62), 8, 10, 6)
	box.border_width_left = 3
	box.border_color = Color(UiKit.ACCENT, 0.9)
	box.shadow_size = 0
	card.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	for key in a.rewards:   # the icon (or else the card) it unlocks, drawn
		if str(key).begins_with("icon:") or (str(key).begins_with("card:") and not a.rewards.any(func(k): return str(k).begins_with("icon:"))):
			var thumb := AchievementsPanel.Thumb.new(key, true)
			thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(thumb)
			break
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var kicker := UiKit.label(top, "ACHIEVEMENT", false, 10)
	kicker.add_theme_font_override("font", HudStyle.font_spaced(2))
	kicker.add_theme_color_override("font_color", UiKit.CYAN)
	var name_label := UiKit.label(top, str(a.name).to_upper(), false, 14)
	name_label.add_theme_font_override("font", HudStyle.font(true))
	var reward := UiKit.label(col, "Unlocked: %s" % ", ".join(a.rewards.map(item_name)), true, 12)
	reward.name = "reward"
	for l: Label in [kicker, name_label, reward]:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF   # (a wrapping label asks for a tall box)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A long list of rewards is cut short, so the toast stays small.
	var font := reward.get_theme_font("font")
	var wide := font.get_string_size(reward.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 2.0
	reward.clip_text = true
	reward.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	reward.custom_minimum_size.x = minf(wide, TOAST_SIZE.x - 70.0)
	return card


func _show_toast(a: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _layer == null:
		_layer = CanvasLayer.new()
		_layer.layer = 90
		add_child(_layer)
	var card := make_toast(a)
	_layer.add_child(card)
	var left := toast_on_left()
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT if left else Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(TOAST_MARGIN.x))
	card.position.y = TOAST_MARGIN.y
	card.modulate.a = 0.0
	_toast = card
	_toast_left = TOAST_TIME
	if Sound.has_sound("ui_confirm"):
		Sound.play("ui_confirm")
