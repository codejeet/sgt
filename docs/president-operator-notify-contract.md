# President Operator-Notify Event Contract

Issue: `#320`

This document defines the operator-facing event model for the President runtime and the dedupe rules that keep President and Mayor from paging the operator twice for the same incident.

It does not require President to narrate every cycle. The contract is intentionally biased toward important, actionable events.

## Goal

President notifications exist to answer one question:

"Does the operator need to check, judge, or unblock something at the cross-rig supervision layer?"

If the answer is no, President should log the event for observability without emitting a top-level operator notification.

## Event Shape

Every President operator event uses these fields:

- `rig`: the affected rig
- `kind`: the normalized event family
- `severity`: `info`, `warning`, or `critical`
- `notify`: `1` when this is operator-facing, `0` when it is log-only
- `dedupe_key`: President-local replay key
- `overlap_key`: cross-layer incident key for President/Mayor/UI coalescing
- `action`: what President did or attempted (`start`, `wake`, `refresh`, later `restart` if added)
- `reason`: the raw runtime reason
- `outcome`: current result such as `intervened` or `suppressed-by-cooldown`
- `cycle_trigger`: why the President cycle ran
- `detail`: operator-readable evidence

The runtime emits this as `PRESIDENT_OPERATOR_EVENT ...`.

## Event Kinds

President normalizes raw reasons into these operator-facing kinds:

- `drift`: a rig is moving, but not toward the intended repo plan or larger purpose
- `stalled-purpose`: a rig is technically active or actionable, but meaningful forward motion is absent
- `contradiction`: observed rig behavior conflicts with the accepted repo truth, completion path, or higher-level program intent
- `intervention`: President had to start, wake, refresh, or later restart a rig-local Mayor because the Mayor itself was unhealthy or missing
- `escalation`: President is explicitly raising a high-urgency operator attention event
- `human-question`: President needs operator judgment or missing human input

The kind model is intentionally stable even if the underlying raw `reason` strings grow over time.

## Current Runtime Mapping

Current President supervision reasons map as follows:

- `mayor-session-missing` -> `intervention`, `severity=warning`, `notify=1`
- `mayor-heartbeat-invalid` or `mayor-heartbeat-stale` -> `intervention`, `severity=warning`, `notify=1`
- `actionable-no-forward-motion` -> `stalled-purpose`, `severity=warning`, `notify=1`
- `actionable-rig-recheck` -> `intervention`, `severity=info`, `notify=0`

That last case is important: a quiet recheck wake is part of healthy bounded supervision, not operator-worthy noise by default.

## Notify Rules

President should notify only when at least one of these is true:

- the rig appears to be drifting from intended purpose
- actionable work exists but the rig lacks healthy forward motion
- the rig-local behavior contradicts the accepted plan or program intent
- the President had to intervene because the rig-local Mayor was missing, stale, wedged, or otherwise unhealthy
- President is escalating a problem that should not stay implicit
- President needs human judgment or missing human input

President should stay log-only when the event is merely a low-signal recheck, periodic observation, or a duplicate replay of an already surfaced incident.

## Dedupe Rules

There are two dedupe layers.

### 1. President-local replay dedupe

President-local dedupe uses `dedupe_key`.

- Format: `president:<rig>:<kind>:<reason>:<action>`
- Purpose: suppress repeated President re-alerting for the same rig, normalized event kind, raw reason, and intervention action
- Current runtime fence: the President intervention cooldown (`SGT_PRESIDENT_INTERVENTION_COOLDOWN_SECS`) already suppresses exact replay of the same `rig + reason + action`
- When cooldown suppresses a replay, President should emit `PRESIDENT_OPERATOR_EVENT ... outcome=suppressed-by-cooldown` instead of a second operator page

### 2. Cross-layer overlap dedupe

Cross-layer dedupe uses `overlap_key`.

- Purpose: let President, Mayor, the Web UI, and notification surfaces coalesce one underlying incident instead of paging separately from both layers
- Rule: if President and Mayor are surfacing the same operational incident, only one visible operator notification should survive; the other should remain visible as linked evidence, not a second page
- Current overlap key families:
  - `rig-incident:<rig>:actionable-no-forward-motion` for no-progress situations
  - `mayor-health:<rig>:<reason>` for Mayor-missing or Mayor-heartbeat incidents
  - `president-incident:<rig>:<kind>:<reason>` for President-specific drift, contradiction, escalation, or human-question situations

The first surfaced notification owns operator attention. Later overlapping events should be shown as corroborating context or merged history, not another independent alert.

## Operator Surface Expectations

Operator surfaces should preserve both truth and quietness:

- show the latest `PRESIDENT_OPERATOR_EVENT` records directly
- expose `kind`, `reason`, `action`, `outcome`, `notify`, `dedupe_key`, and `overlap_key`
- make `suppressed-by-cooldown` visible in logs/history so silence is explainable
- prefer recent, unresolved, and operator-actionable President events over old chatter

## Scope Boundary

This contract does not authorize President to take over routine rig-local Mayor work.

It only defines how President-class incidents are named, logged, and deduped when President observes or performs bounded supervision.
