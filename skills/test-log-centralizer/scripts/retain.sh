#!/usr/bin/env bash
# retain.sh — count-based retention sweep over a `<project>/.test-runs/` root.
#
# Policy (per docs/ARCHITECTURE.md §(b) Retention Policy, count form):
#   - Keep the newest 10 run dirs as plain folders (untouched).
#   - The next 2 oldest are compacted: gzip `run.log` → `run.log.gz`, remove
#     `streams/` and `screenshots/`. Preserved: run.json, manifest.json,
#     summary.json, meta.json (and run.log.gz).
#   - Anything older than that (rank 13+) is deleted entirely.
#
# 30-day age-based pruning is deferred to Phase 4 per task spec; Phase 1 is
# count-only.
#
# Usage:
#   retain.sh <runs-root> [--keep-plain N] [--keep-gz M]
#
# Defaults: --keep-plain 10  --keep-gz 2.
#
# Behaviour:
#   - Missing <runs-root>            → exit 0 (no-op).
#   - Empty <runs-root>              → exit 0 (no-op).
#   - `latest` symlink + non-conformant entries (foreign files, dirs whose name
#     doesn't match the run-id pattern) → ignored, never touched.
#   - Idempotent — running twice on the same state is a no-op (no re-gzip,
#     no churn). Safe to wire into `finalize-run.sh` as an opt-in post-step.
#
# Cross-platform notes (loop Rule 2):
#   - Plain `gzip <file>` works on BSD (macOS) + GNU. We never rely on
#     `--keep` / `-k` (BSD-only) or `--rsyncable` (GNU-only).
#   - No `stat -c`, no `date -d`, no `readlink -f`.
#   - Sorting: run-id format `YYYYMMDDTHHMMSSZ[-N]` is lex-sortable; `sort` works.
#
# Exit codes:
#   0  success (incl. all the no-op paths)
#   2  bad usage / unparseable arg
set -uo pipefail

RUN_ID_RE='^[0-9]{8}T[0-9]{6}Z(-[0-9]+)?$'

KEEP_PLAIN=10
KEEP_GZ=2

if [[ $# -lt 1 ]]; then
  echo "usage: retain.sh <runs-root> [--keep-plain N] [--keep-gz M]" >&2
  exit 2
fi

runs_root="$1"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-plain) KEEP_PLAIN="${2:-}"; shift 2 ;;
    --keep-gz)    KEEP_GZ="${2:-}";    shift 2 ;;
    --keep-plain=*) KEEP_PLAIN="${1#--keep-plain=}"; shift ;;
    --keep-gz=*)    KEEP_GZ="${1#--keep-gz=}";       shift ;;
    *)
      echo "retain: unknown arg '$1'" >&2
      exit 2
      ;;
  esac
done

# Validate numeric args.
if ! [[ "$KEEP_PLAIN" =~ ^[0-9]+$ ]] || ! [[ "$KEEP_GZ" =~ ^[0-9]+$ ]]; then
  echo "retain: --keep-plain and --keep-gz must be non-negative integers" >&2
  exit 2
fi

# No-op fast paths.
[[ -e "$runs_root" ]] || exit 0
[[ -d "$runs_root" ]] || exit 0

# --- collect run dirs -----------------------------------------------------
# Build a sorted list (oldest first) of entries whose basename matches the
# run-id regex AND which are real directories (not symlinks like `latest`).
runs=()
shopt -s nullglob
for entry in "$runs_root"/*; do
  base="$(basename "$entry")"
  # Skip symlinks (e.g. `latest`) — they are not run dirs.
  [[ -L "$entry" ]] && continue
  # Must be a directory.
  [[ -d "$entry" ]] || continue
  # Must match the run-id pattern.
  [[ "$base" =~ $RUN_ID_RE ]] || continue
  runs+=("$base")
done
shopt -u nullglob

# Sort lex (== chronological for our id format). bash 3.2-compatible.
if [[ "${#runs[@]}" -gt 0 ]]; then
  IFS=$'\n' sorted=( $(printf '%s\n' "${runs[@]}" | LC_ALL=C sort) )
  unset IFS
else
  sorted=()
fi

total=${#sorted[@]}
[[ "$total" -le "$KEEP_PLAIN" ]] && exit 0   # Nothing to compact.

# Indices:
#   sorted[0 .. (total - KEEP_PLAIN - 1)]                        → "old tail"
#     ├── last KEEP_GZ                                           → gz target
#     └── everything before that                                 → prune
#   sorted[(total - KEEP_PLAIN) .. total - 1]                    → keep plain (newest)
keep_plain_start=$(( total - KEEP_PLAIN ))
gz_start=$(( keep_plain_start - KEEP_GZ ))
[[ "$gz_start" -lt 0 ]] && gz_start=0

# --- prune oldest (rank 13+ in the default config) ---------------
i=0
while [[ "$i" -lt "$gz_start" ]]; do
  victim="$runs_root/${sorted[$i]}"
  rm -rf "$victim"
  i=$((i + 1))
done

# --- gzip the next KEEP_GZ ---------------------------------------
i="$gz_start"
while [[ "$i" -lt "$keep_plain_start" ]]; do
  rd="$runs_root/${sorted[$i]}"
  # Compact run.log → run.log.gz iff the source still exists. If we already
  # have run.log.gz (idempotent re-run), skip without touching the gz file.
  if [[ -f "$rd/run.log" && ! -f "$rd/run.log.gz" ]]; then
    # Atomic compaction: gzip <file> writes <file>.gz and removes <file>.
    # If gzip fails (disk full / read-only), leave both states so a retry
    # on the next finalize can recover.
    if gzip -- "$rd/run.log" 2>/dev/null; then :; else
      echo "retain: gzip failed on $rd/run.log" >&2
    fi
  elif [[ -f "$rd/run.log" && -f "$rd/run.log.gz" ]]; then
    # Defensive: stale plain run.log alongside an existing .gz. Drop the
    # plain one to converge to the policy state.
    rm -f "$rd/run.log"
  fi
  # Drop large auxiliary state regardless of whether we just gzipped or were
  # idempotently re-running.
  [[ -d "$rd/streams" ]]     && rm -rf "$rd/streams"
  [[ -d "$rd/screenshots" ]] && rm -rf "$rd/screenshots"
  i=$((i + 1))
done

exit 0
