# SGT Web UI Control Panel

Real-time dashboard for monitoring and managing SGT agents, workers, rigs, logs, and dispatching tasks.

## Setup

```bash
cd web
npm install
npm start
```

The UI will be available at `http://localhost:4747`.

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SGT_WEB_PORT` | `4747` | Server port |
| `SGT_ROOT` | `~/sgt` | SGT workspace root |
| `SGT_BIN` | `$SGT_ROOT/sgt` | Path to sgt binary |

## Features

- **Dashboard** — Live agent status, polecat overview, merge queue summary
- **Polecats panel** — All active polecats with status, rig, issue, branch, PR info. Click to peek at tmux output
- **Dogs panel** — Active dogs with status
- **Rigs** — Registered rigs with repo links, witness/refinery status, polecat counts
- **Sling** — Dispatch new polecats (pick rig, enter task, optional labels/convoy) or dogs
- **Log viewer** — Real-time tailing of sgt.log with auto-scroll
- **Merge Queue** — Pending PRs in refinery queue

## Architecture

- **Backend**: Node.js + Express. Reads SGT state from `~/.sgt/` directory and shells out to `sgt` CLI for actions.
- **Frontend**: Single HTML page with vanilla JS. Dark theme, monospace design.
- **Real-time**: WebSocket connection pushes status updates (polled every 3s) and new log lines (file watcher).

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
