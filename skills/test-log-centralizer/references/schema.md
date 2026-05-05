# test-log-centralizer — JSON contract

> Source-of-truth for the four JSON shapes produced by the three scripts under
> `scripts/`. Downstream skills (`auto-test`, `unit-test-runner`, future
> `browser-test` / `flaky-detector` / `coverage-reporter`) and the
> claude-bridge loop consumer rely on these fields. **Versioned via
> `schema_version` — additive changes bump the minor; breaking changes bump
> the major and require a coordinated migration across all callers.**

Current version: **`schema_version: "1"`**.

## Path layout

```
<project>/.test-runs/
├── <run-id>/                        ← run-id = YYYYMMDDTHHMMSSZ (UTC, sortable; -N suffix on collision)
│   ├── run.log                      ← canonical merged log (per-line ISO-ts prefix)
│   ├── meta.json                    ← init-run.sh: scaffold metadata
│   ├── summary.json                 ← init-run.sh placeholder; finalize-run.sh promotes to final form
│   ├── manifest.json                ← finalize-run.sh: rich index per ARCHITECTURE §(b)
│   ├── run.json                     ← finalize-run.sh placeholder; T-1.4 parsers populate `suites`
│   ├── streams/
│   │   ├── unit.log                 ← per-layer streams; append-log.sh writes here
│   │   ├── integration.log
│   │   ├── browser.log
│   │   ├── orchestrator.log
│   │   ├── skill.log
│   │   ├── setup.log
│   │   ├── teardown.log
│   │   └── all.log                  ← tee of every appended line; live-tail convenience
│   └── screenshots/                 ← browser-test artifacts (Phase 2)
└── latest -> <run-id>               ← symlink updated atomically by finalize-run.sh
```

## `meta.json` — T-1.1 scaffold

Written once by `init-run.sh`; not touched after. All fields are required.

| Field              | Type    | Notes                                                                                                          |
| ------------------ | ------- | -------------------------------------------------------------------------------------------------------------- |
| `schema_version`   | string  | Always `"1"` for now.                                                                                          |
| `run_id`           | string  | `YYYYMMDDTHHMMSSZ` (UTC); collision suffix `-N` appended if dir already exists.                                |
| `start_ts`         | string  | RFC3339 UTC (`YYYY-MM-DDTHH:MM:SSZ`). Whole-second precision.                                                  |
| `started_epoch_ms` | int     | Milliseconds since UNIX epoch. ms-precision via `python3`; falls back to second-precision when unavailable.    |
| `project_dir`      | string  | Absolute, symlink-resolved (`pwd -P`).                                                                         |
| `runner`           | string  | Framework label e.g. `"jest"`, `"vitest"`, `"bun:test"`, or `"tbd"` when caller has not yet detected.           |
| `command`          | string  | Exact runner CLI string. May be empty when caller hasn't decided yet.                                          |

## `summary.json` — final form (T-1.2 finalize)

`init-run.sh` writes a placeholder (status `in_progress`, counts 0). `finalize-run.sh`
overwrites with the **final form** below. This is the file the claude-bridge loop
reads first to make pass/fail/rollback decisions (per ARCHITECTURE §(d)).

