# auto-test-skills

Bộ skill cho Claude Code giúp **auto-test product sau khi vibe code** — agent tự phát hiện framework, chạy đủ lớp test (unit → integration → browser), và tổng hợp log vào một chỗ duy nhất để dễ debug.

## Vision

Vibe code (AI agent generate code nhanh) chỉ thực sự "done" khi đã verify functional. Compile pass và lint sạch không đảm bảo feature work. `auto-test-skills` lấp khoảng trống đó: agent gọi 1 skill → bộ skill tự lo phần còn lại → trả pass/fail kèm link xem chi tiết.

Mục tiêu cụ thể:

- **Đa runtime**: Node, Bun, Python, Rust, Go — không cần nhớ command từng project.
- **Đa lớp test**: unit, integration, browser (Playwright), manual checklist khi auto không cover hết.
- **Centralized log**: mọi run ghi về `<project>/.test-runs/<timestamp>/` — 1 grep là ra root cause.
- **Loop-friendly**: tích hợp với `claude-bridge` loop, agent có thể dispatch test ở iter X+1 sau khi code ở iter X.

## Install

```bash
git clone https://github.com/<owner>/auto-test-skills /tmp/auto-test-skills
mkdir -p ~/.claude/skills
cp -R /tmp/auto-test-skills/skills/* ~/.claude/skills/
# restart Claude Code, then ask: "run the unit tests"
```

Verify the drop with `bash /tmp/auto-test-skills/tools/lint-all.sh`. After restart, the skills `auto-test`, `unit-test-runner`, and `test-log-centralizer` are listed and Claude auto-triggers `auto-test` when the user asks to run tests. See [`skills/README.md`](skills/README.md) for the full skill manifest.

## Supported runtimes

| Runtime | Detect signal | Default command |
| --- | --- | --- |
| Node / Bun | `package.json#scripts.test` | `npm test` / `bun test` |
| Python | `pytest.ini`, `pyproject.toml [tool.pytest]` | `pytest` |
| Rust | `Cargo.toml [dev-dependencies]` | `cargo test` |
| Go | `go.mod` + `*_test.go` | `go test ./...` |
| Browser | dev server detect (`vite`, `next`, `bun dev`) | Playwright headless |

Nếu detect thất bại, skill đọc `CLAUDE.md` của project để tìm hint hoặc hỏi user.

## Quick start

```text
User: "Vừa thêm endpoint /users/:id, test giúp tao."

Claude (auto-trigger skill `auto-test`):
  1. Detect runtime: Node + Bun (package.json + bun.lockb)
  2. Run unit:        bun test           → 42 pass, 0 fail
  3. Run integration: bun test:integration → 8 pass, 1 fail
  4. Aggregate log:   .test-runs/20260505-201500/run.log
  5. Report:
     ❌ FAIL: tests/integration/users.test.ts:23
        expected 200, got 404 — route /users/:id not registered
     📂 Logs: .test-runs/20260505-201500/
```

Agent có thể tự `Read` file log đó để debug, không cần chạy lại test.

## Documentation

- **[docs/PRD.md](docs/PRD.md)** — vision, persona, user story, success metric, non-goals.
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — danh sách skill, log schema, framework detection, integration với Claude Code và `claude-bridge` loop.
- **[docs/IMPLEMENTATION-PLAN.md](docs/IMPLEMENTATION-PLAN.md)** — phase 0 → 4, atomic task, risk register, cost estimate.

## Status

Pre-spike. Đang ở giai đoạn planning (4 docs). Chưa có code skill nào — xem `IMPLEMENTATION-PLAN.md` cho lộ trình MVP.

## License

TBD (sẽ chốt khi public release).
