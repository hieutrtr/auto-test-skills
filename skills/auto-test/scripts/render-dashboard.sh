#!/usr/bin/env bash
# render-dashboard.sh — read a finalized run dir + emit ASCII dashboard.
# Phase 1 / T-1.5 (compact form of docs/PRD.md §7 wireframe).
#
# Usage:
#   render-dashboard.sh <run-dir> [<runner-exit-code>]
#
# Reads:
#   <run-dir>/manifest.json
#   <run-dir>/summary.json
#   <run-dir>/run.json     (Phase 1: jest|vitest|bun parser output)
#
# Emits:
#   <ASCII box with rows: header, Project / Framework / Command, UNIT counts,
#    optional FAILURES (≤ 3), ARTIFACTS, EXIT footer>
#   <blank line>
#   LATEST=<abs run dir>
#   LOG=<abs run.log>
#   JSON=<abs run.json>
#   EXIT=<code>
#
# Why the trailing KEY=value block: the loop / claude-bridge consumer
# needs to grep one line without parsing the box-drawn unicode table.
# Keeping the keys stable is part of the auto-test public contract.
set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: render-dashboard.sh <run-dir> [<runner-exit-code>]" >&2
  exit 2
fi

run_dir="$1"
runner_exit="${2:-}"

if [[ ! -d "$run_dir" ]]; then
  echo "render: run-dir not found: $run_dir" >&2
  exit 2
fi

# Resolve run-dir to absolute path early; consumers grep `LATEST=`.
run_dir="$(cd "$run_dir" && pwd -P)"

manifest="$run_dir/manifest.json"
summary="$run_dir/summary.json"
run_json="$run_dir/run.json"
run_log="$run_dir/run.log"

for f in "$manifest" "$summary"; do
  if [[ ! -f "$f" ]]; then
    echo "render: missing $f (was finalize-run.sh called?)" >&2
    exit 2
  fi
done

# -------------------------------------------------------------------------
# Pull all the data we need via a single python3 invocation. Output is a
# stream of `K=V` lines that bash can `read` into vars. Values are
# already truncated/escaped for ASCII safety.
# -------------------------------------------------------------------------
PY_SCRIPT=$(cat <<'PYEOF'
import json, os, sys

run_dir = sys.argv[1]
manifest = json.load(open(os.path.join(run_dir, "manifest.json")))
summary  = json.load(open(os.path.join(run_dir, "summary.json")))

run_path = os.path.join(run_dir, "run.json")
run_data = {}
try:
    with open(run_path) as f:
        run_data = json.load(f)
except Exception:
    run_data = {}

def s(v, default=""):
    return "" if v is None else str(v)

run_id      = s(manifest.get("run_id"))
project     = s(manifest.get("project"))
framework   = s(manifest.get("framework"))
command     = s(manifest.get("command"))
duration_ms = manifest.get("duration_ms", 0) or 0

status   = s(summary.get("status"))
exitcode = summary.get("exit_code", 0) or 0
total    = int(summary.get("total", 0) or 0)
passed   = int(summary.get("passed", 0) or 0)
failed   = int(summary.get("failed", 0) or 0)
skipped  = int(summary.get("skipped", 0) or 0)

# Collect up to 3 failures from run.json.
failures = run_data.get("failures") or []
fail_lines = []
for fail in failures[:3]:
    name = s(fail.get("name"))
    fpath = s(fail.get("file"))
    msg = s(fail.get("message"))
    # Truncate to keep box stable.
    if len(msg) > 60:
        msg = msg[:59] + "…"
    suite = os.path.basename(fpath) if fpath else "(unknown)"
    fail_lines.append(f"{suite} › {name}|{msg}")
fail_more = max(0, len(failures) - 3)

# Project basename for the header row (full path is too long for the box).
project_basename = os.path.basename(project.rstrip("/")) or project or "(unknown)"

def kv(k, v):
    print(f"{k}={v}")

kv("RUN_ID", run_id)
kv("PROJECT_BASENAME", project_basename)
kv("FRAMEWORK", framework or "(unknown)")
kv("COMMAND", command or "(none)")
kv("DURATION_MS", duration_ms)
kv("STATUS", status or "unknown")
kv("EXIT_CODE", exitcode)
kv("TOTAL", total)
kv("PASSED", passed)
kv("FAILED", failed)
kv("SKIPPED", skipped)
kv("FAIL_COUNT", len(failures))
kv("FAIL_MORE", fail_more)
for i, line in enumerate(fail_lines):
    # Escape literal newlines (none expected after our truncation but be safe).
    print(f"FAIL_{i}={line}")
PYEOF
)

