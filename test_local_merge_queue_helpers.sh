#!/usr/bin/env bash
# test_local_merge_queue_helpers.sh — Verify queue helpers use local forge PR state without gh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/.local/bin"
cp "$SGT_SCRIPT" "$TMP_HOME/.local/bin/sgt"
chmod +x "$TMP_HOME/.local/bin/sgt"

MOCK_BIN="$TMP_HOME/mock-bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
echo "unexpected gh call: $*" >&2
exit 1
GH
chmod +x "$MOCK_BIN/gh"

run_cmd() {
  local command="$1"
  env -i \
    HOME="$TMP_HOME" \
    PATH="$MOCK_BIN:$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    SGT_WORKFLOW_BACKEND=local \
    SGT_FORGE_BACKEND=local \
    bash --noprofile --norc -c "$command"
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if grep -Fq "$needle" <<<"$haystack"; then
    echo "PASS: $label"
  else
    echo "FAIL: $label" >&2
    printf '%s\n' "$haystack" >&2
    exit 1
  fi
}

run_cmd "sgt init >/dev/null"
run_cmd "mkdir -p \"\$HOME/sgt/.sgt/rigs\" \"\$HOME/sgt/rigs/demo\" && printf '%s\n' 'https://github.com/acme/demo' > \"\$HOME/sgt/.sgt/rigs/demo\""
run_cmd "cd \"\$HOME/sgt/rigs/demo\" && git init -b main >/dev/null && git config user.name sgt && git config user.email sgt@local && printf 'base\n' > app.txt && git add app.txt && git commit -m 'initial' >/dev/null && git checkout -b sgt/qdemo >/dev/null && printf 'queue\n' >> app.txt && git add app.txt && git commit -m 'queue' >/dev/null"
run_cmd "sgt forge issue create --repo https://github.com/acme/demo --title 'Queue me' --body 'Closes #1' --label sgt-authorized >/dev/null || true"
run_cmd "sgt forge issue create --repo https://github.com/acme/demo --title 'Queue me' --body 'queue issue' --label sgt-authorized >/dev/null"
run_cmd "sgt forge pr create --repo https://github.com/acme/demo --head sgt/qdemo --base main --title 'Queue helper PR' --body 'Closes #2' >/dev/null"

meta="$(run_cmd 'source "$HOME/.local/bin/sgt" >/dev/null 2>&1 || true; _witness_pr_meta https://github.com/acme/demo sgt/qdemo')"
assert_contains "witness pr meta sees local pr" "$meta" $'1\tOPEN'

head_sha="$(run_cmd 'source "$HOME/.local/bin/sgt" >/dev/null 2>&1 || true; _pr_head_sha https://github.com/acme/demo 1')"
[[ -n "$head_sha" ]] || { echo "FAIL: missing head sha" >&2; exit 1; }
echo "PASS: local pr head sha available"

run_cmd 'source "$HOME/.local/bin/sgt" >/dev/null 2>&1 || true; _merge_queue_enqueue_polecat demo https://github.com/acme/demo sgt/qdemo 2 1 "$(_pr_head_sha https://github.com/acme/demo 1)" false codex demo-polecat witness-pr-ready'
queue_file="$TMP_HOME/sgt/.sgt/merge-queue/demo-pr1"
[[ -f "$queue_file" ]] || { echo "FAIL: merge queue file missing" >&2; exit 1; }
queue_contents="$(cat "$queue_file")"
assert_contains "queue stores repo" "$queue_contents" 'REPO=https://github.com/acme/demo'
assert_contains "queue stores head sha" "$queue_contents" "HEAD_SHA=$head_sha"

snapshot="$(run_cmd 'source "$HOME/.local/bin/sgt" >/dev/null 2>&1 || true; _gh_pr_state_mergeable_live https://github.com/acme/demo 1')"
assert_contains "state/mergeable snapshot available" "$snapshot" 'OPEN|MERGEABLE'

echo "PASS: local merge queue helpers"
