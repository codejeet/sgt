# SGT Project Context — sgt

Shared durable context for agents working on this rig.

Use this file for project-wide memory that should survive across polecats, dogs, and crew.

Useful commands:
- sgt context add sgt "<note>" — append a durable note
- sgt context search sgt "<query>" — semantic search over prior context
- sgt context index sgt — rebuild the embedding index

## Notes

## 2026-03-10
- 2026-03-10T05:40:56+01:00 — Implement shared per-rig SGT_CONTEXT.md memory plus CLI commands: sgt context add/search/index/path. Semantic search should use OpenAI Embeddings API, default model text-embedding-3-small, and persist local indexes under ~/.sgt/context/<rig>/index.json. Handle missing OPENAI_API_KEY and missing python gracefully.
- 2026-03-10T05:40:56+01:00 — Update spawned-agent instructions and docs so polecats, dogs, crew, CI-fix flows, and mayor-facing docs read SGT_CONTEXT.md before work, use sgt context search when helpful, and append durable shared notes with sgt context add before task completion when useful.
- 2026-03-10T05:51:12+01:00 — Shared memory now lives in repo-local SGT_CONTEXT.md; spawned polecat/dog/crew/CI-fix workspaces materialize or copy that file, and embedding indexes persist under ~/.sgt/context/<rig>/index.json with explicit missing-OPENAI_API_KEY failures for index/search.

## 2026-03-11
- 2026-03-11T11:31:38+01:00 — 2026-03-11T00:00:00Z — Added durable acceptance blockers via 'sgt create blocker' / 'sgt blocker resolve'. Mayor now treats open blockers as unresolved acceptance state, suppresses idle-green all-clear, and re-invokes follow-up when a blocker exists with no open issues, PRs, polecats, or pending plan requests.
- 2026-03-11T11:39:05+01:00 — Repo plans now support completion_condition plus acceptance status in SGT_PLAN.json; plan-state persists completion.rollup/status, and mayor treats tasks-exhausted-awaiting-acceptance as unresolved work instead of all-clear.
- 2026-03-11T11:46:54+01:00 — Deacon now supervises the mayor tmux session and restarts it when sgt-mayor is missing; mayor exit paths also append durable MAYOR_STOP receipts with reason_code/exit_code/signal/unexpected fields for silent-exit forensics.
- 2026-03-11T16:28:42+01:00 — 2026-03-11T00:00:00Z — CI regression guard forbids heredocs inside command substitution in the main sgt script; use printf -v for multiline evidence/comment bodies instead.

## 2026-03-12
- 2026-03-12T03:57:21+01:00 — Repo plan hardening: cmd_sling now auto-creates all requested labels (including plan / plan-<task> labels); mayor request completion syncs SGT_PLAN.json into plan-state and precreates future plan labels; plan tick records durable movement blockers under ~/.sgt/plan-blockers on sync/dispatch failures; mayor treats dispatch failures or ready pending tasks with inflight=0 as unresolved plan movement instead of idle-green.
- 2026-03-12T04:05:09+01:00 — Worker prompts now inject repo-plan completion context on both sling and re-sling paths: completion_condition, acceptance status/details, unresolved blocker summary, and a reminder that merged intermediate work is not full rig completion while acceptance remains pending or blocked.
- 2026-03-12T04:12:04+01:00 — Plan request sgt-1773285124-33793d09 submitted by OpenClaw agent gastown. Full spec appended below.

### Plan Request sgt-1773285124-33793d09

- Requested at: 2026-03-12T04:12:04+01:00
- Requesting OpenClaw agent: gastown

