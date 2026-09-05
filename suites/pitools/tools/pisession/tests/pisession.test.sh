#!/usr/bin/env bash
# Behavior tests for pisession's Pi JSONL parser, picker, preview, and launch.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PISESSION="$HERE/../pisession"

if [ ! -f "$PISESSION" ]; then
  printf 'FAIL: missing pisession entrypoint: %s\n' "$PISESSION" >&2
  exit 1
fi

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1"
}
assert_eq() {
  if [ "$1" = "$2" ]; then ok; else bad "$3 (got [$1] want [$2])"; fi
}
assert_contains() {
  case "$1" in *"$2"*) ok ;; *) bad "$3 ([$1] lacks [$2])" ;; esac
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export PI_CODING_AGENT_DIR="$SANDBOX/agent"
SESSIONS_DIR="$PI_CODING_AGENT_DIR/sessions/--fixtures--"
LIVE_CWD="$SANDBOX/live project"
GONE_CWD="$SANDBOX/removed-project"
mkdir -p "$SESSIONS_DIR" "$LIVE_CWD"

live_id='11111111-1111-4111-8111-111111111111'
gone_id='22222222-2222-4222-8222-222222222222'
invalid_id='not-a-uuid'
live_session="$SESSIONS_DIR/2026-08-28T10-00-00-000Z_$live_id.jsonl"
gone_session="$SESSIONS_DIR/2026-08-28T09-00-00-000Z_$gone_id.jsonl"
invalid_session="$SESSIONS_DIR/invalid.jsonl"
missing_cwd_session="$SESSIONS_DIR/missing-cwd.jsonl"
not_session="$SESSIONS_DIR/export.jsonl"

cat >"$live_session" <<JSONL
{"type":"session","version":3,"id":"$live_id","timestamp":"2026-08-28T10:00:00.000Z","cwd":"$LIVE_CWD"}
{"type":"message","id":"a1b2c3d4","parentId":null,"timestamp":"2026-08-28T10:00:01.000Z","message":{"role":"user","content":"Initial Pi prompt"}}
{"type":"message","id":"b2c3d4e5","parentId":"a1b2c3d4","timestamp":"2026-08-28T10:00:02.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Working"}],"provider":"anthropic","model":"claude-sonnet-4","usage":{},"stopReason":"stop"}}
{"type":"session_info","id":"c3d4e5f6","parentId":"b2c3d4e5","timestamp":"2026-08-28T10:00:03.000Z","name":"Initial name"}
{"type":"model_change","id":"d4e5f6a7","parentId":"c3d4e5f6","timestamp":"2026-08-28T10:00:04.000Z","provider":"openai-codex","modelId":"gpt-5.6"}
{"type":"session_info","id":"e5f6a7b8","parentId":"d4e5f6a7","timestamp":"2026-08-28T10:00:05.000Z","name":"  Renamed\t Pi\n session \u001f safe  "}
JSONL

cat >"$gone_session" <<JSONL
{"type":"session","version":2,"id":"$gone_id","timestamp":"2026-08-28T09:00:00.000Z","cwd":"$GONE_CWD"}
{"type":"message","id":"f6a7b8c9","parentId":null,"timestamp":"2026-08-28T09:00:01.000Z","message":{"role":"user","content":[{"type":"text","text":"Array fallback"},{"type":"image","data":"abc","mimeType":"image/png"},{"type":"text","text":"summary"}]}}
JSONL

cat >"$invalid_session" <<JSONL
{"type":"session","version":3,"id":"$invalid_id","cwd":"$LIVE_CWD"}
JSONL
cat >"$missing_cwd_session" <<JSONL
{"type":"session","version":3,"id":"33333333-3333-4333-8333-333333333333"}
JSONL
cat >"$not_session" <<'JSONL'
{"type":"message","message":{"role":"user","content":"No header"}}
JSONL

# Portable timestamp setup: -t is supported by both BSD and GNU touch.
touch -t 202608281205 "$live_session"
touch -t 202608281150 "$gone_session"
touch -t 202608281210 "$invalid_session" "$missing_cwd_session" "$not_session"

# shellcheck source=/dev/null
source "$PISESSION"

