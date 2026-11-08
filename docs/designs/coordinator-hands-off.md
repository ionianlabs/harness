# Coordinator hands off: the main thread delegates all repo writes to worker agents

Status: reviewed
Slug: coordinator-hands-off
Date: 2026-11-08

## Problem
The harness is a Claude Code plugin (`README.md`). Its design (`CONCEPT.md`) is one continuous main thread on a strong model, the coordinator: it designs, decides, briefs, reviews and talks to the user, while cheap context-isolated workers do the volume work and zero-context reviewers check it. In practice nothing enforces this. Milestone 1 shipped a read gate, a `reader` agent, a commit gate and four skills; the `coder`, `reviewer` and `qa` agents of `CONCEPT.md` section 2 do not exist, and the "main thread hands off" hook of section 4 is unbuilt (planned for milestone 2, only inside `/change` and `/build`, which do not exist either). So the main thread edits code, writes specs and explores files itself. That fills the expensive context, mixes the architect's judgement with the worker's detail, and leaves no independent check of the work. Evidence: in the gate log of the pilot repo (Ionian Flow), about 880 gated tool calls and 0 dispatches of the `reader` agent. The user's requirement: delegation is enforced always, for code and for specs and docs, not only inside lanes.

## Out of scope
- Worktree flow, merge gate, `qa` agent and the `/fix`, `/change`, `/build` lanes (milestones 2 and 3 of `CONCEPT.md`).
- Main-thread writes through interpreters (python, node, ruby), `git apply`, `patch`, and commands built from variables: a documented gap (F3).
- Enforcing that the reviewer runs after a coder commit. It is measured from the gate log (SC4), not enforced.
- Other file-writing shell forms: deleting or moving files other than the two protected config paths (`rm`, the source of `mv`), `touch`, `ln`, `install`, `dd of=`, `truncate`.
- Checking that a worker's type fits the path it writes (a drafter writing source, a coder writing a spec).
- A per-session off switch for the hook (only the per-repo config key exists).
- The Copilot port.
- Changing the three spec reviewers (`spec-paraphrase`, `spec-critic`, `spec-readiness`), their model or their tools.
- Read budget and `lib/ask.sh` (see the related spec `docs/designs/read-gate-v2.md`).

## Terms
- **main thread**: the session the user talks to. Its hook payload has an empty `agent_id` (verified in milestone 0 of `CONCEPT.md`).
- **worker**: a dispatched subagent. Its payload carries a non-empty `agent_id` and an `agent_type`, bare or prefixed `ionian-harness:`.
- **work tree**: the directory printed by `git rev-parse --show-toplevel` run in the payload `cwd`.
- **repo write**: a file creation or change whose target path resolves inside the work tree, outside `.git/`.
- **allow-list**: the globs in `[handoff] allow`; a repo write whose path (relative to the work tree root) matches one is not denied.
- **brief**: a self-contained text the coordinator gives a worker: goal, files, constraints, acceptance checks.
- **harness config**: `lib/config.sh` looks for `harness.toml` at the repo root, then `$IONIAN_HOME/harness/<repo-name>.toml` (`IONIAN_HOME` defaults to `~/Ionian`; `<repo-name>` is the work tree's folder name, so it is that repo's file, not any file in the folder). A repo has a harness config when either exists, as for `hooks/commit-gate.sh`.
- **lane**: a planned command (`/fix`, `/change`, `/build`, `CONCEPT.md` section 1) that sizes the process; none is built.
- **milestone**: a pilot stage in `CONCEPT.md` section 8; milestone 0 verified the hook payload fields, milestone 1 shipped the current floor.
- **item**: one entry of a brief or plan checklist, at most three deliverables, built and committed as one unit.
- **skills**: the four existing ones are `spec-draft`, `spec-review`, `tdd` and `state` (folders under `skills/`).

