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
akey="$(jq -r '.agent_id // ""' <<<"$payload")"; [ -n "$akey" ] || akey=main   # budgets and denials are kept per agent context

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

reads="$state_dir/reads-$session"
rec_start=""; rec_end=""; rec_path=""   # the range a read delivers if it is let through
pending=""                              # ranges of this call that passed so far, one ledger line each
record() {  # appends the pending ranges and the current one; a failed write is a state error and never denies
  if [ -n "$rec_start" ]; then pending="$pending$akey $rec_path $rec_start $rec_end"$'\n'; rec_start=""; fi
  [ -n "$pending" ] || return 0
  printf '%s' "$pending" >> "$reads" 2>/dev/null || echo "  -> state error, allowed" >> "$log"
  pending=""
}
union() {  # $1 start $2 end; prints "<distinct lines seen if added><TAB><merged ranges seen so far>"
  # the ledger plus this call's pending ranges; the path is compared exactly, whatever it contains
  local src="$reads"; [ -e "$src" ] || src=/dev/null
  A="$akey" P="$rec_path" PEND="$pending" awk -v ns="$1" -v ne="$2" '
    function add(line,   pre, rest, r, i) {
      pre = ENVIRON["A"] " " ENVIRON["P"] " "
      if (substr(line, 1, length(pre)) != pre) return
      rest = substr(line, length(pre) + 1)
      if (split(rest, r, " ") != 2 || r[1] !~ /^[0-9]+$/ || r[2] !~ /^[0-9]+$/) return
      for (i = r[1] + 0; i <= r[2] + 0; i++) { seen[i] = 1; if (i > mx) mx = i }
    }
    BEGIN { m = split(ENVIRON["PEND"], pl, "\n"); for (k = 1; k <= m; k++) if (pl[k] != "") add(pl[k]) }
    { add($0) }
    END { str = ""; c = 0; i = 1
      while (i <= mx) { if (seen[i]) { j = i; while (seen[j+1]) j++; str = str (str == "" ? "" : ",") i "-" j; c += j - i + 1; i = j + 1 } else i++ }
      for (i = ns; i <= ne; i++) if (!seen[i]) c++
      printf "%d\t%s\n", c, str }' "$src" 2>/dev/null
}

