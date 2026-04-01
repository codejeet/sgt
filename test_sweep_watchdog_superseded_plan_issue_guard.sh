#!/usr/bin/env bash
# Regression: sweep watchdog should skip open authorized plan issues that no longer match the current repo-local task definition.

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
  label=""
  state_filter="open"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json_fields="${2:-}"
        shift 2
        ;;
      --label)
        label="${2:-}"
        shift 2
        ;;
      --state)
        state_filter="${2:-}"
        shift 2
        ;;
      --jq)
        shift 2
        ;;
      --repo|--limit)
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  if [[ "$json_fields" == "number,title" ]]; then
    printf '77\tImplement and evaluate late_expiry_taker_h5_only_reset_confirmation_confidence_lift_gate as the immediate next continuation lane\n'
  elif [[ "$label" == "plan-PKNXT-15" && "$state_filter" == "all" ]]; then
    echo '[]'
  else
    echo '[]'
  fi
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  issue_number="${3:-}"
  issue_number="${issue_number#\#}"
  shift 3
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
    labels) echo "sgt-authorized plan plan-PKNXT-15" ;;
    state) echo "OPEN" ;;
    title) echo "Implement and evaluate late_expiry_taker_h5_only_reset_confirmation_confidence_lift_gate as the immediate next continuation lane" ;;
    body) cat <<'EOF'
## Task

Implement and evaluate late_expiry_taker_h5_only_reset_confirmation_confidence_lift_gate as the immediate next continuation lane
EOF
      ;;
    title,body,labels) cat <<'EOF'
{"title":"Implement and evaluate late_expiry_taker_h5_only_reset_confirmation_confidence_lift_gate as the immediate next continuation lane","body":"## Task\n\nImplement and evaluate late_expiry_taker_h5_only_reset_confirmation_confidence_lift_gate as the immediate next continuation lane\n","labels":[{"name":"sgt-authorized"},{"name":"plan"},{"name":"plan-PKNXT-15"}]}
EOF
      ;;
    *) echo "" ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  exit 0
fi

if [[ "${1:-}" == "label" && "${2:-}" == "create" ]]; then
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

if [[ "${1:-}" == "new-session" ]]; then
  n="$(cat "$COUNT_FILE")"
  n=$((n + 1))
  printf '%s\n' "$n" > "$COUNT_FILE"
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
  worktree|branch)
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
cat > "$SGT_ROOT/rigs/test/SGT_PLAN.json" <<'"'"'JSON'"'"'
{
  "version": 1,
  "rig": "test",
  "policy": { "max_in_flight": 1 },
  "tasks": [
    { "id": "PKNXT-15", "title": "Implement and evaluate late_expiry_taker_h5_h10_passive_improvement_proof_subset_lane as the primary widened-corpus continuation lane", "status": "pending" }
  ]
}
JSON

sgt sweep > "$SGT_ROOT/sweep.out" 2>&1
'

if [[ "$(cat "$TMUX_NEW_SESSION_COUNT")" != "0" ]]; then
  echo "expected sweep watchdog to skip superseded plan issue" >&2
  exit 1
fi

LOG_FILE="$HOME_DIR/sgt/sgt.log"

grep -q 'SWEEP_WATCHDOG_RESLING_SKIP issue=#77 rig=test repo=acme/demo reason_code=superseded-plan-task-issue' "$LOG_FILE" || {
  echo "expected structured superseded-plan watchdog skip telemetry" >&2
  cat "$LOG_FILE" >&2
  exit 1
}

echo "ALL TESTS PASSED"
