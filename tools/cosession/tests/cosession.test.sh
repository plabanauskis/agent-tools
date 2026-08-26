#!/usr/bin/env bash
# Behavior tests for cosession's Codex rollout parser, picker, preview, and
# resume boundary. Each assertion names the production mutation it catches.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COSESSION="$HERE/../cosession"

if [ ! -f "$COSESSION" ]; then
  printf 'FAIL: missing cosession entrypoint: %s\n' "$COSESSION" >&2
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
  if [ "$1" = "$2" ]; then
    ok
  else
    bad "$3 (got [$1] want [$2])"
  fi
}
assert_contains() {
  case "$1" in
    *"$2"*) ok ;;
    *) bad "$3 ([$1] lacks [$2])" ;;
  esac
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export CODEX_HOME="$SANDBOX/codex"
SESSIONS_DIR="$CODEX_HOME/sessions/2026/08/26"
LIVE_CWD="$SANDBOX/live project"
DESKTOP_CWD="$SANDBOX/desktop-project"
GONE_CWD="$SANDBOX/removed-project"
mkdir -p "$SESSIONS_DIR" "$LIVE_CWD" "$DESKTOP_CWD"

cli_id='11111111-1111-4111-8111-111111111111'
desktop_id='22222222-2222-4222-8222-222222222222'
subagent_id='33333333-3333-4333-8333-333333333333'
gone_id='44444444-4444-4444-8444-444444444444'
missing_id='55555555-5555-4555-8555-555555555555'

cli_rollout="$SESSIONS_DIR/rollout-2026-08-26T10-00-00-$cli_id.jsonl"
desktop_rollout="$SESSIONS_DIR/rollout-2026-08-26T11-00-00-$desktop_id.jsonl"
subagent_rollout="$SESSIONS_DIR/rollout-2026-08-26T12-00-00-$subagent_id.jsonl"
gone_rollout="$SESSIONS_DIR/rollout-2026-08-26T09-00-00-$gone_id.jsonl"
missing_uuid_rollout="$SESSIONS_DIR/rollout-missing-uuid.jsonl"
missing_cwd_rollout="$SESSIONS_DIR/rollout-missing-cwd.jsonl"

cat >"$cli_rollout" <<JSONL
{"timestamp":"2026-08-26T10:00:00Z","type":"session_meta","payload":{"id":"$cli_id","cwd":"$LIVE_CWD","source":"cli","originator":"codex-tui","git":{"branch":"main"}}}
{"timestamp":"2026-08-26T10:00:01Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"CLI fallback summary"}]}}
JSONL

cat >"$desktop_rollout" <<JSONL
{"timestamp":"2026-08-26T11:00:00Z","type":"session_meta","payload":{"id":"$desktop_id","cwd":"$DESKTOP_CWD","source":"vscode","originator":"Codex Desktop"}}
{"timestamp":"2026-08-26T11:00:01Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>generated context</environment_context>"}]}}
{"timestamp":"2026-08-26T11:00:02Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Desktop fallback summary"}]}}
JSONL

cat >"$subagent_rollout" <<JSONL
{"timestamp":"2026-08-26T12:00:00Z","type":"session_meta","payload":{"id":"$subagent_id","cwd":"$LIVE_CWD","source":{"subagent":{"thread_spawn":{"parent_thread_id":"$cli_id","depth":1}}}}}
JSONL

