# Ionian Harness

Build. The agentic engineering setup we use to build with agents: one coordinator thread, context-isolated workers, gates enforced by hooks rather than by instruction.

Status: milestone 1. Read gate, reader agent, commit gate, config loader, spec-draft, spec-review and tdd skills. Not ready for use.

Harness brings together established practices and standards for building with agents: zero-context review as described in Google's EGM, test-driven development as practised in superpowers, a read gate after Spotify's shunt, and the document formats of spec-kit. Every file is our own implementation. Where a passage stays close to its source, it is marked and credited.

## What is here

- `hooks/read-gate.sh`: denies whole-file reads over 350 lines (Read, and cat/head/tail in bash) for everyone except the `reader` agent and the three spec reviewers; targeted reads pass; three denials of one file in a session and it lets go.
- `agents/reader.md`: Haiku, read-only, answers one question with line numbers.
- `skills/spec-draft`: the main thread drafts `docs/designs/<slug>.md` from a fixed template: features in priority order, each with a why, numbered Given/When/Then scenarios and a testability note, plus measurable success criteria.
- `skills/spec-review`: three zero-context reviewers (`agents/spec-paraphrase.md`, `spec-critic.md`, `spec-readiness.md`, Opus, read-only) review the draft, one re-audit, then forced convergence and your approval.
- `skills/state`: rewrites `STATE.md` in the repo root at session end, a fixed template under 400 words, status only. Run it before `brain:handover` if you use Ionian Brain.
- `skills/tdd`: whoever writes code works one item test first: a test seen failing for the right reason, the smallest change, the whole unit suite green, one deliberate break per new test, one commit, a fixed report.
- Works with Ionian Brain: see CONCEPT.md section 6b. `tests/compat-brain.sh` is the manual check.
- `hooks/commit-gate.sh`: in repos with a harness config (`harness.toml`, or `$IONIAN_HOME/harness/<repo>.toml` (default `~/Ionian`) for repos that must stay untouched), on `git commit`, refuses `--no-verify` (read from the commit's own arguments) and `git commit-tree`, follows `git -C <dir>`, scans staged lines with gitleaks, runs the unit suite from `harness.toml`, and denies source changes that come without a test change (`[no-tests]` in the message is the documented escape).
- `lib/config.sh`: reads `harness.toml` (repo, then `$IONIAN_HOME/harness/<repo>.toml` (default `~/Ionian`)).
- `tests/run.sh`: the hooks' own unit tests, fake payloads in, exit codes out. This repo's `harness.toml` points its commit gate at them.
- Every decision is logged to `.git/harness/gate.log`.

## Install for yourself (user level)

    ln -s <path-to-harness> ~/.claude/skills/ionian-harness

Loads in every new session as `ionian-harness@skills-dir`; each commit here is live in the next session. The read gate is on everywhere. The commit gate acts only in repos with `harness.toml`, or with `$IONIAN_HOME/harness/<repo>.toml` (default `~/Ionian`) for repos that must stay untouched, for example:

    [test]
    unit = "pytest -q tests/unit"
    dir  = "tests"

Remove with `rm ~/.claude/skills/ionian-harness` (the link only).

## Try the read gate

    cd <path-to-harness> && git init -q
    claude --plugin-dir .

Then: `What does line 200 of dev/big.txt say?` (denied once, reader dispatched, targeted read passes) and `Read dev/big.txt lines 10 to 12.` (passes directly).

License: MIT.
