# Development guide

## One-time setup (about 10 minutes)

1. **Install Godot 4.7.2**, the standard version (not ".NET"), from
   https://godotengine.org/download. On Windows it is a single .exe; put it somewhere
   permanent such as `C:\Godot\`.
2. **Get the project.** Clone this repository (GitHub Desktop is the easiest way), or
   download it as a ZIP from GitHub and unzip it.
3. **Open it in Godot.** Start Godot, click **Import**, choose `project.godot` in this
   folder, then **Import & Edit**. The first import takes a minute.
4. Press **F5** to play.

## Running several copies on one PC

This is the quickest way to test multiplayer. From the project folder:

- **Windows:** first tell the script where Godot is (once per Command Prompt window):
  ```
  set GODOT=C:\Godot\Godot_v4.7.2-stable_win64.exe
  tools\run_local.bat 3
  ```
  The number is how many copies (2 to 5). The first copy hosts and the rest join it
  automatically, in a grid of windows.
- **Linux/macOS:** `GODOT=/path/to/godot tools/run_local.sh 3`

Click inside a window to control that copy. Esc frees the mouse.

You can also do it by hand: run the game twice, choose **Multiplayer → Create lobby** in
one and **Multiplayer → Join lobby** with address `127.0.0.1` in the other.

## Playing with a friend

**Until Steam is wired in**, connecting is direct (no server). The host's lobby shows a
**lobby code** (like `ABCD-EFGH`) that stands for the host's address; friends type it into
the Join box on the Multiplayer page. An IP address works there too.

- **Same home network:** host with **Create lobby**. If the router can't be opened, the
  lobby's code stands for your local address (for example `192.168.1.20`, shown beside it).
  Your friend types the code (or that address) into **Join lobby**.
- **Over the internet:** when you create a lobby, the game asks your router to open
  UDP port 24680 (UPnP) and the lobby shows a code for your public address with a **Copy code**
  button. Send that to friends; they type it into **Join lobby**. If the lobby says the
  router would not open the port, forward UDP 24680 to your PC by hand in the router's
  settings (or UPnP is switched off there, or your provider shares one address between
  homes, which no router setting fixes).

Windows may ask whether to allow Godot through the firewall the first time you host.
Allow it on private networks.

**With Steam (coming next):** create a lobby and invite friends through Steam; no
addresses or router settings. Everyone needs Steam running.

## Automated tests

`tests/run_all.sh` runs everything in about 4 minutes on a 4-core machine (needs bash
and python3, so on Windows use Git Bash or WSL; I run these on every change anyway).
The quick checks run side by side (`JOBS=8 tests/run_all.sh` for more at once), and the
ones that only step physics run on a fixed game clock (Godot's `--fixed-fps 60`), so
they play out as fast as the machine allows instead of in real time. Their logs go to
`tests/out/check_<name>.log`.

Quick checks:

- movement (`tests/movement_test.gd`): speeds, stopping, jump height, momentum in the air;
- movement variants (`tests/movement_variant_test.gd`): Variant B is the only movement
  and the default (see `MovementTuning.VARIANTS`; Classic is retired and an old "classic"
  pick means B), every player gets their own copy, Practice and Vs Bots start you and
  every bot on it, and no movement switch is left in the menus;
- Variant B movement (`tests/movement_b_test.gd`), against the plain numbers: the same
  running and jump, legs tucked in the air, Space for flips and the jetpack (not before
  it has been held a moment in the air), Ctrl dives,
  back-slides and crouches, the wall sit, the air brake and the speed limit;
- robots (`tests/robot_test.gd`), for every character: the model files hold every bone
  and clip, the skeletons match, each movement state plays the right animation, the
  poses fit the hitbox, and every gun has its muzzle bone and its own clips;
- the body on the grappling hook's rope (`tests/rope_swing_test.gd`, with `--fixed-fps 60`):
  the slack phase is untouched; tight, the body leans along the rope
  with the legs trailing and the gun down; the jolt grows with the slack; the legs follow
  the hips after a change of direction; a shot brings the gun up at once; the hips face
  the swing and the chest the aim; steering works the legs; letting go on the way up
  rolls the body (whichever news arrives first, and a shot hurries it); your own body
  leans less; a blade hangs point down, a cape streams; killcam bodies are told the rope;
  dived into the rope, the body zips in line with the way it is going, corkscrews as the
  rope pulls tight (the way it was steered; a small tug only twists it; not your own body
  in first person), flips over the top on arriving, rolls or dives on when let go, and
  turns to face the hook when dragged on its belly;
- diving into the rope (`tests/dive_rope_test.gd`, with `--fixed-fps 60`): in a dive as
  the rope pulls tight (dived after firing, or fired in the dive) it is the rope's move,
  with the rope's steering and jump off, until you arrive; let go before that and the dive
  carries on into its roll or onto your belly; a low hook with the key held drags you on
  your belly; a near hook, or a rope caught without a dive, is just a swing;
- ragdolls (`tests/ragdoll_test.gd`, with `--fixed-fps 60`), for every robot and two
  custom characters: thrown over a floor they settle above it, at rest, with elbows and
  knees bent the right way; each lasts 10 s and dissolves, a respawn or the player
  leaving changes nothing, at most 8 at once, none with the setting off;
- weapons (`tests/weapon_test.gd`): damage and falloff, magazine and shell-by-shell
  reloads, melee wind-ups and shoves;
- the air cannon (`tests/air_cannon_test.gd`): no damage to anyone or anything, no ammo
  or reload, full charge in 1.5 s, a charged blast shoves far harder than a tap (and a
  tap never hurts anyone on a wall), and the cone takes in only who is in front, within
  its angle and reach and in sight;
- sounds (`tests/audio_test.gd`): every sound file loads and every sound the code asks
  for exists;
- the portrait banner (`tests/portrait_test.gd`, with `--fixed-fps 60`): the 3D is drawn
  at the screen's own size (twice that on High) with your anti-aliasing picks, whatever
  the render scale (the results screen's killcam fills the window's pixels at the game's
  own render scale); every character's head and the ring under it fit the frame at three
  shapes, and the name ends short of the head; every weapon goes through its three holds
  and its flourish; a drag turns the character and it turns back the short way; another
  character builds in, a new gun or colour does not;
- map scenes (`tests/map_scene_test.gd`): every map loads and builds, blocks, resize
  handles, race gates, bot routes, hazards, and the map lists keep race and arena maps apart;
- tube collision (`tests/tube_collision_test.gd`): a tube block collides as the ring you
  see, flat side for flat side, not as the box round it: nothing to hit in its hole or
  past its flat sides where the box's corners were, its ring all round, a tube with no
  hole as a cylinder, and no ground in the hole of one that moves;
- the Testing Grounds courses and the Construction Site and Office routes: a scripted
  player runs each one (`tests/course_test.gd`, `tests/site_test.gd`,
  `tests/office_test.gd`), plus spawn points and bot navigation; the other arenas'
  spawns and navigation (`tests/arena_maps_test.gd`). To run one route and print what
  the player did: `COURSE_ONLY="fence" COURSE_DEBUG="fence" godot --headless --fixed-fps 60
  --path . --script tests/site_test.gd`;
- breakable walls and floors (`tests/destruction_test.gd`);
- flicker (`tests/map_flicker_test.gd`), on the Castle, Castle 2, Rail Yard, Lost Temple, Neon
  Arcade and Sky Island: no two surfaces of different colours share a plane where both can be seen,
  and no sign lies in the wall behind it. `FLICKER_MAPS=all` tries every map,
  `FLICKER_LIST=40` prints more of what it found;
- Halcyon (`tests/halcyon_test.gd`): spawn points, pickups, the terminal on its dais,
  bot navigation through every room and level, the hull stays sealed, the reactor pit
  kills;
- Cirrus (`tests/cirrus_test.gd`, with `--fixed-fps 60`): spawn points and pickups, the
  pool of arrangements, the clock's timing and sounds, no writing, what crosses the gap,
  a move (riders on an island that stays are carried, those on one that goes die), the
  glass, bots' routes and crossings;
- Sky Island (`tests/sky_island_test.gd`): its moving parts, spawns and pickups; the
  bots' crossings join every island to every other; the navigation mesh's frame
  (`MapRoot.to_nav`); and the crossings themselves, done the way a bot does them, with
  the clock stopped and with the islands and pads on the move;
- the map terminal (`tests/terminal_test.gd`): a 2 s hold in range fires its event,
  what cancels a hold, no use during the event or cooldown, one player at a time;
- low gravity (`tests/gravity_test.gd`): the multiplier's schedule, jump heights,
  rockets and grenades fly the same path, the centrifuge slows, and gravity always
  comes back to 1.0; gravity zones: 1.0 inside and 0.4 outside, eased over a second,
  multiplied with an event's, never touching projectiles, gone with the map;
- tractor-beam lifts (`tests/lift_test.gd`, with `--fixed-fps 60`): 9 m/s, the hover at
  the top, leaving sideways at any height, what the beam leaves alone;
- Haunted House (`tests/haunted_house_test.gd`): the Haunting's clock (the order of
  layouts comes from its state alone, never one layout twice running, every prop where the
  clock says however it got there), and in each of the four layouts every spawn point
  clear and on a floor, every pickup clear, and on the bots' navigation mesh every spawn
  point and pickup on both floors; doorways never solid while they come and go, someone
  in a doorway when it closes put out on the nearer side, someone caught in furniture put
  beside it, and a new match putting the house back in layout 0. It is held to
  `tests/map_flicker_test.gd` too;
- Empyrean Tower (`tests/empyrean_test.gd`): no two faces that would flicker, the river
  of magic clear of everything in the shaft, how it asks to be drawn, no bounds and the burn layer, the gravity
  zones, force fields that stop nothing, spawn points (none sees the altar) and pickups,
  the altar and the ring gates (scenery) and the lifts, only the glass breaks, and on the bots'
  navigation mesh every tier from its neighbours, every storey, the docking ring and the
  altar from six directions; and in a real Practice match
  (`tests/empyrean_play_test.gd`): gravity through a doorway, a lift ride, the magic
  answering to you (stirred when you stand in it, at rest while you sneak, never through a
  wall, through glass), walking through a ring gate, and the three deaths (the core, the
  burn layer, not flying off);
- menu layout (`tests/ui_layout_test.gd`): builds every menu page (main menu and its
  pages, the four Settings tabs, lobby, results, pause, loadout) at 18 window sizes
  and shapes (960x540 to 4K, 16:10, 21:9, 32:9, 4:3, 5:4, tall and tiny windows) and
  fails if any button, text box or slider is off screen, if a robot or weapon button
  cuts its name short, or if the death screen's two columns do not fit;
- controls rebinding (`tests/controls_check.gd`: defaults, conflicts, save and load, the
  Controls tab, and saved bindings brought up to date: the glide to Alt, the mobility button
  to middle mouse, alt fire onto right mouse unless it is taken; alt fire's weapon data and
  its held flag surviving a snapshot), the main menu's mode switch
  (`tests/menu_mode_test.gd`), Deathmatch maps, pickups and inventory
  (`tests/deathmatch_test.gd`), and the debug menu and target dummies in a real
  Practice match (`tests/debug_test.gd`);
- killcams (`tests/killcam_test.gd`): the kill scores, their breakdown into parts that
  add up to them, and the pick of the best three,
  what travels with a death, recording and blending frames, a replay from the killer's
  eyes (camera, arms, the victim, the shot, slow motion), the best kills playing
  fullscreen after a match (counting down to the best), the results page with
  them listed still fits 1600x900, and a killcam saved as a video is a Motion JPEG
  AVI with every frame and an index, as long as the clip plays;
- killcams that match the match (`tests/killcam_sync_test.gd`): the replay looks exactly
  where each of the killer's shots was aimed, from where it was fired (easing onto a lone
  shot, shot to shot through a burst, never swinging past a flick), a target the killer
  hit is moved in time to where the hits say, and on the Construction Site the crane's
  load, the signs on its jib, its rope and a wall shot through since are drawn as they
  were, while their collision stays the match's, and drawn live again afterwards;
- spectating (`tests/spectator_test.gd`): in a Vs Bots match you switch to spectating and
  back; a spectator has no robot, score or scoreboard row, the bots play on, and the free
  camera flies through the floor, faster with Sprint, the way it looks;
- respawn visibility (`tests/respawn_visible_test.gd`): another player who dies and comes
  back is shown again (drawn and solid) whether their first snapshot from the new life
  or the news of the respawn gets here first, when killed again before any snapshot
  from the new life, after a new robot or gun while waiting to see them back, and
  through the safety net (alive, hidden over a second, snapshots coming: shown anyway);
- the mobility slot and the jetpack (`tests/mobility_test.gd`), in a real Practice match:
  the grappling hook is the only tool (an old pick of one that is gone is the hook); no
  jetpack by default (holding Space in mid-air is just a jump); with the lobby's jetpack
  on, it is on Space (a tap is a plain jump and burns nothing, nor does holding
  it through the jump for less than `space_hold_time`; held on in mid-air it fires,
  lifts you and burns fuel that refills; held in a fall it catches you); bots have it
  while it is on; a race has the grapple and never the jetpack;
- the game boots into practice mode on every map without script errors.

- the railgun (`tests/railgun_test.gd`), in a real Practice match: through a wall a pistol
  round stops at, its slug kills a dummy outright, its tracer runs its whole range and it
  never hurts the one who fired it (`tests/destruction_test.gd` checks that a line through
  walls finds every breakable piece on it);
- the grappling hook (`tests/grappling_hook_test.gd`), in a real Practice match: it is the
  only hook (a saved `grapple2`, the old Grappling Hook 2's id, becomes it); nothing pulls
  while the hook flies, it takes the distance at its speed to arrive, bites with slack,
  the winch takes it in, the rope pulls tight with a yank and
  then pulls; a miss, a hook called back, hooking a bot; the hook's way back
  (it catches a slab put in its way while the button is held, after a miss or a new
  press, not with the button up nor after a jump off the rope); in first person the
  rope starts on the arm's wrist as drawn while moving and turning; the rope drawn is as
  long as the rope out; a copy rebuilt from snapshots (every one, a third lost, two
  thirds lost and late) draws the hook, slack and rope exactly where the player's own
  game had them, a miss and the catch on its way back included; a killcam replay
  between its frames; a race has the same hook;

Networked and bot runs (real time):

- the grappling hook online (`tests/run_hook_sync_test.sh [PLAYERS] [NET_SIM]`): every copy
  fires it on its own on a bad network; every other copy must see each launch, bite,
  pull-tight and release within 30 ms of when it happened and draw the hook within
  15 cm of where its owner's game had it (95% of frames; never 40 cm), in the same
  stage (`tests/check_hook.py`);

- sync (`tests/run_sync_test.sh`): 3 copies on a simulated bad network (100 ms latency,
  60 ms jitter, 10% loss) move on their own; every copy must draw every other player
  within 15 cm of where they really were (95% of frames), with no visible pops, show
  the move they were really doing (`tests/check_anim.py`) as the robot they picked,
  and notice when the host leaves. `SYNC_DEBUG=1 python3 tests/check_sync.py
  tests/out/sync_*.log` prints where and when each pop happened;
- match (`tests/run_match_test.sh`): 3 copies on a laggy network play two matches back
  to back, aiming and shooting on their own: hits land, the match ends at the kill
  target, every copy agrees on the results and on broken walls, new robot and gun
  picks show in the second match, and every copy hears its own gun and the others'
  shots and footsteps;
- bots (`tests/run_bot_test.sh`): a bot of every difficulty finds you and shoots, Expert
  beats Easy on accuracy, the hard bots use the movement set, Rematch works, a
  5-player free-for-all against 4 bots, a sword bot, and your and the bots' sounds;
- spectating online (`tests/run_spectator_test.sh`): a client joins mid-match to spectate;
  it sees both players move, nobody sees it, and it is never on the player list;
- ground slam (`tests/run_slam_test.sh`): a hammer slam from a drop in Practice hits
  the target dummy, and online a client's slam is ruled on by the host, hits the host's
  player and is heard by both;
- respawn visibility online (`tests/run_respawn_visible_test.sh`): a host and two clients
  shoot it out; one client gets every respawn 300 ms late (`--delay-respawn`), behind the
  player's first snapshot from the new life, and both must show every respawned player;
- Halcyon online and with bots (`tests/run_gravity_test.sh`): a client fires the
  terminal on the host, a client across the room cannot, a late joiner is told how far
  along the event is, and bots use the terminal and keep moving in low gravity;
- killcams (`tests/run_killcam_test.sh`): Vs Bots (in game time), the killcam plays each
  time the bot gets you and runs until you respawn, Jump skips it (not in its first 0.75 s),
  with `--manual-respawn` Jump brings you back (and nothing else does), and the results
  screen plays the best kills and saves the best as a video; online, a host and a client on a laggy network each
  watch their killcams, score every kill the same, show each killer their kill's points
  (adding up to its score), pick the same best three and have a clip of each; every
  killcam has the killer's shot aims and records the map's moving parts (`KILLCAM SYNC`
  and `KILLCAM AIM` in the logs);
- Golden Gun (`tests/run_golden_gun_test.sh`): Vs Bots and online, one player holds the
  Golden Gun at a time, whoever kills the holder takes it, every kill with it gives its
  round back, and host and client see the same hand-overs and results;
- Killcam mode (`tests/run_killcam_mode_test.sh`): Vs Bots and online, everyone has the
  anti-materiel rifle (even a client who picked another gun), each player's points are their
  kills' killcam scores plus the #1 killcam bonus, the match ends at the kill that
  reaches the target, the rankings go by points, and host and client agree;
- races (`tests/run_race_test.sh`, in game time): you and 4 bots finish Rooftop Run in
  time order and "Race again" starts another, Easy bots finish, and a hazard, a fall and
  R each send you back. After changing a course, run it on that map:
  `MAPS="foundry" tests/run_race_test.sh`.

The sync, match and bot tests take a map and a player count, for example
`MAP=testing_grounds tests/run_bot_test.sh` or `MAP=office tests/run_sync_test.sh 5 "100,60,10"`.
- breakable walls and floors (`tests/destruction_test.gd`): the arena maps have them and
  race maps none, no spawn stands on floor that can break, an intact wall still collides
  as one box, damage cracks then breaks a piece and a shot then goes through the hole;
  online (`tests/run_break_test.sh`, laggy network) the host shoots the floor out from
  under itself and falls through, a client breaks a wall, a player joining mid-match is
  shown what is broken and every copy agrees; the match test also checks every copy
  ends each match with the same broken pieces;
- Halcyon (`tests/halcyon_test.gd`): 16 or more spawn points, each clear, none in the
  Control Room or in sight of the terminal's dais; the pickups (the heavy weapons up
  high, none in the Control Room); the terminal on its dais and its event; on the bots'
  navigation mesh, every room and level reached from the dais and back, both decks
  joined, and the Control Room entered by each of its six doorways; the dome and the
  floor glass cannot break and nothing gets out of the hull; no lit strip hangs across
  a doorway or in mid-air; no two floors or floor markings of different colours share a
  height where they overlap (that flickers); the reactor pit kills;
- the map terminal (`tests/terminal_test.gd`): one press in range fires its event; a
  press from out of range, or during the event or the cooldown, does nothing, and a key
  kept down does not fire it again; and for a terminal set to need a hold: a 2 s hold
  fires it, letting go, leaving the range and dying cancel and taking damage does not,
  one player at a time;
- achievements (`tests/achievements_test.gd`): every reward is a real item given once;
  your kills, deaths, wins and race finishes are counted and a bot's are not; an
  achievement completes once at its goal and unlocks its items; the creator shows a
  locked item but won't save it, and Randomize keeps to what you have; what a saved
  character wears stays yours; the counts come back from the file, and two copies of
  the game add to it; a kill counts for its weapon's group and each weapon once, kills
  without dying, revenge, the first kill, big, far and fast kills; wins count for their
  mode, by one kill, with no deaths, against an Expert bot, online and hosted; plants,
  defuses and captures; race medals and best times; every achievement has a kind,
  and the page's tabs show each kind's own;
- calling cards (`tests/calling_card_test.gd`): every card and icon has its own id and
  draws, with a glyph or pattern the drawing code knows; the plain ones are free and the rest locked; the picker takes a free one and
  refuses a locked one, saying what it needs; your card goes into the lobby with you,
  a pick there shows at once, a made-up id becomes the plain card, and bots have one;
- your colour (`tests/player_color_test.gd`): the colour you picked is yours when you
  host, a joiner gets theirs unless another player has it, a bot hands its colour over,
  nobody changes mid-match, and the swatch on the robot stage offers the free ones;
- low gravity (`tests/gravity_test.gd`): the multiplier reaches 0.3 and returns to 1.0
  on schedule, a jump reaches about 4 m against about 1.2 m, rockets and grenades fly
  the same path, the centrifuge slows to half speed, and gravity is back at 1.0 when a
  match ends mid-event, when the next starts and when the map is unloaded; online and
  with bots (`tests/run_gravity_test.sh`): a client fires the terminal on the host, a
  client across the room cannot, a late joiner is told how far along the event is, and
  bots use the terminal and keep moving through the low gravity;
- the debug menu and target dummies, in a real Practice match on the Testing Grounds:
  body shots and headshots on a dummy, it goes down and gets back up, god mode, infinite
  ammo, adding and removing bots, changing robot and gun, game speed, and that no cheat
  works online (`tests/debug_test.gd`);
- map scenes: every map loads and builds, every block has a colour, and the resize
  handles move the right face; race maps have gates numbered in order ending in one
  finish, a bot route, hazards and moving parts that move, and the map lists keep race
  maps and arena maps apart (`tests/map_scene_test.gd`);
- races (`tests/run_race_test.sh`, in game time so it plays out the same on a slow
  machine): on every race map you (on autopilot) and 4 Normal bots all finish, in time
  order, and "Race again" starts another; Easy bots finish every map too; a hazard, a
  fall and R each send you back; an online race between a host and a client finishes
  for both and both see the same finishers;
- the game boots into practice mode on every map without script errors;
- bots climb the Construction Site tower to a player standing on a high floor
  (`tests/run_bot_climb_test.sh`);
- a bot of every difficulty finds you and shoots, even Easy hits a player standing still, harder bots hit a moving player more often, the hard bots slide, dive, belly-slide, flip and grapple (and the easier ones never belly-slide), and Rematch starts a new match; a 5-player free-for-all against 4 bots, where every bot shoots, bots fight each other as well as you, the robots alternate, and the rematch keeps all 4 bots (`tests/run_bot_test.sh`);
- a match test: 3 copies on a laggy network play two matches back to back, aiming
  and shooting on their own; checks that hits land, the match ends at the kill target,
  every copy agrees on the results, and "return to lobby, play again" works;
- a sync test: 2 copies on a clean network, then 5 copies on a simulated bad network
  (100 ms latency, 60 ms jitter, 10% packet loss). Each copy moves on its own, and the test
  checks that every copy draws every other player within 15 cm of where they really were
  (95% of frames), with no visible pops, and that everyone notices when the host leaves.
  The 5-copy run fails now and then on a small test machine (five copies sharing four
  processor cores); `SYNC_DEBUG=1 python3 tests/check_sync.py tests/out/sync_*.log` prints
  where and when each pop happened;
- the sync, match and bot tests take a map: `MAP=testing_grounds tests/run_bot_test.sh`.
  `run_all.sh` spreads them over both maps;
- animation sync (`tests/check_anim.py`, part of the sync and match tests): every copy
  shows each other player doing the move they were really doing at that moment, shows
  each held move, and kicks their gun on every shot. The bot test checks the bot's body
  the same way.
- sound effects (`tests/run_audio_test.sh`): every sound file loads and every sound the
  code asks for exists (`tests/audio_test.gd`); in a bot match your own gun, reloads,
  steps and hit markers play, and the bots' shots, impacts and steps play placed in the
  world; online, each copy hears the other's shots and footsteps in the world.
- character sync (same checker): the copies play different robots, and every copy must
  show each player as the robot they picked. In the match test everyone picks again in
  the lobby between matches, and the new picks must show in the next match. The bot
  test checks the bot plays the robot you did not pick, and that with several bots they take turns through the robots starting with the other one.

## Debug menu

Press **F1** (or **`**) in Practice or Vs Bots for testing cheats: god mode, infinite
ammo, no cooldowns, noclip, game speed, teleports, changing robot and gun, adding and
freezing bots, and an FPS readout. It lives in `game/dev/debug_menu.gd`; the switches
are in `game/dev/cheats.gd`, whose checks all answer "off" in an online match, so a new
cheat should go through one of them.