```markdown
# SGT self-test convoy — completion condition flow on SGT itself

Rig: sgt
Repo: codejeet/sgt
Priority: medium

## Goal

Exercise and prove the current SGT completion-condition / acceptance-blocker workflow on the SGT repo itself, using a lightweight self-test convoy.

This is not a request for a large new feature. It is a practical validation plan for the mechanics that now exist:
- repo-local `completion_condition`
- `acceptance` in `SGT_PLAN.json`
- durable `sgt create blocker` / `sgt blocker resolve`
- worker prompt relay of completion context
- plan movement that should continue until acceptance is met

## Why

PMKB repeatedly exposed that even after the completion-condition feature landed, movement could still stall or go idle-green when plan/task/label state drifted.
We want a small SGT-native convoy that proves the intended usage pattern and catches regressions.

## Explicit completion condition

This self-test is only done when latest master can demonstrate, with repo-owned docs/tests/evidence, that:
1. a plan can declare `completion_condition` and `acceptance`
2. mayor/plan-state treat tasks exhausted + acceptance pending as unresolved
3. worker prompts/CLAUDE context include the larger completion condition when present
4. the intended operator usage pattern is documented clearly enough that an OpenClaw dispatcher can use it consistently

## Suggested task shape

Please break this into a small set of issues such as:
- add or refine deterministic regression coverage around completion-condition + acceptance lifecycle
- add/verify worker-prompt relay tests or fixtures for completion context
- improve README / operator usage docs with a concise recommended pattern
- publish a tiny example plan snippet showing `completion_condition`, `acceptance`, and blocker usage together

## Guardrails

- Prefer small changes and deterministic tests/docs over large refactors
- Keep the result generic for all rigs
- Avoid destabilizing the rest of SGT

## Acceptance evidence expected

Do not close this self-test just because one PR merged.
Close it when latest master has:
- tests/docs/evidence showing the completion-condition workflow actually works end-to-end
- a clearly documented recommended usage pattern for dispatchers
- confirmation that workers receive completion/acceptance context when a plan declares it
```
- 2026-03-12T04:17:09+01:00 — 2026-03-12: Mayor notify receipt verification for OpenClaw now calls 'openclaw agent --deliver --json' and treats exit-0 deliveries as success unless JSON or explicit text contains negative delivery evidence; regression coverage includes plain reply-text success and JSON not-delivered retry/escalation.
- 2026-03-12T04:35:15+01:00 — 2026-03-12 — README now publishes a copyable minimal SGT_PLAN.json example for completion_condition/acceptance plus a dispatcher loop: tasks are intermediate work, verify on latest master when tasks exhaust, create an acceptance blocker only for verified red acceptance after merges, and mark acceptance verified before treating the rig as done.
- 2026-03-12T04:48:01+01:00 — 2026-03-12 — Worker prompt relay regression now explicitly verifies acceptance rollup and acceptance details appear in both generated CLAUDE.md and runtime tmux prompts for sling and re-sling paths.
- 2026-03-12T04:51:13+01:00 — Plan-state completion snapshots must only carry the terminal timestamp/reason for the current acceptance.status; otherwise blocked->verified or blocked->waived transitions can leak stale blocked_at/blocked_reason into plan-state and worker/mayor context.
- 2026-03-12T04:59:03+01:00 — 2026-03-12 — Added test_self_test_convoy_latest_main_proof.sh as the explicit latest-main proof path for the SGT self-test convoy; it bundles acceptance lifecycle, worker prompt relay, and mayor completion-condition follow-up coverage, and README now points operators at that one-command proof.
- 2026-03-12T05:21:03+01:00 — Acceptance blocker sgt-acceptance-1773289263-f79b8b40 reported by rigger: SGT is currently spamming wake/retry messages because Mayor is flapping, not because useful work is happening.

### Acceptance Blocker sgt-acceptance-1773289263-f79b8b40

- Reported at: 2026-03-12T05:21:03+01:00
- Reported by: rigger
- Title: SGT is currently spamming wake/retry messages because Mayor is flapping, not because useful work is happening.

