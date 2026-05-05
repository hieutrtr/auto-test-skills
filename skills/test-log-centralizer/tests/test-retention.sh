#!/usr/bin/env bash
# test-retention.sh — T-1.6 acceptance tests for scripts/retain.sh.
#
# Plain bash TAP-style harness (consistent with T-1.1..T-1.5 tests; no bats dep).
# Run:    bash skills/test-log-centralizer/tests/test-retention.sh
# Exit:   0 when all assertions pass, 1 otherwise.
#
# Coverage:
#   T1.6-R1..R18 — see docs/tasks/phase-1/T-1.6-retention.md §4.2.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
RETAIN="$SCRIPTS/retain.sh"
INIT="$SCRIPTS/init-run.sh"
FIN="$SCRIPTS/finalize-run.sh"

PASS=0
FAIL=0
ASSERTIONS=()

ok()   { ASSERTIONS+=("ok   $1");        PASS=$((PASS + 1)); }
fail() { ASSERTIONS+=("FAIL $1: $2");    FAIL=$((FAIL + 1)); }

assert_file()    { [[ -f "$1" ]] && ok "file exists: ${2:-$(basename "$1")}"   || fail "file missing"  "$1"; }
assert_no_file() { [[ ! -e "$1" ]] && ok "no file: ${2:-$(basename "$1")}"     || fail "unexpected file" "$1"; }
assert_dir()     { [[ -d "$1" ]] && ok "dir exists: ${2:-$(basename "$1")}"    || fail "dir missing"   "$1"; }
assert_no_dir()  { [[ ! -e "$1" ]] && ok "no dir: ${2:-$(basename "$1")}"      || fail "unexpected dir" "$1"; }
assert_eq()      { [[ "$2" == "$3" ]] && ok "$1 == $3"                          || fail "$1" "expected '$3', got '$2'"; }
assert_match()   { [[ "$2" =~ $3 ]] && ok "$1 matches /$3/"                     || fail "$1" "value '$2' does not match /$3/"; }

# Pre-check.
[[ -x "$RETAIN" ]] || { fail "retain.sh executable" "$RETAIN not present or not +x"; }
ok "retain.sh present + executable"

TMP_RAW="$(mktemp -d)"
TMP="$(cd "$TMP_RAW" && pwd -P)"
trap 'rm -rf "$TMP_RAW"' EXIT

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# seed_run <runs_root> <run-id-name> <payload-tag>
# Lays down the full T-1.2 file set (run.log + streams/ + screenshots/ +
# run.json + manifest.json + summary.json + meta.json) with deterministic
# content so the gunzip round-trip can be byte-compared.
seed_run() {
  local rr="$1" id="$2" tag="$3" rd="$1/$2"
  mkdir -p "$rd/streams" "$rd/screenshots"
  printf 'unit log %s\n'         "$tag" > "$rd/streams/unit.log"
  printf 'all log %s\n'          "$tag" > "$rd/streams/all.log"
  : > "$rd/screenshots/foo.png"
  printf 'merged log payload %s\n' "$tag" > "$rd/run.log"
  printf '{"run_id":"%s","schema_version":"1","suites":[]}\n' "$id" > "$rd/run.json"
  printf '{"run_id":"%s","schema_version":"1"}\n' "$id" > "$rd/manifest.json"
  printf '{"status":"passed","schema_version":"1"}\n' > "$rd/summary.json"
  printf '{"run_id":"%s","schema_version":"1"}\n' "$id" > "$rd/meta.json"
}

# Generate 12 lex-sortable run-ids (oldest first → newest last).
# Format: YYYYMMDDTHHMMSSZ. We embed an incrementing 2-digit minute stamp so
# the ordering is unambiguous on every platform.
gen_ids_12() {
  for n in 01 02 03 04 05 06 07 08 09 10 11 12; do
    echo "20260101T0100${n}Z"
  done
}
gen_ids_14() {
  for n in 01 02 03 04 05 06 07 08 09 10 11 12 13 14; do
    echo "20260101T0100${n}Z"
  done
}
gen_ids_5() {
  for n in 01 02 03 04 05; do
    echo "20260101T0100${n}Z"
  done
}

