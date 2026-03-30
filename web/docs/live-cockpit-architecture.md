# SGT Web Live Cockpit Architecture Lock

Issue: `#262`

This document records the current `web/` audit and locks the implementation shape for the live cockpit build-out. Follow-on work should extend this architecture rather than replace it with a separate app tree or a different stack without an explicit new decision.

## Audit Summary

Current repo-tracked implementation:

- Backend: single-process Node.js + Express server in `web/server.js`
- Frontend: single-page vanilla HTML/CSS/JS app in `web/public/index.html`
- Realtime transport: one WebSocket connection used for coarse `sgt status` pushes and incremental `sgt.log` tail updates
- Current data sources:
  - `sgt status` shell-out, parsed into agents/polecats/dogs/crew/merge queue
  - `sgt rig list`
  - state files under `~/.sgt/`
  - `sgt peek <target>` snapshot fetches
  - direct tailing of `~/sgt/sgt.log`
- Existing operator capabilities:
  - status dashboard
  - polecat/dog/rig views
  - manual dispatch from browser
  - log tail
  - one-shot tmux peek modal

Observed gaps against the larger live-cockpit plan:

- tmux visibility is snapshot-only; there is no live Mayor or polecat pane stream
- the WebSocket payload is a coarse whole-status poll, not a normalized event/state model
- acceptance blockers are not modeled or surfaced
- there is no TTS integration
- there is no topology or WebGL view
- the deployed copy at `/root/sgt/web` is operationally separate from the repo unless the operator syncs it manually

## Locked Decisions

### 1. Canonical code location

`web/` in the repo is the only canonical web app source tree.

- Do not create a second standalone cockpit elsewhere.
- `/root/sgt/web` is a deployment target, not a source of truth.
- All follow-on web UI work lands in repo `web/` first, then syncs outward.

### 2. Stack and process model

Keep the current lightweight stack:

- Node.js + Express on the backend
- WebSocket for live updates
- static frontend served by the same process
- no database
- no frontend framework migration for this plan

Reasoning:

- the app is ops-local, small, and already integrated with `sgt`
- the main problem is live state modeling and operator ergonomics, not framework capability
- preserving a single deployable process keeps the live cockpit easier to run on the rig host

### 3. Backend architecture

The backend should evolve into a small in-memory aggregator with two output forms:

- a normalized snapshot document for initial page load / reconnect
- incremental WebSocket events for live updates

Locked backend shape:

- retain shell/file based integration with `sgt`; do not introduce a separate persistence layer
- centralize polling/watchers server-side rather than having the browser fan out to many endpoints
- treat `sgt status`, state files, blocker records, merge queue, and tmux captures as input adapters into one backend state model
- support per-panel subscriptions over the existing WebSocket so tmux streams/topology updates can be opt-in instead of always-on

### 4. Live tmux streaming model

Mayor and active polecats must be streamed through the existing backend, not by having the browser shell out directly.

Locked approach:

- add server-side tmux stream workers keyed by target session/pane
- stream captured pane deltas over WebSocket channels such as `stream/open`, `stream/data`, `stream/stale`, `stream/close`
- keep current `peek` as a snapshot fallback and debugging path
- expose clear freshness state: live, stale, reconnecting, unavailable
- make streams demand-driven so inactive panes do not consume resources

Non-goal for this phase:

- terminal emulation fidelity. This cockpit needs readable operational tail/focus streams, not a full browser terminal emulator.

### 5. State model

The frontend should consume one normalized cockpit model instead of scraping per-panel shapes ad hoc.

The locked top-level model is:

- `meta`: server time, websocket health, feature flags, version
- `agents`: daemon, mayor, witness, refinery, crew and health/freshness data
- `rigs`: rig summary, hibernation state, open work counts, active blockers
- `workers`: active polecats/dogs with issue, branch, PR, role, freshness, stream availability
- `queue`: merge queue and dispatch-ready signals
- `blockers`: acceptance blockers and important lifecycle transitions
- `logs`: recent operator log events and stream metadata
- `topology`: graph nodes/edges derived from the same snapshot

