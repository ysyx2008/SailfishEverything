#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Everything

APP="dist/Everything.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Everything "$APP/Contents/MacOS/Everything"
cp Resources/Info.plist "$APP/Contents/Info.plist"
open "$APP"
