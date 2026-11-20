#!/usr/bin/env bash
# Runs every automated test. Needs Godot ("godot" on PATH, or set GODOT) and python3.
#
# The quick checks run first, side by side, on a fixed game clock (Godot's
# --fixed-fps 60), so physics plays out as fast as the machine can go instead of in
# real time. The networked and bot runs come after; they need real time.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
export GODOT
OUT=tests/out
mkdir -p "$OUT"
echo "== Importing project"
"$GODOT" --headless --path . --import > /dev/null 2>&1 || true

# Each quick check: "name|args". Logs go to tests/out/check_<name>.log.
CHECKS=(
  "movement|--fixed-fps 60 --script tests/movement_test.gd"
  "movement_variant|--script tests/movement_variant_test.gd"
  "movement_b|--fixed-fps 60 --script tests/movement_b_test.gd"
  "grapple_points|--script tests/grapple_point_test.gd"
  "robot|--fixed-fps 60 --script tests/robot_test.gd"
  "rope_swing|--fixed-fps 60 --script tests/rope_swing_test.gd"
  "dive_rope|--fixed-fps 60 --script tests/dive_rope_test.gd"
  "ragdoll|--fixed-fps 60 --script tests/ragdoll_test.gd"
  "custom_character|--script tests/custom_character_test.gd"
  "gibs|--fixed-fps 60 --script tests/gibs_test.gd"
  "weapons|--script tests/weapon_test.gd"
  "new_weapons|--script tests/new_weapons_test.gd"
  "air_cannon|--script tests/air_cannon_test.gd"
  "audio|--script tests/audio_test.gd"
  "maps|--script tests/map_scene_test.gd"
  "spawn_clearance|--script tests/spawn_clearance_test.gd"
  "controls|--script tests/controls_check.gd"
  "menu|--script tests/menu_mode_test.gd"
  "ui_layout|--script tests/ui_layout_test.gd"
  "hud_icons|--script tests/hud_icons_test.gd"
  "kill_feed|--script tests/kill_feed_test.gd"
  "character_showcase|--script tests/character_showcase_test.gd"
  "portrait|--fixed-fps 60 --script tests/portrait_test.gd"
  "hud_settings|--script tests/hud_settings_test.gd"
  "graphics_settings|--script tests/graphics_settings_test.gd"
  "deathmatch|--script tests/deathmatch_test.gd"
  "destruction|--script tests/destruction_test.gd"
  "block_settings|--script tests/block_settings_test.gd"
  "map_tools|--script tests/map_tools_test.gd"
  "arena_maps|--script tests/arena_maps_test.gd"
  "flicker|--script tests/map_flicker_test.gd"
  "halcyon|--script tests/halcyon_test.gd"
  "terminal|--script tests/terminal_test.gd"
  "cirrus|--fixed-fps 60 --script tests/cirrus_test.gd"
  "gravity|--fixed-fps 60 --script tests/gravity_test.gd"
  "lift|--fixed-fps 60 --script tests/lift_test.gd"
  "empyrean|--script tests/empyrean_test.gd"
  "empyrean_play|--script tests/empyrean_play_test.gd"
  "haunted_house|--script tests/haunted_house_test.gd"
  "testing_grounds|--fixed-fps 60 --script tests/course_test.gd"
  "construction_site|--fixed-fps 60 --script tests/site_test.gd"
  "office|--fixed-fps 60 --script tests/office_test.gd"
  "debug|--script tests/debug_test.gd"
  "killcam|--script tests/killcam_test.gd"
  "killcam_remains|--fixed-fps 60 --script tests/killcam_remains_test.gd"
  "killcam_sync|--script tests/killcam_sync_test.gd"
  "mobility|--fixed-fps 60 --script tests/mobility_test.gd"
  "portal_view|--script tests/portal_view_test.gd"
  "portal_shot|--fixed-fps 60 --script tests/portal_shot_test.gd"
  "portal_gun|--fixed-fps 60 --script tests/portal_gun_test.gd"
  "grappling_hook|--fixed-fps 60 --script tests/grappling_hook_test.gd"
  "lobby_settings|--script tests/lobby_settings_test.gd"
  "scoreboard|--script tests/scoreboard_test.gd"
  "lobby_code|--script tests/lobby_code_test.gd"
  "lobby_player_card|--script tests/lobby_player_card_test.gd"
  "lobby_bots|--script tests/lobby_bots_test.gd"
  "host_controls|--script tests/host_controls_test.gd"
  "spectator|--script tests/spectator_test.gd"
  "team_modes|--script tests/team_modes_test.gd"
  "player_color|--script tests/player_color_test.gd"
  "achievements|--script tests/achievements_test.gd"
  "calling_card|--script tests/calling_card_test.gd"
  "cloud_save|--script tests/cloud_save_test.gd"
  "respawn_visible|--script tests/respawn_visible_test.gd"
)
# Practice mode boots without errors on every map.
for map in construction_site office kilnworks castle halcyon cirrus empyrean haunted_house testing_grounds rooftop_run foundry sky_ruins summit_plunge; do
  CHECKS+=("boot_$map|-- --practice --map=$map --quit-after=3")
