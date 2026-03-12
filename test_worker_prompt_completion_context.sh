#!/usr/bin/env bash
# test_worker_prompt_completion_context.sh — Worker prompts must include plan completion context on sling and re-sling paths.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/mock-bin" "$TMP_HOME/state/issues"

cat > "$TMP_HOME/mock-bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${GH_STATE_DIR:?missing GH_STATE_DIR}"
ISSUES_DIR="$STATE_DIR/issues"
NEXT_FILE="$STATE_DIR/next-issue"
mkdir -p "$ISSUES_DIR"

cmd="${1:-}"
sub="${2:-}"
shift 2 || true

case "$cmd:$sub" in
  label:create)
    exit 0
    ;;
  issue:create)
    next=1
    if [[ -f "$NEXT_FILE" ]]; then
      next="$(cat "$NEXT_FILE")"
    fi
    title=""
    body=""
    repo=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo)
          repo="$2"
          shift 2
          ;;
        --title)
          title="$2"
          shift 2
          ;;
        --body)
          body="$2"
          shift 2
          ;;
        --label)
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    printf 'STATE=%q\nTITLE=%q\nBODY=%q\nREPO=%q\nLABELS=%q\n' \
      "OPEN" "$title" "$body" "$repo" "sgt-authorized" > "$ISSUES_DIR/$next.env"
    echo $((next + 1)) > "$NEXT_FILE"
    printf 'https://github.com/acme/demo/issues/%s\n' "$next"
    ;;
  issue:view)
    issue_number="${1:-}"
    issue_number="${issue_number#\#}"
    shift || true
    issue_file="$ISSUES_DIR/$issue_number.env"
    [[ -f "$issue_file" ]] || exit 1
    # shellcheck disable=SC1090
    source "$issue_file"
    json=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --json)
          json="$2"
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
    case "$json" in
      state)
        printf '%s\n' "${STATE:-OPEN}"
        ;;
      title)
        printf '%s\n' "${TITLE:-}"
        ;;
      labels)
        printf '%s\n' "sgt-authorized"
        ;;
      body)
        printf '%s\n' "${BODY:-}"
        ;;
      *)
        printf '%s\n' "${STATE:-OPEN}"
        ;;
    esac
    ;;
  issue:list|issue:edit|issue:comment|pr:view|pr:list|api:*)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMP_HOME/mock-bin/gh"

cat > "$TMP_HOME/mock-bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="${TMUX_LOG_FILE:?missing TMUX_LOG_FILE}"
case "${1:-}" in
  has-session)
    exit 1
    ;;
  new-session)
    printf '%s\n' "$*" >> "$LOG_FILE"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMP_HOME/mock-bin/tmux"

cat > "$TMP_HOME/mock-bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$TMP_HOME/mock-bin/codex"

LIB_SCRIPT="$TMP_HOME/sgt-lib.sh"
sed '$d' "$SGT_SCRIPT" > "$LIB_SCRIPT"

env -i \
  HOME="$TMP_HOME" \
  PATH="$TMP_HOME/mock-bin:/usr/local/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm}" \
  GH_STATE_DIR="$TMP_HOME/state" \
  TMUX_LOG_FILE="$TMP_HOME/tmux.log" \
  SGT_AI_BACKEND=codex \
  SGT_MAYOR_DISPATCH_COOLDOWN=0 \
  bash --noprofile --norc <<'BASH'
set -euo pipefail

source "$HOME/sgt-lib.sh"

cmd_init >/dev/null
mkdir -p "$HOME/sgt/.sgt/rigs" "$HOME/sgt/rigs/demo"
printf '%s\n' 'https://github.com/acme/demo' > "$HOME/sgt/.sgt/rigs/demo"

repo_dir="$HOME/sgt/rigs/demo"
git -C "$repo_dir" init -b main >/dev/null
git -C "$repo_dir" config user.name "SGT Test"
git -C "$repo_dir" config user.email "sgt@example.com"
cat > "$repo_dir/README.md" <<'EOF_README'
# Demo

