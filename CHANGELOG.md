# Changelog

## Unreleased

- Mayor dispatch hardening: added a pre-dispatch live revalidation guard to `sgt sling` (mayor context) that atomically checks for open PRs and open `sgt-authorized` issues before issue creation.
- Mayor decision flow now skips dispatch when revalidation is dirty/stale and logs a clear reason in both terminal output and `~/.sgt/mayor-decisions.log`.
- Added regression coverage for stale snapshot races and no-duplicate dispatch behavior in `test_mayor_stale_dispatch_race.sh`.
