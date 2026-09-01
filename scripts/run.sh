#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$(./scripts/package.sh)"
open "$APP"
