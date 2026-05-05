---
name: auto-test
description: Run a project's automated tests end-to-end and return a single structured report (ASCII dashboard + machine-readable trailing lines + path to .test-runs/<UTC-ts>/run.log). Trigger when the user asks to run, execute, or check the status of a project's tests — phrases like "run the unit tests", "run the tests", "execute the test suite", "ai check tests for me", "run npm test and tell me what failed", or "how are the tests doing?". This is the meta-skill that delegates to layer-specific runners (Phase 1 ships only the `unit-test-runner` child); future phases will add `browser-test`, `integration-test-runner`, and `coverage-reporter` to the same orchestration. Do NOT trigger on "tail the log", "show me the latest test output", or "what does .test-runs/latest contain?" — those are plain `Read` of `<project>/.test-runs/latest/run.log`. Do NOT trigger on lint, typecheck, build, deploy, or coverage-only requests — those belong to other (separate) skills. Do NOT trigger on browser-only / Playwright-with-page.goto navigation requests until the Phase 2 `browser-test` skill ships.
allowed-tools: Bash, Read, Glob, Grep
---

# auto-test

Single entry-point for "run the tests" intents in a JS / TS / Bun project.
Phase 1 wires:

```
detect framework  →  init run folder  →  exec runner (stdout streamed to log)
                                    →  parse runner output → run.json
                                    →  finalize (summary/manifest/run.log + latest)
                                    →  render ASCII dashboard
```

The output is a single dashboard block plus four trailing
`KEY=value` lines (`LATEST=...`, `LOG=...`, `JSON=...`, `EXIT=...`) that
loop / agent consumers can parse without ANSI handling.

## When to use

Activate when a user (or a higher-level orchestrator like a claude-bridge
loop) wants to **run the test suite** of the project at the current
working directory and get a verdict back. Concretely the trigger phrases:

- "run the unit tests", "run the tests", "run npm test"
- "execute the test suite", "kick off tests"
- "ai test this for me", "check that tests still pass"
- "what failed in the last run?" (re-runs the suite — *not* a log read)

Do **not** activate when:

- The user wants to **read** an existing run log — `Read
  <project>/.test-runs/latest/run.log` directly.
- The request is for **lint / type-check / build** — separate concerns.
- The request is for **browser-only** / Playwright navigation tests — Phase 2
  `browser-test` skill (not yet shipped).
- The request is for **coverage thresholds only** — future
  `coverage-reporter` skill.
- The project is Python / Rust / Go / Ruby — Phase 3 multi-runtime
  detectors (not yet shipped).

If detection fails (framework=unknown), this skill exits 2 with a clear
"could not detect a JS/TS test framework" message — do *not* loop or
retry; surface the error to the user.

## How to use

```bash
# This skill is invoked by Claude (or another agent) — there is one
# argument: the project root. Output goes to stdout.
SKILL_DIR="<install-path>/skills/auto-test"

"$SKILL_DIR/scripts/orchestrate.sh" "$PROJECT_ROOT"

# Exit codes:
#   0  — all tests passed
#   1  — at least one test failed
#   2  — error: detection failed, runner crashed, parser failed,
#         unsupported framework, missing dependency
```

The dashboard rendered to stdout looks like:

```
┌──────────────────────────────────────────────────────────────────┐
│  auto-test  ·  run 20260506T0500Z  ·  duration 782ms   ✔ ALL     │
├──────────────────────────────────────────────────────────────────┤
│  Project   : my-app                                              │
│  Framework : bun (auto-detected)                                 │
│  Command   : bun test                                            │
├──────────────────────────────────────────────────────────────────┤
│  UNIT          ✔ 12 passed   ✘ 0 failed    ⚠ 0 skipped            │
├──────────────────────────────────────────────────────────────────┤
│  ARTIFACTS                                                       │
│    log       /abs/path/.test-runs/20260506T0500Z/run.log         │
│    json      /abs/path/.test-runs/20260506T0500Z/run.json        │
│    manifest  /abs/path/.test-runs/20260506T0500Z/manifest.json   │
├──────────────────────────────────────────────────────────────────┤
│  EXIT 0   all 12 tests passed                                    │
└──────────────────────────────────────────────────────────────────┘

LATEST=/abs/path/.test-runs/20260506T0500Z
LOG=/abs/path/.test-runs/20260506T0500Z/run.log
JSON=/abs/path/.test-runs/20260506T0500Z/run.json
EXIT=0
```

When tests fail, a `FAILURES` section lists up to the first 3 failing
cases (name + first 60 chars of error_msg). Beyond 3 the dashboard
emits `(… N more — see run.log)`; the full list is in
`<run-dir>/run.json` under the `failures` array.

## Examples

User: "run the tests" → activate; resolve project root from cwd; emit
dashboard; reply with the box + trailing `LATEST=` etc.

User: "tail the latest test log" → do **not** activate;
`Read <project>/.test-runs/latest/run.log` directly.

User: "what failed in the last run?" → activate (re-runs the suite — the
question implies the user wants the *current* state, not the log).

User: "run the playwright e2e against the dev server" → do **not**
activate; that needs Phase 2 `browser-test`.

## Files

```
SKILL.md
scripts/
  orchestrate.sh          — meta orchestrator: delegates to unit-test-runner/run.sh + render
  render-dashboard.sh     — read manifest/summary/run.json → ASCII box (Phase 1 compact form)
references/
  exit-codes.md           — 0 / 1 / 2 contract (matches PRD §7 + ARCHITECTURE §(g))
tests/
  test-orchestrate.sh     — E2E on a fixture (skips on missing bun)
  test-render-dashboard.sh — pure-fn unit test against a pre-baked run dir
  run-all.sh              — convenience runner
  goldens/
    sample-run/           — handcrafted summary/manifest/run for renderer test
```

## See also

- `docs/PRD.md` §7 — meta-skill terminal report wireframe (we ship the compact Phase-1 form).
- `docs/ARCHITECTURE.md` §2 — `auto-test` row.
- `docs/ARCHITECTURE.md` §(b) — run folder contents this skill consumes.
- `docs/ARCHITECTURE.md` §(g) — exit-code contract.
- `skills/unit-test-runner/` — the only Phase-1 child orchestrated.
- `skills/test-log-centralizer/` — folder layout + finalize contract.
