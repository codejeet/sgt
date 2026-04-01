#!/usr/bin/env bash
# Regression: plan tick should record a continuation blocker when acceptance stays pending and live polecats are below target.

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
exit 0
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
  rev-parse)
    if [[ "${2:-}" == "--abbrev-ref" ]]; then
      echo "main"
    else
      echo "deadbeef"
    fi
    exit 0
    ;;
  status)
    exit 0
    ;;
  show)
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMP_HOME/mock-bin/git"

cat > "$TMP_HOME/mock-bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}:${2:-}" in
  label:create|issue:list|pr:list|api:*)
    exit 0
    ;;
  issue:view)
    echo "CLOSED"
    exit 0
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
  "policy": { "max_in_flight": 2 },
  "completion_condition": "Keep refilling until acceptance is verified.",
  "acceptance": {
    "status": "pending",
    "details": "Continuation should stay live while acceptance is still open."
  },
  "tasks": [
    { "id": "ACC2", "title": "Continuation lane already merged", "depends_on": [] }
  ]
}
JSON

cat > "$HOME/sgt/.sgt/plan-state/demo.json" <<'JSON'
{
  "tasks": {
    "ACC2": {
      "status": "completed",
      "issue_number": "42",
      "issue_url": "https://github.com/acme/demo/issues/42"
    }
  },
  "completion": {
    "status": "pending",
    "rollup": "tasks-in-progress"
  }
}
JSON

sgt plan tick demo > "$HOME/plan-tick.out" 2>&1
BASH

BLOCKER_FILE="$TMP_HOME/sgt/.sgt/plan-blockers/demo--__continuation__.env"
STATE_FILE="$TMP_HOME/sgt/.sgt/plan-state/demo.json"

[[ -f "$BLOCKER_FILE" ]] || {
  echo "expected continuation blocker file to be created" >&2
  exit 1
}

python3 - "$BLOCKER_FILE" "$STATE_FILE" <<'PY'
import json
import sys

blocker = {}
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        blocker[key] = value

with open(sys.argv[2], "r", encoding="utf-8") as fh:
    state = json.load(fh)

assert blocker["TASK_ID"] == "__continuation__", blocker
assert blocker["STATUS"] == "open", blocker
assert blocker["REASON_CODE"] == "continuation-underfilled", blocker
assert "live_polecats=0" in blocker["REASON"], blocker
assert "target=2" in blocker["REASON"], blocker

completion = state["completion"]
assert completion["status"] == "pending", completion
assert completion["rollup"] == "tasks-exhausted-awaiting-acceptance", completion
PY

grep -q 'completion=tasks-exhausted-awaiting-acceptance status=pending' "$TMP_HOME/plan-tick.out" || {
  echo "expected plan tick summary to retain tasks-exhausted-awaiting-acceptance" >&2
  cat "$TMP_HOME/plan-tick.out" >&2
  exit 1
}

echo "ALL TESTS PASSED"
