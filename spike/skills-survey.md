# Skills Survey — Claude Code Skill Ecosystem

> Phase 0 / T-0.1 deliverable. Khảo sát SKILL.md frontmatter convention + file layout từ 5+ skill thực tế (1 user-level, 4 bundled từ `document-skills` marketplace) + canonical guidance từ skill-creator. Mục tiêu: nắm chắc spec để Phase 1 viết SKILL.md cho 8 skill `auto-test-skills` đúng convention ngay từ đầu.
>
> Surveyed 2026-05-05. Source: `~/.claude/skills/drawio/`, `~/.claude/plugins/cache/anthropic-agent-skills/document-skills/1ed29a03dc85/skills/`.

---

## TL;DR

- **2 nguồn skill**: (1) user-drop ở `~/.claude/skills/<name>/SKILL.md`; (2) plugin marketplace cache ở `~/.claude/plugins/cache/<repo>/skills/<name>/`.
- **Frontmatter required**: chỉ `name` + `description`. Optional: `license`, `allowed-tools`, `compatibility`, `metadata`.
- **`description` là router**: Claude đọc metadata (always loaded) để quyết khi nào trigger skill. Description của bundled skills rất chi tiết — liệt kê trigger keywords, file extensions, anti-patterns ("Do NOT use for X"). 1 trong 5 skill viết description ≥ 150 từ.
- **File layout chuẩn**: `SKILL.md` (root) + `scripts/` (Python/Bash) + `references/` (load-on-demand docs) + `examples/` (sample inputs) + `assets/` (output templates) + `LICENSE.txt`. Không tạo README.md / CHANGELOG.md / INSTALLATION.md trong skill folder (skill-creator nhấn mạnh).
- **"Loadable" checklist**: (a) folder dưới `~/.claude/skills/` hoặc plugin path; (b) `SKILL.md` ở root folder; (c) frontmatter có `name` + `description`; (d) folder name khớp `name` frontmatter (convention, chưa verify hard requirement); (e) Claude Code auto-discover lúc start session — restart-or-not chưa kiểm chứng (resolve T-0.2).

---

## 1. Skill Sample List (5 skill khảo sát chính + 12 quan sát phụ)

### 1.1 `drawio` — user-level, đơn giản

- **Path**: `~/.claude/skills/drawio/SKILL.md`
- **Layout**: chỉ 1 file `SKILL.md` (10.5 KB). Không có `scripts/`, không có `LICENSE.txt`.
- **Frontmatter**:
  ```yaml
  ---
  name: drawio
  description: Generate draw.io diagrams as .drawio files, optionally export to PNG/SVG/PDF with embedded XML
  allowed-tools: Bash, Write
  ---
  ```
- **Trigger style**: ngắn gọn (~ 20 từ). Dựa vào keyword "draw.io" + "diagram" + format (PNG/SVG/PDF).
- **Body cấu trúc**: # Draw.io Diagram Skill → How to create a diagram (numbered steps) → Choosing the output format → draw.io CLI (path-by-platform table). Highly procedural, low-freedom.
- **Tool restriction**: `allowed-tools: Bash, Write` — skill chỉ được phép dùng 2 tool này.

### 1.2 `webapp-testing` — bundled, complex (Playwright wrapper)

- **Path**: `~/.claude/plugins/cache/anthropic-agent-skills/document-skills/1ed29a03dc85/skills/webapp-testing/`
- **Layout**:
  ```
  webapp-testing/
  ├── SKILL.md
  ├── LICENSE.txt
  ├── examples/
  └── scripts/   (chứa with_server.py — server lifecycle helper)
  ```
- **Frontmatter**:
  ```yaml
  ---
  name: webapp-testing
  description: Toolkit for interacting with and testing local web applications using Playwright. Supports verifying frontend functionality, debugging UI behavior, capturing browser screenshots, and viewing browser logs.
  license: Complete terms in LICENSE.txt
  ---
  ```
- **Trigger style**: ~ 35 từ, mô tả capability (test webapp, screenshot, browser logs).
- **Body convention quan trọng**:
  > "Always run scripts with `--help` first ... DO NOT read the source until you try running the script first ... These scripts can be very large and thus pollute your context window. They exist to be called directly as black-box scripts rather than ingested into your context window."
  → Bundled scripts là **opaque executables**, không phải code-to-read. Tiết kiệm context window.
- **Liên quan auto-test-skills**: chính là skill mà Phase 2 sẽ memo "reuse vs rewrite" (task 2.1). Layout `scripts/` + `examples/` là pattern tốt để reuse.

### 1.3 `xlsx` — bundled, "thick description" example

