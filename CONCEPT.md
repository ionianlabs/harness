# Ionian Harness: concept

Build. One coordinator thread, context-isolated workers, gates enforced by hooks rather than by instruction. Three principles behind it: one continuous thread delegating to zero-context workers (after Google's EGM), never loading what is not needed (after Spotify's shunt), and spending tokens on verification rather than generation (merge gates, separate QA, tests first). Every gate exists because something broke first; add a gate only when something breaks.

Status and next steps live in `STATE.md`. This file is the design.



## 1. Three lanes, picked by you

The lane is an explicit command. No triage magic, no branch detection. Each lane turns on a subset of the gates; the floor (section 4) is always on.

| Lane | When | What runs | Human gates |
|---|---|---|---|
| `/fix <what>` | typo, config, one-function bug, anything you could review in a minute | Main thread edits directly on the current branch. Commit gate (unit tests, secret scan). No subagents except the reader when the shunt fires. | none |
| `/change <what>` | contained change, no new interfaces or dependencies, a few files | Coordinator writes a short checklist, dispatches coder per item (TDD), reviewer per item, QA once at the end, merge gate, PR. No spec document. | merge (PR) |
| `/build <what>` | feature, new module, anything with design decisions | EGM spec phase (draft, goldfish review, your approval), implementation plan, then the /change loop per plan item, security pass, merge gate, PR. | spec, merge (PR) |

The lane skill writes the active lane into `$(git rev-parse --git-dir)/harness-lane`. That file lives inside `.git`, so it is never committed and leaves no footprint in a client repo, and every hook reads it to decide what to enforce. No lane file means `/fix` behaviour.

Escalation is one-way and cheap: if a `/fix` turns out to need design, the coordinator says so and stops. It does not quietly grow into a `/change`.

## 2. Roles and models

Four worker definitions plus three spec reviewers. Flat fan-out from the main thread only, no worker spawns workers (subagent nesting depth is not confirmed in the docs and the design does not need it).

| Role | Model | Tools | Does | Never |
|---|---|---|---|---|
| coordinator (the main thread, no agent file) | Opus | all | reads briefs and results, writes checklists, dispatches, re-runs the suite itself, reads the git log, merges | edits source in `/change` and `/build` (hook-enforced) |
| reader | Haiku | Read, Grep, Glob | answers one question about files in structured bullets, each leading with exact name, type or line number, no prose | writes anything |
| coder | Sonnet | Read, Edit, Write, Bash, Grep, Glob | one checklist item per dispatch: failing test first, smallest change that makes it pass, run unit suite, commit | touches dependency manifests, works outside its worktree, declares done without a green run |
| reviewer | Sonnet | Read, Grep, Glob, Bash (read-only) | reviews the diff of one item against a fixed checklist and returns a punch-list with file and line | edits anything |
| qa | Sonnet | Read, Edit, Write (tests only), Bash | runs the full suite, writes missing tests, tries to break the change, reports with real output | edits anything outside the test directory (hook-enforced) |
| spec reviewers (`spec-paraphrase`, `spec-critic`, `spec-readiness`) | Opus | Read; critic and readiness also Grep, Glob | zero-context spec review in `/build`: paraphrase test, critic, implementation readiness; our own personas after the EGM concept | see anything but the spec, except the critic searching for reuse and readiness verifying names in the repo |

Two judgement tiers (Opus thinks, Sonnet builds) plus one reader tier that is a different kind of job, not a third opinion. If a loop step keeps failing on Sonnet, the fix is a better brief or a smaller item, not a bigger model. Upgrade a role only with data.

## 3. The loop (`/build`, `/change` skips the first row)

