---
repo: harness
updated: 2026-11-03
---

## Goal
An installable plugin (Claude Code first, Copilot port later) that makes agent-built code trustworthy without ceremony for small changes: one coordinator thread, zero-context workers, gates enforced by hooks. Design in `CONCEPT.md`.

## Active workstream
Milestone 1, the bare floor. Done: read gate with Haiku reader agent, commit gate, config loader, spec-draft and spec-review skills with three reviewer agents, hook unit tests (21 checks, `bash tests/run.sh`). Remaining for the floor: TDD skill for the coder, then two weeks of use on the pilot repo before any lane or further role.

## Architecture
- `.claude-plugin/plugin.json`: manifest, MIT. Skills and agents auto-discovered.
- `hooks/hooks.json`: PreToolUse `Read|Bash` -> `hooks/read-gate.sh`; PreToolUse `Bash` -> `hooks/commit-gate.sh` (timeout 180).
- `hooks/read-gate.sh`: denies whole-file reads over 350 lines. Exempt: `reader`, `spec-paraphrase`, `spec-critic`, `spec-readiness`. Loop guard at three denials. Fails open.
- `hooks/commit-gate.sh`: `--no-verify` denied, secret scan, unit suite, source needs test change (`[no-tests]` escape). Fails closed.
- `lib/config.sh`: flat TOML reader, repo `harness.toml` then `~/.config/harness/<repo>.toml`.
- `agents/reader.md`: Haiku, bullets with line ranges.
- `skills/spec-draft/`: SKILL.md plus `template.md`; writes `docs/designs/<slug>.md`, never approves.
- `skills/spec-review/`: round 1 paraphrase then critic and readiness in parallel, one re-audit, forced convergence, user approval. Raw replies in `.git/harness/review/<slug>/`.
- `agents/spec-*.md`: Opus, Read only (readiness also Grep, Glob), fixed reply formats, Blocker/Major/Nit.

## Decisions
- Hook payload: main thread `agent_id`/`agent_type` null, subagents carry both. Role gates key on `agent_type`.
- Protective gates fail closed, token-saving gates fail open.
- Spec reviewers are agent files, not inline prompts: pinned model, read-only tools, an `agent_type` the read gate can exempt. They cannot dispatch the reader, so a denial would not resolve.
- Dispatch to reviewers carries paths only; re-audit adds prior findings without resolutions.
- Own wording throughout; nothing kept close to EGM, so no `THIRD_PARTY.md` yet.

## Debt
- Skills and reviewer agents not yet run live on a real spec.
- Exemption assumes plugin agents report bare `agent_type` (verified for `reader` only).
- Commit gate skips the test-change rule for `hooks/*.sh` and `lib/*.sh`, although the repo rule wants a test per hook change.
- `lib/config.sh` flat TOML only. Secret scan syntax not exercised live. Source glob heuristic. No `claude plugin eval` cases.

## Next
Run spec-draft and spec-review live on one small spec (a read-gate denial for a `spec-*` agent in `.git/harness/gate.log` means its `agent_type` is namespaced), then write the coder TDD skill.
