---
name: state
description: Persist session progress by rewriting STATE.md in the repo root, the handoff file a fresh chat reads first. Use at the end of a working session in a repo, or when the user says "/state", "update STATE.md" or "save progress". Writes a terse fixed-template snapshot (goal, workstream, architecture, decisions, debt, next) so the next session resumes with no lost context.
---

Rewrite `STATE.md` in the repo root. Overwrite the whole file. Be terse.

STATE.md is a Harness artefact and belongs in the project repo next to `docs/designs/` and `harness.toml`. It is committed to git, so name only tracked files, modules and paths: no absolute paths, no generated output, no folders outside the repo.

Use exactly this structure:

    ---
    repo: <current folder name>
    updated: <today's date>
    ---

    ## Goal
    The outcome this repo is after, in one or two lines. Not tasks.

    ## Active workstream
    What is in flight and what changed this session. Tracked files and modules only.

    ## Architecture
    Key components, how they connect, data flow if it matters.

    ## Decisions
    Decisions in force, each with a one-line reason. Link the spec in `docs/designs/` where one exists.

    ## Debt
    Known shortcuts and things to revisit. Keep entries from earlier sessions until they are paid.

    ## Next
    The single most important next action, one line.

Rules:

- Under 400 words in total. No filler. Omit a section that is empty, except Goal and Next.
- Status lives only here. No history: that is git and, if you use one, the brain log.
- No personal names, customer data or conversation snippets. Refer to roles.
- Do not commit or push. After writing, print the suggested command for the user to run: `git add STATE.md && git commit -m "STATE: <summary>"`.

If Ionian Brain is installed, `brain:handover` is the next step: it reads STATE.md and summarises it one level up (status, owners, dates). Run `state` first, then `brain:handover`. Without Brain, stop after STATE.md.
