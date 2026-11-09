# Read gate v2: a script every agent can call, and a budget in lines

Status: approved 2026-11-09
Slug: read-gate-v2
Date: 2026-11-08

## Problem
Today: Ionian Harness is a Claude Code plugin (`README.md`). The host runs `hooks/read-gate.sh` before each Read and Bash call of an agent, passing a JSON payload on stdin; exit 2 denies the call and its stderr text goes to the agent. The gate denies a Read of a large file without offset and limit, and in Bash a `cat`, `less` or `more` of one, or a `head` or `tail` of one without a line count or with a count over the read limit. Every other read form passes. Ionian Flow is an application repo where the harness is used day to day, the first pilot. P1, P2, P3 below are priorities, P1 first.

The read gate (`hooks/read-gate.sh`, PreToolUse on `Read` and `Bash`) exists to keep large files out of an agent's context and to push that work to a cheaper reader. The audit log of the first pilot-like use (`<git-dir>/harness/gate.log` in the Ionian Flow repo) shows it does neither: about 880 gated tool calls, 10 denials, 0 dispatches of the `reader` agent. Seven denials were false positives on screenshots (fixed in commit 3f70237, with two other quick fixes listed below). The two real code denials hit `general-purpose` subagents, which were told to dispatch the reader agent. A subagent has no agent-dispatch tool, so it fell back to chunked reads, for example `sed -n 1,135p; sed -n 285,440p; sed -n 500,520p` on an 864-line file right after its denial. Three causes: the only delegation path is an agent dispatch, which subagents cannot use and the main thread never used; the gate judges syntax ("is this read targeted?") and not volume, so a file can be read whole in ranges, and `sed -n`, `awk` and Read offset/limit are never counted; nothing makes the main thread delegate at all. The concept followed (credited in `README.md`: Spotify's shunt) points denials at a shell script that sends files to a cheaper model outside the session and returns only the answer, so any agent can use it.

Already shipped in 3f70237, and unchanged here only for the image/PDF pass and the pipe and redirect part of the segment rule: images and PDFs (png jpg jpeg gif webp pdf) pass the Read gate; a pipe or redirect makes only its own command segment targeted. The denial texts shipped there (a subagent's Grep message, the main thread's reader message) are replaced by F1.

## Out of scope
- A Copilot CLI fallback and the Copilot port.
- Counting output of non-read commands (git diff, test output, build logs).
- Enforcing that the main thread delegates edits: see `docs/designs/coordinator-hands-off.md`.
- Resetting budgets on context compaction.
- Caching ask answers.
- Read forms that are not counted, known gaps: awk programs other than the two forms in F2, python or perl reads, a `<` redirect, `$( )`, the Grep tool's content output with context lines, and a counted command whose output is piped, `sed -i`, `sed` with regex addresses, and `head -c` or `tail -c`.

## Terms
- **delivered lines**: the line numbers of a file that a read puts into an agent's context.
- **exempt agent**: `reader`, `spec-paraphrase`, `spec-critic`, `spec-readiness`, bare or prefixed `ionian-harness:`. The gate does not count or deny them.
- **main thread**: a payload whose `agent_id` is empty (CONCEPT.md, milestone 0: gates key on `agent_type` for roles and on an empty `agent_id` for the main thread). Exemptions keep keying on `agent_type`.
- **segment rule**: a Bash command is split at `;`, `&` and newlines outside quotes (so `&&` splits and `||` does not today); a segment containing a pipe or a redirect is treated as targeted and passes. v2 also splits at `||` outside quotes, so each side is judged on its own.
- **fallback message**: today's subagent denial text in `hooks/read-gate.sh`: "Find the part you need with Grep (or grep -n) for a name or string, then Read with offset and limit on that range only."
- **read limit**: `HARNESS_READ_LIMIT`, default 350 lines.
- **large file**: a file with more lines than the read limit, always measured against the read limit; `file_budget` only caps the union of lines seen.

## Features

### F1. ask script, and every denial points to it (P1)
Why: removes cause one of the Problem. A shell command works for the main thread and for every subagent, so a denial can always name a step the denied agent can carry out.

