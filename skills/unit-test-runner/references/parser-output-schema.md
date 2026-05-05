# Parser output schema — canonical `run.json` (Phase 1 / T-1.4)

> The shape produced by `scripts/parse-{jest,vitest,bun}.sh` and consumed
> by `auto-test/scripts/orchestrate.sh` (T-1.5) when populating
> `<project>/.test-runs/<run-id>/run.json` and the rolled-up
> `summary.json` / `manifest.json` (test-log-centralizer T-1.2).
>
> Versioned via `schema_version` — additive changes bump the minor;
> breaking changes bump the major and ripple to all parsers + downstream
> consumers in lockstep.

Current version: **`schema_version: "1"`**.

## Top-level shape

```jsonc
{
  "schema_version": "1",
  "framework": "jest",                    // or "vitest" | "bun"
  "summary": { /* see § Summary */ },
  "failures": [ /* see § Failures */ ],
  "suites":   [ /* see § Suites + Cases */ ]
}
```

Exactly **5 top-level keys**, no extras. Keys are emitted in
`json.dumps(..., sort_keys=True, indent=2)` order so output is
deterministic / byte-equal-comparable across runs and across Python
3.x versions.

## § Summary

```jsonc
{
  "total":       6,    // = passed + failed + skipped
  "passed":      3,
  "failed":      1,
  "skipped":     2,
  "duration_ms": 680   // wall time of the entire run, integer ms ≥ 0
}
```

- `passed`, `failed`, `skipped` are counts of the canonical 3-state enum.
  Statuses below those map onto the 3:

  | Source enum (jest / vitest)  | Source enum (bun) | Canonical |
  |------------------------------|-------------------|-----------|
  | `passed`                     | `pass`            | `passed`  |
  | `failed`                     | `fail`            | `failed`  |
  | `pending` / `todo` / `skipped` / `disabled` | `skip` | `skipped` |

  → Phase 4 will introduce `flaky` (count cases that passed only after
  retry); for Phase 1 it is not produced.

- `duration_ms`:
  - jest / vitest: `max(testResults[].endTime) − startTime`, integer.
  - bun: parsed from `Ran T tests across F files. [WALL.WWms]` line.
- The invariant `passed + failed + skipped == total` is asserted by
  the test suite (T1.4-6).

## § Failures (denormalized)

A flat array of every failed case across every suite, in suite-then-case
order. Empty `[]` when the run has no failures. This is the loop's fast
path: a claude-bridge consumer can `jq '.failures[].message'` without
walking nested suites.

```jsonc
[
  {
    "name":    "Login flow rejects bad password",   // canonical case name
    "file":    "/abs/path/to/auth.test.js",         // file path emitted by the runner
    "message": "Error: expected 401 got 500"         // first line of error_msg
  }
]
```

## § Suites + Cases

```jsonc
[
  {
    "name":        "auth.test.js",       // basename of `file`
    "file":        "/abs/path/to/auth.test.js",
    "duration_ms": 320,
    "status":      "failed",             // "passed" | "failed" | "skipped"
    "cases": [
      {
        "name":        "Login flow rejects bad password",
        "status":      "failed",
        "duration_ms": 18,
        "error_msg":   "Error: expected 401 got 500",
        "error_stack": "Error: expected 401 got 500\n    at Object.<anonymous> (/abs/path/to/auth.test.js:14:7)\n    at TestScheduler._run (...)"
      }
    ]
  }
]
```

### `suite.name` / `suite.file`

- `file` is whatever the runner emits (jest / vitest emit absolute paths;
  bun emits paths relative to the project root).
- `name` is `basename(file)` for the JS frameworks. If the runner did
  not emit a file path, `name = "(unknown)"`.

### `suite.status` rule

- `failed` if **any** case has status `failed`.
- otherwise `passed` if at least one case has status `passed`.
- otherwise (all-skipped / empty) `skipped`.

### `case.name`

- jest: prefer `assertionResults[].fullName`; fallback to
  `ancestorTitles.join(" ") + " " + title` (jest convention).
- vitest: prefer `fullName` (already formatted as `"a > b > c"`);
  fallback to `ancestorTitles.join(" > ") + " > " + title`.
- bun: full name is whatever appears between `(pass|fail|skip)` and the
  `[N.NNms]` duration on the status line.

### `case.duration_ms`

Always integer ≥ 0. Sub-millisecond durations round to nearest int (so
`0.42 ms → 0`, `0.95 ms → 1`). Missing duration → 0. Stored as int (not
float) so JSON diff stays stable across Python releases.

### `case.error_msg` vs `case.error_stack`

- `error_stack` — full multi-line text:
  - jest / vitest: `"\n".join(failureMessages)`.
  - bun: every line buffered between the previous status / file-header
    and the current `(fail)` line — includes source context, the
    `error: …` line, expected/received block, and stack frames.
- `error_msg` — concise single-line summary:
  - jest / vitest: first line of `error_stack`.
  - bun: the `error: …` line within the buffered block; if no such
    line, empty string.
- For non-failed cases both fields are empty string `""`.

## Edge cases

- **Empty input** → all parsers exit 2 with stderr "empty input".
- **Malformed JSON** (jest / vitest) → exit 2 with stderr "invalid JSON".
- **Bun input with no `(pass|fail|skip)` lines AND no summary block** →
  exit 2 with stderr "could not find any test markers in input".
- **Bun verbose-off mode** (passing tests are silent): the parser
  reconciles against the summary `N pass` block by appending synthetic
  `"(implicit pass)"` cases to the first suite so the summary count is
  honored. Callers that need per-pass detail must pass `--verbose` to
  bun.
- **Run with zero tests / framework crashed before a test ran**:
  parsers emit `summary: {total: 0, ...}` + `suites: []` + `failures: []`,
  exit 0. The orchestrator (T-1.5) is responsible for surfacing the
  "no tests ran" signal to the user.

## Why `--json` instead of "TAP" for jest

The plan row 1.4 (`docs/IMPLEMENTATION-PLAN.md`) said "jest TAP". This
parser implements `jest --json` instead. Reasoning:

1. Jest ships **no built-in TAP reporter**; TAP support is via the
   community `jest-tap-reporter` npm package, which adds a runtime dep
   and a setup step every consuming project would need to add.
2. `jest --json` is built-in, well-documented (jestjs.io/docs/cli), and
   the field shape we read (`testResults[].assertionResults[].
   {title, status, duration, failureMessages, ancestorTitles}`) has been
   stable since Jest 22 (~2018).
3. ARCHITECTURE §2 line 27 already states the architecture preference:
   *"Run với JSON reporter nếu có (`--reporter=json`, …)"*. The plan's
   "TAP" wording predates that clarification.

The deviation is logged in `docs/tasks/phase-1/T-1.4-parsers.md` §1 and
the T-1.4 review file.

## Versioning policy

Same rules as `test-log-centralizer/references/schema.md` §Versioning:
additive (new optional field, new artifact slot) keeps `"1"`; breaking
(rename, remove, type change) bumps to `"2"` with cross-skill migration.