# Generic formatting helpers remain copied from the mature picker implementation.
assert_eq "$(dir_status "$LIVE_CWD")" 'live' 'dir_status existing directory'
assert_eq "$(dir_status "$GONE_CWD")" 'gone' 'dir_status absent directory'
assert_eq "$(relative_time 999970 1000000)" 'just now' 'relative_time seconds'
assert_eq "$(relative_time 999880 1000000)" '2m ago' 'relative_time minutes'
assert_eq "$(relative_time 996400 1000000)" '1h ago' 'relative_time hours'
assert_eq "$(relative_time 900000 1000000)" 'yesterday' 'relative_time yesterday'
assert_eq "$(relative_time 740800 1000000)" '3d ago' 'relative_time days'
assert_eq "$(relative_time 1000050 1000000)" 'just now' 'relative_time future clamp'
assert_eq "$(fit 'ab' 5)" 'ab   ' 'fit padding'
assert_eq "$(fit 'abcdef' 3)" 'abc' 'fit truncation'
assert_eq "$(printf '%s' "$(fit '●' 3)" | wc -m | tr -d ' ')" '3' 'fit character width'
assert_eq "$(trunc 'hello world' 5)" 'hell…' 'trunc ellipsis'
assert_eq "$(HOME=/home/paulius shorten_dir /home/paulius)" '~' 'shorten_dir home'
# shellcheck disable=SC2088
assert_eq "$(HOME=/home/paulius shorten_dir /home/paulius/Downloads/k8s)" '~/Downloads/k8s' 'shorten_dir child'
long='/home/paulius/Insync/x@example.com/Google Drive/Documents/Job search/CV/markdown'
short="$(HOME=/home/paulius shorten_dir "$long")"
# shellcheck disable=SC2088
assert_eq "$short" '~/…/CV/markdown' 'shorten_dir middle elision'
assert_eq "$([ "${#short}" -le 38 ] && printf yes || printf no)" 'yes' 'shorten_dir width guard'
assert_eq "$(model_label '')" '—' 'model_label empty fallback'

# Pi header/model parsing and session filtering.
live_meta="$(session_meta "$live_session")"
assert_eq "$live_meta" "$live_id${SEP}$LIVE_CWD${SEP}openai-codex/gpt-5.6${SEP}3" \
  'session_meta reads header and latest model change'
gone_meta="$(session_meta "$gone_session")"
assert_eq "$gone_meta" "$gone_id${SEP}$GONE_CWD${SEP}${SEP}2" \
  'session_meta preserves an empty model field'
assert_eq "$(is_pi_session "$live_session" && echo yes || echo no)" 'yes' 'valid Pi session accepted'
assert_eq "$(is_pi_session "$invalid_session" && echo yes || echo no)" 'no' 'invalid UUID rejected'
assert_eq "$(is_pi_session "$missing_cwd_session" && echo yes || echo no)" 'no' 'missing cwd rejected'
assert_eq "$(is_pi_session "$not_session" && echo yes || echo no)" 'no' 'missing header rejected'

# Pi summary precedence and normalization.
assert_eq "$(session_summary "$live_session" "$live_id")" 'Renamed Pi session safe' \
  'latest session_info name wins and is normalized'
assert_eq "$(session_summary "$gone_session" "$gone_id")" 'Array fallback summary' \
  'first user text array is the fallback summary'
assert_eq "$(session_summary "$invalid_session" fallback-id)" 'fallback-id' \
  'ID is used when no name or prompt exists'
extracted="$(extract_session "$live_session")"
assert_eq "$extracted" "$LIVE_CWD${SEP}openai-codex/gpt-5.6${SEP}Renamed Pi session safe${SEP}$live_id${SEP}3" \
  'extract_session preserves picker field contract'

# Rows, filtering, ordering, header, and preview.
live_row="$(build_row "$live_session" 1787918700 1787918700)"
assert_contains "$live_row" '●' 'build_row live glyph'
assert_contains "$live_row" 'openai-codex/gpt-5.6' 'build_row model'
assert_contains "$live_row" 'Renamed Pi session safe' 'build_row summary'
assert_contains "$live_row" $'\t'"$live_session" 'build_row hidden session path'
gone_row="$(build_row "$gone_session" 1787917800 1787918700)"
assert_contains "$gone_row" '✗' 'build_row gone glyph'
assert_contains "$gone_row" "$DIM" 'build_row gone dimming'

list="$(build_list 1787918700)"
assert_eq "$(printf '%s\n' "$list" | grep -c $'\t' || true)" '2' 'picker valid session count'
assert_contains "$(printf '%s\n' "$list" | sed -n '1p')" "$live_id" 'picker newest valid session first'
header="$(make_header 2)"
assert_contains "$header" 'pisession · 2 sessions' 'header identity/count'
assert_contains "$header" 'MODEL' 'header model column'
assert_contains "$header" '⏎ resume' 'header action hint'

preview="$(render_preview "$live_session")"
assert_contains "$preview" '┌─ session' 'preview frame'
assert_contains "$preview" '● live' 'preview live status'
assert_contains "$preview" 'model    openai-codex/gpt-5.6' 'preview model'
assert_contains "$preview" 'format   v3' 'preview session format'
assert_contains "$preview" "$live_id" 'preview UUID'
assert_contains "$preview" 'Renamed Pi session safe' 'preview summary'
assert_contains "$(render_preview "$gone_session")" '✗ directory gone' 'preview gone status'

# Simulated macOS/BSD utilities reject GNU-only options.
REAL_DATE="$(command -v date)"
REAL_FIND="$(command -v find)"
REAL_STAT="$(command -v stat)"
# shellcheck disable=SC2317
uname() { printf 'Darwin\n'; }
# shellcheck disable=SC2317
date() {
  case "${1:-}" in
    -d) return 64 ;;
    -r)
      local epoch="$2"
      shift 2
      "$REAL_DATE" -d "@$epoch" "$@"
      ;;
    *) "$REAL_DATE" "$@" ;;
  esac
}
# shellcheck disable=SC2317
find() {
  local arg
  for arg in "$@"; do [ "$arg" = '-printf' ] && return 64; done
  "$REAL_FIND" "$@"
}
# shellcheck disable=SC2317
stat() {
  case "${1:-}" in
    -c) return 64 ;;
    -f) "$REAL_STAT" -c %Y "$3" ;;
    *) "$REAL_STAT" "$@" ;;
  esac
}
assert_eq "$(relative_time 0 1000000)" '1970-01-01' 'relative_time BSD date'
bsd_list="$(build_list 1787918700)"
assert_eq "$(printf '%s\n' "$bsd_list" | grep -c $'\t' || true)" '2' 'picker BSD discovery'
assert_contains "$(render_preview "$live_session")" 'active   2026-08-28 12:05' 'preview BSD active time'
unset -f uname date find stat

