#!/usr/bin/env bash
# The pistols' tilt online (alt fire held: see Player.alt_held, WeaponData.tilt_interval).
# On the Testing Grounds a client with the Pistol holds alt fire and clicks six times,
# 0.11 s apart (quicker than the pistol's 0.17 s between shots, slower than its tilted
# 0.10 s), lets go of alt fire, then clicks six more times at the same pace (twelve
# clicks, so it never runs dry: a reload would hold the gun upright).
# Checks that:
#  - the client's own guns turn over while alt fire is held, and back
#  - the host sees them turn over and back (the hold travels in the snapshots)
#  - tilted, every click fires; held upright the same clicks are too quick for some
#  - the host takes every one of the client's shots, the quicker tilted ones included
#  - there are no script errors
# Usage: tests/run_tilt_test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=tests/out
mkdir -p "$OUT"
rm -f "$OUT"/tilt_*.log
PORT=$((26000 + RANDOM % 200))
COMMON=(--map=testing_grounds --sync-log --kill-target=99 --from-start --weapon=pistol)
fail=0
check() {   # check "what" file pattern
  if grep -q -E "$3" "$2"; then echo "  ok    $1"; else echo "  FAIL  $1"; fail=1; fi
}
clicks() {   # clicks START COUNT: --hold of fire, 0.11 s apart
  for k in $(seq 0 $(($2 - 1))); do
    printf -- "--hold=%s:fire:0.03 " "$(awk -v s="$1" -v k="$k" 'BEGIN { printf "%.2f", s + 0.11 * k }')"
  done
}

timeout 90 "$GODOT" --headless --path . -- --host --name=P1 --autostart=2 --port="$PORT" "${COMMON[@]}" \
  --spawn=13,0.2,31.4,90 --quit-after=10 > "$OUT/tilt_host.log" 2>&1 &
sleep 1
# shellcheck disable=SC2046
timeout 90 "$GODOT" --headless --path . -- --join="127.0.0.1:$PORT" --name=P2 "${COMMON[@]}" \
  --spawn=7,0.2,31.4,-90,-40 --hold=1.0:alt_fire:1.6 $(clicks 1.4 6) $(clicks 3.2 6)\
  --quit-after=12 > "$OUT/tilt_client.log" 2>&1 &
wait || true

H="$OUT/tilt_host.log"
C="$OUT/tilt_client.log"
ME=$(grep -m1 -oE "^TILT SELF [0-9]+ [0-9]+ on" "$C" | awk '{print $4}' || true)
ME=${ME:-0}
echo "Tilt checks (the client is $ME)"
check "the client's own pistol turns over while alt fire is held" "$C" "^TILT SELF $ME $ME on\$"
check "...and back" "$C" "^TILT SELF $ME $ME off\$"
check "the host sees it turn over" "$H" "^TILT SEEN [0-9]+ $ME on\$"
check "...and back" "$H" "^TILT SEEN [0-9]+ $ME off\$"
read -r tilted upright < <(awk -v me="$ME" '
  $0 == "TILT SELF " me " " me " on" { phase = 1; next }
  $0 == "TILT SELF " me " " me " off" { if (phase == 1) phase = 2; next }
  $0 == "ANIM FIRE " me { if (phase == 1) t++; else if (phase == 2) u++ }
  END { print t + 0, u + 0 }' "$C")
if [[ $tilted -eq 6 ]]; then echo "  ok    tilted, all 6 clicks 0.11 s apart fire"
else echo "  FAIL  tilted, all 6 clicks 0.11 s apart fire ($tilted)"; fail=1; fi
if [[ $upright -ge 2 && $upright -lt 6 ]]; then echo "  ok    upright, the same pace is too quick for some of 6 clicks ($upright fired)"
else echo "  FAIL  upright, the same pace is too quick for some of 6 clicks ($upright fired)"; fail=1; fi
sent=$(grep -cE "^ANIM FIRE $ME\$" "$C" || true)
taken=$(grep -cE "^SHOT $ME " "$H" || true)
if [[ $sent -gt 0 && $taken -eq $sent ]]; then echo "  ok    the host takes all $sent of the client's shots"
else echo "  FAIL  the host takes all of the client's shots ($taken of $sent)"; fail=1; fi
if grep -h "SCRIPT ERROR" "$OUT"/tilt_*.log; then
  echo "  FAIL  script errors above"
  fail=1
fi
if [[ $fail -ne 0 ]]; then
  echo "FAIL: tilt checks failed (logs in $OUT/tilt_*.log)"
  exit 1
fi
echo "PASS: the pistols' tilt online"
