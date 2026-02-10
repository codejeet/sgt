#!/usr/bin/env bash
# test_refinery_stale_close_event_hard_stop.sh — Regression checks for late CLOSED/MERGED replay hard-stop at dispatch instant.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

run_case() {
  local final_pr_state="$1"
  local case_root="$TMP_ROOT/${final_pr_state,,}"
  local home_dir="$case_root/home"
  local mock_bin="$case_root/mockbin"
  local pr_state_calls="$case_root/pr-state-calls"
  local tmux_new_session_marker="$case_root/tmux-new-session"
  mkdir -p "$home_dir/.local/bin" "$mock_bin"
  cp "$SGT_SCRIPT" "$home_dir/.local/bin/sgt"
  chmod +x "$home_dir/.local/bin/sgt"
  : > "$pr_state_calls"

  cat > "$mock_bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

PR_STATE_CALLS_FILE="${SGT_MOCK_PR_STATE_CALLS:?missing SGT_MOCK_PR_STATE_CALLS}"
FINAL_PR_STATE="${SGT_MOCK_FINAL_PR_STATE:?missing SGT_MOCK_FINAL_PR_STATE}"

inc_file() {
  local path="$1"
  local n=0
  if [[ -s "$path" ]]; then
    n="$(cat "$path" 2>/dev/null || echo 0)"
  fi
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  n=$((n + 1))
  printf '%s\n' "$n" > "$path"
  echo "$n"
}

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  shift 2
  json_fields=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json_fields="${2:-}"
        shift 2
        ;;
      --jq)
        shift 2
        ;;
      --repo)
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  case "$json_fields" in
    labels) echo "sgt-authorized" ;;
    title) echo "Stale close replay hard-stop issue" ;;
    state) echo "OPEN" ;;
    body) echo "Issue body" ;;
    *) echo "" ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  shift 2
  json_fields=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json_fields="${2:-}"
        shift 2
        ;;
      --jq)
        shift 2
        ;;
      --repo)
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  case "$json_fields" in
    title)
      echo "Stale close replay hard-stop PR"
      ;;
    state)
      call_n="$(inc_file "$PR_STATE_CALLS_FILE")"
      if [[ "$call_n" -le 2 ]]; then
        echo "OPEN"
      else
        echo "$FINAL_PR_STATE"
      fi
      ;;
    state,mergeable)
      call_n="$(inc_file "$PR_STATE_CALLS_FILE")"
      if [[ "$call_n" -le 2 ]]; then
        echo "OPEN|MERGEABLE"
      else
        echo "${FINAL_PR_STATE}|UNKNOWN"
      fi
      ;;
    mergeable)
      # Trigger refinery conflict handling and queued redispatch path.
      echo "CONFLICTING"
      ;;
    *)
      echo ""
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "checks" ]]; then
  echo "all checks pass"
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "comment" ]]; then
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "close" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "reopen" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  exit 0
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
  chmod +x "$mock_bin/gh"

  cat > "$mock_bin/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

MARKER="${SGT_MOCK_TMUX_NEW_SESSION_MARKER:?missing SGT_MOCK_TMUX_NEW_SESSION_MARKER}"

if [[ "${1:-}" == "new-session" ]]; then
  touch "$MARKER"
  exit 0
fi

if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi

exit 0
TMUX
  chmod +x "$mock_bin/tmux"

  cat > "$mock_bin/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail

args=("$@")
if [[ "${args[0]:-}" == "-C" ]]; then
  args=("${args[@]:2}")
fi

if [[ "${args[0]:-}" == "symbolic-ref" ]]; then
  echo "refs/remotes/origin/main"
  exit 0
fi

if [[ "${args[0]:-}" == "fetch" ]]; then
  exit 0
fi

if [[ "${args[0]:-}" == "worktree" && "${args[1]:-}" == "add" ]]; then
  target=""
  for ((i=0; i<${#args[@]}; i++)); do
    if [[ "${args[$i]}" == "-b" ]]; then
      target="${args[$((i + 2))]:-}"
      break
    fi
  done
  [[ -n "$target" ]] && mkdir -p "$target"
  exit 0
fi

if [[ "${args[0]:-}" == "worktree" && "${args[1]:-}" == "remove" ]]; then
  last_idx=$(( ${#args[@]} - 1 ))
  rm -rf "${args[$last_idx]:-}"
  exit 0
fi

if [[ "${args[0]:-}" == "branch" ]]; then
  exit 0
fi

exit 0
GIT
  chmod +x "$mock_bin/git"

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_MOCK_PR_STATE_CALLS="$pr_state_calls" \
    SGT_MOCK_FINAL_PR_STATE="$final_pr_state" \
    SGT_MOCK_TMUX_NEW_SESSION_MARKER="$tmux_new_session_marker" \
    bash --noprofile --norc -c '
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"

cat > "$SGT_ROOT/.sgt/merge-queue/test-pr123" <<MQ
POLECAT=test-pr123
RIG=test
REPO=https://github.com/acme/demo
BRANCH=sgt/test-pr123
ISSUE=77
PR=123
HEAD_SHA=abc123
AUTO_MERGE=true
TYPE=polecat
QUEUED=$(date -Iseconds)
MQ

timeout 6 sgt _refinery test > "$SGT_ROOT/refinery.out" 2>&1 &
pid=$!

for _ in $(seq 1 120); do
  fifo="$SGT_ROOT/.sgt/refinery-test.fifo"
  if [[ -p "$fifo" ]]; then
    printf "test-wake\n" > "$fifo"
    break
  fi
  sleep 0.05
done

wait "$pid" || true
'

  local out_file="$home_dir/sgt/refinery.out"
  local log_file="$home_dir/sgt/sgt.log"

  if [[ -f "$tmux_new_session_marker" ]]; then
    echo "expected dispatch hard-stop for late $final_pr_state replay, but new session was spawned" >&2
    exit 1
  fi

  if ! grep -q 'dispatch hard-stop' "$out_file"; then
    echo "expected dispatch hard-stop message in refinery output for $final_pr_state replay" >&2
    exit 1
  fi

  if ! grep -q "source PR #123 state=$final_pr_state" "$out_file"; then
    echo "expected stale-close reason to include source PR state=$final_pr_state" >&2
    exit 1
  fi

  if ! grep -q 'RESLING_SKIP_STALE issue=#77 rig=test gate=dispatch-instant source_event=refinery-conflict source_event_key=refinery-conflict source_pr=123 skip_reason=source-pr-not-open' "$log_file"; then
    echo "expected structured dispatch-instant stale skip log entry for $final_pr_state replay" >&2
    exit 1
  fi

  if [[ -n "$(ls -A "$home_dir/sgt/.sgt/polecats" 2>/dev/null || true)" ]]; then
    echo "expected no new polecat state files after dispatch hard-stop ($final_pr_state)" >&2
    exit 1
  fi
}

run_case "MERGED"
run_case "CLOSED"

echo "ALL TESTS PASSED"
