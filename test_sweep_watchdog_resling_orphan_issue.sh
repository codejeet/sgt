#!/usr/bin/env bash
# Regression: sweep watchdog should re-sling open sgt-authorized issues with no active polecat and no open PR.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
TMUX_NEW_SESSION_COUNT="$TMP_ROOT/tmux-new-session-count"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"
printf '0\n' > "$TMUX_NEW_SESSION_COUNT"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  shift 2
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
      --repo|--state|--label|--limit)
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  if [[ "$json_fields" == "number,title" ]]; then
    printf '77\tSweep watchdog issue\n'
  fi
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  shift 2
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
  case "$json_fields" in
    labels) echo "sgt-authorized" ;;
    title) echo "Sweep watchdog issue" ;;
    state) echo "OPEN" ;;
    body) echo "Issue body" ;;
    *) echo "" ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  # No open PR linked to issue.
  exit 0
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
chmod +x "$MOCK_BIN/gh"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

COUNT_FILE="${SGT_MOCK_TMUX_NEW_SESSION_COUNT:?missing SGT_MOCK_TMUX_NEW_SESSION_COUNT}"

inc_file() {
  local path="$1"
  local n=0
  if [[ -s "$path" ]]; then
    n="$(cat "$path" 2>/dev/null || echo 0)"
  fi
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  n=$((n + 1))
  printf '%s\n' "$n" > "$path"
  echo "$n"
}

if [[ "${1:-}" == "new-session" ]]; then
  inc_file "$COUNT_FILE" >/dev/null
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
  SGT_MOCK_TMUX_NEW_SESSION_COUNT="$TMUX_NEW_SESSION_COUNT" \
  bash --noprofile --norc -c '
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"

sgt sweep > "$SGT_ROOT/sweep.out" 2>&1
'

if [[ "$(cat "$TMUX_NEW_SESSION_COUNT")" != "1" ]]; then
  echo "expected sweep watchdog to spawn exactly one polecat" >&2
  exit 1
fi

OUT_FILE="$HOME_DIR/sgt/sweep.out"
LOG_FILE="$HOME_DIR/sgt/sgt.log"

if ! grep -q 'watchdog re-slinging issue #77 (no active polecat, no open PR)' "$OUT_FILE"; then
  echo "expected operator-visible sweep watchdog redispatch message" >&2
  exit 1
fi
if ! grep -q 'SWEEP_WATCHDOG_RESLING_DISPATCH issue=#77 rig=test repo=acme/demo reason_code=no-active-polecat-no-open-pr' "$LOG_FILE"; then
  echo "expected structured sweep watchdog dispatch telemetry" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
