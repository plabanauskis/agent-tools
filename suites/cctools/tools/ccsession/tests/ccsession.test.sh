#!/usr/bin/env bash
# Plain-bash test suite for ccsession. Sources the script (the source guard keeps
# main from running) and asserts on its pure functions.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../ccsession"

PASS=0
FAIL=0
assert_eq() { # <got> <want> <msg>
  if [ "$1" = "$2" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  got:  [%s]\n  want: [%s]\n' "$3" "$1" "$2"
  fi
}
assert_contains() { # <haystack> <needle> <msg>
  if [[ "$1" == *"$2"* ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  [%s] does not contain [%s]\n' "$3" "$1" "$2"
  fi
}

# --- dir_status ---
assert_eq "$(dir_status "$HERE")" "live" "dir_status: existing dir is live"
assert_eq "$(dir_status "/no/such/path/$$")" "gone" "dir_status: missing dir is gone"

# --- relative_time (now fixed at 1000000) ---
assert_eq "$(relative_time 999970 1000000)" "just now" "relative_time: <60s"
assert_eq "$(relative_time 999880 1000000)" "2m ago" "relative_time: minutes"
assert_eq "$(relative_time 996400 1000000)" "1h ago" "relative_time: hours"
assert_eq "$(relative_time 900000 1000000)" "yesterday" "relative_time: ~28h -> yesterday"
assert_eq "$(relative_time 740800 1000000)" "3d ago" "relative_time: days"
assert_eq "$(relative_time 1000050 1000000)" "just now" "relative_time: future clamps to just now"

# --- fit: char-based width (multibyte safe) ---
assert_eq "$(fit "ab" 5)" "ab   " "fit: pads short ASCII to width"
assert_eq "$(fit "abcdef" 3)" "abc" "fit: truncates long to width"
assert_eq "$(printf '%s' "$(fit "●" 3)" | wc -m)" "3" "fit: multibyte glyph counts as 1 char, padded to 3"

# --- trunc ---
assert_eq "$(trunc "hello" 10)" "hello" "trunc: short string unchanged"
assert_eq "$(trunc "hello world" 5)" "hell…" "trunc: appends ellipsis when cut"

# --- dashes ---
assert_eq "$(printf '%s' "$(dashes 4)" | wc -m)" "4" "dashes: emits N box-drawing chars"

# --- branch_label: detached HEAD and empty render as — ---
assert_eq "$(branch_label main)" "main" "branch_label: real branch passes through"
assert_eq "$(branch_label HEAD)" "—" "branch_label: detached HEAD -> —"
assert_eq "$(branch_label '')" "—" "branch_label: empty -> —"

# --- shorten_dir (DIR_W = 38) ---
assert_eq "$(HOME=/home/paulius shorten_dir /home/paulius)" "~" "shorten_dir: bare home -> ~"
# shellcheck disable=SC2088  # expected value contains a literal ~
assert_eq "$(HOME=/home/paulius shorten_dir /home/paulius/Downloads/k8s)" "~/Downloads/k8s" "shorten_dir: short home path"
assert_eq "$(HOME=/home/paulius shorten_dir /tmp/cchat.wJlIhV)" "/tmp/cchat.wJlIhV" "shorten_dir: short absolute path unchanged"
long="/home/paulius/Insync/x@y.com/Google Drive/Documents/Job search/CV/markdown"
got="$(HOME=/home/paulius shorten_dir "$long")"
# shellcheck disable=SC2088  # expected value contains a literal ~
assert_eq "$got" "~/…/CV/markdown" "shorten_dir: long home path elided to tail"
assert_eq "$([ "${#got}" -le 38 ] && echo ok)" "ok" "shorten_dir: result within DIR_W"

# --- extraction fixtures ---
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# fixture A: has ai-title (last wins), a branch, cwd
cat >"$TMP/aaaaaaaa-0000-0000-0000-000000000001.jsonl" <<'JSONL'
{"type":"user","cwd":"/home/paulius/Downloads/k8s","gitBranch":"main","message":{"role":"user","content":"hi there"}}
{"type":"ai-title","aiTitle":"First title (stale)","sessionId":"x"}
{"type":"ai-title","aiTitle":"Kubernetes architecture crash course","sessionId":"x"}
JSONL

# fixture B: NO ai-title; first user record is meta; real prompt is a command tag
cat >"$TMP/bbbbbbbb-0000-0000-0000-000000000002.jsonl" <<'JSONL'
{"type":"user","isMeta":true,"cwd":"/tmp/cchat.AbCdEf","message":{"role":"user","content":"<local-command-caveat>Caveat...</local-command-caveat>"}}
{"type":"user","cwd":"/tmp/cchat.AbCdEf","message":{"role":"user","content":"<command-name>/plugin</command-name>"}}
JSONL

# fixture C: no ai-title, no usable text -> fallback to session id; cwd has spaces
cat >"$TMP/cccccccc-0000-0000-0000-000000000003.jsonl" <<'JSONL'
{"type":"user","cwd":"/home/paulius/Google Drive/Job search","message":{"role":"user","content":""}}
JSONL

# session_summary
assert_eq "$(session_summary "$TMP/aaaaaaaa-0000-0000-0000-000000000001.jsonl")" \
  "Kubernetes architecture crash course" "session_summary: last ai-title wins"
assert_eq "$(session_summary "$TMP/bbbbbbbb-0000-0000-0000-000000000002.jsonl")" \
  "/plugin" "session_summary: skips meta, strips tags from fallback"
assert_eq "$(session_summary "$TMP/cccccccc-0000-0000-0000-000000000003.jsonl")" \
  "cccccccc-0000-0000-0000-000000000003" "session_summary: empty text -> session id"

# extract_session (SEP-separated; SEP is non-whitespace so empty fields survive)
IFS=$SEP read -r ecwd ebranch esum < <(extract_session "$TMP/aaaaaaaa-0000-0000-0000-000000000001.jsonl")
assert_eq "$ecwd" "/home/paulius/Downloads/k8s" "extract_session: cwd"
assert_eq "$ebranch" "main" "extract_session: branch"
assert_eq "$esum" "Kubernetes architecture crash course" "extract_session: summary"

# branch empty when absent; cwd-with-spaces preserved
# shellcheck disable=SC2034  # csum is intentionally read-but-unused here
IFS=$SEP read -r ccwd cbranch csum < <(extract_session "$TMP/cccccccc-0000-0000-0000-000000000003.jsonl")
assert_eq "$ccwd" "/home/paulius/Google Drive/Job search" "extract_session: cwd with spaces"
assert_eq "$cbranch" "" "extract_session: empty branch when no gitBranch"

# --- build_row ---
LIVEDIR="$TMP/live"
mkdir -p "$LIVEDIR"
cat >"$TMP/dddddddd-0000-0000-0000-000000000004.jsonl" <<JSONL
{"type":"user","cwd":"$LIVEDIR","gitBranch":"main","message":{"role":"user","content":"hi"}}
{"type":"ai-title","aiTitle":"Live session here","sessionId":"x"}
JSONL

row_live="$(build_row "$TMP/dddddddd-0000-0000-0000-000000000004.jsonl" 1000000 1000000)"
assert_contains "$row_live" "●" "build_row: live row uses ● glyph"
assert_contains "$row_live" "Live session here" "build_row: includes summary"
assert_contains "$row_live" $'\t'"$TMP/dddddddd-0000-0000-0000-000000000004.jsonl" "build_row: hidden jsonl field present"
disp="${row_live%%$'\t'*}"
assert_eq "$(printf '%s' "$disp" | tr -cd '\t' | wc -c)" "0" "build_row: display field has no tab"

row_gone="$(build_row "$TMP/cccccccc-0000-0000-0000-000000000003.jsonl" 1000000 1000000)"
assert_contains "$row_gone" "✗" "build_row: gone row uses ✗ glyph"
assert_contains "$row_gone" "$DIM" "build_row: gone row is dimmed"

# --- make_header ---
hdr="$(make_header 42)"
assert_contains "$hdr" "42 sessions" "make_header: shows count"
assert_contains "$hdr" "DIRECTORY" "make_header: column titles"
assert_contains "$hdr" "⏎ resume" "make_header: hint line"

# --- render_preview ---
card_live="$(render_preview "$TMP/dddddddd-0000-0000-0000-000000000004.jsonl")"
assert_contains "$card_live" "┌─ session" "render_preview: top border/title"
assert_contains "$card_live" "● live" "render_preview: live status line"
assert_contains "$card_live" "dddddddd-0000-0000-0000-000000000004" "render_preview: shows id"
assert_contains "$card_live" "Live session here" "render_preview: shows summary"
assert_contains "$card_live" "└" "render_preview: bottom border"

card_gone="$(render_preview "$TMP/cccccccc-0000-0000-0000-000000000003.jsonl")"
assert_contains "$card_gone" "✗ directory gone" "render_preview: gone status line"

# --- launch: gone directory ---
out="$(launch "$TMP/cccccccc-0000-0000-0000-000000000003.jsonl" 2>&1 1>/dev/null)"
rc=$?
assert_eq "$rc" "1" "launch: gone dir exits non-zero"
assert_contains "$out" "directory no longer exists, cannot resume: /home/paulius/Google Drive/Job search" \
  "launch: gone dir error message"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
