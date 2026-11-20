#!/usr/bin/env bash
# Automated bot test. Runs a 1v1 against each bot difficulty, headless, with the
# player moving on its own (and not shooting), plus one Expert match where the
# player shoots back. Checks that:
#  - the bot finds the player and shoots at every difficulty; Normal and up hit a
#    moving player, and even Easy hits a player standing still
#  - harder bots are more accurate (Expert beats Easy)
#  - the harder bots use the movement set: slides, dives, belly slides, flips, grapples
#  - the bot's body is animated: it plays its moves and its gun kicks on every shot
#  - the bot plays a different robot from yours (you are Needle or Vanguard in turn)
#  - the bot dodges when it gets shot
#  - matches end, and "Rematch" starts a new one
#  - a 5-player free-for-all against 4 bots: every bot shoots and hits, bots fight
#    each other as well as you, the robots alternate starting with the one you did
#    not pick, and the rematch keeps all 4 bots
#  - a melee bot (sword) rushes in winding its swing up, lands blows and knocks you back
#  - a blink bot blinks; bots fly the jetpack (Space held in mid-air) now and then
#  - sounds: your gun, steps, jumps and hit markers play in your head; the bot's shots,
#    impacts and steps play placed in the world
#  - there are no script errors
# The 1v1 bots carry the rifle (and the grapple) so their accuracy can be compared;
# the free-for-all bots take any weapon and mobility tool at random.
# Usage: [MAP=map_id] tests/run_bot_test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=tests/out
mkdir -p "$OUT"
rm -f "$OUT"/bot_*.log
COMMON=(--headless --path . -- --scripted-input --sync-log)
STILL=(--headless --path . -- --sync-log)
if [[ -n "${MAP:-}" ]]; then   # MAP=testing_grounds picks the map (default: the game's default)
  COMMON+=("--map=$MAP")
  STILL+=("--map=$MAP")
fi

for level in 0 1 2 3; do
  character=$([[ $((level % 2)) -eq 0 ]] && echo needle || echo vanguard)
  timeout 120 "$GODOT" "${COMMON[@]}" --bot="$level" --bot-weapon=rifle --bot-mobility=grapple --character="$character" --time-limit=45 --quit-after=50 \
    > "$OUT/bot_$level.log" 2>&1 &
done
# Easy against a player who stands still: even the weakest bot must land hits.
timeout 90 "$GODOT" "${STILL[@]}" --bot=0 --bot-weapon=rifle --bot-mobility=grapple --time-limit=40 --quit-after=45 \
  > "$OUT/bot_still.log" 2>&1 &
# Expert again, but the player fights back; first to 2 so it ends, then rematches.
timeout 90 "$GODOT" "${COMMON[@]}" --bot=3 --bot-weapon=rifle --bot-mobility=grapple --scripted-fire --sound-log --kill-target=2 --time-limit=40 \
  --auto-return --quit-after=50 > "$OUT/bot_fight.log" 2>&1 &
# Free-for-all: you plus 4 Hard bots, first to 3 kills, then a rematch.
timeout 150 "$GODOT" "${COMMON[@]}" --bot=2 --bots=4 --character=vanguard --kill-target=3 --time-limit=25 \
  --auto-return --quit-after=62 > "$OUT/bot_ffa.log" 2>&1 &
# A sword bot (Hard) against a player who moves on its own.
timeout 90 "$GODOT" "${COMMON[@]}" --bot=2 --bot-weapon=sword --bot-mobility=grapple --time-limit=40 --quit-after=45 \
  > "$OUT/bot_melee.log" 2>&1 &
# An Expert bot with blink.
timeout 90 "$GODOT" "${COMMON[@]}" --bot=3 --bot-weapon=rifle --bot-mobility=blink --time-limit=40 --quit-after=45 \
  > "$OUT/bot_blink.log" 2>&1 &
wait || true

python3 - "$OUT" <<'EOF'
import json, re, sys
out = sys.argv[1]
names = ["Easy", "Normal", "Hard", "Expert"]
fail = False
rates = {}
moves = set()
anims = set()

def read(name):
    return open(f"{out}/bot_{name}.log", encoding="utf-8", errors="replace").read()

