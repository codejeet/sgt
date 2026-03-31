#!/usr/bin/env bash
# Regression: plan tick should reconcile against the authoritative default-branch plan when the rig checkout is dirty or off-branch.

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
exit 0
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
  rev-parse)
    if [[ "${2:-}" == "--abbrev-ref" ]]; then
      echo "stale/operator-snapshot"
    else
      echo "deadbeef"
    fi
    exit 0
    ;;
  status)
    printf ' M SGT_PLAN.json\n'
    exit 0
    ;;
  show)
    if [[ "${2:-}" == "origin/main:SGT_PLAN.json" ]]; then
      cat "${REMOTE_PLAN_FILE:?missing REMOTE_PLAN_FILE}"
      exit 0
    fi
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
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

case "$command:$subcommand" in
  label:create|issue:list|pr:list|issue:edit|pr:view|api:*)
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
  "REMOTE_PLAN_FILE=$TMP_HOME/remote-plan.json"
)

cat > "$TMP_HOME/remote-plan.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "completion_condition": "Close out acceptance from the merged default-branch plan.",
  "acceptance": {
    "status": "verified",
    "details": "The final acceptance PR merged on the default branch.",
    "verified_at": "2026-03-31T10:52:10Z"
  },
  "tasks": [
    { "id": "ACC1", "title": "Resolve acceptance", "depends_on": [] }
  ]
}
JSON

env -i "${COMMON_ENV[@]}" bash --noprofile --norc <<'BASH'
set -euo pipefail

sgt init >/dev/null
mkdir -p "$HOME/sgt/.sgt/rigs" "$HOME/sgt/rigs/demo" "$HOME/sgt/.sgt/plan-state"
printf '%s\n' 'https://github.com/acme/demo' > "$HOME/sgt/.sgt/rigs/demo"

cat > "$HOME/sgt/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "completion_condition": "Local stale plan that should not win.",
  "acceptance": {
    "status": "planned",
    "details": "This stale local checkout still thinks acceptance is unresolved."
  },
  "tasks": [
    { "id": "ACC1", "title": "Resolve acceptance", "depends_on": [] }
  ]
}
JSON

cat > "$HOME/sgt/.sgt/plan-state/demo.json" <<'JSON'
{
  "tasks": {
    "ACC1": {
      "status": "completed",
      "issue_number": "1018",
      "issue_url": "https://github.com/acme/demo/issues/1018",
      "updated_at": "2026-03-31T10:52:54Z"
    }
  },
  "completion": {
    "status": "pending",
    "rollup": "tasks-exhausted-awaiting-acceptance",
    "details": "Stale pending completion carried over from the dirty local plan."
  }
}
JSON

printf 'STATE=%q\n' 'CLOSED' > "$HOME/state/issues/1018.env"

sgt plan tick demo > "$HOME/plan-tick.out" 2>&1
BASH

STATE_FILE="$TMP_HOME/sgt/.sgt/plan-state/demo.json"
LOCAL_PLAN="$TMP_HOME/sgt/rigs/demo/SGT_PLAN.json"
CACHE_PLAN="$TMP_HOME/sgt/.sgt/plan-cache/demo.json"

python3 - "$STATE_FILE" "$LOCAL_PLAN" "$CACHE_PLAN" <<'PY'
import json
import sys

state_file, local_plan_file, cache_plan_file = sys.argv[1:4]

with open(state_file, "r", encoding="utf-8") as fh:
    state = json.load(fh)
with open(local_plan_file, "r", encoding="utf-8") as fh:
    local_plan = json.load(fh)
with open(cache_plan_file, "r", encoding="utf-8") as fh:
    cache_plan = json.load(fh)

completion = state["completion"]
assert completion["status"] == "verified", completion
assert completion["rollup"] == "acceptance-verified", completion
assert completion["details"] == "The final acceptance PR merged on the default branch.", completion
assert completion["acceptance"]["status"] == "verified", completion
assert state["plan_file"].endswith("/sgt/rigs/demo/SGT_PLAN.json"), state["plan_file"]

assert local_plan["acceptance"]["status"] == "planned", local_plan
assert cache_plan["acceptance"]["status"] == "verified", cache_plan
PY

grep -q 'completion=acceptance-verified status=verified' "$TMP_HOME/plan-tick.out" || {
  echo "expected plan tick summary to report verified acceptance from the authoritative default-branch plan" >&2
  cat "$TMP_HOME/plan-tick.out" >&2
  exit 1
}

echo "ALL TESTS PASSED"
