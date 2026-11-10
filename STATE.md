---
repo: harness
updated: 2026-11-10
---

## Goal
A plugin (Claude Code first, Copilot later) that makes agent-built code trustworthy without ceremony: one coordinator thread, zero-context workers, hook-enforced gates. Design in `CONCEPT.md`.

## Active workstream
`docs/designs/read-gate-v2.md` built (F1 to F3) plus a hook speed pass. `docs/designs/coordinator-hands-off.md`: F1, F4, F5 built; F2, F3 (`hooks/handoff-gate.sh`) open. Public beta 0.1.0 is on GitHub, installable via the `ionianlabs` marketplace; install verified. 496 checks in `bash tests/run.sh`.

## Architecture
- `.claude-plugin/plugin.json`: manifest, MIT; skills and agents auto-discovered.
- `hooks/hooks.json`: PreToolUse `Read|Bash` -> `hooks/read-gate.sh` (skipped if it does not parse); `Bash` -> `hooks/commit-gate.sh`.
- `hooks/read-gate.sh`: whole-file reads over 350 lines denied; 350 distinct lines per agent and file across Read, cat, head, tail, `sed -n`, awk; main thread 3000 lines per session, then 40 at a time; denials name `lib/ask.sh`; loop guard at three; fails open.
- `hooks/commit-gate.sh`: only with a harness config; `--no-verify`, secret scan, unit suite, source needs a test change (`[no-tests]`); fails closed.
- `agents/`: `reader` (Haiku); `coder`, `reviewer`, `drafter` (Sonnet); `spec-paraphrase`, `spec-critic`, `spec-readiness` (Opus).
- `skills/`: `spec-draft`, `spec-review`, `tdd` (pointer to the coder), `state`.

## Decisions
- Main thread is the architect; workers code, draft and probe; it checks their reports.
- Main thread detected by empty `agent_id`; roles by `agent_type`.
- Coders work in worktrees; the live plugin is a pinned checkout that advances only on a green suite: a half-edited hook once blocked every session.
- Denials point to a shell command every agent can run (read-gate-v2).
- `head` and `tail` without a count count 10 lines (read-gate-v2 amendment).
- The hand-off gate protects its own config; only the user turns it off (coordinator-hands-off).
- Protective gates fail closed, token-saving gates fail open.
- Shared `ionianlabs` marketplace, status BETA; every push passes the publish triage; no benefit numbers until measured.

## Debt
- Suite takes 60 to 80 s wall (about 20 s CPU); the 30 s rule in `AGENTS.md` needs a decision.
- Read gate: `<`, `$( )`, backslash continuations uncounted; multi-file `sed` counted per file.
- A main-thread small read costs one `lib/config.sh` call.
- Commit gate blind to commands built from variables and to heredocs run later.
- `lib/config.sh` flat TOML. No `claude plugin eval` cases.
- No objective measure of tokens saved or quality gained yet.

## Next
Build coordinator-hands-off F2 and F3 (`hooks/handoff-gate.sh`) with a coder in a worktree, then a reviewer.
