# SGT (Simple GitHub Gastown)

SGT is a small, ops-first replacement for older “Gas Town” workflows.

- **Source of truth**: GitHub Issues + PRs
- **Execution**: tmux workers (polecats / dogs)
- **Operations**: `gh` CLI + a thin Bash/Node layer

## Web UI

The repo includes a minimal Web UI for realtime monitoring and dispatch:

- Docs / quick start: [`web/README.md`](web/README.md)
- Default URL: `http://localhost:4747`

## Why SGT exists (short)

Gas Town got bloated/fragile over time: “beads” were easy to break, and persistence/state became brittle.
SGT replaces that with a simpler mental model: GitHub Issues/PRs + tmux + `gh`.

## `sgt sweep` exit codes

`sgt sweep` now has deterministic exit semantics:

- Exit `0`: successful run, including when nothing needs cleanup, benign closed-stream conditions, or empty sweep actions.
- Exit non-zero: real failures only (for example, invalid polecat state files or unrecoverable cleanup errors), with actionable stderr text that includes the polecat name and recommended recovery (`sgt nuke <polecat>`).

## Repo Plans (SGT_PLAN.json) — deterministic parallel + sequential

SGT supports **repo-local work plans** so the system can keep itself fed without relying on LLM planning.

- **File**: `SGT_PLAN.json` at the repo root of any rig you want on autopilot.
- **What it does**: defines a DAG of tasks with explicit dependencies via `depends_on`.
- **How it runs**:
  - Mayor calls `sgt plan tick <rig>` automatically for any rig that contains `SGT_PLAN.json`.
  - `sgt plan tick` queues “ready” tasks up to `policy.max_in_flight`.
  - Plan state is stored at: `~/sgt/.sgt/plan-state/<rig>.json`

### Minimal schema

```json
{
  "version": 1,
  "rig": "scrapegoat",
  "policy": { "max_in_flight": 2 },
  "tasks": [
    { "id": "ci", "title": "Add CI", "depends_on": [] },
    { "id": "lint-fix", "title": "Fix lint", "depends_on": ["ci"] }
  ]
}
```

### Manual control

```bash
# queue ready work now
sgt plan tick scrapegoat

# wake mayor immediately (event-driven)
sgt wake-mayor "plan-update:scrapegoat"
```

## CI self-healing (Mayor watchdog)

For rigs with `SGT_PLAN.json`, Mayor also watches the latest **master** GitHub Actions run.
If it goes red, Mayor auto-dispatches a **CI-fix** issue (once per failing SHA) so the system repairs itself instead of stalling.

Mayor dispatches are idempotent within a cooldown window:
- Before creating a new issue, `sgt sling` checks recent open/closed issues for the same symptom signature (normalized title) and required labels.
- If a match is found within cooldown, dispatch is suppressed to avoid duplicate redispatch loops while a fix is pending or just merged.
- Default cooldown: `21600` seconds (6 hours), configurable with:

```bash
export SGT_MAYOR_DISPATCH_COOLDOWN=21600
```

Set `SGT_MAYOR_DISPATCH_COOLDOWN=0` to disable suppression.

Mayor AI dispatches also include a stale-state revalidation immediately before issue creation:
- The mayor path performs a single live snapshot check for open PRs and open `sgt-authorized` issues on the target rig repo, live-counts active polecats on the target rig, and tracks per-rig merge-queue item counts.
- Mayor writes a per-rig dispatch snapshot from briefing time and compares it against live state right before dispatch.
- Explicit mismatch categories are emitted when briefing/live diverge:
  - `pr-state` (open PR count drift; e.g. stale merged PR),
  - `polecat-liveness` (briefing listed active polecat but it was cleaned),
  - `queue-contents` (authorized issue count or merge-queue count drift).
- Mayor computes `parallel_in_flight=max(open_sgt_authorized_issues, active_polecats)` and enforces `SGT_MAYOR_DISPATCH_MAX_PARALLEL` (default `3`, set `0` to disable).
- If live state cannot be confirmed, the briefing/live consistency check mismatches, or the parallel budget is exhausted, dispatch is skipped as a no-op.
- Consistency mismatches emit `MAYOR_DISPATCH_SKIP_CONSISTENCY ... retry=next-mayor-cycle` telemetry and include both `snapshot_summary` and `live_summary` in `~/.sgt/mayor-decisions.log`.
- A reasoned operator-visible line is emitted (`[mayor] dispatch skipped ...`) and a corresponding entry is appended to `~/.sgt/mayor-decisions.log`.
- Budget skips also emit explicit structured telemetry (`MAYOR_DISPATCH_SKIP_BUDGET reason_code=parallel-budget-exhausted ...`) for runbook/debug filtering.

