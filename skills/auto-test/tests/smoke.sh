#!/usr/bin/env bash
# smoke.sh — Phase 1 / T-1.8 end-to-end smoke harness for auto-test.
#
# Purpose:
#   Drive skills/auto-test/scripts/orchestrate.sh against a real test runner
#   (bun / npm-jest / pnpm-vitest) on a copy of one of the unit-test-runner
#   fixtures, then assert the auto-test public contract:
#     1. orchestrate exits with the framework-truth code (0 pass / 1 fail).
#     2. A run dir is created under <project>/.test-runs/<ts>/.
#     3. The trailing KEY=value block (LATEST/LOG/JSON/EXIT) is present and
#        every path resolves to a real file.
#     4. run.json is well-formed and summary counts match the scenario.
#
# Why this is a *smoke* test rather than a unit test:
#   T-1.5 already unit-tests render-dashboard.sh + orchestrate.sh against
#   canned fixtures. This harness exercises the same orchestrate.sh against
#   a *live* framework subprocess (no canned stdin, no mocked parser) so we
#   verify integration paths that unit tests cannot reach: stdout pipeline,
#   PIPESTATUS through `bash -c`, real ANSI stripping in append-log, real
#   parser line-rate on actual framework output, run-dir cleanup ordering.
#
# Sandbox-fallback policy (INDEX §10 R-E):
#   When the runtime for a scenario is missing in the sandbox, the harness
#   prints "[skip:<reason>]" and exits 0. Manual instructions live in
#   docs/tasks/phase-1/T-1.8-smoke.md §6 (and PHASE-MANUAL-VERIFY.md).
#
# Usage:
#   smoke.sh                 # run every scenario, skip what's not runnable
#   smoke.sh <scenario>      # run a single scenario (bun-pass / bun-fail / jest / vitest)
#   smoke.sh regression      # run only the unit-test regression sweep
#
# Exit codes (harness, not orchestrator):
#   0 — every requested scenario was either green or skipped with a reason
#   1 — one or more scenarios FAILED an assertion (real failure, not skip)
#   2 — usage / setup error (e.g. orchestrate.sh missing)
#
# Cross-platform: BSD + GNU. bash 3.2+. python3 for JSON.
set -uo pipefail

# --- locate paths ---------------------------------------------------------
self_dir="$(cd "$(dirname "$0")" && pwd -P)"
auto_test_dir="$(cd "$self_dir/.." && pwd -P)"
skills_root="$(cd "$auto_test_dir/.." && pwd -P)"
repo_root="$(cd "$skills_root/.." && pwd -P)"
orchestrate="$auto_test_dir/scripts/orchestrate.sh"
fixtures_root="$skills_root/unit-test-runner/tests/fixtures"
transcript_dir="$self_dir/smoke"

if [[ ! -x "$orchestrate" ]]; then
  echo "smoke.sh: orchestrate.sh missing or not executable: $orchestrate" >&2
  exit 2
fi
mkdir -p "$transcript_dir"

# --- helpers --------------------------------------------------------------
now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
have()    { command -v "$1" >/dev/null 2>&1; }

# Print to both stdout and the transcript file. Supports a single -n flag
# (no trailing newline), matching the printf default.
emit() {
  local file="$1"; shift
  printf '%s\n' "$*"
  printf '%s\n' "$*" >> "$file"
}

emit_raw() {
  local file="$1"; shift
  printf '%s' "$*"
  printf '%s' "$*" >> "$file"
}

# Parse the KEY=value block from orchestrate stdout. Returns 0 if all four
# keys are present, 1 otherwise. Echoes "LATEST=...\nLOG=...\n...".
extract_trailer() {
  local raw="$1"
  printf '%s\n' "$raw" | awk '/^(LATEST|LOG|JSON|EXIT)=/ {print}'
}

# JSON field reader. Args: <json-file> <dotted.path>. Echoes "" on miss.
json_get() {
  python3 -c '
import json,sys
p = sys.argv[2].split(".")
try:
    d = json.load(open(sys.argv[1]))
    for k in p:
        d = d.get(k) if isinstance(d, dict) else None
        if d is None:
            print("")
            sys.exit(0)
    print(d)
except Exception:
    print("")
' "$1" "$2"
}

# Track results across all scenarios run in one harness invocation.
PASS=0; FAIL=0; SKIP=0
FAILED_NAMES=""

