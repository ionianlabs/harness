---
repo: harness
updated: 2026-11-03
---

## Goal
An installable plugin (Claude Code first, Copilot port later) that makes agent-built code trustworthy without ceremony for small changes: one coordinator thread, zero-context workers, gates enforced by hooks. Design in `CONCEPT.md`.

## Active workstream
Milestone 1, the bare floor. Built and verified live this session: read gate with Haiku reader agent, commit gate, config loader, hook unit tests (17 checks, `bash tests/run.sh`). Plugin loads with `claude --plugin-dir .`; `hooks/hooks.json` registers both gates, scripts run via `bash` so execute bits do not matter. Remaining for the floor: spec-draft and spec-review skills (three stages: paraphrase test, critic, implementation readiness), TDD skill for the coder, then two weeks of use on the pilot repo before any lane or further role.

## Architecture
- `.claude-plugin/plugin.json`: manifest, MIT.
- `hooks/hooks.json`: PreToolUse `Read|Bash` -> `hooks/read-gate.sh`; PreToolUse `Bash` -> `hooks/commit-gate.sh` (timeout 180).
- `hooks/read-gate.sh`: denies whole-file reads over 350 lines (Read without offset/limit; cat/less/more, head/tail without -n/-c in bash). `agent_type: reader` exempt. Three denials of one file per session, then allowed. Fails open.
- `hooks/commit-gate.sh`: on `git commit`, denies `--no-verify`, runs secret scan and unit suite from `harness.toml`, denies source change without test change (`[no-tests]` escape). Fails closed when jq or `lib/config.sh` missing.
- `lib/config.sh`: flat TOML reader, `harness.toml` in repo then `~/.config/harness/<repo>.toml`.
- `agents/reader.md`: Haiku, Read/Grep/Glob, bullets with line ranges only.
- `tests/run.sh`: fake payloads in, exit codes out; this repo's own `harness.toml` points the commit gate at it.
- Per-call audit in `.git/harness/gate.log`.

## Decisions
- Hook payload verified: main thread has `agent_id`/`agent_type` null, subagents carry both. All role gates key on `agent_type`.
- Protective gates fail closed, token-saving gates fail open. A crashing hook is "non-blocking" in Claude Code, so a broken commit gate would silently vanish.
- Denial messages never mention the loop guard; it would invite retries.
- Borrow concepts, write own files; attribute in README. No upstream plugin installed.

## Debt
- `lib/config.sh` parses flat TOML only (no arrays, no nested tables).
- Secret scan default assumes gitleaks 8.19+ CLI syntax; not yet exercised live.
- Source-file glob and test-dir rule are heuristics; expect false positives on config-only commits.
- No `claude plugin eval` cases yet, only `tests/run.sh`.

## Next
Write `skills/spec-draft/SKILL.md` and `skills/spec-review/SKILL.md` with three zero-context reviewer personas, from the design in `CONCEPT.md` section 3 and 6.
