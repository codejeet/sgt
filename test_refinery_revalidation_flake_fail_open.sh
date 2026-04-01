#!/usr/bin/env bash
# Regression: redispatch should fail open when source-PR mergeability revalidation flakes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
TMUX_NEW_SESSION_MARKER="$TMP_ROOT/tmux-new-session"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

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

  case "$json_fields" in
    labels)
      echo "sgt-authorized"
      ;;
    title)
      echo "Redispatch fail-open issue"
      ;;
    state)
      echo "OPEN"
      ;;
    body)
      echo "Issue body"
      ;;
    *)
      echo ""
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
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

  case "$json_fields" in
    title)
      echo "Redispatch fail-open PR"
      ;;
    state)
      echo "OPEN"
      ;;
    mergeable)
      echo "CONFLICTING"
      ;;
    state,mergeable)
      echo "OPEN|UNKNOWN"
      ;;
    *)
      echo ""
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "checks" ]]; then
  echo "all checks pass"
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "comment" ]]; then
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "close" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "reopen" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  exit 0
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
chmod +x "$MOCK_BIN/gh"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

MARKER="${SGT_MOCK_TMUX_NEW_SESSION_MARKER:?missing SGT_MOCK_TMUX_NEW_SESSION_MARKER}"

if [[ "${1:-}" == "new-session" ]]; then
  touch "$MARKER"
  exit 0
fi

if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi

exit 0
TMUX
chmod +x "$MOCK_BIN/tmux"

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
      mkdir -p "${5:-}"
      exit 0
    fi
    if [[ "${2:-}" == "remove" ]]; then
      rm -rf "${4:-}"
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

env -i \
  HOME="$HOME_DIR" \
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm}" \
  SGT_ROOT="$HOME_DIR/sgt" \
  SGT_MOCK_TMUX_NEW_SESSION_MARKER="$TMUX_NEW_SESSION_MARKER" \
  bash --noprofile --norc -c '
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"

cat > "$SGT_ROOT/.sgt/merge-queue/test-pr123" <<MQ
POLECAT=test-pr123
RIG=test
REPO=https://github.com/acme/demo
BRANCH=sgt/test-pr123
ISSUE=77
PR=123
HEAD_SHA=abc123
AUTO_MERGE=true
TYPE=polecat
QUEUED=$(date -Iseconds)
MQ

timeout 6 sgt _refinery test > "$SGT_ROOT/refinery.out" 2>&1 &
pid=$!

for _ in $(seq 1 120); do
  fifo="$SGT_ROOT/.sgt/refinery-test.fifo"
  if [[ -p "$fifo" ]]; then
    printf "test-wake\n" > "$fifo"
    break
  fi
  sleep 0.05
done

wait "$pid" || true
'

[[ -f "$TMUX_NEW_SESSION_MARKER" ]] || {
  echo "expected redispatch to proceed despite flaky mergeability revalidation" >&2
  exit 1
}

grep -q 'RESLING .* issue=#77' "$HOME_DIR/sgt/sgt.log" || {
  echo "expected resling log entry after fail-open redispatch" >&2
  exit 1
}

echo "ALL TESTS PASSED"
