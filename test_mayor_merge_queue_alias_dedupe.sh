#!/usr/bin/env bash
# test_mayor_merge_queue_alias_dedupe.sh — Regression checks for repo+PR queue-key alias dedupe.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

bash -s "$SGT_SCRIPT" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _repo_owner_repo)"
eval "$(extract_fn _merge_queue_repo_pr_key)"
eval "$(extract_fn _merge_queue_repo_pr_key_id)"
eval "$(extract_fn _merge_queue_find_file_by_repo_pr)"
eval "$(extract_fn _merge_queue_claim_repo_pr)"
eval "$(extract_fn _merge_queue_release_repo_pr)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SGT_CONFIG="$TMP_ROOT/.sgt"
mkdir -p "$SGT_CONFIG/merge-queue"

existing_alias="$SGT_CONFIG/merge-queue/sgt-691e731c"
new_alias="$SGT_CONFIG/merge-queue/sgt-pr84"

cat > "$existing_alias" <<'MQ'
POLECAT=sgt-691e731c
RIG=sgt
REPO=https://github.com/acme/demo
BRANCH=sgt/sgt-691e731c
ISSUE=84
PR=84
HEAD_SHA=abc123
TYPE=polecat
AUTO_MERGE=true
QUEUED=2026-02-10T00:00:00Z
MQ

if _merge_queue_claim_repo_pr "https://github.com/acme/demo" "84" "$new_alias" "sgt-pr84"; then
  echo "expected alias duplicate claim to be rejected for same repo+PR key" >&2
  exit 1
fi

if [[ "${_MERGE_QUEUE_DUPLICATE_QUEUE_FILE:-}" != "$existing_alias" ]]; then
  echo "expected duplicate pointer to existing alias queue file" >&2
  echo "got: ${_MERGE_QUEUE_DUPLICATE_QUEUE_FILE:-<empty>}" >&2
  exit 1
fi

if [[ ! -f "${_MERGE_QUEUE_PR_KEY_FILE:-}" ]]; then
  echo "expected repo+PR key file to exist for duplicate alias fence" >&2
  exit 1
fi

if ! grep -q "^QUEUE_FILE=$existing_alias$" "${_MERGE_QUEUE_PR_KEY_FILE}"; then
  echo "expected queue key file to map to existing alias queue file" >&2
  exit 1
fi

_merge_queue_release_repo_pr "https://github.com/acme/demo" "84"
rm -f "$existing_alias"

if ! _merge_queue_claim_repo_pr "https://github.com/acme/demo" "84" "$new_alias" "sgt-pr84"; then
  echo "expected claim to succeed after queue cleanup release" >&2
  exit 1
fi

if [[ "${_MERGE_QUEUE_DUPLICATE_QUEUE_FILE:-}" != "" ]]; then
  echo "expected no duplicate pointer after successful claim" >&2
  exit 1
fi
BASH

if ! grep -q 'MERGE_QUEUE_DUPLICATE_SKIP actor=mayor' "$SGT_SCRIPT"; then
  echo "expected mayor duplicate-skip observability log event" >&2
  exit 1
fi

if ! grep -q 'MERGE_QUEUE_DUPLICATE_SKIP actor=witness' "$SGT_SCRIPT"; then
  echo "expected witness duplicate-skip observability log event" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
