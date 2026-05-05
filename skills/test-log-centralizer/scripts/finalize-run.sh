#!/usr/bin/env bash
# finalize-run.sh — close out a run folder: merge per-layer streams into the
# canonical run.log, promote summary.json to its final shape, write the rich
# manifest.json (per docs/ARCHITECTURE.md §(b)) and a run.json placeholder
# (suites filled later by T-1.4 parsers), and atomically re-point
# <project>/.test-runs/latest at this run.
#
# Usage:
#   finalize-run.sh <run-dir> <exit_code> [total] [passed] [failed] [skipped]
#
# Inputs:
#   <run-dir>    absolute path produced by init-run.sh
#   <exit_code>  the framework's exit code (0 == pass, 1 == failed test, 2 == error)
#   counts       optional; default 0/0/0/0. Filled by T-1.4 parsers in real flow.
#
# Outputs (atomic via tmp + rename):
#   <run-dir>/run.log        canonical merged log (in fixed layer order)
#   <run-dir>/summary.json   final form: status / exit_code / duration_ms / counts / log_path
#   <run-dir>/manifest.json  rich index per ARCHITECTURE §(b)
#   <run-dir>/run.json       skeleton: { schema_version, run_id, suites: [] }
#   <run-dir>/../latest      symlink → basename(run-dir)  (re-pointed atomically)
#
# On error: diagnostic on stderr, non-zero exit. No partial files left behind
# (writes go to *.tmp, mv -f only after full write succeeds).
set -uo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: finalize-run.sh <run-dir> <exit_code> [total] [passed] [failed] [skipped]" >&2
  exit 2
fi

run_dir="$1"
exit_code="$2"
total="${3:-0}"
passed="${4:-0}"
failed="${5:-0}"
skipped="${6:-0}"

if [[ ! -d "$run_dir" ]]; then
  echo "finalize: run-dir not found: $run_dir" >&2
  exit 1
fi
if [[ ! -f "$run_dir/meta.json" ]]; then
  echo "finalize: meta.json missing — was init-run.sh called? ($run_dir/meta.json)" >&2
  exit 1
fi

