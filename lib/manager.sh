#!/usr/bin/env bash
# Shared lifecycle implementation. common.sh and suite paths are set by the entrypoint.

tool_enabled() {
  local c entry
  entry="$(entrypoint_path "$NAME")"
  for c in $COMMANDS; do
    [ -L "$BIN_DIR/$c" ] && [ "$(readlink "$BIN_DIR/$c")" = "$entry" ] || return 1
  done
  return 0
}

enable_tool() {
  load_manifest "$1" || return 1
  if ! platform_ok && [ "${FORCE:-0}" != 1 ]; then
    echo "$SUITE: $1 does not support $(current_os) (PLATFORM=\"$PLATFORM\")" >&2
    return 1
  fi
  local miss c entry
  miss="$(missing_deps)"
  if [ -n "$miss" ] && [ "${FORCE:-0}" != 1 ]; then
    echo "$SUITE: $1 missing deps: $miss — install them, or '$SUITE enable $1 --force'" >&2
    return 1
  fi
  mkdir -p "$BIN_DIR"
  entry="$(entrypoint_path "$1")"
  for c in $COMMANDS; do ln -sf "$entry" "$BIN_DIR/$c"; done
  echo "enabled $1 (${COMMANDS// /, } -> $BIN_DIR)"
  [ -z "$miss" ] || echo "  warning: linked despite missing deps: $miss"
  [ -z "$POST_ENABLE" ] || echo "  $POST_ENABLE"
  return 0
}

disable_tool() {
  load_manifest "$1" || return 1
  local c link entry removed=0
  entry="$(entrypoint_path "$1")"
  for c in $COMMANDS; do
    link="$BIN_DIR/$c"
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$entry" ]; then
      rm -f "$link"
      removed=1
    fi
  done
  if [ "$removed" = 1 ]; then echo "disabled $1"; else echo "$1 was not enabled"; fi
}

cmd_list() {
  printf '%-12s %-9s %-9s %-12s %s\n' TOOL ENABLED VERSION PLATFORM DEPS
  local t state plat miss
  for t in $(list_tools); do
    load_manifest "$t"
    tool_enabled && state=enabled || state=disabled
    platform_ok && plat=ok || plat="no:$PLATFORM"
    miss="$(missing_deps)"
    [ -z "$miss" ] && miss=ok || miss="missing:$miss"
    printf '%-12s %-9s %-9s %-12s %s\n' "$t" "$state" "$(tool_version "$t")" "$plat" "$miss"
  done
}

cmd_doctor() {
  local tools rc=0 t d
  if [ -n "${1:-}" ]; then
    known_tool "$1" || {
      echo "$SUITE: unknown tool '$1'" >&2
      return 1
    }
    tools="$1"
  else
    tools="$(list_tools)"
  fi
  for t in $tools; do
    load_manifest "$t"
    echo "$t ($(tool_version "$t")) — $DESC"
    if platform_ok; then
      printf '  %-10s ok (%s)\n' platform "$(current_os)"
    else
      printf '  %-10s UNSUPPORTED (needs %s; host %s)\n' platform "$PLATFORM" "$(current_os)"
      rc=1
    fi
    for d in $DEPS; do
      if command -v "$d" >/dev/null 2>&1; then
        printf '  %-10s ok\n' "$d"
      else
        printf '  %-10s MISSING\n' "$d"
        rc=1
      fi
    done
    [ -z "$POST_ENABLE" ] || echo "  note: $POST_ENABLE"
  done
  return "$rc"
}

cmd_update() {
  require_managed_prefix || return 1
  echo "$SUITE: updating $PREFIX"
  update_prefix "$PREFIX" || return 1
  # Start the newly checked-out implementation rather than retain stale functions.
  "${BASH:-bash}" "$PREFIX/bin/$SUITE" relink
}

cmd_relink() {
  require_managed_prefix || return 1
  local t
  for t in $(list_tools); do
    load_manifest "$t"
    if tool_enabled; then
      FORCE=1 enable_tool "$t" >/dev/null || return 1
      echo "re-linked $t"
    fi
  done
  echo "$SUITE: update complete."
}