Mayor cycle decisions also protect against stale snapshot text in generated `CLAUDE.md`:
- Merge-queue count now performs a one-time live revalidation immediately before issue surfacing.
- Deterministic precedence rules:
  - if live count is available and differs from snapshot, `live` wins (`status=stale-snapshot`);
  - if live is unavailable, snapshot is kept (`status=live-unavailable`);
  - if both match, snapshot is accepted (`status=in-sync`).
- Mayor emits an explicit status line with both values and chosen source:
  - `[mayor] snapshot guard merge_queue_count snapshot=<n> live=<n> chosen=<n> source=<snapshot|live> status=<...>`
- When a stale snapshot is detected, mayor records a `Snapshot Freshness` note in decision output instead of treating the stale snapshot value as an active issue.

Mayor AI briefing generation also has a strict freshness gate:
- Immediately before every AI decision cycle, mayor regenerates `~/.sgt/mayor-briefing.md` and stamps:
  - `generated_at: <ISO-8601 timestamp>`
  - `generated_at_epoch: <unix-seconds>`
- Mayor validates briefing age against `SGT_MAYOR_BRIEFING_STALE_SECS` (default `5` seconds).
- If the briefing is stale/invalid, mayor performs one immediate auto-refresh and re-check.
- If freshness still fails after refresh, mayor aborts that AI cycle (`MAYOR_AI_CYCLE aborted reason=stale-briefing`) instead of sending stale context to the model.
- Structured freshness telemetry is emitted on each path:
  - `MAYOR_BRIEFING_GATE stale_detected=<true|false> path=<fresh|refreshed|aborted> status=<fresh|stale|invalid|missing> generated_at="..." age=<n>s threshold=<n>s refresh_attempted=<true|false> ...`
  - `MAYOR_BRIEFING_GATE_STATUS path=<...> stale_detected=<...> status=<...> generated_at="..." age=<n>s threshold=<n>s` (just before AI invoke).

Mayor orphan-PR queueing also revalidates live PR state at queue time:
- If an orphan was listed as open from a stale snapshot but live state is `MERGED`/`CLOSED`, mayor skips queueing.
- Mayor emits an explicit operator line and structured activity-log event (`MAYOR_ORPHAN_SKIP_STALE ... snapshot_state=OPEN live_state=<...>`).

Mayor also runs a stale-polecat reconciliation fence after merged/closed transitions:
- On `merged:*` or `dog-approved:*` wake cycles, mayor revalidates each tracked polecat against live issue/PR state.
- If a polecat is still in-flight but tied to `issue_state=CLOSED` or `pr_state=MERGED`, mayor cleans the stale session/worktree/state and records one idempotent cleanup decision.
- Cleanup is restart-safe and replay-safe via a durable fence under `~/.sgt/mayor-stale-polecat-fence/`, so repeated cycles/restarts do not duplicate session nukes or duplicate decision entries.

Stale-polecat symptoms and telemetry:
- Symptom: `sgt status` still shows a running polecat after its issue is closed or PR merged.
- Activity log event: `MAYOR_POLECAT_CLEANUP reason_code=<stale-issue-closed|stale-pr-merged> polecat=<name> repo=<owner/repo> issue=#<n> pr=#<n|unknown> branch="<branch>" issue_state=<state> pr_state=<state> action=<cleanup-action>`.
- Decision log event: `MAYOR POLECAT CLEANUP reason_code=<...> polecat=<...> ... action=<...>` (`context=stale-polecat-cleanup` in `~/.sgt/mayor-decisions.log`).

