#!/bin/bash
# Builds TaskAlarm.app (universal: Apple Silicon + Intel) into ./build.
#   --install  also copy it to /Applications and launch it
#   --zip      also package build/TaskAlarm.zip for a GitHub release
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Compiling…"
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" 2>&1 | grep -v "x86_64 architecture is deprecated" || true
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP="build/TaskAlarm.app"
rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/TaskAlarm" "$APP/Contents/MacOS/TaskAlarm"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "▸ Drawing the smiley icon…"
swift scripts/make_icon.swift build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "✓ Built $APP"

if [[ " $* " == *" --zip "* ]]; then
    rm -f build/TaskAlarm.zip
    ditto -c -k --keepParent "$APP" build/TaskAlarm.zip
    echo "✓ Packaged build/TaskAlarm.zip"
fi

if [[ " $* " == *" --install "* ]]; then
    pkill -x TaskAlarm 2>/dev/null || true
    rm -rf /Applications/TaskAlarm.app
    cp -R "$APP" /Applications/
    open /Applications/TaskAlarm.app
    echo "✓ Installed to /Applications and launched — look for the smiley in your menu bar."
fi
