# President And Per-Rig Mayor Architecture Contract

Issue: `#300`

This document defines the control-plane contract for the SGT migration from one shared Mayor to a hierarchy with one Mayor per rig and a President supervising those Mayors.

It is intentionally explicit about two things:

- the target operating model SGT is converging on
- the transitional state that exists in the repo today

## Current Transitional State

As of this contract:

- the default runtime is still the legacy shared Mayor (`sgt-mayor`)
- SGT now supports a first-class President runtime when `SGT_MAYOR_ARCHITECTURE=per-rig`
- in per-rig mode, President runs in `sgt-president` with scoped transient files under `~/.sgt/president/`
- in per-rig mode, each rig Mayor runs in its own tmux session (`sgt-mayor-<rig>`) with scoped transient files under `~/.sgt/mayors/<rig>/`
- operator surfaces now expose `president` separately from `mayor/<rig>` in status, peek, logs, and the Web UI

Shared Mayor mode remains as a legacy compatibility fallback, but the President-led runtime now exists for the per-rig control-plane path.

## Target Hierarchy

The target control plane is:

`President -> Mayor/<rig> -> rig-local workers`

The role split is strict:

- `President` is the cross-rig supervisor
- `Mayor/<rig>` is the executive owner for one rig only
- Witness, Refinery, polecats, dogs, and crew remain rig-local execution/support agents

SGT is done with this migration only when the President exists as the top-level supervisor and the system no longer depends on one shared cross-rig Mayor as the sole executive brain.

## Role Contract

### President

The President owns cross-rig supervision and only cross-rig supervision.

The President must:

- monitor health and forward progress for all rig-local Mayors
- detect wedges, contradictory control-plane state, stale supervision loops, or rigs with actionable work but no healthy movement
- perform bounded interventions such as wake, refresh, restart, or escalation for one affected Mayor when justified
- coordinate system-level or cross-rig policy decisions that do not belong inside one rig
- emit operator-visible evidence for why it intervened, deferred, or declared a rig healthy

The President must not:

- take over routine repo-local execution from a rig Mayor
- dispatch normal rig work directly except for an explicitly documented recovery path
- become a new hidden shared reasoning loop that collapses rig boundaries again

### Mayor/<rig>

Each rig-local Mayor owns one rig and only that rig.

Each Mayor must:

- reason only over that rig's repo truth, plan truth, blockers, PRs, issues, hibernation state, and in-flight workers
- keep isolated transient assets such as heartbeat, lease, logs, briefing, handoff archive, and wake FIFO/state
- preserve rig-local ownership for plan decomposition, dispatch, re-dispatch, blocker follow-up, and stale-work compaction
- remain refreshable, inspectable, and restartable without disturbing other rigs

Each Mayor must not:

- supervise other rigs
- make cross-rig policy decisions that belong to the President
- depend on another rig's transient state in order to make normal rig-local decisions

## Process And State Boundaries

The contract requires explicit process and filesystem boundaries.

- President state must live separately from every Mayor's state.
- Each Mayor must have scoped runtime assets under a rig-local directory.
- Restarting or refreshing one Mayor must not rewrite or discard another Mayor's transient state.
- Durable truth stays repo-owned or rig-owned: GitHub issues/PRs, blocker records, plan-state, and shared context are not duplicated into invented control-plane truth.

Transient state can be rebuilt. Durable truth must be preserved.

## Operator Scope Contract

Operator commands and surfaces must make scope obvious.

Required scopes:

- `president` for the top-level supervisor
- `mayor/<rig>` for one rig-local Mayor
- all-rigs operations only when the action is explicitly global

The long-term command contract is:

- `sgt up` / `sgt down` manage President plus all required rig-local Mayors coherently
- `sgt status` distinguishes President from each `mayor/<rig>`
- `sgt peek` and log surfaces let the operator inspect `president` separately from `mayor/<rig>`
- refresh/restart flows work at the right scope: President, one Mayor, or all Mayors
- compatibility shims may exist during migration, but they must not hide scope

## Observability Contract

Operator-visible state must answer all of these questions without inference:

- is the President healthy?
- which Mayors are healthy, stale, hibernated, or wedged?
- what was each Mayor's last cycle, last wake, and last meaningful action?
- did the President intervene, and why?
- is a rig blocked because of repo truth, hibernation, missing work, or control-plane failure?

This applies to:

- `sgt status`
- `sgt status --json`
- `sgt peek`
- log surfaces
- the Web UI / cockpit

## Migration Safety Rules

The migration from shared Mayor to President plus per-rig Mayors must preserve rig truth.

Required invariants:

- do not manufacture duplicate work during topology changes
- preserve durable board, blocker, plan-state, and in-flight work truth
- keep hibernation semantics authoritative at rig scope
- keep common operator actions coherent while shared-mode compatibility still exists
- allow incremental rollout and rollback without orphaning recoverable rigs

The optional per-rig Mayor runtime already in the repo is the approved staging step for this migration, not the endpoint.

## Repo-Owned Proof Expectations

This contract is only useful if the repo keeps proving it.

Current proof for the transition:

- `./test_mayor_per_rig_architecture.sh` proves the existing per-rig Mayor runtime contract: separate Mayor sessions, scoped status entries, and targeted wake routing
- `./test_president_runtime_supervision.sh` proves deacon supervises President and President can perform a bounded per-rig refresh intervention without taking over routine rig work
- `./test_peek_mayor_log_fallback.sh` proves `sgt peek president` and `sgt peek mayor/<rig>` both retain scoped log fallback behavior
- `./test_president_per_rig_mayor_contract.sh` proves the architecture contract remains documented in-repo
- `./test_president_runtime_latest_main_proof.sh` bundles the runtime, surface, and contract checks as the latest-main proof for the active hierarchy

The latest-main proof for the active runtime now proves:

- President runtime exists and is separately inspectable
- status and peek surfaces distinguish `president` from `mayor/<rig>`
- at least two rigs can appear under independent Mayors in status
- President supervision can perform a justified per-rig unblock or recovery action without taking over routine rig-local ownership

## Summary

The contract is simple:

- President supervises rigs
- each Mayor owns exactly one rig
- operator surfaces must expose that hierarchy explicitly
- migration must preserve durable rig truth

Anything that blurs those boundaries is out of contract.
