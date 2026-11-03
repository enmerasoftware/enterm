#!/bin/zsh
# Builds Enterm.app from the Swift package. Usage: scripts/bundle.sh [debug|release]
set -e
config=${1:-release}
root=${0:A:h:h}
cd "$root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build -c "$config" -j 2
bin=$(swift build -c "$config" -j 2 --show-bin-path)
app="$root/build/Enterm.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/EntermApp" "$app/Contents/MacOS/EntermApp"
cp "$bin/entermd" "$app/Contents/MacOS/entermd"
cp "$bin/enterm" "$app/Contents/MacOS/enterm"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
[[ -f "$root/Resources/Enterm.icns" ]] && cp "$root/Resources/Enterm.icns" "$app/Contents/Resources/Enterm.icns"
codesign --force --sign - --entitlements "$root/Resources/Enterm.entitlements" "$app/Contents/MacOS/entermd" "$app/Contents/MacOS/enterm" >/dev/null 2>&1 || true
codesign --force --sign - --entitlements "$root/Resources/Enterm.entitlements" "$app" >/dev/null 2>&1 || true
echo "$app"