- **Path**: `.../skills/xlsx/`
- **Layout**: `SKILL.md` + `LICENSE.txt` + `scripts/`.
- **Frontmatter** (description rất dài, đáng quan sát):
  ```yaml
  ---
  name: xlsx
  description: "Use this skill any time a spreadsheet file is the primary input or output. This means any task where the user wants to: open, read, edit, or fix an existing .xlsx, .xlsm, .csv, or .tsv file (e.g., adding columns, computing formulas, formatting, charting, cleaning messy data); create a new spreadsheet from scratch or from other data sources; or convert between tabular file formats. Trigger especially when the user references a spreadsheet file by name or path — even casually (like \"the xlsx in my downloads\") — and wants something done to it or produced from it. Also trigger for cleaning or restructuring messy tabular data files (malformed rows, misplaced headers, junk data) into proper spreadsheets. The deliverable must be a spreadsheet file. Do NOT trigger when the primary deliverable is a Word document, HTML report, standalone Python script, database pipeline, or Google Sheets API integration, even if tabular data is involved."
  license: Proprietary. LICENSE.txt has complete terms
  ---
  ```
- **Description anatomy** (~ 175 từ) — pattern lặp lại ở `pdf`, `docx`:
  1. **Trigger condition** ("Use this skill any time ...").
  2. **Capability list** (open / read / edit / fix / create / convert).
  3. **File extensions** (.xlsx, .xlsm, .csv, .tsv).
  4. **Casual trigger phrases** ("the xlsx in my downloads").
  5. **Anti-pattern / negative trigger** ("Do NOT trigger when ...").
- **Body**: starts với "# Requirements for Outputs" → constraints (zero formula errors, professional font, preserve templates).

### 1.4 `pdf` — bundled, has `references/` for progressive disclosure

- **Path**: `.../skills/pdf/`
- **Layout**:
  ```
  pdf/
  ├── SKILL.md
  ├── LICENSE.txt
  ├── forms.md     ← reference, load-on-demand cho form-fill task
  ├── reference.md ← extra reference doc
  └── scripts/
  ```
- **Frontmatter**: similar pattern; description liệt kê đầy đủ verb (read / extract / merge / split / rotate / watermark / encrypt / OCR / fill forms).
- **Body opener**:
  > "This guide covers essential PDF processing operations using Python libraries and command-line tools. For advanced features, JavaScript libraries, and detailed examples, see REFERENCE.md. If you need to fill out a PDF form, read FORMS.md and follow its instructions."
- **Pattern**: SKILL.md là "entry doc" — pointer ra `reference.md` / `forms.md` cho deep-dive. Đây là **progressive disclosure** — chỉ load khi cần.

### 1.5 `docx` — bundled, similar pattern to xlsx

- **Path**: `.../skills/docx/`
- **Layout**: `SKILL.md` + `LICENSE.txt` + `scripts/`.
- **Frontmatter**: description dài (~ 140 từ), pattern xlsx (capability + file ext + casual phrase + anti-pattern).
- **Body table** ngay đầu:
  | Task | Approach |
  |---|---|
  | Read/analyze content | `pandoc` or unpack for raw XML |
  | Create new document | Use `docx-js` |
  | Edit existing document | Unpack → edit XML → repack |
  → Quick reference table giúp Claude pick path mà không phải đọc hết SKILL.md.

### 1.6 `skill-creator` — bundled, **canonical guidance về cách viết skill**

- **Path**: `.../skills/skill-creator/`
- **Layout**: `SKILL.md` + `LICENSE.txt` + `references/` + `scripts/`.
- **Authoritative quotes** (đáng nhớ cho Phase 1):
  - **Concise is key**: "The context window is a public good ... Default assumption: Claude is already very smart. Only add context Claude doesn't already have."
  - **Degrees of freedom**: low (specific scripts) cho fragile task; medium (pseudocode); high (text instructions) cho task có nhiều đường đúng. Cho `auto-test-skills`: framework detection = medium-low (script `detect.sh` + heuristic table); skill orchestration = high (Claude tự decide chạy layer nào).
  - **Anatomy required vs optional**:
    ```
    skill-name/
    ├── SKILL.md (REQUIRED)
    │   ├── frontmatter (required: name, description)
    │   └── markdown body (required)
    └── Bundled (optional): scripts/, references/, assets/
    ```
  - **What NOT to include**:
    > "A skill should only contain essential files that directly support its functionality. Do NOT create extraneous documentation or auxiliary files, including: README.md, INSTALLATION_GUIDE.md, QUICK_REFERENCE.md, CHANGELOG.md, etc."
  - **Three-level loading** (progressive disclosure):
    1. Metadata (name + description) — **always in context** (~ 100 words).
    2. SKILL.md body — loaded **after** skill triggers (< 5k words).
    3. References (`references/*.md`) — loaded on-demand by Claude (no size limit but mention grep patterns nếu > 10k words).