Its **Achievements and unlocks** section changes your saved progress
(`user://achievements.cfg`), through four functions of the Achievements autoload:
`complete(id)` (as if you had earned it, toast and all), `complete_all()`,
`unlock_items(cards)` (the creator's items, or the calling cards and icons, with no
achievement done) and `reset_progress()` (back to nothing; it deletes the file). What
your saved characters wear stays unlocked after a reset, as it does everywhere else.

## Measuring performance

Settings → Graphics → **Run benchmark** (or `godot --path . -- --benchmark`, which quits
when done and prints `BENCHMARK_REPORT <path>`) flies the same path over Cirrus, Castle
and Halcyon and writes a report and a per-frame CSV to `user://benchmarks`
(`%APPDATA%\Godot\app_userdata\Jumpy Shooty\benchmarks`). The code is
`game/core/benchmark.gd`. Keep `Benchmark.MAPS` and the path timings as they are, so
runs from different days and PCs compare; change them only on purpose and say so in
the commit.

How to use it to choose what to optimize:

- Run it in a window (not headless), twice. Runs agree within about half a millisecond
  on the same PC; a single run after a change to shaders or materials may pay for
  compiling them, even with the warm-up.
- Read **Limited by** first. **GPU**: make the drawing smaller (fewer draw calls, fewer
  lights casting shadows, less transparency, lower MSAA; on a map with movers every
  block kind on every MapMover is its own draw call). **CPU**: look at the CPU split
  under each map (drawing set-up vs physics), then run the game with the Godot editor's
  Profiler for scripts.
- The **Slowest part** line names the view to look at. A spawn stop is spawn point N
  in the map's list (spread evenly through it); the Overview circles the spawn
  points' middle. `tools/map_preview.sh` can render the same view to look at.
- Change one thing, run it again, and compare the two reports. Check a big win in an
  exported build too: the editor's debug build runs scripts slower.

The benchmark measures drawing only. A match also has players, bots, bullets and the
network; for that, play Vs Bots with the debug menu's FPS readout (F1) and use the
editor's Profiler and Visual Profiler (Debugger panel).

## Developer command-line options

Pass these after `--`, for example `godot --path . -- --practice`. The full list is at the
top of `game/dev/dev_args.gd`. The useful ones:

| Option | What it does |
| --- | --- |
| `--practice` | Go straight into the arena alone |
| `--benchmark` | Run the graphics benchmark (see Measuring performance), print where the report went, and quit |
| `--map=ID` | Which map: `construction_site` (the default), `office`, `kilnworks`, `castle`, `halcyon`, `cirrus`, `empyrean`, `haunted_house`, `testing_grounds`, a race map (`rooftop_run`, `foundry`, `sky_ruins`, `summit_plunge`), or a map scene's path (`res://game/maps/my_map.tscn`). Works with `--practice`, `--bot` and `--host` |
| `--host` / `--join=ADDRESS` | Host or join straight away |
| `--name=NAME` | Player name for this copy |
| `--autostart=N` | Host starts the match when N players are in the lobby |
| `--net-sim=L,J,P` | Pretend the connection is bad: L ms latency, J ms jitter, P% loss |
| `--delay-respawn=MS` | Client: apply other players' respawns MS ms late, as if the message were held up on the way, so their first snapshot from the new life arrives first (`tests/run_respawn_visible_test.sh`) |
| `--third-person` | Start in third person |
| `--spawn=X,Y,Z,YAW[,PITCH]` | Start at a given spot, facing YAW (degrees). Pick a spot that is clear on the map you use: start inside something and you fall out of the map |
| `--bot=LEVEL` | Go straight into a 1v1 against a bot (0 Easy, 1 Normal, 2 Hard, 3 Expert) |
| `--bots=N` | With `--bot`: play a free-for-all against N bots (1 to 4) instead of one |
| `--menu=PAGE` | Open the main menu on a page: `play`, `practice`, `bot`, `multiplayer`, `settings`, `profile`, `creator`, `card`, `achievements` |
| `--showcase=N` | Start the main menu's character showcase on its Nth character (from 1), for screenshots |
| `--settings-tab=N` | Open Settings on a tab: 0 Controls, 1 Camera, 2 HUD, 3 Audio, 4 Graphics (with `--menu=settings`, or in the pause menu) |
| `--pause-page=PAGE` | The pause menu opens on `loadout` or `settings` (pair with `--press=SEC:pause`) |
| `--hud=STYLE` | Use the `arcs` or `clean` HUD in both views for this run |
| `--hud-scale=X` | HUD scale for this run, 0.75 to 1.25 (as Settings → HUD → HUD scale) |
| `--manual-respawn` | Respawn only on a Jump or Fire press, as in a real game, even headless or with `--scripted-input` (which otherwise ask to respawn as soon as the wait is over) |
| `--save-killcam=N` | On the results screen, save best kill #N as a video straight away, into the game's own data folder (`user://killcams`) instead of Videos (tests) |
| `--fall=SEC` | Your player falls out of the arena after SEC seconds, to show the death screen |
| `--character=ID` | Play as `needle`, `vanguard`, `kestrel`, `bulwark`, `rivet`, `specter`, `orbit` or `templar`, or as a Character Creator id (`'--character=custom:n=Greg|l=frog|t=human|h=goblin|hat=crown'`), without changing your saved choice |
| `--unlock-all` | Nothing is locked behind an achievement (Character Creator items, calling cards, icons) |
| `--color=N` | Your colour in a free-for-all: a number in `Net.PLAYER_COLORS` (0 red, 1 blue, 2 green... 15 brown) |
| `--weapon=ID` | Play with `pistol`, `shotgun`, `rifle` or `railgun` without changing your saved choice |
| `--bot-weapon=ID` | Give every bot this gun (normally each bot picks one at random) |
| `--switch-weapon` | With `--auto-return`: pick the next gun in the lobby between matches (for the match test) |
| `--press=SEC:ACTION` | Press an input action after SEC seconds, e.g. `--press=10:toggle_camera` (pairs with `--screenshot`) |
| `--hold=SEC:ACTION:DURATION` | Hold an input action down, e.g. `--hold=5:move_forward:3` |
| `--look=SEC:YAW,PITCH` | Turn your view by YAW and to PITCH (degrees) after SEC seconds, e.g. `--look=3:0,-60` to look down |
| `--speed=X` | Game speed, e.g. `0.25` for quarter speed (to film a move in slow motion) |
| `--game-clock` | Count the SEC of `--press`, `--hold`, `--look`, `--screenshot` and `--quit-after` in game time. With Godot's own `--fixed-fps 60` (before the `--`) a scripted run plays out the same however slowly the machine renders, so screenshots land on the right frame |
| `--kill-target=N` / `--time-limit=S` | Host: shorter matches for testing |
| `--rules=golden` | Host or `--bot`: a Golden Gun match (first to `--kill-target`) |
| `--rules=killcam` / `--points=N` | Host or `--bot`: a Killcam-mode match; `--points` sets the points to win (a lobby setting, so clients play to it too; default 5,000) |
| `--race` | With `--practice`, `--bot` or `--host` and no `--map`: race on the first race map (a race map in `--map` makes it a race anyway) |
| `--game=dm` | With `--practice`, `--bot` or `--host`: a Deathmatch (an arena map: `construction_site`, `office`, `kilnworks`, `castle`, `halcyon`, `cirrus`...) |
| `--map-event=SEC` | Start the map's events (Halcyon's low gravity) after SEC seconds, as if a terminal had fired them: for tests and screenshots |
| `--eager-terminal` | Bots go for a map terminal whenever one is ready and they have nobody to fight (normally they only try now and then) |
| `--autopilot` | Your own racer runs the course the way a bot does (race tests and screenshots) |
| `--bot-level=LEVEL` | With `--autopilot`: at this bot difficulty (default 3, Expert) |

## Maps

Maps are scenes you edit in the Godot editor: `game/maps/construction_site.tscn`,
`game/maps/office.tscn`, `game/maps/kilnworks.tscn`, `game/maps/rail_yard.tscn`,
`game/maps/lost_temple.tscn`, `game/maps/neon_arcade.tscn`, `game/maps/castle.tscn`, `game/maps/halcyon.tscn`, `game/maps/cirrus.tscn`, `game/maps/empyrean.tscn`, `game/maps/haunted_house.tscn` and `game/maps/testing_grounds.tscn`. Double-click one in the FileSystem dock to open it.

