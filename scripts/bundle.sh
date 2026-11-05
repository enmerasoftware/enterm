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
[[ -x "$root/vendor/whisper/bin/whisper-cli" ]] && cp "$root/vendor/whisper/bin/whisper-cli" "$app/Contents/MacOS/whisper-cli"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
[[ -f "$root/Resources/Enterm.icns" ]] && cp "$root/Resources/Enterm.icns" "$app/Contents/Resources/Enterm.icns"
codesign --force --sign - --entitlements "$root/Resources/Enterm.entitlements" "$app/Contents/MacOS/entermd" "$app/Contents/MacOS/enterm" >/dev/null 2>&1 || true
codesign --force --sign - --entitlements "$root/Resources/Enterm.entitlements" "$app" >/dev/null 2>&1 || true
echo "$app"
