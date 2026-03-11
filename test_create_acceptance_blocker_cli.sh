#!/usr/bin/env bash
# test_create_acceptance_blocker_cli.sh — Regression coverage for durable acceptance blocker lifecycle.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/.local/bin"
cp "$SGT_SCRIPT" "$TMP_HOME/.local/bin/sgt"
chmod +x "$TMP_HOME/.local/bin/sgt"

OUT_FILE="$TMP_HOME/create-blocker.out"
ERR_FILE="$TMP_HOME/create-blocker.err"
LIST_FILE="$TMP_HOME/blocker-list.out"

env -i \
  HOME="$TMP_HOME" \
  PATH="$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm}" \
  bash --noprofile --norc <<'BASH' >"$OUT_FILE" 2>"$ERR_FILE"
set -euo pipefail

sgt init >/dev/null
mkdir -p "$HOME/sgt/.sgt/rigs" "$HOME/sgt/rigs/demo"
printf '%s\n' 'https://github.com/acme/demo' > "$HOME/sgt/.sgt/rigs/demo"

printf 'Verified acceptance still red on latest master\n\nSelected wallets remain empty after fresh ingest.\n' | \
  sgt create blocker demo --agent verifier-7 -
sgt blocker list demo
BASH

if [[ -s "$ERR_FILE" ]]; then
  cat "$ERR_FILE" >&2
  exit 1
fi

blocker_id="$(awk '/acceptance blocker recorded:/ {print $5; exit}' "$OUT_FILE")"
if [[ -z "$blocker_id" ]]; then
  echo "expected create blocker output to include blocker id" >&2
  cat "$OUT_FILE" >&2
  exit 1
fi

meta_file="$TMP_HOME/sgt/.sgt/acceptance-blockers/$blocker_id/blocker.env"
evidence_file="$TMP_HOME/sgt/.sgt/acceptance-blockers/$blocker_id/evidence.md"
context_file="$TMP_HOME/sgt/rigs/demo/SGT_CONTEXT.md"

[[ -f "$meta_file" ]] || { echo "missing blocker env file" >&2; exit 1; }
[[ -f "$evidence_file" ]] || { echo "missing blocker evidence file" >&2; exit 1; }
[[ -f "$context_file" ]] || { echo "missing rig context file" >&2; exit 1; }

grep -q '^STATUS=open$' "$meta_file" || { echo "expected blocker status=open" >&2; exit 1; }
grep -q '^REQUESTING_AGENT_ID=verifier-7$' "$meta_file" || { echo "expected reporter id in blocker env" >&2; exit 1; }
meta_title="$(bash --noprofile --norc -c "source '$meta_file'; printf '%s' \"\$TITLE\"")"
[[ "$meta_title" == "Verified acceptance still red on latest master" ]] || { echo "expected blocker title in blocker env" >&2; exit 1; }
grep -q 'Selected wallets remain empty after fresh ingest\.' "$evidence_file" || { echo "expected blocker evidence to be stored verbatim" >&2; exit 1; }
grep -q "Acceptance Blocker $blocker_id" "$context_file" || { echo "expected blocker section in SGT_CONTEXT.md" >&2; exit 1; }
grep -q 'verifier-7' "$context_file" || { echo "expected reporter id in SGT_CONTEXT.md" >&2; exit 1; }
grep -q "$blocker_id \[open\]" "$OUT_FILE" || { echo "expected blocker list to show open blocker" >&2; exit 1; }

env -i \
  HOME="$TMP_HOME" \
  PATH="$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm}" \
  bash --noprofile --norc -c "sgt blocker resolve $blocker_id --note 'Acceptance now passes on latest master'" >/dev/null

grep -q '^STATUS=resolved$' "$meta_file" || { echo "expected blocker status=resolved after resolve" >&2; exit 1; }
resolution_note="$(bash --noprofile --norc -c "source '$meta_file'; printf '%s' \"\${RESOLUTION_NOTE:-}\"")"
[[ "$resolution_note" == "Acceptance now passes on latest master" ]] || { echo "expected resolution note in blocker env" >&2; exit 1; }
grep -q 'Acceptance blocker '"$blocker_id"' resolved' "$context_file" || { echo "expected blocker resolution note in SGT_CONTEXT.md" >&2; exit 1; }

env -i \
  HOME="$TMP_HOME" \
  PATH="$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm}" \
  bash --noprofile --norc -c "sgt blocker list demo" >"$LIST_FILE"

grep -q 'no active acceptance blockers for demo' "$LIST_FILE" || { echo "expected resolved blocker to disappear from active list" >&2; exit 1; }

echo "ALL TESTS PASSED"
