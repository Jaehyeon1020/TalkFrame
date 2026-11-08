#!/usr/bin/env python3
"""Inspect distributable payloads without installing to /Applications."""
from pathlib import Path
import hashlib
import plistlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

root = Path(__file__).resolve().parents[1]
version = plistlib.loads((root / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
zip_path = root / f"build/TalkFrame-{version}-macos-universal.zip"
pkg_path = root / f"build/TalkFrame-{version}-macos-universal.pkg"

def architectures(path):
    return set(subprocess.check_output(["lipo", "-archs", str(path)], text=True).split())

def inspect_app(app):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleShortVersionString"] == version
    assert info["CFBundleIconFile"] == "AppIcon"
    icon = app / "Contents/Resources/AppIcon.icns"
    assert icon.read_bytes().startswith(b"icns") and icon.stat().st_size > 1000
    for binary in [app / "Contents/MacOS/TalkFrame", app / "Contents/Resources/TalkFrameServer"]:
        assert architectures(binary) == {"arm64", "x86_64"}, binary
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    assert sorted(p.name for p in (app / "Contents/Resources").iterdir()) == [
        "AppIcon.icns", "TalkFrameServer", "install.sh", "uninstall.sh"
    ]

for artifact in [zip_path, pkg_path]:
    digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
    assert artifact.with_name(artifact.name + ".sha256").read_text().split()[0] == digest

with tempfile.TemporaryDirectory(prefix="talkframe-package-") as temporary:
    folder = Path(temporary)
    with zipfile.ZipFile(zip_path) as archive:
        assert "TalkFrame.app/Contents/Resources/AppIcon.icns" in archive.namelist()
        archive.extractall(folder / "zip")
    inspect_app(folder / "zip/TalkFrame.app")
    subprocess.run(["pkgutil", "--expand-full", str(pkg_path), str(folder / "pkg")], check=True)
    apps = list((folder / "pkg").rglob("TalkFrame.app"))
    assert len(apps) == 1, apps
    inspect_app(apps[0])
    distribution = ET.parse(folder / "pkg/Distribution").getroot()
    options = distribution.find("options")
    assert options is not None and set(options.attrib["hostArchitectures"].split(",")) == {"arm64", "x86_64"}
    assert distribution.find("welcome").attrib["file"] == "welcome.html"
    assert distribution.find("conclusion").attrib["file"] == "conclusion.html"
    assert not list((folder / "pkg").rglob("postinstall"))
    assert not list((folder / "pkg").rglob("preinstall"))
    info_files = list((folder / "pkg").rglob("PackageInfo"))
    assert len(info_files) == 1
    info = ET.parse(info_files[0]).getroot()
    assert info.attrib["identifier"] == "local.talkframe.pkg" and info.attrib["version"] == version
    bundle = info.find("bundle")
    assert bundle is not None and bundle.attrib["path"].removeprefix("./") == "Applications/TalkFrame.app"

cask = (root / "Casks/talkframe.rb").read_text()
assert hashlib.sha256(zip_path.read_bytes()).hexdigest() in cask
assert f'version "{version}"' in cask
assert all(word not in cask for word in ["GH_TOKEN", "HOMEBREW_GITHUB_API_TOKEN", "PrivateRelease", "depends_on formula"])
print("PASS ZIP/PKG checksums, payload signatures, universal app/server, icon, PKG destinations and standard cask")
