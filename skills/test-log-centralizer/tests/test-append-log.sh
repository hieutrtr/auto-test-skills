#!/usr/bin/env bash
# test-append-log.sh — T-1.2 acceptance tests for scripts/append-log.sh.
#
# Plain bash TAP-style harness (matches tests/test-init-run.sh; bats-core not on dev box).
# Run:    bash skills/test-log-centralizer/tests/test-append-log.sh
# Exit:   0 when all assertions pass, 1 otherwise.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
INIT="$SCRIPTS/init-run.sh"
APPEND="$SCRIPTS/append-log.sh"

PASS=0
FAIL=0
ASSERTIONS=()

ok()   { ASSERTIONS+=("ok   $1");        PASS=$((PASS + 1)); }
fail() { ASSERTIONS+=("FAIL $1: $2");    FAIL=$((FAIL + 1)); }

assert_file()    { [[ -f "$1" ]] && ok "file exists: ${2:-$(basename "$1")}"  || fail "file missing"  "$1"; }
assert_no_file() { [[ ! -e "$1" ]] && ok "no file: ${2:-$(basename "$1")}"     || fail "unexpected file" "$1"; }
assert_eq()      { [[ "$2" == "$3" ]] && ok "$1 == $3"                          || fail "$1" "expected '$3', got '$2'"; }
assert_match()   { [[ "$2" =~ $3 ]] && ok "$1 matches /$3/"                     || fail "$1" "value '$2' does not match /$3/"; }

# Pre-check: scripts present + executable.
if [[ ! -x "$INIT" ]];   then fail "init-run.sh executable" "$INIT not present or not +x"; fi
if [[ ! -x "$APPEND" ]]; then fail "append-log.sh executable" "$APPEND not present or not +x"; fi
if [[ -x "$INIT" && -x "$APPEND" ]]; then ok "init-run.sh + append-log.sh present + executable"; fi

# Setup: throwaway project root (resolve symlinks per init-run pwd -P contract).
TMP_RAW="$(mktemp -d)"
TMP="$(cd "$TMP_RAW" && pwd -P)"
trap 'rm -rf "$TMP_RAW"' EXIT

# ts-prefix regex: RFC3339 UTC; fractional seconds optional (python3 path produces ms).
TS_PREFIX_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z'

# ===========================================================================
# T1.2-A1: inline form, single line — file gets exactly one prefixed line.
# ===========================================================================
RUN="$("$INIT" "$TMP" "bun:test" "bun test")"
"$APPEND" "$RUN" unit "hello"
UNIT_LOG="$RUN/streams/unit.log"
assert_file "$UNIT_LOG" "streams/unit.log"
GOT_LINES=$(wc -l <"$UNIT_LOG" | tr -d ' ')
assert_eq "inline append → 1 line" "$GOT_LINES" "1"
LINE1="$(head -n 1 "$UNIT_LOG")"
assert_match "line 1 has ts prefix"  "$LINE1" "$TS_PREFIX_RE"
assert_match "line 1 ends in 'hello'" "$LINE1" '[[:space:]]hello$'

# ===========================================================================
# T1.2-A2: stdin form preserves order across multiple lines.
# ===========================================================================
RUN_A2="$("$INIT" "$TMP")"
printf 'a\nb\nc\n' | "$APPEND" "$RUN_A2" unit
A2_LINES=$(wc -l <"$RUN_A2/streams/unit.log" | tr -d ' ')
assert_eq "stdin form → 3 lines" "$A2_LINES" "3"
# Suffix-after-prefix must be a, b, c in order.
A2_TAILS=()
while IFS= read -r _l; do A2_TAILS+=("$_l"); done < <(awk '{print $NF}' "$RUN_A2/streams/unit.log")
assert_eq "stdin order line 1" "${A2_TAILS[0]:-}" "a"
assert_eq "stdin order line 2" "${A2_TAILS[1]:-}" "b"
assert_eq "stdin order line 3" "${A2_TAILS[2]:-}" "c"

# Each line has ts prefix.
PREFIXED_OK=$(awk -v re="$TS_PREFIX_RE" '$0 !~ re { bad++ } END { print (bad+0) }' "$RUN_A2/streams/unit.log")
assert_eq "stdin: every line has ts prefix" "$PREFIXED_OK" "0"

# ===========================================================================
# T1.2-A3: tee to streams/all.log (live-tail convenience).
# ===========================================================================
ALL_LOG="$RUN_A2/streams/all.log"
assert_file "$ALL_LOG" "streams/all.log"
ALL_COUNT=$(wc -l <"$ALL_LOG" | tr -d ' ')
assert_eq "all.log mirrors prior 3 stdin lines" "$ALL_COUNT" "3"

# After one more inline append, all.log should grow by exactly 1.
"$APPEND" "$RUN_A2" browser "B-1"
ALL_AFTER=$(wc -l <"$ALL_LOG" | tr -d ' ')
assert_eq "all.log grows by 1 after a browser append" "$ALL_AFTER" "4"

# ===========================================================================
# T1.2-A4: layer whitelist — all 7 layers accepted; per-layer file emerges.
# ===========================================================================
RUN_A4="$("$INIT" "$TMP")"
for L in unit integration browser orchestrator skill setup teardown; do
  "$APPEND" "$RUN_A4" "$L" "ping-$L"
