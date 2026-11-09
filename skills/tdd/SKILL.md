---
name: tdd
description: Write code test first. Use for any change that alters behaviour: a plan item, a spec scenario, a bug fix, a reviewer's fix. Dispatch the ionian-harness:coder agent with an item brief. Not for docs or config without behaviour.
---
# Test-driven change

Behaviour changes are done by the coder agent, not on the main thread. The test-first rules, the commit rules and the report block live in `agents/coder.md`.

1. Write an item brief: the goal, the files, the scenario ids or bug symptom, the acceptance checks and the test command. At most three deliverables.
2. Dispatch `ionian-harness:coder` with the brief. If the coder reports `BLOCKED` for a dependency, ask the user; on approval dispatch it again with the user's approval sentence quoted.
3. When it returns, dispatch `ionian-harness:reviewer` on the commit, and compare both reports with what the user asked for before you report.
