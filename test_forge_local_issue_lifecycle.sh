#!/usr/bin/env bash
# test_forge_local_issue_lifecycle.sh — Exercise the local forge issue/label lifecycle.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/.local/bin"
cp "$SGT_SCRIPT" "$TMP_HOME/.local/bin/sgt"
chmod +x "$TMP_HOME/.local/bin/sgt"

run_cmd() {
  local command="$1"
  env -i \
    HOME="$TMP_HOME" \
    PATH="$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
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

label_output="$(run_cmd "sgt forge label create --repo https://github.com/acme/demo sgt-authorized >/dev/null && sgt forge label create --repo https://github.com/acme/demo backend-limited --description 'Blocked locally' --color BFD4F2 >/dev/null && sgt forge label list --repo https://github.com/acme/demo")"
assert_contains "local forge stores label descriptions/colors" "$label_output" "backend-limited|Blocked locally|BFD4F2"
assert_contains "local forge lists authorized label" "$label_output" "sgt-authorized|"

issue_url="$(run_cmd "sgt forge issue create --repo https://github.com/acme/demo --title 'Local queue drift' --body 'Track local backend slice' --label sgt-authorized --label backend-limited --milestone convoy-1")"
assert_contains "local forge issue URL uses local scheme" "$issue_url" "local://acme/demo/issues/1"

view_output="$(run_cmd "sgt forge issue view --repo https://github.com/acme/demo 1")"
assert_contains "issue view shows milestone" "$view_output" "Milestone: convoy-1"
assert_contains "issue view shows labels" "$view_output" "Labels: backend-limited, sgt-authorized"

open_list="$(run_cmd "sgt forge issue list --repo https://github.com/acme/demo --state open --label sgt-authorized")"
assert_contains "issue list shows created issue" "$open_list" "#1 [OPEN] Local queue drift"

run_cmd "sgt forge issue comment --repo https://github.com/acme/demo 1 'Needs local queue replay handling' >/dev/null"
comment_view="$(run_cmd "sgt forge issue view --repo https://github.com/acme/demo 1")"
assert_contains "issue comment is persisted locally" "$comment_view" "Needs local queue replay handling"

run_cmd "sgt forge issue close --repo https://github.com/acme/demo 1 >/dev/null"
closed_list="$(run_cmd "sgt forge issue list --repo https://github.com/acme/demo --state closed")"
assert_contains "issue closes locally" "$closed_list" "#1 [CLOSED] Local queue drift"

run_cmd "sgt forge issue reopen --repo https://github.com/acme/demo 1 >/dev/null"
reopened_list="$(run_cmd "sgt forge issue list --repo https://github.com/acme/demo --state open")"
assert_contains "issue reopens locally" "$reopened_list" "#1 [OPEN] Local queue drift"

activity_output="$(run_cmd "sgt forge activity tail --repo https://github.com/acme/demo --limit 5")"
assert_contains "activity tail records issue creation" "$activity_output" "issue.created|issue|1|Local queue drift"
assert_contains "activity tail records commenting" "$activity_output" "issue.commented|issue|1|Needs local queue replay handling"

echo "PASS: local forge issue lifecycle"
