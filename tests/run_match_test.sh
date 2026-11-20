#!/usr/bin/env bash
# Automated match test: a host and clients run headless, move on their own, aim at
# the nearest opponent they can see and shoot. Checks that:
#  - hits land (the host's rewind matches what shooters saw), even on a laggy network
#  - kills, deaths and respawns happen
#  - the match ends at the kill target and every copy gets the same results
#  - every copy shows the others' animations, shots, reloads and deaths
#  - every copy shows each player as the robot they picked and with the gun they
#    picked (the copies start with different guns), and new picks made in the lobby
#    between the two matches show up in the second one
#  - every copy hears its own gun, and the other players' shots and footsteps placed
#    in the world, and someone hears a hit
#  - there are no script errors
# Usage: tests/run_match_test.sh [PLAYERS] [NET_SIM]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PLAYERS="${1:-3}"
SIM="${2:-}"
PORT=$((25000 + RANDOM % 200))
OUT=tests/out
mkdir -p "$OUT"
rm -f "$OUT"/match_*.log
EXTRA=()
if [[ -n "$SIM" ]]; then EXTRA+=("--net-sim=$SIM"); fi
if [[ -n "${MAP:-}" ]]; then EXTRA+=("--map=$MAP"); fi   # MAP=testing_grounds picks the map (default: the game's default)
COMMON=(--scripted-input --scripted-fire --sync-log --sound-log --auto-return --switch-character --switch-weapon --quit-after=150)
CHARACTERS=(needle vanguard)
GUNS=(pistol shotgun rifle bolt_action)

"$GODOT" --headless --path . -- --host --port="$PORT" --name=P1 --character=needle --weapon=pistol --autostart="$PLAYERS" \
  --rules=kills:4 --time-limit=60 "${COMMON[@]}" "${EXTRA[@]}" > "$OUT/match_1.log" 2>&1 &
HOST=$!
sleep 1
for i in $(seq 2 "$PLAYERS"); do
  "$GODOT" --headless --path . -- --join="127.0.0.1:$PORT" --name="P$i" --character="${CHARACTERS[$(((i + 1) % 2))]}" --weapon="${GUNS[$(((i - 1) % 4))]}" "${COMMON[@]}" "${EXTRA[@]}" \
    > "$OUT/match_$i.log" 2>&1 &
done
# Two matches back to back (results -> lobby -> play again). Stop everyone a few
# seconds after the host reports the second match is over.
for _ in $(seq 1 150); do
  sleep 1
  if [[ $(grep -c "^MATCH_OVER" "$OUT/match_1.log") -ge 2 ]]; then sleep 3; break; fi
done
pkill -f -- "--port=$PORT" || true
pkill -f -- "--join=127.0.0.1:$PORT" || true
wait || true

fail=0
if grep -h "SCRIPT ERROR" "$OUT"/match_*.log; then echo "FAIL: script errors"; fail=1; fi
python3 - "$OUT" "$PLAYERS" <<'PY' || fail=1
import glob, json, sys, re
out, players = sys.argv[1], int(sys.argv[2])
results = {}
ok = True
hits = misses = heads = 0
per_gun = {}   # gun -> [shots that hit, shots]
walls = {}     # path -> what was cracked and broken when each match ended
for path in sorted(glob.glob(f"{out}/match_*.log")):
    last_shot = ""
    wall_state = "none"
    for line in open(path, errors="replace"):
        if line.startswith("BROKEN_STATE "):
            wall_state = line.split(" ", 1)[1].strip()
            if wall_state.startswith("0/0 "): wall_state = "none"
        if line.startswith("MATCH_OVER "):
            walls.setdefault(path, []).append(wall_state)
            wall_state = "none"   # the next match starts on a whole map
        if path.endswith("match_1.log") and line.startswith("PELLETS "):
            g = per_gun.setdefault(line.split()[2], [0, 0])
            g[0] += " hit " in last_shot
            g[1] += 1
        if line.startswith("MATCH_OVER "):
            results.setdefault(path, []).append(json.loads(line[len("MATCH_OVER "):]))
        if path.endswith("match_1.log") and line.startswith("SHOT "):
            last_shot = line
            if " hit " in line:
                hits += 1
                if line.rstrip().endswith(" head"): heads += 1
            else: misses += 1