record_pass() { PASS=$((PASS+1)); }
record_fail() {
  FAIL=$((FAIL+1))
  FAILED_NAMES="${FAILED_NAMES}${FAILED_NAMES:+ }$1"
}
record_skip() { SKIP=$((SKIP+1)); }

# --- scenario runners -----------------------------------------------------

# run_bun_scenario <pass|fail>
# Stages a copy of the bun fixture under mktemp, optionally injects a
# failing test, runs orchestrate.sh end-to-end, asserts the contract, and
# writes a transcript to skills/auto-test/tests/smoke/bun-<pass|fail>.log.
run_bun_scenario() {
  local kind="$1"  # pass | fail
  local name="bun-$kind"
  local transcript="$transcript_dir/$name.log"
  : > "$transcript"

  emit "$transcript" "## auto-test smoke — scenario=$name"
  emit "$transcript" "## host=$(uname -s)/$(uname -m)  bash=$BASH_VERSION"

  if ! have bun; then
    emit "$transcript" "[skip:bun not found in PATH]"
    emit "$transcript" "## manual fallback:"
    emit "$transcript" "##   curl -fsSL https://bun.sh/install | bash"
    emit "$transcript" "##   bash $orchestrate $fixtures_root/bun"
    record_skip
    return 0
  fi

  local bun_version; bun_version="$(bun --version 2>/dev/null || echo unknown)"
  emit "$transcript" "## bun=$bun_version"

  local work; work="$(mktemp -d -t autotest_smoke_${name}.XXXXXX)"
  trap 'rm -rf "$work"' RETURN  # only fires on this function's return
  cp -R "$fixtures_root/bun" "$work/proj"
  rm -rf "$work/proj/.test-runs"  # always start clean

  if [[ "$kind" == "fail" ]]; then
    cat > "$work/proj/tests/fail.test.ts" <<'TS'
import { test, expect } from "bun:test";
test("intentional failure for smoke", () => {
  expect(1 + 1).toBe(3);
});
TS
  fi

  emit "$transcript" "## work=$work"
  emit "$transcript" "## scenario=$kind"

  local started_ms ended_ms elapsed_ms raw rc
  started_ms="$(now_ms)"
  raw="$(bash "$orchestrate" "$work/proj" 2>&1)"
  rc=$?
  ended_ms="$(now_ms)"
  elapsed_ms=$((ended_ms - started_ms))

  emit "$transcript" "----- orchestrate.sh stdout (rc=$rc) -----"
  printf '%s\n' "$raw" >> "$transcript"
  printf '%s\n' "$raw"
  emit "$transcript" "----- end stdout -----"
  emit "$transcript" "# elapsed_ms=$elapsed_ms"

  # Re-extract from the second (clean) run's $raw — the rc must match $kind
  # expectation. Pull the trailer from $raw.
  local trailer; trailer="$(extract_trailer "$raw")"
  local LATEST LOG JSON EXIT
  LATEST="$(printf '%s\n' "$trailer" | awk -F= '$1=="LATEST"{print $2}')"
  LOG="$(printf '%s\n'    "$trailer" | awk -F= '$1=="LOG"{print $2}')"
  JSON="$(printf '%s\n'   "$trailer" | awk -F= '$1=="JSON"{print $2}')"
  EXIT="$(printf '%s\n'   "$trailer" | awk -F= '$1=="EXIT"{print $2}')"

  emit "$transcript" "----- parsed trailer -----"
  emit "$transcript" "LATEST=$LATEST"
  emit "$transcript" "LOG=$LOG"
  emit "$transcript" "JSON=$JSON"
  emit "$transcript" "EXIT=$EXIT"

  # ------ assertions ------
  local fail_msg=""

  # AC-2/3: rc matches scenario expectation
  local expected_rc=0
  [[ "$kind" == "fail" ]] && expected_rc=1
  if [[ "$rc" -ne "$expected_rc" ]]; then
    fail_msg="$fail_msg|rc=$rc expected=$expected_rc"
  fi

  # AC-4: trailer keys present
  for k in LATEST LOG JSON EXIT; do
    if ! printf '%s\n' "$trailer" | grep -qE "^${k}="; then
      fail_msg="$fail_msg|trailer missing $k"
    fi
  done

  # AC-4: trailer paths point at real files
  for f in "$LATEST" "$LOG" "$JSON"; do
    if [[ -z "$f" || ! -e "$f" ]]; then
      fail_msg="$fail_msg|missing path: $f"
    fi
  done

  # AC-5: run.json shape
  if [[ -s "$JSON" ]]; then
    local total failed
    total="$(json_get "$JSON" summary.total)"
    failed="$(json_get "$JSON" summary.failed)"
    emit "$transcript" "----- summary: total=$total failed=$failed -----"
    case "$kind" in
      pass)
        if [[ "${total:-0}" -lt 1 ]]; then fail_msg="$fail_msg|expected total>=1 got=$total"; fi
        if [[ "${failed:-1}" -ne 0 ]]; then fail_msg="$fail_msg|expected failed=0 got=$failed"; fi
        ;;
      fail)
        if [[ "${failed:-0}" -lt 1 ]]; then fail_msg="$fail_msg|expected failed>=1 got=$failed"; fi
        ;;
    esac
  else
    fail_msg="$fail_msg|run.json empty or missing"
  fi

  # AC-4 (extra): dashboard contains the expected verdict glyph
  case "$kind" in
    pass)
      if ! printf '%s' "$raw" | grep -q '✔ ALL'; then
        fail_msg="$fail_msg|dashboard missing pass glyph"
      fi
      ;;
    fail)
      if ! printf '%s' "$raw" | grep -q '✘ FAIL'; then
        fail_msg="$fail_msg|dashboard missing fail glyph"
      fi
      ;;
  esac

  if [[ -z "$fail_msg" ]]; then
    emit "$transcript" "RESULT: PASS  (elapsed_ms=$elapsed_ms)"
    record_pass
  else
    emit "$transcript" "RESULT: FAIL  ${fail_msg# |}"
    record_fail "$name"
  fi
}

