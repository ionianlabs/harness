# Commit gate: shell scripts under hooks/ and lib/ need a test change

Status: approved (2026-11-03)
Slug: commit-gate-shell-tests
Date: 2026-11-03

## Problem
The harness is a Claude Code plugin (`README.md`). Its hooks are shell scripts the host runs before each tool call an agent makes (PreToolUse, registered in `hooks/hooks.json`): the host writes a JSON payload describing the call to the script's stdin, and exit code 2 blocks the call. The commit gate (`hooks/commit-gate.sh`) denies a commit when source files are staged and nothing under the test directory is. It skips that rule for any staged path matching `^(hooks|lib)/.*\.sh$` (`hooks/commit-gate.sh` line 63). The gate ships in the plugin, so the skip applies in every repo that installs it: a repo that keeps shell scripts in `hooks/` or `lib/` can commit them with no test change and no `[no-tests]` reason. In this repo it also defeats the rule in `CLAUDE.md` that every hook change comes with a test case, because the gate is what enforces that rule at commit time. It is listed as debt in `STATE.md`, and the next milestone adds more hook scripts.

## Out of scope
- Checking that the test change covers the script that changed. Any staged path under the test directory still satisfies the rule.
- A config key to exempt paths per repo.
- A notice or release note to repos that install the plugin: it is at version 0.0.1 and not yet published.
- Changes to `gate.source_glob`, the `[no-tests]` escape, the secret scan, the unit suite step or the `--no-verify` check.

## Terms
- **source file**: a staged path that matches `gate.source_glob` and does not start with `<test.dir>/`.
- **test change**: a staged path that starts with `<test.dir>/`.

## Features

### F1. Shell scripts under hooks/ and lib/ count as source (P1)
Why: removes the skip, so the existing test-change rule applies to these scripts like to any other source file, in this repo and in every other.

Story: As a maintainer of a repo using the harness, I want a staged `hooks/*.sh` or `lib/*.sh` change without a test change to be denied, so that untested shell scripts cannot be committed silently.

Scenarios (each in a fresh throwaway git repo, not shared with other checks, whose `harness.toml` sets `test.unit = "true"`, `test.dir = "tests"`, `security.secrets = "true"`; both commands are `true`, so the unit suite and the secret scan always pass and any deny comes from step 4; file contents do not matter):
- F1.1 Given only `hooks/x.sh` is staged, when the gate receives a Bash payload with command `git commit -m 'change x'`, then it exits 2 and its stderr contains `hooks/x.sh`.
- F1.2 Given only `lib/y.sh` is staged, when the gate receives command `git commit -m 'change y'`, then it exits 2 and its stderr contains `lib/y.sh`.
- F1.3 Given `hooks/x.sh` and `tests/x_test.sh` are staged, when the gate receives command `git commit -m 'change x with test'`, then it exits 0.
- F1.4 Given only `hooks/x.sh` is staged, when the gate receives command `git commit -m 'change x [no-tests] comment only'`, then it exits 0.
- F1.5 Given only `hooks/x.sh` is staged and `harness.toml` also sets `gate.require_tests = "false"`, when the gate receives command `git commit -m 'change x'`, then it exits 0.

Testability: unit. Tested on its own by new `check` lines in `tests/run.sh` that stage the files above in the throwaway repo and pipe a fake PreToolUse payload into `hooks/commit-gate.sh`; shows the exit code (2 or 0), and for F1.1 and F1.2 the path in stderr.

## Success criteria
- SC1 Every scenario F1.1 to F1.5 passes, and every check that passes in `tests/run.sh` before the change still passes after it.
- SC2 `bash tests/run.sh` finishes in under 30 seconds.
- SC3 (manual, reading step 4 of `hooks/commit-gate.sh`) A staged path is left out of the source file list only when it does not match `gate.source_glob` or lies under `<test.dir>/`.

## Interfaces and data
- `hooks/commit-gate.sh` acts only on payloads with `tool_name` `Bash` whose `tool_input.command` is a `git commit`, run in `cwd`. Its steps, in order: 1 deny `--no-verify`, 2 secret scan, 3 unit suite, 4 test-change rule; the first failing step denies.
- Step 4 ("source changed without a test change"): the list of changed source files no longer drops paths under `hooks/` or `lib/`. Input, exit codes (2 deny, 0 allow) and the denial message stay as they are; that message already lists the staged source files on stderr.
- Config keys read, unchanged: `gate.require_tests` (default `true`), `test.dir` (default `tests`), `gate.source_glob` (default `\.(py|js|ts|tsx|go|rs|sh|rb|java|kt|swift)$`, an extended regex matched against the whole staged path, so `hooks/x.sh` matches), via `lib/config.sh`.
- `tests/run.sh`: new checks using the existing `check <name> <expected exit> <hook> <payload>` helper for the exit codes. That helper discards stderr, so F1.1 and F1.2 each get one more inline line that captures the gate's stderr and looks for the path, printing `ok` or `FAIL` and on `FAIL` setting the suite's failure status, like the existing `config: value` line. `check` itself is not changed.

## Decisions
- Remove the skip outright. Rejected: a config key `gate.exempt_glob` (new) holding per-repo exemptions, because no repo needs one today and `[no-tests]` already covers a single commit that genuinely has no test.
- Rejected: keeping the skip only for this repo, because the gate would need a special case to recognise the harness repo, and this repo is the one whose rule the skip breaks.

## Assumptions
- No existing check in `tests/run.sh` stages a file under `hooks/` or `lib/`. If wrong: that check gains a staged test file or `[no-tests]`, and still counts as passing for SC1.
- The skip was added while the hooks had no test suite and no repo relies on it today. If wrong: that repo needs `[no-tests]` per commit until a second spec adds an exemption key.

## Dependencies
none

## Review
- Round 1 (2026-11-03): paraphrase context missing, 0 divergences, 4 guesses; critic B0 M2 N2; readiness B0 M2 N1 (both Majors shared, merged). Fixed 10, rejected 0, escalated 0. Not run: none.
- Round 2 (2026-11-03): paraphrase context sufficient, 0 divergences, 3 guesses; critic B0 M0 N0; readiness B0 M0 N0; all round 1 findings resolved. Fixed 3 after the re-audit (P2-1 to P2-3), not reviewed. Not run: none.
- Approved by the user (2026-11-03).
