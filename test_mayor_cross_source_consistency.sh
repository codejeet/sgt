#!/usr/bin/env bash
# test_mayor_cross_source_consistency.sh — Regression checks for cross-source mayor snapshot/live consistency revalidation.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

run_case() {
  local case_name="$1"
  local snapshot_open_prs="$2"
  local snapshot_open_authorized="$3"
  local snapshot_open_polecats="$4"
  local snapshot_queue_count="$5"
  local expected_category="$6"

  local case_root="$TMP_ROOT/$case_name"
  local home_dir="$case_root/home"
  local mock_bin="$case_root/mockbin"
  local state_file="$case_root/issues.json"
  local snapshot_file="$case_root/snapshot.tsv"
  mkdir -p "$home_dir/.local/bin" "$mock_bin"
  cp "$SGT_SCRIPT" "$home_dir/.local/bin/sgt"
  chmod +x "$home_dir/.local/bin/sgt"
  printf '[]\n' > "$state_file"
  printf 'test\thttps://github.com/acme/demo\t%s\t%s\t%s\t%s\n' \
    "$snapshot_open_prs" "$snapshot_open_authorized" "$snapshot_open_polecats" "$snapshot_queue_count" > "$snapshot_file"

  cat > "$mock_bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${SGT_MOCK_GH_STATE:?missing SGT_MOCK_GH_STATE}"

if [[ "${1:-}" == "label" && "${2:-}" == "create" ]]; then
  exit 0
fi

if [[ "${1:-}" == "api" && "${2:-}" == "graphql" ]]; then
  echo "0|0"
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "create" ]]; then
  python3 - "$STATE_FILE" <<'PY'
import json
import sys

state_file = sys.argv[1]
with open(state_file, "r", encoding="utf-8") as f:
    issues = json.load(f)
issues.append({"created": True})
with open(state_file, "w", encoding="utf-8") as f:
    json.dump(issues, f)
print("https://github.com/acme/demo/issues/1")
PY
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "edit" ]]; then
  exit 0
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
  chmod +x "$mock_bin/gh"

  cat > "$mock_bin/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "fetch" || "${1:-}" == "symbolic-ref" ]]; then
  exit 0
fi
echo "mock git unsupported: $*" >&2
exit 1
GIT
  chmod +x "$mock_bin/git"

  cat > "$mock_bin/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi
if [[ "${1:-}" == "new-session" || "${1:-}" == "kill-session" ]]; then
  exit 0
fi
echo "mock tmux unsupported: $*" >&2
exit 1
TMUX
  chmod +x "$mock_bin/tmux"

  env -i \
    HOME="$home_dir" \
    PATH="$mock_bin:$home_dir/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    SGT_MOCK_GH_STATE="$state_file" \
    SGT_ROOT="$home_dir/sgt" \
    SGT_MAYOR_DISPATCH_REVALIDATE=1 \
    SGT_MAYOR_DISPATCH_SNAPSHOT_FILE="$snapshot_file" \
    bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
mkdir -p "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"
sgt sling test "Consistency mismatch regression task" --label high >/tmp/sgt-consistency.out
'

  python3 - "$state_file" <<'PY'
import json
import sys
issues = json.load(open(sys.argv[1], "r", encoding="utf-8"))
if issues:
    raise SystemExit(f"expected no issue creation on consistency mismatch, got {len(issues)} create(s)")
PY

  local mayor_log="$home_dir/sgt/.sgt/mayor-decisions.log"
  [[ -f "$mayor_log" ]] || {
    echo "expected mayor decision log for consistency mismatch case $case_name" >&2
    exit 1
  }
  grep -q 'MAYOR DISPATCH SKIP (consistency-mismatch)' "$mayor_log" || {
    echo "missing consistency-mismatch decision header for case $case_name" >&2
    exit 1
  }
  grep -q "mismatch_categories=${expected_category}" "$mayor_log" || {
    echo "missing mismatch category ${expected_category} for case $case_name" >&2
    exit 1
  }
  grep -q 'snapshot_summary=open_prs=' "$mayor_log" || {
    echo "missing snapshot summary in decision log for case $case_name" >&2
    exit 1
  }
  grep -q 'live_summary=open_prs=' "$mayor_log" || {
    echo "missing live summary in decision log for case $case_name" >&2
    exit 1
  }
  grep -q 'retry=next-mayor-cycle' "$mayor_log" || {
    echo "missing retry hint in decision log for case $case_name" >&2
    exit 1
  }
}

run_case "stale-merged-pr" "1" "0" "0" "0" "pr-state"
run_case "cleaned-polecat" "0" "0" "1" "0" "polecat-liveness"

echo "ALL TESTS PASSED"
