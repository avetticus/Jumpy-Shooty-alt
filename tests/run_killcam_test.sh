#!/usr/bin/env bash
# Killcam test: real matches, headless. Checks that:
#  - Vs Bots: when the bot knocks you out, the killcam plays the kill from the bot's
#    eyes with seconds of its recording, and stops when you respawn; jump skips it
#    (and you still respawn); at the end every best kill has a clip, they play, and
#    the best saves as a video file
#  - online, a host and a client (the client on a laggy network): each copy that is
#    knocked out watches its killcam; both copies score every kill the same, pick the
#    same best kills, have a clip of each, and play them on the results screen
#  - every killcam knows where the killer's shots were aimed (the replay holds the
#    crosshair to them) and records the map's moving parts (the crane, its rope and
#    the breakable walls)
#  - there are no script errors
# Usage: tests/run_killcam_test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=tests/out
mkdir -p "$OUT"
rm -f "$OUT"/killcam_*.log
MAP="${MAP:-construction_site}"
PORT=$((25300 + RANDOM % 200))

# Vs Bots, on a fixed game clock (Godot's --fixed-fps 60 and --game-clock), so a
# busy machine plays them out the same, only slower: you run about without shooting
# and the Expert bot gets you three times (first to 3, or the time limit).
OFFLINE=(--fixed-fps 60 --headless --path . -- --game-clock --bot=3 --bot-weapon=rifle --map="$MAP" --scripted-input --sync-log)
timeout 300 "$GODOT" "${OFFLINE[@]}" --kill-target=3 --time-limit=60 --quit-after=100 --save-killcam=1 > "$OUT/killcam_bot.log" 2>&1 &
# ...and once more pressing jump every half second (from 2 s, first to 3: a killcam to
# skip whenever the bot strikes), respawning only on a press as in a
# real game (--manual-respawn): every killcam is skipped, and jump brings you back.
PRESSES=()
for s in $(seq 2 0.5 60); do PRESSES+=("--press=$s:jump"); done
timeout 240 "$GODOT" "${OFFLINE[@]}" --kill-target=3 --time-limit=60 --quit-after=64 --manual-respawn "${PRESSES[@]}" > "$OUT/killcam_skip.log" 2>&1 &
# ...and with no key pressed at all: knocked out once, you stay down.
timeout 120 "$GODOT" "${OFFLINE[@]}" --kill-target=3 --time-limit=25 --quit-after=27 --manual-respawn > "$OUT/killcam_wait.log" 2>&1 &
wait || true
# Online (real time): a host and a client who move and shoot on their own; first to 4.
COMMON=(--scripted-input --scripted-fire --sync-log --map="$MAP" --quit-after=150)
"$GODOT" --headless --path . -- --host --port="$PORT" --name=Host --weapon=bolt_action --autostart=2 --rules=kills:4 \
  --time-limit=80 "${COMMON[@]}" > "$OUT/killcam_host.log" 2>&1 &
sleep 1
"$GODOT" --headless --path . -- --join="127.0.0.1:$PORT" --name=Client --weapon=revolver --net-sim=80,20,2 "${COMMON[@]}" \
  > "$OUT/killcam_client.log" 2>&1 &
# Stop the online pair a few seconds after the match ends (the results screen plays).
for _ in $(seq 1 150); do
  sleep 1
  if grep -q "^KILLCAM_RESULTS_DONE" "$OUT/killcam_client.log" 2>/dev/null && grep -q "^KILLCAM_RESULTS_DONE" "$OUT/killcam_host.log"; then sleep 2; break; fi
done
pkill -f -- "--port=$PORT" || true
pkill -f -- "--join=127.0.0.1:$PORT" || true
wait || true

python3 - "$OUT" <<'PY'
import re, sys
out = sys.argv[1]
fail = False

def read(name):
    return open(f"{out}/killcam_{name}.log", errors="replace").read()

def bad(msg):
    global fail
    print("  FAIL: " + msg)
    fail = True

def plays(log):
    # KILLCAM PLAY <me> <killer> <seq> <killer frames> <first> <last> (seconds from the kill)
    return [tuple(float(x) for x in m) for m in re.findall(r"^KILLCAM PLAY (\d+) (\d+) (\d+) (\d+) (-?[\d.]+) (-?[\d.]+)$", log, re.M)]

def syncs(log):
    # KILLCAM SYNC <me> <killer> <shots aimed> <map parts> <victim moved (ms)>
    return re.findall(r"^KILLCAM SYNC (\d+) (\d+) (\d+) (\S*) (-?\d+)$", log, re.M)

