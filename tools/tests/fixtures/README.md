# tools/tests/fixtures

Negative SKILL.md fixtures used by `tools/tests/test-validate-skill.sh`.

Each subfolder is a *deliberately broken* skill that must trigger a hard FAIL
in `tools/validate-skill.sh`. Do **not** copy these into `~/.claude/skills/` —
they are test-only.

| Folder | Defect | Linter check that should fail |
|---|---|---|
| `no-frontmatter/`   | no leading `---`           | check 3 |
| `missing-name/`     | no `name:` field           | check 4 |
| `missing-desc/`     | no `description:` field    | check 5 |
| `name-mismatch/`    | `name: foo`, folder ≠ foo  | check 6 |
| `desc-too-short/`   | description < 40 chars     | check 7 |
| `no-body/`          | empty body                 | check 8 |

Adding a new defect class? Drop a new folder + update this table + extend
`test-validate-skill.sh`.