Mayor decision logging is durable:
- Decision entries are appended under an exclusive file lock.
- Each append captures the pre-write file offset and rolls back (`ftruncate`) on write/fsync failure, so concurrent cycles do not leave interleaved or truncated decision lines.
- Each append is explicitly flushed with `fsync` before returning.
- Each entry is prefixed with a UTC ISO-8601 timestamp and `workspace=<path>`.
- If a decision-log write fails, mayor continues the cycle, emits a console warning (`[mayor] warning: MAYOR_DECISION_LOG_WRITE_FAILED ...`), writes structured `MAYOR_DECISION_LOG_WRITE_FAILED ... notify=<sent|suppressed|unavailable>` metadata to `~/.sgt/sgt.log`, and surfaces `decision-log warning: ...` in `sgt status`.
- Mayor also sends at most one decision-log failure notification per cooldown window (`SGT_MAYOR_DECISION_LOG_ALERT_COOLDOWN`, default `600` seconds; set `0` to disable suppression).

Mayor wake processing is also cycle-idempotent:
- Within a single mayor loop cycle, repeated identical wake events are coalesced.
- Replayed identical `merged:*` wake events in that cycle produce only one AI dispatch decision.
- Non-periodic wake summaries are emitted once per coalesced event in order.

Mayor wake processing also applies short-lived cross-cycle stale-trigger suppression:
- Mayor dedupes identical wake trigger keys (event key before `|` metadata, e.g. `merged:pr#77:#40:rig-a`) for a short TTL window.
- Distinct wake keys still pass through immediately, even inside that dedupe window.
- Default wake dedupe TTL: `15` seconds, configurable with:

```bash
export SGT_MAYOR_WAKE_DEDUPE_TTL=15
```

Set `SGT_MAYOR_WAKE_DEDUPE_TTL=0` to disable wake-trigger dedupe.
- Suppressed stale triggers are logged as structured dispatch-cooldown suppressions with:
  - `reason=dispatch_cooldown`
  - `trigger_key=<wake event key>`
  - `ttl_remaining=<seconds>`
  - `prior_decision_ts=<unix epoch>`
- Suppressed dispatches append a durable `~/.sgt/mayor-decisions.log` line (`MAYOR WAKE SKIP reason=dispatch_cooldown ...`).

Mayor proactive post-merge dispatches also use a durable idempotency fence:
- Mayor keys merged-trigger dispatch eligibility by `repo+PR+merged head SHA` (`owner/repo|pr=<n>|merged_head=<sha>`), persisted under `~/.sgt/mayor-dispatch-triggers/`.
- The key is claimed before triggering proactive AI dispatch from merged wake events, so replayed merged events (including after mayor restart) become no-op.
- Duplicate merged-trigger replay is suppressed before wake-summary notify fanout, so mayor/openclaw merge summaries are emitted exactly once per `repo+PR+merged_head`.
- Duplicate merged-trigger replays emit explicit operator/log observability:
  - status line: `[mayor] dispatch skipped duplicate merged trigger key=<key> reason_code=duplicate-dispatch-trigger-key trigger_event_key=<event-key>`
  - activity log: `MAYOR_DISPATCH_SKIPPED_DUPLICATE reason_code=duplicate-dispatch-trigger-key skip_reason="..." trigger_event_key="merged:..." rig=<rig> repo="<repo>" pr=#<n> issue=#<n> merged_head="<sha>" key="<key>" wake="merged:..."`
  - decision log: `MAYOR WAKE SKIP (duplicate-merged-trigger) reason_code=duplicate-dispatch-trigger-key trigger_key=<owner/repo|pr=<n>|merged_head=<sha>> trigger_event_key="merged:..." wake="merged:..."`

Mayor dispatch-start verification fence (restart-safe):
- Mayor-tagged proactive dispatches write durable attempt records under `~/.sgt/mayor-dispatch-attempts/`, keyed by `repo+issue+trigger` (`owner/repo|issue=<n>|trigger=<wake-key>`).
- Each record carries a bounded verification deadline (`VERIFY_DEADLINE_TS`). Mayor replays pending records every cycle, including after restart.
- Success is recorded when active work is observed (`active-polecat` state file or active tmux session for the dispatched polecat).
- If verification times out before active work appears, mayor emits explicit timeout telemetry and performs one idempotent retry via re-sling guardrails.
- Retry budget is strictly one attempt per record (`RETRY_COUNT<=1`), with terminal fail reasons such as:
  - `retry-dispatch-failed`
  - `retry-title-lookup-failed`
  - `retry-budget-exhausted`