## Features
Order: F2 and F3 ship only together with F4 and F5 (one release), because with the gate live the spec skills must already route their writes to the drafter. F4 and F5 may ship before F2 and F3, never after them. So the priority order is F1, F4, F5, F2, F3 and ids are kept.

### F1. Worker agents to delegate to (P1)
Why: the main thread cannot hand off work to agents that do not exist. These three are the targets of every later denial and of the changed `spec-draft` skill.

Story: As the coordinator, I want a coder, a reviewer and a drafter agent, so that every kind of repo work has a worker to dispatch it to.

Scenarios:
- F1.1 Given the plugin, when `agents/coder.md` is parsed, then its frontmatter has `name: coder`, a non-empty `description`, `model: sonnet` and `tools` exactly Read, Edit, Write, Bash, Grep, Glob.
- F1.2 Given `agents/reviewer.md`, then `name: reviewer`, `model: sonnet`, `tools` exactly Read, Grep, Glob, Bash.
- F1.3 Given `agents/drafter.md`, then `name: drafter`, `model: sonnet`, `tools` exactly Read, Write, Edit, Grep, Glob.
- F1.4 Given each of the three files, when its `description` is read, then it contains the exact phrase `Dispatch when` followed by the situation: `agents/coder.md` a behaviour change or fix with a brief, `agents/reviewer.md` a finished commit to check, `agents/drafter.md` a spec to write or revise.
- F1.5 Given the body of `agents/coder.md`, which holds the test-first rules and the report block moved from `skills/tdd/SKILL.md` with their wording kept, then it contains each of: `test first`; `STATUS: DONE`; `RED:`; `GREEN:`; `one commit per item`; `dependency manifests` (never edited unless the dispatch quotes the user's approval sentence; otherwise the coder reports `BLOCKED` naming the package and why, the coordinator asks the user, and only on approval re-dispatches the coder with the quoted approval); `follow the denial` (a denied large-file read is resolved by the denial's instructions, and the line names `ask.sh` as `docs/designs/read-gate-v2.md` requires).
- F1.6 Given the body of `agents/reviewer.md`, then it contains each of these exact phrases: `read-only` (use of Bash); `file:line`; `no findings`; and the checklist of `CONCEPT.md` section 3 step 4: `prove the behaviour`, `smallest change`, `reuse what exists`, `surface nobody asked for`, `input handling`, `secrets`, `injection`, `auth`, `personal data in fixtures`.
- F1.7 Given the body of `agents/drafter.md`, which holds the writing rules and self-check of `skills/spec-draft/SKILL.md` sections 2 and 3 and the spec template, both moved with their wording kept, then it contains each of: `## Success criteria`; `Testability:`; `[NEEDS CLARIFICATION`; `could not place` (every brief item, listed in the reply with the self-check results); `verbatim` (it sets `Status: approved` only when the dispatch quotes the user's approval sentence verbatim with its date, and records it under Review).
- F1.8 Given the three agent bodies, when searched for `skills/`, then nothing is found (workers have no Skill tool and no plugin path).
- F1.9 Given the repo, then `skills/tdd/SKILL.md` contains `ionian-harness:coder` and is a short pointer (behaviour changes are done by dispatching the coder with an item brief), and `skills/spec-draft/template.md` does not exist.

Testability: unit. Tested on its own by new inline ok/FAIL lines in `tests/run.sh`, like the existing `config: value` line, that parse each frontmatter with shell and `grep` each quoted phrase; shows ok or FAIL per file and phrase. The quality of the workers' output is a manual check in the pilot (SC3, SC4).

### F4. Spec drafting moves to the drafter (P2)
Why: this is the first release slice after F1 and stands without the hook; the main thread drafting specs is the same drift as editing code, and F2 denies its writes to `docs/designs/`. The coordinator keeps what only it can do: ask the user, and check that nothing the user said was lost.

Story: As the user, I want the main thread to ask me the questions and brief a drafter, so that the spec is written by a worker and checked against what I said.

Scenarios:
- F4.1 Given `skills/spec-draft/SKILL.md`, then it contains `at most five` (questions in total per spec, ranked), `Why it matters:`, a brief with the parts problem with evidence, every user requirement, every decision with rejected alternatives, assumptions and out of scope, and `ionian-harness:drafter` as the dispatch target.
- F4.2 Given the drafter's reply lists items it `could not place`, then the skill tells the main thread to send them back to the drafter in a new dispatch before spec-review.
- F4.3 Given the drafter says the draft is done, then the skill tells the main thread to run the reconciliation itself: `every requirement in the brief` appears as a feature, scenario, success criterion, decision, assumption or out-of-scope item, and missing ones go back to the drafter.
- F4.4 Given the skill text, then it contains the sentence `If the drafter cannot be dispatched, tell the user and stop.` and no instruction to write the spec on the main thread.
- F4.5 Given a reconciled draft, then the skill runs `spec-review` as today with its three zero-context reviewers unchanged.

Testability: unit. Tested on its own by inline ok/FAIL lines in `tests/run.sh` that `grep` each quoted phrase in the skill; shows ok or FAIL per phrase. Manual for the pilot run only: one spec drafted in a session, and `gate.log` shows its lines written with the drafter as `agent=`.

### F5. Spec review fixes go through the drafter (P3)
Why: `skills/spec-review/SKILL.md` has the main thread edit `docs/designs/` after each round, fill Review and set Status; with F2 live those writes are denied and the review loop breaks.

Story: As the coordinator, I want the drafter to apply my triaged fixes and record the outcome, so that the review loop runs without the main thread writing the spec.

Scenarios:
- F5.1 Given `skills/spec-review/SKILL.md`, then the main thread still dispatches the three reviewers, numbers, merges and triages findings, asks escalations and decides, and the text contains `ionian-harness:drafter` for applying each round's `fix list` (the triaged list with ids and the required change, not the reviewers' raw text).
- F5.2 Given a finished round, then the skill has the main thread give the drafter the counts for the Review section (for example round 1, findings 4, fixed 3, rejected 1), and contains `Status: reviewed` as the status the drafter sets after the final review round only.
- F5.3 Given the user writes "I approve this spec" on 2026-11-09, then the skill has the dispatch quote that sentence and date `verbatim` and contains `Status: approved`; the drafter records the quote under Review. Given a dispatch without a quoted approval, the drafter leaves the status unchanged and says so (the phrase is in `agents/drafter.md`, F1.7).
- F5.4 Given a reviewer dispatch, then the skill sends paths and earlier finding ids only and contains `never into a reviewer dispatch` for the fix list.
- F5.5 Given the skill text, then it contains the sentence `If the drafter cannot be dispatched, tell the user and stop.`

