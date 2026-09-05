#!/usr/bin/env bash
set -euo pipefail

# Sysbox keeps the inner daemon isolated from the host. The default-zero
# expansion remains safe under nounset when the launcher does not export it.
if [ "${PIBOX_NO_DOCKER:-0}" != "1" ] && ! docker info >/dev/null 2>&1; then
  sudo sh -c 'dockerd >/tmp/dockerd.log 2>&1 &'
fi

exec "$@"