This README excerpt should be present in worker prompts.
EOF_README
cat > "$repo_dir/CLAUDE.md" <<'EOF_CLAUDE'
# Project Context
EOF_CLAUDE
cat > "$repo_dir/SGT_CONTEXT.md" <<'EOF_CONTEXT'
# SGT Project Context
EOF_CONTEXT
cat > "$repo_dir/SGT_PLAN.json" <<'EOF_PLAN'
{
  "version": 1,
  "rig": "demo",
  "completion_condition": "Run a fresh-state verification on latest main and confirm the workflow succeeds.",
  "acceptance": {
    "status": "pending",
    "details": "Fresh-state verification is still required after merges."
  },
  "tasks": [
    { "id": "worker-prompts", "title": "Inject completion context into worker prompts" }
  ]
}
EOF_PLAN
git -C "$repo_dir" add README.md CLAUDE.md SGT_CONTEXT.md SGT_PLAN.json
git -C "$repo_dir" commit -m "test fixture" >/dev/null

_acceptance_blocker_write "demo" "Verified acceptance is still red after merge." "tester" "argv" >/dev/null

cmd_sling "demo" "Inject completion context into worker prompts" --backend codex >/dev/null
first_polecat="${_SGT_LAST_SLING_POLECAT:?missing first polecat}"
first_claude="$HOME/sgt/polecats/$first_polecat/CLAUDE.md"

grep -q '## Rig Completion Context' "$first_claude" || { echo "missing rig completion context in sling CLAUDE" >&2; exit 1; }
grep -q 'Run a fresh-state verification on latest main and confirm the workflow succeeds.' "$first_claude" || { echo "missing completion condition in sling CLAUDE" >&2; exit 1; }
grep -q '\*\*Acceptance status\*\*: pending' "$first_claude" || { echo "missing acceptance status in sling CLAUDE" >&2; exit 1; }
grep -q '\*\*Unresolved acceptance blockers\*\*: yes (1 active)' "$first_claude" || { echo "missing acceptance blocker summary in sling CLAUDE" >&2; exit 1; }
grep -q 'merged intermediate work is not rig completion' "$first_claude" || { echo "missing merged-work rule in sling CLAUDE" >&2; exit 1; }

grep -q 'Rig Completion Context' "$HOME/tmux.log" || { echo "missing rig completion context in sling runtime prompt" >&2; exit 1; }
grep -q 'Run a fresh-state verification on latest main and confirm the workflow succeeds.' "$HOME/tmux.log" || { echo "missing completion condition in sling runtime prompt" >&2; exit 1; }

rm -f "$HOME/sgt/.sgt/polecats/$first_polecat"
rm -rf "$HOME/sgt/polecats/$first_polecat"
rm -f "$HOME/tmux.log"

_resling_existing_issue "demo" "1" "Inject completion context into worker prompts" "https://github.com/acme/demo" "codex" "" "test-resling" "test-resling:issue-1"
second_polecat="${_RESLING_LAST_POLECAT:?missing reslung polecat}"
second_claude="$HOME/sgt/polecats/$second_polecat/CLAUDE.md"

grep -q '## Rig Completion Context' "$second_claude" || { echo "missing rig completion context in resling CLAUDE" >&2; exit 1; }
grep -q 'Run a fresh-state verification on latest main and confirm the workflow succeeds.' "$second_claude" || { echo "missing completion condition in resling CLAUDE" >&2; exit 1; }
grep -q '\*\*Acceptance status\*\*: pending' "$second_claude" || { echo "missing acceptance status in resling CLAUDE" >&2; exit 1; }
grep -q '\*\*Unresolved acceptance blockers\*\*: yes (1 active)' "$second_claude" || { echo "missing acceptance blocker summary in resling CLAUDE" >&2; exit 1; }

grep -q 'Rig Completion Context' "$HOME/tmux.log" || { echo "missing rig completion context in resling runtime prompt" >&2; exit 1; }
grep -q 'Run a fresh-state verification on latest main and confirm the workflow succeeds.' "$HOME/tmux.log" || { echo "missing completion condition in resling runtime prompt" >&2; exit 1; }

echo "ALL TESTS PASSED"
BASH
