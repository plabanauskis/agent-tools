#!/usr/bin/env bash
# Shared installer. SOURCE_ROOT points to the checkout containing this code.
# shellcheck source=common.sh
. "$SOURCE_ROOT/lib/common.sh"

installer_init() {
  configure_suite "$1" || return 1
  REPO_URL="$(suite_env REPO 'https://github.com/plabanauskis/harness-tools.git')"
  PREFIX="$(suite_env HOME "$HOME/.local/share/$SUITE")"
  BIN_DIR="$(suite_env BIN "$HOME/.local/bin")"
  BRANCH="$(suite_env BRANCH main)"
}

load_lib() {
  ROOT="$PREFIX/suites/$SUITE"
  TOOLS_DIR="$ROOT/tools"
}

have_tty() { (exec </dev/tty) 2>/dev/null; }

clone_or_update() {
  if [ -e "$PREFIX" ]; then
    PREFIX="$(cd "$PREFIX" && pwd -P)" || return 1
    require_managed_prefix || return 1
    echo "$SUITE: updating existing clone at $PREFIX"
    update_prefix "$PREFIX" || return 1
  else
    echo "$SUITE: cloning $REPO_URL -> $PREFIX"
    mkdir -p "$(dirname "$PREFIX")" || return 1
    git clone --branch "$BRANCH" "$REPO_URL" "$PREFIX" || return 1
    PREFIX="$(cd "$PREFIX" && pwd -P)" || return 1
    if [ ! -f "$PREFIX/lib/installer.sh" ] || [ ! -d "$PREFIX/suites/$SUITE/tools" ]; then
      echo "$SUITE: cloned repository is not a harness-tools monorepo; no links created." >&2
      return 1
    fi
    # Keep the original marker name: existing installed clones depend on it.
    printf '%s\n' "$SUITE" >"$PREFIX/.agent-tools-suite"
  fi
}

link_tool() {
  load_manifest "$1" || return 1
  if ! platform_ok && [ "${FORCE:-0}" != 1 ]; then
    SKIPPED+=("$1: unsupported on $(current_os) (needs $PLATFORM); enable later: $SUITE enable $1")
    return 0
  fi
  local miss c entry
  miss="$(missing_deps)"
  if [ -n "$miss" ] && [ "${FORCE:-0}" != 1 ]; then
    SKIPPED+=("$1: missing deps ($miss); install them, then: $SUITE enable $1")
    return 0
  fi
  mkdir -p "$BIN_DIR" || return 1
  entry="$(entrypoint_path "$1")"
  for c in $COMMANDS; do ln -sf "$entry" "$BIN_DIR/$c" || return 1; done
  if [ -n "$miss" ]; then ENABLED+=("$1 (forced; missing $miss)"); else ENABLED+=("$1"); fi
  [ -z "$POST_ENABLE" ] || POST+=("$1: $POST_ENABLE")
  return 0
}

select_tools_auto() {
  local t miss
  for t in $(list_tools); do
    load_manifest "$t"
    if platform_ok && [ -z "$(missing_deps)" ]; then
      SELECTED+=("$t")
    elif ! platform_ok; then
      SKIPPED+=("$t: unsupported on $(current_os) (needs $PLATFORM); enable later: $SUITE enable $t")
    else
      miss="$(missing_deps)"
      SKIPPED+=("$t: missing deps ($miss); install them, then: $SUITE enable $t")
    fi
  done
}

select_tools_interactive() {
  local t extra ans
  echo 'Select tools to enable:'
  for t in $(list_tools); do
    load_manifest "$t"
    extra=''
    platform_ok || extra=" [unsupported on $(current_os)]"
    [ -z "$(missing_deps)" ] || extra="$extra [missing: $(missing_deps)]"
    printf '  enable %s — %s%s? [y/N] ' "$t" "$DESC" "$extra"
    read -r ans </dev/tty 2>/dev/null || ans=n
    case "$ans" in y | Y) SELECTED+=("$t") ;; esac
  done
}

print_summary() {
  echo
  echo "== $SUITE install summary =="
  if [ "${#ENABLED[@]}" -gt 0 ]; then
    printf 'Enabled:\n'
    printf '  - %s\n' "${ENABLED[@]}"
  else echo 'Enabled: (none)'; fi
  if [ "${#SKIPPED[@]}" -gt 0 ]; then
    printf 'Skipped:\n'
    printf '  - %s\n' "${SKIPPED[@]}"
  fi
  if [ "${#POST[@]}" -gt 0 ]; then
    printf 'Next steps:\n'
    printf '  - %s\n' "${POST[@]}"
  fi
  echo "Manage with: $SUITE list"
  # shellcheck disable=SC2016 # Print a literal shell command for the user.
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) printf '\nWARNING: add your bin directory to PATH:\n  export PATH="%s:$PATH"\n' "$BIN_DIR" ;;
  esac
}

usage() {
  cat <<EOF
$SUITE installer

Usage:
  suites/$SUITE/install.sh [--all | --tools=a,b,c] [--force]
  install.sh --suite=$SUITE [--all | --tools=a,b,c] [--force]

  --all           Enable every eligible tool in this suite.
  --tools=LIST    Enable only these tools (comma-separated).
  --force         Link despite missing dependencies or platform support.
  (no selection)  Interactive picker with a TTY; otherwise eligible tools only.

Env: ${ENV_PREFIX}_HOME (clone prefix, default ~/.local/share/$SUITE),
     ${ENV_PREFIX}_BIN (default ~/.local/bin), ${ENV_PREFIX}_REPO, ${ENV_PREFIX}_BRANCH.
The default repository is public; no GitHub account is required.
For a fork or offline development, set ${ENV_PREFIX}_REPO to its Git URL or local checkout.
EOF
}

select_explicit_tools() {
  local csv="$1" t
  local IFS=,
  case "$csv" in
    '' | ,* | *, | *,,*)
      echo 'install.sh: --tools requires nonempty tool names' >&2
      return 1
      ;;
  esac
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
  local sel_all=0 sel_tools=0 sel_csv='' a t
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
        usage >&2
        return 1
        ;;
    esac
  done
  if [ "$sel_all" = 1 ] && [ "$sel_tools" = 1 ]; then
    echo 'install.sh: choose --all or --tools, not both' >&2
    return 1
  fi
  SELECTED=()
  if [ "$sel_tools" = 1 ]; then select_explicit_tools "$sel_csv" || return 1; fi
  command -v git >/dev/null 2>&1 || {
    echo 'install.sh: git is required' >&2
    return 1
  }
  echo "$SUITE installer — host $(uname -s)/$(uname -m)"
  clone_or_update || return 1
  load_lib
  ENABLED=() SKIPPED=() POST=()
  if [ "$sel_all" = 1 ]; then
    for t in $(list_tools); do SELECTED+=("$t"); done
  elif [ "$sel_tools" != 1 ] && have_tty; then
    select_tools_interactive
  elif [ "$sel_tools" != 1 ]; then
    select_tools_auto
  fi
  if [ "${#SELECTED[@]}" -gt 0 ]; then
    for t in "${SELECTED[@]}"; do link_tool "$t" || return 1; done
  fi
  mkdir -p "$BIN_DIR" || return 1
  ln -sf "$PREFIX/bin/$SUITE" "$BIN_DIR/$SUITE" || return 1
  print_summary
}
