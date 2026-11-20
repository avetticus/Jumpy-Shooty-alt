#!/usr/bin/env bash
# Bots in an online lobby: the host adds two (--host-bots) and runs them; a client on
# a laggy network plays with them. Checks that:
#  - the client sees both bots, and sees them move where the host has them (the host
#    sends their movement for them)
#  - bots kill and are killed, and the host and the client agree on every kill
#  - the match ends and both copies agree on the results
#  - there are no script errors
# Usage: tests/run_online_bots_test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=tests/out
mkdir -p "$OUT"
rm -f "$OUT"/obots_*.log
MAP="${MAP:-construction_site}"
PORT=$((26100 + RANDOM % 200))
TARGET=6

COMMON=(--scripted-input --scripted-fire --sync-log --map="$MAP" --quit-after=150)
"$GODOT" --headless --path . -- --host --port="$PORT" --name=Host --weapon=rifle --host-bots=2 --bot-level=2 \
  --autostart=4 --kill-target=$TARGET --time-limit=90 "${COMMON[@]}" > "$OUT/obots_host.log" 2>&1 &
sleep 1
"$GODOT" --headless --path . -- --join="127.0.0.1:$PORT" --name=Client --weapon=rifle --net-sim=60,15,1 "${COMMON[@]}" \
  > "$OUT/obots_client.log" 2>&1 &
for _ in $(seq 1 150); do
  sleep 1
  if grep -q "^MATCH_OVER" "$OUT/obots_client.log" 2>/dev/null && grep -q "^MATCH_OVER" "$OUT/obots_host.log"; then sleep 2; break; fi
done
pkill -f -- "--port=$PORT" || true
pkill -f -- "--join=127.0.0.1:$PORT" || true
wait || true

python3 - "$OUT" <<'PY'
import json, re, sys
out = sys.argv[1]
fail = False
def bad(msg):
    global fail
    fail = True
    print("  FAIL:", msg)
host = open(f"{out}/obots_host.log", errors="replace").read()
client = open(f"{out}/obots_client.log", errors="replace").read()
for name, log in (("host", host), ("client", client)):
    if "SCRIPT ERROR" in log:
        bad(f"{name}: script errors")
        for m in re.finditer(r"SCRIPT ERROR.*\n.*\n", log):
            print("   ", m.group(0).strip().replace("\n", " | "))
            break
bots = sorted({int(b) for b in re.findall(r"^SYNC SELF (9\d\d\d) ", host, re.M)})
print(f"bots the host runs: {bots}")
if len(bots) != 2:
    bad(f"the host should run 2 bots, not {bots}")
# Where the client sees each bot, against where the host had it at about that moment.
for b in bots:
    seen = [(float(t), float(x), float(z)) for t, x, z in re.findall(rf"^SYNC SEEN \d+ {b} ([\d.-]+) ([\d.-]+) [\d.-]+ ([\d.-]+)", client, re.M)]
    own = [(float(t), float(x), float(z)) for t, x, z in re.findall(rf"^SYNC SELF {b} ([\d.-]+) ([\d.-]+) [\d.-]+ ([\d.-]+)", host, re.M)]
    if len(seen) < 100:
        bad(f"the client hardly sees bot {b} ({len(seen)} frames)")
        continue
    moved = sum(abs(a[1] - c[1]) + abs(a[2] - c[2]) for a, c in zip(seen, seen[1:]))
    if moved < 20:
        bad(f"bot {b} doesn't move on the client ({moved:.1f} m)")
    # The client's view runs on the host's clock (a little behind): match each seen
    # position to the host's at that time.
    errs = []
    j = 0
    for t, x, z in seen[::10]:
        while j + 1 < len(own) and own[j + 1][0] <= t:
            j += 1
        if own and abs(own[j][0] - t) < 0.1:
            errs.append(((own[j][1] - x) ** 2 + (own[j][2] - z) ** 2) ** 0.5)
    errs.sort()
    median = errs[len(errs) // 2] if errs else 99
    print(f"bot {b}: client sees {len(seen)} frames, moved {moved:.0f} m, median gap to the host {median:.2f} m ({len(errs)} matched)")
    if not errs or median > 1.5:
        bad(f"the client sees bot {b} far from where the host has it (median {median:.2f} m)")
kills = lambda log: re.findall(r"^KILL_SCORE (\d+) (\d+) (\d+)", log, re.M)
hk, ck = kills(host), kills(client)
print(f"kills: host {len(hk)}, client {len(ck)}; with a bot in them: {sum(1 for _, k, v in hk if int(k) > 9000 or int(v) > 9000)}")
if not any(int(k) > 9000 for _, k, v in hk):
    bad("no bot got a kill")
if not any(int(v) > 9000 for _, k, v in hk):
    bad("no bot was killed")
if hk != ck:
    bad("the host and the client disagree on the kills")
over = lambda log: (re.findall(r"^MATCH_OVER (.*)$", log, re.M) or [None])[0]
ho, co = over(host), over(client)
if not ho or not co:
    bad("the match didn't end on both copies")
else:
    rows = lambda o: [(r["name"], r["kills"]) for r in json.loads(o)]
    print(f"results: {rows(ho)}")
    if rows(ho) != rows(co):
        bad("the host and the client disagree on the results")
print("ONLINE BOTS TEST", "FAILED" if fail else "PASSED")
sys.exit(1 if fail else 0)
PY
