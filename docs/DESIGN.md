# Design decisions

Decisions Austin has made, so nobody has to ask again. Newest at the top of each section.

## Technology (2026-11-15)

- Engine: Godot 4 (4.7.2).
- Networking: Steam (lobbies, invites, relay) plus direct IP for development and LAN.
- One player hosts; no dedicated servers. If the host leaves, the match ends (no host migration yet).
- Hits: the host decides, with rewind to what the shooter saw.

## Golden Gun (2026-11-17)

- Asked for: one player has a golden gun with one in the chamber that kills whoever it
  hits; kill the holder to take it; everyone else has some other gun.
- My calls: a random player starts with it; a kill with it loads the next round at once,
  a miss means a 3 s reload; the others use the weapon they picked (as the host allows);
  first to the host's kill target wins; with nobody to credit (a fall, a crash) or when
  the holder leaves, it goes to a random other player. It is the revolver in gold (its
  model, animations and sounds), not a new model.

## Killcams (2026-11-17)

- The winning kill: slow motion and a fade to "MATCH OVER" before the best kills
  (asked for, 2026-11-18). Killcams of melee kills in third person (asked for,
  2026-11-18): every blow (kicks and crashes too, see KillScore.is_blow), since a blow
  is about the bodies, not the aim.

- Killcam mode (asked for, 2026-11-17): snipers only; every kill scores its killcam
  points; first to 10,000 or the most after 10 minutes (later: 5,000 and 5 minutes by
  default, and the host sets both, asked for 2026-11-17); extra points for the match's #1
  killcam at the end. My call: the bonus is +1,500 (about three good kills, enough to
  swing a close match but not a rout), awarded after the match ends, so it can change
  the winner; both end conditions apply at once; the sniper rifle only (not the other
  marksman guns).

- Asked for: when you die, watch the kill from the enemy's perspective as a short
  replay; and the best killcam of the match, or the top three, at the end.
- As built: the replay plays in the respawn wait and can be skipped (not in its first
  0.75 s) or switched off; since respawning waits for a key press it plays to its end. When the match ends the top three play fullscreen,
  counting down to the best, before the results page (asked for, 2026-11-17). Replays are
  rebuilt from what each copy already receives and draws, not video.
- The score also rewards momentum, the killer's and the victim's, and how far the
  killer's aim moved just before the kill (asked for, 2026-11-17).
- Momentum counts only when both players are moving (their speeds combined, so a
  stationary killer or victim earns next to none), and trickshots, several tricks in
  one kill, earn a large combo bonus: the best killcam should be the one viewers agree
  is the coolest, and motion drives the game (asked for, 2026-11-17).
- Kicks and melee scored far too high: grapple-and-kick was the best killcam every
  time (playtesting, 2026-11-17). On a blow (kick, flying kick, crash, blade) momentum
  now counts at 40%, and the flick, air shot and trickshot combo do not count, since
  the reel-in and the kick's fling bring them on their own; the kick bonuses are lower
  (kick +40, flying kick +60, crash +50). Grapple-and-kick went from about 750 to
  about 340, against about 780 for a sniper trickshot.
- Not decided yet: the rest of the scoring rule that picks the top three (range,
  headshot, mid-air / rope / wall run / glide, air shot, kicks, crashes, multikills,
  clutch; ties go to the earlier kill) and all the point values are a first pick,
  explained in `KillScore` and FEATURES.md; tune them freely.

## Look and feel (2026-11-15)

- Art style: clean, stylized low-poly.
- Characters: robots.
- Player robots (2026-11-16): two characters to choose from. **Needle**: slim, one
  glowing eye, thin struts and blade limbs. **Vanguard**: an athletic armoured frame
  with broad shoulders and a helmet with a visor band. White armour for everyone; each
  player's colour shows on the trim panels and the glowing visor.
- Five more robots (2026-11-16), picked from mockups in the same style: **Kestrel** (scout:
  wedge helmet with crest fins, back thrusters, talon feet), **Bulwark** (heavy: low
  three-eyed head in a high collar, dome shoulders, piston legs), **Rivet** (site worker:
  hard hat, camera-lens eye, hazard stripes, tank backpack), **Specter** (stealth: hood
  with a V visor, trailing scarf, blade fins) and **Orbit** (glowing orb head in gimbal
  rings, glowing chest core). The bot named Rivet became Gizmo so names do not clash.
