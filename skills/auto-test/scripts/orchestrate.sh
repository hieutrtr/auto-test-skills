#!/usr/bin/env bash
# orchestrate.sh — meta-orchestrator for the auto-test skill. Phase 1 / T-1.5.
#
# Phase 1 delegates exclusively to skills/unit-test-runner/scripts/run.sh
# (the only test layer wired so far). Future phases will add browser /
# integration / coverage layers in parallel and merge results before the
# dashboard render.
#
# Usage:
#   orchestrate.sh <project-root>
#   orchestrate.sh <project-root> --skills-root <path>
#
# Stdout shape:
#   <ASCII box dashboard>
#   <blank line>
#   LATEST=<abs path to run dir>
#   LOG=<abs path to run.log>
#   JSON=<abs path to run.json>
#   EXIT=<0|1|2>
#
# Exit codes (carried from run.sh):
#   0  — all tests passed
#   1  — test failures
#   2  — error (detection / parser / framework crash / unsupported framework)
#
# Cross-platform: BSD + GNU. Bash 3.2+.
set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: orchestrate.sh <project-root> [--skills-root <path>]" >&2
  exit 2
fi

project_root="$1"
shift

self_dir="$(cd "$(dirname "$0")" && pwd -P)"
auto_test_dir="$(cd "$self_dir/.." && pwd -P)"
skills_root="$(cd "$auto_test_dir/.." && pwd -P)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skills-root)
      shift
      skills_root="$(cd "$1" && pwd -P)"
      shift
      ;;
    *)
      echo "orchestrate.sh: unknown arg '$1'" >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$project_root" ]]; then
  echo "orchestrate: project root not found: $project_root" >&2
  exit 2
fi

unit_runner="$skills_root/unit-test-runner/scripts/run.sh"
if [[ ! -x "$unit_runner" ]]; then
  echo "orchestrate: sibling skill not found: $unit_runner" >&2
  echo "orchestrate: pass --skills-root if skills live elsewhere" >&2
  exit 2
fi

# --- delegate to unit-test-runner -----------------------------------------
# run.sh emits the run dir on stdout (one line) and translates framework
# exit through to its own exit code. Stderr streams live to caller.
tmp_stdout="$(mktemp -t autotest_orch_stdout.XXXXXX)"
trap 'rm -f "$tmp_stdout"' EXIT
"$unit_runner" "$project_root" >"$tmp_stdout"
runner_exit=$?
run_dir="$(tail -n 1 "$tmp_stdout" | tr -d '\r\n')"

if [[ -z "$run_dir" || ! -d "$run_dir" ]]; then
  echo "orchestrate: unit-test-runner produced no run dir (exit=$runner_exit)" >&2
  exit 2
fi

# --- render dashboard -----------------------------------------------------
render="$auto_test_dir/scripts/render-dashboard.sh"
if [[ ! -x "$render" ]]; then
  echo "orchestrate: render-dashboard.sh missing or not executable: $render" >&2
  echo "$run_dir"
  exit 2
fi

# render-dashboard.sh prints the box + KEY=value lines and inherits exit code.
"$render" "$run_dir" "$runner_exit"
exit $runner_exit
