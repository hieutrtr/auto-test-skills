# Auto-Test Skills — Implementation Plan

5 phase: spike (P0) → MVP (P1) → browser (P2) → multi-runtime (P3) → polish (P4). Mỗi phase có task list, AC, dep, risk. Tổng **6–7 dev-week** full-time (12–14 tuần part-time).

---

## Phase 0 — Spike & decision memo (3 ngày)

**Mục tiêu**: Validate (a) skill loading Claude Code, (b) centralized log pattern.

| # | Task | AC | Dep | Risk |
|---|---|---|---|---|
| 0.1 | Khảo sát `~/.claude/skills/` + plugin skills (`webapp-testing`, `xlsx`) | Memo `spike/skills-survey.md` 5 skill mẫu + frontmatter field | — | Low |
| 0.2 | Prototype `hello-test` drop `~/.claude/skills/` → test trigger | Skill load, Claude tự call khi prompt match `description` | 0.1 | Skill discovery không deterministic |
| 0.3 | Prototype `test-log-centralizer`: tạo `.test-runs/<ts>/` + write `run.log`, `manifest.json` | Run Bun project → folder match schema, agent đọc lại được | 0.2 | Path edge case (Windows, symlink) |
| 0.4 | Benchmark log centralizer: 100 concurrent append | < 50ms p99 SSD, không corrupt | 0.3 | Concurrent write race |
| 0.5 | Decision memo: go/no-go, TS hay Bun, file format | Memo có recommendation + 3 trade-off | 0.2–0.4 | Phase vượt 3 ngày |
| 0.6 | Repo skeleton: README, `docs/`, `skills/`, LICENSE, `.gitignore` | `git status` clean, `tree -L 2` đúng | 0.1 | — |

**Exit**: Memo approve → P1. Skill loading fail → pivot plugin packaging.

---

## Phase 1 — MVP core skills (1–2 tuần)

**Mục tiêu**: 3 skill end-to-end cho JS/Bun: `auto-test` → `unit-test-runner` → `test-log-centralizer`.

| # | Task | AC | Dep | Risk |
|---|---|---|---|---|
| 1.1 | `test-log-centralizer/SKILL.md` + `init-run.sh` tạo folder + `manifest.json` skeleton | Unit test 3 sample project tạo folder đúng format | 0.5 | Concurrent run conflict |
| 1.2 | `append-log.sh` + `finalize-run.sh` (tính duration, update manifest) | Snapshot test JSON match golden file | 1.1 | — |
| 1.3 | `unit-test-runner/SKILL.md` + framework detector (`package.json` scripts, `vitest.config.ts`, `bun.lockb`) | 5 fixture (jest, vitest, bun, mocha, playwright-runner) detect đúng | 1.1 | Heuristic miss edge case |
| 1.4 | Output parser cho 3 framework đầu (jest TAP, vitest JSON, bun text) → canonical `TestRun` JSON | Parser unit test ≥ 90% coverage, golden output 3 framework | 1.3 | Framework đổi format giữa version |
| 1.5 | `auto-test/SKILL.md` (meta): detect → invoke runner → centralize log → render summary | E2E: chạy trên fixture, output dashboard ASCII + path `.test-runs/` đúng | 1.2, 1.4 | Meta-skill không invoke được sub-skill |
| 1.6 | Retention helper: keep last 10 runs, gz cũ | Test 12 fake run → còn 10 + 2 gz | 1.2 | — |
| 1.7 | Doc `skills/<name>/SKILL.md` chuẩn frontmatter, update README install | Drop vào `~/.claude/skills/` → Claude pick up | 1.5 | — |
| 1.8 | Smoke test trên 3 repo thực (Bun, npm, vitest) | 3/3: agent dispatch → log appear → pass/fail accurate | 1.5 | Pre-test setup phức tạp |

**Exit criteria**: dev `git clone` → drop skill → từ Claude Code dispatch "run unit tests" → nhận summary + link `.test-runs/<ts>/run.log`.

---

## Phase 2 — Browser test skill (1 tuần)

**Mục tiêu**: `browser-test` chạy Playwright, capture screenshot, log vào centralizer.

| # | Task | AC | Dep | Risk |
|---|---|---|---|---|
| 2.1 | Khảo sát `webapp-testing` skill — reuse vs rewrite | Memo `phase2/reuse-decision.md` | P1 | License compatibility |
| 2.2 | `browser-test/run.ts` (Bun): spawn dev server (`package.json` `dev`), wait port, run Playwright | Fixture Next.js + Vite: server up < 30s, scenario run | 2.1 | Dev server stuck / port conflict |
| 2.3 | Screenshot capture trên fail → `.test-runs/<ts>/screenshots/` | Failing scenario sinh screenshot, manifest có entry | 2.2, 1.2 | Headless render khác headed |
| 2.4 | Headed/headless toggle qua skill arg (default headless) | Cả 2 mode chạy được, doc rõ trade-off | 2.2 | — |
| 2.5 | DSL tối giản cho scenario: `tests/browser/*.scenario.md` (goto, click, expect text) | Parser unit test + 3 scenario fixture pass | 2.2 | DSL quá hạn chế hoặc phức tạp |
| 2.6 | Integration `auto-test` meta: repo có `tests/browser/` → auto invoke | E2E repo unit + browser → meta orchestrate cả 2 | 2.5, 1.5 | Sequence dependency unclear |
| 2.7 | Doc `docs/browser-test.md` + example scenario | Doc reviewed, example chạy được | 2.5 | — |

**Exit criteria**: Demo GIF: dispatch task tới repo Next.js → auto-test chạy unit + browser → screenshot fail trong log folder.

---

