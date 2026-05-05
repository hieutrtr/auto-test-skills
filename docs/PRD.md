# PRD — auto-test-skills

> Product Requirements Document cho bộ skill auto-test phục vụ Claude Code và các AI agent vibe-coding.

---

## 1. Vision & Value Proposition

**Vision:** Vibe code không "xong" cho đến khi auto-test pass. AI agent (Claude Code, claude-bridge loop, Cursor, …) phải tự xác minh tính năng vừa code thật sự **chạy được**, không chỉ "compile + lint pass".

**Vấn đề hiện tại:**

- Vibe code generate code rất nhanh, nhưng **verification** vẫn là bottleneck thủ công. Agent thường claim "done" sau khi typecheck pass, trong khi feature thực tế bể trên runtime.
- Mỗi project dùng test command khác nhau (`bun test`, `npm test`, `pytest`, `cargo test`, `go test`). Agent phải nhớ — và thường nhớ sai.
- Browser test gần như không bao giờ được agent chạy: cần spawn dev server, mở browser, tương tác — quá nhiều bước.
- Log scattered: stdout/stderr trộn lẫn, file log mỗi framework một chỗ. Khi 1 test fail, agent phải mò log → tốn nhiều turn.

**Value prop trong 1 câu:** Cho Claude Code (và mọi AI agent) một bộ skill modular để **detect → run → aggregate → report** mọi loại test (unit, integration, browser, manual checklist) với log centralized — agent chỉ cần invoke `auto-test`, đọc file `manifest.json`, biết chính xác cái gì pass/fail và ở đâu.

**Tại sao là skill, không phải CLI/MCP?**

- Skill = native Claude Code primitive. Drop folder vào `~/.claude/skills/` là dùng được. Không cần daemon, không cần server, không cần auth.
- Frontmatter `description` đóng vai trò router: Claude tự quyết định khi nào cần test → invoke. Không phải hardcode trigger.
- Skill compose được: meta-skill `auto-test` orchestrate `unit-test-runner` + `browser-test` + `test-log-centralizer` mà không cần build hệ thống plugin riêng.

---

## 2. Personas

### Persona A — Solo Dev Vibe-coding (Linh, indie hacker)

- **Context:** ship MVP cuối tuần, dùng Claude Code generate cả backend + frontend. Không có CI, không viết test trước.
- **Pain:** sau mỗi vibe session, không biết tính năng có thật sự work không. Phải tự mở browser, click thử — quên bước nào là bug lọt.
- **Mong muốn:** Claude tự test, báo "feature X login pass, feature Y checkout fail vì button không bind handler". Có screenshot khi browser test fail.

### Persona B — Team Lead có CI (Minh, senior eng tại scaleup)

- **Context:** team 8 người, đã có Jest + Playwright + GitHub Actions. Dùng Claude Code để accelerate task.
- **Pain:** Claude generate code rồi push PR, CI fail — round-trip 5–10 phút mỗi lần. Muốn Claude chạy test **local** trước khi push. Cần log structured để Claude tự đọc và sửa loop được.
- **Mong muốn:** skill detect đúng framework có sẵn (không cài đè), respect existing `package.json` scripts, output log JSON để parse.

### Persona C — Agent Loop tự test (claude-bridge loop, autonomous workflow)

- **Context:** loop orchestrator (như claude-bridge `loop` command) chạy iterative: iter N code, iter N+1 verify, iter N+2 fix. Hoàn toàn không có human in the loop từng iteration.
- **Pain:** loop cần signal pass/fail **machine-readable** để evaluator quyết định continue / rollback / escalate. Hiện tại phải parse stdout fragile.
- **Mong muốn:** `auto-test` trả JSON `{run_id, framework, pass, fail, duration_ms, log_path}`. Loop đọc → branch logic. Có exit code chuẩn.

---

## 3. User Stories (MoSCoW)

### Must Have (M)

