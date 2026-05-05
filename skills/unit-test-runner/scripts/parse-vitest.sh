#!/usr/bin/env bash
# parse-vitest.sh — convert Vitest's `--reporter=json` output to canonical
# `run.json` shape consumed by `auto-test` + claude-bridge loop.
#
# Usage:
#   parse-vitest.sh <input-file>       # reads JSON from <input-file>
#   parse-vitest.sh -                  # reads JSON from stdin
#
# Vitest's JSON reporter format follows Jest's (Vitest documents this
# explicitly), so the assertion shape is near-identical. The differences
# we account for:
#   - vitest emits `fullName` as `"suite > sub > case"` (jest uses spaces);
#     we trust whichever field is present and fall back to ancestorTitles.
#   - vitest has no `numTodoTests` (only `numPendingTests`); we still treat
#     `pending` and `todo` as "skipped" if either appears.
#
# Exit codes:
#   0 — parsed OK; canonical JSON on stdout
#   2 — bad usage / unreadable input / invalid JSON
#
# Cross-platform: BSD + GNU; python3 only (no jq, no node).
set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: parse-vitest.sh <input-file|->" >&2
  exit 2
fi

input="$1"
if [[ "$input" != "-" ]] && [[ ! -f "$input" ]]; then
  echo "parse-vitest: not a file: $input" >&2
  exit 2
fi

PY_SCRIPT=$(cat <<'PYEOF'
import json, os, sys

path = sys.argv[1]
try:
    raw = sys.stdin.read() if path == "-" else open(path, "r").read()
except Exception as e:
    print(f"parse-vitest: cannot read input: {e}", file=sys.stderr); sys.exit(2)
if not raw.strip():
    print("parse-vitest: empty input", file=sys.stderr); sys.exit(2)
try:
    j = json.loads(raw)
except Exception as e:
    print(f"parse-vitest: invalid JSON: {e}", file=sys.stderr); sys.exit(2)

def norm_status(s):
    if s == "passed":
        return "passed"
    if s == "failed":
        return "failed"
    return "skipped"  # pending / todo / skipped → "skipped"

def first_line(t):
    return t.splitlines()[0] if t else ""

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
    has_fail = False
    has_pass = False
    for ar in tr.get("assertionResults", []) or []:
        status = norm_status(ar.get("status", ""))
        title = ar.get("title", "") or ""
        ancestors = ar.get("ancestorTitles", []) or []
        # vitest format `a > b > c`; fallback to joined ancestors + title
        full_name = ar.get("fullName") or " > ".join([*ancestors, title]).strip(" >")
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
            has_fail = True
            failures.append({
                "name": full_name,
                "file": file_path,
                "message": error_msg or "(no error message)",
            })
        elif status == "passed":
            has_pass = True

    if has_fail:
        suite_status = "failed"
    elif has_pass:
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
    "framework": "vitest",
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