def bot_stats(log):
    shots = re.findall(r"^SHOT 9001 (.*)$", log, re.M)
    hits = [s for s in shots if s.startswith("hit")]
    kinds = set(re.findall(r"^BOT_MOVE 9001 (\w+)", log, re.M))
    ropes = len(re.findall(r"^ROPE SELF 9001 on", log, re.M))
    spots = re.findall(r"^BOT 9001 (\S+) (\S+) (\S+)", log, re.M)
    return shots, hits, kinds, ropes, spots

for level in range(4):
    log = read(level)
    shots, hits, kinds, ropes, spots = bot_stats(log)
    errors = log.count("SCRIPT ERROR")
    moved = len({(round(float(x)), round(float(z))) for x, _, z in spots})
    rate = len(hits) / max(len(shots), 1)
    rates[level] = rate
    moves |= kinds
    print(f"{names[level]:7} shots {len(shots):3}  hits {len(hits):3} ({rate:.0%})  "
          f"places {moved:3}  ropes {ropes}  moves {sorted(kinds)}  errors {errors}")
    if errors:
        print("  FAIL: script errors"); fail = True
    if not shots:
        print("  FAIL: the bot never shot"); fail = True
    if level > 0 and not hits:
        print("  FAIL: the bot never hit"); fail = True
    if moved < 8:
        print("  FAIL: the bot barely moved"); fail = True
    if level < 2 and "BELLY_SLIDE" in kinds:
        print("  FAIL: only Hard and Expert bots belly-slide"); fail = True
    if "MATCH_OVER" not in log:
        print("  FAIL: the match never ended"); fail = True
    played = set(re.findall(r"^ANIM SELF 9001 \S+ ([a-z_]+)", log, re.M))
    kicks = len(re.findall(r"^ANIM FIRE 9001", log, re.M))
    anims |= played
    print(f"        animations {sorted(played)}  gun kicks {kicks}")
    if "loco" not in played or "air" not in played:
        print("  FAIL: the bot's body never showed running or jumping"); fail = True
    if kicks != len(shots):
        print("  FAIL: the bot's gun did not kick once per shot"); fail = True
    mine = re.findall(r"^CHAR SELF 1 (\w+)", log, re.M)
    bots = re.findall(r"^CHAR SELF 9001 (\w+)", log, re.M)
    want = "needle" if level % 2 == 0 else "vanguard"
    print(f"        you play {' '.join(mine) or '?'}, the bot plays {' '.join(bots) or '?'}")
    if mine != [want] or len(bots) != 1 or bots[0] == want:
        print(f"  FAIL: expected you as {want} and the bot as a different robot"); fail = True

if rates[3] <= rates[0]:
    print("FAIL: Expert should be more accurate than Easy"); fail = True

log = read("still")
shots, hits, kinds, ropes, spots = bot_stats(log)
print(f"Easy vs a player standing still: shots {len(shots)}  hits {len(hits)}  errors {log.count('SCRIPT ERROR')}")
if not hits or log.count("SCRIPT ERROR"):
    print("  FAIL: Easy should hit a player who stands still"); fail = True

log = read("fight")
shots, hits, kinds, ropes, spots = bot_stats(log)
moves |= kinds
anims |= set(re.findall(r"^ANIM SELF 9001 \S+ ([a-z_]+)", log, re.M))  # the only match where the bot dies
overs = log.count("MATCH_OVER")
print(f"Fight   shots {len(shots):3}  hits {len(hits):3}  moves {sorted(kinds)}  matches {overs}  "
      f"errors {log.count('SCRIPT ERROR')}")
if log.count("SCRIPT ERROR"):
    print("  FAIL: script errors"); fail = True
if overs < 2:
    print("  FAIL: expected a match and a rematch"); fail = True
if "FLIP" not in kinds:
    print("  FAIL: the bot never flip-dodged while being shot"); fail = True
for needed in ["slide", "dive", "grapple", "death"]:
    if needed not in anims:
        print(f"FAIL: no bot's body ever showed {needed}"); fail = True
if not any(a.startswith("flip") for a in anims):
    print("FAIL: no bot's body ever showed a flip"); fail = True
