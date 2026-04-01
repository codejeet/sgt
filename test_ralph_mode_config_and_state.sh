#!/usr/bin/env bash
# test_ralph_mode_config_and_state.sh — Ralph config/state model, lane accounting, and anti-false-completion regression coverage.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail
active_session="${SGT_TEST_ACTIVE_SESSION:-}"
case "${1:-}" in
  has-session)
    if [[ "${3:-}" == "$active_session" ]]; then
      exit 0
    fi
    exit 1
    ;;
  kill-session|new-session)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
TMUX
chmod +x "$MOCK_BIN/tmux"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

issues_file="${SGT_TEST_ISSUES_JSON:?missing SGT_TEST_ISSUES_JSON}"
args=" $* "

if [[ "$args" == *" issue list "* ]]; then
  if [[ "$args" == *" --json number,labels,title "* ]]; then
    cat "$issues_file"
    exit 0
  fi
  if [[ "$args" == *" --json number "* ]] && [[ "$args" == *" --jq "* ]]; then
    python3 - "$issues_file" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    issues = json.load(fh)
print(len(issues))
PY
    exit 0
  fi
fi

if [[ "$args" == *" issue view "* ]] && [[ "$args" == *" --json state "* ]]; then
  echo "OPEN"
  exit 0
fi

if [[ "$args" == *" pr list "* ]] && [[ "$args" == *" --json number "* ]] && [[ "$args" == *" --jq "* ]]; then
  echo "0"
  exit 0
fi

if [[ "$args" == *" pr list "* ]] && [[ "$args" == *" --json number,state,title "* ]]; then
  echo ""
  exit 0
fi

if [[ "$args" == *" label create "* ]] || [[ "$args" == *" issue create "* ]] || [[ "$args" == *" issue edit "* ]]; then
  exit 0
fi

exit 0
GH
chmod +x "$MOCK_BIN/gh"

cat > "$MOCK_BIN/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
exit 0
GIT
chmod +x "$MOCK_BIN/git"

cat > "$TMP_ROOT/issues.json" <<'JSON'
[
  {
    "number": 11,
    "title": "Explore materially different lane",
    "labels": [
      {"name": "sgt-authorized"},
      {"name": "research"}
    ]
  },
  {
    "number": 12,
    "title": "Cleanup support lane",
    "labels": [
      {"name": "sgt-authorized"},
      {"name": "support-only"}
    ]
  },
  {
    "number": 13,
    "title": "Duplicate lane",
    "labels": [
      {"name": "sgt-authorized"},
      {"name": "duplicate"}
    ]
  }
]
JSON

ENV_PREFIX=(
  env -i
  HOME="$HOME_DIR"
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin"
  TERM=dumb
  SGT_ROOT="$HOME_DIR/sgt"
  SGT_TEST_ISSUES_JSON="$TMP_ROOT/issues.json"
  SGT_TEST_ACTIVE_SESSION="sgt-demo-worker"
)

"${ENV_PREFIX[@]}" bash --noprofile --norc <<'BASH'
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs" "$SGT_ROOT/.sgt/polecats" "$SGT_ROOT/rigs/demo"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/demo"
cat > "$SGT_ROOT/.sgt/polecats/demo-worker" <<'STATE'
RIG=demo
REPO=https://github.com/acme/demo
ISSUE=11
BRANCH=sgt/demo-worker
WORKTREE=/tmp/demo-worker
SESSION=sgt-demo-worker
STATE

cat > "$SGT_ROOT/rigs/demo/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "demo",
  "policy": { "max_in_flight": 1 },
  "completion_condition": "Fresh-state proof passes.",
  "acceptance": {
    "status": "verified",
    "details": "Latest main already looked green.",
    "verified_at": "2026-03-31T08:15:00Z"
  },
  "tasks": []
}
JSON

sgt config ralph demo --enable --condition "1K PNL for 5m btc pipeline" --target 2 >/dev/null
sgt plan tick demo >/dev/null 2>&1
sgt status > "$SGT_ROOT/status-before.txt"
sgt status --json > "$SGT_ROOT/status-before.json"

BLOCKER_FILE="$SGT_ROOT/.sgt/plan-blockers/demo--__continuation__.env"
[[ -f "$BLOCKER_FILE" ]] || {
  echo "expected Ralph continuation blocker to be recorded while live lanes stay below target" >&2
  exit 1
}

grep -q 'ralph: state=underfilled target=2 active_lanes=1 admissible=1 backlog=0 support_excluded=1 duplicate_excluded=1 underfilled=1 condition_status=unmet' "$SGT_ROOT/status-before.txt" || {
  echo "expected human status to show Ralph live state" >&2
  exit 1
}

grep -q 'ralph condition: 1K PNL for 5m btc pipeline' "$SGT_ROOT/status-before.txt" || {
  echo "expected human status to show Ralph condition text" >&2
  exit 1
}

