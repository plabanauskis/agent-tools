#!/usr/bin/env bash
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then set -euo pipefail; fi
SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../lib/common.sh
. "$SOURCE_ROOT/lib/common.sh"
# shellcheck source=../lib/release.sh
. "$SOURCE_ROOT/lib/release.sh"
release_entry() {
  case "${1:-}" in
    cchat | ccsession | ccbox) configure_suite cctools ;;
    cochat | cosession | cobox) configure_suite cotools ;;
    pichat | pisession | pibox) configure_suite pitools ;;
    *)
      usage >&2
      return 1
      ;;
  esac
  RELEASE_ROOT="$(suite_env HOME "$SOURCE_ROOT")/suites/$SUITE"
  main "$@"
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then release_entry "$@"; fi
