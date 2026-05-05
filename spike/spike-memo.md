# Spike memo — Phase 0 decision synthesis

> **Phase**: 0 — Spike & decision memo
> **Audience**: Phase 1 implementer + project sponsor (go/no-go reader)
> **Inputs**: `spike/T-0.1` → `spike/T-0.6` task files, reviews, and prototype artifacts
> **Companion**: `spike/T-0.5-success-criteria.md` (per-metric pass/fail table) and `spike/PHASE-0-COMPLETE.md` (sign-off checklist)
> **Word budget**: 600–1000 words (this memo: ~ 920)

---

## 1. Go / No-Go on the two unknowns

### U1 — Skill loading: 🟡 **GO with manual-verify gate**

The `hello-test` prototype (`spike/code/skills/hello-test/SKILL.md`) parses cleanly, the structural validator (`validate-skill.sh`) passes 8/8 checks, and the frontmatter shape matches every bundled skill we surveyed in T-0.1 (`drawio`, `webapp-testing`, `xlsx`, `pdf`, `docx`, `skill-creator`). What we **could not** verify from inside the agent sandbox is the behavioural side: does Claude Code actually discover a skill dropped into `~/.claude/skills/` and auto-trigger it on a matching prompt? There is no in-sandbox introspection tool (`/skills list`, dispatch-trace, etc.) that exposes the discovery hook.

The mitigation, documented in `T-0.2-hello-test.md` §"Manual Verification Procedure", is a 5-prompt human-in-the-loop run (P1–P5) that takes ~5 minutes on a fresh Claude Code session and answers three open questions in one pass: (a) does discovery require restart, (b) does folder-name vs `name`-field mismatch break loading, (c) what is the false-positive rate on negative prompts. **Phase 1 must complete this run before shipping its first real skill.** If it fails, the documented fallback is to package the skill as a plugin and require `/plugins enable` — a known-good route per T-0.1 survey but with worse onboarding ergonomics.

### U2 — Centralized log pattern: ✅ **GO**

T-0.4 ran 22,000 concurrent appends (2k cross-process + 20k inline) across the per-source-stream design and observed **zero corruption, zero loss, zero duplication**. The 7.2 MB retrieval bench landed at **48 ms median (×95 inside the 5 s G2 budget)**. The design-time decision in T-0.3 to give each layer (`unit`, `integration`, `browser`, `orchestrator`) its own writer file and `cat`-merge at finalize time turned out to be the single most consequential choice — it eliminated the entire `O_APPEND` / `flock` / `PIPE_BUF` debate at the **architecture** layer rather than at the **implementation** layer. Manifest atomicity comes from `tmp+rename`, which T-0.4 verified holds under concurrent-finalize stress.

There is one carry-over: pure-bash on macOS cannot resolve sub-millisecond per-syscall timings (python3 cold-start ate the measurement), so the formal "p99 < 50 ms" claim should be re-measured in Phase 1's chosen runtime with `performance.now()`. The aggregate throughput number (58k writes/sec, 17.2 µs amortized) gives high confidence the syscall-level p99 is well inside budget.

---

## 2. Tech picks (with explicit rejected alternatives)

| Decision | Choice | Rejected | Why |
|---|---|---|---|
| Helper-script runtime (Phase 1) | **Bun preferred, Node fallback** — install `bun` for users who already have it, ship a Node entrypoint as a transparent fallback. All scripts use only `fs`, `path`, `child_process` so they're identical on both runtimes. | Pure-bash (rejected for production: T-0.4 hit cross-platform measurement gaps); pure-Node-only (rejected for cold-start: `bun --bun start-run.ts` is ~20 ms vs Node's ~80 ms, matters for G1 < 30 s budget); pure-Bun-only (rejected for install footprint: macOS-default Node coverage is broader). | Lets us optimise hot path on Bun without abandoning users on `apt install nodejs`. |
| `run.log` format | **Plain text** (no per-line JSON) | JSONL (rejected: breaks `tail -f` ergonomics for Persona A who manually inspects logs; needs a parser to read what was written); single big JSON (rejected: not append-friendly, can't stream while running). | Preserves the unmodified test-runner stdout. Structured side-data lives in `manifest.json` and `events.ndjson` (optional, per-skill). |
| `manifest.json` format | **JSON-text, atomic write via tmp+rename** | SQLite (rejected for v1: no daemon allowed by PRD §6, the cross-run query patterns SQLite would shine at don't exist yet — defer to v2 per ARCHITECTURE §f); JSONL append (rejected: shape stability is load-bearing for the loop contract — see ARCHITECTURE §d). | Four fields (`exit_code`, `summary`, `failed_cases`, `log_path`) form the public API; everything else is internal/advisory. |
| Concurrency strategy | **Per-source streams + post-finalize `cat` merge** | Single `O_APPEND` log with per-write `flock` (rejected: corrupts on writes > PIPE_BUF, e.g. multi-line stack traces). | Atomicity for free, deterministic merge order, zero coordination code. |
| Skill packaging (Phase 1 default) | **Drop-folder into `~/.claude/skills/`** | Plugin (`/plugins enable`) — kept as documented fallback if U1 manual-verify fails. | Lower install friction; matches PRD §"Plugin Packaging" claim. |

---

## 3. Three explicit trade-offs accepted

1. **Per-source streams cost a finalize step.** We pay one `cat` and one `mv` per run to dodge the entire concurrent-write race-condition surface. Acceptable: the merge is O(bytes) and the test runners we care about emit < 10 MB per run. Worth it for the design-time clarity.
2. **Bash + python3 prototype stays in `spike/code/`, will be re-implemented in Bun/Node for Phase 1.** Spike LOC (~590) is throwaway. Worth it because it kept the spike honest about the runtime cost question and produced numbers no one can argue with — the design contract held under shell, so the TS rewrite is mechanical.
3. **Structural-only skill validation in Phase 0; behavioural validation owed to Phase 1.** We accept a non-zero risk that Claude Code's discovery semantics surprise us. Mitigation: the manual-verify procedure is short (5 min) and the fallback (plugin packaging) is low-cost. Worth it because it would have taken weeks to mock the discovery hook end-to-end.

---

## 4. Recommendation for Phase 1

**Start Phase 1.** Both unknowns clear; both PRD metrics that Phase 0 was scoped to measure (G2, G6) pass with margin. The Phase-1 entry checklist is:

1. **First action**: run the 5-prompt manual skill-activation eval (T-0.2 procedure) and record results in a `phase-1/manual-verify.md`. If FAIL, switch to plugin packaging *before* writing the first real skill.
2. **Second action**: re-implement `start-run.sh` / `append-log.sh` / `finalize-run.sh` in Bun, keeping the same file layout and `manifest.json` schema. Re-measure per-syscall write p99 with `performance.now()` to retire the T-0.4 carry-over.
3. **Third action**: implement `auto-test` orchestrator + `unit-test-runner` skill against the locked log contract; bolt `validate-skill.sh` into a pre-commit hook.

Phase 1 carry-over backlog (10 items) is enumerated in `T-0.5-success-criteria.md` §4 — start grooming there.

---

**Memo signed off.** No blockers. Proceed to Phase 1.