def aims(log):
    # KILLCAM AIM <me> <shots worked out> <the most the recording was off at one (degrees)>
    return [(int(n), float(d)) for n, d in re.findall(r"^KILLCAM AIM \d+ (\d+) ([\d.]+)$", log, re.M)]

def check_sync(name, log, gun_kills):
    sy, am = syncs(log), aims(log)
    print(f"{name}: killcam sync {[(int(k), int(ms)) for _, _, k, _, ms in sy]} (shots aimed, victim moved ms); "
          f"aim worked out {am} (shots, worst degrees off before the fix)")
    for _, _, keys, parts, ms in sy:
        if gun_kills and int(keys) < 1:
            bad(f"{name}: a killcam of a gun kill has none of the killer's aims")
        if not {".", "Breakables", "Crane/CraneEvent"} <= set(parts.split(",")):
            bad(f"{name}: a killcam did not record the map's moving parts ({parts})")
        if abs(int(ms)) > 300:
            bad(f"{name}: the victim was moved further than allowed ({ms} ms)")
    if gun_kills and am and max(n for n, _ in am) < 1:
        bad(f"{name}: no killcam worked out the killer's aim at their shots")

def scores(log):
    return re.findall(r"^KILL_SCORE (\d+) (\d+) (\d+) (\d+)", log, re.M)

def best_kills(log):
    return re.findall(r"^HIGHLIGHTS (.*)$", log, re.M)

def clips(log):
    return re.findall(r"^KILLCAM_CLIPS \d+ (.*)$", log, re.M)

def check_results(name, log):
    hl = best_kills(log)
    cl = clips(log)
    shown = re.findall(r"^KILLCAM_RESULTS \d+ (\d+) (\w+)", log, re.M)
    if not hl or not hl[-1].strip():
        bad(f"{name}: the match ended with no best kills"); return
    seqs = [h.split(":")[0] for h in hl[-1].split()]
    if not cl or any(not c.endswith(":clip") for c in cl[-1].split()):
        bad(f"{name}: not every best kill has a clip ({cl[-1] if cl else 'none'})")
    want = [(s, "play") for s in reversed(seqs)]   # counting down to the best
    if shown[:len(want)] != want:
        bad(f"{name}: after the match the best kills should play {list(reversed(seqs))}, the best last ({shown})")
    if f"KILLCAM_RESULTS_DONE" not in log:
        bad(f"{name}: the best kills never finished playing to show the results page")
    print(f"{name}: best kills {hl[-1]}  clips {cl[-1] if cl else '-'}  results played {[s for s, _ in shown]}")

# --- Vs Bots
log = read("bot")
if "SCRIPT ERROR" in log:
    bad("bot match: script errors")
p = plays(log)
deaths = [s for s in scores(log) if s[2] == "1"]
print(f"Vs Bots: you were knocked out {len(deaths)} times, killcams {len(p)}, "
      f"ended at respawn {log.count('KILLCAM END 1')}, ran to the end {log.count('KILLCAM DONE 1')}")
if len(p) < 2:
    bad("the killcam should play each time the bot knocks you out")
for me, killer, seq, frames, first, last in p:
    if killer != 9001:
        bad(f"killcam {int(seq)} is not from the bot's view")
    if frames < 10 or last < -0.2:
        bad(f"killcam {int(seq)} has too little of the bot's recording ({int(frames)} frames, {first} to {last} s round the kill)")
if p and max(f for _, _, _, f, _, _ in p) < 60:
    bad("no killcam had the full few seconds before the kill (only right after the start can it have less)")
if log.count("KILLCAM END 1") + log.count("KILLCAM DONE 1") < len(p) - 1:   # (the last may be cut short by the end of the match)
    bad("killcams should run until you respawn")
check_results("Vs Bots", log)
check_sync("Vs Bots", log, True)
saved = re.findall(r"^KILLCAM_SAVED \d+ (\d+) (\d+) ([\d.]+) (\S+) (.*)$", log, re.M)
print(f"Vs Bots: saved as a video {saved[:1]}")
if not saved or saved[0][3] != "ok" or int(saved[0][1]) < 60 or not saved[0][4].endswith((".mp4", ".avi")):
    bad("the best kill should save as a video from the results screen")
else:
    import os
    head = open(saved[0][4], "rb").read(8) if os.path.isfile(saved[0][4]) else b""
    if not (head[4:8] == b"ftyp" if saved[0][4].endswith(".mp4") else head[:4] == b"RIFF"):
        bad(f"the saved video is not there ({saved[0][4]})")
    else:
        os.remove(saved[0][4])

log = read("skip")
if "SCRIPT ERROR" in log:
    bad("skip match: script errors")
