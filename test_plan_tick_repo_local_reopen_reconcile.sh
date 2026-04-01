#!/usr/bin/env bash
# Regression: repo-local task status can explicitly reopen a stale completed plan-state task for redispatch.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/.local/bin" "$TMP_HOME/mock-bin" "$TMP_HOME/state/issues"
cp "$SGT_SCRIPT" "$TMP_HOME/.local/bin/sgt"
chmod +x "$TMP_HOME/.local/bin/sgt"

cat > "$TMP_HOME/mock-bin/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$TMP_HOME/mock-bin/openclaw"

cat > "$TMP_HOME/mock-bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  has-session)
    exit 1
    ;;
  new-session|kill-session)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMP_HOME/mock-bin/tmux"

cat > "$TMP_HOME/mock-bin/git" <<'EOF'
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
    echo "refs/remotes/origin/main"
    exit 0
    ;;
  worktree)
    shift
    case "${1:-}" in
      add)
        shift
        if [[ "${1:-}" == "-b" ]]; then
          worktree="${3:-}"
        else
          worktree="${1:-}"
        fi
        mkdir -p "$worktree"
        exit 0
        ;;
      remove)
        exit 0
        ;;
    esac
    ;;
esac
exit 0
EOF
chmod +x "$TMP_HOME/mock-bin/git"

cat > "$TMP_HOME/mock-bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${GH_STATE_DIR:?missing GH_STATE_DIR}"
ISSUES_DIR="$STATE_DIR/issues"
mkdir -p "$ISSUES_DIR"

command="${1:-}"
subcommand="${2:-}"
shift 2 || true

next_issue() {
  local counter_file="$STATE_DIR/issue-counter"
  local current=0
  if [[ -f "$counter_file" ]]; then
    current="$(cat "$counter_file")"
  fi
  current=$((current + 1))
  printf '%s' "$current" > "$counter_file"
  echo "$current"
}

case "$command:$subcommand" in
  label:create|pr:list|issue:edit|api:*)
    exit 0
    ;;
  issue:list)
    echo '[]'
    exit 0
    ;;
  issue:view)
    issue_number="${1:-}"
    issue_number="${issue_number#\#}"
    issue_file="$ISSUES_DIR/$issue_number.env"
    [[ -f "$issue_file" ]] || exit 1
    state_value="$(sed -n 's/^STATE=//p' "$issue_file" | head -1)"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --json|--jq)
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    printf '%s\n' "${state_value:-}"
    ;;
  issue:create)
    repo=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo) repo="$2"; shift 2 ;;
        --title|--body|--label) shift 2 ;;
        *) shift ;;
      esac
    done
    issue_number="$(next_issue)"
    printf 'STATE=%q\n' "OPEN" > "$ISSUES_DIR/$issue_number.env"
    echo "${repo}/issues/${issue_number}"
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMP_HOME/mock-bin/gh"

COMMON_ENV=(
  "HOME=$TMP_HOME"
  "PATH=$TMP_HOME/mock-bin:$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
  "TERM=${TERM:-xterm}"
  "GH_STATE_DIR=$TMP_HOME/state"
)

env -i "${COMMON_ENV[@]}" bash --noprofile --norc <<'BASH'
set -euo pipefail

sgt init >/dev/null
mkdir -p "$HOME/sgt/.sgt/rigs" "$HOME/sgt/rigs/demo" "$HOME/sgt/.sgt/plan-state"
printf '%s\n' 'https://github.com/acme/demo' > "$HOME/sgt/.sgt/rigs/demo"

cat > "$HOME/sgt/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 1 },
  "tasks": [
    { "id": "ACC2", "title": "Repo-local continuation reopened", "status": "planned" }
  ]
}
JSON

cat > "$HOME/sgt/.sgt/plan-state/demo.json" <<'JSON'
{
  "tasks": {
    "ACC2": {
      "status": "completed",
      "issue_number": "42",
      "issue_url": "https://github.com/acme/demo/issues/42",
      "completed_at": "2026-04-01T04:52:23Z"
    }
  },
  "completion": {
    "status": "pending",
    "rollup": "tasks-exhausted-awaiting-acceptance",
    "details": "stale carried-over completion"
  }
}
JSON

printf 'STATE=%q\n' 'CLOSED' > "$HOME/state/issues/42.env"

sgt plan tick demo > "$HOME/plan-tick.out" 2>&1
BASH

STATE_FILE="$TMP_HOME/sgt/.sgt/plan-state/demo.json"

python3 - "$STATE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    state = json.load(fh)

task = state["tasks"]["ACC2"]
assert task["status"] in ("dispatched", "in_progress"), task
assert str(task.get("issue_number")) == "1", task
assert "completed_at" not in task, task
PY

grep -q 'dispatched_now=1' "$TMP_HOME/plan-tick.out" || {
  echo "expected reopened repo-local task to dispatch replacement work" >&2
  cat "$TMP_HOME/plan-tick.out" >&2
  exit 1
}

echo "ALL TESTS PASSED"
