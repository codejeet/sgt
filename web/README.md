# SGT Web UI (Operator Shell)

SGT Web UI is a small, dependency-light **real-time operator shell** for SGT (Simple GitHub Gastown): monitor Mayor and workers live, surface blockers and queue state, tail logs, inspect topology relationships, and dispatch new work.

For the locked follow-on cockpit architecture and deployment path, see [`web/docs/live-cockpit-architecture.md`](docs/live-cockpit-architecture.md).
For the research-first redesign constraints that govern the next visual refinement pass, see [`web/docs/human-dashboard-redesign-rules.md`](docs/human-dashboard-redesign-rules.md).

## Quick start

```bash
cd web
npm ci
npm start
# open http://localhost:4747
```

## Deploy path

The repo-tracked `web/` directory is the only canonical source for the cockpit.
The default live served copy on a rig host lives at `/root/sgt/web`, and the default URL is `http://localhost:4747` when you run it locally or `http://<tailscale-host>:4747` on the rig host.

Sync the repo copy into the live target with:

```bash
web/scripts/sync-live-copy.sh
```

Dry-run the sync first if needed:

```bash
web/scripts/sync-live-copy.sh --dry-run
```

Override the live target without editing the script:

```bash
SGT_WEB_LIVE_DIR=/srv/sgt/web web/scripts/sync-live-copy.sh
```

`web/scripts/sync-live-copy.sh` uses `rsync --delete`, preserves runtime-only artifacts such as `node_modules/` and `webui.log`, copies the repo-tracked `package-lock.json`, and runs `npm ci` in the live target so `/root/sgt/web` stays a served deployment copy rather than a second source tree.

## Configuration

Server runtime environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SGT_WEB_PORT` | `4747` | Server port |
| `SGT_ROOT` | `~/sgt` | SGT workspace root |
| `SGT_BIN` | `$SGT_ROOT/sgt` | Path to sgt binary |
| `SGT_WEB_ELEVENLABS_API_KEY` | unset | Optional ElevenLabs API key for blocker voice announcements |
| `SGT_WEB_ELEVENLABS_VOICE_ID` | unset | Optional ElevenLabs voice id used when voice is enabled |
| `SGT_WEB_ELEVENLABS_MODEL_ID` | `eleven_turbo_v2_5` | Optional ElevenLabs model override |
| `SGT_WEB_VOICE_EVENT_KINDS` | `blocker-resolved` | Comma-separated blocker alert kinds eligible for voice |
| `SGT_WEB_VOICE_RATE_LIMIT_SECS` | `90` | Minimum seconds between eligible voice announcements |

Deploy-helper environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SGT_WEB_LIVE_DIR` | `/root/sgt/web` | Alternate live sync target used by `web/scripts/sync-live-copy.sh` |

Behavior notes:

- Voice stays optional. Without `SGT_WEB_ELEVENLABS_API_KEY` and `SGT_WEB_ELEVENLABS_VOICE_ID`, the cockpit stays fully usable and the UI reports voice as unavailable.
- The browser mute toggle is local state only. Backend event gating and rate limiting still come from `SGT_WEB_VOICE_EVENT_KINDS` and `SGT_WEB_VOICE_RATE_LIMIT_SECS`.
- The topology panel prefers WebGL for the live graph and falls back to the canvas/overlay path when WebGL init or GPU support is unavailable.

## Latest-main proof

Run this on a fresh checkout of the latest `master`/mainline commit when you want repo-owned proof that the repo-tracked cockpit still covers the documented shell, data model, and deploy path:

```bash
./test_web_cockpit_latest_main_proof.sh
```

That proof path bundles:

- `npm --prefix web ci && npm --prefix web test` for a fresh-checkout dependency install plus the cockpit snapshot/topology/blocker alert contracts, operator-shell UI, and docs/deploy-helper assertions
- `web/scripts/sync-live-copy.sh --dry-run <tempdir>` so the canonical repo `web/` to live-copy sync path is exercised without touching `/root/sgt/web`

## Features

- **Dense cockpit shell** — Single-page JARVIS-style HUD with command pulse, alert center, worker roster, rig matrix, topology radar, and dispatch console
- **Live tmux monitoring** — Mayor gets a dedicated live monitor, while all active polecats can stay open simultaneously in a filtered multi-pane wall with per-pane tail/focus/peek controls
- **Acceptance blocker center** — Open blockers stay prominent with rig ownership, evidence snippets, and timestamps
- **Recent alert rail** — New blocker openings, follow-up escalations, and resolutions surface as explicit alert cards instead of blending into the blocker list
- **Optional ElevenLabs voice** — Env-gated blocker voice announcements with browser mute control plus backend dedupe and rate limiting
- **Realtime WS** — Normalized `snapshot` pushes plus tmux stream events and live `sgt.log` updates; reconnect/backoff and stale states remain visible
- **Topology radar** — Force-laid live graph driven from normalized `topology` nodes/edges, using WebGL when available plus a canvas fallback with the same click/hover focus workflows
- **Keyboard shortcuts** — `1..5` jump between shell sections, `c` toggles compact mode, `Esc` closes peek modal
- **Dispatch** — Sling polecats and dogs without leaving the shell

## Redesign Direction

Issue `#278` locks the next UI pass to an explicit research-first rule set rather than ad hoc style tweaking.

