#!/usr/bin/env bash
# test_mayor_notify_scope_compat.sh — Scoped mayor notify should inherit rig routing/state without explicit notify_rig.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
OPENCLAW_LOG="$TMP_ROOT/openclaw.log"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"

cat > "$MOCK_BIN/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${OPENCLAW_LOG:?missing OPENCLAW_LOG}"
printf '{"delivered":true,"deliveryStatus":"delivered"}\n'
EOF
chmod +x "$MOCK_BIN/openclaw"

cat > "$MOCK_BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$MOCK_BIN/gh"

env -i \
  HOME="$HOME_DIR" \
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  TERM=dumb \
  OPENCLAW_LOG="$OPENCLAW_LOG" \
  SGT_ROOT="$HOME_DIR/sgt" \
  SGT_MAYOR_ARCHITECTURE=per-rig \
  SGT_MAYOR_SCOPE_RIG=alpha \
  bash --noprofile --norc -c '
    set -euo pipefail
    sgt init >/dev/null
    mkdir -p "$SGT_ROOT/.sgt/mayors/alpha" "$SGT_ROOT/.sgt/rig-config" "$SGT_ROOT/rigs/alpha"
    printf "https://github.com/acme/alpha\n" > "$SGT_ROOT/.sgt/rigs/alpha"
    cat > "$SGT_ROOT/.sgt/notify.json" <<JSON
{"agent":"default-agent","channel":"last"}
JSON
    cat > "$SGT_ROOT/.sgt/rig-config/alpha.json" <<JSON
{"notify_agent":"alpha-agent"}
JSON
    sgt mayor notify "scoped notify compatibility" >/dev/null
  '

grep -q -- '--agent alpha-agent' "$OPENCLAW_LOG" || {
  echo "expected scoped notify to use alpha rig notify agent" >&2
  cat "$OPENCLAW_LOG" >&2
  exit 1
}

find "$HOME_DIR/sgt/.sgt/mayors/alpha/mayor-notify-receipts" -type f | grep -q . || {
  echo "expected scoped notify receipt under alpha mayor scope" >&2
  exit 1
}

if [[ -d "$HOME_DIR/sgt/.sgt/mayor-notify-receipts" ]] && find "$HOME_DIR/sgt/.sgt/mayor-notify-receipts" -type f | grep -q .; then
  echo "expected scoped notify to avoid shared mayor receipt path" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
