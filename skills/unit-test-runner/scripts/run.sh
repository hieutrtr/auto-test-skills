#!/usr/bin/env bash
# run.sh — orchestrator helper for unit-test-runner. Phase 1 / T-1.5.
#
# Chains the full pipeline:
#   1. detect.sh <project>  → pick framework + command
#   2. test-log-centralizer/init-run.sh  → scaffold run dir
#   3. exec the framework command, piping stdout/stderr through append-log.sh (layer=unit)
#   4. parse.sh <framework> <streams/unit.log>  → run.json
#   5. test-log-centralizer/finalize-run.sh  → counts + summary/manifest/run.json + latest
#
# Usage:
#   run.sh <project-root> [--centralizer-dir <path>]
#
# Outputs on stdout (one absolute path per line):
#   <run-dir>
#
# Exit codes:
#   0 — all tests passed
#   1 — at least one test failed (framework exit 1, parse OK)
#   2 — error: detection failed, framework crashed, parser failed, or unsupported framework
#
# Note for callers (auto-test/scripts/orchestrate.sh): the run-dir is the
# single line on stdout. All other diagnostics + framework output are
# captured into the run dir; nothing else leaks to caller stdout.
#
# Cross-platform: BSD + GNU. Uses bash 3.2+ features (PIPESTATUS, set -o pipefail).
set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: run.sh <project-root> [--centralizer-dir <path>]" >&2
  exit 2
fi

project_root="$1"
shift

# Resolve this script's directory (works under symlink + relative path).
self_dir="$(cd "$(dirname "$0")" && pwd -P)"
skill_dir="$(cd "$self_dir/.." && pwd -P)"
skills_root="$(cd "$skill_dir/.." && pwd -P)"
centralizer_dir="$skills_root/test-log-centralizer"

# Optional override (e.g. when skills are installed under different paths).
while [[ $# -gt 0 ]]; do
  case "$1" in
    --centralizer-dir)
      shift
      centralizer_dir="$1"
      shift
      ;;
    *)
      echo "run.sh: unknown arg '$1'" >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$project_root" ]]; then
  echo "run.sh: project root not found: $project_root" >&2
  exit 2
fi
if [[ ! -x "$self_dir/detect.sh" ]]; then
  echo "run.sh: detect.sh not executable at $self_dir/detect.sh" >&2
  exit 2
fi
if [[ ! -x "$centralizer_dir/scripts/init-run.sh" ]]; then
  echo "run.sh: test-log-centralizer not found or not executable at $centralizer_dir" >&2
  exit 2
fi

# --- 1. detect ------------------------------------------------------------
detect_json="$("$self_dir/detect.sh" "$project_root")"
detect_rc=$?
if [[ "$detect_rc" -ne 0 ]]; then
  echo "run.sh: detect.sh failed (rc=$detect_rc)" >&2
  exit 2
fi

# Pull framework + command via python3 (already a hard dep of parse-*.sh).
read_field() {
  local key="$1"
  python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get(sys.argv[2],''))" \
    "$detect_json" "$key"
}
framework="$(read_field framework)"
command_str="$(read_field command)"
runtime="$(read_field runtime)"

if [[ "$framework" == "unknown" || -z "$framework" ]]; then
  echo "run.sh: framework not detected (project=$project_root)" >&2
  exit 2
fi
if [[ -z "$command_str" ]]; then
  echo "run.sh: detect produced empty command for framework=$framework" >&2
  exit 2
fi

# Phase 1 only parses jest, vitest, bun. mocha + playwright-runner detect but
# do not parse — fail loud at orchestration so we never silently produce a
# zero-suite run.json.
case "$framework" in
  jest|vitest|bun) ;;
  *)
    echo "run.sh: framework '$framework' detected but parser not yet implemented (Phase 4 scope)" >&2
    exit 2
    ;;
esac

# --- 2. init-run ----------------------------------------------------------
run_dir="$("$centralizer_dir/scripts/init-run.sh" "$project_root" "$framework" "$command_str")"
init_rc=$?
if [[ "$init_rc" -ne 0 || -z "$run_dir" ]]; then
  echo "run.sh: init-run.sh failed (rc=$init_rc)" >&2
  exit 2
fi

# --- 3. exec runner, piping into append-log -------------------------------
# We:
#   - run the command from the project root (so framework picks up local config).
#   - merge stderr into stdout so tests' stack-traces also land in unit.log.
#   - PIPESTATUS[0] preserves the framework's own exit code through the pipe.
#   - bun runs in non-color mode (NO_COLOR=1) so the parser does not have to
#     strip every ANSI escape; jest/vitest also honor NO_COLOR.
set -o pipefail
(
  cd "$project_root"
  NO_COLOR=1 FORCE_COLOR=0 CI=1 \
    bash -c "$command_str" 2>&1
) | "$centralizer_dir/scripts/append-log.sh" "$run_dir" unit
framework_exit=${PIPESTATUS[0]}
set +o pipefail