---

## 2. Frontmatter Field Reference (compiled từ 6 skill quan sát)

| Field | Required? | Type | Example | Semantic |
|---|---|---|---|---|
| `name` | **YES** | string (kebab-case) | `webapp-testing` | Identifier. Convention: matches folder name. |
| `description` | **YES** | string (1 line YAML, có thể quoted multi-sentence) | `"Use this skill any time a spreadsheet file ..."` | **Router input** — Claude đọc để decide trigger. Always in context. Best practice: liệt kê (a) trigger condition, (b) capability, (c) file ext / keyword, (d) anti-pattern. |
| `allowed-tools` | optional | comma-separated tool names | `Bash, Write` | Restrict tool set skill được phép invoke. Quan sát ở `drawio`. Nếu không có → skill có quyền dùng mọi tool của session. |
| `license` | optional | string (free-form, often pointer) | `Proprietary. LICENSE.txt has complete terms` | Metadata, không ảnh hưởng load. Bundled skills luôn có; user-level (drawio) không có. |
| `metadata` | optional (chưa thấy use trong sample) | object | — | Spec mention nhưng 0/6 skill khảo sát dùng. |
| `compatibility` | optional (chưa thấy use trong sample) | string/object | — | Skill-creator body mention "for noting environment requirements (target product, system packages)" — most skills không cần. |

> ⚠️ **Note**: `docs/ARCHITECTURE.md` §(c) example dùng field `tools: Bash, Read, Glob, Grep`. Quan sát thực tế (drawio) dùng `allowed-tools`. → Phase 1 SKILL.md **dùng `allowed-tools`** (đang là canonical trong skill thực tế). Cập nhật ARCHITECTURE.md sau khi Phase 0 sign-off.

---

## 3. File Layout Reference

| Folder / File | Convention | Loaded into context? | Mô đích | Quan sát ở |
|---|---|---|---|---|
| `SKILL.md` | **required**, root level | Body load sau khi trigger | Instructions cho Claude | All 6 |
| `scripts/` | optional | **Không** load tự động — invoke as black-box | Deterministic helper (Python/Bash). Skill body chỉ kể "run script X --help" | webapp-testing, xlsx, pdf, docx, skill-creator |
| `references/` | optional | Load **on-demand** khi Claude grep/Read | Detailed docs / schemas / domain knowledge | skill-creator |
| `examples/` | optional | Load on-demand | Sample input / output để Claude tham khảo | webapp-testing |
| `assets/` | optional | **Không** load — copy vào output | Templates, fonts, boilerplate | (chưa thấy ở 6 skill khảo sát; spec từ skill-creator) |
| `forms.md` / `reference.md` | optional, root level | Load on-demand (pointer từ SKILL.md) | Reference docs ngắn (alternative cho `references/<name>.md`) | pdf |
| `LICENSE.txt` | optional, root level | Không | Legal | webapp-testing, xlsx, pdf, docx, skill-creator |
| `README.md`, `CHANGELOG.md`, `INSTALLATION.md` | **AVOID** | — | (skill-creator: "Do NOT create extraneous documentation") | (đúng — 0/6 skill có) |

---

## 4. "Loadable" Criteria — Checklist

Từ quan sát + skill-creator guidance, skill được Claude Code discover & trigger nếu:

- [x] **Path**: ở `~/.claude/skills/<name>/` HOẶC `~/.claude/plugins/cache/<repo>/skills/<name>/` HOẶC `~/.claude/plugins/marketplaces/<repo>/skills/<name>/`.
- [x] **`SKILL.md` ở root** của folder (không nested).
- [x] **YAML frontmatter** parse được, có ít nhất `name` + `description`.
- [x] **Folder name = `name` field** (convention; chưa verify hard requirement — sẽ test T-0.2).
- [x] **Description đủ trigger keyword** để Claude match user prompt. Vague description = skill không bao giờ trigger (G5 in PRD).
- [ ] **Restart Claude Code session?** — PRD claim "không cần". Verify thực tế trong T-0.2.

---

## 5. Description-Writing Best Practices (cho Phase 1)

Từ pattern xlsx/docx/pdf, mỗi description nên có 4 thành phần:

1. **When to use** — "Use this skill any time / whenever ..."
2. **Capability** — verb list: read / write / edit / detect / parse / aggregate / report.
3. **Trigger keywords** — file extensions (.test.ts, package.json), tools (Bun, pytest, cargo), domain words (test, verify, kiểm tra).
4. **Anti-pattern** — "Do NOT trigger when ..." (giảm false positive G3).

