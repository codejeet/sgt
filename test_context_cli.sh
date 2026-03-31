#!/usr/bin/env bash
# test_context_cli.sh — Validate context CLI help/syntax, missing-key failures, and malformed-index recovery.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SGT_SCRIPT="$REPO_ROOT/sgt"
FAIL=0

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
mkdir -p "$TMP_HOME/.local/bin"
cp "$SGT_SCRIPT" "$TMP_HOME/.local/bin/sgt"
chmod +x "$TMP_HOME/.local/bin/sgt"
MOCK_PYTHONPATH="$TMP_HOME/mock-python"
mkdir -p "$MOCK_PYTHONPATH"

cat >"$MOCK_PYTHONPATH/sitecustomize.py" <<'PY'
import io
import json
import os
import urllib.error
import urllib.request


class _MockResponse:
    def __init__(self, body):
        self._body = body

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False


def _embed_text(text):
    total = sum(ord(ch) for ch in text)
    length = len(text)
    return [float(length or 1), float((total % 97) + 1), float((total % 53) + 1)]


_real_urlopen = urllib.request.urlopen


def _mock_urlopen(req, timeout=60):
    url = getattr(req, "full_url", "")
    if url == "https://api.openai.com/v1/embeddings":
        payload = json.loads(req.data.decode("utf-8"))
        input_value = payload.get("input")
        if isinstance(input_value, list):
            texts = input_value
        else:
            texts = [input_value]
        log_path = os.environ.get("MOCK_EMBED_LOG")
        if log_path:
            with open(log_path, "a", encoding="utf-8") as fh:
                fh.write(f"{len(texts)}\n")
        if os.environ.get("MOCK_EMBED_FORCE_ERROR") == "1":
            body = b'{"error":{"message":"mock embeddings failed"}}'
            raise urllib.error.HTTPError(url, 400, "Bad Request", hdrs=None, fp=io.BytesIO(body))
        if len(texts) > 2048:
            body = b'{"error":{"message":"Invalid input: array length must be 2048 or less."}}'
            raise urllib.error.HTTPError(url, 400, "Bad Request", hdrs=None, fp=io.BytesIO(body))
        body = {
            "data": [{"embedding": _embed_text(text or "")} for text in texts],
        }
        return _MockResponse(json.dumps(body).encode("utf-8"))
    return _real_urlopen(req, timeout=timeout)


urllib.request.urlopen = _mock_urlopen
PY

run_cmd() {
  local command="$1"
  local out_file="$2"
  local err_file="$3"
  local rc_file="$4"
  local rc

  set +e
  env -i \
    HOME="$TMP_HOME" \
    PATH="$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    bash --noprofile --norc -c "$command" >"$out_file" 2>"$err_file"
  rc=$?
  set -e
  echo "$rc" >"$rc_file"
}

run_cmd_mock_embeddings() {
  local command="$1"
  local out_file="$2"
  local err_file="$3"
  local rc_file="$4"
  local rc

  set +e
  env -i \
    HOME="$TMP_HOME" \
    PATH="$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    OPENAI_API_KEY="test-key" \
    PYTHONPATH="$MOCK_PYTHONPATH" \
    bash --noprofile --norc -c "$command" >"$out_file" 2>"$err_file"
  rc=$?
  set -e
  echo "$rc" >"$rc_file"
}

run_cmd_mock_embeddings_env() {
  local extra_env="$1"
  local command="$2"
  local out_file="$3"
  local err_file="$4"
  local rc_file="$5"
  local rc

  set +e
  env -i \
    HOME="$TMP_HOME" \
    PATH="$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TERM="${TERM:-xterm}" \
    OPENAI_API_KEY="test-key" \
    PYTHONPATH="$MOCK_PYTHONPATH" \
    $extra_env \
    bash --noprofile --norc -c "$command" >"$out_file" 2>"$err_file"
  rc=$?
  set -e
  echo "$rc" >"$rc_file"
}

check_equals() {
  local name="$1"
  local got="$2"
  local want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (expected '$want', got '$got')"
    FAIL=1
  fi
}

