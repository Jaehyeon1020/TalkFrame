#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
APP="$PWD/build/TalkFrame.app"
[[ -d $APP ]] || { print -u2 "먼저 ./build.sh --universal을 실행해 주세요."; exit 1; }
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCHS=($(lipo -archs "$APP/Contents/MacOS/TalkFrame"))
ARCH=${ARCHS[1]}
[[ ${#ARCHS[@]} -eq 1 ]] || ARCH=universal
WORK=$(mktemp -d "$PWD/build/pkg.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root/Applications"
ditto "$APP" "$WORK/root/Applications/TalkFrame.app"
python3 - "$WORK" "$VERSION" "${ARCHS[@]}" <<'PY'
import plistlib, sys
from pathlib import Path
folder = Path(sys.argv[1])
components = [{
    "RootRelativeBundlePath": "Applications/TalkFrame.app",
    "BundleIsRelocatable": False,
    "BundleIsVersionChecked": True,
    "BundleHasStrictIdentifier": True,
    "BundleOverwriteAction": "upgrade",
}]
(folder / "components.plist").write_bytes(plistlib.dumps(components))
(folder / "requirements.plist").write_bytes(plistlib.dumps({"os": ["13.0"], "arch": sys.argv[3:]}))
PY
pkgbuild --root "$WORK/root" --install-location / --ownership recommended \
  --identifier local.talkframe.pkg --version "$VERSION" \
  --component-plist "$WORK/components.plist" "$WORK/TalkFrame-component.pkg"
productbuild --synthesize --product "$WORK/requirements.plist" \
  --package "$WORK/TalkFrame-component.pkg" "$WORK/Distribution.xml"
python3 - "$WORK/Distribution.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
path = sys.argv[1]
tree = ET.parse(path)
root = tree.getroot()
ET.SubElement(root, "title").text = "톡프레임"
ET.SubElement(root, "welcome", {"file": "welcome.html", "mime-type": "text/html"})
ET.SubElement(root, "conclusion", {"file": "conclusion.html", "mime-type": "text/html"})
ET.SubElement(root, "domains", {"enable_localSystem": "true", "enable_currentUserHome": "false", "enable_anywhere": "false"})
tree.write(path, encoding="utf-8", xml_declaration=True)
PY
OUTPUT="$PWD/build/TalkFrame-$VERSION-macos-$ARCH.pkg"
productbuild --distribution "$WORK/Distribution.xml" --package-path "$WORK" \
  --resources Installer/Resources "$OUTPUT"
(
  cd build
  shasum -a 256 "${OUTPUT:t}" > "${OUTPUT:t}.sha256"
)
print "$OUTPUT"
