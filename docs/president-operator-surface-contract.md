# President Operator-Surface Contract

Issue: `#333`

This document defines the operator-facing surface contract for the President pass on latest main.

It ties together the runtime hierarchy, the structured President event model, and the concrete operator surfaces that must expose that activity without log archaeology.

## Required Surfaces

The President pass is only in contract when all of these surfaces stay explicit and separately inspectable:

- `sgt status` shows `president` separately from each `mayor/<rig>` and includes recent President activity in the human-readable operator view
- `sgt status --json` emits control-plane `role` / `scope` metadata plus bounded `president_events` history with rig, kind, reason, action, outcome, severity, dedupe, and overlap fields
- `sgt peek president` and `sgt peek mayor/<rig>` retain scoped inspection so the operator can inspect the top-level supervisor separately from one rig-local Mayor
- the Web UI topology keeps `president` and `mayor/<rig>` directly inspectable as separate control-plane nodes
- the Web UI alert rail prefers recent and actionable President incidents instead of quiet replay noise or stale resolved overflow
- the Web UI `President Activity` panel renders recent President event history with rig, reason, action, outcome, and detail context

## Operator Outcome

The operator should be able to answer these questions directly from the product surfaces:

- is President running and healthy?
- which rig-local Mayors exist, and which rig does each own?
- what did President do most recently, to which rig, and why?
- was the action a `start`, `wake`, `refresh`, or a suppressed replay?
- is the incident operator-actionable, or just a quiet bounded recheck?

If an operator still has to grep raw logs to learn those answers, the surface pass is incomplete.

## Latest-Main Proof

Run this on a fresh checkout of the latest `master`/mainline commit:

```bash
./test_president_operator_surface_latest_main_proof.sh
```

That proof path bundles the repo-owned checks for the full President operator-surface pass:

- `./test_president_runtime_latest_main_proof.sh` proves the active hierarchy, scoped status/peek behavior, Web UI control-plane distinction, and President bounded supervision plus notify contract
- `./test_status_json.sh` proves `sgt status --json` keeps machine-readable President event history in `president_events`
- `npm --prefix web test` keeps the cockpit snapshot, topology, alert rail, and `President Activity` rendering contract under test

## Surface Mapping To Existing Contracts

- The control-plane hierarchy and scope rules live in [`docs/president-per-rig-mayor-contract.md`](docs/president-per-rig-mayor-contract.md)
- The President event shape, kinds, and dedupe rules live in [`docs/president-operator-notify-contract.md`](docs/president-operator-notify-contract.md)
- This document is the operator-facing join point: it defines where those contracts must become visible to operators on latest main
