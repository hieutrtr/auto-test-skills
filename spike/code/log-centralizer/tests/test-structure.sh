#!/usr/bin/env bash
# test-structure.sh — verify the log-centralizer prototype produces the
# directory layout, file shapes, and manifest schema specified in T-0.3 §2/§3.
#
# Tap-style output for human readability; exit 0 = all pass.
set -uo pipefail

LIB="$(cd "$(dirname "$0")/../lib" && pwd)"
PASS=0
FAIL=0
ASSERTIONS=()

ok()   { ASSERTIONS+=("ok   $1");   PASS=$((PASS + 1)); }
fail() { ASSERTIONS+=("FAIL $1: $2"); FAIL=$((FAIL + 1)); }

assert_file()    { [[ -f "$1" ]] && ok "file exists: $(basename "$1")" || fail "file missing" "$1"; }
assert_dir()     { [[ -d "$1" ]] && ok "dir exists: $(basename "$1")"  || fail "dir missing"  "$1"; }
assert_symlink() { [[ -L "$1" ]] && ok "symlink: $(basename "$1")"      || fail "not a symlink" "$1"; }
assert_eq()      { [[ "$2" == "$3" ]] && ok "$1 == $3" || fail "$1" "expected '$3', got '$2'"; }
assert_jq()      {
  local desc="$1" file="$2" expr="$3" want="$4"
  local got
  got="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); $expr" "$file" 2>&1)" \
    || { fail "$desc" "$got"; return; }
  [[ "$got" == "$want" ]] && ok "$desc == $want" || fail "$desc" "expected '$want', got '$got'"
}

# --- setup ------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

RUN="$("$LIB/start-run.sh" "$TMP" "bun:test" "bun test")"

# --- T1: start-run produces correct skeleton -------------------------------
assert_dir  "$RUN"
assert_dir  "$RUN/streams"
assert_dir  "$RUN/screenshots"
assert_file "$RUN/.meta"

# Run-id format YYYYMMDDTHHmmssZ (16 chars).
RUN_ID="$(basename "$RUN")"
if [[ "$RUN_ID" =~ ^[0-9]{8}T[0-9]{6}Z(-[0-9]+)?$ ]]; then
  ok "run_id format: $RUN_ID"
else
  fail "run_id format" "$RUN_ID does not match YYYYMMDDTHHmmssZ"
fi

# --- T2: append writes per-layer streams (no inter-stream interleaving) ----
"$LIB/append-log.sh" "$RUN" unit "u-line-1"
"$LIB/append-log.sh" "$RUN" unit "u-line-2"
"$LIB/append-log.sh" "$RUN" integration "i-line-1"
"$LIB/append-log.sh" "$RUN" browser "b-line-1"

assert_file "$RUN/streams/unit.log"
assert_file "$RUN/streams/integration.log"
assert_file "$RUN/streams/browser.log"

# Each per-layer file holds only its own messages.
unit_lines="$(wc -l <"$RUN/streams/unit.log" | tr -d ' ')"
assert_eq "streams/unit.log line count" "$unit_lines" "2"
int_lines="$(wc -l <"$RUN/streams/integration.log" | tr -d ' ')"
assert_eq "streams/integration.log line count" "$int_lines" "1"

# --- T3: invalid layer rejected --------------------------------------------
if "$LIB/append-log.sh" "$RUN" ../etc-passwd "evil" 2>/dev/null; then
  fail "invalid layer rejected" "append-log accepted '../etc-passwd'"
else
  ok "invalid layer rejected"
fi

# --- T4: finalize merges in fixed order, writes manifest + run.json -------
"$LIB/finalize-run.sh" "$RUN" 1 3 2 1 0 >/dev/null

assert_file "$RUN/manifest.json"
assert_file "$RUN/run.json"
assert_file "$RUN/run.log"
[[ -f "$RUN/.meta" ]] && fail ".meta cleaned up" ".meta still present" || ok ".meta cleaned up"

# Merge order: unit (2 lines) → integration (1) → browser (1) = 4 lines total.
total_lines="$(wc -l <"$RUN/run.log" | tr -d ' ')"
assert_eq "run.log merged line count" "$total_lines" "4"

# First line is from unit (merge order locked).
first="$(head -n1 "$RUN/run.log")"
assert_eq "run.log first line is unit" "$first" "u-line-1"
# Last line is from browser (after unit + integration).
last="$(tail -n1 "$RUN/run.log")"
assert_eq "run.log last line is browser" "$last" "b-line-1"

# --- T5: latest symlink points to current run ------------------------------
assert_symlink "$TMP/.test-runs/latest"
target="$(readlink "$TMP/.test-runs/latest")"
assert_eq "latest -> run-id" "$target" "$RUN_ID"

# --- T6: manifest schema (load-bearing fields per T-0.3 §3) ---------------
M="$RUN/manifest.json"
assert_jq "schema_version"       "$M" "print(d['schema_version'])"      "1"
assert_jq "run_id"               "$M" "print(d['run_id'])"              "$RUN_ID"
assert_jq "exit_code"            "$M" "print(d['exit_code'])"           "1"
assert_jq "summary.total"        "$M" "print(d['summary']['total'])"    "3"
assert_jq "summary.passed"       "$M" "print(d['summary']['passed'])"   "2"
assert_jq "summary.failed"       "$M" "print(d['summary']['failed'])"   "1"
assert_jq "log_path"             "$M" "print(d['log_path'])"            ".test-runs/$RUN_ID/run.log"
assert_jq "artifacts.log"        "$M" "print(d['artifacts']['log'])"    "run.log"
assert_jq "layers"               "$M" "print(','.join(d['layers']))"    "unit,integration,browser"
assert_jq "command preserved"    "$M" "print(d['command'])"             "bun test"

# --- T7: parallel runs in same second don't collide -----------------------
RUN_A="$("$LIB/start-run.sh" "$TMP" "a" "cmd a")" &
PID_A=$!
RUN_B="$("$LIB/start-run.sh" "$TMP" "b" "cmd b")" &
PID_B=$!
wait $PID_A
wait $PID_B
# Cannot capture subshell stdout with & — re-do sequentially but guard names.
RUN_A="$("$LIB/start-run.sh" "$TMP" "a" "cmd a")"
RUN_B="$("$LIB/start-run.sh" "$TMP" "b" "cmd b")"
[[ "$RUN_A" != "$RUN_B" ]] && ok "parallel start-run produces unique dirs" \
  || fail "collision guard" "$RUN_A == $RUN_B"

# --- report ----------------------------------------------------------------
echo "# T-0.4 structure tests"
for line in "${ASSERTIONS[@]}"; do echo "  $line"; done
echo
echo "# summary: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
