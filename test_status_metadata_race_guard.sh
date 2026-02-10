#!/usr/bin/env bash
# test_status_metadata_race_guard.sh — status should tolerate polecat metadata races/misses.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/.local/bin"
cp "$SGT_SCRIPT" "$TMP_HOME/.local/bin/sgt"
chmod +x "$TMP_HOME/.local/bin/sgt"

cat > "$TMP_HOME/.local/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
# Simulate dead sessions.
exit 1
TMUX
chmod +x "$TMP_HOME/.local/bin/tmux"

cat > "$TMP_HOME/.local/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
counter_file="${SGT_TEST_GH_COUNTER:?}"
args=" $* "
if [[ "$args" == *" pr list "* ]]; then
  count=0
  if [[ -f "$counter_file" ]]; then
    count="$(cat "$counter_file")"
  fi
  count=$((count + 1))
  printf '%s\n' "$count" > "$counter_file"

  if [[ "$args" == *" --json number,state,title "* ]]; then
    echo $'77\tOPEN\tRace-safe metadata title'
    exit 0
  fi

  # Legacy split-call path should never be used by status now.
  if [[ "$args" == *" --json number "* ]]; then echo "77"; exit 0; fi
  if [[ "$args" == *" --json state "* ]]; then echo ""; exit 0; fi
  if [[ "$args" == *" --json title "* ]]; then echo ""; exit 0; fi
fi
exit 0
GH
chmod +x "$TMP_HOME/.local/bin/gh"

run_case() {
  local label="$1"
  local polecat_payload="$2"
  local expect_line="$3"
  local expect_count="$4"
  local out_file err_file cmd_exit counter_file

  out_file="$(mktemp)"
  err_file="$(mktemp)"
  counter_file="$(mktemp)"
  printf '0\n' > "$counter_file"

  set +e
  env -i \
    HOME="$TMP_HOME" \
    PATH="$TMP_HOME/.local/bin:/usr/bin:/bin" \
    TERM=dumb \
    SGT_TEST_GH_COUNTER="$counter_file" \
    POLECAT_PAYLOAD="$polecat_payload" \
    bash --noprofile --norc -c '
      sgt init >/dev/null
      printf "%s\n" "$POLECAT_PAYLOAD" > "$HOME/sgt/.sgt/polecats/p1"
      sgt status
    ' >"$out_file" 2>"$err_file"
  cmd_exit=$?
  set -e

  if [[ "$cmd_exit" -ne 0 ]]; then
    echo "FAIL: $label exited $cmd_exit (expected 0)"
    [[ -s "$err_file" ]] && cat "$err_file"
    [[ -s "$out_file" ]] && cat "$out_file"
    rm -f "$out_file" "$err_file" "$counter_file"
    exit 1
  fi

  if [[ -s "$err_file" ]]; then
    echo "FAIL: $label emitted stderr"
    cat "$err_file"
    rm -f "$out_file" "$err_file" "$counter_file"
    exit 1
  fi

  if ! grep -q "$expect_line" "$out_file"; then
    echo "FAIL: $label missing expected line: $expect_line"
    cat "$out_file"
    rm -f "$out_file" "$err_file" "$counter_file"
    exit 1
  fi

  local gh_calls
  gh_calls="$(cat "$counter_file")"
  if [[ "$gh_calls" != "$expect_count" ]]; then
    echo "FAIL: $label expected gh pr list calls=$expect_count, got $gh_calls"
    cat "$out_file"
    rm -f "$out_file" "$err_file" "$counter_file"
    exit 1
  fi

  rm -f "$out_file" "$err_file" "$counter_file"
  echo "PASS: $label"
}

echo "=== status metadata/race guard regression ==="
run_case \
  "missing branch metadata is non-fatal and actionable" \
  $'SESSION=sgt-polecat-p1\nREPO=acme/roadrunner\nISSUE=74' \
  'metadata missing: BRANCH' \
  "0"

run_case \
  "dead polecat PR metadata uses single deterministic query" \
  $'SESSION=sgt-polecat-p1\nREPO=acme/roadrunner\nBRANCH=feature/race\nISSUE=74' \
  'PR#77 OPEN' \
  "1"

echo "ALL TESTS PASSED"
