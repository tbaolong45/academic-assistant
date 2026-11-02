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
# A stable local identity keeps the same signature across rebuilds, so the Keychain's "Always Allow" sticks
# (ad-hoc signing changed it on every build and macOS asked for the password once per stored secret).
# Override with SIGN_IDENTITY=…; falls back to ad-hoc when the identity isn't in this Mac's keychain.
IDENTITY="${SIGN_IDENTITY:-Robo Local Signing}"
if ! { security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\"" && codesign --force --sign "$IDENTITY" "$APP"; }; then
    echo "note: signing with \"$IDENTITY\" failed or it isn't installed; using ad-hoc (Keychain prompts return after each rebuild)"
    codesign --force --sign - "$APP"
fi
echo "Built $APP"
