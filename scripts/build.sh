#!/bin/bash
# Uso: scripts/build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=.build/Recorte.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Recorte "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
if security find-certificate -c "Recorte Dev" >/dev/null 2>&1; then
  codesign --force --options runtime --timestamp=none -s "Recorte Dev" "$APP"
else
  codesign --force -s - "$APP"
fi
if [[ "${1:-}" == "--install" ]]; then
  pkill -x Recorte || true
  rm -rf /Applications/Recorte.app
  cp -R "$APP" /Applications/
  open /Applications/Recorte.app
fi
