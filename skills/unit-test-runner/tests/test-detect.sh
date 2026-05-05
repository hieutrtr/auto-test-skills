#!/usr/bin/env bash
# test-detect.sh — T-1.3 acceptance tests for scripts/detect.sh.
#
# Plain bash TAP-style harness (carries the pattern from T-1.1 / T-1.2 in
# this repo and the spike's spike/code/log-centralizer/tests/). When/if
# bats-core is added to the dev box, port assertions to *.bats — same
# expectations apply.
#
# Run:    bash skills/unit-test-runner/tests/test-detect.sh
# Exit:   0 when all assertions pass, 1 otherwise.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
DETECT="$SCRIPTS/detect.sh"
FIXTURES="$HERE/fixtures"

PASS=0
FAIL=0
ASSERTIONS=()

ok()   { ASSERTIONS+=("ok   $1");   PASS=$((PASS + 1)); }
fail() { ASSERTIONS+=("FAIL $1: $2"); FAIL=$((FAIL + 1)); }

assert_eq() {
  if [[ "$2" == "$3" ]]; then ok "$1 == $3"; else fail "$1" "expected '$3', got '$2'"; fi
}

assert_match() {
  if [[ "$2" =~ $3 ]]; then ok "$1 matches /$3/"; else fail "$1" "value '$2' does not match /$3/"; fi
}

assert_json_valid() {
  if printf '%s' "$2" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' >/dev/null 2>&1; then
    ok "valid JSON: $1"
  else
    fail "invalid JSON" "$1: $2"
  fi
}

# Pull a JSON field out of a JSON document supplied via stdin.
# Args: pyexpr  (e.g.  d["framework"]  )
json_get() {
  local doc="$1" expr="$2"
  python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
v = $expr
if isinstance(v, list):
    print(','.join(str(x) for x in v))
else:
    print('' if v is None else v)
" <<<"$doc" 2>/dev/null
}

assert_field_eq() {
  # Args: desc  json_doc  pyexpr  expected
  local desc="$1" doc="$2" expr="$3" want="$4" got
  got="$(json_get "$doc" "$expr")"
  [[ "$got" == "$want" ]] && ok "$desc == $want" || fail "$desc" "expected '$want', got '$got'"
}

assert_field_contains() {
  # Args: desc  json_doc  pyexpr  needle
  local desc="$1" doc="$2" expr="$3" needle="$4" got
  got="$(json_get "$doc" "$expr")"
  if [[ ",$got," == *",$needle,"* ]]; then
    ok "$desc contains '$needle'"
  else
    fail "$desc" "value '$got' does not contain '$needle'"
  fi
}

assert_keys() {
  # Args: desc  json_doc  csv-key-list
  local desc="$1" doc="$2" want="$3" missing
  missing="$(python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
need = sys.argv[1].split(",")
miss = [k for k in need if k not in d]
print(",".join(miss))
' "$want" <<<"$doc" 2>&1)"
  if [[ -z "$missing" ]]; then
    ok "$desc has keys [$want]"
  else
    fail "$desc" "missing keys: $missing"
  fi
}

# --- pre-check: detect.sh must exist + be executable -----------------------
if [[ ! -x "$DETECT" ]]; then
  fail "pre-check" "detect.sh missing or not executable: $DETECT"
else
  ok "detect.sh present + executable"
fi

# --- 6 fixture detection runs ----------------------------------------------
# bash 3.2 (macOS default) has no associative arrays; cache outputs in
# per-fixture vars instead.
FIX_NAMES="jest vitest bun mocha playwright-runner unknown"
J=""; V=""; B=""; M=""; P=""; U=""

run_fixture() {
  local fix="$1"
  "$DETECT" "$FIXTURES/$fix" 2>/dev/null || true
}

J="$(run_fixture jest)"; assert_json_valid "fixture/jest output" "$J"
V="$(run_fixture vitest)"; assert_json_valid "fixture/vitest output" "$V"
B="$(run_fixture bun)"; assert_json_valid "fixture/bun output" "$B"
M="$(run_fixture mocha)"; assert_json_valid "fixture/mocha output" "$M"
P="$(run_fixture playwright-runner)"; assert_json_valid "fixture/playwright-runner output" "$P"
U="$(run_fixture unknown)"; assert_json_valid "fixture/unknown output" "$U"

