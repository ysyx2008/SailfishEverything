#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f Resources/AppIcon.icns ]]; then
  /usr/bin/swift scripts/make-icon.swift >&2
fi

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  swift build -c release --product SailfishEverything >&2
fi

BIN=".build/release/SailfishEverything"
if [[ ! -x "$BIN" ]]; then
  BIN=".build/debug/SailfishEverything"
fi
if [[ ! -x "$BIN" ]]; then
  echo "missing SailfishEverything binary" >&2
  exit 1
fi

APP="dist/Sailfish Everything.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SailfishEverything"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/en.lproj "$APP/Contents/Resources/en.lproj"
cp -R Resources/zh-Hans.lproj "$APP/Contents/Resources/zh-Hans.lproj"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if /usr/bin/codesign --force --deep --sign - "$APP" >&2; then
  echo "signed ad-hoc" >&2
fi

DMG="dist/Sailfish Everything.dmg"
STAGE="$(mktemp -d /tmp/sailfish-dmg.XXXXXX)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
if /usr/bin/hdiutil create -volname "Sailfish Everything" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >&2; then
  echo "dmg $DMG" >&2
fi
rm -rf "$STAGE"

echo "$APP"
