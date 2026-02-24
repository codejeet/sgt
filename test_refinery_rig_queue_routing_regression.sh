#!/usr/bin/env bash
# test_refinery_rig_queue_routing_regression.sh — Regression check for rig-specific merge-queue routing and stale terminal cleanup.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
MERGE_CALLS="$TMP_ROOT/merge-calls"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"
printf '0\n' > "$MERGE_CALLS"

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

k_scrapegoat="$(_merge_queue_repo_pr_key "scrapegoat" "https://github.com/acme/demo" "44")"
k_monorepo="$(_merge_queue_repo_pr_key "scrapegoat-monorepo" "https://github.com/acme/demo" "44")"

if [[ "$k_scrapegoat" == "$k_monorepo" ]]; then
  echo "expected rig-specific queue keys to differ for similarly prefixed rig names" >&2
  exit 1
fi
BASH

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

MERGE_CALLS_FILE="${SGT_MOCK_MERGE_CALLS:?missing SGT_MOCK_MERGE_CALLS}"

inc_file() {
  local path="$1"
  local n=0
  if [[ -s "$path" ]]; then
    n="$(cat "$path" 2>/dev/null || echo 0)"
  fi
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  n=$((n + 1))
  printf '%s\n' "$n" > "$path"
  echo "$n"
}

repo_from_args() {
  local repo=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        repo="${2:-}"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  printf '%s' "$repo"
}

json_from_args() {
  local json_fields=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json_fields="${2:-}"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  printf '%s' "$json_fields"
}

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  shift 2
  json_fields="$(json_from_args "$@")"
  case "$json_fields" in
    labels) echo "sgt-authorized" ;;
    *) echo "" ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  pr_number="${3:-}"
  shift 3
  repo="$(repo_from_args "$@")"
  json_fields="$(json_from_args "$@")"

  case "$repo|$pr_number|$json_fields" in
    *"|202|state") echo "OPEN" ;;
    *"|303|state") echo "MERGED" ;;
    *"scrapegoat|101|title") echo "Routing regression PR" ;;
    *"scrapegoat|101|state") echo "OPEN" ;;
    *"scrapegoat|101|mergeable") echo "MERGEABLE" ;;
    *"scrapegoat|101|mergeable,isDraft,mergeStateStatus") echo "MERGEABLE|false|CLEAN" ;;
    *"scrapegoat|101|state,headRefOid") echo "OPEN|head101" ;;
    *"scrapegoat|101|state,mergeCommit") echo "MERGED|merge101" ;;
    *) echo "" ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "checks" ]]; then
  echo "all checks pass"
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "diff" ]]; then
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "merge" ]]; then
  inc_file "$MERGE_CALLS_FILE" >/dev/null
  echo "merged"
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "comment" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  # Pretend branch still exists for post-merge verification branch probe.
  exit 0
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
chmod +x "$MOCK_BIN/gh"

env -i \
  HOME="$HOME_DIR" \
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm}" \
  SGT_ROOT="$HOME_DIR/sgt" \
  SGT_MOCK_MERGE_CALLS="$MERGE_CALLS" \
  bash --noprofile --norc -c '
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs"
printf "https://github.com/acme/scrapegoat\n" > "$SGT_ROOT/.sgt/rigs/scrapegoat"
printf "https://github.com/acme/scrapegoat-monorepo\n" > "$SGT_ROOT/.sgt/rigs/scrapegoat-monorepo"
mkdir -p "$SGT_ROOT/rigs/scrapegoat"

cat > "$SGT_ROOT/.sgt/merge-queue/scrapegoat-pr101" <<MQ
POLECAT=scrapegoat-pr101
RIG=scrapegoat
REPO=https://github.com/acme/scrapegoat
BRANCH=sgt/scrapegoat-pr101
ISSUE=11
PR=101
HEAD_SHA=head101
AUTO_MERGE=true
TYPE=polecat
QUEUED=$(date -Iseconds)
MQ

cat > "$SGT_ROOT/.sgt/merge-queue/scrapegoat-monorepo-pr202-open" <<MQ
POLECAT=scrapegoat-monorepo-pr202-open
RIG=scrapegoat-monorepo
REPO=https://github.com/acme/scrapegoat-monorepo
BRANCH=sgt/scrapegoat-monorepo-pr202
ISSUE=22
PR=202
HEAD_SHA=head202
AUTO_MERGE=true
TYPE=polecat
QUEUED=$(date -Iseconds)
MQ

cat > "$SGT_ROOT/.sgt/merge-queue/scrapegoat-monorepo-pr303-merged" <<MQ
POLECAT=scrapegoat-monorepo-pr303-merged
RIG=scrapegoat-monorepo
REPO=https://github.com/acme/scrapegoat-monorepo
BRANCH=sgt/scrapegoat-monorepo-pr303
ISSUE=33
PR=303
HEAD_SHA=head303
AUTO_MERGE=true
TYPE=polecat
QUEUED=$(date -Iseconds)
MQ

timeout 6 sgt _refinery scrapegoat > "$SGT_ROOT/refinery.out" 2>&1 &
pid=$!

for _ in $(seq 1 120); do
  fifo="$SGT_ROOT/.sgt/refinery-scrapegoat.fifo"
  if [[ -p "$fifo" ]]; then
    printf "test-wake\n" > "$fifo"
    break
  fi
  sleep 0.05
done

wait "$pid" || true
'

if [[ "$(cat "$MERGE_CALLS")" != "1" ]]; then
  echo "expected exactly one merge attempt for refinery/scrapegoat" >&2
  exit 1
fi

QUEUE_DIR="$HOME_DIR/sgt/.sgt/merge-queue"
if [[ ! -f "$QUEUE_DIR/scrapegoat-monorepo-pr202-open" ]]; then
  echo "expected open monorepo queue item to remain for refinery/scrapegoat-monorepo" >&2
  exit 1
fi

if [[ -f "$QUEUE_DIR/scrapegoat-monorepo-pr303-merged" ]]; then
  echo "expected stale merged monorepo queue item to be cleaned" >&2
  exit 1
fi

LOG_FILE="$HOME_DIR/sgt/sgt.log"
if ! grep -q 'REFINERY_QUEUE_CLEAN_STALE_TERMINAL queue=scrapegoat-monorepo-pr303-merged rig=scrapegoat queue_rig=scrapegoat-monorepo repo=acme/scrapegoat-monorepo pr=#303 pr_state=MERGED reason_code=rig-mismatch' "$LOG_FILE"; then
  echo "expected stale terminal cleanup telemetry for similarly prefixed rig queue item" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