cat >"$gone_rollout" <<JSONL
{"timestamp":"2026-08-26T09:00:00Z","type":"session_meta","payload":{"session_id":"$gone_id","cwd":"$GONE_CWD","source":"exec","git":{"branch":"HEAD"}}}
{"timestamp":"2026-08-26T09:00:01Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"  Rollout\\t fallback\\n summary \\u001f safe  "}]}}
JSONL

cat >"$missing_uuid_rollout" <<JSONL
{"timestamp":"2026-08-26T08:00:00Z","type":"session_meta","payload":{"cwd":"$LIVE_CWD","source":"cli"}}
JSONL

cat >"$missing_cwd_rollout" <<JSONL
{"timestamp":"2026-08-26T07:00:00Z","type":"session_meta","payload":{"id":"$missing_id","source":"cli"}}
JSONL

cat >"$CODEX_HOME/session_index.jsonl" <<JSONL
{"id":"$cli_id","thread_name":"Initial CLI thread"}
{"id":"$desktop_id","thread_name":""}
{"id":"$cli_id","thread_name":"Renamed CLI thread"}
JSONL

cat >"$CODEX_HOME/history.jsonl" <<JSONL
{"session_id":"$desktop_id","ts":1787732400,"text":""}
{"session_id":"$desktop_id","ts":1787732401,"text":"Desktop prompt from history"}
{"session_id":"$desktop_id","ts":1787732402,"text":"Later desktop prompt"}
JSONL

# Portable timestamp setup: -t is supported by both BSD and GNU touch.
touch -t 202608261205 "$cli_rollout"
touch -t 202608261200 "$desktop_rollout"
touch -t 202608261155 "$subagent_rollout"
touch -t 202608261150 "$gone_rollout"
touch -t 202608261145 "$missing_uuid_rollout"
touch -t 202608261140 "$missing_cwd_rollout"

# shellcheck source=/dev/null
source "$COSESSION"

# Basic formatting. Mutations named in each assertion message are realistic
# wrong branches or boundary errors in the corresponding production helper.
assert_eq "$(dir_status "$LIVE_CWD")" 'live' \
  'dir_status existing directory [mutation: remove live-directory branch]'
assert_eq "$(dir_status "$GONE_CWD")" 'gone' \
  'dir_status absent directory [mutation: treat every nonempty cwd as live]'
assert_eq "$(relative_time 999970 1000000)" 'just now' \
  'relative_time seconds [mutation: round sub-minute age to minutes]'
assert_eq "$(relative_time 999880 1000000)" '2m ago' \
  'relative_time minutes [mutation: divide minute ages by hours]'
assert_eq "$(relative_time 996400 1000000)" '1h ago' \
  'relative_time hours [mutation: retain minute formatting after one hour]'
assert_eq "$(relative_time 900000 1000000)" 'yesterday' \
  'relative_time yesterday [mutation: omit the one-day label branch]'
assert_eq "$(relative_time 740800 1000000)" '3d ago' \
  'relative_time days [mutation: compute day divisor incorrectly]'
assert_eq "$(relative_time 1000050 1000000)" 'just now' \
  'relative_time future clamp [mutation: display a negative age]'
assert_eq "$(fit 'ab' 5)" 'ab   ' \
  'fit padding [mutation: stop right-padding short fields]'
assert_eq "$(fit 'abcdef' 3)" 'abc' \
  'fit truncation [mutation: allow a field to exceed its column]'
assert_eq "$(printf '%s' "$(fit '●' 3)" | wc -m | tr -d ' ')" '3' \
  'fit character width [mutation: count UTF-8 bytes as display characters]'
assert_eq "$(trunc 'hello world' 5)" 'hell…' \
  'trunc ellipsis [mutation: hard-cut summaries without an ellipsis]'
assert_eq "$(HOME=/home/paulius shorten_dir /home/paulius)" '~' \
  'shorten_dir home [mutation: fail to abbreviate the exact home directory]'
# shellcheck disable=SC2088
assert_eq "$(HOME=/home/paulius shorten_dir /home/paulius/Downloads/k8s)" '~/Downloads/k8s' \
  'shorten_dir child [mutation: abbreviate only exact HOME]'
long='/home/paulius/Insync/x@example.com/Google Drive/Documents/Job search/CV/markdown'
short="$(HOME=/home/paulius shorten_dir "$long")"
# shellcheck disable=SC2088
assert_eq "$short" '~/…/CV/markdown' \
  'shorten_dir middle elision [mutation: retain overflowing middle segments]'
assert_eq "$([ "${#short}" -le 38 ] && printf yes || printf no)" 'yes' \
  'shorten_dir width guard [mutation: return a path wider than DIR_W]'

# Rollout metadata and root filtering.
cli_meta="$(session_meta "$cli_rollout")"
assert_eq "$cli_meta" "$cli_id${SEP}$LIVE_CWD${SEP}main${SEP}cli" \
  'session_meta CLI fields [mutation: read id/cwd/branch/source from wrong JSON level]'
desktop_meta="$(session_meta "$desktop_rollout")"
assert_eq "$desktop_meta" "$desktop_id${SEP}$DESKTOP_CWD${SEP}${SEP}vscode" \
  'session_meta empty branch [mutation: collapse an empty branch into source]'
gone_meta="$(session_meta "$gone_rollout")"
assert_eq "$gone_meta" "$gone_id${SEP}$GONE_CWD${SEP}HEAD${SEP}exec" \
  'session_meta session_id fallback [mutation: accept only payload.id]'
assert_eq "$(is_root_session "$cli_rollout" && echo yes || echo no)" 'yes' \
  'is_root_session CLI [mutation: reject string cli source]'
assert_eq "$(is_root_session "$desktop_rollout" && echo yes || echo no)" 'yes' \
  'is_root_session Desktop [mutation: whitelist cli and reject other string sources]'
assert_eq "$(is_root_session "$subagent_rollout" && echo yes || echo no)" 'no' \
  'is_root_session subagent [mutation: accept structured source objects]'
assert_eq "$(is_root_session "$missing_uuid_rollout" && echo yes || echo no)" 'no' \
  'is_root_session UUID validation [mutation: accept empty UUID]'
assert_eq "$(is_root_session "$missing_cwd_rollout" && echo yes || echo no)" 'no' \
  'is_root_session cwd validation [mutation: accept empty cwd]'

# Summary precedence and normalization.
assert_eq "$(session_summary "$cli_rollout" "$cli_id")" 'Renamed CLI thread' \
  'latest name [mutation: take first matching session_index name]'
assert_eq "$(session_summary "$desktop_rollout" "$desktop_id")" 'Desktop prompt from history' \
  'history precedence [mutation: use rollout text before history]'
assert_eq "$(session_summary "$gone_rollout" "$gone_id")" 'Rollout fallback summary safe' \
  'rollout normalization [mutation: retain tabs/newlines/SEP or outer whitespace]'
assert_eq "$(session_summary "$missing_uuid_rollout" 'fallback-id')" 'fallback-id' \
  'UUID fallback [mutation: return an empty summary when all text sources miss]'

extracted="$(extract_session "$cli_rollout")"
assert_eq "$extracted" "$LIVE_CWD${SEP}main${SEP}Renamed CLI thread${SEP}$cli_id${SEP}cli" \
  'extract_session contract [mutation: reorder or omit picker metadata fields]'

# Rows, filtering, ordering, header, and previews.
live_row="$(build_row "$cli_rollout" 1787738400 1787738400)"
assert_contains "$live_row" '●' \
  'build_row live glyph [mutation: render live sessions as gone]'
assert_contains "$live_row" 'Renamed CLI thread' \
  'build_row summary [mutation: omit the resolved summary]'
assert_contains "$live_row" $'\t'"$cli_rollout" \
  'build_row hidden rollout [mutation: omit the launch/preview selector field]'
display="${live_row%%$'\t'*}"
assert_eq "$(printf '%s' "$display" | tr -cd '\t' | wc -c | tr -d ' ')" '0' \
  'build_row delimiter isolation [mutation: leak tabs into visible columns]'

gone_row="$(build_row "$gone_rollout" 1787738100 1787738400)"
assert_contains "$gone_row" '✗' \
  'build_row gone glyph [mutation: render removed cwd as live]'
assert_contains "$gone_row" "$DIM" \
  'build_row gone dimming [mutation: omit gone-row visual distinction]'

list="$(build_list 1787738400)"
assert_eq "$(printf '%s\n' "$list" | grep -c "$subagent_id" || true)" '0' \
  'picker omits subagent [mutation: build rows without root-source filtering]'
assert_eq "$(printf '%s\n' "$list" | grep -c 'rollout-missing-' || true)" '0' \
  'picker omits malformed [mutation: list rollouts without UUID/cwd validation]'
assert_eq "$(printf '%s\n' "$list" | grep -c $'\t' || true)" '3' \
  'picker root count [mutation: omit CLI, Desktop, or session_id-root rollout]'
first="$(printf '%s\n' "$list" | sed -n '1p')"
assert_contains "$first" "$cli_id" \
  'picker newest first [mutation: sort rollout mtimes ascending]'

header="$(make_header 3)"
assert_contains "$header" 'cosession · 3 sessions' \
  'header identity/count [mutation: show wrong tool or row count]'
assert_contains "$header" 'DIRECTORY' \
  'header columns [mutation: omit directory column label]'
assert_contains "$header" '⏎ resume' \
  'header action hint [mutation: omit the resume affordance]'

preview="$(render_preview "$cli_rollout")"
assert_contains "$preview" '┌─ session' \
  'preview frame [mutation: omit preview card boundary]'
assert_contains "$preview" '● live' \
  'preview live status [mutation: report existing cwd as gone]'
assert_contains "$preview" "source   cli" \
  'preview source [mutation: omit Codex source metadata]'
assert_contains "$preview" "$cli_id" \
  'preview UUID [mutation: derive id from rollout filename incorrectly]'
assert_contains "$preview" 'Renamed CLI thread' \
  'preview summary [mutation: omit resolved summary from card]'
assert_contains "$preview" '└' \
  'preview bottom border [mutation: emit an unterminated card]'

gone_preview="$(render_preview "$gone_rollout")"
assert_contains "$gone_preview" '✗ directory gone' \
  'preview gone status [mutation: ignore missing cwd in preview]'

# Simulated macOS/BSD utilities. These behavior doubles reject the GNU-only
# flags unavailable on standard macOS, translate supported BSD forms to the
# Linux host's real utilities, and leave the parser/picker itself real.
REAL_DATE="$(command -v date)"
REAL_FIND="$(command -v find)"
REAL_STAT="$(command -v stat)"
# shellcheck disable=SC2317 # invoked indirectly by sourced production helpers
uname() { printf 'Darwin\n'; }
# shellcheck disable=SC2317 # invoked indirectly by sourced production helpers
date() {
  case "${1:-}" in
    -d)
      printf 'simulated BSD date: -d is unsupported\n' >&2
      return 64
      ;;
    -r)
      local epoch="$2"
      shift 2
      "$REAL_DATE" -d "@$epoch" "$@"
      ;;
    *) "$REAL_DATE" "$@" ;;
  esac
}
# shellcheck disable=SC2317 # invoked indirectly by sourced production helpers
find() {
  local arg
  for arg in "$@"; do
    if [ "$arg" = '-printf' ]; then
      printf 'simulated BSD find: -printf is unsupported\n' >&2
      return 64
    fi
  done
  "$REAL_FIND" "$@"
}
# shellcheck disable=SC2317 # invoked indirectly by sourced production helpers
stat() {
  case "${1:-}" in
    -c)
      printf 'simulated BSD stat: -c is unsupported\n' >&2
      return 64
      ;;
    -f)
      if [ "${2:-}" != '%m' ]; then return 64; fi
      "$REAL_STAT" -c %Y "$3"
      ;;
    *) "$REAL_STAT" "$@" ;;
  esac
}