- Configure verification window with:

```bash
export SGT_MAYOR_DISPATCH_VERIFY_TIMEOUT_SECS=120
```

Mayor action-evidence receipt fence (dispatch/nuke/merge):
- Mayor AI cycles set `SGT_MAYOR_ACTION_FENCE=1`, which enables mandatory post-action live verification receipts for side effects.
- Receipts are written under `~/.sgt/mayor-action-receipts/` and include structured fields:
  - `action`
  - `target`
  - `expected_state`
  - `observed_state`
  - `verified_at`
- Receipt decisions append to `~/.sgt/mayor-decisions.log` as `MAYOR ACTION RECEIPT ...`.
- A side effect is only declared success after immediate live recheck confirms expected state.
- Mismatches are logged as non-success with explicit `reason=<...>` and `retry=<...>` hints (for example `retry-next-mayor-cycle`, `retry-nuke-manual`, `retry-merge-manual`).
- Replayed action keys do not write conflicting success receipts; replay is logged as non-success/no-op (`reason=replayed-action-key-existing-success retry=no-op`).
- Use `sgt mayor merge <pr#> --repo <repo>` for mayor merge actions (includes receipt fence and post-merge live verification).

Mayor notify delivery receipt + retry fence (`sgt mayor notify` / `_mayor_notify_rigger`):
- Mayor notify writes durable attempt state under `~/.sgt/mayor-notify-attempts/`, keyed by `channel+target+message_key`.
- Every notify attempt is live-verified against transport/ack result and writes a structured receipt under `~/.sgt/mayor-notify-receipts/` with:
  - `channel`
  - `target`
  - `message_key`
  - `attempt`
  - `verified_at`
  - `outcome`
- Transient transport failures (`timeout/network/http-5xx/secondary-rate-limit`) and missing/stale ack outcomes trigger at most one idempotent retry.
- Non-retriable transport failures are retry-fenced immediately; replay of the same `message_key` does not re-send and emits explicit dedupe skip telemetry.
- Receipt outcomes and escalation/skip reasons are recorded in both:
  - decision log: `MAYOR NOTIFY RECEIPT ...`, `MAYOR NOTIFY ESCALATE ...`, `MAYOR NOTIFY SKIP ...`
  - activity log: `MAYOR_NOTIFY_RECEIPT ...`, `MAYOR_NOTIFY_ESCALATE ...`, `MAYOR_NOTIFY_ESCALATE_SUPPRESS ...`

Troubleshooting duplicate merged-trigger dispatch skips:
1. Confirm the durable trigger key exists (key should match `repo+PR+merged_head`):

```bash
ls -1 ~/.sgt/mayor-dispatch-triggers/
```

2. Inspect the structured duplicate-skip event for exact context and reason:

```bash
grep 'MAYOR_DISPATCH_SKIPPED_DUPLICATE' ~/.sgt/sgt.log | tail -20
```

3. Confirm decision-log duplicate suppression telemetry includes the expected trigger key:

```bash
grep 'MAYOR WAKE SKIP (duplicate-merged-trigger)' ~/.sgt/mayor-decisions.log | tail -20
```

4. Verify the wake payload carried `merged_head=...` (required for keying):

```bash
sgt peek mayor
```

5. If a new post-merge window is expected but skips continue, confirm the upstream event is for a new head SHA; dispatch dedupe is intentionally sticky per `repo+PR+merged_head` across mayor restarts.

Troubleshooting dispatch-start verification fence:
1. Inspect pending/terminal verifier records:

```bash
ls -1 ~/.sgt/mayor-dispatch-attempts/
tail -100 ~/.sgt/mayor-dispatch-attempts/*.state
```

2. Correlate verifier telemetry in activity log:

```bash
grep 'MAYOR_DISPATCH_VERIFY_' ~/.sgt/sgt.log | tail -50
```

3. Correlate durable decision-log timeout/success entries:

```bash
grep 'MAYOR DISPATCH VERIFY' ~/.sgt/mayor-decisions.log | tail -50
```

Troubleshooting mayor action receipts (dispatch/nuke/merge):
1. Inspect the durable receipt files:

```bash
ls -1 ~/.sgt/mayor-action-receipts/
tail -100 ~/.sgt/mayor-action-receipts/*.state
```

