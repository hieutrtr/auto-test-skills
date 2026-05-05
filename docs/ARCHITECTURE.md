# Architecture — auto-test-skills

Tài liệu này mô tả thiết kế kỹ thuật của bộ skill `auto-test-skills`: danh sách skill, log centralization, cách integrate với Claude Code skill system + claude-bridge loop, framework detection heuristic, và data model.

---

## (a) Skill Set — 8 skill

Bộ skill chia thành **1 meta-skill** orchestrate + **7 worker skill** đảm nhiệm 1 concern. Mỗi skill là folder `<name>/SKILL.md` + helper script (`run.sh`, `parse.ts`, etc.) độc lập, có thể invoke riêng.

### 1. `auto-test` — meta-skill (orchestrator)

- **Trigger**: khi user hoặc agent nói "verify", "test xong chưa", "chạy test", hoặc sau task vibe-code lớn.
- **Responsibility**:
  1. Detect framework (gọi heuristic ở section e).
  2. Quyết định layer cần chạy: unit → integration → browser (skip layer nào không có).
  3. Spawn từng worker skill, collect output JSON.
  4. Aggregate kết quả → render dashboard ASCII (xem PRD wireframe).
  5. Trả exit code: 0 = all pass, 1 = test fail, 2 = framework not detected.
- **Output contract**: 1 file `manifest.json` ở `<project>/.test-runs/<ts>/manifest.json` + stdout dashboard.
- **Concurrency**: chạy unit + integration song song nếu cả 2 dùng test runner độc lập (Promise.all). Browser test luôn chạy sau cùng (đợi backend test pass mới mở browser, tránh waste khi backend đã fail).
- **Timeout**: mỗi worker skill có timeout cứng (unit 60s, integration 5min, browser 10min). Quá timeout → kill subprocess + ghi lý do vào `manifest.json.timeouts[]`.

### 2. `unit-test-runner`

- Detect script `test` (package.json), `pytest` (pytest.ini/pyproject), `cargo test` (Cargo.toml), `go test` (go.mod).
- Run với JSON reporter nếu có (`--reporter=json`, `pytest --json-report`, `cargo test -- --format json`).
- Parse output → list `TestCase` (name, status, duration, error). Fallback: regex line "FAIL" / "PASS" nếu reporter không khả dụng.
- Pipe raw stdout/stderr vào `test-log-centralizer`.

### 3. `integration-test-runner`

- Tách biệt với unit để có thể chạy độc lập (integration thường chậm + cần env DB/Redis).
- Filter test theo convention: folder `tests/integration/`, suffix `*.int.test.ts`, hoặc tag (`@integration` cho pytest, `#[ignore]` rồi `--ignored` cho Rust integration).
- Đọc `<project>/.test-runs/integration-env.sh` (optional) để export env trước khi chạy.
- Output format giống unit-test-runner.

### 4. `browser-test`

- Wrap Playwright (kế thừa `webapp-testing` skill của document-skills nhưng modular hơn).
- Steps:
  1. Detect dev server command (`npm run dev`, `bun run dev`, `vite`, `next dev`) qua package.json scripts.
  2. Spawn dev server, đợi port ready (default poll `localhost:3000`).
  3. Đọc test scenarios từ `tests/browser/*.spec.ts` hoặc generate basic smoke test (load homepage, click main CTA).
  4. Chạy headless mặc định, có flag `--headed` cho debug.
  5. Capture screenshot mỗi failure → `<project>/.test-runs/<ts>/screenshots/<scenario>.png`.
  6. Capture browser console log → `<project>/.test-runs/<ts>/browser-console.log`.
- Cleanup: tear down dev server (kill PID).

### 5. `manual-test-helper`

- Trigger khi auto-test không cover được (UI flow phức tạp, payment flow staging, etc.).
- Generate file `<project>/.test-runs/<ts>/manual-checklist.md` với:
  - Bullet list step (numbered).
  - Expected result mỗi step.
  - Checkbox markdown để user tick.
  - Link sang screenshot reference (nếu có baseline).