Testability: unit. Tested on its own by inline ok/FAIL lines in `tests/run.sh` that `grep` each quoted phrase in `skills/spec-review/SKILL.md`; shows ok or FAIL per phrase. Manual for the pilot run only: in one review round, `gate.log` shows the spec fixes written with the drafter as `agent=`.

### F2. Hand-off hook for Edit, Write, MultiEdit and NotebookEdit (P4)
Why: ships only together with F4 and F5 (one release), because without them the spec skills would hit this gate; removes the main thread's ability to write repo files with the file tools, which is the bulk of the drift in the Problem.

Story: As the user, I want the main thread denied when it writes a file in the repo, so that it dispatches a worker and keeps its context for judgement.

Scenarios (each in a throwaway git repo with `harness.toml` present unless stated; payloads are PreToolUse JSON piped into `hooks/handoff-gate.sh`; `cwd` is the repo root):
- F2.1 Given `tool_name` Write, `file_path` `src/app.py`, no `agent_id`, when the gate runs, then it exits 2 and stderr contains `coder`.
- F2.2 Given tool Edit, `file_path` `docs/designs/x.md`, no `agent_id`, then exit 2 and stderr contains `drafter` and not `coder`.
- F2.3 Given tool NotebookEdit with `notebook_path` `analysis/n.ipynb`, no `agent_id`, then exit 2 and stderr contains `coder`.
- F2.4 Given Write to `STATE.md` with no `agent_id` and default config, then exit 0.
- F2.5 Given `harness.toml` sets `[handoff]` `allow = "STATE.md,notes/*.md"`, when Write targets `notes/today.md`, then exit 0; when it targets `src/app.py`, then exit 2.
- F2.6 Given Write with `agent_id` `a1` and `agent_type` `ionian-harness:coder` to `src/app.py`, then exit 0. The same with `agent_id` `a2` and `agent_type` `drafter` (bare) to `docs/designs/x.md`, then exit 0.
- F2.7 Given Write with `file_path` `/tmp/scratch.txt` (outside the work tree), no `agent_id`, then exit 0.
- F2.8 Given Write to `.git/info/exclude` (absolute path inside the repo), no `agent_id`, then exit 0.
- F2.9 Given `file_path` `./src/../src/app.py` or the absolute path of `src/app.py`, no `agent_id`, then exit 2 (paths are normalised before the comparison).
- F2.10 Given `harness.toml` sets `[handoff]` `enabled = "false"`, when Write targets `src/app.py` with no `agent_id`, then exit 0 and no line is logged.
- F2.11 Given a repo with no `harness.toml` and no file in `$IONIAN_HOME/harness/`, when Write targets `src/app.py` with no `agent_id`, then exit 0 and no `gate.log` is created.
- F2.12 Given stdin `not json`, then exit 0 and the line is `agent=unknown tool=unknown path=- allowed note=unparseable`. Given `jq` is not on `PATH`, then exit 0 and the same line with `note=no-jq`. Given a payload with tool Write and no path key, then exit 0 and `note=no-path` on a line with the known agent and tool and `path=-`.
- F2.13 Given any decision in F2.1 to F2.9, then `<git-dir>/harness/gate.log` gains one line of the form `HH:MM:SS agent=<main or agent_type> tool=<tool> path=<relative path> allowed` or `... DENIED`.
- F2.14 Given `cwd` is `<repo>/src` and `file_path` is the relative `app.py`, no `agent_id`, then exit 2 (relative paths resolve against the payload `cwd`) and the log path is `src/app.py`.
- F2.15 Given `allow = "notes/*.md"` (a set `allow` replaces the default), when Write targets `STATE.md`, no `agent_id`, then exit 2.
- F2.16 Given tool MultiEdit with `file_path` `src/app.py`, no `agent_id`, then exit 2. Given Write to `/tmp/scratch.txt`, then the log line has `path=/tmp/scratch.txt` (outside-tree targets are logged absolute).
- F2.17 Given a payload whose `cwd` is missing or not a string, then exit 0 and the line `... note=no-cwd` goes, without a config check, to `<git-dir>/harness/gate.log` of the hook process's working directory (the test runs the hook from inside the throwaway repo), else `/tmp/harness/gate.log`; the same location is used for `unparseable` and `no-jq`.
- F2.18 Given `cwd` is a directory outside any git repo, then exit 0 and nothing is logged.
- F2.19 Given the repo is opened through a symlink `link` to its real path, when Write targets `<link>/src/app.py` with `cwd` `<link>`, no `agent_id`, then exit 2.
- F2.20 Given `allow = " STATE.md , notes/*.md "`, when Write targets `STATE.md`, then exit 0 (whitespace around each glob is trimmed).
- F2.21 Given Write to `harness.toml`, no `agent_id`, then exit 2 and stderr contains `coder`; the same with `allow = "harness.toml"` (the protection holds even if listed in `allow`).
- F2.22 Given `IONIAN_HOME` set to a temp directory and no `harness.toml` in the repo, when Edit targets `$IONIAN_HOME/harness/<repo-name>.toml`, no `agent_id`, then exit 2 and the log path is that absolute path. Given `agent_id` `a1`, `agent_type` `coder`, Write to `harness.toml` exits 0.

