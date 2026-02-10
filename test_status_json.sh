#!/usr/bin/env bash
# test_status_json.sh — validates machine-readable `sgt status --json` output and stale prune behavior.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"

TMUX_ACTIVE_FILE="$TMP_ROOT/tmux-active"
echo "0" > "$TMUX_ACTIVE_FILE"

cat > "$MOCK_BIN/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail
active_file="${SGT_TEST_TMUX_ACTIVE_FILE:?missing SGT_TEST_TMUX_ACTIVE_FILE}"
if [[ "${1:-}" == "has-session" ]]; then
  if [[ -f "$active_file" ]] && [[ "$(cat "$active_file")" == "1" ]]; then
    exit 0
  fi
  exit 1
fi
if [[ "${1:-}" == "kill-session" ]]; then
  echo "0" > "$active_file"
  exit 0
fi
exit 1
TMUX
chmod +x "$MOCK_BIN/tmux"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

args=" $* "
pr_state="${SGT_TEST_PR_STATE:-OPEN}"
pr_number="${SGT_TEST_PR_NUMBER:-123}"

if [[ "$args" == *" pr list "* ]] && [[ "$args" == *" --json number,state,title "* ]]; then
  if [[ "$pr_state" == "NONE" ]]; then
    echo ""
  else
    printf '%s\t%s\t%s\n' "$pr_number" "$pr_state" "Mock PR $pr_state"
  fi
  exit 0
fi

if [[ "$args" == *" issue view "* ]] && [[ "$args" == *" --json state "* ]]; then
  echo "OPEN"
  exit 0
fi

exit 0
GH
chmod +x "$MOCK_BIN/gh"

ENV_PREFIX=(
  env -i
  HOME="$HOME_DIR"
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin"
  TERM=dumb
  SGT_ROOT="$HOME_DIR/sgt"
  SGT_TEST_TMUX_ACTIVE_FILE="$TMUX_ACTIVE_FILE"
)

"${ENV_PREFIX[@]}" bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs" "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"
cat > "$SGT_ROOT/.sgt/polecats/p1" <<STATE
RIG=test
REPO=https://github.com/acme/demo
ISSUE=42
BRANCH=sgt/p1
WORKTREE=$SGT_ROOT/polecats/p1
SESSION=sgt-p1
DEFAULT_BRANCH=master
STATE
'

JSON_OUT="$TMP_ROOT/status.json"
JSON_ERR="$TMP_ROOT/status.err"

"${ENV_PREFIX[@]}" SGT_TEST_PR_STATE="OPEN" bash --noprofile --norc -c '
set -euo pipefail
sgt status --json > "$1" 2> "$2"
' bash "$JSON_OUT" "$JSON_ERR"

if [[ -s "$JSON_ERR" ]]; then
  echo "expected no stderr from status --json" >&2
  cat "$JSON_ERR" >&2
  exit 1
fi

python3 - "$JSON_OUT" <<'PY'
import json
import sys
p = sys.argv[1]
with open(p, "r", encoding="utf-8") as f:
    data = json.load(f)

for key in ["agents", "dogs", "crew", "merge_queue", "polecats", "summary"]:
    if key not in data:
        raise SystemExit(f"missing top-level key: {key}")

if data["summary"].get("polecat_count") != 1:
    raise SystemExit(f"expected polecat_count=1, got {data['summary'].get('polecat_count')}")

if not any(a.get("name") == "daemon" for a in data["agents"]):
    raise SystemExit("missing daemon agent entry")
if not any(a.get("name") == "mayor" for a in data["agents"]):
    raise SystemExit("missing mayor agent entry")

polecats = data["polecats"]
if len(polecats) != 1:
    raise SystemExit(f"expected one polecat entry, got {len(polecats)}")
p = polecats[0]
if p.get("name") != "p1":
    raise SystemExit(f"unexpected polecat name: {p.get('name')}")
if p.get("status") != "dead":
    raise SystemExit(f"expected dead polecat in test, got {p.get('status')}")
pr = p.get("pr", {})
if str(pr.get("number")) != "123" or pr.get("state") != "OPEN":
    raise SystemExit(f"unexpected PR metadata: {pr}")
PY

"${ENV_PREFIX[@]}" SGT_TEST_PR_STATE="MERGED" bash --noprofile --norc -c '
set -euo pipefail
sgt status --json > "$SGT_ROOT/status-pruned.json" 2> "$SGT_ROOT/status-pruned.err"
if [[ -s "$SGT_ROOT/status-pruned.err" ]]; then
  echo "expected no stderr during JSON prune run" >&2
  cat "$SGT_ROOT/status-pruned.err" >&2
  exit 1
fi
if [[ -f "$SGT_ROOT/.sgt/polecats/p1" ]]; then
  echo "expected merged dead polecat to be pruned during JSON status" >&2
  exit 1
fi
python3 - "$SGT_ROOT/status-pruned.json" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
if data.get("summary", {}).get("polecat_count") != 0:
    raise SystemExit("expected no tracked polecats after prune")
if data.get("polecats") != []:
    raise SystemExit("expected empty polecats array after prune")
PY
'

echo "ALL TESTS PASSED"