get_doc() {
  case "$1" in
    jest) printf '%s' "$J" ;;
    vitest) printf '%s' "$V" ;;
    bun) printf '%s' "$B" ;;
    mocha) printf '%s' "$M" ;;
    playwright-runner) printf '%s' "$P" ;;
    unknown) printf '%s' "$U" ;;
  esac
}

# T1.3-1: jest
assert_field_eq "jest.framework"        "$J" 'd["framework"]'        "jest"
assert_field_eq "jest.runtime"          "$J" 'd["runtime"]'          "node"
assert_field_eq "jest.package_manager"  "$J" 'd["package_manager"]'  "npm"
assert_field_eq "jest.command"          "$J" 'd["command"]'          "npm test"
assert_field_eq "jest.test_script"      "$J" 'd["test_script"]'      "jest"
assert_field_contains "jest.markers"    "$J" 'd["markers"]'          "jest.config.js"
assert_field_contains "jest.markers"    "$J" 'd["markers"]'          "devDep:jest"
assert_field_contains "jest.markers"    "$J" 'd["markers"]'          "script:test"

# T1.3-2: vitest
assert_field_eq "vitest.framework"        "$V" 'd["framework"]'       "vitest"
assert_field_eq "vitest.runtime"          "$V" 'd["runtime"]'         "node"
assert_field_eq "vitest.package_manager"  "$V" 'd["package_manager"]' "pnpm"
assert_field_eq "vitest.command"          "$V" 'd["command"]'         "pnpm test"
assert_field_eq "vitest.test_script"      "$V" 'd["test_script"]'     "vitest run"
assert_field_contains "vitest.markers"    "$V" 'd["markers"]'         "vitest.config.ts"
assert_field_contains "vitest.markers"    "$V" 'd["markers"]'         "devDep:vitest"

# T1.3-3: bun
assert_field_eq "bun.framework"        "$B" 'd["framework"]'       "bun"
assert_field_eq "bun.runtime"          "$B" 'd["runtime"]'         "bun"
assert_field_eq "bun.package_manager"  "$B" 'd["package_manager"]' "bun"
assert_field_eq "bun.command"          "$B" 'd["command"]'         "bun test"
assert_field_eq "bun.test_script"      "$B" 'd["test_script"]'     "bun test"
assert_field_contains "bun.markers"    "$B" 'd["markers"]'         "bun.lockb"
assert_field_contains "bun.markers"    "$B" 'd["markers"]'         "script:test:contains:bun test"

# T1.3-4: mocha
assert_field_eq "mocha.framework"        "$M" 'd["framework"]'       "mocha"
assert_field_eq "mocha.runtime"          "$M" 'd["runtime"]'         "node"
assert_field_eq "mocha.package_manager"  "$M" 'd["package_manager"]' "yarn"
assert_field_eq "mocha.command"          "$M" 'd["command"]'         "yarn test"
assert_field_eq "mocha.test_script"      "$M" 'd["test_script"]'     "mocha"
assert_field_contains "mocha.markers"    "$M" 'd["markers"]'         ".mocharc.json"
assert_field_contains "mocha.markers"    "$M" 'd["markers"]'         "devDep:mocha"

# T1.3-5: playwright-runner
assert_field_eq "pw.framework"        "$P" 'd["framework"]'       "playwright-runner"
assert_field_eq "pw.runtime"          "$P" 'd["runtime"]'         "node"
assert_field_eq "pw.package_manager"  "$P" 'd["package_manager"]' "npm"
assert_field_eq "pw.command"          "$P" 'd["command"]'         "npm test"
assert_field_eq "pw.test_script"      "$P" 'd["test_script"]'     "playwright test"
assert_field_contains "pw.markers"    "$P" 'd["markers"]'         "playwright.config.ts"
assert_field_contains "pw.markers"    "$P" 'd["markers"]'         "devDep:@playwright/test"

