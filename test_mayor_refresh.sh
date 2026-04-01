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

shared_transient_entries=(
  mayor-action-receipts
  mayor-agent-heartbeat-watchdog.state
  mayor-ai-cycle.state
  mayor-ai-observability.state
  mayor-auto-refresh.state
  mayor-briefing.md
  mayor-ci-check-watchdog.state
  mayor-critical-alert.state
  mayor-dispatch-attempts
  mayor-dispatch-snapshot.tsv
  mayor-dispatch-triggers
  mayor-exit.state
  mayor-heartbeat.state
  mayor-last-cycle.state
  mayor-notify-alert.state
  mayor-notify-attempts
  mayor-notify-receipts
  mayor-prompt-budget.state
  mayor-review-watchdog.state
  mayor-start-failure.state
  mayor-start.log
  mayor-start.receipt
  mayor-workspace
)

run_env "$SHARED_HOME" "$SHARED_SESSIONS" bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/mayor-workspace"
printf "briefing\n" > "$SGT_ROOT/.sgt/mayor-briefing.md"
printf "snapshot\n" > "$SGT_ROOT/.sgt/mayor-dispatch-snapshot.tsv"
printf "status=running\n" > "$SGT_ROOT/.sgt/mayor-ai-cycle.state"
printf "observability\n" > "$SGT_ROOT/.sgt/mayor-ai-observability.state"
printf "1|2026-03-30T00:00:00Z|100|400|150000|false|prompt\n" > "$SGT_ROOT/.sgt/mayor-prompt-budget.state"
printf "1|2026-03-30T00:00:00Z|manual|100|400|150000|handoff|token|scheduled\n" > "$SGT_ROOT/.sgt/mayor-auto-refresh.state"
printf "1|2026-03-30T00:00:00Z|123|running|7|manual\n" > "$SGT_ROOT/.sgt/mayor-heartbeat.state"
printf "1|2026-03-30T00:00:00Z|manual|completed\n" > "$SGT_ROOT/.sgt/mayor-last-cycle.state"
printf "1|clean-exit|0|EXIT|false|123|manual|2026-03-30T00:00:00Z|completed\n" > "$SGT_ROOT/.sgt/mayor-exit.state"
printf "1|critical|reason\n" > "$SGT_ROOT/.sgt/mayor-critical-alert.state"
printf "1|context|workspace|error\n" > "$SGT_ROOT/.sgt/mayor-decision-log-alert.state"
printf "1|channel|target|key|1|failed|reason|matcher|true\n" > "$SGT_ROOT/.sgt/mayor-notify-alert.state"
printf "1|2|900\n" > "$SGT_ROOT/.sgt/mayor-review-watchdog.state"
printf "1|ci-key|900\n" > "$SGT_ROOT/.sgt/mayor-ci-check-watchdog.state"
printf "1|witness|sgt|900\n" > "$SGT_ROOT/.sgt/mayor-agent-heartbeat-watchdog.state"
printf "ATTEMPT=abc\n" > "$SGT_ROOT/.sgt/mayor-start.receipt"
printf "spawn log\n" > "$SGT_ROOT/.sgt/mayor-start.log"
printf "1|startup-failed|attempt|log|detail\n" > "$SGT_ROOT/.sgt/mayor-start-failure.state"
printf "decision\n" > "$SGT_ROOT/.sgt/mayor-decisions.log"
printf "notes\n" > "$SGT_ROOT/.sgt/mayor-workspace/CLAUDE.md"
mkdir -p "$SGT_ROOT/.sgt/mayor-action-receipts" "$SGT_ROOT/.sgt/mayor-notify-receipts" "$SGT_ROOT/.sgt/mayor-notify-attempts" "$SGT_ROOT/.sgt/mayor-dispatch-triggers" "$SGT_ROOT/.sgt/mayor-dispatch-attempts"
printf "receipt\n" > "$SGT_ROOT/.sgt/mayor-action-receipts/one"
printf "notify\n" > "$SGT_ROOT/.sgt/mayor-notify-receipts/one"
printf "attempt\n" > "$SGT_ROOT/.sgt/mayor-notify-attempts/one"
printf "trigger\n" > "$SGT_ROOT/.sgt/mayor-dispatch-triggers/one"
printf "dispatch\n" > "$SGT_ROOT/.sgt/mayor-dispatch-attempts/one"
'

