#!/usr/bin/env bash
# Regression: sweep/watchdog must not revive a stale open plan-task issue after the repo-local task changed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/.local/bin" "$TMP_HOME/mock-bin"
cp "$SGT_SCRIPT" "$TMP_HOME/.local/bin/sgt"
chmod +x "$TMP_HOME/.local/bin/sgt"

cat > "$TMP_HOME/mock-bin/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$TMP_HOME/mock-bin/openclaw"

cat > "$TMP_HOME/mock-bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  has-session)
    exit 1
    ;;
  new-session|kill-session)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMP_HOME/mock-bin/tmux"

cat > "$TMP_HOME/mock-bin/git" <<'EOF'
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
    echo "refs/remotes/origin/main"
    exit 0
    ;;
  worktree)
    shift
    case "${1:-}" in
      add)
        shift
        if [[ "${1:-}" == "-b" ]]; then
          worktree="${3:-}"
        else
          worktree="${1:-}"
        fi
        mkdir -p "$worktree"
        exit 0
        ;;
      remove)
        exit 0
        ;;
    esac
    ;;
esac
exit 0
EOF
chmod +x "$TMP_HOME/mock-bin/git"

cat > "$TMP_HOME/mock-bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command="${1:-}"
subcommand="${2:-}"
shift 2 || true

case "$command:$subcommand" in
  label:create|issue:edit|pr:list|api:*)
    exit 0
    ;;
  issue:list)
    state_filter="open"
    label=""
    jq_expr=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --state) state_filter="${2:-}"; shift 2 ;;
        --label) label="${2:-}"; shift 2 ;;
        --json) shift 2 ;;
        --jq) jq_expr="${2:-}"; shift 2 ;;
        --limit|--repo) shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ "$state_filter" == "open" && "$label" == "sgt-authorized" ]]; then
      if [[ -n "$jq_expr" ]]; then
        printf '42\tDuplicate-closed continuation lane\n'
      else
        cat <<'JSON'
[
  {
    "number": 42,
    "title": "Duplicate-closed continuation lane"
  }
]
JSON
      fi
    else
      echo '[]'
    fi
    ;;
  issue:view)
    issue_number="${1:-}"
    issue_number="${issue_number#\#}"
    shift || true
    json_fields=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --json) json_fields="${2:-}"; shift 2 ;;
        --jq|--repo) shift 2 ;;
        *) shift ;;
      esac
    done
    case "$issue_number:$json_fields" in
      42:title,body,labels)
        cat <<'JSON'
{"title":"Duplicate-closed continuation lane","body":"## Task\n\nDuplicate-closed continuation lane\n","labels":[{"name":"sgt-authorized"},{"name":"plan-ACC2"}]}
JSON
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMP_HOME/mock-bin/gh"

COMMON_ENV=(
  "HOME=$TMP_HOME"
  "PATH=$TMP_HOME/mock-bin:$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
  "TERM=${TERM:-xterm}"
)

env -i "${COMMON_ENV[@]}" bash --noprofile --norc <<'BASH'
set -euo pipefail

sgt init >/dev/null
mkdir -p "$HOME/sgt/.sgt/rigs" "$HOME/sgt/rigs/demo"
printf '%s\n' 'https://github.com/acme/demo' > "$HOME/sgt/.sgt/rigs/demo"

cat > "$HOME/sgt/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 1 },
  "tasks": [
    { "id": "ACC2", "title": "Relaunch materially different continuation lane", "task": "Dispatch a successor lane with new continuation evidence" }
  ]
}
JSON

sgt sweep > "$HOME/sweep.out" 2>&1
BASH

if find "$TMP_HOME/sgt/.sgt/polecats" -type f | grep -q .; then
  echo "expected no replacement polecat state for stale plan issue" >&2
  find "$TMP_HOME/sgt/.sgt/polecats" -type f >&2
  exit 1
fi

grep -q 'SWEEP_WATCHDOG_RESLING_SKIP issue=#42 rig=demo repo=acme/demo reason_code=plan-task-mismatch task_id=ACC2' "$TMP_HOME/sgt/sgt.log" || {
  echo "expected stale plan-task mismatch skip in sweep watchdog log" >&2
  cat "$TMP_HOME/sgt/sgt.log" >&2
  exit 1
}

echo "ALL TESTS PASSED"