Story: As an agent denied a large file, I want one command that answers my question about it with line locations, so that I read only the ranges I need.

Scenarios (unit scenarios put a fake `claude` executable first on `PATH`; the file `big.txt` has 400 lines `line 1` to `line 400`):
- F1.1 Given a fake `claude` that echoes its stdin, when `ask.sh "where is line 200?" big.txt` runs, then stdout contains every line as the line number, one tab, the line, no padding (`200<TAB>line 200`), the tag `<file path="` followed by the absolute path of `big.txt`, and the question text; exit 0.
- F1.2 Given two files, when `ask.sh` runs with both, then stdout of the echoing fake shows two `<file path=...>` blocks in argument order; exit 0.
- F1.3 Given no arguments, a question and no file, or an empty question string, when `ask.sh` runs, then exit 64 and one stderr line with the usage.
- F1.4 Given `missing.txt` does not exist, when `ask.sh "q" missing.txt` runs, then exit 65 and stderr names `missing.txt`; a directory as argument also exits 65.
- F1.5 Given a file containing a NUL byte, or a file named `shot.png`, when `ask.sh "q"` runs on it, then exit 66, stderr names the file, and no `claude` call is made (the other files are not read either).
- F1.6 Given `HARNESS_ASK_MAX_BYTES=1000` and a 400-line file (the assembled payload of question, tags and numbered lines is about 4000 bytes, over 1000), when `ask.sh` runs, then exit 67 and stderr names the cap and suggests fewer files or Grep first.
- F1.7 Given `claude` is not on `PATH`, when `ask.sh` runs, then exit 68 and stderr says so.
- F1.8 Given a fake `claude` that prints `API error` on stdout and exits 1, when `ask.sh` runs, then exit 69, stdout is empty, and stderr has one line.
- F1.9 Given a fake `claude` that sleeps 5 seconds and `HARNESS_ASK_TIMEOUT=1`, when `ask.sh` runs, then exit 70 within 3 seconds stderr names the timeout, and no process of the fake `claude` or its children is left running (the `claude` process and its children are killed before exit 70).
- F1.10 Given any run of `ask.sh` in a git repo, then one line is appended to `<git-dir>/harness/gate.log` with `tool=ask`, file count, bytes, exit code and seconds; outside git the same fallback directory as the read gate is used.
- F1.11 Given a main-thread Read of the 400-line file without offset or limit, when the gate denies it, then stderr contains `bash <absolute plugin-root>/lib/ask.sh "` and the absolute path of the file, and says to Read with offset and limit only on the returned ranges; the same holds for a payload with a non-empty `agent_id` and `agent_type` `general-purpose`.
- F1.12 Given `[read] ask = false` in `harness.toml`, or `claude` not on `PATH` when the hook runs, when the gate denies, then every F2 and whole-file denial uses the fallback message for the main thread and subagents alike, and the F3 denial keeps "dispatch a subagent" and drops the ask command.
- F1.13 Given the `reader` agent reads big.txt whole, then exit 0; the denial stderr of F1.11 and F2.3 does not contain `reader`.
- F1.14 Given a fake `claude` that writes its argv, its environment and `pwd` to a file, when `ask.sh` runs, then argv contains `-p`, `--model haiku` (or `$HARNESS_ASK_MODEL` when set), `--tools` with an empty argument, `--no-session-persistence`, `--strict-mcp-config`, `--setting-sources` with an empty argument, `--disable-slash-commands`, `--system-prompt` and `--output-format text`; the environment has `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` and `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1`; and `pwd` was an empty directory that no longer exists after exit.

The model call itself: the prompt requires bullets only, each starting `<absolute path>:L<start>-L<end>` then the fact, at most 25 bullets, and one bullet saying so when the answer is not in the files. The answer is a locator; the caller Reads the cited ranges when it needs the text. The call runs from a fresh empty temporary directory with auto memory and CLAUDE.md loading disabled, no tools, no session persistence, no MCP, no settings sources and no slash commands. A bound of `HARNESS_ASK_TIMEOUT` seconds is enforced without relying on `timeout`, which macOS lacks.

