#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

export HOME="$TMP_HOME"
export SGT_ROOT="$HOME/sgt"
export SGT_WORKFLOW_BACKEND=local
export SGT_AI_BACKEND=claude

MOCK_BIN="$HOME/mock-bin"
mkdir -p "$MOCK_BIN"
GH_CALLS="$HOME/gh.calls"

cat > "$MOCK_BIN/gh" <<'GH'
#!/usr/bin/env bash
echo "unexpected gh in local refinery test: $*" >> "$GH_CALLS"
exit 1
GH

cat > "$MOCK_BIN/claude" <<'CL'
#!/usr/bin/env bash
printf '%s\n' 'VERDICT: APPROVE'
CL

chmod +x "$MOCK_BIN/gh" "$MOCK_BIN/claude"
export PATH="$MOCK_BIN:$PATH"

cd "$ROOT_DIR"
"$ROOT_DIR/sgt" init >/dev/null
mkdir -p "$SGT_ROOT/.sgt/rigs" "$SGT_ROOT/rigs/demo"
printf '%s\n' 'https://github.com/acme/demo' > "$SGT_ROOT/.sgt/rigs/demo"

git -C "$SGT_ROOT/rigs/demo" init -b main >/dev/null
git -C "$SGT_ROOT/rigs/demo" config user.name tester
git -C "$SGT_ROOT/rigs/demo" config user.email tester@example.com
printf 'base\n' > "$SGT_ROOT/rigs/demo/file.txt"
git -C "$SGT_ROOT/rigs/demo" add file.txt
git -C "$SGT_ROOT/rigs/demo" commit -m base >/dev/null
git -C "$SGT_ROOT/rigs/demo" checkout -b feat >/dev/null
printf 'change\n' >> "$SGT_ROOT/rigs/demo/file.txt"
git -C "$SGT_ROOT/rigs/demo" commit -am feat >/dev/null
git -C "$SGT_ROOT/rigs/demo" checkout main >/dev/null

"$ROOT_DIR/sgt" forge issue create --repo https://github.com/acme/demo --title 'Issue one' --body 'body' --label sgt-authorized >/dev/null
"$ROOT_DIR/sgt" forge pr create --repo https://github.com/acme/demo --head feat --base main --title 'Local PR' --body 'Closes #1' >/dev/null
"$ROOT_DIR/sgt" forge pr checks set --repo https://github.com/acme/demo 1 --name build --state success >/dev/null

mkdir -p "$SGT_ROOT/.sgt/merge-queue"
cat > "$SGT_ROOT/.sgt/merge-queue/demo-pr1" <<'EOF'
POLECAT=demo-1234
RIG=demo
REPO=https://github.com/acme/demo
BRANCH=feat
ISSUE=1
PR=1
HEAD_SHA=
AUTO_MERGE=false
BACKEND=claude
TYPE=polecat
REVIEW_STATE=REVIEW_PENDING
REVIEW_UPDATED_AT=0
REVIEW_UNCLEAR_SINCE=
REVIEW_UNCLEAR_RETRY_COUNT=0
REVIEW_UNCLEAR_NEXT_RETRY_AT=0
REVIEW_UNCLEAR_LAST_REASON=
REVIEW_UNCLEAR_LAST_CLASS=
REVIEW_UNCLEAR_ESCALATED=0
REVIEW_UNCLEAR_ESCALATED_AT=
REVIEWED_HEAD_SHA=
REVIEWED_AT=
QUEUED=now
EOF

set +e
timeout 8 "$ROOT_DIR/sgt" _refinery demo > "$SGT_ROOT/refinery.out" 2>&1 &
pid=$!
for _ in 1 2 3 4 5; do
  fifo="$SGT_ROOT/.sgt/refinery-demo.fifo"
  if [[ -p "$fifo" ]]; then
    printf 'local-test\n' > "$fifo"
    break
  fi
  sleep 0.2
done
wait "$pid"
rc=$?
set -e

if [[ "$rc" != "0" && "$rc" != "124" ]]; then
  echo "unexpected refinery exit code: $rc" >&2
  cat "$SGT_ROOT/refinery.out" >&2
  exit 1
fi

grep -Fq 'PR #1 APPROVED' "$SGT_ROOT/refinery.out"
grep -Fq 'PR #1 merged successfully' "$SGT_ROOT/refinery.out"

view_out=$("$ROOT_DIR/sgt" forge pr view --repo https://github.com/acme/demo 1)
grep -Fq 'PR #1 [MERGED]' <<<"$view_out"

if [[ -s "$GH_CALLS" ]]; then
  echo "local refinery test unexpectedly invoked gh" >&2
  cat "$GH_CALLS" >&2
  exit 1
fi

echo "PASS: test_local_refinery_queue_happy_path"
