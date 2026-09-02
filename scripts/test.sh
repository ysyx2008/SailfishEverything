#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> app icon"
if [[ ! -f Resources/AppIcon.icns || ! -f Resources/MenuBarIcon.png ]]; then
  /usr/bin/swift scripts/make-icon.swift
fi

echo "==> build app for launch e2e"
swift build --product SailfishEverything

echo "==> unit / smoke / regression / e2e"
swift run SailfishEverythingTests

echo "==> release speed"
SAILFISH_BENCH=1 swift run -c release SailfishEverythingTests

echo "==> release build and package"
APP="$(./scripts/package.sh)"
test -x "$APP/Contents/MacOS/SailfishEverything"
test -f "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/grep -q "Sailfish Everything" "$APP/Contents/Info.plist"
/usr/bin/grep -q "AppIcon" "$APP/Contents/Info.plist"
/usr/bin/grep -q "旗鱼搜索" "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
/usr/bin/grep -q "Sailfish Everything" "$APP/Contents/Resources/en.lproj/InfoPlist.strings"
echo "packaged $APP"
test -f "dist/Sailfish Everything.dmg"
test -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
/usr/bin/grep -q "LSMinimumSystemVersion" "$APP/Contents/Info.plist"
/usr/bin/grep -q "14.0" "$APP/Contents/Info.plist"
/usr/bin/codesign --verify "$APP"
SIGN_INFO="$(/usr/bin/codesign -d --verbose=4 "$APP" 2>&1 || true)"
print -r -- "$SIGN_INFO" | /usr/bin/grep -q "flags=.*runtime"
ARCHS="$(/usr/bin/lipo -archs "$APP/Contents/MacOS/SailfishEverything")"
print -r -- "$ARCHS" | /usr/bin/grep -q arm64
print -r -- "$ARCHS" | /usr/bin/grep -q x86_64
echo "signed and dmg ready"

echo "==> packaged app e2e"
FIXTURE="$(mktemp -d /tmp/sailfish-pack-e2e.XXXXXX)"
# reuse the test fixture by launching the packaged binary against a tiny tree
mkdir -p "$FIXTURE/Desktop" "$FIXTURE/Downloads"
printf 'x' > "$FIXTURE/Desktop/会议纪要.docx"
printf 'x' > "$FIXTURE/Downloads/photo.jpg"
OUT="$FIXTURE/e2e.json"
SAILFISH_E2E=1 SAILFISH_HOME="$FIXTURE" SAILFISH_E2E_OUT="$OUT" \
  SAILFISH_E2E_QUERIES='["会议","ext:jpg"]' \
  "$APP/Contents/MacOS/SailfishEverything"
/usr/bin/grep -q "会议纪要.docx" "$OUT"
/usr/bin/grep -q "photo.jpg" "$OUT"
/usr/bin/grep -q "Sailfish Everything" "$OUT"
rm -rf "$FIXTURE"

echo "==> all tests passed"
