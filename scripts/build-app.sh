#!/bin/bash
# Builds AirplayScreen.app without Xcode: swift build + manual bundle assembly + ad-hoc codesign.
# The CLI is the app's executable, installed as `airplay-screen` by the cask's `binary` stanza.
# Usage: scripts/build-app.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0}"
BUNDLE="build/AirplayScreen.app"

echo "Building AirplayScreen ${VERSION}..."
swift build -c release

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp ".build/release/AirplayScreen" "$BUNDLE/Contents/MacOS/airplay-screen"

PLIST="$BUNDLE/Contents/Info.plist"
cp Resources/Info.plist "$PLIST"
# PlistBuddy fails loudly on a typo key; sed would no-op silently
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "$PLIST"

echo "Signing (ad-hoc)..."
codesign --force --sign - "$BUNDLE"

echo "Built: $BUNDLE"
codesign -dv "$BUNDLE"
