#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP_HOME=$(mktemp -d)
trap 'rm -rf "$TMP_HOME"' EXIT

export HOME="$TMP_HOME"
export SGT_ROOT="$HOME/sgt"
export SGT_WORKFLOW_BACKEND=local
MOCK_BIN="$HOME/mock-bin"
mkdir -p "$MOCK_BIN" "$SGT_ROOT/.sgt/rigs"
GH_CALLS="$HOME/gh.calls"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
echo "unexpected gh call: $*" >> "$GH_CALLS"
exit 1
GH
chmod +x "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"
export GH_CALLS

REPO="https://github.com/acme/demo"
printf '%s\n' "$REPO" > "$SGT_ROOT/.sgt/rigs/demo"

"$ROOT_DIR/sgt" init >/dev/null
"$ROOT_DIR/sgt" label init demo >/dev/null

label_out=$("$ROOT_DIR/sgt" forge label list --repo "$REPO")
grep -Fq 'sgt-authorized|Authorized for sgt processing' <<<"$label_out"

if [[ -s "$GH_CALLS" ]]; then
  echo "label init unexpectedly invoked gh" >&2
  cat "$GH_CALLS" >&2
  exit 1
fi

echo "PASS: test_label_init_local_backend"
