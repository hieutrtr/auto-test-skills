#!/usr/bin/env bash
# test-finalize-run.sh — T-1.2 acceptance tests for scripts/finalize-run.sh.
#
# Plain bash TAP-style harness (matches tests/test-init-run.sh + test-append-log.sh).
# Exercises end-to-end: init → append (cross-layer) → finalize → assert outputs.
# Run:    bash skills/test-log-centralizer/tests/test-finalize-run.sh
# Exit:   0 when all assertions pass, 1 otherwise.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
GOLDEN_DIR="$HERE/goldens"
INIT="$SCRIPTS/init-run.sh"
APPEND="$SCRIPTS/append-log.sh"
FIN="$SCRIPTS/finalize-run.sh"

PASS=0
FAIL=0
ASSERTIONS=()

ok()   { ASSERTIONS+=("ok   $1");        PASS=$((PASS + 1)); }
fail() { ASSERTIONS+=("FAIL $1: $2");    FAIL=$((FAIL + 1)); }

assert_file()    { [[ -f "$1" ]] && ok "file exists: ${2:-$(basename "$1")}"  || fail "file missing"  "$1"; }
assert_no_file() { [[ ! -e "$1" ]] && ok "no file: ${2:-$(basename "$1")}"     || fail "unexpected file" "$1"; }
assert_eq()      { [[ "$2" == "$3" ]] && ok "$1 == $3"                          || fail "$1" "expected '$3', got '$2'"; }
assert_match()   { [[ "$2" =~ $3 ]] && ok "$1 matches /$3/"                     || fail "$1" "value '$2' does not match /$3/"; }

