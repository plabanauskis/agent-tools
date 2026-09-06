#!/usr/bin/env bash
# Compatibility entrypoint; run from a complete harness-tools checkout.
[ "${CCTOOLS_TEST_SOURCE:-0}" = 1 ] || set -euo pipefail
SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=../../lib/installer.sh
. "$SOURCE_ROOT/lib/installer.sh"
installer_init cctools
if [ "${CCTOOLS_TEST_SOURCE:-0}" != 1 ]; then main "$@"; fi
