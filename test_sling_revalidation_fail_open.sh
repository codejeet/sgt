#!/usr/bin/env bash
# Regression: flaky live revalidation must not block sling dispatch.

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

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "label" && "${2:-}" == "create" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "create" ]]; then
  echo "https://github.com/acme/demo/issues/88"
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "edit" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  shift 2
  json_fields=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_fields="${2:-}"; shift 2 ;;
      --jq) shift 2 ;;
      --repo) shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ "$json_fields" == "state" ]]; then
    echo "OPEN"
    exit 0
  fi
fi

if [[ "${1:-}" == "api" && "${2:-}" == "graphql" ]]; then
  echo "GraphQL: upstream temporarily unavailable" >&2
  exit 1
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
chmod +x "$MOCK_BIN/gh"

cat > "$MOCK_BIN/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-C" ]]; then
  shift 2
fi

case "${1:-}" in
  fetch)
    exit 0
    ;;
  symbolic-ref)
    echo "refs/remotes/origin/master"
    exit 0
    ;;
  worktree)
    if [[ "${2:-}" == "add" ]]; then
      mkdir -p "${5:?missing worktree path}"
      exit 0
    fi
    if [[ "${2:-}" == "remove" ]]; then
      rm -rf "${4:?missing worktree path}"
      exit 0
    fi
    ;;
  branch)
    exit 0
    ;;
esac

echo "mock git unsupported: $*" >&2
exit 1
GIT
chmod +x "$MOCK_BIN/git"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  has-session)
    exit 1
    ;;
  new-session)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
TMUX
chmod +x "$MOCK_BIN/tmux"

env -i \
  HOME="$HOME_DIR" \
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm}" \
  SGT_ROOT="$HOME_DIR/sgt" \
  SGT_MAYOR_DISPATCH_REVALIDATE=1 \
  bash --noprofile --norc -c '
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"

sgt sling test "revalidation fail-open regression" > "$SGT_ROOT/sling.out" 2>&1
'

grep -q 'dispatch live revalidation flaked on test' "$HOME_DIR/sgt/sling.out" || {
  echo "expected operator-visible fail-open revalidation notice" >&2
  exit 1
}

grep -q 'issue #88 created' "$HOME_DIR/sgt/sling.out" || {
  echo "expected sling to continue creating the issue after fail-open" >&2
  exit 1
}

grep -q 'MAYOR_DISPATCH_REVALIDATE_FAIL_OPEN reason_code=live-query-failed rig=test' "$HOME_DIR/sgt/sgt.log" || {
  echo "expected structured fail-open log entry" >&2
  exit 1
}

echo "ALL TESTS PASSED"