- **Templar** (2026-11-17): a crusader knight built the same way: a flat-topped great
  helm with a glowing eye slit behind a cross of trim, a white surcoat with a red cross
  front and back over chain mail, round shoulder plates, elbow and knee plates, a split
  surcoat skirt and steel sabatons. The red cross stays red; the player colour shows on
  the helm's cross, the sword belt, the shoulder bands and the surcoat hems.
- Characters are looks only (2026-11-16): same hitbox, same movement, same animations.
  You pick yours before the round: on the Practice and Vs Bots pages, or in the lobby.
  The choice is remembered. In a 1v1 the bot plays the robot after yours in the list, never your own.
- The grapple fires from the robot's left wrist; the pistol is in the right hand.
- A robot that dies powers down (visor goes dark) and collapses; a respawn boots it back up.
- First person shows your own body (2026-11-16): legs and torso when you look down, and
  in the moves that bring them into view. Flips keep the camera steady (chosen over a
  camera that tumbles with the flip, so aiming still works mid-flip); the legs tuck and
  sweep through the view instead.
- UI: minimal and clean.
- Music: none for now (Austin will add it later; the Music slider and bus are ready).
- Sound effects: crisp and realistic, not high-pitched or arcade-like. Other players' sounds are positional (3D) so fights read clearly.

## Weapons

- For now: one semi-automatic pistol (one shot per click).
- Headshots do 1.5x damage.

## Health

- No health regeneration and no health pickups.

## Movement

