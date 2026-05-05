# Phase 0 — Spike Index

> Bootstrap doc cho phase spike. Liệt kê 6 atomic task, dep graph, success metrics, execution order.
> Source: `docs/IMPLEMENTATION-PLAN.md` (Phase 0), `docs/ARCHITECTURE.md`, `docs/PRD.md`.

---

## Mục tiêu Phase 0

Validate **2 unknown** trước khi commit Phase 1:

1. **Skill loading**: drop folder vào `~/.claude/skills/` → Claude Code có discover + auto-trigger theo `description` không?
2. **Centralized log pattern**: `.test-runs/<ts>/run.log` + `manifest.json` schema có robust với concurrent write + path edge case không?

Phase exit: memo `spike/spike-memo.md` approve → bắt đầu P1. Skill loading fail → pivot plugin packaging.

---

## 6 Atomic Task

### T-0.1 — Khảo sát skill ecosystem  *(research, no code)*
- **AC**: Memo `spike/skills-survey.md` mô tả ≥ 5 skill mẫu (`drawio` user-level + bundled `webapp-testing`, `xlsx`, `pdf`, `docx` từ `document-skills`) + bảng frontmatter fields (`name`, `description`, `tools`, `allowed-tools`, …).
- **ARCHITECTURE ref**: §(c) Integration với Claude Code Skill System.
- **Dep**: —
- **Risk**: Low.

### T-0.2 — Prototype `hello-test` skill  *(spike + manual verify)*
- **AC**: Skill folder có SKILL.md hợp lệ; drop vào `~/.claude/skills/` → Claude tự call khi prompt match `description`. Test "skill có thể load" trước khi viết SKILL.md (TDD nhỏ).
- **ARCHITECTURE ref**: §(c) SKILL.md frontmatter, plugin packaging.
- **Dep**: T-0.1.
- **Risk**: Skill discovery không deterministic. Mitigation: document manual verify steps (drop file + restart Claude Code).

### T-0.3 — Prototype `test-log-centralizer`  *(TS/bash script + tests)*
- **AC**: Script tạo `.test-runs/<ts>/` + `run.log` (append-only) + `manifest.json` skeleton. Agent đọc lại được → schema match §(b). Vitest/bats test cho file structure.
- **ARCHITECTURE ref**: §(b) Centralized Log Design (path convention, file list).
- **Dep**: T-0.2 (cần biết skill helper script chạy thế nào).
- **Risk**: Path edge case (Windows, symlink, worktree).

### T-0.4 — Benchmark concurrent append  *(test + measurement)*
- **AC**: 100 concurrent `append-log` từ subprocess → p99 < 50ms trên SSD, file không corrupt (lines well-formed, no interleaving). Output: bảng số liệu trong review.
- **ARCHITECTURE ref**: §(b) retention + concurrency note (R4 risk register).
- **Dep**: T-0.3.
- **Risk**: Concurrent write race. Mitigation: lock file hoặc per-PID subfolder.

### T-0.5 — Decision memo  *(research, synthesis)*
- **AC**: `spike/spike-memo.md` (~600-1000 từ): go/no-go cho 2 unknown, tech pick (TS vs Bun, file format JSON vs JSONL), ≥ 3 trade-off, recommend cho Phase 1.
- **ARCHITECTURE ref**: §(b), §(c), §(f) Data model & storage choice.
- **Dep**: T-0.2, T-0.3, T-0.4.
- **Risk**: Phase vượt 3 ngày → memo trễ.

### T-0.6 — Repo skeleton  *(scaffolding, verify only)*
- **AC**: `git status` clean, `tree -L 2` clean. README ✓ (đã có, không sửa), `docs/` ✓ (đã có), `skills/` placeholder + `.gitkeep`, LICENSE (MIT), `.gitignore` ✓ (đã có).
- **ARCHITECTURE ref**: —
- **Dep**: T-0.1.
- **Risk**: —

---

## Dependency Graph

