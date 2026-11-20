extends Node
## Achievement checks (started by tests/achievements_test.gd). Nothing here touches
## the real achievements file or saves the settings.

const TEST_FILE := "user://achievements_test.cfg"

var _fails: Array[String] = []
var _announced: Array = []


func run() -> void:
	await get_tree().process_frame
	print("Achievement checks")
	var saved_characters: Array = Settings.custom_characters.duplicate()
	var saved_pick := Settings.character
	Settings.custom_characters = []
	Settings.character = Characters.default_id()
	Achievements.reset_for_test()
	Achievements.unlocked.connect(func(id: String): _announced.append(id))

	print("  the list")
	var seen := {}
	var bad := []
	for a in Achievements.LIST:
		for key in a.rewards:
			var kind: String = key.get_slice(":", 0)
			var id: String = key.get_slice(":", 1)
			var real := false
			match kind:
				"part": real = Characters.has_part(id) and not id in ["human", "goblin", "frog", Characters.default_id()]
				"paint": real = CustomCharacter.paint_color(id).a > 0.0
				"card": real = CallingCard.valid_card(id) == id and id != CallingCard.DEFAULT_CARD
				"icon": real = CallingCard.valid_icon(id) == id and id != CallingCard.DEFAULT_ICON
				_: real = kind in CustomCharacter.SLOTS and CustomCharacter.accessory_name(kind, id) != "None"
			if not real or seen.has(key):
				bad.append(key)
			seen[key] = true
	_expect(bad.is_empty(), "every reward is a real item, given once, and never the dude, the goblin or the frog %s" % [bad])
	_expect(Achievements.item_counts() == [0, seen.size()] and Achievements.done_count() == 0, "a new player has none of the %d locked items" % seen.size())
	_expect(Achievements.locked("hat:crown") and not Achievements.locked("hat:top_hat") and not Achievements.locked("part:frog"),
		"the crown is locked; the top hat and the frog are free")
	_expect("0 / 500" in Achievements.requirement("hat:crown") and "Warlord" in Achievements.requirement("hat:crown"),
		"a locked item says what it needs (%s)" % Achievements.requirement("hat:crown"))
	_expect(Achievements.item_name("hat:crown") == "Crown" and Achievements.item_name("part:ninja") == "Ninja" and Achievements.item_name("paint:gold") == "Gold paint",
		"items go by their creator names")
	_expect(Achievements.item_name("card:sunset") == "Sunset Drive calling card" and Achievements.item_name("icon:skull") == "Skull icon",
		"a calling card and an icon say what they are")
	var ids := {}
	for a in Achievements.LIST:
		ids[a.id] = true
	_expect(ids.size() == Achievements.LIST.size(), "no two achievements share an id")

	print("  kills")
	Net.start_offline("Host", "needle", "pistol")
	var bot := Net.add_bot(1)
	Match.kill_scored.emit(_kill(bot, 1, KillScore.T_HEADSHOT))
	_expect(Achievements.stat("kills") == 0, "a bot's kill is not yours")
	Match.kill_scored.emit(_kill(1, bot, KillScore.T_HEADSHOT | KillScore.T_MID_AIR | KillScore.T_ROPE))
	_expect(Achievements.stat("kills") == 1 and Achievements.stat("headshots") == 1 and Achievements.stat("air_kills") == 1
		and Achievements.stat("rope_kills") == 1 and Achievements.stat("long_shots") == 0, "your kill counts, with what was special about it")
	_expect(_announced == ["first_blood"] and Achievements.done("first_blood") and not Achievements.locked("hat:party"),
		"the first kill completes First Blood and unlocks the party hat")
	Match.kill_scored.emit(_kill(1, bot, KillScore.T_LONG | KillScore.T_AIR_SHOT, 1))
	Match.kill_scored.emit(_kill(1, bot, KillScore.T_FLYING_KICK, 2))
	_expect(Achievements.stat("doubles") == 1 and Achievements.stat("triples") == 1 and Achievements.stat("trickshots") == 1,
		"a second kill in a run is a double, a third a triple; a long shot on a target in the air is a trickshot (%d)" % Achievements.stat("trickshots"))
	_expect(Achievements.stat("kicks") == 1 and Achievements.stat("flying_kicks") == 1, "a flying kick is a kick too")
	Match.player_died.emit(1, bot)
	Match.player_died.emit(bot, 1)
	_expect(Achievements.stat("deaths") == 1, "your deaths count, not the bot's")
	_announced.clear()
	Achievements.add("headshots", 8)
	_expect(_announced.is_empty() and Achievements.locked("face:monocle"), "9 headshots: Sharp Eye is not done yet")
	Achievements.add("headshots")
	Achievements.add("headshots")
	_expect(_announced == ["headshots_10"] and not Achievements.locked("face:monocle"), "the 10th completes it, once")

	print("  matches")
	Match.match_over.emit([{"id": 1, "kills": 3, "deaths": 1}])
	_expect(Achievements.stat("matches") == 0, "a match alone is no match")
	Match.match_over.emit([{"id": 1, "kills": 3, "deaths": 1}, {"id": bot, "kills": 1, "deaths": 3}])
	_expect(Achievements.stat("matches") == 1 and Achievements.stat("wins") == 1, "top of the table: a match and a win")
	Match.match_over.emit([{"id": bot, "kills": 3, "deaths": 1}, {"id": 1, "kills": 1, "deaths": 3}])
	_expect(Achievements.stat("matches") == 2 and Achievements.stat("wins") == 1, "second place: a match, no win")
	Match.match_over.emit([{"id": bot, "kills": 9, "deaths": 1, "team": 0, "team_won": true}, {"id": 1, "kills": 0, "deaths": 3, "team": 0, "team_won": true}])
	_expect(Achievements.stat("wins") == 2, "on the winning team: a win, wherever you are in the table")

	print("  races")
	Net.match_settings["map"] = "rooftop_run"
	Race.progress = {1: {"cp": 3, "finish": 41.5, "resets": 0, "time": 41.5}, bot: {"cp": 2, "finish": -1.0, "resets": 1, "time": 0.0}}
	Race.gate_passed.emit(1, 2, 20.0, false)
	_expect(Achievements.stat("races") == 0, "a gate is not the finish")
	Race.gate_passed.emit(bot, 3, 30.0, true)
	_expect(Achievements.stat("races") == 0, "a bot's finish is not yours")
	Race.gate_passed.emit(1, 3, 41.5, true)
	_expect(Achievements.stat("races") == 1 and Achievements.stat("clean_races") == 1 and Achievements.stat("race_wins") == 1 and Achievements.stat("courses") == 1,
		"first over the line with no resets: a race, a clean run, a win and a course")
	Race.progress[1]["resets"] = 2
	Race.progress[bot]["finish"] = 30.0
	Race.gate_passed.emit(1, 3, 41.5, true)
	_expect(Achievements.stat("races") == 2 and Achievements.stat("clean_races") == 1 and Achievements.stat("race_wins") == 1 and Achievements.stat("courses") == 1,
		"second, after resets, on the same course: only the race counts")
	_expect(Achievements.stat("bronze_medals") == 1 and Achievements.stat("gold_medals") == 1 and is_equal_approx(Achievements.best_time("rooftop_run"), 41.5),
		"a time under gold is a bronze, a silver and a gold medal, each once, and your best time")
	Net.match_settings["map"] = "foundry"
	Race.gate_passed.emit(1, 3, 90.0, true)
	Race.gate_passed.emit(1, 3, 95.0, true)
	_expect(Achievements.stat("bronze_medals") == 2 and Achievements.stat("silver_medals") == 1 and Achievements.stat("gold_medals") == 1
		and is_equal_approx(Achievements.best_time("foundry"), 90.0), "a slower run on another course: bronze only, and the quicker time is kept")
	_expect(Achievements.medal("foundry", 74.0) == 2 and Achievements.medal("foundry", 74.01) == 1 and Achievements.medal("foundry", 200.0) == -1
		and Achievements.medal("nowhere", 1.0) == -1, "medal times are to beat or match")
	var in_order := true
	for course in Achievements.MEDALS:
		var t: Array = Achievements.MEDALS[course]
		in_order = in_order and Maps.game_of(course) == "race" and t[0] > t[1] and t[1] > t[2] and t[2] > 0.0
	_expect(in_order and Achievements.MEDALS.size() == Maps.ids().filter(func(id): return Maps.game_of(id) == "race").size(),
		"every race course has bronze, silver and gold times, each quicker than the last")
	Race.progress = {}
	Net.match_settings["map"] = "construction_site"

	print("  weapons, streaks and feats")
	var before := Achievements.stat("sidearm_kills")
	for weapon in ["shotgun", "rifle", "bolt_action", "rocket_launcher", "sword", "kick", "shotgun"]:
		var k := _kill(1, bot, 0)
		k.weapon = weapon
		Match.kill_scored.emit(k)
	_expect(Achievements.stat("sidearm_kills") == before and Achievements.stat("shotgun_kills") == 2 and Achievements.stat("rifle_kills") == 1
		and Achievements.stat("marksman_kills") == 1 and Achievements.stat("explosive_kills") == 1, "a kill counts for its weapon's group")
	_expect(Achievements.stat("weapons_used") == 6, "six different weapons so far: a kick is not one, and a weapon counts once (%d)" % Achievements.stat("weapons_used"))
	_expect(Achievements.stat("streaks_5") == 1 and Achievements.stat("streaks_10") == 0, "that was 7 kills without dying: On a Roll")
	for i in 3:
		Match.kill_scored.emit(_kill(1, bot, 0))
	_expect(Achievements.stat("streaks_10") == 1 and not Achievements.locked("card:inferno"), "10 without dying unlocks the Inferno card")
	var revenges := Achievements.stat("revenges")
	Match.death_cause[1] = ""
	Match.player_died.emit(1, bot)
	for i in 4:
		Match.kill_scored.emit(_kill(1, bot, 0))
	_expect(Achievements.stat("streaks_5") == 1 and Achievements.stat("revenges") == revenges + 1, "dying starts the count again; killing who killed you is revenge, once")
	var big := _kill(1, bot, 0, 3)
	big.merge({"score": 420, "distance": 104.0, "speed": 26.0}, true)
	Match.kill_log = [big]
	Match.kill_scored.emit(big)
	Match.kill_log = []
	_expect(Achievements.stat("big_kills") == 1 and Achievements.stat("far_kills") == 1 and Achievements.stat("very_far_kills") == 1
		and Achievements.stat("sonic_kills") == 1 and Achievements.stat("quads") == 1 and Achievements.stat("first_kills") == 1,
		"a 420 point quad kill from 104 m at 26 m/s, first of the match: all of those count")
	var deaths := Achievements.stat("deaths")
	Match.death_cause[1] = "fell"
	Match.player_died.emit(1, 0)
	Match.death_cause[1] = ""
	Match.player_died.emit(1, 1)
	_expect(Achievements.stat("deaths") == deaths + 2 and Achievements.stat("falls") == 1 and Achievements.stat("self_kills") == 1, "a fall and an own goal are deaths of their own kind")

	print("  modes")
	var wins := Achievements.stat("wins")
	var mine := {"id": 1, "kills": 6, "deaths": 0}
	var theirs := {"id": bot, "kills": 5, "deaths": 6}
	Match.match_over.emit([mine, theirs])
	_expect(Achievements.stat("wins") == wins + 1 and Achievements.stat("close_wins") == 1 and Achievements.stat("flawless_wins") == 1,
		"6 kills to 5 with no deaths: a win by one, and a flawless one")
	_expect(Achievements.stat("expert_wins") == 0 and Achievements.stat("online_matches") == 0, "a Normal bot, offline: no more than that")
	var expert := Net.add_bot(3)
	Net.match_settings["mode"] = "gungame"
	Match.match_over.emit([mine, {"id": expert, "kills": 2, "deaths": 6}, theirs])
	Net.match_settings["mode"] = "killcam"
	Match.match_over.emit([mine, theirs])
	Net.match_settings["mode"] = "golden"
	Match.match_over.emit([mine, theirs])
	Match.match_over.emit([theirs, mine])
	Net.match_settings["mode"] = ""
	_expect(Achievements.stat("gun_game_wins") == 1 and Achievements.stat("killcam_wins") == 1 and Achievements.stat("golden_gun_wins") == 1,
		"a win counts for its mode (a loss does not)")
	_expect(Achievements.stat("close_wins") == 2 and Achievements.stat("expert_wins") == 3, "by one kill in Golden Gun too; and all three were against an Expert bot")
	var team_wins := Achievements.stat("team_wins")
	Match.match_over.emit([{"id": bot, "kills": 9, "deaths": 1, "team": 0, "team_won": true}, {"id": 1, "kills": 0, "deaths": 3, "team": 0, "team_won": true}])
	_expect(Achievements.stat("team_wins") == team_wins + 1 and Achievements.stat("close_wins") == 2, "a team's win is a team win")
	Net.is_online = true
	Match.match_over.emit([theirs, mine])
	_expect(Achievements.stat("online_matches") == 0, "online with only bots is not company")
	for id in [2, 3, 4]:
		Net.players[id] = {"name": "Guest %d" % id, "color": id, "character": "needle", "weapon": "pistol"}
	Match.match_over.emit([theirs, mine])
	_expect(Achievements.stat("online_matches") == 1 and Achievements.stat("hosted") == 1, "four people in your lobby: an online match, and one you hosted")
	for id in [2, 3, 4]:
		Net.players.erase(id)
	Net.is_online = false
	Teams.event.emit("bomb_planted", 0, 1)
	Teams.event.emit("bomb_planted", 0, bot)
	Teams.event.emit("bomb_defused", 1, 1)
	Teams.event.emit("flag_captured", 0, 1)
	Teams.event.emit("flag_taken", 0, 1)
	_expect(Achievements.stat("plants") == 1 and Achievements.stat("defuses") == 1 and Achievements.stat("captures") == 1, "your plants, defuses and captures count")

	print("  the page's tabs")
	var kinds: Array = Achievements.GROUPS.map(func(group): return group[0])
	_expect(Achievements.LIST.all(func(a): return a.get("group", "") in kinds), "every achievement has a kind: %s" % ", ".join(kinds))
	var counted := 0
	var each_has_some := true
	for kind in kinds:
		var of_kind: Array = AchievementsPanel.shown(kind)
		counted += of_kind.size()
		each_has_some = each_has_some and of_kind.size() >= 4 and of_kind.all(func(a): return a.group == kind)
	_expect(each_has_some and counted == Achievements.LIST.size() and AchievementsPanel.shown("all").size() == Achievements.LIST.size(),
		"each tab shows its own kind, and between them every achievement once")
	var by_id := func(id: String) -> String: return Achievements.by_id(id).group
	_expect(by_id.call("headshots_10") == "combat" and by_id.call("wall_10") == "movement" and by_id.call("gun_game_3") == "matches"
		and by_id.call("medal_gold") == "races" and by_id.call("falls_10") == "misc", "headshots are Combat, wall-running Movement, Gun Game wins Matches, medals Races, falls Misc")
	var page := AchievementsPanel.new()
	add_child(page)
	var bar := AchievementsPanel.tabs(page)
	add_child(bar)
	_expect(bar.get_child_count() == kinds.size() + 1 and (bar.get_child(0) as Button).text.begins_with("All") and (bar.get_child(4) as Button).text.begins_with("Races")
		and ("/ %d" % AchievementsPanel.shown("races").size()) in (bar.get_child(4) as Button).text, "a tab for All and one for each kind, with how many are done (%s)" % (bar.get_child(4) as Button).text)
	(bar.get_child(4) as Button).pressed.emit()
	_expect(AchievementsPanel.category == "races" and page.get_child_count() == AchievementsPanel.shown("races").size()
		and page.get_child(0).name == StringName(AchievementsPanel.shown("races")[0].id), "pressing Races shows only the race achievements")
	(bar.get_child(0) as Button).pressed.emit()
	_expect(page.get_child_count() == Achievements.LIST.size(), "and All shows them all again")
	_expect(page.find_child("streak_10", false, false).find_children("", "Control", true, false).any(func(c): return c is AchievementsPanel.Thumb),
		"an achievement's card shows the calling card or icon it unlocks")
	AchievementsPanel.category = "all"

	print("  tracking, level and the Profile page")
	var saved_tracked: Array = Settings.tracked_achievements.duplicate()
	Settings.tracked_achievements = []
	var xp := Achievements.stat("xp")
	Match.kill_scored.emit(_kill(1, bot, 0))
	_expect(Achievements.stat("xp") == xp + 100, "a kill adds its killcam score as experience (%d -> %d)" % [xp, Achievements.stat("xp")])
	_expect(PlayerLevel.of(0) == {"level": 1, "into": 0, "need": PlayerLevel.FIRST} and PlayerLevel.of(PlayerLevel.FIRST).level == 2
		and PlayerLevel.of(PlayerLevel.FIRST + PlayerLevel.need(2) + 5) == {"level": 3, "into": 5, "need": PlayerLevel.need(3)},
		"levels: each takes a little more experience than the last")
	var near := Achievements.closest()
	_expect(near.size() == Achievements.MAX_TRACKED and near.all(func(a): return not Achievements.done(a.id))
		and Achievements.fraction(near[0]) >= Achievements.fraction(near[1]) and Achievements.fraction(near[1]) >= Achievements.fraction(near[2]),
		"the Profile shows the three nearest to done, nearest first")
	_expect(not Achievements.toggle_tracked("first_blood") and Achievements.tracked().is_empty(), "a done achievement can't be tracked")
	page.toggle_track("kills_1000")
	_expect(Achievements.closest()[0].id == "kills_1000" and page.find_child("kills_1000", false, false).has_meta("tracked"),
		"a tracked one comes first on the Profile, and its card says TRACKED")
	for id in ["deaths_200", "race_10", "rope_100"]:
		Achievements.toggle_tracked(id)
	_expect(Achievements.tracked().map(func(a): return a.id) == ["deaths_200", "race_10", "rope_100"],
		"tracking a fourth lets the oldest go (%s)" % [Settings.tracked_achievements])
	Achievements.toggle_tracked("race_10")
	_expect(not Achievements.is_tracked("race_10") and Achievements.tracked().size() == 2, "tracking one again stops tracking it")
	var latest := Achievements.most_recent()
	_expect(not latest.is_empty() and Achievements.done(latest.id), "the most recent achievement is a done one (%s)" % latest.get("name", ""))
	var profile := ProfilePage.new()
	add_child(profile)
	var stats := profile.find_child("stats", true, false)
	_expect(stats.get_child_count() == ProfilePage.PER_PAGE and str(stats.get_child(0).name) == "Kills"
		and (stats.get_child(0).find_child("value", true, false) as Label).text == str(Achievements.stat("kills")),
		"the Profile's first stat is your kills")
	profile.turn(-1)
	_expect(ProfilePage.page == ProfilePage.pages() - 1 and (profile.find_child("page", true, false) as Label).text == "%d/%d" % [ProfilePage.pages(), ProfilePage.pages()],
		"the stats pages wrap round")
	profile.turn(1)
	_expect(profile.find_child("closest", true, false).get_child(0).name == StringName("deaths_200"), "the Profile lists the tracked ones first")
	_expect(ProfilePage.time_text(3 * 3600 + 21 * 60) == "3 hours 21 minutes" and ProfilePage.time_text(60) == "1 minute", "time played reads in hours and minutes")
	profile.queue_free()
	Settings.tracked_achievements = saved_tracked
	Settings.save_settings()
	page.queue_free()
	bar.queue_free()

	print("  the Character Creator")
	var creator: Node = load("res://game/ui/character_creator.gd").new("")
	add_child(creator)
	creator.set_part("whole", "ninja")
	creator.set_part("hat", "top_hat")
	_expect(not creator.can_save() and "Ninja" in creator.locked_note() and "Wall Crawler" in creator.status.text,
		"a locked body can be tried on, and the creator says what it needs (%s)" % creator.status.text)
	_expect(creator.save() == "" and Settings.custom_characters.is_empty(), "but it can't be saved")
	creator.open_list("whole")
	var names := []
	for i in creator._list.item_count:
		names.append(creator._list.get_item_text(i))
	creator._list.hide()
	_expect("Ninja  (locked)" in names and "Frog" in names, "the list marks the locked ones")
	creator.open_palette("p")
	_expect((creator._palette_grid.find_child("pick_gold", false, false) as Button).disabled
		and not (creator._palette_grid.find_child("pick_red", false, false) as Button).disabled, "a locked paint is greyed out in the palette")
	creator._palette.hide()
	Achievements.add("wall_kills", 10)
	creator.set_part("hat", "cap")
	_expect(creator.can_save() and creator.locked_note() == "", "10 wall-run kills later the ninja can be saved")
	var clean := true
	for i in 40:
		creator.randomize_parts()
		clean = clean and creator.can_save()
	_expect(clean, "Randomize only uses what you have")
	creator.queue_free()

	print("  yours to keep")
	Settings.custom_characters = ["custom:n=King|l=needle|t=needle|h=needle|hat=crown|back=cape.gold"]
	_expect(Achievements.locked("hat:crown") and Achievements.locked("paint:gold"), "before: the crown and gold paint are locked")
	Achievements.keep_saved()
	_expect(not Achievements.locked("hat:crown") and not Achievements.locked("paint:gold") and Achievements.locked("hat:halo"),
		"what a saved character wears is unlocked, and nothing else")
	Achievements.unlock_all = true
	_expect(not Achievements.locked("hat:halo") and Achievements.locked_in(CustomCharacter.parse("custom:n=x|l=zombie|t=imp|h=yeti|hat=halo")).is_empty(),
		"--unlock-all: nothing is locked")
	Achievements.unlock_all = false

	print("  the file")
	var kills := Achievements.stat("kills")
	Achievements._file = TEST_FILE
	Achievements.save()
	Settings.custom_characters = []
	Achievements._load()
	_expect(Achievements.stat("kills") == kills and Achievements.stat("wall_kills") == 10 and not Achievements.locked("hat:crown")
		and not Achievements.locked("part:ninja") and Achievements._sets.courses.has("rooftop_run"), "counts, kept items and courses come back from the file")
	_expect(Achievements.stat("gold_medals") == 1 and Achievements.stat("bronze_medals") == 2 and Achievements.stat("weapons_used") == 6
		and is_equal_approx(Achievements.best_time("foundry"), 90.0), "and so do the medals, the weapons you have used and your best times")
	_announced.clear()
	Achievements.add("deaths")
	_expect(_announced.is_empty(), "and nothing already done is announced again")
	# Another copy of the game on this PC counted 5 kills and saved while this one was open.
	var other := ConfigFile.new()
	other.load(TEST_FILE)
	other.set_value("stats", "kills", kills + 5)
	other.save(TEST_FILE)
	Achievements.add("kills", 2)
	Achievements.save()
	other.load(TEST_FILE)
	_expect(Achievements.stat("kills") == kills + 7 and int(other.get_value("stats", "kills", 0)) == kills + 7,
		"two copies of the game add to the same file instead of writing over each other (%d)" % Achievements.stat("kills"))
	Achievements.save()
	_expect(Achievements.stat("kills") == kills + 7, "and saving twice counts nothing twice")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_FILE))

	print("  The toast is small and takes the corner the HUD leaves free")
	var biggest := Vector2.ZERO
	for a in Achievements.LIST:
		var toast := Achievements.make_toast(a)
		add_child(toast)
		biggest = biggest.max(toast.get_combined_minimum_size())
		toast.free()
	_expect(biggest.x <= Achievements.TOAST_SIZE.x and biggest.y <= Achievements.TOAST_SIZE.y,
		"no achievement's toast is bigger than %s (the biggest is %s)" % [Achievements.TOAST_SIZE, biggest])
	var saved_corner: String = Settings.hud.feed_corner
	Settings.hud.feed_corner = "right"
	_expect(Achievements.toast_on_left(), "it sits top left, across from the kill feed")
	Settings.hud.feed_corner = "left"
	_expect(not Achievements.toast_on_left(), "top right when Settings moves the feed to the left")
	Settings.hud.feed_corner = saved_corner
	Race.active = true
	_expect(not Achievements.toast_on_left(), "and top right in a race, where the standings are down the left")
	Race.active = false

	print("  The debug menu completes, unlocks and resets")
	Achievements.reset_for_test()
	Achievements._file = TEST_FILE
	Achievements.complete("kills_100")
	_expect(Achievements.done("kills_100") and Achievements.stat("kills") == 100 and not Achievements.done("kills_500"),
		"completing an achievement brings its count to the goal, and no further")
	_expect(Achievements._toasts.size() == 1 and Achievements._toasts[0].id == "kills_100", "with its toast")
	Achievements.complete("medal_gold_4")
	_expect(Achievements.done("medal_gold_4") and Achievements.done("medal_silver") and Achievements.done("medal_bronze"),
		"completing the gold medals gives the silver and bronze ones too")
	_expect(Achievements.MEDALS.keys().all(func(c): return Achievements.medal(c, Achievements.best_time(c)) == 2),
		"with a best time on each course that earns the medal")
	Achievements._load()
	_expect(Achievements.done("kills_100") and Achievements.done("medal_gold_4") and Achievements.stat("gold_medals") == 4,
		"and they are still done after reading the file back")
	Achievements.complete_all()
	var all_items := Achievements.item_counts()
	_expect(Achievements.done_count() == Achievements.LIST.size() and all_items[0] == all_items[1],
		"completing everything finishes all %d achievements and unlocks all %d rewards" % [Achievements.LIST.size(), all_items[1]])
	_expect(Achievements._toasts.is_empty(), "without a queue of toasts")
	Achievements._load()
	_expect(Achievements.done_count() == Achievements.LIST.size(), "and all of them are still done after reading the file back (%d)" % Achievements.done_count())
	var saved_card := Settings.calling_card
	var saved_icon := Settings.icon
	Settings.calling_card = "frostbite"
	Settings.icon = "crown"
	_expect(not Achievements.wear_unlocked() and Settings.calling_card == "frostbite", "a card and icon you have unlocked stay on")
	Achievements.reset_progress()
	_expect(Achievements.done_count() == 0 and Achievements.item_counts()[0] == 0 and Achievements.best_time("rooftop_run") == 0.0,
		"resetting wipes every count, unlock and best time")
	_expect(Achievements.wear_unlocked() and Settings.calling_card == CallingCard.DEFAULT_CARD and Settings.icon == CallingCard.DEFAULT_ICON,
		"and a calling card and icon that are locked again go back to the free ones")
	Achievements._load()
	_expect(Achievements.done_count() == 0 and Achievements.item_counts()[0] == 0, "the file is wiped too")
	Achievements.unlock_items(false)
	_expect(not Achievements.locked("hat:crown") and not Achievements.locked("paint:gold") and Achievements.locked("card:frostbite")
		and Achievements.done_count() == 0, "unlocking cosmetics gives the creator's items, with no achievement done and no card")
	Achievements.unlock_items(true)
	_expect(not Achievements.locked("card:frostbite") and not Achievements.locked("icon:crown") and Achievements.done_count() == 0,
		"unlocking cards and icons gives those")
	Achievements._load()
	_expect(Achievements.item_counts()[0] == Achievements.item_counts()[1], "and the unlocks are kept in the file")
	Achievements.reset_progress()
	_expect(Achievements.item_counts()[0] == 0, "a reset takes those away as well")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_FILE))
	Settings.calling_card = saved_card
	Settings.icon = saved_icon

	Achievements.reset_for_test()
	Settings.custom_characters.assign(saved_characters)
	Settings.character = saved_pick
	Net.leave()
	if _fails.is_empty():
		print("PASS: every check passed")
	else:
		print("FAIL:\n  " + "\n  ".join(_fails))
	get_tree().quit(1 if not _fails.is_empty() else 0)


func _kill(killer: int, victim: int, tags: int, streak: int = 0) -> Dictionary:
	return {"seq": 1, "score": 100, "tags": tags, "streak": streak, "distance": 10.0, "weapon": "pistol",
		"speed": 5.0, "target_speed": 5.0, "flick": 0.0, "killer": killer, "victim": victim}


func _expect(ok: bool, what: String) -> void:
	print("    %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)
