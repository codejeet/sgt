#!/usr/bin/env bash
# Regression: plan tick should clear a stale open plan-task issue when the task changed materially and dispatch the fresh successor instead.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/.local/bin" "$TMP_HOME/mock-bin" "$TMP_HOME/state"
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
  branch)
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$TMP_HOME/mock-bin/git"

cat > "$TMP_HOME/mock-bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}:${2:-}" in
  label:create|issue:edit|pr:view|api:*)
    exit 0
    ;;
  issue:list)
    label=""
    state_filter="open"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --label) label="${2:-}"; shift 2 ;;
        --state) state_filter="${2:-}"; shift 2 ;;
        --json|--repo|--limit) shift 2 ;;
        --jq) shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ "$label" == "plan-PKNXT-15" && "$state_filter" == "all" ]]; then
      echo '[]'
    else
      echo '[]'
    fi
    ;;
  issue:view)
    issue_number="${3:-}"
    issue_number="${issue_number#\#}"
    shift 3
    json_fields=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --json) json_fields="${2:-}"; shift 2 ;;
        --jq) shift 2 ;;
        --repo) shift 2 ;;
        *) shift ;;
      esac
    done
    case "$issue_number:$json_fields" in
      1095:state) echo "OPEN" ;;
      *) echo "" ;;
    esac
    ;;
  pr:list)
    echo '[]'
    ;;
  issue:create)
    echo "https://github.com/acme/demo/issues/1097"
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
  "SGT_MAYOR_DISPATCH_COOLDOWN=0"
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
    { "id": "PKNXT-15", "title": "Implement and evaluate late_expiry_taker_h5_h10_passive_improvement_proof_subset_lane as the primary widened-corpus continuation lane", "status": "pending" }
  ]
}
JSON
cat > "$HOME/sgt/.sgt/plan-state/demo.json" <<'JSON'
{
  "tasks": {
    "PKNXT-15": {
      "issue_number": "1095",
      "issue_url": "https://github.com/acme/demo/issues/1095",
      "status": "dispatched",
      "task_signature": "old-confidence-lift-signature",
      "updated_at": "2026-04-01T09:47:00Z"
    }
  }
}
JSON

sgt plan tick demo > "$HOME/plan-tick.out" 2>&1
BASH

STATE_FILE="$TMP_HOME/sgt/.sgt/plan-state/demo.json"

python3 - "$STATE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)

task = data["tasks"]["PKNXT-15"]
assert task["status"] == "dispatched", task
assert str(task.get("issue_number")) == "1097", task
assert task.get("task_signature_changed") is False, task
PY

grep -q 'PLAN_TASK_CLEAR_STALE_ISSUE_BINDING rig=demo task=PKNXT-15 previous_issue=#1095 reason_code=material-task-change issue_state=OPEN source=manual' "$TMP_HOME/sgt/sgt.log" || {
  echo "expected stale open issue binding to be cleared" >&2
  cat "$TMP_HOME/sgt/sgt.log" >&2
  exit 1
}

grep -q 'dispatched_now=1' "$TMP_HOME/plan-tick.out" || {
  echo "expected fresh successor dispatch after stale open issue clear" >&2
  cat "$TMP_HOME/plan-tick.out" >&2
  exit 1
}

echo "ALL TESTS PASSED"
