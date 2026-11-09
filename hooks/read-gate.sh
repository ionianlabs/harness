#!/bin/bash
# Ionian Harness read gate.
# Denies untargeted reads of large files for the main thread and worker agents.
# The reader and the three spec reviewers are exempt: reading whole is their job, and they
# cannot dispatch the reader. Targeted reads (offset/limit, pipes, redirects) pass.
# Loop guard: after 3 denials of the same file in one session, the read passes.
# Mechanism inspired by Spotify's shunt plugin; written from the idea, not the code.

LIMIT="${HARNESS_READ_LIMIT:-350}"
# Process starts are what is slow on a managed machine, so this gate keeps them few: the payload
# is read by a builtin and parsed by one jq, git is asked once, the config is read only where its
# value is needed, and bash builtins do what tr, sed and wc would.
IFS= read -r -d '' payload
tool=""; agent=""; session=""; akey=""; base=""; f=""; off=""; lim=""; cmd=""; summary=""
# @sh quotes every value, so its output is safe to eval whatever the payload holds
eval "$(jq -r '@sh "tool=\(.tool_name // "") agent=\(.agent_type // "") session=\(.session_id // "nosession") akey=\(.agent_id // "") base=\(.cwd // "") f=\(.tool_input.file_path // "") off=\(.tool_input.offset // "") lim=\(.tool_input.limit // "") cmd=\(.tool_input.command // "") summary=\(.tool_input | (.file_path // .command // "") + (if .offset or .limit then " [offset=\(.offset // "-") limit=\(.limit // "-")]" else "" end))"' <<<"$payload" 2>/dev/null)"
[ -n "$akey" ] || akey=main   # budgets and denials are kept per agent context

# plugin agents arrive as ionian-harness:<name>; only our own prefix is stripped
case "${agent#ionian-harness:}" in reader|spec-paraphrase|spec-critic|spec-readiness) exit 0 ;; esac

# one git call: the git dir of the directory the hook runs in, and its work tree
gitout="$(git rev-parse --git-dir --show-toplevel 2>/dev/null)"
if [[ "$gitout" == *$'\n'* ]]; then gitdir="${gitout%%$'\n'*}"; top0="${gitout#*$'\n'}"; else gitdir="$gitout"; top0=""; fi
state_dir="${gitdir:-/tmp}/harness"
[ -d "$state_dir" ] || mkdir -p "$state_dir"
counter="$state_dir/denials-$session"
# audit line per call: time, agent, tool, input summary, decision filled in by deny/exit
log="$state_dir/gate.log"
printf -v ts '%(%H:%M:%S)T' -1 2>/dev/null || ts="$(date +%H:%M:%S)"   # the builtin needs bash 4.2, older bash asks date
echo "$ts agent=${agent:-main} tool=$tool session=$session $summary" >> "$log"

