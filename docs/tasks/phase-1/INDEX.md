# Phase 1 — MVP Core Skills · INDEX

> Bootstrap doc cho Phase 1 (MVP). Liệt kê 8 atomic task (T-1.1..T-1.8), dependency graph,
> TDD strategy per task, file inventory, exit criteria. Source: `docs/IMPLEMENTATION-PLAN.md`
> Phase 1, `docs/ARCHITECTURE.md` §(a)–(f), `docs/PRD.md` §3–§4, `spike/PHASE-0-COMPLETE.md`,
> `spike/spike-memo.md`.

---

## 1. Mục tiêu Phase 1

Ship 3 skill end-to-end cho stack JS/Bun:

1. **`test-log-centralizer`** — singleton dependency cung cấp `init-run` / `append-log` /
   `finalize-run` để mọi skill khác share log folder duy nhất ở `<project>/.test-runs/<ts>/`.
2. **`unit-test-runner`** — detect framework (jest, vitest, bun:test, mocha,
   playwright-runner) → spawn runner → parse output (jest TAP, vitest JSON, bun text) →
   emit canonical `TestRun` JSON.
3. **`auto-test`** — meta orchestrator: detect → invoke runner → centralize log → render
   ASCII dashboard + emit `manifest.json` + `run.json` cho loop consumer.

**Phase exit (từ `IMPLEMENTATION-PLAN.md`)**: dev `git clone` → drop skill folder → từ
Claude Code dispatch "run unit tests" → nhận lại ASCII summary + path
`.test-runs/<ts>/run.log`. 3 fixture project (Bun, npm, vitest) pass.

---

## 2. 8 Atomic Task — Summary Table

| # | Task | AC (verbatim từ plan) | Dep | Risk | Est |
|---|---|---|---|---|---|
| 1.1 | `test-log-centralizer/SKILL.md` + `init-run.sh` tạo folder + `manifest.json` skeleton | Unit test 3 sample project tạo folder đúng format | 0.5 | Concurrent run conflict | 1 iter |
| 1.2 | `append-log.sh` + `finalize-run.sh` (tính duration, update manifest) | Snapshot test JSON match golden file | 1.1 | — | 1 iter |
| 1.3 | `unit-test-runner/SKILL.md` + framework detector | 5 fixture (jest, vitest, bun, mocha, playwright-runner) detect đúng | 1.1 | Heuristic miss edge case | 1 iter |
| 1.4 | Output parser cho 3 framework (jest TAP, vitest JSON, bun text) → canonical `TestRun` JSON | Parser unit test ≥ 90 % coverage, golden output 3 framework | 1.3 | Framework đổi format giữa version | 1 iter |
| 1.5 | `auto-test/SKILL.md` (meta) — detect → invoke runner → centralize log → render summary | E2E: chạy trên fixture, output dashboard ASCII + path `.test-runs/` đúng | 1.2, 1.4 | Meta-skill không invoke được sub-skill | 1 iter |
| 1.6 | Retention helper: keep last 10 runs, gz cũ | Test 12 fake run → còn 10 + 2 gz | 1.2 | — | 1 iter |
| 1.7 | Doc `skills/<name>/SKILL.md` chuẩn frontmatter, update README install | Drop vào `~/.claude/skills/` → Claude pick up | 1.5 | — | 1 iter |
| 1.8 | Smoke test trên 3 repo thực (Bun, npm, vitest) | 3/3: agent dispatch → log appear → pass/fail accurate | 1.5 | Pre-test setup phức tạp | 1 iter |

Per-task task file: `docs/tasks/phase-1/T-1.<N>-<slug>.md`.
Per-task review file: `docs/tasks/phase-1/T-1.<N>-review.md`.
Per-task commit (no push) per loop Rule 4.

---

## 3. Dependency Graph

