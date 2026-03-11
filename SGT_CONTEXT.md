# SGT Project Context — sgt

Shared durable context for agents working on this rig.

Use this file for project-wide memory that should survive across polecats, dogs, and crew.

Useful commands:
- sgt context add sgt "<note>" — append a durable note
- sgt context search sgt "<query>" — semantic search over prior context
- sgt context index sgt — rebuild the embedding index

## Notes

## 2026-03-10
- 2026-03-10T05:40:56+01:00 — Implement shared per-rig SGT_CONTEXT.md memory plus CLI commands: sgt context add/search/index/path. Semantic search should use OpenAI Embeddings API, default model text-embedding-3-small, and persist local indexes under ~/.sgt/context/<rig>/index.json. Handle missing OPENAI_API_KEY and missing python gracefully.
- 2026-03-10T05:40:56+01:00 — Update spawned-agent instructions and docs so polecats, dogs, crew, CI-fix flows, and mayor-facing docs read SGT_CONTEXT.md before work, use sgt context search when helpful, and append durable shared notes with sgt context add before task completion when useful.
- 2026-03-10T05:51:12+01:00 — Shared memory now lives in repo-local SGT_CONTEXT.md; spawned polecat/dog/crew/CI-fix workspaces materialize or copy that file, and embedding indexes persist under ~/.sgt/context/<rig>/index.json with explicit missing-OPENAI_API_KEY failures for index/search.

## 2026-03-11
- 2026-03-11T11:31:38+01:00 — 2026-03-11T00:00:00Z — Added durable acceptance blockers via 'sgt create blocker' / 'sgt blocker resolve'. Mayor now treats open blockers as unresolved acceptance state, suppresses idle-green all-clear, and re-invokes follow-up when a blocker exists with no open issues, PRs, polecats, or pending plan requests.
- 2026-03-11T11:39:05+01:00 — Repo plans now support completion_condition plus acceptance status in SGT_PLAN.json; plan-state persists completion.rollup/status, and mayor treats tasks-exhausted-awaiting-acceptance as unresolved work instead of all-clear.
