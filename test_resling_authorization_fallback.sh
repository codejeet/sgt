#!/usr/bin/env bash
# test_resling_authorization_fallback.sh — Authorization checks should use REST/list fallbacks and classify read failures.

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

eval "$(extract_fn _one_line)"
eval "$(extract_fn _repo_owner_repo)"
eval "$(extract_fn _gh_issue_labels_live)"
eval "$(extract_fn _labels_contain_sgt_authorized)"
eval "$(extract_fn _label_list_one_line)"
eval "$(extract_fn _has_sgt_authorized)"

_workflow_backend_default() { printf '%s\n' 'github'; }
_forge_issue_labels() { return 0; }

gh() {
  if [[ "${1:-}" == "api" ]]; then
    printf '%s\n' 'sgt-authorized'
    printf '%s\n' 'plan'
    return 0
  fi
  echo "unexpected gh call: $*" >&2
  return 1
}

_has_sgt_authorized "https://github.com/acme/demo" "1300" || {
  echo "expected REST fallback to authorize issue" >&2
  exit 1
}
[[ "${_SGT_AUTHZ_LAST_REASON_CODE:-}" == "authorized" ]]
[[ "${_SGT_AUTHZ_LAST_DETAIL:-}" == *"github-rest"* ]]

gh() {
  if [[ "${1:-}" == "api" ]]; then
    echo "gh api backend unavailable" >&2
    return 1
  fi
  if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
    echo "gh issue list backend unavailable" >&2
    return 1
  fi
  echo "unexpected gh call: $*" >&2
  return 1
}

if _has_sgt_authorized "https://github.com/acme/demo" "1301"; then
  echo "expected read failure to block authorization" >&2
  exit 1
fi
[[ "${_SGT_AUTHZ_LAST_REASON_CODE:-}" == "label-read-failed" ]] || {
  echo "expected label-read-failed, got ${_SGT_AUTHZ_LAST_REASON_CODE:-unset}" >&2
  exit 1
}
[[ "${_SGT_AUTHZ_LAST_DETAIL:-}" == *"rest_error="* ]]
[[ "${_SGT_AUTHZ_LAST_DETAIL:-}" == *"list_error="* ]]

echo "ALL TESTS PASSED"