done
for L in unit integration browser orchestrator skill setup teardown; do
  assert_file "$RUN_A4/streams/$L.log" "streams/$L.log"
done

# ===========================================================================
# T1.2-A5: layer whitelist (negative) — bogus layer rejected, no file written.
# ===========================================================================
RUN_A5="$("$INIT" "$TMP")"
if "$APPEND" "$RUN_A5" bogus "x" 2>/dev/null; then
  fail "bogus layer rejected" "append-log.sh returned 0 for layer 'bogus'"
else
  ok "bogus layer rejected"
fi
assert_no_file "$RUN_A5/streams/bogus.log" "streams/bogus.log not created"

# ===========================================================================
# T1.2-A6: usage / missing args → exit 2 with 'usage:' on stderr.
# ===========================================================================
SET_E_CODE=0
ERR="$("$APPEND" "$RUN_A5" 2>&1 >/dev/null)" || SET_E_CODE=$?
assert_eq "missing-arg exit code == 2" "$SET_E_CODE" "2"
assert_match "usage diagnostic on stderr" "$ERR" "usage:"

# ===========================================================================
# T1.2-A7: bad run-dir → exit 1 with diagnostic.
# ===========================================================================
BAD_E_CODE=0
BAD_ERR="$("$APPEND" "$TMP/no-such-run" unit "x" 2>&1 >/dev/null)" || BAD_E_CODE=$?
[[ "$BAD_E_CODE" -ne 0 ]] && ok "bad run-dir exit ≠ 0 (got $BAD_E_CODE)" \
  || fail "bad run-dir exit" "expected non-zero, got 0"
assert_match "bad run-dir diagnostic" "$BAD_ERR" "append-log"

# ===========================================================================
# T1.2-A8: cross-layer isolation — sequential interleave, per-layer streams stay clean.
# ===========================================================================
RUN_A8="$("$INIT" "$TMP")"
"$APPEND" "$RUN_A8" unit "U-1"
"$APPEND" "$RUN_A8" browser "B-1"
"$APPEND" "$RUN_A8" unit "U-2"
"$APPEND" "$RUN_A8" browser "B-2"
"$APPEND" "$RUN_A8" integration "I-1"

UC=$(wc -l <"$RUN_A8/streams/unit.log" | tr -d ' ')
BC=$(wc -l <"$RUN_A8/streams/browser.log" | tr -d ' ')
IC=$(wc -l <"$RUN_A8/streams/integration.log" | tr -d ' ')
assert_eq "unit.log line count" "$UC" "2"
assert_eq "browser.log line count" "$BC" "2"
assert_eq "integration.log line count" "$IC" "1"

# Foreign tag check: unit.log only `U-`; browser.log only `B-`; integration.log only `I-`.
U_FOREIGN=$(awk '{ if ($NF !~ /^U-/) bad++ } END { print (bad+0) }' "$RUN_A8/streams/unit.log")
B_FOREIGN=$(awk '{ if ($NF !~ /^B-/) bad++ } END { print (bad+0) }' "$RUN_A8/streams/browser.log")
I_FOREIGN=$(awk '{ if ($NF !~ /^I-/) bad++ } END { print (bad+0) }' "$RUN_A8/streams/integration.log")
assert_eq "unit.log: zero foreign tags"        "$U_FOREIGN" "0"
assert_eq "browser.log: zero foreign tags"     "$B_FOREIGN" "0"
assert_eq "integration.log: zero foreign tags" "$I_FOREIGN" "0"

# all.log captures all 5 lines (tee).
ALL8=$(wc -l <"$RUN_A8/streams/all.log" | tr -d ' ')
assert_eq "all.log: 5 tee'd lines" "$ALL8" "5"

# ===========================================================================
# T1.2-A9: timestamp UTC + non-decreasing across two appends within a run.
# ===========================================================================
RUN_A9="$("$INIT" "$TMP")"
"$APPEND" "$RUN_A9" unit "first"
# Tiny pause so monotonic-non-decreasing is unambiguous even at second precision.
sleep 1
"$APPEND" "$RUN_A9" unit "second"
A9_LINES=()
while IFS= read -r _l; do A9_LINES+=("$_l"); done < "$RUN_A9/streams/unit.log"
TS1="$(printf '%s' "${A9_LINES[0]:-}" | awk '{print $1}')"
TS2="$(printf '%s' "${A9_LINES[1]:-}" | awk '{print $1}')"
# String compare works because RFC3339 is lex-sortable.
if [[ "$TS2" > "$TS1" || "$TS2" == "$TS1" ]]; then
  ok "TS non-decreasing across 1s gap (TS1=$TS1, TS2=$TS2)"
else
  fail "TS monotonic" "TS2='$TS2' < TS1='$TS1'"
fi
assert_match "TS1 is RFC3339-UTC" "$TS1" "$TS_PREFIX_RE"
assert_match "TS2 is RFC3339-UTC" "$TS2" "$TS_PREFIX_RE"

# --- report ---------------------------------------------------------------
echo "# T-1.2 append-log.sh tests"
for line in "${ASSERTIONS[@]}"; do echo "  $line"; done
echo
echo "# summary: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
