#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f Resources/AppIcon.icns || ! -f Resources/MenuBarIcon.png ]]; then
  /usr/bin/swift scripts/make-icon.swift >&2
fi

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  swift build -c release --product SailfishEverything --arch arm64 >&2
  swift build -c release --product SailfishEverything --arch x86_64 >&2
fi

pick_binary() {
  local arch="$1"
  local candidates=(
    ".build/${arch}-apple-macosx/release/SailfishEverything"
    ".build/release/${arch}/SailfishEverything"
  )
  local path
  for path in "${candidates[@]}"; do
    if [[ -x "$path" ]]; then
      print -r -- "$path"
      return 0
    fi
  done
  return 1
}

ARM_BIN="$(pick_binary arm64 || true)"
X86_BIN="$(pick_binary x86_64 || true)"
UNIVERSAL=".build/release/SailfishEverything-universal"
mkdir -p .build/release

if [[ -n "${ARM_BIN:-}" && -n "${X86_BIN:-}" ]]; then
  /usr/bin/lipo -create "$ARM_BIN" "$X86_BIN" -output "$UNIVERSAL"
  BIN="$UNIVERSAL"
elif [[ -x .build/release/SailfishEverything ]]; then
  BIN=".build/release/SailfishEverything"
elif [[ -n "${ARM_BIN:-}" ]]; then
  BIN="$ARM_BIN"
elif [[ -n "${X86_BIN:-}" ]]; then
  BIN="$X86_BIN"
elif [[ -x .build/debug/SailfishEverything ]]; then
  BIN=".build/debug/SailfishEverything"
else
  echo "missing SailfishEverything binary" >&2
  exit 1
fi

/usr/bin/strip -rSTx "$BIN" 2>/dev/null || true

APP="dist/Sailfish Everything.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SailfishEverything"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp -R Resources/en.lproj "$APP/Contents/Resources/en.lproj"
cp -R Resources/zh-Hans.lproj "$APP/Contents/Resources/zh-Hans.lproj"
printf 'APPL????' > "$APP/Contents/PkgInfo"

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if /usr/bin/codesign --force --deep --options runtime \
  --entitlements Resources/SailfishEverything.entitlements \
  --sign "$SIGN_IDENTITY" "$APP" >&2; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "signed ad-hoc with hardened runtime" >&2
  else
    echo "signed with $SIGN_IDENTITY" >&2
  fi
fi

make_dmg() {
  local app="$1"
  local dmg="$2"
  local volname="Sailfish Everything"
  local stage rw_dmg mount

  stage="$(mktemp -d /tmp/sailfish-dmg.XXXXXX)"
  cp -R "$app" "$stage/"
  ln -s /Applications "$stage/Applications"

  rw_dmg="${dmg%.dmg}.rw.dmg"
  rm -f "$rw_dmg" "$dmg"
  if [[ -d "/Volumes/${volname}" ]]; then
    /usr/bin/hdiutil detach "/Volumes/${volname}" >&2 || true
  fi
  /usr/bin/hdiutil create -volname "$volname" -srcfolder "$stage" -ov -format UDRW -fs HFS+ "$rw_dmg" >&2
  rm -rf "$stage"

  if ! /usr/bin/hdiutil attach -readwrite -noverify -noautoopen "$rw_dmg" >&2; then
    echo "failed to mount disk image" >&2
    rm -f "$rw_dmg"
    return 1
  fi
  mount="/Volumes/${volname}"
  if [[ ! -d "$mount" ]]; then
    echo "failed to mount disk image" >&2
    rm -f "$rw_dmg"
    return 1
  fi
  sleep 1

  /usr/bin/osascript - "$volname" <<'APPLESCRIPT' >&2 || true
on run argv
  set volName to item 1 of argv
  tell application "Finder"
    tell disk volName
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {240, 180, 880, 560}
      set viewOptions to the icon view options of container window
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 80
      set position of item "Sailfish Everything.app" of container window to {180, 200}
      set position of item "Applications" of container window to {460, 200}
      close
      open
      update without registering applications
      delay 1
    end tell
  end tell
end run
APPLESCRIPT

  rm -rf "$mount/.fseventsd" "$mount/.Trashes" "$mount/.Spotlights-V100" 2>/dev/null || true
  /usr/bin/hdiutil detach "$mount" >&2
  /usr/bin/hdiutil convert "$rw_dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg" >&2
  rm -f "$rw_dmg"
}

DMG="dist/Sailfish Everything.dmg"
if make_dmg "$APP" "$DMG"; then
  echo "dmg $DMG" >&2
else
  STAGE="$(mktemp -d /tmp/sailfish-dmg.XXXXXX)"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  /usr/bin/hdiutil create -volname "Sailfish Everything" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >&2
  rm -rf "$STAGE"
  echo "dmg $DMG (plain)" >&2
fi

if [[ -n "${NOTARIZE_PROFILE:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  /usr/bin/xcrun notarytool submit "$DMG" --keychain-profile "$NOTARIZE_PROFILE" --wait >&2
  /usr/bin/xcrun stapler staple "$DMG" >&2
  /usr/bin/xcrun stapler staple "$APP" >&2
  echo "notarized" >&2
fi

echo "$APP"