check_file_contains() {
  local name="$1"
  local file="$2"
  local pattern="$3"
  if grep -qE "$pattern" "$file"; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
    cat "$file"
    FAIL=1
  fi
}

BASE_OUT="$(mktemp)"
BASE_ERR="$(mktemp)"
BASE_RC="$(mktemp)"
HELPFLAG_OUT="$(mktemp)"
HELPFLAG_ERR="$(mktemp)"
HELPFLAG_RC="$(mktemp)"
HELPWORD_OUT="$(mktemp)"
HELPWORD_ERR="$(mktemp)"
HELPWORD_RC="$(mktemp)"
BAD_OUT="$(mktemp)"
BAD_ERR="$(mktemp)"
BAD_RC="$(mktemp)"
PATH_OUT="$(mktemp)"
PATH_ERR="$(mktemp)"
PATH_RC="$(mktemp)"
INDEX_OUT="$(mktemp)"
INDEX_ERR="$(mktemp)"
INDEX_RC="$(mktemp)"
SEARCH_OUT="$(mktemp)"
SEARCH_ERR="$(mktemp)"
SEARCH_RC="$(mktemp)"
RECOVER_OUT="$(mktemp)"
RECOVER_ERR="$(mktemp)"
RECOVER_RC="$(mktemp)"
BATCH_OUT="$(mktemp)"
BATCH_ERR="$(mktemp)"
BATCH_RC="$(mktemp)"
BATCH_LOG="$(mktemp)"
HTTPFAIL_OUT="$(mktemp)"
HTTPFAIL_ERR="$(mktemp)"
HTTPFAIL_RC="$(mktemp)"
ADDWARN_OUT="$(mktemp)"
ADDWARN_ERR="$(mktemp)"
ADDWARN_RC="$(mktemp)"

trap 'rm -rf "$TMP_HOME" "$BASE_OUT" "$BASE_ERR" "$BASE_RC" "$HELPFLAG_OUT" "$HELPFLAG_ERR" "$HELPFLAG_RC" "$HELPWORD_OUT" "$HELPWORD_ERR" "$HELPWORD_RC" "$BAD_OUT" "$BAD_ERR" "$BAD_RC" "$PATH_OUT" "$PATH_ERR" "$PATH_RC" "$INDEX_OUT" "$INDEX_ERR" "$INDEX_RC" "$SEARCH_OUT" "$SEARCH_ERR" "$SEARCH_RC" "$RECOVER_OUT" "$RECOVER_ERR" "$RECOVER_RC" "$BATCH_OUT" "$BATCH_ERR" "$BATCH_RC" "$BATCH_LOG" "$HTTPFAIL_OUT" "$HTTPFAIL_ERR" "$HTTPFAIL_RC" "$ADDWARN_OUT" "$ADDWARN_ERR" "$ADDWARN_RC"' EXIT

run_cmd "sgt context" "$BASE_OUT" "$BASE_ERR" "$BASE_RC"
run_cmd "sgt context --help" "$HELPFLAG_OUT" "$HELPFLAG_ERR" "$HELPFLAG_RC"
run_cmd "sgt context help" "$HELPWORD_OUT" "$HELPWORD_ERR" "$HELPWORD_RC"
run_cmd "sgt context nope" "$BAD_OUT" "$BAD_ERR" "$BAD_RC"

check_equals "sgt context exits 0" "$(cat "$BASE_RC")" "0"
check_equals "sgt context --help exits 0" "$(cat "$HELPFLAG_RC")" "0"
check_equals "sgt context help exits 0" "$(cat "$HELPWORD_RC")" "0"
check_equals "sgt context writes no stderr" "$(wc -c <"$BASE_ERR" | tr -d ' ')" "0"
check_equals "sgt context --help writes no stderr" "$(wc -c <"$HELPFLAG_ERR" | tr -d ' ')" "0"
check_equals "sgt context help writes no stderr" "$(wc -c <"$HELPWORD_ERR" | tr -d ' ')" "0"

if diff -u "$BASE_OUT" "$HELPFLAG_OUT" >/dev/null; then
  echo "PASS: sgt context and sgt context --help output match"
