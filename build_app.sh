#!/bin/bash
# Builds a local, sandboxed Tidy.app for testing: same Xcode project,
# entitlements and resources as the App Store build, but ad-hoc signed so it
# runs on this Mac without a provisioning profile. App Store builds are made
# with ./release_app_store.sh instead.
set -euo pipefail
cd "$(dirname "$0")"

DERIVED="build/DerivedData"
APP_BUNDLE="build/Tidy.app"

echo "==> Building Release with Xcode"
xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Release \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build -quiet

echo "==> Copying to ${APP_BUNDLE}"
rm -rf "$APP_BUNDLE"
cp -R "$DERIVED/Build/Products/Release/Tidy.app" "$APP_BUNDLE"

echo "==> Ad-hoc signing with sandbox entitlements"
codesign --force --sign - --options runtime --entitlements AppPackaging/Tidy.entitlements "$APP_BUNDLE"

echo "==> Done: ${APP_BUNDLE}"
echo "Run it with: open \"${APP_BUNDLE}\""
