#!/usr/bin/env bash
# test_refinery_stale_queue_item.sh — Regression checks for refinery pre-merge stale queue revalidation.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
MERGE_MARKER="$TMP_ROOT/merge-called"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

MERGE_MARKER="${SGT_MOCK_MERGE_MARKER:?missing SGT_MOCK_MERGE_MARKER}"

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  echo "sgt-authorized"
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  shift 2
  json_fields=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json_fields="${2:-}"
        shift 2
        ;;
      --jq)
        shift 2
        ;;
      --repo)
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  case "$json_fields" in
    title)
      echo "Stale queue regression PR"
      ;;
    state)
      echo "OPEN"
      ;;
    mergeable)
      echo "MERGEABLE"
      ;;
    state,headRefOid)
      echo "OPEN|live999"
      ;;
    *)
      echo ""
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "checks" ]]; then
  echo "all checks pass"
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "diff" ]]; then
  # Empty diff -> refinery treats as pass and proceeds to pre-merge revalidation.
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "merge" ]]; then
  touch "$MERGE_MARKER"
  echo "merged"
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "comment" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  exit 0
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
chmod +x "$MOCK_BIN/gh"

ENV_PREFIX=(
  env -i
  HOME="$HOME_DIR"
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin"
  TERM="${TERM:-xterm}"
  SGT_ROOT="$HOME_DIR/sgt"
  SGT_MOCK_MERGE_MARKER="$MERGE_MARKER"
)

"${ENV_PREFIX[@]}" bash --noprofile --norc -c '
set -euo pipefail

sgt init >/dev/null
mkdir -p "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"

cat > "$SGT_ROOT/.sgt/merge-queue/test-pr123" <<MQ
POLECAT=test-pr123
RIG=test
REPO=https://github.com/acme/demo
BRANCH=sgt/test-pr123
ISSUE=77
PR=123
HEAD_SHA=queued111
AUTO_MERGE=true
TYPE=polecat
QUEUED=$(date -Iseconds)
MQ

timeout 6 sgt _refinery test > "$SGT_ROOT/refinery.out" 2>&1 &
pid=$!

for _ in $(seq 1 120); do
  fifo="$SGT_ROOT/.sgt/refinery-test.fifo"
  if [[ -p "$fifo" ]]; then
    printf "test-wake\n" > "$fifo"
    break
  fi
  sleep 0.05
done

wait "$pid" || true
'

if [[ -f "$MERGE_MARKER" ]]; then
  echo "expected refinery to skip merge on stale queue head SHA drift, but merge was attempted" >&2
  exit 1
fi

OUT_FILE="$HOME_DIR/sgt/refinery.out"
if ! grep -q 'pre-merge revalidation drift — skipping' "$OUT_FILE"; then
  echo "expected refinery output to report pre-merge drift skip" >&2
  exit 1
fi

LOG_FILE="$HOME_DIR/sgt/sgt.log"
if ! grep -q 'REFINERY_PREMERGE_SKIP pr=#123' "$LOG_FILE"; then
  echo "expected activity log entry for pre-merge skip" >&2
  exit 1
fi

QUEUE_FILE="$HOME_DIR/sgt/.sgt/merge-queue/test-pr123"
if ! grep -q '^HEAD_SHA=live999$' "$QUEUE_FILE"; then
  echo "expected queue HEAD_SHA to refresh to live head after drift" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
