#!/usr/bin/env bash
# parse-bun.sh — convert `bun test` plain-text output to canonical run.json.
#
# Bun has no JSON reporter as of bun 1.3 (oven-sh/bun#11214). The default
# CLI output is a small, deterministic shape:
#
#   bun test v1.x.x (commit-hash)
#                                                 ← blank line
#   <relative/file/path.test.ts>:                 ← suite header
#   (pass) <full case name> [N.NNms]              ← pass line (verbose)
#   (skip) <full case name>                       ← skip line (no duration)
#   <error block — N | code | error: msg | at>    ← preceded by source ctx
#   (fail) <full case name> [N.NNms]              ← fail line (after error)
#                                                 ← blank line between files
#   <next file>:
#   ...
#                                                 ← blank line
#    N pass                                       ← summary block
#    M skip
#    K fail
#    P expect() calls                             ← optional, ignored
#   Ran T tests across F files. [WALL.WWms]      ← run total
#
# Notes:
# - Default reporter is *silent on pass*: passing tests do NOT emit a (pass)
#   line. We rely on the summary block ` N pass` for the pass count when
#   verbose mode is off; per-case pass entries appear only when `--verbose`
#   is set or when stderr/stdout interleaves a (pass) line.
# - For (fail) lines, the preceding error block (until the previous status
#   line or file header) is the error_stack; the line beginning `error:`
#   is the error_msg.
#
# Usage:
#   parse-bun.sh <input-file>           # reads text from <input-file>
#   parse-bun.sh -                      # reads from stdin
#
# Exit 0 OK, exit 2 on bad usage / empty input / unparseable text.
#
# Cross-platform: BSD + GNU; python3 only.
set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: parse-bun.sh <input-file|->" >&2
  exit 2
fi

input="$1"
if [[ "$input" != "-" ]] && [[ ! -f "$input" ]]; then
  echo "parse-bun: not a file: $input" >&2
  exit 2
fi

