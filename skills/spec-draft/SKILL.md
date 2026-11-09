---
name: spec-draft
description: Draft a design spec before any code is written, as docs/designs/<slug>.md. Use when the user asks for a spec or a design, starts a /build, or describes a feature that carries design decisions (new module, new interface, new dependency). Ends by handing the draft to spec-review; never approves it.
---
# Spec draft

You are the coordinator. You hold the conversation; a drafter agent writes the file. You ask the user, brief the drafter, and check that nothing the user said was lost. You do not write the spec yourself. The writing rules, the self-check and the spec template are in `agents/drafter.md`.

## 1. Before briefing

- Slug: a short kebab-case name for the feature. The target is `docs/designs/<slug>.md`. If it exists, the drafter revises it in place and keeps its Review section.
- Learn what exists: earlier decisions in `docs/designs/` and `docs/adr/`, and the code the feature touches. Large files go to the `reader` agent, one question each.
- Ask the user one question at a time, at most five in total per spec, ranked by how much the answer changes what gets built: scope first, then security and privacy, then user-visible behaviour, then technical. Each question carries a `Why it matters:` line and your recommended answer. Keep every answer for the brief.
- What the user is not asked: decide it and list it in the brief as a decision, or take an informed guess and list it as an assumption. Only what cannot be guessed and only the user can decide is passed as an open question for a `[NEEDS CLARIFICATION: <question>]` marker.

## 2. Brief and dispatch

Write a self-contained brief. The drafter sees nothing of the conversation. It holds:
- the target path and the slug,
- the problem with evidence (what it costs today, the numbers or logs the user gave),
- every user requirement and constraint, in the user's words where they matter,
- every decision with its rejected alternatives,
- assumptions, each with what changes if it is wrong,
- out of scope,
- the open questions that stay markers.

Dispatch `ionian-harness:drafter` with the brief. If the drafter cannot be dispatched, tell the user and stop.

## 3. When the drafter replies

- If the reply lists items it `could not place`, send them back to the drafter in a new dispatch, with the target path, before spec-review.
- When the drafter says the draft is done, reconcile it yourself, because only you saw the conversation: every requirement in the brief appears in the spec as a feature, scenario, success criterion, decision, assumption or out-of-scope item. Missing ones go back to the drafter in a new dispatch.

## 4. Hand off

The spec stays `Status: draft`. Run the spec-review skill on the file. Never approve it yourself, and start no plan or code before the user has approved the reviewed spec.
