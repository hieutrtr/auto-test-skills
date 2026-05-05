#!/usr/bin/env bash
# start-run.sh — initialize a fresh test-run folder under <project>/.test-runs/.
#
# Usage:
#   start-run.sh <project-root> [framework] [command]
# Echoes the absolute path to the created run folder on stdout.
#
# Layout produced (matches T-0.3 design memo §2):
#   <project>/.test-runs/<run-id>/
#     streams/        empty; append-log.sh writes here
#     screenshots/    empty
#     .meta           run-scoped k/v store used by finalize-run.sh
#
# run-id format: YYYYMMDDTHHmmssZ (UTC, no colons, sortable).
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: start-run.sh <project-root> [framework] [command]" >&2
  exit 2
fi

project_root="$1"
framework="${2:-unknown}"
command="${3:-}"

if [[ ! -d "$project_root" ]]; then
  echo "start-run: project root not found: $project_root" >&2
  exit 1
fi

run_id="$(date -u +%Y%m%dT%H%M%SZ)"
runs_root="$project_root/.test-runs"
run_dir="$runs_root/$run_id"

# Collision guard: if same-second run exists (parallel spawn), append a counter.
n=1
while [[ -e "$run_dir" ]]; do
  run_dir="$runs_root/${run_id}-${n}"
  n=$((n + 1))
done

mkdir -p "$run_dir/streams" "$run_dir/screenshots"

# Seed .meta with starter facts. finalize-run.sh consumes these.
{
  echo "run_id=$(basename "$run_dir")"
  echo "project=$project_root"
  echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "started_epoch_ms=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || date +%s000)"
  echo "framework=$framework"
  echo "command=$command"
} > "$run_dir/.meta"

echo "$run_dir"
