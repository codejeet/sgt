#!/usr/bin/env bash
# test_local_forge_rigs.sh — Validate local forge features against the configured rigs using disposable clones.

set -euo pipefail

SGT_BIN="${SGT_BIN:-/usr/local/bin/sgt}"
REAL_SGT_ROOT="${REAL_SGT_ROOT:-$HOME/sgt}"
[[ -x "$SGT_BIN" ]] || { echo "missing installed sgt at $SGT_BIN" >&2; exit 1; }
[[ -d "$REAL_SGT_ROOT/.sgt/rigs" ]] || { echo "missing rig inventory at $REAL_SGT_ROOT/.sgt/rigs" >&2; exit 1; }

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
TMP_SGT_ROOT="$TMP_HOME/sgt"
MOCK_BIN="$TMP_HOME/mock-bin"
GH_CALLS="$TMP_HOME/gh.calls"
mkdir -p "$MOCK_BIN" "$TMP_SGT_ROOT/.sgt/rigs" "$TMP_SGT_ROOT/rigs"

cat > "$MOCK_BIN/gh" <<GH
#!/usr/bin/env bash
echo "unexpected gh call: \$*" >> "$GH_CALLS"
exit 1
GH

cat > "$MOCK_BIN/codex" <<'CODEX'
#!/usr/bin/env bash
sleep 2
printf '%s\n' 'mock codex complete'
exit 0
CODEX
chmod +x "$MOCK_BIN/gh" "$MOCK_BIN/codex"

run_sgt() {
  env -i \
    HOME="$TMP_HOME" \
    SGT_ROOT="$TMP_SGT_ROOT" \
    PATH="$MOCK_BIN:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    SGT_WORKFLOW_BACKEND=local \
    SGT_FORGE_BACKEND=local \
    SGT_AI_BACKEND=codex \
    "$SGT_BIN" "$@"
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if grep -Fq "$needle" <<<"$haystack"; then
    echo "PASS: $label"
  else
    echo "FAIL: $label" >&2
    echo "expected to find: $needle" >&2
    echo "--- output ---" >&2
    printf '%s\n' "$haystack" >&2
    exit 1
  fi
}

run_sgt init >/dev/null

mapfile -t RIG_FILES < <(find "$REAL_SGT_ROOT/.sgt/rigs" -maxdepth 1 -type f | sort)
[[ "${#RIG_FILES[@]}" -gt 0 ]] || { echo "no configured rigs" >&2; exit 1; }

for rig_file in "${RIG_FILES[@]}"; do
  rig="$(basename "$rig_file")"
  repo_url="$(cat "$rig_file")"
  src_repo="$REAL_SGT_ROOT/rigs/$rig"
  dest_repo="$TMP_SGT_ROOT/rigs/$rig"
  [[ -d "$src_repo/.git" ]] || { echo "missing git repo for rig $rig at $src_repo" >&2; exit 1; }
  printf '%s\n' "$repo_url" > "$TMP_SGT_ROOT/.sgt/rigs/$rig"
  git clone "$src_repo" "$dest_repo" >/dev/null 2>&1
  git -C "$dest_repo" config user.name sgt >/dev/null
  git -C "$dest_repo" config user.email sgt@local >/dev/null

done

