#!/usr/bin/env bash
# test_president_refresh.sh — President refresh should archive scoped transient state into a handoff and restart cleanly.

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
printf 'sgt-president\n' > "$SESSIONS_FILE"

cat > "$MOCK_BIN/tmux" <<'EOF'
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
    printf '%s\n' "$session" >> "$sessions_file"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$MOCK_BIN/tmux"

cat > "$MOCK_BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$MOCK_BIN/gh"

env -i \
  HOME="$HOME_DIR" \
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM=dumb \
  SGT_ROOT="$HOME_DIR/sgt" \
  SGT_MAYOR_ARCHITECTURE=per-rig \
  SGT_TEST_TMUX_SESSIONS_FILE="$SESSIONS_FILE" \
  bash --noprofile --norc -c '
    set -euo pipefail
    sgt init >/dev/null
    mkdir -p "$SGT_ROOT/.sgt/president"
    printf "1|2026-03-31T00:00:00Z|123|cycle-complete|4|periodic\n" > "$SGT_ROOT/.sgt/president/president-heartbeat.json"
    printf "1|clean-exit|0|EXIT|false\n" > "$SGT_ROOT/.sgt/president/president-exit.state"
    printf "demo\t1\tactionable-no-forward-motion\trefresh\n" > "$SGT_ROOT/.sgt/president/president-interventions.tsv"
    printf "president start log\n" > "$SGT_ROOT/.sgt/president/president-start.log"
    sgt president refresh > "$SGT_ROOT/.sgt/president-refresh.out"
  '

HANDOFF_FILE="$(tail -n 1 "$HOME_DIR/sgt/.sgt/president-refresh.out")"
[[ -f "$HANDOFF_FILE" ]] || {
  echo "expected president refresh to print a handoff file path" >&2
  exit 1
}

case "$HANDOFF_FILE" in
  *"/.sgt/president/handoffs/"*) ;;
  *)
    echo "expected president handoff path under president scope" >&2
    exit 1
    ;;
esac

grep -q '^# President Refresh Handoff$' "$HANDOFF_FILE" || {
  echo "expected president handoff title" >&2
  exit 1
}

grep -q 'president_was_running: true' "$HANDOFF_FILE" || {
  echo "expected handoff to record running president" >&2
  exit 1
}

[[ -f "$(dirname "$HANDOFF_FILE")/president-heartbeat.json" ]] || {
  echo "expected archived president heartbeat state" >&2
  exit 1
}

[[ ! -f "$HOME_DIR/sgt/.sgt/president/president-heartbeat.json" ]] || {
  echo "expected president heartbeat state to be moved into handoff" >&2
  exit 1
}

grep -qx 'sgt-president' "$SESSIONS_FILE" || {
  echo "expected president session to be restarted" >&2
  exit 1
}

echo "ALL TESTS PASSED"
