#!/usr/bin/env bash
# test_mayor_refresh.sh — Verify mayor refresh archives transient state into a handoff and restarts scoped mayor sessions.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

make_mock_bin() {
  local mock_bin="$1"
  local sessions_file="$2"
  mkdir -p "$mock_bin"

  cat > "$mock_bin/tmux" <<'TMUX'
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
    else
      receipt_dir="$HOME/sgt/.sgt"
      fifo_path="$receipt_dir/mayor.fifo"
    fi
    mkdir -p "$receipt_dir"
    cat > "$receipt_dir/mayor-start.receipt" <<EOF
ATTEMPT=$start_token
PID=999
STARTED_AT=2026-03-30T00:00:00Z
STARTED_EPOCH=1774828800
EOF
    if [[ -p "$fifo_path" ]]; then
      ( timeout 10 cat "$fifo_path" >/dev/null 2>&1 || true ) &
    fi
    ;;
  *)
    exit 1
    ;;
esac
TMUX
  chmod +x "$mock_bin/tmux"

  cat > "$mock_bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
exit 0
GH
  chmod +x "$mock_bin/gh"
}

run_env() {
  local home_dir="$1"
  local sessions_file="$2"
  shift 2
  env -i \
    HOME="$home_dir" \
    PATH="$home_dir/.local/bin:$TMP_ROOT/mockbin:/usr/local/bin:/usr/bin:/bin" \
    TERM=dumb \
    SGT_ROOT="$home_dir/sgt" \
    SGT_TEST_TMUX_SESSIONS_FILE="$sessions_file" \
    "$@"
}

assert_file() {
  local path="$1"
  [[ -f "$path" ]] || {
    echo "expected file: $path" >&2
    exit 1
  }
}

assert_dir_missing() {
  local path="$1"
  [[ ! -d "$path" ]] || {
    echo "expected directory to be removed: $path" >&2
    exit 1
  }
}

assert_file_missing() {
  local path="$1"
  [[ ! -f "$path" ]] || {
    echo "expected file to be removed: $path" >&2
    exit 1
  }
}

mkdir -p "$TMP_ROOT/mockbin"

echo "=== shared mayor refresh ==="
SHARED_HOME="$TMP_ROOT/shared-home"
SHARED_SESSIONS="$TMP_ROOT/shared-sessions"
mkdir -p "$SHARED_HOME/.local/bin"
cp "$SGT_SCRIPT" "$SHARED_HOME/.local/bin/sgt"
chmod +x "$SHARED_HOME/.local/bin/sgt"
printf 'sgt-mayor\n' > "$SHARED_SESSIONS"
make_mock_bin "$TMP_ROOT/mockbin" "$SHARED_SESSIONS"

run_env "$SHARED_HOME" "$SHARED_SESSIONS" bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/mayor-workspace"
printf "briefing\n" > "$SGT_ROOT/.sgt/mayor-briefing.md"
printf "snapshot\n" > "$SGT_ROOT/.sgt/mayor-dispatch-snapshot.tsv"
printf "status=running\n" > "$SGT_ROOT/.sgt/mayor-ai-cycle.state"
printf "ATTEMPT=abc\n" > "$SGT_ROOT/.sgt/mayor-start.receipt"
printf "spawn log\n" > "$SGT_ROOT/.sgt/mayor-start.log"
printf "1|startup-failed|attempt|log|detail\n" > "$SGT_ROOT/.sgt/mayor-start-failure.state"
printf "decision\n" > "$SGT_ROOT/.sgt/mayor-decisions.log"
printf "notes\n" > "$SGT_ROOT/.sgt/mayor-workspace/CLAUDE.md"
'

