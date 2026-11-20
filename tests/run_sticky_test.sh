#!/usr/bin/env bash
# Sticky grenades online (the grenade launcher's alt fire; see Match._host_stick).
# On the Testing Grounds a client stands 6 m from the host, looking at the floor in
# front of it, and fires four sticky grenades with alt fire; then the host walks
# towards it. Checks that:
#  - the client's alt fire reaches the host as sticky grenades, and each sticks to the
#    floor; the client draws each stuck where the host has it (within 30 cm)
#  - the fourth takes the first away, on the host and on the client, without a blast
#  - they are armed on both copies, and the host walking within reach sets them off:
#    the blasts are the client's, with the grenade launcher, and hurt the host, and
#    the client sees them go off
#  - there are no script errors
# Usage: tests/run_sticky_test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=tests/out
mkdir -p "$OUT"
rm -f "$OUT"/sticky_*.log
PORT=$((25800 + RANDOM % 200))
COMMON=(--map=testing_grounds --sync-log --kill-target=99 --from-start)
fail=0
check() {   # check "what" file pattern
  if grep -q -E "$3" "$2"; then echo "  ok    $1"; else echo "  FAIL  $1"; fail=1; fi
}

timeout 90 "$GODOT" --headless --path . -- --host --name=P1 --autostart=2 --port="$PORT" "${COMMON[@]}" \
  --weapon=pistol --spawn=13,0.2,31.4,90 --hold=5.5:move_forward:1.5 --quit-after=22 \
  > "$OUT/sticky_host.log" 2>&1 &
sleep 1
timeout 90 "$GODOT" --headless --path . -- --join="127.0.0.1:$PORT" --name=P2 "${COMMON[@]}" \
  --weapon=grenade_launcher --spawn=7,0.2,31.4,-90,-40 \
  --hold=1.0:alt_fire:0.1 --hold=1.8:alt_fire:0.1 --hold=2.6:alt_fire:0.1 --hold=3.4:alt_fire:0.1 \
  --quit-after=24 > "$OUT/sticky_client.log" 2>&1 &
wait || true

H="$OUT/sticky_host.log"
C="$OUT/sticky_client.log"
ME=$(grep -m1 -oE "^STICKY_SEEN [0-9]+" "$C" | awk '{print $2}' || true)
ME=${ME:-0}
echo "Sticky grenade checks (the client is $ME)"
fired=$(grep -cE "^PROJECTILE $ME grenade_launcher [0-9]+ sticky" "$H" || true)
if [[ $fired -eq 4 ]]; then echo "  ok    the client's alt fire reaches the host as 4 sticky grenades"
else echo "  FAIL  the client's alt fire reaches the host as 4 sticky grenades ($fired)"; fail=1; fi
stuck=$(grep -cE "^STICKY_STUCK $ME [0-9]+ on 0 " "$H" || true)
if [[ $stuck -eq 4 ]]; then echo "  ok    each sticks to the floor"
else echo "  FAIL  each sticks to the floor ($stuck)"; fail=1; fi
# Where the client draws each one, against where the host has it.
if awk '
  FNR == NR { if (/^STICKY_STUCK /) { split($NF, a, ","); host[$3] = a[1] " " a[2] " " a[3] }; next }
  /^STICKY_SEEN / && $3 == "stuck" { split($NF, b, ","); if (!($4 in host)) next; split(host[$4], a, " ")
    d = sqrt((a[1]-b[1])^2 + (a[2]-b[2])^2 + (a[3]-b[3])^2); n++; if (d > worst) worst = d }
  END { printf "    %d drawn stuck, at most %.2f m from where the host has them\n", n, worst; exit (n == 4 && worst <= 0.3) ? 0 : 1 }
' "$H" "$C"; then echo "  ok    the client draws each stuck where the host has it"
else echo "  FAIL  the client draws each stuck where the host has it"; fail=1; fi
first=$(grep -m1 -oE "^STICKY_STUCK $ME [0-9]+" "$H" | awk '{print $3}' || true)
check "the fourth takes the first away on the host" "$H" "^STICKY_GONE $ME ${first:-x}\$"
check "...and on the client" "$C" "^STICKY_SEEN $ME gone ${first:-x}\$"
check "armed on the host" "$H" "^STICKY_ARMED $ME "
check "...and on the client" "$C" "^STICKY_SEEN $ME armed "
check "the host walking within reach sets one off: the client's, with the grenade launcher, and it hurts the host" "$H" "^BOOM $ME grenade_launcher 0 hit [1-9]"
check "the client sees it go off" "$C" "^STICKY_SEEN $ME boom "
if grep -qE "^BOOM $ME grenade_launcher" "$H" && [[ $(grep -cE "^BOOM $ME grenade_launcher" "$H") -gt 3 ]]; then
  echo "  FAIL  more blasts than stickies"; fail=1
fi
if grep -h "SCRIPT ERROR" "$OUT"/sticky_*.log; then
  echo "  FAIL  script errors above"
  fail=1
fi
if [[ $fail -ne 0 ]]; then
  echo "FAIL: sticky grenade checks failed (logs in $OUT/sticky_*.log)"
  exit 1
fi
echo "PASS: sticky grenades online"
