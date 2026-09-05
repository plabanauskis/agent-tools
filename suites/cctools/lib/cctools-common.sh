#!/usr/bin/env bash
# cctools-common.sh — manifest-reading helpers shared by bin/cctools and
# install.sh. Source after setting CCTOOLS_TOOLS_DIR to the bundle's tools/ dir.
# Pure function definitions only — no side effects, no strict-mode toggles — so
# it is safe to source from a strict-mode script or a test harness alike.

current_os() {
  case "$(uname -s)" in
    Linux) echo linux ;;
    Darwin) echo macos ;;
    *) echo unknown ;;
  esac
}

list_tools() {
  local d
  for d in "$CCTOOLS_TOOLS_DIR"/*/; do
    [ -f "${d}tool.manifest" ] && basename "$d"
  done
}

# Load a tool's manifest into the contract vars (reset first so stale values
# never leak between tools).
load_manifest() {
  # shellcheck disable=SC2034
  # SC2034: NAME/ENTRYPOINT/COMMANDS/DEPS/PLATFORM/DESC/POST_ENABLE are assigned
  # here and consumed by callers (bin/cctools, install.sh) after sourcing this lib.
  NAME='' ENTRYPOINT='' COMMANDS='' DEPS='' PLATFORM='' DESC='' POST_ENABLE=''
  # shellcheck source=/dev/null
  . "$CCTOOLS_TOOLS_DIR/$1/tool.manifest"
}

platform_ok() { # uses $PLATFORM
  local os p
  os="$(current_os)"
  # shellcheck disable=SC2086
  # SC2086: $PLATFORM is a space-separated list; word-splitting is intentional.
  for p in $PLATFORM; do [ "$p" = "$os" ] && return 0; done
  return 1
}

missing_deps() { # uses $DEPS -> echoes space-joined missing binaries (empty if none)
  local d out=''
  # shellcheck disable=SC2086
  # SC2086: $DEPS is a space-separated list; word-splitting is intentional.
  for d in $DEPS; do command -v "$d" >/dev/null 2>&1 || out+="$d "; done
  printf '%s' "${out% }"
}

tool_version() { cat "$CCTOOLS_TOOLS_DIR/$1/VERSION" 2>/dev/null || echo '?'; }
entrypoint_path() { printf '%s/%s/%s' "$CCTOOLS_TOOLS_DIR" "$1" "$ENTRYPOINT"; }
