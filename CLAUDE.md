# Ionian Harness

Read `STATE.md` first, then `CONCEPT.md` for the design. Status lives only in `STATE.md`; the concept is the design, not a status board.

Rules for this repo:
- No em dashes or en dashes in anything written here.
- Tests: `bash tests/run.sh`, under 30 seconds. Every hook change comes with a test case. The commit gate in this repo runs this suite.
- Gates that protect something fail closed; gates that save tokens fail open.
- Borrow concepts, write our own files. Upstream prompts and scripts may be read and compared against, never pasted. Where a passage is deliberately kept close to an original, mark it in the file and list the source in `THIRD_PARTY.md`.
- Denial messages tell the model exactly what to do instead, and never mention loop guards or escape hatches beyond the documented `[no-tests]`.
- Scripts are called via `bash <path>`; do not rely on execute bits.
- At session end, rewrite `STATE.md` (fixed template, under 400 words).
