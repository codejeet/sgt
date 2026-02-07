# SGT AI Backends (Claude vs Codex)

SGT can run its agents and reviewers using either **Claude Code** or the **Codex CLI**.

## Configure default backend

SGT reads settings from:

1. `SGT_AI_BACKEND` environment variable
2. `~/sgt/.sgt/settings.env` (created on `sgt init`)

Example:

```bash
# One-off for a command
SGT_AI_BACKEND=codex sgt sling myrig "Do something"

# Or edit:
$EDITOR ~/sgt/.sgt/settings.env
# set: SGT_AI_BACKEND=codex
```

Supported values:
- `claude` (default)
- `codex`

## Per-command override

Use `--backend` to override the backend for a specific dispatch:

```bash
sgt sling myrig "Implement X" --backend codex
sgt dog   myrig "Research Y"  --backend codex
```

## Notes

- Color output is enabled only when stdout is a TTY. Set `NO_COLOR=1` to force-disable.
- You must have the corresponding CLI installed and authenticated (`claude` or `codex`).
