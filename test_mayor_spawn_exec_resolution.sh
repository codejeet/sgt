#!/usr/bin/env bash
# test_mayor_spawn_exec_resolution.sh — Regression checks for stable mayor exec resolution + spawn failure telemetry.

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

echo "=== mayor spawn prefers stable PATH executable over polecat worktree script ==="
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

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
RUNTIME_ROOT="$TMP_ROOT/runtime"
POLECAT_DIR="$RUNTIME_ROOT/polecats/sgt-issue-189"
PATH_BIN="$TMP_ROOT/bin"
mkdir -p "$POLECAT_DIR" "$PATH_BIN"

cat > "$PATH_BIN/sgt" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$PATH_BIN/sgt"

cat > "$POLECAT_DIR/run.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
SGT_SCRIPT="$SGT_SCRIPT"
PATH="$PATH_BIN:\$PATH"

extract_fn() {
  local name="\$1"
  awk -v n="\$name" '
    \$0 ~ "^" n "\\\\(\\\\) \\\\{" {in_fn=1}
    in_fn {print}
    in_fn && \$0 == "}" {exit}
  ' "\$SGT_SCRIPT"
}

eval "\$(extract_fn _sgt_exec_path)"
eval "\$(extract_fn _mayor_start_log_file)"
eval "\$(extract_fn _mayor_start_failure_state_file)"
eval "\$(extract_fn _mayor_start_failure_state_read)"
eval "\$(extract_fn _mayor_start_failure_state_write)"
eval "\$(extract_fn _mayor_start_validation_timeout_secs)"
eval "\$(extract_fn _mayor_start_log_tail)"
eval "\$(extract_fn cmd_mayor_start)"

SGT_ROOT="$RUNTIME_ROOT"
SGT_CONFIG="\$SGT_ROOT/.sgt"
SGT_MAYOR_FIFO="\$SGT_CONFIG/mayor.fifo"
SGT_MAYOR_INTERVAL="600"
EVENT_LOG="$TMP_ROOT/events.log"
TMUX_LOG="$TMP_ROOT/tmux.log"
STDERR_LOG="$TMP_ROOT/stderr.log"
mkdir -p "\$SGT_CONFIG"
export PATH SGT_ROOT SGT_CONFIG SGT_MAYOR_FIFO SGT_MAYOR_INTERVAL EVENT_LOG TMUX_LOG STDERR_LOG

ensure_init() { :; }
info() { :; }
warn() { echo "\$*" >> "\$STDERR_LOG"; }
_escape_quotes() { printf '%s' "\$1"; }
_escape_wake_value() { printf '%s' "\$1"; }
_mayor_wait_for_start() { return 1; }
log_event() { echo "\$*" >> "\$EVENT_LOG"; }

tmux() {
  if [[ "\${1:-}" == "has-session" && "\${2:-}" == "-t" ]]; then
    return 1
  fi
  if [[ "\${1:-}" == "new-session" ]]; then
    printf '%s\n' "\${5:-}" > "\$TMUX_LOG"
    return 0
  fi
  return 0
}

set +e
cmd_mayor_start
rc=\$?
set -e

if [[ "\$rc" -eq 0 ]]; then
  echo "expected startup validation failure in stubbed environment" >&2
  exit 1
fi
EOF
chmod +x "$POLECAT_DIR/run.sh"

"$POLECAT_DIR/run.sh"

if ! grep -q "$PATH_BIN/sgt _mayor" "$TMP_ROOT/tmux.log"; then
  echo "expected mayor spawn command to use stable PATH executable" >&2
  exit 1
fi
if grep -q "$POLECAT_DIR/run.sh _mayor" "$TMP_ROOT/tmux.log"; then
  echo "expected mayor spawn command to avoid ephemeral polecat worktree script path" >&2
  exit 1
fi
BASH

echo "=== mayor spawn failure logs explicit tmux failure telemetry ==="
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

eval "$(extract_fn _sgt_exec_path)"
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
STDERR_LOG="$TMP_ROOT/stderr.log"
mkdir -p "$SGT_CONFIG"
export SGT_ROOT SGT_CONFIG SGT_MAYOR_FIFO SGT_MAYOR_INTERVAL EVENT_LOG STDERR_LOG

ensure_init() { :; }
info() { :; }
warn() { echo "$*" >> "$STDERR_LOG"; }
_escape_quotes() { printf '%s' "$1"; }
_escape_wake_value() { printf '%s' "$1"; }
_mayor_wait_for_start() { return 1; }
log_event() { echo "$*" >> "$EVENT_LOG"; }
_sgt_exec_path() { printf '%s\n' "/tmp/sgt-stable/bin/sgt"; }

tmux() {
  if [[ "${1:-}" == "has-session" && "${2:-}" == "-t" ]]; then
    return 1
  fi
  if [[ "${1:-}" == "new-session" ]]; then
    echo "no server running on /tmp/tmux-999/default" >&2
    return 1
  fi
  return 0
}

set +e
cmd_mayor_start
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "expected tmux startup failure to return non-zero" >&2
  exit 1
fi
if ! grep -q 'MAYOR_SPAWN attempt=mayor-start-' "$EVENT_LOG"; then
  echo "expected structured MAYOR_SPAWN event before tmux failure" >&2
  exit 1
fi
if ! grep -q 'MAYOR_SPAWN_FAILED reason_code=tmux-new-session-failed' "$EVENT_LOG"; then
  echo "expected explicit tmux spawn failure event" >&2
  exit 1
fi
if grep -q 'MAYOR_START_FAILED' "$EVENT_LOG"; then
  echo "did not expect startup-validation telemetry when tmux spawn itself failed" >&2
  exit 1
fi
if [[ ! -f "$SGT_CONFIG/mayor-start-failure.state" ]]; then
  echo "expected durable mayor startup failure state for tmux failure" >&2
  exit 1
fi
if ! grep -q 'tmux-new-session-failed' "$SGT_CONFIG/mayor-start-failure.state"; then
  echo "expected tmux failure reason code in state file" >&2
  exit 1
fi
if ! grep -q 'mayor spawn failed before startup validation' "$STDERR_LOG"; then
  echo "expected operator-visible tmux startup failure warning" >&2
  exit 1
fi
BASH

echo "ALL TESTS PASSED"
