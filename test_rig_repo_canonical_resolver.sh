#!/usr/bin/env bash
# test_rig_repo_canonical_resolver.sh — Regression checks for canonical rig->repo resolution in open-issue/open-PR revalidation.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _one_line)"
eval "$(extract_fn _escape_quotes)"
eval "$(extract_fn _repo_owner_repo)"
eval "$(extract_fn _repo_owner_repo_strict)"
eval "$(extract_fn _repo_owner_repo_url)"
eval "$(extract_fn _rig_repo_resolve_error)"
eval "$(extract_fn _rig_repo_resolve_error_unpack)"
eval "$(extract_fn _resolve_rig_repo_canonical)"
eval "$(extract_fn _resling_live_issue_state)"
eval "$(extract_fn _resling_live_pr_state_mergeable)"
eval "$(extract_fn _resling_pre_dispatch_revalidate)"

export SGT_ROOT="$TMP_ROOT/root"
export SGT_CONFIG="$SGT_ROOT/.sgt"
export SGT_RIGS="$SGT_CONFIG/rigs"
export SGT_LOG="$SGT_ROOT/sgt.log"
mkdir -p "$SGT_RIGS"
printf 'https://github.com/acme/openclaw-agent-dm\n' > "$SGT_RIGS/oadm"

log_event() {
  printf '%s\n' "${1:-}" >> "$SGT_LOG"
}

rig_repo() {
  local rig="${1:-}"
  cat "$SGT_RIGS/$rig"
}

GH_CALLS_FILE="$TMP_ROOT/gh-calls"
GH_MODE_FILE="$TMP_ROOT/gh-mode"
printf '0\n' > "$GH_CALLS_FILE"
printf 'direct\n' > "$GH_MODE_FILE"
gh() {
  local calls
  local mode
  mode="$(cat "$GH_MODE_FILE")"
  calls="$(cat "$GH_CALLS_FILE")"
  calls=$((calls + 1))
  printf '%s\n' "$calls" > "$GH_CALLS_FILE"

  if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
    if [[ "$mode" == "issue-rest-fallback" || "$mode" == "mixed-rest-fallback" ]]; then
      return 1
    fi
    echo "OPEN"
    return 0
  fi
  if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
    if [[ "$mode" == "pr-rest-fallback" || "$mode" == "mixed-rest-fallback" ]]; then
      return 1
    fi
    echo "OPEN|MERGEABLE"
    return 0
  fi
  if [[ "${1:-}" == "api" ]]; then
    case "${2:-}" in
      repos/acme/openclaw-agent-dm/issues/12)
        echo "OPEN"
        return 0
        ;;
      repos/acme/openclaw-agent-dm/pulls/34)
        echo "OPEN|MERGEABLE"
        return 0
        ;;
    esac
  fi
  echo "mock gh unsupported: $*" >&2
  return 1
}

assert_ok() {
  local name="$1" mode="$2" rig="$3" repo="$4" issue="$5" source_pr="$6" expect_calls="$7"
  local out before after
  printf '%s\n' "$mode" > "$GH_MODE_FILE"
  before="$(cat "$GH_CALLS_FILE")"
  out="$(_resling_pre_dispatch_revalidate "$rig" "$repo" "$issue" "$source_pr" 2>&1 || true)"
  after="$(cat "$GH_CALLS_FILE")"
  if [[ -n "$out" ]]; then
    echo "FAIL: $name expected success, got: $out" >&2
    exit 1
  fi
  if [[ $((after - before)) -ne "$expect_calls" ]]; then
    echo "FAIL: $name expected gh calls delta=$expect_calls, got $((after - before))" >&2
    exit 1
  fi
  echo "PASS: $name"
}

assert_fail() {
  local name="$1" rig="$2" repo="$3" issue="$4" source_pr="$5" reason_substr="$6"
  local out before after
  before="$(cat "$GH_CALLS_FILE")"
  set +e
  out="$(_resling_pre_dispatch_revalidate "$rig" "$repo" "$issue" "$source_pr" 2>&1)"
  rc=$?
  set -e
  after="$(cat "$GH_CALLS_FILE")"
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: $name expected failure" >&2
    exit 1
  fi
  if [[ "$out" != *"$reason_substr"* ]]; then
    echo "FAIL: $name expected reason containing '$reason_substr', got: $out" >&2
    exit 1
  fi
  if [[ "$after" -ne "$before" ]]; then
    echo "FAIL: $name expected no gh calls on resolver failure" >&2
    exit 1
  fi
  echo "PASS: $name"
}

echo "=== rig repo canonical resolver regression ==="
assert_ok "canonical repo" "direct" "oadm" "https://github.com/acme/openclaw-agent-dm" "12" "34" "2"
assert_ok "alias owner/repo" "direct" "oadm" "acme/openclaw-agent-dm" "12" "34" "2"
assert_ok "issue state REST fallback" "issue-rest-fallback" "oadm" "https://github.com/acme/openclaw-agent-dm" "12" "34" "3"
assert_ok "source PR REST fallback" "pr-rest-fallback" "oadm" "https://github.com/acme/openclaw-agent-dm" "12" "34" "3"
assert_ok "issue and PR REST fallback" "mixed-rest-fallback" "oadm" "https://github.com/acme/openclaw-agent-dm" "12" "34" "4"
assert_fail "missing repo rejected" "oadm" "" "12" "34" "missing repo"
assert_fail "mismatched repo rejected" "oadm" "acme/other-repo" "12" "34" "repo mismatch"

if ! grep -q "RIG_REPO_RESOLVE_ERROR" "$SGT_LOG"; then
  echo "FAIL: expected resolver errors to emit telemetry events" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
