#!/usr/bin/env bash
# parse.sh — dispatcher for framework-specific output parsers.
#
# Usage:
#   parse.sh <framework> <input-file|->
#
# <framework> ∈ {jest, vitest, bun}. Routes to scripts/parse-<framework>.sh
# and forwards the input arg. Phase 1 scope; mocha + playwright-runner are
# detected by detect.sh but not yet parsed (Phase 4).
#
# Exit codes:
#   0 — parser succeeded
#   2 — unknown framework / missing args / parser failure (parser's own code)
set -uo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: parse.sh <jest|vitest|bun> <input-file|->" >&2
  exit 2
fi

framework="$1"
input="$2"
here="$(cd "$(dirname "$0")" && pwd)"

case "$framework" in
  jest|vitest|bun)
    exec "$here/parse-$framework.sh" "$input"
    ;;
  mocha|playwright-runner)
    echo "parse: framework '$framework' detection works but parser not yet implemented (Phase 4 scope)" >&2
    exit 2
    ;;
  *)
    echo "parse: unknown framework: '$framework' (expected: jest, vitest, or bun)" >&2
    exit 2
    ;;
esac
