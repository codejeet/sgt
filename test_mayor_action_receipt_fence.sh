#!/usr/bin/env bash
# test_mayor_action_receipt_fence.sh — Regression checks for mayor post-action receipt fence (drift + replay).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

run_dispatch_drift_case() {
  local case_root="$TMP_ROOT/dispatch-drift"
  local home_dir="$case_root/home"
  local mock_bin="$case_root/mockbin"
  mkdir -p "$home_dir/.local/bin" "$mock_bin"
  cp "$SGT_SCRIPT" "$home_dir/.local/bin/sgt"
  chmod +x "$home_dir/.local/bin/sgt"

  cat > "$mock_bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "label" && "${2:-}" == "create" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "create" ]]; then
  echo "https://github.com/acme/demo/issues/101"
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  if [[ "$*" == *"--json state"* ]]; then
    echo "CLOSED"
    exit 0
  fi
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "edit" ]]; then
  exit 0
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
  chmod +x "$mock_bin/gh"

  cat > "$mock_bin/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-C" ]]; then
  shift 2
fi

case "${1:-}" in
  fetch)
    exit 0
    ;;
  symbolic-ref)
    echo "refs/remotes/origin/master"
    exit 0
    ;;
  worktree)
    if [[ "${2:-}" == "add" ]]; then
      mkdir -p "${5:-}"
      exit 0
    fi
    ;;
esac

echo "mock git unsupported: $*" >&2
exit 1
GIT
  chmod +x "$mock_bin/git"

  cat > "$mock_bin/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi
if [[ "${1:-}" == "new-session" || "${1:-}" == "kill-session" ]]; then
  exit 0
fi

echo "mock tmux unsupported: $*" >&2
exit 1
TMUX
  chmod +x "$mock_bin/tmux"

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_MAYOR_ACTION_FENCE=1 \
    SGT_MAYOR_DISPATCH_COOLDOWN=0 \
    bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
mkdir -p "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"
if sgt sling test "Receipt drift regression" --label high >/tmp/sgt-dispatch-drift.out 2>/tmp/sgt-dispatch-drift.err; then
  echo "expected dispatch drift case to fail receipt verification" >&2
  exit 1
fi
'

  local decision_log="$home_dir/sgt/.sgt/mayor-decisions.log"
  local receipt_dir="$home_dir/sgt/.sgt/mayor-action-receipts"
  [[ -f "$decision_log" ]] || { echo "expected decision log for dispatch drift case" >&2; exit 1; }
  [[ -d "$receipt_dir" ]] || { echo "expected receipt dir for dispatch drift case" >&2; exit 1; }

  grep -q 'MAYOR ACTION RECEIPT non-success reason=post-action-drift-issue-state retry=retry-next-mayor-cycle' "$decision_log" || {
    echo "expected explicit non-success drift reason and retry hint for dispatch" >&2
    exit 1
  }
  grep -q 'action=dispatch target=acme/demo#101 expected_state=' "$decision_log" || {
    echo "expected structured dispatch receipt fields in decision log" >&2
    exit 1
  }
  grep -q 'observed_state=' "$decision_log" || {
    echo "expected observed_state field in dispatch receipt entry" >&2
    exit 1
  }
  grep -q 'verified_at=' "$decision_log" || {
    echo "expected verified_at field in dispatch receipt entry" >&2
    exit 1
  }

  local receipt_file
  receipt_file="$(find "$receipt_dir" -type f | head -n1)"
  [[ -n "$receipt_file" ]] || { echo "expected at least one dispatch receipt file" >&2; exit 1; }
  grep -q '^ACTION=dispatch$' "$receipt_file" || { echo "expected dispatch receipt ACTION field" >&2; exit 1; }
  grep -q '^RECEIPT_STATUS=mismatch$' "$receipt_file" || { echo "expected dispatch receipt mismatch status" >&2; exit 1; }
}

run_merge_replay_case() {
  local case_root="$TMP_ROOT/merge-replay"
  local home_dir="$case_root/home"
  local mock_bin="$case_root/mockbin"
  local merge_calls="$case_root/merge-calls"
  mkdir -p "$home_dir/.local/bin" "$mock_bin"
  : > "$merge_calls"
  cp "$SGT_SCRIPT" "$home_dir/.local/bin/sgt"
  chmod +x "$home_dir/.local/bin/sgt"

  cat > "$mock_bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

CALLS_FILE="${SGT_MAYOR_MERGE_CALLS_FILE:?missing SGT_MAYOR_MERGE_CALLS_FILE}"

if [[ "${1:-}" == "pr" && "${2:-}" == "merge" ]]; then
  current="$(cat "$CALLS_FILE" 2>/dev/null || echo 0)"
  if [[ -z "$current" ]]; then
    current=0
  fi
  current=$((current + 1))
  printf '%s\n' "$current" > "$CALLS_FILE"
  echo "merged"
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  if [[ "$*" == *"--json state"* ]]; then
    echo "MERGED"
    exit 0
  fi
  if [[ "$*" == *"--json mergedAt"* ]]; then
    echo "2026-02-10T00:00:00Z"
    exit 0
  fi
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
  chmod +x "$mock_bin/gh"

  cat > "$mock_bin/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail
exit 1
TMUX
  chmod +x "$mock_bin/tmux"

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_MAYOR_ACTION_FENCE=1 \
    SGT_MAYOR_MERGE_CALLS_FILE="$merge_calls" \
    bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
sgt mayor merge 77 --repo https://github.com/acme/demo >/tmp/sgt-merge-replay-1.out
sgt mayor merge 77 --repo https://github.com/acme/demo >/tmp/sgt-merge-replay-2.out
'

  if [[ "$(cat "$merge_calls" | tr -d '[:space:]')" != "1" ]]; then
    echo "expected replayed merge action key to suppress duplicate gh pr merge side effect" >&2
    exit 1
  fi

  local decision_log="$home_dir/sgt/.sgt/mayor-decisions.log"
  local receipt_dir="$home_dir/sgt/.sgt/mayor-action-receipts"
  [[ -f "$decision_log" ]] || { echo "expected decision log for merge replay case" >&2; exit 1; }
  [[ -d "$receipt_dir" ]] || { echo "expected receipt dir for merge replay case" >&2; exit 1; }

  if [[ "$(grep -c 'MAYOR ACTION RECEIPT success action=merge' "$decision_log" || true)" -ne 1 ]]; then
    echo "expected exactly one merge success receipt decision entry" >&2
    exit 1
  fi
  grep -q 'MAYOR ACTION RECEIPT non-success reason=replayed-action-key-existing-success retry=no-op action=merge' "$decision_log" || {
    echo "expected explicit replay no-op decision entry for merge action key" >&2
    exit 1
  }

  if [[ "$(find "$receipt_dir" -type f | wc -l | tr -d ' ')" -ne 1 ]]; then
    echo "expected exactly one durable receipt file for replayed merge action key" >&2
    exit 1
  fi
  local receipt_file
  receipt_file="$(find "$receipt_dir" -type f | head -n1)"
  grep -q '^ACTION=merge$' "$receipt_file" || { echo "expected merge receipt ACTION field" >&2; exit 1; }
  grep -q '^ACTION_KEY=merge/acme/demo/pr=77$' "$receipt_file" || { echo "expected stable merge action key in receipt" >&2; exit 1; }
  grep -q '^RECEIPT_STATUS=success$' "$receipt_file" || { echo "expected merge receipt success status" >&2; exit 1; }
}

run_dispatch_drift_case
run_merge_replay_case

echo "ALL TESTS PASSED"
