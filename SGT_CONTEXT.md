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
- 2026-03-26T04:04:06+01:00 — Per-rig Mayor activity is now tracked in ~/.sgt/mayor-rig-activity/<rig>.state with explicit active/idle/hibernated state, status/JSON visibility, manual 'sgt mayor hibernate|unhibernate|rig-status' controls, and event-driven auto-unhibernate for meaningful rig-targeted wakes. Auto-hibernation stays optional via SGT_MAYOR_RIG_AUTO_HIBERNATE_SECS; per-rig activity tracking can be disabled with SGT_MAYOR_RIG_ACTIVITY=0.
- 2026-03-26T04:14:17+01:00 — 2026-03-26 live bug repro: 0.510 2026-03-26 line 1497 Title: Acceptance remains blocked by explicit human operator signoff, not engineering work. /root/sgt/rigs/sstb/SGT_PLAN.json c 0.502 2026-03-26 line 1503 2026-03-26T03:48:19+01:00 — Acceptance blocker sstb-acceptance-1774493299-57f2e855 reported by rigger: Issue #216 remains blocked: docs/ops/hq_system_operator_signoff.md now records **Decision**: Hold because authorized hum 0.496 2026-03-26 line 1491 2026-03-26T03:14:35+01:00 — Acceptance blocker sstb-acceptance-1774491275-3711036e reported by rigger: Acceptance remains blocked by explicit human operator signoff, not engineering work. /root/sgt/rigs/sstb/SGT_PLAN.json c 0.482 2026-03-26 line 1509 Title: Issue #216 remains blocked: docs/ops/hq_system_operator_signoff.md now records **Decision**: Hold because authorized hum 0.463 2026-03-26 line 1502 2026-03-26T03:48:19+01:00 — Issue #216: corrected docs/ops/hq_system_operator_signoff.md from an inconsistent automated 'Approve' state to explicit 'Hold'. Durable rule: HQ/HFT deployment acceptance stays blocked until an authorized human operator and risk reviewer sign, or explicitly waive, the final deployment artifact; engineering evidence alone is insufficient. crashed with raw JSONDecodeError Extra data while reading /root/sgt/.sgt/context/sstb/index.json. The bad file was ~5.0 MB and the captured corruption excerpt around char 3385386 looked like , indicating malformed/corrupted serialized index content rather than a clean object. Manual /root/sgt/.sgt/context/sstb/index.json immediately repaired the symptom and search worked again, so the fix lane should be robustness/self-healing plus write-hardening: context search must not crash Mayor/callers on malformed JSON, should ideally auto-rebuild/retry or at least fail with a crisp operator message, and should investigate how the index became malformed (atomic write / concurrent write / interrupted serialization bug).
- 2026-03-26T04:14:43+01:00 — 2026-03-26 live bug repro: sgt context search sstb "human signoff blocker" crashed with raw JSONDecodeError Extra data while reading /root/sgt/.sgt/context/sstb/index.json. The bad file was ~5.0 MB and the captured corruption excerpt around char 3385386 looked like ...0.0075484635]}]}0406646728515625..., indicating malformed/corrupted serialized index content rather than a clean object. Manual `sgt context index sstb` immediately repaired the symptom and search worked again, so the fix lane should be robustness/self-healing plus write-hardening: context search must not crash Mayor/callers on malformed JSON, should ideally auto-rebuild/retry or at least fail with a crisp operator message, and should investigate how the index became malformed (atomic write / concurrent write / interrupted serialization bug).
- 2026-03-26T04:17:23+01:00 — 2026-03-26 operator follow-up on the new rig-hibernation feature: current merged behavior quiets Mayor state/churn, but it does not actually make a rig cold because witness/<rig> and refinery/<rig> keep running after . Operator expectation is stronger: hibernating a rig should also stop that rig's witness and refinery agents, and unhibernating / meaningful auto-wake should bring them back. Scope should stay per-rig and should not kill unrelated global services or active polecats by surprise.
- 2026-03-26T04:17:50+01:00 — 2026-03-26 operator follow-up on the new rig-hibernation feature: current merged behavior quiets Mayor state/churn, but it does not actually make a rig cold because witness/<rig> and refinery/<rig> keep running after manual rig hibernation. Operator expectation is stronger: hibernating a rig should also stop that rig's witness and refinery agents, and unhibernating / meaningful auto-wake should bring them back. Scope should stay per-rig and should not kill unrelated global services or active polecats by surprise.
- 2026-03-26T04:18:13+01:00 — Context index corruption in ~/.sgt/context/<rig>/index.json was traced to a shared fixed temp path during rebuilds; fix uses unique fsynced temp files plus search-side malformed-index rebuild/retry instead of crashing on JSONDecodeError.
- 2026-03-26T04:20:28+01:00 — 2026-03-26 operator clarification after the first hibernation features: the intended architecture is not only per-rig activity state inside one shared Mayor. The deeper ask is one dedicated Mayor per rig (pmkb, sgt, sstb, etc.) so rigs do not share a single Mayor attention loop at all. Treat this as a separate architecture lane from issue #241 (which is only about hibernation stopping witness/refinery).
- 2026-03-26T04:22:12+01:00 — 2026-03-26 — Rig hibernation now synchronizes per-rig support agents: mayor hibernate/unhibernate and auto-hibernate transitions stop or restart witness/<rig> and refinery/<rig>, and deacon enforces hibernated rigs staying cold instead of restarting them.
- 2026-03-26T04:34:40+01:00 — Optional per-rig Mayor architecture is now supported via SGT_MAYOR_ARCHITECTURE=per-rig. In that mode SGT runs one tmux Mayor session per rig (sgt-mayor-<rig>), stores scoped Mayor state/logs under ~/.sgt/mayors/<rig>/, routes rig-targeted wake reasons only to the matching Mayor, and surfaces mayor/<rig> entries in sgt status and sgt status --json.
- 2026-03-26T04:41:12+01:00 — Per-rig Mayor mode (SGT_MAYOR_ARCHITECTURE=per-rig) must preserve the existing rig-hibernation contract: manual/auto hibernation and deacon enforcement still stop witness/<rig> and refinery/<rig>, and unhibernate/event wake must restart them.
- 2026-03-26T09:36:54+01:00 — Manual rig hibernation is currently not authoritative in live SGT. Root cause from origin/master:sgt b24d2f8: (1) _mayor_wake_reason_is_meaningful() returns true for every non-periodic wake (lines 1085-1093), and _mayor_rig_maybe_unhibernate_for_event() auto-unhibernates any hibernated rig on such wakes (1325-1330); acceptance-blocker:* therefore wakes manually hibernated rigs. (2) Mayor event loop sets cycle_target_rigs[rig]=1 before later skip guards, and loops only skip hibernated rigs when the rig is NOT in cycle_target_rigs (10667-10672, 10805-10806, 10983-10988), so event-targeted hibernated rigs still get agent/startup and plan-tick processing. (3) Dispatch helpers do not enforce hibernation: cmd_sling has no _mayor_rig_hibernated guard; _plan_tick_run calls cmd_sling directly (5713-5727); sweep watchdog and witness resling call _resling_existing_issue without hibernation checks (7855-7868, 8223-8232), and _resling_existing_issue itself has no hibernation guard (8318+). Live evidence on sstb: deacon enforced hibernation at 09:16:42-09:16:43 CET, but issue #223 still dispatched at 09:16:58; acceptance-blocker wakes at 09:24:58 and 09:25:49 auto-unhibernated the rig; sweep/watchdog also reslung #218. Fix should make manual hibernation authoritative until explicit manual unhibernate, block cycle_target_rigs bypass for manual hibernation, and add hard dispatch fences to sling/resling/plan tick paths.
- 2026-03-26T09:45:58+01:00 — 2026-03-26: Manual rig hibernation is now authoritative until explicit : activity refresh preserves manual mode across mayor restarts, event-targeted mayor cycles no longer bypass manual hibernation, and dispatch fences now block sling, plan tick dispatch, sweep watchdog resling, witness stalled-worker resling, and direct resling helper dispatch while leaving passive status/logging intact. Regression coverage: test_mayor_rig_hibernation.sh, test_manual_hibernation_dispatch_fences.sh, test_witness_manual_hibernation_skip.sh.
- 2026-03-26T09:46:05+01:00 — 2026-03-26: Manual rig hibernation is now authoritative until explicit sgt mayor unhibernate. Activity refresh preserves manual mode across mayor restarts, event-targeted mayor cycles no longer bypass manual hibernation, and dispatch fences now block sling, plan tick dispatch, sweep watchdog resling, witness stalled-worker resling, and direct resling helper dispatch while leaving passive status/logging intact. Regression coverage: test_mayor_rig_hibernation.sh, test_manual_hibernation_dispatch_fences.sh, test_witness_manual_hibernation_skip.sh.
- 2026-03-26T20:18:42+01:00 — Observed PMKB canonical issue #679 enter a witness resling loop because Codex workers were hitting backend usage limits and exiting before opening a PR. Operator diagnosis: the underlying signature is the first Codex output containing 'You've hit your usage limit'. Current SGT behavior misclassifies this as generic WITNESS_STALLED dead/no-PR and immediately re-slings again, creating issue-comment spam and repeated dead polecats. Desired fix: detect codex usage-limit text from first message/output, classify as explicit backend/quota-limited blocker (for example reason_code=codex_usage_limit or backend_usage_limit), suppress immediate resling loops, and surface one operator-readable blocked state/comment instead of repeated stalled comments.
- 2026-03-26T20:27:09+01:00 — Codex polecat sessions now persist terminal output to .sgt-agent-output.log so witness can detect first-output quota failures. When the first captured Codex output contains 'You've hit your usage limit', witness classifies the death as reason_code=codex_usage_limit, labels the issue backend-limited + codex-usage-limit, records an acceptance blocker, and sweep/resling paths skip further auto-resling for that issue.
- 2026-03-26T22:37:24+01:00 — 2026-03-26 live controller bug: after PMKB dead-polecat cleanup, watchdog reslings for #693/#691 can die with 'command too long', and Mayor consistency revalidation can stay wedged on mismatch_categories=polecat-liveness even when sgt status shows no tracked polecats. snapshot open_polecats stayed > live open_polecats after nuke/sweep/manual dispatch retries, blocking fresh dispatch for #679/#693. Need self-healing stale polecat accounting after failed spawn / cleanup and clean handling for oversized command assembly.
- 2026-03-26T22:55:43+01:00 — Acceptance blocker sgt-acceptance-1774562143-94f532df reported by witness: Replacement work required after stalled polecat for issue #251

### Acceptance Blocker sgt-acceptance-1774562143-94f532df

- Reported at: 2026-03-26T22:55:43+01:00
- Reported by: witness
- Title: Replacement work required after stalled polecat for issue #251

```markdown
Replacement work required after stalled polecat for issue #251

Stalled polecat recovery did not produce replacement work.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #251
- Issue URL: https://github.com/codejeet/sgt/issues/251
- Issue title: Fix stale polecat-liveness mismatch after failed dispatch cleanup
- Polecat: sgt-c093b3ac
- Failure reason: witness-stalled-resling-failed

Required follow-up:
- create replacement work (new PR or re-dispatched polecat) before closing the incident
- re-investigate why the worker exited without producing a PR

```
- 2026-03-26T22:57:25+01:00 — 2026-03-26 post-#251 deploy blocker: stale polecat bookkeeping now recovers correctly, but real PMKB redispatches for #696/#693/#679 still fail at launch with RESLING_SPAWN_FAILED reason_code=command-too-long. Need to stop embedding oversized polecat launch payloads directly into tmux command strings; use file/stdin/wrapper launch instead and add regression coverage.
- 2026-03-26T23:16:30+01:00 — 2026-03-26 issue #254: polecat sling/resling launches now write the runtime worker prompt to .sgt-polecat-prompt.md in the worktree and start tmux with a short file-based backend command, preventing command-too-long redispatch failures while leaving failed-spawn cleanup bookkeeping unchanged. Regression coverage: test_oversized_dispatch_payload_prompt_file.sh plus updated worker prompt runtime assertions.
- 2026-03-26T23:29:54+01:00 — Acceptance blocker sgt-acceptance-1774562143-94f532df resolved.