PY_SCRIPT=$(cat <<'PYEOF'
import json, os, re, sys

path = sys.argv[1]
try:
    raw = sys.stdin.read() if path == "-" else open(path, "r").read()
except Exception as e:
    print(f"parse-bun: cannot read input: {e}", file=sys.stderr); sys.exit(2)
if not raw.strip():
    print("parse-bun: empty input", file=sys.stderr); sys.exit(2)

# Strip ANSI escape sequences (CSI). Bun emits color codes in stderr that
# leak through tee/redirect; the test_log_centralizer pipeline does the
# same, but be defensive — never trust upstream not to colorize.
ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
text = ANSI_RE.sub("", raw)

STATUS_RE = re.compile(r"^\(([a-z]+)\) (.+?)(?: \[([0-9.]+)ms\])?$")
FILE_HEADER_RE = re.compile(r"^([^\s].+?\.(?:test|spec)\.[a-zA-Z]+):$")
SUMMARY_PASS_RE = re.compile(r"^\s+(\d+)\s+pass\s*$")
SUMMARY_SKIP_RE = re.compile(r"^\s+(\d+)\s+skip\s*$")
SUMMARY_FAIL_RE = re.compile(r"^\s+(\d+)\s+fail\s*$")
RUN_TOTAL_RE = re.compile(r"^Ran\s+(\d+)\s+tests?\s+across\s+\d+\s+files?\.\s*\[([0-9.]+)ms\]\s*$")

def norm_status(s):
    if s == "pass":
        return "passed"
    if s == "fail":
        return "failed"
    if s == "skip":
        return "skipped"
    return "skipped"

def to_int_ms(v):
    if v is None or v == "":
        return 0
    try:
        return max(0, int(round(float(v))))
    except (TypeError, ValueError):
        return 0

# State machine: walk lines, group into suites by file header. Buffer
# non-status lines for error capture on (fail).
suites_by_file = {}        # preserves insertion order
suite_order = []
buffer = []
current_file = "(unknown)"
counts = {"passed": 0, "failed": 0, "skipped": 0}
summary_pass = summary_skip = summary_fail = None
run_duration_ms = 0

def open_suite(file_path):
    if file_path not in suites_by_file:
        suites_by_file[file_path] = {
            "name": os.path.basename(file_path) if file_path != "(unknown)" else "(unknown)",
            "file": file_path,
            "cases": [],
            "duration_ms": 0,
            "status": "passed",
        }
        suite_order.append(file_path)

for line in text.splitlines():
    m = FILE_HEADER_RE.match(line.rstrip())
    if m:
        current_file = m.group(1)
        open_suite(current_file)
        buffer = []
        continue

    m = STATUS_RE.match(line.rstrip())
    if m:
        raw_status, full_name, dur = m.group(1), m.group(2), m.group(3)
        status = norm_status(raw_status)
        duration_ms = to_int_ms(dur)
        error_stack = ""
        error_msg = ""
        if status == "failed" and buffer:
            error_stack = "\n".join(buffer).strip("\n")
            err_line = next((b for b in buffer if b.lstrip().startswith("error:")), "")
            error_msg = err_line.strip()
        open_suite(current_file)
        suites_by_file[current_file]["cases"].append({
            "name": full_name.strip(),
            "status": status,
            "duration_ms": duration_ms,
            "error_msg": error_msg,
            "error_stack": error_stack,
        })
        counts[status] = counts.get(status, 0) + 1
        buffer = []
        continue

    m = SUMMARY_PASS_RE.match(line)
    if m:
        summary_pass = int(m.group(1)); buffer = []; continue
    m = SUMMARY_SKIP_RE.match(line)
    if m:
        summary_skip = int(m.group(1)); buffer = []; continue
    m = SUMMARY_FAIL_RE.match(line)
    if m:
        summary_fail = int(m.group(1)); buffer = []; continue
    m = RUN_TOTAL_RE.match(line)
    if m:
        run_duration_ms = to_int_ms(m.group(2)); buffer = []; continue

    # Non-status, non-summary line — accumulate as potential error context.
    if line.strip() == "" and not buffer:
        continue
    buffer.append(line)

# When verbose mode is off, only failed/skip cases show as status lines.
# Reconcile against the summary block: if `summary_pass` > observed pass
# cases, append synthetic placeholder pass cases so totals are correct
# (callers that need per-case detail must run with --verbose).
observed_pass = counts["passed"]
if summary_pass is not None and summary_pass > observed_pass:
    deficit = summary_pass - observed_pass
    # Attach to first suite (or create a synthetic one) — we don't know
    # which file/name. The synthetic cases carry name "(implicit pass)"
    # so they are clearly distinguishable.
    if not suite_order:
        open_suite("(unknown)")
    bucket_file = suite_order[0]
    for _ in range(deficit):
        suites_by_file[bucket_file]["cases"].append({
            "name": "(implicit pass)",
            "status": "passed",
            "duration_ms": 0,
            "error_msg": "",
            "error_stack": "",
        })
        counts["passed"] += 1

# Compute suite status + duration_ms (sum of case durations as approximation).
suites = []
failures = []
for fp in suite_order:
    s = suites_by_file[fp]
    has_fail = any(c["status"] == "failed" for c in s["cases"])
    has_pass = any(c["status"] == "passed" for c in s["cases"])
    if has_fail:
        s["status"] = "failed"
    elif has_pass:
        s["status"] = "passed"
    else:
        s["status"] = "skipped"
    s["duration_ms"] = sum(c["duration_ms"] for c in s["cases"])
    for c in s["cases"]:
        if c["status"] == "failed":
            failures.append({
                "name": c["name"],
                "file": fp,
                "message": c["error_msg"] or "(no error message)",
            })
    suites.append(s)

# Prefer summary-block counts (authoritative) over per-line counts; fall
# back to observed when summary block missing.
total_passed = summary_pass if summary_pass is not None else counts["passed"]
total_failed = summary_fail if summary_fail is not None else counts["failed"]
total_skipped = summary_skip if summary_skip is not None else counts["skipped"]
total = total_passed + total_failed + total_skipped

# Sanity: if no suites, no summary block, and no run total → unparseable.
if not suites and summary_pass is None and run_duration_ms == 0:
    print("parse-bun: could not find any test markers in input", file=sys.stderr)
    sys.exit(2)

doc = {
    "schema_version": "1",
    "framework": "bun",
    "summary": {
        "total": total,
        "passed": total_passed,
        "failed": total_failed,
        "skipped": total_skipped,
        "duration_ms": run_duration_ms,
    },
    "failures": failures,
    "suites": suites,
}
print(json.dumps(doc, indent=2, sort_keys=True))
PYEOF
)
exec python3 -c "$PY_SCRIPT" "$input"
