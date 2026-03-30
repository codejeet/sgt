# SGT Web UI (Operator Shell)

SGT Web UI is a small, dependency-light **real-time operator shell** for SGT (Simple GitHub Gastown): monitor Mayor and workers live, surface blockers and queue state, tail logs, inspect topology relationships, and dispatch new work.

For the locked follow-on cockpit architecture and deployment path, see [`web/docs/live-cockpit-architecture.md`](docs/live-cockpit-architecture.md).

## Quick start

```bash
cd web
npm install
npm start
# open http://localhost:4747
```

To sync the repo-tracked `web/` copy into the live served target on the rig host:

```bash
web/scripts/sync-live-copy.sh
```

Dry-run the sync first if needed:

```bash
web/scripts/sync-live-copy.sh --dry-run
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SGT_WEB_PORT` | `4747` | Server port |
| `SGT_ROOT` | `~/sgt` | SGT workspace root |
| `SGT_BIN` | `$SGT_ROOT/sgt` | Path to sgt binary |

## Features

- **Dense cockpit shell** — Single-page JARVIS-style HUD with command pulse, alert center, worker roster, rig matrix, topology radar, and dispatch console
- **Live tmux monitoring** — Mayor plus active worker panes subscribe on demand over WebSocket; focus mode and snapshot `peek` remain available
- **Acceptance blocker center** — Open blockers stay prominent with rig ownership, evidence snippets, and timestamps
- **Realtime WS** — Normalized `snapshot` pushes plus tmux stream events and live `sgt.log` updates; reconnect/backoff and stale states remain visible
- **Topology radar** — Canvas relationship view driven from normalized `topology` nodes/edges, with a clean fallback when WebGL is absent
- **Keyboard shortcuts** — `1..5` jump between shell sections, `c` toggles compact mode, `Esc` closes peek modal
- **Dispatch** — Sling polecats and dogs without leaving the shell

## Theme

The UI uses a dense **dark HUD / JARVIS-inspired** shell:
- display typography via Orbitron for cockpit headers
- IBM Plex Sans / Mono for readable dense operational content
- cyan, amber, lime, and red accents reserved for live state and alert severity

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
| GET | `/api/peek/:target` | Peek at tmux pane output |
| GET | `/api/logs?lines=N` | Tail sgt.log |
| GET | `/api/plan-state/:rig` | Repo plan-state JSON for one rig |
| POST | `/api/sling` | Dispatch a polecat `{rig, task, labels?, convoy?}` |
| POST | `/api/sling-dog` | Dispatch a dog `{rig, issue}` |
| WS | `/` | Real-time status/log stream plus snapshot + tmux stream events |

## WebSocket control messages

Client-to-server:

- `{"type":"snapshot/request"}` — request an immediate normalized snapshot
- `{"type":"stream/subscribe","target":"mayor"}` — start a live tmux stream for `mayor`, `mayor/<rig>`, `witness/<rig>`, `refinery/<rig>`, `crew/<name>`, `dog/<name>`, or a polecat name
- `{"type":"stream/unsubscribe","target":"mayor"}` — stop a live tmux stream

Server-to-client additions:

- `snapshot` — normalized cockpit state document
- `stream/open` — tmux stream became available
- `stream/data` — pane delta payload; `reset=true` means replace the current client buffer
- `stream/stale` — session became unavailable or stopped updating
- `stream/close` — stream worker closed after unsubscribe
