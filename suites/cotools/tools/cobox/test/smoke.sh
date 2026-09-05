#!/usr/bin/env bash
set -euo pipefail

image="${1:-cobox:latest}"
fail=0
check() {
  printf '  %-10s ' "$1:"
  if docker run --rm -e COBOX_NO_DOCKER=1 "$image" bash -lc "$2" >/dev/null 2>&1; then
    echo OK
  else
    echo FAIL
    fail=1
  fi
}

echo "Toolchain smoke test for $image"
check node "node --version"
check npm "npm --version"
check python "python3 --version"
check uv "uv --version"
check go "go version"
check rustc "rustc --version"
check cargo "cargo --version"
check dotnet "dotnet --version"
check gh "gh --version"
check rg "rg --version"
check fd "fd --version"
check socat "socat -V"

printf '  %-10s ' "non-root:"
if docker run --rm -e COBOX_NO_DOCKER=1 "$image" bash -lc 'test "$(id -u)" -ne 0'; then
  echo OK
else
  echo FAIL
  fail=1
fi

printf '  %-10s ' "inner-docker:"
if docker info -f '{{.Runtimes}}' 2>/dev/null | grep -q sysbox-runc; then
  if docker run --rm --runtime=sysbox-runc "$image" bash -lc \
    'sudo sh -c "dockerd >/tmp/d.log 2>&1 &"
     ready=0
     for attempt in $(seq 1 30); do
       if docker info >/dev/null 2>&1; then
         ready=1
         break
       fi
       sleep 1
     done
     if [ "$ready" -ne 1 ]; then
       echo "inner Docker daemon did not become ready" >&2
       cat /tmp/d.log >&2 || true
       exit 1
     fi
     docker run --rm hello-world >/dev/null 2>&1'; then
    echo OK
  else
    echo FAIL
    fail=1
  fi
else
  echo "SKIP (sysbox not installed)"
fi

# shellcheck disable=SC2015 # echo is cosmetic; the right branch records failure.
[ "$fail" -eq 0 ] && echo "ALL PASS" || {
  echo "SOME CHECKS FAILED"
  exit 1
}