# run_node_scenario <jest|vitest>
# Both jest and vitest need node + a package manager (npm or pnpm) plus a
# real `npm ci` / `pnpm install` against a populated cache. The sandbox
# does not ship node, so this scenario *expects to skip* and emit a
# manual-fallback transcript that records the exact reproduction commands.
run_node_scenario() {
  local fw="$1"  # jest | vitest
  local name="$fw"
  local transcript="$transcript_dir/$name.log"
  : > "$transcript"

  emit "$transcript" "## auto-test smoke — scenario=$name"
  emit "$transcript" "## host=$(uname -s)/$(uname -m)  bash=$BASH_VERSION"

  if ! have node; then
    emit "$transcript" "[skip:node not found in PATH]"
    emit "$transcript" "## manual fallback (run on a host with node + the right pkg manager):"
    case "$fw" in
      jest)
        emit "$transcript" "##   cd \$(mktemp -d)"
        emit "$transcript" "##   cp -R $fixtures_root/jest jest-smoke && cd jest-smoke"
        emit "$transcript" "##   npm ci          # installs jest@^29"
        emit "$transcript" "##   bash $orchestrate ."
        emit "$transcript" "##   echo \"exit=\$?\""
        emit "$transcript" "##   ls .test-runs/"
        emit "$transcript" "##   python3 -m json.tool .test-runs/*/run.json | head -40"
        ;;
      vitest)
        emit "$transcript" "##   cd \$(mktemp -d)"
        emit "$transcript" "##   cp -R $fixtures_root/vitest vitest-smoke && cd vitest-smoke"
        emit "$transcript" "##   pnpm install     # or: npm i"
        emit "$transcript" "##   bash $orchestrate ."
        emit "$transcript" "##   echo \"exit=\$?\""
        emit "$transcript" "##   ls .test-runs/"
        emit "$transcript" "##   python3 -m json.tool .test-runs/*/run.json | head -40"
        ;;
    esac
    emit "$transcript" "## expected: exit=0, dashboard ends with 'EXIT 0   all <N> tests passed'"
    record_skip
    return 0
  fi

  if ! have npm && ! have pnpm; then
    emit "$transcript" "[skip:neither npm nor pnpm in PATH]"
    record_skip
    return 0
  fi

  # If we *do* have node + a package manager, attempt the real run. (This
  # branch is exercised on contributor hosts that happen to have node.
  # Sandbox CI flow stays in the [skip] branch above.)
  local pkg_mgr="npm"; have pnpm && [[ "$fw" == "vitest" ]] && pkg_mgr="pnpm"
  emit "$transcript" "## node=$(node --version 2>/dev/null) pkg-manager=$pkg_mgr"

  local work; work="$(mktemp -d -t autotest_smoke_${name}.XXXXXX)"
  trap 'rm -rf "$work"' RETURN
  cp -R "$fixtures_root/$fw" "$work/proj"
  rm -rf "$work/proj/.test-runs"

  emit "$transcript" "## work=$work"
  emit "$transcript" "## installing deps with $pkg_mgr (this may take 30-60s)..."
  ( cd "$work/proj" && $pkg_mgr install --silent 2>&1 ) >> "$transcript" || {
    emit "$transcript" "[skip:dep install failed; manual reproduction needed]"
    record_skip
    return 0
  }

  emit "$transcript" "----- orchestrate.sh stdout -----"
  local started_ms ended_ms elapsed_ms
  started_ms="$(now_ms)"
  local raw; raw="$(bash "$orchestrate" "$work/proj" 2>&1)"
  local rc=$?
  ended_ms="$(now_ms)"; elapsed_ms=$((ended_ms - started_ms))
  printf '%s\n' "$raw" >> "$transcript"

  emit "$transcript" "----- orchestrate.sh exit=$rc -----"
  emit "$transcript" "# elapsed_ms=$elapsed_ms"

  # Pass-only assertion: fixtures are pass-path. Same shape as bun-pass.
  local trailer; trailer="$(extract_trailer "$raw")"
  local JSON; JSON="$(printf '%s\n' "$trailer" | awk -F= '$1=="JSON"{print $2}')"
  local total failed
  total="$(json_get "$JSON" summary.total 2>/dev/null)"
  failed="$(json_get "$JSON" summary.failed 2>/dev/null)"
  emit "$transcript" "----- summary: total=$total failed=$failed -----"

  local fail_msg=""
  if [[ "$rc" -ne 0 ]]; then fail_msg="$fail_msg|rc=$rc expected=0"; fi
  if [[ "${total:-0}" -lt 1 ]]; then fail_msg="$fail_msg|expected total>=1 got=$total"; fi
  if [[ "${failed:-1}" -ne 0 ]]; then fail_msg="$fail_msg|expected failed=0 got=$failed"; fi

  if [[ -z "$fail_msg" ]]; then
    emit "$transcript" "RESULT: PASS  (elapsed_ms=$elapsed_ms)"
    record_pass
  else
    emit "$transcript" "RESULT: FAIL  ${fail_msg# |}"
    record_fail "$name"
  fi
}

