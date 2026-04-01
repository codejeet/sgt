#!/usr/bin/env bash
# test_ralph_mode_realistic_rig_example.sh — Prove the documented PMKB-style Ralph example on a latest-main checkout.

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
active_sessions=",${SGT_TEST_ACTIVE_SESSIONS:-},"
case "${1:-}" in
  has-session)
    session="${3:-}"
    if [[ "$active_sessions" == *",$session,"* ]]; then
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
    "number": 701,
    "title": "PMKB BTC 5m candidate lane",
    "labels": [
      {"name": "sgt-authorized"},
      {"name": "candidate-lane"},
      {"name": "btc"}
    ]
  },
  {
    "number": 702,
    "title": "PMKB ETH 15m candidate lane",
    "labels": [
      {"name": "sgt-authorized"},
      {"name": "candidate-lane"},
      {"name": "eth"}
    ]
  },
  {
    "number": 703,
    "title": "PMKB SOL widened-corpus lane",
    "labels": [
      {"name": "sgt-authorized"},
      {"name": "candidate-lane"},
      {"name": "sol"}
    ]
  },
  {
    "number": 704,
    "title": "PMKB support metrics cleanup",
    "labels": [
      {"name": "sgt-authorized"},
      {"name": "support-only"}
    ]
  },
  {
    "number": 705,
    "title": "PMKB duplicate ETH lane",
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
  TMP_ROOT="$TMP_ROOT"
  SGT_ROOT="$HOME_DIR/sgt"
  SGT_TEST_ISSUES_JSON="$TMP_ROOT/issues.json"
  SGT_TEST_ACTIVE_SESSIONS="sgt-pmkb-btc,sgt-pmkb-eth"
)

"${ENV_PREFIX[@]}" bash --noprofile --norc <<'BASH'
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs" "$SGT_ROOT/.sgt/polecats" "$SGT_ROOT/rigs/pmkb"
printf "https://github.com/acme/pmkb\n" > "$SGT_ROOT/.sgt/rigs/pmkb"

cat > "$SGT_ROOT/.sgt/polecats/pmkb-btc" <<'STATE'
RIG=pmkb
REPO=https://github.com/acme/pmkb
ISSUE=701
BRANCH=sgt/pmkb-btc
WORKTREE=/tmp/pmkb-btc
SESSION=sgt-pmkb-btc
STATE

cat > "$SGT_ROOT/.sgt/polecats/pmkb-eth" <<'STATE'
RIG=pmkb
REPO=https://github.com/acme/pmkb
ISSUE=702
BRANCH=sgt/pmkb-eth
WORKTREE=/tmp/pmkb-eth
SESSION=sgt-pmkb-eth
STATE

cat > "$SGT_ROOT/rigs/pmkb/SGT_PLAN.json" <<'JSON'
{
  "version": 1,
  "rig": "pmkb",
  "policy": { "max_in_flight": 3 },
  "completion_condition": "Latest-main widened-corpus proof stays above +1000 USDC.",
  "acceptance": {
    "status": "verified",
    "details": "A previous latest-main proof run was green.",
    "verified_at": "2026-03-31T18:20:00Z"
  },
  "tasks": []
}
JSON

RALPH_CONDITION="Sustain net +1000 USDC on widened corpus with >=3 materially different live candidate lanes"
sgt config ralph pmkb --enable --condition "$RALPH_CONDITION" --target 3 >/dev/null
sgt plan tick pmkb >/dev/null 2>&1
sgt status > "$SGT_ROOT/status.txt"
sgt status --json > "$SGT_ROOT/status.json"

grep -q 'ralph: state=underfilled target=3 active_lanes=2 admissible=3 backlog=1 support_excluded=1 duplicate_excluded=1 underfilled=1 condition_status=unmet' "$SGT_ROOT/status.txt" || {
  echo "expected PMKB-style Ralph status line with realistic lane accounting" >&2
  exit 1
}

grep -q 'ralph condition: Sustain net +1000 USDC on widened corpus with >=3 materially different live candidate lanes' "$SGT_ROOT/status.txt" || {
  echo "expected PMKB-style Ralph condition to appear in human status output" >&2
  exit 1
}

python3 - "$SGT_ROOT/status.json" "$SGT_ROOT/.sgt/plan-state/pmkb.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    status = json.load(fh)
with open(sys.argv[2], "r", encoding="utf-8") as fh:
    plan_state = json.load(fh)

mayor_rigs = status.get("mayor_rigs") or []
pmkb = next((item for item in mayor_rigs if item.get("rig") == "pmkb"), None)
assert pmkb is not None, mayor_rigs
ralph = pmkb.get("ralph") or {}
assert ralph.get("enabled") is True, ralph
assert ralph.get("state") == "underfilled", ralph
assert ralph.get("target_concurrency") == 3, ralph
assert ralph.get("active_lane_count") == 2, ralph
assert ralph.get("admissible_lane_count") == 3, ralph
assert ralph.get("backlog_lane_count") == 1, ralph
assert ralph.get("support_lane_count") == 1, ralph
assert ralph.get("duplicate_lane_count") == 1, ralph
assert ralph.get("active_issue_numbers") == ["701", "702"], ralph
assert ralph.get("backlog_issue_numbers") == ["703"], ralph
assert ralph.get("support_issue_numbers") == ["704"], ralph
assert ralph.get("duplicate_issue_numbers") == ["705"], ralph

completion = plan_state.get("completion") or {}
assert completion.get("status") == "pending", completion
assert completion.get("rollup") == "ralph-underfilled", completion
assert completion.get("blocked_reason") == "ralph condition unmet: Sustain net +1000 USDC on widened corpus with >=3 materially different live candidate lanes", completion
assert "Ralph mode remains active" in completion.get("details", ""), completion
acceptance = completion.get("acceptance") or {}
assert acceptance.get("status") == "pending", acceptance
assert acceptance.get("details") == "A previous latest-main proof run was green.", acceptance
assert acceptance.get("declared_status") == "verified", acceptance
assert acceptance.get("declared_verified_at") == "2026-03-31T18:20:00Z", acceptance
assert "verified_at" not in acceptance, acceptance
PY
BASH

grep -q 'Sustain net +1000 USDC on widened corpus with >=3 materially different live candidate lanes' "$REPO_ROOT/README.md" || {
  echo "expected README to document the realistic Ralph rig example" >&2
  exit 1
}

grep -q 'Issue `#703` is an open SOL follow-up lane with no live polecat yet.' "$REPO_ROOT/README.md" || {
  echo "expected README to describe the realistic backlog lane example" >&2
  exit 1
}

echo "REALISTIC RALPH RIG EXAMPLE PASSED"