2. Correlate decision-log receipt outcomes:

```bash
grep 'MAYOR ACTION RECEIPT' ~/.sgt/mayor-decisions.log | tail -50
```

3. Correlate activity log telemetry:

```bash
grep 'MAYOR_ACTION_RECEIPT' ~/.sgt/sgt.log | tail -50
```

4. If replay no-op keeps appearing (`reason=replayed-action-key-existing-success`), confirm you are not replaying the same action key (`action_key=...`) and that a new merge/dispatch target really changed.

Troubleshooting mayor notify receipts (`sgt mayor notify`):
1. Inspect notify attempt state + receipt artifacts:

```bash
ls -1 ~/.sgt/mayor-notify-attempts/
ls -1 ~/.sgt/mayor-notify-receipts/
tail -100 ~/.sgt/mayor-notify-attempts/*.state
tail -100 ~/.sgt/mayor-notify-receipts/*.state
```

2. Correlate decision-log outcomes and explicit skip/escalate reasons:

```bash
grep 'MAYOR NOTIFY ' ~/.sgt/mayor-decisions.log | tail -80
```

3. Correlate operator-visible telemetry in activity log:

```bash
grep 'MAYOR_NOTIFY_' ~/.sgt/sgt.log | tail -80
```

4. Expected event patterns:
- `MAYOR_NOTIFY_RECEIPT ... outcome=delivered` indicates ack-verified success.
- `MAYOR_NOTIFY_RECEIPT ... outcome=transport-failure|missing-ack|stale-ack` indicates a failed attempt.
- `MAYOR_NOTIFY_ESCALATE reason=notify-...` indicates terminal failure requiring operator attention.
- `MAYOR NOTIFY SKIP reason=notify-retry-budget-exhausted-escalation-deduped` indicates replay was safely fenced and no duplicate notification was sent.

Troubleshooting dispatch-cooldown suppressions (replayed merged wake events):
1. Inspect structured cooldown suppression telemetry:

```bash
grep 'MAYOR_DISPATCH_COOLDOWN_SUPPRESSED reason=dispatch_cooldown' ~/.sgt/sgt.log | tail -20
```

2. Confirm each suppressed dispatch wrote a durable decision-log audit line:

```bash
grep 'MAYOR WAKE SKIP reason=dispatch_cooldown' ~/.sgt/mayor-decisions.log | tail -20
```

3. Correlate suppression context:
- `trigger_key` identifies the deduped wake trigger.
- `ttl_remaining` shows remaining cooldown window.
- `prior_decision_ts` shows the previous accepted decision timestamp used for cooldown math.

Troubleshooting briefing/live consistency mismatch suppressions:
1. Inspect structured mismatch telemetry and reason code:

```bash
grep 'MAYOR_DISPATCH_SKIP_CONSISTENCY' ~/.sgt/sgt.log | tail -20
```

2. Confirm decision-log entry includes mismatch categories and both state summaries:

```bash
grep 'MAYOR DISPATCH SKIP (consistency-mismatch)' ~/.sgt/mayor-decisions.log | tail -20
```

3. Correlate mismatch details:
- `mismatch_categories` shows which class diverged (`pr-state`, `polecat-liveness`, `queue-contents`).
- `snapshot_summary` is the briefing-time state.
- `live_summary` is the pre-dispatch revalidation state.
- `retry=next-mayor-cycle` indicates mayor intentionally did no-op and will retry after the next revalidation pass.

Mayor cycle ownership uses a lease lockfile (`~/.sgt/mayor.lock`):
- Lockfile fields: `ownerPid`, `startedAt`, `leaseUntil`.
- On startup/refresh, Mayor emits explicit lock decisions: `acquired`, `reused`, or `stolen`.
- If lock owner is still live with a valid lease, a competing Mayor exits and respects the existing owner.
- If owner is dead or lease is expired, a new Mayor safely steals the stale lock and continues.
- Lease length is tunable via:

```bash
export SGT_MAYOR_LOCK_LEASE_SECS=720
```

Default lease is `SGT_MAYOR_INTERVAL + 120` seconds.

Mayor and boot both guard against stale deacon heartbeats:
- Default stale threshold is `300` seconds (`5` minutes), configurable with:

```bash
export SGT_DEACON_HEARTBEAT_STALE_SECS=300
```

