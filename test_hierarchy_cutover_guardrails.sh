#!/usr/bin/env bash
# test_hierarchy_cutover_guardrails.sh — Verify per-rig startup retires shared Mayor transient state without touching durable rig truth.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
SESSIONS_FILE="$TMP_ROOT/tmux-sessions"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"
printf 'sgt-mayor\n' > "$SESSIONS_FILE"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail
sessions_file="${SGT_TEST_TMUX_SESSIONS_FILE:?missing SGT_TEST_TMUX_SESSIONS_FILE}"
cmd="${1:-}"
case "$cmd" in
  has-session)
    [[ "${2:-}" == "-t" ]] || exit 1
    grep -qx "${3:-}" "$sessions_file" 2>/dev/null
    ;;
  kill-session)
    [[ "${2:-}" == "-t" ]] || exit 1
    tmp="${sessions_file}.tmp.$$"
    grep -vx "${3:-}" "$sessions_file" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$sessions_file"
    ;;
  new-session)
    session=""
    command_str=""
    while [[ $# -gt 0 ]]; do
      case "${1:-}" in
        -s)
          session="${2:-}"
          shift 2
          ;;
        *)
          command_str="${1:-}"
          shift
          ;;
      esac
    done
    [[ -n "$session" ]] || exit 1
    printf '%s\n' "$session" >> "$sessions_file"
    start_token="$(printf '%s' "$command_str" | sed -n 's/.*SGT_MAYOR_START_TOKEN=\([^ ]*\).*/\1/p')"
    scope_rig="$(printf '%s' "$command_str" | sed -n 's/.*SGT_MAYOR_SCOPE_RIG=\([^ ]*\).*/\1/p')"
    start_token="${start_token%\'}"
    start_token="${start_token#\'}"
    scope_rig="${scope_rig%\'}"
    scope_rig="${scope_rig#\'}"
    if [[ -n "$scope_rig" && "$scope_rig" != "''" ]]; then
      receipt_dir="$HOME/sgt/.sgt/mayors/$scope_rig"
      fifo_path="$receipt_dir/mayor.fifo"
      mkdir -p "$receipt_dir"
      cat > "$receipt_dir/mayor-start.receipt" <<EOF
ATTEMPT=$start_token
PID=999
STARTED_AT=2026-03-31T00:00:00Z
STARTED_EPOCH=1774915200
EOF
      if [[ -p "$fifo_path" ]]; then
        ( timeout 10 cat "$fifo_path" >/dev/null 2>&1 || true ) &
      fi
    fi
    ;;
  *)
    exit 1
    ;;
esac
TMUX
chmod +x "$MOCK_BIN/tmux"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
exit 0
GH
chmod +x "$MOCK_BIN/gh"

ENV_PREFIX=(
  env -i
  HOME="$HOME_DIR"
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin"
  TERM=dumb
  SGT_ROOT="$HOME_DIR/sgt"
  SGT_MAYOR_ARCHITECTURE=per-rig
  SGT_TEST_TMUX_SESSIONS_FILE="$SESSIONS_FILE"
)

"${ENV_PREFIX[@]}" bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs" "$SGT_ROOT/rigs/alpha" "$SGT_ROOT/.sgt/acceptance-blockers/keep" "$SGT_ROOT/.sgt/plan-state" "$SGT_ROOT/.sgt/polecats" "$SGT_ROOT/.sgt/mayors/alpha" "$SGT_ROOT/.sgt/mayor-workspace" "$SGT_ROOT/.sgt/mayor-stale-polecat-fence"
printf "https://github.com/acme/alpha\n" > "$SGT_ROOT/.sgt/rigs/alpha"
printf "shared snapshot\n" > "$SGT_ROOT/.sgt/mayor-dispatch-snapshot.tsv"
printf "shared heartbeat\n" > "$SGT_ROOT/.sgt/mayor-heartbeat.state"
printf "shared review watchdog\n" > "$SGT_ROOT/.sgt/mayor-review-watchdog.state"
printf "shared notify warning\n" > "$SGT_ROOT/.sgt/mayor-notify-alert.state"
printf "shared decision alert\n" > "$SGT_ROOT/.sgt/mayor-decision-log-alert.state"
printf "shared log\n" > "$SGT_ROOT/.sgt/mayor-start.log"
printf "shared durable decisions\n" > "$SGT_ROOT/.sgt/mayor-decisions.log"
printf "plan truth\n" > "$SGT_ROOT/.sgt/plan-state/alpha.json"
printf "blocker truth\n" > "$SGT_ROOT/.sgt/acceptance-blockers/keep/blocker.env"
printf "polecat truth\n" > "$SGT_ROOT/.sgt/polecats/keep.env"
printf "fence\n" > "$SGT_ROOT/.sgt/mayor-stale-polecat-fence/one"
printf "shared workspace\n" > "$SGT_ROOT/.sgt/mayor-workspace/CLAUDE.md"
printf "scoped heartbeat\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-heartbeat.state"
'