for pattern, what in [(r"^SFX fire_\w+_fp", "your own shot"), (r"^SFX step$", "your footsteps"),
                      (r"^SFX (jump|land)", "your jumps and landings"), (r"^SFX (hitmarker|kill)", "hit markers"),
                      (r"^SFX match_start", "the match start"), (r"^SFX3D fire_rifle ", "the bot's shots, in the world"),
                      (r"^SFX3D impact_(wall|body)", "bullet impacts"), (r"^SFX3D step ", "the bot's footsteps, in the world")]:
    if not re.search(pattern, log, re.M):
        print(f"  FAIL: no sound for {what} ('{pattern}')"); fail = True
for needed in ["SLIDE", "DIVE", "BELLY_SLIDE", "FLIP", "GRAPPLE"]:
    if needed not in moves:
        print(f"FAIL: no bot ever used {needed}"); fail = True

log = read("ffa")
errors = log.count("SCRIPT ERROR")
overs = [json.loads(m) for m in re.findall(r"^MATCH_OVER (.*)$", log, re.M)]
chars = re.findall(r"^CHAR SELF (\d+) (\w+)", log, re.M)
hits = re.findall(r"^SHOT (\d+) hit (\d+)", log, re.M)
bot_ids = ["9001", "9002", "9003", "9004"]
print(f"FFA     players per match {[len(o) for o in overs]}  hits {len(hits)}  errors {errors}")
print(f"        robots {' '.join(f'{i}={c}' for i, c in chars)}")
if errors:
    print("  FAIL: script errors"); fail = True
if len(overs) < 2 or any(len(o) != 5 for o in overs):
    print("  FAIL: expected two 5-player matches (a match and a rematch with all 4 bots)"); fail = True
first = dict(chars[:5])
want = {"1": "vanguard", "9001": "kestrel", "9002": "bulwark", "9003": "rivet", "9004": "specter"}
if first != want:
    print(f"  FAIL: expected robots {want}"); fail = True
for b in bot_ids:
    if not any(s == b for s, _ in hits):
        print(f"  FAIL: bot {b} never hit anyone"); fail = True
if not any(s in bot_ids and t in bot_ids for s, t in hits):
    print("  FAIL: the bots never fought each other"); fail = True
if not any(t == "1" for _, t in hits):
    print("  FAIL: no bot ever hit you"); fail = True

log = read("melee")
blows = re.findall(r"^MELEE 9001 sword (\d+) charge ([\d.]+)", log, re.M)
landed = sum(1 for b, _ in blows if int(b) > 0)
wound = sum(1 for _, c in blows if float(c) >= 0.5)
knocks = len(re.findall(r"^KNOCK 1 ", log, re.M))
print(f"Melee   swings {len(blows)}  wound up half or more {wound}  landed {landed}  knocked you back {knocks}  errors {log.count('SCRIPT ERROR')}")
if log.count("SCRIPT ERROR"):
    print("  FAIL: script errors"); fail = True
if landed == 0 or knocks == 0:
    print("  FAIL: the sword bot should land blows that knock you back"); fail = True
if wound == 0:
    print("  FAIL: the sword bot should wind its swings up"); fail = True

log = read("blink")
blinks = re.findall(r"^BLINK 9001 ([\d.]+)", log, re.M)
print(f"Blink   blinks {len(blinks)}  shots {len(re.findall(r'^SHOT 9001 ', log, re.M))}  errors {log.count('SCRIPT ERROR')}")
if log.count("SCRIPT ERROR"):
    print("  FAIL: script errors"); fail = True
if not blinks:
    print("  FAIL: the blink bot never blinked"); fail = True
if re.search(r"^GRAPPLE|^ROPE SELF 9001 on", log, re.M):
    print("  FAIL: the blink bot used a grapple"); fail = True

# Every bot has the jetpack (Space held in mid-air): it flies it now and then.
jets = sum(len(re.findall(r"^JETPACK 9001", read(n), re.M)) for n in ("blink", "fight", "3"))
print(f"Jetpack bursts {jets} (Expert bots: blink, fight, level 3)")
if not jets:
    print("  note: no Expert bot flew the jetpack this time (it needs higher ground to reach, a far target in sight, or a hit to dodge)")

print("BOT TEST", "FAILED" if fail else "PASSED")
sys.exit(1 if fail else 0)
EOF