Testability: unit. Tested on its own by running `lib/ask.sh` and the gate against a fake `claude` first on `PATH` (echo, argv dump, error text with exit 1, sleep) in a throwaway git repo; shows exit code, stdout, stderr, the log line and the recorded argv. The real model call is a manual check outside the unit suite because it costs tokens; see SC3.

### F2. Per-file line budget across read forms (P2)
Why: removes cause two. The gate counts lines, not syntax, so ranges cannot add up to a whole file unnoticed.

Story: As the maintainer, I want an agent to see at most a budget of distinct lines of a large file, so that chunked reads cannot bypass the gate.

Scenarios (session `s1`, `big.txt` of 400 lines, `file_budget` 350, non-exempt agent):
- F2.1 Given nothing read yet, when Read with offset 1 and limit 300 arrives, then exit 0.
- F2.2 Given F2.1 happened, when Read with offset 200 and limit 100 arrives (lines 200 to 299, all seen), then exit 0 and the union stays 300.
- F2.3 Given F2.1 happened, when `sed -n '301,360p' big.txt` arrives (60 new lines, union would be 360), then exit 2, and stderr contains `seen 1-300`, `budget 350` and `lib/ask.sh` (several ranges are joined with commas, e.g. `seen 1-3,9-9`).
- F2.4 Given a fresh session, when Read with offset 391 arrives, then exit 0 and `reads-s1` gains `main <path> 391 400`; likewise Read with limit 5 gains `main <path> 1 5`, and Read with offset 10 and limit 3 gains `main <path> 10 12`.
- F2.5 Given a fresh session, when `sed -n '1,400p' big.txt` or Read without offset and limit arrives, then exit 2 (whole-file reads stay denied).
- F2.6 Given `sed -n '1,300p' big.txt | cat`, when it arrives, then it is not counted and exits 0.
- F2.7 Given the same file denied 3 times to one agent in the session (budget and whole-file denials share the counter), when its 4th read arrives, then exit 0 and the log notes the loop guard.
- F2.8 Given agent type `reader` or `ionian-harness:spec-critic`, when any read arrives, then exit 0 and nothing is recorded.
- F2.9 Given `reads-s1` is mode 000, when Read offset 1 limit 300 arrives, then exit 0 and `gate.log` has `state error`; given `sed -n "$X" big.txt` (unexpanded variable), then exit 0 and the log has `parse error`; whole-file denials are unaffected by state errors.
- F2.10 Given a 400-line file and `file_budget = 100` in `harness.toml`, when Read offset 1 limit 150 arrives, then exit 2.
- F2.11 Given a 200-line file (not large), when `sed -n '1,200p'` or a whole Read of it arrives, then exit 0 and nothing is added to `reads-s1`.
- F2.12 Given a fresh session, when `sed -n '10,12p' big.txt` arrives, then exit 0 and the delivered range is 10 to 12.
- F2.13 Given a fresh session, when `sed -n 10p big.txt` arrives, then exit 0 and the delivered range is 10 to 10; `sed -n -e '1,3p' -e '9p' big.txt` delivers 1 to 3 and 9 to 9.
- F2.14 Given a fresh session, when `head -n 20 big.txt` or `head -20 big.txt` arrives, then exit 0 and the delivered range is 1 to 20.
- F2.15 Given a fresh session, when `tail -n 20 big.txt` arrives, then exit 0 and the delivered range is 381 to 400.
- F2.16 Given a fresh session, when `tail -n +395 big.txt` arrives, then exit 0 and the delivered range is 395 to 400.
- F2.17 Given a fresh session, when `awk 'NR>=5 && NR<=8' big.txt` arrives, then exit 0 and the delivered range is 5 to 8.
- F2.18 Given a fresh session, when `awk 'NR==5,NR==8' big.txt` arrives, then exit 0 and the delivered range is 5 to 8.
- F2.19 Given a fresh session in which Read with offset 1 and limit 350 passed, when Read with offset 351 and limit 50 arrives (50 unseen lines, union would be 400), then exit 2.
- F2.20 Given agent A (`agent_id` `a1`) has read lines 1 to 300 of big.txt in session `s1`, when agent B (`agent_id` `b1`, same session) reads lines 1 to 300, then both exit 0, because the union is kept per agent.
- F2.21 Given agent a1 was denied 3 times on big.txt in session `s1`, when agent b1 makes its first whole Read of big.txt, then exit 2, because the loop guard counts per agent.
- F2.22 Given a fresh session, when `sed 's/a/b/' big.txt` (no `-n`, no `-i`) arrives, then exit 2 as a whole-file read; `sed -i 's/a/b/' big.txt` exits 0 and records nothing.
- F2.23 Given a fresh session, when `sed -n '391,$p' big.txt` arrives, then exit 0 and the delivered range is 391 to 400.
- F2.24 Given a fresh session, when `sed -n '1,400p' big.txt || true` arrives, then exit 2; `cat big.txt || true` also exits 2.

