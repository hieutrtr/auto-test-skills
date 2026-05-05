#!/usr/bin/env bash
# init-run.sh — initialize a fresh test-run folder under <project>/.test-runs/.
#
# Usage:
#   init-run.sh <project-root> [runner] [command]
#
# On success: echoes the absolute path to the created run folder on stdout, exit 0.
# On error:   diagnostic on stderr, non-zero exit.
#
# Layout produced (matches docs/ARCHITECTURE.md §(b) + T-1.1 task spec):
#   <project>/.test-runs/<run-id>/
#     run.log          empty file; append-log.sh + finalize-run.sh write here (T-1.2)
#     meta.json        run scaffold metadata (replaces spike's `.meta` key=value form)
#     summary.json     placeholder; finalize-run.sh fills counts + status (T-1.2)
#     streams/         per-layer log files; written by append-log.sh (T-1.2)
#     screenshots/     browser-test artifacts (Phase 2)
#
# run-id format: YYYYMMDDTHHMMSSZ (UTC, no colons, sortable). When two invocations
# land in the same UTC second, a `-N` counter suffix is appended so each call
# returns a distinct dir (carries spike collision guard).
#
# Cross-platform notes (loop Rule 2):
#   - `date -u +%Y%m%dT%H%M%SZ` is portable BSD + GNU.
#   - millisecond epoch uses python3 (universally present on macOS / most distros);
#     falls back to `date +%s000` (second precision) when python3 is absent.
#   - JSON escape uses python3 with sed fallback. No `jq` dependency.
#   - No GNU-only flags (`stat -c`, `date -d`, `gzip --keep`).
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: init-run.sh <project-root> [runner] [command]" >&2
  exit 2
fi

project_root_input="$1"
runner="${2:-tbd}"
command_str="${3:-}"

if [[ ! -d "$project_root_input" ]]; then
  echo "init-run: project root not found: $project_root_input" >&2
  exit 1
fi

# Absolute path — required so meta.project_dir is unambiguous when caller cd's later.
project_root="$(cd "$project_root_input" && pwd -P)"

if [[ ! -w "$project_root" ]]; then
  echo "init-run: project root not writable: $project_root" >&2
  exit 1
fi

run_id="$(date -u +%Y%m%dT%H%M%SZ)"
runs_root="$project_root/.test-runs"
run_dir="$runs_root/$run_id"

mkdir -p "$runs_root"

# Collision guard: if same-second run dir exists (parallel spawn or repeat call),
# append a counter until we find a free slot.
n=1
while [[ -e "$run_dir" ]]; do
  run_dir="$runs_root/${run_id}-${n}"
  n=$((n + 1))
done
final_run_id="$(basename "$run_dir")"

mkdir -p "$run_dir/streams" "$run_dir/screenshots"
: > "$run_dir/run.log"

start_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
started_epoch_ms="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null \
  || echo "$(date +%s)000")"

# Minimal JSON-string escape for fields that may contain spaces, quotes, backslashes.
json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1])[1:-1])' "$1" 2>/dev/null \
    || printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
project_j="$(json_escape "$project_root")"
runner_j="$(json_escape "$runner")"
command_j="$(json_escape "$command_str")"
run_id_j="$(json_escape "$final_run_id")"
start_ts_j="$(json_escape "$start_ts")"

# --- write meta.json (atomic: tmp + rename) -------------------------------
meta_tmp="$run_dir/meta.json.tmp"
meta_final="$run_dir/meta.json"
cat > "$meta_tmp" <<EOF
{
  "schema_version": "1",
  "run_id": "$run_id_j",
  "start_ts": "$start_ts_j",
  "started_epoch_ms": $started_epoch_ms,
  "project_dir": "$project_j",
  "runner": "$runner_j",
  "command": "$command_j"
}
EOF
mv -f "$meta_tmp" "$meta_final"

# --- write summary.json placeholder (atomic: tmp + rename) ----------------
# `exit_code: null` and `status: "in_progress"` until finalize-run.sh updates.
summary_tmp="$run_dir/summary.json.tmp"
summary_final="$run_dir/summary.json"
cat > "$summary_tmp" <<EOF
{
  "schema_version": "1",
  "status": "in_progress",
  "exit_code": null,
  "total": 0,
  "passed": 0,
  "failed": 0,
  "skipped": 0
}
EOF
mv -f "$summary_tmp" "$summary_final"

echo "$run_dir"