for rig_file in "${RIG_FILES[@]}"; do
  rig="$(basename "$rig_file")"
  repo_url="$(cat "$rig_file")"
  repo_dir="$TMP_SGT_ROOT/rigs/$rig"
  echo "=== rig: $rig ==="

  label_name="local-smoke-$rig"
  run_sgt forge label create --repo "$repo_url" "$label_name" >/dev/null
  label_list="$(run_sgt forge label list --repo "$repo_url")"
  assert_contains "$rig label created" "$label_list" "$label_name|"

  issue_title="Rig smoke issue $rig"
  issue_url="$(run_sgt forge issue create --repo "$repo_url" --title "$issue_title" --body "local rig smoke" --label sgt-authorized --label "$label_name")"
  issue_id="$(printf '%s\n' "$issue_url" | grep -oE '/issues/[0-9]+' | grep -oE '[0-9]+')"
  [[ -n "$issue_id" ]] || { echo "FAIL: missing issue id for $rig" >&2; exit 1; }
  issue_view="$(run_sgt forge issue view --repo "$repo_url" "$issue_id")"
  assert_contains "$rig issue created" "$issue_view" "Issue #$issue_id [OPEN]"
  run_sgt forge issue comment --repo "$repo_url" "$issue_id" "rig comment $rig" >/dev/null
  issue_view2="$(run_sgt forge issue view --repo "$repo_url" "$issue_id")"
  assert_contains "$rig issue comment" "$issue_view2" "rig comment $rig"

  base_ref="$(git -C "$repo_dir" symbolic-ref --short HEAD)"
  feature_branch="sgt/local-forge-$rig"
  smoke_file="LOCAL_FORGE_${rig}_SMOKE.txt"
  git -C "$repo_dir" checkout -b "$feature_branch" >/dev/null 2>&1
  printf 'ok\n' > "$repo_dir/$smoke_file"
  git -C "$repo_dir" add "$smoke_file"
  git -C "$repo_dir" commit -m "local forge smoke $rig" >/dev/null 2>&1

  pr_title="Local forge PR $rig"
  pr_url="$(run_sgt forge pr create --repo "$repo_url" --head "$feature_branch" --base "$base_ref" --title "$pr_title" --body "Closes #$issue_id")"
  pr_id="$(printf '%s\n' "$pr_url" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+')"
  [[ -n "$pr_id" ]] || { echo "FAIL: missing pr id for $rig" >&2; exit 1; }
  pr_list="$(run_sgt forge pr list --repo "$repo_url" --state open)"
  assert_contains "$rig pr listed" "$pr_list" "#$pr_id [OPEN] $pr_title"
  pr_view="$(run_sgt forge pr view --repo "$repo_url" "$pr_id")"
  assert_contains "$rig pr view" "$pr_view" "Head: $feature_branch"
  pr_diff="$(run_sgt forge pr diff --repo "$repo_url" "$pr_id")"
  assert_contains "$rig pr diff" "$pr_diff" "+ok"
  run_sgt forge pr comment --repo "$repo_url" "$pr_id" "ready $rig" >/dev/null
  run_sgt forge pr review --repo "$repo_url" "$pr_id" --state APPROVE --body "approved $rig" >/dev/null
  run_sgt forge pr checks set --repo "$repo_url" "$pr_id" --name build --state success --started-at 2026-04-02T00:00:00Z --finished-at 2026-04-02T00:01:00Z >/dev/null
  checks_out="$(run_sgt forge pr checks list --repo "$repo_url" "$pr_id")"
  assert_contains "$rig pr checks" "$checks_out" $'build\tSUCCESS\t2026-04-02T00:00:00Z\t2026-04-02T00:01:00Z'

  merge_out="$(run_sgt forge pr merge --repo "$repo_url" "$pr_id")"
  [[ -n "$merge_out" ]] || { echo "FAIL: empty merge output for $rig" >&2; exit 1; }
  merged_list="$(run_sgt forge pr list --repo "$repo_url" --state merged)"
  assert_contains "$rig pr merged" "$merged_list" "#$pr_id [MERGED] $pr_title"
  issue_view_after="$(run_sgt forge issue view --repo "$repo_url" "$issue_id")"
  assert_contains "$rig linked issue closed" "$issue_view_after" "Issue #$issue_id [CLOSED]"

  before_count="$(find "$TMP_SGT_ROOT/.sgt/polecats" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
  run_sgt sling "$rig" "SMOKE TEST $rig: create LOCAL_RIG_SMOKE_$rig.txt with ok" --backend codex >/dev/null
  after_count="$(find "$TMP_SGT_ROOT/.sgt/polecats" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$after_count" -le "$before_count" ]]; then
    echo "FAIL: sling did not create polecat state for $rig" >&2
    exit 1
  fi
  latest_polecat="$(find "$TMP_SGT_ROOT/.sgt/polecats" -maxdepth 1 -type f -name "${rig}-*" | sort | tail -n 1 | xargs -r basename)"
  [[ -n "$latest_polecat" ]] || { echo "FAIL: missing latest polecat for $rig" >&2; exit 1; }
  run_sgt nuke "$latest_polecat" >/dev/null
  echo "PASS: $rig sling smoke"

done

if [[ -s "$GH_CALLS" ]]; then
  echo "FAIL: local forge rig test unexpectedly invoked gh" >&2
  cat "$GH_CALLS" >&2
  exit 1
fi

echo "PASS: local forge rigs matrix"
