#!/usr/bin/env bash
# Regression: default plan "pending" status must not reopen a task already completed by merged lineage.

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
command="${1:-}"
subcommand="${2:-}"
shift 2 || true

case "$command:$subcommand" in
  label:create|issue:edit|pr:view|api:*)
    exit 0
    ;;
  issue:list)
    state_filter="open"
    label=""
    json_fields=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --state) state_filter="${2:-}"; shift 2 ;;
        --label) label="${2:-}"; shift 2 ;;
        --json) json_fields="${2:-}"; shift 2 ;;
        --limit|--repo) shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ "$label" == "plan-SGT55" && "$state_filter" == "all" ]]; then
      cat <<'JSON'
[
  {
    "number": 335,
    "url": "https://github.com/acme/demo/issues/335",
    "state": "CLOSED",
    "closedAt": "2026-04-01T04:59:02Z",
    "createdAt": "2026-04-01T04:42:27Z"
  },
  {
    "number": 361,
    "url": "https://github.com/acme/demo/issues/361",
    "state": "CLOSED",
    "closedAt": "2026-04-01T06:26:22Z",
    "createdAt": "2026-04-01T06:23:00Z"
  },
  {
    "number": 364,
    "url": "https://github.com/acme/demo/issues/364",
    "state": "OPEN",
    "closedAt": null,
    "createdAt": "2026-04-01T06:41:52Z"
  }
]
JSON
    elif [[ "$label" == "plan-SGT55" && "$state_filter" == "open" ]]; then
      cat <<'JSON'
[
  {
    "number": 364,
    "url": "https://github.com/acme/demo/issues/364",
    "updatedAt": "2026-04-01T06:41:52Z",
    "createdAt": "2026-04-01T06:41:52Z"
  }
]
JSON
    else
      echo '[]'
    fi
    ;;
  issue:view)
    issue_number="${1:-}"
    issue_number="${issue_number#\#}"
    shift || true
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
      335:state) echo "CLOSED" ;;
      361:state) echo "CLOSED" ;;
      364:state) echo "OPEN" ;;
      *) echo "" ;;
    esac
    ;;
  pr:list)
    cat <<'JSON'
[
  {
    "number": 341,
    "body": "Closes #335",
    "mergedAt": "2026-04-01T04:59:02Z"
  },
  {
    "number": 362,
    "body": "Closes #361",
    "mergedAt": "2026-04-01T06:26:21Z"
  }
]
JSON
    ;;
  issue:create)
    echo "unexpected duplicate issue creation" >&2
    exit 1
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
    { "id": "SGT55", "title": "Define Ralph mode config, state model, and concurrency accounting rules", "status": "pending" }
  ]
}
JSON
cat > "$HOME/sgt/.sgt/plan-state/demo.json" <<'JSON'
{
  "tasks": {
    "SGT55": {
      "issue_number": "364",
      "issue_url": "https://github.com/acme/demo/issues/364",
      "status": "dispatched",
      "updated_at": "2026-04-01T06:41:56Z"
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

task = data["tasks"]["SGT55"]
assert task["status"] == "completed", task
assert str(task.get("issue_number")) == "361", task
assert "completed_at" in task, task
assert task.get("reopen_requested") is False, task
PY

grep -q 'PLAN_TASK_RETAIN_MERGED_LINEAGE rig=demo task=SGT55 issue=#361 pr=#362 merged_at=2026-04-01T06:26:21Z source=manual' "$TMP_HOME/sgt/sgt.log" || {
  echo "expected merged-lineage retention log entry" >&2
  cat "$TMP_HOME/sgt/sgt.log" >&2
  exit 1
}

grep -q 'dispatched_now=0' "$TMP_HOME/plan-tick.out" || {
  echo "expected duplicate completed task to avoid fresh dispatch" >&2
  cat "$TMP_HOME/plan-tick.out" >&2
  exit 1
}

echo "ALL TESTS PASSED"