1. Spec: EGM draft, goldfish review (one re-audit, then forced convergence), you approve. Output `docs/designs/<slug>.md` with a why per feature and a testability note. If this file cannot be paraphrased by a fresh agent, it is not done.
2. Plan: coordinator writes `docs/designs/<slug>.plan.md`, a checklist of items of at most three deliverables each. A fresh session can resume from spec plus plan alone.
3. Worktree: `harness worktree new <slug>` creates a branch and worktree from main. All workers run inside it. The coordinator never codes in it.
4. Per item: coder (red, green, commit) then reviewer (punch-list). A non-empty punch-list becomes a fix dispatch plus a re-review. Two rounds maximum, then the coordinator stops and asks you. The reviewer's checklist: does the test prove the behaviour, is this the smallest change, does it reuse what exists, does it add surface nobody asked for, input handling, secrets, injection, auth, personal data in fixtures.
5. QA once: full suite, missing tests, breakage attempts. Punch-list goes back to the coder the same way.
6. Security: `/security-review` on the branch diff plus the dependency audit from `harness.toml`.
7. Merge gate: coordinator runs `harness merge`, which is `full suite && lint && merge`, exit code is the runner's, nothing piped. Full suite re-runs on the merged result three times to surface flakiness. A raw `git merge` into main is denied by hook.
8. PR: created with the plan, the QA report and the test evidence. You approve. CI runs unit plus integration. A red CI run becomes the first item of the next session, before any new work.

Stop rule for the autonomous part: in `/build` and `/change` a Stop hook keeps the coordinator working until the plan checklist is complete or an item is marked `BLOCKED` with a handoff (state, not instructions: commits by hash, files changed, steps already run). Same item blocked twice means it was too big: split, do not retry.

## 4. The floor: hooks that are always on

Each one maps to an incident in the source notes. Each runs as a small shell script reading the hook payload, and exits 2 with a reason the model sees.

| Hook | Event and matcher | Rule | Incident |
|---|---|---|---|
| read shunt | PreToolUse Read, Bash | deny untargeted reads of files over 350 lines and `cat`/`head`/`tail` on them; piped or redirected commands and offset/limit reads pass; `agent_type: reader` exempt | context blow-up, Spotify's 82 to 94 percent savings |
| main thread hands off | PreToolUse Edit, Write | in `/change` and `/build`, deny edits when `agent_id` is empty (main thread), except `docs/designs/**` and `docs/adr/**` | coordinator drifting into specialist work |
| qa stays in tests | PreToolUse Edit, Write | `agent_type: qa` may only write under the configured test directory | agents declaring their own work done |
| commit gate | PreToolUse Bash `git commit` | run `test.unit` from `harness.toml` first, deny on red; deny `--no-verify`; deny if the diff touches source but no test file (configurable); run `gitleaks` on staged lines | red merge through a pipe, secrets in sample data |
| dependency gate | PreToolUse Edit, Write on manifests | deny direct edits to `pyproject.toml`, `package.json`, `requirements*.txt`, `go.mod`, `Cargo.toml`; the only path is `harness dep add <pkg> --why "..."`, which writes `docs/adr/NNNN-<pkg>.md` and the manifest edit together | uncontrolled dependency growth, no ADR trail |
| merge gate | PreToolUse Bash `git merge`, `gh pr merge` | deny unless invoked through `harness merge` | two green branches red together |
| loop stop | Stop | in `/change` and `/build`, block stop while the plan has unticked items and no `BLOCKED` marker | runs ending with nothing committed |

Fail-open versus fail-closed: Claude Code treats a crashing hook (any exit other than 0 or 2) as non-blocking, so a broken gate silently stops existing. Gates that protect something (commit, merge, dependency, QA path) check their own prerequisites and deny when they cannot do their job. Gates that save tokens (read shunt) fail open. Learned 2026-11-03 when a lost execute bit let a commit through unguarded.

Unit suite budget is 30 seconds. A test over budget is first suspected of being badly written, then moved to the integration suite. Agents run the suite far more often than a human, so loop speed is token cost.

Shunt loop guard: the deny message names the exact next step (dispatch the reader with this question), the reader always returns line ranges so the follow-up read is targeted and passes, and after three denials on the same file in one session the hook lets the read through with a note. A gate that fires without resolving is a bug in the gate.

