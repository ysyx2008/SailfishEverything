#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$(./scripts/package.sh)"
DEST="/Applications/Sailfish Everything.app"

quit_running() {
  if ! /usr/bin/pgrep -xq SailfishEverything; then
    return 0
  fi
  /usr/bin/osascript -e 'tell application "Sailfish Everything" to quit' >/dev/null 2>&1 || true
  local i
  for i in {1..20}; do
    /usr/bin/pgrep -xq SailfishEverything || return 0
    sleep 0.25
  done
  /usr/bin/killall SailfishEverything 2>/dev/null || true
}

quit_running

if [[ -e "$DEST" ]]; then
  rm -rf "$DEST"
fi
/usr/bin/ditto "$APP" "$DEST"
echo "installed $DEST" >&2
open "$DEST"