- Mayor also checks this heartbeat age and proactively restarts deacon when the heartbeat is missing/invalid/stale.
- `sgt status` now shows deacon heartbeat age + health (`healthy|stale|unknown`) and the active stale threshold.
- `sgt status` render guardrails are non-fatal: terminal width falls back safely in non-TTY/sparse envs, and polecat metadata races/misses are surfaced as actionable warning lines (for example, retry `sgt status` or run `sgt nuke <polecat>` if stale) while `sgt status` still exits `0`.

Critical/high issue alerts from Mayor are deduped with a cooldown:
- Mayor sends at most one identical critical/high OpenClaw alert per rig within the cooldown window.
- Default alert cooldown is `3600` seconds (`1` hour), configurable with:

```bash
export SGT_MAYOR_CRITICAL_ALERT_COOLDOWN=3600
```

Set `SGT_MAYOR_CRITICAL_ALERT_COOLDOWN=0` to disable alert dedupe.

Mayor also watches refinery queue items that are stuck in `REVIEW_UNCLEAR`:
- Queue items that remain in `REVIEW_UNCLEAR` for at least the stale threshold are escalated once per PR review-state transition.
- Escalations include stale age and direct PR/issue URLs.
- `sgt status` surfaces watchdog health with stale age (`oldest=<n>s`) and active threshold.
- Default stale threshold is `900` seconds (`15` minutes), configurable with:

```bash
export SGT_MAYOR_REVIEW_UNCLEAR_STALE_SECS=900
```

Mayor also watches witness/refinery heartbeats for stuck-but-still-running sessions:
- Witness and refinery loops emit per-rig heartbeat files under `~/.sgt/`.
- If heartbeat age exceeds the stale threshold, mayor emits an escalation event with exact `stale_seconds` and `last_heartbeat`.
- Escalations are deduped per agent (`witness/<rig>` or `refinery/<rig>`) per dedupe window, and reset on heartbeat recovery.
- Defaults are:

```bash
export SGT_AGENT_HEARTBEAT_STALE_SECS=180
export SGT_MAYOR_AGENT_HEARTBEAT_DEDUPE_SECS=900
```

Mayor also watches required CI checks on open PRs:
- Required checks that remain `QUEUED` or `IN_PROGRESS` past the stale threshold are escalated with exact `stale_seconds` and `check_url`.
- Escalations are deduped per `pr+check` within the dedupe window, and dedupe resets when that check recovers/completes for the PR.
- Defaults are:

```bash
export SGT_MAYOR_CI_CHECK_STALE_SECS=900
export SGT_MAYOR_CI_CHECK_DEDUPE_SECS=900
```

Runbook action mapping for watchdog escalations:
- `notify`: witness/refinery heartbeat stale incidents (session still up, but loop appears stuck) escalate to Rigger with stale context.
- `retry`: stale required CI checks on open PRs should trigger a check rerun/retry path before stronger remediation.
- `nuke`: use `sgt nuke <polecat>` for stale individual polecat workers.

## Refinery merge retries

Refinery merge attempts now use bounded retry with jitter for transient `gh pr merge` failures.

