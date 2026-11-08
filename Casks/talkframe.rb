# frozen_string_literal: true

cask "talkframe" do
  version "0.3.1"
  sha256 "957b3411d4868e2690f066da3ed202cf0d1c31908f090f7d23e76dac6ed91b8a"

  url "https://github.com/Jaehyeon1020/TalkFrame/releases/download/v#{version}/TalkFrame-#{version}-macos-universal.zip"
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