# run_regression — re-run all four prior unit-test suites and tally.
run_regression() {
  local transcript="$transcript_dir/regression.log"
  : > "$transcript"
  emit "$transcript" "## auto-test smoke — scenario=regression"

  local suites=(
    "$skills_root/test-log-centralizer/tests/run-all.sh"
    "$skills_root/unit-test-runner/tests/run-all.sh"
    "$skills_root/auto-test/tests/run-all.sh"
    "$repo_root/tools/tests/run-all.sh"
  )
  local fail_msg=""
  for s in "${suites[@]}"; do
    if [[ ! -x "$s" ]]; then
      emit "$transcript" "  [missing] $s"
      fail_msg="$fail_msg|missing: $s"
      continue
    fi
    if bash "$s" >>"$transcript" 2>&1; then
      emit "$transcript" "  [ok] $s"
    else
      emit "$transcript" "  [FAIL] $s"
      fail_msg="$fail_msg|regression: $s"
    fi
  done

  if [[ -z "$fail_msg" ]]; then
    emit "$transcript" "RESULT: PASS"
    record_pass
  else
    emit "$transcript" "RESULT: FAIL ${fail_msg# |}"
    record_fail "regression"
  fi
}

# --- dispatch -------------------------------------------------------------
scenario="${1:-all}"

case "$scenario" in
  bun-pass)   run_bun_scenario pass ;;
  bun-fail)   run_bun_scenario fail ;;
  jest)       run_node_scenario jest ;;
  vitest)     run_node_scenario vitest ;;
  regression) run_regression ;;
  all)
    run_bun_scenario pass
    run_bun_scenario fail
    run_node_scenario jest
    run_node_scenario vitest
    run_regression
    ;;
  *)
    echo "smoke.sh: unknown scenario '$scenario'" >&2
    echo "  usage: smoke.sh [bun-pass|bun-fail|jest|vitest|regression|all]" >&2
    exit 2
    ;;
esac

echo
echo "smoke summary: pass=$PASS fail=$FAIL skip=$SKIP"
[[ -n "$FAILED_NAMES" ]] && echo "  failed: $FAILED_NAMES"

# Harness rc: 0 if no real fails, 1 otherwise. Skips do not fail.
[[ "$FAIL" -eq 0 ]]