deny() {  # $1 file  $2 line count  $3 lines seen so far and $4 budget, for a budget denial
  local n
  # a gate that cannot name the file or the count must not deny: it saves tokens, so it fails open
  if [ -z "$1" ] || ! [[ "$2" =~ ^[0-9]+$ ]]; then echo "  -> gate error, allowed" >> "$log"; exit 0; fi
  n=$(( $(grep -cxF -- "$akey $1" "$counter" 2>/dev/null) + 1 ))
  echo "$akey $1" >> "$counter"
  if [ "$n" -gt 3 ]; then record; echo "  -> loop guard, allowed" >> "$log"; exit 0; fi
  echo "  -> DENIED ($n/3)" >> "$log"
  if [ -n "$4" ]; then
    echo "Read gate: $1 has $2 lines. This read would take you past the line budget: seen ${3:-none}, budget $4." >&2
  else
    echo "Read gate: $1 has $2 lines (limit $LIMIT). Do not load it whole." >&2
  fi
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
    # images and PDFs are rendered by Read, not loaded as lines
    case "$(tr '[:upper:]' '[:lower:]' <<<"${f##*.}")" in png|jpg|jpeg|gif|webp|pdf) exit 0 ;; esac
    n="$(lines_of "$f")"
    [ "$n" -gt "$LIMIT" ] || exit 0   # small or missing files are not counted
    if ! [[ "${off:-1}" =~ ^[0-9]+$ && "${lim:-1}" =~ ^[0-9]+$ ]]; then echo "  -> parse error, allowed" >> "$log"; exit 0; fi
    start="${off:-1}"; [ "$start" -ge 1 ] || start=1
    if [ -n "$lim" ]; then end=$(( start + lim - 1 )); else end="$n"; fi
    [ "$end" -le "$n" ] || end="$n"
    [ "$start" -le "$end" ] || exit 0   # nothing delivered
    case "$f" in /*) rec_path="$f" ;; *) rec_path="$base/$f" ;; esac
    rec_start="$start"; rec_end="$end"
    # a read that covers the whole file is a whole-file read, however it is spelled
    if [ "$start" -le 1 ] && [ "$end" -ge "$n" ]; then deny "$f" "$n"; fi
    budget="$(bash "$here/lib/config.sh" "$repo" read.file_budget 350 2>/dev/null)"
    [[ "$budget" =~ ^[0-9]+$ ]] || budget=350
    if ! res="$(union "$start" "$end")"; then echo "  -> state error, allowed" >> "$log"; exit 0; fi
    if [ "${res%%$'\t'*}" -gt "$budget" ]; then deny "$f" "$n" "${res#*$'\t'}" "$budget"; fi
    record
    ;;
  Bash)
    cmd="$(jq -r '.tool_input.command // ""' <<<"$payload")"
    # redirects to /dev/null or another fd hide nothing; a redirect to a file still passes
    cmd="$(sed -E 's/[0-9&]*>>?[[:space:]]*\/dev\/null//g; s/[0-9]>&[0-9]//g' <<<"$cmd")"
    is_image() { case "$(tr '[:upper:]' '[:lower:]' <<<"${1##*.}")" in png|jpg|jpeg|gif|webp|pdf) return 0 ;; esac; return 1; }
    abs() { case "$1" in /*) echo "$1" ;; *) echo "$base/$1" ;; esac; }
    whole_file() {  # $1 file: denied when large; never recorded
      is_image "$1" && return 0
      rec_start=""; local n; n="$(lines_of "$1")"
      [ "$n" -gt "$LIMIT" ] && deny "$1" "$n"
      return 0
    }
    range_of() {  # $1 file, $2 mode (abs, head or tail), $3 and $4 the numbers; counts the lines a read delivers
      local f="$1" n s e budget res
      is_image "$f" && return 0
      n="$(lines_of "$f")"; [ "$n" -gt "$LIMIT" ] || return 0   # small or missing files are not counted
      case "$2" in
        head) s=1; e="$3" ;;
        tail) s=$(( n - $3 + 1 )); e="$n" ;;
        *) s="$3"; e="$4"; [ "$e" = '$' ] && e="$n" ;;
      esac
      [ "$s" -ge 1 ] || s=1
      [ "$e" -ge "$s" ] || e="$s"   # sed prints line A for a range that runs backwards
      [ "$e" -le "$n" ] || e="$n"
      [ "$s" -le "$e" ] || return 0   # nothing delivered
      rec_path="$(abs "$f")"; rec_start="$s"; rec_end="$e"
      if [ "$s" -le 1 ] && [ "$e" -ge "$n" ]; then deny "$f" "$n"; fi
      budget="$(bash "$here/lib/config.sh" "$repo" read.file_budget 350 2>/dev/null)"
      [[ "$budget" =~ ^[0-9]+$ ]] || budget=350
      if ! res="$(union "$s" "$e")"; then echo "  -> state error, allowed" >> "$log"; exit 0; fi
      if [ "${res%%$'\t'*}" -gt "$budget" ]; then deny "$f" "$n" "${res#*$'\t'}" "$budget"; fi
      pending="$pending$akey $rec_path $s $e"$'\n'; rec_start=""
    }
    awk_one='^[[:space:]]*NR[[:space:]]*>=[[:space:]]*([0-9]+)[[:space:]]*&&[[:space:]]*NR[[:space:]]*<=[[:space:]]*([0-9]+)[[:space:]]*$'
    awk_two='^[[:space:]]*NR[[:space:]]*==[[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*NR[[:space:]]*==[[:space:]]*([0-9]+)[[:space:]]*$'
    sed_print='^[[:space:]]*([0-9]+)[[:space:]]*(,[[:space:]]*([0-9]+|\$))?[[:space:]]*p[[:space:]]*$'
    # split into simple commands at ; & && || and newlines outside quotes, in order, tracking cd;
    # each line is "<1 if the simple command has a pipe or redirect outside quotes, else 0><TAB><command>"
    while IFS=$'\t' read -r flag seg; do
      # a pipe or redirect makes only its own command targeted, not the whole chain
      [ "$flag" = 1 ] && continue
      if [[ "$seg" =~ ^[[:space:]]*cd[[:space:]]+([^[:space:]]+) ]]; then
        t="${BASH_REMATCH[1]}"; case "$t" in /*) base="$t" ;; *) base="$base/$t" ;; esac
        continue
      fi
      w=()
      while IFS= read -r word; do w+=("$word"); done < <(xargs printf '%s\n' <<<"$seg" 2>/dev/null)  # xargs splits like a shell, so quoted paths stay whole
      [ "${#w[@]}" -gt 0 ] || continue
      files=(); count=""; plus=0; bytes=0; i=1
      case "${w[0]}" in
        cat|less|more)
          for x in "${w[@]:1}"; do case "$x" in -*) ;; *) whole_file "$x" ;; esac; done
          ;;
        head|tail)
          while [ "$i" -lt "${#w[@]}" ]; do
            x="${w[$i]}"; i=$(( i + 1 ))
            case "$x" in
              -n) count="${w[$i]}"; i=$(( i + 1 )) ;;
              -n*) count="${x#-n}" ;;
              -c|-c*) bytes=1 ;;
              -[0-9]*) count="${x#-}" ;;
              -*) ;;
              *) files+=("$x") ;;
            esac
          done
          [ "$bytes" = 1 ] && continue
          case "$count" in +*) plus=1; count="${count#+}" ;; esac
          if [ -n "$count" ] && ! [[ "$count" =~ ^[0-9]+$ ]]; then echo "  -> parse error, allowed" >> "$log"; continue; fi
          for x in "${files[@]}"; do
            if [ -z "$count" ] || { [ "$plus" = 0 ] && [ "$count" -gt "$LIMIT" ]; }; then whole_file "$x"
            elif [ "${w[0]}" = head ]; then [ "$count" -ge 1 ] && range_of "$x" head "$count"
            elif [ "$plus" = 1 ]; then range_of "$x" abs "$count" '$'
            else [ "$count" -ge 1 ] && range_of "$x" tail "$count"; fi
          done
          ;;
        sed)
          scripts=(); script_e=0; quiet=0; inplace=0; skip=0
          while [ "$i" -lt "${#w[@]}" ]; do
            x="${w[$i]}"; i=$(( i + 1 ))
            case "$x" in
              -i*) inplace=1 ;;
              --in-place*) inplace=1 ;;
              --*) skip=1 ;;
              -[A-Za-z]*)
                case "$x" in *f*) skip=1 ;; esac
                case "$x" in *n*) quiet=1 ;; esac
                case "$x" in *e*) scripts+=("${w[$i]}"); script_e=1; i=$(( i + 1 )) ;; esac
                ;;
              *) if [ "$script_e" = 0 ] && [ "${#scripts[@]}" = 0 ]; then scripts+=("$x"); else files+=("$x"); fi ;;
            esac
          done
          if [ "$inplace" = 1 ] || [ "$skip" = 1 ]; then continue; fi
          if [ "${#scripts[@]}" = 0 ] || [ "${#files[@]}" = 0 ]; then continue; fi
          if [ "$quiet" = 0 ]; then for x in "${files[@]}"; do whole_file "$x"; done; continue; fi
          ranges=(); bad=""
          while IFS= read -r one; do
            [ -n "${one//[[:space:]]/}" ] || continue
            if [[ "$one" =~ $sed_print ]]; then
              b="${BASH_REMATCH[3]}"; [ -n "${BASH_REMATCH[2]}" ] || b="${BASH_REMATCH[1]}"
              ranges+=("${BASH_REMATCH[1]} $b")
            elif [[ "$one" == */* ]]; then bad=regex
            else bad=parse; fi
          done < <(printf '%s\n' "${scripts[@]}" | tr ';' '\n')
          if [ "$bad" = parse ]; then echo "  -> parse error, allowed" >> "$log"; continue; fi
          [ -z "$bad" ] || continue   # regex addresses pass uncounted
          for x in "${files[@]}"; do for r in "${ranges[@]}"; do range_of "$x" abs ${r}; done; done
          ;;
        awk)
          prog=""; skip=0
          while [ "$i" -lt "${#w[@]}" ]; do
            x="${w[$i]}"; i=$(( i + 1 ))
            case "$x" in
              -F|-v) i=$(( i + 1 )) ;;
              -f) skip=1 ;;
              -*) ;;
              *) if [ -z "$prog" ]; then prog="$x"; else files+=("$x"); fi ;;
            esac
          done
          [ "$skip" = 0 ] || continue
          if [[ "$prog" =~ $awk_one ]] || [[ "$prog" =~ $awk_two ]]; then
            a="${BASH_REMATCH[1]}"; b="${BASH_REMATCH[2]}"
            for x in "${files[@]}"; do range_of "$x" abs "$a" "$b"; done
          fi
          ;;
      esac
    done < <(awk '{ q=""; out=""; fl=0; len=length($0)
        for (i=1;i<=len;i++) { c=substr($0,i,1)
          if (q!="") { if (c==q) q=""; out=out c }
          else if (c=="\"" || c=="\x27") { q=c; out=out c }
          else if (c==";" || c=="&") { print fl "\t" out; out=""; fl=0 }
          else if (c=="|" && substr($0,i+1,1)=="|") { print fl "\t" out; out=""; fl=0; i++ }
          else { if (c=="|" || c==">") fl=1; out=out c } }
        print fl "\t" out }' <<<"$cmd")
    record   # every read of the command passed: count them all
    ;;
esac
exit 0