grep -q 'RIG_RALPH_MODE_SET rig=demo enabled=true condition_status=unmet target=2 count_support_lanes=false' "$SGT_ROOT/sgt.log" || {
  echo "expected Ralph config changes to be written to the durable event log" >&2
  exit 1
}

python3 - "$SGT_ROOT/status-before.json" "$SGT_ROOT/.sgt/plan-state/demo.json" "$BLOCKER_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    status = json.load(fh)
with open(sys.argv[2], "r", encoding="utf-8") as fh:
    plan_state = json.load(fh)
blocker = {}
with open(sys.argv[3], "r", encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        blocker[key] = value

mayor_rigs = status.get("mayor_rigs") or []
demo = next((item for item in mayor_rigs if item.get("rig") == "demo"), None)
assert demo is not None, mayor_rigs
ralph = demo.get("ralph") or {}
assert ralph.get("enabled") is True, ralph
assert ralph.get("condition") == "1K PNL for 5m btc pipeline", ralph
assert ralph.get("target_concurrency") == 2, ralph
assert ralph.get("active_lane_count") == 1, ralph
assert ralph.get("admissible_lane_count") == 1, ralph
assert ralph.get("support_lane_count") == 1, ralph
assert ralph.get("duplicate_lane_count") == 1, ralph
assert ralph.get("underfilled") is True, ralph

completion = plan_state.get("completion") or {}
assert completion.get("status") == "pending", completion
assert completion.get("rollup") == "ralph-underfilled", completion
assert "Ralph mode remains active" in completion.get("details", ""), completion
assert completion.get("blocked_reason") == "ralph condition unmet: 1K PNL for 5m btc pipeline", completion
acceptance = completion.get("acceptance") or {}
assert acceptance.get("status") == "pending", acceptance
assert acceptance.get("declared_status") == "verified", acceptance
assert acceptance.get("declared_verified_at") == "2026-03-31T08:15:00Z", acceptance
assert "verified_at" not in acceptance, acceptance
assert blocker.get("TASK_ID") == "__continuation__", blocker
assert blocker.get("REASON_CODE") == "continuation-underfilled", blocker
assert "Ralph continuation intent remains active" in blocker.get("REASON", ""), blocker
assert "live_polecats=1" in blocker.get("REASON", ""), blocker
assert "target=2" in blocker.get("REASON", ""), blocker

plan_ralph = plan_state.get("ralph") or {}
assert plan_ralph.get("target_concurrency") == 2, plan_ralph
assert plan_ralph.get("active_lane_count") == 1, plan_ralph
PY

sgt config ralph demo --count-support yes >/dev/null
sgt status --json > "$SGT_ROOT/status-after.json"

grep -q 'RIG_RALPH_MODE_SET rig=demo enabled=true condition_status=unmet target=2 count_support_lanes=true' "$SGT_ROOT/sgt.log" || {
  echo "expected Ralph support-lane changes to be written to the durable event log" >&2
  exit 1
}

python3 - "$SGT_ROOT/status-after.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    status = json.load(fh)

mayor_rigs = status.get("mayor_rigs") or []
demo = next((item for item in mayor_rigs if item.get("rig") == "demo"), None)
assert demo is not None, mayor_rigs
ralph = demo.get("ralph") or {}
assert ralph.get("count_support_lanes") is True, ralph
assert ralph.get("admissible_lane_count") == 2, ralph
assert ralph.get("support_lane_count") == 0, ralph
assert ralph.get("duplicate_lane_count") == 1, ralph
assert ralph.get("backlog_lane_count") == 1, ralph
PY

python3 - "$SGT_ROOT/rigs/demo/SGT_PLAN.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    plan = json.load(fh)

plan["acceptance"] = {
    "status": "blocked",
    "details": "Candidate no-go evidence needs a replacement lane.",
    "blocked_at": "2026-03-31T09:45:00Z",
    "blocked_reason": "candidate no-go from witness"
}

with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(plan, fh, ensure_ascii=True, indent=2, sort_keys=True)
    fh.write("\n")
PY

sgt plan tick demo >/dev/null 2>&1

python3 - "$SGT_ROOT/.sgt/plan-state/demo.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    plan_state = json.load(fh)

completion = plan_state.get("completion") or {}
assert completion.get("status") == "pending", completion
assert completion.get("rollup") == "ralph-underfilled", completion
assert completion.get("blocked_reason") == "ralph condition unmet: 1K PNL for 5m btc pipeline", completion
acceptance = completion.get("acceptance") or {}
assert acceptance.get("status") == "pending", acceptance
assert acceptance.get("declared_status") == "blocked", acceptance
assert acceptance.get("declared_blocked_at") == "2026-03-31T09:45:00Z", acceptance
assert acceptance.get("declared_blocked_reason") == "candidate no-go from witness", acceptance
assert "blocked_at" not in acceptance, acceptance
assert "blocked_reason" not in acceptance, acceptance
PY
BASH

echo "ALL TESTS PASSED"