SHARED_OUT="$TMP_ROOT/shared-refresh.out"
run_env "$SHARED_HOME" "$SHARED_SESSIONS" bash --noprofile --norc -c 'set -euo pipefail; timeout 15 sgt mayor refresh' > "$SHARED_OUT"
shared_handoff="$(tail -n 1 "$SHARED_OUT")"
assert_file "$shared_handoff"
for entry in "${shared_transient_entries[@]}"; do
  if [[ -d "$(dirname "$shared_handoff")/$entry" ]]; then
    :
  elif [[ "$entry" == "mayor-workspace" || "$entry" == "mayor-action-receipts" || "$entry" == "mayor-notify-receipts" || "$entry" == "mayor-notify-attempts" || "$entry" == "mayor-dispatch-triggers" || "$entry" == "mayor-dispatch-attempts" ]]; then
    [[ -d "$(dirname "$shared_handoff")/$entry" ]] || {
      echo "expected archived directory: $entry" >&2
      exit 1
    }
  else
    assert_file "$(dirname "$shared_handoff")/$entry"
  fi
done
assert_file "$(dirname "$shared_handoff")/mayor-workspace/CLAUDE.md"
assert_file "$SHARED_HOME/sgt/.sgt/mayor-decisions.log"
assert_file_missing "$SHARED_HOME/sgt/.sgt/mayor-briefing.md"
assert_dir_missing "$SHARED_HOME/sgt/.sgt/mayor-workspace"
assert_dir_missing "$SHARED_HOME/sgt/.sgt/mayor-action-receipts"
assert_dir_missing "$SHARED_HOME/sgt/.sgt/mayor-notify-receipts"
assert_dir_missing "$SHARED_HOME/sgt/.sgt/mayor-notify-attempts"
assert_dir_missing "$SHARED_HOME/sgt/.sgt/mayor-dispatch-triggers"
assert_dir_missing "$SHARED_HOME/sgt/.sgt/mayor-dispatch-attempts"
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

per_rig_transient_entries=(
  mayor-action-receipts
  mayor-agent-heartbeat-watchdog.state
  mayor-ai-cycle.state
  mayor-ai-observability.state
  mayor-auto-refresh.state
  mayor-briefing.md
  mayor-ci-check-watchdog.state
  mayor-critical-alert.state
  mayor-dispatch-attempts
  mayor-dispatch-snapshot.tsv
  mayor-dispatch-triggers
  mayor-exit.state
  mayor-heartbeat.state
  mayor-last-cycle.state
  mayor-notify-alert.state
  mayor-notify-attempts
  mayor-notify-receipts
  mayor-prompt-budget.state
  mayor-review-watchdog.state
  mayor-start-failure.state
  mayor-start.log
  mayor-start.receipt
  mayor-workspace
)

