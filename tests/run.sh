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
# read: documented gap: outside a git repo the denial counter lives in /tmp/harness (shared by every non-git cwd); kept because a per-user path would need a decision on cleanup
ng="$(mktemp -d)"; rm -f /tmp/harness/denials-gapsess
(cd "$ng" && echo "{\"tool_name\":\"Read\",\"session_id\":\"gapsess\",\"tool_input\":{\"file_path\":\"$tmp/big.txt\"}}" | bash "$OLDPWD/$R" >/dev/null 2>&1)
if [ -f /tmp/harness/denials-gapsess ]; then echo "ok   read: documented gap: state outside git lives in /tmp/harness"; else echo "FAIL read: documented gap: state outside git lives in /tmp/harness"; fail=1; fi
n=$((n+1)); rm -rf "$ng"
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
# the gate acts only where a harness config exists: repo harness.toml or ~/Ionian/harness/<repo>.toml (IONIAN_HOME overrides ~/Ionian)
unset IONIAN_HOME
home="$(mktemp -d "$fresh/home.XXXXXX")"
d="$(repo_with "" src/a.py)"; rm "$d/harness.toml"
HOME="$home" check "commit: unconfigured repo left alone" 0 $C "$(commit "$d" "add a")"
HOME="$home" check "commit: unconfigured --no-verify left alone" 0 $C "$(bash_cmd 'git commit --no-verify -m x' "$d")"
[ ! -e "$d/.git/harness" ] && echo "ok   commit: unconfigured repo gets no .git/harness" || { echo "FAIL commit: unconfigured repo gets no .git/harness"; fail=1; }
mkdir -p "$home/Ionian/harness"; printf '[test]\nunit = "true"\n[security]\nsecrets = "true"\n' > "$home/Ionian/harness/$(basename "$d").toml"
HOME="$home" check "commit: home config gates the repo" 2 $C "$(commit "$d" "add a")"
check "config: reads section.key"          0 lib/config.sh ""
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
# live secret scan: the real gitleaks binary against staged content (skipped when it is not installed)
if command -v gitleaks >/dev/null 2>&1; then
  live="$(repo_with '' src/a.py tests/a_test.sh)"
  printf '[test]\nunit = "true"\ndir = "tests"\n' > "$live/harness.toml"   # no [security]: the default scan command runs
  fake="ghp_$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 36)"      # built at runtime, never a literal
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
rm -rf "$tmp" "$fresh" /tmp/harness
echo "$n checks"; exit $fail
