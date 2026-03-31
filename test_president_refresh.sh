#!/usr/bin/env bash
# test_president_refresh.sh — Verify president refresh archives transient state into a handoff and restarts President.

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
mkdir -p "$SGT_ROOT/.sgt/rigs" "$SGT_ROOT/rigs/alpha"
printf "https://github.com/acme/alpha\n" > "$SGT_ROOT/.sgt/rigs/alpha"
mkdir -p "$SGT_ROOT/.sgt/president"
printf "{\"timestamp\":\"2026-03-31T00:00:00Z\",\"state\":\"ok\",\"pid\":\"321\",\"phase\":\"cycle-complete\",\"cycle\":\"7\",\"trigger\":\"periodic\"}\n" > "$SGT_ROOT/.sgt/president/president-heartbeat.json"
printf "2026-03-31T00:00:00Z|nonzero-exit|9|EXIT|true\n" > "$SGT_ROOT/.sgt/president/president-exit.state"
printf "1774915200|actionable-no-forward-motion|refresh\n" > "$SGT_ROOT/.sgt/president/president-interventions.tsv"
printf "president start log\n" > "$SGT_ROOT/.sgt/president/president-start.log"
'

OUT_FILE="$TMP_ROOT/president-refresh.out"
"${ENV_PREFIX[@]}" bash --noprofile --norc -c 'set -euo pipefail; timeout 15 sgt president refresh' > "$OUT_FILE"
handoff_file="$(tail -n 1 "$OUT_FILE")"

[[ -f "$handoff_file" ]] || {
  echo "expected president refresh to print a handoff path" >&2
  exit 1
}
case "$handoff_file" in
  *"/.sgt/president/handoffs/"*) ;;
  *)
    echo "expected president handoff path under scoped president runtime dir" >&2
    exit 1
    ;;
esac

grep -q '^# President Refresh Handoff$' "$handoff_file" || {
  echo "expected president handoff title" >&2
  exit 1
}
grep -q 'president_was_running: true' "$handoff_file" || {
  echo "expected president handoff to note running president" >&2
  exit 1
}
for archived in president-heartbeat.json president-exit.state president-interventions.tsv president-start.log; do
  [[ -f "$(dirname "$handoff_file")/$archived" ]] || {
    echo "expected archived president transient: $archived" >&2
    exit 1
  }
done
[[ ! -f "$HOME_DIR/sgt/.sgt/president/president-heartbeat.json" ]] || {
  echo "expected president heartbeat to be archived out of runtime dir" >&2
  exit 1
}
[[ ! -f "$HOME_DIR/sgt/.sgt/president/president-interventions.tsv" ]] || {
  echo "expected president intervention state to be archived out of runtime dir" >&2
  exit 1
}
grep -qx 'sgt-president' "$SESSIONS_FILE" || {
  echo "expected president session to be restarted" >&2
  exit 1
}

echo "ALL TESTS PASSED"
