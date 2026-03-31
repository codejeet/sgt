#!/usr/bin/env bash
# test_peek_mayor_log_fallback.sh — Verify mayor peek falls back to mayor-start.log when the tmux pane is blank.

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
cmd="${1:-}"
case "$cmd" in
  has-session)
    [[ "${2:-}" == "-t" ]] || exit 1
    case "${3:-}" in
      sgt-president|sgt-mayor|sgt-mayor-alpha) exit 0 ;;
      *) exit 1 ;;
    esac
    ;;
  capture-pane)
    [[ "${2:-}" == "-t" ]] || exit 1
    session="${3:-}"
    if [[ "$session" == "sgt-mayor-alpha" ]]; then
      printf '   \n'
    else
      printf '\n'
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
  shift
  env -i \
    HOME="$home_dir" \
    PATH="$home_dir/.local/bin:$TMP_ROOT/mockbin:/usr/local/bin:/usr/bin:/bin" \
    TERM=dumb \
    SGT_ROOT="$home_dir/sgt" \
    "$@"
}

mkdir -p "$TMP_ROOT/mockbin"
make_mock_bin "$TMP_ROOT/mockbin"

HOME_DIR="$TMP_ROOT/home"
mkdir -p "$HOME_DIR/.local/bin"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"

run_env "$HOME_DIR" bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/president"
mkdir -p "$SGT_ROOT/.sgt/mayors/alpha"
printf "president line\n" > "$SGT_ROOT/.sgt/president/president-start.log"
printf "shared mayor line\n" > "$SGT_ROOT/.sgt/mayor-start.log"
printf "per-rig mayor line\n" > "$SGT_ROOT/.sgt/mayors/alpha/mayor-start.log"
'

president_out="$(run_env "$HOME_DIR" bash --noprofile --norc -c 'set -euo pipefail; sgt peek president')"
printf '%s' "$president_out" | grep -q 'president line' || {
  echo "expected president peek to fall back to president-start.log" >&2
  exit 1
}

shared_out="$(run_env "$HOME_DIR" bash --noprofile --norc -c 'set -euo pipefail; sgt peek mayor')"
printf '%s' "$shared_out" | grep -q 'shared mayor line' || {
  echo "expected shared mayor peek to fall back to mayor-start.log" >&2
  exit 1
}

rig_out="$(run_env "$HOME_DIR" bash --noprofile --norc -c 'set -euo pipefail; sgt peek mayor/alpha')"
printf '%s' "$rig_out" | grep -q 'per-rig mayor line' || {
  echo "expected per-rig mayor peek to fall back to scoped mayor-start.log" >&2
  exit 1
}
