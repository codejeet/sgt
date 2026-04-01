#!/usr/bin/env bash
# test_web_cli_deploy.sh — Verify first-class Web UI deploy/status/verify flow.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
LIVE_DIR="$TMP_ROOT/live-web"
SESSION_DIR="$TMP_ROOT/tmux-sessions"
WEB_UP_FILE="$TMP_ROOT/web-up"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN" "$SESSION_DIR" "$LIVE_DIR"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

SESSIONS_DIR="${SGT_TMUX_SESSIONS_DIR:?missing SGT_TMUX_SESSIONS_DIR}"
WEB_UP_FILE="${SGT_TEST_WEB_UP_FILE:?missing SGT_TEST_WEB_UP_FILE}"

case "${1:-}" in
  has-session)
    [[ "${2:-}" == "-t" ]] || exit 1
    [[ -f "$SESSIONS_DIR/${3:-}" ]]
    ;;
  new-session)
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
    : > "$WEB_UP_FILE"
    ;;
  kill-session)
    [[ "${2:-}" == "-t" ]] || exit 1
    rm -f "$SESSIONS_DIR/${3:-}"
    rm -f "$WEB_UP_FILE"
    ;;
  *)
    echo "mock tmux unsupported: $*" >&2
    exit 1
    ;;
esac
TMUX
chmod +x "$MOCK_BIN/tmux"

cat > "$MOCK_BIN/npm" <<'NPM'
#!/usr/bin/env bash
set -euo pipefail
exit 0
NPM
chmod +x "$MOCK_BIN/npm"

cat > "$MOCK_BIN/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
WEB_UP_FILE="${SGT_TEST_WEB_UP_FILE:?missing SGT_TEST_WEB_UP_FILE}"
if [[ -f "$WEB_UP_FILE" ]]; then
  printf '{}\n'
  exit 0
fi
exit 1
CURL
chmod +x "$MOCK_BIN/curl"

run_sgt() {
  env -i \
    HOME="$HOME_DIR" \
    PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM=dumb \
    SGT_ROOT="$HOME_DIR/sgt" \
    SGT_WEB_REPO_DIR="$REPO_ROOT" \
    SGT_WEB_LIVE_DIR="$LIVE_DIR" \
    SGT_TMUX_SESSIONS_DIR="$SESSION_DIR" \
    SGT_TEST_WEB_UP_FILE="$WEB_UP_FILE" \
    "$@"
}

printf 'stale\n' > "$LIVE_DIR/README.md"
if run_sgt bash --noprofile --norc -c 'set -euo pipefail; sgt web verify'; then
  echo "expected verify to fail before deploy" >&2
  exit 1
fi

status_before="$(run_sgt bash --noprofile --norc -c 'set -euo pipefail; sgt web status')"
[[ "$status_before" == *"tree state: mismatch"* || "$status_before" == *"tree state: live-missing"* ]] || {
  echo "expected pre-deploy status to report mismatch or missing live tree" >&2
  printf '%s\n' "$status_before" >&2
  exit 1
}

run_sgt bash --noprofile --norc -c 'set -euo pipefail; sgt web deploy'

run_sgt bash --noprofile --norc -c 'set -euo pipefail; sgt web verify'
status_after="$(run_sgt bash --noprofile --norc -c 'set -euo pipefail; sgt web status')"
[[ "$status_after" == *"tree state: in-sync"* ]] || {
  echo "expected post-deploy status to report in-sync" >&2
  printf '%s\n' "$status_after" >&2
  exit 1
}
[[ "$status_after" == *"tmux session: sgt-web (on)"* ]] || {
  echo "expected post-deploy status to report running session" >&2
  printf '%s\n' "$status_after" >&2
  exit 1
}
[[ "$status_after" == *"http verify: http://127.0.0.1:4747/api/status (ok)"* ]] || {
  echo "expected post-deploy status to report healthy HTTP" >&2
  printf '%s\n' "$status_after" >&2
  exit 1
}

run_sgt bash --noprofile --norc -c 'set -euo pipefail; sgt web stop'
if run_sgt bash --noprofile --norc -c 'set -euo pipefail; sgt web verify'; then
  echo "expected verify to fail once the live session is stopped" >&2
  exit 1
fi

echo "PASS: web CLI deploy flow"
