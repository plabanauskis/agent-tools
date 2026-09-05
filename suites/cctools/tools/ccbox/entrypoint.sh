#!/usr/bin/env bash
set -euo pipefail

# Start the inner Docker daemon in the background (sysbox makes this host-safe).
# Set CCBOX_NO_DOCKER=1 to skip for a faster, no-Docker session.
if [ "${CCBOX_NO_DOCKER:-0}" != "1" ] && ! docker info >/dev/null 2>&1; then
  sudo sh -c 'dockerd >/tmp/dockerd.log 2>&1 &'
fi

# Recreate the native-installer launcher symlink the box otherwise lacks. ccbox mounts only
# the read-only versioned binary (~/.local/share/claude/...) and runs it by absolute path, so
# ~/.local/bin/claude is absent and Claude Code's startup install-health check reports it
# "missing or broken". Point it at the exact binary we're about to run (always $1), mirroring
# the host. The bind mount makes Docker auto-create ~/.local as root, so the bin dir needs
# sudo; best-effort — a cosmetic warning must never abort the launch.
case "${1:-}" in
  "$HOME"/.local/share/claude/*)
    if sudo install -d -o "$(id -u)" -g "$(id -g)" "$HOME/.local/bin" 2>/dev/null; then
      ln -sf "$1" "$HOME/.local/bin/claude" 2>/dev/null || true
    fi
    ;;
esac

exec "$@"
