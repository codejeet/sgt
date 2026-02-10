#!/usr/bin/env bash
# test_bash_startup_warnings.sh — Ensure startup commands emit no bash parse warnings.

set -euo pipefail

SGT_SCRIPT="$(dirname "$0")/sgt"
WARN_RE='warning: command substitution: [0-9]+ unterminated here-document'
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
check_no_legacy_heredoc_pattern
check_bash_parse
check_command "sgt --help" --help
check_command "sgt status" status
check_command "sgt sweep" sweep
check_command "sgt sling" sling

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi

echo "ALL TESTS PASSED"