Rules: reads of png jpg jpeg gif webp pdf are not counted by F2 or F3. `cat` of a large file stays denied as a whole-file read and is not recorded in the union. A denied read records nothing; a read let through by the loop guard is recorded like any delivered read. The union is kept per session and per agent: the key is the payload's `agent_id`, or `main` when it is empty. A Read with offset alone delivers offset to the end of the file; limit alone delivers from line 1; ranges are clipped to the file length. Several print commands in one `sed -n`, separated by `-e` or `;`, are all counted. The union is of distinct line numbers per agent key and absolute path; re-reading a seen range costs nothing. The denial states the lines already seen, the budget, and the F1 command. In fallback mode (F1.12) an F2 denial keeps `seen ...` and `budget N` with the fallback text in place of the ask command. Once an agent has 3 denials on a file, every later read of that file by that agent passes for the rest of the session; F3 denials share the same per-agent, per-file counter. The whole-file rule also applies to a Read whose offset and limit cover the whole file. Every Bash form on a large file falls in one row:

| Form | Rule |
|---|---|
| `cat`, `less`, `more`; `head`/`tail` with a count over the read limit | denied whole-file |
| `sed` without `-n` and without `-i` (prints every line) | denied whole-file |
| `sed -n 'A,Bp'`, `sed -n Ap`, `sed -n 'A,$p'` (A to end), `head -n N`, `tail -n N`, `tail -n +K`, `head`/`tail` with no count (10 lines), `sed Nq` (lines 1 to N), the two awk forms | counted as the range |
| any counted range covering every line of the file | denied whole-file |
| `sed -i`; `sed` with regex addresses; `head -c`, `tail -c`; `tail -f`, `-F`, `--follow` | passes uncounted |

Testability: unit. Tested on its own by feeding payload sequences with one session id into `hooks/read-gate.sh`; shows the exit codes, stderr and the content of `reads-<session>`.

### F3. Main-thread session read budget (P3)
Why: removes cause three. Without it nothing makes the main thread delegate, and the pilot cannot measure how much a main thread reads.

Story: As the maintainer, I want the main thread to delegate after it has loaded a set amount, so that its context stays free for coordination.

F3 counts and limits every read the gate can measure on the main thread: Read (whole or ranged, any file size), `cat` of a file (its line count), and every counted form of F2.

Rule: when the summed total is at or above `session_budget`, a main-thread read delivering more than `small_read` lines is denied; reads of at most `small_read` lines pass and are still counted.

Scenarios (session `s2`, main thread, `session_budget` 3000, `small_read` 40):
- F3.1 Given a main-thread session that has read 3000 lines in total through Read (whole or ranged, any file size) and `cat` of files, when a Read delivering 41 lines arrives, then exit 2 and stderr tells it to dispatch a subagent for the task or to run the ask.sh command.
- F3.2 Given the same state, when a Read delivering 40 lines arrives, then exit 0.
- F3.3 Given 2999 lines read so far, when a whole Read of a 300-line file arrives, then exit 0 and the total becomes 3299 (the budget is checked before the read; the read that crosses it passes).
- F3.4 Given the same state as F3.1 and a payload with a non-empty `agent_id` and agent type `general-purpose`, when the same Read arrives, then exit 0: the session budget counts and limits the main thread only.
- F3.5 Given F3.1's state, when a 41-line read of one file is denied 3 times, then the 4th passes.
- F3.6 Given a Read of the same 100 lines repeated, when counted, then each delivery adds 100 (context was consumed each time).
- F3.7 Given F3.1's state, when `sed -n '1,100p' small.txt` (a 200-line file) arrives, then exit 2.

