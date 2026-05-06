# Phase 1 — Manual Verify Guide

> Step-by-step recipe for a developer to confirm Phase 1 works **end-to-end on
> their own machine**, exactly as the Phase exit criterion in
> `docs/IMPLEMENTATION-PLAN.md` demands:
>
> > dev `git clone` → drop skill folder → từ Claude Code dispatch
> > "run unit tests" → nhận ASCII summary + path `.test-runs/<ts>/run.log`.
>
> This file replaces the original "PHASE-BROWSER-TEST" placeholder for Phase 1
> (Phase 1 ships **no browser layer** — that lands in Phase 2). It is the
> human gate for **G5 — Skill activation correctness ≥ 90%** (PRD §4 / INDEX
> §8). Automated tests close G1/G4/G6; G5 needs a real Claude Code session
> because skill discovery is non-deterministic black-box behaviour.
>
> Audience: anyone (the user, a teammate, a reviewer) running this on macOS or
> Linux with Claude Code installed.

---

## 0. Prerequisites

- **OS**: macOS (BSD userland) or Linux (GNU userland). Not tested on Windows.
- **Bash 3.2+** (macOS default) — the skills are POSIX-portable; no GNU-only
  flags required.
- **Claude Code CLI** installed and you can launch it from a terminal.
- At least **one of** `bun`, `node + npm`, or a project with `vitest` /
  `jest` / `mocha` configured. The smoke layer in this repo prefers `bun` (T-1.8).
- `git`, `cp`, `mkdir`, `tar`, `gzip` (all base userland).

Optional but recommended:
- `jq` — only used by some smoke transcripts for human-readable JSON; not
  required by any production script.

---

## 1. Install the skills

From a clean checkout:

```bash
git clone https://github.com/<owner>/auto-test-skills /tmp/auto-test-skills
mkdir -p ~/.claude/skills
cp -R /tmp/auto-test-skills/skills/* ~/.claude/skills/
```

Then **fully quit and relaunch** Claude Code (skill discovery happens at
process start; a hot reload is unreliable per spike memo §1 R-A).

Sanity-check the drop **before** restarting Claude Code, so you catch a bad
copy locally instead of through a failed prompt:

```bash
bash /tmp/auto-test-skills/tools/lint-all.sh
# expected last line:
# lint-all: 3 / 3 skill(s) passed
```

If lint fails, do **not** continue — investigate the failing skill first
(missing frontmatter / folder rename / etc.).

---

## 2. Pick a target repository

Use any JS/TS/Bun project you own with at least one passing unit test. If
you do not have one handy, the repo's own bun fixture works:

```bash
TARGET=/tmp/auto-test-skills/skills/unit-test-runner/tests/fixtures/bun
cd "$TARGET"
ls package.json     # must exist
ls bun.lockb 2>/dev/null || echo "(bun lock optional — detector uses package.json hint)"
```

You should see at least `package.json`. The bun fixture has a single
passing test that exercises every step of the pipeline.

---

## 3. Five-prompt skill-activation eval (G5 gate)

Open a Claude Code session **inside the target repo**. Run each prompt below
in a **fresh** session (`/clear` between prompts), so the model has no
memory of prior turns. For each prompt, record whether `auto-test` was
auto-triggered (PASS) or not (FAIL).

