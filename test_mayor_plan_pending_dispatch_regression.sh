#!/usr/bin/env bash
# test_mayor_plan_pending_dispatch_regression.sh — Mayor should keep advancing pending plans even when the board is empty.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/.local/bin" "$TMP_HOME/mock-bin" "$TMP_HOME/state/issues" "$TMP_HOME/state/labels"
cp "$SGT_SCRIPT" "$TMP_HOME/.local/bin/sgt"
chmod +x "$TMP_HOME/.local/bin/sgt"

cat > "$TMP_HOME/mock-bin/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$TMP_HOME/mock-bin/openclaw"

cat > "$TMP_HOME/mock-bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$TMP_HOME/mock-bin/codex"

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
  repo_dir="$2"
  shift 2
else
  repo_dir="$PWD"
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
          branch="$2"
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
LABELS_DIR="$STATE_DIR/labels"
ISSUES_DIR="$STATE_DIR/issues"
mkdir -p "$LABELS_DIR" "$ISSUES_DIR"

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
    label="${1:-}"
    : > "$LABELS_DIR/$label"
    exit 0
    ;;
  issue:create)
    repo=""
    title=""
    labels=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo) repo="$2"; shift 2 ;;
        --title) title="$2"; shift 2 ;;
        --body) shift 2 ;;
        --label) labels+=("$2"); shift 2 ;;
        *) shift ;;
      esac
    done
    for label in "${labels[@]}"; do
      [[ -f "$LABELS_DIR/$label" ]] || exit 1
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
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --json|--jq) shift 2 ;;
        *) shift ;;
      esac
    done
    printf '%s\n' "${state_value:-OPEN}"
    ;;
  issue:list|pr:list|api:*|issue:edit|pr:view)
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
  "SGT_AI_BACKEND=codex"
  "SGT_MAYOR_INTERVAL=1"
  "SGT_MAYOR_DISPATCH_COOLDOWN=0"
)

env -i "${COMMON_ENV[@]}" bash --noprofile --norc <<'BASH'
set -euo pipefail

sgt init >/dev/null
mkdir -p "$HOME/sgt/.sgt/rigs" "$HOME/sgt/rigs/demo"
printf '%s\n' 'https://github.com/acme/demo' > "$HOME/sgt/.sgt/rigs/demo"

now="$(date -Iseconds)"
cat > "$HOME/sgt/.sgt/deacon-heartbeat.json" <<EOF_HEARTBEAT
{"timestamp":"$now"}
EOF_HEARTBEAT
cat > "$HOME/sgt/.sgt/witness-demo-heartbeat.json" <<EOF_HEARTBEAT
{"timestamp":"$now"}
EOF_HEARTBEAT
cat > "$HOME/sgt/.sgt/refinery-demo-heartbeat.json" <<EOF_HEARTBEAT
{"timestamp":"$now"}
EOF_HEARTBEAT

cat > "$HOME/sgt/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 1 },
  "completion_condition": "Run a manual operator verification on latest main.",
  "acceptance": {
    "status": "pending"
  },
  "tasks": [
    { "id": "PK51", "title": "Continue the convoy on an empty board" }
  ]
}
JSON

sgt _mayor > "$HOME/mayor.out" 2>&1 &
mayor_pid=$!

for _ in $(seq 1 40); do
  [[ -f "$HOME/state/issues/1.env" ]] && break
  sleep 0.25
done

kill "$mayor_pid" 2>/dev/null || true
for _ in $(seq 1 20); do
  if ! kill -0 "$mayor_pid" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
kill -9 "$mayor_pid" 2>/dev/null || true
wait "$mayor_pid" 2>/dev/null || true
BASH

STATE_FILE="$TMP_HOME/sgt/.sgt/plan-state/demo.json"
ISSUE_FILE="$TMP_HOME/state/issues/1.env"

[[ -f "$ISSUE_FILE" ]] || { echo "expected mayor to dispatch pending plan task on empty board" >&2; exit 1; }

python3 - "$STATE_FILE" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
task = data["tasks"]["PK51"]
completion = data["completion"]
assert task["status"] in ("dispatched", "in_progress"), task
assert completion["status"] == "pending", completion
assert completion["rollup"] == "tasks-in-progress", completion
PY

echo "ALL TESTS PASSED"
