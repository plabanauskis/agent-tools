#!/usr/bin/env bash
# Local "CI": shellcheck + shfmt (run-if-present) + all test suites + gated ccbox
# smoke. Run from anywhere; resolves the repo root itself. Never a silent pass:
# a missing linter prints SKIP with an install hint, not OK.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
SHFMT_FLAGS=(-i 2 -ci)
rc=0

# All shell scripts we own (imported tool scripts included).
mapfile -t SCRIPTS < <(
  printf '%s\n' \
    install.sh \
    lib/cctools-common.sh \
    bin/cctools \
    scripts/check.sh scripts/dev-setup.sh scripts/release.sh \
    .githooks/pre-push \
    tools/cchat/cchat \
    tools/ccsession/ccsession \
    tools/ccbox/bin/ccbox tools/ccbox/entrypoint.sh tools/ccbox/test/smoke.sh
  find tests tools/*/tests -name '*.test.sh' -type f 2>/dev/null
)

echo "== bash -n (syntax) =="
for f in "${SCRIPTS[@]}"; do
  [ -f "$f" ] || continue
  if bash -n "$f"; then echo "  ok   $f"; else
    echo "  FAIL $f"
    rc=1
  fi
done

echo "== shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
  for f in "${SCRIPTS[@]}"; do
    [ -f "$f" ] || continue
    if shellcheck -x "$f"; then echo "  ok   $f"; else
      echo "  FAIL $f"
      rc=1
    fi
  done
else
  echo "  SKIP: shellcheck not installed (apt install shellcheck / brew install shellcheck)"
fi

echo "== shfmt --diff =="
if command -v shfmt >/dev/null 2>&1; then
  for f in "${SCRIPTS[@]}"; do
    [ -f "$f" ] || continue
    if shfmt "${SHFMT_FLAGS[@]}" -d "$f" | grep -q .; then
      echo "  FAIL $f (run: shfmt ${SHFMT_FLAGS[*]} -w $f)"
      shfmt "${SHFMT_FLAGS[@]}" -d "$f"
      rc=1
    else
      echo "  ok   $f"
    fi
  done
else
  echo "  SKIP: shfmt not installed (go install mvdan.cc/sh/v3/cmd/shfmt@latest)"
fi

echo "== test suites =="
while IFS= read -r t; do
  [ -f "$t" ] || continue
  echo "--- $t"
  if bash "$t"; then echo "  PASS $t"; else
    echo "  FAIL $t"
    rc=1
  fi
done < <(find tests tools/*/tests -name '*.test.sh' -type f 2>/dev/null | sort)

echo "== ccbox smoke =="
if docker info -f '{{.Runtimes}}' 2>/dev/null | grep -q sysbox-runc; then
  if docker image inspect "${CCBOX_IMAGE:-ccbox:latest}" >/dev/null 2>&1; then
    if bash tools/ccbox/test/smoke.sh "${CCBOX_IMAGE:-ccbox:latest}"; then echo "  PASS"; else
      echo "  FAIL"
      rc=1
    fi
  else
    echo "  SKIP: ccbox image not built (run 'ccbox build')"
  fi
else
  echo "  SKIP: ccbox smoke (no sysbox)"
fi

echo
[ "$rc" -eq 0 ] && echo "check.sh: ALL CHECKS PASSED" || echo "check.sh: SOME CHECKS FAILED"
exit "$rc"
