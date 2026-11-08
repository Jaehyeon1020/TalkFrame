#!/usr/bin/env python3
"""Generate a standard, unauthenticated cask from a universal release ZIP."""
import hashlib
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parents[1]
version = plistlib.loads((root / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
archive = root / f"build/TalkFrame-{version}-macos-universal.zip"
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
output = root / "Casks/talkframe.rb"
output.parent.mkdir(exist_ok=True)
output.write_text(f'''# frozen_string_literal: true

cask "talkframe" do
  version "{version}"
  sha256 "{checksum}"

  url "https://github.com/Jaehyeon1020/TalkFrame/releases/download/v#{{version}}/TalkFrame-#{{version}}-macos-universal.zip"
  name "톡프레임"
  name "TalkFrame"
  desc "Display a chosen image in the KakaoTalk banner area"
  homepage "https://github.com/Jaehyeon1020/TalkFrame"

  depends_on macos: :ventura

  app "TalkFrame.app"

  caveats <<~EOS
    설치 후 톡프레임에서 이미지를 선택하고 이미지 적용을 눌러 주세요.
    삭제 전에 앱의 원래 설정으로 복구를 실행해야 서버와 hosts 설정이 제거됩니다.
  EOS
end
''')
print(output)
