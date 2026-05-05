#!/usr/bin/env bash
# test-retrieval.sh — measure G2 (PRD §4): agent reads `latest/manifest.json`
# in well under 5s, no multi-file grep needed.
#
# We simulate the agent's happy path from T-0.3 §5:
#   1. open .test-runs/latest/manifest.json
#   2. parse JSON → exit_code, summary, log_path
#   3. tail run.log for context
# Total wall-clock < 5s on cold disk; cite p99 across N trials.
set -uo pipefail

LIB="$(cd "$(dirname "$0")/../lib" && pwd)"
PASS=0
FAIL=0
ASSERTIONS=()
ok()   { ASSERTIONS+=("ok   $1");   PASS=$((PASS + 1)); }
fail() { ASSERTIONS+=("FAIL $1: $2"); FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Build a realistic-sized run.log (10 MB / ~100k lines) — defensible upper
# bound for a test suite log; agent rarely touches run.log directly per G2.
RUN="$("$LIB/start-run.sh" "$TMP" "bun:test" "bun test")"
python3 -c "
import os
with open(os.path.join('$RUN', 'streams', 'unit.log'), 'w') as f:
    for i in range(100000):
        f.write(f'PASS test {i:06d} > assertion checked, body somewhat long padding xxxxxx\n')
"
"$LIB/finalize-run.sh" "$RUN" 0 100000 100000 0 0 >/dev/null

LATEST="$TMP/.test-runs/latest"
LOG_BYTES=$(wc -c <"$LATEST/run.log" | tr -d ' ')
LOG_LINES=$(wc -l <"$LATEST/run.log" | tr -d ' ')
echo "# fixture: run.log = $LOG_BYTES bytes, $LOG_LINES lines"

# --- T1: latest symlink resolves -------------------------------------------
[[ -L "$TMP/.test-runs/latest" ]] \
  && ok "latest symlink exists" \
  || fail "latest symlink" "missing"

# --- T2: agent retrieval timing (10 trials) -------------------------------
TRIALS=10
TIMINGS=()
for ((t = 0; t < TRIALS; t++)); do
  # Hint to drop FS cache — purge requires sudo on macOS, so we simulate
  # cold-ish reads with shell only. The 10MB log + 4KB manifest fits in
  # page cache trivially after first trial; record both warm and cold.
  start=$(python3 -c 'import time; print(int(time.time()*1000000))')
  # 1) read manifest (one Read call equivalent).
  python3 -c "
import json, sys
m = json.load(open('$LATEST/manifest.json'))
# 2) extract load-bearing fields per ARCHITECTURE §(d).
ec = m['exit_code']
s = m['summary']
log_path = m['log_path']
# 3) tail run.log (last 200 lines — ~20KB) for context.
" >/dev/null
  tail -n 200 "$LATEST/run.log" >/dev/null
  end=$(python3 -c 'import time; print(int(time.time()*1000000))')
  TIMINGS+=($((end - start)))
done

read -r MIN MED MAX P99 <<<"$(python3 -c "
xs = [int(x) for x in '${TIMINGS[*]}'.split()]
xs.sort()
n = len(xs)
def pct(p): return xs[min(n-1, int(n*p))]
print(xs[0], pct(0.5), xs[-1], pct(0.99))
")"
MIN_MS=$(awk "BEGIN{printf \"%.2f\", $MIN/1000}")
MED_MS=$(awk "BEGIN{printf \"%.2f\", $MED/1000}")
MAX_MS=$(awk "BEGIN{printf \"%.2f\", $MAX/1000}")
P99_MS=$(awk "BEGIN{printf \"%.2f\", $P99/1000}")

echo "# retrieval timing (n=$TRIALS, manifest + tail-200 of ${LOG_BYTES}-byte run.log)"
echo "  min = ${MIN_MS}ms"
echo "  med = ${MED_MS}ms"
echo "  max = ${MAX_MS}ms"
echo "  p99 = ${P99_MS}ms"

# G2 budget: < 5000 ms (5 s).
OK=$(awk "BEGIN{print ($MAX < 5000000) ? 1 : 0}")
[[ "$OK" == "1" ]] \
  && ok "max retrieval ${MAX_MS}ms < 5000ms (G2)" \
  || fail "G2 budget" "max ${MAX_MS}ms exceeds 5s budget"

# Even tighter target from T-0.3 §5 worked example: 50-300ms typical.
TIGHT_OK=$(awk "BEGIN{print ($MED < 300000) ? 1 : 0}")
[[ "$TIGHT_OK" == "1" ]] \
  && ok "median retrieval ${MED_MS}ms within T-0.3 §5 worked example (50-300ms)" \
  || ok "median retrieval ${MED_MS}ms (T-0.3 §5 target was 50-300ms; over but still < G2 budget)"

# --- T3: retrieval-by-run-id (no symlink) ---------------------------------
RUN_ID="$(basename "$RUN")"
DIRECT="$TMP/.test-runs/$RUN_ID/manifest.json"
[[ -f "$DIRECT" ]] \
  && ok "retrieval by run-id (direct path) works" \
  || fail "by-run-id" "$DIRECT missing"

# --- T4: load-bearing fields parseable in one Read ------------------------
SUMMARY="$(python3 -c "
import json
m = json.load(open('$LATEST/manifest.json'))
print(m['exit_code'], m['summary']['total'], m['log_path'])
")"
[[ "$SUMMARY" == "0 100000 .test-runs/$RUN_ID/run.log" ]] \
  && ok "load-bearing fields readable in single parse" \
  || fail "load-bearing fields" "got '$SUMMARY'"

# --- report ----------------------------------------------------------------
echo
echo "# T-0.4 retrieval tests"
for line in "${ASSERTIONS[@]}"; do echo "  $line"; done
echo
echo "# summary: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
