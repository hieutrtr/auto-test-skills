#!/usr/bin/env bash
# test-parsers.sh — T-1.4 acceptance tests for scripts/parse-{jest,vitest,bun}.sh
# and scripts/parse.sh dispatcher.
#
# Plain bash TAP-style harness (matches T-1.1 / T-1.2 / T-1.3 patterns in
# this repo). 22 test cases (T1.4-1 .. T1.4-22) per the task plan.
#
# Run:    bash skills/unit-test-runner/tests/test-parsers.sh
# Exit:   0 when all assertions pass, 1 otherwise.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
PJEST="$SCRIPTS/parse-jest.sh"
PVIT="$SCRIPTS/parse-vitest.sh"
PBUN="$SCRIPTS/parse-bun.sh"
PDISP="$SCRIPTS/parse.sh"
GOLDEN="$HERE/goldens"
REFS="$HERE/../references"

PASS=0
FAIL=0
ASSERTIONS=()

ok()   { ASSERTIONS+=("ok   $1");    PASS=$((PASS + 1)); }
fail() { ASSERTIONS+=("FAIL $1: $2"); FAIL=$((FAIL + 1)); }

assert_eq() {
  if [[ "$2" == "$3" ]]; then ok "$1 == $3"; else fail "$1" "expected '$3', got '$2'"; fi
}
assert_match() {
  if [[ "$2" =~ $3 ]]; then ok "$1 matches /$3/"; else fail "$1" "value does not match /$3/: $2"; fi
}
assert_file() { [[ -f "$1" ]] && ok "file exists: ${2:-$(basename "$1")}" || fail "file missing" "$1"; }
assert_exec() { [[ -x "$1" ]] && ok "executable: ${2:-$(basename "$1")}"   || fail "not executable" "$1"; }
assert_json_valid() {
  if printf '%s' "$2" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' >/dev/null 2>&1; then
    ok "valid JSON: $1"
  else
    fail "invalid JSON" "$1: $2"
  fi
}
assert_byte_equal() {
  # Args: desc actual_file expected_file
  local desc="$1" a="$2" e="$3"
  if diff -q "$a" "$e" >/dev/null 2>&1; then
    ok "$desc byte-equals golden"
  else
    local d
    d="$(diff "$a" "$e" | head -20 || true)"
    fail "$desc byte diff" "$d"
  fi
}

# Inline JSON field reader. Args: desc, json-file, py-expr, expected
assert_json_field() {
  local desc="$1" file="$2" expr="$3" want="$4" got
  got="$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
v = $expr
print(v if not isinstance(v, list) else ','.join(str(x) for x in v))
" "$file" 2>&1)" || { fail "$desc" "py error: $got"; return; }
  if [[ "$got" == "$want" ]]; then ok "$desc == $want"; else fail "$desc" "expected '$want', got '$got'"; fi
}

# Pre-flight: every script + golden file present & executable.
assert_exec "$PJEST"
assert_exec "$PVIT"
assert_exec "$PBUN"
assert_exec "$PDISP"
assert_file "$GOLDEN/jest.input.json"      "jest.input.json"
assert_file "$GOLDEN/vitest.input.json"    "vitest.input.json"
assert_file "$GOLDEN/bun.input.txt"        "bun.input.txt"
assert_file "$GOLDEN/jest.expected.json"   "jest.expected.json"
assert_file "$GOLDEN/vitest.expected.json" "vitest.expected.json"
assert_file "$GOLDEN/bun.expected.json"    "bun.expected.json"
assert_file "$REFS/parser-output-schema.md" "parser-output-schema.md"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ============================================================================
# T1.4-1 — jest happy path: byte-equals golden
# ============================================================================
"$PJEST" "$GOLDEN/jest.input.json" > "$TMP/jest.actual.json"
assert_byte_equal "T1.4-1 jest output" "$TMP/jest.actual.json" "$GOLDEN/jest.expected.json"

# T1.4-2 — vitest happy path
"$PVIT" "$GOLDEN/vitest.input.json" > "$TMP/vitest.actual.json"
assert_byte_equal "T1.4-2 vitest output" "$TMP/vitest.actual.json" "$GOLDEN/vitest.expected.json"

# T1.4-3 — bun happy path
"$PBUN" "$GOLDEN/bun.input.txt" > "$TMP/bun.actual.json"
assert_byte_equal "T1.4-3 bun output" "$TMP/bun.actual.json" "$GOLDEN/bun.expected.json"

