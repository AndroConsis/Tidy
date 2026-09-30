#!/bin/bash
# Archives Tidy for the Mac App Store and exports a signed installer package.
#
#   ./release_app_store.sh            archive + export build/AppStore/Tidy.pkg
#   ./release_app_store.sh --upload   archive + upload straight to App Store Connect
#
# Signing is automatic via the Apple account signed into Xcode (team
# TGVA34SFZ9). The build number defaults to a timestamp so every upload is
# higher than the last; override with BUILD_NUMBER=42.
set -euo pipefail
cd "$(dirname "$0")"

BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
ARCHIVE="build/Tidy.xcarchive"
EXPORT_DIR="build/AppStore"
DESTINATION="export"
[[ "${1:-}" == "--upload" ]] && DESTINATION="upload"

echo "==> Archiving build ${BUILD_NUMBER}"
rm -rf "$ARCHIVE"
xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Release \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive -quiet

OPTIONS="$(mktemp -t ExportOptions).plist"
cat > "$OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>${DESTINATION}</string>
	<key>teamID</key>
	<string>TGVA34SFZ9</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
EOF

echo "==> Exporting (${DESTINATION})"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$OPTIONS" -allowProvisioningUpdates
rm -f "$OPTIONS"

if [[ "$DESTINATION" == "upload" ]]; then
  echo "==> Uploaded build ${BUILD_NUMBER}. It appears in App Store Connect › TestFlight after processing (usually 5–30 min)."
else
  echo "==> Exported: ${EXPORT_DIR}/Tidy.pkg (build ${BUILD_NUMBER})"
fi
