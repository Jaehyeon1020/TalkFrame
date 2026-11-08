#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/build/TalkFrame.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/module-cache
ARCH=$(uname -m)
FLAGS=(-swift-version 5 -O -sdk "$(xcrun --show-sdk-path)" -module-cache-path "$PWD/build/module-cache" -target "$ARCH-apple-macosx13.0")
/usr/bin/swiftc "${FLAGS[@]}" Sources/Shared/Banner.swift Sources/Server/main.swift -o "$APP/Contents/Resources/TalkFrameServer"
/usr/bin/swiftc "${FLAGS[@]}" -parse-as-library Sources/Shared/Banner.swift Sources/App/*.swift -o "$APP/Contents/MacOS/TalkFrame"
cp scripts/install.sh scripts/uninstall.sh "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP/Contents/Resources/TalkFrameServer"
codesign --force --sign - "$APP"
print "$APP"
