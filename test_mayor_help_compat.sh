#!/usr/bin/env bash
# test_mayor_help_compat.sh — Verify mayor help compatibility + unknown subcommand handling.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
FAIL=0

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
mkdir -p "$TMP_HOME/.local/bin"
cp "$SGT_SCRIPT" "$TMP_HOME/.local/bin/sgt"
chmod +x "$TMP_HOME/.local/bin/sgt"

run_cmd() {
  local command="$1"
  local out_file="$2"
  local err_file="$3"
  local rc_file="$4"
  local rc

  set +e
  env -i \
    HOME="$TMP_HOME" \
    PATH="$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    bash --noprofile --norc -c "$command" >"$out_file" 2>"$err_file"
  rc=$?
  set -e
  echo "$rc" >"$rc_file"
}

check_equals() {
  local name="$1"
  local got="$2"
  local want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (expected '$want', got '$got')"
    FAIL=1
  fi
}

check_file_contains() {
  local name="$1"
  local file="$2"
  local pattern="$3"
  if grep -qE "$pattern" "$file"; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
    cat "$file"
    FAIL=1
  fi
}

echo "=== mayor help compatibility ==="

BASE_OUT="$(mktemp)"
BASE_ERR="$(mktemp)"
BASE_RC="$(mktemp)"
HELPFLAG_OUT="$(mktemp)"
HELPFLAG_ERR="$(mktemp)"
HELPFLAG_RC="$(mktemp)"
HELPWORD_OUT="$(mktemp)"
HELPWORD_ERR="$(mktemp)"
HELPWORD_RC="$(mktemp)"
BAD_OUT="$(mktemp)"
BAD_ERR="$(mktemp)"
BAD_RC="$(mktemp)"

trap 'rm -rf "$TMP_HOME" "$BASE_OUT" "$BASE_ERR" "$BASE_RC" "$HELPFLAG_OUT" "$HELPFLAG_ERR" "$HELPFLAG_RC" "$HELPWORD_OUT" "$HELPWORD_ERR" "$HELPWORD_RC" "$BAD_OUT" "$BAD_ERR" "$BAD_RC"' EXIT

run_cmd "sgt mayor" "$BASE_OUT" "$BASE_ERR" "$BASE_RC"
run_cmd "sgt mayor --help" "$HELPFLAG_OUT" "$HELPFLAG_ERR" "$HELPFLAG_RC"
run_cmd "sgt mayor help" "$HELPWORD_OUT" "$HELPWORD_ERR" "$HELPWORD_RC"
run_cmd "sgt mayor nope" "$BAD_OUT" "$BAD_ERR" "$BAD_RC"

check_equals "sgt mayor exits 0" "$(cat "$BASE_RC")" "0"
check_equals "sgt mayor --help exits 0" "$(cat "$HELPFLAG_RC")" "0"
check_equals "sgt mayor help exits 0" "$(cat "$HELPWORD_RC")" "0"
check_equals "sgt mayor writes no stderr" "$(wc -c <"$BASE_ERR" | tr -d ' ')" "0"
check_equals "sgt mayor --help writes no stderr" "$(wc -c <"$HELPFLAG_ERR" | tr -d ' ')" "0"
check_equals "sgt mayor help writes no stderr" "$(wc -c <"$HELPWORD_ERR" | tr -d ' ')" "0"

if diff -u "$BASE_OUT" "$HELPFLAG_OUT" >/dev/null; then
  echo "PASS: sgt mayor and sgt mayor --help output match"
else
  echo "FAIL: sgt mayor and sgt mayor --help output differ"
  diff -u "$BASE_OUT" "$HELPFLAG_OUT" || true
  FAIL=1
fi

if diff -u "$BASE_OUT" "$HELPWORD_OUT" >/dev/null; then
  echo "PASS: sgt mayor and sgt mayor help output match"
else
  echo "FAIL: sgt mayor and sgt mayor help output differ"
  diff -u "$BASE_OUT" "$HELPWORD_OUT" || true
  FAIL=1
fi

check_file_contains "mayor usage includes command synopsis" "$BASE_OUT" '^Usage: sgt mayor <command> \[args\]$'
check_file_contains "unknown mayor subcommand exits 1" "$BAD_RC" '^1$'
check_equals "unknown mayor subcommand writes no stdout" "$(wc -c <"$BAD_OUT" | tr -d ' ')" "0"
check_file_contains "unknown mayor subcommand error is explicit" "$BAD_ERR" '^sgt: unknown mayor command: nope \(try: help, start, stop, notify, merge\)$'

check_file_contains "mayor command keeps start subcommand" "$SGT_SCRIPT" 'start\)[[:space:]]+cmd_mayor_start'
check_file_contains "mayor command keeps stop subcommand" "$SGT_SCRIPT" 'stop\)[[:space:]]+cmd_mayor_stop'
check_file_contains "mayor command keeps notify subcommand" "$SGT_SCRIPT" 'notify\)[[:space:]]+cmd_mayor_notify'
check_file_contains "mayor command keeps merge subcommand" "$SGT_SCRIPT" 'merge\)[[:space:]]+cmd_mayor_merge'

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi

echo "ALL TESTS PASSED"
