#!/usr/bin/env bash
# run-all.sh — invoke every test-*.sh file in this dir alphabetically.
# Phase 1 / T-1.5.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
total_fail=0

for t in "$here"/test-*.sh; do
  [[ -f "$t" ]] || continue
  name="$(basename "$t")"
  echo "=== running $name ==="
  if bash "$t"; then
    echo "=== $name OK ==="
  else
    rc=$?
    echo "=== $name FAIL (rc=$rc) ==="
    total_fail=$((total_fail + 1))
  fi
  echo
done

if [[ "$total_fail" -gt 0 ]]; then
  echo "run-all: $total_fail test file(s) failed"
  exit 1
fi
echo "run-all: all green"
exit 0
