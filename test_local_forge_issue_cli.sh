#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP_HOME=$(mktemp -d)
trap 'rm -rf "$TMP_HOME"' EXIT

export HOME="$TMP_HOME"
export SGT_ROOT="$HOME/sgt"
export SGT_WORKFLOW_BACKEND=local
MOCK_BIN="$HOME/mock-bin"
mkdir -p "$MOCK_BIN"
GH_CALLS="$HOME/gh.calls"

cat > "$MOCK_BIN/gh" <<GH
#!/usr/bin/env bash
echo "gh should not be called for local forge tests: \$*" >> "$GH_CALLS"
exit 1
GH
chmod +x "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"

REPO="https://github.com/acme/demo"

"$ROOT_DIR/sgt" init >/dev/null

label_create_out=$("$ROOT_DIR/sgt" forge label create --repo "$REPO" triage)
grep -Fq "forge label created: triage" <<<"$label_create_out"
label_list_out=$("$ROOT_DIR/sgt" forge label list --repo "$REPO")
grep -Fq "triage|" <<<"$label_list_out"

create_out=$("$ROOT_DIR/sgt" forge issue create --repo "$REPO" --title "Local forge issue" --body "Offline body" --label sgt-authorized --label offline)
issue_id=$(printf '%s\n' "$create_out" | grep -oE '/issues/[0-9]+' | grep -oE '[0-9]+')
[[ -n "$issue_id" ]]
[[ "$create_out" == "local://acme/demo/issues/$issue_id" ]]

list_out=$("$ROOT_DIR/sgt" forge issue list --repo "$REPO")
grep -Fq "#$issue_id [OPEN] Local forge issue" <<<"$list_out"
grep -Fq "labels=offline,sgt-authorized" <<<"$list_out"

view_out=$("$ROOT_DIR/sgt" forge issue view --repo "$REPO" "$issue_id")
grep -Fq "Issue #$issue_id [OPEN]" <<<"$view_out"
grep -Fq "Title: Local forge issue" <<<"$view_out"
grep -Fq "Body:" <<<"$view_out"
grep -Fq "Offline body" <<<"$view_out"
grep -Fq "Labels: offline, sgt-authorized" <<<"$view_out"
grep -Fq "Comments:" <<<"$view_out"
grep -Fq "(none)" <<<"$view_out"

"$ROOT_DIR/sgt" forge issue comment --repo "$REPO" "$issue_id" "First durable comment" >/dev/null
view_with_comment=$("$ROOT_DIR/sgt" forge issue view --repo "$REPO" "$issue_id")
grep -Fq "First durable comment" <<<"$view_with_comment"

"$ROOT_DIR/sgt" mail send "$REPO" "$issue_id" "Mail layer local comment" >/dev/null
mail_out=$("$ROOT_DIR/sgt" mail check "$REPO")
grep -Fq "#$issue_id" <<<"$mail_out"
grep -Fq "Mail layer local comment" <<<"$mail_out"

"$ROOT_DIR/sgt" forge issue close --repo "$REPO" "$issue_id" >/dev/null
closed_list=$("$ROOT_DIR/sgt" forge issue list --repo "$REPO" --state closed)
grep -Fq "#$issue_id [CLOSED] Local forge issue" <<<"$closed_list"
open_list_after_close=$("$ROOT_DIR/sgt" forge issue list --repo "$REPO")
if grep -Fq "#$issue_id [OPEN]" <<<"$open_list_after_close"; then
  echo "closed issue unexpectedly remained in open list" >&2
  exit 1
fi

"$ROOT_DIR/sgt" forge issue reopen --repo "$REPO" "$issue_id" >/dev/null
reopened_view=$("$ROOT_DIR/sgt" forge issue view --repo "$REPO" "$issue_id")
grep -Fq "Issue #$issue_id [OPEN]" <<<"$reopened_view"

DB_PATH="$SGT_ROOT/.sgt/forge.db"
[[ -f "$DB_PATH" ]]
python3 - "$DB_PATH" <<'PY'
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
issue_count = conn.execute('select count(*) from issues').fetchone()[0]
comment_count = conn.execute('select count(*) from issue_comments').fetchone()[0]
label_count = conn.execute('select count(*) from labels').fetchone()[0]
assert issue_count == 1, issue_count
assert comment_count == 2, comment_count
assert label_count == 3, label_count
print('local-forge-db-ok')
PY

help_out=$("$ROOT_DIR/sgt" help)
grep -Fq "forge <subcommand>" <<<"$help_out"
grep -Fq "SGT_FORGE_BACKEND" <<<"$help_out"
forge_help_out=$("$ROOT_DIR/sgt" forge)
grep -Fq "issue <subcommand>" <<<"$forge_help_out"
grep -Fq "label <subcommand>" <<<"$forge_help_out"

if [[ -s "$GH_CALLS" ]]; then
  echo "local forge test unexpectedly invoked gh" >&2
  cat "$GH_CALLS" >&2
  exit 1
fi

echo "PASS: test_local_forge_issue_cli"
