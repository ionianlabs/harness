---
name: spec-review
description: Review a drafted spec in docs/designs/ with three zero-context reviewer agents (paraphrase test, critic, implementation readiness), fix it, re-audit once, then bring it to the user for approval. Use after spec-draft, or when the user asks to review a spec or design document.
---
# Spec review

The drafter knows too much to see the gaps in its own spec. Reviewers who know nothing but the document find them. Your job: dispatch them clean, triage what they report, have the drafter apply the fixes, stop after one re-audit, and bring the rest to the user. You do not edit the spec yourself: every change to it, fixes, the Review section and the Status lines, is made by dispatching `ionian-harness:drafter`. If the drafter cannot be dispatched, tell the user and stop.

Drafter dispatches: the prompt holds the spec path and a fix list, the triaged list with each finding's id and the required change, in your words, not the reviewers' raw text.

Reviewer agents:
- `spec-paraphrase`: restates the spec in its own words (problem, how the existing system works, what it builds, what it does not, done when) and lists every place where two readings would build or test different things.
- `spec-critic`: contradictions, missing whys, hidden decisions, vague terms, scope creep, constitution conflicts. Searches the repo for existing code that already does what a feature describes, and asks whether the feature should exist at all.
- `spec-readiness`: could a coder start from this tomorrow: testable scenarios, names that exist in the repo, a plausible first item.

## Dispatch rules, every round

A reviewer is useful only while it knows nothing. The dispatch prompt holds exactly:
- the spec path,
- for `spec-critic`, the path of `docs/constitution.md` if that file exists,
- in the re-audit, for `spec-critic` and `spec-readiness`, the path of `r2-earlier.md`: the round 1 critic and readiness findings, each line the reviewer's text verbatim, prefixed with its id.

Nothing else: paths and earlier finding ids only, and the fix list goes never into a reviewer dispatch. No summary of the feature, no intent, no "focus on", no worries, nothing from the conversation. If you feel the need to explain something to a reviewer, the explanation belongs in the spec itself; reviewers follow no links, so a repo path on the page is provenance, not an explanation.

Save every reply verbatim to `$(git rev-parse --git-dir)/harness/review/<slug>/r<round>-<agent>.md`. That folder is never committed.

Then number the reply's findings in order of appearance. Ids are yours, not the reviewer's: `P<round>-<n>` for paraphrase guesses and divergences, `C<round>-<n>` for critic, `R<round>-<n>` for readiness. Write the numbered list to `r<round>-findings.md` in the same folder.

Reviewer failure: if a dispatch errors, times out, or the reply does not follow the agent's reply format, dispatch a fresh instance once more. If that fails too, record the reviewer as `not run` for that round. A reviewer that did not run is never zero findings.

## Round 1

1. Paraphrase. Dispatch `spec-paraphrase`. Compare its restatement with what you meant and with the repo.
   - `CONTEXT: missing` is a Blocker.
   - A wrong EXISTING SYSTEM or BUILDS line (diverges from what you meant, or from the repo) is a Blocker on the text.
   - A guess that picked a reading you did not mean is a Blocker, like a divergence. A guess that picked your reading is a Major in round 1 and a Nit in round 2: the text is ambiguous, but this reader got it right, and a fix after the re-audit goes unreviewed.
   Fix the text, not the reader (the drafter applies the fix list). Do not redispatch the reviewer; go on.
2. Critic and readiness. Once the drafter has applied the fix list of step 1, dispatch `spec-critic` and `spec-readiness` in parallel on the fixed spec. A constitution conflict is a Blocker unless the Decisions section justifies it.
3. Merge duplicates: critic and readiness findings about the same text and the same problem become one. Keep both ids, take the higher severity.
4. Triage every finding into one category, in this order of preference:
   - Fix: the default.
   - Escalate: the finding needs a decision only the user can make (scope, a trade-off with no obvious default, anything a user of the feature would notice). Do not decide it yourself, even if you have an opinion: the session that wrote the spec agrees with it.
   - Reject: only when the spec already says it explicitly (cite the line) or it asks for something under Out of scope. "It was intentional" is not evidence: intent that is not on the page is a fix. A misread is evidence the text is unclear: fix it.
   - Nit: fix when cheap, otherwise drop.
5. Before applying any fix, check two things:
   - Does it add a component, abstraction, option or caveat the Problem does not need? Then find a smaller fix or escalate.
   - Does it add text only a zero-context reader needs? Then write the shortest summary that stands alone on the page; cite the repo path that holds the full fact as provenance, never in place of the summary.
6. Apply fixes: dispatch `ionian-harness:drafter` with the spec path and the fix list (ids and the required change). Markers that a fix has resolved are removed by the drafter.
7. Ask the escalations one at a time, before round 2. Each gets `Why it matters:` and your recommended answer. Have the drafter apply each answer as under Answers, so round 2 reviews it.

## Round 2: one re-audit

Dispatch all three again as fresh agents. `spec-critic` and `spec-readiness` get the path of `r2-earlier.md` (write it to the review folder first), without your resolutions. They answer each as `- <id>: resolved "<quote>" | open` and report anything new at Blocker level only. `spec-paraphrase` gets the path only.

Number, merge and triage as in round 1, have the drafter apply the fix list, then stop reviewing. There is no round 3, whatever round 2 found. Escalations from round 2 go to the approval step. Fixes applied after round 2 are not reviewed by anyone, so list them for the user at approval.

## Answers

When the user answers a question (round 1 escalations or approval): dispatch the drafter with the answer, so that it edits the affected section in place so no stale statement remains, removes any marker the answer resolves, and adds a line to Review:
`- Clarification (<date>): <question> Answer: <answer>. Changed: <section>.`

## Converge

Everything still open after the re-audit goes to exactly one place:
- Blocker: a question for the user, with your recommended answer.
- Major: fixed, or recorded in the Review section as an accepted risk with one line on why.
- Nit: dropped.

Dispatch the drafter to fill in the Review section of the spec, giving it the counts of each finished round (for example round 1, findings 4, fixed 3, rejected 1) and the rejected and accepted lines. Counts are after merging.

```
## Review
- Round 1 (<date>): paraphrase context <sufficient|missing>, <n> divergences, <n> guesses; critic B<n> M<n> N<n>; readiness B<n> M<n> N<n>. Fixed <n>, rejected <n>, escalated <n>. Not run: <agent or none>.
- Round 2 (<date>): same counts.
- Clarification (<date>): <question> Answer: <answer>. Changed: <section>.
- Rejected: <id>: <finding, one line>. Reason: <the spec line that already says it, or out of scope>.
- Accepted risk: <id>: <finding, one line>. Why: <reason>.
```

The same dispatch tells the drafter to set `Status: reviewed`, after the final review round only.

## Approval

Show the user, in this order and nothing more:
1. Any reviewer recorded as `not run`, first, before Blockers.
2. The round 2 paraphrase, as the reviewer wrote it. It is the best evidence of what the spec says to someone who was not here.
3. Open Blockers and round 2 escalations as questions, each with your recommended answer.
4. Accepted risks.
5. Fixes made after round 2, one line each.
6. The spec path.

Fold the user's answers into the spec as under Answers. Dispatch the drafter to set `Status: approved` only when the user approves in so many words; the dispatch quotes the user's sentence and its date verbatim (for example "I approve this spec", 2026-11-09), and the drafter records the quote under Review. Silence, "looks good so far" or an answer to one question is not approval, and a dispatch without a quoted approval leaves the status unchanged. If the answers add or remove a feature, say that a fresh review is warranted, and do not start one unasked.

After approval the spec changes only with the user's consent, recorded with a date in the Review section by the drafter.
