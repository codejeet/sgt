#!/usr/bin/env bash
# test_oversized_dispatch_payload_prompt_file.sh — Oversized polecat prompts must live in files, not tmux command strings.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

TMP_HOME="$TMP_ROOT/home"
mkdir -p "$TMP_HOME/mock-bin" "$TMP_HOME/.local/bin"

cat > "$TMP_HOME/mock-bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}:${2:-}"
case "$cmd" in
  label:create)
    exit 0
    ;;
  issue:create)
    echo "https://github.com/acme/demo/issues/251"
    exit 0
    ;;
  issue:view)
    if [[ " $* " == *" --json labels "* ]]; then
      printf 'sgt-authorized\n'
    elif [[ " $* " == *" --json title "* ]]; then
      printf 'oversized payload regression\n'
    else
      printf 'OPEN\n'
    fi
    exit 0
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
  TMUX_LOG_FILE="$TMP_HOME/tmux.log" \
  SGT_AI_BACKEND=codex \
  SGT_REQUIRE_AUTH_LABEL=0 \
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
EOF_README
cat > "$repo_dir/CLAUDE.md" <<'EOF_CLAUDE'
# Project Context
EOF_CLAUDE
cat > "$repo_dir/SGT_CONTEXT.md" <<'EOF_CONTEXT'
# SGT Project Context
EOF_CONTEXT
git -C "$repo_dir" add README.md CLAUDE.md SGT_CONTEXT.md
git -C "$repo_dir" commit -m "test fixture" >/dev/null

huge_title="Oversized payload regression $(printf 'X%.0s' $(seq 1 25000))"

cmd_sling "demo" "$huge_title" --backend codex >/dev/null
first_polecat="${_SGT_LAST_SLING_POLECAT:?missing sling polecat}"
first_prompt="$HOME/sgt/polecats/$first_polecat/.sgt-polecat-prompt.md"

grep -q "$huge_title" "$first_prompt" || { echo "expected sling prompt file to contain oversized title" >&2; exit 1; }
grep -q '\.sgt-polecat-prompt\.md' "$HOME/tmux.log" || { echo "expected sling tmux command to reference prompt file" >&2; exit 1; }
if grep -q "$huge_title" "$HOME/tmux.log"; then
  echo "expected sling tmux command to omit oversized title" >&2
  exit 1
fi
if [[ "$(wc -c < "$HOME/tmux.log" | tr -d ' ')" -ge 6000 ]]; then
  echo "expected sling tmux command log to stay small even for oversized payloads" >&2
  exit 1
fi

rm -f "$HOME/sgt/.sgt/polecats/$first_polecat"
rm -rf "$HOME/sgt/polecats/$first_polecat"
rm -f "$HOME/tmux.log"

_resling_existing_issue "demo" "251" "$huge_title" "https://github.com/acme/demo" "codex" "" "oversized-resling" "oversized-resling:issue-251"
second_polecat="${_RESLING_LAST_POLECAT:?missing resling polecat}"
second_prompt="$HOME/sgt/polecats/$second_polecat/.sgt-polecat-prompt.md"

grep -q "$huge_title" "$second_prompt" || { echo "expected resling prompt file to contain oversized title" >&2; exit 1; }
grep -q '\.sgt-polecat-prompt\.md' "$HOME/tmux.log" || { echo "expected resling tmux command to reference prompt file" >&2; exit 1; }
if grep -q "$huge_title" "$HOME/tmux.log"; then
  echo "expected resling tmux command to omit oversized title" >&2
  exit 1
fi
if [[ "$(wc -c < "$HOME/tmux.log" | tr -d ' ')" -ge 6000 ]]; then
  echo "expected resling tmux command log to stay small even for oversized payloads" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
BASH
