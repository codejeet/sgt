#!/usr/bin/env bash
# test_control_plane_scope_env.sh — Control-plane tmux spawns must preserve Mayor architecture scope.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

echo "=== mayor spawn preserves architecture env ==="
bash -s "$SGT_SCRIPT" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _mayor_scope_session_name)"
eval "$(extract_fn _mayor_scope_agent_name)"
eval "$(extract_fn _mayor_scope_dir)"
eval "$(extract_fn _mayor_scope_apply)"
eval "$(extract_fn _sgt_exec_path)"
eval "$(extract_fn _mayor_start_log_file)"
eval "$(extract_fn _mayor_start_failure_state_file)"
eval "$(extract_fn _mayor_start_failure_state_read)"
eval "$(extract_fn _mayor_start_failure_state_write)"
eval "$(extract_fn _mayor_exit_state_file)"
eval "$(extract_fn _mayor_exit_state_write)"
eval "$(extract_fn _mayor_start_validation_timeout_secs)"
eval "$(extract_fn _mayor_start_log_tail)"
eval "$(extract_fn _cmd_mayor_start_one)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
SGT_ROOT="$TMP_ROOT/root"
SGT_CONFIG="$SGT_ROOT/.sgt"
SGT_MAYOR_INTERVAL="600"
SGT_MAYOR_ARCHITECTURE="per-rig"
TMUX_LOG="$TMP_ROOT/tmux.log"
STDERR_LOG="$TMP_ROOT/stderr.log"
EVENT_LOG="$TMP_ROOT/events.log"
mkdir -p "$SGT_CONFIG"
export SGT_ROOT SGT_CONFIG SGT_MAYOR_INTERVAL SGT_MAYOR_ARCHITECTURE TMUX_LOG STDERR_LOG EVENT_LOG

ensure_init() { :; }
info() { :; }
warn() { echo "$*" >> "$STDERR_LOG"; }
log_event() { echo "$*" >> "$EVENT_LOG"; }
_escape_quotes() { printf '%s' "$1"; }
_mayor_wait_for_start() { return 1; }
_sgt_exec_path() { printf '%s\n' "/tmp/sgt-stable/bin/sgt"; }

tmux() {
  if [[ "${1:-}" == "has-session" && "${2:-}" == "-t" ]]; then
    return 1
  fi
  if [[ "${1:-}" == "new-session" ]]; then
    printf '%s\n' "${5:-}" > "$TMUX_LOG"
    return 0
  fi
  return 0
}

set +e
_cmd_mayor_start_one alpha >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "expected startup validation to fail in stubbed environment" >&2
  exit 1
fi
grep -q "SGT_MAYOR_ARCHITECTURE=per-rig" "$TMUX_LOG" || {
  echo "expected mayor spawn command to preserve architecture env" >&2
  exit 1
}
grep -q "SGT_MAYOR_SCOPE_RIG=alpha" "$TMUX_LOG" || {
  echo "expected mayor spawn command to preserve rig scope" >&2
  exit 1
}
BASH

echo "=== deacon spawn preserves architecture env ==="
bash -s "$SGT_SCRIPT" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn cmd_deacon_start)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
SGT_ROOT="$TMP_ROOT/root"
SGT_MAYOR_ARCHITECTURE="per-rig"
TMUX_LOG="$TMP_ROOT/tmux.log"
export SGT_ROOT SGT_MAYOR_ARCHITECTURE TMUX_LOG

ensure_init() { :; }
info() { :; }
log_event() { :; }

tmux() {
  if [[ "${1:-}" == "has-session" && "${2:-}" == "-t" ]]; then
    return 1
  fi
  if [[ "${1:-}" == "new-session" ]]; then
    printf '%s\n' "${5:-}" > "$TMUX_LOG"
    return 0
  fi
  return 0
}

cmd_deacon_start

grep -q "SGT_MAYOR_ARCHITECTURE='per-rig'" "$TMUX_LOG" || {
  echo "expected deacon spawn command to preserve architecture env" >&2
  exit 1
}
BASH

echo "=== daemon spawn preserves architecture env ==="
bash -s "$SGT_SCRIPT" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn cmd_daemon_start)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
SGT_ROOT="$TMP_ROOT/root"
SGT_MAYOR_ARCHITECTURE="per-rig"
SGT_DAEMON_INTERVAL="30"
SGT_DAEMON_PID="$TMP_ROOT/daemon.pid"
TMUX_LOG="$TMP_ROOT/tmux.log"
export SGT_ROOT SGT_MAYOR_ARCHITECTURE SGT_DAEMON_INTERVAL SGT_DAEMON_PID TMUX_LOG

ensure_init() { :; }
info() { :; }

tmux() {
  if [[ "${1:-}" == "new-session" ]]; then
    printf '%s\n' "${5:-}" > "$TMUX_LOG"
    return 0
  fi
  return 1
}

cmd_daemon_start

grep -q "SGT_MAYOR_ARCHITECTURE='per-rig'" "$TMUX_LOG" || {
  echo "expected daemon spawn command to preserve architecture env" >&2
  exit 1
}
BASH

echo "ALL TESTS PASSED"
