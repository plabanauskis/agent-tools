#!/usr/bin/env bash
# One-time: point git at the repo's hooks so 'git push' runs scripts/check.sh.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
echo "Dev hooks enabled (core.hooksPath=.githooks)."
echo "scripts/check.sh will now run on every 'git push' and block it on failure."
