#!/usr/bin/env bash
# test_sling_spawn_failure_cleanup.sh — Spawn failures must not leave stale polecat bookkeeping behind.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"

BRANCH_DELETE_LOG="$TMP_ROOT/branch-delete.log"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "label" && "${2:-}" == "create" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "create" ]]; then
  echo "https://github.com/acme/demo/issues/251"
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "edit" ]]; then
  exit 0
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
chmod +x "$MOCK_BIN/gh"

cat > "$MOCK_BIN/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail

BRANCH_DELETE_LOG="${SGT_TEST_BRANCH_DELETE_LOG:?missing branch delete log}"

if [[ "${1:-}" == "-C" ]]; then
  shift 2
fi

if [[ "${1:-}" == "fetch" ]]; then
  exit 0
fi

if [[ "${1:-}" == "symbolic-ref" ]]; then
  echo "refs/remotes/origin/master"
  exit 0
fi

if [[ "${1:-}" == "worktree" && "${2:-}" == "add" ]]; then
  mkdir -p "${5:?missing worktree path}"
  exit 0
fi

if [[ "${1:-}" == "worktree" && "${2:-}" == "remove" ]]; then
  rm -rf "${4:?missing worktree path}"
  exit 0
fi

if [[ "${1:-}" == "branch" && "${2:-}" == "-D" ]]; then
  printf '%s\n' "${3:-}" >> "$BRANCH_DELETE_LOG"
  exit 0
fi

echo "mock git unsupported: $*" >&2
exit 1
GIT
chmod +x "$MOCK_BIN/git"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi

if [[ "${1:-}" == "new-session" ]]; then
  echo "command too long" >&2
  exit 1
fi

echo "mock tmux unsupported: $*" >&2
exit 1
TMUX
chmod +x "$MOCK_BIN/tmux"

env -i \
  HOME="$HOME_DIR" \
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm}" \
  SGT_ROOT="$HOME_DIR/sgt" \
  SGT_TEST_BRANCH_DELETE_LOG="$BRANCH_DELETE_LOG" \
  bash --noprofile --norc -c '
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"

set +e
sgt sling test "spawn failure cleanup regression" --label critical > "$SGT_ROOT/sling.out" 2> "$SGT_ROOT/sling.err"
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "expected sling to fail when tmux spawn returns command too long" >&2
  exit 1
fi

if ! grep -q "failed to spawn polecat" "$SGT_ROOT/sling.err"; then
  echo "expected explicit spawn failure error" >&2
  cat "$SGT_ROOT/sling.err" >&2
  exit 1
fi

if find "$SGT_ROOT/.sgt/polecats" -type f | grep -q .; then
  echo "expected no polecat state files after failed spawn cleanup" >&2
  find "$SGT_ROOT/.sgt/polecats" -type f >&2
  exit 1
fi

worktree_path="$(find "$SGT_ROOT/polecats" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"
if [[ -n "$worktree_path" ]]; then
  echo "expected failed spawn cleanup to remove worktree residue" >&2
  find "$SGT_ROOT/polecats" -mindepth 1 -maxdepth 1 -type d >&2
  exit 1
fi

if ! grep -q "^sgt/" "'"$BRANCH_DELETE_LOG"'"; then
  echo "expected failed spawn cleanup to delete the local branch" >&2
  cat "'"$BRANCH_DELETE_LOG"'" >&2
  exit 1
fi

if ! grep -q "SLING_SPAWN_FAILED .*reason_code=command-too-long" "$SGT_ROOT/sgt.log"; then
  echo "expected structured spawn failure log entry" >&2
  cat "$SGT_ROOT/sgt.log" >&2
  exit 1
fi
'

echo "ALL TESTS PASSED"
