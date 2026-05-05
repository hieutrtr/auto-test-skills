---
name: test-log-centralizer
description: Centralize test-run logs under <project>/.test-runs/<UTC-timestamp>/ so every other testing skill (auto-test, unit-test-runner, browser-test, integration-test-runner, flaky-detector, coverage-reporter) writes into a single shared run folder. Use ONLY as a dependency invoked by another testing skill — it is not user-facing on its own. Trigger when another skill needs to (a) start a new run folder via `scripts/init-run.sh`, (b) append per-layer log lines via `scripts/append-log.sh`, or (c) finalize a run via `scripts/finalize-run.sh`. Do NOT trigger on user phrases like "show me the logs", "tail the logs", "check what tests printed" — those should call `auto-test` (which internally uses this skill) or read `<project>/.test-runs/latest/run.log` directly with the Read tool. Do NOT use this skill for non-test logging (application logs, build output, lint output) — those belong to other tools.
allowed-tools: Bash, Read
---

# test-log-centralizer

Singleton dependency for all testing skills in this repo. Provides a uniform path
convention and three small bash entrypoints under `scripts/` so every test layer
(unit, integration, browser, orchestrator, skill, setup, teardown) writes into the
same `<project>/.test-runs/<run-id>/` folder. Output structure is documented in
`docs/ARCHITECTURE.md` §(b).

## When to use

Activate **only** when invoked as a sub-step of another testing skill — typically
`auto-test`, `unit-test-runner`, `browser-test`, `integration-test-runner`,
`flaky-detector`, or `coverage-reporter`. Concretely:

- A caller skill needs to **start** a fresh run → run `scripts/init-run.sh`.
- A caller skill needs to **append** stdout/stderr to a per-layer stream → run
  `scripts/append-log.sh`. Each emitted line is prefixed with an ISO-8601 UTC
  timestamp (ms-precision when `python3` is available, second-precision otherwise).
- A caller skill needs to **finalize** the run (merge streams → `run.log`,
  emit `summary.json` (final form) + `manifest.json` + `run.json`, re-point
  `latest`) → run `scripts/finalize-run.sh`.

Do **not** activate when the user message is about reading or tailing existing
logs — that is a plain `Read` / `Grep` of `<project>/.test-runs/latest/run.log`
and does not need this skill.

Do **not** activate for non-test logging (general application logs, build output,
lint output, deployment output). Those belong elsewhere.

## How to use

```bash
SKILL_DIR="$(dirname "$0")/.."   # caller adjusts to its own layout

# 1. Start a new run — echoes the absolute run-folder path on stdout.
RUN=$("$SKILL_DIR/scripts/init-run.sh" "<project-root>" "<runner>" "<command>")
# RUN now points to <project-root>/.test-runs/<UTC-ts>/.
# Initial folder contents (T-1.1):
#   run.log          (empty file; finalize-run.sh fills via stream merge)
#   meta.json        (run_id, start_ts, project_dir, runner, command, schema_version)
#   summary.json     (placeholder; finalize-run.sh promotes to final form)
#   streams/         (per-layer log files; written by append-log.sh)
#   screenshots/     (browser-test artifacts — Phase 2)

# 2. Append per-layer log lines.
# Inline form:
"$SKILL_DIR/scripts/append-log.sh" "$RUN" unit "starting suite tests/auth"
# Stdin form (stream a runner's stdout/stderr line-buffered):
bun test 2>&1 | "$SKILL_DIR/scripts/append-log.sh" "$RUN" unit
# Each appended line is also tee-ed to streams/all.log for live tail.

# 3. Finalize — merge streams into run.log, write final summary/manifest/run.json,
# re-point <project>/.test-runs/latest. Counts are caller-supplied (T-1.4 parsers
# fill them later); pass 0/0/0/0 for a placeholder.
"$SKILL_DIR/scripts/finalize-run.sh" "$RUN" "$EXIT_CODE" "$TOTAL" "$PASSED" "$FAILED" "$SKIPPED"
```

The `<runner>` and `<command>` arguments to `init-run.sh` are optional — when
omitted, `meta.runner` defaults to `"tbd"` and `meta.command` to the empty
string. They are filled later by the caller skill once framework detection
has run. See `references/schema.md` for the full JSON shape contract that
downstream skills + agents can rely on.

## Examples

User says: "run the unit tests" → Claude invokes `auto-test`, which calls
`unit-test-runner`, which calls this skill's `init-run.sh` to scaffold the run
folder before spawning the framework.

User says: "show me the latest test log" → Claude does **not** invoke this skill;
it calls `Read` on `<project>/.test-runs/latest/run.log` directly.

## Files

```
scripts/
  init-run.sh           — T-1.1: scaffold run folder + meta.json + summary.json placeholder
  append-log.sh         — T-1.2: per-layer stream append with ISO-8601 UTC ts prefix
  finalize-run.sh       — T-1.2: merge streams → run.log, write summary/manifest/run.json,
                          re-point .test-runs/latest atomically
  retention.sh          — T-1.6 (pending; gz oldest, prune > 10)
references/
  schema.md             — T-1.2: contract for meta.json, summary.json, manifest.json, run.json
tests/
  test-init-run.sh      — T-1.1 acceptance (35 assertions)
  test-append-log.sh    — T-1.2 acceptance (36 assertions)
  test-finalize-run.sh  — T-1.2 acceptance (55 assertions, incl. golden compare)
  goldens/
    manifest.golden.json — normalized golden for finalize-run shape stability
  run-all.sh            — convenience runner; bash run-all.sh exits 0 when everything green
```

## See also

- `docs/ARCHITECTURE.md` §(b) — folder layout, retention policy, `latest` symlink.
- `docs/ARCHITECTURE.md` §(f) — TestRun data-model (`run.json` schema).
- `spike/code/log-centralizer/` — Phase 0 prototype (frozen reference).