Follow-on APIs and UI code should converge on this vocabulary.

### 6. Acceptance blocker and TTS path

Acceptance blockers are first-class cockpit data.

Locked behavior:

- blocker creation, resolution, and major state transitions are backend events
- the UI must surface blockers visually even when audio is disabled
- ElevenLabs remains optional and env-gated
- TTS is a backend concern triggered from blocker/milestone events, with mute state and dedupe/rate limiting
- lack of ElevenLabs configuration must never reduce cockpit usefulness

Operator preference from shared context:

- visual emphasis is highest priority for new blocker creation/escalation
- voice is most valuable for blocker resolution or major milestone progress

### 7. WebGL/topology path

The topology view should be an optional panel driven from the same normalized snapshot/event stream.

Locked behavior:

- graph data originates from backend snapshot/event state, not from a separate crawler
- the topology view must degrade cleanly to a non-WebGL fallback message or static relationship list
- the graph is for orientation and triage, so nodes/edges must represent real SGT entities: rigs, Mayor, workers, issues, PRs, blockers, queue links

### 8. UI shell direction

The cockpit should keep the dense operator-shell direction, but the next refinement pass must be driven by the explicit anti-pattern research in [`web/docs/human-dashboard-redesign-rules.md`](human-dashboard-redesign-rules.md) instead of leaning further into generic JARVIS/sci-fi dashboard styling.

Locked UI constraints:

- keep status, logs, and dispatch utility available
- prioritize dense, scannable live-state presentation over decorative motion
- maintain keyboard-friendly workflows
- clearly distinguish healthy, active, stale, blocked, and critical states
- make live monitoring the first major section operators encounter
- use the visible title `SGT SGT Cockpit`
- materially reduce gradients, glow, blur, and over-rounded surfaces
- keep the palette dark and intentionally triadic while retaining blue

## Implementation Sequence

Follow-on issues should stay roughly in this order:

1. Backend normalized snapshot/event model
2. Demand-driven live tmux streaming for Mayor and polecats
3. Cockpit shell redesign around the normalized model
4. Blocker center and event prominence
5. Optional ElevenLabs integration
6. Topology/WebGL panel
7. Acceptance verification on latest `master`

## Deployment Path

The repo copy stays canonical. The live served copy updates from it.

Default local deployment target:

- source: repo `web/`
- target: `/root/sgt/web`
- served URL today: `http://<tailscale-host>:4747`

Use the repo-owned helper:

```bash
web/scripts/sync-live-copy.sh
```

That script syncs repo `web/` into the live target, preserves runtime-only artifacts such as `node_modules/` and `webui.log`, and runs `npm install` in the live directory so the served copy reflects the repo source.

## Latest-main proof path

Run this on a fresh checkout of the latest `master`/mainline commit when you want repo-owned proof that the repo-tracked cockpit still matches the locked deploy/config/proof contract:

```bash
./test_web_cockpit_latest_main_proof.sh
```

This proof path is intentionally narrow:

- `npm --prefix web test` verifies the normalized cockpit snapshot/topology contracts, operator-shell UI structure, and the docs/deploy-helper assertions for the canonical repo copy
- `web/scripts/sync-live-copy.sh --dry-run <tempdir>` exercises the documented repo `web/` to live-copy deployment helper without mutating `/root/sgt/web`

## Guardrails For Follow-on Work

- Do not split the app into multiple deployables for this plan.
- Do not bypass the backend for tmux streaming, blocker state, or topology state.
- Do not make ElevenLabs or WebGL a requirement for baseline operator use.
- Do not improvise the redesign from taste alone; use the anti-pattern catalog and redesign rules in `web/docs/human-dashboard-redesign-rules.md`.
- Do not treat a merged intermediate PR as final cockpit completion while plan acceptance remains pending.
