#!/usr/bin/env bash
# Regression: plan tick should reconcile merged issue-backed work even if GitHub issue close state lags.

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
printf '%s\n' "$*" >> "${OPENCLAW_CALLS_FILE:?missing OPENCLAW_CALLS_FILE}"
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
MERGED_PRS_JSON="$STATE_DIR/merged-prs.json"
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
  label:create)
    exit 0
    ;;
  issue:create)
    repo=""
    title=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo) repo="$2"; shift 2 ;;
        --title) title="$2"; shift 2 ;;
        --body) shift 2 ;;
        --label) shift 2 ;;
        *) shift ;;
      esac
    done
    issue_number="$(next_issue)"
    printf 'STATE=%q\nREPO=%q\nTITLE=%q\n' "OPEN" "$repo" "$title" > "$ISSUES_DIR/$issue_number.env"
    echo "${repo}/issues/${issue_number}"
    ;;
  issue:view)
    issue_number="${1:-}"
    issue_number="${issue_number#\#}"
    issue_file="$ISSUES_DIR/$issue_number.env"
    [[ -f "$issue_file" ]] || exit 1
    state_value="$(sed -n 's/^STATE=//p' "$issue_file" | head -1)"
    title_value="$(sed -n 's/^TITLE=//p' "$issue_file" | head -1)"
    json=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --json) json="$2"; shift 2 ;;
        --jq) shift 2 ;;
        *) shift ;;
      esac
    done
    case "$json" in
      *state*)
        printf '%s\n' "${state_value:-OPEN}"
        ;;
      *title*)
        printf '%s\n' "${title_value:-}"
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  pr:list)
    if [[ -f "$MERGED_PRS_JSON" ]]; then
      cat "$MERGED_PRS_JSON"
    else
      echo '[]'
    fi
    ;;
  issue:list|issue:edit|pr:view|api:*)
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
  "OPENCLAW_CALLS_FILE=$TMP_HOME/openclaw.calls"
  "SGT_MAYOR_DISPATCH_COOLDOWN=0"
)

env -i "${COMMON_ENV[@]}" bash --noprofile --norc <<'BASH'
set -euo pipefail

sgt init >/dev/null
mkdir -p "$HOME/sgt/.sgt/rigs" "$HOME/sgt/rigs/demo" "$HOME/sgt/.sgt/plan-state"
printf '%s\n' 'https://github.com/acme/demo' > "$HOME/sgt/.sgt/rigs/demo"
cat > "$HOME/sgt/.sgt/notify.json" <<'JSON'
{"agent":"mayor-bot","channel":"last","reply_to":"sgt-thread"}
JSON
cat > "$HOME/sgt/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 1 },
  "completion_condition": "Keep dispatching until the convoy is complete on latest main.",
  "acceptance": {
    "status": "pending",
    "details": "Verify after the plan graph empties."
  },
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
      "status": "in_progress",
      "updated_at": "2026-03-24T12:10:00Z"
    },
    "PKOC3": {
      "status": "pending",
      "updated_at": "2026-03-24T12:10:00Z"
    }
  }
}
JSON
printf 'STATE=%q\nREPO=%q\nTITLE=%q\n' \
  'OPEN' \
  'https://github.com/acme/demo' \
  'Record onchain dispatcher readiness' \
  > "$HOME/state/issues/540.env"
cat > "$HOME/state/merged-prs.json" <<'JSON'
[
  {
    "body": "Closes #540",
    "mergedAt": "2026-03-24T12:12:37Z",
    "number": 541
  }
]
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
completion = data["completion"]

assert pkoc2["status"] == "completed", pkoc2
assert str(pkoc2.get("issue_number")) == "540", pkoc2
assert pkoc3["status"] in ("dispatched", "in_progress"), pkoc3
assert str(pkoc3.get("issue_number")) == "1", pkoc3
assert completion["status"] == "pending", completion
assert completion["rollup"] == "tasks-in-progress", completion
PY

grep -q 'completion=tasks-in-progress status=pending' "$TMP_HOME/plan-tick.out" || {
  echo "expected plan tick summary to report continued in-progress completion state" >&2
  exit 1
}

echo "ALL TESTS PASSED"
