#!/usr/bin/env bash
# test_forge_local_pr_lifecycle.sh — Exercise local forge PR/review/check/merge lifecycle.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/.local/bin"
cp "$SGT_SCRIPT" "$TMP_HOME/.local/bin/sgt"
chmod +x "$TMP_HOME/.local/bin/sgt"

MOCK_BIN="$TMP_HOME/mock-bin"
GH_CALLS="$TMP_HOME/gh.calls"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
echo "unexpected gh call: $*" >> "$GH_CALLS"
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
    echo "expected to find: $needle" >&2
    echo "--- output ---" >&2
    printf '%s\n' "$haystack" >&2
    exit 1
  fi
}

run_cmd "sgt init >/dev/null"
run_cmd "mkdir -p \"\$HOME/sgt/.sgt/rigs\" \"\$HOME/sgt/rigs/demo\" && printf '%s\n' 'https://github.com/acme/demo' > \"\$HOME/sgt/.sgt/rigs/demo\""
run_cmd "cd \"\$HOME/sgt/rigs/demo\" && git init -b main >/dev/null && git config user.name sgt && git config user.email sgt@local && printf 'base\n' > app.txt && git add app.txt && git commit -m 'initial' >/dev/null && git checkout -b sgt/local-pr >/dev/null && printf 'feature\n' >> app.txt && git add app.txt && git commit -m 'feature' >/dev/null"

issue_url="$(run_cmd "sgt forge issue create --repo https://github.com/acme/demo --title 'Track local PR cutover' --body 'Needed for local refinery' --label sgt-authorized")"
assert_contains "issue created" "$issue_url" "local://acme/demo/issues/1"

pr_url="$(run_cmd "sgt forge pr create --repo https://github.com/acme/demo --head sgt/local-pr --base main --title 'Local PR cutover' --body 'Closes #1'")"
assert_contains "pr created" "$pr_url" "local://acme/demo/pull/1"

pr_list="$(run_cmd "sgt forge pr list --repo https://github.com/acme/demo --state open")"
assert_contains "pr list shows open pr" "$pr_list" "#1 [OPEN] Local PR cutover"

pr_view="$(run_cmd "sgt forge pr view --repo https://github.com/acme/demo 1")"
assert_contains "pr view shows head" "$pr_view" "Head: sgt/local-pr"
assert_contains "pr view shows body" "$pr_view" "Closes #1"

pr_diff="$(run_cmd "sgt forge pr diff --repo https://github.com/acme/demo 1")"
assert_contains "pr diff includes feature line" "$pr_diff" "+feature"

run_cmd "sgt forge pr comment --repo https://github.com/acme/demo 1 'Looks ready locally' >/dev/null"
run_cmd "sgt forge pr review --repo https://github.com/acme/demo 1 --state APPROVE --body 'Approved locally' >/dev/null"
run_cmd "sgt forge pr checks set --repo https://github.com/acme/demo 1 --name build --state success --started-at 2026-04-02T00:00:00Z --finished-at 2026-04-02T00:01:00Z --log-path /tmp/build.log >/dev/null"

pr_view_after="$(run_cmd "sgt forge pr view --repo https://github.com/acme/demo 1")"
assert_contains "pr comment persisted" "$pr_view_after" "Looks ready locally"
assert_contains "pr review persisted" "$pr_view_after" "Approved locally"

checks_out="$(run_cmd "sgt forge pr checks list --repo https://github.com/acme/demo 1")"
assert_contains "pr checks persisted" "$checks_out" $'build\tSUCCESS\t2026-04-02T00:00:00Z\t2026-04-02T00:01:00Z'

merge_out="$(run_cmd "sgt forge pr merge --repo https://github.com/acme/demo 1")"
if [[ "$merge_out" =~ ^[0-9a-f]{40}$ || "$merge_out" == *"merged"* ]]; then
  echo "PASS: pr merged locally"
else
  echo "FAIL: pr merged locally" >&2
  printf '%s\n' "$merge_out" >&2
  exit 1
fi

merged_list="$(run_cmd "sgt forge pr list --repo https://github.com/acme/demo --state merged")"
assert_contains "merged list shows pr" "$merged_list" "#1 [MERGED] Local PR cutover"

issue_view_after_merge="$(run_cmd "sgt forge issue view --repo https://github.com/acme/demo 1")"
assert_contains "linked issue closed on merge" "$issue_view_after_merge" "Issue #1 [CLOSED]"

activity_out="$(run_cmd "sgt forge activity tail --repo https://github.com/acme/demo --limit 8")"
assert_contains "activity records pr creation" "$activity_out" "pr.created|pr|1|Local PR cutover"
assert_contains "activity records pr merge" "$activity_out" "pr.merged|pr|1|"

if [[ -s "$GH_CALLS" ]]; then
  echo "FAIL: local PR lifecycle unexpectedly invoked gh" >&2
  cat "$GH_CALLS" >&2
  exit 1
fi

echo "PASS: local forge PR lifecycle"