- Skill không chạy gì — chỉ tạo doc + nhắc user execute.

### 6. `test-log-centralizer`

- Singleton dependency của tất cả skill khác.
- API: `centralizer.append(runId, source, payload)` ghi vào `<project>/.test-runs/<runId>/run.log`.
- Cũng update `run.json` structured (xem data model section f).
- Quản lý retention (xem section b).

### 7. `flaky-detector`

- Sau khi `auto-test` xong, xác định test fail. Rerun từng test fail N lần (default 3).
- Tính flaky rate = (số lần pass trong rerun) / N.
- Flag test có flaky rate > 0% nhưng < 100% là **flaky**, ghi vào `<project>/.test-runs/<ts>/flaky-report.json`.
- Skill này optional — chỉ chạy khi user yêu cầu (`auto-test --check-flaky`) vì tốn thời gian.

### 8. `coverage-reporter`

- Wrap c8 (JS/TS), `coverage.py` (Python), `cargo-tarpaulin` (Rust).
- Chạy unit-test-runner với coverage flag rồi parse output.
- So sánh với threshold trong `<project>/.test-runs/coverage-threshold.json` (mặc định 70%).
- Generate `coverage-summary.md` với bảng file/lines/branches.

---

## (b) Centralized Log Design

Mục tiêu: **1 chỗ duy nhất** chứa tất cả output test run, agent có thể `Read` hoặc `grep` trực tiếp.

### Path Convention

```
<project>/.test-runs/
├── 20260505T142318/         <- run timestamp (UTC, sortable)
│   ├── manifest.json        <- index file (link tất cả con)
│   ├── run.log              <- raw stdout + stderr append-only
│   ├── run.json             <- structured TestRun (xem data model)
│   ├── browser-console.log  <- browser test console (nếu có)
│   ├── screenshots/
│   │   ├── homepage.png
│   │   └── checkout-fail.png
│   ├── flaky-report.json    <- nếu flaky-detector chạy
│   ├── coverage-summary.md  <- nếu coverage-reporter chạy
│   └── manual-checklist.md  <- nếu manual-test-helper chạy
├── 20260505T133012/
└── latest -> 20260505T142318  <- symlink update sau mỗi run
```

### Files trong mỗi run folder

| File | Format | Mô đích |
|---|---|---|
| `manifest.json` | JSON | Liệt kê tất cả file con + metadata (timestamp, framework, exit_code, duration). Agent đọc đây trước. |
| `run.log` | Plain text | Raw stdout/stderr append. Lớn nhất, nhưng dễ `tail -f` khi debug. |
| `run.json` | JSON | TestRun structured (suites, cases, status). Agent parse nhanh. |
| `screenshots/*.png` | Binary | Browser failure proof. |
| `browser-console.log` | Plain text | Browser-side console.* lines (separate vì noisy). |

### Retention Policy

- Giữ **10 run gần nhất** ở dạng plain folder.
- Run thứ 11 trở đi: gzip `run.log` → `run.log.gz`, xóa `screenshots/` (giữ `run.json` + `manifest.json`).
- Run > 30 ngày: xóa hoàn toàn (config được trong `<project>/.test-runs/config.json`).
- Cleanup chạy lazy: mỗi lần `auto-test` start, check + cleanup folder cũ.

### Easy Access

Agent / human dùng các shortcut sau:

```bash
# Latest run folder
LATEST=$(readlink <project>/.test-runs/latest)

# Quick fail summary
jq '.failed_cases' <project>/.test-runs/latest/run.json

# Full log
cat <project>/.test-runs/latest/run.log

# Screenshot debug
open <project>/.test-runs/latest/screenshots/checkout-fail.png
```

