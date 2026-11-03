---
name: spec-draft
description: Draft a design spec before any code is written, as docs/designs/<slug>.md. Use when the user asks for a spec or a design, starts a /build, or describes a feature that carries design decisions (new module, new interface, new dependency). Ends by handing the draft to spec-review; never approves it.
---
# Spec draft

You are the drafter. You hold the full context: the conversation, the code, what the user meant. The reviewers who read this spec next hold none of it. Write for them. A spec is done when someone who was not here can build the right thing from the page alone.

## 1. Before writing

- Slug: a short kebab-case name for the feature. The target is `docs/designs/<slug>.md`. If it exists, revise it in place and keep its Review section; never start a second file for the same feature.
- Learn what exists: earlier decisions in `docs/designs/` and `docs/adr/`, and the code the feature touches. Large files go to the `reader` agent, one question each.
- Ask the user only what the code cannot answer and only the user can decide: scope edges, what is explicitly out, trade-offs with no obvious default. One batch, at most four questions. Decide everything else yourself and record it under Decisions.

## 2. Write

Copy `template.md` from this skill folder to the target and fill it in.

- Self-contained. No "as discussed", no references to the chat, no "the usual way". If it matters, it is on the page.
- Every feature has a why that follows from the Problem. A feature whose why is "nice to have" is cut or moved to Out of scope.
- Every feature has at least one Given/When/Then scenario with concrete values, and a testability note: unit, integration or manual, and the observable result that proves it. The coder writes these scenarios as the first failing tests, so a scenario that cannot become a test is not finished.
- Name things exactly. Files, functions, commands, config keys, formats: existing names as they appear in the repo, new names marked `(new)`.
- For anything that comes from outside (user input, files, network, other processes), say what happens on bad input and on failure.
- Define each domain term once under Terms and use it the same way throughout.
- No number without a unit, no "fast", "large" or "robust" without a threshold.
- What, not how. Interfaces and data shapes belong here because they are decisions; file-by-file steps belong in the plan, which comes after approval.
- Short. Aim for under 200 lines. Over 300 usually means two features: split into two specs and say which comes first.
- Open questions are allowed in a draft. Each one names what it blocks.

## 3. Self-check

Answer each with yes, or fix the spec first:
- Could a stranger state the problem in one sentence from the Problem section alone?
- Does every feature have a why, a scenario with concrete values and a testability note?
- Is everything a reader could assume is included, and is not, listed under Out of scope?
- Is every name either found in the repo or marked `(new)`?
- Does any sentence depend on something said only in this conversation?

## 4. Hand off

Leave `Status: draft` and run the spec-review skill on the file. Never set the status to approved yourself, and start no plan or code before the user has approved the reviewed spec.