skips = log.count("KILLCAM SKIP 1")
print(f"Skipping: killcams {len(plays(log))}, skipped {skips}")
if skips < 1 or skips < len(plays(log)) - 1:
    bad("pressing jump should skip the killcam")
if "KILLCAM SKIP BY" not in log:
    bad("the skip should come from the jump key")
early = [float(t) for t in re.findall(r"^KILLCAM SKIP BY .* ([\d.]+)$", log, re.M) if float(t) < 0.75]
if early:
    bad(f"a killcam was skipped before it had played 0.75 s ({early})")
if "KILLCAM TOO SOON" not in log:
    bad("a press right as the killcam starts should not skip it (none was too soon)")
asks = [float(t) for t in re.findall(r"^RESPAWN BY .* ([\d.]+)$", log, re.M)]
back = log.count("RESPAWNED 1")
print(f"Respawning on a press: deaths {len(scores(log))}, respawned {back}, pressed after {asks} s of the death screen")
if back < 1 or back != len(asks):
    bad("pressing jump on the death screen should bring you back, and only a press should")
if any(t < 0.5 for t in asks):
    bad("a press in the death screen's first half second should not respawn you")
if "RESPAWN TOO SOON" not in log or re.search(r"^RESPAWN_ASK 1 \S+ early", log, re.M):
    bad("presses before the wait is over should be ignored, and none should reach the host")

log = read("wait")
if "SCRIPT ERROR" in log:
    bad("wait match: script errors")
deaths = [s for s in scores(log) if s[2] == "1"]
print(f"No key pressed: knocked out {len(deaths)} times, respawned {log.count('RESPAWNED 1')}")
if len(deaths) != 1 or "RESPAWNED 1" in log:
    bad("with no key pressed you should stay down after your first death")
if "KILLCAM DONE 1" not in log and "KILLCAM NONE 1" not in log:   # (none: knocked out too soon after the start for a replay)
    bad("the killcam should play to its end and give way to the death screen")

# --- Online
host, client = read("host"), read("client")
for name, l in [("host", host), ("client", client)]:
    if "SCRIPT ERROR" in l:
        bad(f"online {name}: script errors")
hs, cs = scores(host), scores(client)
print(f"Online: {len(hs)} kills on the host, {len(cs)} on the client")
if len(hs) < 4:
    bad("too few kills online")
if hs != cs:
    bad(f"the copies scored the kills differently:\n    host   {hs}\n    client {cs}")
for name, l in [("host", host), ("client", client)]:
    me = re.search(r"^KILLCAM_CLIPS (\d+)", l, re.M)
    me = me.group(1) if me else None
    mine = [s for s in hs if s[2] == me]
    p = plays(l)
    print(f"  {name} (id {me}): knocked out {len(mine)} times, killcams {len(p)}")
    if mine and not p:
        bad(f"{name} never watched a killcam")
    for _, killer, seq, frames, first, last in p:
        killed = [s for s in hs if s[0] == str(int(seq))]
        if not killed or killed[0][1] != str(int(killer)) or killed[0][2] != me:
            bad(f"{name}: killcam {int(seq)} is not of a kill on this copy's player by its killer")
        if (frames < 10 and first < -1.0) or last < -0.5:   # (a kill in the first second has little before it)
            bad(f"{name}: killcam {int(seq)} has too little of the killer's recording ({int(frames)} frames, {first} to {last} s)")
# The killer sees the points their kill scored, and where they came from.
by_seq = {s[0]: s for s in hs}
points = []
for name, l in [("host", host), ("client", client)]:
    for me, seq, total, parts in re.findall(r"^KILL_POINTS (\d+) (\d+) (\d+) (.*)$", l, re.M):
        points.append(seq)
        got = sum(int(x.rsplit("=", 1)[1]) for x in parts.split(","))
        if got != int(total) or seq not in by_seq or by_seq[seq][1] != me or by_seq[seq][3] != total:
            bad(f"{name}: kill {seq}'s points ({parts}) should add up to its score {by_seq.get(seq)} and show to its killer")
print(f"  points shown to the killer for {len(points)} of {len(hs)} kills")
if len(points) < len(hs) - 1:
    bad("each kill's points should show to its killer")
hb, cb = best_kills(host), best_kills(client)
if not hb or hb != cb:
    bad(f"the copies picked different best kills: host {hb}, client {cb}")
check_results("  host", host)
check_results("  client", client)
check_sync("  host", host, True)
check_sync("  client", client, True)

print("KILLCAM TEST", "FAILED" if fail else "PASSED")
sys.exit(1 if fail else 0)
PY
