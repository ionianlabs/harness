---
repo: harness
updated: 2026-11-03
---

## Goal
A plugin (Claude Code first, Copilot later) that makes agent-built code trustworthy without ceremony: one coordinator thread, zero-context workers, hook-enforced gates. Design in `CONCEPT.md`.

## Active workstream
Milestone 1, bare floor. Done: read gate and reader agent, commit gate, config loader, spec skills with three reviewers (one spec through to code), tdd skill (used on two gate fixes), 45 checks in `bash tests/run.sh`. Plugin wiring verified headless: exemptions match, reviewers have Grep and Glob. Remaining: two weeks on the pilot repo.

## Architecture
- `.claude-plugin/plugin.json`: manifest, MIT. Skills and agents auto-discovered.
- `hooks/hooks.json`: PreToolUse `Read|Bash` -> read gate; `Bash` -> commit gate (timeout 180).
- `hooks/read-gate.sh`: denies whole-file reads over 350 lines. Exempt: `reader` and the three `spec-*`, bare or `ionian-harness:`-prefixed. Loop guard at three denials. Fails open.
- `hooks/commit-gate.sh`: only in repos with a harness config (repo or home); `--no-verify` denied, secret scan, unit suite, source needs test change (`[no-tests]` escape). Fails closed.
- `lib/config.sh`: flat TOML reader, repo `harness.toml` then `~/.config/harness/<repo>.toml`.
- `agents/reader.md`: Haiku, bullets, line ranges.
- `skills/spec-draft/`: SKILL.md plus `template.md`; writes `docs/designs/<slug>.md`, never approves.
- `skills/spec-review/`: paraphrase, then critic and readiness in parallel, one re-audit, user approval. Replies in `.git/harness/review/<slug>/`.
- `skills/tdd/`: one item test first, deliberate break per new test, staged by name, fixed report with status.
- `agents/spec-*.md`: Opus, read-only (critic and readiness also Grep, Glob), fixed replies, Blocker/Major/Nit.

## Decisions
- Hook payload: main thread `agent_id`/`agent_type` null, subagents carry both. Plugin agents arrive as `ionian-harness:<name>` (verified headless 2026-11-03); role gates strip only that prefix.
- Protective gates fail closed, token-saving gates fail open.
- Spec reviewers are agent files: pinned model, read-only tools, an `agent_type` the read gate can exempt (they cannot dispatch the reader).
- Dispatch to reviewers carries paths only; re-audit adds prior findings without resolutions.
- Own wording throughout, so no `THIRD_PARTY.md` yet.

## Debt
- Read gate gaps in `docs/study/shunt.md` (`2>/dev/null`, quoted paths, chained commands, large `head -n`, state in /tmp): pin in tests or fix.
- Commit gate exits 0 on an unparseable payload (fails open). It cannot see `git commit-tree` or commands built from variables (`g=git; $g commit`).
- `lib/config.sh` flat TOML only. Secret scan untested live. Source glob heuristic. No `claude plugin eval` cases.

## Next
Two weeks of use on the pilot repo (Ionian Flow, after its migration), then the milestone 1 lessons entry. Headless plugin checks: `claude -p --plugin-dir . --output-format stream-json --verbose`.
