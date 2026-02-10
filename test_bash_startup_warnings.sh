#!/usr/bin/env bash
# test_bash_startup_warnings.sh — Ensure startup commands emit no bash parse warnings.

set -euo pipefail

SGT_SCRIPT="$(dirname "$0")/sgt"
WARN_RE='unterminated here-document'
FAIL=0

check_no_legacy_heredoc_pattern() {
  # Regression guard: redirection must appear before <<'PY' within $(...).
  # The old form `$(python ... <<'PY' 2>/dev/null)` triggers parser warnings.
  if grep -Eq 'notify_out=\$\(python3? - "\$SGT_NOTIFY" <<'\''PY'\'' 2>/dev/null\)' "$SGT_SCRIPT"; then
    echo "FAIL: legacy here-doc pattern found in $SGT_SCRIPT"
    FAIL=1
  else
    echo "PASS: no legacy here-doc pattern found in $SGT_SCRIPT"
  fi
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

  if grep -Eiq "$WARN_RE" "$stderr_file"; then
    echo "FAIL: bash -n emitted parse warning"
    cat "$stderr_file"
    FAIL=1
  else
    echo "PASS: bash -n emitted no parse warning"
  fi

  rm -f "$stderr_file"
}

check_command() {
  local name="$1"
  local expected_exit="$2"
  shift 2

  local stdout_file stderr_file cmd_exit
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  set +e
  "$SGT_SCRIPT" "$@" >"$stdout_file" 2>"$stderr_file"
  cmd_exit=$?
  set -e

  if [[ "$cmd_exit" -ne "$expected_exit" ]]; then
    echo "FAIL: $name exit code changed (expected $expected_exit, got $cmd_exit)"
    FAIL=1
  else
    echo "PASS: $name exit code is $expected_exit"
  fi

  if grep -Eiq "$WARN_RE" "$stderr_file"; then
    echo "FAIL: $name emitted here-doc warning"
    cat "$stderr_file"
    FAIL=1
  else
    echo "PASS: $name emitted no here-doc warning"
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
check_no_legacy_heredoc_pattern
check_bash_parse
check_command "sgt --help" 0 --help
check_command "sgt status" 0 status
check_command "sgt sweep" 0 sweep

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi

echo "ALL TESTS PASSED"
