#!/usr/bin/env bash
# test_plan_completion_acceptance_lifecycle.sh — Regression coverage for deterministic acceptance lifecycle rollups/timestamps.

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
    printf '%s\n' "$*" >> "${TMUX_CALLS_FILE:?missing TMUX_CALLS_FILE}"
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
        printf '%s\n' "${state_value:-}"
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
    exit 0
    ;;
  issue:list)
    exit 0
    ;;
  issue:edit)
    exit 0
    ;;
  api:*)
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
  "TMUX_CALLS_FILE=$TMP_HOME/tmux.calls"
  "SGT_MAYOR_DISPATCH_COOLDOWN=0"
)

env -i "${COMMON_ENV[@]}" bash --noprofile --norc <<'BASH'
set -euo pipefail

sgt init >/dev/null
mkdir -p "$HOME/sgt/.sgt/rigs" "$HOME/sgt/rigs/demo"
printf '%s\n' 'https://github.com/acme/demo' > "$HOME/sgt/.sgt/rigs/demo"
cat > "$HOME/sgt/.sgt/notify.json" <<'JSON'
{"agent":"mayor-bot","channel":"last","reply_to":"sgt-thread"}
JSON
cat > "$HOME/sgt/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 1 },
  "completion_condition": "Run the feature end-to-end on latest main from a fresh state path.",
  "acceptance": {
    "status": "pending",
    "details": "Verify after code lands."
  },
  "tasks": [
    { "id": "spec", "title": "Write the implementation spec" },
    { "id": "impl", "title": "Implement the feature", "depends_on": ["spec"] }
  ]
}
JSON

sgt create plan demo --agent requester-9 "Build the feature from the whitepaper" >/dev/null
sgt plan tick demo >/dev/null 2>&1
BASH

printf 'STATE=%q\nREPO=%q\nTITLE=%q\n' \
  'CLOSED' \
  'https://github.com/acme/demo' \
  'Write the implementation spec' \
  > "$TMP_HOME/state/issues/1.env"

env -i "${COMMON_ENV[@]}" bash --noprofile --norc -c 'sgt plan tick demo >/dev/null 2>&1'

printf 'STATE=%q\nREPO=%q\nTITLE=%q\n' \
  'CLOSED' \
  'https://github.com/acme/demo' \
  'Implement the feature' \
  > "$TMP_HOME/state/issues/2.env"

env -i "${COMMON_ENV[@]}" bash --noprofile --norc -c 'sgt plan tick demo > "$HOME/pending-plan-tick.out" 2>&1'

STATE_FILE="$TMP_HOME/sgt/.sgt/plan-state/demo.json"
[[ -f "$STATE_FILE" ]] || { echo "missing plan state file" >&2; exit 1; }

python3 - "$STATE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
completion = data["completion"]
assert completion["status"] == "pending", completion
assert completion["rollup"] == "tasks-exhausted-awaiting-acceptance", completion
assert completion["details"] == "Verify after code lands.", completion
assert "verified_at" not in completion, completion
assert "blocked_at" not in completion, completion
assert "waived_at" not in completion, completion
PY

cat > "$TMP_HOME/sgt/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 1 },
  "completion_condition": "Run the feature end-to-end on latest main from a fresh state path.",
  "acceptance": {
    "status": "blocked",
    "details": "Fresh-state verification failed after the merge.",
    "blocked_reason": "Checkout remains red on latest main."
  },
  "tasks": [
    { "id": "spec", "title": "Write the implementation spec" },
    { "id": "impl", "title": "Implement the feature", "depends_on": ["spec"] }
  ]
}
JSON

env -i "${COMMON_ENV[@]}" bash --noprofile --norc -c 'sgt plan tick demo > "$HOME/blocked-plan-tick.out" 2>&1'

python3 - "$STATE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
completion = data["completion"]
assert completion["status"] == "blocked", completion
assert completion["rollup"] == "blocked-pending-external", completion
assert completion["details"] == "Fresh-state verification failed after the merge.", completion
assert completion["blocked_reason"] == "Checkout remains red on latest main.", completion
assert completion.get("blocked_at"), completion
assert "verified_at" not in completion, completion
assert "waived_at" not in completion, completion
PY

grep -q 'completion=blocked-pending-external status=blocked' "$TMP_HOME/blocked-plan-tick.out" || {
  echo "expected blocked plan tick summary to include blocked acceptance rollup" >&2
  exit 1
}

cat > "$TMP_HOME/sgt/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 1 },
  "completion_condition": "Run the feature end-to-end on latest main from a fresh state path.",
  "acceptance": {
    "status": "verified",
    "details": "Fresh-state verification now passes on latest main."
  },
  "tasks": [
    { "id": "spec", "title": "Write the implementation spec" },
    { "id": "impl", "title": "Implement the feature", "depends_on": ["spec"] }
  ]
}
JSON

env -i "${COMMON_ENV[@]}" bash --noprofile --norc -c 'sgt plan tick demo > "$HOME/verified-plan-tick.out" 2>&1'

python3 - "$STATE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
completion = data["completion"]
assert completion["status"] == "verified", completion
assert completion["rollup"] == "acceptance-verified", completion
assert completion["details"] == "Fresh-state verification now passes on latest main.", completion
assert completion["blocked_reason"] == "", completion
assert completion.get("verified_at"), completion
assert "blocked_at" not in completion, completion
assert "waived_at" not in completion, completion
PY

grep -q 'completion=acceptance-verified status=verified' "$TMP_HOME/verified-plan-tick.out" || {
  echo "expected verified plan tick summary to include verified acceptance rollup" >&2
  exit 1
}

cat > "$TMP_HOME/sgt/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 1 },
  "completion_condition": "Run the feature end-to-end on latest main from a fresh state path.",
  "acceptance": {
    "status": "waived",
    "details": "Operator waived the manual check for this convoy."
  },
  "tasks": [
    { "id": "spec", "title": "Write the implementation spec" },
    { "id": "impl", "title": "Implement the feature", "depends_on": ["spec"] }
  ]
}
JSON

env -i "${COMMON_ENV[@]}" bash --noprofile --norc -c 'sgt plan tick demo > "$HOME/waived-plan-tick.out" 2>&1'

python3 - "$STATE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
completion = data["completion"]
assert completion["status"] == "waived", completion
assert completion["rollup"] == "acceptance-waived", completion
assert completion["details"] == "Operator waived the manual check for this convoy.", completion
assert completion["blocked_reason"] == "", completion
assert completion.get("waived_at"), completion
assert "verified_at" not in completion, completion
assert "blocked_at" not in completion, completion
PY

grep -q 'completion=acceptance-waived status=waived' "$TMP_HOME/waived-plan-tick.out" || {
  echo "expected waived plan tick summary to include waived acceptance rollup" >&2
  exit 1
}

echo "ALL TESTS PASSED"
