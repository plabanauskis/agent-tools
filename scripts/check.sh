#!/usr/bin/env bash
# Unified local CI. No image builds, downloads, or live harness sessions.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT" || exit 1
rc=0
scripts=()
while IFS= read -r file; do
  if IFS= read -r first <"$file" && [[ "$first" == '#!'*bash* ]]; then
    scripts+=("$file")
  fi
done < <(find bin lib scripts tests suites .githooks -type f ! -name '*.png' ! -name '*.svg' ! -name '*.md' | sort)
scripts+=(install.sh)

echo '== bash syntax, shellcheck, shfmt =='
for dependency in shellcheck shfmt jq git rg convert identify compare xmllint; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "FAIL: required checker $dependency missing"
    exit 1
  fi
done
for file in "${scripts[@]}"; do
  bash -n "$file" || rc=1
  shellcheck -x -P SCRIPTDIR "$file" || rc=1
  shfmt -i 2 -ci -d "$file" || rc=1
done

echo '== test suites =='
while IFS= read -r file; do
  echo "--- $file"
  if bash "$file"; then echo "PASS $file"; else
    echo "FAIL $file"
    rc=1
  fi
done < <(find tests suites -type f -name '*.test.sh' | sort)

echo '== optional Docker smoke tests =='
# Explicit opt-in as smoke tests launch containers and can write Docker data.
if [ "${AGENT_TOOLS_SMOKE:-0}" != 1 ]; then
  echo 'SKIP: live Docker smoke (set AGENT_TOOLS_SMOKE=1 to opt in)'
elif ! docker info -f '{{.Runtimes}}' 2>/dev/null | grep -q sysbox-runc; then
  echo 'SKIP: live Docker smoke (no sysbox runtime)'
else
  for entry in 'cctools ccbox CCBOX_IMAGE' 'cotools cobox COBOX_IMAGE' 'pitools pibox PIBOX_IMAGE'; do
    read -r suite box variable <<<"$entry"
    image="${!variable:-$box:latest}"
    if docker image inspect "$image" >/dev/null 2>&1; then
      bash "suites/$suite/tools/$box/test/smoke.sh" "$image" || rc=1
    else
      echo "SKIP: $box image not built"
    fi
  done
fi
if [ "$rc" = 0 ]; then echo 'check.sh: ALL CHECKS PASSED'; else echo 'check.sh: SOME CHECKS FAILED'; fi
exit "$rc"
