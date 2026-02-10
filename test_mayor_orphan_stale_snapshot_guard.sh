#!/usr/bin/env bash
# test_mayor_orphan_stale_snapshot_guard.sh — Regression check for mayor orphan PR stale-snapshot live-state revalidation.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
STATE_CALLS="$TMP_ROOT/pr-state-calls"
MERGEABLE_CALLS="$TMP_ROOT/pr-mergeable-calls"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"
: > "$STATE_CALLS"
: > "$MERGEABLE_CALLS"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

STATE_CALLS_FILE="${SGT_MOCK_PR_STATE_CALLS:?missing SGT_MOCK_PR_STATE_CALLS}"
MERGEABLE_CALLS_FILE="${SGT_MOCK_PR_MERGEABLE_CALLS:?missing SGT_MOCK_PR_MERGEABLE_CALLS}"

count_file() {
  local file="$1"
  local n=0
  if [[ -s "$file" ]]; then
    n="$(cat "$file" 2>/dev/null || echo 0)"
  fi
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  n=$((n + 1))
  printf '%s\n' "$n" > "$file"
}

if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  # Mayor critical/high scans: no issues.
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  # Snapshot says open orphan PR exists.
  echo '#12 [sgt/test-orphan-pr12]'
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  shift 2
  pr_num="${1:-}"
  shift || true
  json_fields=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json_fields="${2:-}"
        shift 2
        ;;
      --jq)
        shift 2
        ;;
      --repo)
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ "$pr_num" != "12" ]]; then
    echo "unexpected pr number: $pr_num" >&2
    exit 1
  fi

  case "$json_fields" in
    state)
      count_file "$STATE_CALLS_FILE"
      echo "MERGED"
      ;;
    mergeable)
      count_file "$MERGEABLE_CALLS_FILE"
      echo "MERGEABLE"
      ;;
    body)
      echo "Closes #77"
      ;;
    headRefOid)
      echo "deadbeef"
      ;;
    *)
      echo ""
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  # Should not be needed when stale check short-circuits, but keep compatible.
  echo "sgt-authorized"
  exit 0
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
chmod +x "$MOCK_BIN/gh"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "has-session" ]]; then
  # Keep mayor health checks quiet by reporting sessions as present.
  exit 0
fi

if [[ "${1:-}" == "new-session" || "${1:-}" == "kill-session" ]]; then
  exit 0
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
  SGT_MOCK_PR_STATE_CALLS="$STATE_CALLS" \
  SGT_MOCK_PR_MERGEABLE_CALLS="$MERGEABLE_CALLS" \
  SGT_MAYOR_INTERVAL=1 \
  bash --noprofile --norc -c '
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"

sgt _mayor > "$SGT_ROOT/mayor.out" 2>&1 &
mayor_pid=$!
sleep 6
kill -9 "$mayor_pid" 2>/dev/null || true
wait "$mayor_pid" 2>/dev/null || true
'

QUEUE_DIR="$HOME_DIR/sgt/.sgt/merge-queue"
if [[ -n "$(ls -A "$QUEUE_DIR" 2>/dev/null || true)" ]]; then
  echo "expected no queued orphan PR when live state is MERGED" >&2
  ls -la "$QUEUE_DIR" >&2
  exit 1
fi

if [[ "$(cat "$STATE_CALLS" 2>/dev/null || echo 0)" -lt 1 ]]; then
  echo "expected at least one live PR state revalidation call" >&2
  exit 1
fi

if [[ "$(cat "$MERGEABLE_CALLS" 2>/dev/null || echo 0)" -ne 0 ]]; then
  echo "expected no mergeability lookup after stale-state short-circuit" >&2
  exit 1
fi

SGT_LOG_FILE="$HOME_DIR/sgt/sgt.log"
if [[ ! -f "$SGT_LOG_FILE" ]]; then
  echo "expected sgt.log to exist after mayor cycle" >&2
  [[ -f "$HOME_DIR/sgt/mayor.out" ]] && cat "$HOME_DIR/sgt/mayor.out" >&2 || true
  exit 1
fi
if ! grep -q 'MAYOR_ORPHAN_SKIP_STALE pr=#12' "$SGT_LOG_FILE"; then
  echo "expected stale orphan skip event in sgt.log" >&2
  cat "$HOME_DIR/sgt/mayor.out" >&2 || true
  exit 1
fi

if ! grep -q 'snapshot_state=OPEN live_state=MERGED' "$SGT_LOG_FILE"; then
  echo "expected stale skip event to include snapshot/live state details" >&2
  exit 1
fi

MAYOR_OUT="$HOME_DIR/sgt/mayor.out"
if ! grep -q 'stale snapshot (listed open, live state=MERGED)' "$MAYOR_OUT"; then
  echo "expected explicit stale snapshot skip reason in mayor output" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
