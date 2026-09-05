#!/usr/bin/env bash
# Keep tool artwork visible, not merely stored in assets directories.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PASS=0
check_icon() { # <readme> <relative asset directory> <expected picture count>
  local readme="$1" assets="$2" expected="$3" matches count variant
  for variant in icon.svg icon-dark.svg; do
    if [ ! -f "$(dirname "$readme")/$assets/$variant" ]; then
      echo "FAIL: broken icon path in $readme: $assets/$variant" >&2
      return 1
    fi
  done
  if ! matches="$(grep -F "<picture><source media=\"(prefers-color-scheme: dark)\" srcset=\"$assets/icon-dark.svg\">" "$readme" |
    grep -F "<img src=\"$assets/icon.svg\"" | grep -F '</picture>')"; then
    echo "FAIL: missing light/dark icon picture in $readme: $assets" >&2
    return 1
  fi
  count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
  if [ "$count" != "$expected" ]; then
    echo "FAIL: expected $expected pictures in $readme for $assets, got $count" >&2
    return 1
  fi
  PASS=$((PASS + 1))
}

for row in 'cctools cchat ccsession ccbox' 'cotools cochat cosession cobox' 'pitools pichat pisession pibox'; do
  read -r suite chat session box <<<"$row"
  for tool in "$chat" "$session" "$box"; do
    check_icon "$ROOT/README.md" "suites/$suite/tools/$tool/assets" 1
    # Suite landing pages retain both their prominent header and table icons.
    check_icon "$ROOT/suites/$suite/README.md" "tools/$tool/assets" 2
  done
done
printf '%d passed, 0 failed\n' "$PASS"