- After review approval, refinery captures the reviewed head SHA and immediately revalidates live head right before merge; if head drifted after review, merge is skipped.
- Review-ready evidence is now persisted durably on the merge candidate record as `REVIEWED_HEAD_SHA` plus `REVIEWED_AT` before any merge call is attempted.
- Retries only trigger for transient classes: `timeout`, `network`, `http-5xx`, and `secondary-rate-limit`.
- Before each retry, refinery re-checks live PR state (`OPEN`) and head SHA; if either drifts, retry is skipped and the queue item is kept with refreshed `HEAD_SHA`.
- If merge fails specifically because branch policy requires auto-merge, refinery revalidates PR state/head and retries exactly once with `--auto`.
- Refinery also enforces a durable per-attempt idempotency key of `repo+PR+head SHA`, persisted under `~/.sgt/refinery-merge-attempts/`.
- Once a merge action has been attempted for that key, the fence is kept across retries, future refinery cycles, and process restarts.
- Duplicate PR-ready queue replays for the same key are skipped before any additional merge action runs.
- If a replayed queue candidate is marked `REVIEW_APPROVED` but lacks `REVIEWED_HEAD_SHA`, refinery blocks merge, emits explicit telemetry, and resets it to `REVIEW_PENDING` for a fresh review/revalidation path.
- When mergeability is `CONFLICTING`, refinery now writes durable conflict evidence under `~/.sgt/refinery-conflicts/` including original PR/head/attempt/timestamp context (`ORIGIN_PR`, `ORIGIN_HEAD_SHA`, `ORIGIN_ATTEMPT_KEY`, `ORIGIN_TS`).
- Conflict re-sling is now guarded by a per-issue claim (`~/.sgt/resling-issue-claims/`) so concurrent conflict handlers dedupe to one active re-sling per issue.
- On refinery restart, pending conflict evidence is replayed and resumed from disk without spawning duplicate polecats; already-dispatched evidence is treated as complete.
- Final merge failure emits structured activity log metadata and an OpenClaw notification that includes attempts and error class.
- For repeated `REVIEW_UNCLEAR` review loops, refinery persists per-PR retry state directly on the queue item (`REVIEW_UNCLEAR_RETRY_COUNT`, `REVIEW_UNCLEAR_NEXT_RETRY_AT`, `REVIEW_UNCLEAR_LAST_REASON`, escalation markers).
- Unclear re-review attempts use bounded exponential backoff with jitter; backoff windows survive daemon restarts so replay does not hammer re-review.
- When the unclear retry cap is reached, refinery emits a single saturation escalation notification (PR, issue, last reason, next-action hint) and then holds the PR until manual intervention.
- Saturation escalation dedupe is restart-safe via persisted queue markers (`REVIEW_UNCLEAR_ESCALATED`, `REVIEW_UNCLEAR_ESCALATED_AT`), so refinery restart replay does not re-page.

Configure retry behavior with:

```bash
export SGT_REFINERY_MERGE_MAX_ATTEMPTS=3
export SGT_REFINERY_MERGE_RETRY_BASE_MS=1000
export SGT_REFINERY_MERGE_RETRY_JITTER_MS=400
export SGT_REFINERY_REVIEW_UNCLEAR_MAX_RETRIES=5
export SGT_REFINERY_REVIEW_UNCLEAR_BACKOFF_BASE_SECS=30
export SGT_REFINERY_REVIEW_UNCLEAR_BACKOFF_MAX_SECS=600
export SGT_REFINERY_REVIEW_UNCLEAR_JITTER_SECS=15
```

Observability:
- `REFINERY_PREMERGE_SKIP pr=#... reason_code=<stale-reviewed-head|reviewed-head-capture-failed|premerge-revalidation-failed> ...`
- `REFINERY_MERGE_RETRY pr=#... attempt=<n>/<max> class=<class> delay_s=<seconds>`
- `REFINERY_MERGE_RETRY_SKIP pr=#... attempt=<n>/<max> reason="..."`
- `REFINERY_MERGE_RETRY_AUTO repo=<owner/repo> pr=#... reason=branch-policy-requires-auto-merge outcome=<success|failed|skipped> ...`
- `REFINERY_MERGE_FAILED pr=#... attempt=<n>/<max> class=<class> transient=<true|false> error="..."`
- `REFINERY_DUPLICATE_SKIP pr=#... issue=#... reason_code=duplicate-merge-attempt-key reason="duplicate merge-attempt key (repo+pr+head) already processed" key="owner/repo|pr=<n>|head=<sha>"`
- `REFINERY_MERGE_BLOCKED_MISSING_REVIEW_SHA pr=#... issue=#... queue=<queue-file> ...`
- `REFINERY_CONFLICT_EVIDENCE_WRITTEN pr=#... issue=#... head=<sha> attempt_key="owner/repo|pr=<n>|head=<sha>" evidence="~/.sgt/refinery-conflicts/<id>.state"`
- `REFINERY_CONFLICT_RESLING_DEDUPE issue=#... reason_code=<active-resling-claim|active-polecat-existing> ...`
- `REFINERY_CONFLICT_RESLING_RESUMED issue=#... source_pr=<n> polecat=<name> evidence="..."`
- `REFINERY_CONFLICT_RESLING_SKIPPED issue=#... status=<SKIPPED_STALE|SKIPPED_UNAUTHORIZED|PENDING> reason="..."`
- `REFINERY_REVIEW_UNCLEAR_PENDING pr=#... issue=#... attempt=<n>/<max> retry_in=<seconds>s next_retry_at=<epoch> reason="..."`
- `REFINERY_REVIEW_UNCLEAR_BACKOFF pr=#... issue=#... attempt=<n> wait_s=<seconds> next_retry_at=<epoch>`
- `REFINERY_REVIEW_UNCLEAR_ESCALATED pr=#... issue=#... attempts=<n>/<max> reason="..." next_action_hint="..."`
- `REFINERY_REVIEW_UNCLEAR_CAP_HOLD pr=#... issue=#... attempts=<n>/<max> escalated=<0|1>`

