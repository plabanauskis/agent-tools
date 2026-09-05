#!/usr/bin/env bash
# pitools installer — clone the bundle into a user-owned prefix and symlink
# selected tools' commands onto PATH. No sudo. Touches only $PITOOLS_HOME and
# ~/.local/bin. Sourceable for tests via PITOOLS_TEST_SOURCE=1.
[ "${PITOOLS_TEST_SOURCE:-0}" = "1" ] || set -euo pipefail

REPO_URL="${PITOOLS_REPO:-https://github.com/plabanauskis/pitools.git}"
PITOOLS_HOME="${PITOOLS_HOME:-$HOME/.local/share/pitools}"
BIN_DIR="${PITOOLS_BIN:-$HOME/.local/bin}"
BRANCH="${PITOOLS_BRANCH:-main}"
KNOWN_TOOLS="pichat pisession pibox"

# Source the shared manifest helpers from the (already-cloned) prefix. Called
# after clone_or_update — the lib is never needed before the clone exists.
load_lib() {
  PITOOLS_TOOLS_DIR="$PITOOLS_HOME/tools"
  # shellcheck source=lib/pitools-common.sh
  . "$PITOOLS_HOME/lib/pitools-common.sh"
}

have_tty() { (exec </dev/tty) 2>/dev/null; }

clone_or_update() {
  if [ -d "$PITOOLS_HOME/.git" ]; then
    echo "pitools: updating existing clone at $PITOOLS_HOME"
    git -C "$PITOOLS_HOME" pull --ff-only
  else
    echo "pitools: cloning $REPO_URL -> $PITOOLS_HOME"
    mkdir -p "$(dirname "$PITOOLS_HOME")"
    git clone --branch "$BRANCH" "$REPO_URL" "$PITOOLS_HOME"
  fi
}

# Link one tool's command(s); records into ENABLED / SKIPPED / POST.
link_tool() {
  load_manifest "$1"
  if ! platform_ok && [ "${FORCE:-0}" != "1" ]; then
    SKIPPED+=("$1: unsupported on $(current_os) (needs $PLATFORM); enable later: pitools enable $1")
    return 1
  fi
  local miss
  miss="$(missing_deps)"
  if [ -n "$miss" ] && [ "${FORCE:-0}" != "1" ]; then
    SKIPPED+=("$1: missing deps ($miss); install them, then: pitools enable $1")
    return 1
  fi
  mkdir -p "$BIN_DIR"
  local c entry
  entry="$PITOOLS_HOME/tools/$1/$ENTRYPOINT"
  # shellcheck disable=SC2086
  # Deliberate word-splitting: $COMMANDS is a space-separated list from the manifest.
  for c in $COMMANDS; do ln -sf "$entry" "$BIN_DIR/$c"; done
  if [ -n "$miss" ]; then ENABLED+=("$1 (forced; missing $miss)"); else ENABLED+=("$1"); fi
  [ -n "$POST_ENABLE" ] && POST+=("$1: $POST_ENABLE")
  return 0
}

# No explicit selection and no TTY: link every platform-matching, deps-clean
# tool; record skipped ones (with the command to enable each later).
select_tools_auto() {
  local t miss
  # shellcheck disable=SC2086
  # Deliberate word-splitting: $(list_tools) returns a newline-separated list.
  for t in $(list_tools); do
    load_manifest "$t"
    if platform_ok && [ -z "$(missing_deps)" ]; then
      SELECTED+=("$t")
    elif ! platform_ok; then
      SKIPPED+=("$t: unsupported on $(current_os) (needs $PLATFORM); enable later: pitools enable $t")
    else
      miss="$(missing_deps)"
      SKIPPED+=("$t: missing deps ($miss); install them, then: pitools enable $t")
    fi
  done
}

select_tools_interactive() {
  local t extra ans
  echo "Select tools to enable:"
  # shellcheck disable=SC2086
  # Deliberate word-splitting: $(list_tools) returns a newline-separated list.
  for t in $(list_tools); do
    load_manifest "$t"
    extra=''
    platform_ok || extra=" [unsupported on $(current_os)]"
    [ -n "$(missing_deps)" ] && extra="$extra [missing: $(missing_deps)]"
    printf '  enable %s — %s%s? [y/N] ' "$t" "$DESC" "$extra"
    read -r ans </dev/tty 2>/dev/null || ans=n
    case "$ans" in y | Y) SELECTED+=("$t") ;; esac
  done
}