# T1.4-4 — dispatcher routing
"$PDISP" jest   "$GOLDEN/jest.input.json"   > "$TMP/disp-jest.json"
"$PDISP" vitest "$GOLDEN/vitest.input.json" > "$TMP/disp-vitest.json"
"$PDISP" bun    "$GOLDEN/bun.input.txt"     > "$TMP/disp-bun.json"
assert_byte_equal "T1.4-4 dispatch jest"   "$TMP/disp-jest.json"   "$GOLDEN/jest.expected.json"
assert_byte_equal "T1.4-4 dispatch vitest" "$TMP/disp-vitest.json" "$GOLDEN/vitest.expected.json"
assert_byte_equal "T1.4-4 dispatch bun"    "$TMP/disp-bun.json"    "$GOLDEN/bun.expected.json"

# T1.4-5 — dispatch unknown framework → exit 2 + stderr message
set +e
out_err="$("$PDISP" foobar /dev/null 2>&1 1>/dev/null)"
ec=$?
set -e
assert_eq "T1.4-5 dispatch unknown exit code" "$ec" "2"
assert_match "T1.4-5 dispatch unknown stderr" "$out_err" "unknown framework"

# T1.4-6 — summary integrity: passed + failed + skipped == total
for fw in jest vitest bun; do
  py="$(python3 -c "
import json
d = json.load(open('$GOLDEN/$fw.expected.json'))
s = d['summary']
print('OK' if s['passed']+s['failed']+s['skipped']==s['total'] else 'BAD')
")"
  assert_eq "T1.4-6 ${fw} summary integrity" "$py" "OK"
done

# T1.4-7 — failures denorm count
for fw in jest vitest bun; do
  py="$(python3 -c "
import json
d = json.load(open('$GOLDEN/$fw.expected.json'))
fail_cases = sum(1 for s in d['suites'] for c in s['cases'] if c['status']=='failed')
print('OK' if len(d['failures'])==fail_cases else f'BAD: {len(d[chr(34)+chr(102)+chr(97)+chr(105)+chr(108)+chr(117)+chr(114)+chr(101)+chr(115)+chr(34)])} != {fail_cases}')
")"
  assert_eq "T1.4-7 ${fw} failures count == suite-level fail count" "$py" "OK"
done

# T1.4-8 — failures denorm has {name, file, message} all non-empty
for fw in jest vitest bun; do
  py="$(python3 -c "
import json
d = json.load(open('$GOLDEN/$fw.expected.json'))
ok = all(f.get('name') and f.get('file') and f.get('message') for f in d['failures']) if d['failures'] else True
print('OK' if ok else 'BAD')
")"
  assert_eq "T1.4-8 ${fw} failures fields populated" "$py" "OK"
done

# T1.4-9..11 — status branch coverage: every framework's golden contains
# at least one passed / failed / skipped case
for fw in jest vitest bun; do
  for st in passed failed skipped; do
    n="$(python3 -c "
import json
d = json.load(open('$GOLDEN/$fw.expected.json'))
print(sum(1 for s in d['suites'] for c in s['cases'] if c['status']=='$st'))
")"
    if [[ "$n" -ge 1 ]]; then
      ok "T1.4-9..11 ${fw} has '$st' case (n=$n)"
    else
      fail "T1.4-9..11 ${fw} missing '$st'" "expected ≥1 case with status=$st"
    fi
  done
done

# T1.4-12 — jest pending/todo → skipped normalization
n="$(python3 -c "
import json
d = json.load(open('$GOLDEN/jest.expected.json'))
print(sum(1 for s in d['suites'] for c in s['cases'] if c['status']=='skipped'))
")"
[[ "$n" -ge 2 ]] && ok "T1.4-12 jest todo+pending mapped to skipped (n=$n)" \
  || fail "T1.4-12 jest skip mapping" "expected ≥2 skipped cases (todo + pending)"

# T1.4-13 — vitest pending → skipped
n="$(python3 -c "
import json
d = json.load(open('$GOLDEN/vitest.expected.json'))
print(sum(1 for s in d['suites'] for c in s['cases'] if c['status']=='skipped'))
")"
[[ "$n" -ge 1 ]] && ok "T1.4-13 vitest pending → skipped (n=$n)" \
  || fail "T1.4-13 vitest skip mapping" "expected ≥1 skipped case"

# T1.4-14 — empty input → exit 2 (every parser)
echo -n "" > "$TMP/empty"
for p in "$PJEST" "$PVIT" "$PBUN"; do
  set +e; out="$("$p" "$TMP/empty" 2>&1)"; ec=$?; set -e
  assert_eq "T1.4-14 $(basename "$p") empty input exit code" "$ec" "2"
  assert_match "T1.4-14 $(basename "$p") empty input stderr" "$out" "empty"
done

