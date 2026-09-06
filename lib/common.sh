#!/usr/bin/env bash
# Shared suite metadata and manifest helpers. No strict-mode or startup effects.

# shellcheck disable=SC2034 # Suite metadata is consumed by the sourced entrypoints.
configure_suite() {
  SUITE="$1"
  case "$SUITE" in
    cctools)
      ENV_PREFIX=CCTOOLS
      KNOWN_TOOLS='cchat ccsession ccbox'
      BOX=ccbox
      ;;
    cotools)
      ENV_PREFIX=COTOOLS
      KNOWN_TOOLS='cochat cosession cobox'
      BOX=cobox
      ;;
    pitools)
      ENV_PREFIX=PITOOLS
      KNOWN_TOOLS='pichat pisession pibox'
      BOX=pibox
      ;;
    *)
      echo "harness-tools: unknown suite '$SUITE'" >&2
      return 1
      ;;
  esac
}

suite_env() { # <suffix> <default>; preserve the established suite overrides
  local name="${ENV_PREFIX}_$1"
  printf '%s' "${!name:-$2}"
}

known_tool() {
  local known
  local IFS=' ' # Callers may be parsing a comma-separated selection.
  for known in $KNOWN_TOOLS; do
    [ "$known" = "$1" ] && return 0
  done
  return 1
}

current_os() {
  case "$(uname -s)" in
    Linux) echo linux ;;
    Darwin) echo macos ;;
    *) echo unknown ;;
  esac
}

list_tools() {
  local tool
  for tool in $KNOWN_TOOLS; do
    [ -f "$TOOLS_DIR/$tool/tool.manifest" ] && printf '%s\n' "$tool"
  done
}

load_manifest() {
  known_tool "$1" || {
    echo "$SUITE: unknown tool '$1'" >&2
    return 1
  }
  # shellcheck disable=SC2034 # Manifest contract consumed by callers.
  NAME='' ENTRYPOINT='' COMMANDS='' DEPS='' PLATFORM='' DESC='' POST_ENABLE=''
  # shellcheck source=/dev/null
  . "$TOOLS_DIR/$1/tool.manifest"
}

platform_ok() {
  local os p
  os="$(current_os)"
  for p in $PLATFORM; do [ "$p" = "$os" ] && return 0; done
  return 1
}

missing_deps() {
  local d out=''
  for d in $DEPS; do command -v "$d" >/dev/null 2>&1 || out+="$d "; done
  printf '%s' "${out% }"
}

tool_version() { cat "$TOOLS_DIR/$1/VERSION" 2>/dev/null || echo '?'; }
entrypoint_path() { printf '%s/%s/%s' "$TOOLS_DIR" "$1" "$ENTRYPOINT"; }

require_managed_prefix() {
  if [ ! -d "$PREFIX/.git" ] || [ ! -f "$PREFIX/.agent-tools-suite" ] ||
    [ "$(cat "$PREFIX/.agent-tools-suite")" != "$SUITE" ]; then
    echo "$SUITE: $PREFIX is not an installer-managed $SUITE clone; refusing update/removal." >&2
    return 1
  fi
  # Never treat a nested directory or a moved marker as authorization for another repo.
  [ "$(git -C "$PREFIX" rev-parse --show-toplevel)" = "$PREFIX" ] || return 1
}

update_prefix() { # <dir>; only callers decide whether the clone is managed.
  local dir="$1" upstream
  if ! git -C "$dir" diff --quiet || ! git -C "$dir" diff --cached --quiet; then
    echo "$SUITE: local changes in $dir — refusing to overwrite. Remove them and retry." >&2
    return 1
  fi
  git -C "$dir" fetch --prune || return 1
  upstream="$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || {
    echo "$SUITE: no upstream branch configured in $dir" >&2
    return 1
  }
  git -C "$dir" reset --hard "$upstream"
}