# T1.3-6: unknown / empty fixture
assert_field_eq "unknown.framework"        "$U" 'd["framework"]'       "unknown"
assert_field_eq "unknown.runtime"          "$U" 'd["runtime"]'         "unknown"
assert_field_eq "unknown.package_manager"  "$U" 'd["package_manager"]' "unknown"
assert_field_eq "unknown.command"          "$U" 'd["command"]'         ""
assert_field_eq "unknown.test_script"      "$U" 'd["test_script"]'     ""

# T1.3-7: JSON shape — all required keys
for fix in $FIX_NAMES; do
  assert_keys "fixture/$fix keys" "$(get_doc "$fix")" \
    "schema_version,framework,runtime,package_manager,command,project_dir,test_script,markers"
done

# T1.3-8: project_dir absolute = canonical fixture path
for fix in $FIX_NAMES; do
  want="$(cd "$FIXTURES/$fix" && pwd -P)"
  assert_field_eq "fixture/$fix project_dir" "$(get_doc "$fix")" 'd["project_dir"]' "$want"
done

# schema_version is "1"
for fix in $FIX_NAMES; do
  assert_field_eq "fixture/$fix schema_version" "$(get_doc "$fix")" 'd["schema_version"]' "1"
done

# T1.3-9: bad arg (missing) → exit 2
set +e
"$DETECT" >/dev/null 2>/tmp/detect-err.$$.txt
rc=$?
set -e
assert_eq "missing arg exit code" "$rc" "2"
err="$(cat /tmp/detect-err.$$.txt 2>/dev/null || true)"
rm -f /tmp/detect-err.$$.txt
assert_match "missing arg stderr" "$err" "usage"

# T1.3-10: bad arg (not a dir) → exit 2
set +e
"$DETECT" "/nonexistent/path/should/not/exist/$$" >/dev/null 2>/tmp/detect-err.$$.txt
rc=$?
set -e
assert_eq "bad-dir arg exit code" "$rc" "2"
rm -f /tmp/detect-err.$$.txt

# T1.3-11: symlink stability — detect via a symlink, expect canonical path
TMPLINK="$(mktemp -d)/fixture-jest-link"
ln -s "$FIXTURES/jest" "$TMPLINK"
out_link="$("$DETECT" "$TMPLINK")"
canon="$(cd "$FIXTURES/jest" && pwd -P)"
assert_field_eq "symlink resolves to canonical" "$out_link" 'd["project_dir"]' "$canon"
rm -rf "$(dirname "$TMPLINK")"

# T1.3-12: priority tie-breaker — synthetic mixed fixture (jest+vitest)
MIX="$(mktemp -d)/mixed"
mkdir -p "$MIX"
cat > "$MIX/package.json" <<'JSON'
{
  "name": "fixture-mixed",
  "version": "0.0.0",
  "scripts": { "test": "vitest run" },
  "devDependencies": { "jest": "^29.0.0", "vitest": "^1.6.0" }
}
JSON
: > "$MIX/jest.config.js"
: > "$MIX/vitest.config.ts"
out_mix="$("$DETECT" "$MIX")"
assert_field_eq "tie-break: vitest beats jest" "$out_mix" 'd["framework"]' "vitest"
rm -rf "$(dirname "$MIX")"

# T1.3-13: frontmatter validate — defer to validate-skill.sh in the runner
VALIDATE="$HERE/../../../spike/code/tests/validate-skill.sh"
SKILL_DIR="$(cd "$HERE/.." && pwd -P)"
if [[ -x "$VALIDATE" ]]; then
  if bash "$VALIDATE" "$SKILL_DIR" >/tmp/detect-fm.$$.txt 2>&1; then
    ok "validate-skill.sh PASS for unit-test-runner"
  else
    fail "validate-skill.sh" "$(cat /tmp/detect-fm.$$.txt)"
  fi
  rm -f /tmp/detect-fm.$$.txt
else
  fail "validate-skill.sh" "not executable at $VALIDATE"
fi

# --- emit TAP-ish output ---------------------------------------------------
echo "# T-1.3 detect.sh tests"
for line in "${ASSERTIONS[@]}"; do
  echo "  $line"
done
echo "# summary: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]