# T1.4-15 — missing file → exit 2
for p in "$PJEST" "$PVIT" "$PBUN"; do
  set +e; out="$("$p" "$TMP/does-not-exist" 2>&1)"; ec=$?; set -e
  assert_eq "T1.4-15 $(basename "$p") missing file exit code" "$ec" "2"
  assert_match "T1.4-15 $(basename "$p") missing file stderr" "$out" "not a file"
done

# T1.4-16 — malformed JSON (jest/vitest only)
echo "{ this is not json" > "$TMP/bad.json"
for p in "$PJEST" "$PVIT"; do
  set +e; out="$("$p" "$TMP/bad.json" 2>&1)"; ec=$?; set -e
  assert_eq "T1.4-16 $(basename "$p") malformed JSON exit code" "$ec" "2"
  assert_match "T1.4-16 $(basename "$p") malformed JSON stderr" "$out" "(invalid JSON|JSON)"
done

# bun parser with garbage text (no test markers) → exit 2
echo "this text contains no bun test markers whatsoever" > "$TMP/bad.txt"
set +e; out="$("$PBUN" "$TMP/bad.txt" 2>&1)"; ec=$?; set -e
assert_eq "T1.4-16 parse-bun no markers exit code" "$ec" "2"
assert_match "T1.4-16 parse-bun no markers stderr" "$out" "test markers"

# T1.4-17 — every duration_ms is integer ≥ 0
for fw in jest vitest bun; do
  py="$(python3 -c "
import json
d = json.load(open('$GOLDEN/$fw.expected.json'))
ok = isinstance(d['summary']['duration_ms'], int) and d['summary']['duration_ms']>=0
for s in d['suites']:
    if not (isinstance(s['duration_ms'], int) and s['duration_ms']>=0): ok=False
    for c in s['cases']:
        if not (isinstance(c['duration_ms'], int) and c['duration_ms']>=0): ok=False
print('OK' if ok else 'BAD')
")"
  assert_eq "T1.4-17 ${fw} duration_ms int≥0" "$py" "OK"
done

# T1.4-18 — first suite in output corresponds to first input file
first_jest="$(python3 -c "import json; d=json.load(open('$GOLDEN/jest.expected.json')); print(d['suites'][0]['file'])")"
first_jest_in="$(python3 -c "import json; d=json.load(open('$GOLDEN/jest.input.json')); print(d['testResults'][0]['name'])")"
assert_eq "T1.4-18 jest suite[0] preserves input order" "$first_jest" "$first_jest_in"

first_vit="$(python3 -c "import json; d=json.load(open('$GOLDEN/vitest.expected.json')); print(d['suites'][0]['file'])")"
first_vit_in="$(python3 -c "import json; d=json.load(open('$GOLDEN/vitest.input.json')); print(d['testResults'][0]['name'])")"
assert_eq "T1.4-18 vitest suite[0] preserves input order" "$first_vit" "$first_vit_in"

# bun: first file header in input determines first suite
first_bun="$(python3 -c "import json; d=json.load(open('$GOLDEN/bun.expected.json')); print(d['suites'][0]['file'])")"
assert_eq "T1.4-18 bun suite[0] preserves input order" "$first_bun" "tests/utils.test.ts"

# T1.4-19 — top-level keys exactly equal {schema_version, framework, summary, failures, suites}
for fw in jest vitest bun; do
  py="$(python3 -c "
import json
d = json.load(open('$GOLDEN/$fw.expected.json'))
keys = sorted(d.keys())
expected = sorted(['schema_version','framework','summary','failures','suites'])
print('OK' if keys==expected else f'BAD: {keys}')
")"
  assert_eq "T1.4-19 ${fw} top-level keys exact" "$py" "OK"
done

# T1.4-20 — bun captured error text into error_msg + error_stack
py="$(python3 -c "
import json
d = json.load(open('$GOLDEN/bun.expected.json'))
fc = next(c for s in d['suites'] for c in s['cases'] if c['status']=='failed')
ok = fc['error_msg'].startswith('error:') and 'expect(received).toBe(expected)' in fc['error_stack']
print('OK' if ok else f'BAD: msg={fc[chr(34)+chr(101)+chr(114)+chr(114)+chr(111)+chr(114)+chr(95)+chr(109)+chr(115)+chr(103)+chr(34)]!r}')
")"
assert_eq "T1.4-20 bun fail error captured" "$py" "OK"

# T1.4-21 — frontmatter regression (validate-skill.sh from spike)
VAL_SCRIPT="$HERE/../../../spike/code/tests/validate-skill.sh"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
if [[ -x "$VAL_SCRIPT" ]]; then
  set +e; vout="$("$VAL_SCRIPT" "$SKILL_ROOT" 2>&1)"; vec=$?; set -e
  assert_eq "T1.4-21 validate-skill exit code" "$vec" "0"
  assert_match "T1.4-21 validate-skill 8/8" "$vout" "8 / 8|8/8|PASS"
