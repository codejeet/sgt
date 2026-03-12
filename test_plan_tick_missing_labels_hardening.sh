#!/usr/bin/env bash
# test_plan_tick_missing_labels_hardening.sh — Plan tick should auto-create required labels before dispatch.

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
    printf '%s\n' "$label" >> "$STATE_DIR/label-create.log"
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
      [[ -f "$LABELS_DIR/$label" ]] || {
        echo "missing label: $label" >&2
        exit 1
      }
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
  issue:list|pr:list|issue:edit|api:*)
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
)

env -i "${COMMON_ENV[@]}" bash --noprofile --norc <<'BASH'
set -euo pipefail

sgt init >/dev/null
mkdir -p "$HOME/sgt/.sgt/rigs" "$HOME/sgt/rigs/demo"
printf '%s\n' 'https://github.com/acme/demo' > "$HOME/sgt/.sgt/rigs/demo"

cat > "$HOME/sgt/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 1 },
  "tasks": [
    {
      "id": "PK50",
      "title": "Expand plan phase",
      "labels": ["custom-phase-label"]
    }
  ]
}
JSON

sgt plan tick demo > "$HOME/plan-tick.out" 2>&1
BASH

STATE_FILE="$TMP_HOME/sgt/.sgt/plan-state/demo.json"
LABEL_LOG="$TMP_HOME/state/label-create.log"

[[ -f "$STATE_FILE" ]] || { echo "expected plan state file" >&2; exit 1; }
grep -qx 'plan' "$LABEL_LOG" || { echo "expected plan label creation" >&2; exit 1; }
grep -qx 'plan-PK50' "$LABEL_LOG" || { echo "expected plan-PK50 label creation" >&2; exit 1; }
grep -qx 'custom-phase-label' "$LABEL_LOG" || { echo "expected custom task label creation" >&2; exit 1; }

python3 - "$STATE_FILE" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
task = data["tasks"]["PK50"]
assert task["status"] in ("dispatched", "in_progress"), task
assert str(task["issue_number"]) == "1", task
PY

echo "ALL TESTS PASSED"