| # | Prompt (paste verbatim) | Expected behaviour |
|---|---|---|
| P1 | `run the unit tests`                                   | Claude triggers `auto-test`. Trailing dashboard + `LATEST=`, `LOG=`, `JSON=`, `EXIT=` lines. |
| P2 | `please execute the test suite and tell me what failed` | Same — `auto-test` engaged. |
| P3 | `how are the tests doing?`                              | Same — auto-trigger. |
| P4 | `show me the latest test output`                        | **Should NOT trigger** `auto-test` (it's a `Read` of `.test-runs/latest/`). PASS = no skill invocation. |
| P5 | `lint the code please`                                  | **Should NOT trigger** `auto-test` (lint ≠ test). PASS = no skill invocation. |

Pass criterion: **≥ 4 / 5 correct** = **G5 met** (90 %). Three or fewer
correct = **G5 NOT met**; file an issue with the actual transcript.

If any positive prompt (P1–P3) fails to trigger, retry once. If it still
misses, capture the full assistant turn and the rendered system reminders —
that is the data we need to tune the description in
`skills/auto-test/SKILL.md` (line 3).

---

## 4. Inspect the run output

When P1 (or any positive prompt) succeeds, the assistant should print
(approximately):

```
┌──────────────────────────────────────────────────────────────────┐
│ ✔ ALL  ·  bun                                                    │
├──────────────────────────────────────────────────────────────────┤
│ all 1 test passed                                                │
└──────────────────────────────────────────────────────────────────┘
LATEST=/your/repo/.test-runs/20260506T123456Z
LOG=/your/repo/.test-runs/20260506T123456Z/run.log
JSON=/your/repo/.test-runs/20260506T123456Z/run.json
EXIT=0
```

(Glyph and exact framework label vary — `✔ ALL` for green, `✘ FAIL` for
red, `‼ ERROR` for runner crash.)

Verify on disk:

```bash
ls .test-runs/                                  # ≥ 1 timestamped folder
ls .test-runs/latest/                           # symlink to newest run
cat .test-runs/latest/run.log    | head        # framework's raw stdout
cat .test-runs/latest/run.json   | head        # canonical TestRun JSON
cat .test-runs/latest/manifest.json | head     # run metadata
```

Expected schema highlights (full schema in
`skills/unit-test-runner/references/parser-output-schema.md`):

- `run.json.schema_version` = `1`.
- `run.json.summary.total ≥ 1`, `failed = 0` for the bun fixture.
- `manifest.json.framework` = `"bun"` (or `"jest"` / `"vitest"` for those
  fixtures).
- `manifest.json.duration_ms ≥ 0`.

---

## 5. Negative-path sanity check

Inject a forced failure to confirm the dashboard turns red and `EXIT=1`:

```bash
cd "$TARGET"
cat >> tests/forced-fail.test.ts <<'EOF'
import { test, expect } from "bun:test";
test("intentional fail (manual verify)", () => { expect(1).toBe(2); });
EOF
```

Re-prompt Claude with `run the unit tests`. Expected output:

- Dashboard shows `✘ FAIL` glyph, framework label intact.
- Trailer `EXIT=1`.
- `run.json.summary.failed = 1`.
- A new `.test-runs/<UTC-ts>/` folder distinct from the previous run.

Cleanup:

```bash
rm tests/forced-fail.test.ts
```

---

## 6. Retention sweep (T-1.6)

Optional — verifies the retention helper behaves on your machine:

```bash
# fake-spawn 12 run folders — each ≥ 1 second apart so timestamps differ
for i in $(seq 1 12); do
  bash ~/.claude/skills/test-log-centralizer/scripts/init-run.sh "$TARGET" >/dev/null
  sleep 1
done

ls "$TARGET/.test-runs/" | grep -v latest | wc -l   # 12

bash ~/.claude/skills/test-log-centralizer/scripts/retention.sh "$TARGET"

ls "$TARGET/.test-runs/" | grep -v latest | wc -l   # still 12, because gz keeps the dir
ls "$TARGET/.test-runs/" -1 | grep -v latest | head -2 | \
  while read d; do ls "$TARGET/.test-runs/$d" | grep -c "\.gz$"; done
# expected: each of the 2 oldest dirs has 1 .gz file
```

The helper is non-destructive in plain mode (no `--prune`); see
`skills/test-log-centralizer/scripts/retention.sh --help` and T-1.6 task file
for the prune flag.

---

## 7. Reporting results

If anything in §3, §4, or §5 fails, capture:

1. Output of `bash /tmp/auto-test-skills/tools/lint-all.sh` (proves the drop is intact).
2. Claude Code transcript — full assistant turn + which skills (if any) were invoked.
3. `ls .test-runs/` and the contents of the most recent `manifest.json`.
4. Your OS / shell version (`uname -a`, `bash --version`).

That is enough to triage without you re-running anything.

---

## 8. What is **not** in scope here

- **Browser tests** — Phase 2 lands `browser-test` (Playwright). This guide
  exercises only the Phase 1 unit layer.
- **Multi-runtime** (Python / Rust / Go) — Phase 3.
- **Coverage**, **flaky-detection**, **redact rules** — deferred Phase 4.
- **Windows** — `LATEST` symlink + GNU date are not validated; Phase 4
  Windows pass adds a `LATEST.txt` fallback (per spike memo §6).

If you hit one of these as a blocker, file an issue and reference the phase
in the IMPLEMENTATION-PLAN — do not expect this manual-verify pass to cover it.
