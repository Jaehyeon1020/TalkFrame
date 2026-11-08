#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
APP="$PWD/build/TalkFrame.app"
[[ -d $APP ]] || { print -u2 "먼저 ./build.sh를 실행해 주세요."; exit 1; }
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCHS=($(lipo -archs "$APP/Contents/MacOS/TalkFrame"))
ARCH=${ARCHS[1]}
[[ ${#ARCHS[@]} -eq 1 ]] || ARCH=universal
NAME="TalkFrame-$VERSION-macos-$ARCH.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "build/$NAME"
(
  cd build
  shasum -a 256 "$NAME" > "$NAME.sha256"
)
print "$PWD/build/$NAME"