else
  echo "FAIL: sgt context and sgt context --help output differ"
  diff -u "$BASE_OUT" "$HELPFLAG_OUT" || true
  FAIL=1
fi

if diff -u "$BASE_OUT" "$HELPWORD_OUT" >/dev/null; then
  echo "PASS: sgt context and sgt context help output match"
else
  echo "FAIL: sgt context and sgt context help output differ"
  diff -u "$BASE_OUT" "$HELPWORD_OUT" || true
  FAIL=1
fi

check_file_contains "context usage includes synopsis" "$BASE_OUT" '^Usage: sgt context <command> \[args\]$'
check_file_contains "context help includes path command" "$BASE_OUT" '^  path <rig>[[:space:]]+Print the repo-local shared memory path$'
check_file_contains "unknown context subcommand exits 1" "$BAD_RC" '^1$'
check_equals "unknown context subcommand writes no stdout" "$(wc -c <"$BAD_OUT" | tr -d ' ')" "0"
check_file_contains "unknown context subcommand error is explicit" "$BAD_ERR" '^sgt: unknown context command: nope \(try: help, path, add, index, search\)$'

run_cmd "sgt init >/dev/null && mkdir -p \"\$HOME/sgt/.sgt/rigs\" \"\$HOME/sgt/rigs/demo\" && printf '%s\n' 'https://github.com/acme/demo' > \"\$HOME/sgt/.sgt/rigs/demo\" && sgt context path demo" "$PATH_OUT" "$PATH_ERR" "$PATH_RC"

check_equals "sgt context path exits 0" "$(cat "$PATH_RC")" "0"
check_equals "sgt context path writes no stderr" "$(wc -c <"$PATH_ERR" | tr -d ' ')" "0"
check_file_contains "context path points at repo-local file" "$PATH_OUT" '/sgt/rigs/demo/SGT_CONTEXT\.md$'

run_cmd "sgt init >/dev/null && mkdir -p \"\$HOME/sgt/.sgt/rigs\" \"\$HOME/sgt/rigs/demo\" && printf '%s\n' 'https://github.com/acme/demo' > \"\$HOME/sgt/.sgt/rigs/demo\" && sgt context add demo 'remember the watchdog cooldown'" "$INDEX_OUT" "$INDEX_ERR" "$INDEX_RC"
check_equals "sgt context add exits 0 without OPENAI_API_KEY" "$(cat "$INDEX_RC")" "0"

run_cmd "sgt context index demo" "$INDEX_OUT" "$INDEX_ERR" "$INDEX_RC"
run_cmd "sgt context search demo 'watchdog cooldown'" "$SEARCH_OUT" "$SEARCH_ERR" "$SEARCH_RC"

check_file_contains "context index without OPENAI_API_KEY exits 1" "$INDEX_RC" '^1$'
check_file_contains "context search without OPENAI_API_KEY exits 1" "$SEARCH_RC" '^1$'
check_equals "context index without key writes no stdout" "$(wc -c <"$INDEX_OUT" | tr -d ' ')" "0"
check_equals "context search without key writes no stdout" "$(wc -c <"$SEARCH_OUT" | tr -d ' ')" "0"
check_file_contains "context index missing key error is explicit" "$INDEX_ERR" "^sgt: OPENAI_API_KEY is required for 'sgt context index' and 'sgt context search'$"
check_file_contains "context search missing key error is explicit" "$SEARCH_ERR" "^sgt: OPENAI_API_KEY is required for 'sgt context index' and 'sgt context search'$"

run_cmd_mock_embeddings "sgt init >/dev/null && mkdir -p \"\$HOME/sgt/.sgt/rigs\" \"\$HOME/sgt/rigs/demo\" && printf '%s\n' 'https://github.com/acme/demo' > \"\$HOME/sgt/.sgt/rigs/demo\" && sgt context add demo 'remember the watchdog cooldown' >/dev/null && sgt context index demo >/dev/null && printf '%s' '}{broken-json' >> \"\$HOME/sgt/.sgt/context/demo/index.json\" && sgt context search demo 'watchdog cooldown'" "$RECOVER_OUT" "$RECOVER_ERR" "$RECOVER_RC"

