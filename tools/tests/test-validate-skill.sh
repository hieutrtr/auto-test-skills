#!/usr/bin/env bash
# test-validate-skill.sh — T-1.7 acceptance tests for tools/validate-skill.sh
# and tools/lint-all.sh.
#
# Plain bash TAP-style harness (matches the pattern used by every other Phase 1
# test suite). Asserts that:
#   1. all 3 production skills pass the linter (positive cases)
#   2. each negative fixture under tools/tests/fixtures/* fails with exit 1
#   3. lint-all.sh exits 0 over skills/* (regression guard)
#   4. lint-all.sh exits 1 when pointed at the negative-fixture root
#
# Run:    bash tools/tests/test-validate-skill.sh
# Exit:   0 when all assertions pass, 1 otherwise.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
VALIDATOR="$ROOT/tools/validate-skill.sh"
LINT_ALL="$ROOT/tools/lint-all.sh"
SKILLS_ROOT="$ROOT/skills"
FIXTURES="$HERE/fixtures"

PASS=0
FAIL=0
LINES=()

ok()   { LINES+=("ok   $1");   PASS=$((PASS + 1)); }
bad()  { LINES+=("FAIL $1: $2"); FAIL=$((FAIL + 1)); }

# --- T1.7-V1..V3: positive cases — every production skill passes
for skill in test-log-centralizer unit-test-runner auto-test; do
  if bash "$VALIDATOR" "$SKILLS_ROOT/$skill" >/dev/null 2>&1; then
    ok "[T1.7-V$skill] validate-skill.sh PASS on production skill: $skill"
  else
    bad "[T1.7-V$skill]" "validator failed on production skill: $skill"
  fi
done

# --- T1.7-N1..N6: negative fixtures — must each exit non-zero
for defect in no-frontmatter missing-name missing-desc name-mismatch desc-too-short no-body; do
  set +e
  bash "$VALIDATOR" "$FIXTURES/$defect" >/dev/null 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    ok "[T1.7-N-$defect] validator FAIL on defect fixture: $defect (rc=$rc)"
  else
    bad "[T1.7-N-$defect]" "validator unexpectedly passed on defect fixture: $defect"
  fi
done

# --- T1.7-N-arg: missing-arg invocation exits 2
set +e
bash "$VALIDATOR" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 2 ]]; then
  ok "[T1.7-N-arg] validator exits 2 on missing arg"
else
  bad "[T1.7-N-arg]" "expected rc=2, got $rc"
fi

# --- T1.7-N-path: invalid path exits 1
set +e
bash "$VALIDATOR" "$FIXTURES/__does_not_exist__" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 1 ]]; then
  ok "[T1.7-N-path] validator exits 1 on missing folder"
else
  bad "[T1.7-N-path]" "expected rc=1 on missing folder, got $rc"
fi

# --- T1.7-LA1: lint-all.sh exits 0 over real skills/
if bash "$LINT_ALL" "$SKILLS_ROOT" >/dev/null 2>&1; then
  ok "[T1.7-LA1] lint-all.sh PASS over skills/*"
else
  bad "[T1.7-LA1]" "lint-all.sh failed over skills/* (production skills)"
fi

# --- T1.7-LA2: lint-all.sh exits 1 when pointed at fixtures (each defect fixture fails)
set +e
bash "$LINT_ALL" "$FIXTURES" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 1 ]]; then
  ok "[T1.7-LA2] lint-all.sh exits 1 on negative-fixture root"
else
  bad "[T1.7-LA2]" "expected rc=1 on negative-fixture root, got $rc"
fi

# --- T1.7-LA3: lint-all.sh exits 2 when no skills under root
TMP_EMPTY="$(mktemp -d)"
trap "rm -rf '$TMP_EMPTY'" EXIT
set +e
bash "$LINT_ALL" "$TMP_EMPTY" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 2 ]]; then
  ok "[T1.7-LA3] lint-all.sh exits 2 on empty root"
else
  bad "[T1.7-LA3]" "expected rc=2 on empty root, got $rc"
fi

# --- T1.7-DEF: each negative fixture maps to a clearly-named defect (sanity)
for defect in no-frontmatter missing-name missing-desc name-mismatch desc-too-short no-body; do
  if [[ -f "$FIXTURES/$defect/SKILL.md" ]]; then
    ok "[T1.7-DEF-$defect] fixture present"
  else
    bad "[T1.7-DEF-$defect]" "fixture SKILL.md missing"
  fi
done

# --- Print log
echo
for ln in "${LINES[@]}"; do
  echo "$ln"
done
echo
TOTAL=$((PASS + FAIL))
echo "# tests: $PASS pass / $FAIL fail (of $TOTAL)"
[[ "$FAIL" -eq 0 ]]