assert_eq "$(relative_time 0 1000000)" '1970-01-01' \
  'relative_time BSD date [mutation: use GNU date -d on Darwin]'
bsd_list="$(build_list 1787738400)"
assert_eq "$(printf '%s\n' "$bsd_list" | grep -c $'\t' || true)" '3' \
  'picker BSD discovery [mutation: use GNU find -printf on Darwin]'
bsd_first="$(printf '%s\n' "$bsd_list" | sed -n '1p')"
assert_contains "$bsd_first" "$cli_id" \
  'picker BSD mtime sorting [mutation: use GNU stat -c on Darwin]'
bsd_preview="$(render_preview "$cli_rollout")"
assert_contains "$bsd_preview" 'active   2026-08-26 12:05' \
  'preview BSD active time [mutation: use GNU stat/date flags on Darwin]'

unset -f uname date find stat

# Launch boundary: assert the real fake-process recorder output, not calls.
FAKEBIN="$SANDBOX/fakebin"
RECORDER="$SANDBOX/codex.record"
mkdir -p "$FAKEBIN"
cat >"$FAKEBIN/codex" <<'SH'
#!/usr/bin/env bash
{
  printf 'CWD=<%s>\n' "$PWD"
  printf 'ARG=<%s>\n' "$@"
} >"$COS_RECORDER"
SH
chmod +x "$FAKEBIN/codex"