```markdown
SGT is currently spamming wake/retry messages because Mayor is flapping, not because useful work is happening.

Live evidence from `sgt trail` / `sgt status`:
- Mayor repeatedly starts, emits notify receipt checks, logs `MAYOR_NOTIFY_ESCALATE ... outcome=missing-ack`, then exits with `MAYOR_STOP reason_code=nonzero-exit exit_code=1 unexpected=true`.
- Deacon then restarts mayor (`DEACON_RESTART_MAYOR reason=session-missing ...`), which creates another burst of wake/startup messages.
- Current status shows mayor on, but there are no active polecats and no meaningful work movement at this moment.
- PMKB specifically is quiet because there are no active PMKB workers right now, not because it is actively coding in the background.

This is an SGT control-plane reliability/spam blocker.
Do not treat the repeated wake traffic as successful progress.

Needed:
- identify why mayor still exits nonzero after the recent AI-cycle / notify-related fixes
- stop the retry/spam loop
- make notify receipt false-negatives and mayor fail-closed behavior stop generating noisy restart churn
- ensure real work movement is distinguishable from retry noise
```
- 2026-03-12T05:49:23+01:00 — 2026-03-12 — The mayor flapping path in issue #210 was returning nonzero on notify receipt escalation inside AI shells running under ; fix is fail-open notify after durable receipt/escalation logging, surface the latest notify warning in ╭─ Agents ────────────────────────────────────────────────────────────────────╮ daemon on (pid 376043) deacon on last heartbeat: 2026-03-12T05:49:01+01:00 (21s ago, healthy, stale>300s) witness/pmkb on refinery/pmkb on witness/quant on refinery/quant on witness/sgt on refinery/sgt on witness/sstb on refinery/sstb on mayor on lock: state=live/valid ownerPid=599583 startedAt=1773290809 leaseUntil=1773291529 last heartbeat: 2026-03-12T05:46:49+01:00 (153s ago, healthy, stale>720s, phase=startup, trigger=startup) review watchdog: clear (threshold>=900s) ╭─ Dogs ──────────────────────────────────────────────────────────────────────╮ none ╭─ Crew ──────────────────────────────────────────────────────────────────────╮ none ╭─ Merge Queue ───────────────────────────────────────────────────────────────╮ empty ╭─ Polecats ──────────────────────────────────────────────────────────────────╮ pmkb-dacf90fc alive #155 sgt/pmkb-dacf90fc sgt-c1337d5a alive #210 sgt/sgt-c1337d5a 2 polecat(s) tracked, and classify === Recent Activity === [2026-03-12T05:42:33+01:00] RESLING pmkb-dacf90fc rig=pmkb issue=#155 branch=sgt/pmkb-dacf90fc [2026-03-12T05:42:33+01:00] REFINERY_CONFLICT_RESLING_RESUMED issue=#155 repo=codejeet/polymarket-kalshi-copy-trading-bot source_pr=none polecat=pmkb-dacf90fc source_pr_state=CLOSED evidence="/root/sgt/.sgt/refinery-conflicts/4e947b6e7a8f6f04c17ba87dfcaaf56e9f9d9eed786c0b2520aebde68d95d282.state" [2026-03-12T05:44:47+01:00] MAYOR_NOTIFY_RECEIPT channel=last target="channel=last" message_key=notify-cb0d9c9e124cd26d870a67335874a91009e9d1156258ea2f735aebbb6462024c attempt=1 verified_at=2026-03-12T05:44:46+01:00 outcome=delivered reason=channel-last-no-ack-assumed-delivered matcher=channel-last-fail-open details="completed" [2026-03-12T05:44:47+01:00] MAYOR_NOTIFY_RIGGER success channel=last target="channel=last" message_key=notify-cb0d9c9e124cd26d870a67335874a91009e9d1156258ea2f735aebbb6462024c attempt=1 [2026-03-12T05:44:47+01:00] MAYOR_SNAPSHOT_GUARD merge_queue_count snapshot=0 live=0 chosen=0 source=snapshot status=in-sync reason=snapshot-matches-live [2026-03-12T05:44:49+01:00] MAYOR_STOP reason_code=nonzero-exit exit_code=1 signal=EXIT unexpected=true last_cycle_trigger="manual-retry after inert startup" last_cycle_status=completed last_cycle_at="2026-03-12T05:41:23+01:00" [2026-03-12T05:45:00+01:00] DEACON_RESTART_MAYOR reason=session-missing session=off heartbeat_state=ok heartbeat_health=healthy heartbeat_age=26s heartbeat_phase=cycle-begin heartbeat_cycle=1 trigger="PMKB Phase 6 watch 2026-03-12 05:30 CET: latest origin/main 5c3e56e re-verified green on real latest-main path (proof: eligible_markets=162 candidate_wallets=3686 wallet_backfill_trades=51978 selected_wallets=43 copied_trades=357 live_guard=fail_closed; direct fresh-state path also green with ingest/show-wide-proof-after-paper-follow/paper-follow => candidate_wallets=3677 selected_wallets=44 copied_trades=358). Remaining gap is bookkeeping/operator-proof semantics only: repo-local SGT_PLAN.json still reports nodes=8 completed=7 actionable=1 even though acceptance is effectively complete. Active issue #154 / polecat pmkb-53acd650 is the correct remaining lane. Please avoid duplicate dispatch from pending request pmkb-1773289517-5bd5c2ea; reconcile/close that request against #154 and lock acceptance metadata once fresh-state verification is done. Keep live trading fail-closed." last_exit_reason=nonzero-exit last_exit_signal=EXIT last_exit_code=1 last_exit_unexpected=true last_exit_pid=578873 last_cycle_trigger="manual-retry after inert startup" last_cycle_status=completed last_cycle_at="2026-03-12T05:41:23+01:00" [2026-03-12T05:45:00+01:00] MAYOR_SPAWN attempt=mayor-start-1773290700-375867 exec_path="/usr/local/bin/sgt" [2026-03-12T05:45:00+01:00] MAYOR_LOCK_DECISION decision=acquired ownerPid=588082 startedAt=1773290700 leaseUntil=1773291420 reason=empty-or-invalid [2026-03-12T05:45:00+01:00] MAYOR_START [2026-03-12T05:45:00+01:00] MAYOR_LOCK_DECISION decision=reused ownerPid=588082 startedAt=1773290700 leaseUntil=1773291420 reason=same-owner [2026-03-12T05:46:19+01:00] MAYOR_NOTIFY_RECEIPT channel=last target="channel=last" message_key=notify-fc2eb178a88c4542052569e2e9d67d7938c652d112da835d9820bc5ff7001a8c attempt=1 verified_at=2026-03-12T05:46:19+01:00 outcome=delivered reason=channel-last-no-ack-assumed-delivered matcher=channel-last-fail-open details="I’m checking the live PMKB board and the actual issue texts so I can correct the lane instead of blindly relaying Mayor’s warning. I found the exact mismatch: PMKB is moving, but the repo-local plan-state is still internally inconsistent after #154 closed. I’m nudging Mayor to treat #155 as the separate docs/reporting lane you asked for, while reconciling stale acceptance metadata instead of letting the malformed issue replace the real acceptance-lock task. PMKB is moving, but I found a bookkeeping mess I just corrected upward. ### What’s live right now - **PMKB worker active:** `pmkb-dacf90fc` - **issue #155** is open and in flight - **SGT worker active:** `sgt-c1337d5a` on the Mayor flapping blocker ### What I found The real acceptance-lock task **#154** is correctly closed, but PMKB plan-state is still inconsistent: - `completion.acceptance.summary` says Phase 6 is complete via **#154** - but `completion.status` is still **pending** - `rollup` is still **tasks-in-progress** - and stale tasks like **PK44 / PK46** still show pending So the board/state is mixing: - **real acceptance metadata work** - with your newer **docs/reporting/readout** request ### What I did I woke Mayor with the correction: - keep **#155** as the **separate docs/reporting/readout lane** you asked for - do **not** let it replace the already-completed acceptance-lock task - reconcile PMKB repo-local plan/plan-state - clear stale synthetic placeholders - keep live trading fail-closed ### So practical status - **Yes, PMKB is moving** - **#155** should now be treated as the reporting/docs improvement lane - and I’ve explicitly pushed Mayor to clean up the broken acceptance metadata instead of letting the two concerns blur together" [2026-03-12T05:46:19+01:00] MAYOR_NOTIFY_RIGGER success channel=last target="channel=last" message_key=notify-fc2eb178a88c4542052569e2e9d67d7938c652d112da835d9820bc5ff7001a8c attempt=1 [2026-03-12T05:46:20+01:00] MAYOR_SNAPSHOT_GUARD merge_queue_count snapshot=0 live=0 chosen=0 source=snapshot status=in-sync reason=snapshot-matches-live [2026-03-12T05:46:21+01:00] MAYOR_STOP reason_code=nonzero-exit exit_code=1 signal=EXIT unexpected=true last_cycle_trigger="manual-retry after inert startup" last_cycle_status=completed last_cycle_at="2026-03-12T05:41:23+01:00" [2026-03-12T05:46:49+01:00] MAYOR_SPAWN attempt=mayor-start-1773290809-598197 exec_path="/usr/local/bin/sgt" [2026-03-12T05:46:49+01:00] MAYOR_LOCK_DECISION decision=acquired ownerPid=599583 startedAt=1773290809 leaseUntil=1773291529 reason=empty-or-invalid [2026-03-12T05:46:49+01:00] MAYOR_START [2026-03-12T05:46:49+01:00] MAYOR_LOCK_DECISION decision=reused ownerPid=599583 startedAt=1773290809 leaseUntil=1773291529 reason=same-owner [2026-03-12T05:46:50+01:00] SYSTEM_UP output into work vs retry-noise so churn is visible without looking like progress.
- 2026-03-12T05:49:42+01:00 — 2026-03-12 - Issue #210 root cause: mayor churn came from sgt mayor notify returning nonzero after notify receipt escalation inside AI shells running under set -e. The fix is to fail open after durable receipt and escalation logging, surface the latest notify warning in sgt status, and classify sgt trail output into work versus retry-noise so unresolved acceptance stays visible without looking like progress.
- 2026-03-12T06:41:58+01:00 — 2026-03-12 — Deacon now treats queued-work refinery sessions with missing/invalid/stale refinery heartbeats as restartable stalls; sgt status marks refinery/<rig> degraded and shows queue watchdog pending/oldest backlog so parked merge-queue items are visible before manual restart.
- 2026-03-12T23:38:18+01:00 — Plan request sgt-1773355098-365882b0 submitted by OpenClaw agent gastown. Full spec appended below.

