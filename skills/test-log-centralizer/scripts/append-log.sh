#!/usr/bin/env bash
# append-log.sh — append a line (or stdin) to a per-layer stream file with an
# ISO-8601 UTC timestamp prefix. Carries the spike pattern at
# spike/code/log-centralizer/lib/append-log.sh, refit per T-1.2 to:
#   - Always prefix every emitted line with `<RFC3339-UTC-ts> ` so downstream
#     tools (auto-test dashboard, agent grep) can correlate events to wall-clock.
#   - Tee every line into streams/all.log (live-tail convenience).
#
# Usage:
#   append-log.sh <run-dir> <layer> <message>           # inline form
#   <cmd> | append-log.sh <run-dir> <layer>             # stdin form (line-buffered)
#
# Layer whitelist (matches docs/ARCHITECTURE.md §(b) / spike T-0.3 §4):
#   unit | integration | browser | orchestrator | skill | setup | teardown
#
# Atomicity / concurrency:
#   POSIX guarantees `O_APPEND` writes ≤ PIPE_BUF (4096 Linux / 512 macOS) are
#   atomic. We keep one append per call ≤ a single line; long single lines
#   above PIPE_BUF can theoretically interleave under very high concurrency,
#   but for skill-emitted log output this is well below the limit. Per-layer
#   stream files mean exactly one writer-target per logical source, eliminating
#   inter-stream interleaving entirely (carry from spike concurrent test §B).
#
# Cross-platform notes (loop Rule 2):
#   - `date -u +%Y-%m-%dT%H:%M:%SZ` is identical BSD + GNU.
#   - Millisecond precision via `python3 -c 'time.time()'`; falls back to
#     second-precision `date -u +...Z` when python3 is absent.
#   - No `stat -c`, `date -d`, GNU-only flags.
set -uo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: append-log.sh <run-dir> <layer> [message]" >&2
  exit 2
fi

run_dir="$1"
layer="$2"
shift 2

if [[ ! -d "$run_dir" ]]; then
  echo "append-log: run-dir not found: $run_dir" >&2
  exit 1
fi

if [[ ! -d "$run_dir/streams" ]]; then
  echo "append-log: run-dir missing streams/: $run_dir (was init-run.sh called?)" >&2
  exit 1
fi

# Layer whitelist (anchored case match — rejects path-traversal and typos).
case "$layer" in
  unit|integration|browser|orchestrator|skill|setup|teardown) ;;
  *)
    echo "append-log: unknown layer '$layer' (allowed: unit|integration|browser|orchestrator|skill|setup|teardown)" >&2
    exit 1
    ;;
esac

stream_file="$run_dir/streams/${layer}.log"
all_file="$run_dir/streams/all.log"

# Generate ts; prefer ms precision via python3, fall back to s precision via date.
ts() {
  python3 -c '
import time, datetime
t = time.time()
ms = int((t - int(t)) * 1000)
print(datetime.datetime.utcfromtimestamp(int(t)).strftime("%Y-%m-%dT%H:%M:%S") + ".%03dZ" % ms)
' 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ
}

# Single emit: write `<ts> <line>\n` to the per-layer stream and tee to all.log.
# `>>` opens with O_APPEND; one printf == one POSIX write per file.
emit() {
  local _line="$1" _ts
  _ts="$(ts)"
  printf '%s %s\n' "$_ts" "$_line" >> "$stream_file"
  printf '%s %s\n' "$_ts" "$_line" >> "$all_file"
}

if [[ $# -gt 0 ]]; then
  # Inline form: rejoin remaining args with single spaces (consistent with `echo`-like usage).
  emit "$*"
else
  # Stdin form — read line-buffered; each line gets its own ts + append.
  # `IFS= read -r` preserves leading/trailing whitespace and disables `\` escapes.
  while IFS= read -r _line; do
    emit "$_line"
  done
fi