```
Phase 0 sign-off (fe9a0f5)
        │
        ▼
T-1.1 (init-run.sh + log-centralizer SKILL.md)
        │
        ├──> T-1.2 (append-log.sh + finalize-run.sh + golden snapshot)
        │       │
        │       ├──> T-1.6 (retention helper: gz oldest, drop > 10)
        │       │
        │       └──> T-1.5 (auto-test meta) ◄── also requires T-1.4
        │                   │
        │                   ├──> T-1.7 (frontmatter lint + README install update)
        │                   │       │
        │                   │       └──> T-1.8 (smoke test 3 real repos)
        │                   │
        │                   └─── E2E exit-criteria gate
        │
        └──> T-1.3 (unit-test-runner SKILL.md + framework detector + 5 fixtures)
                    │
                    └──> T-1.4 (output parser jest/vitest/bun + goldens)
                                │
                                └──> T-1.5 (see above)
```

Critical path: **1.1 → 1.2 → 1.3 → 1.4 → 1.5 → 1.7 → 1.8** (7 sequential).
Parallel-friendly: **1.6** can run after 1.2 in parallel with 1.3+1.4 if iters are split.

In this loop we execute one task per iteration — no parallelism — keeping dep order strict.

---

## 4. TDD Strategy per Task

Loop Rule 2 (TDD strict). Each task lands tests **first** (RED), then implementation (GREEN),
then commit. Test runner picks per task — chosen for minimal install friction:

| Task | Test framework | Test surface | Coverage / criteria |
|---|---|---|---|
| 1.1 | **bats-core** (POSIX-portable shell) | Folder shape: `streams/`, `screenshots/`, `.meta`, `manifest.json` skeleton fields | 3 fixture (empty repo, repo w/ existing `.test-runs/`, parallel-spawn collision) — assert run-id format `YYYYMMDDTHHMMSSZ`, no overwrite |
| 1.2 | **bats-core** + golden JSON | `append-log` per-layer write atomicity; `finalize-run` JSON output match golden | Snapshot `manifest.json` for fixed input; assert `duration_ms ≥ 0`, `summary` shape, `latest` symlink re-pointed |
| 1.3 | **bats-core** | Detector: 5 fixture project under `skills/unit-test-runner/tests/fixtures/{jest,vitest,bun,mocha,playwright-runner}/` (each w/ minimal `package.json` + lockfile) | Each fixture → detector outputs correct `{framework, runtime, command}`. Plus negative: empty project → `unknown` |
| 1.4 | **bats-core** + golden text/JSON | Parser: feed canned stdout (jest TAP, vitest `--reporter=json`, bun text) → assert canonical `TestRun` JSON shape (`schema_version`, `suites[].cases[]`) | Golden compare for 3 framework; ≥ 90 % branch coverage measured by counting which case-status branches (pass/fail/skip/timeout) hit |
| 1.5 | **bats-core** E2E + manual ASCII compare | E2E on `tests/fixtures/bun-pass/` and `tests/fixtures/jest-fail/` (use 1.3 fixtures): orchestrator writes `.test-runs/<ts>/{run.log,run.json,manifest.json}` and prints dashboard with `LATEST=`, `LOG=`, `JSON=` trailing lines | Assert exit code 0/1, `run.json.summary` correct, `latest` symlink valid |
| 1.6 | **bats-core** | Seed 12 fake run dirs (touch + sleep stagger) → invoke retention → list result | Exact: 10 plain dirs remain, 2 oldest gz'd (`run.log.gz` + `screenshots/` removed), `run.json` + `manifest.json` retained per ARCHITECTURE §(b) |
| 1.7 | `validate-skill.sh` (carry-over from spike T-0.2) + markdown lint | Frontmatter shape: `name`, `description` (≥ 40 chars, has trigger phrase + anti-pattern per skills-survey §5), folder name == `name` | All 3 skills pass; README install snippet exists + ≤ 5-line; manual-verify gate from spike memo §1 documented |
| 1.8 | Smoke harness `skills/auto-test/tests/smoke.sh` | Clone (or symlink) 3 throwaway repos: Bun project (e.g. small public Bun fixture), npm project, vitest project. Invoke `auto-test` → assert log folder appears, exit code matches truth | If sandbox cannot fetch network repos, fall back to **3 local fixtures** under `skills/auto-test/tests/smoke-repos/` and document manual-run procedure |

**Cross-cutting**: Loop Rule 2 line 9 — scripts must be cross-platform (macOS + Linux); avoid GNU-only flags (`stat -c`, `date -d`, `gzip --keep` when not needed). Spike already established BSD-compatible patterns (`date -u +%Y%m%dT%H%M%SZ`, `python3` fallback for ms epoch).