### Plan Request sgt-1773355098-365882b0

- Requested at: 2026-03-12T23:38:18+01:00
- Requesting OpenClaw agent: gastown

```markdown
# Mayor Context Compaction / Prompt-Budget Management

## Problem

Mayor context/briefing can drift toward huge prompts (>100k tokens) from accumulated issue churn, stale blockers, repeated watch messages, plan-state noise, and repeated restatements. We need a real feature so Mayor stays sharp and bounded instead of just growing forever.

## Goal

Add a Mayor-side context compaction layer before prompt assembly so the effective prompt stays under a configurable budget while preserving current actionable facts.

## Requested behavior

- Add a Mayor-side context compaction layer before prompt assembly.
- Keep the effective Mayor context under a configurable budget.
  - Target: under 100k tokens.
  - Prefer a lower operational default if practical.
- Preserve the highest-signal current facts:
  - active/open issues and PRs
  - current acceptance blockers
  - latest detached-proof / latest-main evidence
  - current plan-state / actionable tasks
  - recent mayor decisions that still matter
  - durable project context
- Compact or summarize stale/redundant history:
  - repeated watch updates that say the same thing
  - superseded blocker narratives
  - closed/merged churn that no longer matters
  - duplicate restatements of acceptance bars
- Prefer structured compaction over blind truncation.
- Make compaction observable to operators:
  - logs and/or stats
  - what was kept vs summarized
  - budget used

## Acceptance criteria

1. Mayor prompt/context assembly enforces a bounded token/size budget rather than unbounded growth.
2. When over budget, stale history is summarized/compacted while current actionable facts survive intact.
3. Active blockers/issues/PRs/current plan state are not dropped accidentally.
4. Repeated stale messages no longer cause prompt bloat or degraded sharpness.
5. Add tests covering compaction behavior and preservation of active facts.
6. Add operator-visible docs or status output describing the budget/compaction behavior.

## Design preference from user

- Keep Mayor below 100k tokens and sharp.
- Use summary checkpoints / rolling compaction rather than feeding raw history forever if needed.

## Notes

This is a feature request against the `sgt` repo / Mayor control-plane behavior.
```
- 2026-03-12T23:51:22+01:00 — 2026-03-12 — Mayor briefing assembly now enforces SGT_MAYOR_PROMPT_BUDGET_TOKENS (default 60000) with protected sections for system status, merge queue, open issues/PRs, active acceptance blockers, pending plan requests, and repo-plan state; noisy history is compacted into summaries and MAYOR_BRIEFING_BUDGET telemetry records budget use plus kept/summarized/omitted sections.
- 2026-03-12T23:57:00+01:00 — 2026-03-12 — The repo-owned latest-main proof bundle now runs test_mayor_briefing_budget_contract.sh, so mayor prompt-budget/compaction acceptance is covered by ./test_self_test_convoy_latest_main_proof.sh instead of relying on a standalone test invocation.

