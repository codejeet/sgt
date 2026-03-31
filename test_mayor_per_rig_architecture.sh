#!/usr/bin/env bash
# test_mayor_per_rig_architecture.sh — Verify optional per-rig mayor status + wake routing.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
SESSIONS_FILE="$TMP_ROOT/tmux-sessions"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"

cat > "$SESSIONS_FILE" <<'EOF'
sgt-president
sgt-mayor-alpha
sgt-mayor-beta
EOF

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail
sessions_file="${SGT_TEST_TMUX_SESSIONS_FILE:?missing SGT_TEST_TMUX_SESSIONS_FILE}"
cmd="${1:-}"
case "$cmd" in
  has-session)
    [[ "${2:-}" == "-t" ]] || exit 1
    grep -qx "${3:-}" "$sessions_file" 2>/dev/null
    ;;
  kill-session)
    [[ "${2:-}" == "-t" ]] || exit 1
    tmp="${sessions_file}.tmp.$$"
    grep -vx "${3:-}" "$sessions_file" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$sessions_file"
    ;;
  new-session)
    session=""
    while [[ $# -gt 0 ]]; do
      case "${1:-}" in
        -s)
          session="${2:-}"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    [[ -n "$session" ]] || exit 1
    printf '%s\n' "$session" >> "$sessions_file"
    ;;
  *)
    exit 1
    ;;
esac
TMUX
chmod +x "$MOCK_BIN/tmux"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
exit 0
GH
chmod +x "$MOCK_BIN/gh"

ENV_PREFIX=(
  env -i
  HOME="$HOME_DIR"
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin"
  TERM=dumb
  SGT_ROOT="$HOME_DIR/sgt"
  SGT_MAYOR_ARCHITECTURE=per-rig
  SGT_TEST_TMUX_SESSIONS_FILE="$SESSIONS_FILE"
)

"${ENV_PREFIX[@]}" bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs" "$SGT_ROOT/rigs/alpha" "$SGT_ROOT/rigs/beta"
printf "https://github.com/acme/alpha\n" > "$SGT_ROOT/.sgt/rigs/alpha"
printf "https://github.com/acme/beta\n" > "$SGT_ROOT/.sgt/rigs/beta"
mkdir -p "$SGT_ROOT/.sgt/mayors/alpha" "$SGT_ROOT/.sgt/mayors/beta"
' 

STATUS_JSON="$TMP_ROOT/status.json"
"${ENV_PREFIX[@]}" bash --noprofile --norc -c 'set -euo pipefail; sgt status --json > "$1"' bash "$STATUS_JSON"

python3 - "$STATUS_JSON" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
agents = data.get("agents", [])
names = {agent.get("name") for agent in agents}
for expected in ("mayor/alpha", "mayor/beta"):
    if expected not in names:
        raise SystemExit(f"missing {expected} in status agents: {sorted(names)}")
if "president" not in names:
    raise SystemExit(f"missing president in status agents: {sorted(names)}")
if "mayor" in names:
    raise SystemExit("legacy shared mayor entry unexpectedly present in per-rig status output")
president = next(agent for agent in agents if agent.get("name") == "president")
if president.get("role") != "president" or president.get("scope") != "global":
    raise SystemExit(f"unexpected president role/scope: {president}")
for expected in ("alpha", "beta"):
    mayor = next(agent for agent in agents if agent.get("name") == f"mayor/{expected}")
    if mayor.get("role") != "mayor" or mayor.get("scope") != "rig" or mayor.get("rig") != expected:
        raise SystemExit(f"unexpected mayor role/scope for {expected}: {mayor}")
PY

ALPHA_FIFO="$HOME_DIR/sgt/.sgt/mayors/alpha/mayor.fifo"
BETA_FIFO="$HOME_DIR/sgt/.sgt/mayors/beta/mayor.fifo"
ALPHA_OUT="$TMP_ROOT/alpha.out"
BETA_OUT="$TMP_ROOT/beta.out"
mkfifo "$ALPHA_FIFO" "$BETA_FIFO"

timeout 3 cat "$ALPHA_FIFO" > "$ALPHA_OUT" &
alpha_reader=$!
timeout 1 cat "$BETA_FIFO" > "$BETA_OUT" &
beta_reader=$!

"${ENV_PREFIX[@]}" bash --noprofile --norc -c 'set -euo pipefail; sgt wake-mayor "acceptance-blocker:alpha:test-blocker" >/dev/null'

wait "$alpha_reader"
wait "$beta_reader" || true

grep -qx 'acceptance-blocker:alpha:test-blocker' "$ALPHA_OUT" || {
  echo "expected alpha mayor fifo to receive targeted wake" >&2
  exit 1
}

if [[ -s "$BETA_OUT" ]]; then
  echo "expected beta mayor fifo to stay idle for alpha-targeted wake" >&2
  cat "$BETA_OUT" >&2
  exit 1
fi

: > "$ALPHA_OUT"
: > "$BETA_OUT"
timeout 3 cat "$ALPHA_FIFO" > "$ALPHA_OUT" &
alpha_reader=$!
timeout 1 cat "$BETA_FIFO" > "$BETA_OUT" &
beta_reader=$!

"${ENV_PREFIX[@]}" bash --noprofile --norc -c 'set -euo pipefail; sgt wake-mayor "president:alpha:actionable-rig-recheck" >/dev/null'

wait "$alpha_reader"
wait "$beta_reader" || true

grep -qx 'president:alpha:actionable-rig-recheck' "$ALPHA_OUT" || {
  echo "expected alpha mayor fifo to receive President-targeted wake" >&2
  exit 1
}

if [[ -s "$BETA_OUT" ]]; then
  echo "expected beta mayor fifo to stay idle for President-targeted alpha wake" >&2
  cat "$BETA_OUT" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
