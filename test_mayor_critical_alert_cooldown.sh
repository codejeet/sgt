#!/usr/bin/env bash
# test_mayor_critical_alert_cooldown.sh — Regression checks for mayor critical alert dedupe cooldown.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
mkdir -p "$HOME_DIR/sgt/.sgt"

bash -s "$SGT_SCRIPT" "$HOME_DIR" <<'BASH'
set -euo pipefail
SGT_SCRIPT="$1"
HOME_DIR="$2"
SGT_CONFIG="$HOME_DIR/sgt/.sgt"
SGT_MAYOR_CRITICAL_ALERT_STATE="$SGT_CONFIG/mayor-critical-alert.state"
SGT_MAYOR_CRITICAL_ALERT_COOLDOWN=120

extract_fn() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\) \\{" {in_fn=1}
    in_fn {print}
    in_fn && $0 == "}" {exit}
  ' "$SGT_SCRIPT"
}

eval "$(extract_fn _symptom_signature)"
eval "$(extract_fn _critical_alert_cooldown_secs)"
eval "$(extract_fn _mayor_critical_alert_signature)"
eval "$(extract_fn _mayor_should_notify_critical_alert)"

rig="demo"
repo="https://github.com/acme/demo"
issues_a=$'#12 prod outage in checkout\n#20 payment retries failing'
issues_b=$'#13 build broken on master'

if ! _mayor_should_notify_critical_alert "$rig" "$repo" "$issues_a"; then
  echo "expected first critical alert to notify" >&2
  exit 1
fi

if _mayor_should_notify_critical_alert "$rig" "$repo" "$issues_a"; then
  echo "expected duplicate critical alert to be suppressed during cooldown" >&2
  exit 1
fi

if ! _mayor_should_notify_critical_alert "$rig" "$repo" "$issues_b"; then
  echo "expected changed critical signature to notify immediately" >&2
  exit 1
fi

sig_b="$(_mayor_critical_alert_signature "$rig" "$repo" "$issues_b")"
printf '%s|%s|%s\n' "$rig" "$sig_b" "$(( $(date +%s) - 121 ))" > "$SGT_MAYOR_CRITICAL_ALERT_STATE"
if ! _mayor_should_notify_critical_alert "$rig" "$repo" "$issues_b"; then
  echo "expected cooldown expiry to allow re-notify" >&2
  exit 1
fi

SGT_MAYOR_CRITICAL_ALERT_COOLDOWN=0
if ! _mayor_should_notify_critical_alert "$rig" "$repo" "$issues_b"; then
  echo "expected cooldown=0 to disable suppression" >&2
  exit 1
fi
BASH

echo "ALL TESTS PASSED"
