#!/usr/bin/env bash
# test-render-dashboard.sh — pure-function tests for render-dashboard.sh.
# Phase 1 / T-1.5.
#
# Drives the renderer against a pre-baked sample run dir under
# tests/goldens/sample-run/ so we don't depend on bun being installed.
#
# Asserts content presence (regex grep), not byte-equal — duration_ms /
# timestamps drift, and we don't want goldens that flake on locale.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
skill_dir="$(cd "$here/.." && pwd -P)"
render="$skill_dir/scripts/render-dashboard.sh"
golden_run_dir="$here/goldens/sample-run"

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

echo "[render-dashboard] driving against $golden_run_dir"

if [[ ! -x "$render" ]]; then
  echo "FATAL: $render not executable" >&2
  exit 1
fi

if [[ ! -d "$golden_run_dir" ]]; then
  echo "FATAL: golden run dir missing: $golden_run_dir" >&2
  exit 1
fi

# Capture rendered output once for shared assertions.
out_tmp="$(mktemp -t test_render.XXXXXX)"
err_tmp="$(mktemp -t test_render_err.XXXXXX)"
trap 'rm -f "$out_tmp" "$err_tmp"' EXIT

if ! "$render" "$golden_run_dir" 1 >"$out_tmp" 2>"$err_tmp"; then
  echo "FATAL: renderer exited non-zero on golden sample"
  cat "$err_tmp"
  exit 1
fi

# --- structural assertions ------------------------------------------------
check "header line contains 'auto-test'"               "grep -q 'auto-test' '$out_tmp'"
check "header contains run_id 20260506T050000Z"        "grep -q '20260506T050000Z' '$out_tmp'"
check "header shows duration 1234ms"                   "grep -q 'duration 1234ms' '$out_tmp'"
check "Project row present with basename 'sample-app'" "grep -qE 'Project[[:space:]]+:[[:space:]]+sample-app' '$out_tmp'"
check "Framework row shows vitest"                      "grep -qE 'Framework[[:space:]]+:[[:space:]]+vitest' '$out_tmp'"
check "Command row shows 'pnpm test'"                   "grep -q 'pnpm test' '$out_tmp'"
check "UNIT row present"                                "grep -q 'UNIT' '$out_tmp'"
check "UNIT row shows 3 passed"                         "grep -qE '3[[:space:]]+passed' '$out_tmp'"
check "UNIT row shows 2 failed"                         "grep -qE '2[[:space:]]+failed' '$out_tmp'"
check "UNIT row shows 0 skipped"                        "grep -qE '0[[:space:]]+skipped' '$out_tmp'"

# Failures block (2 failures in the sample → no '… more')
check "FAILURES section present"                        "grep -q 'FAILURES' '$out_tmp'"
check "shows auth failure name"                         "grep -q 'rejects expired token' '$out_tmp'"
check "shows auth failure message"                      "grep -q 'expected 401 got 200' '$out_tmp'"
check "shows checkout failure name"                     "grep -q 'applies coupon discount' '$out_tmp'"
check "no '(… more — see run.log)' for 2 failures"      "! grep -q 'more — see run.log' '$out_tmp'"

# Artifacts block
check "ARTIFACTS section present"                       "grep -q 'ARTIFACTS' '$out_tmp'"
check "log line present"                                "grep -q 'log[[:space:]]' '$out_tmp'"
check "json line present"                               "grep -q 'json[[:space:]]' '$out_tmp'"
check "manifest line present"                           "grep -q 'manifest[[:space:]]' '$out_tmp'"

# Footer + machine-readable trailer
check "EXIT footer shows '2 of 5 tests failed'"         "grep -q 'tests failed' '$out_tmp'"
check "trailing LATEST= absolute path present"          "grep -qE '^LATEST=/' '$out_tmp'"
check "trailing LOG= ends with run.log"                 "grep -qE '^LOG=.*run\\.log$' '$out_tmp'"
check "trailing JSON= ends with run.json"               "grep -qE '^JSON=.*run\\.json$' '$out_tmp'"
check "trailing EXIT=1 (runner-exit override applied)"  "grep -qE '^EXIT=1$' '$out_tmp'"

