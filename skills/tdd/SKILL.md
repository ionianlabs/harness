---
name: tdd
description: Write code test first. Use for any change that alters behaviour: a plan item, a spec scenario, a bug fix, a reviewer's fix. One failing test, the smallest change that passes it, the whole unit suite green, one commit. Not for docs or config without behaviour.
---
# Test-driven change

You write the code for one item: a plan item, one or more spec scenarios (`F1.1`), one bug, or one fix from a review. A test that was never seen failing proves nothing, so every behaviour starts as a test that fails for the right reason.

## Before the first test

- Read the item and, if it cites a spec in `docs/designs/`, the scenarios it names. The scenario's concrete values are your test data.
- Commands and places come from config: `harness.toml` at the repo root, else `~/.config/harness/<repo-name>.toml`. `test.unit` is the unit command, `test.full` the full one, `test.dir` (default `tests`) where tests live. The commit gate counts only files under `test.dir` as tests. If `test.unit` is defined nowhere, or the repo keeps its tests somewhere else, do not guess: ask, or report `NEEDS_CONTEXT`.
- Run the unit command once before changing anything. If it is red already, stop and report it; do not build on a red suite.
- If a test cannot be written without a decision the item does not make (a value, a format, a behaviour a user would notice), do not choose. Ask, or, as a dispatched subagent that cannot ask, report `NEEDS_CONTEXT` with the exact question.
- Files over 350 lines: search with `grep -n` for the name you need, then Read with offset and limit around the hit. Never read them whole.

## The cycle, once per behaviour

1. **Name it.** One scenario id or one bug symptom. Before writing the test, say which wrong line of production code would make it fail. If you cannot name one, the test checks nothing.
2. **Red.** Write one test for that behaviour only. Run the unit command, or the same runner narrowed to your test if it supports that. Red means your test is reported failing at its check of the new behaviour, not at setup, syntax or an import. A test that passes at once tests something that already exists: rewrite it, or report that the behaviour is already there. Keep the command and the failing line for the report.
3. **Green.** The smallest change that makes this test pass. No option, branch or input case that no test asks for, no tidying of code nearby. If the test still fails, change the code, not the test. Change a test only when it contradicts the spec, and say so in the report.
4. **Whole suite.** Run the full unit command, not just your test. Green means zero failures, exit code 0, and no new warnings or error text in the output. Every failure you see goes in the report by name, including ones you did not cause.
5. **Tidy, only on green.** Duplication, names, a helper. No new behaviour. Run the suite again.

Repeat for the next behaviour of the item, then commit.

Scenarios marked integration go in the integration suite and run Red and Green with `test.full`; report both commands. Scenarios marked manual get no test: name them under concerns.

## Tests that prove something

- Expected values come from the spec or are worked out by hand, never computed by the code under test.
- Test the contract a caller sees: inputs, outputs, exit codes, files written, messages that the spec names. Not private helpers, not the order of internal calls, not the source text of a script or document.
- Fake only what is slow or outside the process (network, clock, other services). List what the real call does before faking it. Never assert on the fake itself.
- No test that only restates the code (same constant, same expression), and no test that breaks on harmless rewording unless the wording is the contract.
- No test-only code in production files. Fixture values are obviously fake: no real credentials, names, addresses or tokens.
- A bug fix starts with a test that reproduces the symptom and fails. After the fix, revert the fix once and watch the test fail again, then restore it.
- Before committing, break the change on purpose once per new test: flip a condition, change a constant, return early or drop a check. At least one test must fail each time. If none does, write the missing test and go back to Red. Restore the code and run the suite again.

## Code that came first

Code written before its test is deleted, not adapted and not kept for reference. Exploring to learn how something works is fine; throw it away, then start at Red. "It is only a small change", "I tested it by hand" and "the test would just repeat the code" are the usual reasons for skipping Red, and none of them is a reason.

## Commit

- One commit per dispatch, on the branch and in the directory you were started in. Never amend, rebase, check out, push or merge. A fix after review is a new commit.
- Stage files by name, never `git add -A` or `git add .`. Read `git diff --staged` first: only this item's tests and code, no deliberate break left in, no debug output, no exploration file.
- The message names the item or the scenario ids. Commit with a plain `git commit -m "..."`.
- The commit gate re-runs the suite and requires a test change when source changed. Never pass `--no-verify`. `[no-tests]` with a reason is for commits that change no behaviour: docs, comments, config no code reads differently, or a removal, rename or tidy after a green suite, written as `[no-tests] no behaviour change, covered by <test names>`.
- If the gate denies, do what its message says and commit again the same plain way. Never reword the command to get it through. A second denial for the same reason is a stop.
- Do not edit dependency manifests or add packages. A new dependency is a decision: stop and ask, or report `BLOCKED` naming the package and why.

## Stop

Stop, and do not try once more, when:
- the same test is still red after three different code changes,
- the item needs work outside its scope,
- the suite turns red in a way you cannot explain,
- the gate denies twice for the same reason.

Leave uncommitted work in place and list it. A stop is reported as state, not advice.

Status: `BLOCKED` for a red baseline, a stop above, or a needed dependency. `NEEDS_CONTEXT` for a decision the item does not make. `DONE_WITH_CONCERNS` when you changed a test against the spec or left a manual scenario. Otherwise `DONE`.

## Report

When dispatched as a subagent, reply in exactly this form, at most 15 lines. On the main thread, give the user the same facts.

```
STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
ITEM: <item or scenario ids>
RED: <command> -> <failing test and the output line that shows why it failed>
GREEN: <command> -> <summary line and exit code>
BROKEN ON PURPOSE: <what you broke, which test caught it>
COMMIT: <hash> <subject> | none
FILES: <paths changed, marked (uncommitted) where so>
RAN: <commands after the last commit and their last output line> | none
FAILURES SEEN: <test names> | none
CONCERNS OR QUESTION: <one line each> | none
```
