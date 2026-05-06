#!/usr/bin/env bash
# lint-all.sh — run validate-skill.sh against every skill under skills/*.
#
# Walks ONLY the top-level skills/* tree (does NOT descend into spike/ —
# Phase 0 prototype skill is exempt and validated by spike's own test).
#
# Usage:
#   bash tools/lint-all.sh [skills-root]
#
# Exit:
#   0 — every skill passes hard checks (warnings allowed)
#   1 — at least one skill failed
#   2 — no skills found (likely wrong root)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR="$HERE/validate-skill.sh"

ROOT="${1:-$HERE/../skills}"
ROOT="$(cd "$ROOT" && pwd)"

if [[ ! -d "$ROOT" ]]; then
  echo "lint-all: skills root not found: $ROOT" >&2
  exit 2
fi

shopt -s nullglob
SKILL_DIRS=( "$ROOT"/*/ )
shopt -u nullglob

if [[ ${#SKILL_DIRS[@]} -eq 0 ]]; then
  echo "lint-all: no skill folders under $ROOT" >&2
  exit 2
fi

GLOBAL_FAIL=0
PASSED=0

for d in "${SKILL_DIRS[@]}"; do
  d="${d%/}"
  name="$(basename "$d")"
  echo "==> $name"
  if bash "$VALIDATOR" "$d"; then
    PASSED=$((PASSED + 1))
  else
    GLOBAL_FAIL=$((GLOBAL_FAIL + 1))
  fi
  echo
done

TOTAL=${#SKILL_DIRS[@]}
if [[ "$GLOBAL_FAIL" -eq 0 ]]; then
  echo "# lint-all: $PASSED / $TOTAL skill(s) passed"
  exit 0
else
  echo "# lint-all: $GLOBAL_FAIL / $TOTAL skill(s) FAILED" >&2
  exit 1
fi