remove_managed_links() {
  local t c link entry manager_link expected
  for t in $(list_tools); do
    load_manifest "$t"
    entry="$(entrypoint_path "$t")"
    for c in $COMMANDS; do
      link="$BIN_DIR/$c"
      if [ -L "$link" ] && [ "$(readlink "$link")" = "$entry" ]; then
        rm -f "$link"
        echo "removed $link"
      fi
    done
  done
  manager_link="$BIN_DIR/$SUITE"
  if [ -L "$manager_link" ]; then
    expected="$(readlink "$manager_link")"
    if [ "$expected" = "$PREFIX/bin/$SUITE" ] || [ "$expected" = "$ROOT/bin/$SUITE" ]; then
      rm -f "$manager_link"
      echo "removed $manager_link"
    fi
  fi
  return 0
}

remove_prefix() { # Separated for non-interactive ownership regression tests.
  require_managed_prefix || return 1
  remove_managed_links || return 1
  rm -rf -- "$PREFIX"
}

cmd_uninstall() {
  require_managed_prefix || return 1
  echo "$SUITE uninstall removes its managed clone and owned command symlinks:"
  echo "  prefix: $PREFIX"
  echo "  bindir: $BIN_DIR"
  echo "Run '$BOX uninstall' first only if you also want to remove box artifacts."
  echo "$SUITE never deletes harness sessions, credentials, or Docker data."
  printf 'Remove %s now? [y/N] ' "$SUITE"
  local ans
  read -r ans </dev/tty 2>/dev/null || ans=n
  case "$ans" in y | Y) ;; *)
    echo 'aborted.'
    return 0
    ;;
  esac
  remove_prefix || return 1
  echo "$SUITE uninstalled."
}

cmd_version() {
  if [ -n "${1:-}" ]; then
    known_tool "$1" || {
      echo "$SUITE: unknown tool '$1'" >&2
      return 1
    }
    echo "$1 $(tool_version "$1")"
    return 0
  fi
  local t
  for t in $(list_tools); do echo "$t $(tool_version "$t")"; done
}

usage() {
  cat <<EOF
$SUITE — manage the $SUITE bundle (tools run by their own names)

Usage:
  $SUITE list                    Tools, enabled state, versions, platform and deps
  $SUITE doctor [tool]           Check dependencies and platform
  $SUITE enable <tool> [--force] Link a command into the configured bin directory
  $SUITE disable <tool>          Remove an owned tool link
  $SUITE update                  Sync a clean managed clone and re-link enabled tools
  $SUITE uninstall               Remove owned links and managed clone (prompts first)
  $SUITE version [tool]          Print version(s)
  $SUITE help                    Show help

Overrides: ${ENV_PREFIX}_HOME (clone root), ${ENV_PREFIX}_BIN (link directory).
Update/uninstall require an installer-managed prefix, not a development checkout.
EOF
}

main() {
  local cmd="${1:-help}" a
  shift || true
  FORCE=0
  local rest=()
  for a in "$@"; do
    if [ "$a" = --force ]; then FORCE=1; else rest+=("$a"); fi
  done
  if [ "${#rest[@]}" -gt 0 ]; then set -- "${rest[@]}"; else set --; fi
  case "$cmd" in
    list) cmd_list ;;
    doctor) cmd_doctor "${1:-}" ;;
    enable | disable)
      known_tool "${1:-}" || {
        echo "usage: $SUITE $cmd <tool> [--force]" >&2
        return 1
      }
      "${cmd}_tool" "$1"
      ;;
    update) cmd_update ;;
    relink) cmd_relink ;;
    uninstall) cmd_uninstall ;;
    version) cmd_version "${1:-}" ;;
    help | -h | --help) usage ;;
    *)
      echo "$SUITE: unknown command '$cmd' (try '$SUITE help')" >&2
      return 1
      ;;
  esac
}
