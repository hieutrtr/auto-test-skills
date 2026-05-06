#!/usr/bin/env bash
# tools/tests/run-all.sh — convenience entry point for tools/* test scripts.
# Runs every test-*.sh in this directory in alphabetical order, aggregates
# pass/fail counts, exits non-zero if any script reports failures.
#
# Usage: bash tools/tests/run-all.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

shopt -s nullglob
SCRIPTS=( "$HERE"/test-*.sh )
shopt -u nullglob

if [[ ${#SCRIPTS[@]} -eq 0 ]]; then
  echo "run-all: no test-*.sh found under $HERE" >&2
  exit 1
fi

GLOBAL_FAIL=0
for s in "${SCRIPTS[@]}"; do
  name="$(basename "$s")"
  echo "==> $name"
  if bash "$s"; then
    echo "    [pass] $name"
  else
    echo "    [FAIL] $name"
    GLOBAL_FAIL=$((GLOBAL_FAIL + 1))
  fi
  echo
done

if [[ "$GLOBAL_FAIL" -eq 0 ]]; then
  echo "# run-all: ALL tools test scripts passed"
  exit 0
else
  echo "# run-all: $GLOBAL_FAIL test script(s) FAILED" >&2
  exit 1
fi
