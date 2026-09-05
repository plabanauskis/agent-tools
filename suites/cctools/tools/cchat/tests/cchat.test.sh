#!/usr/bin/env bash
# Tests for cchat: it must make a fresh temp dir, cd into it, and exec `claude`
# there, passing through args. We stub `claude` with a recorder on PATH so the
# real CLI never launches.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCHAT="$HERE/../cchat"

PASS=0
FAIL=0
assert_contains() { # <haystack> <needle> <msg>
  if [[ "$1" == *"$2"* ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  [%s] does not contain [%s]\n' "$3" "$1" "$2"
  fi
}
assert_eq() { # <got> <want> <msg>
  if [ "$1" = "$2" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  got:  [%s]\n  want: [%s]\n' "$3" "$1" "$2"
  fi
}

# Sandbox: fake claude + a private TMPDIR so we never touch the real /tmp/cchat.*
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAKEBIN="$SANDBOX/bin"
mkdir -p "$FAKEBIN"
cat >"$FAKEBIN/claude" <<'SH'
#!/usr/bin/env bash
echo "CWD=$PWD"
echo "ARGS=$*"
SH
chmod +x "$FAKEBIN/claude"

# Run cchat with the stub claude first on PATH and an isolated TMPDIR.
out="$(TMPDIR="$SANDBOX" PATH="$FAKEBIN:$PATH" bash "$CCHAT" --model opus -p hi)"
assert_contains "$out" "CWD=$SANDBOX/cchat." "cchat: claude runs inside a fresh cchat.* dir under TMPDIR"
assert_contains "$out" "ARGS=--model opus -p hi" "cchat: passes args straight through to claude"

# --help prints usage and does NOT launch claude.
help_out="$(PATH="$FAKEBIN:$PATH" bash "$CCHAT" --help)"
help_rc=$?
assert_eq "$help_rc" "0" "cchat: --help exits 0"
assert_contains "$help_out" "cchat" "cchat: --help mentions the tool name"
case "$help_out" in *CWD=*)
  FAIL=$((FAIL + 1))
  echo "FAIL: --help must not launch claude"
  ;;
*) PASS=$((PASS + 1)) ;; esac

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
