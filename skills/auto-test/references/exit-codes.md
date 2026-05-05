# Exit codes — auto-test orchestrator (T-1.5)

The `auto-test/scripts/orchestrate.sh` script (and the unit-layer
delegate `unit-test-runner/scripts/run.sh`) follow a strict
3-value exit-code contract. This is part of the public API a
claude-bridge loop, agent, or shell pipeline can rely on.

| Exit | Meaning | When emitted |
|------|---------|--------------|
| **0** | All tests passed. | Framework returned 0 AND parsed `failed == 0` AND parser succeeded. |
| **1** | Test failures present, run is otherwise healthy. | Framework returned 1 (typical "1+ tests failed") AND parser succeeded. The dashboard's `FAILURES` block lists up to 3; the rest are in `<run-dir>/run.json`. |
| **2** | Error / could not produce a verdict. | Any of: detection failed (framework=unknown), framework crashed (exit ≥ 2), parser failed, mocha / playwright-runner detected (no Phase 1 parser), missing sibling skill, missing centralizer dir, malformed package.json. |

A consumer therefore only needs to special-case **2** as
"infrastructure problem, do not retry blindly"; **0/1** are
ordinary test outcomes. PRD §7's wireframe footer matches this
mapping (`EXIT 0` / `EXIT 1` / `EXIT 2` rendered in the box).

## Why not bubble the framework's exact exit code?

Some frameworks return values like 130 (SIGINT) or 137 (SIGKILL)
that confuse downstream pipes (a script returning 130 may itself
be misinterpreted as user cancel). Collapsing to {0, 1, 2}
gives consumers a clean tri-state without losing information —
the original framework exit is preserved in
`<run-dir>/manifest.json#exit_code` and
`<run-dir>/summary.json#exit_code`.

## Cross-reference

- `docs/PRD.md` §7 — wireframe footer.
- `docs/ARCHITECTURE.md` §(g) — exit-code contract for downstream
  consumers (claude-bridge loop, RemoteTrigger).
- `skills/test-log-centralizer/scripts/finalize-run.sh` — derives
  `summary.status` from the framework exit code (passed / failed / error).