run_env "$RIG_HOME" "$RIG_SESSIONS" bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs" "$SGT_ROOT/rigs/alpha" "$SGT_ROOT/rigs/beta"
printf "https://github.com/acme/alpha\n" > "$SGT_ROOT/.sgt/rigs/alpha"
printf "https://github.com/acme/beta\n" > "$SGT_ROOT/.sgt/rigs/beta"
mkdir -p "$SGT_ROOT/.sgt/mayors/alpha/mayor-workspace" "$SGT_ROOT/.sgt/mayors/beta/mayor-workspace"
printf "alpha briefing\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-briefing.md"
printf "beta briefing\n" > "$SGT_ROOT/.sgt/mayors/beta/mayor-briefing.md"
printf "alpha obs\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-ai-observability.state"
printf "alpha cycle\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-ai-cycle.state"
printf "alpha budget\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-prompt-budget.state"
printf "alpha refresh\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-auto-refresh.state"
printf "alpha heartbeat\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-heartbeat.state"
printf "alpha last cycle\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-last-cycle.state"
printf "alpha exit\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-exit.state"
printf "alpha critical\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-critical-alert.state"
printf "alpha notify\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-notify-alert.state"
printf "alpha review\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-review-watchdog.state"
printf "alpha ci\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-ci-check-watchdog.state"
printf "alpha agent hb\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-agent-heartbeat-watchdog.state"
printf "alpha start receipt\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-start.receipt"
printf "alpha start log\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-start.log"
printf "alpha start failure\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-start-failure.state"
printf "alpha snapshot\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-dispatch-snapshot.tsv"
mkdir -p "$SGT_ROOT/.sgt/mayors/alpha/mayor-action-receipts" "$SGT_ROOT/.sgt/mayors/alpha/mayor-notify-receipts" "$SGT_ROOT/.sgt/mayors/alpha/mayor-notify-attempts" "$SGT_ROOT/.sgt/mayors/alpha/mayor-dispatch-triggers" "$SGT_ROOT/.sgt/mayors/alpha/mayor-dispatch-attempts"
printf "alpha action receipt\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-action-receipts/one"
printf "alpha notify receipt\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-notify-receipts/one"
printf "alpha notify attempt\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-notify-attempts/one"
printf "alpha trigger\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-dispatch-triggers/one"
printf "alpha dispatch attempt\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-dispatch-attempts/one"
printf "alpha notes\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-workspace/CLAUDE.md"
printf "beta notes\n" > "$SGT_ROOT/.sgt/mayors/beta/mayor-workspace/CLAUDE.md"
printf "alpha decision\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-decisions.log"
printf "beta decision\n" > "$SGT_ROOT/.sgt/mayors/beta/mayor-decisions.log"
'

RIG_OUT="$TMP_ROOT/per-rig-refresh.out"
run_env "$RIG_HOME" "$RIG_SESSIONS" SGT_MAYOR_ARCHITECTURE=per-rig bash --noprofile --norc -c 'set -euo pipefail; timeout 15 sgt mayor refresh alpha' > "$RIG_OUT"
rig_handoff="$(tail -n 1 "$RIG_OUT")"
assert_file "$rig_handoff"
for entry in "${per_rig_transient_entries[@]}"; do
  if [[ "$entry" == "mayor-workspace" || "$entry" == "mayor-action-receipts" || "$entry" == "mayor-notify-receipts" || "$entry" == "mayor-notify-attempts" || "$entry" == "mayor-dispatch-triggers" || "$entry" == "mayor-dispatch-attempts" ]]; then
    [[ -d "$(dirname "$rig_handoff")/$entry" ]] || {
      echo "expected archived per-rig directory: $entry" >&2
      exit 1
    }
  else
    assert_file "$(dirname "$rig_handoff")/$entry"
  fi
done
assert_file "$(dirname "$rig_handoff")/mayor-workspace/CLAUDE.md"
assert_file "$RIG_HOME/sgt/.sgt/mayors/alpha/mayor-decisions.log"
assert_file "$RIG_HOME/sgt/.sgt/mayors/beta/mayor-briefing.md"
assert_file "$RIG_HOME/sgt/.sgt/mayors/beta/mayor-workspace/CLAUDE.md"
assert_file_missing "$RIG_HOME/sgt/.sgt/mayors/alpha/mayor-briefing.md"
assert_dir_missing "$RIG_HOME/sgt/.sgt/mayors/alpha/mayor-workspace"
assert_dir_missing "$RIG_HOME/sgt/.sgt/mayors/alpha/mayor-action-receipts"
assert_dir_missing "$RIG_HOME/sgt/.sgt/mayors/alpha/mayor-notify-receipts"
assert_dir_missing "$RIG_HOME/sgt/.sgt/mayors/alpha/mayor-notify-attempts"
assert_dir_missing "$RIG_HOME/sgt/.sgt/mayors/alpha/mayor-dispatch-triggers"
assert_dir_missing "$RIG_HOME/sgt/.sgt/mayors/alpha/mayor-dispatch-attempts"
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

