#!/bin/bash
# Unit tests for the hooks: fake payloads in, exit codes out. Under 30 seconds.
cd "$(dirname "$0")/.." || exit 1
export HARNESS_STATE_TMP=1
fail=0; n=0
check() {  # name, expected exit, hook, payload
  n=$((n+1)); local got
  echo "$4" | bash "$3" >/dev/null 2>&1; got=$?
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (expected $2, got $got)"; fail=1; fi
}
tmp="$(mktemp -d)"; git -C "$tmp" init -q; printf 'line %d\n' $(seq 1 400) > "$tmp/big.txt"; echo hi > "$tmp/small.txt"
R="hooks/read-gate.sh"; C="hooks/commit-gate.sh"
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
check "bash: head without -n denied"       2 $R "{\"tool_name\":\"Bash\",\"session_id\":\"t2\",\"tool_input\":{\"command\":\"head $tmp/big.txt\"}}"
for i in 1 2 3; do echo "{\"tool_name\":\"Read\",\"session_id\":\"t3\",\"tool_input\":{\"file_path\":\"$tmp/big.txt\"}}" | bash $R >/dev/null 2>&1; done
check "read: loop guard, 4th passes"       0 $R "{\"tool_name\":\"Read\",\"session_id\":\"t3\",\"tool_input\":{\"file_path\":\"$tmp/big.txt\"}}"
# commit gate, in a throwaway repo with its own harness.toml
printf '[test]\nunit = "true"\ndir = "tests"\n[security]\nsecrets = "true"\n' > "$tmp/harness.toml"
mkdir -p "$tmp/tests" "$tmp/src"; echo "x=1" > "$tmp/src/a.py"; git -C "$tmp" add -A
check "commit: non-commit bash ignored"    0 $C "{\"tool_name\":\"Bash\",\"cwd\":\"$tmp\",\"tool_input\":{\"command\":\"git status\"}}"
check "commit: --no-verify denied"         2 $C "{\"tool_name\":\"Bash\",\"cwd\":\"$tmp\",\"tool_input\":{\"command\":\"git commit --no-verify -m x\"}}"
# every way of spelling a commit reaches the gate; --no-verify makes "recognised" visible as exit 2
bash_cmd() { jq -nc --arg c "$1" --arg d "${2:-$tmp}" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }
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
# shell scripts under hooks/ and lib/ count as source (docs/designs/commit-gate-shell-tests.md)
fresh="$(mktemp -d)"
repo_with() {  # extra harness.toml text, then files to stage; prints the repo dir
  local d; d="$(mktemp -d "$fresh/r.XXXXXX")"; git -C "$d" init -q
  printf '[test]\nunit = "true"\ndir = "tests"\n[security]\nsecrets = "true"\n%b' "$1" > "$d/harness.toml"; shift
  for f in "$@"; do mkdir -p "$d/$(dirname "$f")"; echo x > "$d/$f"; git -C "$d" add "$f"; done
  echo "$d"
}
commit() { echo "{\"tool_name\":\"Bash\",\"cwd\":\"$1\",\"tool_input\":{\"command\":\"git commit -m '$2'\"}}"; }
d="$(repo_with "" hooks/x.sh)"
check "commit: hooks/*.sh without tests denied" 2 $C "$(commit "$d" "change x")"
commit "$d" "change x" | bash $C 2>&1 >/dev/null | grep -qF hooks/x.sh && echo "ok   commit: denial names hooks/x.sh" || { echo "FAIL commit: denial names hooks/x.sh"; fail=1; }
d="$(repo_with "" lib/y.sh)"
check "commit: lib/*.sh without tests denied" 2 $C "$(commit "$d" "change y")"
commit "$d" "change y" | bash $C 2>&1 >/dev/null | grep -qF lib/y.sh && echo "ok   commit: denial names lib/y.sh" || { echo "FAIL commit: denial names lib/y.sh"; fail=1; }
check "commit: hooks/*.sh plus test passes" 0 $C "$(commit "$(repo_with "" hooks/x.sh tests/x_test.sh)" "change x with test")"
check "commit: hooks/*.sh [no-tests] passes" 0 $C "$(commit "$(repo_with "" hooks/x.sh)" "change x [no-tests] comment only")"
check "commit: require_tests false passes"  0 $C "$(commit "$(repo_with '[gate]\nrequire_tests = "false"\n' hooks/x.sh)" "change x")"
# the gate acts only where a harness config exists: repo harness.toml or ~/.config/harness/<repo>.toml
home="$(mktemp -d "$fresh/home.XXXXXX")"
d="$(repo_with "" src/a.py)"; rm "$d/harness.toml"
HOME="$home" check "commit: unconfigured repo left alone" 0 $C "$(commit "$d" "add a")"
HOME="$home" check "commit: unconfigured --no-verify left alone" 0 $C "$(bash_cmd 'git commit --no-verify -m x' "$d")"
[ ! -e "$d/.git/harness" ] && echo "ok   commit: unconfigured repo gets no .git/harness" || { echo "FAIL commit: unconfigured repo gets no .git/harness"; fail=1; }
mkdir -p "$home/.config/harness"; printf '[test]\nunit = "true"\n[security]\nsecrets = "true"\n' > "$home/.config/harness/$(basename "$d").toml"
HOME="$home" check "commit: home config gates the repo" 2 $C "$(commit "$d" "add a")"
check "config: reads section.key"          0 lib/config.sh ""
[ "$(lib/config.sh "$tmp" test.unit)" = "true" ] && echo "ok   config: value" || { echo "FAIL config: value"; fail=1; }
[ "$(lib/config.sh "$tmp" nope.key dflt)" = "dflt" ] && echo "ok   config: default" || { echo "FAIL config: default"; fail=1; }
bash lib/config.sh "$tmp" --exists && echo "ok   config: --exists with repo file" || { echo "FAIL config: --exists with repo file"; fail=1; }
HOME="$home" bash lib/config.sh "$(mktemp -d "$fresh/bare.XXXXXX")" --exists && { echo "FAIL config: --exists without any file"; fail=1; } || echo "ok   config: --exists without any file"
rm -rf "$tmp" "$fresh" /tmp/harness
echo "$n checks"; exit $fail
