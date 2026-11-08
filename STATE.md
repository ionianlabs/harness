---
repo: harness
updated: 2026-11-08
---

## Goal
A plugin (Claude Code first, Copilot later) that makes agent-built code trustworthy without ceremony: one coordinator thread, zero-context workers, hook-enforced gates. Design in `CONCEPT.md`.

## Active workstream
Pilot logs: read gate barely acts (7 of 10 denials were screenshots, reader never dispatched, subagents told to do what they cannot); nothing enforces delegation. Quick fixes shipped (3f70237). Two specs, worker-drafted and through spec-review, `Status: reviewed`, awaiting approval, uncommitted:
- `docs/designs/read-gate-v2.md`: `lib/ask.sh` (headless Haiku answers questions about files, target of every denial), per-agent per-file line budget across read forms, main-thread session read budget.
- `docs/designs/coordinator-hands-off.md`: coder, reviewer, drafter agents (Sonnet, rules inline); spec-draft and spec-review route writes through the drafter; `hooks/handoff-gate.sh` denies main-thread repo writes (file tools and common Bash forms) and protects the harness config.
Wording: sources framed as established practices we build on (1e136e7). 112 checks in `bash tests/run.sh`.

## Architecture
- `.claude-plugin/plugin.json`: manifest, MIT; skills and agents auto-discovered.
- `hooks/hooks.json`: PreToolUse `Read|Bash` -> `hooks/read-gate.sh`; `Bash` -> `hooks/commit-gate.sh`.
- `hooks/read-gate.sh`: denies untargeted reads over 350 lines; images and PDFs pass; exempt `reader` and `spec-*`; loop guard at three; fails open.
- `hooks/commit-gate.sh`: only with a harness config; `--no-verify`, secret scan, unit suite, source needs a test change (`[no-tests]`); fails closed.
- `agents/`: `reader` (Haiku), `spec-paraphrase`, `spec-critic`, `spec-readiness` (Opus).
- `skills/`: `spec-draft`, `spec-review`, `tdd`, `state`.

## Decisions
- Main thread is the architect and user interface; workers do code, specs and probes; it reviews their reports against requirements.
- Main thread detected by empty `agent_id`; roles by `agent_type`.
- Denials point to a shell command every agent can run, not an agent dispatch (read-gate-v2).
- The hand-off gate protects its own config; only the user turns it off (coordinator-hands-off).
- Protective gates fail closed, token-saving gates fail open.
- Own wording throughout, so no `THIRD_PARTY.md` yet.

## Debt
- Read gate: `||` is not split, so `cat big || true` passes (fixed by read-gate-v2 F2.24); `sed -n`, `awk`, `<`, `$( )` uncounted.
- `tests/run.sh` payloads without `cwd` log into this repo's own `gate.log`.
- Commit gate blind to commands built from variables and to heredocs run later.
- `lib/config.sh` flat TOML. No `claude plugin eval` cases. Suite near its 30 s budget.
- Pre-push guard refuses until the publish triage.

## Next
User approves both specs, then build read-gate-v2 F1 with a coder worker, test first.