grep -q 'MAYOR_REFRESH scope=alpha' "$RIG_HOME/sgt/sgt.log" || {
  echo "expected per-rig refresh log scope to stay on alpha" >&2
  exit 1
}
if grep -q 'MAYOR_REFRESH scope=shared' "$RIG_HOME/sgt/sgt.log"; then
  echo "did not expect shared refresh scope in per-rig refresh log" >&2
  exit 1
fi

echo "=== president-mode refresh without caller env ==="
PRESIDENT_HOME="$TMP_ROOT/president-mode-home"
PRESIDENT_SESSIONS="$TMP_ROOT/president-mode-sessions"
mkdir -p "$PRESIDENT_HOME/.local/bin"
cp "$SGT_SCRIPT" "$PRESIDENT_HOME/.local/bin/sgt"
chmod +x "$PRESIDENT_HOME/.local/bin/sgt"
printf 'sgt-president\nsgt-mayor-alpha\nsgt-mayor-beta\n' > "$PRESIDENT_SESSIONS"

run_env "$PRESIDENT_HOME" "$PRESIDENT_SESSIONS" bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs" "$SGT_ROOT/rigs/alpha" "$SGT_ROOT/rigs/beta"
printf "https://github.com/acme/alpha\n" > "$SGT_ROOT/.sgt/rigs/alpha"
printf "https://github.com/acme/beta\n" > "$SGT_ROOT/.sgt/rigs/beta"
mkdir -p "$SGT_ROOT/.sgt/president" "$SGT_ROOT/.sgt/mayors/alpha/mayor-workspace" "$SGT_ROOT/.sgt/mayors/beta/mayor-workspace"
printf "alpha briefing\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-briefing.md"
printf "beta briefing\n" > "$SGT_ROOT/.sgt/mayors/beta/mayor-briefing.md"
printf "alpha notes\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-workspace/CLAUDE.md"
printf "beta notes\n" > "$SGT_ROOT/.sgt/mayors/beta/mayor-workspace/CLAUDE.md"
printf "alpha decision\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-decisions.log"
printf "beta decision\n" > "$SGT_ROOT/.sgt/mayors/beta/mayor-decisions.log"
'

PRESIDENT_OUT="$TMP_ROOT/president-mode-refresh.out"
run_env "$PRESIDENT_HOME" "$PRESIDENT_SESSIONS" bash --noprofile --norc -c 'set -euo pipefail; timeout 15 sgt mayor refresh alpha' > "$PRESIDENT_OUT"
president_handoff="$(tail -n 1 "$PRESIDENT_OUT")"
assert_file "$president_handoff"
case "$president_handoff" in
  *"/mayors/alpha/handoffs/"*) ;;
  *)
    echo "expected president-mode refresh to infer alpha per-rig scope" >&2
    exit 1
    ;;
esac
assert_file "$PRESIDENT_HOME/sgt/.sgt/mayors/beta/mayor-briefing.md"
assert_file "$PRESIDENT_HOME/sgt/.sgt/mayors/beta/mayor-workspace/CLAUDE.md"
grep -q 'MAYOR_REFRESH scope=alpha' "$PRESIDENT_HOME/sgt/sgt.log" || {
  echo "expected president-mode refresh log scope to stay on alpha" >&2
  exit 1
}
if grep -q 'MAYOR_REFRESH scope=shared' "$PRESIDENT_HOME/sgt/sgt.log"; then
  echo "did not expect shared refresh scope under live president mode" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
