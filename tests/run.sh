#!/bin/bash
# Unit tests for the hooks: fake payloads in, exit codes out. Under 30 seconds.
# Independent groups run in parallel subshells; output is replayed in group order, so the
# log, the final count and the exit code are deterministic.
cd "$(dirname "$0")/.." || exit 1
export HARNESS_STATE_TMP=1
ROOT="$PWD"
TROOT="$(mktemp -d)"; export TMPDIR="$TROOT"   # every fixture lives under one root, removed at the end
SBX="$(mktemp -d)"; git -C "$SBX" init -q       # cwd for payloads without a cwd: hooks log here, never into this repo
fail=0; n=0
check() {  # name, expected exit, hook, payload
  n=$((n+1)); local got
  echo "$4" | (cd "$SBX" && bash "$3") >/dev/null 2>&1; got=$?
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (expected $2, got $got)"; fail=1; fi
}
tmp="$(mktemp -d)"; git -C "$tmp" init -q; printf 'line %d\n' $(seq 1 400) > "$tmp/big.txt"; echo hi > "$tmp/small.txt"
R="$ROOT/hooks/read-gate.sh"; C="$ROOT/hooks/commit-gate.sh"; unset IONIAN_HOME
fresh="$(mktemp -d)"
repo_with() {  # extra harness.toml text, then files to stage; prints the repo dir
  local d; d="$(mktemp -d "$fresh/r.XXXXXX")"; git -C "$d" init -q
  printf '[test]\nunit = "true"\ndir = "tests"\n[security]\nsecrets = "true"\n%b' "$1" > "$d/harness.toml"; shift
  for f in "$@"; do mkdir -p "$d/$(dirname "$f")"; echo x > "$d/$f"; git -C "$d" add "$f"; done
  echo "$d"
}
commit() { echo "{\"tool_name\":\"Bash\",\"cwd\":\"$1\",\"tool_input\":{\"command\":\"git commit -m '$2'\"}}"; }
bash_cmd() { jq -nc --arg c "$1" --arg d "${2:-$tmp}" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }
ok() {  # name, condition result (0 = pass)
  n=$((n+1)); if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
mcheck() {  # name, message, wanted substring, unwanted substring
  n=$((n+1)); if [[ "$2" == *"$3"* && "$2" != *"$4"* ]]; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi
}
g_read1() {
check "read: small file passes"            0 $R "{\"tool_name\":\"Read\",\"session_id\":\"t1\",\"cwd\":\"$tmp\",\"tool_input\":{\"file_path\":\"$tmp/small.txt\"}}"
check "read: big file denied"              2 $R "{\"tool_name\":\"Read\",\"session_id\":\"t1\",\"cwd\":\"$tmp\",\"tool_input\":{\"file_path\":\"$tmp/big.txt\"}}"
check "read: offset/limit passes"          0 $R "{\"tool_name\":\"Read\",\"session_id\":\"t1\",\"tool_input\":{\"file_path\":\"$tmp/big.txt\",\"offset\":10,\"limit\":3}}"
check "read: reader agent exempt"          0 $R "{\"tool_name\":\"Read\",\"agent_type\":\"reader\",\"session_id\":\"t1\",\"tool_input\":{\"file_path\":\"$tmp/big.txt\"}}"
for a in spec-paraphrase spec-critic spec-readiness; do
  check "read: $a agent exempt"          0 $R "{\"tool_name\":\"Read\",\"agent_type\":\"$a\",\"session_id\":\"t4\",\"tool_input\":{\"file_path\":\"$tmp/big.txt\"}}"
  [ -f "agents/$a.md" ] && echo "ok   read: $a has an agent file" || { echo "FAIL read: $a has no agent file"; fail=1; }
done
# plugin agents arrive namespaced (verified 2026-11-03 with claude --plugin-dir)
for a in reader spec-paraphrase spec-critic spec-readiness; do
  check "read: ionian-harness:$a exempt" 0 $R "{\"tool_name\":\"Read\",\"agent_type\":\"ionian-harness:$a\",\"session_id\":\"t6-$a\",\"tool_input\":{\"file_path\":\"$tmp/big.txt\"}}"
done
check "read: other plugin's reader denied" 2 $R "{\"tool_name\":\"Read\",\"agent_type\":\"other-plugin:reader\",\"session_id\":\"t7\",\"tool_input\":{\"file_path\":\"$tmp/big.txt\"}}"
check "read: other agent still denied"     2 $R "{\"tool_name\":\"Read\",\"agent_type\":\"coder\",\"session_id\":\"t5\",\"tool_input\":{\"file_path\":\"$tmp/big.txt\"}}"
check "bash: cat big denied"               2 $R "{\"tool_name\":\"Bash\",\"session_id\":\"t2\",\"tool_input\":{\"command\":\"cat $tmp/big.txt\"}}"
check "bash: cat | head passes"            0 $R "{\"tool_name\":\"Bash\",\"session_id\":\"t2\",\"tool_input\":{\"command\":\"cat $tmp/big.txt | head -3\"}}"
check "bash: head -n passes"               0 $R "{\"tool_name\":\"Bash\",\"session_id\":\"t2\",\"tool_input\":{\"command\":\"head -n 5 $tmp/big.txt\"}}"
check "bash: head without -n counts 10 lines" 0 $R "{\"tool_name\":\"Bash\",\"session_id\":\"t2\",\"tool_input\":{\"command\":\"head $tmp/big.txt\"}}"
bcmd() { jq -nc --arg c "$1" --arg d "$tmp" --argjson n "$n" '{tool_name:"Bash",session_id:("tb"+($ARGS.named.n|tostring)+"-'"$$"'"),cwd:$d,tool_input:{command:$c}}'; }
check "bash: cat big 2>/dev/null denied"   2 $R "$(bcmd "cat $tmp/big.txt 2>/dev/null")"
check "bash: cat big > file passes"        0 $R "$(bcmd "cat $tmp/big.txt > $tmp/out.txt")"
cp "$tmp/big.txt" "$tmp/big file.txt"; cp "$tmp/small.txt" "$tmp/small file.txt"
check "bash: cat quoted big path denied"   2 $R "$(bcmd "cat \"$tmp/big file.txt\"")"
check "bash: cat quoted small path passes" 0 $R "$(bcmd "cat '$tmp/small file.txt'")"
mkdir "$tmp/sub"; cp "$tmp/big.txt" "$tmp/sub/deep.txt"
check "bash: cd sub && cat big denied"     2 $R "$(bcmd "cd sub && cat deep.txt")"
check "bash: true; cat big denied"         2 $R "$(bcmd "true; cat $tmp/big.txt")"
check "bash: cd dir && cat small passes"   0 $R "$(bcmd "cd $tmp && cat small.txt")"
check "bash: chain with a pipe passes"     0 $R "$(bcmd "cd $tmp && cat big.txt | head -3")"
check "bash: echo with ; in quotes passes" 0 $R "$(bcmd "echo \"x; cat $tmp/big.txt\"")"
check "bash: head -n 5000 big denied"      2 $R "$(bcmd "head -n 5000 $tmp/big.txt")"
check "bash: tail -n 400 big denied"       2 $R "$(bcmd "tail -n 400 $tmp/big.txt")"
check "bash: head -n 350 big passes"       0 $R "$(bcmd "head -n 350 $tmp/big.txt")"
check "bash: head -3 big passes"           0 $R "$(bcmd "head -3 $tmp/big.txt")"
check "bash: tail -n5 big passes"          0 $R "$(bcmd "tail -n5 $tmp/big.txt")"
check "bash: head -n 5000 small passes"    0 $R "$(bcmd "head -n 5000 $tmp/small.txt")"
check "bash: pipe elsewhere, cat big denied" 2 $R "$(bcmd "cat $tmp/big.txt; ls | wc -l")"
}
g_read2() {
# images and PDFs are rendered by Read, not loaded as lines; newline bytes in them are no line count
printf '\x89PNG\r\n\x1a\n%.0s' $(seq 1 400) > "$tmp/shot.png"; cp "$tmp/big.txt" "$tmp/doc.pdf"
check "read: big png passes"               0 $R "{\"tool_name\":\"Read\",\"session_id\":\"t8\",\"tool_input\":{\"file_path\":\"$tmp/shot.png\"}}"
check "read: big pdf passes"               0 $R "{\"tool_name\":\"Read\",\"session_id\":\"t8\",\"tool_input\":{\"file_path\":\"$tmp/doc.pdf\"}}"
# a subagent cannot dispatch the reader, so its denial must name a step it can take
msg_has() {  # name, agent_type, expected substring, unwanted substring
  n=$((n+1)); local m
  m="$(echo "{\"tool_name\":\"Read\",\"agent_type\":\"$2\",\"session_id\":\"t9-$2\",\"tool_input\":{\"file_path\":\"$tmp/big.txt\"}}" | (cd "$SBX" && bash $R) 2>&1 >/dev/null)"
  if [[ "$m" == *"$3"* && "$m" != *"$4"* ]]; then echo "ok   $1"; else echo "FAIL $1: $m"; fail=1; fi
}
# F1.11-F1.13: every denial names the ask.sh command; fallback text without claude or with ask = false
NOCLAUDE="$(tr : '\n' <<<"$PATH" | grep -vxF "$(dirname "$(command -v claude)")" | paste -sd: -)"
askrepo="$(mktemp -d)"; git -C "$askrepo" init -q; printf '[read]\nask = "false"\n' > "$askrepo/harness.toml"
dmsg() {  # session, agent_id, agent_type, cwd, PATH ; prints the denial stderr, run in a throwaway repo
  jq -nc --arg s "$1" --arg i "$2" --arg t "$3" --arg c "$4" --arg f "$tmp/big.txt" \
    '{tool_name:"Read",session_id:$s,agent_id:$i,agent_type:$t,cwd:$c,tool_input:{file_path:$f}}' \
    | (cd "$tmp" && PATH="$5" bash "$R" 2>&1 >/dev/null)
}
mcheck() {  # name, message, wanted substring, unwanted substring
  n=$((n+1)); if [[ "$2" == *"$3"* && "$2" != *"$4"* ]]; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi
}
ASK="bash $ROOT/lib/ask.sh \""
m="$(dmsg f11a "" "" "$tmp" "$PATH")"
mcheck "read: main denial names the ask command and file" "$m" "$ASK" "@@none@@"
mcheck "read: main denial names the denied file"          "$m" "$tmp/big.txt" "reader"
mcheck "read: main denial says offset and limit on ranges" "$m" "offset and limit" "reader"
m="$(dmsg f11b "agent-1" "general-purpose" "$tmp" "$PATH")"
mcheck "read: subagent denial names the ask command"       "$m" "$ASK" "reader"
mcheck "read: subagent denial names the denied file"       "$m" "$tmp/big.txt" "reader"
m="$(dmsg f12a "" "" "$tmp" "$NOCLAUDE")"
mcheck "read: no claude on PATH, main gets fallback"       "$m" "Grep (or grep -n)" "ask.sh"
m="$(dmsg f12b "agent-1" "general-purpose" "$tmp" "$NOCLAUDE")"
mcheck "read: no claude on PATH, subagent gets fallback"   "$m" "Grep (or grep -n)" "ask.sh"
m="$(dmsg f12c "" "" "$askrepo" "$PATH")"
mcheck "read: ask = false, main gets fallback"             "$m" "Grep (or grep -n)" "ask.sh"
m="$(dmsg f12d "agent-1" "general-purpose" "$askrepo" "$PATH")"
mcheck "read: ask = false, subagent gets fallback"         "$m" "Grep (or grep -n)" "ask.sh"
n=$((n+1)); if grep -q "agent=main tool=Read session=f11a " "$tmp/.git/harness/gate.log"; then echo "ok   read: log line carries session"; else echo "FAIL read: log line carries session"; fail=1; fi
# read: documented gap: outside a git repo the denial counter lives in /tmp/harness (shared by every non-git cwd); kept because a per-user path would need a decision on cleanup
ng="$(mktemp -d)"; gapsess="gapsess-$$-$RANDOM"   # a session id of its own: two suites at once never meet in /tmp/harness
(cd "$ng" && echo "{\"tool_name\":\"Read\",\"session_id\":\"$gapsess\",\"tool_input\":{\"file_path\":\"$tmp/big.txt\"}}" | bash "$R" >/dev/null 2>&1)
if [ -f "/tmp/harness/denials-$gapsess" ]; then echo "ok   read: documented gap: state outside git lives in /tmp/harness"; else echo "FAIL read: documented gap: state outside git lives in /tmp/harness"; fail=1; fi
n=$((n+1)); rm -rf "$ng"
rm -f "/tmp/harness/denials-$gapsess" "/tmp/harness/reads-$gapsess"   # only this test's own files; the directory and gate.log are shared, so they stay
for i in 1 2 3; do echo "{\"tool_name\":\"Read\",\"session_id\":\"t3\",\"tool_input\":{\"file_path\":\"$tmp/big.txt\"}}" | (cd "$SBX" && bash $R) >/dev/null 2>&1; done
check "read: loop guard, 4th passes"       0 $R "{\"tool_name\":\"Read\",\"session_id\":\"t3\",\"tool_input\":{\"file_path\":\"$tmp/big.txt\"}}"
}
g_failopen() {
# the read gate saves tokens, so its own errors must never deny a call
  local pr cmd d rc
  pr="$(mktemp -d)"; mkdir -p "$pr/hooks" "$pr/lib"; cp "$ROOT"/lib/*.sh "$pr/lib/"; cp "$R" "$pr/hooks/read-gate.sh"
  cmd="$(jq -r '.hooks.PreToolUse[] | select(.matcher=="Read|Bash") | .hooks[0].command' "$ROOT/hooks/hooks.json")"
  d="$(mktemp -d)"; git -C "$d" init -q; printf 'line %d\n' $(seq 1 400) > "$d/big.txt"
  runwrap() { jq -nc --arg c "$d" --arg f "$d/big.txt" '{tool_name:"Read",session_id:"fo1",cwd:$c,tool_input:{file_path:$f}}' | (cd "$d" && CLAUDE_PLUGIN_ROOT="$pr" bash -c "$cmd" >/dev/null 2>&1); }
  runwrap; rc=$?; n=$((n+1)); if [ "$rc" = 2 ]; then echo "ok   failopen: intact gate through hooks.json still denies"; else echo "FAIL failopen: intact gate through hooks.json (got $rc)"; fail=1; fi
  echo 'if [ then' >> "$pr/hooks/read-gate.sh"
  runwrap; rc=$?; n=$((n+1)); if [ "$rc" = 0 ]; then echo "ok   failopen: gate with a syntax error is skipped"; else echo "FAIL failopen: gate with a syntax error (got $rc)"; fail=1; fi
  n=$((n+1)); if [ "$(jq -r '.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[0].command' "$ROOT/hooks/hooks.json")" = 'bash ${CLAUDE_PLUGIN_ROOT}/hooks/commit-gate.sh' ]; then echo "ok   failopen: commit gate entry unchanged"; else echo "FAIL failopen: commit gate entry changed"; fail=1; fi
  # a payload that reaches deny with an empty path (limit -1 makes the empty file count as large) is allowed and logged
  jq -nc --arg c "$d" '{tool_name:"Bash",session_id:"fo2",cwd:$c,tool_input:{command:"cat \"\""}}' | (cd "$d" && HARNESS_READ_LIMIT=-1 bash "$R" >/dev/null 2>&1); rc=$?
  n=$((n+1)); if [ "$rc" = 0 ] && grep -q 'gate error, allowed' "$d/.git/harness/gate.log"; then echo "ok   failopen: empty path reaching deny is allowed and logged"; else echo "FAIL failopen: empty path reaching deny (got $rc)"; fail=1; fi
  rm -rf "$pr" "$d"
}
g_budget() {
# read-gate-v2 F2 part a: per-agent line budget for Read ranges; own throwaway repos, state never lands here
  local br br2 br3 st f rc err
  br="$(mktemp -d)"; git -C "$br" init -q; br2="$(mktemp -d)"; git -C "$br2" init -q; br3="$(mktemp -d)"; git -C "$br3" init -q
  for d in "$br" "$br2" "$br3"; do printf 'line %d\n' $(seq 1 400) > "$d/big.txt"; done
  printf '[read]\nfile_budget = "100"\n' > "$br2/harness.toml"; printf '[read]\nask = "false"\n' > "$br3/harness.toml"
  printf 'line %d\n' $(seq 1 200) > "$br/mid.txt"; printf '\x89PNG\r\n\x1a\n%.0s' $(seq 1 400) > "$br/shot.png"
  st="$br/.git/harness"; f="$br/big.txt"
  rd() {  # repo session agent_id agent_type offset limit file ; sets rc and err
    err="$(jq -nc --arg s "$2" --arg i "$3" --arg t "$4" --arg o "$5" --arg l "$6" --arg f "$7" --arg c "$1" \
      '{tool_name:"Read",session_id:$s,agent_id:$i,agent_type:$t,cwd:$c,
        tool_input:({file_path:$f}+(if $o!="" then {offset:($o|tonumber)} else {} end)+(if $l!="" then {limit:($l|tonumber)} else {} end))}' \
      | (cd "$1" && bash "$R" 2>&1 >/dev/null)

)"; rc=$?
  }
  rdc() {  # name, expected exit, then rd arguments
    local nm="$1" want="$2"; shift 2; rd "$@"; n=$((n+1))
    if [ "$rc" = "$want" ]; then echo "ok   $nm"; else echo "FAIL $nm (expected $want, got $rc)"; fail=1; fi
  }
  has() { grep -qxF "$2" "$st/$1" 2>/dev/null; }
  rdc "F2.1 read 1-300 passes"                     0 "$br" s1 "" "" 1 300 "$f"
  rdc "F2.2 read 200-299 passes, all seen"         0 "$br" s1 "" "" 200 100 "$f"
  rdc "F2.2 union stays 300: 301-350 still fits"   0 "$br" s1 "" "" 301 50 "$f"
  rdc "F2.3 read: 1-300 then 301-360 denied"       0 "$br" s3 "" "" 1 300 "$f"
  rdc "F2.3 read: 301-360 would make 360"          2 "$br" s3 "" "" 301 60 "$f"
  mcheck "F2.3 read: denial says seen 1-300"       "$err" "seen 1-300" "loop"
  mcheck "F2.3 read: denial says budget 350"       "$err" "budget 350" "loop"
  mcheck "F2.3 read: denial names lib/ask.sh"      "$err" "lib/ask.sh" "loop"
  ok "F2.3 read: denied read records nothing" "$([ "$(wc -l < "$st/reads-s3" | tr -d ' ')" = 1 ]; echo $?)"
  rdc "F2.3 ranges: 1-3"                           0 "$br" s3b "" "" 1 3 "$f"
  rdc "F2.3 ranges: 9-9"                           0 "$br" s3b "" "" 9 1 "$f"
  rdc "F2.3 ranges: 20-400 denied"                 2 "$br" s3b "" "" 20 381 "$f"
  mcheck "F2.3 ranges joined with commas"          "$err" "seen 1-3,9-9" "loop"
  rdc "F2.3 fallback: 1-300"                       0 "$br3" s3c "" "" 1 300 "$br3/big.txt"
  rdc "F2.3 fallback: 301-360 denied"              2 "$br3" s3c "" "" 301 60 "$br3/big.txt"
  mcheck "F2.3 fallback keeps seen and budget"     "$err" "seen 1-300" "ask.sh"
  mcheck "F2.3 fallback has budget and Grep text"  "$err" "budget 350" "ask.sh"
  mcheck "F2.3 fallback names the Grep text"       "$err" "Grep (or grep -n)" "ask.sh"
  rdc "F2.4 offset 391 alone passes"               0 "$br" s4 "" "" 391 "" "$f"
  ok "F2.4 offset 391 records 391 400" "$(has reads-s4 "main $f 391 400"; echo $?)"
  rdc "F2.4 limit 5 alone passes"                  0 "$br" s4 "" "" "" 5 "$f"
  ok "F2.4 limit 5 records 1 5" "$(has reads-s4 "main $f 1 5"; echo $?)"
  rdc "F2.4 offset 10 limit 3 passes"              0 "$br" s4 "" "" 10 3 "$f"
  ok "F2.4 offset 10 limit 3 records 10 12" "$(has reads-s4 "main $f 10 12"; echo $?)"
  rdc "F2.5 read: offset 1 limit 400 is whole"     2 "$br" s5 "" "" 1 400 "$f"
  rdc "F2.5 read: limit past the end is whole"     2 "$br" s5 "" "" 1 1000 "$f"
  rdc "F2.5 read: offset 1 alone is whole"         2 "$br" s5 "" "" 1 "" "$f"
  ok "F2.5 read: whole-file denials record nothing" "$([ ! -e "$st/reads-s5" ]; echo $?)"
  rdc "F2.7 budget denial 1 of 3"                  0 "$br" s7 "" "" 1 300 "$f"
  rdc "F2.7 denied 1"                              2 "$br" s7 "" "" 301 60 "$f"
  rdc "F2.7 denied 2"                              2 "$br" s7 "" "" 301 60 "$f"
  rdc "F2.7 whole-file denial shares the counter"  2 "$br" s7 "" "" "" "" "$f"
  rdc "F2.7 4th read passes"                       0 "$br" s7 "" "" 301 60 "$f"
  ok "F2.7 loop guard pass is recorded" "$(has reads-s7 "main $f 301 360"; echo $?)"
  ok "F2.7 log notes the loop guard" "$(grep -q 'loop guard' "$st/gate.log"; echo $?)"
  rdc "F2.8 reader whole read passes"              0 "$br" s8 "" reader "" "" "$f"
  rdc "F2.8 spec-critic range passes"              0 "$br" s8 "" ionian-harness:spec-critic 1 400 "$f"
  ok "F2.8 exempt agents record nothing" "$([ ! -e "$st/reads-s8" ]; echo $?)"
  mkdir -p "$st"; : > "$st/reads-s9"; chmod 000 "$st/reads-s9"
  rdc "F2.9 unreadable state fails open"           0 "$br" s9 "" "" 1 300 "$f"
  ok "F2.9 log says state error" "$(grep -q 'state error' "$st/gate.log"; echo $?)"
  rdc "F2.9 whole-file denial unaffected"          2 "$br" s9 "" "" "" "" "$f"
  chmod 600 "$st/reads-s9"
  rdc "F2.10 file_budget 100 denies 1-150"         2 "$br2" s10 "" "" 1 150 "$br2/big.txt"
  rdc "F2.10 file_budget 100 allows 1-100"         0 "$br2" s10b "" "" 1 100 "$br2/big.txt"
  rdc "F2.11 whole read of 200-line file passes"   0 "$br" s11 "" "" "" "" "$br/mid.txt"
  rdc "F2.11 range of 200-line file passes"        0 "$br" s11 "" "" 1 200 "$br/mid.txt"
  ok "F2.11 not-large files are not recorded" "$([ ! -e "$st/reads-s11" ]; echo $?)"
  rdc "images are not counted"                     0 "$br" s12 "" "" 1 5 "$br/shot.png"
  ok "images record nothing" "$([ ! -e "$st/reads-s12" ]; echo $?)"
  rdc "F2.19 read 1-350 passes"                    0 "$br" s19 "" "" 1 350 "$f"
  rdc "F2.19 then 351-400 denied"                  2 "$br" s19 "" "" 351 50 "$f"
  rdc "F2.20 agent a1 reads 1-300"                 0 "$br" s20 a1 general-purpose 1 300 "$f"
  rdc "F2.20 agent b1 reads 1-300"                 0 "$br" s20 b1 general-purpose 1 300 "$f"
  ok "F2.20 state has both agents" "$(has reads-s20 "a1 $f 1 300" && has reads-s20 "b1 $f 1 300"; echo $?)"
  for i in 1 2 3; do rdc "F2.21 a1 whole read denied $i" 2 "$br" s21 a1 general-purpose "" "" "$f"; done
  rdc "F2.21 b1 first whole read denied"           2 "$br" s21 b1 general-purpose "" "" "$f"
  rdc "F2.21 a1 4th passes"                        0 "$br" s21 a1 general-purpose "" "" "$f"
  # the gate never denies what it cannot measure: small files, missing files, plain commands
  rdc "small file whole read passes"               0 "$br" s22 "" "" "" "" "$br/mid.txt"
  rdc "missing file read passes"                   0 "$br" s22 "" "" "" "" "$br/nope.txt"
  rdc "missing file with offset passes"            0 "$br" s22 "" "" 5 10 "$br/nope.txt"
  rdc "relative path is resolved against cwd"      0 "$br" s23 "" "" 1 300 big.txt
  ok "relative path is recorded absolute" "$(has reads-s23 "main $br/big.txt 1 300"; echo $?)"
  rc=0; jq -nc --arg c "$br" '{tool_name:"Bash",session_id:"s25",cwd:$c,tool_input:{command:"ls"}}' | (cd "$br" && bash "$R" >/dev/null 2>&1) || rc=$?
  ok "bash ls passes" "$rc"
  rm -rf "$br" "$br2" "$br3"
}
bb_setup() {
# read-gate-v2 F2 part b: Bash read forms count into the same per-agent ledger as Read
# three groups share this setup so they run in parallel; every group is its own subshell, so plain variables are fine
  br="$(mktemp -d)"; git -C "$br" init -q; br2="$(mktemp -d)"; git -C "$br2" init -q
  printf 'line %d\n' $(seq 1 400) > "$br/big.txt"; printf 'line %d\n' $(seq 1 400) > "$br2/big.txt"
  printf '[read]\nfile_budget = "100"\n' > "$br2/harness.toml"
  printf 'line %d\n' $(seq 1 200) > "$br/mid.txt"; printf '\x89PNG\r\n\x1a\n%.0s' $(seq 1 400) > "$br/shot.png"
  mkdir "$br/sub"; printf 'line %d\n' $(seq 1 400) > "$br/sub/deep.txt"
  sp="$br/dbl  space.txt"; printf 'line %d\n' $(seq 1 400) > "$sp"
  st="$br/.git/harness"; f="$br/big.txt"
  bsh() {  # repo session agent_id agent_type command ; sets rc and err
    err="$(jq -nc --arg s "$2" --arg i "$3" --arg t "$4" --arg c "$1" --arg m "$5" \
      '{tool_name:"Bash",session_id:$s,agent_id:$i,agent_type:$t,cwd:$c,tool_input:{command:$m}}' \
      | (cd "$1" && bash "$R" 2>&1 >/dev/null))"; rc=$?
  }
  bdc() {  # name, expected exit, then repo session agent_id agent_type command
    local nm="$1" want="$2"; shift 2; bsh "$@"; n=$((n+1))
    if [ "$rc" = "$want" ]; then echo "ok   $nm"; else echo "FAIL $nm (expected $want, got $rc)"; fail=1; fi
  }
  rdo() {  # repo session offset limit file ; main-thread Read, sets rc and err
    err="$(jq -nc --arg s "$2" --arg c "$1" --arg o "$3" --arg l "$4" --arg f "$5" \
      '{tool_name:"Read",session_id:$s,cwd:$c,tool_input:({file_path:$f}+(if $o!="" then {offset:($o|tonumber)} else {} end)+(if $l!="" then {limit:($l|tonumber)} else {} end))}' \
      | (cd "$1" && bash "$R" 2>&1 >/dev/null))"; rc=$?
  }
  has() { grep -qxF "$2" "$st/$1" 2>/dev/null; }
  nrec() { if [ -e "$st/reads-$1" ]; then wc -l < "$st/reads-$1" | tr -d ' '; else echo 0; fi; }
}
g_budgetb1() {
  bb_setup
  # F2.3 shared ledger: Read and Bash count into one budget
  rdo "$br" b3 1 300 "$f"; bdc "F2.3 bash: after Read 1-300, sed 301-360 denied" 2 "$br" b3 "" "" "sed -n '301,360p' $f"
  mcheck "F2.3 bash: denial says seen 1-300"   "$err" "seen 1-300" "loop"
  mcheck "F2.3 bash: denial says budget 350"   "$err" "budget 350" "loop"
  mcheck "F2.3 bash: denial names lib/ask.sh"  "$err" "lib/ask.sh" "loop"
  bdc "F2.3 bash: seen lines cost nothing"     0 "$br" b3 "" "" "sed -n '200,299p' $f"
  bdc "F2.3 bash first, then Read denied"      0 "$br" b3b "" "" "sed -n '1,300p' $f"
  rdo "$br" b3b 301 60 "$f"; n=$((n+1)); if [ "$rc" = 2 ]; then echo "ok   F2.3 Read after bash 1-300: 301-360 denied"; else echo "FAIL F2.3 Read after bash 1-300 (got $rc)"; fail=1; fi
  mcheck "F2.3 Read after bash: seen 1-300"   "$err" "seen 1-300" "loop"
  bdc "F2.3 bash fallback ask=false"           0 "$br2" b3c "" "" "sed -n '1,100p' $br2/big.txt"
  bdc "F2.3 bash: ranges joined with commas"   0 "$br" b3d "" "" "sed -n -e '1,3p' -e '9p' $f"
  bdc "F2.3 bash: 20-400 denied"               2 "$br" b3d "" "" "sed -n '20,400p' $f"
  mcheck "F2.3 bash: seen 1-3,9-9"             "$err" "seen 1-3,9-9" "loop"
  bdc "F2.3 one sed with two ranges, 351 lines" 2 "$br" b3e "" "" "sed -n '1,200p;250,400p' $f"
  mcheck "F2.3 each print command is counted"  "$err" "seen 1-200" "loop"
  ok "F2.3 denied command records nothing" "$([ "$(nrec b3e)" = 0 ]; echo $?)"
  bdc "F2.3 && chain: second read denied"      2 "$br" b3f "" "" "sed -n '1,300p' $f && sed -n '301,360p' $f"
  ok "F2.3 && chain denial records nothing" "$([ "$(nrec b3f)" = 0 ]; echo $?)"
  bdc "F2.3 ; chain: both reads fit"           0 "$br" b3g "" "" "sed -n '1,100p' $f; head -n 50 $f"
  ok "F2.3 ; chain records both" "$(has reads-b3g "main $f 1 100" && has reads-b3g "main $f 1 50"; echo $?)"
  # F2.5 whole-file reads stay denied
  bdc "F2.5 sed -n 1,400p denied"              2 "$br" b5 "" "" "sed -n '1,400p' $f"
  bdc "F2.5 sed -n 1,\$p denied"               2 "$br" b5 "" "" "sed -n '1,\$p' $f"
  bdc "F2.5 cat denied"                        2 "$br" b5 "" "" "cat $f"
  bdc "F2.5 head -n 351 denied (over limit)"   2 "$br" b5b "" "" "head -n 351 $f"
  bdc "F2.5 tail -n +1 covers every line"      2 "$br" b5c "" "" "tail -n +1 $f"
  ok "F2.5 whole-file denials record nothing" "$([ ! -e "$st/reads-b5" ] && [ ! -e "$st/reads-b5b" ] && [ ! -e "$st/reads-b5c" ]; echo $?)"
  # F2.6 a pipe makes the segment targeted; not counted
  bdc "F2.6 sed piped to cat passes"           0 "$br" b6 "" "" "sed -n '1,300p' $f | cat"
  bdc "F2.6 awk with a > inside quotes is not a redirect" 0 "$br" b6b "" "" "awk 'NR>=5 && NR<=8' $f"
  ok "F2.6 piped sed not counted" "$([ ! -e "$st/reads-b6" ]; echo $?)"
  ok "F2.6 quoted > does not hide the awk range" "$(has reads-b6b "main $f 5 8"; echo $?)"
  bdc "F2.6 sed redirected to a file passes"   0 "$br" b6c "" "" "sed -n '1,400p' $f > $br/o.txt"
  # F2.7 loop guard shared across forms, per agent and file
  bdc "F2.7 bash denial 1"                     2 "$br" b7 "" "" "cat $f"
  bdc "F2.7 bash denial 2"                     2 "$br" b7 "" "" "sed -n '1,400p' $f"
  rdo "$br" b7 "" "" "$f"; n=$((n+1)); if [ "$rc" = 2 ]; then echo "ok   F2.7 Read denial 3 shares the counter"; else echo "FAIL F2.7 Read denial 3 (got $rc)"; fail=1; fi
  bdc "F2.7 4th read passes"                   0 "$br" b7 "" "" "sed -n '1,300p' $f"
  ok "F2.7 loop guard pass is recorded" "$(has reads-b7 "main $f 1 300"; echo $?)"
  rm -rf "$br" "$br2"
}
g_budgetb2() {
  bb_setup
  # F2.8 exempt agents
  bdc "F2.8 reader sed passes"                 0 "$br" b8 x reader "cat $f"
  bdc "F2.8 spec-critic head passes"           0 "$br" b8 x ionian-harness:spec-critic "head -n 50 $f"
  ok "F2.8 exempt bash records nothing" "$([ ! -e "$st/reads-b8" ]; echo $?)"
  # F2.9 fail open
  bdc "F2.9 unexpanded variable in sed passes" 0 "$br" b9 "" "" 'sed -n "$X" '"$f"
  ok "F2.9 log says parse error" "$(grep -q 'parse error' "$st/gate.log"; echo $?)"
  ok "F2.9 parse error records nothing" "$([ ! -e "$st/reads-b9" ]; echo $?)"
  mkdir -p "$st"; : > "$st/reads-b9s"; chmod 000 "$st/reads-b9s"
  bdc "F2.9 unreadable state, sed passes"      0 "$br" b9s "" "" "sed -n '1,300p' $f"
  ok "F2.9 bash log says state error" "$(grep -q 'state error' "$st/gate.log"; echo $?)"
  bdc "F2.9 whole-file denial unaffected"      2 "$br" b9s "" "" "cat $f"
  chmod 600 "$st/reads-b9s"
  # F2.10 configured budget
  bdc "F2.10 file_budget 100 denies head 150"  2 "$br2" b10 "" "" "head -n 150 $br2/big.txt"
  bdc "F2.10 file_budget 100 allows head 100"  0 "$br2" b10b "" "" "head -n 100 $br2/big.txt"
  # F2.11 small files
  bdc "F2.11 sed 1,200p of 200-line file"      0 "$br" b11 "" "" "sed -n '1,200p' $br/mid.txt"
  bdc "F2.11 cat of 200-line file"             0 "$br" b11 "" "" "cat $br/mid.txt"
  bdc "F2.11 missing file passes"              0 "$br" b11 "" "" "sed -n '1,200p' $br/nope.txt"
  ok "F2.11 nothing recorded" "$([ ! -e "$st/reads-b11" ]; echo $?)"
  # F2.12 to F2.18 and F2.23: the delivered range of each form
  rng() {  # name, session, command, expected "start end" list separated by ';'
    bdc "$1 passes" 0 "$br" "$2" "" "" "$3"
    local want="$4" r
    local IFS=';'; for r in $want; do ok "$1 delivers $r" "$(has "reads-$2" "main $f $r"; echo $?)"; done
  }
  rng "F2.12 sed -n '10,12p'"            b12 "sed -n '10,12p' $f" "10 12"
  rng "F2.13 sed -n 10p"                 b13 "sed -n 10p $f" "10 10"
  rng "F2.13 sed -n -e -e"               b13b "sed -n -e '1,3p' -e '9p' $f" "1 3;9 9"
  rng "F2.14 head -n 20"                 b14 "head -n 20 $f" "1 20"
  rng "F2.14 head -20"                   b14b "head -20 $f" "1 20"
  rng "F2.15 tail -n 20"                 b15 "tail -n 20 $f" "381 400"
  rng "F2.16 tail -n +395"               b16 "tail -n +395 $f" "395 400"
  rng "F2.17 awk NR>=5 && NR<=8"         b17 "awk 'NR>=5 && NR<=8' $f" "5 8"
  rng "F2.18 awk NR==5,NR==8"            b18 "awk 'NR==5,NR==8' $f" "5 8"
  rng "F2.23 sed -n '391,\$p'"           b23 "sed -n '391,\$p' $f" "391 400"
  bdc "relative path after cd passes" 0 "$br" b12r "" "" "cd sub && sed -n '1,3p' deep.txt"
  ok "cd sub records the absolute path" "$(has reads-b12r "main $br/sub/deep.txt 1 3"; echo $?)"
  # F2.19 and F2.20
  bdc "F2.19 head -n 350 passes"               0 "$br" b19 "" "" "head -n 350 $f"
  bdc "F2.19 then sed 351,400p denied"         2 "$br" b19 "" "" "sed -n '351,400p' $f"
  bdc "F2.20 agent a1 reads 1-300"             0 "$br" b20 a1 general-purpose "sed -n '1,300p' $f"
  bdc "F2.20 agent b1 reads 1-300"             0 "$br" b20 b1 general-purpose "sed -n '1,300p' $f"
  ok "F2.20 state has both agents" "$(has reads-b20 "a1 $f 1 300" && has reads-b20 "b1 $f 1 300"; echo $?)"
  for i in 1 2 3; do bdc "F2.21 a1 cat denied $i" 2 "$br" b21 a1 general-purpose "cat $f"; done
  bdc "F2.21 b1 first cat denied"              2 "$br" b21 b1 general-purpose "cat $f"
  bdc "F2.21 a1 4th passes"                    0 "$br" b21 a1 general-purpose "cat $f"
  rm -rf "$br" "$br2"
}
g_budgetb3() {
  bb_setup
  # F2.22 sed without -n prints everything
  bdc "F2.22 sed s/a/b/ is whole-file"         2 "$br" b22 "" "" "sed 's/a/b/' $f"
  bdc "F2.22 sed -i passes"                    0 "$br" b22b "" "" "sed -i 's/a/b/' $br2/big.txt"
  bdc "F2.22 sed with regex address passes"    0 "$br" b22b "" "" "sed -n '/line 5/p' $f"
  bdc "F2.22 regex address beside a range: nothing counted" 0 "$br" b22b "" "" "sed -n -e '1,300p' -e '/line 5/p' $f"
  bdc "F2.22 head -c passes"                  0 "$br" b22b "" "" "head -c 100 $f"
  bdc "F2.22 tail -c passes"                   0 "$br" b22b "" "" "tail -c 100 $f"
  bdc "F2.22 other awk program passes"         0 "$br" b22b "" "" "awk '{print}' $f"
  ok "F2.22 uncounted forms record nothing" "$([ ! -e "$st/reads-b22b" ]; echo $?)"
  # F2.24 split at ||
  bdc "F2.24 sed whole range || true"          2 "$br" b24 "" "" "sed -n '1,400p' $f || true"
  bdc "F2.24 cat || true"                      2 "$br" b24b "" "" "cat $f || true"
  bdc "F2.24 || with a pipe on the other side" 0 "$br" b24c "" "" "true || cat $f | head -3"
  bdc "F2.24 || inside quotes does not split"  0 "$br" b24d "" "" "echo 'a || cat $f'"
  # images, PDFs, plain commands
  bdc "bash cat of a big png passes"           0 "$br" b25 "" "" "cat $br/shot.png"
  bdc "bash sed range of a big png passes"     0 "$br" b25 "" "" "sed -n '1,300p' $br/shot.png"
  ok "png reads are not recorded" "$([ ! -e "$st/reads-b25" ]; echo $?)"
  bdc "bash ls passes"                         0 "$br" b26 "" "" "ls"
  bdc "bash git status passes"                 0 "$br" b26 "" "" "git status"
  # nit: a path with two spaces in a row matches exactly
  rdo "$br" b27 1 300 "$sp"; rdo "$br" b27 301 60 "$sp"
  n=$((n+1)); if [ "$rc" = 2 ]; then echo "ok   union: path with two spaces matches exactly"; else echo "FAIL union: path with two spaces matches exactly (got $rc)"; fail=1; fi
  mcheck "union: two-space path seen 1-300" "$err" "seen 1-300" "loop"
  bdc "union: two-space path via bash"         2 "$br" b27b "" "" "sed -n '1,300p' '$sp'; sed -n '301,360p' '$sp'"
  rm -rf "$br" "$br2"
}
g_budgetb4() {
  bb_setup
  # review fixes: multi-line commands, heredocs, tail/head option forms, &>, sed Nq, interval merge
  local nl=$'\n'
  rng() {  # name, session, command, expected "start end" list separated by ';'
    bdc "$1 passes" 0 "$br" "$2" "" "" "$3"
    local want="$4" r
    local IFS=';'; for r in $want; do ok "$1 delivers $r" "$(has "reads-$2" "main $f $r"; echo $?)"; done
  }
  bdc "split: heredoc body is not a command"       0 "$br" c1 "" "" "git commit -F - <<EOF${nl}cat $f${nl}EOF"
  bdc "split: <<-'EOF' heredoc body skipped"       0 "$br" c1b "" "" "git commit -F - <<-'EOF'${nl}cat $f${nl}EOF"
  bdc "split: <<\"EOF\" heredoc body skipped"      0 "$br" c1c "" "" "git commit -F - <<\"EOF\"${nl}cat $f${nl}EOF"
  bdc "split: <<-EOF with tab-indented end"        0 "$br" c1d "" "" "git commit -F - <<-EOF${nl}cat $f${nl}	EOF"
  bdc "split: command after a heredoc still judged" 2 "$br" c1e "" "" "cat <<EOF${nl}x${nl}EOF${nl}cat $f"
  bdc "split: quote spans lines"                   0 "$br" c2 "" "" "git commit -m \"title${nl}cat $f${nl}\""
  bdc "split: newline outside quotes splits"       2 "$br" c2b "" "" "ls${nl}cat $f"
  bdc "split: quote closed on line 2, then ; splits" 2 "$br" c2c "" "" "echo \"a${nl}b\"; cat $f"
  bdc "split: unterminated quote fails open"       0 "$br" c2d "" "" "echo \"abc${nl}cat $f"
  bdc "split: unterminated heredoc fails open"     0 "$br" c2e "" "" "cat <<EOF${nl}cat $f"
  bdc "tail -f passes"                             0 "$br" c3 "" "" "tail -f $f"
  bdc "tail -F passes"                             0 "$br" c3 "" "" "tail -F $f"
  bdc "tail --follow passes"                       0 "$br" c3 "" "" "tail --follow $f"
  bdc "tail -f -n 20 passes"                       0 "$br" c3 "" "" "tail -f -n 20 $f"
  ok "tail follow forms record nothing" "$([ ! -e "$st/reads-c3" ]; echo $?)"
  rng "tail --lines=20"                            c4 "tail --lines=20 $f" "381 400"
  rng "tail --lines 20"                            c4b "tail --lines 20 $f" "381 400"
  rng "head --lines=5"                             c4c "head --lines=5 $f" "1 5"
  bdc "head --bytes=100 passes"                    0 "$br" c4d "" "" "head --bytes=100 $f"
  bdc "head --bytes 100 passes"                    0 "$br" c4d "" "" "head --bytes 100 $f"
  bdc "tail --bytes=100 passes"                    0 "$br" c4d "" "" "tail --bytes=100 $f"
  ok "bytes forms record nothing" "$([ ! -e "$st/reads-c4d" ]; echo $?)"
  rng "head without a count is 10 lines"           c5 "head $f" "1 10"
  rng "tail without a count is the last 10"        c5b "tail $f" "391 400"
  bdc "cat big &> out.log passes"                  0 "$br" c6 "" "" "cat $f &> $br/out.log"
  bdc "cat big >& out.log passes"                  0 "$br" c6 "" "" "cat $f >& $br/out.log"
  bdc "cat big & still splits"                     2 "$br" c6b "" "" "cat $f & true"
  rng "sed 5q is lines 1-5"                        c7 "sed 5q $f" "1 5"
  rng "sed -e 5q is lines 1-5"                     c7b "sed -e 5q $f" "1 5"
  bdc "sed 400q is a whole-file read"              2 "$br" c7c "" "" "sed 400q $f"
  bdc "sed with another command and 5q is whole"   2 "$br" c7d "" "" "sed -e 's/a/b/' -e 5q $f"
  # union merges intervals: a huge ledger entry costs nothing
  mkdir -p "$st"; echo "main $f 1 100000000" > "$st/reads-c8"
  local t0 t1; t0=$(date +%s)
  rdo "$br" c8 301 60 "$f"
  t1=$(date +%s)
  n=$((n+1)); if [ "$rc" = 2 ]; then echo "ok   union: read after a 1-100000000 entry decided"; else echo "FAIL union: huge entry (got $rc)"; fail=1; fi
  mcheck "union: huge entry reported as seen 1-100000000" "$err" "seen 1-100000000" "loop"
  ok "union: huge entry decides in under 20 seconds" "$([ $(( t1 - t0 )) -lt 20 ]; echo $?)"
  printf 'main %s 101 200\nmain %s 1 60\nmain %s 50 100\nmain %s 300 310\n' "$f" "$f" "$f" "$f" > "$st/reads-c9"
  rdo "$br" c9 150 251 "$f"
  mcheck "union: overlapping and adjacent entries merge" "$err" "seen 1-200,300-310" "loop"
  rm -rf "$br" "$br2"
}
g_commit1() {
  tmp="$(mktemp -d)"; git -C "$tmp" init -q; printf 'line %d\n' $(seq 1 400) > "$tmp/big.txt"; echo hi > "$tmp/small.txt"
# commit gate, in a throwaway repo with its own harness.toml
printf '[test]\nunit = "true"\ndir = "tests"\n[security]\nsecrets = "true"\n' > "$tmp/harness.toml"
mkdir -p "$tmp/tests" "$tmp/src"; echo "x=1" > "$tmp/src/a.py"; git -C "$tmp" add -A
check "commit: non-commit bash ignored"    0 $C "{\"tool_name\":\"Bash\",\"cwd\":\"$tmp\",\"tool_input\":{\"command\":\"git status\"}}"
check "commit: --no-verify denied"         2 $C "{\"tool_name\":\"Bash\",\"cwd\":\"$tmp\",\"tool_input\":{\"command\":\"git commit --no-verify -m x\"}}"
# every way of spelling a commit reaches the gate; --no-verify makes "recognised" visible as exit 2
for c in 'git -c user.name=x commit --no-verify -m x' 'git --no-pager commit --no-verify -m x' \
         "bash -c 'git commit --no-verify -m x'" 'sh -c "git commit --no-verify -m x"' \
         $'cd /tmp\ngit commit --no-verify -m x' 'env A=1 git commit --no-verify -m x' \
         '(git commit --no-verify -m x)' '/usr/bin/git commit --no-verify -m x'; do
  check "commit: recognised: ${c//$'\n'/\\n}" 2 $C "$(bash_cmd "$c")"
done
for c in 'git log --grep commit' 'git status && echo commit' 'legit commit --no-verify'; do
  check "commit: not a commit: $c" 0 $C "$(bash_cmd "$c")"
done
check "commit: source without tests denied" 2 $C "{\"tool_name\":\"Bash\",\"cwd\":\"$tmp\",\"tool_input\":{\"command\":\"git commit -m 'add a'\"}}"
check "commit: [no-tests] escape passes"   0 $C "{\"tool_name\":\"Bash\",\"cwd\":\"$tmp\",\"tool_input\":{\"command\":\"git commit -m 'add a [no-tests] config only'\"}}"
echo "def test_a(): pass" > "$tmp/tests/test_a.py"; git -C "$tmp" add -A
check "commit: source plus test passes"    0 $C "{\"tool_name\":\"Bash\",\"cwd\":\"$tmp\",\"tool_input\":{\"command\":\"git commit -m 'add a with test'\"}}"
printf '[test]\nunit = "false"\n[security]\nsecrets = "true"\n' > "$tmp/harness.toml"
check "commit: red unit suite denied"      2 $C "{\"tool_name\":\"Bash\",\"cwd\":\"$tmp\",\"tool_input\":{\"command\":\"git commit -m x\"}}"
printf '[test]\nunit = "true"\n[security]\nsecrets = "false"\n' > "$tmp/harness.toml"
check "commit: failed secret scan denied"  2 $C "{\"tool_name\":\"Bash\",\"cwd\":\"$tmp\",\"tool_input\":{\"command\":\"cd $tmp && git commit -m x\"}}"
}
g_commit2() {
  tmp="$(mktemp -d)"; printf '[test]\nunit = "true"\n' > "$tmp/harness.toml"
# shell scripts under hooks/ and lib/ count as source (docs/designs/commit-gate-shell-tests.md)
d="$(repo_with "" hooks/x.sh)"
check "commit: hooks/*.sh without tests denied" 2 $C "$(commit "$d" "change x")"
commit "$d" "change x" | bash $C 2>&1 >/dev/null | grep -qF hooks/x.sh && echo "ok   commit: denial names hooks/x.sh" || { echo "FAIL commit: denial names hooks/x.sh"; fail=1; }
d="$(repo_with "" lib/y.sh)"
check "commit: lib/*.sh without tests denied" 2 $C "$(commit "$d" "change y")"
commit "$d" "change y" | bash $C 2>&1 >/dev/null | grep -qF lib/y.sh && echo "ok   commit: denial names lib/y.sh" || { echo "FAIL commit: denial names lib/y.sh"; fail=1; }
check "commit: hooks/*.sh plus test passes" 0 $C "$(commit "$(repo_with "" hooks/x.sh tests/x_test.sh)" "change x with test")"
check "commit: hooks/*.sh [no-tests] passes" 0 $C "$(commit "$(repo_with "" hooks/x.sh)" "change x [no-tests] comment only")"
check "commit: require_tests false passes"  0 $C "$(commit "$(repo_with '[gate]\nrequire_tests = "false"\n' hooks/x.sh)" "change x")"
# the gate acts only where a harness config exists: repo harness.toml or ~/Ionian/harness/<repo>.toml (IONIAN_HOME overrides ~/Ionian)
home="$(mktemp -d "$fresh/home.XXXXXX")"
d="$(repo_with "" src/a.py)"; rm "$d/harness.toml"
HOME="$home" check "commit: unconfigured repo left alone" 0 $C "$(commit "$d" "add a")"
HOME="$home" check "commit: unconfigured --no-verify left alone" 0 $C "$(bash_cmd 'git commit --no-verify -m x' "$d")"
[ ! -e "$d/.git/harness" ] && echo "ok   commit: unconfigured repo gets no .git/harness" || { echo "FAIL commit: unconfigured repo gets no .git/harness"; fail=1; }
mkdir -p "$home/Ionian/harness"; printf '[test]\nunit = "true"\n[security]\nsecrets = "true"\n' > "$home/Ionian/harness/$(basename "$d").toml"
HOME="$home" check "commit: home config gates the repo" 2 $C "$(commit "$d" "add a")"
check "config: reads section.key"          0 "$ROOT/lib/config.sh" ""
[ "$(lib/config.sh "$tmp" test.unit)" = "true" ] && echo "ok   config: value" || { echo "FAIL config: value"; fail=1; }
[ "$(lib/config.sh "$tmp" nope.key dflt)" = "dflt" ] && echo "ok   config: default" || { echo "FAIL config: default"; fail=1; }
bash lib/config.sh "$tmp" --exists && echo "ok   config: --exists with repo file" || { echo "FAIL config: --exists with repo file"; fail=1; }
HOME="$home" bash lib/config.sh "$(mktemp -d "$fresh/bare.XXXXXX")" --exists && { echo "FAIL config: --exists without any file"; fail=1; } || echo "ok   config: --exists without any file"
# IONIAN_HOME replaces ~/Ionian; the old ~/.config/harness location is no longer read
rn="$(mktemp -d "$fresh/named.XXXXXX")"; nm="$(basename "$rn")"
h2="$(mktemp -d "$fresh/home.XXXXXX")"; ih="$(mktemp -d "$fresh/ih.XXXXXX")"
mkdir -p "$h2/Ionian/harness" "$ih/harness"
printf '[test]\nunit = "fromhome"\n' > "$h2/Ionian/harness/$nm.toml"
[ "$(HOME="$h2" lib/config.sh "$rn" test.unit)" = "fromhome" ] && echo "ok   config: default ~/Ionian/harness" || { echo "FAIL config: default ~/Ionian/harness"; fail=1; }
printf '[test]\nunit = "fromihome"\n' > "$ih/harness/$nm.toml"
[ "$(HOME="$h2" IONIAN_HOME="$ih" lib/config.sh "$rn" test.unit)" = "fromihome" ] && echo "ok   config: IONIAN_HOME overrides default" || { echo "FAIL config: IONIAN_HOME overrides default"; fail=1; }
mkdir -p "$h2/x/harness"; printf '[test]\nunit = "fromtilde"\n' > "$h2/x/harness/$nm.toml"
[ "$(HOME="$h2" IONIAN_HOME='~/x' lib/config.sh "$rn" test.unit)" = "fromtilde" ] && echo "ok   config: IONIAN_HOME ~ expands against HOME" || { echo "FAIL config: IONIAN_HOME ~ expands against HOME"; fail=1; }
h3="$(mktemp -d "$fresh/home.XXXXXX")"; mkdir -p "$h3/.config/harness"
printf '[test]\nunit = "old"\n' > "$h3/.config/harness/$nm.toml"
[ -z "$(HOME="$h3" lib/config.sh "$rn" test.unit)" ] && echo "ok   config: old ~/.config/harness not read" || { echo "FAIL config: old ~/.config/harness not read"; fail=1; }
HOME="$h3" bash lib/config.sh "$rn" --exists && { echo "FAIL config: old location not counted by --exists"; fail=1; } || echo "ok   config: old location not counted by --exists"
}
g_commit3() {
  home="$(mktemp -d "$fresh/home.XXXXXX")"
# git -C <dir> commit is checked against the repo at <dir>, relative to the payload cwd
unc="$(repo_with "" src/a.py)"; rm "$unc/harness.toml"
cfgd="$(repo_with "" src/a.py)"
HOME="$home" check "commit: -C configured repo gated from unconfigured cwd" 2 $C "$(bash_cmd "git -C $cfgd commit -m x" "$unc")"
red="$(repo_with '' src/a.py)"; printf '[test]\nunit = "false"\n[security]\nsecrets = "true"\n' > "$red/harness.toml"
HOME="$home" check "commit: -C unconfigured repo left alone from red cwd" 0 $C "$(bash_cmd "git -C $unc commit -m x" "$red")"
HOME="$home" check "commit: -C relative dir resolved against cwd" 2 $C "$(bash_cmd "git -C ../$(basename "$cfgd") commit -m x" "$unc")"
HOME="$home" check "commit: -C missing dir falls back to cwd repo" 2 $C "$(bash_cmd "git -C /nonexistent/zz commit -m x" "$cfgd")"
# --no-verify and -n count only inside the arguments of the git commit itself
clean="$(repo_with "")"
check "commit: sed -n before a commit is not --no-verify" 0 $C "$(bash_cmd "sed -n 1p x && git commit -m msg" "$clean")"
check "commit: -n after commit denied"          2 $C "$(bash_cmd "git commit -n -m x" "$clean")"
check "commit: --no-verify after message denied" 2 $C "$(bash_cmd "git commit -m x --no-verify" "$clean")"
check "commit: --no-verify after quoted message denied" 2 $C "$(bash_cmd "git commit -m 'a; b' --no-verify" "$clean")"
check "commit: quoted text mentioning commit and -n is not --no-verify" 0 $C "$(bash_cmd $'python3 - <<\'EOF\'\nprint("git -C x commit; then -n")\nEOF' "$clean")"
check "commit: quoted text with -n and a space is not --no-verify" 0 $C "$(bash_cmd $'python3 - <<\'EOF\'\nprint("git -C x commit; then -n now")\nEOF' "$clean")"
check "commit: -n after a separator is not --no-verify" 0 $C "$(bash_cmd "git commit -m x; ls -n" "$clean")"
# an unparseable payload is judged like the no-jq case: denied only when it looks like a commit
check "commit: invalid JSON that looks like a commit denied" 2 $C '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"'
check "commit: invalid JSON that is no commit passes" 0 $C '{"tool_name":"Bash","tool_input":{"command":"git status"'
# git commit-tree makes commits without any hook, so it is denied; other git commands stay out of the gate
check "commit: commit-tree denied" 2 $C "$(bash_cmd 'git commit-tree HEAD^{tree} -m x' "$clean")"
check "commit: commit-tree with -C denied" 2 $C "$(bash_cmd 'git -C . commit-tree abc123 -p HEAD' "$clean")"
for c in 'git log --format=%T' 'git write-tree' 'git rev-parse HEAD^{tree}' 'git show --format=%T -s HEAD'; do
  check "commit: not commit-tree: $c" 0 $C "$(bash_cmd "$c" "$clean")"
done
}
g_commit4() {
  clean="$(repo_with "")"
# heredoc bodies fed to a non-shell command are data; fed to a shell (or when unsure) they are still checked
srcrepo="$(repo_with "" src/a.py)"
check "commit: python heredoc mentioning commit-tree passes" 0 $C "$(bash_cmd $'python3 - <<\'EOF\'\ns = "`git commit-tree` denied"\nEOF' "$clean")"
check "commit: python heredoc mentioning git commit -m skips the suite rule" 0 $C "$(bash_cmd $'python3 - <<\'EOF\'\nprint("git commit -m x")\nEOF' "$srcrepo")"
check "commit: python heredoc mentioning git commit --no-verify passes" 0 $C "$(bash_cmd $'python3 - <<\'EOF\'\nprint("git commit --no-verify -m x")\nEOF' "$clean")"
check "commit: bash heredoc with commit-tree denied" 2 $C "$(bash_cmd $'bash <<EOF\ngit commit-tree HEAD^{tree}\nEOF' "$clean")"
check "commit: sh heredoc with git commit --no-verify denied" 2 $C "$(bash_cmd $'sh <<\'X\'\ngit commit --no-verify -m x\nX' "$clean")"
check "commit: bash -s heredoc with commit-tree denied" 2 $C "$(bash_cmd $'bash -s <<"X"\ngit commit-tree HEAD^{tree}\nX' "$clean")"
check "commit: env bash heredoc with commit-tree denied" 2 $C "$(bash_cmd $'env A=1 bash <<EOF\ngit commit-tree HEAD^{tree}\nEOF' "$clean")"
check "commit: bash 2>&1 heredoc with commit-tree denied" 2 $C "$(bash_cmd $'bash 2>&1 <<EOF\ngit commit-tree HEAD^{tree}\nEOF' "$clean")"
check "commit: <<- python heredoc passes" 0 $C "$(bash_cmd $'python3 - <<-EOF\n\tgit commit-tree x\n\tEOF' "$clean")"
check "commit: <<- bash heredoc with commit-tree denied" 2 $C "$(bash_cmd $'bash <<-EOF\n\tgit commit-tree x\n\tEOF' "$clean")"
check "commit: commit after a cat heredoc is still gated" 2 $C "$(bash_cmd $'cat <<EOF > a.txt\ngit commit-tree x\nEOF\ngit commit -m x' "$srcrepo")"
check "commit: cat heredoc then clean commit passes" 0 $C "$(bash_cmd $'cat <<EOF > a.txt\ngit commit-tree x\nEOF\ngit commit -m x' "$clean")"
check "commit: two heredocs, shell second, denied" 2 $C "$(bash_cmd $'cat <<A; bash <<B\nhello\nA\ngit commit-tree x\nB' "$clean")"
check "commit: two heredocs on one line, both data, pass" 0 $C "$(bash_cmd $'cat <<A <<B\ngit commit-tree x\nA\ngit commit-tree y\nB' "$clean")"
check "commit: heredoc without terminator is still checked" 2 $C "$(bash_cmd $'cat <<EOF\ngit commit-tree x' "$clean")"
check "commit: heredoc into variable-built command is still checked" 2 $C "$(bash_cmd $'$sh <<EOF\ngit commit-tree x\nEOF' "$clean")"
check "commit: [no-tests] in a heredoc message still counts" 0 $C "$(bash_cmd $'git commit -F - <<EOF\nchange [no-tests] docs\nEOF' "$srcrepo")"
# a shell reached through the rest of the marker line (pipe, chain) keeps the body checked
check "commit: cat heredoc piped to bash denied" 2 $C "$(bash_cmd $'cat <<EOF | bash\ngit commit --no-verify -m x\nEOF' "$clean")"
check "commit: cat heredoc piped to sh -s denied" 2 $C "$(bash_cmd $'cat <<EOF | sh -s\ngit commit-tree x\nEOF' "$clean")"
check "commit: cat heredoc to file then bash file denied" 2 $C "$(bash_cmd $'cat <<EOF > run.sh && bash run.sh\ngit commit-tree x\nEOF' "$clean")"
check "commit: cat heredoc to notes.md passes" 0 $C "$(bash_cmd $'cat <<EOF > notes.md\ngit commit-tree x\nEOF' "$clean")"
check "commit: python heredoc printing commit-tree passes" 0 $C "$(bash_cmd $'python3 - <<EOF\nprint("git commit-tree x")\nEOF' "$clean")"
}
g_secret() {
# live secret scan: the real gitleaks binary against staged content (skipped when it is not installed)
if command -v gitleaks >/dev/null 2>&1; then
  live="$(repo_with '' src/a.py tests/a_test.sh)"
  printf '[test]\nunit = "true"\ndir = "tests"\n' > "$live/harness.toml"   # no [security]: the default scan command runs
  # built at runtime, never a literal; finite input, because git hooks run with SIGPIPE ignored and tr on /dev/urandom never ends
  fake="ghp_$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 36)"
  echo "token = $fake" > "$live/src/leak.txt"; git -C "$live" add src/leak.txt
  check "secret: staged token denied (live gitleaks)" 2 $C "$(commit "$live" "add leak")"
  msg="$(commit "$live" "add leak" | bash $C 2>&1 >/dev/null)"
  [[ "$msg" == *"Remove the secret"* && "$msg" == *"git restore --staged"* && "$msg" == *"commit again"* ]] && echo "ok   secret: denial says remove, unstage, commit again" || { echo "FAIL secret: denial says remove, unstage, commit again"; fail=1; }
  [[ "$msg" != *"$fake"* && "$msg" != *"no-verify"* && "$msg" != *"no-tests"* ]] && echo "ok   secret: denial leaks no token and names no escape hatch" || { echo "FAIL secret: denial leaks no token and names no escape hatch"; fail=1; }
  n=$((n+2))
  git -C "$live" rm -q -f --cached src/leak.txt; rm "$live/src/leak.txt"
  check "secret: clean staged change passes (live gitleaks)" 0 $C "$(commit "$live" "clean change")"
  echo "token = $fake" > "$live/src/unstaged.txt"
  check "secret: unstaged-only secret does not block (staged scan)" 0 $C "$(commit "$live" "clean change")"
else
  echo "skip secret: live gitleaks checks (gitleaks not installed)"
fi
}
# ask.sh: fake claude first on PATH, throwaway git repo so gate.log never lands in this repo
A="$ROOT/lib/ask.sh"
ask_setup() {  # own throwaway repo with a fake claude dir, big.txt and two.txt
  ar="$(mktemp -d)"; git -C "$ar" init -q; fk="$ar/fake"; mkdir "$fk"
  printf 'line %d\n' $(seq 1 400) > "$ar/big.txt"; printf 'alpha\nbeta\n' > "$ar/two.txt"
}
fakecl() { printf '#!/bin/bash\n%s\n' "$1" > "$fk/claude"; chmod +x "$fk/claude"; }
askrun() {  # args to ask.sh; sets aout, aerr, arc; runs inside the throwaway repo
  aout="$(cd "$ar" && PATH="$fk:$PATH" bash "$A" "$@" 2>"$ar/err" </dev/null)"; arc=$?; aerr="$(cat "$ar/err")"
}
g_ask1() {
  ask_setup
fakecl 'cat'
askrun "where is line 200?" big.txt
[ "$arc" = 0 ] && [[ "$aout" == *"where is line 200?"* ]] && [[ "$aout" == *"<file path=\"$ar/big.txt\">"* ]] \
  && printf '%s\n' "$aout" | grep -qx "$(printf '200\tline 200')" && [ "$(printf '%s\n' "$aout" | grep -c "^[0-9]*	line ")" = 400 ]; ok "ask: numbered lines, tag with absolute path, question (F1.1)" $?
askrun "q" big.txt two.txt
[ "$arc" = 0 ] && [ "$(printf '%s\n' "$aout" | grep -c '^<file path=')" = 2 ] \
  && [ "$(printf '%s\n' "$aout" | grep '^<file path=' | head -1)" = "<file path=\"$ar/big.txt\">" ] \
  && [ "$(printf '%s\n' "$aout" | grep '^<file path=' | tail -1)" = "<file path=\"$ar/two.txt\">" ]; ok "ask: two files in argument order (F1.2)" $?
askrun;                  [ "$arc" = 64 ] && [ "$(printf '%s\n' "$aerr" | wc -l | tr -d ' ')" = 1 ] && [[ "$aerr" == *usage* ]]; ok "ask: no arguments exits 64 with usage (F1.3)" $?
askrun "q";              [ "$arc" = 64 ]; ok "ask: question without file exits 64 (F1.3)" $?
askrun "" big.txt;       [ "$arc" = 64 ]; ok "ask: empty question exits 64 (F1.3)" $?
askrun "q" missing.txt;  [ "$arc" = 65 ] && [[ "$aerr" == *missing.txt* ]]; ok "ask: missing file exits 65 naming it (F1.4)" $?
mkdir "$ar/adir"
askrun "q" adir;         [ "$arc" = 65 ]; ok "ask: directory exits 65 (F1.4)" $?
printf 'a\0b\n' > "$ar/nul.dat"; echo x > "$ar/shot.png"
fakecl 'touch "'"$ar"'/called"'
askrun "q" two.txt nul.dat; [ "$arc" = 66 ] && [[ "$aerr" == *nul.dat* ]] && [ ! -e "$ar/called" ]; ok "ask: NUL byte exits 66, no claude call (F1.5)" $?
askrun "q" shot.png two.txt; [ "$arc" = 66 ] && [[ "$aerr" == *shot.png* ]] && [ ! -e "$ar/called" ]; ok "ask: image extension exits 66, no claude call (F1.5)" $?
askrun "q" nul.dat missing.txt; [ "$arc" = 66 ]; ok "ask: first failing file in order decides (F1.5)" $?
askrun "q" shot.png missing.txt; [ "$arc" = 66 ] && [ ! -e "$ar/called" ]; ok "ask: first failure decides, later files and claude untouched (F1.5)" $?
fakecl 'cat'
aout="$(cd "$ar" && HARNESS_ASK_MAX_BYTES=1000 PATH="$fk:$PATH" bash "$A" "q" big.txt 2>"$ar/err")"; arc=$?; aerr="$(cat "$ar/err")"
[ "$arc" = 67 ] && [[ "$aerr" == *1000* ]] && [[ "$aerr" == *Grep* ]]; ok "ask: payload over the cap exits 67 naming cap and Grep (F1.6)" $?
nc="$ar/nocl"; mkdir "$nc"; for t in bash git perl awk tr cmp wc date mktemp rm mkdir cat dirname basename sed grep head tail ls kill sleep; do p="$(command -v $t)"; [ -n "$p" ] && ln -s "$p" "$nc/$t"; done
aout="$(cd "$ar" && PATH="$nc" "$nc/bash" "$A" "q" big.txt 2>"$ar/err")"; arc=$?; aerr="$(cat "$ar/err")"
[ "$arc" = 68 ] && [[ "$aerr" == *claude* ]]; ok "ask: claude not on PATH exits 68 (F1.7)" $?
fakecl 'echo "API error"; exit 1'
askrun "q" big.txt; [ "$arc" = 69 ] && [ -z "$aout" ] && [ "$(printf '%s\n' "$aerr" | wc -l | tr -d ' ')" = 1 ]; ok "ask: failing call exits 69, stdout empty, one stderr line (F1.8)" $?
  rm -rf "$ar"
}
g_ask2() {
  ask_setup
fakecl 'echo $$ > "'"$ar"'/pid"; sleep 121 & echo $! > "'"$ar"'/cpid"; sleep 120'
t0=$SECONDS
aout="$(cd "$ar" && HARNESS_ASK_TIMEOUT=1 PATH="$fk:$PATH" bash "$A" "q" big.txt 2>"$ar/err")"; arc=$?; aerr="$(cat "$ar/err")"
dt=$((SECONDS-t0)); sleep 0.3
alive=0; for f in pid cpid; do kill -0 "$(cat "$ar/$f")" 2>/dev/null && alive=1; done
[ "$arc" = 70 ] && [[ "$aerr" == *timed\ out* ]] && [ "$dt" -le 20 ] && [ "$alive" = 0 ] && [ -z "$aout" ]; ok "ask: timeout exits 70 within 20 s, claude and child killed (F1.9)" $?
rm -f "$ar/pid" "$ar/cpid"
  rm -rf "$ar"
}
g_ask3() {
  ask_setup
fakecl 'cat >/dev/null; echo ok'
rm -rf "$ar/.git/harness"
unset CLAUDE_CODE_SESSION_ID; askrun "q" big.txt two.txt
ll="$(tail -1 "$ar/.git/harness/gate.log")"
[ "$arc" = 0 ] && [[ "$ll" =~ ^[0-9:]{8}\ agent=unknown\ tool=ask\ session=unknown\ files=2\ bytes=[0-9]+\ exit=0\ seconds=[0-9]+$ ]]; ok "ask: gate.log line, session unknown without env (F1.10)" $?
aout="$(cd "$ar" && CLAUDE_CODE_SESSION_ID=sess-9 PATH="$fk:$PATH" bash "$A" "q" missing.txt 2>/dev/null)"
ll="$(tail -1 "$ar/.git/harness/gate.log")"
[[ "$ll" == *"tool=ask session=sess-9 files=1 bytes=0 exit=65 "* ]]; ok "ask: failing run is logged with session id and exit (F1.10)" $?
aout="$(cd "$ar" && CLAUDE_SESSION_ID=old-name PATH="$fk:$PATH" bash "$A" "q" missing.txt 2>/dev/null)"
ll="$(tail -1 "$ar/.git/harness/gate.log")"
[[ "$ll" == *"tool=ask session=unknown "* ]]; ok "ask: CLAUDE_SESSION_ID alone is ignored, session unknown" $?
fakecl 'printf "%s\n" "$@" > "'"$ar"'/argv"; env > "'"$ar"'/env"; pwd > "'"$ar"'/pwd"; ls -A | wc -l > "'"$ar"'/cwdfiles"; cat >/dev/null; echo ok'
askrun "q" two.txt
av="$ar/argv"; has() { grep -qxF -- "$1" "$av"; }
pair() { awk -v a="$1" -v b="$2" 'prev==a && $0==b {f=1} {prev=$0} END{exit !f}' "$av"; }
[ "$arc" = 0 ] && has -p && pair --model haiku && pair --tools "" && pair --setting-sources "" && has --no-session-persistence \
  && has --strict-mcp-config && has --disable-slash-commands && has --system-prompt && pair --output-format text; ok "ask: headless call flags (F1.14)" $?
HARNESS_ASK_MODEL=sonnet askrun "q" two.txt; pair --model sonnet; ok "ask: HARNESS_ASK_MODEL overrides the model (F1.14)" $?
grep -qx 'CLAUDE_CODE_DISABLE_AUTO_MEMORY=1' "$ar/env" && grep -qx 'CLAUDE_CODE_DISABLE_CLAUDE_MDS=1' "$ar/env"; ok "ask: env disables auto memory and CLAUDE.md files (F1.14)" $?
cwd="$(cat "$ar/pwd")"; [ "$(tr -d ' ' < "$ar/cwdfiles")" = 0 ] && [ ! -e "$cwd" ] && [ "$cwd" != "$ar" ]; ok "ask: runs from an empty temp dir removed on exit (F1.14)" $?
grep -qF 'L<start>-L<end>' "$av" && grep -qF 'at most 25 bullets' "$av"; ok "ask: system prompt names the line range form and the 25 bullet cap" $?
# review fixes: odd file names, interrupt, session sanitizing
printf 'eq\n' > "$ar/a=b"; printf 'dash\n' > "$ar/-x.txt"; fakecl 'cat'
askrun "q" 'a=b' '-x.txt'
[ "$arc" = 0 ] && printf '%s\n' "$aout" | grep -qx "$(printf '1\teq')" && printf '%s\n' "$aout" | grep -qx "$(printf '1\tdash')" \
  && [[ "$aout" == *"<file path=\"$ar/a=b\">"* ]] && [[ "$aout" == *"<file path=\"$ar/-x.txt\">"* ]]; ok "ask: file names a=b and -x.txt arrive numbered (F1.1)" $?
fakecl 'echo $$ > "'"$ar"'/pid"; sleep 30 & echo $! > "'"$ar"'/cpid"; wait'
rm -f "$ar/pid" "$ar/cpid"
( cd "$ar" && PATH="$fk:$PATH" exec bash "$A" "q" big.txt >/dev/null 2>&1 </dev/null ) & ap=$!
for _ in $(seq 1 50); do [ -s "$ar/pid" ] && [ -s "$ar/cpid" ] && break; sleep 0.05; done
pids="$(cat "$ar/pid" "$ar/cpid" 2>/dev/null)"; kill -TERM "$ap" 2>/dev/null
wait "$ap"; arc=$?; sleep 0.2; alive=0; for p in $pids; do kill -0 "$p" 2>/dev/null && alive=1; done
[ "$arc" = 143 ] && [ "$alive" = 0 ] && [ -n "$pids" ]; ok "ask: TERM kills claude and its child, exits 143" $?
fakecl 'cat >/dev/null; echo ok'
sid="$(printf 'ab\nx=y')"
aout="$(cd "$ar" && CLAUDE_CODE_SESSION_ID="$sid" PATH="$fk:$PATH" bash "$A" "q" two.txt 2>/dev/null)"
ll="$(tail -1 "$ar/.git/harness/gate.log")"
[[ "$ll" == *"tool=ask session=ab_x_y files=1 "* ]] && [ "$(grep -c 'tool=ask session=ab_x_y' "$ar/.git/harness/gate.log")" = 1 ]; ok "ask: session id in gate.log is sanitized" $?
  rm -rf "$ar"
}
g_agents() {  # coordinator-hands-off F1, F4, F5: agent files and skill texts
  fm() {  # file key: the frontmatter value of key
    awk -v k="$2" 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1 && index($0, k ": ")==1 {print substr($0, length(k)+3)}' "$1"
  }
  body() { awk 'c>=2 {print} $0=="---" {c++}' "$1"; }
  has_all() {  # name, file, phrases...: one ok line per phrase
    local nm="$1" f="$2" p; shift 2
    for p in "$@"; do grep -qF -- "$p" "$f"; ok "$nm: contains $p" $?; done
  }
  local a f
  for a in coder reviewer drafter; do
    f="agents/$a.md"
    [ "$(fm "$f" name)" = "$a" ]; ok "agents/$a: name (F1)" $?
    [ "$(fm "$f" model)" = "sonnet" ]; ok "agents/$a: model sonnet (F1)" $?
    [ -n "$(fm "$f" description)" ]; ok "agents/$a: description non-empty (F1)" $?
    [[ "$(fm "$f" description)" == *"Dispatch when"* ]]; ok "agents/$a: description has Dispatch when (F1.4)" $?
    body "$f" | grep -qF 'skills/'; [ $? = 1 ] && [ -s "$f" ]; ok "agents/$a: body never mentions skills/ (F1.8)" $?
  done
  [ "$(fm agents/coder.md tools)" = "Read, Edit, Write, Bash, Grep, Glob" ]; ok "agents/coder: tools exact (F1.1)" $?
  [ "$(fm agents/reviewer.md tools)" = "Read, Grep, Glob, Bash" ]; ok "agents/reviewer: tools exact (F1.2)" $?
  [ "$(fm agents/drafter.md tools)" = "Read, Write, Edit, Grep, Glob" ]; ok "agents/drafter: tools exact (F1.3)" $?
  [[ "$(fm agents/coder.md description)" == *"Dispatch when"*"behaviour change or fix"*"brief"* ]]; ok "agents/coder: Dispatch when a behaviour change or fix with a brief (F1.4)" $?
  [[ "$(fm agents/reviewer.md description)" == *"Dispatch when"*"finished commit"* ]]; ok "agents/reviewer: Dispatch when a finished commit (F1.4)" $?
  [[ "$(fm agents/drafter.md description)" == *"Dispatch when"*"spec to write or revise"* ]]; ok "agents/drafter: Dispatch when a spec to write or revise (F1.4)" $?
  has_all "agents/coder (F1.5)" agents/coder.md 'test first' 'STATUS: DONE' 'RED:' 'GREEN:' 'one commit per item' 'dependency manifests' 'follow the denial' 'ask.sh' 'BLOCKED'
  has_all "agents/reviewer (F1.6)" agents/reviewer.md 'read-only' 'file:line' 'no findings' 'prove the behaviour' 'smallest change' 'reuse what exists' 'surface nobody asked for' 'input handling' 'secrets' 'injection' 'auth' 'personal data in fixtures'
  has_all "agents/drafter (F1.7)" agents/drafter.md '## Success criteria' 'Testability:' '[NEEDS CLARIFICATION' 'could not place' 'verbatim' 'Status: approved'
  grep -qF 'ionian-harness:coder' skills/tdd/SKILL.md; ok "skills/tdd: points to ionian-harness:coder (F1.9)" $?
  [ "$(wc -l < skills/tdd/SKILL.md)" -le 25 ]; ok "skills/tdd: short pointer (F1.9)" $?
  [ ! -e skills/spec-draft/template.md ]; ok "skills/spec-draft/template.md is removed (F1.9)" $?
  has_all "skills/spec-draft (F4)" skills/spec-draft/SKILL.md 'at most five' 'Why it matters:' 'problem with evidence' 'every user requirement' 'every decision' 'rejected alternatives' 'assumptions' 'out of scope' 'ionian-harness:drafter' 'could not place' 'every requirement in the brief' 'spec-review' 'If the drafter cannot be dispatched, tell the user and stop.'
  ! grep -qE 'template\.md|You are the drafter|Copy ' skills/spec-draft/SKILL.md; ok "skills/spec-draft: no instruction to write the spec on the main thread (F4.4)" $?
  has_all "skills/spec-review (F5)" skills/spec-review/SKILL.md 'ionian-harness:drafter' 'fix list' 'Status: reviewed' 'Status: approved' 'verbatim' 'never into a reviewer dispatch' 'If the drafter cannot be dispatched, tell the user and stop.' 'findings 4, fixed 3, rejected 1'
  ! grep -qP '\x{2013}|\x{2014}' agents/coder.md agents/reviewer.md agents/drafter.md skills/*/SKILL.md 2>/dev/null; ok "agents and skills: no em or en dashes" $?
}
g_fast() {  # fast paths of the read gate: commands it does not judge, awkward payloads, non-JSON
  local fr p nasty
  fr="$(mktemp -d "$fresh/f.XXXXXX")"; git -C "$fr" init -q
  rg() { (cd "$fr" && bash "$R") >/dev/null 2>&1; }   # the hook runs in $fr, so anything it ran by mistake would leave a file there
  p="$(jq -nc --arg d "$fr" '{tool_name:"Bash",session_id:"fast1",cwd:$d,tool_input:{command:"git status && ls -la"}}')"
  echo "$p" | rg; ok "read: command with no judged word exits 0" $?
  grep -q 'agent=main tool=Bash session=fast1 git status && ls -la$' "$fr/.git/harness/gate.log"; ok "read: command with no judged word still writes its gate.log line" $?
  # newlines, double and single quotes, $( ), backticks: parsed as data, never run
  nasty="$(cat <<'EOF'
echo "a b" 'it'"'"'s' $(touch ran1) `touch ran2`
ls
EOF
)"
  p="$(jq -nc --arg d "$fr" --arg c "$nasty" '{tool_name:"Bash",session_id:"fast2",cwd:$d,tool_input:{command:$c}}')"
  echo "$p" | rg; ok "read: awkward command text parses and exits 0" $?
  [ ! -e "$fr/ran1" ] && [ ! -e "$fr/ran2" ]; ok "read: awkward command text is never executed" $?
  grep -q 'session=fast2 echo "a b" ' "$fr/.git/harness/gate.log"; ok "read: awkward command text is logged" $?
  p="$(jq -nc --arg d "$fr" --arg c "$nasty"$'\ncat '"$tmp/big.txt" '{tool_name:"Bash",session_id:"fast3",cwd:$d,tool_input:{command:$c}}')"
  echo "$p" | rg; [ $? = 2 ] && [ ! -e "$fr/ran1" ]; ok "read: judged word beside awkward text still denies, nothing runs" $?
  # a judged word that only appears once quotes or a /dev/null redirect are removed is still judged
  local k=0 c
  for c in "c''at $tmp/big.txt" "\"ca\"t $tmp/big.txt" "ca\\t $tmp/big.txt" "ca>/dev/nullt $tmp/big.txt" "ca2>&1t $tmp/big.txt"; do
    k=$((k+1))   # a session of its own each, so the loop guard of three never lets one through
    p="$(jq -nc --arg d "$fr" --arg c "$c" --arg s "fast4-$k" '{tool_name:"Bash",session_id:$s,cwd:$d,tool_input:{command:$c}}')"
    echo "$p" | rg; [ $? = 2 ]; ok "read: disguised cat denied: $c" $?
  done
  # commit gate early exit: no `commit` in the payload leaves no trace; a JSON escape that spells it is still gated
  local cr; cr="$(repo_with '')"
  echo "$(bash_cmd "git status" "$cr")" | (cd "$SBX" && bash "$C") >/dev/null 2>&1; ok "commit: command without commit exits 0" $?
  [ ! -e "$cr/.git/harness/gate.log" ]; ok "commit: command without commit writes nothing" $?
  # the command is "git commit --no-verify" with the c of commit written as a JSON unicode escape (backslash, u, 0063);
  # printf, not echo: the macOS bash 3.2 echo would turn the escape into c before the hook sees it
  local bs=$'\x5c'
  printf '%s\n' '{"tool_name":"Bash","cwd":"'"$cr"'","tool_input":{"command":"git '"${bs}"'u0063ommit --no-verify -m x"}}' | (cd "$SBX" && bash "$C") >/dev/null 2>&1; [ $? = 2 ]; ok "commit: commit spelled with a unicode escape still gated" $?
  check "commit: plain commit --no-verify still denied"       2 $C '{"tool_name":"Bash","cwd":"'"$cr"'","tool_input":{"command":"git commit --no-verify -m x"}}'
  echo 'this is not json {' | rg; ok "read: non-JSON payload fails open" $?
}
run_group() {  # name: run the group in a subshell, output and counters to files
  ( n=0; fail=0; "$1"; echo "$n $fail" > "$OUT/$1.rc" ) > "$OUT/$1.out" 2>&1 &
}
OUT="$TROOT/out"; mkdir "$OUT"
groups="g_read1 g_read2 g_failopen g_budget g_budgetb1 g_budgetb2 g_budgetb3 g_budgetb4 g_commit1 g_commit2 g_commit3 g_commit4 g_secret g_ask1 g_ask2 g_ask3 g_fast"
groups="$groups g_agents"   # coordinator-hands-off group, own line
for g in $groups; do run_group $g; done
wait
total=0
for g in $groups; do
  cat "$OUT/$g.out"
  if [ -s "$OUT/$g.rc" ]; then read -r gn gf < "$OUT/$g.rc"; total=$((total+gn)); [ "$gf" = 0 ] || fail=1
  else echo "FAIL group $g did not finish"; fail=1; fi
done
rm -rf "$TROOT"
echo "$total checks"; exit $fail
