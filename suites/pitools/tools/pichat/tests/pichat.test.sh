#!/usr/bin/env bash
# Tests for pichat: it makes a fresh retained temp dir, cd's into it, and
# launches pi there while preserving the exact argument boundaries.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PICHAT="$HERE/../pichat"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1"
}
assert_contains() {
  case "$1" in
    *"$2"*) ok ;;
    *) bad "$3 ([$1] lacks [$2])" ;;
  esac
}
assert_eq() {
  if [ "$1" = "$2" ]; then
    ok
  else
    bad "$3 (got [$1] want [$2])"
  fi
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAKEBIN="$SANDBOX/fakebin"
mkdir -p "$FAKEBIN"
# shellcheck disable=SC2016
# The single-quoted strings are literal contents for the fake executable.
printf '%s\n' '#!/usr/bin/env bash' 'echo "CWD=$PWD"' 'printf "ARG=<%s>\\n" "$@"' >"$FAKEBIN/pi"
chmod +x "$FAKEBIN/pi"

out="$(TMPDIR="$SANDBOX" PATH="$FAKEBIN:$PATH" bash "$PICHAT" --model openai/gpt-5.6 "two words")"
assert_contains "$out" "CWD=$SANDBOX/pichat." "pichat: pi runs in a fresh pichat directory"
assert_contains "$out" "ARG=<--model>" "pichat: preserves option argument"
assert_contains "$out" "ARG=<openai/gpt-5.6>" "pichat: preserves option value"
assert_contains "$out" "ARG=<two words>" "pichat: preserves argument boundaries"

help_out="$(PATH="$FAKEBIN:$PATH" bash "$PICHAT" --help)"
help_rc=$?
assert_eq "$help_rc" "0" "pichat: --help exits 0"
assert_contains "$help_out" "pichat" "pichat: --help names the tool"
case "$help_out" in
  *CWD=*) bad "pichat: --help must not launch pi" ;;
  *) ok ;;
esac

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