```
T-0.1 (survey)
   │
   ├──> T-0.2 (hello-test prototype)
   │       │
   │       └──> T-0.3 (log centralizer prototype)
   │               │
   │               └──> T-0.4 (concurrent benchmark)
   │                       │
   │                       └──> T-0.5 (decision memo)  <── đọc kết quả 0.2 + 0.3 + 0.4
   │
   └──> T-0.6 (repo skeleton)
```

Critical path: **0.1 → 0.2 → 0.3 → 0.4 → 0.5** (5 task tuần tự).
0.6 chạy song song với 0.2-0.4 sau khi 0.1 done.

---

## Execution Order (loop iterations)

| Iter | Task | Output | Commit type |
|---|---|---|---|
| 1 | Bootstrap | `spike/INDEX.md` | `chore(phase-0): bootstrap` |
| 2 | T-0.1 | `spike/skills-survey.md` + `T-0.1-*.md` + review | `docs(phase-0): T-0.1` |
| 3 | T-0.2 | `experiments/hello-test/` + `T-0.2-*.md` + review | `feat(phase-0): T-0.2` |
| 4 | T-0.3 | `experiments/log-centralizer/` + `T-0.3-*.md` + review | `experiment(phase-0): T-0.3` |
| 5 | T-0.4 | benchmark script + numbers + `T-0.4-*.md` + review | `test(phase-0): T-0.4` |
| 6 | T-0.5 | `spike/spike-memo.md` + `T-0.5-*.md` + review | `docs(phase-0): T-0.5` |
| 7 | T-0.6 | `skills/.gitkeep`, `LICENSE` + `T-0.6-*.md` + review | `chore(phase-0): T-0.6` |
| 8 | Wrap-up | `spike/PHASE-0-COMPLETE.md` | `docs(phase-0): sign-off` |

---

## Success Metrics (từ PRD §4)

| ID | Metric | Target | Phase 0 relevance |
|---|---|---|---|
| G1 | Time-to-first-fail-detected | < 30s | Phase 1+ (need real runner) — not measured here |
| **G2** | **Log retrieval time** | **`Read` < 5s, no multi-file grep** | **Validate trong T-0.3 / T-0.4** |
| G3 | False positive rate | < 5% | Phase 1+ |
| G4 | Framework detection accuracy | ≥ 95% | Phase 1+ |
| **G5** | **Skill activation correctness** | **≥ 90% Claude tự trigger đúng** | **Validate trong T-0.2 (manual eval, n=5 prompt)** |
| G6 | Run reproducibility | Idempotent shape | Validate trong T-0.3 (snapshot) |

Phase 0 đo trực tiếp: G2, G5, G6. G1/G3/G4 defer P1.

---

## Process Constraints (loop rules)

- **Per-task git commit** (không push). Co-Authored-By: Claude Opus 4.7 (1M context) `<noreply@anthropic.com>`.
- **Không modify**: `README.md`, `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/IMPLEMENTATION-PLAN.md`.
- **Không implement Phase 1**: skill thật (`auto-test`, `unit-test-runner`) — đó là P1.
- Mỗi task có 1 task file `spike/T-0.<N>-<slug>.md` + 1 review `spike/T-0.<N>-review.md`.
- Spike-appropriate: 0.1/0.5 = research memo (no code/test); 0.2 = TDD nhỏ; 0.3/0.4 = scripts có test; 0.6 = scaffold only.

---

## Open Questions (resolve trong T-0.5 memo)

1. **TS vs Bun runtime cho helper scripts** — Bun zero-dep nhưng yêu cầu user cài; Node fallback?
2. **File format**: `run.json` (single JSON) vs JSONL (append-friendly cho `run.log`)?
3. **Concurrent write strategy**: lock file vs per-PID subfolder vs append-only newline atomic?
4. **Skill discovery**: cần restart Claude Code session sau drop hay không? (PRD claim không cần — verify trong T-0.2.)
