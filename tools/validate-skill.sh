#!/usr/bin/env bash
# validate-skill.sh — SKILL.md frontmatter linter for the auto-test-skills repo.
#
# Asserts that a skill folder satisfies Claude Code's discovery preconditions:
#   1. folder exists
#   2. SKILL.md at folder root
#   3. file starts with YAML frontmatter delimiter (---)
#   4. closing frontmatter delimiter present
#   5. frontmatter has `name:` field
#   6. frontmatter has `description:` field
#   7. frontmatter `name` value matches the folder basename
#   8. description first-line length >= 40 chars (Claude routing heuristic)
#   9. body content present after frontmatter
#  10. (warn-only) description contains an anti-pattern hint phrase ("Do NOT",
#      "do not", "not for") so Claude is less likely to over-trigger
#
# Ported from spike/code/tests/validate-skill.sh (T-0.2). The spike copy stays
# frozen under spike/** (loop no-touch). This copy is the project-shipped
# linter referenced from skills/README.md and used by tools/lint-all.sh.
#
# Usage:
#   bash tools/validate-skill.sh <path-to-skill-folder>
#
# Exit codes:
#   0 — all hard checks pass (warnings allowed)
#   1 — one or more hard checks failed
#   2 — input arg missing or path invalid

set -u

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <skill-folder>" >&2
  exit 2
fi

SKILL_DIR="$1"
SKILL_FILE="$SKILL_DIR/SKILL.md"
FOLDER_NAME="$(basename "$SKILL_DIR")"

PASS=0
FAIL=0
WARN=0
report() {
  local status="$1"; shift
  local msg="$*"
  case "$status" in
    PASS) printf "  PASS  %s\n" "$msg"; PASS=$((PASS + 1)) ;;
    FAIL) printf "  FAIL  %s\n" "$msg"; FAIL=$((FAIL + 1)) ;;
    WARN) printf "  WARN  %s\n" "$msg"; WARN=$((WARN + 1)) ;;
  esac
}

echo "validate-skill.sh — checking $SKILL_DIR"

# Check 1: folder exists
if [[ -d "$SKILL_DIR" ]]; then
  report PASS "skill folder exists: $SKILL_DIR"
else
  report FAIL "skill folder not found: $SKILL_DIR"
  echo; echo "summary: $PASS pass / $FAIL fail / $WARN warn"
  exit 1
fi

# Check 2: SKILL.md exists at root
if [[ -f "$SKILL_FILE" ]]; then
  report PASS "SKILL.md exists at root"
else
  report FAIL "SKILL.md not found at root: $SKILL_FILE"
  echo; echo "summary: $PASS pass / $FAIL fail / $WARN warn"
  exit 1
fi

# Check 3: file starts with --- (YAML frontmatter delimiter)
FIRST_LINE="$(head -n1 "$SKILL_FILE")"
if [[ "$FIRST_LINE" == "---" ]]; then
  report PASS "starts with YAML frontmatter delimiter (---)"
else
  report FAIL "first line is not '---' (got: '$FIRST_LINE')"
  echo; echo "summary: $PASS pass / $FAIL fail / $WARN warn"
  exit 1
fi

# Extract frontmatter block (between first two --- lines)
FM_END_LINE="$(awk '/^---$/{n++; if(n==2){print NR; exit}}' "$SKILL_FILE")"
if [[ -z "$FM_END_LINE" ]]; then
  report FAIL "closing frontmatter delimiter (---) not found"
  echo; echo "summary: $PASS pass / $FAIL fail / $WARN warn"
  exit 1
fi
FRONTMATTER="$(sed -n "2,$((FM_END_LINE - 1))p" "$SKILL_FILE")"

# Check 4: name field present
NAME_LINE="$(printf '%s\n' "$FRONTMATTER" | grep -E '^name:' || true)"
if [[ -n "$NAME_LINE" ]]; then
  report PASS "frontmatter has 'name' field"
else
  report FAIL "frontmatter missing 'name' field"
fi

# Check 5: description field present
DESC_LINE="$(printf '%s\n' "$FRONTMATTER" | grep -E '^description:' || true)"
if [[ -n "$DESC_LINE" ]]; then
  report PASS "frontmatter has 'description' field"
else
  report FAIL "frontmatter missing 'description' field"
fi

# Check 6: name value matches folder name
NAME_VALUE="$(printf '%s\n' "$NAME_LINE" | sed -E 's/^name:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/')"
if [[ -n "$NAME_VALUE" && "$NAME_VALUE" == "$FOLDER_NAME" ]]; then
  report PASS "frontmatter name ('$NAME_VALUE') matches folder name ('$FOLDER_NAME')"
else
  report FAIL "frontmatter name ('$NAME_VALUE') does not match folder name ('$FOLDER_NAME')"
fi

# Check 7: description first-line length is non-trivially long
DESC_VALUE="$(printf '%s\n' "$DESC_LINE" | sed -E 's/^description:[[:space:]]*//')"
DESC_LEN=${#DESC_VALUE}
if [[ "$DESC_LEN" -ge 40 ]]; then
  report PASS "description length OK ($DESC_LEN chars >= 40)"
else
  report FAIL "description too short ($DESC_LEN chars < 40) — Claude routing may miss this skill"
fi

# Check 8: body content after frontmatter
BODY_FIRST="$(sed -n "$((FM_END_LINE + 1)),\$p" "$SKILL_FILE" | grep -m1 -v '^[[:space:]]*$' || true)"
if [[ -n "$BODY_FIRST" ]]; then
  report PASS "body content present after frontmatter"
else
  report FAIL "body is empty after frontmatter"
fi

# Check 9 (warn-only): description contains anti-pattern hint per
# spike/skills-survey.md §5 ("Do NOT", "do not", "not for"). Skills that fire
# in narrow contexts benefit from explicit anti-pattern phrasing — Claude is
# more accurate when told what NOT to trigger on.
if printf '%s' "$DESC_VALUE" | grep -qE 'Do NOT|do not|not for'; then
  report PASS "description contains anti-pattern hint phrase"
else
  report WARN "description has no anti-pattern hint phrase ('Do NOT' / 'do not' / 'not for') — over-triggering risk"
fi

echo
echo "summary: $PASS pass / $FAIL fail / $WARN warn"
[[ "$FAIL" -eq 0 ]]