Skill `auto-test` luôn print 3 dòng cuối cùng:
```
LATEST=<project>/.test-runs/20260505T142318
LOG=<project>/.test-runs/latest/run.log
JSON=<project>/.test-runs/latest/run.json
```

→ Agent có thể grep từ output stdout, không cần biết thư mục từ đâu.

---

## (c) Integration với Claude Code Skill System

### SKILL.md Frontmatter

Mỗi skill folder có file `SKILL.md`:

```markdown
---
name: auto-test
description: Run all available test layers (unit, integration, browser) and aggregate result into a single dashboard. Trigger when user says "test", "verify", "kiểm tra" after vibe-coding a feature. Returns pass/fail + path to centralized log.
tools: Bash, Read, Glob, Grep
---

# Body — instructions cho Claude khi gọi skill này

## When to use
...

## How to use
...

## Examples
...
```

`description` là **decision factor** — Claude Code dùng để quyết định khi nào trigger. Bắt buộc rõ ràng + có concrete trigger phrase.

### Plugin Packaging (Optional)

3 cách distribute:

1. **Drop-in folder**: copy `auto-test-skills/skills/*` vào `~/.claude/skills/`. Đơn giản nhất.
2. **Plugin repo**: `git clone` vào `~/.claude/plugins/auto-test-skills`, bật bằng `/plugins enable auto-test-skills`. Update bằng `git pull`.
3. **npm package** (v2): `npm i -g @auto-test-skills/cli`, lệnh `auto-test-skills install` symlink vào `~/.claude/skills/`.

V1 chọn cách 1 + 2 (đơn giản, không cần build infra). Repo `auto-test-skills` host trên GitHub public, README có 1 lệnh install:

```bash
git clone https://github.com/<user>/auto-test-skills ~/.claude/skills/auto-test-skills
```

Sau đó Claude Code auto-discover skill ở folder `~/.claude/skills/`. Không cần restart Claude Code session.

### Tool Permissions

Skills cần `Bash` (chạy test command), `Read` (đọc package.json, log), `Glob`/`Grep` (detect framework). `browser-test` thêm cần Playwright binary đã cài sẵn — skill check pre-requisite trong body.

---

## (d) Integration với claude-bridge Loop

Use case: agent loop tự code → tự test → tự decide tiếp.

### Flow

```
Iter N:   Agent vibe-code feature X (edit src/)
Iter N+1: Loop invoke skill `auto-test`
          → run.json kết quả
          → Loop parse exit_code + failed_cases
          → Decision:
              exit_code == 0           → continue iter N+2 (next feature)
              exit_code == 1, fail < 3 → fix loop: agent đọc run.log, sửa
              exit_code == 1, fail ≥ 3 → rollback (git reset --hard HEAD~1)
              exit_code == 2           → halt, ask user
```

### JSON Output Contract

Loop chỉ cần đọc 4 field từ `run.json`:

```json
{
  "exit_code": 1,
  "summary": { "total": 42, "passed": 39, "failed": 3, "skipped": 0 },
  "failed_cases": [
    { "name": "Login > rejects bad password", "file": "tests/auth.test.ts:42", "error": "expected 401 got 500" }
  ],
  "log_path": "<project>/.test-runs/20260505T142318/run.log"
}
```

Schema này stable — loop không phải parse stdout dashboard.

### Rollback Heuristic

Loop config có thể set `auto_rollback_on_test_fail: true`. Khi đó claude-bridge worktree mode + git autocommit per iter cho phép `git reset` về iter trước an toàn.

---

## (e) Framework Detection Heuristic

`auto-test` chạy detect ở step 1. Thuật toán:

```
priority_order = [package.json, pyproject.toml, Cargo.toml, go.mod, Gemfile]

for file in priority_order:
  if exists(file):
    parse + extract test command
    return { framework, runtime, command }

fallback:
  read CLAUDE.md → grep section "Build & Test" → extract command
  if found: return { framework: "custom", command: <extracted> }
  else: return { framework: "unknown" } → exit code 2
```

