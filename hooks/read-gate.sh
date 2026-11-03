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
echo "$(date +%H:%M:%S) agent=${agent:-main} tool=$tool $summary" >> "$log"

lines_of() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }

deny() {  # $1 file  $2 line count
  local n
  n=$(( $(grep -c "^$1\$" "$counter" 2>/dev/null) + 1 ))
  echo "$1" >> "$counter"
  if [ "$n" -gt 3 ]; then echo "  -> loop guard, allowed" >> "$log"; exit 0; fi
  echo "  -> DENIED ($n/3)" >> "$log"
  cat >&2 <<MSG
Read gate: $1 has $2 lines (limit $LIMIT). Do not load it whole.
Dispatch the "reader" agent with one precise question about this file and ask for
line numbers. If you then still need the text, Read with offset and limit on the
range it names.
MSG
  exit 2
}

case "$tool" in
  Read)
    f="$(jq -r '.tool_input.file_path // ""' <<<"$payload")"
    off="$(jq -r '.tool_input.offset // empty' <<<"$payload")"
    lim="$(jq -r '.tool_input.limit // empty' <<<"$payload")"
    [ -n "$off$lim" ] && exit 0
    n="$(lines_of "$f")"
    [ "$n" -gt "$LIMIT" ] && deny "$f" "$n"
    ;;
  Bash)
    cmd="$(jq -r '.tool_input.command // ""' <<<"$payload")"
    case "$cmd" in *"|"*|*">"*) exit 0 ;; esac
    whole=0
    if [[ "$cmd" =~ ^[[:space:]]*(cat|less|more)[[:space:]] ]]; then whole=1; fi
    if [[ "$cmd" =~ ^[[:space:]]*(head|tail)[[:space:]] ]] && [[ ! "$cmd" =~ \ -[nc] ]]; then whole=1; fi
    if [ "$whole" = 1 ]; then
      for word in $cmd; do
        case "$word" in -*|cat|less|more|head|tail) continue ;; esac
        n="$(lines_of "$word")"
        [ "$n" -gt "$LIMIT" ] && deny "$word" "$n"
      done
    fi
    ;;
esac
exit 0
