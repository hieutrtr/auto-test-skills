#!/usr/bin/env bash
# parse-jest.sh — convert Jest's `--json` reporter output to the canonical
# `run.json` shape consumed by `auto-test` + the claude-bridge loop.
#
# Usage:
#   parse-jest.sh <input-file>      # reads JSON from <input-file>
#   parse-jest.sh -                 # reads JSON from stdin
#
# Exit codes:
#   0 — parsed OK; canonical JSON written to stdout
#   2 — bad usage / unreadable input / unparseable JSON
#
# The plan (T-1.4) asked for "jest TAP" but Jest ships no built-in TAP
# reporter; `--json` is built-in and stable across the Jest 22+ line. See
# docs/tasks/phase-1/T-1.4-parsers.md §1 for the rationale.
#
# Cross-platform: BSD + GNU. Uses python3 only (no jq, no node).
set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: parse-jest.sh <input-file|->" >&2
  exit 2
fi

input="$1"
if [[ "$input" != "-" ]] && [[ ! -f "$input" ]]; then
  echo "parse-jest: not a file: $input" >&2
  exit 2
fi

PY_SCRIPT=$(cat <<'PYEOF'
import json, os, sys

path = sys.argv[1]
try:
    raw = sys.stdin.read() if path == "-" else open(path, "r").read()
except Exception as e:
    print(f"parse-jest: cannot read input: {e}", file=sys.stderr); sys.exit(2)
if not raw.strip():
    print("parse-jest: empty input", file=sys.stderr); sys.exit(2)
try:
    j = json.loads(raw)
except Exception as e:
    print(f"parse-jest: invalid JSON: {e}", file=sys.stderr); sys.exit(2)

def norm_status(s):
    if s == "passed":
        return "passed"
    if s == "failed":
        return "failed"
    # pending / todo / skipped / disabled / focused-skipped → "skipped"
    return "skipped"

def first_line(text):
    if not text:
        return ""
    return text.splitlines()[0]

def to_int_ms(v):
    if v is None:
        return 0
    try:
        return max(0, int(round(float(v))))
    except (TypeError, ValueError):
        return 0

suites = []
failures = []
counts = {"passed": 0, "failed": 0, "skipped": 0}

for tr in j.get("testResults", []) or []:
    file_path = tr.get("name", "") or ""
    suite_name = os.path.basename(file_path) if file_path else "(unknown)"
    start = tr.get("startTime") or 0
    end = tr.get("endTime") or 0
    suite_dur = to_int_ms(end - start) if (start and end and end >= start) else 0

    cases = []
    suite_has_fail = False
    suite_has_pass = False
    for ar in tr.get("assertionResults", []) or []:
        status = norm_status(ar.get("status", ""))
        title = ar.get("title", "") or ""
        ancestors = ar.get("ancestorTitles", []) or []
        full_name = ar.get("fullName") or " ".join(ancestors + [title]).strip()
        duration = to_int_ms(ar.get("duration"))
        msgs = ar.get("failureMessages", []) or []
        error_stack = "\n".join(msgs) if msgs else ""
        error_msg = first_line(error_stack) if status == "failed" else ""

        cases.append({
            "name": full_name,
            "status": status,
            "duration_ms": duration,
            "error_msg": error_msg,
            "error_stack": error_stack,
        })
        counts[status] = counts.get(status, 0) + 1
        if status == "failed":
            suite_has_fail = True
            failures.append({
                "name": full_name,
                "file": file_path,
                "message": error_msg or "(no error message)",
            })
        elif status == "passed":
            suite_has_pass = True

    if suite_has_fail:
        suite_status = "failed"
    elif suite_has_pass:
        suite_status = "passed"
    else:
        suite_status = "skipped"

    suites.append({
        "name": suite_name,
        "file": file_path,
        "duration_ms": suite_dur,
        "status": suite_status,
        "cases": cases,
    })

total = counts["passed"] + counts["failed"] + counts["skipped"]
top_start = j.get("startTime") or 0
end_times = [tr.get("endTime") or 0 for tr in (j.get("testResults") or [])]
run_end = max(end_times) if end_times else 0
duration_ms = to_int_ms(run_end - top_start) if (top_start and run_end and run_end >= top_start) else 0

doc = {
    "schema_version": "1",
    "framework": "jest",
    "summary": {
        "total": total,
        "passed": counts["passed"],
        "failed": counts["failed"],
        "skipped": counts["skipped"],
        "duration_ms": duration_ms,
    },
    "failures": failures,
    "suites": suites,
}
print(json.dumps(doc, indent=2, sort_keys=True))
PYEOF
)
exec python3 -c "$PY_SCRIPT" "$input"