---

## 5. File Inventory (delivered by end of Phase 1)

```
auto-test-skills/
├── README.md                                  (updated install section, ≤ 5-line snippet — T-1.7)
├── skills/
│   ├── test-log-centralizer/
│   │   ├── SKILL.md                           (T-1.1 frontmatter; body = how-to-invoke)
│   │   ├── scripts/
│   │   │   ├── init-run.sh                    (T-1.1; port from spike start-run.sh)
│   │   │   ├── append-log.sh                  (T-1.2; port from spike)
│   │   │   ├── finalize-run.sh                (T-1.2; port from spike, golden-tested)
│   │   │   └── retention.sh                   (T-1.6; gz + prune)
│   │   ├── references/
│   │   │   └── schema.md                      (T-1.2; manifest.json + run.json schemas)
│   │   └── tests/
│   │       ├── test-init-run.bats             (T-1.1)
│   │       ├── test-append-log.bats           (T-1.2)
│   │       ├── test-finalize-run.bats         (T-1.2; golden compare)
│   │       ├── test-retention.bats            (T-1.6)
│   │       └── goldens/
│   │           └── manifest.golden.json       (T-1.2)
│   ├── unit-test-runner/
│   │   ├── SKILL.md                           (T-1.3 frontmatter)
│   │   ├── scripts/
│   │   │   ├── detect.sh                      (T-1.3; framework heuristic)
│   │   │   ├── parse-jest.sh                  (T-1.4; jest TAP → run.json)
│   │   │   ├── parse-vitest.sh                (T-1.4; vitest --reporter=json → run.json)
│   │   │   ├── parse-bun.sh                   (T-1.4; bun test text → run.json)
│   │   │   └── run.sh                         (T-1.4; detect + invoke + parse)
│   │   ├── references/
│   │   │   ├── framework-detection.md         (T-1.3)
│   │   │   └── parser-output-schema.md        (T-1.4)
│   │   └── tests/
│   │       ├── test-detect.bats               (T-1.3; 5 fixture)
│   │       ├── test-parse-jest.bats           (T-1.4)
│   │       ├── test-parse-vitest.bats         (T-1.4)
│   │       ├── test-parse-bun.bats            (T-1.4)
│   │       ├── fixtures/                      (T-1.3 + T-1.4)
│   │       │   ├── jest/{package.json,jest.config.js,bun.lockb-skip,...}
│   │       │   ├── vitest/...
│   │       │   ├── bun/...
│   │       │   ├── mocha/...
│   │       │   └── playwright-runner/...
│   │       └── goldens/
│   │           ├── jest.run.golden.json       (T-1.4)
│   │           ├── vitest.run.golden.json     (T-1.4)
│   │           └── bun.run.golden.json        (T-1.4)
│   └── auto-test/
│       ├── SKILL.md                           (T-1.5; meta-skill orchestrator)
│       ├── scripts/
│       │   ├── orchestrate.sh                 (T-1.5; detect → init → run → finalize → render)
│       │   └── render-dashboard.sh            (T-1.5; ASCII per PRD §7 wireframe)
│       ├── references/
│       │   └── exit-codes.md                  (T-1.5; 0/1/2 contract)
│       └── tests/
│           ├── test-orchestrate.bats          (T-1.5; E2E on 2 local fixtures)
│           ├── test-render-dashboard.bats     (T-1.5; ASCII golden)
│           ├── smoke.sh                       (T-1.8; 3 real-repo harness)
│           ├── smoke-repos/                   (T-1.8; local fixtures fallback)
│           └── goldens/
│               └── dashboard.golden.txt       (T-1.5)
├── docs/
│   └── tasks/
│       └── phase-1/
│           ├── INDEX.md                       (← this file)
│           ├── T-1.1-init-run.md              + T-1.1-review.md
│           ├── T-1.2-append-finalize.md       + T-1.2-review.md
│           ├── T-1.3-detector.md              + T-1.3-review.md
│           ├── T-1.4-parsers.md               + T-1.4-review.md
│           ├── T-1.5-auto-test-meta.md        + T-1.5-review.md
│           ├── T-1.6-retention.md             + T-1.6-review.md
│           ├── T-1.7-doc-install.md           + T-1.7-review.md
│           ├── T-1.8-smoke.md                 + T-1.8-review.md
│           ├── PHASE-MANUAL-VERIFY.md         (Phase-1-specific manual-verify guide;
│           │                                   replaces "PHASE-BROWSER-TEST" because
│           │                                   Phase 1 has no browser layer yet)
│           └── PHASE-1-COMPLETE.md            (sign-off, 8-task checklist, GO/CAVEAT/NO-GO)
```