- catalog and remove common AI-generated dashboard tells
- move live monitoring to the first major section on page load
- change the visible operator title to `SGT SGT Cockpit`
- materially reduce gradients and corner radius
- keep the shell dark, but use a stronger triadic palette that still includes blue
- preserve the existing real-time monitoring, blocker, topology, and dispatch capabilities
- keep repo `web/` canonical and sync the served copy with `web/scripts/sync-live-copy.sh`

## Theme

The current UI uses a dense dark cockpit shell. The follow-on refinement issue should use the redesign rules above to reduce generic JARVIS/AI-dashboard styling while preserving the core operator workflows.

- display typography is available for selective emphasis, not broad decorative use
- IBM Plex Sans / Mono remain the readability baseline for dense operational content
- accent colors should stay semantic and become more intentionally distributed in the next pass

## Screenshots

Stored under `web/docs/screenshots/`:

- Before (baseline): `web/docs/screenshots/before-triadic-dashboard.png`
- After (triadic theme):
  - `web/docs/screenshots/after-triadic-dashboard.png`
  - `web/docs/screenshots/after-triadic-polecats.png`
  - `web/docs/screenshots/after-triadic-logs.png`

## Troubleshooting

- **Port already in use (EADDRINUSE)**
  - Find/kill the process: `ss -ltnp | grep ':4747'`
  - Or run on a different port: `SGT_WEB_PORT=4750 npm start`

- **WebSocket shows Disconnected / stale timestamps**
  - The UI will reconnect automatically with backoff.
  - If the server is down, restart it: `npm start`.

- **Missing SGT binary / wrong SGT_ROOT**
  - Set `SGT_ROOT` and/or `SGT_BIN` explicitly, e.g.:
    - `SGT_ROOT=~/sgt SGT_BIN=~/sgt/sgt npm start`

- **Permissions**
  - The server shells out to `sgt` and reads `~/sgt/sgt.log`. Ensure the user running the web server can access those files.

- **Voice announcements are unavailable**
  - Set both `SGT_WEB_ELEVENLABS_API_KEY` and `SGT_WEB_ELEVENLABS_VOICE_ID`.
  - The UI stays fully usable without them; the Voice chip will show `Unavailable`.
  - The browser mute toggle only affects local playback. Backend event gating and rate limiting still apply for eligible announcements.

## Reasoning behind the project

SGT exists because the original **Gas Town** tooling became bloated and fragile:
- “Beads” (naming/prefix conventions) were easy to break and hard to recover.
- Persistence and state management drifted over time.

SGT replaces that complexity with a simpler, more reliable model:
- **GitHub Issues + PRs** as the source of truth
- **tmux** for worker lifecycle/output
- **gh** CLI for consistent operations

The goal is higher reliability, a simpler mental model, and easier ops.

## Architecture

- **Backend**: Node.js + Express. Shells out to `sgt` CLI for actions; tails `~/sgt/sgt.log`.
- **Frontend**: Static vanilla HTML/CSS/JS served by the same process.
- **Real-time**: WebSocket pushes status and log deltas; includes heartbeat + reconnect/backoff.
- **Topology rendering**: browser-side force simulation with a WebGL node/edge pass when supported; overlay labels and fallback rendering remain canvas-based so the panel still works without GPU support.
- **Canonical source**: repo `web/` is the source of truth; `/root/sgt/web` is a deployment target.

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/status` | Full parsed SGT status |
| GET | `/api/cockpit` | Normalized live cockpit snapshot |
| GET | `/api/rigs` | List registered rigs |
| GET | `/api/polecats` | Polecat state files |
| GET | `/api/dogs` | Dog state files |
| GET | `/api/merge-queue` | Merge queue items |
| GET | `/api/blockers` | Active acceptance blockers |
| GET | `/api/announcements/:alertId/audio` | Optional ElevenLabs audio for an eligible blocker alert |
| GET | `/api/peek/:target` | Peek at tmux pane output |
| GET | `/api/logs?lines=N` | Tail sgt.log |
| GET | `/api/plan-state/:rig` | Repo plan-state JSON for one rig |
| POST | `/api/sling` | Dispatch a polecat `{rig, task, labels?, convoy?}` |
| POST | `/api/sling-dog` | Dispatch a dog `{rig, issue}` |
| WS | `/` | Real-time status/log stream plus snapshot + tmux stream events |

## WebSocket control messages

Client-to-server:

- `{"type":"snapshot/request"}` — request an immediate normalized snapshot
- `{"type":"stream/subscribe","target":"president"}` — start a live tmux stream for `president`, `mayor`, `mayor/<rig>`, `witness/<rig>`, `refinery/<rig>`, `crew/<name>`, `dog/<name>`, or a polecat name
- `{"type":"stream/unsubscribe","target":"mayor"}` — stop a live tmux stream

The stream section defaults to a polecat-focused monitor wall:

- rig and role filters narrow the active live panes without leaving the page
- `Match` filters by worker name, rig, issue, or branch text
- `Tail All` toggles auto-follow across every subscribed pane
- each pane still supports `Tail`, `Focus`, and `Peek`

Server-to-client additions:

- `snapshot` — normalized cockpit state document
- `stream/open` — tmux stream became available
- `stream/data` — pane delta payload; `reset=true` means replace the current client buffer
- `stream/stale` — session became unavailable or stopped updating
- `stream/close` — stream worker closed after unsubscribe