[ -n "$base" ] || base="$PWD"
base0="$base"
here=""; repo=""
need_repo() {  # the plugin dir and the work tree of the payload cwd, found only where the config is read
  [ -z "$repo" ] || return 0
  if [ -n "$top0" ] && [ "$base0" = "$PWD" ]; then repo="$top0"
  else repo="$(git -C "$base0" rev-parse --show-toplevel 2>/dev/null || echo "$base0")"; fi
  local d="${BASH_SOURCE[0]%/*}"; [ "$d" != "${BASH_SOURCE[0]}" ] || d=.
  here="$(cd "$d/.." && pwd)"
}
file_budget() {  # sets budget from the config; 350 when absent or not a number
  need_repo
  budget="$(bash "$here/lib/config.sh" "$repo" read.file_budget 350 2>/dev/null)"
  [[ "$budget" =~ ^[0-9]+$ ]] || budget=350
}
lines_of() {  # sets LN; relative paths resolve against the payload cwd, moved by any cd in the command
  local p="$1" c=0 l; case "$p" in /*) ;; *) p="$base/$p" ;; esac
  LN=0; [ -f "$p" ] || return 0
  # a file of at most LIMIT lines is counted by the shell; only a larger one starts wc
  while IFS= read -r l; do c=$((c+1)); [ "$c" -gt "$LIMIT" ] && break; done <"$p" 2>/dev/null
  if [ "$c" -gt "$LIMIT" ]; then LN="$(wc -l < "$p" 2>/dev/null)"; LN="${LN// /}"; else LN="$c"; fi
}
is_image() {  # rendered by Read as an image or document, not loaded as lines
  local r=1; shopt -s nocasematch
  case "${1##*.}" in png|jpg|jpeg|gif|webp|pdf) r=0 ;; esac
  shopt -u nocasematch; return $r
}


reads="$state_dir/reads-$session"
rec_start=""; rec_end=""; rec_path=""   # the range a read delivers if it is let through
pending=""                              # ranges of this call that passed so far, one ledger line each
mainlines="$state_dir/mainlines-$session"   # main thread only: one line per read, the lines it delivered (F3)
mcur=""; mpend=""; msum=0               # lines of the read being judged; of this call's reads that passed; their sum
record() {  # appends the pending ranges and the current one; a failed write is a state error and never denies
  if [ -n "$rec_start" ]; then pending="$pending$akey $rec_path $rec_start $rec_end"$'\n'; rec_start=""; fi
  if [ -n "$mcur" ]; then mpend="$mpend$mcur"$'\n'; mcur=""; fi
  if [ -n "$pending" ]; then
    printf '%s' "$pending" 2>/dev/null >> "$reads" || echo "  -> state error, allowed" >> "$log"
    pending=""
  fi
  if [ -n "$mpend" ]; then
    printf '%s' "$mpend" 2>/dev/null >> "$mainlines" || echo "  -> state error, allowed" >> "$log"
    mpend=""; msum=0
  fi
}
m_judge() {  # $1 file  $2 its line count; the main thread's read of $mcur lines, denied once the session total is at the budget
  [ -n "$mcur" ] || return 0
  local t=0 l bud small
  if [ -f "$mainlines" ]; then
    if [ ! -r "$mainlines" ]; then echo "  -> state error, allowed" >> "$log"; mcur=""; return 0; fi
    # only plain counts of at most 9 digits are summed; anything else in the file is skipped
    while IFS= read -r l; do if [[ "$l" =~ ^[0-9]{1,9}$ ]]; then t=$(( t + 10#$l )); fi; done <"$mainlines"
  fi
  t=$(( t + msum ))
  if [ "$t" -lt 0 ] 2>/dev/null; then echo "  -> state error, allowed" >> "$log"; mcur=""; return 0; fi
  need_repo
  bud="$(bash "$here/lib/config.sh" "$repo" read.session_budget 3000 2>/dev/null)"
  [[ "$bud" =~ ^[0-9]+$ ]] || bud=3000
  if [ "$t" -ge "$bud" ]; then
    small="$(bash "$here/lib/config.sh" "$repo" read.small_read 40 2>/dev/null)"
    [[ "$small" =~ ^[0-9]+$ ]] || small=40
    if [ "$mcur" -gt "$small" ]; then deny "$1" "$2" "$t" "$bud" session; fi
  fi
  mpend="$mpend$mcur"$'\n'; msum=$(( msum + mcur )); mcur=""
}
union() {  # $1 start $2 end; prints "<distinct lines seen if added><TAB><merged ranges seen so far>"
  # the ledger plus this call's pending ranges; the path is compared exactly, whatever it contains
  # Intervals are sorted and merged, never enumerated, so a huge entry costs nothing.
  set -o pipefail   # runs in the caller's command substitution: a failed read of the ledger is a state error
  local src="$reads"; [ -e "$src" ] || src=/dev/null
  A="$akey" P="$rec_path" PEND="$pending" awk '
    function add(line,   pre, rest, r) {
      pre = ENVIRON["A"] " " ENVIRON["P"] " "
      if (substr(line, 1, length(pre)) != pre) return
      rest = substr(line, length(pre) + 1)
      if (split(rest, r, " ") != 2 || r[1] !~ /^[0-9]+$/ || r[2] !~ /^[0-9]+$/) return
      print r[1] + 0, r[2] + 0
    }
    BEGIN { m = split(ENVIRON["PEND"], pl, "\n"); for (k = 1; k <= m; k++) if (pl[k] != "") add(pl[k]) }
    { add($0) }' "$src" 2>/dev/null | sort -n -k1,1 | awk -v ns="$1" -v ne="$2" '
    { if (cnt > 0 && $1 <= me + 1) { if ($2 > me) me = $2 }
      else { cnt++; ms[cnt] = $1; me = $2 }
      mend[cnt] = me }
    END { str = ""; c = 0
      for (i = 1; i <= cnt; i++) { str = str (str == "" ? "" : ",") ms[i] "-" mend[i]; c += mend[i] - ms[i] + 1 }
      add = ne - ns + 1
      for (i = 1; i <= cnt; i++) { lo = (ms[i] > ns ? ms[i] : ns); hi = (mend[i] < ne ? mend[i] : ne); if (hi >= lo) add -= hi - lo + 1 }
      printf "%d\t%s\n", c + add, str }'
}

deny() {  # $1 file  $2 line count  $3 lines seen so far and $4 budget, for a budget denial
  local n
  # a gate that cannot name the file or the count must not deny: it saves tokens, so it fails open
  if [ -z "$1" ] || ! [[ "$2" =~ ^[0-9]+$ ]]; then echo "  -> gate error, allowed" >> "$log"; exit 0; fi
  n=0; local l
  if [ -f "$counter" ]; then while IFS= read -r l; do [ "$l" = "$akey $1" ] && n=$((n+1)); done <"$counter"; fi
  n=$((n+1))
  echo "$akey $1" >> "$counter"
  if [ "$n" -gt 3 ]; then record; echo "  -> loop guard, allowed" >> "$log"; exit 0; fi
  echo "  -> DENIED ($n/3)" >> "$log"
  if [ -n "$5" ]; then
    echo "Read gate: this session has already loaded $3 lines in the main thread (budget $4), and $1 ($2 lines) would add more. Dispatch a subagent for this task rather than reading it yourself." >&2
  elif [ -n "$4" ]; then
    echo "Read gate: $1 has $2 lines. This read would take you past the line budget: seen ${3:-none}, budget $4." >&2
  else
    echo "Read gate: $1 has $2 lines (limit $LIMIT). Do not load it whole." >&2
  fi
  # the ask command is named only when the config allows it and claude is installed
  need_repo
  use_ask=1
  [ "$(bash "$here/lib/config.sh" "$repo" read.ask true 2>/dev/null)" = "false" ] && use_ask=0
  command -v claude >/dev/null 2>&1 || use_ask=0
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
    is_image "$f" && exit 0   # images and PDFs are rendered by Read, not loaded as lines
    lines_of "$f"; n="$LN"
    [ "$n" -gt "$LIMIT" ] || [ "$akey" = main ] || exit 0   # small or missing files are not counted, except in the main thread's session budget
    if ! [[ "${off:-1}" =~ ^[0-9]+$ && "${lim:-1}" =~ ^[0-9]+$ ]]; then echo "  -> parse error, allowed" >> "$log"; exit 0; fi
    start="${off:-1}"; [ "$start" -ge 1 ] || start=1
    if [ -n "$lim" ]; then end=$(( start + lim - 1 )); else end="$n"; fi
    [ "$end" -le "$n" ] || end="$n"
    [ "$start" -le "$end" ] || exit 0   # nothing delivered
    case "$f" in /*) rec_path="$f" ;; *) rec_path="$base/$f" ;; esac
    [ "$akey" != main ] || mcur=$(( end - start + 1 ))
    if [ "$n" -le "$LIMIT" ]; then m_judge "$f" "$n"; record; exit 0; fi
    rec_start="$start"; rec_end="$end"
    # a read that covers the whole file is a whole-file read, however it is spelled
    if [ "$start" -le 1 ] && [ "$end" -ge "$n" ]; then deny "$f" "$n"; fi
    file_budget
    if ! res="$(union "$start" "$end")"; then echo "  -> state error, allowed" >> "$log"; exit 0; fi
    if [ "${res%%$'\t'*}" -gt "$budget" ]; then deny "$f" "$n" "${res#*$'\t'}" "$budget"; fi
    m_judge "$f" "$n"
    record
    ;;
  Bash)
    # redirects to /dev/null or another fd hide nothing; a redirect to a file still passes.
    # Removed in one left-to-right pass per pattern, as sed s///g did; [[:space:]] is spelled out
    # because a bash regex, unlike sed, would also match across a newline.
    strip_matches() {  # $1 regex: removes every match from cmd, only where $2 occurs
      case "$cmd" in *"$2"*) ;; *) return 0 ;; esac
      local rest="$cmd" out="" m
      while [[ "$rest" =~ $1 ]]; do m="${BASH_REMATCH[0]}"; out="$out${rest%%"$m"*}"; rest="${rest#*"$m"}"; done
      cmd="$out$rest"
    }
    sp=$' \t\r\v\f'
    strip_matches "[0-9&]*>>?[$sp]*/dev/null" "/dev/null"
    strip_matches "[0-9]>&[0-9]" ">&"
    cmd="${cmd%"${cmd##*[!$'\n']}"}"   # the old $(...) dropped trailing newlines
    # A command that holds none of the words this gate judges (cat, less, more, head, tail, sed,
    # awk) needs no splitting: only those can be the command word of a segment. Quotes and
    # backslashes are dropped first because xargs below unquotes a command word (c"a"t is cat).
    bare="${cmd//\'/}"; bare="${bare//\"/}"; bare="${bare//\\/}"
    case "$bare" in *cat*|*less*|*more*|*head*|*tail*|*sed*|*awk*) ;; *) exit 0 ;; esac
    whole_file() {  # $1 file: denied when large; never recorded
      is_image "$1" && return 0
      rec_start=""; lines_of "$1"
      if [ "$akey" = main ] && [ "$LN" -ge 1 ]; then mcur="$LN"; fi
      [ "$LN" -gt "$LIMIT" ] && deny "$1" "$LN"
      m_judge "$1" "$LN"
      return 0
    }
    range_of() {  # $1 file, $2 mode (abs, head or tail), $3 and $4 the numbers; counts the lines a read delivers
      local f="$1" n s e budget res
      is_image "$f" && return 0
      lines_of "$f"; n="$LN"
      [ "$n" -gt "$LIMIT" ] || [ "$akey" = main ] || return 0   # small or missing files are not counted, except in the main thread's session budget
      case "$2" in
        head) s=1; e="$3" ;;
        tail) s=$(( n - $3 + 1 )); e="$n" ;;
        *) s="$3"; e="$4"; [ "$e" = '$' ] && e="$n" ;;
      esac
      [ "$s" -ge 1 ] || s=1
      [ "$e" -ge "$s" ] || e="$s"   # sed prints line A for a range that runs backwards
      [ "$e" -le "$n" ] || e="$n"
      [ "$s" -le "$e" ] || return 0   # nothing delivered
      [ "$akey" != main ] || mcur=$(( e - s + 1 ))
      if [ "$n" -le "$LIMIT" ]; then m_judge "$f" "$n"; return 0; fi
      case "$f" in /*) rec_path="$f" ;; *) rec_path="$base/$f" ;; esac; rec_start="$s"; rec_end="$e"
      if [ "$s" -le 1 ] && [ "$e" -ge "$n" ]; then deny "$f" "$n"; fi
      file_budget
      if ! res="$(union "$s" "$e")"; then echo "  -> state error, allowed" >> "$log"; exit 0; fi
      if [ "${res%%$'\t'*}" -gt "$budget" ]; then deny "$f" "$n" "${res#*$'\t'}" "$budget"; fi
      m_judge "$f" "$n"
      pending="$pending$akey $rec_path $s $e"$'\n'; rec_start=""
    }
    awk_one='^[[:space:]]*NR[[:space:]]*>=[[:space:]]*([0-9]+)[[:space:]]*&&[[:space:]]*NR[[:space:]]*<=[[:space:]]*([0-9]+)[[:space:]]*$'
    awk_two='^[[:space:]]*NR[[:space:]]*==[[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*NR[[:space:]]*==[[:space:]]*([0-9]+)[[:space:]]*$'
    sed_quit='^[[:space:]]*([0-9]+)[[:space:]]*q[[:space:]]*$'
    sed_print='^[[:space:]]*([0-9]+)[[:space:]]*(,[[:space:]]*([0-9]+|\$))?[[:space:]]*p[[:space:]]*$'
    # split into simple commands at ; & && || and newlines outside quotes, in order, tracking cd;
    # each line is "<1 if the simple command has a pipe or redirect outside quotes, else 0><TAB><command>"
    # Quote state carries across lines; heredoc bodies are skipped; an unterminated quote or heredoc
    # ends the output with ERR and the gate fails open. A newline inside quotes is kept as \001.
    segs="$(awk '
      function emit() { print fl "\t" out; out = ""; fl = 0 }
      BEGIN { q = ""; out = ""; fl = 0; hd = ""; dash = 0 }
      { line = $0
        if (hd != "") { t = line; if (dash) sub(/^\t+/, "", t); if (t == hd) hd = ""; next }
        len = length(line)
        for (i = 1; i <= len; i++) { c = substr(line, i, 1); d = substr(line, i + 1, 1)
          if (q != "") { if (c == q) q = ""; out = out c }
          else if (c == "\"" || c == "\x27") { q = c; out = out c }
          else if (c == ";") emit()
          else if (c == "&" && d == ">") { fl = 1; out = out "&>"; i++ }
          else if (c == "&") emit()
          else if (c == ">" && d == "&") { fl = 1; out = out ">&"; i++ }
          else if (c == "|" && d == "|") { emit(); i++ }
          else if (c == "<" && d == "<" && substr(line, i + 2, 1) != "<") {
            j = i + 2; dash = 0
            if (substr(line, j, 1) == "-") { dash = 1; j++ }
            while (substr(line, j, 1) == " ") j++
            Q = substr(line, j, 1); w = ""
            if (Q == "\"" || Q == "\x27") { j++; while (j <= len && substr(line, j, 1) != Q) { w = w substr(line, j, 1); j++ }; j++ }
            else while (j <= len && substr(line, j, 1) !~ /[ \t;&|<>()]/) { w = w substr(line, j, 1); j++ }
            if (w != "") hd = w
            out = out substr(line, i, j - i); i = j - 1 }
          else { if (c == "|" || c == ">") fl = 1; out = out c } }
        if (q != "") out = out "\001"; else emit() }
      END { if (q != "" || hd != "") print "ERR" }' <<<"$cmd")"
    if [ "${segs##*$'\n'}" = ERR ]; then echo "  -> parse error, allowed" >> "$log"; exit 0; fi
    while IFS=$'\t' read -r flag seg; do
      # a pipe or redirect makes only its own command targeted, not the whole chain
      [ "$flag" = 1 ] && continue
      seg="${seg//$'\001'/$'\n'}"
      if [[ "$seg" =~ ^[[:space:]]*cd[[:space:]]+([^[:space:]]+) ]]; then
        t="${BASH_REMATCH[1]}"; case "$t" in /*) base="$t" ;; *) base="$base/$t" ;; esac
        continue
      fi
      w=()
      while IFS= read -r word; do w+=("$word"); done < <(xargs printf '%s\n' <<<"$seg" 2>/dev/null)  # xargs splits like a shell, so quoted paths stay whole
      [ "${#w[@]}" -gt 0 ] || continue
      files=(); count=""; plus=0; bytes=0; follow=0; i=1
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
              --lines=*) count="${x#--lines=}" ;;
              --lines) count="${w[$i]}"; i=$(( i + 1 )) ;;
              --bytes=*) bytes=1 ;;
              --bytes) bytes=1; i=$(( i + 1 )) ;;
              -f|-F|--follow*) follow=1 ;;
              -c|-c*) bytes=1 ;;
              -[0-9]*) count="${x#-}" ;;
              -*) ;;
              *) files+=("$x") ;;
            esac
          done
          if [ "$bytes" = 1 ] || [ "$follow" = 1 ]; then continue; fi
          [ -n "$count" ] || count=10   # no count: head and tail deliver 10 lines
          case "$count" in +*) plus=1; count="${count#+}" ;; esac
          if [ -n "$count" ] && ! [[ "$count" =~ ^[0-9]+$ ]]; then echo "  -> parse error, allowed" >> "$log"; continue; fi
          for x in "${files[@]}"; do
            if [ "$plus" = 0 ] && [ "$count" -gt "$LIMIT" ]; then whole_file "$x"
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
          ranges=(); bad=""; others=0; quit_at=""
          sl=""; for sx in "${scripts[@]}"; do sl="$sl$sx"$'\n'; done; sl="${sl//;/$'\n'}"   # one command per line
          while IFS= read -r one; do
            [ -n "${one//[[:space:]]/}" ] || continue
            if [[ "$one" =~ $sed_print ]]; then
              b="${BASH_REMATCH[3]}"; [ -n "${BASH_REMATCH[2]}" ] || b="${BASH_REMATCH[1]}"
              ranges+=("${BASH_REMATCH[1]} $b"); others=1
            elif [[ "$one" =~ $sed_quit ]]; then
              if [ -z "$quit_at" ] || [ "${BASH_REMATCH[1]}" -lt "$quit_at" ]; then quit_at="${BASH_REMATCH[1]}"; fi
            elif [[ "$one" == */* ]]; then bad=regex; others=1
            else bad=parse; others=1; fi
          done <<<"$sl"
          if [ "$quiet" = 0 ]; then   # prints every line, up to a quit command if that is all there is
            if [ "$others" = 0 ] && [ -n "$quit_at" ] && [ "$quit_at" -ge 1 ]; then ranges=("1 $quit_at")
            else for x in "${files[@]}"; do whole_file "$x"; done; continue; fi
          fi
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
    done <<<"$segs"
    record   # every read of the command passed: count them all
    ;;
esac
exit 0
