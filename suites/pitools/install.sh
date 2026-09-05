#!/usr/bin/env bash
# Compatibility entrypoint; run from a complete agent-tools checkout.
[ "${PITOOLS_TEST_SOURCE:-0}" = 1 ] || set -euo pipefail
SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=../../lib/installer.sh
. "$SOURCE_ROOT/lib/installer.sh"
installer_init pitools
if [ "${PITOOLS_TEST_SOURCE:-0}" != 1 ]; then main "$@"; fi
