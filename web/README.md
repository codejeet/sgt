# SGT Web UI (Control Panel)

SGT Web UI is a small, dependency-light **real-time dashboard** for SGT (Simple GitHub Gastown): monitor agents/polecats, tail logs, and dispatch new work.

## Quick start

```bash
cd web
npm install
npm start
# open http://localhost:4747
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SGT_WEB_PORT` | `4747` | Server port |
| `SGT_ROOT` | `~/sgt` | SGT workspace root |
| `SGT_BIN` | `$SGT_ROOT/sgt` | Path to sgt binary |

## Features

- **Dashboard** — Live agent status (incl. mayor), polecat overview, merge queue summary
- **Polecats** — Active polecats with rig/issue/branch/PR; click to peek tmux output
- **Logs** — Tail `sgt.log` (auto-scroll + realtime updates)
- **Realtime WS** — Status push (poll every 3s) + log stream; reconnect/backoff + heartbeat + stale indicators
- **High density** — Compact mode toggle (`c`), multi-column rows, collapsible cards (persisted)
- **Keyboard shortcuts** — `1..7` switch panels, `c` toggles compact, `Esc` closes peek modal
- **Dispatch** — Sling polecats / dogs from the UI

## Theme

The UI uses a **dark triadic “modern color wheel” theme** with accents used sparingly:
- `--accentA` (Cyan) `#22D3EE`
- `--accentB` (Amber) `#F59E0B`
- `--accentC` (Lime) `#84CC16`

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
- **Frontend**: Single HTML page with vanilla JS.
- **Real-time**: WebSocket pushes status and log deltas; includes heartbeat + reconnect/backoff.

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/status` | Full parsed SGT status |
| GET | `/api/rigs` | List registered rigs |
| GET | `/api/polecats` | Polecat state files |
| GET | `/api/dogs` | Dog state files |
| GET | `/api/merge-queue` | Merge queue items |
| GET | `/api/peek/:target` | Peek at tmux pane output |
| GET | `/api/logs?lines=N` | Tail sgt.log |
| POST | `/api/sling` | Dispatch a polecat `{rig, task, labels?, convoy?}` |
| POST | `/api/sling-dog` | Dispatch a dog `{rig, issue}` |
| WS | `/` | Real-time status + log stream |