**No-touch list** (loop Constraints):
- `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/IMPLEMENTATION-PLAN.md` (read-only).
- `spike/**` (frozen Phase 0 record).
- Phase 2/3 skills (`browser-test`, `manual-test-helper`, `flaky-detector`,
  `coverage-reporter`, `integration-test-runner`) — **not** implemented this phase.

---

## 6. Execution Order (loop iterations)

| Iter | Task | Output | Commit type |
|---|---|---|---|
| 1 | T-1.0 (this) | `docs/tasks/phase-1/INDEX.md` | `chore(phase-1): T-1.0 phase-1 index + dep graph` |
| 2 | T-1.1 | `skills/test-log-centralizer/{SKILL.md,scripts/init-run.sh,tests/test-init-run.bats}` + task file + review | `feat(phase-1): T-1.1 log centralizer init-run` |
| 3 | T-1.2 | `append-log.sh` + `finalize-run.sh` + bats + golden manifest | `feat(phase-1): T-1.2 log centralizer append + finalize` |
| 4 | T-1.3 | `unit-test-runner/SKILL.md` + `detect.sh` + 5 fixtures + bats | `feat(phase-1): T-1.3 framework detector + 5 fixtures` |
| 5 | T-1.4 | 3 parsers + 3 goldens + bats | `feat(phase-1): T-1.4 output parsers (jest/vitest/bun)` |
| 6 | T-1.5 | `auto-test/SKILL.md` + orchestrator + dashboard + E2E bats | `feat(phase-1): T-1.5 auto-test meta orchestrator` |
| 7 | T-1.6 | `retention.sh` + bats (12 fake runs) | `feat(phase-1): T-1.6 retention helper (10+gz)` |
| 8 | T-1.7 | README install update + frontmatter lint pass | `docs(phase-1): T-1.7 install doc + frontmatter lint` |
| 9 | T-1.8 | smoke harness + 3-repo verification report | `test(phase-1): T-1.8 smoke test 3 repos` |
| 10 | Wrap-up | `PHASE-MANUAL-VERIFY.md` + `PHASE-1-COMPLETE.md` | `docs(phase-1): sign-off + manual verify guide` |

---

## 7. Phase-0 Carry-overs Resolved Here

From `spike/PHASE-0-COMPLETE.md` §7 — items the spike memo deferred to Phase 1:

| # | Carry-over | Resolution task |
|---|---|---|
| 1 | Re-measure per-syscall write p99 in Bun/Node with `performance.now()` | **Deferred to Phase 4** (out of MVP scope). Spike T-0.4 aggregate showed ×2,900 margin already; Phase 1 sticks with bash scripts per loop deliverables list. |
| 2 | Run 5-prompt manual skill-activation eval (P1–P5) | Documented in **T-1.7 + PHASE-MANUAL-VERIFY.md**; user runs after Phase 1 ships before considering G5 closed. |
| 3 | Bolt `validate-skill.sh` into pre-commit hook / CI | **T-1.7** invokes `spike/code/tests/validate-skill.sh` against all 3 SKILL.md as part of review checklist. |
| 4 | Description quality + anti-pattern enumeration | **T-1.1, T-1.3, T-1.5, T-1.7** — every SKILL.md description follows survey §5 4-part template (when/capability/keyword/anti-pattern). |
| 5 | Retention pass + `latest` re-point on every finalize | **T-1.2** (latest re-point) + **T-1.6** (retention sweep). |
| 6 | Wire redact rules from `config.json` | **Deferred Phase 4** (per PRD §6 — opt-in feature, low MVP value). |
| 7 | Windows `LATEST.txt` fallback | **Deferred Phase 4** — Phase 1 supports macOS + Linux only (loop constraint). |
| 8 | Idempotence content-test (same project + same commit → byte-equal manifest) | **T-1.2** golden test partly covers shape idempotence. Full content test deferred (depends on framework determinism). |
| 9 | Style-guide line: never `source` user-supplied config | **Followed throughout** — all scripts use line-by-line parsers (carry-over from spike `finalize-run.sh`). |
| 10 | Out-of-band: ask Anthropic re `/skills list` | **No action** — out of project scope. |