# Box characters present (sanity for unicode handling)
check "top corner '┌' present"                          "grep -q '┌' '$out_tmp'"
check "bottom corner '└' present"                       "grep -q '└' '$out_tmp'"

# --- passed run path (re-render with runner_exit=0) ----------------------
# Synthesize a fresh "all green" sample by patching summary.json on the fly.
# Use a copy so we don't pollute goldens.
green_dir="$(mktemp -d -t test_render_green.XXXXXX)"
trap 'rm -f "$out_tmp" "$err_tmp"; rm -rf "$green_dir"' EXIT
cp "$golden_run_dir/manifest.json" "$green_dir/manifest.json"
cp "$golden_run_dir/run.json"      "$green_dir/run.json"
python3 - "$green_dir" <<'PY'
import json, os, sys
d = sys.argv[1]
mf = json.load(open(os.path.join(d, "manifest.json")))
mf["summary"] = {"total": 5, "passed": 5, "failed": 0, "skipped": 0}
mf["exit_code"] = 0
json.dump(mf, open(os.path.join(d, "manifest.json"), "w"), indent=2)
sm = {
    "schema_version": "1",
    "status": "passed",
    "exit_code": 0,
    "duration_ms": 999,
    "total": 5,
    "passed": 5,
    "failed": 0,
    "skipped": 0,
    "finished_ts": "2026-05-06T05:00:01Z",
    "log_path": os.path.join(d, "run.log")
}
json.dump(sm, open(os.path.join(d, "summary.json"), "w"), indent=2)
rj = json.load(open(os.path.join(d, "run.json")))
rj["failures"] = []
rj["summary"]["passed"] = 5
rj["summary"]["failed"] = 0
json.dump(rj, open(os.path.join(d, "run.json"), "w"), indent=2)
PY
out_green="$(mktemp -t test_render_green_out.XXXXXX)"
"$render" "$green_dir" 0 >"$out_green" 2>/dev/null

check "green path: header shows '✔ ALL'"               "grep -q '✔ ALL' '$out_green'"
check "green path: NO FAILURES section"                 "! grep -q 'FAILURES' '$out_green'"
check "green path: footer 'all 5 tests passed'"         "grep -q 'all 5 tests passed' '$out_green'"
check "green path: trailing EXIT=0"                     "grep -qE '^EXIT=0$' '$out_green'"
rm -f "$out_green"

# --- error path -----------------------------------------------------------
err_run="$(mktemp -d -t test_render_err.XXXXXX)"
cp "$golden_run_dir/manifest.json" "$err_run/manifest.json"
cp "$golden_run_dir/run.json"      "$err_run/run.json"
python3 - "$err_run" <<'PY'
import json, os, sys
d = sys.argv[1]
sm = {
    "schema_version": "1",
    "status": "error",
    "exit_code": 2,
    "duration_ms": 80,
    "total": 0,
    "passed": 0,
    "failed": 0,
    "skipped": 0,
    "finished_ts": "2026-05-06T05:00:01Z",
    "log_path": os.path.join(d, "run.log")
}
json.dump(sm, open(os.path.join(d, "summary.json"), "w"), indent=2)
PY
out_err="$(mktemp -t test_render_err_out.XXXXXX)"
"$render" "$err_run" 2 >"$out_err" 2>/dev/null
check "error path: header shows '‼ ERROR'"             "grep -q '‼ ERROR' '$out_err'"
check "error path: footer 'EXIT 2'"                     "grep -q 'EXIT 2' '$out_err'"
check "error path: trailing EXIT=2"                     "grep -qE '^EXIT=2$' '$out_err'"
rm -f "$out_err"
rm -rf "$err_run"
rm -rf "$green_dir"

# --- bad input path -------------------------------------------------------
if "$render" /no/such/dir 0 >/dev/null 2>"$err_tmp"; then
  echo "  ✘ render-dashboard should reject missing run-dir but exited 0"
  FAIL=$((FAIL + 1))
else
  printf '  ✔ %s\n' "rejects missing run-dir with non-zero exit"
  PASS=$((PASS + 1))
fi

echo
echo "[render-dashboard] PASS=$PASS  FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
