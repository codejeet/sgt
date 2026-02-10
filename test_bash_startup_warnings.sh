#!/usr/bin/env bash
# test_bash_startup_warnings.sh — Ensure startup commands emit no bash parse warnings.

set -euo pipefail

SGT_SCRIPT="$(dirname "$0")/sgt"
WARN_RE='warning: command substitution: [0-9]+ unterminated here-document'
FAIL=0

check_command() {
  local name="$1"
  shift

  local stderr_file
  stderr_file="$(mktemp)"

  if bash -lc "\"$SGT_SCRIPT\" $*" >/dev/null 2>"$stderr_file"; then
    :
  else
    # This regression focuses on parse warnings, not runtime preconditions.
    :
  fi

  if grep -Eiq "$WARN_RE" "$stderr_file"; then
    echo "FAIL: $name emitted bash parse warning"
    cat "$stderr_file"
    FAIL=1
  else
    echo "PASS: $name emitted no bash parse warning"
  fi

  rm -f "$stderr_file"
}

echo "=== bash startup warning regression ==="
check_command "sgt help" help
check_command "sgt status" status
check_command "sgt rig list" rig list

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi

echo "ALL TESTS PASSED"