check_file_contains "context search recovers from malformed index exits 0" "$RECOVER_RC" '^0$'
check_file_contains "context search recovery warns explicitly" "$RECOVER_ERR" "^⚠ context index for rig 'demo' was malformed; rebuilding$"
check_file_contains "context search recovery returns the matching entry" "$RECOVER_OUT" 'watchdog cooldown'

run_cmd_mock_embeddings_env "MOCK_EMBED_LOG=$BATCH_LOG" "sgt init >/dev/null && mkdir -p \"\$HOME/sgt/.sgt/rigs\" \"\$HOME/sgt/rigs/demo\" && printf '%s\n' 'https://github.com/acme/demo' > \"\$HOME/sgt/.sgt/rigs/demo\" && python3 -c \"from pathlib import Path; ctx = Path.home() / 'sgt' / 'rigs' / 'demo' / 'SGT_CONTEXT.md'; ctx.parent.mkdir(parents=True, exist_ok=True); fh = ctx.open('w', encoding='utf-8'); fh.write('# SGT Project Context — demo\\n\\n## Notes\\n\\n## 2026-03-31\\n'); [fh.write(f'- 2026-03-31T00:00:{i % 60:02d}Z — note {i:04d}\\n') for i in range(2051)]; fh.close()\" && sgt context index demo >/dev/null && python3 -c \"import json; from pathlib import Path; index_path = Path.home() / 'sgt' / '.sgt' / 'context' / 'demo' / 'index.json'; doc = json.load(index_path.open('r', encoding='utf-8')); entries = doc.get('entries') or []; assert len(entries) == 2051, len(entries); assert entries[0]['text'].endswith('note 0000'), entries[0]['text']; assert entries[2048]['text'].endswith('note 2048'), entries[2048]['text']; assert entries[-1]['text'].endswith('note 2050'), entries[-1]['text']; print('verified-order')\"" "$BATCH_OUT" "$BATCH_ERR" "$BATCH_RC"

check_file_contains "context index batches oversized corpora exits 0" "$BATCH_RC" '^0$'
check_file_contains "context index batching preserves entry order" "$BATCH_OUT" 'verified-order'
check_file_contains "context index batching uses a 512-sized chunk" "$BATCH_LOG" '^512$'
check_file_contains "context index batching uses a final small chunk" "$BATCH_LOG" '^3$'

run_cmd_mock_embeddings_env "MOCK_EMBED_FORCE_ERROR=1" "sgt init >/dev/null && mkdir -p \"\$HOME/sgt/.sgt/rigs\" \"\$HOME/sgt/rigs/demo\" && printf '%s\n' 'https://github.com/acme/demo' > \"\$HOME/sgt/.sgt/rigs/demo\" && sgt context add demo 'remember the watchdog cooldown' >/dev/null && sgt context index demo" "$HTTPFAIL_OUT" "$HTTPFAIL_ERR" "$HTTPFAIL_RC"

check_file_contains "context index HTTP failure exits 1" "$HTTPFAIL_RC" '^1$'
check_file_contains "context index HTTP failure prints response body" "$HTTPFAIL_ERR" 'mock embeddings failed'

run_cmd_mock_embeddings_env "MOCK_EMBED_FORCE_ERROR=1" "sgt init >/dev/null && mkdir -p \"\$HOME/sgt/.sgt/rigs\" \"\$HOME/sgt/rigs/demo\" && printf '%s\n' 'https://github.com/acme/demo' > \"\$HOME/sgt/.sgt/rigs/demo\" && sgt context add demo 'remember the watchdog cooldown'" "$ADDWARN_OUT" "$ADDWARN_ERR" "$ADDWARN_RC"

check_file_contains "context add still exits 0 when opportunistic reindex fails" "$ADDWARN_RC" '^0$'
check_file_contains "context add surfaces opportunistic reindex warning" "$ADDWARN_ERR" "opportunistic context reindex failed for rig 'demo'"

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi

echo "ALL TESTS PASSED"
