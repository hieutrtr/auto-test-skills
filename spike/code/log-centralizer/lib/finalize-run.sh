#!/usr/bin/env bash
# finalize-run.sh — merge per-layer streams, write manifest.json + run.json,
# atomically re-point <project>/.test-runs/latest.
#
# Usage:
#   finalize-run.sh <run-dir> <exit-code> [total] [passed] [failed] [skipped]
#
# Spike-grade: enough fields to validate the schema decisions in T-0.3.
# Real Phase 1 will populate failed_cases by parsing framework output.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: finalize-run.sh <run-dir> <exit-code> [total] [passed] [failed] [skipped]" >&2
  exit 2
fi

run_dir="$1"
exit_code="$2"
total="${3:-0}"
passed="${4:-0}"
failed="${5:-0}"
skipped="${6:-0}"

[[ -d "$run_dir" ]] || { echo "finalize: run-dir missing: $run_dir" >&2; exit 1; }
[[ -f "$run_dir/.meta" ]] || { echo "finalize: .meta missing — was start-run.sh called?" >&2; exit 1; }

# Read .meta line-by-line (NOT source — values can contain spaces/quotes
# and we don't want word-splitting or shell expansion of user-supplied
# strings like the original `command`).
get_meta() {
  awk -v k="$1" 'index($0, k"=") == 1 { sub("^"k"=",""); print; exit }' "$run_dir/.meta"
}
project="$(get_meta project)"
started_at="$(get_meta started_at)"
started_epoch_ms="$(get_meta started_epoch_ms)"
framework="$(get_meta framework)"
command="$(get_meta command)"

# Minimal JSON string escape: backslash, double-quote, control chars.
json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1])[1:-1])' "$1" 2>/dev/null \
    || printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
project_j="$(json_escape "$project")"
framework_j="$(json_escape "$framework")"
command_j="$(json_escape "$command")"

finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
finished_epoch_ms="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || date +%s000)"
duration_ms=$(( finished_epoch_ms - started_epoch_ms ))
(( duration_ms < 0 )) && duration_ms=0

# Merge streams in fixed order (T-0.3 §4): unit → integration → browser → orchestrator → skill.
# All other (setup/teardown/unknown) appended last, alphabetic. cat is safe because
# every writer has closed by now.
run_log="$run_dir/run.log"
: > "$run_log"
order=(unit integration browser orchestrator skill setup teardown)
for layer in "${order[@]}"; do
  src="$run_dir/streams/${layer}.log"
  [[ -s "$src" ]] && cat "$src" >> "$run_log"
done

# Collect layers actually used (non-empty stream files).
layers_json="["
first=1
for layer in "${order[@]}"; do
  src="$run_dir/streams/${layer}.log"
  if [[ -s "$src" ]]; then
    if (( first )); then first=0; else layers_json+=","; fi
    layers_json+="\"$layer\""
  fi
done
layers_json+="]"

run_id="$(basename "$run_dir")"

# Write manifest.json atomically (tmp + rename — POSIX atomic).
manifest_tmp="$run_dir/manifest.json.tmp"
manifest_final="$run_dir/manifest.json"
cat > "$manifest_tmp" <<EOF
{
  "schema_version": "1",
  "run_id": "$run_id",
  "project": "$project_j",
  "started_at": "$started_at",
  "finished_at": "$finished_at",
  "duration_ms": $duration_ms,
  "framework": "$framework_j",
  "command": "$command_j",
  "exit_code": $exit_code,
  "summary": {
    "total": $total,
    "passed": $passed,
    "failed": $failed,
    "skipped": $skipped
  },
  "failed_cases": [],
  "log_path": ".test-runs/$run_id/run.log",
  "artifacts": {
    "log": "run.log",
    "json": "run.json",
    "browser_console": null,
    "screenshots": [],
    "flaky_report": null,
    "coverage_summary": null,
    "manual_checklist": null,
    "events": null
  },
  "layers": $layers_json,
  "timeouts": [],
  "redactions_applied": []
}
EOF
mv -f "$manifest_tmp" "$manifest_final"

# Write run.json (minimal v1 — empty suites; Phase 1 fills this).
run_json_tmp="$run_dir/run.json.tmp"
run_json_final="$run_dir/run.json"
cat > "$run_json_tmp" <<EOF
{
  "schema_version": "1",
  "run_id": "$run_id",
  "suites": []
}
EOF
mv -f "$run_json_tmp" "$run_json_final"

# Re-point latest atomically. ln -sfn is rename(2) → POSIX atomic.
runs_root="$(dirname "$run_dir")"
( cd "$runs_root" && ln -sfn "$run_id" latest )

# Best-effort: drop .meta — internal scratch, not part of the contract.
rm -f "$run_dir/.meta"

echo "$run_dir"