1. **(M)** Là dev, tôi gõ task "test feature mới" → Claude invoke `auto-test`, tự detect đây là Bun project, chạy `bun test`, báo kết quả.
2. **(M)** Là dev, khi test fail, tôi nhận được path tới `run.log` đầy đủ stdout/stderr — đọc 1 file là đủ debug.
3. **(M)** Là agent, tôi parse được output JSON `{pass: 12, fail: 1, failures: [{name, file, message}]}` không cần regex stdout.
4. **(M)** Là dev đa-runtime, tôi expect skill detect được Node, Bun, Python (pytest), Rust (cargo test) — không phải config.
5. **(M)** Là dev, tôi expect mọi test run lưu vào `<project>/.test-runs/<timestamp>/` — không scatter file rác.
6. **(M)** Là agent loop, tôi cần exit code 0/1 chuẩn để gate logic tiếp theo.

### Should Have (S)

7. **(S)** Là dev frontend, tôi expect `browser-test` skill spawn dev server, chạy Playwright scenario, capture screenshot khi fail.
8. **(S)** Là dev, tôi expect retention policy — chỉ giữ 10 run mới nhất, gz cũ, không phình `.test-runs/` vô hạn.
9. **(S)** Là dev, tôi expect skill respect `package.json` scripts có sẵn (`npm test`) thay vì gọi runner trực tiếp.
10. **(S)** Là tester manual, tôi expect `manual-test-helper` generate checklist markdown khi auto-test không cover được (vd: visual regression, UX flow).
11. **(S)** Là agent, tôi expect `flaky-detector` rerun N lần test fail, phân biệt flaky vs real bug.

### Could Have (C)

12. **(C)** Là team lead, tôi expect `coverage-reporter` integrate c8/coverage.py, fail run nếu coverage < threshold.
13. **(C)** Là dev CI, tôi expect skill có flag `--ci` xuất JUnit XML để upload lên GitHub Actions.
14. **(C)** Là dev, tôi expect MCP wrapper (v2) để skill dùng được từ ngoài Claude Code (Cursor, Continue, …).

### Won't Have (W) — v1

15. **(W)** Load test, performance benchmarking — out of scope.
16. **(W)** Security pentesting, fuzzing — out of scope, không phù hợp pattern skill.
17. **(W)** Mobile native test (iOS/Android) — defer v3.

---

## 4. Goals & Success Metrics

| # | Metric | Target | Đo bằng |
|---|---|---|---|
| G1 | **Time-to-first-fail-detected** | < 30s từ lúc dev gõ task → Claude báo test fail | Stopwatch trên 10 task mẫu (small project) |
| G2 | **Log retrieval time** | Agent cần xem log → 1 lệnh `Read` < 5s, không cần grep nhiều file | Manual test 20 lần |
| G3 | **False positive rate** | < 5% (test pass nhưng feature thực tế broken) | Audit 50 run trên project có ground truth |
| G4 | **Framework detection accuracy** | ≥ 95% trên top-10 stack phổ biến | Test matrix |
| G5 | **Skill activation correctness** | Claude tự trigger `auto-test` đúng context ≥ 90% | Eval trên prompt corpus 100 task |
| G6 | **Run reproducibility** | Cùng input → cùng `run.json` shape, idempotent | Snapshot test |

**North star:** dev dùng auto-test 1 tuần → niềm tin vào vibe code tăng (subjective survey). Khi không có auto-test, dev quay lại thấy thiếu.

---

## 5. Non-Goals (v1)

- **Load testing / performance benchmarking** — k6, wrk, autocannon. Cần infra riêng, mismatch với pattern skill.
- **Security pentesting** — Burp, ZAP, fuzzing. Domain expertise riêng, không phải auto-test functional.
- **Cross-browser matrix** — chỉ support Chromium qua Playwright. Firefox/Safari defer.
- **Test generation** — skill **chạy** test có sẵn, không generate test mới. (Có thể là skill khác, ngoài scope repo này.)
- **Replace CI** — skill chạy local, không thay thế GitHub Actions / GitLab CI. Có thể tích hợp via JUnit XML export (Could Have).
- **Mobile native** — iOS XCUITest, Android Espresso. Defer.
- **Multi-machine distributed test** — single-host only.

---

## 6. Privacy & Safety

