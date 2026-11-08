#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/test
/usr/bin/swiftc -swift-version 5 -sdk "$(xcrun --show-sdk-path)" -module-cache-path "$PWD/build/module-cache" \
  -parse-as-library Sources/Shared/Banner.swift Sources/App/Model.swift Sources/App/ImageCrop.swift Sources/App/CropEditor.swift Tests/ImageCheck.swift -o build/test/ImageCheck
build/test/ImageCheck "$PWD/build/test/fixtures"
python3 Tests/integration.py "$PWD/build/test/fixtures"
zsh -n build.sh scripts/install.sh scripts/uninstall.sh scripts/test.sh
/usr/bin/plutil -lint Resources/Info.plist
codesign --verify --deep --strict build/TalkFrame.app