| Field            | Type        | Notes                                                                                                                                               |
| ---------------- | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `schema_version` | string      | `"1"`.                                                                                                                                              |
| `status`         | string enum | `"passed"` (exit 0 AND failed 0) ∣ `"failed"` (exit 1 OR failed > 0) ∣ `"error"` (exit 2, e.g. unknown framework, infra error).                      |
| `exit_code`      | int         | The runner's exit code. `0` ok, `1` test failure, `2` error per skill exit-code contract.                                                            |
| `duration_ms`    | int         | `finished_epoch_ms − meta.started_epoch_ms`; floored at 0.                                                                                          |
| `total`          | int         | Total test cases reported. Filled by T-1.4 parsers; placeholder value 0 until then.                                                                |
| `passed`         | int         | Count of `passed`-status cases.                                                                                                                     |
| `failed`         | int         | Count of `failed`-status cases.                                                                                                                     |
| `skipped`        | int         | Count of `skipped` / `pending` cases.                                                                                                               |
| `finished_ts`    | string      | RFC3339 UTC at finalize time.                                                                                                                       |
| `log_path`       | string      | Absolute path to `run.log` (this run's canonical merged log). Loop convenience field; mirrors `manifest.log_path`.                                  |

## `manifest.json` — rich index (T-1.2 finalize)

ARCHITECTURE §(b) defines `manifest.json` as the per-run index. All fields below
are populated unconditionally; downstream skills append optional artifacts via
`artifacts.*` (browser_console, screenshots, flaky_report, coverage_summary,
manual_checklist) — fields are nullable / `[]` until those skills land.

| Field            | Type    | Notes                                                                                                                  |
| ---------------- | ------- | ---------------------------------------------------------------------------------------------------------------------- |
| `schema_version` | string  | `"1"`.                                                                                                                 |
| `run_id`         | string  | Mirror of `meta.run_id`.                                                                                               |
| `project`        | string  | Mirror of `meta.project_dir` (absolute).                                                                              |
| `started_at`     | string  | Mirror of `meta.start_ts`.                                                                                            |
| `finished_at`    | string  | RFC3339 UTC at finalize time (matches `summary.finished_ts`).                                                          |
| `duration_ms`    | int     | Mirror of `summary.duration_ms`.                                                                                      |
| `framework`      | string  | Mirror of `meta.runner` (the same string the detector emitted).                                                       |
| `command`        | string  | Mirror of `meta.command`.                                                                                             |
| `exit_code`      | int     | Same as `summary.exit_code`.                                                                                           |
| `summary`        | object  | `{ total, passed, failed, skipped }` — denormalized for fast loop reads (per ARCHITECTURE §(f)).                       |
| `failed_cases`   | array   | `[{ name, file, error }, ...]` — empty `[]` here; **populated by T-1.4 parsers** in subsequent iter.                   |
| `log_path`       | string  | Absolute path to `run.log`.                                                                                            |
| `artifacts`      | object  | Map of optional artifact keys. `log` / `summary` / `json` always set. Others (`browser_console`, `screenshots`, …) `null`/`[]` until later phases. |
| `layers`         | array   | Subset of `["unit","integration","browser","orchestrator","skill","setup","teardown"]` — only layers with non-empty stream contents. |

### `manifest.summary` shape (denormalized)

```json
{ "total": 42, "passed": 39, "failed": 3, "skipped": 0 }
```

### `manifest.artifacts` shape (Phase 1)

```json
{
  "log": "run.log",
  "summary": "summary.json",
  "json": "run.json",
  "browser_console": null,
  "screenshots": [],
  "flaky_report": null,
  "coverage_summary": null,
  "manual_checklist": null
}
```

## `run.json` — TestRun structured (T-1.4 fills suites)

`finalize-run.sh` writes the placeholder shape below; T-1.4 framework parsers
populate `suites[]`. Schema follows ARCHITECTURE §(f) data model.

```json
{
  "schema_version": "1",
  "run_id": "20260505T142318Z",
  "suites": [
    /* Each entry — produced by parser:
    {
      "name": "Login flow",
      "file": "tests/auth.test.ts",
      "duration_ms": 421,
      "status": "failed",
      "cases": [
        {
          "name": "rejects bad password",
          "status": "failed",
          "duration_ms": 18,
          "error_msg": "expected 401 got 500",
          "error_stack": "..."
        }
      ]
    }
    */
  ]
}
```

## `run.log` — canonical merged log

Plain text, no JSON. Each line: `<RFC3339-UTC ts> <original line>`.
The merge order is fixed (deterministic across re-runs over the same streams):

```
unit → integration → browser → orchestrator → skill → setup → teardown
```

Layers with empty streams are skipped (do **not** appear in `manifest.layers`).
Within a layer, lines preserve insertion order (POSIX `O_APPEND` writes are
atomic for ≤ PIPE_BUF; per-layer single-target eliminates inter-stream
interleaving — see spike concurrent test §B for the proof).

## Atomicity guarantees

- `init-run.sh` writes `meta.json` and `summary.json` placeholder via
  `tmp + mv -f` — kill-9 mid-write cannot leave a half-written file.
- `finalize-run.sh` writes `run.log`, `summary.json`, `manifest.json`,
  `run.json` all via the same tmp-rename pattern.
- `latest` symlink update uses `ln -sfn` — `rename(2)` on Linux,
  `unlink+symlink` on BSD; both end states are atomic from the consumer's
  point of view (either old target or new target, never broken).

## Cross-platform stance (Phase 1)

- macOS BSD + Linux GNU only. No `stat -c`, no `date -d`, no `gzip --keep`,
  no `readlink -f`.
- `python3` is preferred for ms-precision timestamps and JSON escaping; pure
  shell fallback (using `date` and `sed`) keeps scripts functional when
  `python3` is absent (acceptable degradation: second-precision timestamps,
  best-effort string escapes).
- Windows: deferred to Phase 4 (would need `LATEST.txt` fallback + path
  separator handling).

## Versioning policy

- **Additive changes** (new optional field, new artifact slot) → keep
  `schema_version: "1"`. Consumers MUST ignore unknown fields.
- **Breaking changes** (renaming, removing, type change) → bump to `"2"` and
  document the migration here. All scripts and consumers update together.
- Schema version is per-file: `meta`, `summary`, `manifest`, `run` each have
  their own `schema_version`. They happen to all be `"1"` today.