**Sample cho `auto-test` skill (Phase 1)**:

```yaml
description: "Run all available test layers (unit, integration, browser) on the current
project and aggregate results into a centralized log + dashboard. Trigger when the user
or agent says 'test', 'verify', 'kiểm tra', 'chạy test', or asks to confirm a feature works
after vibe-coding. Auto-detects framework (Bun, npm, pytest, cargo, go test) from
package.json / pyproject.toml / Cargo.toml / go.mod. Returns pass/fail counts + path
to .test-runs/<timestamp>/run.json. Do NOT trigger for typecheck-only, lint-only, or
build-only requests — use those dedicated tools instead."
```

---

## 6. Implications cho `auto-test-skills` Phase 1

| Quan sát từ survey | Áp dụng Phase 1 |
|---|---|
| `description` là router — chi tiết = activation rate cao | Mỗi skill viết description theo template 4-phần (§5). G5 target ≥ 90%. |
| `scripts/` là black-box, không pollute context | `unit-test-runner/scripts/run.sh`, `test-log-centralizer/scripts/init-run.sh` — viết để invoke trực tiếp, có `--help`. |
| `references/` cho deep doc | `unit-test-runner/references/framework-detection.md` (heuristic table); `auto-test/references/timeout-policy.md`. |
| Không tạo README.md / CHANGELOG.md trong skill folder | User-facing doc ở repo root (`README.md`, `docs/`); skill folder chỉ chứa SKILL.md + scripts + references. |
| `allowed-tools` = canonical (vs ARCHITECTURE.md `tools`) | Phase 1 SKILL.md dùng `allowed-tools`. Update ARCHITECTURE.md sau Phase 0 sign-off. |
| Bundled skills đều có LICENSE.txt | Repo có 1 LICENSE root (MIT — task T-0.6); reference từ frontmatter (`license: MIT — see /LICENSE`). Tránh duplicate. |
| `xlsx` dùng anti-pattern "Do NOT trigger" để giảm noise | `auto-test` description nên có "Do NOT trigger for typecheck-only / lint-only / build-only". |
| `pdf` dùng pointer pattern (SKILL.md → forms.md / reference.md) | `auto-test/SKILL.md` ngắn (overview + decision tree); detail cho per-runner ở `references/<runner>.md`. |
| `webapp-testing` đã wrap Playwright | Phase 2 task 2.1 sẽ memo reuse. Note layout `examples/` để reuse pattern test scenario. |

---

## 7. Open Questions (resolve trong T-0.2 hoặc T-0.5)

1. **Restart required?** PRD nói "không cần"; spec không explicit. T-0.2 sẽ test bằng cách: drop `hello-test/` → invoke ngay → quan sát.
2. **Folder-name vs `name` mismatch** — Claude Code dùng cái nào để identify skill? Test bằng cách đặt folder `foo` chứa SKILL.md `name: bar`.
3. **`tools` vs `allowed-tools`** — field nào valid? Test bằng cách thử cả 2; đọc Claude Code release notes.
4. **Multiple skills cùng trigger trên 1 prompt** — orchestration ra sao? Claude pick 1, hay invoke tuần tự? Quan trọng cho meta-skill `auto-test`.
5. **Plugin packaging** — `~/.claude/plugins/cache/...` có cơ chế install/enable riêng (`/plugins enable`); user-drop ở `~/.claude/skills/` thì auto. Phase 1 v1 chọn drop-folder; v2 cân nhắc plugin packaging cho update flow.

---

## Appendix: Survey Method (reproducible)

```bash
# 1. List user-level skills
ls -la ~/.claude/skills/

# 2. Locate bundled marketplace
find ~/.claude -type d -name "document-skills" 2>/dev/null
# → ~/.claude/plugins/cache/anthropic-agent-skills/document-skills/<hash>/skills/

# 3. List bundled skill names
SKILLDIR=~/.claude/plugins/cache/anthropic-agent-skills/document-skills/1ed29a03dc85/skills
ls "$SKILLDIR"

# 4. Dump frontmatter + first 20 lines for each surveyed skill
for s in webapp-testing xlsx pdf docx skill-creator; do
  echo "=== $s ==="
  head -20 "$SKILLDIR/$s/SKILL.md"
  echo
done

# 5. List file layout per skill
for s in webapp-testing xlsx pdf docx skill-creator; do
  echo "=== $s ==="
  ls "$SKILLDIR/$s"
done

# 6. Read drawio user-level
head -50 ~/.claude/skills/drawio/SKILL.md
ls -la ~/.claude/skills/drawio/
```

Hash `1ed29a03dc85` có thể đổi sau plugin update — dùng `find` thay vì hardcode.
