#!/usr/bin/env bash
# test_mayor_dispatch_idempotency.sh — Deterministic duplicate-dispatch guard checks.

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

if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
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
  SGT_ROOT="$HOME_DIR/sgt"
  SGT_MAYOR_DISPATCH_COOLDOWN=3600
)

"${ENV_PREFIX[@]}" bash --noprofile --norc -c '
set -euo pipefail
sgt init >/dev/null
mkdir -p "$SGT_ROOT/rigs/test"
printf "https://github.com/acme/demo\n" > "$SGT_ROOT/.sgt/rigs/test"

t1="Fix bash startup warning: here-document at line 14 delimited by end-of-file (wanted \`PY\`)"
t2="Fix bash startup warning: here-document at line 27 delimited by end-of-file (wanted \`PY\`)"
t3="Fix bash startup warning: unmatched quote in notify parser"

sgt sling test "$t1" --label high >/dev/null
sgt sling test "$t2" --label high >/dev/null
sgt sling test "$t3" --label high >/dev/null
'

python3 - "$MOCK_STATE" <<'PY'
import json
import sys

state_file = sys.argv[1]
issues = json.load(open(state_file, "r", encoding="utf-8"))

if len(issues) != 2:
    raise SystemExit(f"expected 2 issues after duplicate suppression + new incident, got {len(issues)}")

titles = [issue["title"] for issue in issues]
here_doc_hits = [title for title in titles if "here-document at line" in title]
if len(here_doc_hits) != 1:
    raise SystemExit(f"expected exactly one here-doc warning dispatch during cooldown, got {len(here_doc_hits)}")

if not any("unmatched quote in notify parser" in title for title in titles):
    raise SystemExit("expected genuinely new incident to dispatch")
PY

"${ENV_PREFIX[@]}" bash --noprofile --norc -c '
set -euo pipefail
t2="Fix bash startup warning: here-document at line 27 delimited by end-of-file (wanted \`PY\`)"
SGT_MAYOR_DISPATCH_COOLDOWN=0 sgt sling test "$t2" --label high >/dev/null
'

python3 - "$MOCK_STATE" <<'PY'
import json
import sys

state_file = sys.argv[1]
issues = json.load(open(state_file, "r", encoding="utf-8"))

if len(issues) != 3:
    raise SystemExit(f"expected 3 issues after cooldown override dispatch, got {len(issues)}")
PY

echo "ALL TESTS PASSED"
