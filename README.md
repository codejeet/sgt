# SGT (Simple GitHub Gastown)

SGT is a small, ops-first replacement for older “Gas Town” workflows.

- **Source of truth**: GitHub Issues + PRs
- **Execution**: tmux workers (polecats / dogs)
- **Operations**: `gh` CLI + a thin Bash/Node layer

## Web UI

The repo includes a minimal Web UI for realtime monitoring and dispatch:

- Docs / quick start: [`web/README.md`](web/README.md)
- Default URL: `http://localhost:4747`

## Why SGT exists (short)

Gas Town got bloated/fragile over time: “beads” were easy to break, and persistence/state became brittle.
SGT replaces that with a simpler mental model: GitHub Issues/PRs + tmux + `gh`.

## OpenClaw notifications

SGT can send delivered OpenClaw alerts when refinery reviews/merges a PR (and when mayor reports).

1. Create a notification config at `$SGT_ROOT/.sgt/notify.json` (default `~/sgt/.sgt/notify.json`).
2. Set routing options: `channel` (default `last`), optional `to`, optional `reply_to` (or `reply-to`).

Example:

```json
{
  "channel": "last",
  "to": "rigger",
  "reply_to": "sgt"
}
```

Test:

```bash
sgt mayor notify "OpenClaw notification test"
```

If `openclaw` is missing or the config is absent, notifications are skipped.