Testability: unit. Tested on its own by pre-writing `mainlines-s2` with a total of 3000 or 2999, then feeding one payload; shows the exit code, the stderr text and the new total in `mainlines-s2`.

## Success criteria
- SC1 0 of the denials point at a step the denied agent cannot carry out, checked for a main-thread payload and a subagent payload in the unit suite.
- SC2 A non-exempt agent that tries to read all of a 1000-line file in 100-line ranges, through any counted read form, is denied at least once before it has seen more than 350 distinct lines.
- SC3 (manual) A question about one file of about 900 lines is answered with line locations in under 15 seconds median over 5 runs, in at most 30 lines, with the cited ranges correct on a spot check.
- SC4 (pilot, two weeks) At least 50 percent of denials are followed within the next 3 gated calls of the same session by a delegated question, that is a `tool=ask` line in `gate.log` with the same session id, counted by session id from the audit log. The share of main-thread sessions that reach the session budget is reported with no threshold; it tunes the default.
- SC5 `bash tests/run.sh` finishes in under 30 seconds with the new checks included.

## Interfaces and data
- `hooks/read-gate.sh` (changed): adds the counted forms, the line budgets and the ask referral; fails open on any parse or state error; keeps the exemption, the loop guard of 3 denials per agent and file in a session, the image and PDF pass, and the segment rule. Its log lines gain `session=<id>`. Resolves the plugin root from its own location.
- `lib/ask.sh` (new): `bash <plugin-root>/lib/ask.sh "<question>" <file>...`. Stdout is only the model's answer. Exit codes: 0 ok; 64 usage; 65 file missing or unreadable; 66 binary file or image/PDF extension; 67 payload over the cap; 68 `claude` not on `PATH`; 69 model call exited nonzero; 70 timeout. Exit 65 also covers a directory and exit 64 an empty question. `ask.sh` checks in this order and the first failure decides: arguments (64), each file in argument order (65, 66), payload size (67), `claude` on `PATH` (68), then the call (69, 70). Each failure writes one stderr line naming the cause and telling the caller to use Grep, then Read with offset and limit.
- Env vars (all new, read by `lib/ask.sh`): `HARNESS_ASK_MODEL` (default `haiku`), `HARNESS_ASK_TIMEOUT` (default 60, seconds), `HARNESS_ASK_MAX_BYTES` (default 400000, bytes of the assembled payload sent to the model: question, tags and numbered lines).
- Headless call of `lib/ask.sh` (new): `claude -p --model $HARNESS_ASK_MODEL --tools "" --no-session-persistence --strict-mcp-config --setting-sources "" --disable-slash-commands --system-prompt <ask prompt> --output-format text`, payload on stdin, run from an empty temporary directory removed on exit, with env `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` and `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1`. On timeout `claude` and its children are killed.
- `harness.toml` section `[read]` (new), read through `lib/config.sh`, defaults apply with no harness config: `ask` (new, default true; false disables the referral), `file_budget` (new, default 350), `session_budget` (new, default 3000), `small_read` (new, default 40). `HARNESS_READ_LIMIT` is unchanged.
- State, in `<git-dir>/harness/` (fallback `/tmp/harness` outside git): `denials-<session>` (existing; lines become `<agent> <path>`, agent being the `agent_id` or `main`); `reads-<session>` (new, one file per session, one line per delivered range: `<agent> <path> <start> <end>`, where `<agent>` is the `agent_id` or `main`, and the last two fields are the range, so a path may contain spaces); `mainlines-<session>` (new, one line per main-thread read holding its delivered line count, summed for F3).
- `gate.log` ask line (new): `HH:MM:SS agent=unknown tool=ask session=<id|unknown> files=<n> bytes=<n> exit=<n> seconds=<n>`; `ask.sh` cannot see the hook payload, so it reads `CLAUDE_CODE_SESSION_ID` from its environment if present, else logs `session=unknown`; read gate lines gain `session=<id>`.
- Denial message (required elements, not exact wording): the file and its line count or the budget figures; the runnable ask command with absolute `lib/ask.sh` path and the denied file; the instruction to Read with offset and limit only on returned ranges; for F2 the substrings `seen A-B`, `budget N` and `lib/ask.sh`. Fallback text per F1.12. No denial text mentions the loop guard.
- Files that must mention `ask.sh` afterwards: `README.md` ("What is here", the `hooks/read-gate.sh` line), `skills/tdd/SKILL.md` (the line on files over 350 lines), `CONCEPT.md` (the read shunt row). `tests/run.sh` gains the checks of F1 to F3.