---

## 8. Success Metrics (PRD §4)

| ID | Metric | Target | Phase 1 measurement |
|---|---|---|---|
| **G1** | Time-to-first-fail-detected | < 30 s | **T-1.8** smoke harness (timer on local fixture) |
| G2 | Log retrieval time | < 5 s for `Read` | Carry from Phase 0 (T-0.4 measured 48 ms) |
| G3 | False-positive rate | < 5 % | Defer Phase 4 (needs ground-truth project set) |
| **G4** | Framework-detection accuracy | ≥ 95 % | **T-1.3** — 5/5 fixture must pass |
| **G5** | Skill activation correctness | ≥ 90 % | **T-1.7 + PHASE-MANUAL-VERIFY** (5-prompt manual eval, gates Phase exit) |
| G6 | Run reproducibility | Idempotent shape | **T-1.2** golden test |

Phase 1 directly measures: G1, G4, G5, G6. G2 carries from Phase 0. G3 defers.

---

## 9. Process Constraints (loop rules)

- **Per-task git commit** on `main` (no push). Co-Authored-By: `Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
- **Test-driven**: tests RED → impl GREEN → commit. Loop Rule 2 framework picks per task table §4.
- **Per-task review** file `T-1.<N>-review.md` with self-review checklist (AC met, reproducible, frontmatter valid, no secret leak, cross-platform).
- **No-touch**: `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/IMPLEMENTATION-PLAN.md`, `spike/**`.
- **No Phase 2/3 work**: skip browser-test, integration-test-runner, manual-test-helper, flaky-detector, coverage-reporter, multi-runtime parsers (pytest/cargo/go).
- **Cross-platform**: bash POSIX-portable, macOS BSD + Linux GNU compatible. JSON for data interchange.
- **Skill discoverable**: every SKILL.md has frontmatter `name` + `description`; folder name == `name`.

---

## 10. Open Risks Carried into Phase 1

| # | Risk (from plan + Phase 0) | Mitigation in Phase 1 |
|---|---|---|
| R-A | Skill discovery non-deterministic (Phase 0 caveat) | T-1.7 + manual-verify gate before declaring G5 met |
| R-B | Framework output format drift between minor versions (R2 in plan) | T-1.4 pin parser to documented format; goldens in `tests/goldens/` |
| R-C | Concurrent run conflict (R4 in plan) | Per-source streams (carry from spike T-0.3); per-run timestamped folder |
| R-D | Cross-platform shell drift (BSD vs GNU date/stat/gzip) | T-1.1..T-1.6 use only POSIX-portable flags; bats run on macOS sandbox |
| R-E | Smoke-test repo network access in sandbox | T-1.8 falls back to local fixtures + documents manual-run path |

---

## 11. Phase Exit Checklist (used in `PHASE-1-COMPLETE.md` at iter 10)

- [ ] T-1.1..T-1.8 all green (8 commits on `main`)
- [ ] Bats suite ≥ 30 assertions across 3 skills
- [ ] 5/5 framework fixture detect (T-1.3)
- [ ] 3/3 parser goldens match (T-1.4) at ≥ 90 % branch
- [ ] E2E dashboard renders + ASCII wireframe match (T-1.5)
- [ ] Retention 12 → 10+2gz (T-1.6)
- [ ] All 3 SKILL.md pass `validate-skill.sh`
- [ ] README install snippet ≤ 5 lines (T-1.7)
- [ ] 3/3 smoke repos green or documented manual fallback (T-1.8)
- [ ] PHASE-MANUAL-VERIFY.md describes 5-prompt eval steps
- [ ] PHASE-1-COMPLETE.md GO/CAVEAT/NO-GO with cost actual + lessons
