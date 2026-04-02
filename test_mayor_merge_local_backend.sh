#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

export HOME="$TMP_HOME"
export SGT_ROOT="$HOME/sgt"
export SGT_WORKFLOW_BACKEND=local
MOCK_BIN="$HOME/mock-bin"
mkdir -p "$MOCK_BIN" "$SGT_ROOT/.sgt/rigs" "$SGT_ROOT/rigs/demo"
GH_CALLS="$HOME/gh.calls"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
echo "unexpected gh call: $*" >> "$GH_CALLS"
exit 1
GH
chmod +x "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"

REPO="https://github.com/acme/demo"
printf '%s\n' "$REPO" > "$SGT_ROOT/.sgt/rigs/demo"
"$ROOT_DIR/sgt" init >/dev/null

REPO_DIR="$SGT_ROOT/rigs/demo"
git -C "$REPO_DIR" init -b main >/dev/null
git -C "$REPO_DIR" config user.email tester@example.com
git -C "$REPO_DIR" config user.name tester
printf 'base\n' > "$REPO_DIR/file.txt"
git -C "$REPO_DIR" add file.txt
git -C "$REPO_DIR" commit -m base >/dev/null
git -C "$REPO_DIR" checkout -b feature/mayor >/dev/null
printf 'base\nmayor\n' > "$REPO_DIR/file.txt"
git -C "$REPO_DIR" commit -am mayor >/dev/null
git -C "$REPO_DIR" checkout main >/dev/null

"$ROOT_DIR/sgt" forge pr create --repo "$REPO" --head feature/mayor --base main --title 'Mayor local merge' --body 'local body' >/dev/null
"$ROOT_DIR/sgt" mayor merge 1 --repo "$REPO" >/dev/null

pr_view=$("$ROOT_DIR/sgt" forge pr view --repo "$REPO" 1)
grep -Fq 'PR #1 [MERGED]' <<<"$pr_view"
if git -C "$REPO_DIR" show-ref --verify --quiet refs/heads/feature/mayor; then
  echo 'feature branch unexpectedly remained after mayor merge' >&2
  exit 1
fi

if [[ -s "$GH_CALLS" ]]; then
  echo 'mayor merge unexpectedly invoked gh' >&2
  cat "$GH_CALLS" >&2
  exit 1
fi

echo 'PASS: test_mayor_merge_local_backend'
