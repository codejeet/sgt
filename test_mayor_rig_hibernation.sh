#!/usr/bin/env bash
# test_mayor_rig_hibernation.sh — Per-rig mayor activity, manual hibernation, and event wake regression.

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

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  echo "0"
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  echo "0"
  exit 0
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
chmod +x "$MOCK_BIN/gh"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

SESSIONS_DIR="${SGT_TMUX_SESSIONS_DIR:?}"

if [[ "${1:-}" == "has-session" ]]; then
  [[ "${2:-}" == "-t" ]] || exit 1
  [[ -f "$SESSIONS_DIR/${3:-}" ]]
  exit $?
fi

if [[ "${1:-}" == "new-session" ]]; then
  session=""
  shift
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      -s)
        session="${2:-}"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  [[ -n "$session" ]] || exit 1
  : > "$SESSIONS_DIR/$session"
  exit 0
fi

if [[ "${1:-}" == "kill-session" ]]; then
  [[ "${2:-}" == "-t" ]] || exit 1
  rm -f "$SESSIONS_DIR/${3:-}"
  exit 0
fi

echo "mock tmux unsupported: $*" >&2
exit 1
TMUX
chmod +x "$MOCK_BIN/tmux"

COMMON_ENV=(
  env -i
  HOME="$HOME_DIR"
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin"
  TERM="${TERM:-xterm}"
  SGT_ROOT="$HOME_DIR/sgt"
  SGT_TMUX_SESSIONS_DIR="$TMP_ROOT/tmux-sessions"
)

"${COMMON_ENV[@]}" bash --noprofile --norc <<'BASH'
set -euo pipefail

sgt init >/dev/null
printf 'https://github.com/acme/demo\n' > "$SGT_ROOT/.sgt/rigs/demo"
mkdir -p "$SGT_TMUX_SESSIONS_DIR"
: > "$SGT_TMUX_SESSIONS_DIR/sgt-witness-demo"
: > "$SGT_TMUX_SESSIONS_DIR/sgt-refinery-demo"

sgt mayor hibernate demo "quiet window" >/tmp/sgt-mayor-hibernate.out
status_line="$(sgt mayor rig-status demo)"
[[ "$status_line" == *"state=hibernated"* ]]
[[ "$status_line" == *"mode=manual"* ]]
[[ "$status_line" == *"reason=quiet window"* ]]
[[ ! -f "$SGT_TMUX_SESSIONS_DIR/sgt-witness-demo" ]]
[[ ! -f "$SGT_TMUX_SESSIONS_DIR/sgt-refinery-demo" ]]

json_file="$HOME/status.json"
sgt status --json > "$json_file"
python3 - "$json_file" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], "r", encoding="utf-8"))
rigs = {entry["rig"]: entry for entry in payload["mayor_rigs"]}
demo = rigs["demo"]
assert demo["state"] == "hibernated", demo
assert demo["hibernation_mode"] == "manual", demo
assert demo["reason"] == "quiet window", demo
PY

sgt mayor unhibernate demo "resume work" >/tmp/sgt-mayor-unhibernate.out
status_line="$(sgt mayor rig-status demo)"
[[ "$status_line" == *"state=idle"* ]]
[[ "$status_line" == *"mode=none"* ]]
[[ "$status_line" == *"reason=resume work"* ]]
[[ -f "$SGT_TMUX_SESSIONS_DIR/sgt-witness-demo" ]]
[[ -f "$SGT_TMUX_SESSIONS_DIR/sgt-refinery-demo" ]]
BASH

bash -s "$SGT_SCRIPT" "$TMP_ROOT" <<'BASH'
set -euo pipefail

SGT_SCRIPT="$1"
TMP_ROOT="$2"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _one_line)"
eval "$(extract_fn _escape_quotes)"
eval "$(extract_fn _escape_wake_value)"
eval "$(extract_fn log_event)"
eval "$(extract_fn _mayor_rig_activity_enabled)"
eval "$(extract_fn _mayor_rig_activity_file)"
eval "$(extract_fn _mayor_rig_activity_state_read)"
eval "$(extract_fn _mayor_rig_activity_state_write)"
eval "$(extract_fn _mayor_wake_reason_is_meaningful)"
eval "$(extract_fn _mayor_rig_hibernated)"
eval "$(extract_fn _rig_hibernation_sync_agents)"
eval "$(extract_fn _mayor_rig_set_manual_hibernation)"
eval "$(extract_fn _mayor_rig_maybe_unhibernate_for_event)"

export SGT_CONFIG="$TMP_ROOT/helper-config"
export SGT_MAYOR_RIG_ACTIVITY_DIR="$SGT_CONFIG/mayor-rig-activity"
export SGT_LOG="$TMP_ROOT/helper.log"
mkdir -p "$SGT_CONFIG"

SYNC_LOG="$TMP_ROOT/sync.log"
cmd_witness_stop() { echo "witness-stop:$1" >> "$SYNC_LOG"; }
cmd_refinery_stop() { echo "refinery-stop:$1" >> "$SYNC_LOG"; }
cmd_refinery_start() { echo "refinery-start:$1" >> "$SYNC_LOG"; }
cmd_witness_start() { echo "witness-start:$1" >> "$SYNC_LOG"; }
tmux() { return 1; }

_mayor_rig_set_manual_hibernation demo hibernate "manual pause"
_mayor_rig_hibernated demo

_mayor_rig_maybe_unhibernate_for_event demo 'merged:pr#77:#40:demo|repo=acme/demo|title=Wake'
IFS='|' read -r state reason _changed_at _changed_epoch mode _meaningful_at _meaningful_epoch _meaningful_reason _wake_at _wake_reason <<< "$(_mayor_rig_activity_state_read demo)"
[[ "$state" == "idle" ]]
[[ "$mode" == "none" ]]
[[ "$reason" == "auto-wake: merged:pr#77:#40:demo"* ]]
grep -q '^refinery-start:demo$' "$SYNC_LOG"
grep -q '^witness-start:demo$' "$SYNC_LOG"
BASH

echo "PASS: mayor rig hibernation regression"
