#!/usr/bin/env bash
# test-orchestrate.sh — E2E test for auto-test/scripts/orchestrate.sh.
# Phase 1 / T-1.5.
#
# Drives orchestrate against unit-test-runner/tests/fixtures/bun/ when bun
# is available. Skips with PASS=0 FAIL=0 (and a banner) if bun is absent
# in the sandbox — manual verification is documented in
# docs/tasks/phase-1/PHASE-MANUAL-VERIFY.md (T-1.10).
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
auto_test_dir="$(cd "$here/.." && pwd -P)"
skills_root="$(cd "$auto_test_dir/.." && pwd -P)"
orchestrate="$auto_test_dir/scripts/orchestrate.sh"
fixture="$skills_root/unit-test-runner/tests/fixtures/bun"

PASS=0
FAIL=0

check() {
  local desc="$1" cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    printf '  ✔ %s\n' "$desc"
    PASS=$((PASS + 1))
  else
    printf '  ✘ %s\n' "$desc"
    FAIL=$((FAIL + 1))
  fi
}

if [[ ! -x "$orchestrate" ]]; then
  echo "FATAL: orchestrate.sh not executable at $orchestrate" >&2
  exit 1
fi
if [[ ! -d "$fixture" ]]; then
  echo "FATAL: bun fixture missing at $fixture" >&2
  exit 1
fi

# --- AC-2: empty-dir → exit 2 (detection failure) -----------------------
empty_proj="$(mktemp -d -t test_orch_empty.XXXXXX)"
trap 'rm -rf "$empty_proj"' EXIT
out_empty="$(mktemp -t test_orch_empty_out.XXXXXX)"
err_empty="$(mktemp -t test_orch_empty_err.XXXXXX)"
"$orchestrate" "$empty_proj" >"$out_empty" 2>"$err_empty"
ec_empty=$?
check "empty-project orchestrate exits 2 (was rc=$ec_empty)"      "[[ '$ec_empty' == '2' ]]"
rm -f "$out_empty" "$err_empty"

# --- AC-2 (cont): missing sibling → exit 2 ------------------------------
fake_skills="$(mktemp -d -t test_orch_fake_skills.XXXXXX)"
out_miss="$(mktemp -t test_orch_miss_out.XXXXXX)"
err_miss="$(mktemp -t test_orch_miss_err.XXXXXX)"
"$orchestrate" "$fixture" --skills-root "$fake_skills" >"$out_miss" 2>"$err_miss"
ec_miss=$?
check "missing sibling skill → exit 2 (was rc=$ec_miss)"           "[[ '$ec_miss' == '2' ]]"
check "missing sibling stderr says 'sibling skill not found'"       "grep -q 'sibling skill not found' '$err_miss'"
rm -f "$out_miss" "$err_miss"
rm -rf "$fake_skills"

# --- AC-1, AC-3, AC-4, AC-5: real bun run -------------------------------
if ! command -v bun >/dev/null 2>&1; then
  echo "[orchestrate] bun not available — skipping E2E happy-path test"
  echo "  (manual verification covered by docs/tasks/phase-1/PHASE-MANUAL-VERIFY.md)"
  echo "[orchestrate] PASS=$PASS  FAIL=$FAIL  SKIPPED=happy-path"
  [[ "$FAIL" -eq 0 ]]
  exit $?
fi

# Clean any prior artifacts on the fixture so test is idempotent.
rm -rf "$fixture/.test-runs"

out_run="$(mktemp -t test_orch_run_out.XXXXXX)"
err_run="$(mktemp -t test_orch_run_err.XXXXXX)"
"$orchestrate" "$fixture" >"$out_run" 2>"$err_run"
ec_run=$?

check "bun fixture orchestrate exits 0 (was rc=$ec_run)"          "[[ '$ec_run' == '0' ]]"
check "stdout has dashboard top corner"                            "grep -q '┌' '$out_run'"
check "stdout has UNIT row"                                        "grep -q 'UNIT' '$out_run'"
check "stdout shows passed=1"                                      "grep -qE '1[[:space:]]+passed' '$out_run'"
check "stdout shows failed=0"                                      "grep -qE '0[[:space:]]+failed' '$out_run'"
check "trailing LATEST= present"                                   "grep -qE '^LATEST=/' '$out_run'"
check "trailing LOG= present"                                      "grep -qE '^LOG=.*run\\.log$' '$out_run'"
check "trailing JSON= present"                                     "grep -qE '^JSON=.*run\\.json$' '$out_run'"
check "trailing EXIT=0 present"                                    "grep -qE '^EXIT=0$' '$out_run'"

# Resolve LATEST from the captured output and verify run dir contents.
latest="$(awk -F= '/^LATEST=/{print $2; exit}' "$out_run")"
check "LATEST path is a directory"                                 "[[ -d '$latest' ]]"
check "summary.json exists in run dir"                             "[[ -f '$latest/summary.json' ]]"
check "manifest.json exists in run dir"                            "[[ -f '$latest/manifest.json' ]]"
check "run.json exists in run dir"                                 "[[ -f '$latest/run.json' ]]"
check "run.log exists in run dir"                                  "[[ -f '$latest/run.log' ]]"

# AC-3: passed + failed + skipped == total invariant.
inv_ok="$(python3 -c '
import json,sys
d = json.load(open(sys.argv[1]))
print("ok" if d["passed"] + d["failed"] + d["skipped"] == d["total"] else "no")
' "$latest/summary.json" 2>/dev/null)"
check "summary invariant passed+failed+skipped == total"           "[[ '$inv_ok' == 'ok' ]]"

# Counts match parser output.
parser_pass="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["summary"]["passed"])' "$latest/run.json" 2>/dev/null || echo X)"
summary_pass="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["passed"])' "$latest/summary.json" 2>/dev/null || echo Y)"
check "summary.json#passed == run.json#summary.passed"             "[[ '$parser_pass' == '$summary_pass' ]]"

# `latest` symlink re-pointed by finalize-run.sh.
check ".test-runs/latest symlink points to run dir basename"       "[[ \"\$(readlink '$fixture/.test-runs/latest')\" == \"\$(basename '$latest')\" ]]"

# Cleanup .test-runs to keep the fixture clean for the next iteration.
rm -rf "$fixture/.test-runs"
rm -f "$out_run" "$err_run"

echo
echo "[orchestrate] PASS=$PASS  FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