When duplicate queue events are ignored, refinery emits both:
- an operator-visible status line: `duplicate merge skipped — reason_code=duplicate-merge-attempt-key ... key=...`
- a structured activity log event: `REFINERY_DUPLICATE_SKIP ...`

Merge-queue enqueueing is also idempotent at `repo+PR` granularity (witness + mayor orphan dispatch paths):
- Queue items are keyed by `owner/repo|pr=<n>`, so the same PR cannot be queued under multiple aliases.
- Alias replays (for example `sgt-691e731c` vs `sgt-pr84`) are skipped before writing a second queue file.
- Duplicate skips emit operator and log observability with reason code `duplicate-queue-key`:
  - status line: `[merge-queue/<rig>] duplicate queue skipped — reason_code=duplicate-queue-key ...`
  - activity log: `MERGE_QUEUE_DUPLICATE_SKIP rig=<rig> repo=<owner/repo> pr=#<n> ...`

Rig naming conventions for query/revalidation paths:
- A rig name can be an alias (for example `oadm`), but it must map to exactly one canonical GitHub repo in `~/.sgt/rigs/<rig>`.
- Status/mayor/refinery open-PR and open-issue checks always resolve `rig -> canonical repo` before querying GitHub.
- If queue/polecat metadata contains an unknown rig, missing repo, invalid repo format, or repo that does not match the rig mapping, SGT now hard-fails that query path instead of treating it as an empty result.
- Resolver failures emit explicit telemetry: `RIG_REPO_RESOLVE_ERROR ... reason_code=<unknown-rig|missing-repo|invalid-repo|repo-mismatch|...>`.

## Security gate (sgt-authorized label)

By default, SGT requires issues/PRs to be linked to an issue labeled `sgt-authorized` before witnesses/refineries will queue or merge work.

To disable this gate (not recommended on public repos), set:

```bash
export SGT_REQUIRE_AUTH_LABEL=0
```

Witness/refinery re-dispatches also apply live stale-event guards immediately before spawning a new polecat:
- Re-sling revalidates that the linked issue is still `OPEN`.
- For stale refinery queue events, re-sling also revalidates the source PR and skips if it is not `OPEN` or not `MERGEABLE`.
- Re-sling now runs a second dispatch-instant hard-stop gate immediately before `tmux` spawn to prevent late stale `CLOSED`/`MERGED` replay races from creating a new polecat.
- Skips emit explicit operator-visible reasons (`[resling] stale event ... — skipping: ...`, `[resling] dispatch-instant gate ... — skipping: ...`) and structured activity log events (`RESLING_SKIP_STALE ...`, `RESLING_SKIP_FINAL_GATE ...`).
- Structured skip logs include forensic fields: `source_event`, `source_event_key`, `source_pr`, and `skip_reason`.

## OpenClaw notifications

SGT can send delivered OpenClaw alerts when refinery reviews/merges a PR. The mayor also emits minimal event summaries when woken by non-periodic events (dog-approved, merged, orphan-pr queued), and escalated watchdog alerts for stalled `REVIEW_UNCLEAR` refinery items; periodic all-clear checks stay quiet.

1. Create a notification config at `$SGT_ROOT/.sgt/notify.json` (default `~/sgt/.sgt/notify.json`).
2. Set routing options: `channel` (default `last`), optional `to`, optional `reply_to` (or `reply-to`).

Example:

```json
{
  "channel": "last",
  "to": "rigger",
  "reply_to": "sgt"
}
```

Test:

```bash
sgt mayor notify "OpenClaw notification test"
```

If `openclaw` is missing or the config is absent, notifications are skipped.
