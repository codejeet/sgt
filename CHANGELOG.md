# Changelog

## Unreleased

- Mayor dispatch hardening: added a pre-dispatch live revalidation guard to `sgt sling` (mayor context) that atomically checks for open PRs and open `sgt-authorized` issues before issue creation.
- Mayor decision flow now skips dispatch when revalidation is dirty/stale and logs a clear reason in both terminal output and `~/.sgt/mayor-decisions.log`.
- Added regression coverage for stale snapshot races and no-duplicate dispatch behavior in `test_mayor_stale_dispatch_race.sh`.
- Mayor merge-queue snapshot freshness guard now performs one live revalidation pass before surfacing active issues in mayor `CLAUDE.md`; when stale and live diverge, live state deterministically wins and stale snapshot details are recorded in decision output.
- Mayor now emits explicit snapshot guard status lines containing `snapshot`, `live`, `chosen`, `source`, and `status` values for merge-queue decisions.
- Added regression coverage for stale-vs-live precedence in both directions (`stale=1/live=0`, `stale=0/live=1`) in `test_mayor_snapshot_freshness_guard.sh`.
