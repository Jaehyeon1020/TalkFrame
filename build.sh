#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/build/TalkFrame.app"
ARCHES=($(uname -m))
if [[ ${1:-} == --universal ]]; then
  ARCHES=(arm64 x86_64)
elif [[ $# -gt 0 ]]; then
  print -u2 "사용법: ./build.sh [--universal]"; exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/module-cache build/arch
zsh scripts/make-icon.sh
FLAGS=(-swift-version 5 -O -sdk "$(xcrun --show-sdk-path)" -module-cache-path "$PWD/build/module-cache")
for ARCH in "${ARCHES[@]}"; do
  /usr/bin/swiftc "${FLAGS[@]}" -target "$ARCH-apple-macosx13.0" Sources/Shared/Banner.swift Sources/Server/main.swift -o "build/arch/Server-$ARCH"
  /usr/bin/swiftc "${FLAGS[@]}" -target "$ARCH-apple-macosx13.0" -parse-as-library Sources/Shared/Banner.swift Sources/App/*.swift -o "build/arch/App-$ARCH"
done
APP_PARTS=(); SERVER_PARTS=()
for ARCH in "${ARCHES[@]}"; do
  APP_PARTS+=("build/arch/App-$ARCH")
  SERVER_PARTS+=("build/arch/Server-$ARCH")
done
/usr/bin/lipo -create "${APP_PARTS[@]}" -output "$APP/Contents/MacOS/TalkFrame"
/usr/bin/lipo -create "${SERVER_PARTS[@]}" -output "$APP/Contents/Resources/TalkFrameServer"
cp scripts/install.sh scripts/uninstall.sh "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP/Contents/Resources/TalkFrameServer"
codesign --force --sign - "$APP"
print "$APP"