## 5. One config file per repo, language-agnostic

`harness.toml` declares the commands and the budgets. Nothing in the plugin assumes Python.

```toml
[test]
unit = "pytest -q -m 'not integration'"
full = "pytest -q"
dir  = "tests"
[lint]
run = "ruff check . && ruff format --check ."
[security]
deps    = "pip-audit"
secrets = "gitleaks git --pre-commit --staged"
[limits]
unit_seconds = 30
review_rounds = 2
worker_turns = 60
[limits.agents]        # max concurrent subagents per lane
fix = 1
change = 4
build = 6
[limits.minutes]       # coordinator stops and reports when exceeded
fix = 10
change = 45
build = 120
```

State and artefacts: anything temporary (lane marker, plan progress, last green run, handovers between workers) lives in `$(git rev-parse --git-dir)/harness/`, never committed. Anything that is a real artefact (spec, plan, ADRs, QA report) lives in `docs/designs/` and `docs/adr/`, because it belongs in the PR.

## 5a. Document formats: spec-kit artefacts, EGM review, one constitution

Steal the formats from [spec-kit](https://github.com/github/spec-kit), not the tool. Three templates: `spec.md` with user stories and Given/When/Then acceptance scenarios (tests waiting to be written), `plan.md` with a constitution check, `tasks.md` with `[P]` markers for parallel-safe items (this is the plan file the coordinator dispatches from). EGM stays the review mechanism over these documents. Spec-kit itself is not installed: its `.specify/` folder, scripts and seven-command workflow would be a second spec phase next to EGM.

`constitution.md` is the quality bar as an artefact: smallest change that passes the test, test before code, reuse before new, no dependency without ADR, no speculative abstraction, unit suite under 30 seconds. The reviewer and the goldfish read it; the plan is checked against it. Versioned, changed only with a dated reason.

## 5b. Keeping it from becoming a monster

Mechanics, not intentions:

- Budgets per lane are config (above). Exceeding one stops the coordinator with a report, it never silently continues.
- The floor is seven hooks. Adding one means removing one, or recording the incident that justified it and the condition under which it is removed again.
- Monthly drift report on the harness itself: per hook, how often it fired and how often it caught something. A hook that fires two hundred times and catches nothing is deleted.
- One number watched over time: turns to first commit. Over ten means ceremony has crept in.

Lookup order: repo root, then `~/.config/harness/<repo-name>.toml` for repos that must stay footprint-free (client code), then auto-detect from `pyproject.toml` or `package.json` with a warning. Missing command means that gate is skipped with a visible notice, never silently.

## 6. Borrow the concepts, write the files ourselves

Nothing is installed. Read the upstream files freely, extract the rules behind them, write our own versions from understanding, then compare against the originals and keep what tests better. Ideas and methods carry no license obligation; the README says it in the Ionian voice: "Harness borrows from the best work I found: the zero-context review from Google's EGM, the TDD discipline from superpowers, the read gate from Spotify's shunt, the document shapes from spec-kit. I read them, learned, and built my own version. Where I kept their words, they are marked." Where a passage is deliberately kept close to the original because rewriting would make it worse (EGM's anti-sycophancy rules are a candidate), it is marked in the file and carries that upstream's copyright and license notice in `THIRD_PARTY.md`. The only line that matters is at the output: text that reads as theirs is marked as theirs. "Elephant and goldfish" is credited as the concept followed (Rensin, Google EGM), never used as a product or role name.

| Concept | From | How it appears here |
|---|---|---|
| full-context drafter, zero-context reviewers, paraphrase test, Blocker/Major/Nit, one re-audit then forced convergence | Google EGM | spec-draft and spec-review skills, three stages (paraphrase, critic, readiness); own personas |
| read gate at a line threshold, targeted reads pass, reader returns structured bullets | Spotify shunt | two hook scripts written from the spec, reader agent, `agent_type` exemption, loop guard |
| red-green-refactor, smallest change, finishing a branch with verification | superpowers, and TDD in general | coder and reviewer skills |
| main thread cannot edit, detected by empty `agent_id` | orchestrator-mode | edit deny hook |
| staged-lines secret scan on commit | gitleaks community hooks | commit gate |
| spec with Given/When/Then, plan with constitution check, tasks with parallel markers, constitution as versioned principles | spec-kit, Gherkin | section 5a templates |
| `/security-review` | built in | step 6 |

Cost of this route: first versions will be worse than the iterated upstream wording for a few rounds. Comparing against the originals on the same spec or task closes the gap faster than guessing.

Build: three lane skills, five agent files, seven hook scripts, `harness.toml` loader, the `harness` CLI (`worktree new`, `dep add`, `merge`, `test unit|full`), `claude plugin eval` cases for the hooks.

## 6a. Why not just install the parts

Installing EGM, superpowers and a secret guard side by side would work for the spec phase and secrets, but the shunt does not run outside Spotify, and the plugins would each carry their own SessionStart injection, spec phase and Read hook. Writing our own from the concepts buys full control over stages, prompts and conflicts, at the cost of iterating the wording ourselves.

What no installed combination gives: ceremony scaled by lane, a main thread that cannot edit while workers can, QA kept out of source mechanically, commit and merge chained to this repo's real test command, dependency edits denied without an ADR, and a config file the gates read. About fifteen small files. That is the plugin: glue and gates around EGM and the shunt, not a replacement for them.

The other benefit is subtraction. Several plugins at once means several SessionStart injections that contradict each other (superpowers says implement inline, an orchestrator plugin denies it), two brainstorm phases triggering on the same intent, three Read hooks each printing a reason. One loop picks one of each.

## 7. Copilot port

Better than expected. The Copilot harness (VS Code Agent Host, Copilot CLI, Copilot app) reads `.claude/agents`, `.claude/skills` and `.claude-plugin/plugin.json` natively, pins models per agent (`model`, `modelPolicy: required`), and its hooks accept PascalCase event names with Claude tool names and payload shape. So the same agent files, skill files and hook scripts should load there with a thin manifest. What degrades:

- Skill arguments are dropped (open bug copilot-cli#4548). Lanes become `/fix` plus the request as the next sentence.
- No per-subagent worktree. Irrelevant for us: `harness worktree new` creates it, workers get the path.
- Model pinning is ignored when the session model is Auto. Pin the session model.
- Hook timeouts fail open in Copilot (fail closed in Claude Code). Set `timeoutSec` generously on the commit gate.
- Enterprise managed settings can restrict models and plugins. In such an organisation the port runs on whatever the org allows; the harness must degrade to "gates only" when Haiku or Opus are not available.

## 8. Pilot, in milestones

1. Bare floor: shunt hooks with the Haiku reader agent, gitleaks commit hook, own spec-draft and spec-review skills (three stages), own TDD skill. No lanes, no other roles, no CLI. Use for two weeks on the pilot repo. The first lessons entry decides which of the remaining gates were actually missed.
1b. Floor: remaining hooks, `harness.toml`, CLI, `/fix` lane. Measure: how often the shunt fires, false positives on the commit gate.
2. `/change`: coder, reviewer, qa agents, worktree flow, merge gate, PR. Run three real changes. Measure: review rounds per item, tokens per lane, how often the coordinator trusted a report it should not have.
3. `/build`: EGM dependency, plan file, Stop hook. One feature end to end. Measure: spec paraphrase pass, items blocked twice.
4. Copilot manifest and a test inside a repo where the Copilot toolchain is the only option.

Each milestone ends with a dated lessons entry in the plugin repo. A rule gets added only when a lesson repeats.

Milestone 0 (done 2026-11-03): hook payload verified. Main thread `agent_id` and `agent_type` null, subagents carry both. Gates key on `agent_type` for roles and on null `agent_id` for the main thread.

Pilot repo: Ionian Flow, after its current migration is done. Not before.