# --- helpers --------------------------------------------------------------
# Pull a string value from meta.json. Prefer python3 (handles JSON properly,
# including escapes/nesting); fall back to a brittle line-grep that's still
# correct for the flat-object meta.json this codebase emits.
read_meta_str() {
  local key="$1" v
  v="$(python3 -c "
import json,sys
d = json.load(open(sys.argv[1]))
print(d.get(sys.argv[2], ''))
" "$run_dir/meta.json" "$key" 2>/dev/null)" && { printf '%s' "$v"; return; }
  # Fallback (no python3): grep the field. Only safe because meta.json is
  # written by init-run.sh as a flat object with one field per line.
  awk -v k="\"$key\"" '
    index($0, k) {
      sub(/.*: *"/, "")
      sub(/"[, ]*$/, "")
      print; exit
    }
  ' "$run_dir/meta.json"
}
read_meta_int() {
  local key="$1" v
  v="$(python3 -c "
import json,sys
d = json.load(open(sys.argv[1]))
print(int(d.get(sys.argv[2], 0)))
" "$run_dir/meta.json" "$key" 2>/dev/null)" && { printf '%s' "$v"; return; }
  awk -v k="\"$key\"" '
    index($0, k) {
      sub(/.*: */, ""); sub(/[, ]*$/, ""); print; exit
    }
  ' "$run_dir/meta.json"
}

json_escape() {
  python3 -c '
import json, sys
print(json.dumps(sys.argv[1])[1:-1])
' "$1" 2>/dev/null \
    || printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# --- read meta ------------------------------------------------------------
project="$(read_meta_str project_dir)"
runner="$(read_meta_str runner)"
command_str="$(read_meta_str command)"
start_ts="$(read_meta_str start_ts)"
started_epoch_ms="$(read_meta_int started_epoch_ms)"

# --- compute duration -----------------------------------------------------
finished_epoch_ms="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null \
  || echo "$(date +%s)000")"
finished_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
duration_ms=$(( finished_epoch_ms - started_epoch_ms ))
(( duration_ms < 0 )) && duration_ms=0

# --- merge streams in canonical order into run.log ------------------------
# Order matches spike T-0.3 §4 / spike finalize-run.sh: unit → integration →
# browser → orchestrator → skill → setup → teardown. all.log is excluded
# (it's a tee of everything; merging would double-count).
order=(unit integration browser orchestrator skill setup teardown)
run_log_tmp="$run_dir/run.log.tmp"
: > "$run_log_tmp"
layers_present=()
for layer in "${order[@]}"; do
  src="$run_dir/streams/${layer}.log"
  if [[ -s "$src" ]]; then
    cat "$src" >> "$run_log_tmp"
    layers_present+=("$layer")
  fi
done
mv -f "$run_log_tmp" "$run_dir/run.log"

# --- determine status -----------------------------------------------------
# - exit_code 0 AND failed 0  → "passed"
# - exit_code 2               → "error"
# - else                      → "failed"
if [[ "$exit_code" == "2" ]]; then
  status="error"
elif [[ "$exit_code" == "0" && "$failed" == "0" ]]; then
  status="passed"
else
  status="failed"
fi

run_id="$(basename "$run_dir")"
log_path_abs="$run_dir/run.log"

# --- escape strings for embedding in JSON ---------------------------------
project_j="$(json_escape "$project")"
runner_j="$(json_escape "$runner")"
command_j="$(json_escape "$command_str")"
run_id_j="$(json_escape "$run_id")"
start_ts_j="$(json_escape "$start_ts")"
finished_ts_j="$(json_escape "$finished_ts")"
log_path_j="$(json_escape "$log_path_abs")"
status_j="$(json_escape "$status")"

# --- build layers JSON array ---------------------------------------------
layers_json="["
first=1
for layer in "${layers_present[@]:-}"; do
  [[ -z "$layer" ]] && continue
  if (( first )); then first=0; else layers_json+=","; fi
  layers_json+="\"$layer\""
done
layers_json+="]"

# --- write summary.json (final form) -------------------------------------
summary_tmp="$run_dir/summary.json.tmp"
cat > "$summary_tmp" <<EOF
{
  "schema_version": "1",
  "status": "$status_j",
  "exit_code": $exit_code,
  "duration_ms": $duration_ms,
  "total": $total,
  "passed": $passed,
  "failed": $failed,
  "skipped": $skipped,
  "finished_ts": "$finished_ts_j",
  "log_path": "$log_path_j"
}
EOF
mv -f "$summary_tmp" "$run_dir/summary.json"

# --- write manifest.json -------------------------------------------------
manifest_tmp="$run_dir/manifest.json.tmp"
cat > "$manifest_tmp" <<EOF
{
  "schema_version": "1",
  "run_id": "$run_id_j",
  "project": "$project_j",
  "started_at": "$start_ts_j",
  "finished_at": "$finished_ts_j",
  "duration_ms": $duration_ms,
  "framework": "$runner_j",
  "command": "$command_j",
  "exit_code": $exit_code,
  "summary": {
    "total": $total,
    "passed": $passed,
    "failed": $failed,
    "skipped": $skipped
  },
  "failed_cases": [],
  "log_path": "$log_path_j",
  "artifacts": {
    "log": "run.log",
    "summary": "summary.json",
    "json": "run.json",
    "browser_console": null,
    "screenshots": [],
    "flaky_report": null,
    "coverage_summary": null,
    "manual_checklist": null
  },
  "layers": $layers_json
}
EOF
mv -f "$manifest_tmp" "$run_dir/manifest.json"

# --- write run.json placeholder ------------------------------------------
# T-1.4 parsers populate `suites`; here we only guarantee the contract shape
# so downstream tooling can rely on the keys existing.
run_json_tmp="$run_dir/run.json.tmp"
cat > "$run_json_tmp" <<EOF
{
  "schema_version": "1",
  "run_id": "$run_id_j",
  "suites": []
}
EOF
mv -f "$run_json_tmp" "$run_dir/run.json"

# --- atomically re-point latest -------------------------------------------
# `ln -sfn` is rename(2) on Linux and unlink+symlink on BSD; both end states
# (after success) are: latest is a symlink whose target == run_id.
runs_root="$(dirname "$run_dir")"
( cd "$runs_root" && ln -sfn "$run_id" latest )

# --- optional retention sweep (T-1.6) -------------------------------------
# Opt-in via TEST_LOG_RETAIN=1 to keep test isolation: T-1.1..T-1.5 unit
# tests must NOT trigger retention while exercising finalize, otherwise
# their assertions about run-dir count + file shape would race against the
# sweep. Production callers (auto-test orchestrator) export the flag.
if [[ "${TEST_LOG_RETAIN:-0}" == "1" ]]; then
  retain_script="$(dirname "$0")/retain.sh"
  if [[ -x "$retain_script" ]]; then
    "$retain_script" "$runs_root" >/dev/null 2>&1 || true
  fi
fi

echo "$run_dir"