- Feel: between fast-and-grounded and very floaty.
- Skill tricks welcome ("skill tricks galore"): bunny-hopping and air-strafing are intended.
- No fall damage.
- Grapple: short cooldown, attaches to any surface.
- Low gravity (2026-11-17, Halcyon's event) changes players only: jumps, falls, swings, slides, wall runs and glides all go light together. Bullets, rockets and grenades do not change, so weapons stay predictable.
- Flips (2026-11-16): an air flip dodge. Press jump again in mid-air to flip toward your WASD direction with a small burst, once per jump.
- Float (2026-11-17, since replaced by the glide below): Shift in mid-air cancels your up-and-down speed and glides you in a straight line the way you face, at the speed you had, sinking slowly, for about a second (2.5 s was tried and was far too long). It pairs with every other move (they take over from it), so it doubles as a vertical cancel, and it is a steadier way to shoot from the air. Rocket boots are the exception: used while floating they turn the float the way you press, so it can change direction. Legs out to the sides, whirling like a helicopter's rotor (the first try, half a flip's speed, was too slow), and they hurt and shove anyone they touch. (A rocket booster out of the seat was tried and dropped: it looked goofy.)
- Glide (2026-11-17) replaces the float, modelled on Warframe's Aim Glide: hold Shift in the air, keep your own heading with free look, speed bleeding to a drift, the fall starting nearly stopped and growing, a 1.5 s budget per time in the air spent in pieces, and half the weapon spread while gliding. The spinning legs and their damage went with the float. Speed bleeds fully (a lighter bleed that kept the race gaps was offered and turned down), so the glide is for hanging and shooting, not for distance: at slide speed a flip carries further than a glide does. The race maps were rebuilt to suit: the ski jumps are a flip and a dive over 21 m (were a float over 24 m), and the 40 m float-and-boost leaps are 20 m glide-and-boost leaps.
- Grapple pulls you in: a yank when it catches, then a steady reel toward the hook that only adds speed along the rope (sideways speed is kept, so pulls turn into swings). The rope takes up its own slack, so it is always tight, and letting go keeps every bit of speed.
- Grappling Hook 2 (2026-11-18, asked for as "not hit scan, a projectile; slack in the line when first shot, then it tightens up and pulls like the current hook; satisfying physics; animations that line up on every client, for spectators and in killcams"): a second hook beside the first, not a replacement. My calls where the brief was silent: 85 m/s (fast enough to feel like a hook, slow enough to see it fly and to need a lead on a runner); the slack is real rope the winch has to take in before anything pulls, so the pull comes a beat after the bite and the beat is longer on a long shot; the snap when it pulls tight is 1.4 times the first hook's yank, as the reward for the wait; after that it is the first hook, number for number. To line up everywhere, nothing about the rope is animated frame by frame: it is drawn from a record of the shot's moments and a time, the same on every copy.
- Grappling Hook 2, the way back (2026-11-18, asked for as "able to catch surfaces on its way back to the player" and "always attached to the arm model in first person"): the hook's return is a real flight now, not a 0.2 s effect. My calls: it only catches while the button is held (a miss with the button still down, or a new press as it comes back), because a hook that grabbed things on its own after you let go would take the release away from you; a jump off the rope does not count as holding, or every jump off would hook the next thing and kill the fling; nothing within 2.5 m of you (the floor at your feet is not a swing). A catch on the way back is a new shot on the record, whose flight is that way back, so every copy draws it by the same rules as any shot.
- One grappling hook (2026-11-19, asked for as "remove the old Grappling Hook, the new Grappling Hook 2 becomes \"Grappling Hook\"; remove all traces or uses of the old Grappling Hook"): the instant-hit hook is gone, in code, menus, bots, races, killcams, tests and tools, and the projectile hook is now the Grappling Hook (`Grapple`, id `grapple`). A saved choice, a lobby's allowed tools or a `--mobility` naming the old `grapple2` id all become the Grappling Hook (`Mobility.RENAMED`). My calls: its yank when the rope pulls tight stays what it was (now `grapple_yank` itself, 9.8 m/s, not "1.4 times the first hook's"); races and race bots use it too (bots hold the button through the flight); the flying kick, the wall-jump and swing momentum and everything else built on the rope work on it unchanged, since they only ever looked at the tight rope; snapshots no longer carry the first hook's anchor (it was only used to draw that hook's straight rope).
- Mobility trimmed (2026-11-19, the trimmed fork): two tools on the mobility button, the grappling hook and blink, picked as before (Loadout, lobby, respawn screen; the host can still allow only one). The button moved from right mouse to middle mouse, and right mouse is free. The fourth tool, a teleporting gun, is gone from the game, and with it the event that opened Empyrean Tower's ring gates (which used its machinery): the altar and the gates are scenery now. The jetpack is no longer a pick: everyone has it, on Space held in mid-air. My calls: it lights only once Space has been held 0.25 s in the air, counted from the press or from the jump it made, so a normal jump, a wall jump or a flip never burns fuel and holding on is a clear choice; a mid-air press is still the flip (once per jump), and holding on after it flies; it does not fire on the rope, on a wall, in a glide, a vault or a ground slam; while it flies a held Space no longer tips the rocket boots up; no jetpack in a race (the courses are the grapple's); its fuel gauge shows under the crosshair only while the tank is not full. Saved controls with the mobility button on right mouse move it to middle mouse once, unless middle mouse was already bound to something else; saved picks and lobby lists of tools that have left the slot load as the default.
- Mobility trimmed again, and a gentler flip (2026-11-20, asked for as "Jetpack: players should not have this by default, should be a lobby toggle", "Blink: remove this from the game", "remove the first person animations for both: double jump (flip) and when the player jumps left or right" and "mid-air flip should not add any permanent momentum, it should only boost the player upwards a small amount to bridge longer gaps"). Blink is gone, so the grappling hook is the only tool on the mobility button and there is nothing to pick: the mobility pickers (lobby, Vs Bots, pause menu Loadout), the death screen's mobility row and the lobby's "Mobility allowed" setting are gone with it. The jetpack is a lobby setting (`jetpack`, a toggle under Loadout rules), off by default; when on, everyone has it in every fight, bots too, and a race never has it. The mid-air flip keeps its lift (at least 4.5 m/s up, about a metre more height) and no longer pushes you along at all, so it adds no speed you keep; WASD still picks which way the body turns over for everyone else. In first person your own flip shows as a plain jump: no arm tuck and no legs sweeping through the view (front, back or side flip). My calls: an old saved pick of blink, or an old lobby list of allowed tools, loads as the hook and is dropped; `--allowed-mobility` became `--jetpack` for tests; the glide's backflip out keeps its first-person legs (it is not the double jump).
- Eight more weapons cut (2026-11-20, asked for as "remove ... from the game" for the mace, scythe, karate, wrench, machete, sniper, laser rifle and derringer): 30 weapons are left. Killcam mode was the sniper's alone, so it now hands everyone the anti-materiel rifle (the user's pick). My calls: map spawns of a cut weapon hold one of the same class (sniper to bolt-action, derringer to revolver, laser rifle to battle rifle, scythe to spear, mace to hammer, machete to sword, wrench to bat, karate to brass knuckles), and the Testing Grounds' 35 m dummy holds a bolt-action; the Gun Game ladder drops their rungs (22 left); bots that waited for a clean shot with the sniper now do so with the anti-materiel rifle; the karate combo machinery (six-blow combos, kicks that pose the legs) stays in MeleeSwing for any weapon that wants it, and so does the self-recharging battery (WeaponData.recharge), though no weapon uses either now. The robot `.glb` files still hold the cut guns' models and clips (the game never shows them); rebuilding needs Blender.
- Five more weapons cut, and a bigger anti-materiel magazine (2026-11-20, asked for as "increase the anti-materiel rifle magazine from 3 to 5" and "remove ... from the game" for the nail gun, dagger, axe, SMG and plasma cannon): 25 weapons are left, and the anti-materiel rifle (Killcam's gun) holds 5 rounds. My calls: map spawns of a cut weapon hold one of the same class (SMG to rifle, nail gun to burst rifle, dagger to sword, axe to hammer, plasma cannon to rocket launcher), renamed to match (the Castle v2 blockout script follows, and its stale Sniper entry now names the BoltAction2 spawn); the Gun Game ladder drops their rungs (19 left); the plasma ball and nail projectile looks are gone; a bot with no weapon in hand judges distance like the brass knuckles (it was the dagger). The dagger's back-stab bonus (WeaponData.backstab_multiplier) stays in the code though no weapon uses it now.
- Lever-action headshot kills (2026-11-20): 56 damage, was 55, so a headshot (x1.8: 100.8) kills a full-health player out to 50 m, where its falloff starts; at 55 it came to 99, one short. Body shots are as they were: two still kill within 50 m.
- Bolt-action rifle cut (2026-11-20): 24 weapons are left, and the lever-action (a headshot kills within 50 m) is the marksman rifle on iron sights. My calls: every map spawn of a bolt-action holds a lever-action instead, renamed to match (LeverAction2 where the map already had one), and so does the Testing Grounds' 35 m dummy; map generator scripts follow; the Gun Game ladder drops its rung (18 left); the Arsenal achievement needs 24 different weapons (its id is kept); bots wait for a clean shot only with the anti-materiel rifle and the railgun; the robot test's bolt gun is now the anti-materiel rifle. The bolt sounds and the bolt-working clips stay, for the anti-materiel rifle. An old saved pick of the bolt-action loads as the pistol (WeaponData.valid), as for every cut weapon.

## Maps

- **Empyrean Tower** (2026-11-18): an immense wizard's tower hanging in low orbit above an alien planet, held up by a crystal fusion engine in its roots. The tallest arena by far (183 m / 600 ft to the eaves, up to 16 players), for free-for-all, Deathmatch and Gun Game. Named Empyrean Tower (plain "Wizard's Tower" was turned down).
  - Half fantasy, half sci-fi, and both unmistakable in every view: the wizard is also an engineer, so every machine on the tower is the wizard's own, woven into the masonry and the magic. A pale stone shell with alloy ribs, plated sections and conduits of light (more alloy the higher you go), brass everywhere; rune circles etched into deck plates, orreries on servo housings, stone arches over force fields, crystals in containment rings. Twilight violet, mysterious and wondrous, not grim. Original throughout: the feel of both genres, nothing named or copied.
  - Shape: round and tapering smoothly (61 m across at the foot, 40 m at the top) under a conical roof with a great crystal and a turning brass orrery; a jagged root of rock below with chains and crystals. Nothing stepped or blocky anywhere (no Minecraft look: a hard rule).
  - Outside is play space, all of it to grapple: eight stabilizer thrusters round the foot (their jets are only light), balconies at every tier, the docking ring at 91.5 m with a parked starship to fight on (an original design, solid all through), sensor masts and dishes on the eaves, and a field of debris within about 76 m of the wall at every height: broken masonry, rune rings, crystal shards, hull plates, a broken satellite, a wrecked shuttle. Most of it is still; three big chunks orbit and carry riders. The field is kept thin, about 28 pieces (halved on 2026-11-18: there were too many floating islands), and the grapple anchors between them are small buoys, not rocks. Small maintenance drones drift about (scenery: no collision).
  - Two kinds of play: outside gravity is 40% and always straight down (toward the planet); inside it is normal. The change is at the wall line, marked by the force-field doorways (players and shots pass through them), and eases over about a second.
  - It has to feel like a wizard's tower in its surfaces and its clutter, not only its shape (2026-11-18): walls of coursed masonry with a rune glowing on a stone here and there; every tier's floor is flagstones laid in rings round the shaft in that tier's colour, with glowing runes (a star chart in the Observatory). And it is heavily dressed, always a piece of each half side by side: banners and tapestries by screens, flame sconces by tube lamps, bookcases and potion shelves by data cabinets, lanterns, carpets, vault ribs, pilasters, tables with their clutter, cargo; outside, turrets with cone roofs, lit slit windows, string courses and banners on the balconies.
  - Fantasy in its construction, sci-fi in its modification (2026-11-18): it is an old tower, built with stone and magic in mind, that has since been modified in a sci-fi manner. Everything structural is stone, wood or brass; the technology is fitted to it (conduits clamped to the ribs, cable trays, pipes, dishes, screens, machines, the docking ring, the thrusters). A first version plated strips of the wall in alloy to show both halves, and it read as two conflicting textures; never mix the wall itself.
  - Magical and a little surreal (2026-11-18, the last design pass, settled question by question):
    - Mostly living magic and atmosphere, with a few impossible-architecture accents, and those outside only so the inside stays readable.
    - Looks and sound only: no new collision, routes, hazards or gameplay. Effects lean on shaders, not blocks.
    - Heaviest in the shaft and the feature rooms, light in the corridors, sparse outside.
    - The showpiece is a river of glowing liquid magic spiralling up the shaft against gravity, from the Engine's core to a pool hanging upside down under the Observatory, taking each tier's colour as it passes; rune rings turn round it.
    - Each tier has its own: caged lightning and rising sparks (Engine), flocks of books and loose pages (Library), rising droplets and bubbles (Labs), small see-through spirit creatures (Menagerie: fish, jellyfish, moths; never human shapes, nothing player-sized), floating candles and turning chalk circles (Summoning Chamber), constellations and little worlds (Observatory).
    - The technology harnesses the magic: at every tier an intake draws a thread off the river and pipes it, glowing, to a tank.
    - Outside: a broken arch whose stones hang apart, a stair of floating treads winding off into nothing, and the tower's top mirrored upside down under the root. They are phantoms (pale, see-through), because they have no collision and must not look like somewhere to land.
    - The sky is alive: the aurora ripples, the planet turns slowly, shooting stars, and now and then a ribbon of magic across it.
    - **The magic answers to players, as a cue for others**: within 13 ft (4 m), motes scatter, runes in the walls and floors glow brighter, books and spirits flee, candles gutter. The river, the sky and the set pieces stay steady. It reacts to every live player, yours and bots too, not to the dead or spectators. **Never through a wall** (it would look like a mistake): it needs line of sight; solid things block it, see-through ones (glass, force fields, holograms) do not. **Crouch-walking does not set it off**, so you can sneak past; running, jumping, sliding and grappling do.
    - A quiet sound per tier (hum, chimes, bubbling, crackle); no voices or whispers.
    - Hard limits: no fog or haze indoors, nothing that hides a player, no red or hostile-feeling colours, no floating text, nothing blocky.
  - No floating label text (2026-11-18): the hologram signs naming each tier and the docking ring were removed. We hate floating label text; a place is told apart by its colour and what stands in it, not by a sign.
  - No walls or ceiling outside, on purpose: fling yourself as far or as high as you like. The only way to die out there is the burn layer, a hazy band of hot light 46 m (150 ft) under the root: far enough to save a fall with the grapple, near enough that a fling-off is not a long wait.
  - Inside pushes fights upward: six tiers of 30.5 m round a hollow shaft 16 m across that runs the whole height (bridges at every tier and upper hall, floating stones and grapple anchors up it). From the bottom, each with its own accent colour: Arcane Engine (cyan; the crystal core is a fusion reactor in turning containment rings, and it kills on touch, in a sunken glowing basin), Grand Library (gold; shelves alternating with data-archive stacks, books of light), Alchemy Labs (green; vats and alembics, bio-tanks and robotic arms), Menagerie (teal; cages, vines, xenobotany pods under grow lights), Summoning Chamber (violet; rune circles in deck plates, the altar), Observatory (silver; a space telescope under a hologram of the planet). Every tier but the top is one plan: a feature room 19 m tall facing the shaft with balconies at 6 and 13 m, three storeys of rooms and a tight two-lane corridor along the outer wall, and an upper hall; two spiral ramps and two long ramps between tiers, drop holes, and three or four openings to the outside.
  - Tractor-beam lifts (four: two in the shaft, two up the outside) make climbing fast: about 3 s a tier, and you can shoot on the way and step out at any height.
  - The rune altar and the eight ring gates (2026-11-19: their map event, which opened the gates as teleports, was removed with the teleporting gun whose machinery it used) stay as scenery.
  - No spawn point in sight of the altar and no weapon near it. Power weapons sit high or outside: on the three orbiting chunks, the starship's back, the eaves among the sensor masts, the Observatory's gallery. Stained glass windows shatter to open shortcuts; none is on a route anyone needs.
  - My calls where the brief was silent: all five lower tiers are turned the same way, so ramps and lifts line up from tier to tier; the three islands people spawn on each have a grapple mast back to the tower, and every bot carries the grapple here, as on Cirrus.
- **Cirrus** (2026-11-17, reworked twice on 2026-11-18): a university campus on floating islands above a sea of cloud, with a ringed planet in the sky. A big arena (about 135 m across with every island home, up to 16 players) for free-for-all, Deathmatch and Gun Game. A decor pass the same day (2026-11-18) furnished the buildings and planted the plazas, the quad and the roofs: small decor is look-only so it never snags movement or blocks a shot, and only big pieces (shelves, counters, desks, planter boxes, benches) are cover; landing spots, lanes and spawn points stay clear.
  - Tone: bright, warm and a little grand: sandstone and terracotta, lawns, banners, a clock tower. A golden afternoon, the opposite of Halcyon's cold corridors.
  - No Minecraft look, anywhere (2026-11-18): nothing stepped, stacked or cube-shaped where a slope or a curve belongs. The tower has a smooth four-sided spire, the observatory a real dome, roofs are slopes and shells, trims and furniture are bevelled, trees are round clumps, stairs are closed in so the zigzag never shows, and the surface patterns are bigger and fainter than on other maps. The game's look is otherwise unchanged. New block shapes (wedge, bevelled box, dome, arch) were added for every map to do this.
  - Scale (2026-11-18): islands and buildings about 1.5 times the first version, the quad 1.3 times, floors 5.5 m apart with two-storey main halls and wide arched doorways, so there is room to grapple, flip and boost indoors.
  - No text (2026-11-18): every sign was removed. Each building is known by colour and shape: Library (blue; a columned porch, arched windows), Lecture Hall (red; a shell roof over the stage), Labs (teal; a glass wall upstairs, stacks and vents on the roof), Cafeteria (orange; a striped awning over a terrace), Observatory (purple; the copper dome).
  - Spread out, no walkways (2026-11-18, second rework; the first version had skyways and bridges and the islands 8 m from the quad): 24.4 m (80 ft) of open sky from the quad to every island and between neighbours, so the map feels big and getting about is a risk. Beyond a jump with a dive or a flip; the whole chain (flip, dive, glide) just makes it, the grapple and the rocket boots make it comfortably. Masts on the quad's rim and on every island's tip are there to hook, and five stepping stones stand just off the quad. Falling is death.
  - Two islands at a time (2026-11-18, replacing the Hub and Ring layouts): only two of the five buildings are up. Every 60 s the other three change places with them: the doomed islands fall away below the clouds, and whoever did not get off dies with them (a fall, nobody's kill). The quad and the tower never move: the one piece of ground that is always there, and the middle everything swings back through.
  - You never know what comes next (2026-11-18): each change is drawn at random from a pool. Never the same pair twice running, never the same kind twice running. Swap (the new pair at their homes), Drift (36 degrees round the quad; an island in both pairs carries its riders there), Close (12 m nearer: a jump from the quad), Far (9 m further out and 7 m up or 9 m down) and Split (one 8 m up, one 8 m down). A match starts with a random pair.
  - The clock (2026-11-18; first built as a bell players rang): it ticks softly all match, well under the fighting, and the tower's clock hands count the minute down. At the minute a deep bell tolls, then 8 s of build-up (5 s when it was only walkways to step off) that starts slow and ends fast: engines spooling, a rising tone, a growing rumble. The doomed islands' engines and lamps turn red and sputter, they sag, and they shake under anyone standing on them. Then a 4 s move and a clunk. The sky goes from afternoon to sunset and back with each change. Nothing is on the HUD.
  - Spawns are only on islands that are up and staying, with five on the quad for the moments there is none. Pickups go down with their island and come back with it. Power weapons: the anti-materiel rifle on the tower's upper ledge (always there), the railgun on the observatory dome and the rocket launcher on the library's hanging perch (only while those are up).
  - Team modes (Search and Destroy, Capture the Flag): the clock is off and all five islands stay up, spread out, because their bomb sites and flag stands are fixed spots.
  - Bots all carry the grapple on this map: it is the only way round they are taught.
- **Halcyon** (2026-11-17): the colony ship *Halcyon*, whose gravity comes from a huge centrifuge ring turning round its hull. The biggest and most vertical arena (140 x 140 m, up to 16 players), for free-for-all, Deathmatch and Gun Game.
  - Tone: the inside of a capital ship in a classic sci-fi shooter (clean, cold corridors, big viewports onto space) but brighter and more hopeful, because this ship carries colonists. The feel only: nothing named or copied.
  - Layout: hub, four spokes and an outer ring. The round Control Room in the middle (30 m across, a glass dome above and a ring of glass in the floor, the centrifuge sweeping past both), a spoke corridor to each of four tall rooms, an outer ring corridor so no room is a dead end, and a tighter lower maintenance deck under the spokes and the ring with two stairwells up into the Control Room.
  - Rooms, one accent colour each: Hangar (cyan; the biggest volume, two shuttles, a viewport onto a planet), Hydroponics (green; terraces of planting beds, grow lights), Engineering (orange; the reactor core, ringed catwalks, and the reactor pit under it, the map's only hazard), Cargo Bay (yellow; container stacks and a gantry crane) and the Cryo/Habitat zone in the ring (pale blue; the one tight part, on purpose). Every tall room is a grapple playground, 32 to 36 m from floor to ceiling.
  - The low gravity event, the game's first interactive map object: press Interact (G) at the terminal on the Control Room's dais and the centrifuge slows to half speed. Gravity eases to 30% for 30 s (a jump reaches about 4 m), then a 60 s cooldown. One press is enough (first built as a 2 s hold that a knock off the dais interrupted; changed the same day, 2026-11-17, to a press, and the gravity from 40% to 30%, for a stronger effect that is simpler to set off). No weapon in the Control Room: going for the event is a risk with no item reward.
  - Its feel is blissful, not an alarm: the lights fade to a deep blue, a soft sustained chord swells in, slow motes of light drift through the big rooms. Shown, never told: nothing on the HUD, no red, no flashing.
  - Surfaces (2026-11-17): bare walls and floors read as empty at this size, so the hull is panelled and the floors tiled by a surface shader (no blocks), and each place carries drawn-only details: ribs, vents, wall displays in the room's colour, conduits and ceiling beams; on the floors a line of each room's colour to follow to it, grates, hazard stripes at every drop hole, railing gap and the reactor pit, and names and deck numbers stencilled. None of it is solid, so movement is unchanged.
  - Power weapons sit up high where only the grapple takes you (the top reactor catwalk, the six-high container stack, the hangar gantry, the top terrace); the rest are in the corridors, the ring and the lower deck.
- **Testing Grounds** (2026-11-16): the starting test map, kept long-term for testing. It is not a player-facing map.
  - The arena part (80 x 80 m) is the original combat test area.
  - The training yard (through the doorway on the east side) has practice lanes for the grapple, wall run and wall jump, slide, and vault and ledge climb.
- **Construction Site:** the first playable, player-facing map.
  - Layout (2026-11-16): "The Tower", picked from three concepts (the others were "The Yard", two structures facing each other, and "The Dig", a deep excavation). One half-built tower in the middle, king of the hill: floors every 4 m up to 20 m, stepping back as they rise, with a crow's nest at 24 m on the lift shaft and the crane's jib at 34 m.
  - Lots of verticality, and a route for every move: stairs, a lift shaft to wall-jump, tall crates to climb a floor at a time, scaffolding and a hoist tower to jump and climb, walls and the fence to wall-run, girders, the crane and floodlight masts to swing from, a conveyor and an earth ramp to slide, pipes to run through.
  - Look (2026-11-16): "Clear midday", picked from four (the others were golden hour, dusk under floodlights, and a misty morning with a muted palette; they were dropped when maps became scenes). Clean, stylized, low-poly; bright sun, blue sky, primary colours.
- **Office:** the second player-facing map, a smaller interior one.
  - Layout (2026-11-16): "Atrium tower", picked from three (the others were "Stacked open-plan floors" and "Split-level lobby"). A 48 x 36 m office building, three floors at 0, 5 and 10 m wrapped round an open atrium under a skylight. A bridge crosses the atrium at 10 m; the 10 m floor's north balcony steps back 2 m so the 5 m floor below has a strip open to the skylight.
  - Rooms: lobby with reception, café and lounges; open-plan desks, meeting rooms and a kitchen at 5 m; corner offices, a server room and a boardroom at 10 m. City backdrop outside the windows (the windows are invisible walls, so you cannot leave).
  - Same look as the Construction Site: same sky and sun, same face shading, its own palette (game/maps/palettes/office.tres).
- Arena size: about the size of the Testing Grounds arena part (80 x 80 m).
- The host picks the map in the lobby; practice and the bot menu have a map picker too.
- Maps are scenes edited in the Godot editor (2026-11-15): every piece is a node you can select, move and resize, and the game merges them into a few meshes when a match starts. Decided before making more maps.
- Themes: different arenas can use different themes.
- Melee weapon looks (2026-11-17): robot-tech, made in the same factory as the robots: solid metal with glowing edges and inlays (not energy blades), gunmetal and armour plate with the player's colour as the only colour, faceted, about 15-20% oversized, no wood. One design per weapon for every robot. Code-built, no outside assets. At rest in first person a weapon covers no more of the view than before. The glowing parts can be dimmed or brightened (`MeleeModel.set_glow`); whether they brighten with the wind-up is for the animation pass, as are moving parts and where the hands hold each weapon.
- Melee swings (2026-11-17). Taps alternate sides and start over after about 1 s without swinging; a swing wound up half way or more is the weapon's own heavy blow (one each: see FEATURES). The edge or face leads. The timing of a blow (when it lands, how long it lasts) was kept so bots, networking and balance are untouched, with one exception: a full wind-up takes 80% of the time it did, because it felt better with the new animations. The first try was turned down: the body did not wind up nearly enough, and the sword was held out in front "like you've never held a sword before". What was wanted and built: bodies relaxed and fluid, not rigid, coiling up with the charge (hips, knees and shoulders, not only the chest, the body leading and the weapon following), and a relaxed stance, the same in first and third person (a low guard for the two-handed weapons). Hit feedback: hit-stop growing with the charge, sparks, a view jolt, a bigger trail, heavier sound; the glow follows the wind-up. No moving parts on the models. Still to come, as a second piece of work: wind-ups of their own in the air (a slowed fall while winding up) and a ground slam.
- Melee in the air and the ground slam (2026-11-17). Asked for: an anime look, where charging in the air ties into the swing. A wind-up hangs you in the air for a moment (a real movement change, capped at 0.6 s per time in the air and refilled like the glide, so it cannot be chained into flight). Each weapon has its own mid-air move, and it is one move from the start of the wind-up to the hit (one long turn for the hammer), not a spin that repeats faster and faster: that was tried first and read as a blur. The hammer comes from the side to match its ground heavy blow. The first-person view never spins: only other players see the full turn. The ground slam is crouch held as you let go, so it needs no new button; it is melee only, the same for every weapon with a hammer bonus, committed once started, once per time in the air and on a cooldown, so it is a punish from above and not a move to spam. The code calls it a ground slam everywhere, because "slam" already meant hitting a wall.

## Match rules

- The host sets the win condition per lobby: first to N kills, or a time limit.

## Still open

- Respawn delay (3 s for now; then you come back when you press Jump or Fire, asked for 2026-11-17, so there is time to change your loadout).
- The end of the cut-off sentence in the original brief ("Networking tradeoffs that affect the...").
