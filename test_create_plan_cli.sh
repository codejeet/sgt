#!/usr/bin/env bash
# test_create_plan_cli.sh — Regression coverage for create-plan request storage and mayor clarification routing.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/.local/bin" "$TMP_HOME/mock-bin"
cp "$SGT_SCRIPT" "$TMP_HOME/.local/bin/sgt"
chmod +x "$TMP_HOME/.local/bin/sgt"

cat > "$TMP_HOME/mock-bin/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${OPENCLAW_CALLS_FILE:?missing OPENCLAW_CALLS_FILE}"
EOF
chmod +x "$TMP_HOME/mock-bin/openclaw"

OUT_FILE="$TMP_HOME/create-plan.out"
ERR_FILE="$TMP_HOME/create-plan.err"

env -i \
  HOME="$TMP_HOME" \
  PATH="$TMP_HOME/mock-bin:$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm}" \
  OPENCLAW_CALLS_FILE="$TMP_HOME/openclaw.calls" \
  bash --noprofile --norc <<'BASH' >"$OUT_FILE" 2>"$ERR_FILE"
set -euo pipefail

sgt init >/dev/null
mkdir -p "$HOME/sgt/.sgt/rigs" "$HOME/sgt/rigs/demo"
printf '%s\n' 'https://github.com/acme/demo' > "$HOME/sgt/.sgt/rigs/demo"
cat > "$HOME/sgt/.sgt/notify.json" <<'JSON'
{"agent":"mayor-bot","channel":"last","reply_to":"sgt-thread"}
JSON

printf 'Short spec\n\nNeed a durable plan.\n' | sgt create plan demo --agent requester-42 -
BASH

if [[ -s "$ERR_FILE" ]]; then
  cat "$ERR_FILE" >&2
  exit 1
fi

request_id="$(awk '/plan request recorded:/ {print $5; exit}' "$OUT_FILE")"
if [[ -z "$request_id" ]]; then
  echo "expected create plan output to include request id" >&2
  cat "$OUT_FILE" >&2
  exit 1
fi

request_env="$TMP_HOME/sgt/.sgt/plan-requests/$request_id/request.env"
prompt_file="$TMP_HOME/sgt/.sgt/plan-requests/$request_id/prompt.md"
context_file="$TMP_HOME/sgt/rigs/demo/SGT_CONTEXT.md"

[[ -f "$request_env" ]] || { echo "missing request env file" >&2; exit 1; }
[[ -f "$prompt_file" ]] || { echo "missing request prompt file" >&2; exit 1; }
[[ -f "$context_file" ]] || { echo "missing rig context file" >&2; exit 1; }

grep -q '^REQUESTING_AGENT_ID=requester-42$' "$request_env" || { echo "expected explicit requester id in request env" >&2; exit 1; }
grep -q '^STATUS=pending$' "$request_env" || { echo "expected pending status after create plan" >&2; exit 1; }
grep -q 'Need a durable plan\.' "$prompt_file" || { echo "expected prompt to be stored verbatim" >&2; exit 1; }
grep -q "Plan Request $request_id" "$context_file" || { echo "expected request section in SGT_CONTEXT.md" >&2; exit 1; }
grep -q 'requester-42' "$context_file" || { echo "expected requester id in SGT_CONTEXT.md" >&2; exit 1; }

env -i \
  HOME="$TMP_HOME" \
  PATH="$TMP_HOME/mock-bin:$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm}" \
  OPENCLAW_CALLS_FILE="$TMP_HOME/openclaw.calls" \
  bash --noprofile --norc -c "sgt mayor request ask $request_id 'What is the preferred rollout order?'" >/dev/null

grep -q -- '--to requester-42' "$TMP_HOME/openclaw.calls" || { echo "expected mayor ask to target requesting agent" >&2; exit 1; }
grep -q 'preferred rollout order' "$TMP_HOME/openclaw.calls" || { echo "expected mayor ask question in OpenClaw payload" >&2; exit 1; }
grep -q '^STATUS=needs-clarification$' "$request_env" || { echo "expected request status to flip to needs-clarification" >&2; exit 1; }

env -i \
  HOME="$TMP_HOME" \
  PATH="$TMP_HOME/mock-bin:$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm}" \
  bash --noprofile --norc -c "sgt mayor request complete $request_id" >/dev/null

grep -q '^STATUS=planned$' "$request_env" || { echo "expected request status to flip to planned" >&2; exit 1; }

echo "ALL TESTS PASSED"
