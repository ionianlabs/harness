# Ionian Harness

Build. The agentic engineering setup I use to build with agents: one coordinator thread, context-isolated workers, gates enforced by hooks rather than by instruction.

Status: milestone 1. Read gate, reader agent, commit gate, config loader, spec-draft, spec-review and tdd skills. Not ready for use.

Harness borrows from the best work I found: the zero-context review from Google's EGM, the TDD discipline from superpowers, the read gate from Spotify's shunt, the document shapes from spec-kit. I read them, learned, and built my own version. Where I kept their words, they are marked.

## What is here

- `hooks/read-gate.sh`: denies whole-file reads over 350 lines (Read, and cat/head/tail in bash) for everyone except the `reader` agent and the three spec reviewers; targeted reads pass; three denials of one file in a session and it lets go.
- `agents/reader.md`: Haiku, read-only, answers one question with line numbers.
- `skills/spec-draft`: the main thread drafts `docs/designs/<slug>.md` from a fixed template: features in priority order, each with a why, numbered Given/When/Then scenarios and a testability note, plus measurable success criteria.
- `skills/spec-review`: three zero-context reviewers (`agents/spec-paraphrase.md`, `spec-critic.md`, `spec-readiness.md`, Opus, read-only) review the draft, one re-audit, then forced convergence and your approval.
- `skills/tdd`: whoever writes code works one item test first: a test seen failing for the right reason, the smallest change, the whole unit suite green, one deliberate break per new test, one commit, a fixed report.
- `hooks/commit-gate.sh`: in repos with a harness config (`harness.toml`, or `~/.config/harness/<repo>.toml` for repos that must stay untouched), on `git commit`, refuses `--no-verify`, scans staged lines with gitleaks, runs the unit suite from `harness.toml`, and denies source changes that come without a test change (`[no-tests]` in the message is the documented escape).
- `lib/config.sh`: reads `harness.toml` (repo, then `~/.config/harness/<repo>.toml`).
- `tests/run.sh`: the hooks' own unit tests, fake payloads in, exit codes out. This repo's `harness.toml` points its commit gate at them.
- Every decision is logged to `.git/harness/gate.log`.

## Try the read gate

    cd <path-to-harness> && git init -q
    claude --plugin-dir .

Then: `What does line 200 of dev/big.txt say?` (denied once, reader dispatched, targeted read passes) and `Read dev/big.txt lines 10 to 12.` (passes directly).

License: MIT.
