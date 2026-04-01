#!/usr/bin/env bash
# Regression: plan tick should bind to an explicit open plan-task issue instead of recreating the lane.

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
  new-session)
    exit 0
    ;;
  kill-session)
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
          worktree="$3"
        else
          worktree="$1"
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

case "${1:-}:${2:-}" in
  label:create)
    exit 0
    ;;
  issue:list)
    label=""
    state_filter="open"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --label) label="${2:-}"; shift 2 ;;
        --state) state_filter="${2:-}"; shift 2 ;;
        --json) shift 2 ;;
        --limit) shift 2 ;;
        --repo) shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ "$label" == "plan-PKOC2" && "$state_filter" == "open" ]]; then
      cat <<JSON
[
  {
    "number": 542,
    "url": "https://github.com/acme/demo/issues/542",
    "updatedAt": "2026-04-01T06:45:00Z",
    "createdAt": "2026-04-01T06:40:00Z"
  }
]
JSON
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
      540:state) echo "CLOSED" ;;
      542:state) echo "OPEN" ;;
      542:title) echo "Canonical successor issue" ;;
      *) echo "" ;;
    esac
    ;;
  pr:list)
    echo '[]'
    ;;
  issue:create)
    echo "unexpected duplicate issue creation" >&2
    exit 1
    ;;
  issue:edit|pr:view|api:*)
    exit 0
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
    { "id": "PKOC2", "title": "Record onchain dispatcher readiness" },
    { "id": "PKOC3", "title": "Dispatch the next ready control-plane task", "depends_on": ["PKOC2"] }
  ]
}
JSON
cat > "$HOME/sgt/.sgt/plan-state/demo.json" <<'JSON'
{
  "tasks": {
    "PKOC2": {
      "issue_number": "540",
      "issue_url": "https://github.com/acme/demo/issues/540",
      "status": "completed",
      "completed_at": "2026-04-01T06:35:00Z",
      "updated_at": "2026-04-01T06:35:00Z"
    },
    "PKOC3": {
      "status": "pending",
      "updated_at": "2026-04-01T06:35:00Z"
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

pkoc2 = data["tasks"]["PKOC2"]
pkoc3 = data["tasks"]["PKOC3"]

assert pkoc2["status"] in ("dispatched", "in_progress"), pkoc2
assert str(pkoc2.get("issue_number")) == "542", pkoc2
assert "completed_at" not in pkoc2, pkoc2
assert pkoc3["status"] == "pending", pkoc3
PY

grep -q 'PLAN_TASK_CANONICAL_ISSUE_BIND rig=demo task=PKOC2 issue=#542 previous_issue=#540 previous_status=completed source=manual' "$TMP_HOME/sgt/sgt.log" || {
  echo "expected canonical issue bind log entry" >&2
  exit 1
}

echo "ALL TESTS PASSED"
