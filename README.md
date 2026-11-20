# Jumpy Shooty

A fast, high-mobility 3D multiplayer arena shooter: grapple, wall-run, slide, dive and
fight in free-for-all matches of up to 16 players, or offline against 1 to 4 bots. Play a
**Deathmatch** where everyone starts unarmed and grabs weapons floating around the map, or
team up as Red or Blue for **Search and Destroy** (plant or defuse the bomb, no respawns in a
round) and **Capture the Flag** (online, or with up to 7 bots for a 4v4). Or put
the guns away and **race**: run an obstacle course against friends or bots, from
checkpoint to checkpoint, to the finish.

Built with **Godot 4.7** (GDScript). Multiplayer is player-hosted: one player hosts and
up to 15 friends connect to them. Today that works over direct IP; Steam invites and
relays are next.

**Status:** Milestone 1 in progress: match loop, full movement set, the Construction Site, Office, Kilnworks, Rail Yard, Lost Temple and Neon Arcade maps, four race courses (Rooftop Run, Foundry, Sky Ruins, Summit Plunge), a Character Creator (mix the heads, torsos and legs of the robots and of 20 creatures such as a dude, a goblin, a frog or a skeleton, pick its main, second and detail colours and a skin tone, add hats, glasses, capes, tails and more, each in a colour of its own, and play as it online), your own colour in a free-for-all, achievements that unlock creator items, calling cards and icons (kills, headshots, wins, race medals and more), the Testing Grounds test map and offline bot matches (1v1, or a free-for-all against up to 4 bots) work, with sound effects for every gun, hit, move and menu; Steam is next. See [docs/FEATURES.md](docs/FEATURES.md)
for what works and what does not yet.

## Quick start

1. Install Godot 4.7.2 (standard version, not .NET) from https://godotengine.org/download.
2. Open Godot, click **Import**, and pick this folder's `project.godot`.
3. Press **F5** (or the ▶ button) to play.

More detail, including how to play with a friend and run several copies on one PC, is in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Controls

| Action | Key |
| --- | --- |
| Move | W A S D |
| Sprint | Shift |
| Glide (hold in mid-air: you fly on along a locked track at the speed you had, free to turn and shoot, and guns scatter less; you can hold it as long as you like but it weakens into a fall; let go to stop, with a backflip) | Alt |
| Jump | Space |
| Shoot (melee: hold to wind a swing up, let go to swing; the longer the wind-up, the harder the hit; Karate: each swing is the next move of a six-hit combo; air cannon: hold to charge, let go to blast everyone in front of you away) | Left mouse |
| Change weapon (while waiting to respawn) | 1-7 or mouse wheel |
| Deathmatch: take out the weapon in slot 1 or 2 (you carry two) | 1 / 2 or mouse wheel |
| Kick (any weapon; with a player on your grapple: flying kick) | F |
| Rocket boots (a burst toward WASD as you look; hold Space to tip it up; while gliding, turns the glide that way) | E |
| Interact (press at the terminal in Halcyon's Control Room: low gravity; at the lever in the Construction Site's crane cab: the crane moves its load; Search and Destroy: hold to plant or defuse the bomb) | G |
| Reload (in a race: back to your last checkpoint) | R |
| Switch first / third person | V |
| Scoreboard | Tab (hold) |
| Menu (Loadout: change robot or weapon for your next respawn) | Esc |
| Debug menu (Practice and Vs Bots only) | F1 |
| Spectate (fly a noclip camera nobody can see) | Esc > Spectate, or **Join as spectator**; then W A S D fly, Space up, Ctrl / C down, Shift fast |

Right mouse is your **mobility** tool, picked before a match, in the pause menu's Loadout or
by pressing right mouse while you wait to respawn: the **grappling hook**
(the hook is a projectile: it flies out with slack in the rope, bites, the winch takes the slack in and
the rope snaps tight with a yank, then it reels you in and you swing; lead a moving target, and let go to call it back; while you hold the
button, a hook on its way back catches the first surface in its way), the **portal gun**
(each press puts up your next portal, blue then orange, up to 45 m apart, fitted to the surface you shoot: moved off edges and obstacles and stood clear of ribs, beams and signs; walk into one and come out of the other
at the same spot, with your speed and the way you look carried through, and see and shoot through each to the other side (bullets, rockets and grenades go through too); portals on moving parts of a map ride them; anyone can use anyone's portals, and yours go when you die) or
**blink** (a short teleport where you look, one charge that recharges, with a trail of sparks to where you land) or the **jetpack** (hold to fly and steer with WASD, on fuel that refills when you let go, fastest on the ground). A race always has the grapple.
Grapple is right mouse; Ctrl (or Q, or C) crouches, dives when moving forward and slides on your back when moving back. Every key except Esc can be
rebound under **Settings > Controls** (two bindings per action, keys or mouse buttons); a key
you give to one action is taken off any other that had it, and **Reset controls to defaults**
puts them all back.

## Project layout

```
game/
  core/      settings, screen changes
  net/       multiplayer: hosting, joining, lobby, movement smoothing
  player/    player, movement (movement/), camera (camera/)
  match/     match rules run by the host: health, hits, kills, respawns, timer, races
  combat/    weapons and shot effects
  audio/     sound effects (sfx/) and the code that plays them
  arena/     the arena and the map system (see docs/DEVELOPMENT.md)
  maps/      the maps: scenes you edit in the Godot editor, and their palettes
  ui/        menus, lobby, HUD, pause menu
  dev/       developer command-line options
addons/      map_tools: the editor plugin for editing maps
tools/       launch several copies, take screenshots, render map previews, build the robots, sounds and race maps
tests/       automated tests (tests/run_all.sh)
docs/        setup guide, feature tracker
```
