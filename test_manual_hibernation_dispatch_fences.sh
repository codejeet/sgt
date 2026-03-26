#!/usr/bin/env bash
# test_manual_hibernation_dispatch_fences.sh — Manual hibernation must fence sling, plan tick, sweep, and direct resling.

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
printf '%s\n' "$*" >> "${TMUX_CALLS_FILE:?missing TMUX_CALLS_FILE}"
case "${1:-}" in
  has-session)
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
TMUX
chmod +x "$MOCK_BIN/tmux"

cat > "$MOCK_BIN/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
exit 0
GIT
chmod +x "$MOCK_BIN/git"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${GH_CALLS_FILE:?missing GH_CALLS_FILE}"
case "${1:-}:${2:-}" in
  label:create)
    exit 0
    ;;
  issue:create)
    printf '%s\n' "$*" >> "${ISSUE_CREATES_FILE:?missing ISSUE_CREATES_FILE}"
    echo "https://github.com/acme/demo/issues/99"
    exit 0
    ;;
  issue:list)
    printf '55\tDormant issue\n'
    exit 0
    ;;
  pr:list)
    exit 0
    ;;
  issue:view)
    if [[ " $* " == *" --json title "* ]]; then
      printf 'Dormant issue\n'
      exit 0
    fi
    if [[ " $* " == *" --json state "* ]]; then
      printf 'OPEN\n'
      exit 0
    fi
    exit 0
    ;;
  issue:edit|api:*)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
GH
chmod +x "$MOCK_BIN/gh"

COMMON_ENV=(
  env -i
  HOME="$HOME_DIR"
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin"
  TERM="${TERM:-xterm}"
  SGT_ROOT="$HOME_DIR/sgt"
  TMUX_CALLS_FILE="$TMP_ROOT/tmux.calls"
  GH_CALLS_FILE="$TMP_ROOT/gh.calls"
  ISSUE_CREATES_FILE="$TMP_ROOT/issue.creates"
)

"${COMMON_ENV[@]}" bash --noprofile --norc <<'BASH'
set -euo pipefail

: > "$TMUX_CALLS_FILE"
: > "$GH_CALLS_FILE"
: > "$ISSUE_CREATES_FILE"

sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs" "$SGT_ROOT/rigs/demo"
printf '%s\n' 'https://github.com/acme/demo' > "$SGT_ROOT/.sgt/rigs/demo"

cat > "$SGT_ROOT/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 1 },
  "acceptance": { "status": "pending", "details": "Verify later." },
  "tasks": [
    { "id": "task-1", "title": "Dormant task" }
  ]
}
JSON

sgt mayor hibernate demo "quiet window" >/dev/null

if sgt sling demo "Do not dispatch while manually hibernated" >"$HOME/sling.out" 2>&1; then
  echo "expected sling to refuse dispatch for manually hibernated rig" >&2
  exit 1
fi
grep -q 'manually hibernated' "$HOME/sling.out"

sgt plan tick demo > "$HOME/plan-tick.out" 2>&1
sgt sweep > "$HOME/sweep.out" 2>&1

if [[ -s "$ISSUE_CREATES_FILE" ]]; then
  echo "expected no GitHub issues to be created while rig is manually hibernated" >&2
  cat "$ISSUE_CREATES_FILE" >&2
  exit 1
fi
if grep -q '^new-session ' "$TMUX_CALLS_FILE"; then
  echo "expected no tmux sessions to be created while rig is manually hibernated" >&2
  cat "$TMUX_CALLS_FILE" >&2
  exit 1
fi
grep -q 'PLAN_TICK_SKIP_DISPATCH rig=demo source=manual reason_code=manual-hibernation' "$SGT_ROOT/sgt.log"
grep -q 'SWEEP_WATCHDOG_RESLING_SKIP rig=demo repo=acme/demo reason_code=manual-hibernation source_event=sweep-watchdog' "$SGT_ROOT/sgt.log"
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

eval "$(extract_fn _mayor_rig_activity_enabled)"
eval "$(extract_fn _mayor_rig_activity_file)"
eval "$(extract_fn _mayor_rig_activity_state_read)"
eval "$(extract_fn _mayor_rig_hibernation_mode)"
eval "$(extract_fn _mayor_rig_manually_hibernated)"
eval "$(extract_fn _resling_existing_issue)"

export SGT_CONFIG="$TMP_ROOT/resling-config"
export SGT_MAYOR_RIG_ACTIVITY_DIR="$SGT_CONFIG/mayor-rig-activity"
export SGT_LOG="$TMP_ROOT/resling.log"
mkdir -p "$SGT_MAYOR_RIG_ACTIVITY_DIR"

cat > "$SGT_MAYOR_RIG_ACTIVITY_DIR/demo.state" <<'STATE'
STATE=hibernated
LAST_REASON=manual pause
CHANGED_AT=2026-03-26T00:00:00Z
CHANGED_EPOCH=1
HIBERNATION_MODE=manual
LAST_MEANINGFUL_AT=
LAST_MEANINGFUL_EPOCH=
LAST_MEANINGFUL_REASON=
LAST_WAKE_AT=
LAST_WAKE_REASON=
STATE

_wake_trigger_key() { printf '%s\n' "$1"; }
_escape_quotes() { printf '%s' "$1"; }
log_event() { printf '%s\n' "$1" >> "$SGT_LOG"; }

if _resling_existing_issue demo 55 "Dormant issue" "https://github.com/acme/demo" "codex" "" "witness-stalled" "witness-stalled:demo:#55" >/tmp/resling.out 2>&1; then
  echo "expected direct resling helper to refuse dispatch for manually hibernated rig" >&2
  exit 1
fi

grep -q 'RESLING_SKIP_HIBERNATED issue=#55 rig=demo mode=manual source_event=witness-stalled' "$SGT_LOG"
BASH

echo "ALL TESTS PASSED"
