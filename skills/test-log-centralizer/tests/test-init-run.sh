#!/usr/bin/env bash
# test-init-run.sh — T-1.1 acceptance tests for scripts/init-run.sh.
#
# Plain bash TAP-style harness (bats-core not installed on dev box; spike
# established this pattern in spike/code/log-centralizer/tests/test-structure.sh).
# When/if bats is added, port assertions to *.bats; same expectations apply.
#
# Run:    bash skills/test-log-centralizer/tests/test-init-run.sh
# Exit:   0 when all assertions pass, 1 otherwise.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
INIT="$SCRIPTS/init-run.sh"

PASS=0
FAIL=0
ASSERTIONS=()

ok()   { ASSERTIONS+=("ok   $1");   PASS=$((PASS + 1)); }
fail() { ASSERTIONS+=("FAIL $1: $2"); FAIL=$((FAIL + 1)); }

assert_file()    { [[ -f "$1" ]] && ok "file exists: ${2:-$(basename "$1")}" || fail "file missing" "$1"; }
assert_dir()     { [[ -d "$1" ]] && ok "dir exists: ${2:-$(basename "$1")}"  || fail "dir missing"  "$1"; }
assert_empty()   { [[ ! -s "$1" ]] && ok "file empty: ${2:-$(basename "$1")}" || fail "file not empty" "$1"; }
assert_eq()      {
  if [[ "$2" == "$3" ]]; then ok "$1 == $3"; else fail "$1" "expected '$3', got '$2'"; fi
}
assert_match() {
  if [[ "$2" =~ $3 ]]; then ok "$1 matches /$3/"; else fail "$1" "value '$2' does not match /$3/"; fi
}
assert_json_field() {
  # Args: desc, file, python-expr-printing-value, expected
  local desc="$1" file="$2" expr="$3" want="$4" got
  got="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); $expr" "$file" 2>&1)" \
    || { fail "$desc" "$got"; return; }
  [[ "$got" == "$want" ]] && ok "$desc == $want" || fail "$desc" "expected '$want', got '$got'"
}
assert_json_valid() {
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$1" >/dev/null 2>&1; then
    ok "valid JSON: ${2:-$(basename "$1")}"
  else
    fail "invalid JSON" "$1"
  fi
}
assert_json_has_keys() {
  # Args: desc, file, comma-separated key list
  local desc="$1" file="$2" keys="$3" missing
  missing="$(python3 -c '
import json,sys
d = json.load(open(sys.argv[1]))
need = sys.argv[2].split(",")
miss = [k for k in need if k not in d]
print(",".join(miss))
' "$file" "$keys" 2>&1)"
  if [[ -z "$missing" ]]; then ok "$desc has keys [$keys]"; else fail "$desc" "missing keys: $missing"; fi
}

# --- pre-check: init-run.sh must exist + be executable -----------------------
if [[ ! -x "$INIT" ]]; then
  fail "init-run.sh executable" "$INIT not present or not +x"
  echo "# T-1.1 init-run.sh tests"
  for line in "${ASSERTIONS[@]}"; do echo "  $line"; done
  echo "# summary: $PASS passed, $FAIL failed"
  exit 1
fi
ok "init-run.sh present + executable"

# --- setup: throwaway project root -------------------------------------------
# init-run.sh uses `pwd -P` to resolve symlinks (so meta.project_dir is canonical).
# On macOS `mktemp -d` returns /var/... which is a symlink to /private/var/...;
# resolve here so equality checks against meta.project_dir match.
TMP_RAW="$(mktemp -d)"
TMP="$(cd "$TMP_RAW" && pwd -P)"
trap 'rm -rf "$TMP_RAW"' EXIT

# ===========================================================================
# T1.1-1: empty project root → folder skeleton
# ===========================================================================
RUN="$("$INIT" "$TMP" "bun:test" "bun test")"
assert_dir  "$RUN"           "run dir"
assert_dir  "$RUN/streams"   "streams/"
assert_dir  "$RUN/screenshots" "screenshots/"
assert_file "$RUN/run.log"   "run.log"
assert_file "$RUN/meta.json" "meta.json"
assert_file "$RUN/summary.json" "summary.json"

# ===========================================================================
# T1.1-2: run-id format YYYYMMDDTHHMMSSZ (with optional -N collision suffix)
# ===========================================================================
RUN_ID="$(basename "$RUN")"
assert_match "run_id format" "$RUN_ID" '^[0-9]{8}T[0-9]{6}Z(-[0-9]+)?$'

# ===========================================================================
# T1.1-3: meta.json valid + has required keys
# ===========================================================================
assert_json_valid "$RUN/meta.json" "meta.json"
assert_json_has_keys "meta.json" "$RUN/meta.json" \
  "schema_version,run_id,start_ts,started_epoch_ms,project_dir,runner,command"

