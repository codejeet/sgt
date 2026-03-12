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