## Phase 3 — Multi-runtime + manual helper (1–2 tuần)

**Mục tiêu**: Mở rộng `unit-test-runner` cho Python/Rust/Go. Thêm `manual-test-helper`.

| # | Task | AC | Dep | Risk |
|---|---|---|---|---|
| 3.1 | Pytest detector + parser (JUnit XML) | 3 fixture pytest parse đúng | P1 | pytest plugin variation |
| 3.2 | Cargo test detector + parser (`--format json -Z unstable-options`) | 2 fixture Rust crate parse đúng | P1 | Unstable flag breaking |
| 3.3 | Go test detector + parser (`go test -json`) | 2 fixture Go module parse đúng | P1 | — |
| 3.4 | Cập nhật `TestRun` schema cho language metadata (Rust target, Python venv) | Schema versioned, migration v1 → v1.1 | 3.1, 3.2, 3.3 | Schema bloat |
| 3.5 | `manual-test-helper/SKILL.md`: feature description → checklist `.test-runs/<ts>/manual-checklist.md` | Sample feature gen checklist 5–10 step, agent tick được | P1 | LLM gen không nhất quán |
| 3.6 | Resume: agent đọc checklist tick partial → biết step pending | Resume test pass với fixture 3 step (1 done, 2 pending) | 3.5 | — |
| 3.7 | Cross-language smoke: monorepo TS + Python → meta orchestrate 2 runner song song | Aggregate report đúng, pass/fail count chính xác | 3.1, 3.4 | Concurrent run lock conflict |
| 3.8 | Doc multi-runtime install (Python venv, Rust toolchain, Go) + troubleshooting | Doc clear, có troubleshooting section | 3.7 | — |

**Exit criteria**: README claim "supports Node/Bun/Python/Rust/Go" — chứng minh bằng 5 fixture + 1 monorepo polyglot.

---

## Phase 4 — Polish & release (1 tuần)

**Mục tiêu**: Production-ready, doc đầy đủ.

| # | Task | AC | Dep | Risk |
|---|---|---|---|---|
| 4.1 | `flaky-detector/SKILL.md`: rerun fail N lần (default 3), report flaky rate | Fixture 1 flaky test → detector flag đúng | P1, P3 | Rerun cost (CPU/time) |
| 4.2 | `coverage-reporter/SKILL.md`: c8/istanbul/coverage.py/`cargo tarpaulin` → threshold check | 4 runtime fixture report % đúng | P3 | Tooling fragmentation |
| 4.3 | Retention cleanup helper (`auto-test --cleanup`) | Sau cleanup chỉ giữ 10 run + gz cũ | 1.6 | — |
| 4.4 | Install doc finalize: `~/.claude/skills/` drop, plugin manifest, npm package optional | Fresh machine: 3 install path đều work | All | — |
| 4.5 | CI integration recipe (GitHub Actions): chạy `auto-test` → upload `.test-runs/` artifact | Workflow commit, PR demo có artifact | 4.4 | — |
| 4.6 | (Optional) npm publish `@auto-test-skills/cli` standalone | Package install + run được ngoài skill context | 4.4 | npm namespace conflict |
| 4.7 | Release notes v0.1, tag, GitHub release | Tag pushed, release page có install instruction | 4.4 | — |
| 4.8 | Post-launch survey cho 5 user đầu (friction, false positive thực tế) | Doc `feedback/v0.1.md` ready cho v0.2 plan | 4.7 | — |

**Exit criteria**: 5 external user cài < 10 phút, dispatch test đầu tiên < 2 phút sau cài.

---

## Risk register (top 5)

| # | Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|---|
| R1 | Skill loading không deterministic — Claude không tự trigger khi cần | High | Med | Phase 0 spike validate. Fallback: explicit `/auto-test` slash command |
| R2 | Framework output format đổi giữa minor version → parser break | Med | High | Pin version range trong doc, snapshot parser test, CI matrix 3 version mỗi framework |
| R3 | Browser test flakiness (timing, port) phá user trust | High | High | Default retry 2x, screenshot mọi failure, headed mode debug, doc troubleshooting |
| R4 | Concurrent run từ multi-agent (claude-bridge) → race trên `.test-runs/` | Med | Med | Lock file `.test-runs/.lock` hoặc per-PID subfolder, document constraint |
| R5 | Adoption thấp — user thấy phức tạp, quay về `bun test` thủ công | High | Med | Onboarding < 2 phút, dashboard rõ, demo GIF README |

---

## Cost estimate

**Engineering effort** (1 dev senior):

| Phase | Effort | Calendar (full-time) |
|---|---|---|
| P0 spike | 3 ngày | 3 ngày |
| P1 MVP | 8–10 ngày | 1.5–2 tuần |
| P2 browser | 5 ngày | 1 tuần |
| P3 multi-runtime | 7–10 ngày | 1.5–2 tuần |
| P4 polish | 5 ngày | 1 tuần |
| **Tổng** | **28–33 dev-day** | **6–7 tuần** |

Part-time @ 50% → **12–14 tuần calendar**.

**LLM cost** (dev + dogfood): ~$80–150 (spike + iteration + smoke loops qua Claude Code).

**End-user runtime**: skill chạy local → $0 LLM, chỉ CPU/RAM. CI optional GitHub Actions free tier.

**Maintenance** post-v0.1: ~2 dev-day/tháng cho framework bump + bug fix. Reassess sau 3 tháng.

---

## Open questions

1. Repo standalone hay subfolder claude-bridge?
2. License MIT hay Apache-2.0?
3. Plugin packaging theo spec Anthropic nào? (P0 check)
4. v0.1 chỉ JS/Bun + browser, hay include Python từ MVP?