shots = hits + misses
ratio = hits / shots if shots else 0
print(f"shots judged by host: {shots}, hits {hits} ({ratio:.0%}), headshots {heads}")
print("by gun: " + ", ".join(f"{g} {h}/{n}" for g, (h, n) in sorted(per_gun.items())))
# The automatic guns' wobble (and their long bursts while the target moves) makes
# them miss more by design, so the rewind check looks at the other guns. Any pellet
# counts for the shotgun.
SPRAY = {"rifle", "burst_rifle", "smg", "lmg", "machine_pistol"}
if per_gun:
    aimed = [v for g, v in per_gun.items() if g not in SPRAY]
    hits_aimed, shots_aimed = sum(h for h, _ in aimed), sum(n for _, n in aimed)
    ratio = hits_aimed / shots_aimed if shots_aimed else ratio
    rifle = per_gun.get("rifle", [0, 0])
    if rifle[1] >= 10 and rifle[0] < rifle[1] * 0.25:
        print("FAIL: the rifle hardly ever hits"); ok = False
if hits and heads == 0:
    print("FAIL: no headshots registered although shooters aim at heads half the time"); ok = False
if shots < 20:
    print("FAIL: too few shots"); ok = False
elif ratio < 0.6:
    print("FAIL: hit rate too low; rewind may not match what shooters saw"); ok = False
if len(results) != players or any(len(r) < 2 for r in results.values()):
    print(f"FAIL: not every copy saw both matches end: { {k: len(v) for k, v in results.items()} }"); ok = False
else:
    print("both matches finished on every copy (results -> lobby -> play again works)")
    first = list(results.values())[0][1]
    if any(r[1] != first for r in results.values()):
        print("FAIL: copies disagree about the results"); ok = False
    top = first[0]
    print("results:", ", ".join(f"{r['name']} {r['kills']}K/{r['deaths']}D" for r in first))
    if top["kills"] < 4:
        print("FAIL: winner did not reach the kill target"); ok = False
    if sum(r["deaths"] for r in first) < 4:
        print("FAIL: too few deaths"); ok = False
# Breakable walls and floors: every copy ends each match with the same damage.
first_walls = list(walls.values())[0] if walls else []
print("walls at each match end (cracked/broken checksum): " + ", ".join(first_walls))
if any(w != first_walls for w in walls.values()):
    print(f"FAIL: copies disagree about broken walls: {walls}"); ok = False
print("PASS: match test" if ok else "FAIL: match test")
sys.exit(0 if ok else 1)
PY
echo "-- Animation: every copy shows what each player is doing"
python3 tests/check_anim.py --need=loco,air,death,reload --characters=2 --switched --guns=3 --switched-guns "$OUT"/match_*.log || fail=1
echo "-- Sounds: every copy hears itself and the others"
for i in $(seq 1 "$PLAYERS"); do
  log="$OUT/match_$i.log"
  grep -qE "^SFX fire_[a-z_]+_fp" "$log" || { echo "FAIL: copy $i never heard its own gun"; fail=1; }
  grep -qE "^SFX3D fire_[a-z_]+ " "$log" || { echo "FAIL: copy $i never heard another player's shot in the world"; fail=1; }
  grep -qE "^SFX3D step " "$log" || { echo "FAIL: copy $i never heard another player's footsteps"; fail=1; }
done
grep -qhE "^SFX (hitmarker|hurt|kill)" "$OUT"/match_*.log || { echo "FAIL: nobody heard a hit"; fail=1; }
[[ $fail -eq 0 ]] && echo "PASS: sounds"
exit $fail
