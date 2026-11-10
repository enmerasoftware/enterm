#!/bin/zsh
# Builds the phone app for a simulator, signed to run locally. Usage: scripts/build-ios.sh <simulator id>
set -e
root=${0:A:h:h}
cd "$root/enterm-ios"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodegen generate --spec project.yml >/dev/null
xcodebuild -project EntermPhone.xcodeproj -scheme Enterm -destination "platform=iOS Simulator,id=$1" -derivedDataPath build -jobs 2 \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
echo "$root/enterm-ios/build/Build/Products/Debug-iphonesimulator/Enterm.app"
