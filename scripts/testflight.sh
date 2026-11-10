#!/bin/zsh
# Archives the phone app and sends it to TestFlight under Enmera's team. Usage: scripts/testflight.sh [upload|export]
# "export" stops at a signed .ipa in build/testflight; "upload" (default) also sends it to App Store Connect.
# Signing and the upload use the Enmera account signed in to Xcode, or an App Store Connect API key when
# ENTERM_ASC_KEY_PATH, ENTERM_ASC_KEY_ID and ENTERM_ASC_ISSUER are set. The key stays where it is; nothing copies it.
set -e
mode=${1:-upload}
root=${0:A:h:h}
cd "$root/enterm-ios"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
out="$root/build/testflight"
rm -rf "$out"
mkdir -p "$out"
# Every upload needs a build number above the last one; the minute it was made always is.
build=$(date +%Y%m%d%H%M)
auth=()
if [[ -n "$ENTERM_ASC_KEY_PATH" ]]; then
  auth=(-authenticationKeyPath "$ENTERM_ASC_KEY_PATH" -authenticationKeyID "$ENTERM_ASC_KEY_ID" -authenticationKeyIssuerID "$ENTERM_ASC_ISSUER")
fi
xcodegen generate --spec project.yml >/dev/null
xcodebuild -project EntermPhone.xcodeproj -scheme Enterm -configuration Release -destination "generic/platform=iOS" \
  -archivePath "$out/Enterm.xcarchive" -allowProvisioningUpdates "${auth[@]}" -jobs 2 \
  CURRENT_PROJECT_VERSION="$build" archive
cat > "$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>79N3CT6T46</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>$([[ "$mode" == "upload" ]] && echo upload || echo export)</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$out/Enterm.xcarchive" -exportOptionsPlist "$out/ExportOptions.plist" \
  -exportPath "$out" -allowProvisioningUpdates "${auth[@]}"
echo "Derleme numarası $build"