# Launch boundary: the chosen cwd and exact Pi --session file are observable.
FAKEBIN="$SANDBOX/fakebin"
RECORDER="$SANDBOX/pi.record"
mkdir -p "$FAKEBIN"
cat >"$FAKEBIN/pi" <<'SH'
#!/usr/bin/env bash
{
  printf 'CWD=<%s>\n' "$PWD"
  printf 'ARG=<%s>\n' "$@"
} >"$PISESSION_RECORDER"
SH
chmod +x "$FAKEBIN/pi"
(PISESSION_RECORDER="$RECORDER" PATH="$FAKEBIN:$PATH" launch "$live_session")
assert_eq "$?" '0' 'launch live status'
assert_eq "$(<"$RECORDER")" "CWD=<$LIVE_CWD>
ARG=<--session>
ARG=<$live_session>" 'launch uses original cwd and exact session path'
gone_out="$(launch "$gone_session" 2>&1)"
assert_eq "$?" '1' 'launch gone status'
assert_contains "$gone_out" "directory no longer exists, cannot resume: $GONE_CWD" 'launch gone error'

# Public command behavior and storage override contracts.
help_out="$(PI_CODING_AGENT_SESSION_DIR="$SANDBOX/no-state" PATH="$FAKEBIN:$PATH" bash "$PISESSION" --help)"
assert_eq "$?" '0' 'help status'
assert_contains "$help_out" 'pisession' 'help identity'
DEFAULT_HOME="$SANDBOX/default-home"
empty_out="$(
  unset PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR
  HOME="$DEFAULT_HOME" PATH="$FAKEBIN:$PATH" bash "$PISESSION" 2>&1
)"
assert_eq "$?" '1' 'empty picker status'
assert_contains "$empty_out" "no Pi sessions found under $DEFAULT_HOME/.pi/agent/sessions" \
  'default Pi session root in empty error'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
