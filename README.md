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
- The mayor path performs a single live snapshot check for open PRs and open `sgt-authorized` issues on the target rig repo.
- If either count is non-zero (or live state cannot be confirmed), dispatch is skipped.
- A reasoned operator-visible line is emitted (`[mayor] dispatch skipped ...`) and a corresponding entry is appended to `~/.sgt/mayor-decisions.log`.

Mayor cycle decisions also protect against stale snapshot text in generated `CLAUDE.md`:
- Merge-queue count now performs a one-time live revalidation immediately before issue surfacing.
- Deterministic precedence rules:
  - if live count is available and differs from snapshot, `live` wins (`status=stale-snapshot`);
  - if live is unavailable, snapshot is kept (`status=live-unavailable`);
  - if both match, snapshot is accepted (`status=in-sync`).
- Mayor emits an explicit status line with both values and chosen source:
  - `[mayor] snapshot guard merge_queue_count snapshot=<n> live=<n> chosen=<n> source=<snapshot|live> status=<...>`
- When a stale snapshot is detected, mayor records a `Snapshot Freshness` note in decision output instead of treating the stale snapshot value as an active issue.

Mayor decision logging is durable:
- Decision entries are appended atomically under a file lock.
- Each append is explicitly flushed with `fsync` before returning.
- Each entry is prefixed with a UTC ISO-8601 timestamp and `workspace=<path>`.
- If a decision-log write fails, mayor continues the cycle, emits structured `MAYOR_DECISION_LOG_WRITE_FAILED ... notify=<sent|suppressed|unavailable>` metadata to `~/.sgt/sgt.log`, and surfaces a warning in `sgt status`.
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
- Suppressed stale triggers emit an explicit skip reason in mayor output, Rigger notification status, and `~/.sgt/mayor-decisions.log` (`MAYOR WAKE SKIP (duplicate-trigger)`).

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

Mayor/witness merge-queue enqueue is also repo+PR idempotent:
- Queue admission is fenced by a durable `repo+PR` key under `~/.sgt/merge-queue-keys/`.
- A single PR cannot be queued under multiple aliases (for example `sgt-691e731c` and `sgt-pr84`).
- Duplicate alias enqueue attempts are skipped and emitted as structured activity logs:
  `MERGE_QUEUE_DUPLICATE_SKIP actor=<mayor|witness|witness-orphan> rig=<rig> pr=#<n> reason_code=duplicate-queue-pr-key key="owner/repo|pr=<n>" queue=<alias> existing_queue=<alias>`

## Refinery merge retries

Refinery merge attempts now use bounded retry with jitter for transient `gh pr merge` failures.

- Retries only trigger for transient classes: `timeout`, `network`, `http-5xx`, and `secondary-rate-limit`.
- Before each retry, refinery re-checks live PR state (`OPEN`) and head SHA; if either drifts, retry is skipped and the queue item is kept with refreshed `HEAD_SHA`.
- Refinery also enforces a durable per-attempt idempotency key of `repo+PR+head SHA`, persisted under `~/.sgt/refinery-merge-attempts/`.
- Once a merge action has been attempted for that key, the fence is kept across retries, future refinery cycles, and process restarts.
- Duplicate PR-ready queue replays for the same key are skipped before any additional merge action runs.
- Final merge failure emits structured activity log metadata and an OpenClaw notification that includes attempts and error class.

Configure retry behavior with:

```bash
export SGT_REFINERY_MERGE_MAX_ATTEMPTS=3
export SGT_REFINERY_MERGE_RETRY_BASE_MS=1000
export SGT_REFINERY_MERGE_RETRY_JITTER_MS=400
```

Observability:
- `REFINERY_MERGE_RETRY pr=#... attempt=<n>/<max> class=<class> delay_s=<seconds>`
- `REFINERY_MERGE_RETRY_SKIP pr=#... attempt=<n>/<max> reason="..."`
- `REFINERY_MERGE_FAILED pr=#... attempt=<n>/<max> class=<class> transient=<true|false> error="..."`
- `REFINERY_DUPLICATE_SKIP pr=#... issue=#... reason_code=duplicate-merge-attempt-key reason="duplicate merge-attempt key (repo+pr+head) already processed" key="owner/repo|pr=<n>|head=<sha>"`

When duplicate queue events are ignored, refinery emits both:
- an operator-visible status line: `duplicate merge skipped — reason_code=duplicate-merge-attempt-key ... key=...`
- a structured activity log event: `REFINERY_DUPLICATE_SKIP ...`

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

SGT can send delivered OpenClaw alerts when refinery reviews/merges a PR. The mayor also emits minimal event summaries when woken by non-periodic events (dog-approved, merged, orphan-pr queued); periodic all-clear checks stay quiet.

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
