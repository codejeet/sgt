#!/usr/bin/env bash
# test_mayor_startup_validation.sh — Regression checks for mayor bootstrap validation and spawn failure logging.

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

echo "=== mayor startup validation failure logging ==="
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

eval "$(extract_fn _mayor_start_log_file)"
eval "$(extract_fn _mayor_start_failure_state_file)"
eval "$(extract_fn _mayor_start_failure_state_read)"
eval "$(extract_fn _mayor_start_failure_state_write)"
eval "$(extract_fn _mayor_start_validation_timeout_secs)"
eval "$(extract_fn _mayor_start_log_tail)"
eval "$(extract_fn cmd_mayor_start)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
SGT_ROOT="$TMP_ROOT/root"
SGT_CONFIG="$SGT_ROOT/.sgt"
SGT_MAYOR_FIFO="$SGT_CONFIG/mayor.fifo"
SGT_MAYOR_INTERVAL="600"
EVENT_LOG="$TMP_ROOT/events.log"
TMUX_LOG="$TMP_ROOT/tmux.log"
STDERR_LOG="$TMP_ROOT/stderr.log"
mkdir -p "$SGT_CONFIG"
export SGT_ROOT SGT_CONFIG SGT_MAYOR_FIFO SGT_MAYOR_INTERVAL EVENT_LOG TMUX_LOG STDERR_LOG

ensure_init() { :; }
info() { :; }
warn() { echo "$*" >> "$STDERR_LOG"; }
_escape_quotes() { printf '%s' "$1"; }
_escape_wake_value() { printf '%s' "$1"; }
_sgt_exec_path() { printf '%s\n' "/tmp/sgt-worktree/bin/sgt"; }
_mayor_wait_for_start() { return 1; }
log_event() { echo "$*" >> "$EVENT_LOG"; }

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
cmd_mayor_start
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "expected startup validation failure to return non-zero" >&2
  exit 1
fi

if ! grep -q 'MAYOR_SPAWN attempt=mayor-start-' "$EVENT_LOG"; then
  echo "expected structured MAYOR_SPAWN event" >&2
  exit 1
fi
if ! grep -q 'MAYOR_SPAWN_FAILED reason_code=startup-validation-failed' "$EVENT_LOG"; then
  echo "expected explicit mayor spawn failure event" >&2
  exit 1
fi
if ! grep -q 'MAYOR_START_FAILED reason_code=startup-validation-failed' "$EVENT_LOG"; then
  echo "expected explicit mayor start failure event" >&2
  exit 1
fi
if [[ ! -f "$SGT_CONFIG/mayor-start-failure.state" ]]; then
  echo "expected durable mayor startup failure state file" >&2
  exit 1
fi
if ! grep -q 'startup-validation-failed' "$SGT_CONFIG/mayor-start-failure.state"; then
  echo "expected failure state reason code" >&2
  exit 1
fi
if ! grep -q "$SGT_CONFIG/mayor-start.log" "$SGT_CONFIG/mayor-start-failure.state"; then
  echo "expected failure state to include mayor startup log path" >&2
  exit 1
fi
if ! grep -q '/tmp/sgt-worktree/bin/sgt _mayor' "$TMUX_LOG"; then
  echo "expected mayor tmux spawn command to use resolved executable path" >&2
  exit 1
fi
if grep -q ' sgt _mayor' "$TMUX_LOG"; then
  echo "expected mayor tmux spawn command to avoid bare PATH-dependent 'sgt _mayor'" >&2
  exit 1
fi
if ! grep -q 'mayor spawn failed validation' "$STDERR_LOG"; then
  echo "expected operator-visible mayor spawn validation warning" >&2
  exit 1
fi
BASH

echo "ALL TESTS PASSED"
