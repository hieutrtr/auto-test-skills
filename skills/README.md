# skills/

Phase 1 ships three Claude Code skills. Drop any subset of these folders into
`~/.claude/skills/` (or the project-local `.claude/skills/`) and restart Claude
Code — they are self-contained and discover each other through shared
filesystem conventions, not imports.

| Skill | Purpose | When Claude triggers it |
|---|---|---|
| [`auto-test/`](auto-test/SKILL.md) | Meta orchestrator: detect → init run folder → invoke `unit-test-runner` → render ASCII dashboard + machine-readable trailer | User says "run the tests" / "run the unit tests" / "ai check tests for me" |
| [`unit-test-runner/`](unit-test-runner/SKILL.md) | JS/TS unit-test framework detector + jest/vitest/bun output parser → canonical `TestRun` JSON | Sub-step of `auto-test`, or direct user ask "what test framework does this repo use?" |
| [`test-log-centralizer/`](test-log-centralizer/SKILL.md) | Singleton dependency: `init-run.sh` / `append-log.sh` / `finalize-run.sh` → every layer writes into one `<project>/.test-runs/<ts>/` folder | Used only by other testing skills; never user-facing |

## Activation order

```
user ──asks── "run the tests"
   ▼
auto-test (meta)
   ├── test-log-centralizer  init-run.sh   ← create .test-runs/<ts>/
   ├── unit-test-runner       detect + run + parse
   ├── test-log-centralizer  append-log.sh + finalize-run.sh
   └── render-dashboard.sh                 ← print ASCII + LATEST=/LOG=/JSON=/EXIT= trailer
```

## Contributor checklist

Before adding or modifying a skill, run:

```bash
bash tools/lint-all.sh           # frontmatter + folder-name + description gate
bash skills/<name>/tests/run-all.sh   # per-skill test suite
```

The linter checks: frontmatter delimiters, `name` + `description` keys, folder
name == `name`, description ≥ 40 chars, body present, and (warn-only) presence
of an anti-pattern hint phrase. See `tools/validate-skill.sh` for the full list
and `spike/skills-survey.md` §5 for the rationale (4-part description template).

## Phase scope

- **Phase 1 (this directory)** — JS / TS / Bun unit testing.
- **Phase 2** — `browser-test/` (Playwright + screenshot capture).
- **Phase 3** — `manual-test-helper/` + multi-runtime parsers (pytest, cargo, go).
- **Phase 4** — flaky detector, coverage reporter, plugin marketplace publish.
