#!/usr/bin/env bash
# test_status_rig_activity_live_accounting.sh — Status should not relay stale active_polecats from persisted rig activity state.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail
exit 1
TMUX
chmod +x "$MOCK_BIN/tmux"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
args=" $* "
if [[ "$args" == *" pr list "* && "$args" == *" --json number "* && "$args" == *" --jq "* ]]; then
  echo "0"
  exit 0
fi
if [[ "$args" == *" issue list "* && "$args" == *" --json number "* && "$args" == *" --jq "* ]]; then
  echo "1"
  exit 0
fi
if [[ "$args" == *" pr list "* && "$args" == *" --json number,state,title "* ]]; then
  echo ""
  exit 0
fi
exit 0
GH
chmod +x "$MOCK_BIN/gh"

ENV_PREFIX=(
  env -i
  HOME="$HOME_DIR"
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin"
  TERM=dumb
  SGT_ROOT="$HOME_DIR/sgt"
)

"${ENV_PREFIX[@]}" bash --noprofile --norc <<'BASH'
set -euo pipefail

sgt init >/dev/null
printf 'https://github.com/acme/demo\n' > "$SGT_ROOT/.sgt/rigs/demo"
mkdir -p "$SGT_ROOT/.sgt/mayor-rig-activity"
cat > "$SGT_ROOT/.sgt/mayor-rig-activity/demo.state" <<'STATE'
STATE=active
LAST_REASON=ralph target=3 active_lanes=3 underfilled=0 plan_rollup=ralph-condition-unmet plan_status=pending open_issues=3 open_prs=0 active_polecats=3 merge_queue=0 pending_plan_requests=0
CHANGED_AT=2026-04-02T05:00:00+02:00
CHANGED_EPOCH=1775106000
HIBERNATION_MODE=none
LAST_MEANINGFUL_AT=2026-04-02T05:00:00+02:00
LAST_MEANINGFUL_EPOCH=1775106000
LAST_MEANINGFUL_REASON=stale active_polecats=3
LAST_WAKE_AT=
LAST_WAKE_REASON=
STATE

sgt status --json > "$SGT_ROOT/status.json"
sgt mayor rig-status demo > "$SGT_ROOT/rig-status.txt"

python3 - "$SGT_ROOT/status.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], "r", encoding="utf-8"))
rigs = {entry["rig"]: entry for entry in payload.get("mayor_rigs", [])}
demo = rigs.get("demo")
assert demo is not None, payload
reason = demo.get("reason", "")
assert "active_polecats=0" in reason, demo
assert "active_polecats=3" not in reason, demo
assert payload.get("summary", {}).get("polecat_count") == 0, payload
PY

head -n 1 "$SGT_ROOT/rig-status.txt" | grep -q 'active_polecats=0' || {
  echo "expected mayor rig-status to use live active_polecats=0" >&2
  cat "$SGT_ROOT/rig-status.txt" >&2
  exit 1
}
if head -n 1 "$SGT_ROOT/rig-status.txt" | grep -q 'active_polecats=3'; then
  echo "rig-status relayed stale active_polecats=3" >&2
  cat "$SGT_ROOT/rig-status.txt" >&2
  exit 1
fi
BASH

echo "ALL TESTS PASSED"
