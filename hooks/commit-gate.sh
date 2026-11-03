#!/bin/bash
# Ionian Harness commit gate (PreToolUse on Bash).
# On `git commit`: refuse --no-verify, scan staged lines for secrets, run the unit
# suite from harness.toml, require a test change when source changed. Exit 2 denies,
# the exit code is the real runner's, nothing is piped into grep.

# This gate protects something, so it fails closed: if it cannot do its job, it denies.
payload="$(cat)"
if ! command -v jq >/dev/null 2>&1; then
  # cannot parse the payload; only deny if this looks like a commit at all
  grep -q 'git[^"]*commit' <<<"$payload" && { echo "Commit gate: jq is not installed, cannot verify this commit. Install jq (brew install jq)." >&2; exit 2; }
  exit 0
fi
tool="$(jq -r '.tool_name // ""' <<<"$payload")"
[ "$tool" = "Bash" ] || exit 0
cmd="$(jq -r '.tool_input.command // ""' <<<"$payload")"
[[ "$cmd" =~ (^|[;&|][[:space:]]*)git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit ]] || exit 0

here="$(cd "$(dirname "$0")/.." && pwd)"
cwd="$(jq -r '.cwd // "."' <<<"$payload")"
# honour a leading `cd <dir> &&`
if [[ "$cmd" =~ ^[[:space:]]*cd[[:space:]]+([^[:space:];&]+)[[:space:]]*(&&|;) ]]; then
  cd "$cwd" 2>/dev/null; cd "${BASH_REMATCH[1]}" 2>/dev/null || true
else
  cd "$cwd" 2>/dev/null || true
fi
repo="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
state="$(git rev-parse --git-dir 2>/dev/null || echo /tmp)/harness"; mkdir -p "$state"
log="$state/gate.log"
[ -f "$here/lib/config.sh" ] || { echo "Commit gate: lib/config.sh missing at $here, refusing to commit unverified." >&2; exit 2; }
cfg() { bash "$here/lib/config.sh" "$repo" "$1" "$2"; }

deny() { echo "  -> commit DENIED: $1" >> "$log"; printf 'Commit gate: %s\n' "$1" >&2; [ -n "$2" ] && printf '%s\n' "$2" | tail -n 25 >&2; exit 2; }
echo "$(date +%H:%M:%S) agent=$(jq -r '.agent_type // "main"' <<<"$payload") tool=Bash git commit in $repo" >> "$log"

# 1. no bypass
[[ "$cmd" =~ --no-verify|[[:space:]]-n([[:space:]]|$) ]] && deny "--no-verify is not allowed. Fix the cause, then commit."

# 2. secrets in staged lines
secrets="$(cfg security.secrets "gitleaks git --pre-commit --staged --redact --no-banner")"
if command -v "${secrets%% *}" >/dev/null 2>&1; then
  out="$(eval "$secrets" 2>&1)" || deny "secret scan failed ($secrets)." "$out"
else
  echo "  note: secret scanner not installed (${secrets%% *}), skipped" >> "$log"
fi

# 3. unit suite
unit="$(cfg test.unit)"
if [ -n "$unit" ]; then
  start=$(date +%s)
  out="$(eval "$unit" 2>&1)" || deny "unit suite is red ($unit). Make it green, then commit." "$out"
  took=$(( $(date +%s) - start )); budget="$(cfg limits.unit_seconds 30)"
  [ "$took" -gt "$budget" ] && echo "  note: unit suite took ${took}s, budget ${budget}s" >> "$log"
else
  echo "  note: no test.unit in harness.toml, tests skipped" >> "$log"
fi

# 4. source changed without a test change
if [ "$(cfg gate.require_tests true)" = "true" ] && [[ ! "$cmd" =~ \[no-tests\] ]]; then
  testdir="$(cfg test.dir tests)"
  src_glob="$(cfg gate.source_glob '\.(py|js|ts|tsx|go|rs|sh|rb|java|kt|swift)$')"
  staged="$(git diff --cached --name-only)"
  src_changed="$(grep -E "$src_glob" <<<"$staged" | grep -v "^$testdir/" || true)"
  tests_changed="$(grep "^$testdir/" <<<"$staged" || true)"
  if [ -n "$src_changed" ] && [ -z "$tests_changed" ]; then
    deny "source files changed but nothing under $testdir/ did. Add or update a test, or put [no-tests] in the commit message with a reason." "$src_changed"
  fi
fi
echo "  -> commit allowed" >> "$log"
exit 0
