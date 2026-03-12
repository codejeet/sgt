#!/usr/bin/env bash
# test_mayor_briefing_budget_contract.sh — Mayor briefing budget and protected-fact contract regression.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

bash -s "$SGT_SCRIPT" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _mayor_build_briefing)"
eval "$(extract_fn _mayor_briefing_token_budget)"
eval "$(extract_fn _mayor_briefing_recent_activity_section)"
eval "$(extract_fn _mayor_briefing_recent_decisions_section)"
eval "$(extract_fn _mayor_briefing_context_section)"
eval "$(extract_fn _mayor_briefing_acceptance_blockers_section)"
eval "$(extract_fn _mayor_briefing_repo_plans_section)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export SGT_ROOT="$TMP_ROOT/repo"
export SGT_CONFIG="$TMP_ROOT/.sgt"
export SGT_RIGS="$TMP_ROOT/rigs"
export SGT_LOG="$TMP_ROOT/sgt.log"
export SGT_ESCALATION="$TMP_ROOT/escalation.json"
export SGT_MAYOR_PROMPT_BUDGET_TOKENS=900
mkdir -p "$SGT_ROOT" "$SGT_CONFIG/merge-queue" "$SGT_RIGS" "$TMP_ROOT/plans/alpha" "$TMP_ROOT/plan-state"

EVENT_LOG="$TMP_ROOT/events.log"
log_event() {
  echo "$*" >> "$EVENT_LOG"
}

cat > "$SGT_ROOT/SGT_CONTEXT.md" <<'CTX'
# SGT Project Context — sgt

## Notes
- 2026-03-12T00:00:00Z — latest-main proof remains required before closure.
- 2026-03-12T00:01:00Z — Mayor prompt budget should stay under 100k tokens with lower default when practical.
- 2026-03-12T00:02:00Z — Compact repeated watch churn instead of feeding raw history forever.
- 2026-03-12T00:03:00Z — Acceptance blockers remain protected facts.
CTX

cat > "$SGT_RIGS/alpha" <<'RIG'
example/alpha
RIG

cat > "$TMP_ROOT/plans/alpha/SGT_PLAN.json" <<'PLAN'
{
  "version": 1,
  "rig": "alpha",
  "completion_condition": "latest main proves mayor prompt compaction keeps active facts intact",
  "acceptance": {
    "status": "pending",
    "details": "Need latest-main proof and operator-visible budget stats."
  },
  "tasks": [
    { "id": "proof", "title": "Collect proof evidence" },
    { "id": "docs", "title": "Document budget contract", "depends_on": ["proof"] }
  ]
}
PLAN

cat > "$TMP_ROOT/plan-state/alpha.json" <<'STATE'
{
  "completion": {
    "condition": "latest main proves mayor prompt compaction keeps active facts intact",
    "details": "Need latest-main proof and operator-visible budget stats.",
    "rollup": "tasks-in-progress",
    "status": "pending"
  },
  "tasks": {
    "proof": {
      "status": "in_progress",
      "issue_number": "214"
    },
    "docs": {
      "status": "pending"
    }
  }
}
STATE

cat > "$SGT_CONFIG/merge-queue/one.state" <<'MQ'
PR=77
MQ

BLOCKER_EVIDENCE="$TMP_ROOT/blocker.md"
cat > "$BLOCKER_EVIDENCE" <<'EVIDENCE'
Mayor prompt still grows from repeated watchdog churn.
Keep open blockers, open issues/PRs, plan state, and latest-main proof evidence intact.
EVIDENCE

REQUEST_PROMPT="$TMP_ROOT/request.md"
cat > "$REQUEST_PROMPT" <<'REQ'
Build a plan that preserves current actionable facts, compacts repeated watch noise, and exposes budget stats.
Include regression tests and docs.
REQ

cat > "$SGT_CONFIG/mayor-decisions.log" <<'DECISIONS'
2026-03-12T00:00:00Z workspace=/tmp MAYOR DISPATCH SKIP (parallel-budget) reason_code=parallel-budget-exhausted
2026-03-12T00:00:01Z workspace=/tmp MAYOR DISPATCH SKIP (parallel-budget) reason_code=parallel-budget-exhausted
2026-03-12T00:00:02Z workspace=/tmp MAYOR AI CYCLE ABORT reason_code=stale-briefing
DECISIONS

: > "$SGT_LOG"
for i in $(seq 1 180); do
  printf '[2026-03-12T00:00:%02dZ] WATCHDOG alpha repeated churn event\n' $((i % 60)) >> "$SGT_LOG"