The Castle is a good small example of a map with several height levels: a curtain
wall with a battlement walk at 6 m, four round corner towers at 12 m reached by
stone ramps laid along the wall walks, a gatehouse with a gate tunnel, and a
central keep whose upper floor (6 m) is reached from a terrace ramp and from the
west wall walk over a timber bridge, and whose roof deck (12 m) the keep stair
climbs to. Its palette (`palettes/castle.tres`) shows a breakable kind (the wooden
hoardings in the bailey). The scene is grouped by object, and each object holds its
own dressing: a merlon's coping is in its `Merlon` group, a torch's arm, cup and flame
are one `Torch` group, a tower's windows and flag are in the tower, and the lake,
causeway, boats, shores and mountains are under `Outside`. Small things you would move
as one (a torch, a shield, a barrel and its hoops, a pine, a mountain) are selection
groups: a click in the viewport picks the whole thing. To work on one piece, pick it in
the Scene dock. The dressing was first written by `tools/arena/castle_dressing.py`,
but the scene is now edited by hand and that script must not be run on it again.
You die only by falling into the lake (Kill Height -5, just under the water; the
Bounds are a far safety net). Outside the walls a 60 degree rock slope (`Outside/Shore`)
runs into the water: too steep to stand on, not steep enough to wall-run, so anyone who
drops off a wall slides in. Invisible blockers close the two footholds the walls leave:
the gate mouth in front of the portcullis, and the wall tops in front of each tower.
Nothing solid may stick out past the walls' outer faces (x and z of plus or minus 30).
The causeway starts 40 m out from the gate.

`game/maps/castle_v2.tscn` (test map `castle_v2`, "Castle 2") is a refreshed Castle:
72 m across instead of 60, a wall walk that runs all
the way round over flush corner bastions, a stair up each wall with a landing from
its head into the bastion, a keep with doors on
every side and ramps inside, four bridges from the keep to the walls, and in each
quarter a climb chain (2.2 m, then 4.2 m) up to a bridge. Two scripts first wrote it. The
layout (everything solid, the spawns and pickups) comes from
`godot --headless --path . --script tools/arena/castle_v2_blockout.gd` (the numbers are
at the top). The detail on top comes from
`godot --headless --path . --script tools/arena/castle_v2_dressing.gd`: about 1,500
blocks (copings, pilasters, torches, door frames, the hall's fittings, a
canopy and its goods in each quarter, paint on the ground, a jetty outside). Nearly
all are drawn only. About 100 are solid (the ones the script wraps in `hard()`): the
canopy roofs with their beams and brackets, the counters, racks, troughs and basins
under them, the well head, the market booth's awning, the crane jib, the hall's
benches and fireplace, and the gatehouse winch. A canopy roof slopes 33 degrees from
4.3 m at the wall to 3.45 m, so you can stand on it and ledge-climb from its top to
the wall walk. The spawns and pickups are where the block-out put them. Each quarter has a colour (stables gold,
training yard red, well court blue, market green) that its bastion flag, the keep's
banners and the pennants under the bridges repeat, so you can tell which way you face
in a map that is the same on all four sides. The dressing script removes its own
earlier pieces first (they carry the meta `dressing`), so it can be run again; the
block-out script starts over from the old Castle. The scene is edited by hand now
(blocks were moved in the editor), so both scripts refuse to run unless
`CASTLE_V2_REBUILD=1` is set: a run would throw the hand edits away. Try the map with
`--map=castle_v2 --practice`.

