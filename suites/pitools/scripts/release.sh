#!/usr/bin/env bash
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then set -euo pipefail; fi
SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
# shellcheck source=../../../lib/common.sh
. "$SOURCE_ROOT/lib/common.sh"
configure_suite pitools
RELEASE_ROOT="$(suite_env HOME "$SOURCE_ROOT")/suites/$SUITE"
# shellcheck source=../../../lib/release.sh
. "$SOURCE_ROOT/lib/release.sh"
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
