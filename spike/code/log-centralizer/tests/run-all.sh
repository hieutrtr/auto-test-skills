#!/usr/bin/env bash
# run-all.sh — entry point for the T-0.4 test suite. Runs all 3 test files
# in series and aggregates pass/fail counts. Single-command reproducibility.
#
# Usage: spike/code/log-centralizer/tests/run-all.sh
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS=(test-structure.sh test-concurrent.sh test-retrieval.sh)

GLOBAL_FAIL=0
for t in "${TESTS[@]}"; do
  echo "=========================================="
  echo "▶ $t"
  echo "=========================================="
  if "$DIR/$t"; then
    echo "✓ $t passed"
  else
    echo "✗ $t FAILED"
    GLOBAL_FAIL=1
  fi
  echo
done

if [[ $GLOBAL_FAIL -eq 0 ]]; then
  echo "🎉 all T-0.4 test files passed"
  exit 0
else
  echo "❌ at least one T-0.4 test file failed"
  exit 1
fi
