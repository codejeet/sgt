#!/usr/bin/env bash
# test_bash_startup_warnings.sh — Ensure startup commands emit zero stderr noise.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
FAIL=0

check_no_heredoc_in_notify_parser() {
  if awk '
    /_notify_openclaw[[:space:]]*\(\)[[:space:]]*\{/ { in_notify=1 }
    in_notify && /^}/ { in_notify=0 }
    in_notify && /<<'\''PY'\''/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$SGT_SCRIPT"; then
    echo "FAIL: found heredoc-based Python parser in _notify_openclaw"
    FAIL=1
  else
    echo "PASS: no heredoc-based Python parser in _notify_openclaw"
  fi
}

check_no_heredoc_in_command_substitution() {
  if grep -nE '\$\(cat[[:space:]]*<<' "$SGT_SCRIPT" >/tmp/sgt_heredoc_subst_hits.$$; then
    echo "FAIL: found heredoc within command substitution"
    cat /tmp/sgt_heredoc_subst_hits.$$
    FAIL=1
  else
    echo "PASS: no heredoc-within-command-substitution patterns found"
  fi
  rm -f /tmp/sgt_heredoc_subst_hits.$$
}

check_bash_parse() {
  local stderr_file
  stderr_file="$(mktemp)"

  if bash -n "$SGT_SCRIPT" 2>"$stderr_file"; then
    :
  else
    echo "FAIL: bash -n failed for $SGT_SCRIPT"
    cat "$stderr_file"
    FAIL=1
    rm -f "$stderr_file"
    return
  fi

  if [[ -s "$stderr_file" ]]; then
    echo "FAIL: bash -n emitted stderr output"
    cat "$stderr_file"
    FAIL=1
  else
    echo "PASS: bash -n emitted zero stderr output"
  fi

  rm -f "$stderr_file"
}

setup_clean_shell() {
  local tmp_home="$1"
  local stdout_file stderr_file init_exit
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  set +e
  env -i \
    HOME="$tmp_home" \
    PATH="$tmp_home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    bash --noprofile --norc -c "sgt init" >"$stdout_file" 2>"$stderr_file"
  init_exit=$?
  set -e

  if [[ "$init_exit" -ne 0 ]]; then
    echo "FAIL: clean-shell setup 'sgt init' failed with exit $init_exit"
    [[ -s "$stderr_file" ]] && cat "$stderr_file"
    FAIL=1
  else
    echo "PASS: clean-shell setup 'sgt init' exited 0"
  fi

  if [[ -s "$stderr_file" ]]; then
    echo "FAIL: clean-shell setup 'sgt init' emitted stderr output"
    cat "$stderr_file"
    FAIL=1
  else
    echo "PASS: clean-shell setup 'sgt init' emitted zero stderr output"
  fi

  rm -f "$stdout_file" "$stderr_file"
}

check_command_clean_shell() {
  local name="$1"
  local expected_exit="$2"
  local subcommand="$3"
  local tmp_home="$4"

  local stdout_file stderr_file cmd_exit

  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  set +e
  env -i \
    HOME="$tmp_home" \
    PATH="$tmp_home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    bash --noprofile --norc -c "sgt $subcommand" >"$stdout_file" 2>"$stderr_file"
  cmd_exit=$?
  set -e

  if [[ "$cmd_exit" -ne "$expected_exit" ]]; then
    echo "FAIL: $name exit code changed (expected $expected_exit, got $cmd_exit)"
    FAIL=1
  else
    echo "PASS: $name exit code is $expected_exit"
  fi

  if [[ -s "$stderr_file" ]]; then
    echo "FAIL: $name emitted stderr output"
    cat "$stderr_file"
    FAIL=1
  else
    echo "PASS: $name emitted zero stderr output"
  fi

  if [[ ! -s "$stdout_file" ]]; then
    echo "FAIL: $name produced empty stdout"
    FAIL=1
  else
    echo "PASS: $name produced stdout"
  fi

  rm -f "$stdout_file" "$stderr_file"
}

echo "=== bash startup warning regression ==="
check_no_heredoc_in_notify_parser
check_no_heredoc_in_command_substitution
check_bash_parse
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
mkdir -p "$TMP_HOME/.local/bin"
cp "$SGT_SCRIPT" "$TMP_HOME/.local/bin/sgt"
chmod +x "$TMP_HOME/.local/bin/sgt"
setup_clean_shell "$TMP_HOME"
check_command_clean_shell "sgt --help" 0 "--help" "$TMP_HOME"
check_command_clean_shell "sgt status" 0 "status" "$TMP_HOME"
check_command_clean_shell "sgt sweep" 0 "sweep" "$TMP_HOME"

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi

echo "ALL TESTS PASSED"
