#!/usr/bin/env bash
# cctools installer — clone the bundle into a user-owned prefix and symlink
# selected tools' commands onto PATH. No sudo. Touches only $CCTOOLS_HOME and
# ~/.local/bin. Sourceable for tests via CCTOOLS_TEST_SOURCE=1.
[ "${CCTOOLS_TEST_SOURCE:-0}" = "1" ] || set -euo pipefail

REPO_URL="${CCTOOLS_REPO:-https://github.com/plabanauskis/cctools.git}"
CCTOOLS_HOME="${CCTOOLS_HOME:-$HOME/.local/share/cctools}"
BIN_DIR="${CCTOOLS_BIN:-$HOME/.local/bin}"
BRANCH="${CCTOOLS_BRANCH:-main}"

# Source the shared manifest helpers from the (already-cloned) prefix. Called
# after clone_or_update — the lib is never needed before the clone exists.
load_lib() {
  CCTOOLS_TOOLS_DIR="$CCTOOLS_HOME/tools"
  # shellcheck source=lib/cctools-common.sh
  . "$CCTOOLS_HOME/lib/cctools-common.sh"
}

have_tty() { (exec </dev/tty) 2>/dev/null; }

clone_or_update() {
  if [ -d "$CCTOOLS_HOME/.git" ]; then
    echo "cctools: updating existing clone at $CCTOOLS_HOME"
    git -C "$CCTOOLS_HOME" pull --ff-only
  else
    echo "cctools: cloning $REPO_URL -> $CCTOOLS_HOME"
    mkdir -p "$(dirname "$CCTOOLS_HOME")"
    git clone --branch "$BRANCH" "$REPO_URL" "$CCTOOLS_HOME"
  fi
}

# Link one tool's command(s); records into ENABLED / SKIPPED / POST.
link_tool() {
  load_manifest "$1"
  if ! platform_ok; then
    SKIPPED+=("$1: unsupported on $(current_os) (needs $PLATFORM); enable later: cctools enable $1")
    return 1
  fi
  local miss
  miss="$(missing_deps)"
  if [ -n "$miss" ] && [ "${FORCE:-0}" != "1" ]; then
    SKIPPED+=("$1: missing deps ($miss); install them, then: cctools enable $1")
    return 1
  fi
  mkdir -p "$BIN_DIR"
  local c entry
  entry="$CCTOOLS_HOME/tools/$1/$ENTRYPOINT"
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
      SKIPPED+=("$t: unsupported on $(current_os) (needs $PLATFORM); enable later: cctools enable $t")
    else
      miss="$(missing_deps)"
      SKIPPED+=("$t: missing deps ($miss); install them, then: cctools enable $t")
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
  echo "== cctools install summary =="
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
  echo "Manage with: cctools list"
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
cctools installer

Usage:
  install.sh [--all | --tools=a,b,c] [--force]

  --all           Enable every tool (subject to platform/deps unless --force).
  --tools=LIST    Enable only the named tools (comma-separated).
  --force         Link even when a tool's deps are missing.
  (no selection)  Interactive prompt if a TTY is available, else auto-select
                  every platform-matching, deps-clean tool (skips are printed).

Env: CCTOOLS_HOME (prefix, default ~/.local/share/cctools),
     CCTOOLS_BIN (default ~/.local/bin), CCTOOLS_REPO, CCTOOLS_BRANCH.
EOF
}

main() {
  FORCE=0
  local sel_all=0 sel_csv='' a
  for a in "$@"; do
    case "$a" in
      --all) sel_all=1 ;;
      --tools=*) sel_csv="${a#--tools=}" ;;
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

  command -v git >/dev/null 2>&1 || {
    echo "install.sh: git is required" >&2
    return 1
  }
  echo "cctools installer — host $(uname -s)/$(uname -m)"
  clone_or_update
  load_lib # shared manifest helpers now available (current_os, list_tools, ...)

  SELECTED=()
  ENABLED=()
  SKIPPED=()
  POST=()
  if [ "$sel_all" = 1 ]; then
    local t
    # shellcheck disable=SC2086
    # Deliberate word-splitting: $(list_tools) returns a newline-separated list.
    for t in $(list_tools); do SELECTED+=("$t"); done
  elif [ -n "$sel_csv" ]; then
    local IFS=, t
    # shellcheck disable=SC2086
    # Deliberate word-splitting: $sel_csv is an IFS=, delimited list of tool names.
    for t in $sel_csv; do
      if [ -d "$CCTOOLS_HOME/tools/$t" ]; then SELECTED+=("$t"); else echo "install.sh: unknown tool '$t' (ignored)" >&2; fi
    done
    unset IFS
  elif have_tty; then
    select_tools_interactive
  else
    select_tools_auto
  fi

  # Guard against empty SELECTED: bash 3.2 (macOS stock) throws "unbound variable"
  # when expanding an empty array with set -u. This is a clean no-op on all versions.
  if [ "${#SELECTED[@]}" -gt 0 ]; then
    local t
    for t in "${SELECTED[@]}"; do link_tool "$t" || true; done
  fi

  mkdir -p "$BIN_DIR"
  ln -sf "$CCTOOLS_HOME/bin/cctools" "$BIN_DIR/cctools"

  print_summary
}

[ "${CCTOOLS_TEST_SOURCE:-0}" = "1" ] || main "$@"
