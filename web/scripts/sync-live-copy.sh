#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: web/scripts/sync-live-copy.sh [--dry-run] [target_dir]

Sync the repo-tracked web/ app into the live served copy.

Environment:
  SGT_WEB_LIVE_DIR   Override the default live target (/root/sgt/web)

Examples:
  web/scripts/sync-live-copy.sh
  web/scripts/sync-live-copy.sh --dry-run
  SGT_WEB_LIVE_DIR=/srv/sgt/web web/scripts/sync-live-copy.sh
EOF
}

dry_run=0
target_arg=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -n "$target_arg" ]]; then
        echo "error: too many positional arguments" >&2
        usage >&2
        exit 1
      fi
      target_arg="$1"
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_DIR="${target_arg:-${SGT_WEB_LIVE_DIR:-/root/sgt/web}}"

if ! command -v rsync >/dev/null 2>&1; then
  echo "error: rsync is required" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "error: npm is required" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"

rsync_args=(
  -a
  --delete
  --exclude=node_modules/
  --exclude=webui.log
  --exclude=.DS_Store
)

if [[ "$dry_run" -eq 1 ]]; then
  rsync_args+=(--dry-run --itemize-changes)
fi

echo "Syncing ${WEB_DIR}/ -> ${TARGET_DIR}/"
rsync "${rsync_args[@]}" "${WEB_DIR}/" "${TARGET_DIR}/"

if [[ "$dry_run" -eq 1 ]]; then
  echo "Dry run complete; skipped npm install."
  exit 0
fi

echo "Installing runtime dependencies in ${TARGET_DIR}"
npm install --prefix "$TARGET_DIR"

echo "Live web copy synced to ${TARGET_DIR}"
