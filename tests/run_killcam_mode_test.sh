#!/usr/bin/env bash
# Killcam mode test: real matches, headless. Checks that:
#  - every player, bots included, has the anti-materiel rifle and nothing else, even a
#    client who picked another gun in the lobby
#  - every kill adds its killcam score (KillScore) to the killer's points, and the
#    match ends when someone reaches the target (--points) or the clock runs out
#  - at the end the match's #1 killcam earns its killer the bonus, and the rankings
#    go by points (bonus included)
#  - online, the host and the client agree on every score, the bonus and the rankings
#  - there are no script errors
# Usage: tests/run_killcam_mode_test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=tests/out
mkdir -p "$OUT"
rm -f "$OUT"/kcmode_*.log
MAP="${MAP:-construction_site}"
PORT=$((25500 + RANDOM % 200))
TARGET=1500

# Vs Bots, on a fixed game clock: you and 3 Hard bots, first to $TARGET points.
timeout 300 "$GODOT" --fixed-fps 60 --headless --path . -- --game-clock --bot=2 --bots=3 --rules=killcam --points=$TARGET \
  --time-limit=120 --map="$MAP" --weapon=shotgun --scripted-input --scripted-fire --sync-log --quit-after=135 \
  > "$OUT/kcmode_bot.log" 2>&1 &
# Online (real time): a host and a client who asked for a revolver.
COMMON=(--scripted-input --scripted-fire --sync-log --map="$MAP" --quit-after=150)
"$GODOT" --headless --path . -- --host --port="$PORT" --name=Host --weapon=pistol --autostart=2 --rules=killcam \
  --points=$TARGET --time-limit=90 "${COMMON[@]}" > "$OUT/kcmode_host.log" 2>&1 &
sleep 1
"$GODOT" --headless --path . -- --join="127.0.0.1:$PORT" --name=Client --weapon=revolver --net-sim=80,20,2 "${COMMON[@]}" \
  > "$OUT/kcmode_client.log" 2>&1 &
for _ in $(seq 1 150); do
  sleep 1
  if grep -q "^MATCH_OVER" "$OUT/kcmode_client.log" 2>/dev/null && grep -q "^MATCH_OVER" "$OUT/kcmode_host.log"; then sleep 2; break; fi
done
pkill -f -- "--port=$PORT" || true
pkill -f -- "--join=127.0.0.1:$PORT" || true
wait || true

python3 - "$OUT" "$TARGET" <<'PY'
import json, re, sys
out, target = sys.argv[1], int(sys.argv[2])
BONUS = 1500
fail = False

def read(name):
    return open(f"{out}/kcmode_{name}.log", errors="replace").read()

def bad(msg):
    global fail
    fail = True
    print("  FAIL:", msg)

def check_match(name, log, host_log=None):
    if "SCRIPT ERROR" in log:
        bad(f"{name}: script errors")
    guns = set(re.findall(r"^GUN SELF \d+ \d+ (\w+)", log, re.M))
    print(f"{name}: guns shown {sorted(guns)}")
    if guns != {"anti_materiel"}:
        bad(f"{name}: everyone should have the anti-materiel rifle and nothing else ({sorted(guns)})")
    overs = re.findall(r"^MATCH_OVER (.*)$", log, re.M)
    if not overs:
        bad(f"{name}: the match never ended"); return None
    rows = json.loads(overs[0])
    # Kills scored by the host (it prints the same KILL_SCORE lines on every copy).
    kills = [(int(s), int(k), int(v), int(p)) for s, k, v, p in re.findall(r"^KILL_SCORE (\d+) (\d+) (\d+) (\d+)", log, re.M)]
    first_over = log.index(overs[0])
    kills = [k for k in kills if log.index(f"KILL_SCORE {k[0]} {k[1]} {k[2]} {k[3]}") < first_over]
    earned = {}
    for _, killer, victim, pts in kills:
        if killer != victim:
            earned[killer] = earned.get(killer, 0) + pts
    best = sorted(kills, key=lambda k: (-k[3], k[0]))[0] if kills else None
    print(f"{name}: {len(kills)} kills, points {[(r['name'], r['points'], r.get('bonus', 0)) for r in rows]}")
    for r in rows:
        want = earned.get(r["id"], 0) + (BONUS if best and r["id"] == best[1] else 0)
        if r["points"] != want:
            bad(f"{name}: {r['name']} has {r['points']} points; their kills' killcam scores plus any bonus make {want}")
        if r.get("bonus", 0) != (BONUS if best and r["id"] == best[1] else 0):
            bad(f"{name}: the #1 killcam bonus should go to the killer of kill {best[0] if best else '-'} only")
    if [r["points"] for r in rows] != sorted((r["points"] for r in rows), reverse=True):
        bad(f"{name}: the rankings should go by points")
    # It ends at the kill that takes someone to the target (or on the clock).
    running = {}
    for i, (_, killer, victim, pts) in enumerate(kills):
        if killer != victim:
            running[killer] = running.get(killer, 0) + pts
            if running[killer] >= target and i != len(kills) - 1:
                bad(f"{name}: the match should have ended at kill {kills[i][0]}, which passed {target} points")
                break
    if not running or max(running.values()) < target:
        print(f"{name}: ended on the clock (the most before the bonus: {max(running.values()) if running else 0})")
    return rows

bot = check_match("Vs Bots", read("bot"))
host = check_match("Online host", read("host"))
client = check_match("Online client", read("client"))
# The host's points to win (a lobby setting, --points) reach the client too.
for name in ["bot", "host", "client"]:
    rules = re.findall(r"^KILLCAM_RULES \d+ (\d+) (\d+)", read(name), re.M)
    print(f"{name}: plays to {rules[:1]}")
    if not rules or int(rules[0][0]) != target:
        bad(f"{name}: the match should play to the host's {target} points ({rules[:1]})")
if host is not None and client is not None and host != client:
    bad(f"the host and the client disagree on the results:\n    host   {host}\n    client {client}")

print("KILLCAM MODE TEST", "FAILED" if fail else "PASSED")
sys.exit(1 if fail else 0)
PY
