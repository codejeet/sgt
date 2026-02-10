#!/usr/bin/env bash
# test_mayor_stale_dispatch_race.sh — Regression checks for mayor stale-snapshot pre-dispatch revalidation.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mockbin"
MOCK_STATE="$TMP_ROOT/issues.json"
MODE_FILE="$TMP_ROOT/mode"
mkdir -p "$HOME_DIR/.local/bin" "$MOCK_BIN"
cp "$SGT_SCRIPT" "$HOME_DIR/.local/bin/sgt"
chmod +x "$HOME_DIR/.local/bin/sgt"
printf '[]\n' > "$MOCK_STATE"
printf 'clean_then_dirty\n' > "$MODE_FILE"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${SGT_MOCK_GH_STATE:?missing SGT_MOCK_GH_STATE}"
MODE_FILE="${SGT_MOCK_MODE_FILE:?missing SGT_MOCK_MODE_FILE}"

if [[ "${1:-}" == "label" && "${2:-}" == "create" ]]; then
  exit 0
fi

if [[ "${1:-}" == "api" && "${2:-}" == "graphql" ]]; then
  mode="$(cat "$MODE_FILE")"
  if [[ "$mode" == "dirty" ]]; then
    echo "1|1"
  else
    echo "0|0"
  fi
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  mode="$(cat "$MODE_FILE")"
  if [[ "$mode" == "clean_then_dirty" ]]; then
    printf 'dirty\n' > "$MODE_FILE"
  fi

  python3 - "$STATE_FILE" <<'PY'
import json
import re
import sys

state_file = sys.argv[1]
issues = json.load(open(state_file, "r", encoding="utf-8"))

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
  SGT_MOCK_MODE_FILE="$MODE_FILE"
  SGT_ROOT="$HOME_DIR/sgt"
  SGT_MAYOR_DISPATCH_COOLDOWN=3600
)

"${ENV_PREFIX[@]}" bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
mkdir -p "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"

# Race case: duplicate-check snapshot is clean, revalidation snapshot flips dirty before dispatch.
SGT_MAYOR_DISPATCH_REVALIDATE=1 sgt sling test "Stale snapshot regression task" --label high >/tmp/sgt-race-1.out

# Clean case: allow one dispatch.
printf "clean\n" > "$SGT_MOCK_MODE_FILE"
SGT_MAYOR_DISPATCH_REVALIDATE=1 sgt sling test "Stale snapshot regression task" --label high >/tmp/sgt-race-2.out

# Duplicate check: should be suppressed (no second issue create).
SGT_MAYOR_DISPATCH_REVALIDATE=1 sgt sling test "Stale snapshot regression task" --label high >/tmp/sgt-race-3.out
'

python3 - "$MOCK_STATE" <<'PY'
import json
import sys

issues = json.load(open(sys.argv[1], "r", encoding="utf-8"))
if len(issues) != 1:
    raise SystemExit(f"expected exactly one created issue after stale-skip + one clean dispatch + duplicate suppression, got {len(issues)}")
PY

MAYOR_LOG="$HOME_DIR/sgt/.sgt/mayor-decisions.log"
if [[ ! -f "$MAYOR_LOG" ]]; then
  echo "expected mayor-decisions.log to be written for stale-state skip" >&2
  exit 1
fi

if ! grep -q 'MAYOR DISPATCH SKIP (stale-state)' "$MAYOR_LOG"; then
  echo "expected stale-state skip entry in mayor decision log" >&2
  exit 1
fi

if ! grep -q 'live state dirty: open_prs=1 open_authorized_issues=1' "$MAYOR_LOG"; then
  echo "expected reasoned stale-state details in mayor decision log" >&2
  exit 1
fi

echo "ALL TESTS PASSED"
