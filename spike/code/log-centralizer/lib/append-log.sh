#!/usr/bin/env bash
# append-log.sh — append a line (or stdin) to a per-layer stream file.
#
# Usage:
#   append-log.sh <run-dir> <layer> <message>
#   echo "line" | append-log.sh <run-dir> <layer>
#
# Per T-0.3 §4: each layer writes to its OWN stream file (streams/<layer>.log)
# so there is exactly one writer per file → no inter-stream interleaving.
# Within a layer (multiple parallel processes appending), POSIX O_APPEND for
# writes ≤ PIPE_BUF is atomic. We deliberately keep one append per call
# small (single line) to stay under that threshold (4096 on Linux, 512 on
# macOS) and document the constraint here.
#
# Side effect: also tees to streams/all.log for "live tail" UX. all.log is a
# convenience; finalize-run.sh re-merges from per-layer files so the canonical
# top-level run.log is reproducible from streams/.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: append-log.sh <run-dir> <layer> [message]" >&2
  exit 2
fi

run_dir="$1"
layer="$2"
shift 2

if [[ ! -d "$run_dir/streams" ]]; then
  echo "append-log: run-dir missing streams/: $run_dir" >&2
  exit 1
fi

# Validate layer (whitelist; reject path-traversal).
case "$layer" in
  unit|integration|browser|orchestrator|skill|setup|teardown) ;;
  *)
    echo "append-log: unknown layer '$layer' (allowed: unit|integration|browser|orchestrator|skill|setup|teardown)" >&2
    exit 1
    ;;
esac

stream_file="$run_dir/streams/${layer}.log"

if [[ $# -gt 0 ]]; then
  # Inline message form. One write per call; trailing newline forces line terminator.
  printf '%s\n' "$*" >> "$stream_file"
else
  # Stdin form — line-buffered; each line is its own append (small write).
  while IFS= read -r line; do
    printf '%s\n' "$line" >> "$stream_file"
  done
fi