assert_json_field() {
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

# Pre-check: scripts present + executable.
for s in "$INIT" "$APPEND" "$FIN"; do
  [[ -x "$s" ]] || { fail "$(basename "$s") executable" "$s not present or not +x"; }
done
ok "init-run.sh + append-log.sh + finalize-run.sh present + executable"

# Setup: throwaway project root.
TMP_RAW="$(mktemp -d)"
TMP="$(cd "$TMP_RAW" && pwd -P)"
trap 'rm -rf "$TMP_RAW"' EXIT

TS_PREFIX_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z'

# ===========================================================================
# T1.2-F1: end-to-end no-fail.
# ===========================================================================
RUN1="$("$INIT" "$TMP" "bun:test" "bun test")"
"$APPEND" "$RUN1" unit "U-1"
"$APPEND" "$RUN1" integration "I-1"
"$APPEND" "$RUN1" browser "B-1"
sleep 1   # ensure duration_ms > 0 so we can sanity-check sign + magnitude
"$FIN" "$RUN1" 0 3 3 0 0 >/dev/null

assert_file "$RUN1/run.log" "run.log"
assert_file "$RUN1/summary.json" "summary.json"
assert_file "$RUN1/manifest.json" "manifest.json"
assert_file "$RUN1/run.json" "run.json"

RUN_LOG_LINES=$(wc -l <"$RUN1/run.log" | tr -d ' ')
assert_eq "run.log line count" "$RUN_LOG_LINES" "3"

assert_json_field "summary.status"      "$RUN1/summary.json" "print(d['status'])"      "passed"
assert_json_field "summary.exit_code"   "$RUN1/summary.json" "print(d['exit_code'])"   "0"
assert_json_field "summary.total"       "$RUN1/summary.json" "print(d['total'])"       "3"
assert_json_field "summary.passed"      "$RUN1/summary.json" "print(d['passed'])"      "3"
assert_json_field "summary.failed"      "$RUN1/summary.json" "print(d['failed'])"      "0"
assert_json_field "summary.skipped"     "$RUN1/summary.json" "print(d['skipped'])"     "0"

# duration_ms ≥ 1000 (we slept 1s).
assert_json_field "summary.duration_ms positive" "$RUN1/summary.json" \
  "v=d['duration_ms']; print(isinstance(v,int) and v>=1000)" \
  "True"

# ===========================================================================
# T1.2-F2: merge order (canonical: unit → integration → browser → orchestrator → skill → setup → teardown).
# ===========================================================================
RUN2="$("$INIT" "$TMP")"
# Append in shuffled order to prove finalize merges, not appends in insertion order.
"$APPEND" "$RUN2" browser "BLINE"
"$APPEND" "$RUN2" unit "ULINE"
"$APPEND" "$RUN2" teardown "TLINE"
"$APPEND" "$RUN2" skill "SLINE"
"$APPEND" "$RUN2" integration "ILINE"
"$APPEND" "$RUN2" orchestrator "OLINE"
"$APPEND" "$RUN2" setup "SETLINE"
"$FIN" "$RUN2" 0 7 7 0 0 >/dev/null

# Pull the trailing token from each run.log line; expect the canonical order.
MERGE_ORDER=()
while IFS= read -r _l; do MERGE_ORDER+=("$_l"); done < <(awk '{print $NF}' "$RUN2/run.log")
EXPECTED=(ULINE ILINE BLINE OLINE SLINE SETLINE TLINE)
for i in 0 1 2 3 4 5 6; do
  assert_eq "merge order [$i]" "${MERGE_ORDER[$i]:-MISSING}" "${EXPECTED[$i]}"
done

# ===========================================================================
# T1.2-F3: summary.json has all 10 keys; log_path is absolute and ends in /run.log.
# ===========================================================================
SUMMARY_KEYS="schema_version,status,exit_code,duration_ms,total,passed,failed,skipped,finished_ts,log_path"
assert_json_has_keys "summary.json" "$RUN1/summary.json" "$SUMMARY_KEYS"
assert_json_field "summary.log_path absolute" "$RUN1/summary.json" \
  "p=d['log_path']; print(p.startswith('/') and p.endswith('/run.log'))" \
  "True"
# finished_ts shape RFC3339 UTC.
assert_json_field "summary.finished_ts shape" "$RUN1/summary.json" \
  "import re; print(bool(re.match(r'^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z\$', d['finished_ts'])))" \
  "True"

# ===========================================================================
# T1.2-F4: status == "failed" when exit != 0.
# ===========================================================================
RUN_F4="$("$INIT" "$TMP")"
"$APPEND" "$RUN_F4" unit "boom"
"$FIN" "$RUN_F4" 1 5 4 1 0 >/dev/null
assert_json_field "F4 summary.status"    "$RUN_F4/summary.json" "print(d['status'])"    "failed"
assert_json_field "F4 summary.exit_code" "$RUN_F4/summary.json" "print(d['exit_code'])" "1"
assert_json_field "F4 summary.failed"    "$RUN_F4/summary.json" "print(d['failed'])"    "1"

# ===========================================================================
# T1.2-F5: status == "failed" when failed > 0 even with exit_code 0.
# ===========================================================================
RUN_F5="$("$INIT" "$TMP")"
"$FIN" "$RUN_F5" 0 5 4 1 0 >/dev/null
assert_json_field "F5 summary.status (failed-count override)" "$RUN_F5/summary.json" "print(d['status'])" "failed"

# ===========================================================================
# T1.2-F6: status == "error" when exit_code == 2.
# ===========================================================================
RUN_F6="$("$INIT" "$TMP")"
"$FIN" "$RUN_F6" 2 0 0 0 0 >/dev/null
assert_json_field "F6 summary.status (exit 2 → error)" "$RUN_F6/summary.json" "print(d['status'])" "error"

# ===========================================================================
# T1.2-F7: manifest.json shape — keys + types + framework == meta.runner.
# ===========================================================================
MANIFEST_KEYS="schema_version,run_id,project,started_at,finished_at,duration_ms,framework,command,exit_code,summary,failed_cases,log_path,artifacts,layers"
assert_json_valid     "$RUN1/manifest.json" "manifest.json"
assert_json_has_keys  "manifest.json" "$RUN1/manifest.json" "$MANIFEST_KEYS"
assert_json_field "manifest.failed_cases is []" "$RUN1/manifest.json" \
  "print(d['failed_cases'] == [])" "True"
assert_json_field "manifest.framework == meta.runner" "$RUN1/manifest.json" \
  "print(d['framework'])" "bun:test"
assert_json_field "manifest.command   == meta.command" "$RUN1/manifest.json" \
  "print(d['command'])" "bun test"
assert_json_field "manifest.layers is list" "$RUN1/manifest.json" \
  "print(isinstance(d['layers'], list))" "True"
assert_json_field "manifest.layers contains unit/integration/browser" "$RUN1/manifest.json" \
  "ls=set(d['layers']); print(ls == {'unit','integration','browser'})" "True"
assert_json_field "manifest.summary.total == 3" "$RUN1/manifest.json" \
  "print(d['summary']['total'])" "3"

# ===========================================================================
# T1.2-F8: run.json shape.
# ===========================================================================
assert_json_valid "$RUN1/run.json" "run.json"
RUN_ID_BASENAME="$(basename "$RUN1")"
assert_json_field "run.json.schema_version" "$RUN1/run.json" "print(d['schema_version'])" "1"
assert_json_field "run.json.run_id"          "$RUN1/run.json" "print(d['run_id'])"          "$RUN_ID_BASENAME"
assert_json_field "run.json.suites is []"   "$RUN1/run.json" "print(d['suites'] == [])"    "True"

# ===========================================================================
# T1.2-F9: latest symlink → run_id, resolves to run dir.
# ===========================================================================
RUNS_ROOT="$TMP/.test-runs"
LATEST="$RUNS_ROOT/latest"
[[ -L "$LATEST" ]] && ok "latest is a symlink" || fail "latest symlink" "not a symlink: $LATEST"
LINK_TARGET="$(readlink "$LATEST")"
# ===========================================================================
# T1.2-F10: re-point on second finalize — latest tracks most-recent run.
# (Run F1 came first; F2 came after. F6 was the very last finalize.)
# ===========================================================================
RUN_F6_ID="$(basename "$RUN_F6")"
assert_eq "latest target == most recent run_id" "$LINK_TARGET" "$RUN_F6_ID"

# Resolves to a directory.
[[ -d "$LATEST/" ]] && ok "latest resolves to a dir" || fail "latest deref" "$LATEST does not resolve to dir"

# ===========================================================================
# T1.2-F11: duration_ms math — non-negative, ≤ 60000 ms (we never slept that long).
# ===========================================================================
assert_json_field "F1 duration_ms ≤ 60000" "$RUN1/summary.json" \
  "v=d['duration_ms']; print(0 <= v <= 60000)" \
  "True"

# manifest duration_ms also matches summary.duration_ms.
assert_json_field "manifest.duration_ms == summary.duration_ms" \
  "$RUN1/manifest.json" \
  "import json; s=json.load(open('$RUN1/summary.json')); print(d['duration_ms']==s['duration_ms'])" \
  "True"

# ===========================================================================
# T1.2-F12: run dir self-contained — only `<run_id>/` + `latest` in runs_root.
# ===========================================================================
# At this point we have 6 runs (F1..F6) + latest symlink.
# Count entries: should match count(runs) + 1 for latest. No stray *.tmp / *.log files.
ROOT_ENTRIES=()
while IFS= read -r _l; do ROOT_ENTRIES+=("$_l"); done < <(cd "$RUNS_ROOT" && ls -1)
EXTRA=0
for e in "${ROOT_ENTRIES[@]}"; do
  case "$e" in
    latest) ;;
    [0-9]*T[0-9]*Z|[0-9]*T[0-9]*Z-*) ;;
    *) EXTRA=$((EXTRA+1)) ;;
  esac
