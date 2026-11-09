#!/bin/zsh
# Builds Enterm.app from the Swift package. Usage: scripts/bundle.sh [debug|release] [output folder]
# Without a folder a delivery goes to build/release-<commit>. Only build/test is ever built over:
# someone may be running any other copy.
set -e
config=${1:-release}
root=${0:A:h:h}
cd "$root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
output="${2:-$root/build/release-$(git -C "$root" rev-parse --short HEAD)}"
if [[ -e "$output/Enterm.app" && "$output" != "$root/build/test" ]]; then
  echo "$output/Enterm.app zaten var, üzerine yazılmaz." >&2
  exit 1
fi
swift build -c "$config" -j 2
bin=$(swift build -c "$config" -j 2 --show-bin-path)
app="$output/Enterm.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/EntermApp" "$app/Contents/MacOS/EntermApp"
cp "$bin/entermd" "$app/Contents/MacOS/entermd"
cp "$bin/enterm" "$app/Contents/MacOS/enterm"
# Sparkle, the updater, lives in Frameworks; the app finds it there.
mkdir -p "$app/Contents/Frameworks"
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
otool -l "$app/Contents/MacOS/EntermApp" | grep -q '@executable_path/../Frameworks' ||
  install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/EntermApp"
[[ -x "$root/vendor/whisper/bin/whisper-cli" ]] && cp "$root/vendor/whisper/bin/whisper-cli" "$app/Contents/MacOS/whisper-cli"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
[[ -f "$root/Resources/Enterm.icns" ]] && cp "$root/Resources/Enterm.icns" "$app/Contents/Resources/Enterm.icns"
# macOS refuses notifications to an ad-hoc signature, so a delivery carries the Developer ID when this Mac has it.
# Test builds stay ad-hoc: they never ask anyone for permission.
identity="-"
if [[ "$config" == "release" ]]; then
  found=$(security find-identity -v -p codesigning | awk '/Developer ID Application/ && /\(79N3CT6T46\)/ { print $2; exit }')
  [[ -n "$found" ]] && identity="$found"
fi
codesign --force --deep --sign "$identity" "$app/Contents/Frameworks/Sparkle.framework" >/dev/null 2>&1 || true
codesign --force --sign "$identity" --entitlements "$root/Resources/Enterm.entitlements" "$app/Contents/MacOS/entermd" "$app/Contents/MacOS/enterm" >/dev/null 2>&1 || true
codesign --force --sign "$identity" --entitlements "$root/Resources/Enterm.entitlements" "$app" >/dev/null 2>&1 || true
echo "$app"
