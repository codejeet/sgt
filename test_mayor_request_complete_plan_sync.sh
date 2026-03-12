#!/usr/bin/env bash
# test_mayor_request_complete_plan_sync.sh — Completing a plan request should sync plan-state and create future plan labels.

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
mkdir -p "$HOME/sgt/.sgt/rigs" "$HOME/sgt/rigs/demo"
printf '%s\n' 'https://github.com/acme/demo' > "$HOME/sgt/.sgt/rigs/demo"

sgt create plan demo --agent requester-9 "Expand the plan into multiple phases" >/dev/null
request_id="$(sgt mayor request list | awk 'NR==1 {print $1}')"
[[ -n "$request_id" ]] || exit 1

cat > "$HOME/sgt/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 2 },
  "tasks": [
    { "id": "PK50", "title": "First expanded phase" },
    { "id": "PK51", "title": "Second expanded phase", "depends_on": ["PK50"] }
  ]
}
JSON

sgt mayor request complete "$request_id" >/dev/null
BASH

STATE_FILE="$TMP_HOME/sgt/.sgt/plan-state/demo.json"
LABEL_LOG="$TMP_HOME/state/label-create.log"

[[ -f "$STATE_FILE" ]] || { echo "expected synced plan state after request completion" >&2; exit 1; }
grep -qx 'plan' "$LABEL_LOG" || { echo "expected base plan label creation" >&2; exit 1; }
grep -qx 'plan-PK50' "$LABEL_LOG" || { echo "expected plan-PK50 label creation" >&2; exit 1; }
grep -qx 'plan-PK51' "$LABEL_LOG" || { echo "expected plan-PK51 label creation" >&2; exit 1; }

python3 - "$STATE_FILE" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
assert sorted(data["tasks"].keys()) == ["PK50", "PK51"], data["tasks"]
assert data["tasks"]["PK50"]["status"] == "pending", data["tasks"]["PK50"]
assert data["tasks"]["PK51"]["status"] == "pending", data["tasks"]["PK51"]
PY

echo "ALL TESTS PASSED"
