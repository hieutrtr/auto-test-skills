---
name: hello-test
description: Phase-0 spike probe used to verify Claude Code skill discovery and triggering. Trigger ONLY when the user message contains the literal phrase "hello-test ping" — no paraphrases, no partial matches. Output is a single fixed acknowledgement string with the current ISO-8601 UTC timestamp, produced by running a one-liner Bash command. Do NOT trigger on the words "hello", "test", "ping" individually, on phrases like "hello world", "say hello", "ping me", or any other variant. This skill exists purely as a fingerprint for the auto-test-skills repo Phase 0 spike to confirm that user-level skills dropped at ~/.claude/skills/<name>/SKILL.md are auto-discovered. Safe to delete after Phase 0 sign-off.
allowed-tools: Bash
---

# Hello-Test — Phase 0 Spike Skill

> Minimal probe skill used during the `auto-test-skills` Phase 0 spike (created
> 2026-05-05) to validate that Claude Code discovers + auto-triggers user-level
> skills dropped at `~/.claude/skills/<name>/SKILL.md`. Intentionally narrow
> trigger so that any successful activation can be unambiguously attributed to
> this skill rather than to a generic Claude response. Safe to delete after
> Phase 0 sign-off.

## When to use

Trigger **only** when the user message contains the exact literal phrase:

```
hello-test ping
```

This is a unique fingerprint — it does not appear in normal English usage, so
any activation can be attributed to this skill firing rather than to a default
Claude response. Do **not** activate on:

- The word "hello" alone, "test" alone, or "ping" alone.
- Paraphrases such as "hello world", "ping the hello-test", "say hello in a
  test", "run a hello world test".
- Tangentially related requests like "test hello.ts" or "is the test passing?".

If the user's message does not contain the literal substring `hello-test ping`,
do nothing — defer to other skills or a normal response.

## How to respond

When triggered, run exactly one Bash command and return its output verbatim,
followed by one acknowledgement line.

```bash
echo "HELLO-TEST-PONG $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

Then add this single line, unchanged:

```
Skill 'hello-test' fired correctly — Phase 0 skill-loading validation passed.
```

Do not perform any file writes, network calls, or further investigation.

## Examples

User: `hello-test ping`
Assistant: runs the bash command, then prints both lines. Example output:

```
HELLO-TEST-PONG 2026-05-05T10:00:00Z
Skill 'hello-test' fired correctly — Phase 0 skill-loading validation passed.
```

User: `hello world`
Assistant: does **not** invoke this skill — phrase does not match.

User: `please run a test`
Assistant: does **not** invoke this skill — phrase does not match.

User: `hello-test ping please confirm`
Assistant: invokes the skill (literal substring is present).