done

run_check() {  # fails on any script error, even if the script itself reports PASS
  local name="${1%%|*}" args="${1#*|}" log="$OUT/check_${1%%|*}.log"
  # shellcheck disable=SC2086
  if ! timeout 120 "$GODOT" --headless --path . $args > "$log" 2>&1; then
    echo "FAIL $name (exit code; see $log)"; return 1
  fi
  if grep -q "SCRIPT ERROR\|^ERROR" "$log"; then
    echo "FAIL $name (script errors; see $log)"; return 1
  fi
  echo "ok   $name"
}
export -f run_check
export OUT

echo "== Quick checks: movement, robots, weapons, sounds, maps and routes, menus, modes, lobby codes, random maps and lobby songs, practice on every map"
if ! printf '%s\n' "${CHECKS[@]}" | xargs -d '\n' -P "${JOBS:-4}" -I{} bash -c 'run_check "$1"' _ {}; then
  for f in "$OUT"/check_*.log; do
    if grep -q "FAIL\|SCRIPT ERROR\|^ERROR" "$f"; then echo "--- $f"; grep -B2 -A4 "FAIL\|SCRIPT ERROR\|^ERROR" "$f" | head -40; fi
  done
  exit 1
fi
echo "== Sync: 3 players, bad network (100 ms latency, 60 ms jitter, 10% loss) (Construction Site)"
MAP=construction_site tests/run_sync_test.sh 3 "100,60,10"
echo "== Grappling hook online: 3 players, bad network (80 ms latency, 30 ms jitter, 5% loss); every copy draws every hook and rope where its owner had them"
tests/run_hook_sync_test.sh 3 "80,30,5"
echo "== Portal gun online: 3 players, bad network (80 ms latency, 30 ms jitter, 5% loss); every copy has every portal in the same place, seated the same way"
tests/run_portal_sync_test.sh 3 "80,30,5"
echo "== Match: 3 players, laggy network, two matches back to back, sounds (Construction Site)"
MAP=construction_site tests/run_match_test.sh 3 "100,40,5"
echo "== Bots: every difficulty, a fight and a rematch, a free-for-all, a sword bot, sounds (Construction Site)"
MAP=construction_site tests/run_bot_test.sh
echo "== Bots in an online lobby: run by the host, seen moving by a client, kills and results agree"
tests/run_online_bots_test.sh
echo "== Ground slam: in Practice on a dummy, and a client's slam ruled on by the host"
tests/run_slam_test.sh
echo "== Respawn visibility: players dying and coming back online, a client's respawn news held up behind their snapshots; nobody stays invisible"
tests/run_respawn_visible_test.sh
echo "== Kick kills in the kill feed: a client kicked into a wall and kicked down, the boot and the wall on both copies"
tests/run_kick_feed_test.sh
echo "== Halcyon online and with bots: a client fires the terminal, a late joiner is told, bots use it and cope"
tests/run_gravity_test.sh
echo "== Race mode: bots finish a race, fail conditions, results"
tests/run_race_test.sh
echo "== Killcam: Vs Bots (watch, skip), online host and laggy client agree on the best kills, results screen plays them"
tests/run_killcam_test.sh
echo "== Killcam mode: snipers only, points from killcam scores, the #1 killcam bonus, online agreement"
tests/run_killcam_mode_test.sh
echo "== Golden Gun: one holder at a time, the killer takes it, a kill reloads it, online agreement"
tests/run_golden_gun_test.sh
echo "== Lobby settings: the host allows only some weapons and mobility tools; an early and a late joiner, the death-screen pick, Vs Bots with one gun; scoreboard points and pings"
tests/run_lobby_settings_test.sh
echo "== Lobby: size 3 (a fourth player is refused), ready up, the host kicks the one not ready, then starts"
tests/run_lobby_test.sh
echo "== Version check: a host on v0.1.30; older and newer copies are kept out and told why, the same version and a dev build join"
tests/run_version_check_test.sh
echo "== Host controls: a random map from the host's pool for everyone (a late joiner too), and the lobby song the host picks, in step"
tests/run_host_controls_test.sh
echo "== Spectating online: a client joins mid-match to watch; nobody sees it"
tests/run_spectator_test.sh
echo "== Spectating: the host moves a player to the spectators; Play is refused while the lobby is full, and works once a slot frees up"
tests/run_spectate_move_test.sh
echo "ALL TESTS PASSED"
