#!/usr/bin/env bash
# test_nudge_target_resolution.sh — Verify nudge resolves cockpit-exposed targets to the correct tmux sessions.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

make_mock_bin() {
  local mock_bin="$1"
  mkdir -p "$mock_bin"

  cat > "$mock_bin/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail
log_file="${TMUX_LOG:?}"
cmd="${1:-}"
printf '%s\n' "$*" >> "$log_file"
  case "$cmd" in
  has-session)
    [[ "${2:-}" == "-t" ]] || exit 1
    case "${3:-}" in
      sgt-mayor-alpha|sgt-one|sgt-crew-ops) exit 0 ;;
      *) exit 1 ;;
    esac
    ;;
  send-keys)
    exit 0
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
  shift
  env -i \
    HOME="$home_dir" \
    PATH="$home_dir/.local/bin:$TMP_ROOT/mockbin:/usr/local/bin:/usr/bin:/bin" \
    TERM=dumb \
    SGT_ROOT="$home_dir/sgt" \
    TMUX_LOG="$TMP_ROOT/tmux.log" \
    "$@"
}

mkdir -p "$TMP_ROOT/mockbin"
make_mock_bin "$TMP_ROOT/mockbin"

HOME_DIR="$TMP_ROOT/home"
mkdir -p "$HOME_DIR/.local/bin"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"
: > "$TMP_ROOT/tmux.log"

run_env "$HOME_DIR" bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
sgt nudge mayor/alpha "mayor ping" >/dev/null
sgt nudge dog/one "dog ping" >/dev/null
sgt nudge crew/ops "crew ping" >/dev/null
'

grep -q '^has-session -t sgt-mayor-alpha$' "$TMP_ROOT/tmux.log" || {
  echo "expected mayor/alpha nudge to check sgt-mayor-alpha" >&2
  cat "$TMP_ROOT/tmux.log" >&2
  exit 1
}

grep -q '^send-keys -t sgt-mayor-alpha -l mayor ping$' "$TMP_ROOT/tmux.log" || {
  echo "expected mayor/alpha nudge to send keys to sgt-mayor-alpha" >&2
  cat "$TMP_ROOT/tmux.log" >&2
  exit 1
}

grep -q '^has-session -t sgt-one$' "$TMP_ROOT/tmux.log" || {
  echo "expected dog/one nudge to check sgt-one" >&2
  cat "$TMP_ROOT/tmux.log" >&2
  exit 1
}

grep -q '^send-keys -t sgt-one -l dog ping$' "$TMP_ROOT/tmux.log" || {
  echo "expected dog/one nudge to send keys to sgt-one" >&2
  cat "$TMP_ROOT/tmux.log" >&2
  exit 1
}

grep -q '^has-session -t sgt-crew-ops$' "$TMP_ROOT/tmux.log" || {
  echo "expected crew/ops nudge to check sgt-crew-ops" >&2
  cat "$TMP_ROOT/tmux.log" >&2
  exit 1
}

grep -q '^send-keys -t sgt-crew-ops -l crew ping$' "$TMP_ROOT/tmux.log" || {
  echo "expected crew/ops nudge to send keys to sgt-crew-ops" >&2
  cat "$TMP_ROOT/tmux.log" >&2
  exit 1
}

echo "ALL TESTS PASSED"
