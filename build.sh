#!/bin/bash
# Builds "build/Focus Energy.app". Pass --install to copy it to /Applications, --run to launch it.
# Set UNIVERSAL=1 to build for both Apple Silicon and Intel Macs (used for releases).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Focus Energy.app"

VERSION="$(cat VERSION)"
if [ "${UNIVERSAL:-0}" = "1" ]; then
    swift build -c release --arch arm64 --arch x86_64
else
    swift build -c release
fi
BIN="$(swift build -c release ${UNIVERSAL:+--arch arm64 --arch x86_64} --show-bin-path)"

if [ ! -f Resources/AppIcon.icns ]; then
    TMP="$(mktemp -d)"
    swift scripts/make-icon.swift "$TMP/icon.png"
    mkdir "$TMP/AppIcon.iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
    rm -rf "$TMP"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/FocusPlus" "$APP/Contents/MacOS/FocusPlus"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Desktop widget: a WidgetKit extension inside the app. It is sandboxed and may only read the app's data folder.
APPEX="$APP/Contents/PlugIns/FocusPlusWidget.appex"
mkdir -p "$APPEX/Contents/MacOS"
cp "$BIN/FocusPlusWidget" "$APPEX/Contents/MacOS/FocusPlusWidget"
cp Resources/Widget-Info.plist "$APPEX/Contents/Info.plist"
# The system caches a widget extension by its build number, so every build gets a new one.
BUILD="$(date +%Y%m%d%H%M%S)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APPEX/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APPEX/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
codesign --force --sign - --entitlements Resources/Widget.entitlements "$APPEX"
codesign --force --sign - "$APP"
echo "Built $APP"

for arg in "$@"; do
    case "$arg" in
        --install)
            pkill -x FocusPlus 2>/dev/null || true
            # Wait for the old copy to quit, otherwise the relaunch below can fail.
            for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x FocusPlus >/dev/null || break; /bin/sleep 0.3; done
            rm -rf "/Applications/Focus Energy.app"
            # The app used to be called Focus Plus: remove that copy so only one is left.
            if [ -d "/Applications/Focus Plus.app" ]; then
                /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "/Applications/Focus Plus.app" >/dev/null 2>&1 || true
                rm -rf "/Applications/Focus Plus.app"
            fi
            cp -R "$APP" "/Applications/Focus Energy.app"
            LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
            # Keep one copy only, so Spotlight and the Dock never open a stale one from the build folder.
            "$LSREGISTER" -u "$PWD/$APP" >/dev/null 2>&1 || true
            rm -rf "$APP"
            APP="/Applications/Focus Energy.app"
            echo "Installed $APP"
            # Make the system pick up the new widget code: re-register the app and restart the widget process.
            "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
            pluginkit -a "$APP/Contents/PlugIns/FocusPlusWidget.appex" >/dev/null 2>&1 || true
            pkill -x FocusPlusWidget 2>/dev/null || true
            # The system's widget service keeps drawing the old version until it restarts. It comes back by itself.
            killall chronod 2>/dev/null || true
            ;;
        --run) open "$APP" || { /bin/sleep 2; open "$APP"; } ;;
    esac
done