# Count run-id-shaped entries (excludes "latest", config.json, etc.).
count_run_dirs() {
  local rr="$1" c=0
  shopt -s nullglob
  for d in "$rr"/*; do
    local b
    b="$(basename "$d")"
    [[ "$b" == "latest" ]] && continue
    [[ -L "$d" ]] && continue
    [[ -d "$d" ]] || continue
    if [[ "$b" =~ ^[0-9]{8}T[0-9]{6}Z(-[0-9]+)?$ ]]; then
      c=$((c + 1))
    fi
  done
  shopt -u nullglob
  echo "$c"
}

# Classify a run dir as "plain" | "gz" | "broken".
# - plain: run.log present, no run.log.gz, streams/ + screenshots/ kept
# - gz:    run.log.gz present, no run.log, streams/ + screenshots/ removed,
#          run.json + manifest.json + summary.json + meta.json preserved
classify() {
  local rd="$1"
  if [[ -f "$rd/run.log" && ! -f "$rd/run.log.gz" && -d "$rd/streams" && -d "$rd/screenshots" ]]; then
    echo plain; return
  fi
  if [[ -f "$rd/run.log.gz" && ! -f "$rd/run.log" && ! -d "$rd/streams" && ! -d "$rd/screenshots"
        && -f "$rd/run.json" && -f "$rd/manifest.json" && -f "$rd/summary.json" && -f "$rd/meta.json" ]]; then
    echo gz; return
  fi
  echo broken
}

# =============================================================================
# T1.6-R2..R11 — 12-run scenario: 10 plain + 2 gz, no pruning, idempotent.
# =============================================================================
RR1="$TMP/run1/.test-runs"
mkdir -p "$RR1"
IDS=()
while IFS= read -r _id; do IDS+=("$_id"); done < <(gen_ids_12)
for id in "${IDS[@]}"; do
  seed_run "$RR1" "$id" "$id"
done
ok "T1.6-R2: seeded 12 fake runs"

# Add a `latest` symlink (most-recent run-id) — must survive retention untouched.
# bash 3.2-safe: no negative array indexing.
LAST_IDX=$(( ${#IDS[@]} - 1 ))
NEWEST_ID="${IDS[$LAST_IDX]}"
( cd "$RR1" && ln -sfn "$NEWEST_ID" latest )
LATEST_BEFORE="$(readlink "$RR1/latest" 2>/dev/null || true)"
assert_eq "T1.6-R2.latest seed" "$LATEST_BEFORE" "$NEWEST_ID"

# Run retention.
RT_E=0
"$RETAIN" "$RR1" >/dev/null 2>&1 || RT_E=$?
assert_eq "T1.6-R3: retain.sh exit" "$RT_E" "0"

assert_eq "T1.6-R4: 12-run total preserved" "$(count_run_dirs "$RR1")" "12"

# Newest 10 (indices 2..11 in IDS, i.e. ids 03..12) are plain.
NEWEST_10=( "${IDS[@]:2:10}" )
for id in "${NEWEST_10[@]}"; do
  cls="$(classify "$RR1/$id")"
  assert_eq "T1.6-R5: $id classified" "$cls" "plain"
done

# Oldest 2 (indices 0,1 → ids 01, 02) are gz.
OLDEST_2=( "${IDS[0]}" "${IDS[1]}" )
for id in "${OLDEST_2[@]}"; do
  cls="$(classify "$RR1/$id")"
  assert_eq "T1.6-R6: $id classified" "$cls" "gz"
  # AC-3 explicit checks (covered by classify, but call out per file):
  assert_file    "$RR1/$id/run.log.gz"     "$id/run.log.gz"
  assert_no_file "$RR1/$id/run.log"        "$id/run.log"
  assert_no_dir  "$RR1/$id/streams"        "$id/streams"
  assert_no_dir  "$RR1/$id/screenshots"    "$id/screenshots"
  assert_file    "$RR1/$id/run.json"       "$id/run.json"
  assert_file    "$RR1/$id/manifest.json"  "$id/manifest.json"
  assert_file    "$RR1/$id/summary.json"   "$id/summary.json"
  assert_file    "$RR1/$id/meta.json"      "$id/meta.json"
done

# T1.6-R8 gunzip round-trip
EXPECTED_PAYLOAD="merged log payload ${OLDEST_2[0]}"
GOT_PAYLOAD="$(gunzip -c "$RR1/${OLDEST_2[0]}/run.log.gz" 2>/dev/null | tr -d '\n')"
assert_eq "T1.6-R8: gunzip round-trip" "$GOT_PAYLOAD" "$EXPECTED_PAYLOAD"

# T1.6-R10: snapshot mtime/sig of every gz file before second pass; we then
# compare after a second retention call to prove no re-work was done.
sig_run_dir() {
  # Output: "<basename>:<inode>:<sizeof-run.log.gz>" for each retained file.
  local rd="$1" b
  b="$(basename "$rd")"
  if [[ -f "$rd/run.log.gz" ]]; then
    # Use python3 for stat (cross-platform) — st_ino + st_size are stable
    # markers that change iff the file was rewritten.
    python3 -c '
import os,sys
p = sys.argv[1]
s = os.stat(p)
print("%s:%d:%d" % (sys.argv[2], s.st_ino, s.st_size))
' "$rd/run.log.gz" "$b"
  fi
}

SIG_BEFORE_2ND=()
for id in "${OLDEST_2[@]}"; do
  SIG_BEFORE_2ND+=("$(sig_run_dir "$RR1/$id")")
done

# Second retention pass — should be no-op.
RT_E2=0
"$RETAIN" "$RR1" >/dev/null 2>&1 || RT_E2=$?
assert_eq "T1.6-R9: idempotent retain.sh exit" "$RT_E2" "0"

SIG_AFTER_2ND=()
for id in "${OLDEST_2[@]}"; do
  SIG_AFTER_2ND+=("$(sig_run_dir "$RR1/$id")")
done

for i in 0 1; do
  assert_eq "T1.6-R10: ${OLDEST_2[$i]} gz signature stable across re-runs" \
    "${SIG_AFTER_2ND[$i]}" "${SIG_BEFORE_2ND[$i]}"
done

# T1.6-R11: latest symlink survives untouched.
LATEST_AFTER="$(readlink "$RR1/latest" 2>/dev/null || true)"
assert_eq "T1.6-R11: latest symlink unchanged" "$LATEST_AFTER" "$LATEST_BEFORE"

# =============================================================================
# T1.6-R12 — 14-run scenario: 10 plain + 2 gz + 2 pruned (oldest 2 ids gone).
# =============================================================================
RR2="$TMP/run2/.test-runs"
mkdir -p "$RR2"
IDS14=()
while IFS= read -r _id; do IDS14+=("$_id"); done < <(gen_ids_14)
for id in "${IDS14[@]}"; do
  seed_run "$RR2" "$id" "$id"
done

RT3_E=0
"$RETAIN" "$RR2" >/dev/null 2>&1 || RT3_E=$?
assert_eq "T1.6-R12.exit retain on 14-run set" "$RT3_E" "0"

# After: oldest 2 deleted (01, 02); next 2 gz (03, 04); newest 10 plain (05..14).
DELETED=( "${IDS14[0]}" "${IDS14[1]}" )
GZED=(    "${IDS14[2]}" "${IDS14[3]}" )
KEPT=(    "${IDS14[@]:4:10}" )

for id in "${DELETED[@]}"; do
  assert_no_dir "$RR2/$id" "T1.6-R12.del:$id"
done
for id in "${GZED[@]}"; do
  cls="$(classify "$RR2/$id")"
  assert_eq "T1.6-R12.gz $id classified" "$cls" "gz"
done
for id in "${KEPT[@]}"; do
  cls="$(classify "$RR2/$id")"
  assert_eq "T1.6-R12.plain $id classified" "$cls" "plain"
done
assert_eq "T1.6-R12.total dirs after prune" "$(count_run_dirs "$RR2")" "12"

# =============================================================================
# T1.6-R13 — < 10 runs: no compaction, no pruning.
# =============================================================================
RR3="$TMP/run3/.test-runs"
mkdir -p "$RR3"
IDS5=()
while IFS= read -r _id; do IDS5+=("$_id"); done < <(gen_ids_5)
for id in "${IDS5[@]}"; do
  seed_run "$RR3" "$id" "$id"
done
"$RETAIN" "$RR3" >/dev/null 2>&1 || true
for id in "${IDS5[@]}"; do
  cls="$(classify "$RR3/$id")"
  assert_eq "T1.6-R13.plain $id" "$cls" "plain"
done
assert_eq "T1.6-R13.count" "$(count_run_dirs "$RR3")" "5"

# =============================================================================
# T1.6-R14 — empty runs_root: no-op.
# =============================================================================
RR4="$TMP/run4/.test-runs"
mkdir -p "$RR4"
RT4_E=0
"$RETAIN" "$RR4" >/dev/null 2>&1 || RT4_E=$?
assert_eq "T1.6-R14.empty exit" "$RT4_E" "0"
assert_eq "T1.6-R14.empty count" "$(count_run_dirs "$RR4")" "0"

# =============================================================================
# T1.6-R15 — non-existent runs_root: exit 0.
# =============================================================================
RT5_E=0
"$RETAIN" "$TMP/does-not-exist/.test-runs" >/dev/null 2>&1 || RT5_E=$?
assert_eq "T1.6-R15.missing root exit" "$RT5_E" "0"

# =============================================================================
# T1.6-R16/R17 — finalize wiring with TEST_LOG_RETAIN env.
# =============================================================================
# For these we use the real init-run.sh + finalize-run.sh. To avoid sleeping 12
# seconds, we (a) call init-run repeatedly (collision suffix appends -N), and
# (b) seed extra fake-run dirs alongside so finalize triggers the threshold.
PROJ="$TMP/proj"
mkdir -p "$PROJ"
"$INIT" "$PROJ" "x" "y" >/dev/null  # produces 1 real run dir (RR exists)
RR_REAL="$PROJ/.test-runs"

# Seed 11 additional fake older runs (lex-smaller ids) so total = 12 plain.
for n in 01 02 03 04 05 06 07 08 09 10 11; do
  seed_run "$RR_REAL" "20250101T0100${n}Z" "fake-$n"
done

# Get the real run dir we just created via init.
REAL_RUN="$(ls -1d "$RR_REAL"/202[6-9]* 2>/dev/null | head -n 1)"
[[ -d "$REAL_RUN" ]] || REAL_RUN="$(ls -1d "$RR_REAL"/2026* 2>/dev/null | head -n 1)"

# T1.6-R16: finalize WITHOUT env var → 12 runs all plain (no compaction).
"$FIN" "$REAL_RUN" 0 0 0 0 0 >/dev/null 2>&1 || true

# Count gz: should be 0.
GZ_COUNT_NO_FLAG=0
for d in "$RR_REAL"/*; do
  [[ -d "$d" ]] || continue
  [[ -L "$d" ]] && continue
  [[ -f "$d/run.log.gz" ]] && GZ_COUNT_NO_FLAG=$((GZ_COUNT_NO_FLAG + 1))
done
assert_eq "T1.6-R16.no flag → no compaction" "$GZ_COUNT_NO_FLAG" "0"

# T1.6-R17: finalize WITH TEST_LOG_RETAIN=1 → triggers retention.
# We need a fresh real run on top so finalize has something to operate on.
sleep 1  # ensure new init produces a distinct ts (or relies on -N suffix)
"$INIT" "$PROJ" "x" "y" >/dev/null
REAL_RUN2="$(ls -1d "$RR_REAL"/2026* | tail -n 1)"
TEST_LOG_RETAIN=1 "$FIN" "$REAL_RUN2" 0 0 0 0 0 >/dev/null 2>&1 || true

# Now we have 13 dirs total (12 fake + 2 real). Retention: keep 10 plain,
# gz next 2, prune 1. Expected gz count: ≥ 1 (oldest fake gz'd).
GZ_COUNT_FLAG=0
for d in "$RR_REAL"/*; do
  [[ -d "$d" ]] || continue
  [[ -L "$d" ]] && continue
  [[ -f "$d/run.log.gz" ]] && GZ_COUNT_FLAG=$((GZ_COUNT_FLAG + 1))
done
[[ "$GZ_COUNT_FLAG" -ge 1 ]] && ok "T1.6-R17.flag → compaction triggered (gz_count=$GZ_COUNT_FLAG)" \
  || fail "T1.6-R17.flag" "expected ≥1 gz, got $GZ_COUNT_FLAG"

# =============================================================================
# T1.6-R18 — retain.sh ignores non-conformant entries (foreign file/dir + latest).
# =============================================================================
RR5="$TMP/run5/.test-runs"
mkdir -p "$RR5"
# 11 lex-sortable run dirs.
for n in 01 02 03 04 05 06 07 08 09 10 11; do
  seed_run "$RR5" "20260101T0100${n}Z" "stray-$n"
done
# Foreign files / dirs that retention must NOT touch.
echo '{"keep":1}' > "$RR5/config.json"
mkdir -p "$RR5/notes"
echo "scratch" > "$RR5/notes/scratch.txt"
( cd "$RR5" && ln -sfn "20260101T010011Z" latest )

"$RETAIN" "$RR5" >/dev/null 2>&1 || true

assert_file "$RR5/config.json"           "T1.6-R18.config.json untouched"
assert_dir  "$RR5/notes"                 "T1.6-R18.notes/ untouched"
assert_file "$RR5/notes/scratch.txt"     "T1.6-R18.notes/scratch.txt untouched"
LATEST5_AFTER="$(readlink "$RR5/latest" 2>/dev/null || true)"
assert_eq   "T1.6-R18.latest preserved"  "$LATEST5_AFTER" "20260101T010011Z"

# 11-run scenario → 10 plain + 1 gz (no pruning at < 13 total).
CLS_GZ_COUNT=0
CLS_PLAIN_COUNT=0
for n in 01 02 03 04 05 06 07 08 09 10 11; do
  c="$(classify "$RR5/20260101T0100${n}Z")"
  case "$c" in
    gz)    CLS_GZ_COUNT=$((CLS_GZ_COUNT + 1));;
    plain) CLS_PLAIN_COUNT=$((CLS_PLAIN_COUNT + 1));;
  esac
done
assert_eq "T1.6-R18.plain count == 10" "$CLS_PLAIN_COUNT" "10"
assert_eq "T1.6-R18.gz    count ==  1" "$CLS_GZ_COUNT"    "1"

# -----------------------------------------------------------------------------
# Report
# -----------------------------------------------------------------------------
echo
for line in "${ASSERTIONS[@]}"; do echo "$line"; done
echo
echo "# test-retention.sh: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