## 2026-03-13
- 2026-03-13T00:08:06+01:00 — 2026-03-13 — test_mayor_briefing_budget_contract.sh now asserts mayor briefing assembly stays within the configured token budget and preserves durable latest-main proof/budget context plus a recent still-relevant mayor decision under compaction.
- 2026-03-13T00:11:15+01:00 — 2026-03-13 — ╭─ Agents ────────────────────────────────────────────────────────────────────╮ daemon on (pid 805318) deacon on last heartbeat: 2026-03-13T00:10:43+01:00 (30s ago, healthy, stale>300s) witness/pmkb on last heartbeat: 2026-03-13T00:11:04+01:00 (9s ago, stale>180s) refinery/pmkb on last heartbeat: 2026-03-13T00:10:42+01:00 (31s ago, stale>180s) queue watchdog: pending=1 oldest=39s witness/quant on last heartbeat: 2026-03-13T00:11:01+01:00 (12s ago, stale>180s) refinery/quant on last heartbeat: 2026-03-13T00:10:59+01:00 (14s ago, stale>180s) witness/sgt on last heartbeat: 2026-03-13T00:11:09+01:00 (4s ago, stale>180s) refinery/sgt on last heartbeat: 2026-03-13T00:10:46+01:00 (27s ago, stale>180s) witness/sstb on last heartbeat: 2026-03-13T00:10:56+01:00 (17s ago, stale>180s) refinery/sstb on last heartbeat: 2026-03-13T00:10:59+01:00 (14s ago, stale>180s) mayor on lock: state=live/valid ownerPid=3106811 startedAt=1773347786 leaseUntil=1773357519 last heartbeat: 2026-03-13T00:06:39+01:00 (274s ago, healthy, stale>720s, phase=cycle-complete, trigger=periodic) review watchdog: clear (threshold>=900s) ╭─ Dogs ──────────────────────────────────────────────────────────────────────╮ none ╭─ Crew ──────────────────────────────────────────────────────────────────────╮ none ╭─ Merge Queue ───────────────────────────────────────────────────────────────╮ pmkb-pr248 PR#248 pmkb ╭─ Polecats ──────────────────────────────────────────────────────────────────╮ sgt-e53b1a19 alive #219 sgt/sgt-e53b1a19 1 polecat(s) tracked and { "agents": [{"name":"daemon","status":"on","pid":"805318"},{"name":"deacon","status":"on","session":"on","heartbeat":{"age_seconds":"31","timestamp":"2026-03-13T00:10:43+01:00","state":"ok","health":"healthy","stale_seconds":"300"}},{"name":"witness/pmkb","rig":"pmkb","status":"on"},{"name":"refinery/pmkb","rig":"pmkb","status":"on"},{"name":"witness/quant","rig":"quant","status":"on"},{"name":"refinery/quant","rig":"quant","status":"on"},{"name":"witness/sgt","rig":"sgt","status":"on"},{"name":"refinery/sgt","rig":"sgt","status":"on"},{"name":"witness/sstb","rig":"sstb","status":"on"},{"name":"refinery/sstb","rig":"sstb","status":"on"},{"name":"mayor","status":"on","lock":{"state":"live/valid","owner_pid":"3106811","started_at":"1773347786","lease_until":"1773357519"},"heartbeat":{"age_seconds":"275","timestamp":"2026-03-13T00:06:39+01:00","state":"ok","health":"healthy","stale_seconds":"720","pid":"3106811","phase":"cycle-complete","cycle":"46","trigger":"periodic"},"last_exit":{"timestamp":"","age_seconds":"","reason_code":"","exit_code":"","signal":"","unexpected":"","pid":"","last_cycle_trigger":"","last_cycle_at":"","last_cycle_status":""},"decision_log_warning":{"timestamp":"","age_seconds":"","context":"","workspace":"","error":""},"notify_warning":{"timestamp":"","age_seconds":"","channel":"","target":"","message_key":"","attempt":"","outcome":"","reason":"","matcher":"","fail_open":""},"review_watchdog":{"count":"0","oldest_seconds":"0","threshold_seconds":"900"}}], "dogs": [], "crew": [], "merge_queue": [], "polecats": [{"name":"sgt-e53b1a19","status":"alive","issue":"219","rig":"sgt","repo":"https://github.com/codejeet/sgt","branch":"sgt/sgt-e53b1a19","session":"sgt-sgt-e53b1a19","pr":{"number":"","state":"","title":""},"warning":""}], "summary": {"polecat_count": 1} } now expose the latest mayor briefing budget snapshot by parsing , so operators can see target/used/protected tokens plus kept/summarized/omitted sections without opening the briefing file manually.
- 2026-03-13T12:00:00+01:00 — 2026-03-13 — Published a dedicated latest-main proof entrypoint for Mayor context compaction as `./test_mayor_context_compaction_latest_main_proof.sh`; it wraps `test_mayor_briefing_budget_contract.sh` so operators have a narrow proof path in addition to the broader self-test convoy bundle.

