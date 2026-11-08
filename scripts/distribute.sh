#!/bin/zsh
# Builds Enterm for anyone to download: signed with Developer ID, notarized by Apple, in a DMG.
# Usage: scripts/distribute.sh
# Output: build/dist-<commit>/Enterm-<version>.dmg
# ENTERM_NOTARY_PROFILE names the notarytool keychain profile (default: couchsubs, same team).
set -e
root=${0:A:h:h}
cd "$root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
team=79N3CT6T46
profile="${ENTERM_NOTARY_PROFILE:-couchsubs}"
commit=$(git rev-parse --short HEAD)
out="$root/build/dist-$commit"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Çalışma kopyasında commit edilmemiş değişiklik var; dağıtım yalnız temiz bir commit'ten çıkar." >&2
  exit 1
fi
if [[ -e "$out" ]]; then
  echo "$out zaten var, üzerine yazılmaz." >&2
  exit 1
fi
identity=$(security find-identity -v -p codesigning | awk -v team="($team)" '/Developer ID Application/ && index($0, team) { print $2; exit }')
if [[ -z "$identity" ]]; then
  echo "Developer ID Application sertifikası ($team) Anahtar Zinciri'nde yok." >&2
  exit 1
fi

scripts/bundle.sh release "$out" >/dev/null
app="$out/Enterm.app"
plist="$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
# The build number only ever grows, so an update always reads as newer.
build=$(git rev-list --count HEAD)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$plist"
# Only a distributed build asks GitHub for updates.
feed="https://github.com/enmerasoftware/enterm/releases/latest/download/appcast.xml"
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string $feed" "$plist"

# Inner programs first, the app last; every one with the hardened runtime and a secure timestamp.
sign() { codesign --force --timestamp --options runtime --sign "$identity" "$@"; }
# Sparkle's helpers first, inside out, as its documentation orders them.
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$sparkle/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
sign "$sparkle/Autoupdate"
sign "$sparkle/Updater.app"
sign "$app/Contents/Frameworks/Sparkle.framework"
for program in "$app"/Contents/MacOS/*; do
  [[ "${program:t}" == "EntermApp" ]] && continue
  sign "$program"
done
sign --entitlements "$root/Resources/Enterm.entitlements" "$app"
codesign --verify --deep --strict "$app"

# The app is notarized and stapled on its own, so it opens offline even after leaving the DMG.
notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$profile" --wait --output-format plist > "$out/notary.plist"
  result=$(/usr/libexec/PlistBuddy -c "Print :status" "$out/notary.plist")
  if [[ "$result" != "Accepted" ]]; then
    id=$(/usr/libexec/PlistBuddy -c "Print :id" "$out/notary.plist")
    echo "Apple onayı reddetti ($result). Ayrıntı: xcrun notarytool log $id --keychain-profile $profile" >&2
    exit 1
  fi
}
ditto -c -k --keepParent "$app" "$out/Enterm.zip"
notarize "$out/Enterm.zip"
rm "$out/Enterm.zip"
xcrun stapler staple "$app"

dmg="$out/Enterm-$version.dmg"
stage="$out/stage"
mkdir -p "$stage"
ditto "$app" "$stage/Enterm.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Enterm" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null
rm -rf "$stage"
codesign --force --timestamp --sign "$identity" "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature -v "$dmg"
spctl --assess --type execute -v "$app"
echo "$dmg"