(COS_RECORDER="$RECORDER" PATH="$FAKEBIN:$PATH" launch "$cli_rollout")
launch_rc=$?
assert_eq "$launch_rc" '0' \
  'launch live status [mutation: reject a live cwd before exec]'
assert_eq "$(cat "$RECORDER")" "CWD=<$LIVE_CWD>
ARG=<resume>
ARG=<$cli_id>" \
  'launch recorder [mutation: use current cwd, wrong verb, extra arg, or filename-derived id]'

gone_out="$(launch "$gone_rollout" 2>&1)"
gone_rc=$?
assert_eq "$gone_rc" '1' \
  'launch gone status [mutation: report success for an unresumable cwd]'
assert_contains "$gone_out" "directory no longer exists, cannot resume: $GONE_CWD" \
  'launch gone error [mutation: hide which recorded directory disappeared]'

# Public command behavior: --help is state-independent; an empty default root
# reports its actual sessions path and never opens fzf.
help_out="$(CODEX_HOME="$SANDBOX/no-state" PATH="$FAKEBIN:$PATH" bash "$COSESSION" --help)"
help_rc=$?
assert_eq "$help_rc" '0' \
  'help status [mutation: inspect missing session state before handling --help]'
assert_contains "$help_out" 'cosession' \
  'help identity [mutation: leave source-tool name in user-facing help]'

DEFAULT_HOME="$SANDBOX/default-home"
empty_out="$(
  unset CODEX_HOME
  HOME="$DEFAULT_HOME" PATH="$FAKEBIN:$PATH" bash "$COSESSION" 2>&1
)"
empty_rc=$?
assert_eq "$empty_rc" '1' \
  'empty picker status [mutation: treat no valid sessions as cancellation]'
assert_contains "$empty_out" "no Codex sessions found under $DEFAULT_HOME/.codex/sessions" \
  'default root/empty error [mutation: ignore HOME fallback or report wrong sessions path]'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