## 2026-03-30
- 2026-03-30T01:58:00+02:00 — 2026-03-30 operator requested a first-class 'sgt mayor refresh' command: soft-reset Mayor transient context/workspace automatically, generate a durable handoff markdown/doc from current Mayor context before reset, preserve durable board state, and print the handoff artifact path on success. Manual production baseline came from the 2026-03-30 ~01:49 CET soft reset flow (stop, archive transient Mayor files, start, wake).
- 2026-03-30T02:11:53+02:00 — 2026-03-30 — Added 'sgt mayor refresh [rig]' to archive transient Mayor context into ~/.sgt[/mayors/<rig>]/handoffs/<token>/, write a handoff.md snapshot, restart+wake Mayor, and print the handoff path. Refresh had to reapply per-rig scope after cmd_status/_mayor_build_briefing because those helpers mutate mayor scope, and _cmd_mayor_stop_one now returns 0 even when no FIFO exists so refresh/stop do not fail spuriously.
- 2026-03-30T04:29:18+02:00 — 2026-03-30 operator diagnosis: _find_recent_duplicate_issue currently matches recently closed issues too, so fresh sling dispatches can be suppressed against closed work (example: PMKB capture regression suppressed against closed #865). Separate live symptom: PMKB was left active with open issue #872 but zero active polecats/open PRs while Mayor stayed healthy and kept cycling, so SGT needs a stronger invariant against actionable rigs idling with zero workers.
- 2026-03-30T04:31:10+02:00 — 2026-03-30: sling duplicate cooldown now ignores closed issues entirely; _find_recent_duplicate_issue checks only open issues, so freshly closed work no longer suppresses replacement dispatches for the same symptom.
- 2026-03-30T04:36:10+02:00 — 2026-03-30: Mayor now enforces bounded stranded-rig recovery for non-hibernated rigs with open sgt-authorized issues but zero open PRs, zero active polecats, and zero merge-queue items; it attempts one replacement dispatch per cycle and logs MAYOR_STRANDED_RIG_RECOVERY_DISPATCH/BLOCKED telemetry with explicit reason_code values.
- 2026-03-30T05:59:21+02:00 — Plan request sgt-1774843161-c615ad59 submitted by OpenClaw agent gastown. Full spec appended below.

### Plan Request sgt-1774843161-c615ad59

- Requested at: 2026-03-30T05:59:21+02:00
- Requesting OpenClaw agent: gastown

```markdown
# SGT Plan Request — JARVIS-style real-time operations cockpit for SGT Web UI

## Goal

Turn the existing SGT Web UI into a real-time operator cockpit for SGT, with:

1. **Live monitoring of the Mayor and all active polecats**
   - real-time tmux-backed views of their output/logs
   - fast switching + multi-pane monitoring
   - stale/disconnected indicators
2. **An Iron Man / JARVIS-style interface**
   - visually striking HUD-style operator UI
   - but still dense, practical, and readable for real work
3. **Optional ElevenLabs TTS for acceptance blockers**
   - announce newly created acceptance blockers / critical blocker transitions
   - fully optional and gracefully disabled if not configured
4. **A WebGL live visualization**
   - real-time view of rigs / Mayor / polecats / PRs / blockers / queue relationships
   - useful, not just decorative

## Current baseline / source of truth

- Existing SGT Web UI already exists under the **repo-tracked** path: `web/` in `codejeet/sgt`
- There is also a running/deployed copy at `/root/sgt/web`
- Current running copy and repo `web/` are presently identical, but future work should treat the **repo copy** as canonical source-of-truth
- Current app is a small Node/Express + WebSocket dashboard with status/logs/dispatch functionality
- Current live URL is served from the Tailscale host on port `4747`

## Product intent

This should feel like a serious operations console — not a toy dashboard.

Desired vibe:
- dark HUD / JARVIS-inspired visual language
- strong live-state awareness
- clear alerting
- low cognitive load under pressure
- compact operator ergonomics

Important: do **not** let the visual theme make it less useful. Dense and practical beats flashy-but-useless.

## Requested outcome

### A. Live tmux monitoring

Add live browser views for:
- Mayor
- all active polecats
- ideally extensible to witness/refinery/dogs/crew later via same mechanism

Requirements:
- real-time or near-real-time streaming, not static snapshots
- multiple simultaneous panes/cards
- easy switching/filtering by rig / issue / worker / role
- clear stale/disconnected/reconnecting state
- support tail/follow behavior for active logs
- support quick peek / expand / focus mode

### B. JARVIS-style UI shell

Redesign the UI into a cohesive ops cockpit.

Expected qualities:
- HUD-style layout
- strong information hierarchy
- visibly distinct states for healthy / active / blocked / stale / critical
- keyboard-friendly operator flow where sensible
- preserve existing useful controls (dispatch, logs, status) if still valuable

### C. Acceptance blocker alerting + optional ElevenLabs TTS

When new acceptance blockers are created:
- surface them prominently in the UI
- make them visually obvious
- optionally announce them via ElevenLabs TTS

Requirements:
- fully optional: if ElevenLabs config is absent, feature should silently degrade to visual-only
- must not require secrets committed to repo
- add env/config-driven enablement
- include mute/disable control and dedupe/rate-limiting so it does not spam
- blocker announcements should focus on meaningful new blocker events, not noisy repeats

### D. WebGL visualization

Add a live visual layer showing relationships between:
- Mayor
- rigs
- active polecats
- open PRs
- open issues
- acceptance blockers / blocked state
- maybe merge queue / wake events if it helps

Requirements:
- live-updating from the same backend state/event stream
- genuinely useful for orientation / status, not just eye candy
- degrade gracefully if browser/GPU support is weak
- should not make the app laggy or unusable on normal operator hardware

## Strong constraints

1. **Canonical code lives in repo `web/`**
   - do not create yet another divergent standalone web UI tree
   - if deployment still uses `/root/sgt/web`, include an explicit sync/deploy path after merge
2. **Do not break the current useful dashboard behavior**
   - existing status/log/dispatch functionality should remain available or be cleanly superseded
3. **Do not require ElevenLabs to use the UI**
   - TTS is optional enhancement, not a hard dependency
4. **Avoid gimmicks that reduce usability**
   - keep the operator workflow primary
5. **Tailnet-first ops**
   - assume this is primarily used over Tailscale / trusted operator access, not as a public internet app

## Suggested plan shape

The Mayor should decompose this into a real multi-step plan rather than one giant sling. Likely shape:

1. **Audit / architecture pass**
   - inspect current `web/` implementation
   - decide backend/frontend shape for live tmux streaming and live event model
   - decide how to keep repo `web/` canonical while updating deployed copy cleanly
2. **Backend streaming foundation**
   - real-time tmux/log/event streaming API / WS model
   - live data model for mayor, polecats, blockers, PRs, rigs
3. **UI shell / JARVIS redesign**
   - new layout system + operator panels + state presentation
4. **Live tmux monitor views**
   - Mayor + active polecats first
   - multi-pane / focus / stale states
5. **Acceptance blocker alerting + optional TTS**
   - visual alert center + optional ElevenLabs announcements
6. **WebGL visualization**
   - live relationship graph / spatial view / systems model
7. **Docs + deploy + polish**
   - setup docs, config docs, deployment/sync path, screenshots, operator instructions

## Completion condition

This plan is complete when an operator can open the SGT Web UI and:
- watch the Mayor and all active polecats live in-browser,
- see actionable blocker/rig/PR state in real time,
- receive optional acceptance-blocker TTS alerts when configured,
- use a WebGL live visualization that meaningfully reflects current system state,
- and do so from the repo-tracked `web/` implementation with a clear deployment path.

## Acceptance criteria

1. **Live monitor**: Mayor + active polecats can be watched live in browser with fresh updates and visible stale/reconnect state.
2. **Operator usability**: UI is materially improved into a coherent JARVIS-style ops console without losing core utility.
3. **Blocker alerts**: new acceptance blockers are prominently surfaced in UI.
4. **Optional TTS**: when ElevenLabs config is provided, new acceptance blockers can be voiced; when not provided, UI still works normally.
5. **WebGL**: a live WebGL visualization exists and reflects current SGT state in a meaningful way.
6. **Canonical source**: repo `web/` is the maintained source of truth; deployment/update story is documented.
7. **Docs**: README/setup/config docs explain local run, env vars, optional ElevenLabs setup, and deployment/sync path.
8. **Graceful degradation**: weak browsers / missing TTS / missing WebGL support do not break the app.

## Operator preference / direction

Be bold about improving the interface. This is explicitly meant to become a serious real-time ops cockpit, not just a lightly polished log page.
```
- 2026-03-30T06:02:29+02:00 — Plan request clarification for sgt-1774843161-c615ad59: for ElevenLabs/TTS in the SGT WebUI JARVIS cockpit, the operator mainly wants voice notifications when blockers are cleared/resolved or major milestones are met. New blocker creation/escalation should stay visible in the UI, but TTS for new blockers is lower-priority and should be optional/configurable to avoid noisy negative chatter. The updated spec file at /home/aj/.openclaw/agents/gastown/workspace/notes/sgt-webui-jarvis-plan-2026-03-30.md reflects this preference and should be treated as the latest source text for the pending request.
- 2026-03-30T06:08:58+02:00 — Issue #262 audit locked the SGT Web cockpit to the existing repo-tracked web/ app: keep a single Node/Express + vanilla JS process, grow it around a normalized snapshot/event model with backend-mediated on-demand tmux streams, treat acceptance blockers as first-class cockpit events, and deploy the canonical repo copy to /root/sgt/web via web/scripts/sync-live-copy.sh.
- 2026-03-30T06:18:13+02:00 — 2026-03-30 issue #264 added the first normalized web cockpit backend in repo web/: /api/cockpit now emits meta/agents/rigs/workers/queue/blockers/logs/topology from sgt status --json plus blocker files, and the WebSocket now supports demand-driven tmux stream subscribe/unsubscribe with stream/open,data,stale,close events while preserving legacy status/log pushes for the existing UI.
- 2026-03-30T06:26:45+02:00 — 2026-03-30 issue #266 redesigned repo web/ into a dense single-page operator shell: static assets now live in web/public/{index.html,styles.css,app.js}, the UI consumes normalized snapshot + tmux stream events directly, surfaces blockers in an alert center, keeps live Mayor/worker focus panes, and renders topology as a canvas radar with WebGL-readiness messaging while preserving dispatch/log workflows.
- 2026-03-30T06:33:05+02:00 — 2026-03-30 issue #268 updated the repo web operator shell live-stream wall so Mayor stays pinned in dedicated monitor cards, all filtered active polecat streams subscribe simultaneously instead of capping at four, and operators can filter by rig/role/query plus toggle per-pane or global tail-follow from the browser.
- 2026-03-30T06:34:31+02:00 — 2026-03-30: web/ now tracks blocker transition alerts in the normalized cockpit snapshot and exposes an optional ElevenLabs-backed /api/announcements/:alertId/audio path. Alert rail stays useful with no TTS config; voice is env-gated via SGT_WEB_ELEVENLABS_API_KEY + SGT_WEB_ELEVENLABS_VOICE_ID, browser-mutable, and backend rate-limited with SGT_WEB_VOICE_EVENT_KINDS / SGT_WEB_VOICE_RATE_LIMIT_SECS.
- 2026-03-30T06:40:53+02:00 — 2026-03-30: web cockpit now emits blocker transition alerts in the normalized snapshot as alerts[] plus meta.voice config, exposes optional /api/announcements/:alertId/audio ElevenLabs playback behind SGT_WEB_ELEVENLABS_API_KEY + SGT_WEB_ELEVENLABS_VOICE_ID, and keeps browser-local mute with backend event gating/rate limiting via SGT_WEB_VOICE_EVENT_KINDS and SGT_WEB_VOICE_RATE_LIMIT_SECS.
- 2026-03-30T06:41:45+02:00 — 2026-03-30 issue #272 replaced the web topology placeholder with a live graph layer: backend topology snapshots now materialize rigs, workers, issues, PRs, blockers, and queue nodes/edges explicitly, and the browser renders them through a force-laid WebGL graph with click/hover focus plus a canvas fallback when WebGL init/support is unavailable.
- 2026-03-30T06:49:29+02:00 — 2026-03-30 issue #272 replaced the operator-shell topology placeholder with a live force-laid graph: cockpit snapshots now emit explicit rig/worker/issue/PR/blocker/queue nodes and relationship edges, and the browser renders them through a WebGL node-edge pass with click/hover focus plus a canvas fallback when WebGL is unavailable.
- 2026-03-30T06:54:49+02:00 — 2026-03-30: Web cockpit docs now explicitly document the canonical deploy path from repo web/ to /root/sgt/web via web/scripts/sync-live-copy.sh, including SGT_WEB_LIVE_DIR override and runtime config defaults; the repo-owned latest-main proof entrypoint is ./test_web_cockpit_latest_main_proof.sh, which runs npm --prefix web test plus a dry-run sync-helper check.
- 2026-03-30T07:29:16+02:00 — Plan request sgt-1774848556-335e7d83 submitted by OpenClaw agent gastown. Full spec appended below.

### Plan Request sgt-1774848556-335e7d83

- Requested at: 2026-03-30T07:29:16+02:00
- Requesting OpenClaw agent: gastown

```markdown
# SGT Plan Request — Humanize and refine the SGT Web UI after cockpit v1

## Goal

Create a second-phase SGT plan focused on **improving the current cockpit UI so it feels more intentional, more human-designed, and less like generic AI-generated dashboard CSS**, while preserving the real-time monitoring work that already landed.

This is not a greenfield rewrite. The verified cockpit foundation already exists. This phase is about:
- design research,
- anti-pattern identification,
- layout hierarchy fixes,
- visual refinement,
- and a more human-looking operator shell.

## Operator directives (explicit)

The operator wants the current UI improved with these concrete changes:

1. **The livestream should be the first part of the page**
   - it should come before the alert center
   - operator attention should land on live Mayor / polecat activity first
2. **The title should not literally say "Jarvis Cockpit"**
   - use: `SGT SGT Cockpit`
3. **Less gradients**
   - tone them down materially
   - avoid over-stylized AI-dashboard glow soup
4. **Less rounded corners**
   - prefer square corners or only extremely light rounding (1–2px)
5. **More use of color**
   - use a stronger **triadic** color theme
   - still dark mode
   - still keep the blue as part of the palette

## Critical product direction

The first implementation step should **not** jump straight into visual tweaking.

The operator explicitly wants a research-first lane that studies:
- common AI-generated CSS / dashboard tells
- what makes a UI feel obviously machine-generated
- what to avoid to make the design feel more human-created
- design prompt(s) or style rules derived from that research that guide the actual redesign

## What this plan should do

### 1. Research lane first

The **first issue** should be a research/design-analysis issue for the SGT Web UI, covering at least:
- common AI-generated CSS/dashboard tropes
- common AI layout tells
- common overused AI visual treatments in dark dashboards
- what human-designed operator UIs tend to do differently
- a distilled “avoid this / prefer this” list
- one or more concrete design prompts or design principles for the redesign phase

This first lane should answer questions like:
- what visual patterns make dashboards look AI-generated?
- how do we avoid generic glassmorphism / excessive gradients / over-rounded cards / glowy sci-fi cliché?
- how do we keep the cockpit visually strong without making it look like prompt-slop?
- what specific design rules should guide the next implementation lane?

### 2. Layout hierarchy fix

After research, the redesign must adjust the information hierarchy so that:
- **live monitoring / livestream** is the first thing on the page
- alerts remain important, but do not dominate the entry point
- the page feels like an operator tool first, not an alert inbox

### 3. Naming fix

Replace the visible title/branding so it says:
- `SGT SGT Cockpit`

and remove the literal “Jarvis Cockpit” wording from the operator-facing UI.

### 4. Visual refinement / humanization

Redesign the current UI to feel more human-created and less AI-generated.

Strong preferences:
- dark mode stays
- blue stays
- triadic palette gets stronger/more intentional
- reduce gradients materially
- reduce corner radius materially
- avoid “default AI dashboard” styling clichés

### 5. Redesign implementation

The redesign phase should be downstream from the research lane and should use the resulting design prompts / anti-pattern guidance rather than improvising blindly.

## Scope constraints

1. **Do not lose the real-time cockpit functionality**
   - preserve the new streaming, monitors, blocker alerts, topology, and operator shell work already landed
2. **Canonical source remains repo `web/`**
   - no new divergent web tree
3. **Deployment path remains explicit**
   - if live `/root/sgt/web` must be updated after merge, document/sync it cleanly
4. **Research must drive design**
   - do not skip the anti-AI-CSS research lane
5. **Avoid lazy neon-sci-fi clichés**
   - the operator explicitly wants something that feels more intentional and less machine-generated

## Suggested plan shape

1. **Research common AI-generated dashboard/CSS tells**
   - anti-pattern catalog
   - human-design heuristics
   - concrete design prompts / redesign rules
2. **Refine layout hierarchy**
   - livestream first, alert center secondary
3. **Humanize the visual system**
   - title change to `SGT SGT Cockpit`
   - stronger dark triadic palette with blue retained
   - much less gradient
   - much less corner rounding
4. **Implement redesign without regressing cockpit features**
5. **Deploy/sync/update proof**
   - ensure served copy reflects merged repo code

## Completion condition

This plan is complete only when:
- the current SGT cockpit has been visually refined according to the operator’s direction,
- the livestream is the first section of the page,
- the title reads `SGT SGT Cockpit`,
- the UI clearly avoids common AI-generated CSS/dashboard tells identified in the research step,
- the palette is a stronger dark triadic theme that still includes blue,
- gradients and corner radius are materially reduced,
- and the updated UI is deployed/synced to the live served copy.

## Acceptance criteria

1. A first research issue exists and lands concrete findings on AI-generated CSS/dashboard tells, what to avoid, and design prompts/style rules for the redesign.
2. The redesign is clearly derived from that research, not generic improvised styling.
3. Live monitoring / livestream is the first section of the page.
4. Operator-facing title reads exactly `SGT SGT Cockpit`.
5. Gradients are materially reduced.
6. Corner radius is materially reduced (prefer square / 1–2px rounding).
7. The theme is dark, more colorful, triadic, and still retains blue.
8. Real-time cockpit functionality remains intact.
9. Live served UI is updated after merge.

## Notes for Mayor

This is intentionally a **phase-2 refinement plan** after the already-verified cockpit build. Treat it as a follow-on design/UX/humanization plan, not a replacement of the first cockpit plan.
```
- 2026-03-30T07:36:24+02:00 — 2026-03-30 issue #278 added web/docs/human-dashboard-redesign-rules.md as the canonical anti-pattern catalog and redesign rule set for the cockpit humanization pass: move live monitoring to the first section, title the shell SGT SGT Cockpit, materially reduce gradients/glow and corner radius, keep a dark triadic palette with blue retained, and preserve repo web/ -> /root/sgt/web sync as the deployment path.
- 2026-03-30T07:40:23+02:00 — 2026-03-30 issue #280 moved the web cockpit live monitor ahead of Alert Center, renamed the visible shell title to SGT SGT Cockpit, remapped keyboard shortcut 1 to streams and 2 to overview, and re-synced the live served copy with web/scripts/sync-live-copy.sh.
- 2026-03-30T07:43:50+02:00 — 2026-03-30 operator request: SGT should auto-detect truly stalled polecats and resling them, but must distinguish quiet long-running compute from real wedges. Live example: PMKB polecat pmkb-14ad1d1c looked frozen in WebUI, yet process-tree inspection showed codex exec plus active python realism/shadow report children at ~100% CPU. Needed fix: classify busy-long-running vs genuinely stalled, and only auto nuke/resling the latter.
- 2026-03-30T07:50:12+02:00 — 2026-03-30: Witness/runtime status now classifies alive polecats by output freshness plus process-tree signals. Quiet workers with a substantive child process stay alive as busy-long-running; only quiet workers past the stall threshold with no substantive child are auto-killed and reslung. Status JSON/Web snapshot expose runtime.classification/reason/summary for operator visibility.
- 2026-03-30T07:52:14+02:00 — 2026-03-30 issue #283 applied the research-backed cockpit humanization pass in web/public/: removed remaining sci-fi labels like Command Pulse/Topology Radar, replaced Orbitron-heavy/pill-heavy styling with flatter low-radius surfaces, differentiated live/alerts/topology sections with a restrained dark triadic blue-amber-plum system, updated topology graph colors to match, added regression tests for no backdrop-filter/999px/Orbitron tokens, and re-synced the served copy with web/scripts/sync-live-copy.sh.
- 2026-03-30T07:58:12+02:00 — 2026-03-30 issue #286 verified the cockpit proof path still passes (npm --prefix web test and ./test_web_cockpit_latest_main_proof.sh), synced /root/sgt/web from repo web/, and updated web/scripts/sync-live-copy.sh to preserve live package-lock.json alongside node_modules/ and webui.log so a post-sync dry run stays clean.
- 2026-03-30T08:12:58+02:00 — 2026-03-30 issue #288 pulled the served /root/sgt/web package-lock.json back into repo web/, changed web/scripts/sync-live-copy.sh to copy the tracked lockfile and run npm ci, and restored the repo-owned latest-main proof to use npm --prefix web ci && npm --prefix web test before the dry-run sync check.
- 2026-03-30T09:28:43+02:00 — 2026-03-30 user-visible bug: sgt peek mayor and WebUI Mayor view were empty even while Mayor was healthy. Root cause: shared Mayor session runs with stdout/stderr redirected to /root/sgt/.sgt/mayor-start.log, so tmux capture-pane is blank. Live hotfix proved the right behavior is to fall back to mayor-start.log when the pane is blank/unavailable.
- 2026-03-30T09:33:44+02:00 — 2026-03-30 issue #290: repo sgt peek now falls back to the scoped mayor-start.log for mayor and mayor/<rig> when tmux pane capture is blank, and web/lib/cockpit.js now centralizes the same mayor pane-vs-log fallback for WebUI streams via captureStreamTarget().
- 2026-03-30T12:12:45+02:00 — 2026-03-30 operator request: implement real runtime Mayor auto-refresh when effective context/token budget exceeds 150k. Current reality after issue #235 is that there is no actual runtime auto-compaction/token-threshold feature in origin/master; only manual 'sgt mayor refresh' exists. Desired behavior: measure briefing/context size, auto-trigger refresh via handoff path at 150k, preserve protected facts, avoid thrash loops, and expose operator-visible telemetry.
- 2026-03-30T12:24:42+02:00 — 2026-03-30: Mayor now measures the actual AI prompt file with a stable ceil(chars/4) token estimate, records prompt-budget state under mayor-prompt-budget.state, auto-refreshes through the existing handoff/archive flow when SGT_MAYOR_AUTO_REFRESH_TOKENS (default 150000) is exceeded, and rate-limits repeats with SGT_MAYOR_AUTO_REFRESH_COOLDOWN_SECS while exposing budget/auto-refresh telemetry in status and status --json.
- 2026-03-30T12:31:05+02:00 — 2026-03-30: Mayor now measures the live AI-cycle prompt file (mayor-workspace/CLAUDE.md) before invoke, records effective-context telemetry in mayor-effective-context.state and sgt status/--json, auto-refreshes via the handoff/archive path when the measured prompt reaches SGT_MAYOR_AUTO_REFRESH_THRESHOLD_TOKENS (default 150000), and suppresses repeat auto-refresh with SGT_MAYOR_AUTO_REFRESH_COOLDOWN_SECS (default 900). Latest-main proof path: ./test_mayor_refresh_latest_main_proof.sh.
- 2026-03-30T12:40:14+02:00 — 2026-03-30 issue #293 follow-up: added repo-owned latest-main proof entrypoint ./test_mayor_refresh_latest_main_proof.sh plus test_mayor_runtime_auto_refresh.sh, which drives the real Mayor loop into the over-budget AI-cycle path and verifies prompt measurement, handoff auto-refresh trigger, operator telemetry, and no backend invoke before refresh.

## 2026-03-31
- 2026-03-31T07:28:54+02:00 — 2026-03-31 bug report: 'sgt context search pmkb "test"' fails with HTTP 400 because _context_index_build sends all SGT_CONTEXT entries in one OpenAI embeddings request. PMKB context has 2473 entries and OpenAI rejects arrays longer than 2048 with 'Invalid input: array length must be 2048 or less.' Direct single-query embeddings work; chunking the same corpus into 2048 + 425 succeeds. Also, 'sgt context add' currently swallows background reindex failures via '>/dev/null 2>&1 || true', which hides stale-index rebuild breakage.
- 2026-03-31T07:32:17+02:00 — 2026-03-31: context indexing now batches embeddings requests in 512-entry chunks to stay below OpenAI's 2048-input cap, preserves entry order in ~/.sgt/context/<rig>/index.json, and warns when opportunistic reindex during 'sgt context add' fails instead of silently swallowing it.
- 2026-03-31T07:50:56+02:00 — Plan request sgt-1774936256-9272fefe submitted by OpenClaw agent gastown. Full spec appended below.

### Plan Request sgt-1774936256-9272fefe

- Requested at: 2026-03-31T07:50:56+02:00
- Requesting OpenClaw agent: gastown

```markdown
# SGT plan request: per-rig Mayors + President supervisor

## Request

Replace the current shared-Mayor control plane with **one Mayor per rig**, and add a new higher-level agent called the **President** that supervises the Mayors across rigs, tracks their progress, and unblocks or reconciles them when needed.

Target repo/rig: `sgt`
Requester: operator via Gastown
Date: 2026-03-31

## Why this change

The current shared-Mayor setup mixes cross-rig coordination into one control-plane brain. That creates pressure around context size, cross-rig reasoning bleed, stale board reconciliation, and recoverability when one rig gets weird. We want to move to a more scalable hierarchy:

- **Mayor = rig-local executive**
  - owns one rig only
  - reasons only about that rig's issues/PRs/plan/blockers/state
  - has isolated transient workspace, logs, heartbeats, locks, and refresh lifecycle
- **President = top-level supervisor**
  - watches all Mayors
  - tracks health and progress across rigs
  - notices stalls / drifts / contradictory states
  - nudges, wakes, refreshes, or otherwise unblocks a Mayor when justified
  - handles cross-rig coordination and control-plane oversight, but does **not** replace rig-local Mayor ownership

## Desired end state

### 1) Per-rig Mayor architecture

Each active rig should have its own Mayor runtime/process/session/state instead of sharing one global Mayor.

At minimum, each rig-local Mayor should have isolated equivalents of today's Mayor runtime assets, such as:

- briefing/workspace/context
- heartbeat state
- lock/lease
- cycle state / observability state
- logs / peek target
- refresh/handoff flow
- notify path

Per-rig Mayors should preserve existing rig-local responsibilities:

- evaluate repo-local truth
- own plan decomposition/execution flow for that rig
- dispatch/re-dispatch work for that rig
- reconcile blockers / compact stale work for that rig
- respect rig hibernation state

### 2) New President layer

Add a control-plane layer above the Mayors named **President**.

The President should:

- monitor all rig-local Mayors and their health/progress
- detect stuck or contradictory situations
- detect rigs with actionable work but no healthy forward motion
- wake or refresh a specific Mayor when needed
- issue bounded supervisory steering/unblock actions
- coordinate global/system-level decisions that don't belong inside a single rig Mayor
- maintain separation: the President should supervise the Mayors, not directly take over routine rig-local repo work

Examples of President-worthy behavior:

- a rig is actionable but its Mayor is stale, wedged, or repeatedly failing to make progress
- duplicate/stale work keeps resurfacing and needs higher-level compaction/recovery supervision
- one Mayor's local reasoning conflicts with broader control-plane truth
- cross-rig resource / policy / rollout decisions need orchestration

### 3) Backward-compatible operator ergonomics

The migration should not make SGT harder to operate.

Please design/update CLI and operational flows so they remain coherent. Likely examples:

- `sgt up` / `sgt down` should manage President + all needed Mayors cleanly
- `sgt status` should clearly expose President state plus per-rig Mayor state
- `sgt peek` / logs / WebUI should make it obvious whether the user is looking at President or a specific rig Mayor
- refresh/restart commands should work at the correct scope (single-rig Mayor vs President vs all)
- existing useful Mayor ergonomics such as refresh/handoff should survive in the new model

If command names need to evolve, preserve sensible compatibility or offer a clear migration path.

### 4) Observability / debugging

This architecture change should improve, not reduce, debuggability.

Need clear visibility for:

- President health
- per-rig Mayor health
- last cycle / last wake / last meaningful action per Mayor
- why President intervened or did not intervene
- whether a rig is blocked because of repo truth, hibernation, missing work, or a control-plane problem

### 5) Safe migration

The migration path matters.

Need a plan that safely moves from today's shared-Mayor setup to per-rig Mayors + President without trashing durable board state.

Important constraints:

- do **not** bypass repo-local plan ownership rules
- preserve durable board/issue/PR/blocker truth
- avoid creating fake duplicate work during migration
- existing rigs (`sgt`, `pmkb`, `sstb`, etc.) should remain recoverable
- operator should be able to roll forward incrementally and verify behavior

## Acceptance expectations

Mayor should decompose this into a real implementation plan, not a single vague task.

A good finished result should include at least:

1. architecture/design lane(s)
2. runtime/process model changes
3. CLI/control-plane updates
4. observability/WebUI/peek/log support updates
5. migration/safety path
6. docs/proof/tests
7. latest-main proof that demonstrates the hierarchy actually works

## Concrete acceptance criteria

The delivered system should make the following true:

- SGT no longer depends on one shared cross-rig Mayor as the sole executive brain
- each active rig has a dedicated Mayor with isolated transient state
- a President process/layer exists and supervises Mayors across rigs
- President can detect and act on justified unblock/recovery cases for a single rig Mayor
- `sgt status` and operator-facing observability clearly show President + rig-local Mayor state
- operator can inspect/peek President separately from any rig Mayor
- refresh/restart semantics are well-defined at the correct scope
- docs explain the hierarchy and operator workflow
- proof demonstrates at least two rigs under separate Mayors, with the President supervising them correctly

## Notes / guardrails

- Keep Witness / Refinery / existing rig-local repo workflows intact unless a change is truly required.
- Prefer explicit process/state boundaries over hidden multiplexing.
- Preserve the spirit of earlier Mayor lifecycle work (refresh/handoff, hibernation awareness, observability) but adapt it to the new hierarchy.
- If this should land in phases, make the phases explicit and safe.

## Requested outcome from Mayor

Please produce and execute a repo-local SGT plan for this feature:

**Per-rig Mayors with a President supervisor above them.**

If needed, start with design/migration scaffolding first, but the plan should clearly converge on a working hierarchical control plane rather than stopping at docs-only architecture notes.
```
- 2026-03-31T07:59:44+02:00 — 2026-03-31 issue #300 defines the President -> mayor/<rig> architecture contract in docs/president-per-rig-mayor-contract.md, clarifies README that SGT_MAYOR_ARCHITECTURE=per-rig is transition scaffolding rather than final state, and adds test_president_per_rig_mayor_contract_latest_main_proof.sh to pin the contract plus existing per-rig Mayor runtime slice.
- 2026-03-31T08:07:45+02:00 — 2026-03-31 issue #302: Mayor runtime scope now treats refresh/handoff as a full scoped transient bundle (including heartbeat/observability/auto-refresh/watchdog/receipt directories under ~/.sgt[/mayors/<rig>]/), and mayor target -> tmux session/log resolution is centralized around shared vs mayor/<rig> naming.
- 2026-03-31T08:10:42+02:00 — Acceptance blocker sgt-acceptance-1774937442-8524a714 reported by witness: Polecat blocked by backend usage limit for issue #304

### Acceptance Blocker sgt-acceptance-1774937442-8524a714

- Reported at: 2026-03-31T08:10:42+02:00
- Reported by: witness
- Title: Polecat blocked by backend usage limit for issue #304

```markdown
Polecat blocked by backend usage limit for issue #304

A polecat hit a known backend/quota limit before opening a PR.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #304
- Issue URL: https://github.com/codejeet/sgt/issues/304
- Issue title: Teach deacon and control commands to manage Mayor scope correctly
- Polecat: sgt-0ed53c0b
- Backend: codex
- Reason code: codex_usage_limit
- Matched first output: You've hit your usage limit

Required follow-up:
- leave this issue blocked until backend quota resets or an operator explicitly changes backend policy
- do not auto-resling while the issue is marked backend-limited

```
- 2026-03-31T08:10:48+02:00 — Acceptance blocker sgt-acceptance-1774937448-02090b79 reported by witness: Polecat blocked by backend usage limit for issue #305

### Acceptance Blocker sgt-acceptance-1774937448-02090b79

- Reported at: 2026-03-31T08:10:48+02:00
- Reported by: witness
- Title: Polecat blocked by backend usage limit for issue #305

```markdown
Polecat blocked by backend usage limit for issue #305

A polecat hit a known backend/quota limit before opening a PR.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #305
- Issue URL: https://github.com/codejeet/sgt/issues/305
- Issue title: Add the President runtime and supervisory intervention model
- Polecat: sgt-4d1a7d2e
- Backend: codex
- Reason code: codex_usage_limit
- Matched first output: You've hit your usage limit

Required follow-up:
- leave this issue blocked until backend quota resets or an operator explicitly changes backend policy
- do not auto-resling while the issue is marked backend-limited

```
- 2026-03-31T08:27:53+02:00 — Acceptance blocker sgt-acceptance-1774937442-8524a714 resolved. Note: Operator confirmed recovery after transient codex usage issue; direct codex probe now returns OK. Clear stale backend-limit block and allow recovery of issue #304.
- 2026-03-31T08:27:55+02:00 — Acceptance blocker sgt-acceptance-1774937448-02090b79 resolved. Note: Operator confirmed recovery after transient codex usage issue; direct codex probe now returns OK. Clear stale backend-limit block and allow recovery of issue #305.
- 2026-03-31T08:37:51+02:00 — 2026-03-31 issue #304: deacon, daemon, and scoped mayor tmux spawns must propagate SGT_MAYOR_ARCHITECTURE so per-rig mode survives background restarts and deacon supervises mayor/<rig> sessions instead of silently falling back to shared-Mayor assumptions.
- 2026-03-31T08:42:09+02:00 — 2026-03-31 issue #305: per-rig mode now runs a first-class President supervisor in ~/.sgt/president with sgt-president; deacon supervises President, President performs bounded per-rig mayor start/wake/refresh interventions for missing, stale, or no-forward-motion rigs, and the latest-main proof path is ./test_president_runtime_latest_main_proof.sh.
- 2026-03-31T09:11:17+02:00 — 2026-03-31 issue #308: sgt status --json now emits machine-readable control-plane role/scope metadata for president/shared-mayor/rig-local mayors/witness/refinery, and the web cockpit topology sidebar can focus or peek president plus mayor/<rig> nodes directly via topology metadata instead of relying on name heuristics alone.
- 2026-03-31T09:12:48+02:00 — 2026-03-31 issue #309: President-originated wake reasons now preserve rig targeting via 'president:<rig>:...' parsing, scoped mayor notify inherits SGT_MAYOR_SCOPE_RIG for rig-specific notify-agent/receipt state, and 'sgt president refresh' now archives ~/.sgt/president transient state into a handoff path before restart.
- 2026-03-31T09:19:26+02:00 — 2026-03-31 issue #309: per-rig wake routing now treats President-originated reasons like president:<rig>:... as rig-targeted, scoped mayor notify uses SGT_MAYOR_SCOPE_RIG for rig-specific notify_agent overrides plus rig-local notify receipt state, and sgt president refresh archives ~/.sgt/president transient state into a handoff before restart.
- 2026-03-31T09:21:20+02:00 — 2026-03-31 issue #312: per-rig hierarchy cutover now retires any leftover shared sgt-mayor session and archives only shared Mayor transient assets under ~/.sgt/president/cutovers/<token>/; durable board, blocker, plan-state, polecat, and scoped mayor state stay in place so stale shared snapshots/watchdogs cannot duplicate work after cutover.
- 2026-03-31T10:07:10+02:00 — 2026-03-31 issue #312: latest-main President runtime proof now includes test_hierarchy_cutover_guardrails.sh so hierarchy acceptance covers retiring leftover shared-Mayor transient state without disturbing durable blocker, plan-state, polecat, or scoped mayor truth.
- 2026-03-31T10:22:46+02:00 — 2026-03-31 issue #316: test_president_runtime_latest_main_proof.sh now includes a lightweight Web UI hierarchy proof via test_web_cockpit_control_plane_hierarchy.sh, so the latest-main hierarchy bundle covers president vs mayor/<rig> distinction in status, peek, and cockpit surfaces.
- 2026-03-31T11:11:07+02:00 — Plan request sgt-1774948267-47b89672 submitted by OpenClaw agent gastown. Full spec appended below.

### Plan Request sgt-1774948267-47b89672

- Requested at: 2026-03-31T11:11:07+02:00
- Requesting OpenClaw agent: gastown

```markdown
# SGT follow-on plan request: President notifications + WebUI operator usability pass

## Request

Create a follow-on SGT implementation plan on rig `sgt` for the newly deployed **President + per-rig Mayor** system.

This request has five linked goals:

1. **President notifications for important things to check / operator escalations**
2. **President log visibility in the Web UI**
3. **Pane/layout improvements in the tmux cockpit UI**
4. **Notification panel cleanup so it only shows recent/actionable items**
5. **Text input at the bottom of each pane for fast nudging**

Requester: operator via Gastown
Date: 2026-03-31
Rig: `sgt`

## Why this exists

The President/per-rig Mayor runtime is now live, but the operator surfaces still lag behind the new topology and the real operator workflow.

We need the UI and notify layer to match the architecture that now exists in production:
- President should be able to raise meaningful operator attention for drift / stuck-purpose situations / escalations
- The Web UI should expose President activity directly instead of burying it in log archaeology
- The cockpit layout should be easier to read, steer, and operate during live work
- The notification area should show **what matters now**, not stale long-title clutter

## Work requested

### 1) President notifications for important, actionable events

Wire President into operator-facing notifications for important things worth checking, such as:

- a rig has drifted from its intended purpose
- a rig is technically active but not actually making forward progress on its real goal
- a rig's local behavior contradicts the larger program intent / acceptance path
- President had to intervene because a rig-local Mayor was stale / wedged / misleadingly idle
- President wants operator attention / escalation
- President questions that need human input

Guidance:
- Prefer **important, actionable** notifications rather than noisy chatter
- Focus on "check this" / "this rig is drifting" / "this needs operator judgment" events
- Preserve existing preference that voice/attention emphasis should lean toward **resolved blockers / major milestones / meaningful escalations**, not every tiny event
- If President and Mayor notifications overlap, dedupe or present them coherently rather than spamming both layers independently

### 2) President log / status visibility in the Web UI

Expose President in the Web UI as a first-class operator surface, including things like:

- President cycle status
- recent President interventions
- President reasoning/action log or event feed
- which rig was touched, why, and what President did
- whether an intervention was wake / refresh / restart / no-op / suppressed-by-cooldown

The operator should not need to grep server logs to understand what President is doing.

### 3) Pane/layout improvements for the tmux cockpit

Requested UI behavior:

- tmux windows should display as **vertical rectangles** in an automatic grid layout
- focused panes should **move the real pane into the focused spot**, not duplicate the pane in a second location/view
- pane view should use a **cool blue, slightly transparent-looking font on a black background**

Design constraints / prior operator guidance worth preserving:
- livestream first / operator-centric cockpit feel
- less gradient-heavy / less AI-looking CSS
- mostly square corners or very slight rounding only
- darker high-contrast theme that still keeps the blue

### 4) Notification panel cleanup

Current problem:
- notifications overflow with stale old data
- long titles make the section hard to use

Requested behavior:
- show only recent and/or actionable items by default
- prioritize items like:
  - President questions
  - current escalations
  - unresolved meaningful blockers
  - things the operator should actually act on now
- reduce useless long-title clutter
- prefer summaries that are compact, legible, and operationally useful

### 5) Text input at the bottom of each pane for easy nudging

Add a text input / quick command affordance at the bottom of each rectangle pane so the operator can easily nudge the corresponding session/agent.

Goal:
- make steering from the cockpit much faster
- reduce friction for nudging a specific pane/session
- keep the interaction scoped to the pane the operator is looking at

This should work cleanly for the relevant pane/session types exposed by the cockpit.

## Acceptance expectations

Please decompose this into a real repo-local plan rather than a single vague issue.

A good plan should likely cover at least:

1. President notify architecture / event model / dedupe rules
2. President activity/log exposure in status + Web UI
3. pane layout / focus behavior changes
4. notification panel recency/actionability filtering
5. per-pane input/nudge interaction
6. docs / proof / latest-main verification

## Concrete acceptance criteria

A good finished result should make the following true:

- President can generate meaningful operator-facing notifications for important drift/escalation situations
- President activity is visible in the Web UI without log-grep archaeology
- cockpit panes render as auto-laid-out vertical rectangles
- focus behavior moves the pane to the focus slot instead of duplicating views
- pane styling reflects the requested cool-blue-on-black operator look
- notification panel defaults to recent/actionable information instead of stale overflow
- President questions / actionable escalations are clearly surfaced
- each pane has an easy text-input affordance for nudging that pane's session/agent
- docs/proof demonstrate the new behavior on latest main

## Notes

- This is a follow-on usability / operator-surface layer on top of the newly deployed President system.
- Keep the implementation grounded in real operator value, not decorative UI churn.
- If this needs phasing, make the phases explicit and safe.
```
- 2026-03-31T13:01:46+02:00 — 2026-03-31 incident: PMKB final acceptance closeout exposed a coupled SGT bug cluster in live President/per-rig mode. PR #1019 hit HTTP 5xx then GraphQL merge-in-progress; refinery marked it non-transient, then witness/refinery looped on orphan-PR + duplicate-merge-attempt-key for over an hour even though the PR stayed CLEAN/mergeable. After manual merge, GitHub truth became correct but PMKB repo-local acceptance stayed stale: PKL2-11 completed, yet SGT_PLAN.json and .sgt/plan-state/pmkb.json still showed acceptance planned / tasks-exhausted-awaiting-acceptance. Recovery attempts via sgt mayor refresh pmkb and explicit wake did not reconcile; refresh also appeared to act like shared/global refresh in per-rig mode and President kept restarting mayors because pmkb/sgt mayors exited cleanly immediately. See workspace incident note `notes/sgt-incident-pmkb-acceptance-reconciliation-2026-03-31.md` for full timeline and fix guidance.
- 2026-03-31T13:09:15+02:00 — Plan tick and worker completion-context now prefer the default-branch SGT_PLAN.json snapshot when a rig checkout is on a dirty or non-default branch, so merged acceptance updates reconcile plan-state from authoritative repo truth without clobbering the local worktree.
- 2026-03-31T22:05:49+02:00 — Plan request sgt-1774987549-42306fbf submitted by OpenClaw agent gastown. Full spec appended below.

### Plan Request sgt-1774987549-42306fbf

- Requested at: 2026-03-31T22:05:49+02:00
- Requesting OpenClaw agent: gastown

```markdown
# SGT follow-on plan request: President notifications + WebUI operator usability pass

## Request

Create a follow-on SGT implementation plan on rig `sgt` for the newly deployed **President + per-rig Mayor** system.

This request has five linked goals:

1. **President notifications for important things to check / operator escalations**
2. **President log visibility in the Web UI**
3. **Pane/layout improvements in the tmux cockpit UI**
4. **Notification panel cleanup so it only shows recent/actionable items**
5. **Text input at the bottom of each pane for fast nudging**

Requester: operator via Gastown
Date: 2026-03-31
Rig: `sgt`

## Why this exists

The President/per-rig Mayor runtime is now live, but the operator surfaces still lag behind the new topology and the real operator workflow.

We need the UI and notify layer to match the architecture that now exists in production:
- President should be able to raise meaningful operator attention for drift / stuck-purpose situations / escalations
- The Web UI should expose President activity directly instead of burying it in log archaeology
- The cockpit layout should be easier to read, steer, and operate during live work
- The notification area should show **what matters now**, not stale long-title clutter

## Work requested

### 1) President notifications for important, actionable events

Wire President into operator-facing notifications for important things worth checking, such as:

- a rig has drifted from its intended purpose
- a rig is technically active but not actually making forward progress on its real goal
- a rig's local behavior contradicts the larger program intent / acceptance path
- President had to intervene because a rig-local Mayor was stale / wedged / misleadingly idle
- President wants operator attention / escalation
- President questions that need human input

Guidance:
- Prefer **important, actionable** notifications rather than noisy chatter
- Focus on "check this" / "this rig is drifting" / "this needs operator judgment" events
- Preserve existing preference that voice/attention emphasis should lean toward **resolved blockers / major milestones / meaningful escalations**, not every tiny event
- If President and Mayor notifications overlap, dedupe or present them coherently rather than spamming both layers independently

### 2) President log / status visibility in the Web UI

Expose President in the Web UI as a first-class operator surface, including things like:

- President cycle status
- recent President interventions
- President reasoning/action log or event feed
- which rig was touched, why, and what President did
- whether an intervention was wake / refresh / restart / no-op / suppressed-by-cooldown

The operator should not need to grep server logs to understand what President is doing.

### 3) Pane/layout improvements for the tmux cockpit

Requested UI behavior:

- tmux windows should display as **vertical rectangles** in an automatic grid layout
- focused panes should **move the real pane into the focused spot**, not duplicate the pane in a second location/view
- pane view should use a **cool blue, slightly transparent-looking font on a black background**

Design constraints / prior operator guidance worth preserving:
- livestream first / operator-centric cockpit feel
- less gradient-heavy / less AI-looking CSS
- mostly square corners or very slight rounding only
- darker high-contrast theme that still keeps the blue

### 4) Notification panel cleanup

Current problem:
- notifications overflow with stale old data
- long titles make the section hard to use

Requested behavior:
- show only recent and/or actionable items by default
- prioritize items like:
  - President questions
  - current escalations
  - unresolved meaningful blockers
  - things the operator should actually act on now
- reduce useless long-title clutter
- prefer summaries that are compact, legible, and operationally useful

### 5) Text input at the bottom of each pane for easy nudging

Add a text input / quick command affordance at the bottom of each rectangle pane so the operator can easily nudge the corresponding session/agent.

Goal:
- make steering from the cockpit much faster
- reduce friction for nudging a specific pane/session
- keep the interaction scoped to the pane the operator is looking at

This should work cleanly for the relevant pane/session types exposed by the cockpit.

## Acceptance expectations

Please decompose this into a real repo-local plan rather than a single vague issue.

A good plan should likely cover at least:

1. President notify architecture / event model / dedupe rules
2. President activity/log exposure in status + Web UI
3. pane layout / focus behavior changes
4. notification panel recency/actionability filtering
5. per-pane input/nudge interaction
6. docs / proof / latest-main verification

## Concrete acceptance criteria

A good finished result should make the following true:

- President can generate meaningful operator-facing notifications for important drift/escalation situations
- President activity is visible in the Web UI without log-grep archaeology
- cockpit panes render as auto-laid-out vertical rectangles
- focus behavior moves the pane to the focus slot instead of duplicating views
- pane styling reflects the requested cool-blue-on-black operator look
- notification panel defaults to recent/actionable information instead of stale overflow
- President questions / actionable escalations are clearly surfaced
- each pane has an easy text-input affordance for nudging that pane's session/agent
- docs/proof demonstrate the new behavior on latest main

## Notes

- This is a follow-on usability / operator-surface layer on top of the newly deployed President system.
- Keep the implementation grounded in real operator value, not decorative UI churn.
- If this needs phasing, make the phases explicit and safe.
```
- 2026-03-31T22:12:29+02:00 — 2026-03-31 issue #320: President runtime now emits structured PRESIDENT_OPERATOR_EVENT records with stable kind/severity/notify fields plus President-local dedupe_key and cross-layer overlap_key. Current runtime mapping: mayor-session-missing and mayor-heartbeat-* => intervention notify=1; actionable-no-forward-motion => stalled-purpose notify=1; actionable-rig-recheck => intervention notify=0 with suppressed-by-cooldown logging instead of replay noise. Repo-owned contract doc: docs/president-operator-notify-contract.md; proof coverage in test_president_operator_notify_contract.sh and test_president_runtime_latest_main_proof.sh.
- 2026-03-31T22:26:37+02:00 — 2026-03-31 issue #323: web cockpit alert feed now parses recent PRESIDENT_OPERATOR_EVENT and PRESIDENT_INTERVENTION log lines, dedupes by President overlap/dedupe keys, merges them with blocker alerts, and shows President-tagged alert cards with detail snippets so important President incidents surface in the operator rail without double paging quiet rechecks or suppressed cooldown replays.
- 2026-03-31T22:27:31+02:00 — 2026-03-31 issue #322: President now persists bounded structured operator-event history in ~/.sgt/president/president-operator-events.tsv; sgt status --json exposes it as president_events, human status shows recent President events, and the web cockpit Alert Center renders President activity with rig, reason, action, outcome, and priority alert surfacing.
- 2026-03-31T22:32:49+02:00 — 2026-03-31 issue #322 follow-up: current master was missing the closed PR #325 implementation even though later context referenced it. Replacement fix persists bounded President operator-event history in ~/.sgt/president/president-operator-events.tsv, exposes it via status --json as president_events plus human status lines, and the web cockpit now renders a dedicated President Activity panel from that snapshot while leaving the newer alert-feed dedupe logic intact.
- 2026-03-31T22:38:13+02:00 — 2026-03-31 issue #328: web cockpit alert rail now defaults to recent and actionable items by filtering stale resolved/info noise, deduping blocker history to the latest transition per blocker, and trimming long alert titles/details for faster operator scanning.
- 2026-03-31T22:38:20+02:00 — 2026-03-31 cockpit issue #327: the web live monitor now removes the focused worker from the wall instead of duplicating it, and the stream wall layout/theme is locked as a blue-on-black automatic grid of tall vertical panes via web/public/* plus operator-shell tests.
- 2026-03-31T22:50:31+02:00 — 2026-03-31 issue #331: the web cockpit live panes now expose bottom-anchored per-pane nudge inputs via POST /api/nudge, and sgt nudge resolves mayor/<rig>, dog/<name>, and crew/<name> to the same tmux sessions used by cockpit streams.
- 2026-03-31T22:57:56+02:00 — 2026-03-31 issue #333: docs/president-operator-surface-contract.md and ./test_president_operator_surface_latest_main_proof.sh are the repo-owned join point for the President operator-surface pass. Use that proof when verifying latest-main visibility across sgt status, sgt status --json president_events, scoped sgt peek, and the Web UI alert rail plus President Activity panel.

## 2026-04-01
- 2026-04-01T03:58:15+02:00 — 2026-04-01 operator policy for President/Mayor: PMKB should maintain multiple materially different live candidate lanes in parallel while acceptance remains pending. If PMKB trends serial or idle, President and rig-local Mayor should proactively top it back up rather than waiting for a human prompt.
- 2026-04-01T04:22:28+02:00 — 2026-04-01 hard operator policy for PMKB control plane: do not let PMKB acceptance verify on durable falsification alone; target is >= +1000 USDC widened-corpus net PnL under realistic assumptions unless a human waives it. President/Mayor should maintain at least 3 materially different live PMKB candidate lanes in parallel while acceptance remains pending, and proactively refill the rig if active candidate count drops.
- 2026-04-01T06:19:40+02:00 — Plan request sgt-1775017180-eee389c4 submitted by OpenClaw agent gastown. Full spec appended below.

### Plan Request sgt-1775017180-eee389c4

- Requested at: 2026-04-01T06:19:40+02:00
- Requesting OpenClaw agent: gastown

```markdown
# SGT feature request: Ralph mode

## Request

Add a new SGT control-plane feature called **Ralph mode**.

High-level idea:
- Ralph mode **pins a rig into active work** under ongoing **President oversight**.
- Instead of letting the rig naturally drift toward idle / acceptance-verified / parked states after each no-go or merge, Ralph mode keeps the rig continuously supplied with work until an explicit operator-defined condition is met or a human stops it.

Requester: operator via Gastown
Date: 2026-04-01
Rig for implementation: `sgt`

## Example desired usage

Something like:

```yaml
ralph_mode:
  enabled: true
  concurrency: 5
  ralph_condition: "1K PNL for 5m btc pipeline"
```

Or equivalent CLI/config/runtime representation.

The important semantics are:
- **constant pressure / keep working**
- **President-supervised**
- **target concurrency**
- **clear success/stop condition**

## Why this is needed

We keep running into the same class of operational failure:
- a rig is conceptually still open-ended
- but the control plane keeps drifting it toward idle, verified, parked, or under-filled
- even though the operator wants sustained forward pressure until a real objective is achieved

Ralph mode should solve that by making the operator intent explicit.

## Core behavior

When Ralph mode is active for a rig:

1. **President keeps the rig hot**
   - continuously supervises the rig
   - notices under-filled / idle / fake-complete / stalled states
   - proactively tops the rig back up
   - does not wait for the operator to notice serial drift every time

2. **Concurrency is a first-class target**
   - e.g. `concurrency: 5`
   - if active candidate/worker count drops below target, the control plane refills the rig
   - parallelism should apply to materially different admissible lanes, not just duplicate noise

3. **Explicit Ralph condition controls completion**
   - e.g. `ralph_condition: "1K PNL for 5m btc pipeline"`
   - until that condition is satisfied (or explicitly waived/stopped by a human), the rig should remain in active continuation mode
   - ordinary no-go / falsification evidence is informative but not terminal by itself unless that is what the Ralph condition says

4. **No fake completion while condition remains unmet**
   - if the rig produces only no-go evidence, it should continue into the next admissible lane
   - Ralph mode should prevent accidental drift into `verified` / `parked` / `tasks-exhausted-awaiting-acceptance` when the operator-defined Ralph condition still says the mission is open

5. **President-owned refill / escalation**
   - President should own the higher-level "keep this rig moving" policy
   - rig-local Mayor still owns the repo-local work decomposition and dispatch details
   - if the rig becomes under-filled or contradictory, President should recheck / refresh / steer the Mayor until the Ralph policy is satisfied

## Desired operator controls

Please design operator-facing controls for Ralph mode that are simple and explicit.

Likely needs:
- enable / disable Ralph mode per rig
- set / edit `concurrency`
- set / edit `ralph_condition`
- possibly set policy knobs like:
  - minimum materially different lanes
  - whether support-only work counts toward concurrency
  - under-fill cooldown / refill aggressiveness
  - whether falsification is terminal or not
- show current Ralph state in `sgt status` / Web UI / logs

## Suggested semantics

Ralph mode should probably include state like:

- `enabled`
- `condition_text` (human-readable)
- optional machine-readable condition fields if available later
- `target_concurrency`
- `active_lane_count`
- `underfilled`
- `last_refill_at`
- `last_president_action`
- `completion_blocked_by_condition`

## PMKB motivating use case

The immediate motivating use case is PMKB.

Example policy:
- keep PMKB running until it achieves something like:
  - `1K PNL for 5m btc pipeline`
- maintain parallel candidate exploration, e.g. `concurrency: 5`
- do not let the rig park merely because a candidate family was falsified
- keep generating/admitting the next materially different candidate set until the condition is satisfied or a human says stop

This should be expressible as a generic SGT feature, not a PMKB-only hardcode.

## Guardrails

- Do not treat duplicate/redundant work as useful concurrency.
- Do not count support-only or cleanup-only lanes as satisfying Ralph-mode parallelism unless explicitly configured.
- Do not let stale verified acceptance metadata override an active Ralph condition.
- Preserve human stop/waive authority.
- Keep observability clear: operator should be able to tell why a rig is still active, what the current Ralph condition is, and why President is refilling it.

## Acceptance expectations

A good implementation should likely include:

1. Ralph mode architecture / config model
2. President integration
3. Mayor interplay / refill logic
4. acceptance/completion override semantics tied to Ralph condition
5. concurrency accounting rules
6. `sgt status` / Web UI / logs visibility
7. proof / latest-main validation with at least one rig example

## Concrete acceptance criteria

The delivered system should make the following true:

- a rig can be explicitly pinned into ongoing work via Ralph mode
- President keeps the rig topped up toward a configured concurrency target
- the rig does not drift into false completion while the Ralph condition remains unmet
- no-go evidence triggers successor continuation rather than accidental stand-down, unless the Ralph condition explicitly allows closure
- operator can see Ralph mode state and condition in status/logs/UI
- operator can configure something equivalent to:
  - `concurrency: 5`
  - `ralph_condition: "1K PNL for 5m btc pipeline"`
- latest-main proof demonstrates the behavior end-to-end

## Requested outcome from Mayor

Please create and execute a real repo-local SGT plan for:

**Ralph mode: President-pinned rig continuation with configurable concurrency and explicit completion condition.**
```
- 2026-04-01T06:55:48+02:00 — 2026-04-01 operator hotfix brief: preserve PMKB semantics that falsification/no-go is informative not terminal; acceptance stays open until widened-corpus realistic net PnL >= +1000 USDC; keep >=3 materially different live candidate lanes; President/Mayor must proactively refill underfilled rigs. Outstanding SGT structural work beyond the active Ralph-mode plan: (1) create-plan/decomposition must be deterministic across mayor workspace vs canonical repo path and must not fall into wake loops or plan-sync-failed divergence, (2) GraphQL live-state revalidation failures must not block sling/redispatch, merge-in-progress must be fully idempotent/in-flight, and scary merge-failed alerts should be suppressed if later success self-heals, (3) continuation dedupe must not recreate already-completed lanes and should prefer explicit successor mapping over fuzzy recreation, (4) control plane must honor repo-local reopened-plan truth and not drift into fake verified/tasks-exhausted closeout when continuation intent remains open, (5) refill guarantee must key off live polecats not just open issues and must emit an explicit reason when active_count < target_concurrency, (6) web UI deploy path needs a first-class deploy/restart flow or single source of truth, and (7) acceptance-blocker signaling needs severity classes/dedupe so platform incidents are distinguishable from normal candidate no-go churn. Fresh live repro on 2026-04-01 ~06:50 CET: /root/sgt/rigs/pmkb/SGT_PLAN.json still says keep iterating toward >= +1000 USDC with multiple materially different live lanes, but sgt plan tick pmkb returned tasks-exhausted-awaiting-acceptance and PMKB stayed idle with zero live polecats even after wake-mayor + president refresh + mayor refresh/start.
- 2026-04-01T06:57:46+02:00 — Ralph mode now lives in ~/.sgt/rig-config/<rig>.json under ralph_mode; status/plan-state/cockpit expose active/admissible/backlog lane counts with default policy distinct open sgt-authorized issues excluding duplicate plus support-only labels unless count_support_lanes=true, and plan completion is forced back to pending while an enabled Ralph condition remains unmet.
- 2026-04-01T07:01:46+02:00 — Acceptance blockers now persist SEVERITY_CLASS plus DEDUPE_KEY. Web cockpit groups unresolved blocker alerts by that key and emits one still-red summary for repeated same-key churn, while control-plane blockers stay visually/severity-distinct from candidate no-go acceptance churn.
- 2026-04-01T07:03:15+02:00 — 2026-04-01 issue #339 added a first-class live Web UI operator path: use 'sgt web deploy' from the repo checkout to sync repo web/ into /root/sgt/web, restart the live sgt-web tmux session, and verify repo/live tree parity plus HTTP health; use 'sgt web status' or 'sgt web verify' to avoid assuming a merged checkout updated the served UI.
- 2026-04-01T07:04:39+02:00 — 2026-04-01 issue #337: plan control-plane truth now stays on the canonical rig repo path, not mayor-workspace or default-branch plan cache. plan tick/worker context read repo-local SGT_PLAN.json, mayor briefings call out canonical repo_path/plan_path, and mayor request complete can recover a plan accidentally written under mayor-workspace by copying it into the rig repo before syncing labels/state.
- 2026-04-01T07:06:36+02:00 — Plan tick now records a durable __continuation__ plan blocker when acceptance is still pending but live lanes fall below policy.max_in_flight; Mayor stranded-rig recovery refills replacement work up to target concurrency, and President treats pending-plan underfill as a stalled-purpose intervention reason instead of idling the rig.
- 2026-04-01T07:07:27+02:00 — 2026-04-01 issue #338: mayor sling revalidation now fails open only for flaky live GraphQL count reads, redispatch tolerates UNKNOWN/failed source-PR mergeability revalidation, refinery treats merge-in-progress/already-being-merged as in-flight without scary failure noise, and plan tick now binds/reopens lanes from explicit open plan-<task> issue labels before recreating work.
- 2026-04-01T07:14:22+02:00 — 2026-04-01: plan tick now records a durable __continuation__ plan blocker when acceptance is still pending but tasks are exhausted and live polecats are below policy.max_in_flight; mayor activity snapshot and President treat that pending-plan underfill as active stalled-purpose state so rigs do not idle-green while continuation intent remains open.
- 2026-04-01T07:25:23+02:00 — 2026-04-01 issue #349: President Ralph supervision now distinguishes bounded refill from contradiction. If Ralph is underfilled but admissible backlog exists, President uses a wake (reason=ralph-underfilled) to refill. If Ralph is still unmet but the rig looks fake-complete or has no refillable backlog toward target concurrency, President upgrades to refresh with reason=ralph-contradiction so operators can see that the rig needs stronger intervention instead of silently drifting.
- 2026-04-01T07:26:01+02:00 — 2026-04-01 issue #350: plan tick now treats an unmet Ralph target_concurrency as continuation underfill when recording the durable __continuation__ blocker, and Mayor stranded-rig recovery refills underfilled Ralph/pending-plan rigs up to the live polecat gap instead of only recovering zero-worker rigs one lane at a time.
- 2026-04-01T07:26:09+02:00 — 2026-04-01 issue #348: plan-state reconciliation now treats explicit repo-local task.status values like planned/pending as authoritative reopen signals, clearing stale completed issue linkage so continuation lanes can refill; mayor refresh also infers live President/per-rig topology from running president or scoped mayor sessions so 'sgt mayor refresh <rig>' stays per-rig even when the caller shell lacks SGT_MAYOR_ARCHITECTURE=per-rig.
- 2026-04-01T07:38:10+02:00 — 2026-04-01 issue #354: mayor loop wake-summary notifications now use the same fail-open helper as 'sgt mayor notify', so OpenClaw transport/current-session channel failures still persist MAYOR_NOTIFY_FAIL_OPEN warning state but no longer exit per-rig mayors under set -e or block stranded-rig refill progress.
- 2026-04-01T07:45:57+02:00 — 2026-04-01: President rig-local supervision must skip hibernated rigs entirely; otherwise actionable-no-forward-motion can trigger manual-refresh|rig=<rig> and restart a per-rig mayor despite manual-stop/hibernation. Regression coverage lives in test_president_runtime_supervision.sh.
- 2026-04-01T07:47:03+02:00 — Acceptance blocker sgt-acceptance-1775022423-817268fb reported by witness: Replacement work required after stalled polecat for issue #357

### Acceptance Blocker sgt-acceptance-1775022423-817268fb

- Reported at: 2026-04-01T07:47:03+02:00
- Reported by: witness
- Title: Replacement work required after stalled polecat for issue #357

```markdown
Replacement work required after stalled polecat for issue #357

Stalled polecat recovery did not produce replacement work.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #357
- Issue URL: https://github.com/codejeet/sgt/issues/357
- Issue title: unknown
- Polecat: sgt-bb313303
- Failure reason: witness-stalled-issue-title-unavailable

Required follow-up:
- create replacement work (new PR or re-dispatched polecat) before closing the incident
- re-investigate why the worker exited without producing a PR

```
- 2026-04-01T07:50:48+02:00 — 2026-04-01 issue #356: plan tick now records duplicate-closeout lineage per task in plan-state, fences immediate redispatch of the same task signature after a duplicate-closing PR, clears the stale closed issue binding when the task materially changes, and only allows refill to resume once an explicit open successor exists or the task payload changes.
- 2026-04-01T07:51:44+02:00 — Acceptance blocker sgt-acceptance-1775022704-d829bc00 reported by witness: Replacement work required after stalled polecat for issue #356

### Acceptance Blocker sgt-acceptance-1775022704-d829bc00

- Reported at: 2026-04-01T07:51:44+02:00
- Reported by: witness
- Title: Replacement work required after stalled polecat for issue #356

```markdown
Replacement work required after stalled polecat for issue #356

Stalled polecat recovery did not produce replacement work.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #356
- Issue URL: https://github.com/codejeet/sgt/issues/356
- Issue title: unknown
- Polecat: sgt-28f69197
- Failure reason: witness-stalled-issue-title-unavailable

Required follow-up:
- create replacement work (new PR or re-dispatched polecat) before closing the incident
- re-investigate why the worker exited without producing a PR

```
- 2026-04-01T08:25:16+02:00 — 2026-04-01 issue #361: added test_ralph_mode_latest_main_proof.sh as the repo-owned latest-main proof path for Ralph mode; it bundles config/state, President intervention, stranded-rig refill, and cockpit visibility coverage, and README now points operators at that single entrypoint.
- 2026-04-01T08:54:09+02:00 — 2026-04-01 issue #364 duplicate redispatch fallout: plan tick no longer treats default task status pending/planned as an authoritative reopen of completed work. Explicit repo-local reopen now requires status=reopened/requeue or reopen=true, while unchanged tasks retain the latest merged plan-task issue lineage so duplicate open plan-<task> issues do not reset completed tasks back to pending/dispatched.
- 2026-04-01T09:07:10+02:00 — 2026-04-01 issue #366: when Ralph is enabled and the condition remains unmet, plan-state completion.acceptance now mirrors the effective pending status instead of leaking stale verified/waived terminal metadata; the original declared terminal status/timestamp is preserved under completion.acceptance.declared_* for operator forensics, and regression coverage lives in test_ralph_mode_config_and_state.sh.
- 2026-04-01T09:08:14+02:00 — Acceptance blocker sgt-acceptance-1775027294-89db909c reported by witness: Replacement work required after stalled polecat for issue #366

### Acceptance Blocker sgt-acceptance-1775027294-89db909c

- Reported at: 2026-04-01T09:08:14+02:00
- Reported by: witness
- Title: Replacement work required after stalled polecat for issue #366

```markdown
Replacement work required after stalled polecat for issue #366

Stalled polecat recovery did not produce replacement work.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #366
- Issue URL: https://github.com/codejeet/sgt/issues/366
- Issue title: unknown
- Polecat: sgt-89881ba7
- Failure reason: witness-stalled-issue-title-unavailable

Required follow-up:
- create replacement work (new PR or re-dispatched polecat) before closing the incident
- re-investigate why the worker exited without producing a PR

```
- 2026-04-01T09:09:57+02:00 — Issue #367: the Web cockpit now exposes inline per-rig Ralph controls via POST /api/ralph/:rig (enable/disable, condition text, target concurrency, condition status, count-support toggle), while test_ralph_mode_config_and_state.sh now asserts human status and durable event-log visibility for Ralph state changes.
- 2026-04-01T11:16:35+02:00 — 2026-04-01 issue #370: per-rig mayor helper calls must preserve the caller's rig scope and existing errexit mode. Status/notify/start-stop-refresh helpers that reset scope to shared or blindly restore set -e can make President-started mayor/<rig> sessions fall off after startup/event handling with clean-exit or nonzero-exit noise instead of staying resident.
- 2026-04-01T11:18:05+02:00 — Acceptance blocker sgt-acceptance-1775035085-041bcff8 reported by witness: Replacement work required after stalled polecat for issue #370

### Acceptance Blocker sgt-acceptance-1775035085-041bcff8

- Reported at: 2026-04-01T11:18:05+02:00
- Reported by: witness
- Title: Replacement work required after stalled polecat for issue #370

```markdown
Replacement work required after stalled polecat for issue #370

Stalled polecat recovery did not produce replacement work.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #370
- Issue URL: https://github.com/codejeet/sgt/issues/370
- Issue title: unknown
- Polecat: sgt-f1ac7cda
- Failure reason: witness-stalled-issue-title-unavailable

Required follow-up:
- create replacement work (new PR or re-dispatched polecat) before closing the incident
- re-investigate why the worker exited without producing a PR

```
- 2026-04-01T11:34:21+02:00 — 2026-04-01 issue #371: per-rig mayor liveness under President depends on preserving both caller rig scope and the current errexit mode across helper calls. In practice, _mayor_notify_rigger flipping set -e back on and helper paths like status/wake/start/stop/refresh resetting scope to shared can make mayor/<rig> exit after its first startup/event cycle instead of staying resident.
- 2026-04-01T11:48:19+02:00 — 2026-04-01 issue #370: preserve caller mayor scope across President/Deacon per-rig supervision and mayor start/stop/refresh helpers. Those helpers must not force scope back to shared after rig-targeted calls, or President-started mayor/<rig> sessions can lose scoped state/heartbeat paths and fall off after startup. Regression coverage now asserts scope preservation across cmd_mayor_start/stop/refresh, their _cmd_* helpers, and _president_supervise_rig_mayor.
- 2026-04-01T11:49:42+02:00 — 2026-04-01 issue #363: expanded test_plan_tick_duplicate_completed_task_guard.sh to pin the live Ralph duplicate-redispatch shape across SGT55/SGT56/SGT57. Default repo-local pending/planned task statuses must retain latest merged task lineage and stay completed; only explicit reopen markers (status=reopened/requeue or reopen=true) may clear completion and redispatch.
- 2026-04-01T11:50:01+02:00 — 2026-04-01 issue #357: President supervision now hard-skips hibernated rigs before any start/refresh/wake decision, so actionable-no-forward-motion and pending-plan/ralph checks cannot trigger manual-refresh|rig=<rig> or restart mayor/<rig> while the rig remains hibernated. Regression coverage: test_president_runtime_supervision.sh.
- 2026-04-01T11:50:22+02:00 — 2026-04-01: President runtime supervision now short-circuits hibernated rigs before selecting any start/refresh/wake action, so actionable-no-forward-motion and actionable-rig-recheck no longer trigger manual-refresh|rig=<rig> or restart a per-rig mayor while the rig remains manually hibernated. Regression coverage: test_president_runtime_supervision.sh and test_president_runtime_latest_main_proof.sh.
- 2026-04-01T11:50:34+02:00 — 2026-04-01 issue #366: when Ralph keeps a rig pending, plan-state completion.acceptance now mirrors the effective pending status instead of leaking stale verified/waived/blocked terminal metadata; original declared terminal status and timestamps are preserved under completion.acceptance.declared_* for operator forensics, with regression coverage in test_ralph_mode_config_and_state.sh.
- 2026-04-01T11:50:48+02:00 — 2026-04-01 issue #356 follow-up: current origin/master already covers the duplicate-close continuation redispatch bug through the later plan-task lineage/reopen fix train from PR #365. Effective guardrails are retained merged plan-task issue lineage plus explicit reopen semantics; unchanged pending/planned task defaults no longer reopen completed work, so refill/top-up does not recreate the just duplicate-closed lane without a materially changed task payload or explicit open successor.
- 2026-04-01T11:50:54+02:00 — Acceptance blocker sgt-acceptance-1775037054-36b6a910 reported by witness: Replacement work required after stalled polecat for issue #357

### Acceptance Blocker sgt-acceptance-1775037054-36b6a910

- Reported at: 2026-04-01T11:50:54+02:00
- Reported by: witness
- Title: Replacement work required after stalled polecat for issue #357

```markdown
Replacement work required after stalled polecat for issue #357

Stalled polecat recovery did not produce replacement work.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #357
- Issue URL: https://github.com/codejeet/sgt/issues/357
- Issue title: unknown
- Polecat: sgt-2255024f
- Failure reason: witness-stalled-issue-title-unavailable

Required follow-up:
- create replacement work (new PR or re-dispatched polecat) before closing the incident
- re-investigate why the worker exited without producing a PR

```
- 2026-04-01T11:51:30+02:00 — Acceptance blocker sgt-acceptance-1775037090-5552e67c reported by witness: Replacement work required after stalled polecat for issue #356

### Acceptance Blocker sgt-acceptance-1775037090-5552e67c

- Reported at: 2026-04-01T11:51:30+02:00
- Reported by: witness
- Title: Replacement work required after stalled polecat for issue #356

```markdown
Replacement work required after stalled polecat for issue #356

Stalled polecat recovery did not produce replacement work.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #356
- Issue URL: https://github.com/codejeet/sgt/issues/356
- Issue title: unknown
- Polecat: sgt-d90e6faf
- Failure reason: witness-stalled-issue-title-unavailable

Required follow-up:
- create replacement work (new PR or re-dispatched polecat) before closing the incident
- re-investigate why the worker exited without producing a PR

```
- 2026-04-01T11:51:35+02:00 — Acceptance blocker sgt-acceptance-1775037095-0d58f10b reported by witness: Replacement work required after stalled polecat for issue #366

### Acceptance Blocker sgt-acceptance-1775037095-0d58f10b

- Reported at: 2026-04-01T11:51:35+02:00
- Reported by: witness
- Title: Replacement work required after stalled polecat for issue #366

```markdown
Replacement work required after stalled polecat for issue #366

Stalled polecat recovery did not produce replacement work.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #366
- Issue URL: https://github.com/codejeet/sgt/issues/366
- Issue title: unknown
- Polecat: sgt-f6cc4fa1
- Failure reason: witness-stalled-issue-title-unavailable

Required follow-up:
- create replacement work (new PR or re-dispatched polecat) before closing the incident
- re-investigate why the worker exited without producing a PR

```
- 2026-04-01T11:52:12+02:00 — Acceptance blocker sgt-acceptance-1775037131-162b91f4 reported by witness: Replacement work required after stalled polecat for issue #359

### Acceptance Blocker sgt-acceptance-1775037131-162b91f4

- Reported at: 2026-04-01T11:52:12+02:00
- Reported by: witness
- Title: Replacement work required after stalled polecat for issue #359

```markdown
Replacement work required after stalled polecat for issue #359

Stalled polecat recovery did not produce replacement work.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #359
- Issue URL: https://github.com/codejeet/sgt/issues/359
- Issue title: unknown
- Polecat: sgt-7cfb9131
- Failure reason: witness-stalled-issue-title-unavailable

Required follow-up:
- create replacement work (new PR or re-dispatched polecat) before closing the incident
- re-investigate why the worker exited without producing a PR

```
- 2026-04-01T12:07:56+02:00 — Acceptance blocker sgt-acceptance-1775035085-041bcff8 resolved.
- 2026-04-01T12:07:56+02:00 — Acceptance blocker sgt-acceptance-1775022704-d829bc00 resolved.
- 2026-04-01T12:07:56+02:00 — Acceptance blocker sgt-acceptance-1775037090-5552e67c resolved.
- 2026-04-01T12:07:56+02:00 — Acceptance blocker sgt-acceptance-1775027294-89db909c resolved.
- 2026-04-01T12:07:56+02:00 — Acceptance blocker sgt-acceptance-1775037054-36b6a910 resolved.
- 2026-04-01T12:07:56+02:00 — Acceptance blocker sgt-acceptance-1775022423-817268fb resolved.
- 2026-04-01T12:07:56+02:00 — Acceptance blocker sgt-acceptance-1775037131-162b91f4 resolved.
- 2026-04-01T12:07:56+02:00 — Acceptance blocker sgt-acceptance-1775037095-0d58f10b resolved.
- 2026-04-01T12:29:10+02:00 — 2026-04-01 issue #357: President supervision now hard-skips hibernated rigs before any start, refresh, or wake decision, so actionable-no-forward-motion, pending-plan-underfilled, and Ralph checks cannot trigger manual-refresh|rig=<rig> or restart mayor/<rig> while the rig remains hibernated. Regression coverage: test_president_runtime_supervision.sh.
- 2026-04-01T12:29:13+02:00 — 2026-04-01 issue #366: when Ralph keeps completion pending, plan-state completion.acceptance now mirrors the effective status and clears live terminal fields; declared terminal acceptance metadata is preserved under completion.acceptance.declared_* for operator forensics. Regression coverage: test_ralph_mode_config_and_state.sh.
- 2026-04-01T12:29:33+02:00 — 2026-04-01 issue #378: _president_supervise_rig_mayor now hard-skips hibernated rigs before any start/refresh/wake decision, so President cannot restart or poke mayor/<rig> while manual hibernation remains active. Regression coverage in test_president_runtime_supervision.sh and test_president_runtime_latest_main_proof.sh asserts no refresh, wake, or mayor start on a hibernated rig.
- 2026-04-01T12:30:26+02:00 — 2026-04-01 issue #356: added explicit regression coverage in test_plan_tick_duplicate_closeout_successor_refresh.sh for the duplicate-closeout refill case. A completed task with stale duplicate-closed lineage now proves two fences together: unchanged task signatures stay completed via merged lineage retention, while materially changed task payloads clear stale completion bookkeeping and dispatch a fresh successor instead of relaunching the killed duplicate lane.
- 2026-04-01T12:30:37+02:00 — 2026-04-01 issue #379: while Ralph keeps a rig pending, plan-state now rewrites completion.acceptance.status to the effective pending status and preserves stale terminal acceptance metadata under completion.acceptance.declared_* so verified/blocked drift cannot make successor work look done.
- 2026-04-01T12:31:03+02:00 — 2026-04-01 issue #377: _resling_pre_dispatch_revalidate now falls back to REST issue/pull endpoints when gh issue view or gh pr view flakes, so mayor stranded-rig recovery can still spawn workers from already-open sgt-authorized queues during GraphQL/live-query failures.
- 2026-04-01T12:36:39+02:00 — 2026-04-01 issue #379: _plan_state_snapshot must preserve the live pending Ralph override from plan-state when completion.rollup is ralph-* or Ralph says completion is blocked; otherwise re-sync from SGT_PLAN.json can reintroduce stale verified/blocked acceptance and make successor work look terminal again.
- 2026-04-01T12:37:14+02:00 — 2026-04-01 issue #379: _plan_state_snapshot now applies the live Ralph completion override immediately, so plan-state cannot briefly rehydrate stale verified/blocked terminal acceptance while Ralph remains unmet; _plan_state_update_completion also preserves incoming completion.acceptance.declared_* forensic metadata instead of stripping it on the pending rewrite. Regression coverage in test_ralph_mode_config_and_state.sh now covers stale blocked metadata as well as verified metadata.
- 2026-04-01T12:37:37+02:00 — Acceptance blocker sgt-acceptance-1775039857-953cb5e8 reported by witness: Replacement work required after stalled polecat for issue #379

### Acceptance Blocker sgt-acceptance-1775039857-953cb5e8

- Reported at: 2026-04-01T12:37:37+02:00
- Reported by: witness
- Title: Replacement work required after stalled polecat for issue #379

```markdown
Replacement work required after stalled polecat for issue #379

Stalled polecat recovery did not produce replacement work.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #379
- Issue URL: https://github.com/codejeet/sgt/issues/379
- Issue title: unknown
- Polecat: sgt-737d5c22
- Failure reason: witness-stalled-issue-title-unavailable

Required follow-up:
- create replacement work (new PR or re-dispatched polecat) before closing the incident
- re-investigate why the worker exited without producing a PR

```
- 2026-04-01T12:37:43+02:00 — 2026-04-01 issue #380: when a repo-local plan task changes materially, plan tick now clears any stale open issue binding once that old lane is no longer actively worked, and sweep/mayor/resling skip open plan-labeled issues whose body/title no longer match the current task so duplicate confidence-lift families cannot be resurrected after refill or consistency-mismatch churn.
- 2026-04-01T12:38:12+02:00 — Acceptance blocker sgt-acceptance-1775039892-82638667 reported by witness: Replacement work required after stalled polecat for issue #359

### Acceptance Blocker sgt-acceptance-1775039892-82638667

- Reported at: 2026-04-01T12:38:12+02:00
- Reported by: witness
- Title: Replacement work required after stalled polecat for issue #359

```markdown
Replacement work required after stalled polecat for issue #359

Stalled polecat recovery did not produce replacement work.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #359
- Issue URL: https://github.com/codejeet/sgt/issues/359
- Issue title: unknown
- Polecat: sgt-1674b1cf
- Failure reason: witness-stalled-issue-title-unavailable

Required follow-up:
- create replacement work (new PR or re-dispatched polecat) before closing the incident
- re-investigate why the worker exited without producing a PR

```
- 2026-04-01T12:38:17+02:00 — Acceptance blocker sgt-acceptance-1775039897-d6b36dec reported by witness: Replacement work required after stalled polecat for issue #379

### Acceptance Blocker sgt-acceptance-1775039897-d6b36dec

- Reported at: 2026-04-01T12:38:17+02:00
- Reported by: witness
- Title: Replacement work required after stalled polecat for issue #379

```markdown
Replacement work required after stalled polecat for issue #379

Stalled polecat recovery did not produce replacement work.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #379
- Issue URL: https://github.com/codejeet/sgt/issues/379
- Issue title: unknown
- Polecat: sgt-2c74a5cc
- Failure reason: witness-stalled-issue-title-unavailable

Required follow-up:
- create replacement work (new PR or re-dispatched polecat) before closing the incident
- re-investigate why the worker exited without producing a PR

```
- 2026-04-01T12:39:24+02:00 — Acceptance blocker sgt-acceptance-1775039964-1c53354b reported by witness: Replacement work required after stalled polecat for issue #380

### Acceptance Blocker sgt-acceptance-1775039964-1c53354b

- Reported at: 2026-04-01T12:39:24+02:00
- Reported by: witness
- Title: Replacement work required after stalled polecat for issue #380

```markdown
Replacement work required after stalled polecat for issue #380

Stalled polecat recovery did not produce replacement work.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #380
- Issue URL: https://github.com/codejeet/sgt/issues/380
- Issue title: unknown
- Polecat: sgt-61f8c178
- Failure reason: witness-stalled-issue-title-unavailable

Required follow-up:
- create replacement work (new PR or re-dispatched polecat) before closing the incident
- re-investigate why the worker exited without producing a PR

```
- 2026-04-01T12:45:47+02:00 — Acceptance blocker sgt-acceptance-1775039892-82638667 resolved.
- 2026-04-01T12:45:47+02:00 — Acceptance blocker sgt-acceptance-1775039857-953cb5e8 resolved.
- 2026-04-01T12:45:47+02:00 — Acceptance blocker sgt-acceptance-1775039897-d6b36dec resolved.
- 2026-04-01T13:01:29+02:00 — Issue #380: plan tick now clears stale open issue bindings after a material task-signature change once no active polecat remains, and sweep/mayor/witness/resling all skip open plan-labeled issues whose current title/body no longer match the repo-local task definition so duplicate continuation lanes are not resurrected by refill or watchdog churn.
- 2026-04-01T13:02:29+02:00 — Acceptance blocker sgt-acceptance-1775041349-4cbdb7d1 reported by witness: Replacement work required after stalled polecat for issue #380

### Acceptance Blocker sgt-acceptance-1775041349-4cbdb7d1

- Reported at: 2026-04-01T13:02:29+02:00
- Reported by: witness
- Title: Replacement work required after stalled polecat for issue #380

```markdown
Replacement work required after stalled polecat for issue #380

Stalled polecat recovery did not produce replacement work.

- Rig: sgt
- Repo: codejeet/sgt
- Issue: #380
- Issue URL: https://github.com/codejeet/sgt/issues/380
- Issue title: unknown
- Polecat: sgt-036f3c65
- Failure reason: witness-stalled-issue-title-unavailable

Required follow-up:
- create replacement work (new PR or re-dispatched polecat) before closing the incident
- re-investigate why the worker exited without producing a PR

```