# ===========================================================================
# T1.1-4: meta.json values reflect inputs
# ===========================================================================
assert_json_field "meta.run_id"      "$RUN/meta.json" "print(d['run_id'])"      "$RUN_ID"
assert_json_field "meta.project_dir" "$RUN/meta.json" "print(d['project_dir'])" "$TMP"
assert_json_field "meta.runner"      "$RUN/meta.json" "print(d['runner'])"      "bun:test"
assert_json_field "meta.command"     "$RUN/meta.json" "print(d['command'])"     "bun test"
assert_json_field "meta.schema_version" "$RUN/meta.json" "print(d['schema_version'])" "1"

# start_ts must be RFC3339-ish UTC.
assert_json_field "meta.start_ts shape" "$RUN/meta.json" \
  "import re; print(bool(re.match(r'^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z\$', d['start_ts'])))" \
  "True"

# started_epoch_ms must be a positive int.
assert_json_field "meta.started_epoch_ms positive int" "$RUN/meta.json" \
  "v=d['started_epoch_ms']; print(isinstance(v,int) and v>0)" \
  "True"

# ===========================================================================
# T1.1-5: summary.json placeholder shape
# ===========================================================================
assert_json_valid "$RUN/summary.json" "summary.json"
assert_json_field "summary.schema_version" "$RUN/summary.json" "print(d['schema_version'])" "1"
assert_json_field "summary.status"         "$RUN/summary.json" "print(d['status'])" "in_progress"
assert_json_field "summary.total"          "$RUN/summary.json" "print(d['total'])" "0"
assert_json_field "summary.passed"         "$RUN/summary.json" "print(d['passed'])" "0"
assert_json_field "summary.failed"         "$RUN/summary.json" "print(d['failed'])" "0"
assert_json_field "summary.skipped"        "$RUN/summary.json" "print(d['skipped'])" "0"
assert_json_field "summary.exit_code"      "$RUN/summary.json" "print(d['exit_code'])" "None"

# ===========================================================================
# T1.1-6: run.log is empty
# ===========================================================================
assert_empty "$RUN/run.log" "run.log"

# ===========================================================================
# T1.1-7: pre-existing .test-runs folder is honored, not clobbered
# ===========================================================================
PREEXIST_MARKER="$TMP/.test-runs/marker.txt"
echo "preexisting" > "$PREEXIST_MARKER"
RUN2="$("$INIT" "$TMP")"
[[ -f "$PREEXIST_MARKER" ]] && ok "pre-existing marker preserved" \
  || fail "pre-existing .test-runs/" "marker.txt was deleted"
assert_dir "$RUN2" "second run dir"

# ===========================================================================
# T1.1-8: collision counter — manually pre-create the would-be run dir
# ===========================================================================
SAMERUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$TMP/.test-runs/$SAMERUN_ID"
RUN3="$("$INIT" "$TMP")"
RUN3_ID="$(basename "$RUN3")"
if [[ "$RUN3_ID" != "$SAMERUN_ID" ]]; then
  ok "collision counter avoided clobber: $RUN3_ID"
else
  fail "collision guard" "init-run.sh reused existing $SAMERUN_ID"
fi
assert_match "collision suffix shape" "$RUN3_ID" '^[0-9]{8}T[0-9]{6}Z-[0-9]+$'

# ===========================================================================
# T1.1-9: bad project root → non-zero exit + diagnostic
# ===========================================================================
BOGUS="$TMP/does-not-exist-$$"
if "$INIT" "$BOGUS" 2>/dev/null; then
  fail "bad project root rejected" "init-run.sh returned 0 for $BOGUS"
else
  ok "bad project root rejected"
fi

# Empty arg list → usage on stderr, non-zero exit.
if "$INIT" 2>/dev/null; then
  fail "missing args rejected" "init-run.sh returned 0 with no args"
else
  ok "missing args rejected"
fi

# ===========================================================================
# T1.1-10: optional runner+command — default 'tbd' / '' when omitted
# ===========================================================================
RUN4="$("$INIT" "$TMP")"
assert_json_field "meta.runner default"  "$RUN4/meta.json" "print(d['runner'])"  "tbd"
assert_json_field "meta.command default" "$RUN4/meta.json" "print(d['command'])" ""

# ===========================================================================
# Bonus: run dirs are pairwise distinct (no two invocations clobber)
# ===========================================================================
ALL_DIRS=("$RUN" "$RUN2" "$RUN3" "$RUN4")
UNIQ=$(printf '%s\n' "${ALL_DIRS[@]}" | sort -u | wc -l | tr -d ' ')
assert_eq "4 invocations → 4 distinct run dirs" "$UNIQ" "4"

# --- report ---------------------------------------------------------------
echo "# T-1.1 init-run.sh tests"
for line in "${ASSERTIONS[@]}"; do echo "  $line"; done
echo
echo "# summary: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
