#!/usr/bin/env bash
set -euo pipefail
img="${1:-ccbox:latest}"
fail=0
check() {
  printf '  %-10s ' "$1:"
  if docker run --rm "$img" bash -lc "$2" >/dev/null 2>&1; then echo OK; else
    echo FAIL
    fail=1
  fi
}

echo "Toolchain smoke test for $img"
# Note: 'claude' is NOT installed in the image — ccbox mounts the host's binary at run time.
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
if docker run --rm "$img" bash -lc 'test "$(id -u)" -ne 0'; then echo "OK"; else
  echo FAIL
  fail=1
fi

printf '  %-10s ' "inner-docker:"
if docker info -f '{{.Runtimes}}' 2>/dev/null | grep -q sysbox-runc; then
  if docker run --rm --runtime=sysbox-runc "$img" bash -lc \
    'sudo sh -c "dockerd >/tmp/d.log 2>&1 &"; until docker info >/dev/null 2>&1; do sleep 1; done; docker run --rm hello-world >/dev/null 2>&1'; then
    echo OK
  else
    echo FAIL
    fail=1
  fi
else
  echo "SKIP (sysbox not installed)"
fi

# shellcheck disable=SC2015  # false positive: echo rarely fails; C branch intentionally means failure
[ "$fail" -eq 0 ] && echo "ALL PASS" || {
  echo "SOME CHECKS FAILED"
  exit 1
}
