#!/usr/bin/env bash
# Local CI: shell quality checks, every discovered suite, then an environment-
# gated pibox smoke test. Missing optional linters are explicit skips.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
SHFMT_FLAGS=(-i 2 -ci)
rc=0

mapfile -t SCRIPTS < <(
  printf '%s\n' \
    install.sh \
    lib/pitools-common.sh \
    bin/pitools \
    scripts/check.sh scripts/dev-setup.sh scripts/release.sh \
    .githooks/pre-push \
    tools/pichat/pichat \
    tools/pisession/pisession \
    tools/pibox/bin/pibox tools/pibox/entrypoint.sh tools/pibox/test/smoke.sh
  find tests tools/*/tests -name '*.test.sh' -type f 2>/dev/null
)

echo "== bash -n (syntax) =="
for file in "${SCRIPTS[@]}"; do
  [ -f "$file" ] || continue
  if bash -n "$file"; then
    echo "  ok   $file"
  else
    echo "  FAIL $file"
    rc=1
  fi
done

echo "== shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
  for file in "${SCRIPTS[@]}"; do
    [ -f "$file" ] || continue
    if shellcheck -x "$file"; then
      echo "  ok   $file"
    else
      echo "  FAIL $file"
      rc=1
    fi
  done
else
  echo "  SKIP: shellcheck not installed (apt install shellcheck / brew install shellcheck)"
fi

echo "== shfmt --diff =="
if command -v shfmt >/dev/null 2>&1; then
  for file in "${SCRIPTS[@]}"; do
    [ -f "$file" ] || continue
    if shfmt "${SHFMT_FLAGS[@]}" -d "$file" | grep -q .; then
      echo "  FAIL $file (run: shfmt ${SHFMT_FLAGS[*]} -w $file)"
      shfmt "${SHFMT_FLAGS[@]}" -d "$file"
      rc=1
    else
      echo "  ok   $file"
    fi
  done
else
  echo "  SKIP: shfmt not installed (go install mvdan.cc/sh/v3/cmd/shfmt@latest)"
fi

echo "== test suites =="
while IFS= read -r test_file; do
  [ -f "$test_file" ] || continue
  echo "--- $test_file"
  if bash "$test_file"; then
    echo "  PASS $test_file"
  else
    echo "  FAIL $test_file"
    rc=1
  fi
done < <(find tests tools/*/tests -name '*.test.sh' -type f 2>/dev/null | sort)

echo "== pibox smoke =="
if docker info -f '{{.Runtimes}}' 2>/dev/null | grep -q sysbox-runc; then
  if docker image inspect "${PIBOX_IMAGE:-pibox:latest}" >/dev/null 2>&1; then
    if bash tools/pibox/test/smoke.sh "${PIBOX_IMAGE:-pibox:latest}"; then
      echo "  PASS"
    else
      echo "  FAIL"
      rc=1
    fi
  else
    echo "  SKIP: pibox image not built (run 'pibox build')"
  fi
else
  echo "  SKIP: pibox smoke (no sysbox)"
fi

echo
[ "$rc" -eq 0 ] && echo "check.sh: ALL CHECKS PASSED" || echo "check.sh: SOME CHECKS FAILED"
exit "$rc"
