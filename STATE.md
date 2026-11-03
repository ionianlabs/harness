---
repo: harness
updated: 2026-11-03
---

## Goal
A plugin (Claude Code first, Copilot later) that makes agent-built code trustworthy without ceremony: one coordinator thread, zero-context workers, hook-enforced gates. Design in `CONCEPT.md`.

## Active workstream
Milestone 1, bare floor. Done: read gate and reader agent, commit gate, config loader, spec skills with three reviewers (one spec through to code), tdd skill (not used live), 26 checks in `bash tests/run.sh`. Remaining: wiring check with the plugin loaded, then two weeks on the pilot repo.

## Architecture
- `.claude-plugin/plugin.json`: manifest, MIT. Skills and agents auto-discovered.
- `hooks/hooks.json`: PreToolUse `Read|Bash` -> read gate; `Bash` -> commit gate (timeout 180).
- `hooks/read-gate.sh`: denies whole-file reads over 350 lines. Exempt: `reader`, `spec-paraphrase`, `spec-critic`, `spec-readiness`. Loop guard at three denials. Fails open.
- `hooks/commit-gate.sh`: `--no-verify` denied, secret scan, unit suite, source needs test change (`[no-tests]` escape). Fails closed.
- `lib/config.sh`: flat TOML reader, repo `harness.toml` then `~/.config/harness/<repo>.toml`.
- `agents/reader.md`: Haiku, bullets, line ranges.
- `skills/spec-draft/`: SKILL.md plus `template.md`; writes `docs/designs/<slug>.md`, never approves.
- `skills/spec-review/`: paraphrase, then critic and readiness in parallel, one re-audit, user approval. Replies in `.git/harness/review/<slug>/`.
- `skills/tdd/`: one item test first, deliberate break per new test, staged by name, fixed report with status.
- `agents/spec-*.md`: Opus, read-only (critic and readiness also Grep, Glob), fixed replies, Blocker/Major/Nit.

## Decisions
- Hook payload: main thread `agent_id`/`agent_type` null, subagents carry both. Role gates key on `agent_type`.
- Protective gates fail closed, token-saving gates fail open.
- Spec reviewers are agent files: pinned model, read-only tools, an `agent_type` the read gate can exempt (they cannot dispatch the reader).
- Dispatch to reviewers carries paths only; re-audit adds prior findings without resolutions.
- Own wording throughout, so no `THIRD_PARTY.md` yet.

## Debt
- Read gate gaps in `docs/study/shunt.md` (`2>/dev/null`, quoted paths, chained commands, large `head -n`, state in /tmp): pin in tests or fix.
- Spec reviewers ran once as general-purpose agents (plugin not loaded): tool limits and bare `agent_type` exemption unverified (verified for `reader` only). They had no Grep or Glob.
- Commit gate regex misses `git -c k=v commit` and `bash -c "git commit"`.
- `lib/config.sh` flat TOML only. Secret scan untested live. Source glob heuristic. No `claude plugin eval` cases.

## Next
With `claude --plugin-dir .`: have `spec-critic` and `spec-readiness` list their tools and Read `dev/big.txt` whole (no `gate.log` line: exemption matched). Then tdd live on the gate regex debt.
