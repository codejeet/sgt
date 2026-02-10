# Changelog

## Unreleased

- Mayor dispatch hardening: added a pre-dispatch live revalidation guard to `sgt sling` (mayor context) that atomically checks for open PRs and open `sgt-authorized` issues before issue creation.
- Mayor decision flow now skips dispatch when revalidation is dirty/stale and logs a clear reason in both terminal output and `~/.sgt/mayor-decisions.log`.
- Added regression coverage for stale snapshot races and no-duplicate dispatch behavior in `test_mayor_stale_dispatch_race.sh`.
- Mayor merge-queue snapshot freshness guard now performs one live revalidation pass before surfacing active issues in mayor `CLAUDE.md`; when stale and live diverge, live state deterministically wins and stale snapshot details are recorded in decision output.
- Mayor now emits explicit snapshot guard status lines containing `snapshot`, `live`, `chosen`, `source`, and `status` values for merge-queue decisions.
- Added regression coverage for stale-vs-live precedence in both directions (`stale=1/live=0`, `stale=0/live=1`) in `test_mayor_snapshot_freshness_guard.sh`.
- Mayor decision-log appends now use a lock + `fsync` durability path and route wake-dedupe skip logging through the same hardened append helper.
- Decision-log write failures are now non-fatal in mayor cycles, emit structured warning metadata, surface in `sgt status`, and notify Rigger at most once per cooldown window (`SGT_MAYOR_DECISION_LOG_ALERT_COOLDOWN`).
- Added/expanded regression coverage for concurrent mayor decision-log appends plus simulated write-error warning/notify cooldown behavior in `test_mayor_decision_log_durability.sh`.
- Refinery merge processing now retries transient `gh pr merge` failures with bounded attempts + jitter (`SGT_REFINERY_MERGE_MAX_ATTEMPTS`, `SGT_REFINERY_MERGE_RETRY_BASE_MS`, `SGT_REFINERY_MERGE_RETRY_JITTER_MS`), revalidates PR open/head state before each retry, and emits structured final-failure notify metadata including attempts/error class.
- Added refinery merge resilience regression coverage for transient-then-success and retry-time head-drift skip paths in `test_refinery_merge_retry_resilience.sh`.
- Refinery merge attempts now claim an idempotency key (`repo+PR+head SHA`) so duplicate PR-ready queue replays for the same head are explicitly skipped before merge/conflict/reject side effects run.
- Duplicate replay skips now emit explicit status output (`duplicate event ignored`) and structured activity log events (`REFINERY_DUPLICATE_SKIP ... key="owner/repo|pr=<n>|head=<sha>"`).
- Added regression coverage for duplicate PR-ready queue replay dedupe in `test_refinery_pr_ready_dedupe.sh` (also wired into `test_mayor_wake_replay_regression.sh`).
- Witness/refinery stale-close hard-stop: re-sling now enforces a final dispatch-instant gate that aborts spawn when the linked issue is not `OPEN` or when the source PR is not `OPEN`/`MERGEABLE`.
- Re-sling stale/final-gate skip logging now records structured forensic fields including `source_event_key` and `skip_reason` (`RESLING_SKIP_STALE`, `RESLING_SKIP_FINAL_GATE`).
- Expanded stale replay regression coverage in `test_refinery_stale_post_merge_redispatch.sh` to reproduce a late `CLOSED`/`MERGED` event replay where stale pre-check passes but dispatch-instant gate blocks spawn.
- `sgt status` now guards terminal-width initialization for non-TTY/narrow environments, avoids nounset crashes in PR-title truncation, and always exits `0` after rendering.
- Added regression coverage for status rendering with unset/narrow `COLUMNS` in `test_status_non_tty_term_cols_guard.sh`.
