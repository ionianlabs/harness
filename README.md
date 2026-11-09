# Ionian Harness.

Harness is a plugin for Claude Code that makes agent-built code easier to trust. I wrote it for how I build: a spec before code, a test before a change, zero-context reviewers who check the work, and a read gate that keeps big files out of the main chat. Hooks enforce the rules that matter, so they do not depend on the model remembering an instruction.

## Status.

Beta: you can install and use it, and it is still changing.

Not built yet:

- A handoff gate that stops the main thread from writing repo files itself (the spec is approved, the hook is not written).
- The lane commands `/fix`, `/change` and `/build`.
- A `qa` agent.
- A `harness` command line tool.
- Dependency, merge and loop-stop hooks.
- A GitHub Copilot port.

Known limits:

- The commit gate cannot see commands built from variables, or heredocs that run later.
- The read gate does not count reads made with `<` or `$( )`.
- I develop and test on macOS only.

## Install.

    /plugin marketplace add ionianlabs/brain
    /plugin install ionian-harness@ionianlabs

The ionianlabs marketplace lives in the Brain repo and lists all Ionian Labs plugins. If you already use Brain, you only need the second line.

To try it without installing: `claude --plugin-dir <path-to-this-repo>`.

Requirements: bash, git and jq. Optional: gitleaks for the secret scan on commit, and the `claude` command line tool for `lib/ask.sh`, which the read gate points to when it denies a read.

## Set up a repo.

The read gate works everywhere once the plugin is on. The commit gate acts only in a repo that has a `harness.toml` at its root. This repo's own file is the smallest real example:

    [test]
    unit = "bash tests/run.sh"
    dir  = "tests"

    [security]
    secrets = "gitleaks git --pre-commit --staged --redact --no-banner"

    [gate]
    require_tests = true

    [limits]
    unit_seconds = 30

`unit` is the command the gate runs before each commit. With `require_tests` on, a commit that changes source without changing a test is denied. Put `[no-tests]` in the message of a commit that truly needs no test, such as docs. Every gate decision is logged to `.git/harness/gate.log`.

## What is inside.

Spec

- `spec-draft`: asks you a few ranked questions, then has the `drafter` agent write `docs/designs/<slug>.md` from a fixed template with numbered Given/When/Then scenarios.
- `spec-review`: three zero-context reviewers (`spec-paraphrase`, `spec-critic`, `spec-readiness`) check the draft, the drafter fixes it, and you approve.

Build

- `tdd`: behaviour changes go to the `coder` agent with an item brief. It sees a test fail for the right reason, makes the smallest change, runs the whole unit suite and commits.

Review

- `reviewer` agent: checks one finished commit against a fixed checklist and returns a punch-list. It edits nothing.

Hand off

- `state`: rewrites `STATE.md` at the end of a session, a fixed template under 400 words, so the next chat starts with context.

Guard

- `hooks/read-gate.sh`: denies whole-file reads of large files (over 350 lines by default) and keeps a per-agent line budget of 350 distinct lines per file, across Read, `cat`, `head`, `tail`, `sed -n` and `awk`. The main thread also has a session budget of 3000 lines, after which it reads at most 40 lines at a time. The denial tells the model to ask a question with `lib/ask.sh` or to read a range.
- `agents/reader.md`: a small read-only agent that answers one question about a file with line numbers.
- `hooks/commit-gate.sh`: on `git commit`, refuses `--no-verify`, scans staged lines with gitleaks, runs your unit suite and requires a test change with a source change.
- `lib/config.sh`: reads `harness.toml`.

## With Ionian Brain.

Harness and Brain are separate and work well together. At the end of a session in a repo, run the `state` skill, which writes `STATE.md`. Then run Brain's `sync` skill, which reads `STATE.md` and carries the status into your brain. Harness never reads or writes your brain. The design is in `CONCEPT.md`.

## Credits.

Harness brings together established practices and standards for building with agents: zero-context review as described in Google's EGM, test-driven development as practised in superpowers, a read gate after Spotify's shunt, the document formats of spec-kit, and the secret scan of gitleaks. Every file is my own wording. `CONCEPT.md` lists each practice and where it shows up.

## License.

MIT.
