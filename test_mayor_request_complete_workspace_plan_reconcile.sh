#!/usr/bin/env bash
# Regression: mayor request complete should reconcile a plan accidentally written under mayor-workspace back into the canonical rig repo path.

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

cat > "$TMP_HOME/mock-bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${GH_STATE_DIR:?missing GH_STATE_DIR}"
mkdir -p "$STATE_DIR"

command="${1:-}"
subcommand="${2:-}"
shift 2 || true

case "$command:$subcommand" in
  label:create)
    printf '%s\n' "${1:-}" >> "$STATE_DIR/label-create.log"
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
mkdir -p "$HOME/sgt/.sgt/rigs" "$HOME/sgt/rigs/demo" "$HOME/sgt/.sgt/mayor-workspace"
printf '%s\n' 'https://github.com/acme/demo' > "$HOME/sgt/.sgt/rigs/demo"

sgt create plan demo --agent requester-9 "Expand the plan into multiple phases" >/dev/null
request_id="$(sgt mayor request list | awk 'NR==1 {print $1}')"
[[ -n "$request_id" ]] || exit 1

cat > "$HOME/sgt/.sgt/mayor-workspace/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 2 },
  "tasks": [
    { "id": "PK60", "title": "Workspace-authored phase" },
    { "id": "PK61", "title": "Follow-up phase", "depends_on": ["PK60"] }
  ]
}
JSON

sgt mayor request complete "$request_id" >/dev/null
BASH

STATE_FILE="$TMP_HOME/sgt/.sgt/plan-state/demo.json"
PLAN_FILE="$TMP_HOME/sgt/rigs/demo/SGT_PLAN.json"
LABEL_LOG="$TMP_HOME/state/label-create.log"
REQUEST_META="$(find "$TMP_HOME/sgt/.sgt/plan-requests" -mindepth 2 -maxdepth 2 -name request.env | head -1)"

[[ -f "$STATE_FILE" ]] || { echo "expected synced plan state after request completion" >&2; exit 1; }
[[ -f "$PLAN_FILE" ]] || { echo "expected canonical rig plan file to be created" >&2; exit 1; }
[[ -f "$REQUEST_META" ]] || { echo "expected request metadata" >&2; exit 1; }
grep -qx 'plan' "$LABEL_LOG" || { echo "expected base plan label creation" >&2; exit 1; }
grep -qx 'plan-PK60' "$LABEL_LOG" || { echo "expected plan-PK60 label creation" >&2; exit 1; }
grep -qx 'plan-PK61' "$LABEL_LOG" || { echo "expected plan-PK61 label creation" >&2; exit 1; }
grep -Fqx "PLAN_FILE=$PLAN_FILE" "$REQUEST_META" || { echo "expected request metadata to point at canonical plan path" >&2; exit 1; }

python3 - "$STATE_FILE" "$PLAN_FILE" <<'PY'
import json, sys
state_file, plan_file = sys.argv[1:3]
with open(state_file, "r", encoding="utf-8") as fh:
    state = json.load(fh)
with open(plan_file, "r", encoding="utf-8") as fh:
    plan = json.load(fh)
assert sorted(state["tasks"].keys()) == ["PK60", "PK61"], state["tasks"]
assert state["tasks"]["PK60"]["status"] == "pending", state["tasks"]["PK60"]
assert state["tasks"]["PK61"]["status"] == "pending", state["tasks"]["PK61"]
assert [task["id"] for task in plan["tasks"]] == ["PK60", "PK61"], plan
PY

echo "ALL TESTS PASSED"
