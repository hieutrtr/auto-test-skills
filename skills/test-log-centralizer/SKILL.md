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
  `scripts/append-log.sh`.
- A caller skill needs to **finalize** the run (merge streams → `run.log`,
  emit `manifest.json` + `run.json`, re-point `latest`) → run
  `scripts/finalize-run.sh`. *(T-1.2 — not yet present in iter T-1.1.)*

Do **not** activate when the user message is about reading or tailing existing
logs — that is a plain `Read` / `Grep` of `<project>/.test-runs/latest/run.log`
and does not need this skill.

Do **not** activate for non-test logging (general application logs, build output,
lint output, deployment output). Those belong elsewhere.

## How to use (T-1.1 surface only)

```bash
# Start a new run — echoes the absolute run-folder path on stdout.
RUN=$("$SKILL_DIR/scripts/init-run.sh" "<project-root>" "<runner>" "<command>")
# RUN now points to <project-root>/.test-runs/<UTC-ts>/.
# The folder contains:
#   run.log          (empty file, append target)
#   meta.json        (run_id, start_ts, project_dir, runner, command, schema_version)
#   summary.json     (placeholder; finalize-run.sh fills counts + status)
#   streams/         (per-layer log files; written by append-log.sh — T-1.2)
#   screenshots/     (browser-test artifacts — T-2.x)
```

The `<runner>` and `<command>` arguments are optional — when omitted, `meta.runner`
defaults to `"tbd"` and `meta.command` to the empty string. They are filled later by
the caller skill once framework detection has run.

## Examples

User says: "run the unit tests" → Claude invokes `auto-test`, which calls
`unit-test-runner`, which calls this skill's `init-run.sh` to scaffold the run
folder before spawning the framework.

User says: "show me the latest test log" → Claude does **not** invoke this skill;
it calls `Read` on `<project>/.test-runs/latest/run.log` directly.

## Files

```
scripts/
  init-run.sh        — T-1.1; this iter
  append-log.sh      — T-1.2 (pending)
  finalize-run.sh    — T-1.2 (pending)
  retention.sh       — T-1.6 (pending)
references/
  schema.md          — T-1.2 (pending; manifest.json + run.json schemas)
tests/
  test-init-run.sh   — T-1.1; this iter (plain-bash TAP harness)
```

## See also

- `docs/ARCHITECTURE.md` §(b) — folder layout, retention policy, `latest` symlink.
- `docs/ARCHITECTURE.md` §(f) — TestRun data-model (`run.json` schema).
- `spike/code/log-centralizer/` — Phase 0 prototype (frozen reference).
