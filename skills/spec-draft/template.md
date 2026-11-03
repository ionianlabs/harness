# <Feature name>

Status: draft
Slug: <slug>
Date: <YYYY-MM-DD>

## Problem
<Who has the problem, what it costs them today, why now. Three to six sentences.>

## Out of scope
- <What a reader could reasonably assume is included, and is not.>

## Terms
- **<term>**: <definition, used exactly this way below> (optional: delete if empty)

## Features
<Ordered by priority. F1 alone is a usable slice: buildable, testable, worth shipping without the others. Each later feature stands on its own on top of the ones before it.>

### F1. <name> (P1)
Why: <the part of the Problem this feature removes, one or two sentences>

Story: As <who>, I want <what>, so that <outcome>.

Scenarios:
<Ids are unique per feature and never reused after a deletion.>
- F1.1 Given <state with concrete values>, when <action>, then <observable result>.
- F1.2 Given <bad input or failure>, when <action>, then <defined behaviour>.

Testability: <unit | integration | manual>. Tested on its own by <what the test does>; shows <observable result>.

### F2. <name> (P2)

## Success criteria
- SC1 <measurable outcome with unit or threshold, naming no technology>

## Interfaces and data
<Commands, functions, files, config keys and formats this touches. Existing names exactly as in the repo, new names marked (new). Signatures and shapes, not implementations.>

## Decisions
- <Decision>. Rejected: <alternative>, because <reason>. (optional: delete if empty)
- <Decision>. Conflicts with constitution "<rule>": needed because <reason>; simpler alternative rejected because <reason>. (only if docs/constitution.md exists and is contradicted)

## Assumptions
- <Assumption taken as given>. If wrong: <what changes>. (optional: delete if empty)

## Dependencies
<New packages or services, each with a reason, or "none".>

## Review
<Filled in by spec-review.>
