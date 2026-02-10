#!/usr/bin/env bash
# test_mayor_post_merge_dispatch_budget_gate.sh — Regression checks for mayor proactive dispatch parallel-budget gate.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
MOCK_STATE="$TMP_ROOT/issues.json"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"
printf '[]\n' > "$MOCK_STATE"

cat > "$MOCK_BIN/gh" <<'GH'
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
  python3 - "$STATE_FILE" <<'PY'
import json
import re
import sys

issues = json.load(open(sys.argv[1], "r", encoding="utf-8"))

def signature(title: str) -> str:
    out = title.lower()
    out = re.sub(r"[0-9]+", " num ", out)
    out = re.sub(r"[^a-z]+", " ", out)
    out = re.sub(r" +", " ", out).strip()
    return out

for issue in issues:
    labels = ",".join((lbl.get("name", "").lower() for lbl in issue.get("labels", [])))
    created = issue.get("createdAt", "")
    closed = issue.get("closedAt") or ""
    print(
        "\t".join(
            [
                str(issue.get("number", "")),
                issue.get("url", ""),
                issue.get("state", ""),
                signature(issue.get("title", "")),
                labels,
                created,
                closed,
            ]
        )
    )
PY
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "create" ]]; then
  shift 2
  title=""
  repo=""
  labels=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title)
        title="${2:-}"
        shift 2
        ;;
      --repo)
        repo="${2:-}"
        shift 2
        ;;
      --label)
        labels+=("${2:-}")
        shift 2
        ;;
      --body)
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  python3 - "$STATE_FILE" "$repo" "$title" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${labels[*]-}" <<'PY'
import json
import sys

state_file, repo, title, created_at, labels_flat = sys.argv[1:6]
labels = [x for x in labels_flat.split(" ") if x]

with open(state_file, "r", encoding="utf-8") as f:
    issues = json.load(f)

next_number = max([i.get("number", 0) for i in issues], default=0) + 1
owner_repo = repo.replace("https://github.com/", "")
url = f"https://github.com/{owner_repo}/issues/{next_number}"

issues.append(
    {
        "number": next_number,
        "title": title,
        "state": "OPEN",
        "url": url,
        "createdAt": created_at,
        "closedAt": None,
        "labels": [{"name": label} for label in labels],
    }
)

with open(state_file, "w", encoding="utf-8") as f:
    json.dump(issues, f)

print(url)
PY
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "edit" ]]; then
  exit 0
fi

echo "mock gh unsupported: $*" >&2
exit 1
GH
chmod +x "$MOCK_BIN/gh"

cat > "$MOCK_BIN/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-C" ]]; then
  shift 2
fi

case "${1:-}" in
  fetch)
    exit 0
    ;;
  symbolic-ref)
    echo "refs/remotes/origin/master"
    exit 0
    ;;
  worktree)
    if [[ "${2:-}" == "add" ]]; then
      mkdir -p "${5:-}"
      exit 0
    fi
    ;;
esac

echo "mock git unsupported: $*" >&2
exit 1
GIT
chmod +x "$MOCK_BIN/git"

cat > "$MOCK_BIN/tmux" <<'TMUX'
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
chmod +x "$MOCK_BIN/tmux"

ENV_PREFIX=(
  env -i
  HOME="$HOME_DIR"
  PATH="$MOCK_BIN:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin"
  TERM="${TERM:-xterm}"
  SGT_MOCK_GH_STATE="$MOCK_STATE"
  SGT_ROOT="$HOME_DIR/sgt"
  SGT_MAYOR_DISPATCH_COOLDOWN=3600
  SGT_MAYOR_DISPATCH_MAX_PARALLEL=1
)

"${ENV_PREFIX[@]}" bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
mkdir -p "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"

# Race-safe budget gate: local active polecat appears before proactive dispatch.
mkdir -p "$SGT_ROOT/.sgt/polecats"
cat > "$SGT_ROOT/.sgt/polecats/test-existing" <<EOF
RIG=test
REPO=https://github.com/acme/demo
EOF

SGT_MAYOR_DISPATCH_REVALIDATE=1 sgt sling test "Budget gate regression task" --label high >/tmp/sgt-budget-1.out

rm -f "$SGT_ROOT/.sgt/polecats/test-existing"
SGT_MAYOR_DISPATCH_REVALIDATE=1 sgt sling test "Budget gate regression task" --label high >/tmp/sgt-budget-2.out
'

python3 - "$MOCK_STATE" <<'PY'
import json
import sys

issues = json.load(open(sys.argv[1], "r", encoding="utf-8"))
if len(issues) != 1:
    raise SystemExit(f"expected exactly one created issue after budget-skip then clean dispatch, got {len(issues)}")
PY

MAYOR_LOG="$HOME_DIR/sgt/.sgt/mayor-decisions.log"
if [[ ! -f "$MAYOR_LOG" ]]; then
  echo "expected mayor-decisions.log to be written for budget skip" >&2
  exit 1
fi

if ! grep -q 'MAYOR DISPATCH SKIP (parallel-budget)' "$MAYOR_LOG"; then
  echo "expected parallel-budget skip entry in mayor decision log" >&2
  exit 1
fi

if ! grep -q 'reason_code=parallel-budget-exhausted' "$MAYOR_LOG"; then
  echo "expected reason_code=parallel-budget-exhausted in mayor decision log" >&2
  exit 1
fi

if ! grep -q 'open_polecats=1' "$MAYOR_LOG"; then
  echo "expected budget skip details to include open_polecats=1" >&2
  exit 1
fi

if ! grep -q 'MAYOR_DISPATCH_SKIP_BUDGET reason_code=parallel-budget-exhausted' "$HOME_DIR/sgt/sgt.log"; then
  echo "expected structured MAYOR_DISPATCH_SKIP_BUDGET event in activity log" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
