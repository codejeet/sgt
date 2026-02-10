#!/usr/bin/env bash
# test_status_non_tty_term_cols_guard.sh — Regression check for status rendering when term width is unset/narrow.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/.local/bin"
cp "$SGT_SCRIPT" "$TMP_HOME/.local/bin/sgt"
chmod +x "$TMP_HOME/.local/bin/sgt"

cat > "$TMP_HOME/.local/bin/gh" <<'GH'
#!/usr/bin/env bash
args=" $* "
if [[ "$args" == *" pr list "* ]] && [[ "$args" == *" --json number "* ]]; then
  echo "123"
  exit 0
fi
if [[ "$args" == *" pr list "* ]] && [[ "$args" == *" --json state "* ]]; then
  echo "OPEN"
  exit 0
fi
if [[ "$args" == *" pr list "* ]] && [[ "$args" == *" --json title "* ]]; then
  echo "Very long pull request title that should be safely truncated in narrow mode"
  exit 0
fi
exit 0
GH
chmod +x "$TMP_HOME/.local/bin/gh"

cat > "$TMP_HOME/.local/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
# Simulate no active sessions.
exit 1
TMUX
chmod +x "$TMP_HOME/.local/bin/tmux"

run_case() {
  local label="$1"
  local columns_mode="$2"
  local out_file err_file cmd_exit
  out_file="$(mktemp)"
  err_file="$(mktemp)"

  set +e
  env -i \
    HOME="$TMP_HOME" \
    PATH="$TMP_HOME/.local/bin:/usr/bin:/bin" \
    TERM=dumb \
    COLUMNS="$columns_mode" \
    bash --noprofile --norc -c '
      sgt init >/dev/null
      cat > "$HOME/sgt/.sgt/polecats/p1" <<"PSTATE"
SESSION=sgt-polecat-p1
REPO=acme/roadrunner
BRANCH=feature/term-cols-guard
ISSUE=69
PSTATE
      if [[ -z "${COLUMNS:-}" ]]; then
        unset COLUMNS
      fi
      sgt status
    ' >"$out_file" 2>"$err_file"
  cmd_exit=$?
  set -e

  if [[ "$cmd_exit" -ne 0 ]]; then
    echo "FAIL: $label exited $cmd_exit (expected 0)"
    [[ -s "$err_file" ]] && cat "$err_file"
    [[ -s "$out_file" ]] && cat "$out_file"
    rm -f "$out_file" "$err_file"
    exit 1
  fi

  if [[ -s "$err_file" ]]; then
    echo "FAIL: $label emitted stderr"
    cat "$err_file"
    rm -f "$out_file" "$err_file"
    exit 1
  fi

  for section in Agents Dogs Crew "Merge Queue" Polecats; do
    if ! grep -q "$section" "$out_file"; then
      echo "FAIL: $label missing status section '$section'"
      cat "$out_file"
      rm -f "$out_file" "$err_file"
      exit 1
    fi
  done

  if ! grep -q "Very long pull request" "$out_file"; then
    echo "FAIL: $label missing PR title line"
    cat "$out_file"
    rm -f "$out_file" "$err_file"
    exit 1
  fi

  rm -f "$out_file" "$err_file"
  echo "PASS: $label"
}

echo "=== status term-cols guard regression ==="
run_case "non-tty with COLUMNS unset" ""
run_case "non-tty with narrow COLUMNS" "1"

echo "ALL TESTS PASSED"