### Detection Rules per Framework

| Marker | Framework | Default Command |
|---|---|---|
| `package.json` có script `test` | npm/yarn/bun (detect by lockfile) | `<runtime> test` |
| `package.json` script `test:unit` | same | `<runtime> run test:unit` |
| `pytest.ini` / `pyproject.toml` có `[tool.pytest]` | pytest | `pytest --json-report` |
| `Cargo.toml` | Rust | `cargo test --message-format json` |
| `go.mod` | Go | `go test -json ./...` |
| `Gemfile` + `spec/` | RSpec | `bundle exec rspec --format json` |
| `mix.exs` | Elixir/ExUnit | `mix test` |

Lockfile detection cho JS runtime: `bun.lockb` → bun, `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, else npm.

### Multi-framework

Project có cả backend Python + frontend TS → detect cả 2 → spawn 2 sub-run trong cùng folder `<ts>/`:

```
.test-runs/20260505T142318/
├── backend/run.log
├── backend/run.json
├── frontend/run.log
├── frontend/run.json
└── manifest.json   <- aggregate cả 2
```

---

## (f) Data Model

### ER ASCII

```
┌─────────────┐       ┌──────────────┐       ┌─────────────┐
│  TestRun    │ 1───* │  TestSuite   │ 1───* │  TestCase   │
├─────────────┤       ├──────────────┤       ├─────────────┤
│ id          │       │ id           │       │ id          │
│ project     │       │ run_id (FK)  │       │ suite_id(FK)│
│ started_at  │       │ name         │       │ name        │
│ duration_ms │       │ file         │       │ status      │
│ framework   │       │ duration_ms  │       │ duration_ms │
│ exit_code   │       │ status       │       │ error_msg   │
│ summary     │       └──────────────┘       │ error_stack │
└─────────────┘                              │ retry_count │
       │ 1                                   └─────────────┘
       │                                            │ 1
       * │                                          │
┌──────────────┐                                    * │
│  LogEntry    │                            ┌──────────────┐
├──────────────┤                            │  Screenshot  │
│ id           │                            ├──────────────┤
│ run_id (FK)  │                            │ case_id (FK) │
│ timestamp    │                            │ path         │
│ source       │                            │ taken_at     │
│ level        │                            └──────────────┘
│ message      │
└──────────────┘
```

### Field Notes

- **TestRun.summary**: denormalized JSON `{ total, passed, failed, skipped }` để loop đọc nhanh.
- **TestCase.status**: enum `passed | failed | skipped | flaky`.
- **TestCase.retry_count**: chỉ > 0 nếu flaky-detector chạy.
- **LogEntry.source**: enum `stdout | stderr | browser-console | skill`.
- **LogEntry.level**: heuristic parse — `error | warn | info | debug`.

### Storage

V1: tất cả lưu file (`run.json` chứa cả TestRun + nested suites/cases). Không dùng SQLite — agent đọc JSON đủ nhanh, file portable.

V2 (nếu nhiều run): SQLite `<project>/.test-runs/index.db` index toàn bộ history → query "test X fail bao nhiêu lần trong 30 ngày qua". Dùng `bun:sqlite` (zero dep) cho TS skill, `sqlite3` stdlib cho Python.

---

## Tóm tắt

8 skill modular (1 meta + 7 worker), log tập trung file-based ở `<project>/.test-runs/<ts>/`, integrate qua SKILL.md frontmatter, expose JSON contract cho claude-bridge loop tự rollback. Framework detection ưu tiên file marker → fallback CLAUDE.md → exit code 2 nếu unknown. Data model file-first (TestRun → TestSuite → TestCase + LogEntry + Screenshot), dễ debug bằng `cat`/`jq`/`grep` thuần, không cần SQLite ở v1. Mọi skill đều chia sẻ chung `test-log-centralizer` để guarantee single-source-of-truth khi agent đọc log.