else
  fail "T1.4-21 validate-skill.sh missing" "$VAL_SCRIPT"
fi

# T1.4-22 — reference doc shape
ref="$REFS/parser-output-schema.md"
lines="$(wc -l < "$ref" | tr -d ' ')"
[[ "$lines" -ge 30 ]] && ok "T1.4-22 parser-output-schema.md ≥ 30 lines (n=$lines)" \
  || fail "T1.4-22 parser-output-schema.md too short" "lines=$lines"
grep -q 'schema_version' "$ref" && ok "T1.4-22 mentions schema_version" \
  || fail "T1.4-22 missing schema_version" "$ref"
grep -q 'TAP' "$ref" && ok "T1.4-22 documents TAP→JSON deviation" \
  || fail "T1.4-22 missing TAP rationale" "$ref"

# T1.4-23 — parsing from stdin works (regression test for "-" arg)
"$PJEST" - < "$GOLDEN/jest.input.json" > "$TMP/stdin-jest.json"
assert_byte_equal "T1.4-23 jest stdin == file" "$TMP/stdin-jest.json" "$GOLDEN/jest.expected.json"
"$PBUN"  - < "$GOLDEN/bun.input.txt"     > "$TMP/stdin-bun.json"
assert_byte_equal "T1.4-23 bun stdin == file"  "$TMP/stdin-bun.json"  "$GOLDEN/bun.expected.json"

# T1.4-24 — unknown source status (e.g. hypothetical "timeout") falls back to
# "skipped" via the else-branch in norm_status. Covers the 4th case-status
# coverage cell for jest/vitest (the plan calls out pass/fail/skip/timeout).
cat > "$TMP/ts.json" <<'EOF'
{
  "numTotalTests": 1, "numPassedTests": 0, "numFailedTests": 0,
  "startTime": 1, "success": true,
  "testResults": [{
    "name": "/p/x.test.js", "startTime": 1, "endTime": 2, "status": "passed",
    "assertionResults": [
      {"ancestorTitles": [], "title": "timeout case",
       "fullName": "timeout case", "status": "timeout",
       "duration": 0, "failureMessages": []}
    ]
  }]
}
EOF
out_j="$("$PJEST" "$TMP/ts.json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["suites"][0]["cases"][0]["status"])')"
assert_eq "T1.4-24 jest timeout-status → skipped"   "$out_j" "skipped"
out_v="$("$PVIT" "$TMP/ts.json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["suites"][0]["cases"][0]["status"])')"
assert_eq "T1.4-24 vitest timeout-status → skipped" "$out_v" "skipped"

# T1.4-25 — all-skipped suite branch coverage: a suite with only skip cases
# resolves to suite.status = "skipped" (third branch of suite-status logic).
cat > "$TMP/all-skip.json" <<'EOF'
{
  "numTotalTests": 1, "startTime": 1, "success": true,
  "testResults": [{
    "name": "/p/all-skip.test.js", "startTime": 1, "endTime": 2, "status": "passed",
    "assertionResults": [
      {"ancestorTitles": [], "title": "stub", "fullName": "stub",
       "status": "pending", "duration": 0, "failureMessages": []}
    ]
  }]
}
EOF
ss_j="$("$PJEST" "$TMP/all-skip.json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["suites"][0]["status"])')"
assert_eq "T1.4-25 jest all-skip suite status"   "$ss_j" "skipped"
ss_v="$("$PVIT" "$TMP/all-skip.json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["suites"][0]["status"])')"
assert_eq "T1.4-25 vitest all-skip suite status" "$ss_v" "skipped"

# Bun all-skip equivalent — verbose output with only skip lines.
cat > "$TMP/bun-allskip.txt" <<'EOF'
bun test v1.3.11 (test)

tests/skip-only.test.ts:
(skip) only > stub a
(skip) only > stub b

 0 pass
 2 skip
 0 fail
Ran 2 tests across 1 file. [1.00ms]
EOF
ss_b="$("$PBUN" "$TMP/bun-allskip.txt" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["suites"][0]["status"])')"
assert_eq "T1.4-25 bun all-skip suite status" "$ss_b" "skipped"

# ============================================================================
# Report
# ============================================================================
printf "\n--- Test Summary ---\n"
for line in "${ASSERTIONS[@]}"; do printf '%s\n' "$line"; done
printf "\n%d passed / %d failed (total %d)\n" "$PASS" "$FAIL" "$((PASS + FAIL))"

if (( FAIL > 0 )); then exit 1; fi
exit 0