Testability: unit. Tested on its own by inline ok/FAIL lines in `tests/run.sh` that build a throwaway repo, pipe a fake payload into `hooks/handoff-gate.sh` and compare the exit code, grep stderr for the agent name and grep the log line; shows exit 2 or 0, the agent name and the log line.

### F3. Main-thread Bash writes into the repo (P5)
Why: ships with F2 in the same release; with F2 alone the main thread writes the same files through `sed -i` or `>`; the common forms must close or F2 is a formality.

Story: As the user, I want the common shell ways of writing a repo file denied for the main thread too, so that F2 is not bypassed by accident.

Scenarios (same setup and activation as F2; tool `Bash`, no `agent_id`, `tool_input.command` as given; "denied" means exit 2 and the F2 message; the allow-list applies to each target):
- F3.1 `sed -i 's/a/b/' src/app.py` is denied; `sed -i '' 's/a/b/' src/app.py` is denied; `perl -pi -e 's/a/b/' src/app.py` is denied; `sed -n '1,5p' src/app.py` exits 0.
- F3.2 `echo x > src/out.txt` and `echo x >> src/out.txt` are denied; `echo x > /dev/null`, `make 2>&1 > /dev/null` and `echo x > /tmp/out.txt` exit 0.
- F3.3 `echo x | tee src/out.txt` and `tee -a src/out.txt < in.txt` are denied; `tee /tmp/out.txt` exits 0.
- F3.4 `cp /tmp/a.py src/app.py` and `mv /tmp/a.py src/app.py` are denied; `cp src/app.py /tmp/app.py` exits 0.
- F3.5 `echo x > STATE.md` exits 0 under the default allow-list, and the log line has `path=STATE.md` (an allowed command with a matched target logs that target).
- F3.6 `git commit -m "a > b"`, `git merge feature`, `git stash`, `git checkout main` and `echo "a > b"` exit 0 (quoted text is not a redirect; git's own writes are not matched).
- F3.7 `python3 -c "open('src/app.py','w').write('x')"`, `git apply fix.patch` and `f=src/app.py; echo x > $f` exit 0 (documented gap).
- F3.8 With a worker payload (`agent_id` `a1`, `agent_type` `coder`), `sed -i 's/a/b/' src/app.py` exits 0.
- F3.9 With `[handoff] enabled = "false"`, or with unparseable stdin, `echo x > src/out.txt` exits 0.
- F3.10 `cd src && echo x > out.txt` is denied with target `src/out.txt`; `cd /tmp && echo x > out.txt` exits 0. Targets resolve against `cwd` as moved by `cd` segments. Commands are split at `;`, `&&`, `||`, a lone `&` and newlines outside quotes, unlike `hooks/read-gate.sh`, which splits only at `;`, `&` and newlines; an `&` inside `>&`, `&>` or `2>&1` does not split.
- F3.11 `make 2> src/err.log`, `make &> src/all.log` and `echo x >| src/out.txt` are denied; `make 2>&1` and `make 2> /dev/null` exit 0.
- F3.12 `git log > src/x.txt` is denied (git's own object writes are exempt, a redirect in a git command line is not); `git log` exits 0.
- F3.13 `rm harness.toml`, `mv harness.toml /tmp/x`, `mv /tmp/x harness.toml` and `echo x > harness.toml` are denied, also with `allow = "harness.toml"`; with a temp `IONIAN_HOME`, `rm $IONIAN_HOME/harness/<repo-name>.toml` written out as its absolute path is denied; `rm src/app.py` exits 0 (documented gap).

Testability: unit. Tested on its own by one inline ok/FAIL line in `tests/run.sh` per scenario command, run through `hooks/handoff-gate.sh` in a throwaway repo; shows the exit code and, for the denials, `coder` in stderr.

## Success criteria
- SC1 In a repo with a harness config, 0 of the file-tool writes by the main thread to repo-work-tree paths outside the allow-list pass the gate, and 0 of the Bash write forms listed in F3.1 to F3.4 pass; every such case is a unit check.
- SC2 100 percent of denial messages name an agent that exists as a file in the plugin's `agents/` folder and a next step the main thread can carry out.
- SC3 Over two weeks of pilot use, workers perform at least 90 percent of repo file writes. Counted from `gate.log`: every in-tree, non-`.git` write decision (allowed or denied) of F2 and F3, including allow-listed main-thread writes and excluding Bash lines with `path=-`; the share is lines whose `agent=` is not `main`, after stripping the `ionian-harness:` prefix.
- SC4 Over the same two weeks, at least 80 percent of coder commits are reviewed (measured, not enforced). A coder commit is a `hooks/commit-gate.sh` line `... agent=coder tool=Bash git commit in <repo>` (that line already logs the agent; the prefix `ionian-harness:` is stripped for every SC3 and SC4 count); it counts as reviewed when a gate.log line with `agent=reviewer` follows it before the next coder commit line in the same repo log.
- SC5 Main-thread tokens per session, a measurement with no threshold (manual step): for each main-thread session file in `~/.claude/projects/<project-slug>/*.jsonl`, sum `input_tokens + cache_creation_input_tokens + cache_read_input_tokens + output_tokens` of the non-sidechain assistant entries; report the median over sessions for the two weeks before and the two weeks after.
- SC6 `bash tests/run.sh` finishes in under 30 seconds and every check that passed before still passes.

## Interfaces and data
- `hooks/hooks.json` (changed): one new PreToolUse entry with matcher `Edit|Write|MultiEdit|NotebookEdit|Bash` running `bash ${CLAUDE_PLUGIN_ROOT}/hooks/handoff-gate.sh` (`MultiEdit` is harmless if the host has no such tool; its target key is `file_path`); the existing `read-gate.sh` and `commit-gate.sh` entries stay as they are.
- `hooks/handoff-gate.sh` (new): reads the payload from stdin; uses `tool_name`, `agent_id` (empty means main thread), `agent_type` (for the log), `cwd`, `tool_input.file_path` (Edit, Write, MultiEdit), `tool_input.notebook_path` (NotebookEdit) and `tool_input.command` (Bash). Finds the work tree with `git rev-parse --show-toplevel` in `cwd`, detects a harness config and reads keys through `lib/config.sh` exactly as `hooks/commit-gate.sh` does (`cfg --exists`). Exit 2 denies with the message on stderr, exit 0 allows. It fails open. Relative targets resolve against `cwd`; Bash targets also against `cd` segments. A target is normalised by resolving its longest existing parent physically (`pwd -P`) and appending the remaining components lexically; the work tree from `git rev-parse --show-toplevel` is physical. Outside a git repo, or with no harness config, or with `enabled` false: exit 0, nothing logged. The `allow` globs are trimmed of surrounding whitespace. Two config paths are protected for the main thread: `harness.toml` at the work tree root and `$IONIAN_HOME/harness/<repo-name>.toml` (`IONIAN_HOME` default `~/Ionian`). A write, `rm` or `mv` (source or destination) naming either is denied through every tool and Bash form above, even though the second is outside the work tree and even if listed in `allow`; workers may edit them.
- `harness.toml` keys (new): `[handoff]` `enabled` (default `true`; only the value `false` turns the hook off) and `allow` (default `STATE.md`). `lib/config.sh` reads flat `key = "value"` lines, so `allow` is one quoted string of comma-separated globs, relative to the work tree root, matched with shell pattern matching on the whole relative path; `*` also matches `/`.
- Denial messages, two texts, each carrying the relative path of the target (no tool slot):
  (a) path under `docs/designs/`: `Hand-off gate: the main thread does not write files in the repo (<relative path>). Dispatch the "ionian-harness:drafter" agent with a brief for this spec, then run the spec-review skill on the result.`
  (b) every other path: `Hand-off gate: the main thread does not write files in the repo (<relative path>). Dispatch the "ionian-harness:coder" agent with a brief holding the goal, the files, the acceptance checks and the test command. When it returns, dispatch "ionian-harness:reviewer" on the resulting commit, then compare both reports with the user's requirements before you report.`
- `<git-dir>/harness/gate.log` (existing file, shared with `hooks/read-gate.sh` and `hooks/commit-gate.sh`): one new line per decision, `HH:MM:SS agent=<main|agent_type> tool=<tool> path=<path> allowed|DENIED`, with `note=<reason>` at the end for fail-open cases; reasons are exactly `unparseable`, `no-jq`, `no-path`, `no-cwd`, and a line that cannot parse them reads `agent=unknown tool=unknown path=-`. `agent=` is `main` whenever `agent_id` is empty, else the raw `agent_type`. `path=` is relative inside the work tree (`.git/` targets too, e.g. `path=.git/info/exclude`), absolute outside. For Bash it is the first target that caused the denial when denied, the first matched target when allowed (worker commands are parsed too, so their writes log a real `path=`), and `-` when none matched. A target outside the work tree (the `$IONIAN_HOME` config) appears in the denial text with its absolute path. `note=no-path` is logged after the config and enabled checks. Lines for `unparseable`, `no-jq` and `no-cwd` go, without a config check, to the git dir of the hook process's working directory, else `/tmp/harness/gate.log`.
- `agents/coder.md`, `agents/reviewer.md`, `agents/drafter.md` (new): same format as `agents/reader.md`: frontmatter `name`, `description`, `model`, `tools`, then the prompt. They are the single source of their rules because workers run in the user's repo with no Skill tool: coder holds the test-first rules, report block and large-file line, drafter the writing rules, self-check and spec template, reviewer the checklist. `agents/coder.md` meets the requirement of `docs/designs/read-gate-v2.md` that the tdd rules mention `ask.sh`. Plugin agents are auto-discovered from `agents/`.
- `skills/spec-draft/SKILL.md` (changed; carries the stop sentence of F4.4): keeps only the coordinator steps (questions, brief, dispatch, reconciliation, hand-off). `skills/spec-draft/template.md` is removed (its content is in the drafter). `skills/tdd/SKILL.md` (changed) becomes the pointer of F1.9. The `reader` agent stays the way to learn what exists.
- `skills/spec-review/SKILL.md` (changed): fixes, the Review section and the Status lines are written by dispatching `ionian-harness:drafter` (F5); it carries the stop sentence of F4.4; the three reviewers stay as they are.
- `tests/run.sh` (changed): new inline ok/FAIL lines (not the `check` helper) for F1 to F5.
- Files that must mention the new pieces afterwards: `README.md` "What is here"; `CONCEPT.md` section 2 roles table (workers exist, drafter added) and section 4 floor table (the "main thread hands off" row is always on, config-switchable, not lane-bound); `STATE.md` architecture lines.

## Decisions
- Always on in repos with a harness config, not only inside lanes. Rejected: lane-only, as `CONCEPT.md` planned, because the lanes do not exist yet and the user wants the architect model for every task.
- The main thread is the payload with an empty `agent_id`. Rejected: an empty `agent_type`, because a session started with a named main agent may carry one on the main thread; rejected: a marker the model sets, because it can forget or fake it.
- Deny by write target, not by tool alone, so writes outside the work tree (memory files, scratchpad, other folders) and under `.git/` pass: they are not the repo's work.
- The default allow-list is `STATE.md` only: the state handoff is the coordinator's own summary. Rejected: allowing `docs/designs/**`, because the user wants specs drafted by a worker too.
- The hook fails open and logs. Rejected: fail closed, because a crashed hook would freeze the whole session, and this gate saves tokens and enforces process; it protects nothing irreversible (`AGENTS.md`).
- Sonnet for `coder`, `reviewer` and `drafter`; the spec reviewers stay as they are. Rejected: Opus workers, because of cost and `CONCEPT.md` says to upgrade a role only with data.
- The drafter is a worker; the coordinator keeps the questions and the reconciliation. Only the main thread holds the conversation, so only it can check that nothing the user said got lost.
- Flat fan-out: workers never dispatch workers (`CONCEPT.md` section 2). Denials for subagents are defined by `docs/designs/read-gate-v2.md`.
- Git commands that write repo objects (commit, merge, stash, checkout) are not matched in F3: the coordinator runs merges and the gates.
- `allow` is a comma-separated string. Rejected: a TOML array, because `lib/config.sh` reads flat `key = "value"` lines only and extending the parser is outside this change.
- The gate protects its own config: the main thread is denied writing, deleting or moving `harness.toml` and `$IONIAN_HOME/harness/<repo-name>.toml`, even if listed in `allow`; workers may edit them, which shows as a coder commit; turning the gate off is the user's own edit outside the agent. Rejected: documenting the gaps only, because the gated thread could disable its own gate in one command.
- A coder edits a dependency manifest only after the user approves the dependency: the coder reports `BLOCKED` naming the package and why (as the tdd rules, now in `agents/coder.md`, say), the coordinator asks the user, and re-dispatches the coder with the approval sentence quoted. Rejected: coder edits on its own judgement, because a new dependency is a decision for the user.
- The rules live inline in the agent files, the single source. Rejected: `${CLAUDE_PLUGIN_ROOT}` paths in briefs, because the coordinator would have to resolve and pass them every dispatch and a missing path fails silently.

## Assumptions
- The PreToolUse payload for Edit and Write carries the target as `tool_input.file_path`, for NotebookEdit as `tool_input.notebook_path`. If wrong: the hook reads the right key, found from a logged payload, and the F2 scenarios change their key.
- A dispatched subagent's payload carries a non-empty `agent_id` and `agent_type` (verified for subagents in milestone 0). If wrong: every worker write is denied; F2.6 and F3.8 are the tests that catch it, and the gate is switched off with `enabled = "false"` until fixed.
- The main thread may need to edit in a hurry. The user turns the hook off per repo by editing `harness.toml` themselves, outside the agent, to `[handoff] enabled = "false"`. If wrong: add a per-session switch in a later spec.
- The main thread's `agent_id` is empty in every session, including one started with a named main agent. If wrong: the hook treats that session as a worker and allows its writes (fail open), SC3 shows a main-thread share of zero, and detection needs a second signal.
- The `reviewer` can be given a commit range and read it with read-only `git` commands through Bash. If wrong: the brief carries the diff as a file path under a scratchpad.

## Dependencies
none

## Review
- Round 1 (2026-11-08): paraphrase context missing, 0 divergences, 15 guesses; critic B0 M6 N7; readiness B0 M6 N3. Fixed 34, rejected 0, escalated 1 (C1-3). Not run: none.
- Round 2 (2026-11-08): paraphrase context sufficient, 0 divergences, 9 guesses; critic B1 M0 N0, all 22 earlier resolved; readiness B1 M0 N0, 21 earlier resolved, R1-1 open. Not run: none.
- Clarification (2026-11-08): Should the gate protect its own config? Answer: deny main-thread writes, deletes and moves of both config paths. Changed: F2, F3, Decisions, Out of scope.
- Fixed after round 2, unreviewed: C2-1 rules inline in the agent files, skills become pointers, template folded into the drafter; R2-1 splitter description; R1-1 exact phrases for descriptions and checklist; `path=` for denied Bash; six one-line clarifications.
