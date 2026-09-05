#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
git -C "$ROOT" config core.hooksPath .githooks
echo 'Installed the agent-tools pre-push check hook.'
