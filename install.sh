#!/usr/bin/env bash
# Standalone public installer, also usable directly from a complete checkout.
set -euo pipefail
suite=''
args=()
for argument in "$@"; do
  case "$argument" in
    --suite=*)
      [ -z "$suite" ] || {
        echo 'install.sh: specify --suite only once' >&2
        exit 1
      }
      suite="${argument#--suite=}"
      ;;
    -h | --help)
      echo 'Usage: install.sh --suite=cctools|cotools|pitools [--all | --tools=a,b,c] [--force]'
      echo 'Run from a checkout, a downloaded file, or curl | bash -s -- --suite=<suite>.'
      echo 'Requires Bash and Git; no GitHub account or sudo needed.'
      exit 0
      ;;
    --all | --force | --tools=*) args+=("$argument") ;;
    *)
      echo "install.sh: unknown arg '$argument'" >&2
      exit 1
      ;;
  esac
done
case "$suite" in
  cctools | cotools | pitools) ;;
  *)
    echo 'install.sh: --suite must be cctools, cotools, or pitools' >&2
    exit 1
    ;;
esac

# BASH_SOURCE is empty for stdin. Never assume the caller's current directory
# contains a checkout when the installer is piped or downloaded on its own.
SOURCE_ROOT=''
script_path="${BASH_SOURCE[0]:-}"
if [ -n "$script_path" ] && [ -f "$script_path" ]; then
  candidate="$(cd "$(dirname "$script_path")" && pwd -P)"
  if [ -f "$candidate/lib/installer.sh" ] && [ -f "$candidate/suites/$suite/install.sh" ]; then
    SOURCE_ROOT="$candidate"
  fi
fi

if [ -z "$SOURCE_ROOT" ]; then
  command -v git >/dev/null 2>&1 || {
    echo 'install.sh: git is required' >&2
    exit 1
  }
  # Respect the same override names as the shared installer, including forks
  # and local file:// repositories. This bootstrap adds no separate core install.
  env_prefix="$(printf '%s' "$suite" | tr '[:lower:]' '[:upper:]')"
  repo_var="${env_prefix}_REPO"
  branch_var="${env_prefix}_BRANCH"
  repo="${!repo_var:-https://github.com/plabanauskis/agent-tools.git}"
  branch="${!branch_var:-main}"
  BOOTSTRAP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agent-tools-bootstrap.XXXXXX")"
  trap 'rm -rf -- "$BOOTSTRAP_DIR"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  git clone --quiet --depth=1 --branch "$branch" -- "$repo" "$BOOTSTRAP_DIR/source" </dev/null
  SOURCE_ROOT="$BOOTSTRAP_DIR/source"
fi

# Lifecycle, dependency checks, selections, and prefix ownership stay shared.
# shellcheck source=lib/installer.sh
. "$SOURCE_ROOT/lib/installer.sh"
installer_init "$suite"
if [ "${#args[@]}" -gt 0 ]; then main "${args[@]}"; else main; fi