## Decisions
- A shell script, not the `reader` agent, is the denial target, because subagents cannot dispatch agents and a Bash command works for every agent. Rejected: keeping the reader agent as the main-thread target, because it was dispatched 0 times in about 880 calls.
- The script calls the headless Claude CLI with the cheap model on the session's own login. Rejected: `--bare`, because it skips the keychain (not logged in, exit 1); a Copilot CLI fallback, deferred to the Copilot port; a separate API key, because it is a new secret to manage. Data goes to the provider the session already sends its reads to, so there is no new destination; `[read] ask = false` serves repos whose policy forbids the CLI.
- The budget is a union of distinct lines, not a sum of reads, because re-reading a range around an edit must stay free.
- The budget default equals the read limit, so a non-exempt agent never sees more of a large file than of a whole small file.
- The loop guard stays, because token-saving gates fail open; with ask.sh available it should rarely fire and the log shows when it does. Rejected: dropping it, because a broken ask.sh would then block work.
- F3 is on by default with a measured default tuned after the pilot. Rejected: off by default, because nothing would be measured.
- The reader agent stays for open-ended exploration across files, exempt, and is no longer named in denials.

- Budgets are per agent context: the union is keyed by session and `agent_id`. Rejected: one union per session, because a reviewer subagent would be denied for lines the coder subagent read in its own context.
- The model call gets no tools, so instructions planted in file content cannot make it act; its output is plain text the caller reads as a locator. Rejected: giving it Read and Grep, because it would become a second agent whose reads interplay with the read gate.

## Assumptions
- 3000 lines is a sensible main-thread budget. If wrong: tune from the pilot log.
- Haiku's line ranges are accurate enough as a locator (probe 2026-11-08: 864 lines in 9.8 s, two files in 6.1 s, 490 KB in 3.0 s, numbers spot-checked). If wrong: the caller reads a wider range, or `HARNESS_ASK_MODEL` changes.
- `claude` is on `PATH` where the harness runs. If wrong: denials fall back to the Grep message.
- The session id stays the same across context compaction. If wrong: budgets reset, which is lenient and acceptable.

- The environment provides `CLAUDE_CODE_SESSION_ID` to commands the agent runs. If wrong: SC4 is counted by a 60 second time window after each denial instead of by session id.

## Dependencies
none new. The `claude` CLI is already required by the host; `perl` and `awk` are present on macOS.

## Review
- Round 1 (2026-11-08): paraphrase context missing, 0 divergences, 10 guesses; critic B0 M5 N4; readiness B0 M5 N3. Fixed 27, rejected 0, escalated 0. Not run: none.
- Round 2 (2026-11-08): paraphrase context sufficient, 0 divergences, 6 guesses; critic B0 M0 N0, all 17 earlier resolved; readiness B1 M0 N0. Fixed 6 after the re-audit (R2-1 and five guess clarifications), dropped 1 Nit (usage line wording). Not run: none.
- Fixed after round 2, unreviewed: R2-1 splitting at `||` (F2.24); five one-line clarifications of fallback denial content, loop guard after the 3rd denial, shared counter for F3, whole-range rule for Read, ask.sh check order.
- Amended after code review (2026-11-09): head and tail without a count count 10 lines instead of a whole-file read; coordinator decision, lenient direction.
- Approved (2026-11-09): the user replied "go" to the request "If you say I approve read-gate-v2, I'll record that in the spec and start right away".
