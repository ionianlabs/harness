#!/bin/bash
# Ionian Harness read gate.
# Denies untargeted reads of large files for the main thread and worker agents.
# The reader and the three spec reviewers are exempt: reading whole is their job, and they
# cannot dispatch the reader. Targeted reads (offset/limit, pipes, redirects) pass.
# Loop guard: after 3 denials of the same file in one session, the read passes.
# Mechanism inspired by Spotify's shunt plugin; written from the idea, not the code.

LIMIT="${HARNESS_READ_LIMIT:-350}"
payload="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$payload")"
agent="$(jq -r '.agent_type // ""' <<<"$payload")"
session="$(jq -r '.session_id // "nosession"' <<<"$payload")"

# plugin agents arrive as ionian-harness:<name>; only our own prefix is stripped
case "${agent#ionian-harness:}" in reader|spec-paraphrase|spec-critic|spec-readiness) exit 0 ;; esac

state_dir="$(git rev-parse --git-dir 2>/dev/null || echo /tmp)/harness"
mkdir -p "$state_dir"
counter="$state_dir/denials-$session"
# audit line per call: time, agent, tool, input summary, decision filled in by deny/exit
log="$state_dir/gate.log"
summary="$(jq -r '.tool_input | (.file_path // .command // "") + (if .offset or .limit then " [offset=\(.offset // "-") limit=\(.limit // "-")]" else "" end)' <<<"$payload")"
echo "$(date +%H:%M:%S) agent=${agent:-main} tool=$tool session=$session $summary" >> "$log"

base="$(jq -r '.cwd // empty' <<<"$payload")"; [ -n "$base" ] || base="$PWD"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(git -C "$base" rev-parse --show-toplevel 2>/dev/null || echo "$base")"
# the ask command is named only when the config allows it and claude is installed
use_ask=1
[ "$(bash "$here/lib/config.sh" "$repo" read.ask true 2>/dev/null)" = "false" ] && use_ask=0
command -v claude >/dev/null 2>&1 || use_ask=0
lines_of() {  # relative paths resolve against the payload cwd, moved by any cd in the command
  local f="$1"; case "$f" in /*) ;; *) f="$base/$f" ;; esac
  if [ -f "$f" ]; then wc -l < "$f" | tr -d ' '; else echo 0; fi
}

deny() {  # $1 file  $2 line count
  local n
  # a gate that cannot name the file or the count must not deny: it saves tokens, so it fails open
  if [ -z "$1" ] || ! [[ "$2" =~ ^[0-9]+$ ]]; then echo "  -> gate error, allowed" >> "$log"; exit 0; fi
  n=$(( $(grep -c "^$1\$" "$counter" 2>/dev/null) + 1 ))
  echo "$1" >> "$counter"
  if [ "$n" -gt 3 ]; then echo "  -> loop guard, allowed" >> "$log"; exit 0; fi
  echo "  -> DENIED ($n/3)" >> "$log"
  echo "Read gate: $1 has $2 lines (limit $LIMIT). Do not load it whole." >&2
  if [ "$use_ask" = 1 ]; then
    cat >&2 <<MSG
Get the lines you need with one precise question about this file, answered by a cheap model:
bash $here/lib/ask.sh "<one precise question>" $1
Then Read with offset and limit only on the line ranges it returns.
MSG
  else
    cat >&2 <<MSG
Find the part you need with Grep (or grep -n) for a name or string, then Read with
offset and limit on that range only.
MSG
  fi
  exit 2
}

case "$tool" in
  Read)
    f="$(jq -r '.tool_input.file_path // ""' <<<"$payload")"
    off="$(jq -r '.tool_input.offset // empty' <<<"$payload")"
    lim="$(jq -r '.tool_input.limit // empty' <<<"$payload")"
    [ -n "$off$lim" ] && exit 0
    # images and PDFs are rendered by Read, not loaded as lines
    case "$(tr '[:upper:]' '[:lower:]' <<<"${f##*.}")" in png|jpg|jpeg|gif|webp|pdf) exit 0 ;; esac
    n="$(lines_of "$f")"
    [ "$n" -gt "$LIMIT" ] && deny "$f" "$n"
    ;;
  Bash)
    cmd="$(jq -r '.tool_input.command // ""' <<<"$payload")"
    # redirects to /dev/null or another fd hide nothing; a redirect to a file still passes
    cmd="$(sed -E 's/[0-9&]*>>?[[:space:]]*\/dev\/null//g; s/[0-9]>&[0-9]//g' <<<"$cmd")"
    # split into simple commands at ; & && || and newlines outside quotes, in order, tracking cd
    while IFS= read -r seg; do
      # a pipe or redirect makes only its own command targeted, not the whole chain
      case "$seg" in *"|"*|*">"*) continue ;; esac
      if [[ "$seg" =~ ^[[:space:]]*cd[[:space:]]+([^[:space:]]+) ]]; then
        t="${BASH_REMATCH[1]}"; case "$t" in /*) base="$t" ;; *) base="$base/$t" ;; esac
        continue
      fi
      whole=0
      if [[ "$seg" =~ ^[[:space:]]*(cat|less|more)[[:space:]] ]]; then whole=1; fi
      if [[ "$seg" =~ ^[[:space:]]*(head|tail)[[:space:]] ]]; then
        # a line count above the limit is a whole-file read; -c and -n +N stay targeted
        if [[ "$seg" =~ [[:space:]]-(n[[:space:]]*)?([0-9]+)([[:space:]]|$) ]]; then
          [ "${BASH_REMATCH[2]}" -gt "$LIMIT" ] && whole=1
        elif [[ ! "$seg" =~ \ -[nc] ]]; then whole=1; fi
      fi
      [ "$whole" = 1 ] || continue
      while IFS= read -r word; do  # xargs splits like a shell, so quoted paths stay whole
        case "$word" in -*|cat|less|more|head|tail) continue ;; esac
        n="$(lines_of "$word")"
        [ "$n" -gt "$LIMIT" ] && deny "$word" "$n"
      done < <(xargs printf '%s\n' <<<"$seg" 2>/dev/null)
    done < <(awk '{ q=""; out=""; for (i=1;i<=length($0);i++) { c=substr($0,i,1)
        if (q!="") { if (c==q) q=""; out=out c } else if (c=="\"" || c=="\x27") { q=c; out=out c }
        else if (c==";" || c=="&") { print out; out="" } else out=out c }
      print out }' <<<"$cmd")
    ;;
esac
exit 0
