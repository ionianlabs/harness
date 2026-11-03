---
repo: harness
updated: 2026-11-03
---

## Goal
A plugin (Claude Code first, Copilot later) that makes agent-built code trustworthy without ceremony: one coordinator thread, zero-context workers, hook-enforced gates. Design in `CONCEPT.md`.

## Active workstream
Milestone 1, bare floor. Done: read gate, reader, commit gate, config loader, spec skills with three reviewers, tdd skill, 61 checks in `bash tests/run.sh`. Installed at user level (`~/.claude/skills/ionian-harness` symlink). Remaining: two weeks on the pilot repo.

## Architecture
- `.claude-plugin/plugin.json`: manifest, MIT; loads as `ionian-harness@skills-dir` through the symlink.
- `hooks/hooks.json`: PreToolUse `Read|Bash` -> read gate; `Bash` -> commit gate (timeout 180).
- `hooks/read-gate.sh`: denies whole-file reads over 350 lines. Exempt: `reader` and the three `spec-*`, bare or `ionian-harness:`-prefixed. Loop guard at three denials. Fails open.
- `hooks/commit-gate.sh`: only in repos with a harness config (repo or home); `--no-verify` denied, secret scan, unit suite, source needs test change (`[no-tests]` escape). Fails closed.
- `lib/config.sh`: flat TOML reader, repo `harness.toml` then `$IONIAN_HOME/harness/<repo>.toml`.
- `agents/reader.md`: Haiku, bullets, line ranges.
- `skills/spec-draft/`: SKILL.md plus `template.md`; writes `docs/designs/<slug>.md`, never approves.
- `skills/spec-review/`: paraphrase, then critic and readiness in parallel, one re-audit, user approval. Replies in `.git/harness/review/<slug>/`.
- `skills/tdd/`: one item test first, deliberate break per new test, staged by name, fixed report with status.
- `agents/spec-*.md`: Opus, read-only (critic and readiness also Grep, Glob), fixed replies, Blocker/Major/Nit.

## Decisions
- Hook payload: main thread `agent_id`/`agent_type` null, subagents carry both. Plugin agents arrive as `ionian-harness:<name>`; gates strip only that prefix.
- Protective gates fail closed, token-saving gates fail open.
- Spec reviewers are agent files: pinned model, read-only tools, an exemptable `agent_type`.
- Dispatch to reviewers carries paths only; re-audit adds prior findings without resolutions.
- Own wording, so no `THIRD_PARTY.md`.

## Debt
- Read gate open: `<` redirect, `sed -n`, `awk`, `$( )`. Pinned: outside git the counter sits in `/tmp/harness`.
- Commit gate blind to `g=git; $g commit` (commands built from variables).
- `lib/config.sh` flat TOML. Secret scan untested live. No `claude plugin eval` cases.

## Next
Two weeks of use on the pilot repo (Ionian Flow, after its migration), then the milestone 1 lessons entry. Headless plugin checks: `claude -p --plugin-dir . --output-format stream-json --verbose`.