done
cat >> "$SGT_LOG" <<'LOG'
[2026-03-12T00:10:00Z] PLAN_MOVEMENT_BLOCKER rig=alpha task=proof reason_code=dispatch-failed
[2026-03-12T00:11:00Z] MAYOR_NOTIFY_RIGGER success channel=last
[2026-03-12T00:12:00Z] MAYOR_BRIEFING_GATE stale_detected=false path=fresh status=fresh
LOG

python3 - "$SGT_ESCALATION" <<'PY'
import json
import sys
path = sys.argv[1]
data = {"rules": [{"name": f"rule-{idx}", "severity": "high"} for idx in range(80)]}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh)
PY

cmd_status() {
  cat <<'STATUS'
daemon on
deacon on
mayor on
active polecats: 1
STATUS
}

_plan_file_path() {
  echo "$TMP_ROOT/plans/$1/SGT_PLAN.json"
}

_plan_state_path() {
  echo "$TMP_ROOT/plan-state/$1.json"
}

_plan_request_list_pending() {
  printf 'req-1|alpha|pending|2026-03-12T00:00:00Z|gastown|%s\n' "$REQUEST_PROMPT"
}

_acceptance_blocker_list_active() {
  printf 'blocker-1|alpha|open|2026-03-12T00:05:00Z|rigger|Mayor prompt budget still red|%s\n' "$BLOCKER_EVIDENCE"
}

MOCK_BIN="$TMP_ROOT/mock-bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
  printf '%s\n' '- #214: Define Mayor prompt budget and protected-fact contract [sgt-authorized,plan]'
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  printf '%s\n' '- PR #99: Preserve mayor facts [sgt/alpha-proof] mergeable=MERGEABLE'
  exit 0
fi
exit 1
GH
chmod +x "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"

briefing_path="$(_mayor_build_briefing)"
[[ -f "$briefing_path" ]] || { echo "expected mayor briefing output file" >&2; exit 1; }

grep -q '^budget_target_tokens=900$' "$briefing_path" || { echo "expected budget metadata" >&2; exit 1; }
grep -q '^budget_compaction_applied=true$' "$briefing_path" || { echo "expected compaction to be recorded" >&2; exit 1; }
grep -q '^protected_fact_sections=system_status,merge_queue,open_issues,open_prs,acceptance_blockers,pending_plan_requests,repo_plans$' "$briefing_path" || {
  echo "expected protected fact contract metadata" >&2
  exit 1
}
grep -q 'Mayor prompt budget still red' "$briefing_path" || { echo "expected active blocker to survive" >&2; exit 1; }
grep -q '#214: Define Mayor prompt budget and protected-fact contract' "$briefing_path" || { echo "expected active issue to survive" >&2; exit 1; }
grep -q 'PR #99: Preserve mayor facts' "$briefing_path" || { echo "expected active PR to survive" >&2; exit 1; }
grep -q 'completion_status: pending' "$briefing_path" || { echo "expected plan completion status to survive" >&2; exit 1; }
grep -q 'acceptance_details: Need latest-main proof and operator-visible budget stats.' "$briefing_path" || {
  echo "expected plan acceptance details to survive" >&2
  exit 1
}
grep -q 'requesting_agent: gastown' "$briefing_path" || { echo "expected pending request to survive" >&2; exit 1; }
grep -q 'repeated_event_groups:' "$briefing_path" || { echo "expected recent activity summary" >&2; exit 1; }
if [[ "$(grep -c 'WATCHDOG alpha repeated churn event' "$briefing_path")" -ge 30 ]]; then
  echo "expected repeated watchdog noise to be compacted" >&2
  exit 1
fi
grep -q 'MAYOR_BRIEFING_BUDGET budget_tokens=900' "$EVENT_LOG" || { echo "expected budget log event" >&2; exit 1; }

ln -s "$SGT_CONFIG" "$SGT_ROOT/.sgt"
cp "$SGT_LOG" "$SGT_ROOT/sgt.log"

status_output="$("$SGT_SCRIPT" status)"
printf '%s\n' "$status_output" | grep -q 'briefing budget: target=900 used=' || {
  echo "expected status to surface mayor briefing budget" >&2
  exit 1
}
printf '%s\n' "$status_output" | grep -q 'budget sections: kept=' || {
  echo "expected status to surface kept/summarized sections" >&2
  exit 1
}

status_json="$("$SGT_SCRIPT" status --json)"
printf '%s\n' "$status_json" | grep -q '"briefing_budget":{"path":' || {
  echo "expected status json to expose briefing budget object" >&2
  exit 1
}
printf '%s\n' "$status_json" | grep -q '"target_tokens":"900"' || {
  echo "expected status json to expose briefing budget target" >&2
  exit 1
}
BASH

echo "ALL TESTS PASSED"