done
assert_eq "no stray entries in .test-runs/" "$EXTRA" "0"

# Inside the latest run-dir: no *.tmp leftovers.
TMP_LEFTOVERS=()
while IFS= read -r _l; do TMP_LEFTOVERS+=("$_l"); done < <(find "$RUN_F6/" -name '*.tmp' 2>/dev/null)
TMP_LEFTOVER_COUNT=${#TMP_LEFTOVERS[@]}
# When array is empty, ${#arr[@]} is 0 in bash 3.2 only when no elements were appended;
# our portable read-loop with empty input leaves the array length 0 (via "${arr[@]}" expansion).
assert_eq "no *.tmp leftovers in run dir" "$TMP_LEFTOVER_COUNT" "0"

# ===========================================================================
# T1.2-F13: missing run-dir → exit non-zero.
# ===========================================================================
F13_E=0
F13_ERR="$("$FIN" "$TMP/no-such-run" 0 2>&1 >/dev/null)" || F13_E=$?
[[ "$F13_E" -ne 0 ]] && ok "missing run-dir exit ≠ 0 (got $F13_E)" \
  || fail "missing run-dir exit" "expected non-zero, got 0"
assert_match "missing run-dir diagnostic" "$F13_ERR" "finalize"

# ===========================================================================
# T1.2-F14: missing meta.json → exit non-zero with diagnostic naming meta.json.
# ===========================================================================
RUN_F14="$("$INIT" "$TMP")"
rm -f "$RUN_F14/meta.json"
F14_E=0
F14_ERR="$("$FIN" "$RUN_F14" 0 2>&1 >/dev/null)" || F14_E=$?
[[ "$F14_E" -ne 0 ]] && ok "missing meta.json exit ≠ 0 (got $F14_E)" \
  || fail "missing meta.json exit" "expected non-zero, got 0"
assert_match "missing meta.json diagnostic" "$F14_ERR" "meta.json"

# ===========================================================================
# T1.2-F15: atomic write — no *.tmp leftovers after success.
# ===========================================================================
RUN_F15="$("$INIT" "$TMP")"
"$FIN" "$RUN_F15" 0 0 0 0 0 >/dev/null
F15_TMP=()
while IFS= read -r _l; do F15_TMP+=("$_l"); done < <(find "$RUN_F15/" -maxdepth 2 -name '*.tmp' 2>/dev/null)
F15_TMP_COUNT=${#F15_TMP[@]}
assert_eq "no *.tmp after successful finalize" "$F15_TMP_COUNT" "0"

# ===========================================================================
# T1.2-F16: golden shape match (normalized).
#   Strip variable fields (run_id, project, started_at, finished_at, duration_ms,
#   started_epoch_ms, log_path, command — only the variable parts) and compare
#   to tests/goldens/manifest.golden.json.
# ===========================================================================
GOLDEN_FILE="$GOLDEN_DIR/manifest.golden.json"
if [[ ! -f "$GOLDEN_FILE" ]]; then
  fail "golden file missing" "$GOLDEN_FILE"
else
  ok "golden file present"
  # Build normalized manifest from RUN1.
  NORM_PY=$(python3 - <<'PY' "$RUN1/manifest.json"
import json,sys
d = json.load(open(sys.argv[1]))
# Strip / canonicalize variable fields.
strip = {"run_id","project","started_at","finished_at","duration_ms","log_path","command"}
for k in strip:
  d[k] = "<redacted>"
# Canonicalize layers ordering for stable compare.
d["layers"] = sorted(d.get("layers", []))
# summary keeps its values; this run was 3/3/0/0.
print(json.dumps(d, sort_keys=True, indent=2))
PY
)
  GOLDEN_NORM=$(python3 - <<'PY' "$GOLDEN_FILE"
import json,sys
d = json.load(open(sys.argv[1]))
d["layers"] = sorted(d.get("layers", []))
print(json.dumps(d, sort_keys=True, indent=2))
PY
)
  if [[ "$NORM_PY" == "$GOLDEN_NORM" ]]; then
    ok "manifest matches golden (normalized)"
  else
    fail "golden mismatch" "diff (live ↔ golden) — first divergence below"
    diff <(printf '%s\n' "$NORM_PY") <(printf '%s\n' "$GOLDEN_NORM") | head -40 || true
  fi
fi

# Ensure no test left a tmp file in the test runs root.
ROOT_TMP=()
while IFS= read -r _l; do ROOT_TMP+=("$_l"); done < <(find "$RUNS_ROOT" -name '*.tmp')
ROOT_TMP_COUNT=${#ROOT_TMP[@]}
assert_eq "no *.tmp anywhere under .test-runs/" "$ROOT_TMP_COUNT" "0"

# --- report ---------------------------------------------------------------
echo "# T-1.2 finalize-run.sh tests"
for line in "${ASSERTIONS[@]}"; do echo "  $line"; done
echo
echo "# summary: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
