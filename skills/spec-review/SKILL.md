---
name: spec-review
description: Review a drafted spec in docs/designs/ with three zero-context reviewer agents (paraphrase test, critic, implementation readiness), fix it, re-audit once, then bring it to the user for approval. Use after spec-draft, or when the user asks to review a spec or design document.
---
# Spec review

The drafter knows too much to see the gaps in its own spec. Reviewers who know nothing but the document find them. Your job: dispatch them clean, fix the spec from what they report, stop after one re-audit, and bring the rest to the user.

Reviewer agents:
- `spec-paraphrase`: restates the spec in its own words and lists every place it had to guess.
- `spec-critic`: contradictions, missing whys, hidden decisions, vague terms, scope creep.
- `spec-readiness`: could a coder start from this tomorrow: testable scenarios, names that exist in the repo, a plausible first item.

## Dispatch rules, every round

A reviewer is useful only while it knows nothing. The dispatch prompt holds exactly:
- the spec path,
- for `spec-critic`, the path of `docs/constitution.md` if that file exists,
- in the re-audit, for `spec-critic` and `spec-readiness`, the previous round's findings verbatim.

Nothing else. No summary of the feature, no intent, no "focus on", no worries, nothing from the conversation. If you feel the need to explain something to a reviewer, the explanation belongs in the spec.

Save every reply verbatim to `$(git rev-parse --git-dir)/harness/review/<slug>/r<round>-<agent>.md`. That folder is never committed.

## Round 1

1. Paraphrase. Dispatch `spec-paraphrase`. Compare its restatement with what you meant. Every divergence is a Blocker on the spec, and every listed guess is at least a Major, no matter which reading is right. Fix the text, not the reader. Do not redispatch; go on.
2. Critic and readiness. Dispatch `spec-critic` and `spec-readiness` in parallel on the fixed spec.
3. Triage every finding:
   - Fix it in the spec. This is the default.
   - Reject it only when the spec already says it explicitly (cite the line) or when it asks for something under Out of scope. A reviewer who misread is evidence that the text is unclear: a misread gets fixed, not rejected.
   - Nits: fix when cheap, otherwise drop.
   Remove open questions that a fix has answered.

## Round 2: one re-audit

Dispatch all three again as fresh agents. `spec-critic` and `spec-readiness` also get the round 1 findings verbatim, without your resolutions; they check each against the text and report anything new at Blocker level. `spec-paraphrase` gets the path only.

Triage as in round 1, then stop reviewing. There is no round 3, whatever round 2 found.

## Converge

Everything still open after the re-audit goes to exactly one place:
- Blocker: a question for the user, with your recommended answer.
- Major: fixed, or recorded in the Review section as an accepted risk with one line on why.
- Nit: dropped.

Fill in the Review section of the spec:

```
## Review
- Round 1 (<date>): paraphrase <n> divergences, <n> guesses; critic B<n> M<n> N<n>; readiness B<n> M<n> N<n>. Fixed <n>, rejected <n>.
- Round 2 (<date>): same counts.
- Rejected: <finding, one line>. Reason: <the spec line that already says it, or out of scope>.
- Accepted risk: <finding, one line>. Why: <reason>.
```

Set `Status: reviewed`.

## Approval

Show the user, in this order and nothing more:
1. The round 2 paraphrase, as the reviewer wrote it. It is the best evidence of what the spec says to someone who was not here.
2. Open Blockers as questions, each with your recommendation.
3. Accepted risks.
4. The spec path.

Fold the user's answers into the spec. Set `Status: approved` with the date only when the user approves in so many words; silence, "looks good so far" or an answer to one question is not approval. If the answers add or remove a feature, say that a fresh review is warranted, and do not start one unasked.

After approval the spec changes only with the user's consent, recorded with a date in the Review section.
