#!/bin/bash
# Ionian Harness ask: a cheap headless model answers one question about files, with line locations.
# Usage: bash ask.sh "<question>" <file>...
# Exit: 0 ok; 64 usage; 65 file missing, unreadable or a directory; 66 binary or image/PDF file;
#       67 payload over HARNESS_ASK_MAX_BYTES; 68 claude not on PATH; 69 model call failed; 70 timeout.
# Env: HARNESS_ASK_MODEL (haiku), HARNESS_ASK_TIMEOUT (60 s), HARNESS_ASK_MAX_BYTES (400000), CLAUDE_SESSION_ID (log only).
model="${HARNESS_ASK_MODEL:-haiku}"; limit="${HARNESS_ASK_TIMEOUT:-60}"; cap="${HARNESS_ASK_MAX_BYTES:-400000}"
gitdir="$(git rev-parse --absolute-git-dir 2>/dev/null || echo /tmp)"
log="$gitdir/harness/gate.log"
stage=""; work=""; sp=""; bytes=0; nfiles=$(( $# > 0 ? $# - 1 : 0 ))
sess="$(printf %s "${CLAUDE_SESSION_ID:-unknown}" | tr -c 'A-Za-z0-9._-' '_')"  # no newline can forge a log line
finish() {  # runs on every exit: one audit line, temp dirs removed
  local rc=$?
  mkdir -p "$gitdir/harness" 2>/dev/null
  echo "$(date +%H:%M:%S) agent=unknown tool=ask session=$sess files=$nfiles bytes=$bytes exit=$rc seconds=$SECONDS" >> "$log" 2>/dev/null
  [ -n "$stage" ] && rm -rf "$stage"; [ -n "$work" ] && rm -rf "$work"
}
trap finish EXIT
onsig() {  # interrupt: the supervisor kills claude's whole process group, then we exit with the signal's code
  [ -n "$sp" ] && { kill -s "$1" "$sp" 2>/dev/null; wait "$sp" 2>/dev/null; }
  exit "$2"
}
trap 'onsig INT 130' INT; trap 'onsig TERM 143' TERM; trap 'onsig HUP 129' HUP
die() { local rc="$1"; shift; echo "ask.sh: $* Use Grep for a name or string, then Read with offset and limit on that range." >&2; exit "$rc"; }

[ $# -ge 2 ] && [ -n "$1" ] || { echo 'usage: bash ask.sh "<question>" <file>...' >&2; exit 64; }
question="$1"; shift

for f in "$@"; do
  [ -d "$f" ] && die 65 "$f is a directory."
  [ -f "$f" ] && [ -r "$f" ] || die 65 "$f is missing or unreadable."
  case "$(printf %s "$f" | tr 'A-Z' 'a-z')" in *.png|*.jpg|*.jpeg|*.gif|*.webp|*.pdf) die 66 "$f is an image or PDF." ;; esac
  [ "$(tr -d '\0' < "$f" | wc -c)" = "$(wc -c < "$f")" ] || die 66 "$f is a binary file."
done

stage="$(mktemp -d)"
{
  printf '%s\n' "$question"
  for f in "$@"; do
    abs="$(cd -- "$(dirname -- "$f")" && pwd)/$(basename -- "$f")"
    printf '<file path="%s">\n' "$abs"
    awk '{ print NR "\t" $0 }' < "$f"
    printf '</file>\n'
  done
} > "$stage/payload"
bytes="$(wc -c < "$stage/payload" | tr -d ' ')"
[ "$bytes" -le "$cap" ] || die 67 "payload is $bytes bytes, over the cap of $cap (HARNESS_ASK_MAX_BYTES); pass fewer files."
command -v claude >/dev/null 2>&1 || die 68 "claude is not on PATH."

read -r -d '' prompt <<'P'
You answer one question about the numbered files in the user message. Each file sits in a file tag that carries its absolute path; every line starts with its line number, a tab, then the text.
Reply with bullets only, no introduction and no closing remarks. Start every bullet with the absolute path, a colon, and the line range in the form L<start>-L<end>, for example /abs/file.txt:L10-L24, then one short statement of the fact found there. Use at most 25 bullets. Cite only ranges that exist in the files. If the files do not contain the answer, reply with exactly one bullet that says so.
P

work="$(mktemp -d)"
# the supervisor puts claude in its own process group and kills the whole group on timeout or signal (macOS has no timeout command)
( cd "$work" && CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 \
  exec perl -e '$t=shift; $p=fork; if(!$p){setpgrp(0,0); exec @ARGV or exit 127}
    $SIG{ALRM}=sub{kill "KILL",-$p; waitpid($p,0); exit 124};
    for $x (["INT",130],["TERM",143],["HUP",129]){ ($n,$c)=@$x; $SIG{$n}=sub{my $c=$c; kill "KILL",-$p; waitpid($p,0); exit $c} }
    alarm $t; waitpid($p,0); $s=$?; kill "KILL",-$p;
    exit($s&127 ? 128+($s&127) : $s>>8)' "$limit" \
  claude -p --model "$model" --tools "" --no-session-persistence --strict-mcp-config \
    --setting-sources "" --disable-slash-commands --system-prompt "$prompt" --output-format text \
    < "$stage/payload" > "$stage/out" 2>/dev/null ) &
sp=$!
wait "$sp"; rc=$?; sp=""
[ "$rc" = 124 ] && die 70 "the model call timed out after ${limit}s."
[ "$rc" = 0 ] || die 69 "the model call failed (exit $rc)."
cat "$stage/out"