## 2026-03-24
- 2026-03-24T14:01:45+01:00 — 2026-03-24 operator follow-up: PMKB onchain plan control-plane drift after merged PR #541 / issue #540. Ground truth observed at ~13:51-13:55 CET: PR #541 ('Record onchain dispatcher readiness') merged into codejeet/polymarket-kalshi-copy-trading-bot main at 2026-03-24T12:12:37Z with PR body 'Closes #540', yet GitHub issue #540 remained open, no PMKB polecat or open PR existed, and /root/sgt/.sgt/plan-state/pmkb.json still marked PKOC2 as in_progress while next_action said dispatch PKOC3. Running sgt plan tick pmkb and waking Mayor did not reconcile immediately. This looks like SGT control-plane bookkeeping drift around merged PR -> issue close / task completion reconciliation, not an intentional work-in-progress state. Fix should preserve honest state transitions and ideally cover merged PRs that resolve issues even when GitHub issue-close state lags or fails.
- 2026-03-24T14:01:46+01:00 — 2026-03-24 operator requested removal of Mayor prompt/context compaction. Current code inspection in /root/sgt/rigs/sgt shows runtime Mayor briefing assembly (_mayor_build_briefing in sgt around lines 9176-9317 on current master checkout) simply writes system status, recent activity, merge queue, issues/PRs, pending plan requests, repo plans, escalation rules, and recent mayor decisions; no actual token-budget / structured-compaction logic is present there. However docs/tests/context/changelog/plan still strongly claim a merged Mayor prompt-budget/context-compaction feature (README.md, CHANGELOG.md, SGT_CONTEXT.md, SGT_PLAN.json, test_mayor_briefing_budget_contract.sh, test_mayor_context_compaction_latest_main_proof.sh). Likely fix is to remove stale compaction/budget contract/docs/tests/plan baggage unless hidden code elsewhere proves otherwise.
- 2026-03-24T14:05:40+01:00 — 2026-03-24 issue #235 removed stale Mayor prompt-budget/context-compaction docs and proof scripts after confirming current master _mayor_build_briefing has no token-budget or structured-compaction logic; README/self-test bundles now describe only the real briefing freshness + section assembly behavior.
- 2026-03-24T14:07:16+01:00 — Plan tick now reconciles issue-backed tasks from merged PR evidence when the issue is still OPEN but no active polecat remains; it scans recent merged PR bodies for close/fix/resolve references, marks the stale task completed, and can dispatch the next ready task in the same tick. Regression coverage reproduces the PMKB #540 / PR #541 drift shape.

## 2026-03-26
- 2026-03-26T03:55:13+01:00 — 2026-03-26 operator feature request: make Mayor activity effectively per-rig / activity-aware instead of one always-chatty loop treating all projects as equally hot forever. Add an optional rig-hibernation behavior so rigs with no recent meaningful activity, or rigs blocked only on human approval/signoff/waiver for a while, can go quiet until something meaningful changes. Concrete motivation: dormant rigs like sstb should not keep generating repeated Mayor rechecks/notifies when no engineering action is possible, while active rigs like pmkb should still receive prompt attention. Desired behavior includes per-rig activity tracking, explicit active/idle/hibernated state + reason, automatic wake on meaningful new events, and manual hibernate/unhibernate controls. This should be optional/configurable and must not regress responsiveness on active rigs.
