#!/usr/bin/env bash
# Lobby settings in real matches: the host allows only some weapons (--allowed-weapons).
#  - online: a client who joins before the start with a weapon that is not allowed,
#    and one who joins mid-match with another, are both told the setting and given an
#    allowed weapon; every copy only ever has allowed weapons on record, the host only
#    judges shots from allowed weapons, and weapons picked on the death screen (the
#    number keys, --swap-on-death) are allowed ones; the host turns the jetpack on
#    (--jetpack): everyone is told, and everyone has the grappling hook on record;
#  - Vs Bots with one gun (the bat): you and every bot have it;
#  - no script errors anywhere.
# (The rules and the pickers are checked step by step in tests/lobby_settings_test.gd.)
# Usage: tests/run_lobby_settings_test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=tests/out
mkdir -p "$OUT"
rm -f "$OUT"/lobby_*.log
MAP="${MAP:-construction_site}"
PORT=$((25900 + RANDOM % 100))
COMMON=(--scripted-input --scripted-fire --sync-log --map="$MAP")

# Vs Bots, on a fixed game clock: one gun for everyone.
timeout 120 "$GODOT" --fixed-fps 60 --headless --path . -- --game-clock --bot=1 --bots=2 --allowed-weapons=bat --weapon=pistol \
  --bot-weapon=bolt_action --sync-log --map="$MAP" --quit-after=8 > "$OUT/lobby_bots.log" 2>&1 &
# Online: the host saved the bolt-action, P2 the pistol, P3 (joins at about 14 s) the rocket launcher.
"$GODOT" --headless --path . -- --host --port="$PORT" --name=P1 --weapon=bolt_action --allowed-weapons=shotgun,railgun,smg --jetpack --mobility=grapple \
  --autostart=2 --rules=kills:30 --time-limit=60 --swap-on-death --quit-after=34 "${COMMON[@]}" > "$OUT/lobby_host.log" 2>&1 &
sleep 1
"$GODOT" --headless --path . -- --join="127.0.0.1:$PORT" --name=P2 --weapon=pistol --mobility=grapple --swap-on-death --quit-after=32 "${COMMON[@]}" \
  > "$OUT/lobby_early.log" 2>&1 &
sleep 13
"$GODOT" --headless --path . -- --join="127.0.0.1:$PORT" --name=P3 --weapon=rocket_launcher --mobility=grapple --swap-on-death --quit-after=17 "${COMMON[@]}" \
  > "$OUT/lobby_late.log" 2>&1 &
wait || true

fail=0
if grep -h "SCRIPT ERROR" "$OUT"/lobby_*.log; then echo "FAIL: script errors"; fail=1; fi
python3 - "$OUT" <<'PY' || fail=1
import re, sys
out = sys.argv[1]
ok = True
ALLOWED = {"shotgun", "railgun", "smg"}


def check(cond, what):
    global ok
    print(("  ok    " if cond else "  FAIL  ") + what)
    ok = ok and cond


def lines(name):
    return open(f"{out}/lobby_{name}.log", errors="replace").read().splitlines()


def loadouts(name):
    """Every LOADOUTS line: a list of (player id, weapon)."""
    found = []
    for line in lines(name):
        m = re.match(r"LOADOUTS \d+ (.*)", line)
        if m:
            found.append([tuple(p.split(":")) for p in m.group(1).split()])
    return found


for name in ["host", "early", "late"]:
    told = [l for l in lines(name) if l.startswith("LOBBY_SETTINGS ")]
    check(bool(told) and told[-1].endswith("weapons=shotgun,smg,railgun"), f"{name}: told the allowed weapons ({told[-1] if told else 'never'})")
    seen = loadouts(name)
    weapons = {w for l in seen for _, w in l}
    check(bool(seen) and weapons <= ALLOWED, f"{name}: only allowed weapons on record ({sorted(weapons)})")
    told = [l for l in lines(name) if l.startswith("LOBBY_JETPACK ")]
    check(bool(told) and told[-1].endswith("jetpack=true"), f"{name}: told the jetpack is on ({told[-1] if told else 'never'})")
    tools = set()
    for line in lines(name):
        m = re.match(r"MOBILITY_LOADOUTS [0-9]+ (.*)", line)
        if m:
            tools |= {p.split(":")[1] for p in m.group(1).split()}
    check(bool(tools) and tools <= {"grapple"}, f"{name}: only the grappling hook on record ({sorted(tools)})")
    # The scoreboard: each kill adds its killcam score to the killer's points (a shoot-out,
    # not Killcam), and clients are told everyone's ping. A late joiner missed the kills
    # before it came, so each killer's first total there is taken as given.
    last, score, steps, bad = {}, 0, 0, []
    for line in lines(name):
        f = line.split()
        if line.startswith("KILL_SCORE "):
            score = int(f[4])
        elif line.startswith("POINTS "):
            if f[1] in last:
                steps += 1
                if int(f[2]) != last[f[1]] + score: bad.append(line)
            last[f[1]] = int(f[2])
    check(steps > 0 and not bad, f"{name}: each kill adds its score to the killer's points ({steps} kills, totals {last}, mismatches {bad[:2]})")
    if name != "host":
        pings = [l for l in lines(name) if l.startswith("PINGS ")]
        last = max((dict(p.split(":") for p in l.split()[2:]) for l in pings), key=len, default={})
        check(len(last) >= 2 and all(0 <= int(v) < 1000 for v in last.values()), f"{name}: told every client's ping ({last})")
late = loadouts("late")
check(any(len(l) == 3 for l in late), "the late joiner is in the list with the others")
pellets = [l.split()[2] for l in lines("host") if l.startswith("PELLETS ")]
check(bool(pellets) and set(pellets) <= ALLOWED, f"the host judges shots from allowed weapons only ({sorted(set(pellets))}, {len(pellets)} shots)")
swaps = [l.split()[2] for n in ["host", "early", "late"] for l in lines(n) if l.startswith("SWAP ")]
check(bool(swaps) and set(swaps) <= ALLOWED, f"death-screen picks are allowed weapons ({sorted(set(swaps))}, {len(swaps)} picks)")
bots = loadouts("bots")
check(bool(bots) and all(w == "bat" for l in bots for _, w in l) and len(bots[-1]) == 3,
      f"Vs Bots, one gun: you and both bots have the bat ({bots[-1] if bots else 'no list'})")
print("PASS: lobby settings test" if ok else "FAIL: lobby settings test")
sys.exit(0 if ok else 1)
PY
exit $fail