# Read python output into a small dict via a temp file (avoids associative-array
# requirement in bash 3.2 on macOS).
data_tmp="$(mktemp -t autotest_render.XXXXXX)"
trap 'rm -f "$data_tmp"' EXIT
python3 -c "$PY_SCRIPT" "$run_dir" > "$data_tmp"

get() {
  local key="$1"
  awk -F= -v k="$key" '$1==k { sub(/^[^=]*=/,""); print; exit }' "$data_tmp"
}

run_id="$(get RUN_ID)"
project_basename="$(get PROJECT_BASENAME)"
framework="$(get FRAMEWORK)"
command_str="$(get COMMAND)"
duration_ms="$(get DURATION_MS)"
status="$(get STATUS)"
exit_code="$(get EXIT_CODE)"
total="$(get TOTAL)"
passed="$(get PASSED)"
failed="$(get FAILED)"
skipped="$(get SKIPPED)"
fail_count="$(get FAIL_COUNT)"
fail_more="$(get FAIL_MORE)"

# Status icon for header row.
status_icon=""
if [[ "$status" == "passed" ]]; then
  status_icon="✔ ALL"
elif [[ "$status" == "failed" ]]; then
  status_icon="✘ FAIL"
elif [[ "$status" == "error" ]]; then
  status_icon="‼ ERROR"
else
  status_icon="? $status"
fi

# Width: 66 char inside the box (content area). PRD §7 wireframe is ~64;
# we allow 66 for path padding.
WIDTH=66
hr="$(printf '─%.0s' $(seq 1 $WIDTH))"
top="┌${hr}┐"
mid="├${hr}┤"
bot="└${hr}┘"

pad_line() {
  # Pads/truncates the supplied content to WIDTH and wraps in │ ... │.
  # Uses python3 because awk's substr truncation is fine but not unicode-aware.
  python3 -c '
import sys
w = int(sys.argv[1])
s = sys.argv[2]
# Truncate by char count, not byte; pad with spaces.
if len(s) > w:
    s = s[:w-1] + "…"
print("│" + s + " " * (w - len(s)) + "│")
' "$WIDTH" "$1"
}

# -------------------------------------------------------------------------
# Render
# -------------------------------------------------------------------------
echo "$top"
pad_line "  auto-test  ·  run $run_id  ·  duration ${duration_ms}ms   $status_icon"
echo "$mid"
pad_line "  Project   : $project_basename"
pad_line "  Framework : $framework (auto-detected)"
pad_line "  Command   : $command_str"
echo "$mid"
pad_line "  UNIT          ✔ $passed passed   ✘ $failed failed    ⚠ $skipped skipped"

if [[ "$fail_count" -gt 0 ]]; then
  echo "$mid"
  pad_line "  FAILURES"
  for i in 0 1 2; do
    line="$(get "FAIL_$i")"
    [[ -z "$line" ]] && continue
    name_part="${line%%|*}"
    msg_part="${line#*|}"
    pad_line "   • $name_part"
    if [[ -n "$msg_part" && "$msg_part" != "$line" ]]; then
      pad_line "       $msg_part"
    fi
  done
  if [[ "${fail_more:-0}" -gt 0 ]]; then
    pad_line "   (… $fail_more more — see run.log)"
  fi
fi

echo "$mid"
pad_line "  ARTIFACTS"
pad_line "    log       $run_log"
pad_line "    json      $run_json"
pad_line "    manifest  $manifest"
echo "$mid"

# Footer EXIT message.
case "$status" in
  passed) footer="EXIT 0   all $total tests passed" ;;
  failed) footer="EXIT 1   $failed of $total tests failed" ;;
  error)  footer="EXIT 2   error — see run.log" ;;
  *)      footer="EXIT $exit_code   status=$status" ;;
esac
pad_line "  $footer"
echo "$bot"

# Trailing machine-readable lines (loop / agent grep target).
echo
echo "LATEST=$run_dir"
echo "LOG=$run_log"
echo "JSON=$run_json"
# EXIT line uses the runner's exit if provided, else the summary's.
if [[ -n "$runner_exit" ]]; then
  echo "EXIT=$runner_exit"
else
  echo "EXIT=$exit_code"
fi