# Handle a few crash-on-startup signals → treat as error (exit 2). The
# canonical heuristic: if the framework returned a fatal exit code (>=2)
# **and** the parser fails to find any markers, escalate to error.
if [[ "$framework_exit" -lt 0 ]]; then
  framework_exit=2
fi

# --- 4. parse stream → run.json ------------------------------------------
unit_log="$run_dir/streams/unit.log"
if [[ ! -s "$unit_log" ]]; then
  echo "run.sh: framework produced no output (stream empty: $unit_log)" >&2
  # Still finalize so the run dir is valid; report error.
  "$centralizer_dir/scripts/finalize-run.sh" "$run_dir" 2 0 0 0 0 >/dev/null || true
  echo "$run_dir"
  exit 2
fi

# parse-*.sh expects the runner's *raw* stdout; our streams/unit.log is
# prefixed with ISO-8601 timestamps from append-log.sh. Strip the prefix
# (first 24 chars + space — `YYYY-MM-DDTHH:MM:SS.MMMZ ` is exactly 25 chars
# including the trailing space when ms-precision is available; second
# precision is 21 chars). Use a sed that handles both.
stripped_log="$run_dir/streams/unit.stripped.log"
sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{3})?Z //' \
  "$unit_log" > "$stripped_log"

run_json="$run_dir/run.json"
parsed_json="$run_dir/streams/parsed.json"
parse_stderr="$run_dir/streams/parse.err.log"
if "$self_dir/parse.sh" "$framework" "$stripped_log" > "$parsed_json" 2>"$parse_stderr"; then
  parse_rc=0
else
  parse_rc=$?
  rm -f "$parsed_json"
fi

# --- 5. extract counts (or default 0/0/0/0 on parse failure) -------------
if [[ "$parse_rc" -eq 0 && -s "$parsed_json" ]]; then
  counts_csv="$(python3 -c '
import json,sys
d = json.load(open(sys.argv[1]))
s = d.get("summary", {}) or {}
print("{},{},{},{}".format(
  int(s.get("total", 0)),
  int(s.get("passed", 0)),
  int(s.get("failed", 0)),
  int(s.get("skipped", 0)),
))
' "$parsed_json" 2>/dev/null)"
  IFS=',' read -r total passed failed skipped <<<"${counts_csv:-0,0,0,0}"
else
  total=0; passed=0; failed=0; skipped=0
fi

# --- 6. finalize ----------------------------------------------------------
# Pass framework exit + counts. finalize-run.sh decides status:
#   exit_code=0 + failed=0 → passed; exit_code=2 → error; else failed.
"$centralizer_dir/scripts/finalize-run.sh" \
  "$run_dir" "$framework_exit" "$total" "$passed" "$failed" "$skipped" >/dev/null
finalize_rc=$?
if [[ "$finalize_rc" -ne 0 ]]; then
  echo "run.sh: finalize-run.sh failed (rc=$finalize_rc)" >&2
  echo "$run_dir"
  exit 2
fi

# finalize-run.sh writes a placeholder run.json (schema_version, run_id,
# suites:[]). Promote our parsed run.json over it so consumers see real
# suites/cases/failures. Preserve finalize's run_id field by merging.
if [[ -s "$parsed_json" ]]; then
  if ! python3 - "$run_json" "$parsed_json" <<'PY'
import json, sys, os
placeholder_path, parsed_path = sys.argv[1], sys.argv[2]
with open(placeholder_path) as f:
    placeholder = json.load(f)
with open(parsed_path) as f:
    parsed = json.load(f)
merged = dict(parsed)
merged["schema_version"] = parsed.get("schema_version") or placeholder.get("schema_version", "1")
if "run_id" in placeholder:
    merged["run_id"] = placeholder["run_id"]
tmp = placeholder_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(merged, f, indent=2, sort_keys=True)
os.replace(tmp, placeholder_path)
PY
  then
    echo "run.sh: failed to merge parsed run.json (using finalize placeholder)" >&2
  fi
fi

echo "$run_dir"

# --- 7. translate framework exit → run.sh exit --------------------------
# Per contract:
#   framework 0  → 0 (passed)
#   framework 1  → 1 (test failures)
#   framework ≥2 → 2 (error / crash)
#   parse failure → 2 (we cannot trust counts)
if [[ "$parse_rc" -ne 0 ]]; then
  exit 2
fi
if [[ "$framework_exit" -eq 0 ]]; then
  exit 0
elif [[ "$framework_exit" -eq 1 ]]; then
  exit 1
else
  exit 2
fi
