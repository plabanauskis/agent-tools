#!/usr/bin/env bash
# Smoke command contracts are tested at the Docker boundary: no local Docker
# daemon or image is required, while each exact `docker run` environment and
# inner-Docker readiness command remains observable.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMOKE="$HERE/../test/smoke.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); }
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1"
}
assert_zero() { # <status> <mutation>
  if [ "$1" -eq 0 ]; then
    pass
  else
    fail "$2 (got exit $1, want 0)"
  fi
}
assert_contains() { # <haystack> <needle> <mutation>
  if [[ "$1" == *"$2"* ]]; then
    pass
  else
    fail "$3\n  [$1] does not contain [$2]"
  fi
}
assert_not_contains() { # <haystack> <needle> <mutation>
  if [[ "$1" != *"$2"* ]]; then
    pass
  else
    fail "$3\n  [$1] unexpectedly contains [$2]"
  fi
}

BIN="$SANDBOX/bin"
mkdir -p "$BIN"
cat >"$BIN/docker" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  info)
    [ "${FAKE_SYSBOX:-0}" = 1 ] && printf '{io.containerd.runc.v2 sysbox-runc}\n'
    ;;
  run)
    printf '%s' "$*" | tr '\n' ' ' >>"$DOCKER_RECORD"
    printf '\n' >>"$DOCKER_RECORD"
    ;;
esac
SH
chmod +x "$BIN/docker"

# Toolchain and non-root probes must bypass the image entrypoint's daemon
# startup. Removing the marker starts dockerd for every otherwise simple check.
NO_SYSBOX_RECORD="$SANDBOX/no-sysbox.runs"
set +e
PATH="$BIN:/usr/bin:/bin" \
  DOCKER_RECORD="$NO_SYSBOX_RECORD" \
  FAKE_SYSBOX=0 \
  bash "$SMOKE" cobox:test >/dev/null 2>&1
no_sysbox_rc=$?
set -e
assert_zero "$no_sysbox_rc" \
  "smoke ordinary probes: a no-sysbox run must complete with the fake Docker boundary"
while IFS= read -r invocation; do
  assert_contains "$invocation" "-e COBOX_NO_DOCKER=1" \
    "smoke ordinary probes: each toolchain/non-root run must disable entrypoint daemon startup"
done <"$NO_SYSBOX_RECORD"

# The inner-Docker command remains enabled, but must carry a finite readiness
# loop and dump the daemon log on timeout. This is asserted from the command
# handed to Docker because its body runs only inside the container image.
SYSBOX_RECORD="$SANDBOX/sysbox.runs"
set +e
PATH="$BIN:/usr/bin:/bin" \
  DOCKER_RECORD="$SYSBOX_RECORD" \
  FAKE_SYSBOX=1 \
  bash "$SMOKE" cobox:test >/dev/null 2>&1
sysbox_rc=$?
set -e
assert_zero "$sysbox_rc" \
  "smoke inner Docker: the fake sysbox boundary must receive the readiness probe"
inner_command="$(tail -n1 "$SYSBOX_RECORD")"
assert_not_contains "$inner_command" "COBOX_NO_DOCKER=1" \
  "smoke inner Docker: the explicit daemon check must not disable the daemon"
assert_contains "$inner_command" "for attempt in \$(seq 1 30)" \
  "smoke inner Docker: replacing the bounded retry loop with an unbounded wait can hang checks"
assert_contains "$inner_command" "cat /tmp/d.log" \
  "smoke inner Docker: timeout failure must expose the daemon log for diagnosis"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