print_summary() {
  echo
  echo "== pitools install summary =="
  if [ "${#ENABLED[@]}" -gt 0 ]; then
    echo "Enabled:"
    printf '  - %s\n' "${ENABLED[@]}"
  else
    echo "Enabled: (none)"
  fi
  if [ "${#SKIPPED[@]}" -gt 0 ]; then
    echo "Skipped:"
    printf '  - %s\n' "${SKIPPED[@]}"
  fi
  if [ "${#POST[@]}" -gt 0 ]; then
    echo "Next steps:"
    printf '  - %s\n' "${POST[@]}"
  fi
  echo "Manage with: pitools list"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
      echo
      echo "WARNING: $BIN_DIR is not on your PATH. Add to your shell rc:"
      echo "  export PATH=\"$BIN_DIR:\$PATH\""
      ;;
  esac
}

usage() {
  cat <<'EOF'
pitools installer

Usage:
  install.sh [--all | --tools=a,b,c] [--force]

  --all           Enable every tool (subject to platform/deps unless --force).
  --tools=LIST    Enable only the named tools (comma-separated).
  --force         Link even when platform support or dependencies are missing.
  (no selection)  Interactive prompt if a TTY is available, else auto-select
                  every platform-matching, deps-clean tool (skips are printed).

Env: PITOOLS_HOME (prefix, default ~/.local/share/pitools),
     PITOOLS_BIN (default ~/.local/bin), PITOOLS_REPO, PITOOLS_BRANCH.
EOF
}

known_tool() { # <name>: pre-clone catalog for validating --tools selections
  local known
  local IFS=' '
  for known in $KNOWN_TOOLS; do
    [ "$known" = "$1" ] && return 0
  done
  return 1
}

select_explicit_tools() { # <csv>: validate and populate SELECTED before clone/update
  local csv="$1" t
  local IFS=,
  if [ -z "$csv" ]; then
    echo "install.sh: --tools requires a comma-separated selection" >&2
    usage >&2
    return 1
  fi
  # shellcheck disable=SC2086
  # Deliberate word-splitting: $csv is an IFS=, delimited list of tool names.
  for t in $csv; do
    if ! known_tool "$t"; then
      echo "install.sh: unknown tool '$t' (available: ${KNOWN_TOOLS// /, })" >&2
      usage >&2
      return 1
    fi
    SELECTED+=("$t")
  done
}

main() {
  FORCE=0
  local sel_all=0 sel_tools=0 sel_csv='' a
  for a in "$@"; do
    case "$a" in
      --all) sel_all=1 ;;
      --tools=*)
        sel_tools=1
        sel_csv="${a#--tools=}"
        ;;
      --force) FORCE=1 ;;
      -h | --help)
        usage
        return 0
        ;;
      *)
        echo "install.sh: unknown arg '$a'" >&2
        usage
        return 1
        ;;
    esac
  done

  SELECTED=()
  if [ "$sel_tools" = 1 ]; then
    select_explicit_tools "$sel_csv" || return 1
  fi

  command -v git >/dev/null 2>&1 || {
    echo "install.sh: git is required" >&2
    return 1
  }
  echo "pitools installer — host $(uname -s)/$(uname -m)"
  clone_or_update
  load_lib # shared manifest helpers now available (current_os, list_tools, ...)

  ENABLED=()
  SKIPPED=()
  POST=()
  if [ "$sel_all" = 1 ]; then
    local t
    # shellcheck disable=SC2086
    # Deliberate word-splitting: $(list_tools) returns a newline-separated list.
    for t in $(list_tools); do SELECTED+=("$t"); done
  elif [ "$sel_tools" != 1 ] && have_tty; then
    select_tools_interactive
  elif [ "$sel_tools" != 1 ]; then
    select_tools_auto
  fi

  # Guard against empty SELECTED: bash 3.2 (macOS stock) throws "unbound variable"
  # when expanding an empty array with set -u. This is a clean no-op on all versions.
  if [ "${#SELECTED[@]}" -gt 0 ]; then
    local t
    for t in "${SELECTED[@]}"; do link_tool "$t" || true; done
  fi

  mkdir -p "$BIN_DIR"
  ln -sf "$PITOOLS_HOME/bin/pitools" "$BIN_DIR/pitools"

  print_summary
}

[ "${PITOOLS_TEST_SOURCE:-0}" = "1" ] || main "$@"
