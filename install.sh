#!/usr/bin/env bash
# Select a suite explicitly; installations retain their independent prefixes.
set -euo pipefail
SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
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
      echo 'Private repository: authenticate Git first, or use a local checkout via the suite REPO override.'
      exit 0
      ;;
    *) args+=("$argument") ;;
  esac
done
# shellcheck source=lib/installer.sh
. "$SOURCE_ROOT/lib/installer.sh"
installer_init "$suite"
if [ "${#args[@]}" -gt 0 ]; then main "${args[@]}"; else main; fi
