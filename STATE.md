---
repo: harness
updated: 2026-11-03
---

## Goal
A plugin (Claude Code first, Copilot later) that makes agent-built code trustworthy without ceremony: one coordinator thread, zero-context workers, hook-enforced gates. Design in `CONCEPT.md`.

## Active workstream
Milestone 1 floor built and in daily use at user level. This session: commit gate hardened (`git -C`, bypass flags read from the commit's own arguments, unparseable payload denied, `commit-tree` denied, heredoc bodies fed to non-shell commands read as data), read gate closes the gaps found in shunt's edge cases, home config under `$IONIAN_HOME/harness/`, `state` skill, CONCEPT section 6b "Works with Ionian Brain", `tests/compat-brain.sh` (5/5 pass), repo rules moved to `AGENTS.md`, repo made publishable (Ionian Labs author, MIT `LICENSE`). 102 checks in `bash tests/run.sh`. Remaining: two weeks on the pilot repo.

## Architecture
- `.claude-plugin/plugin.json`: manifest, MIT; skills and agents auto-discovered.
- `hooks/hooks.json`: PreToolUse `Read|Bash` -> `hooks/read-gate.sh`; `Bash` -> `hooks/commit-gate.sh`.
- `hooks/read-gate.sh`: denies untargeted reads over 350 lines; exempt `reader` and `spec-*`, bare or `ionian-harness:`-prefixed; loop guard at three; fails open.
- `hooks/commit-gate.sh`: only in repos with a harness config; `--no-verify`, secret scan, unit suite, source needs a test change (`[no-tests]`); fails closed.
- `lib/config.sh`: repo `harness.toml`, then `$IONIAN_HOME/harness/<repo>.toml` (default `~/Ionian`).
- `agents/`: `reader` (Haiku), `spec-paraphrase`, `spec-critic`, `spec-readiness` (Opus, read-only).
- `skills/`: `spec-draft`, `spec-review`, `tdd`, `state`.
- `tests/run.sh`: unit suite; `tests/compat-brain.sh`: manual, headless, costs tokens.

## Decisions
- Protective gates fail closed, token-saving gates fail open.
- Plugin agents arrive as `ionian-harness:<name>`; gates strip only that prefix.
- Harness artefacts (`AGENTS.md`, `STATE.md`, `docs/designs/`, `harness.toml`) live in the project repo.
- Harness never reads or writes a brain; session end is `state`, then `brain:handover` if Brain is installed (CONCEPT 6b).
- Spec reviewers get paths only; re-audit adds prior findings without resolutions.
- First spec through the full loop: `docs/designs/commit-gate-shell-tests.md`.
- Own wording throughout, so no `THIRD_PARTY.md` yet.

## Debt
- Read gate open: `<` redirect, `sed -n`, `awk`, `$( )`. Pinned: outside git the counter sits in `/tmp/harness`.
- Commit gate blind to `g=git; $g commit` (commands built from variables) and to a heredoc written to a file that a later line runs with a shell.
- `lib/config.sh` flat TOML. Secret scan untested live. No `claude plugin eval` cases.

## Next
Two weeks of use on the pilot repo (Ionian Flow, after its migration), then the milestone 1 lessons entry.