"${ENV_PREFIX[@]}" bash --noprofile --norc -c 'set -euo pipefail; timeout 15 sgt mayor start alpha >/dev/null'

if grep -qx 'sgt-mayor' "$SESSIONS_FILE"; then
  echo "expected shared mayor session to be retired during per-rig cutover" >&2
  exit 1
fi
grep -qx 'sgt-mayor-alpha' "$SESSIONS_FILE" || {
  echo "expected scoped mayor session to start after cutover" >&2
  exit 1
}

CUTOVER_DIR="$(find "$HOME_DIR/sgt/.sgt/president/cutovers" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[[ -n "$CUTOVER_DIR" && -d "$CUTOVER_DIR" ]] || {
  echo "expected cutover archive under president runtime dir" >&2
  exit 1
}

[[ -f "$CUTOVER_DIR/cutover.md" ]] || {
  echo "expected cutover summary file" >&2
  exit 1
}
grep -q 'retired_shared_session: true' "$CUTOVER_DIR/cutover.md" || {
  echo "expected cutover summary to record shared session retirement" >&2
  exit 1
}
for archived in mayor-dispatch-snapshot.tsv mayor-heartbeat.state mayor-review-watchdog.state mayor-notify-alert.state mayor-decision-log-alert.state mayor-start.log; do
  [[ -f "$CUTOVER_DIR/$archived" ]] || {
    echo "expected archived shared transient: $archived" >&2
    exit 1
  }
done
[[ -d "$CUTOVER_DIR/mayor-workspace" ]] || {
  echo "expected shared mayor workspace to be archived" >&2
  exit 1
}
[[ -d "$CUTOVER_DIR/mayor-stale-polecat-fence" ]] || {
  echo "expected stale polecat fence to be archived" >&2
  exit 1
}

for removed in mayor-dispatch-snapshot.tsv mayor-heartbeat.state mayor-review-watchdog.state mayor-notify-alert.state mayor-decision-log-alert.state mayor-start.log; do
  [[ ! -e "$HOME_DIR/sgt/.sgt/$removed" ]] || {
    echo "expected shared transient to be removed from live root: $removed" >&2
    exit 1
  }
done
[[ ! -d "$HOME_DIR/sgt/.sgt/mayor-workspace" ]] || {
  echo "expected shared mayor workspace to be removed from live root" >&2
  exit 1
}
[[ ! -d "$HOME_DIR/sgt/.sgt/mayor-stale-polecat-fence" ]] || {
  echo "expected stale polecat fence to be removed from live root" >&2
  exit 1
}

[[ -f "$HOME_DIR/sgt/.sgt/plan-state/alpha.json" ]] || {
  echo "expected plan-state durable truth to remain in place" >&2
  exit 1
}
[[ -f "$HOME_DIR/sgt/.sgt/acceptance-blockers/keep/blocker.env" ]] || {
  echo "expected acceptance blocker durable truth to remain in place" >&2
  exit 1
}
[[ -f "$HOME_DIR/sgt/.sgt/polecats/keep.env" ]] || {
  echo "expected polecat durable truth to remain in place" >&2
  exit 1
}
[[ -f "$HOME_DIR/sgt/.sgt/mayors/alpha/mayor-heartbeat.state" ]] || {
  echo "expected scoped mayor state to remain in place" >&2
  exit 1
}
[[ -f "$HOME_DIR/sgt/.sgt/mayor-decisions.log" ]] || {
  echo "expected shared mayor durable decisions log to remain in place" >&2
  exit 1
}

grep -q 'HIERARCHY_CUTOVER_SHARED_MAYOR retired_session=true' "$HOME_DIR/sgt/sgt.log" || {
  echo "expected durable cutover event log entry" >&2
  exit 1
}

echo "ALL TESTS PASSED"
