# Changelog

## Unreleased

- Mayor dispatch hardening: added a pre-dispatch live revalidation guard to `sgt sling` (mayor context) that atomically checks for open PRs and open `sgt-authorized` issues before issue creation.
- Mayor decision flow now skips dispatch when revalidation is dirty/stale and logs a clear reason in both terminal output and `~/.sgt/mayor-decisions.log`.
- Added regression coverage for stale snapshot races and no-duplicate dispatch behavior in `test_mayor_stale_dispatch_race.sh`.
- Mayor decision-log appends now use an exclusive file lock plus `fsync` for atomic/durable writes under concurrent mayor cycles.
- Decision-log write failures are now non-fatal: mayor continues the cycle, emits structured warning events, updates warning status shown by `sgt status`, and sends at most one Rigger warning per cooldown window.
- Expanded `test_mayor_decision_log_durability.sh` to cover concurrent append integrity and simulated write-error cooldown behavior.