- **Local-first by default:** mọi log lưu trong `<project>/.test-runs/`, không gửi ra cloud.
- **Opt-in CI integration:** chỉ khi user explicit set env `AUTO_TEST_UPLOAD=<endpoint>` mới upload. Mặc định off.
- **Secret redaction:** log centralizer phải scrub các pattern (`API_KEY=...`, `password=...`, `Authorization: Bearer ...`) trước khi ghi `run.log`. Default redact list + user override `.test-runs/.redact-rules`.
- **Sandbox dev server:** browser-test spawn dev server với env tách biệt — không inherit secrets từ shell parent trừ khi explicit allow.
- **Screenshot caution:** browser-test chỉ capture khi fail (default), giảm risk leak data trên màn hình khi pass. User có thể opt-in capture-all.
- **No telemetry:** skill không phone home. Không tracking. Không analytics.
- **Worktree-friendly:** nếu chạy trong git worktree (claude-bridge pattern), `.test-runs/` ghi vào worktree đó — không pollute main checkout.

---

## 7. Wireframe — Meta-skill Terminal Report

Output của `auto-test` khi Claude invoke (đây là cái Claude **đọc** + relay cho user):

```
┌──────────────────────────────────────────────────────────────────┐
│  auto-test  ·  run 20260505-203145  ·  duration 14.2s            │
├──────────────────────────────────────────────────────────────────┤
│  Project    : bridge-bot-ts-1                                    │
│  Framework  : bun:test (auto-detected)                           │
│  Worktree   : main                                               │
├──────────────────────────────────────────────────────────────────┤
│  UNIT          ✔ 47 passed   ✘ 1 failed    ⚠ 0 skipped           │
│  INTEGRATION   ✔ 12 passed   ✘ 0 failed    ⚠ 1 skipped           │
│  BROWSER       ✔  3 passed   ✘ 1 failed    ⚠ 0 skipped           │
│  MANUAL        ─ checklist generated (4 items pending)           │
├──────────────────────────────────────────────────────────────────┤
│  FAILURES                                                        │
│   • unit/auth.test.ts › login rejects expired token              │
│       expected 401, got 200                                      │
│       → .test-runs/20260505-203145/run.log:842                   │
│   • browser/checkout.spec.ts › "Pay" button click                │
│       Timeout 5000ms locator(#pay)                               │
│       → .test-runs/20260505-203145/screenshots/checkout-fail.png │
├──────────────────────────────────────────────────────────────────┤
│  ARTIFACTS                                                       │
│    log       .test-runs/20260505-203145/run.log                  │
│    json      .test-runs/20260505-203145/run.json                 │
│    manifest  .test-runs/20260505-203145/manifest.json            │
│    coverage  82.3% (threshold 80% ✔)                             │
├──────────────────────────────────────────────────────────────────┤
│  EXIT 1   ·  2 failures need attention                           │
└──────────────────────────────────────────────────────────────────┘
```

**Khi pass toàn bộ:**

```
┌──────────────────────────────────────────────────────────────────┐
│  auto-test  ·  run 20260505-204022  ·  duration 11.7s   ✔ ALL    │
│  unit 47/47  ·  integration 13/13  ·  browser 4/4                │
│  → .test-runs/20260505-204022/manifest.json                      │
└──────────────────────────────────────────────────────────────────┘
```

**Cấu trúc đảm bảo:**

- Header có `run_id` (timestamp) → agent dùng làm key.
- Mỗi failure có **path:line** đến log để Claude `Read` thẳng.
- Footer luôn có exit code rõ ràng → loop orchestrator parse 1 dòng cuối.
- Kèm machine-readable `run.json` cùng cấp cho consumer không thích parse text.

---

## 8. Open Questions

- Có nên ship default config redact rules cho từng framework hay để user tự define? (Lean: ship default minimal, doc cách override.)
- Browser-test có nên spawn dev server hay assume đã chạy? (Lean: detect cả hai; nếu port đã listen → reuse, không thì spawn theo `package.json` scripts.dev.)
- Manual checklist nên là markdown file hay prompt agent hỏi user trên Telegram (claude-bridge integration)? (Lean: markdown file v1, integration v2.)