SHARED_OUT="$TMP_ROOT/shared-refresh.out"
run_env "$SHARED_HOME" "$SHARED_SESSIONS" bash --noprofile --norc -c 'set -euo pipefail; timeout 15 sgt mayor refresh' > "$SHARED_OUT"
shared_handoff="$(tail -n 1 "$SHARED_OUT")"
assert_file "$shared_handoff"
assert_file "$(dirname "$shared_handoff")/mayor-briefing.md"
assert_file "$(dirname "$shared_handoff")/mayor-dispatch-snapshot.tsv"
assert_file "$(dirname "$shared_handoff")/mayor-ai-cycle.state"
assert_file "$(dirname "$shared_handoff")/mayor-start.receipt"
assert_file "$(dirname "$shared_handoff")/mayor-start.log"
assert_file "$(dirname "$shared_handoff")/mayor-start-failure.state"
assert_file "$(dirname "$shared_handoff")/mayor-workspace/CLAUDE.md"
assert_file "$SHARED_HOME/sgt/.sgt/mayor-decisions.log"
assert_file_missing "$SHARED_HOME/sgt/.sgt/mayor-briefing.md"
assert_dir_missing "$SHARED_HOME/sgt/.sgt/mayor-workspace"
grep -qx 'sgt-mayor' "$SHARED_SESSIONS" || {
  echo "expected shared mayor session to be restarted" >&2
  exit 1
}
grep -q '^# Mayor Refresh Handoff$' "$shared_handoff" || {
  echo "expected handoff title in shared handoff" >&2
  exit 1
}
grep -q 'mayor_was_running: true' "$shared_handoff" || {
  echo "expected shared handoff to note running mayor" >&2
  exit 1
}

echo "=== per-rig mayor refresh ==="
RIG_HOME="$TMP_ROOT/per-rig-home"
RIG_SESSIONS="$TMP_ROOT/per-rig-sessions"
mkdir -p "$RIG_HOME/.local/bin"
cp "$SGT_SCRIPT" "$RIG_HOME/.local/bin/sgt"
chmod +x "$RIG_HOME/.local/bin/sgt"
printf 'sgt-mayor-alpha\nsgt-mayor-beta\n' > "$RIG_SESSIONS"

run_env "$RIG_HOME" "$RIG_SESSIONS" bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs" "$SGT_ROOT/rigs/alpha" "$SGT_ROOT/rigs/beta"
printf "https://github.com/acme/alpha\n" > "$SGT_ROOT/.sgt/rigs/alpha"
printf "https://github.com/acme/beta\n" > "$SGT_ROOT/.sgt/rigs/beta"
mkdir -p "$SGT_ROOT/.sgt/mayors/alpha/mayor-workspace" "$SGT_ROOT/.sgt/mayors/beta/mayor-workspace"
printf "alpha briefing\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-briefing.md"
printf "beta briefing\n" > "$SGT_ROOT/.sgt/mayors/beta/mayor-briefing.md"
printf "alpha notes\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-workspace/CLAUDE.md"
printf "beta notes\n" > "$SGT_ROOT/.sgt/mayors/beta/mayor-workspace/CLAUDE.md"
printf "alpha decision\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-decisions.log"
printf "beta decision\n" > "$SGT_ROOT/.sgt/mayors/beta/mayor-decisions.log"
'

RIG_OUT="$TMP_ROOT/per-rig-refresh.out"
run_env "$RIG_HOME" "$RIG_SESSIONS" SGT_MAYOR_ARCHITECTURE=per-rig bash --noprofile --norc -c 'set -euo pipefail; timeout 15 sgt mayor refresh alpha' > "$RIG_OUT"
rig_handoff="$(tail -n 1 "$RIG_OUT")"
assert_file "$rig_handoff"
assert_file "$(dirname "$rig_handoff")/mayor-briefing.md"
assert_file "$(dirname "$rig_handoff")/mayor-workspace/CLAUDE.md"
assert_file "$RIG_HOME/sgt/.sgt/mayors/alpha/mayor-decisions.log"
assert_file "$RIG_HOME/sgt/.sgt/mayors/beta/mayor-briefing.md"
assert_file "$RIG_HOME/sgt/.sgt/mayors/beta/mayor-workspace/CLAUDE.md"
assert_file_missing "$RIG_HOME/sgt/.sgt/mayors/alpha/mayor-briefing.md"
assert_dir_missing "$RIG_HOME/sgt/.sgt/mayors/alpha/mayor-workspace"
grep -qx 'sgt-mayor-alpha' "$RIG_SESSIONS" || {
  echo "expected alpha mayor session to be restarted" >&2
  exit 1
}
grep -qx 'sgt-mayor-beta' "$RIG_SESSIONS" || {
  echo "expected beta mayor session to remain running" >&2
  exit 1
}
case "$rig_handoff" in
  *"/mayors/alpha/handoffs/"*) ;;
  *)
    echo "expected per-rig handoff path to stay under alpha scope" >&2
    exit 1
    ;;
esac

echo "ALL TESTS PASSED"
