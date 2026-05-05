---
name: unit-test-runner
description: Detect the JavaScript / TypeScript unit-test framework in a project (Jest, Vitest, bun:test, Mocha, or @playwright/test used as a unit-test runner) and prepare a canonical run command. Trigger when another testing skill — usually `auto-test` — needs to know "what unit-test framework does this repo use, what command should I run, and which JS runtime / package manager (npm, pnpm, yarn, bun) drives it?". Concretely fires on user phrases like "run the unit tests", "what framework do these tests use?", "detect the test runner for this project", or as a sub-step of `auto-test`. Do NOT trigger on "run end-to-end tests" / "browser tests" / "integration tests" / "Playwright e2e tests with a dev server" — those belong to the Phase 2 `browser-test` skill (this skill's `playwright-runner` framework keyword is reserved for `@playwright/test` used WITHOUT browser navigation, i.e. as a generic test runner). Do NOT trigger on Python (pytest), Rust (cargo test), Go (`go test`), Ruby (rspec), or Elixir tests — those are Phase 3 multi-runtime scope. Do NOT trigger on "show me the latest test log" or "tail the run.log" — that is a plain `Read` of `<project>/.test-runs/latest/run.log`. Do NOT trigger on lint, type-check, build, or coverage — coverage belongs to a future `coverage-reporter` skill.
allowed-tools: Bash, Read, Glob, Grep
---

# unit-test-runner

JS/TS unit-test framework detector + canonical-output parser. Phase 1
**T-1.3** ships `scripts/detect.sh` (5-fixture heuristic). Phase 1
**T-1.4** ships the parser layer: `scripts/parse-jest.sh`,
`scripts/parse-vitest.sh`, `scripts/parse-bun.sh`, and the
`scripts/parse.sh` dispatcher — they take a runner's stdout and emit the
canonical `run.json` shape consumed by `auto-test` (T-1.5) and the
claude-bridge loop. A future `scripts/run.sh` (T-1.5 orchestrator wiring)
will chain detect → invoke → parse end-to-end.

## When to use

Activate when a caller (skill or user) needs **only the unit-test layer** of
a JS/TS project. Concretely:

- The user said "run the unit tests" or a paraphrase ("execute the test
  suite", "run npm test", "what does my test runner say?").
- A meta-skill (`auto-test`) is orchestrating a multi-layer run and asks
  this skill for the unit layer.
- A debugging session needs a quick *which framework is in this repo*
  answer — `scripts/detect.sh <root>` returns it as JSON.

Do **not** activate when:

- The request is about end-to-end / browser tests, dev-server-required
  scenarios, screenshot capture, `tests/browser/*.scenario.md`, or any
  Playwright run that calls `page.goto(...)`. Those route to
  `browser-test` (Phase 2). The `playwright-runner` framework keyword in
  this skill refers ONLY to `@playwright/test` used as a unit-style runner
  with no browser navigation.
- The project is Python (pytest), Rust (Cargo), Go (`go test`), Ruby
  (rspec), or Elixir (mix). Those route to Phase 3 multi-runtime
  detectors (not yet built).
- The user wants to *read* an already-finished run log — that is a plain
  `Read` of `<project>/.test-runs/latest/run.log`, not this skill.
- The user wants coverage thresholds, flakiness analysis, or lint /
  type-check output. Different skills (or none yet).

## How to use

### Detect (Phase 1.3)

```bash
# Find this skill's scripts dir relative to the caller — the orchestrator
# typically passes its own SKILL_DIR.
SKILL_DIR="<...>/skills/unit-test-runner"

# Emits one-line JSON on stdout, exit 0 on success (incl. unknown), 2 on
# bad input arg. Read-only; never writes to the project tree.
DETECT_JSON="$("$SKILL_DIR/scripts/detect.sh" "$PROJECT_ROOT")"

# Example output (jest fixture):
# {"command":"npm test","framework":"jest","markers":[
#   "devDep:jest","jest.config.js","script:test","script:test:contains:jest"
# ],"package_manager":"npm","project_dir":"/abs/path/to/jest","runtime":"node",
#  "schema_version":"1","test_script":"jest"}
```

The `framework` field is the routing key. Possible values:

| `framework` | Meaning | Phase 1.4 parser |
|---|---|---|
| `jest`              | Jest in devDeps and/or `jest.config.*` present | `parse-jest.sh` |
| `vitest`            | Vitest in devDeps and/or `vitest.config.*` present | `parse-vitest.sh` |
| `bun`               | `bun:test` (built into Bun runtime) — `bun.lockb`/`bun.lock` + no other framework | `parse-bun.sh` |
| `mocha`             | Mocha in devDeps and/or `.mocharc*` / `mocha.opts` present | (Phase 4 — not in T-1.4) |
| `playwright-runner` | `@playwright/test` in devDeps and/or `playwright.config.*` present | (Phase 4 — not in T-1.4; Phase 2 `browser-test` is the navigation case) |
| `unknown`           | No marker matched | caller falls back to ARCHITECTURE §(e) custom CLAUDE.md path or aborts with exit 2 |

Priority (when multiple markers are present, e.g. monorepo migration):
**vitest > jest > playwright-runner > mocha > bun**. Documented in
`references/framework-detection.md` and asserted by the test suite.

### Parse (Phase 1.4 — landed)

The parser layer accepts the runner's structured / text stdout and emits
the canonical `run.json` shape (5 top-level keys: `schema_version`,
`framework`, `summary`, `failures`, `suites`). See
`references/parser-output-schema.md` for the full contract.

```bash
# Parse a captured stdout file (works with absolute or relative paths).
parsed_json="$("$SKILL_DIR/scripts/parse.sh" "$framework" "$RUN/streams/unit.log")"

# Or stream stdin → parser:
"$command" 2>&1 | "$SKILL_DIR/scripts/parse-${framework}.sh" -
```

Per-framework reporter input shape:

| `framework` | Input format          | How to capture                                |
|-------------|-----------------------|-----------------------------------------------|
| `jest`      | Jest's `--json`       | `jest --json`                                  |
| `vitest`    | Vitest `--reporter=json` | `vitest run --reporter=json`                |
| `bun`       | Default text          | `bun test` (verbose adds per-pass lines)       |

> Why Jest `--json` instead of "TAP" (as the plan listed): Jest ships no
> built-in TAP reporter; `--json` is built-in, documented, stable since
> Jest 22, and aligns with ARCHITECTURE §2's "JSON reporter where
> available" preference. Documented in `references/parser-output-schema.md`.

### Run + parse (Phase 1.5 — pending T-1.5 orchestrator)

The end-to-end flow once `auto-test/scripts/orchestrate.sh` lands:

```bash
# 1. init-run via the log centralizer (T-1.1 done)
RUN=$("$LOG_CENTRALIZER/scripts/init-run.sh" "$PROJECT_ROOT" "$framework" "$command")

# 2. spawn runner with stdout/stderr piped through the centralizer
eval "$command" 2>&1 | "$LOG_CENTRALIZER/scripts/append-log.sh" "$RUN" unit
EXIT=${PIPESTATUS[0]}

# 3. parse stream → canonical run.json (T-1.4)
"$SKILL_DIR/scripts/parse.sh" "$framework" "$RUN/streams/unit.log" > "$RUN/run.json"

# 4. finalize (counts come from parsed summary)
"$LOG_CENTRALIZER/scripts/finalize-run.sh" "$RUN" "$EXIT" $TOTAL $PASSED $FAILED $SKIPPED
```

## Examples

User: "run the unit tests" → Claude routes to `auto-test`, which calls this
skill's `scripts/detect.sh` first (then the matching parser in Phase 1.4).

User: "what test framework does this project use?" → Claude calls
`scripts/detect.sh` directly and reports the `framework` + `command`
fields.

User: "run the playwright e2e against the dev server" → does **not**
activate — that is Phase 2 `browser-test`.

User: "tail .test-runs/latest/run.log" → does **not** activate — plain
`Read` is sufficient.

## Files

```
scripts/
  detect.sh                    — T-1.3: framework + runtime + PM heuristic; emits JSON
  parse.sh                     — T-1.4: dispatcher (jest|vitest|bun → parse-<fw>.sh)
  parse-jest.sh                — T-1.4: jest --json → canonical run.json
  parse-vitest.sh              — T-1.4: vitest --reporter=json → canonical run.json
  parse-bun.sh                 — T-1.4: bun text → canonical run.json
  run.sh                       — T-1.5 (pending): detect + invoke + parse wrapper
references/
  framework-detection.md       — T-1.3: priority order, marker table, edge cases
  parser-output-schema.md      — T-1.4: canonical TestRun/run.json shape, status mapping, deviation rationale
tests/
  run-all.sh                   — T-1.4: convenience runner (alphabetical test-*.sh)
  test-detect.sh               — T-1.3: 6-fixture acceptance suite (~70 assertions)
  test-parsers.sh              — T-1.4: 79-assertion acceptance + branch coverage
  fixtures/
    jest/                      — package.json + jest.config.js + package-lock.json
    vitest/                    — package.json + vitest.config.ts + pnpm-lock.yaml
    bun/                       — package.json + bun.lockb stub + script "bun test"
    mocha/                     — package.json + .mocharc.json + yarn.lock
    playwright-runner/         — package.json + playwright.config.ts + package-lock.json
    unknown/                   — empty (no package.json)
  goldens/                     — T-1.4: per-framework {input, expected.json} pairs
```

## See also

- `docs/ARCHITECTURE.md` §2 — `unit-test-runner` skill purpose + non-overlap.
- `docs/ARCHITECTURE.md` §(e) — Detection heuristic.
- `docs/ARCHITECTURE.md` §(f) — TestRun data model (consumed by Phase 1.4).
- `skills/test-log-centralizer/` — sibling skill; `init-run.sh` /
  `append-log.sh` / `finalize-run.sh` are the I/O contract.
- `references/framework-detection.md` — priority + marker table reference.
