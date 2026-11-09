---
repo: harness
updated: 2026-11-09
---

## Goal
A plugin (Claude Code first, Copilot later) that makes agent-built code trustworthy without ceremony: one coordinator thread, zero-context workers, hook-enforced gates. Design in `CONCEPT.md`.

## Active workstream
Preparing the public beta (0.1.0): README, plugin manifest and stale facts fixed on branch `beta`. Both specs are approved and committed. Built so far: `lib/ask.sh`, the per-agent line budget on the read gate (Read and Bash forms), the coder, reviewer and drafter agents, and spec-draft and spec-review routing writes through the drafter. Not built: `hooks/handoff-gate.sh` and the main-thread session read budget. 433 checks in `bash tests/run.sh`.

## Architecture
- `.claude-plugin/plugin.json`: manifest, MIT; skills and agents auto-discovered.
- `hooks/hooks.json`: PreToolUse `Read|Bash` -> `hooks/read-gate.sh`; `Bash` -> `hooks/commit-gate.sh`.
- `hooks/read-gate.sh`: denies untargeted reads over 350 lines; images and PDFs pass; exempt `reader` and `spec-*`; loop guard at three; fails open.
- `hooks/commit-gate.sh`: only with a harness config; `--no-verify`, secret scan, unit suite, source needs a test change (`[no-tests]`); fails closed.
- `agents/`: `reader` (Haiku), `coder`, `reviewer`, `drafter` (Sonnet), `spec-paraphrase`, `spec-critic`, `spec-readiness` (Opus).
- `lib/ask.sh`: headless Haiku answers a question about files; every read denial points to it.
- `skills/`: `spec-draft`, `spec-review`, `tdd`, `state`.

## Decisions
- Main thread is the architect and user interface; workers do code, specs and probes; it reviews their reports against requirements.
- Main thread detected by empty `agent_id`; roles by `agent_type`.
- Denials point to a shell command every agent can run, not an agent dispatch (read-gate-v2).
- The hand-off gate protects its own config; only the user turns it off (coordinator-hands-off).
- Protective gates fail closed, token-saving gates fail open.
- Own wording throughout; sources are credited in `README.md` and `CONCEPT.md`.

## Debt
- Read gate: `sed -n`, `awk`, `<`, `$( )` uncounted.
- `tests/run.sh` payloads without `cwd` log into this repo's own `gate.log`.
- Commit gate blind to commands built from variables and to heredocs run later.
- `lib/config.sh` flat TOML. No `claude plugin eval` cases. Suite near its 30 s budget.

## Next
Build the hand-off gate from `docs/designs/coordinator-hands-off.md` with a coder worker, test first.
