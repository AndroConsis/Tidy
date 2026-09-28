#!/bin/bash
# Builds Tidy.app: compiles the SPM executable in release mode, then
# assembles it into a proper macOS app bundle (needed for notifications,
# SMAppService login-item registration, and TCC/Full Disk Access prompts
# to work — a bare command-line binary can't get any of those).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Tidy"
BUILD_DIR=".build/release"
APP_BUNDLE="build/${APP_NAME}.app"

echo "==> Building release binary"
swift build -c release

echo "==> Assembling ${APP_BUNDLE}"
rm -rf "build"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "AppPackaging/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Copy the SPM resource bundle produced by the build (currently empty, but
# keeps this script correct if resources are added later).
RESOURCE_BUNDLE="${BUILD_DIR}/Tidy_Tidy.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "${APP_BUNDLE}/Contents/Resources/"
fi

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Done: ${APP_BUNDLE}"
echo "Run it with: open \"${APP_BUNDLE}\""
