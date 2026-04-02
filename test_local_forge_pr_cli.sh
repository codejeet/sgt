#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

export HOME="$TMP_HOME"
export SGT_ROOT="$HOME/sgt"
MOCK_BIN="$HOME/mock-bin"
mkdir -p "$MOCK_BIN"
GH_CALLS="$HOME/gh.calls"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
echo "gh should not be called for local forge PR tests: $*" >> "$GH_CALLS"
exit 1
GH
chmod +x "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"

REPO="https://github.com/acme/demo"

"$ROOT_DIR/sgt" init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs" "$SGT_ROOT/rigs/demo"
printf '%s\n' "$REPO" > "$SGT_ROOT/.sgt/rigs/demo"

git -C "$SGT_ROOT/rigs/demo" init -b main >/dev/null
git -C "$SGT_ROOT/rigs/demo" config user.name tester
git -C "$SGT_ROOT/rigs/demo" config user.email tester@example.com
printf '%s\n' "base" > "$SGT_ROOT/rigs/demo/file.txt"
git -C "$SGT_ROOT/rigs/demo" add file.txt
git -C "$SGT_ROOT/rigs/demo" commit -m base >/dev/null
git -C "$SGT_ROOT/rigs/demo" checkout -b feat >/dev/null
printf '%s\n' "feature change" >> "$SGT_ROOT/rigs/demo/file.txt"
git -C "$SGT_ROOT/rigs/demo" commit -am feat >/dev/null

create_out=$("$ROOT_DIR/sgt" forge pr create --repo "$REPO" --head feat --base main --title "Local PR" --body "Closes #1")
[[ "$create_out" == "local://acme/demo/pull/1" ]]

list_out=$("$ROOT_DIR/sgt" forge pr list --repo "$REPO" --state all)
grep -Fq "Local PR" <<<"$list_out"
grep -Fq "local://acme/demo/pull/1" <<<"$list_out"
grep -Fq $'feat\t' <<<"$list_out"

view_out=$("$ROOT_DIR/sgt" forge pr view --repo "$REPO" 1)
grep -Fq "PR #1 [OPEN]" <<<"$view_out"
grep -Fq "Title: Local PR" <<<"$view_out"
grep -Fq "Head: feat" <<<"$view_out"
grep -Fq "Base: main" <<<"$view_out"

diff_out=$("$ROOT_DIR/sgt" forge pr diff --repo "$REPO" 1)
grep -Fq "+feature change" <<<"$diff_out"

"$ROOT_DIR/sgt" forge pr comment --repo "$REPO" 1 "Looks good" >/dev/null
"$ROOT_DIR/sgt" forge pr review --repo "$REPO" 1 --state APPROVED --body "approved" >/dev/null
"$ROOT_DIR/sgt" forge pr checks set --repo "$REPO" 1 --name build --state success >/dev/null
checks_out=$("$ROOT_DIR/sgt" forge pr checks list --repo "$REPO" 1)
grep -Eq $'build\t(SUCCESS|success)\t' <<<"$checks_out"

git -C "$SGT_ROOT/rigs/demo" checkout main >/dev/null
merge_out=$("$ROOT_DIR/sgt" forge pr merge --repo "$REPO" 1)
[[ "$merge_out" =~ [0-9a-f]{7,40}|merged ]]

post_list=$("$ROOT_DIR/sgt" forge pr list --repo "$REPO" --state all)
grep -Fq "Local PR" <<<"$post_list"
grep -Fq "local://acme/demo/pull/1" <<<"$post_list"
grep -Eq 'MERGED|merged' <<<"$post_list"

python3 - "$SGT_ROOT/.sgt/forge.db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
pr_count = conn.execute("select count(*) from pull_requests").fetchone()[0]
comment_count = conn.execute("select count(*) from pull_request_comments").fetchone()[0]
review_count = conn.execute("select count(*) from pull_request_reviews").fetchone()[0]
check_count = conn.execute("select count(*) from pull_request_checks").fetchone()[0]
merged_count = conn.execute("select count(*) from pull_requests where state = 'merged'").fetchone()[0]
assert pr_count == 1, pr_count
assert comment_count == 1, comment_count
assert review_count == 1, review_count
assert check_count == 1, check_count
assert merged_count == 1, merged_count
print("local-forge-pr-db-ok")
PY

if [[ -s "$GH_CALLS" ]]; then
  echo "local PR test unexpectedly invoked gh" >&2
  cat "$GH_CALLS" >&2
  exit 1
fi

echo "PASS: test_local_forge_pr_cli"
