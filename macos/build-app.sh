#!/bin/sh
# Builds "build/Academic Assistant.app" from the Swift package (no Xcode needed).
set -e
cd "$(dirname "$0")"

swift build -c release
.build/release/AcademicAssistant --self-check

APP="build/Academic Assistant.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/AcademicAssistant "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" # ad-hoc signature: runs on this Mac; sharing it needs an Apple Developer ID
echo "Built $APP"
