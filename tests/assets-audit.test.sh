#!/usr/bin/env bash
# Regression tests for the repository-wide legacy-name audit in assets.test.sh.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SANDBOX="$(mktemp -d)"
FIXTURE="$ROOT/.legacy-audit-fixture"
trap 'rm -rf "$SANDBOX"; rm -f "$FIXTURE"' EXIT

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

# The old \b expression misses the old suite name when '_' follows it.
printf '%s%s\n' 'CC' 'TOOLS_HOME=/tmp/old-prefix' >"$FIXTURE"
identifier_out="$(cd "$ROOT" && bash tests/assets.test.sh 2>&1)"
identifier_rc=$?
assert_eq "$identifier_rc" '1' 'asset audit rejects underscore-delimited legacy identifiers'
assert_contains "$identifier_out" '.legacy-audit-fixture' 'asset audit reports the matching file'
rm -f "$FIXTURE"

# Search failures are audit failures, not an empty successful result.
FAKEBIN="$SANDBOX/fakebin"
mkdir -p "$FAKEBIN"
printf '%s\n' '#!/usr/bin/env bash' 'printf "simulated rg failure\\n" >&2' 'exit 2' >"$FAKEBIN/rg"
chmod +x "$FAKEBIN/rg"
error_out="$(cd "$ROOT" && PATH="$FAKEBIN:$PATH" bash tests/assets.test.sh 2>&1)"
error_rc=$?
assert_eq "$error_rc" '1' 'asset audit propagates rg errors as test failure'
assert_contains "$error_out" 'legacy-name audit failed' 'asset audit explains rg failure'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
