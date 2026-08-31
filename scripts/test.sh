#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> unit / smoke / regression / e2e"
swift run EverythingTestRunner

echo "==> release build smoke"
swift build -c release --product Everything

echo "==> all tests passed"
