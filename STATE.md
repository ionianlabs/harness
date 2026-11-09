---
repo: harness
updated: 2026-11-09
---

## Goal
A plugin (Claude Code first, Copilot later) that makes agent-built code trustworthy without ceremony: one coordinator thread, zero-context workers, hook-enforced gates. Design in `CONCEPT.md`.

## Active workstream
`docs/designs/read-gate-v2.md` fully built (F1 to F3), plus a speed pass on both hooks (one jq, one git per ordinary call). `docs/designs/coordinator-hands-off.md` approved; F1, F4, F5 built (worker agents, spec skills write through the drafter); F2, F3 (`hooks/handoff-gate.sh`) not built. Public beta 0.1.0 merged. 496 checks in `bash tests/run.sh`.

## Architecture
- `.claude-plugin/plugin.json`: manifest, MIT; skills and agents auto-discovered.
- `hooks/hooks.json`: PreToolUse `Read|Bash` -> `hooks/read-gate.sh` (skipped if it does not parse); `Bash` -> `hooks/commit-gate.sh`.
- `hooks/read-gate.sh`: whole-file reads over 350 lines denied; 350 distinct lines per agent and file across Read, cat, head, tail, `sed -n`, awk; main thread 3000 lines per session, then 40 at a time; denials name `lib/ask.sh`; loop guard at three; fails open.
- `hooks/commit-gate.sh`: only with a harness config; `--no-verify`, secret scan, unit suite, source needs a test change (`[no-tests]`); fails closed.
- `agents/`: `reader` (Haiku); `coder`, `reviewer`, `drafter` (Sonnet); `spec-paraphrase`, `spec-critic`, `spec-readiness` (Opus).
- `skills/`: `spec-draft`, `spec-review`, `tdd` (pointer to the coder), `state`.

## Decisions
- Main thread is the architect and user interface; workers code, draft and probe; it reviews their reports against requirements.
- Main thread detected by empty `agent_id`; roles by `agent_type`.
- Coders work in git worktrees; the installed plugin runs a separate pinned checkout that local git hooks advance only when the suite passes there. Reason: a half-edited hook once blocked every session.
- Denials point to a shell command every agent can run (read-gate-v2).
- `head` and `tail` without a count count 10 lines (read-gate-v2 amendment).
- The hand-off gate protects its own config; only the user turns it off (coordinator-hands-off).
- Protective gates fail closed, token-saving gates fail open.

## Debt
- Suite takes 60 to 80 s wall here (about 20 s CPU; endpoint security slows process starts); the 30 s rule in `AGENTS.md` needs a decision.
- Read gate: `<`, `$( )`, backslash continuations uncounted; multi-file `sed` counted per file.
- A main-thread small read costs one `lib/config.sh` call.
- Commit gate blind to commands built from variables and to heredocs run later.
- `lib/config.sh` flat TOML. No `claude plugin eval` cases.

## Next
Build coordinator-hands-off F2 and F3 (`hooks/handoff-gate.sh`) with a coder in a worktree, then a reviewer.
