#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/module-cache build/icon
/usr/bin/swiftc -swift-version 5 -sdk "$(xcrun --show-sdk-path)" \
  -module-cache-path "$PWD/build/module-cache" scripts/draw-icon.swift -o build/icon/draw-icon
WORK=$(mktemp -d "$PWD/build/icon/render.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
build/icon/draw-icon "$WORK"
mkdir "$WORK/AppIcon.iconset"
for SIZE in 16 32 128 256 512; do
  cp "$WORK/render-$SIZE.png" "$WORK/AppIcon.iconset/icon_${SIZE}x${SIZE}.png"
  DOUBLE=$((SIZE * 2))
  cp "$WORK/render-$DOUBLE.png" "$WORK/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png"
done
iconutil -c icns "$WORK/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$WORK/render-512.png" Resources/AppIcon.png