`game/maps/sky_island.tscn` (test map `sky_island`, "Sky Island") is a stone castle in
the clouds, in bright colours: seven floating islands of vivid grass (the turf
overhangs a band of earth) with rock hanging underneath in jagged cones (the ground
slabs have 16 sides, the rock under them a few, blocky; pad tops 9 or more) and bits
of rock floating beside them. On top grow pines in clumps (solid trunks) and trees in
pink blossom, over patches of darker and sunnier meadow, with boulders near the
edges; the grass is kept clean (no small flowers, no blades of grass, and nothing
hangs from the rims). The castle
ruins are warm sandstone on darker footings, with loose stones along the broken wall
tops, arrow slits, ivy, banners with gold marks (red on the Keep, blue on the
Citadel, purple on the Broken Tower), pennants on the two whole towers, pale columns
and paved floors with weeds in them. The light is a strong warm sun with cool blue
shade (one ambient colour, not the sky's light, which the white cloud below washed
out) under a deep blue sky; below is a sea of cloud (the sky is a shader,
`game/maps/sky/sky_island_sky.gdshader`, at -30 m). Most colours come from the
palette; a block's tint shades one thing off the next (each clump of pines, each
ball of blossom). The grey
block-out it started from is kept as `game/maps/sky_island_layout.tscn` (test map
`sky_island_layout`, "Sky Island (layout)", its own copy of the old palette). The
scene is grouped like the castle maps: by object, each holding its own dressing, and
whatever you would move as one (a pad, a wall piece with its footing and ivy, a
column, a tree, a patch of meadow, a lobe of an island with its rocks) is a
selection group. The Hearth, in the middle, is the lowest (-3 m, the ruined Keep:
broken walls, a corner of its upper floor on timber joists, two corner drums); the six
stand round it about a sixth of a turn apart, at mixed heights: the Shelf (3 m, a
formal garden: clipped hedges with stone gate posts round a fountain of two bowls),
the Bluff (8 m, a round hole 7.6 m across right through its middle, where
falling in is death, with a tall wooden crane beside it whose rope and iron hook hang
down into the hole, crates and barrels by its winch, and a low dry-stone fence round
the edge with gaps wherever the crossings come in), the Spire (4 m, open), the Citadel (7 m, the Gate and its
curtain wall with a wall walk, a gate arch and a drum), the Garden (2 m, a ring of
grey standing stones, open in the middle) and the Terrace (6 m, the Broken Tower: an eight-sided shell
with a lookout 6 m up inside, reached by a ramp from the doorway, that looks out over
the low west walls). No island is round: each is a handful of overlapping many-sided slabs
of different sizes (36 to 56 m across in all), with a cone of rock hung under each.
The Bluff's hole (`HOLES` in the script) is cut without changing the island's outline:
a slab can only have a hole in its own middle, so the middle slab's turf and earth are
rings of flat three-cornered pieces (wedges lying on their sides: `slab()`), the three
slabs that overlap the middle are built the same way, cut back from the hole along a
straight line hidden inside the ring (which no tube block could do), and the rock under
the middle is panels lining the shaft with a ring of cones round them. (A tube block
does collide as the ring you see, one convex lump per flat side, `MapMesher.tube_hulls`;
the ground was built from flat pieces when a tube still collided as a solid box, and
the lobes that overlap the hole need the flat pieces either way.)
`MapRoot.standing_on()` knows a wedge on its side as ground, and the flicker test
counts a wedge as hiding what is inside it.
There is no path you can walk from one island to another. Stepping pads join the six
outer islands into a ring, each to the next (three or four big pads a gap, 4.5 to 9 m across, scattered:
each row swings side to side and every pad is thrown off it, with its own size and
shape, and about one in four has a smaller pad beside it; no pad stands in an island (one that would is slid along its row until it is 0.8 m clear); the longest hop in a row is
under 5 m). Nothing joins the Hearth to the outer islands and there are no grapple
points: about 24 m of open sky each, the Hearth 4 to 11 m below on average (the climb to each swings with the bob, and every one comes within 7 m at some moment), crossed with rocket
boots or a long jump down. Everything floats up and down: each island is a `MapMover`
with its own rise (4 to 8 m) and its own moment in a 14 second cycle, and carries its
ruins, cover and spawn points; each pad is a `MapMover` too, timed to the two islands
it lies between, so the rows flex with them (one shared period is what lets a pad
follow two islands exactly: see `pad_bob()` in the script). The heights above are the
middle of each bob; in the editor a mover sits at the bottom of its bob, so the scene
looks a little uneven until the game runs it. A mover carries its patterns with it: the
distance grid and the palette's Surface patterns are measured from the moving body, not
from the map (`MapMesher.riding()`, `MapRoot.riding_material_for()`), because a pattern
measured from the map stands still while the block slides through it, and shimmers.
This holds for every `MapMover` in every map. Bots get round by 68 MapJumpLinks:
a hop each way between neighbours along every row of pads (at any moment: the pads keep
every step to about 2 m), the rocket boots down to the Hearth from every outer island
(any moment), and back up to the Shelf, Bluff, Spire and Garden only while the landing
will be 6 m up or less (the Citadel and Terrace never come that low: bots go round by
the pads). Each link rides the part it sets off from. Falling is death (Kill Height
-36). It has 30 spawn points and 15 weapon pickups (the rocket launcher on the Keep's
upper floor, the lever-action rifle on the Citadel's wall walk, the railgun on the Broken
Tower's lookout), all inside islands so they ride the bob, so it is listed for
free-for-all and Deathmatch. It is written from scratch by `godot --headless --path .
--script tools/arena/sky_island_blockout.gd` (the islands and their sizes are at the
top; pads, crossings and pickups after them; the dressing has its own random numbers,
so changing it never moves a pad); run that again after changing them, until the
scene is edited by hand. Try it with `--map=sky_island --practice`.

**What a map is made of.** The root node is a `MapRoot`. Under it:

- **MapBlock** nodes: every floor, wall, crate and girder. A block is a box, cylinder,
  tube or cone with a **Kind** (its colour from the map's palette). A cone's Size is the
  diameter of its foot and its height; **Top** is the diameter at the top (0 comes to a
  point), and it collides as the same flat-sided shape you see. Its inspector also has
  **Size**, **Solid** (off = drawn only, like paint on the floor), **Drawn** (off = an
  invisible wall, shown in the editor as a faint blue box), **Tint** (to make one block
  a little lighter or darker), **Material Type** (what it is made of: its footsteps and
  how it breaks; see below) and a **Breaking** section (see "Breakable walls and floors").
- Plain **Node3D** groups. Each object (a container, a staircase, the crane) is a group
  grouped the Godot way (the group icon beside it in the Scene tree), so a click in the
  3D view selects the whole object. To change one part, pick the part in the Scene
  tree, or select the object and press Ungroup in the 3D toolbar (next to the lock).
- **MapSpawn** nodes (under `Spawns`): where players appear. The green figure shows
  which way they face. Keep at least 8 (5 on a race map: they are the start line).
- **MapDummy** nodes (under `TargetRange` in the Testing Grounds): target dummies. The
  orange figure shows which way the dummy faces; the inspector picks its robot, its gun
  and the caption over its head (the Testing Grounds ones give the distance).
- **MapWeaponSpawn** nodes (under `WeaponSpawns`, on the Construction Site, the
  Office, the Kilnworks and the Castle): Deathmatch weapon pickups. Stand one on a floor and pick its **Weapon** in the
  inspector; in a Deathmatch that weapon floats a metre above it, bobbing and turning,
  until someone walks through it, and is back 10 s after (`Match.PICKUP_RESPAWN`). Other
  games leave the spot empty. The orange ghost and label are editor-only.
- **MapTerminal**, **GravityEvent** and **MapSpinner** nodes (Halcyon): a console players
  press Interact at, the event it sets off, and scenery that turns. See "Terminals and
  map events" below.
- **MapIsland**, **LayoutEvent** and **MapJumpLink** nodes (Cirrus): a group of blocks
  that flies, the clock that rearranges the islands, and a crossing bots are told how
  to make. See "Maps of flying islands" below.
- **MapLever** and **CraneEvent** nodes (Construction Site): a lever players throw with
  Interact, and the tower crane it works. See "The crane" below.
- **MapGravityZone**, **MapHazard**, **MapLiftWell**,
  **OrbitEvent** and **MapDrone** nodes (Empyrean Tower): a place with its own gravity, a
  block that kills, a tractor-beam lift,
  the clock that turns orbiting islands, and a drone that is only scenery. See "Empyrean
  Tower" and "Gravity zones, hazards and lifts" below.
- **HauntProp**, **HauntEvent** and **MapGhost** nodes (Haunted House): furniture that
  floats, shifts to new places and vanishes, the clock that haunts it, and a ghost that is
  only scenery. See "Haunted House" below.
- **Label3D** nodes: signs and painted floor numbers.
- **Environment** (sky, ambient light) and **Sun**: ordinary Godot nodes, so the editor
  shows the map lit the way the game does.

**Editing.** Move, turn and duplicate (Ctrl+D) blocks like any node. To resize a block,
drag one of the red handles on its faces: that face moves and the opposite one stays
put. Sizes snap to the grid (see below), or whole metres while you hold Ctrl, and the
face you drag also snaps flush to a nearby face of another block. You can also type the
Size in the inspector, or use the scale tool (scale is folded into the size in the
game). A block or group you hide with the eye icon is left out of the game.

**The map tools.** While a map is open, the 3D editor's toolbar has a strip of tools
for building with blocks, and there is a **Map** dock (bottom left). Every one of them
makes ordinary MapBlocks and is one step of undo.

- **The grid.** `Grid 0.5 m` in the strip is what the tools snap to: 0.1, 0.25, 0.5, 1,
  2 or 4 m. `[` makes it finer, `]` coarser.
- **Draw** and **Clip** are tools you turn on: press the button (or its key) again, or
  Esc, and you are back to the editor's own select, move, rotate and scale.
- **Draw** (`B`). In the 3D view: press on a block's face, or the ground, and drag out
  the new block's footprint; let go, move the mouse to pull it out of the face, and
  click to set it. In a top, front or side view (the View menu's 2 or 4 viewports give
  you all of them at once): drag a rectangle, and the block is as deep as the selection,
  or the last block you drew. Esc or a right click gives up. The block gets the kind
  chosen in the Map dock and goes beside whatever was selected.
- **Moving** is the editor's own move tool. After a move, **Map > Snap to Neighbours**
  (Alt+N) nudges the selection, by up to one grid square, so its faces meet those of the
  blocks beside it that lie square to it.
- **Clip** (`K`). Point at a selected block: a yellow line shows the cut, on the grid.
  Click to cut it in two. `X` turns the cut the other way across the face. Every
  selected block the cut passes through is cut. Boxes cut any way, cylinders and tubes
  only across their height.
- **Solid**, **Drawn**, **Breakable** buttons (Alt+S, Alt+D, Alt+B): turn those settings
  on or off on every selected block, in groups too.
- **Map > Hollow** (Alt+H): a selected box becomes a room, a group of six walls of the
  thickness you type that fills the same outside. You can leave the top or the floor off.
- **Map > Mirror**: across x or z, about the middle of the map or of the selection, as
  a copy or in place. Nothing is scaled by -1: a mirrored wedge is a wedge facing the
  other way.
- **Map > Array**: copies in a line (how many, how far apart) or round a circle (4 round
  the middle of the map gives a square map its other three sides).
- **Map > Add Stairs or Ramp / Row / Ring**, then click where it goes (Esc to stop).
  These are **pieces**: a node with a few numbers in the inspector that makes its blocks
  again whenever you change one. Stairs and ramps are one piece: its **Style** is Steps
  or Ramp, and it has Rise, Run and Width, which you can also set by dragging its three
  handles in the 3D view (at the top, at the far end of the foot, at the side), as you
  would a block's. Players do not step up kerbs, so steps are drawn only, under an
  invisible ramp, unless you untick Smooth; past 46 degrees (too steep to walk) the piece
  warns you. A Row or a Ring repeats its first child, a block or a whole group: edit that
  one and the copies follow. A Row has a handle at its last copy for how far apart they
  are; a Ring is as wide as its first child is far from its middle. Do not edit the
  blocks a piece made, they are replaced; press **Bake** in its inspector to turn it into
  a plain group first.
- **Map > Show Invisible Blocks / Show Solid Blocks Only**: what the editor shows. The
  second hides everything you cannot bump into, to check a map's real shape.
- **The Map dock, Kinds**: the palette as swatches, with how many blocks use each.
  Click one: new blocks get that kind, and the selected blocks are painted with it.
  Right-click one to select every block of that kind. **Add Kind** adds a colour to the
  palette.
- **The Map dock, Prefabs**: **Save Selection** saves the selected blocks and groups as
  a scene under `game/maps/prefabs/`. Pick one and press **Place**, then click in the
  map: each click puts down a copy as plain blocks in one group. A copy has no tie to
  the prefab's file, so changing the prefab later does not change maps that used it.
  Kinds go by name; the dock tells you if this map's palette lacks one.

The keys are editor shortcuts (Editor Settings > Shortcuts, under `map_tools`), and work
while the mouse is over the 3D view.

Colours live in the palette (`game/maps/palettes/*.tres`): change one there and every
block of that kind changes. To add a kind, add an entry to the palette's Colors, then
type its name into a block's Kind. A colour whose alpha is below 1 makes the kind
see-through (Halcyon's dome and windows): you look through it, but it is as solid as
any block. The palette's **Surface** list gives a kind a pattern drawn on every surface
of that kind with no extra blocks (Halcyon): `panels` (seams on walls, now and then a
hatch or vent slots), `panels_plain`, `tiles`, `plates` (rivets), `grating`, `slats`
(a vent), `hazard` (slanted stripes), `treads` (grip lines across a ramp),
`corrugated` (shipping containers), and for buildings and the outdoors: `checker`,
`pavers` and `slabs` (floors), `bricks`, `blocks` and `blocks_small` (dressed stone; on a
floor, flagstones), `cobbles`, `planks` and `planks_upright`, `shingles` and `thatch`
(roofs), `grass`, `dirt`, `gravel` and `tarmac` (soft blotches), `clumps` (leaves),
`bark`, `strata` (a cliff), `water` (ripples that move), `confetti` (an arcade carpet)
and `windows` / `windows_lit` (rows of windows on far-off buildings), and for a wizard's
tower (Empyrean Tower): `masonry`, `masonry_small` and `masonry_runes` (stone in courses of
four heights, every stone its own length; "_runes" cuts a glowing rune into a few),
`ring_flags` and `ring_flags_cyan` / `_green` / `_teal` / `_violet` / `_stars` (a round
floor laid in courses round the map's middle, x = 0 and z = 0, with a line of brass
inlaid every few courses and, on the coloured ones, glowing runes; only for a round
building that stands on the middle), and for an old house (Haunted House): `wallpaper` (stripes and a damask pattern, pin
seams, stains and peeling), and `arcane_plates` (riveted metal plates with a
brass inlay and a rune in a ring on some). The patterns are settings of one shader,
`game/arena/map_surface.gdshader`, listed in `MapScenery.SURFACES`; they are measured
in metres from where the surface is in the map, so they line up from block to block. A
kind that glows or is see-through takes no pattern. The MapRoot's inspector also has the map's rules:
**Bounds** (leave it and you are out; drawn as a red rectangle), **Kill Height** and the
**Swing Point** the test player hooks.

**Breakable walls and floors.** A block breaks only if you tick **Breakable** in its
**Breaking** section; it is off on a new block. Blocks break only in arena matches,
never races. Ticking it shows two more settings:

- **Break Settings**: a dropdown of ready-made choices. *Per Cell* cuts a thin wall or
  floor (at most 0.6 m thick, at least 7 m² of face, box-shaped) into about 2 m pieces
  that break one at a time; a thicker block set this way warns in the editor and stays
  whole. *Whole Block* gives the block (any size or shape: a crate, a pillar) one pool of
  health and breaks it all at once; what rests on it stays where it is. Each comes plain
  (as tough as its kind: see below), *Fragile* (25: one pistol shot) or *Tough* (300).
  The list is `PRESETS` in `game/arena/block_breakable.gd`; add a line there to offer
  another.
- **Break Health**: the damage this one block takes, in place of what Break Settings
  says. 0 leaves it to Break Settings.

A palette's **Breakable** list says how tough each kind is: the damage a piece of it
takes when its block's settings do not say (a pistol shot is 25; below 50 a whole pane
shatters at once, for glass; a kind left out takes 100). It no longer decides what
breaks. Maps saved when Breakable was *Default / Yes / No* still load: Yes as ticked, No
and Default as not. Default used to mean "if the palette lists its kind", so an old map
needs `godot --headless --path . --script tools/arena/migrate_breakable.gd -- res://game/maps/my_map.tscn`
run on it once, which ticks every block that used to break; the maps here have had it.
The Python map builders in `tools/arena/` still write the old form, so run it on a map
after building it with one.

Per cell, pieces near a spawn, and pieces that something else rests on, hangs from or
passes through, never break; thin drawn-only blocks lying flat on a breakable one (a
ceiling under a floor, a rug, a lamp strip, frosting on glass) break along with it. A
whole block only keeps the spawn rule. The bots' navigation mesh is not rebuilt when
something breaks. The code is `game/arena/map_destruction.gd`.

**Materials.** A block's **Material Type** (concrete, metal, wood, glass, dirt, rubber)
sets the footsteps on it and the crash, rubble and dust when it breaks. Left blank, it
comes from the palette's **Material** list (kind -> material), else from the kind's name
(`glass`, `plank`/`crate` -> wood, `steel`/`girder` -> metal...). The table is
`game/arena/block_materials.gd`: for now most materials reuse the step and break sounds
at another pitch, so real sounds can drop in there later without touching any map.

**Trying it.** With a map scene open, press **F6** (run current scene): the game starts in
practice mode on that map. In the game, all blocks of one kind are merged into a single
mesh and the bots' navigation mesh is worked out from the solid blocks, so moving
things needs no extra step.

The Construction Site's crane, the netting on its scaffold and steel, the cover in its
yard and most of its dressing were written by `tools/arena/construction_site_revamp.gd`
(run once; it is kept as a record and refuses to run again, like the Castle's). The
palette's Surface list gives its kinds their patterns (dirt, gravel, slabs, blockwork,
planks, grating...).

**Checking it.** After moving things on the Construction Site, run `tests/site_test.gd`:
it tells you if a route no longer works or a bot can no longer reach a floor. The test
keeps its own note of where the routes are (at the top of `tests/site_test.gd`), so if
you move the lift shaft or a climbing crate on purpose, change its numbers there too.
The same goes for the Office and `tests/office_test.gd`, and the Testing Grounds courses
and `tests/course_test.gd`.
`tests/map_scene_test.gd` checks that every map loads, has a colour for every block and
has enough spawn points. `tests/map_tools_test.gd` checks the map tools without the
editor: the geometry, the pieces, and the tools themselves, driven by made-up mouse
events.

**A new map.** Make a scene with a MapRoot root (or duplicate an existing map and strip
it down), give it a palette, add blocks, spawns, a WorldEnvironment and a sun. F6 plays
it straight away. To put it in the menus, add a line to `LIST` in `game/arena/maps.gd`.
To offer an arena for Deathmatch too, give it `"also": ["dm"]` there and add
MapWeaponSpawn nodes; `tests/deathmatch_test.gd` checks every Deathmatch map has at
least 8 pickups of 10 or more different weapons, each over a floor with room to stand,
and that all the Deathmatch maps together offer every weapon.

The scripts behind this:

| File | What it holds |
| --- | --- |
| `game/arena/maps.gd` | The list of maps (id, name, scene). Add a map here and it shows up in the menus |
| `game/arena/map_root.gd`, `map_block.gd`, `map_spawn.gd`, `map_palette.gd` | The node types above; `MapRoot.build()` turns the blocks into collision and meshes |
| `game/arena/map_mesher.gd`, `map_scenery.gd` | One merged mesh per kind, the materials, the navigation mesh |
| `game/arena/map_destruction.gd` | Breakable walls and floors: which pieces break, their collision and cracks, rubble |
| `game/arena/map_terminal.gd`, `map_event.gd`, `gravity_event.gd`, `world_gravity.gd` | The console players press Interact at, the event it fires, and the one gravity multiplier all movement reads |
| `game/arena/map_lever.gd`, `crane_event.gd` | A lever (a terminal that looks like one) and the tower crane it works: a jib that turns and a load that rides with it |
| `game/arena/map_replay.gd` | How killcams record the map's moving parts and draw them as they were (see "Moving parts in killcams") |
| `game/arena/map_spinner.gd` | Scenery that turns (never solid) |
| `game/arena/map_gravity_zone.gd`, `map_lift_well.gd`, `orbit_event.gd`, `map_drone.gd` | Places with their own gravity, tractor-beam lifts, orbiting islands, scenery drones (Empyrean Tower; any map can use them) |
| `game/arena/haunt_prop.gd`, `haunt_event.gd`, `map_ghost.gd` | Furniture that floats, shifts and vanishes, doorways that come and go, the clock that moves them, and the ghosts (Haunted House; any map can use them) |
| `game/arena/map_surface.gdshader` | The patterns a palette's Surface list draws on a kind (panel seams, tiles, grating, hazard stripes...) |
| `game/arena/map_piece.gd`, `map_stairs.gd` (stairs and ramps), `map_row.gd`, `map_ring.gd` | The pieces: nodes that make their blocks from a few numbers (editor only; in the game they are plain groups) |
| `addons/map_tools/` | The editor plugin: resize handles, click-to-select, the bounds outline, and the map tools. `plugin.gd` wires it up; `map_ops.gd` (geometry), `tool_*.gd` (what the mouse does) and `map_commands.gd` (Hollow, Mirror...) have no editor in them, so the test can run them; `map_toolbar.gd`, `map_dock.gd` and `map_dialogs.gd` are what you see |

To render pictures of a map without opening the game:

```
tools/map_preview.sh construction_site OUT_DIR --shots="sw;top;cut7.5;-24,1.7,35:0,13,0:75"
```

Shots are corners (`sw`, `ne`, ...), `top` (a plan), `cutY` (a plan with everything above
height Y sliced off, to see one floor) or a camera `x,y,z:look-x,y,z:fov`. The map can
also be a scene path (`res://game/maps/my_map.tscn`). A plan shows 92 m from top to
bottom; `--span=150` fits a map the size of Halcyon (`--shots="cut5.9;cut-0.6"` are its
main and lower decks). On a map with a LayoutEvent every island is shown at its
home; `--layout=SET,KIND,VARIANT,LOOK` shows one of its arrangements instead (SET 1..:
which islands are up; KIND 0 Swap, 1 Drift, 2 Close, 3 Far, 4 Split; LOOK 1 = sunset),
`--layout=A:B:0.5` half way through the move from arrangement A to B, and
`--layout=A:B:warn` the end of the warning before it.

`map_preview.sh` draws with the simple OpenGL renderer. To see a map the way the game
draws it (Forward+, with its anti-aliasing, shadows and ambient occlusion), at eye height
from its spawn points with a robot in view, use:

```
tools/graphics_preview.sh cirrus OUT_DIR --quality=high --spawns=0,2 --tag=after
```

`--quality` is a graphics preset (low, medium, high); left out, the project's own settings
are used. It runs in software when there is no graphics card, about a minute a map.

The portrait banner (the character on its stage in the lobby and the Character Creator)
has a tool of its own, which draws just the banner the way the game does:

```
tools/portrait_preview.sh OUT_DIR --character=bulwark --weapon=hammer --hold=side --quality=high
```

`--shape=creator` is the Character Creator's taller frame, `--hold` is `front`, `low`,
`side` or `flourish`, `--switch=SEC:ID` puts another character on the stage (it builds
in), and `--frames=N --fps=30` saves N pictures in a row for a clip (run it with
`FPS=30` so the game steps at the same rate). The rest are at the top of
`tools/portrait_preview.gd`.

### Rail Yard, Lost Temple and Neon Arcade

These three arenas were laid out by `tools/arena/build_arena_maps.py` (one file per map
in `tools/arena/`, the scene writer in `tools/arena/arena_builder.py`). They are ordinary
map scenes, grouped one object per group like the others, so edit them in the editor.
Running the script again (`python3 tools/arena/build_arena_maps.py rail_yard`) rebuilds a
map and its palette from scratch and overwrites hand edits. After moving things,
`godot --headless --path . --script tests/arena_maps_test.gd` checks that every spawn is
clear, walls and floors still break, and a bot can walk between every spawn point and to
each map's floors (the goals are at the top of the test).

Each map file ends with a `details(m)` function: the small things (window frames, lamps,
signs, pipes, weeds, vines, the street outside the arcade). They are all drawn only, so
they change neither collision nor the bots' navigation. The builder has helpers for them:
`strip` (a box), `on_wall` (a piece that stands proud of a wall face), `rod` and `pipe`
(bars at any angle), `sign`, and `stairs(..., cheek_stop=)` for stair sides that stop
short of a landing. The rules they keep, which `tests/map_flicker_test.gd` checks:

- Two surfaces of different colours never share a plane. A detail stands proud of the
  surface behind it, and one laid over another is both a different depth (2 cm or more)
  and a different outline, so their fronts and their edges are in different planes.
- Paint on a floor is 2 cm thick or more, and each kind of paint has its own height.
- A box that wraps a post (a collar, a cap) ends below the post's top.
- On a wall or floor that breaks, a detail is a thin skin (0.15 m or less) lying
  inside one panel's outline, so it breaks with the panel. Anything bigger, or
  anything that spans two panels, would hold the wall up: stand it on its own posts.

### Halcyon

`game/maps/halcyon.tscn` is the inside of a colony ship, the biggest arena (140 x 140 m,
up to 16 players) and the only one that is sealed all round: a round Control Room in the
middle under a glass dome, four spoke corridors to four tall rooms (Hangar north,
Hydroponics east, Engineering south, Cargo Bay west), an outer ring corridor joining
them through three corner sections and the Cryo zone, and a lower maintenance deck (-6 m)
under the spokes and the ring. The tall rooms run from the lower deck's floor up to
26-30 m, with decks about every 7 m and plenty to hook. The reactor pit in Engineering
is the only hazard: it drops below the map's Kill Height (-16 m).

It was laid out by `python3 tools/arena/build_arena_maps.py halcyon` (the layout is
`tools/arena/halcyon.py`: the four spokes are one spoke turned, three ring corners one
corner mirrored). Like the other generated arenas the scene is an ordinary map scene and
is what you edit from here on; running the script again rebuilds it from scratch and
**overwrites hand edits**. After moving things, `godot --headless --path . --script
tests/halcyon_test.gd` checks the spawns, the routes and that the hull is still sealed
(the places it walks to are at the top of the test).

Things to keep true when editing it:

- The dome, the floor glass and the hull windows are the kind `glass_hull`, which is not
  in the palette's Breakable list (and they are ticked Unbreakable too). The glass
  that breaks is `glass_pane`; a pane only breaks if nothing rests on it, so they stop
  a little short of the lintel above.
- In low gravity a jump reaches 4 m. Every room has a ceiling and the hull has no gaps,
  so nobody gets out; keep it that way when you open a wall.
- Wall and floor details (each place's "Details" group: ribs, vents, wall displays,
  conduits, ceiling beams, floor lines, grates, hazard stripes) are drawn only: Solid
  is off on every one, and none stands more than 0.3 m off its surface, so nothing
  snags a wall run, a slide or a swing. Keep new ones the same. Panel seams, tiles,
  grating and stripes are not blocks at all: the palette's Surface list draws them.
- A light bar or colour band along a wall stops at every doorway and window (in a
  round room it is made of straight pieces, one per wall piece, for that reason). The
  Halcyon test fails if one hangs across an opening.
- Two surfaces of different kinds (or tints) in exactly the same plane flicker. So a
  room's floor stops at its wall under a doorway (the doorway's threshold is the floor
  there), a wall has no sill under an opening that starts at the floor, and corridor
  walls end inside a room's wall, not flush with its face. Paint on a floor goes in
  layers so no two share a height: grates 12 mm thick, lines 20 to 24 mm, hole rims
  30 mm, hazard stripes 40 mm, words 60 mm up. Wall pieces differ in how far they stand
  off the wall. The Halcyon test checks the floors.
- Words on a floor are Label3D nodes lying flat with Shaded on, so they take the
  room's light (and go blue with it in low gravity).
- No spawn point or weapon in the Control Room, and no spawn point that can see the dais.
- Lighting is the ambient light, a soft shadowless "sun" and the glowing kinds (each
  room has its own accent kind: `accent_cyan` and so on). There are no light nodes, so
  it looks the same on every renderer. The sky is `game/maps/sky/halcyon_sky.gdshader`.

### Cirrus

`game/maps/cirrus.tscn` is a university campus on floating islands, open to the sky, for
up to 16 players: the quad in the middle (a round lawn about 29 m across, with the
clock tower on it: nine flights of stairs up to the belfry at 26 m, under a tall slate
spire), five building islands round it (Observatory, Labs, Lecture Hall, Cafeteria,
Library), five stepping stones just off the quad's rim, and nothing underneath: the
Kill Height is -45 m. There are **no walkways**: an island's tip is 24.4 m (80 ft) of open
sky from the quad's rim, and neighbours are as far apart. That is beyond a jump with a
dive or a flip, within reach of the whole chain (flip, dive and glide: 26 m), and easy
for the grapple or the rocket boots. A banner mast on each island's tip and five on the
quad's rim are grapple points. Floors are 5.5 m apart and the main halls are two floors
high. There is no writing anywhere on it: each building is told by its colour and its
shape (the Observatory's copper dome, the Labs' glass wall and roof stacks, the Lecture
Hall's shell roof, the Cafeteria's striped awning, the Library's columned porch).

The scene has all five islands at their homes (about 135 m across), and that is what
you edit. **In a match only two are up at a time**, and the clock changes which, every
60 s for the whole match:

- A clock ticks quietly the whole time, and the clock faces' long hands count the
  minute down.
- At 60 s the bell tolls and there are 8 s of warning. The islands that are about to
  go are doomed: their engines and lamps turn red and sputter, they sag, and anyone
  standing on one feels it shake. Nothing else moves yet: the time to get off.
- Then, for 4 s, the doomed islands fall away below the map (whoever is still on one
  goes under the Kill Height with it: a fall, nobody's kill), an island that is in
  both pairs glides to its new place carrying its riders, and new ones rise out of the
  clouds. A clunk when they have arrived. Afternoon and sunset change places each time.
- What comes next is drawn at random a turn ahead: never the same pair twice running
  (so at least one island comes up fresh) and never the same kind twice running.
  The kinds: **Swap** (each at its home), **Drift** (each 36 degrees round the quad),
  **Close** (each 12.2 m nearer: a jump from the quad), **Far** (each 9.1 m further
  out, and both 7 m up or both 9 m down) and **Split** (one 8 m up, one 8 m down).

Players are only put on islands that are up and staying; when there is none (both are
on the move) on the quad, which has five spawn points of its own. Pickups go down with
their island and come back with it. In the team modes (Search and Destroy, Capture
the Flag) the clock does not run and all five islands stay up, because their bomb
sites and flag stands are fixed spots. How it works is under "Maps of flying islands"
below.

It was laid out by `python3 tools/arena/build_arena_maps.py cirrus` (the layout is
`tools/arena/cirrus.py`; one island function, five building functions). Like the other
generated arenas the scene is what you edit from here on, and running the script again
**overwrites hand edits**. After moving things, `godot --headless --path . --fixed-fps 60
--script tests/cirrus_test.gd` checks it.

Things to keep true when editing it:

- Nothing stepped, stacked or cube-shaped where a slope or a curve belongs: roofs are
  wedges, cones and domes; trims, furniture and posts are bevelled; trees are round
  clumps; stairs are closed in by sloping sides over an invisible ramp, so the zigzag of
  the steps never shows. The game's surface patterns are drawn twice the size and under
  half as strong here (the palette's **Surface Scale** and **Surface Strength**).
- Everything on a building island goes inside that island's MapIsland node (blocks,
  spawn points, pickups, its mast and its two crossings), or it is left behind when
  the island moves.
- **Decor**: each building has a Decor group and each plaza and the quad a Garden
  group (about 2,500 of the map's 5,283 blocks). Small things are drawn only, so you
  walk and shoot straight through them: chairs, stools, armchairs, rugs, pot plants,
  shrubs, flower beds, hanging baskets, ivy, books, pictures, screens, glassware and
  every light. Big things are solid cover: shelves, counters, workbenches, desks,
  cabinets, benches, the planter boxes and tree tubs. Keep it that way, and keep
  solid pieces out of the walking lanes, off spawn points and pickups, and off the
  middle of each island's tip, where people land, and at least 4 m from the quad's
  masts (a lamp post 2 m from one knocked a player landing off the grapple right off
  the lawn). Ivy is round clumps lying on the
  wall, never flat rectangles. Lights are the kind `lamp`, so they come on at sunset
  with the windows and go red on a doomed island.
- Spawn points are on the building islands, plus the five on the quad's lawn for when no
  island has room. None on the tower or a stone.
- An island's line from the quad (and the line 36 degrees either side of it, where it
  stands when it has drifted) is kept clear on the quad's rim: bots set off along it.
  The quad's masts are 18 degrees to one side of each island's line, the stepping
  stones 18 degrees to the other.
- Nothing may stand above the fog (-34 m) under an island at its lowest (9 m down), and
  the Kill Height must stay below that and far above a parked island (-120 m).
- Stairs the bots must use: 2 m wide or more, no steeper than 31 degrees (5.5 m up in
  9.2 m), steps of 0.25 m or less, 2 m of clear floor before the foot and beyond the
  head, nothing narrower than 2 m on the way, and the hole in the floor above starting
  only where the stair still has 2.4 m of headroom. A stair that breaks one of these is
  walkable for a person and missing from the navigation mesh.
- The clock tower's stair winds up over itself, so the MapRoot has **Winding Floors**
  ticked: the navigation mesh is then cut up a way that keeps such a stair (leave it
  off on other maps: the usual way makes tidier paths in the open).
- Bots cannot get round this map without the grapple, so the MapRoot has **Bots
  Grapple** ticked: every bot carries it here, whatever it was dealt.
- Only the Labs' glass (`glass_lab`) breaks. Its panes ride the island like the walls.
- The sky, the cloud sea and the ringed planet are `game/maps/sky/cirrus_sky.gdshader`;
  the LayoutEvent turns its `sunset` and `swirl` up and down. The Environment's fog is
  height fog only (nothing above -34 m is touched): it is what a falling island
  vanishes into.

### Empyrean Tower

`game/maps/empyrean.tscn` is a wizard's tower in low orbit for up to 16 players, the tallest
arena by far: round, 61 m across at its foot and 40 m at the eaves 183 m up, under a
conical roof with a crystal and an orrery at its peak and with a root of rock hanging
below. Fantasy in its construction and sci-fi in its modification: a stone shell with stone ribs
and brass, and fitted to it conduits of light, pipes and dishes, thrusters, a docking ring with a parked starship, holograms.

Inside, six tiers of 30.5 m round a hollow shaft 16 m across: Arcane Engine (cyan),
Grand Library (gold), Alchemy Labs (green), Menagerie (teal), Summoning Chamber (violet),
Observatory (silver). The five lower tiers are one plan, all turned the same way,
measured in 24 sectors of 15 degrees (0 = south, 90 = east):

- sectors 0-9 (0 to 150 degrees): the feature room, open to the shaft, 19 m tall, with a
  balcony along its back wall at 6.35 m and one at each end at 12.7 m;
- sectors 10-23: three storeys (0, 6.35, 12.7 m) of rooms on the shaft side and a
  corridor two lanes wide along the outer wall. Its outer lane carries two spiral ramps,
  one from each end (150 and 360 degrees), 30 degrees a storey, meeting at 19 m;
- 19 m: the upper hall, all the way round, from which two long ramps (150 to 240 and
  360 to 270 degrees) climb to the next tier and come up through its floor.

The Observatory is one room with a gallery half way round at 9 m. Bridges cross the
shaft at every tier's floor and every upper hall, turned so no two line up. The Engine's
crystal core at the bottom of the shaft kills on touch (MapHazard blocks in a sunken,
glowing basin behind a kerb).

Outside: gravity is 40% (the MapRoot's **Gravity Outside**; one MapGravityZone fills the
tower). There are no bounds (its **Bounds** is zero-size) and no ceiling: the only death
out there is the burn layer, the **Kill Height** at -88 m, 46 m under the root's lowest
rock. Balconies at 75, 213.75 and 303.75 degrees on every tier, the docking ring at
91.5 m with the landing pad and starship at 255 degrees, eight thrusters round the foot,
sensor masts on the eaves, and the debris field. Three chunks orbit (MapIslands with an
**Orbit**, turned by the scene's OrbitEvent); the rest is still.

Four tractor-beam lifts: LiftA in the shaft from the Engine to the Menagerie, LiftB in the
shaft from the Labs to the Observatory, LiftC outside from the Engine's west balcony to
the Labs', LiftD outside from the docking ring to the Observatory's. The rune altar stands
in the middle of the Summoning Chamber, and eight ring gates (Engine, Observatory, Library
and a debris island, Labs, Summoning Chamber, Menagerie and another island); both are
scenery.

It was laid out by `python3 tools/arena/build_arena_maps.py empyrean` (the structure is
`tools/arena/empyrean.py`, what stands in it `tools/arena/empyrean_dressing.py`, and the
decor laid over both, banners, sconces, lanterns, wall units, turrets and the rest, most
of it drawn only, `tools/arena/empyrean_decor.py`, and the magic,
`tools/arena/empyrean_magic.py`: see "Living magic" below; its last step,
`tools/arena/empyrean_planes.py`, moves by a few millimetres every face that shares a
plane with a face of another kind, so nothing flickers), followed by
`tools/arena/migrate_breakable.gd` on the scene so its stained glass breaks. Like the
other generated arenas the scene is what you edit from here on, and running the script
again **overwrites hand edits**. After moving things, `godot --headless --path . --script
tests/empyrean_test.gd` checks the map and `tests/empyrean_play_test.gd` plays its systems
in a real Practice match.

Things to keep true when editing it:

- Fantasy in its construction, sci-fi in its modification. It is an old tower, built of
  stone, wood and brass with magic in mind, and fitted out with technology long after.
  So nothing structural is alloy: walls, floors, pillars, ribs, pilasters and courses are
  stone (beams are wood). Alloy, screens, conduits and lamps are always something added
  to the stone: clamped on, bolted on, hung from it or stood on its floor. Never plate a
  stretch of wall in metal. Both halves still show in every view, through what is fitted.
- Nothing stepped or blocky: the shell is 48 leaning wall pieces a tier, roofs are cones,
  ramps are smooth slabs (no steps), trims are tubes and bevelled boxes.
- A force field (the kind `field`) is drawn only: Solid stays off. It stands in the wall
  line, which is where the gravity zone ends; if you move the wall, move the zone.
- Only the stained glass (`glass_stained`) breaks. A pane must be a box square to the
  map (they face due east, north and west), stop a little short of the head above it and
  of the jambs beside it, and have nothing running past it in one piece (the ribs are cut
  into one length a tier for that reason), or it will not break.
- A ramp starts and ends with a short level landing (3 degrees of its curve): without it
  the bots' navigation mesh does not join it to the floor beside it. Leave the floor above
  open over a ramp's whole run.
- The ramps wind up over themselves, so the MapRoot has **Winding Floors** ticked; three
  spawn points are on still islands a grapple swing from the tower, so **Bots Grapple** is
  ticked too, and each of those islands has a MapJumpLink back (under `Debris/Ways`).
- No spawn point that can see the altar, and no weapon within 12 m of it.
- No two faces of different kinds in one plane, facing the same way and overlapping (a
  carpet level with a strip of light in the floor, a landing level with the floor it
  lands on): the two flicker. Lay one a centimetre proud of the other.
  `godot --headless --path . --script tools/arena/find_shared_planes.gd -- --map=empyrean`
  lists them (it works on any map), and `tests/empyrean_test.gd` fails on one.
- The river of magic passes every bridge square on to it, three metres to one side, from
  below the bridge's banners to above its rails, and the shaft's floating stones hang
  across the shaft from it (`river_at`, `bridges` and `stone_at` in empyrean.py). The
  generator stops if the river or a thread off it comes too near any of them, and the
  test checks the built map with rays.
- It is drawn with care, because it is far the biggest map (about 350,000 triangles;
  the next has 42,000). On its MapRoot, under **Drawing**: **Decor Shadows** is off
  (blocks that are drawn only cast no shadow, which is most of its triangles drawn once
  instead of three times), and **Detail Range** is 80 (drawn-only blocks no bigger than
  **Detail Size**, 1.5 m, are not drawn from farther off; they are meshed in cubes of
  **Detail Chunk** metres so that works). Its sun's shadow reaches 150 m in two steps.
  A MapMagic box is not drawn beyond its **Draw Range** (90 m). `tools/perf/draw_load.sh
  --map=empyrean` counts the triangles and draw calls in a frame from six viewpoints
  (about 630,000 and 570; before these settings 1,730,000 and 600).
- Bots: its navigation mesh has about 8,800 polygons, more than the navigation server
  will search by default (4,096), which is why `BotBrain._nav_path` asks with a higher
  limit. `godot --headless --path . --script tools/perf/bot_load.gd -- --perf-map=empyrean`
  prints what a four-bot match costs a frame; compare it with `--perf-map=cirrus`.
- Nothing solid inside a lift's beam, and a floor or a balcony edge within a step of it
  at every level bots get off at (each has a MapJumpLink set to Lift, with its Landing).
- Keep the kerb round the core's basin (0.35 m: more than the bots' navigation mesh
  climbs), and the Kill Height 46 m under the root.
- Lighting is the ambient light, the sun and the glowing kinds; there are no light nodes.
  The sky is `game/maps/sky/empyrean_sky.gdshader`; the fog is height fog under the tower
  only (the burn layer's haze).

### Haunted House

`game/maps/haunted_house.tscn` is a very small map for close quarters: a two-storey house,
30 x 22 m inside, with eleven rooms (on the ground floor a double-height Foyer with a
gallery round it and a grand stair, the Dining Room, Parlour, Kitchen, Library and a Back
Hall with the servants' stair; upstairs the Bedroom, with a hole in its floor into the
Dining Room, the Nursery, Bathroom, Study and Upper Hall). It is for free-for-all (and so
Gun Game) and Deathmatch, 16 spawn points and 13 weapon pickups, mostly shotguns, pistols,
SMGs and blades. Outside, seen through the windows, are the grounds at midnight (graves,
dead trees, the fence, the moon): drawn only, and the windows do not break. The front door
is sealed; the pantry door is boarded up, and the boards can be shot through.

The house is haunted, and the haunting changes the map:
- **Floating furniture** (`HauntProp`, a MapIsland): 68 props. Tables, chairs, sofas,
  the piano, the beds, bookcases and the bath float and bob; most are solid cover.
- **The shift**: the house has four layouts. A turn is 22 s quiet, then 3 s of warning
  (a low groan, the lights flicker, the camera shakes, what is about to move rattles,
  and a faint shimmer shows where a wall will be), then a 2.5 s shift in which furniture
  glides to its place in the next layout (cover moves; two bookcases in the Library
  are walls that move) and the doorways change.
- **Doorways that come and go**: 14 of the 20 doorways are there in some layouts and not
  in others. A doorway that goes fades out and is open at once; one that comes back fades
  in and only turns solid once it is all there. Whoever is standing in it then is put out
  of it on the nearer side; whoever furniture came to rest on is put somewhere free beside
  it (`HauntEvent.free_player`, run by each copy of the game for its own player and, on
  the host, the bots).
- **Ghosts** (`MapGhost`): seven, scenery only (no collision, never hit), flying
  their rounds through walls and floors, moaning now and then, writhing while a shift
  comes.

Online, the haunting is like Construction Site's crane: the host owns the clock. The
**HauntEvent** (a MapEvent) starts when the match starts, never ends by itself (also not
when the match is over), and draws a fresh order of layouts by setting its `state` to a
random number; the order (never one layout twice running) and where every prop is at
every moment are worked out from `state` and the clock alone, so every copy shows the
same thing, a reminder every 5 s keeps the clocks together, and someone who joins late
is told both. A new match puts the house back in layout 0.

Bots stand still while the house shifts (the HauntEvent sets `MapRoot.shifting`), and
the arena keeps a navigation mesh for each layout (`MapRoot.layout_state`), baked the
first time the house settles in it.

It was laid out by `python3 tools/arena/build_arena_maps.py haunted_house` (from
`tools/arena/haunted_house.py`; run `godot --headless --path . --script
tools/arena/migrate_breakable.gd` after, for the pantry boards). Before it writes the
scene the script checks that nothing that moves ends up in a wall, a spawn point, a
pickup, an always-open doorway or another prop, in any layout and on the way between
them; `tests/haunted_house_test.gd` checks the real thing.

### Gravity zones, hazards and lifts

Five things Empyrean Tower added that any map can use. All are in `game/arena/`.

**Gravity zones.** A **MapGravityZone** is a volume with its own gravity: a box, or a
round shape on its own y axis whose **Top** makes it taper (a tower). **Gravity** is the
share of normal inside it; the MapRoot's **Gravity Outside** is the share wherever no
zone covers. Each player's gravity is `WorldGravity.scale` (a map event such as
Halcyon's) times their zone's, and eases from one zone's to the next over one second
(`WorldGravity.BLEND_TIME`); after a respawn or a teleport the new place's counts at
once. `MovementController` works the number out once a step (`gravity_scale`) and uses
it for falling, slopes, wall runs, the hang and the glide; the grapple and the bots read
the same number. Projectiles never do. Zones are fixed map data that `MapRoot.build()`
hands to `WorldGravity`, so every copy of the game works out each player's zone by
itself and nothing travels over the network; a map without zones is exactly 1.0. To use
them on another map: set Gravity Outside, add a MapGravityZone node (a plain Node3D with
`map_gravity_zone.gd`) for each place that differs. For "low gravity outdoors", set
Gravity Outside low and fill the indoors with zones of 1.0, as the tower does.

**Force-field doorways** are not a node type: a MapBlock of a see-through, glowing kind
(`field`) with Solid off, in a doorway that stands on a gravity zone's edge. Nothing
stops at it; it only shows where the gravity changes.

**Hazards in arenas.** A **MapHazard** block used to do something only in races (back to
your checkpoint). In an arena match touching one is now a death, reported exactly as a
fall out of the map is (`Arena._physics_process` asks `MapRoot.body_in_hazard()` for each
player it runs, and calls `Player.report_fell_once()`), so it scores the way a fall does.
Races are unchanged. To use one: add a MapBlock with `map_hazard.gd` (a box or an upright
cylinder), pick a glowing kind, untick Solid, and make the danger plain to see. Give bots
a reason not to walk in: a kerb above 0.25 m, or a drop.

**Tractor-beam lifts.** A **MapLiftWell** stands on a floor and reaches **Height** metres
up; anyone inside its **Radius** rises at **Speed** (9 m/s), slowing to a hover over the
last **Ease Top** metres. It only sets how fast you go up, so you look, shoot and steer as
in any fall, and leave by steering or flipping out sideways. A ground slam, a climb, a
glide and the grapple rope are left alone. Each copy lifts the players it runs just
before their own movement step. The node draws the beam in its **Color**; build the
emitter rings from MapBlocks (the lower one under 0.25 m high). For bots, add a
**MapJumpLink** with **How** set to Lift at the beam's foot (as the lift's child) for
each floor to get off at, its **Landing** a Marker3D on that floor beside the beam: a
bot takes it when its goal is 12 m or more above it and the beam is near on its own floor.

**Orbiting islands.** Give a **MapIsland** an **Orbit** (degrees a second) and a **Pivot**
and add an **OrbitEvent** node to the scene: for as long as a match runs it goes round,
carrying riders, pickups and grapple points, in the same place on every copy (the host
owns the clock). **MapDrone** is unrelated: a drone drawn by its script that drifts round
a spot, for looks only.

### Living magic

Scenery that moves, glows and answers to players, made for Empyrean Tower and usable on
any map. None of it is solid, can be shot or hooked, or is sent over the network: every
copy of the game runs it by itself.

- **MapMagic** (`game/arena/map_magic.gd`): a box of air with something drifting in it.
  Put the node at the middle, set **Size** and pick a **Kind**: motes, sparks, pages,
  books (a flock), droplets, bubbles, fish, jellyfish, moths, candles, stars (a
  constellation) or arcs (caged lightning). **Count**, **Piece** (a piece's size),
  **Color** / **Color B**, **Power** and **Variation** shape it. It is one MultiMesh and
  one shader (`map_magic_glow.gdshader` for light, `map_magic_solid.gdshader` for books,
  pages and candles) and all its movement is worked out on the graphics card, so it
  costs nothing on the CPU while nobody is near.
- **MapMagicStream** (`map_magic_stream.gd`): a rope of liquid magic along **Path** (the
  tower's river, and the threads drawn off it), its light running toward the path's end.
- **MapMagicField** (`map_magic_field.gd`): one per map; it is what makes the magic
  answer. Ten times a second it finds each MapMagic with **Reacts** ticked that has a
  player within 4 m (13 ft) **in plain sight** (a ray from the player's chest to the box:
  walls, floors and furniture block it, glass does not) and tells the box, which
  scatters, flees or gutters. It also tells the rune surfaces (`masonry_runes`,
  `ring_flags_*`, `arcane_plates`) where those players are, and runes within reach
  **that face the player** flare (so a wall's far side never lights). Every living
  player and bot counts, yours too; the dead, spectators and anyone crouched and moving
  no faster than a crouch-walk do not (`MapMagicField.noticed`). Its **Event** is the
  map event that livens everything up while it runs (none on Empyrean Tower now).
  Boxes are sorted into bands of height so each player is compared with few of them;
  with 16 players spread through the tower a look takes about 1.6 ms.
- **MapAmbientSound** (`map_ambient_sound.gd`): a quiet loop that belongs to a place.

Empyrean Tower's rules for it (see docs/DESIGN.md): looks and sound only, no fog indoors,
nothing that hides a player, never red, and the three impossible things outside are
drawn as **phantoms** (the `phantom` kinds: pale and see-through), so nobody takes one
for something to land on.

### Terminals and map events

A **MapTerminal** is a console players use by pressing **Interact** (`interact` in
`Settings.ACTIONS`; G by default, rebindable like any key). Halcyon's stands on the dais
in the Control Room. The rules, which the host decides:

- stand within its **Range** (2 m) and press Interact: one press sets it off;
- it cannot be used while its event is running or cooling down, and a press made then
  does not count later: it takes a new press once it is ready.

A terminal can ask for a hold instead: give its **Channel Time** some seconds (it is 0
by default). Then Interact must be held that long; letting go cancels, and so does
leaving the range (walking off, or being knocked out of it) or dying, while taking
damage does not; and it belongs to one player at a time.

Nothing about it is on the HUD. A ring of light over the console pulses gently when it
is ready, flashes full when someone sets it off (through a hold it fills round in blue,
for everyone to see), and sits dim while it is locked; a hum winds down as it goes off.

Its **Event** points at a **MapEvent** node in the same scene. The one kind a terminal
sets off is **GravityEvent** (Halcyon's `LowGravity`): gravity eases down to **Gravity Scale** (0.3)
over **Ease Time** (2 s), stays there for **Duration** (30 s), eases back, and the
terminal stays locked for **Cooldown** (60 s) more. While it runs every light in the map
fades to a deep blue, a soft chord swells in, motes of light drift through the boxes
listed in **Mote Volumes**, and the map's MapSpinners turn at **Spinner Speed** (half).
All of that follows the same curve as the gravity.

How it works underneath:

- `WorldGravity.scale` is the one gravity multiplier. `MovementController` and
  `Grapple` multiply by it wherever they use gravity (falling, swinging, slides
  downhill, and the wall run's and glide's own gravity, scaled the same), so the
  tuning resource's `gravity` (22) is never changed. Rockets and grenades do not read
  it. The arena puts it back to 1.0 when a match starts and when the map is unloaded.
- The host owns the terminal and the event. A player's copy only says when its player
  presses and lets go of Interact there (`Net.terminal_hold`); the host checks the range (and
  the timing, for a hold) and tells everyone the terminal's state and the event's clock
  (`Net.send_terminal_state`, `Net.send_map_event_state`), again every few seconds, and
  to anyone who joins mid-match (`Net.request_map_state`).
- Bots press at a terminal through the same `PlayerInput.interact` a person does.

**To put a terminal on another map:** add a GravityEvent node (a plain Node with
`game/arena/gravity_event.gd`) to the map scene and set its numbers; add a Node3D with
`game/arena/map_terminal.gd` where the console stands (on a floor; build the console
itself from MapBlocks round it) and point its Event at the GravityEvent; fill in Mote
Volumes if you want motes. Nothing else needs changing: the arena, the network and the
bots find them in the scene. A different kind of event is a script that extends
`MapEvent` and fills in `length()` and `_update()`. An event that leaves something
changed after it ends (a LayoutEvent's layout) keeps it in `state`, which the host
sends along with the clock; `_on_match_started()` is where it puts things back.

### Moving parts in killcams

A killcam records the map's moving parts beside the players and puts them back the
way they were at each moment of the replay (`MapReplay`, `KillClip.PropTrack`): the
crane and its load, flying islands, walkways, walls shot through. Without it a death
killcam showed the map as it is now (a crane already swung away under a killer still
standing on its slab) and the results screen showed the map as it was built.

Already recorded, nothing to do: every **MapMover** and **MapIsland** (their meshes,
and the signs and lamps in an island's scene node), **MapDestruction** (cracks and
holes), **CraneEvent**'s rope and **MapSpan**. So a new map whose moving furniture,
doors or platforms are MapMovers or MapIslands is in every killcam as it is.

A new kind of moving part joins the group `MapReplay.GROUP` and has three methods:
`replay_capture()` (how it looks now, as a plain value; called about 30 times a
second, stored only when it changes), `replay_show(state, next, u, holder)` (look like
that, blended `u` toward `next`) and `replay_clear()` (back to live). `replay_show`
must change only what is drawn, never collision or anything the game plays by: a death
killcam plays in the live arena while the match goes on round it. `MapReplay.draw_at`
draws a mesh somewhere else without moving the node (what MapRoot does for movers).
Parts are found by their path from the MapRoot, so the nodes must be the same every
time the map is built (the results screen replays in a fresh copy of the map).

A terminal's **Bots** box (ticked by default) says whether bots walk up to it and use
it now and then. Untick it for one they cannot walk to, or they stand about under it.

### The crane

The Construction Site's tower crane works. Its parts are all in the `Crane` group of
`game/maps/construction_site.tscn`:

- **Mast**: hollow, 2 m square inside, so it is a chimney to wall-jump up like the lift
  shaft (its walls are hidden boxes; the lattice and the guard mesh are drawn only). A
  ramp leads onto its base and in at the south door. It is open again 20 m up, where the
  **Tie** gangway comes across from the corner of the tower's 20 m steel, and at the
  top, where a collar is level with the deck that turns round it.
- **Jib** (a MapIsland whose Pivot is the middle of the mast): everything that turns.
  The deck round the mast head, the cab, the jib and counter-jib with a walkway along
  their top, the trolley. The cab has a floor, a door at the back and glass that
  shatters; the cabinet behind it and the box on its roof are the steps up to the jib.
- **Lever** (a **MapLever**, in the cab): a MapTerminal in everything but its looks. It
  draws a lever with a red knob that leans back while it is ready and is thrown forward
  while the crane works, and a lamp beside it that is green when it can be pulled and
  amber when it cannot. Its Bots box is unticked.
- **Hook** (a second MapIsland with the same Pivot): the slab on its slings. Solid, so
  it is a platform, and whoever stands on it rides along.
- **CraneEvent** (a MapEvent): what the lever's Event points at. It has a few stops
  (**Turns**: degrees the jib is turned from where the scene has it; **Heights**: metres
  the load hangs above or below where the scene has it) and a **Route**, the order it
  visits them in, round and round. One pull of the lever is one move: the load is
  hoisted to **Carry Height**, the jib turns, the load is lowered, and the lever stays
  locked for **Cooldown** more seconds. On the Construction Site the stops are the
  tower's steel bay (where the scene has it), the south-east yard and the north-west
  yard, and the route is tower, south-east, tower, north-west: about 13 s a move.

The two islands are placed from the event's clock and `state` (how far round the route
it has got) alone, so the crane is in the same place on every copy of the game, also
for someone who joins part-way through a move, and a new match puts it back at the
tower. The hoist rope is drawn by the event between two markers (**Rope Top** in the
jib, **Rope Bottom** in the load), because its length changes. Its sounds come from the
top of the mast and carry over the whole site.

If you move a stop, keep the load's way clear: Carry Height must lift it over whatever
stands under its arc, and a stop in the yard must leave standing room under the load (it
is not a hazard, and must not squash anyone). `tests/site_test.gd` sweeps the slab along
every move of the route and looks under every stop, climbs the mast, throws the lever
with a player in the cab and rides the slab to both yards. The loading zones painted on
the ground mark where the slab comes down; they are ordinary drawn-only blocks, so move
them with the stops.

Both islands have **Over Ground** ticked. Bots take a map with MapIslands in it for
islands over a drop (no free swings on the grapple, no jump or dodge without floor in
sight); Over Ground says this island is a machine on a map with solid ground, so it
does not count.

Turns, Heights and Route are typed arrays (`Array[float]`, `Array[int]`), not packed
ones, on purpose. Godot's export drops a packed array (PackedFloat32Array,
PackedInt32Array, PackedStringArray) that a scene sets on a node whose script does not
run in the editor: the value is there when you play from the editor and gone in the
exported game. v0.1.48 shipped that way, with a lever that clacked and a crane with no
stops, and Cirrus and Empyrean Tower had been losing their lit, flaring and pulsing
kinds the same way (LayoutEvent uses typed arrays now too). Give a
new map script's list settings a typed array; `tests/map_scene_test.gd` fails if a map
scene sets a packed array on a node whose script is not a `@tool` script. To look at
an exported copy: `godot --headless --export-pack "Windows Desktop" out.pck`, then
`godot --main-pack out.pck`.

To put a crane (or anything else that swings a load) on another map: two MapIslands
with one Pivot (Over Ground ticked if the map has ground under it), a CraneEvent
pointing at them, and a MapLever or a plain MapTerminal pointing at the event.

A **MapSpinner** is a group of MapBlocks that turns round its own y axis (tip the node
over for another axis): Halcyon's centrifuge ring, outside the hull. It is decoration
only: drawn, never solid, and each copy of the game turns it by its own clock. That is
why it is not a MapMover (a mover is solid, carries riders and runs off the race clock,
so plain movers are for race maps; in an arena the one kind of mover is a MapIsland,
below, which runs off its LayoutEvent's, OrbitEvent's or CraneEvent's clock). MapHazard was race-only
when Halcyon was built, so its pit uses the Kill Height and its decks are joined by fixed
ramps (hazards work in arenas now: see "Gravity zones, hazards and lifts").

### Maps of flying islands

Three node kinds, all in `game/arena/`, none of them tied to Cirrus:

- **MapIsland** (`map_island.gd`, a MapMover): a group that flies. Where it sits in the
  scene is its home; a LayoutEvent can stand it anywhere round **Pivot** (so many
  degrees round, so many metres up, so many metres out) or park it far below the map,
  hidden and with nothing to bump into. In the game it is one moving body, whatever is
  in it: blocks, spawn points, weapon and power-up spots, grapple points, jump links
  and breakable glass all ride along. `up` says people can be on it, `doomed` that it
  goes down at the next move.
- **LayoutEvent** (`layout_event.gd`, a MapEvent, no terminal needed): a clock that runs
  for as long as a match does. Each turn: **Hold Time** (60 s), a tick or a tock every
  second (quiet everywhere, a little louder near **Tick From**); then the bell and
  **Windup Time** (8 s) of warning, in which the doomed islands' engines and **Doom
  Kinds** (lamps) turn **Doom Color** and sputter and they sag by **Doom Dip**; then
  **Move Time** (4 s): doomed islands fall **Down** metres, staying ones glide, new ones
  rise. **Up Count** (2) islands are up at a time. The pool it draws from is under
  **Arrangements**: Drift's turns, how far Close comes in and Far goes out, Far's
  heights, Split's height. It also blends the look (the second look's sun, ambient
  light, fog colour and **Lit Kinds**), and during the warning and the move the camera
  rumbles, the **Flare Kinds** (engines) burn bright, the clouds swirl and scraps of
  paper blow through the **Scraps** box. Nothing is on the HUD. MapSpinners with
  **Driven** set to Countdown are clock hands it turns (once round per turn, at twelve
  when the bell goes); one set to Swing is the bell, which it rocks.
- **MapJumpLink** (`map_jump_link.gd`): tells bots how to cross where the navigation
  mesh has no way. **How** is Grapple (hook, ride the rope, let go), Leap (run off
  toward the landing), Hop (sprint at the landing and jump at the edge: a gap a running
  jump clears, or a step up a ledge climb takes) or Boost (sprint, jump at the edge,
  fire the rocket boots toward the landing, steeper the higher it is, and glide on until
  it can drop onto it: about 24 m of open sky, up to about 6 m higher), Lift (ride the
tractor beam here up to the landing) or Gate (step through the ring gate Hook names while
it is open). **Rise Min** and
  **Rise Max** (Timing) are for parts that keep moving: the bot waits at the takeoff
  until the landing will be that far above it (below, if negative) when it comes down,
  **Flight** seconds on; both zero, any time. **Hook** names what to hook, or **Hook Group** says "the nearest
  node of this group" (a hook found that way may have a child called Land: the
  landing). **Landing** is where it comes down (empty: the link itself). With **Round
  From** and **Round Radius** the takeoff is worked out: on a round floor, facing
  wherever the landing is just now. **Leaves** marks a crossing that leads off its
  island: the only kind bots may take from a doomed island. A link on an island that is
  down or on its way cannot be used. Bots use one only when walking will not get them
  where they are going, and will take two in a row (island to quad, quad to island).
  A link inside a plain MapMover rides it (MapRoot moves the mover's node along). On a
  map of many such parts (Sky Island) bots work out a route part by part instead: each
  part is a place, each link a way from one to another, the shortest way wins, however
  many links long.
  A plain MapMover keeps moving after the bots' navigation mesh is made, so bots ask
  their way in the mesh's own frame: `MapRoot.to_nav()` puts a point back where the part
  under it stood when the mesh was made, `from_nav()` carries a path point forward to
  where that part is now. (A MapIsland is left out: its mesh is redone for each layout.)

(**MapSpan**, a walkway that runs out and draws in, is still in `game/arena/` from the
first version of Cirrus. No map uses it now.)

How it works underneath:

- The host owns the LayoutEvent: it starts the clock when a match starts, keeps it, and
  decides every arrangement a whole turn ahead (`pick_first`, `pick_after`). An
  arrangement is one small number (`LayoutEvent.pack`: which set of islands, which
  kind, a throw of the dice, the look), and `state` holds the present one and the next
  one together. Every copy places the islands from the clock and that number alone, so
  they are in the same place for everyone, also for someone who joins part-way
  (`Net._map_state_request`), and everyone knows which islands are doomed. With the
  clock stopped every island is up at its home. It never runs in a team mode.
- `MapRoot.update_movers()` moves each island's body in the physics step, and its node
  with it, so everything inside rides. Each copy of the game moves its own player, so
  riders are carried by the engine's moving-platform handling; the player's view turns
  with the island. Other players are drawn a little in the past, so their positions
  are carried through `MapRoot.carried()` to where the island is now. Pickups follow
  through `move_to()`. A grapple hook stays on the body it hit (`Grapple.carrier`).
- Someone on a doomed island is not killed by the event: the island carries them under
  the Kill Height, and the arena's ordinary falling-out-of-the-map check does the rest.
- `MapRoot.open_spawns()` is what the arena picks a spawn point from: those on islands
  that are up and not doomed, else those on ground that never moves. When the clock
  first starts, anyone standing on an island that is not in the first pair is put back
  at a spawn point (`LayoutEvent._rescue`).
- Breakable pieces inside an island are built as children of its body
  (`MapDestruction.add_riding`), so they break as usual wherever the island is.
- The bots' navigation mesh is baked once per arrangement: again when a move settles
  (well under a second), kept, and thrown away when something breaks. Parked islands
  are left out of it. While the map moves or the new mesh is not ready
  (`MapRoot.shifting`, `nav_pending`), bots stand where they are and keep fighting.
  During the warning a bot on a doomed island (`MapRoot.doomed_at`) drops everything
  and makes for the crossing that leads off it. On a map with drops bots also check
  for floor ahead before a dash, a hop or a dodge.

**To make another map of flying islands:** put each part that flies in a MapIsland at
its home; add a LayoutEvent and set its times, its pool and the second look; give every
island a MapJumpLink off it (Leaves ticked) and one onto it, with grapple points to
hook; put a few spawn points on ground that never moves; tick Bots Grapple. Then check,
as the Cirrus test does, that the grapple crosses in every arrangement and that
nobody who stays on a staying island ends up inside geometry.

### Race maps

`game/maps/rooftop_run.tscn`, `foundry.tscn`, `sky_ruins.tscn` and `summit_plunge.tscn` are ordinary maps
(MapBlocks in groups, so one click picks a whole piece and F6 plays it as a race) with
four more node types:

- **MapCheckpoint** (under `Checkpoints`): a gate. **Number** says the order (1, 2, 3...),
  **Finish** marks the last one, **Opening** is its width and height. Racers must pass
  them in order; the one before is where you come back to.
- **MapHazard**: a MapBlock that sends you back to your checkpoint when you touch it
  (molten metal, live wires, the presses). Same Size, Kind and Solid as any block.
- **MapMover**: a group that moves. Its blocks ride along (and carry whoever stands on
  them). **Travel** is how far it goes and comes back, **Period** how long the round
  trip takes, **Hold** how long it rests at each end, **Spin** turns it (degrees a
  second, for the sweeper arms) and **Phase** staggers it against its neighbours.
  Everyone sees them in the same place: they run off the race clock.
- **MapRoutePoint** (under `BotRoute`, in running order): the line the bots take, and
  what they do at each point (run, jump, long jump, dive jump, flip dive, slide, crawl,
  wall run, wall jump, chimney, grapple to the point plus Aim, wait for ground, wait for a
  clear path, boost jump, boost up, glide jump). **Boost** on a grapple or glide-jump point
  also fires the rocket boots toward the next point (as it lets go of the rope, or in
  the glide). If you move an obstacle, move its route points with it.

Falling below **Kill Height** sends you back too. A map counts as a race map when it has
checkpoints; `game/arena/maps.gd` lists each map with its game, `ffa` or `race`, and the
menus only offer a map for its own game.

The four courses were laid out by `tools/race/build_race_maps.py` (the sections are in
`tools/race/sections.py`: gaps, vaults, climbs, wall runs, chimneys, grapples, pistons,
presses, sweepers, and the ones built for the newer moves: rocket gaps, boost-up walls,
glide gaps, ski jumps, grapple swings and belly-slide chutes, with the distances each
move covers at the top of that part of the file). Edit a map in the editor and the
change is yours to keep; running the script again rebuilds them all from scratch and
overwrites hand edits. To try a section on its own, build the test strip
`race_lab` (`LAB='[["boost_gap", {"d": 20}]]' python3 tools/race/build_race_maps.py race_lab`,
any sections and arguments) and race it with `--map=res://game/maps/race_lab.tscn --autopilot`.
After changing a course, `MAPS=<map id> tests/run_race_test.sh` checks that bots still get round.
`game/match/race_state.gd` (the `Race` autoload) runs the race rules and
`game/bot/race_brain.gd` the race bots.

## Tuning movement

All movement numbers are in `game/player/movement/movement_tuning.gd`, each with a comment
saying what it does. Change a number, press F5, and feel the difference. Tell me what
feels off and I will tune it with you.

## The robot models and their animations

The player robots are built by code, not drawn in a modelling program, so they can be
changed by editing numbers and rebuilding. Every character shares one skeleton and one
set of animations; only the shape differs. Everything is in `tools/robot/` (needs
python3 with numpy):

| File | What it holds |
| --- | --- |
| `designs.py` | Each robot's shape, and the materials. `PLAYABLE` lists the ones built for the game (Needle, Vanguard, Kestrel, Bulwark, Rivet, Specter, Orbit, Templar); the unused draft, Brick, is kept |
| `creatures.py` | The Character Creator's creatures (a person, a goblin, a frog...): each one's shape, modelled round the same skeleton, and their materials. `KITS` lists them |
| `rig.py` | The skeleton (bone names and positions), the hand poses (`HANDS`) and the pose solver |
| `hands.py` | The robots' hands: one hand (palm, trigger finger, three fingers that move as one, thumb), which each design takes at its own bulk and in its own materials |
| `animations.py` | Every animation, written as key poses: body clips and first-person arm clips |
| `weapons.py` | Every gun's shape and materials, and where the left hand holds each long gun |
| `weapon_anims.py` | The long guns' own clips: how each is held, carried when sprinting, fired (pump, bolt), reloaded, and the first-person arm poses for each |
| `build.py` | Writes, for each playable robot, `game/player/robot/NAME.glb` (full body) and `NAME_arms.glb` (first-person arms and guns), and for each creature `game/player/robot/kits/NAME.glb` (its mesh only: no guns, no animations). `--kits` writes only the creatures (a few seconds) |

After changing any of them:

```
python3 tools/robot/build.py
godot --headless --path . --import
```

To look at the result without opening the game (these render on a machine with no
graphics card, so I can check poses myself):

- `python3 tools/robot/sheet.py OUT_DIR run sprint:8 death:6:0:1.3` renders side and
  front contact sheets of clips (name, frames, start and end time). Add
  `--glb game/player/robot/vanguard.glb` to look at another character.
- `tools/robot/preview.sh JOB.json` renders any set of robots, poses and camera angles
  described in a job file; the format is at the top of `tools/robot/preview.gd`. It can
  also drive a robot with the game's real animator from made-up movement.

**Joints.** A body is stiff pieces, each riding on one bone, so a joint only stays
closed if what fills it is centred on the joint's own point (the bone's place in
`rig.py`). The pattern, in `designs.py` above `needle()`: a dark core (`kit.bead`) at
that point; each half of the limb ending in a sleeve a little wider than the core, its
rim `SEAM` short of the point and its open end faced dark (`_sleeve`); elbows and knees
get the core lying across the limb with a pin through it (`_hinge`). Straight, a slim
dark band shows between the sleeves; bent, they slide over the core and nothing opens.
Keep a core no smaller than the sleeves' inside, and do not go back to `ball()` for a
joint: its flat faces sit well inside its radius, which is where the old gaps came from
(it is still fine for a shoulder or hip ball sunk into the torso, and for ornaments).
All eight robots are built this way (`_wrist` and `_ankle` are the cores every design
shares; a thin strut under a shoulder gets one sleek taper where it leaves the ball, no
bulge). The Templar's elbow cop is its elbow's core, and Orbit's knee keeps the player's
colour as its core.

The Character Creator's creatures (`creatures.py`) are built the same way, dressed to
match: a soft body's core is a rounded `knob` in the limb's own colour, a little wider
than the limb, with each half ending `SOFT` short of the joint's point, inside it, so it
reads as a rounded elbow or knee and not as a part. `arm()` and `leg()` do this (wrists
and ankles included) for every body that uses them; the few with limbs of their own
(the goblin's and imp's bare knees, the snowman, the wizard's robe, the zombie's torn
leg) do the same by hand. The stick-limbed ones (Bones, Quackers' legs, Peel) already
had joints wider than their sticks.

**Any torso on any legs.** `kit.plug` gives a part a rounded core at the point it turns
on, as wide as the part itself there and in its material: every torso gets one at the
waist (`designs.waist`, robots and creatures alike), and every creature one at the belly
and one round the neck's stub (`creatures._close`). A mixed character's torso then rests
on something round whatever legs are under it, and nothing opens at the belt when it
leans back to aim.

**Colours and finish.** `designs.py` writes colours the way the game's code does (sRGB)
and turns them into what a model file holds, as `weapons.py` and `creatures.py` do, so
the robots' armour is the same white as the guns' plates instead of a brighter one that
lost its shading in sunlight. Surfaces are satin (roughness about 0.7, hardly any
metal); only the glowing parts are shiny.

**Idle habits.** Every torso, robot or creature, has its own way of standing still: a
clip named `idle_<torso>` (`IDLES` in `animations.py`), a whole number of the plain
idle's breaths long, with one small thing in it (Needle cocks its head, Rivet taps a
boot, Bulwark sags and hitches back up, the frog puffs its throat...). It goes by the
torso (`RobotModel.idle`), so a Character Creator body stands the way its torso does,
and a torso with none uses the plain `idle`. The habit clips are `lean`: they hold only
the bones that move (`Clip(..., lean=True)` in `rig.py`), which keeps 28 of them from
bloating every model file. A new torso needs its habit added to `IDLES`.
`RobotAnimator` lays it over the plain idle only while standing still and not shooting
or reloading. A habit must never turn the chest or move it sideways (the gun is held
from the chest; `_steady` keeps the chest in place while the hips move under it), may
raise or lower it a little, and must not look like an action. `tests/robot_test.gd`
checks the first two.

**Landing.** `land` is a short strip (dip, then up a little past standing, then settle),
not one pose: `RobotAnimator` plays it through once over the base pose, as strong as the
fall was hard.

**Feet on steps and slopes.** Standing or crouching still, each foot goes to the ground
that is really under it. `Player._feet_ground()` casts a ray down through each foot and
hands the two heights to the animator (`RobotAnimInput.feet`, how far the ground under
each foot is above or below the player's own floor). `RobotAnimator._plant_feet` then
bends that leg at the knee to put the foot there, and lowers the hips a little when a
foot has to reach down (`FEET_REACH` and `FEET_DROP` cap both). It fades out as soon as
you move faster than `FEET_STILL`, so no moving clip is touched, and it is looks only:
the collision capsule never moves. In `preview.gd` a puppet step takes `"feet": [l, r]`
and a shot takes `"blocks"` to stand the body on.

**Spins.** The flips turn at a steady speed with a short ease in and out
(`SPIN_IN` / `SPIN_OUT` in `animations.py`), keyed so the speed never jumps. Change the
two together or the flip will hitch at the seam.

In the game, `game/player/robot/` holds the code: `robot_animator.gd` decides what the
body shows from the movement state (the same way for you, other players and the bot),
and `view_model.gd` does the first-person arms.

**Guns.** Every model file holds all four guns; `RobotModel` keeps only the picked one's
mesh parts (the materials are named `GUN.KIND`, e.g. `rifle.accent`). A long gun's clips
are the base name plus the gun (`aim_rifle`, `fp_reload_shotgun`, `fire_sniper`); the
game falls back to the plain (pistol) clip when a gun has no version of one. Each gun's
shots leave from its own marker bone (`muzzle_shotgun`, ...). The numbers for every gun
are in `game/combat/weapon_data.gd`. The akimbo pistols are the one weapon in two hands:
the left gun rides on its own bones in the left fist (`pistol_l`, `pistol_l_slide`,
`pistol_l_mag`, `muzzle_akimbo_l`; pose specs move them with `pistol_l`, `slide_l` and
`mag_l`), the shots alternate between `muzzle_akimbo` and `muzzle_akimbo_l`
(`WeaponData.muzzle_bone_left`), and `fire(left)` kicks only the arm that fired. A model made in Blender later can
replace the .glb files as long as it keeps the same bone and clip names.

**Alt fire.** The `alt_fire` action (right mouse by default) is read with the trigger in
`Player.read_local_input` into `PlayerInput.alt_fire` (held) and `alt_fire_pressed` (this
frame), and is cleared wherever the trigger is (mouse not captured, a frozen player).
What it does is `WeaponData.alt`: "tilt" (Pistol, Akimbo) is a hold, "sticky" (Grenade
Launcher) a press. `Player.alt_held()` says whether a player is holding a hold-style alt
fire: for your own player and bots from the input, for everyone else from bit 22 of the
animation flags in their snapshots (`RobotAnimInput.make_flags`, `alt_of`), which the
killcam's frames carry too, so a pose built on it shows on every screen. A press calls
`Player._alt_pressed()` from `_update_weapon` (alive, not racing, a weapon in hand).

**Your own body in first person.** The arms and gun you see are the separate arms
model on the camera (`view_model.gd`). The legs and torso are your real body: the same
skeleton and the same animator everyone else sees, drawn for your camera by a second
mesh with the head and arms left out (`RobotModel.add_view_mesh`; the full mesh stays
hidden from your camera and only casts your shadow). Three things make it look right
from inside, all in `robot_animator.gd` and switched by `first_person`:

- The torso stays upright under the camera instead of leaning with your aim or with
  the run, and `place_for_view` keeps the neck just below and behind your eyes, sliding
  the body back as you look straight down so you see your legs and not the inside of
  your chest.
- A move whose normal animation would look wrong from inside has a second version
  made for the camera, named `view_` plus the clip's name (`view_flip_back`,
  `view_slide`, `view_roll`...). When one exists it is played for you instead; everyone
  else still sees the normal clip, and `animator.source` reports the normal name. The
  flips are the main case: the body does not turn over in front of a level camera, the
  legs tuck and sweep through the view instead.
- To add one, write the function next to the others under "The body as you see it in
  first person" in `animations.py` using `_seen(lean, left leg, right leg)`, list it in
  `view_clips()`, rebuild, and look at it with a first-person puppet shot in
  `preview.sh` (`"first_person": {"pitch": -30, "eye": 1.6}`) before trying it in the game.

To photograph a move in the real game, script it, for example a backflip:

```
godot --fixed-fps 60 --path . -- --practice --game-clock --hold=2.0:jump:0.1 \
    --hold=2.4:jump:0.1 --screenshot=2.6:/tmp/flip.png --quit-after=3
```

Use the Vulkan renderer for this; the compatibility renderer draws the first-person
arms wrongly.

**Adding a character:** write its shape as a new function in `designs.py` (model it
around the shared skeleton in `rig.py`), add its name to `DESIGNS` and `PLAYABLE`,
rebuild, then list it in `game/player/robot/characters.gd` with a display name and a
one-line description. The menus, the lobby, the network and the tests pick it up from
that list. If its forearms are bulky, give it an entry in `FP_SLIM` so the
first-person arms do not fill the view.

**Adding a creature** (a body for the Character Creator that is not a full robot): write
its shape as a function in `creatures.py` and add it to `KITS`, run
`python3 tools/robot/build.py --kits` and import, set `meshes/ensure_tangents=false` and
`meshes/generate_lods=false` in its new `.glb.import` (as the others have; import again),
then list it in `KITS` in `game/player/robot/characters.gd`. A creature has no guns or
animations of its own: a character with a creature's torso uses the first robot's
skeleton, clips and guns, and its first-person arms are cut from the creature's own arm
triangles (`RobotModel._kit_arms_mesh`; bulky arms get an entry in
`Characters.KIT_FP_SLIM`). What a material is called decides how the game treats it, by
the part of its name before the first `_`: `armor_*` takes the main colour and the team
colour, `extra_*` takes them too but is left out when accessories are fitted (ears,
fins), `trim_*` takes the second colour, `mark_*` and `hair_*` the detail colour,
`skin_*` and `flesh_*` the skin tone (same split as armor and extra), `hair_*` and
`shell_*` count as the head's surface for fitting hats, `eye_*` is where glasses sit, and
`accent` is the player's colour. Anything else is drawn as built. (`RobotModel.CHANNELS`
is the list.) A creature's shape functions use plain names ("belly", "leather"); `ROLES`
in `creatures.py` says which of them are its second and detail colours, and the build
writes them as `trim_belly`, `mark_spot`. The robots' files keep their own names:
`Characters.material_role` maps them as the model is put together (every robot's `joint`
is its second colour and `detail` its detail colour; the Templar's `steel`, `cloth` and
`cross` are its main, second and detail colours).

**Adding an accessory:** add it to `CustomCharacter.ACCESSORIES` under its slot and write
a function of the same name with a leading underscore in
`game/player/robot/accessories.gd` (`"fox_tail"` is built by `_fox_tail()`), from the
helpers there (`_ball`, `_tube`, `_cone`, `_plate`...), placed with the measurements in
`f` (the head, chest and waist of the body it is on). The creator, the id check and the
test pick it up from the table. Its colour button repaints the material that
covers most of it; if that is the wrong one, name the right one in `Accessories.MAIN`.

**Adding an achievement:** add a line to `LIST` in `game/core/achievements.gd`: an id, a
name, its kind (`group`: the tab it is under, an id from `GROUPS`), the count it watches (`stat`), the `goal`, the line under its name (`what`) and
the items it unlocks (`rewards`: `"part:ninja"`, `"paint:gold"`, `"<slot>:<accessory>"`
such as `"hat:crown"`, or `"card:sunset"` and `"icon:skull"`). An item named by no
achievement is free. The counts are bumped in `_on_kill` (from a kill's tags, see
`KillScore`, and its weapon, score, distance and speed), `_on_died`, `_on_match_over`,
`_on_team_event` and `_on_gate`; for a new kind of count, call `Achievements.add("name")`
where it happens. Something that should count once each (a weapon, a course, a medal)
goes in a set: add it to `SET_STATS` and call `_collect("set", "thing")`. The page, the
creator's locks, the toast and the test read the list. A new race course needs its
bronze, silver and gold times in `MEDALS` (run it with `--bot=3 --bots=3 --autopilot
--sync-log --map=ID` and read the `RACE_GATE ... FINISH` lines: gold is about the
Expert bots' time).

**Adding a calling card or an icon:** add a line to `CARDS` or `ICONS` in
`game/ui/calling_card.gd`: an id, a name, and for a card a `pattern` (one of the ones
`_draw_pattern` knows, or a new branch there) and its three colours `a`, `b`, `c`; for
an icon a `glyph` (a branch of `_draw_glyph`, drawn with the `Pen` there: shapes in a
-1 to 1 square, which the pen also draws once in a dark colour as the glyph's shadow),
its `color` and `accent`, the plate's colour (`back`) and `shape`, and if it should
stand out the rim's metal (`rim`: `BRONZE` or `GOLD`) and `rays`.
It is free unless an achievement's `rewards` name it (`"card:<id>"`, `"icon:<id>"`).
The picker, the lobby and the test read the tables.

**Hands** have fingers: a trigger finger, three more that move as one, and a thumb, two
bones each (`rig.py`: where the knuckles are, from the middle of the fist). How a hand is
held is a pose in `rig.HANDS` (open, flat, relaxed, fist, gun, trigger, handle, support,
foregrip, pinch): eight numbers that blend. A clip's pose can say `"fingers_l"` /
`"fingers_r"`; left out, the right hand is round a gun's grip and the left is under a long
gun or relaxed. The left hand under a fore-end is cupped, palm up (`weapon_anims.CUPPED`),
so a gun's `weapons.SUPPORT` point is 2 cm above the fore-end's underside; a gun with an
upright handle there says `"upright"` and it is held like a second grip. What the clips
cannot know, the game sets (`game/player/robot/hands.gd`, from the one-frame `hand_...`
clips): a blade's handle in the fist (`MeleeSwing.hold`), the akimbo pair's left gun. The
Character Creator's other bodies have the same hands in their own colours
(`creatures.hand()`: which material the palm and fingers, the back of the hand, the band
across the knuckles and the joints each take). To look at the hands on every robot (open,
a fist, on a pistol, a sword, under a rifle): `python3 tools/robot/hand_sheet.py OUT.png`;
on other bodies, name them: `python3 tools/robot/hand_sheet.py OUT.png frog yeti`.

**Guns** share the melee weapons' look (gunmetal frame, armour-plate panels, steel
barrels, lit parts in the player's trim colour: the `glow` kind, which
`RobotModel.set_gun_glow` can dim and brighten). Each is built round fixed points: the
barrel line and muzzle (`rig.py`), where the hands go (`weapons.SUPPORT`, and the bolts,
handles and magazines in `weapon_anims.py`). Keep those where they are when reshaping
one. Each gun's vents are added with `_vent()`, on a bone of their own (`pistol_vent`) that a
reload opens: a flap or louvres on most, the barrels themselves on a break-open gun. To
look at guns on their own: `tools/combat/gun_preview.sh OUT_DIR
--guns=pistol,rifle`; for before/after sheets of every gun by family:
`python3 tools/combat/gun_sheet.py OUT_DIR BEFORE.glb`.

**Reloads** are clips like the rest (`reload_<gun>`, `fp_reload_<gun>`), each as long as
the gun's reload time: the pistol's in `animations.py`, the other sidearms' in
`sidearm_anims.py`, the long guns' in `long_reloads.py` (family by family: each gun's own
flourish is described at the top of its function). A long gun is held relaxed and low,
off to the right in first person (`weapon_anims.HOLD`, `FP_HOLD`), and each is fitted so
the left hand reaches its fore-end with the elbow bent (`_fit`). A gun loaded a round at
a time has a one-round clip that loops and a `reload_end_<gun>` clip (`long_reloads.ENDS`)
that the animators play once the gun is full and the reload was not cut short by a shot:
the gun can already fire, and firing cuts it short. A clip with a part that spins about
its own middle is baked at 60 frames a second (`long_reloads.FPS`), or the part wobbles. A pistol is held in both hands, the left wrapped round the right
(`animations.wrap_l`); in first person only the arms are drawn, so the clip puts the
shoulders where both hands can reach a gun held off to the right (`FP_BODY`). A reload
is written as the right arm's poses, the left hand's (places on the gun are worked out
from where the gun is: `View.fist_on`, `View.palm_on`), the fingers (`rig.HANDS`) and
the gun's parts, including whatever the left hand carries to it. What a clip cannot do
is the game's: `game/combat/reload_fx.gd` throws the spent cell or casings (`SpentCell`:
looks only, each copy of the game throws its own), dims and surges the gun's lit parts,
hides the gun's own cell while the new one is out of sight, and puffs steam and smoke
(`ReloadPuff`). Its table is timed to each clip's keys, and so are the sounds
(`RELOAD_STEPS` and `RELOAD_END_STEPS` in `game/audio/sfx_list.gd`): change a clip and
change both. To check that no hand is asked to reach further than its arm, solve the clip
and compare each wrist with where its pose wants it (every reload was checked this way). To film one
without opening the game: `tools/combat/reload_preview.sh revolver OUT_DIR --speed=0.5
--close` (add `--cut=0.5` to see it cut short half way).

**Melee weapons** are not in the model files: `game/combat/melee_model.gd` builds each one
from faceted shapes (`game/combat/melee_kit.gd`: plates cut from an outline, bars, lofted
blades), in weapon space with the grip at the origin and the blade up +Y. To look at one
on its own: `tools/combat/melee_preview.sh hammer OUT_DIR` (side, three-quarter and face
on, then close up). How far each rests lower in first person is `MELEE_REST_VIEW` in
`view_model.gd`.

**Melee swings** have no clips either: `game/combat/melee_swing.gd` animates the weapon
(where the grip is, which way the blade points, how far the body turns and leans) and
bends the arms to hold it. Each weapon's blows are keys in its `MOVES` table: a ready
stance, two taps that take turns and a heavy blow, each with where it winds up to,
where it lands and where it ends; a key named `fp_...` is used instead in first person.
A weapon's `"air"` entry is its move off the ground: the same three keys, with `axis` and
`turns` (the body goes round that axis that many times, from the start of the wind-up to
the hit), `wind` (how much of that a full wind-up covers), `after` (turns it carries
on round after the hit) or `dive` (no turn: the body tips back, then over into the blow), and `legs` (the
legs' own pose wound up and as it lands: the superman punch's knee and kick back). The ground slam's pose is `SLAM_FALL` and `SLAM_HIT` in the same file.
Change a number and film it:

```
tools/combat/swing_preview.sh hammer OUT_DIR            # front, side and behind, quarter speed, OUT_DIR/swing.mp4
tools/combat/swing_preview.sh hammer OUT_DIR --step=0.0166667 --blows=heavy   # full speed, the heavy blow only
tools/combat/swing_preview.sh hammer OUT_DIR --step=0.0083333 --blows=air,slam   # half speed: the mid-air move, then a ground slam
```

For first person, film the real game: `godot --fixed-fps 60 --write-movie OUT/m.png --path .
-- --practice --map=testing_grounds --game-clock --weapon=hammer --spawn=47,0,2,-90
--hold=1.0:fire:0.13 --hold=2.5:fire:1.3 --quit-after=4.5` stands you in front of a target
dummy, taps once and then lets go a full wind-up (add `--speed=0.25` for slow motion).
`tests/weapon_test.gd` checks every blow: the left hand stays on the handle, the blow
ends back at ready, the taps take turns, a mid-air move's turn ends as it lands, and what a
ground slam does at each distance. `tests/movement_test.gd` checks the hang and the slam's fall.

**On the grappling hook's rope** the body has no clip either, once the rope has pulled
tight: `game/player/robot/rope_swing.gd` (RopeSwing) hangs it from the left arm. The hips
lean toward the line of the rope, the legs trail further along it, and the chest and head
stay nearer upright, on your aim. Each part follows where it should hang on a spring of
its own (the hips, then the thighs, then the shins, and the gun arm), so the legs swing a
beat after the body when the rope changes direction; the numbers at the top of the file
say how far each leans, how fast it follows and how soon it settles. The moment the rope
pulls tight the body takes a jolt, harder the more slack the winch took in. The hips face
along the swing while the waist turns to keep the chest on the aim, steering along the
swing works the legs (a flag in the movement snapshot, so everyone sees it), a cape and a
tail stream behind (`RobotModel.settle_sway`), and letting go on the way up, fast, rolls
the body forward once (`FLIP_RISE`, `FLIP_SPEED`; a shot or a swing hurries it). The gun
hangs at your side until you shoot: a shot brings it up at once, and it drops again
`ROPE_AIM_HOLD` seconds after the last (`robot_animator.gd`); a blade hangs point down.
`RobotAnimator` lays all this over its own steps and `ViewModel` moves your arms in first
person with the same springs (the gun low and canted but still in view: `ROPE_GUN_...`
in `view_model.gd`). It is looks only: nothing in it moves the player, and it is worked
out from what every copy of the game knows about a player (`RobotAnimInput.hook_taut`,
`hook_slack`), so other players and killcams hang the same way. The slack before the rope
is tight is as it was.

**Diving into the rope.** If you are in a dive when the rope pulls tight (dived after
firing, or fired in the dive), the dive gives way to the rope: the state becomes GRAPPLE,
with the rope's steering and its jump off, and `MovementController.dove_in` remembers it
until you arrive (within `grapple_pull_stop` of the hook, or no longer closing on it:
`DIVE_IN_SLOW`). Let go before that and the dive carries on and lands as a dive does;
come down on the floor still on the rope with the key held and it drags you on your
belly (only a hook below your chest keeps you down: a higher one lifts you off). A
hook nearer than `DIVE_IN_MIN` past where the pull fades is just a swing. This is the one
part of all this that is not looks only (a dive on the rope used to keep the dive's weak
steering and its stiff pose the whole way in). While `dove_in` lasts the body zips instead
of hanging (`RopeSwing`, the `ZIP_...` and `SCREW_...` numbers): stretched out in line with
the way it is really going, the hook arm up the rope, the gun arm and the legs streaming
straight behind and fluttering with the speed, the whole body facing down the line until
a shot brings the chest round to the aim. As the rope pulls tight it corkscrews once about
its own length, the way you were steering (away from the gun hand if you were not); a
light jolt only twists it out and back; a shot hurries it. On arriving, still holding on,
it tucks and flips over the top, then hangs. Let go part of the way, rising fast, and it
rolls as above before the dive carries on. Dragged on your belly, the body turns to face
the hook (and back to the aim to shoot). In first person your own body does not roll:
your arms roll out and back instead (`ROPE_SCREW`), and the view stays level. Other
players see all of it: the dive into the rope and the way it was steered travel in the
snapshot's animation flags (bits 20-21). To film any of it:

```
tools/robot/rope_preview.sh OUT_DIR --scene=swing --step=0.0083333   # a test stage, from the side and behind, half speed: OUT_DIR/rope.mp4
tools/robot/rope_preview.sh OUT_DIR --scene=player --weapon=sword    # reeled in to a hooked player; also under (round a hook, steering), turn (aiming off to the side)
tools/robot/rope_film.sh OUT_DIR swing third                         # the real game, played by a script on the Testing Grounds: OUT_DIR/swing_third.mp4
tools/robot/rope_film.sh OUT_DIR player first --weapon=hammer        # scenes: swing, pump, player; first or third person
tools/robot/rope_preview.sh OUT_DIR --scene=dive --step=0.0083333    # diving into the rope; also dive_low (a long, low hook, shooting), dive_go (letting go part of the way), dive_side
tools/robot/rope_film.sh OUT_DIR dive third                          # the same in the real game; also dive_low, dive_go, drag (dragged on your belly)
```

`tests/rope_swing_test.gd` checks each of those things on a body driven by made-up movement,
and `tests/dive_rope_test.gd` the handling of a dive into the rope on a real body.

## Sound effects

Every sound is made by code, like the robots: `tools/audio/make_sfx.py` (python3 with
numpy) builds all of them from noise, sine waves, filters and envelopes and writes
`game/audio/sfx/*.wav`. Nothing is recorded or downloaded, so they are ours to ship
(see `game/audio/LICENSE.md`). The style is crisp but realistic: a clean attack,
real weight in the low end, gun actions and armour that sound like dull steel rather
than ringing bells, and room tails. The players are robots, so their feet and hits are
metal, but nothing beeps. Each recipe is a short function near the sound's name; change its
numbers and rebuild:

```
python3 tools/audio/make_sfx.py            # every sound (a few seconds)
python3 tools/audio/make_sfx.py fire_      # only the ones whose names start with fire_
godot --headless --path . --import
```

Cirrus's clock has six sounds of its own (`clock_tick`, `clock_tock`, `bell_toll`,
`layout_rise`, `island_move`, `bridge_lock`), played by its LayoutEvent. The tick is the
quietest sound in the game on purpose.

Each of Empyrean Tower's tiers has a quiet loop
of its own (`magic_engine`, `magic_library`, `magic_labs`, `magic_menagerie`,
`magic_summoning`, `magic_observatory`), played in the room by a MapAmbientSound.

The Construction Site's crane has four (`lever_pull`, `crane_start`, `crane_stop`, and
`crane_motor`, which loops while the crane moves and is pitched up while the hook goes
up or down), played by its MapLever and CraneEvent.

Two more of the sounds loop (`terminal_hum` and `gravity_pad`, for Halcyon's terminal and low
gravity): every frequency in them fits a whole number of times into the file, so the end
runs into the start, and the nodes that play them (MapTerminal, GravityEvent) set the
loop and fade them in and out.

In the game, `game/audio/` holds the code:

| File | What it does |
| --- | --- |
| `sound.gd` | The `Sound` autoload. Plays your own sounds in your head and everyone else's placed in the world (3D, quieter and duller with distance; far gunshots add a distant echo layer). Sets up the Effects and Music buses for the Audio sliders, with a limiter on Master. Hooks every menu button and slider by itself, and plays hit markers, kill and hurt sounds from the match events |
| `player_sounds.gd` | One per player: footsteps, jumps, landings, slides, wall runs, vaults, the grapple, reload steps, the pump and the bolt. It watches the same movement facts the animation uses, so it works the same for you, bots and other players |
| `sfx_list.gd` | The tables to tune: how loud each sound plays, and when each reload and pump/bolt sound plays (matched to the animations in `tools/robot/weapon_anims.py`) |

A menu button picks its click with `button.set_meta("sfx", "back")` (or `"confirm"`,
`"select"`, `"none"`); buttons labelled Back, Resume, Leave lobby, Leave match and Main
menu play the back sound already, and the orange main buttons play the confirm sound.
`--sound-log` prints every sound as it plays. The Music bus is ready for music but
nothing plays on it yet.
