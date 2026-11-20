#!/usr/bin/env bash
# Respawn visibility online: a host and two clients aim and shoot on their own, so
# players die and come back again and again. Client 2 applies every other player's
# respawn 300 ms late (--delay-respawn), so that player's first snapshot from the new
# life gets there before the news that they are back; client 3 gets them as usual.
# Checks, on each client, that:
#  - every respawned player is shown again (none stays invisible but still in the fight)
#  - on client 2 some were shown at once, their snapshot already there (the delay
#    really did put the snapshot first); on client 3, when their snapshot came
#  - the safety net (RESPAWN_SHOW_LATE: hidden for over a second while alive) never fires
#  - there are no script errors
# Usage: tests/run_respawn_visible_test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=tests/out
mkdir -p "$OUT"
rm -f "$OUT"/respawn_*.log
PORT=$((25600 + RANDOM % 200))
COMMON=(--map=testing_grounds --scripted-input --scripted-fire --sync-log --weapon=lever_action)
fail=0

timeout 110 "$GODOT" --headless --path . -- --host --name=P1 --autostart=3 --port="$PORT" --kill-target=999 --time-limit=120 \
  "${COMMON[@]}" --quit-after=65 > "$OUT/respawn_host.log" 2>&1 &
sleep 1
timeout 110 "$GODOT" --headless --path . -- --join="127.0.0.1:$PORT" --name=P2 --delay-respawn=300 \
  "${COMMON[@]}" --quit-after=67 > "$OUT/respawn_client2.log" 2>&1 &
timeout 110 "$GODOT" --headless --path . -- --join="127.0.0.1:$PORT" --name=P3 \
  "${COMMON[@]}" --quit-after=67 > "$OUT/respawn_client3.log" 2>&1 &
wait || true

# Reads one client's log. A remote player's respawn (RESPAWNED id) must be followed by
# RESPAWN_SHOW for them, or by RESPAWN_CANCEL (killed again before their new life was
# seen), within 90 of this copy's frames (SYNC SELF lines, 60 a second): 1.5 s.
check_client() {   # check_client log how ("early": shown at once, "snapshot": when it came)
  awk -v how="$2" '
    /^SYNC SELF / { frame++; if (me == "") me = $3; for (id in open) if (frame - open[id] > 90) { stuck++; print "    stuck: player " id " respawned, still hidden 1.5 s later"; delete open[id] } }
    /^RESPAWNED / { if ($2 != me) { respawns++; open[$2] = frame } }
    /^RESPAWN_SHOW / { delete open[$3]; shown++; if ($4 == how) expected++ }
    /^RESPAWN_CANCEL / { delete open[$3]; cancelled++ }
    /^RESPAWN_SHOW_LATE / { late++ }
    END { printf "    %d respawns of other players: %d shown (%d %s), %d killed again unseen, %d stuck, %d shown late by the safety net\n", respawns, shown, expected, how == "early" ? "at once, snapshot first" : "when their snapshot came", cancelled, stuck, late
      exit (respawns >= 4 && expected >= 1 && stuck == 0 && late == 0) ? 0 : 1 }
  ' "$1"
}

echo "Respawn visibility checks"
if check_client "$OUT/respawn_client2.log" early; then echo "  ok    client 2 (respawns held up) shows every respawned player"
else echo "  FAIL  client 2 (respawns held up): a respawned player stayed hidden, too few respawns, or none came snapshot-first"; fail=1; fi
if check_client "$OUT/respawn_client3.log" snapshot; then echo "  ok    client 3 shows every respawned player"
else echo "  FAIL  client 3: a respawned player stayed hidden, or too few respawns"; fail=1; fi
if grep -h "SCRIPT ERROR" "$OUT"/respawn_*.log; then
  echo "  FAIL  script errors above"
  fail=1
fi
if [[ $fail -ne 0 ]]; then
  echo "FAIL: respawn visibility checks failed (logs in $OUT/respawn_*.log)"
  exit 1
fi
echo "PASS: respawn visibility"
