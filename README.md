# 톡프레임 (TalkFrame)

맥 카카오톡의 하단 광고 자리에 직접 선택한 이미지를 표시하는 독립적인 macOS 앱입니다. SwiftUI와 Apple Network/Security 프레임워크로 작성했으며 외부 패키지는 사용하지 않습니다.

## 설치

[GitHub Releases에서 설치 파일 받기](https://github.com/Jaehyeon1020/TalkFrame/releases/latest)

### PKG 설치

`TalkFrame-버전-macos-universal.pkg`를 열고 설치 안내를 따라 주세요. Apple Silicon과 Intel용 실행 파일을 함께 포함하며 `/Applications/TalkFrame.app`에 설치합니다. 설치 후 응용 프로그램 폴더에서 톡프레임을 열고 이미지를 고른 뒤 **이미지 적용**을 누릅니다.

PKG는 앱만 설치합니다. 로컬 광고 서버와 hosts 설정, 사용자 인증서 신뢰는 앱에서 처음 이미지를 적용할 때 구성합니다. 앱 종료 후에도 서버는 계속 실행됩니다. 제거할 때는 앱에서 **원래 설정으로 복구**를 먼저 사용해 주세요.

현재 개인 배포용으로 PKG는 서명되지 않았고, 앱은 로컬 ad-hoc 서명입니다. Apple 공증을 받지 않았으므로 다른 Mac에서 실행을 차단하면 시스템 설정 → 개인정보 보호 및 보안에서 설치/실행을 허용해야 할 수 있습니다.

### Homebrew

`konfirm`처럼 릴리스 파일의 버전과 SHA-256을 고정한 tap 구성을 사용하며, GUI 앱이므로 Cask로 설치합니다. **로그인이나 GitHub CLI 의존성은 없습니다. 저장소와 릴리스가 공개된 뒤 아래 명령을 사용할 수 있습니다.** 비공개 상태에서는 GitHub가 익명 다운로드를 허용하지 않습니다. 이 설정은 저장소의 공개 여부를 변경하지 않습니다.

```sh
brew tap Jaehyeon1020/talkframe https://github.com/Jaehyeon1020/TalkFrame.git
brew install --cask Jaehyeon1020/talkframe/talkframe
open /Applications/TalkFrame.app
```

다른 이름의 저장소에서 tap을 가져오는 경우를 지원하기 위해 위와 같이 원격 주소를 명시합니다. Cask는 표준 GitHub Releases ZIP URL로 내려받으며 인증 헤더나 토큰을 사용하지 않습니다.

업데이트:

```sh
brew update
brew upgrade --cask Jaehyeon1020/talkframe/talkframe
```

삭제는 먼저 앱에서 **원래 설정으로 복구**를 실행한 뒤 아래 명령을 사용해 주세요. Homebrew에서 앱만 제거하면 백그라운드 서버와 hosts 설정은 남습니다.

```sh
brew uninstall --cask Jaehyeon1020/talkframe/talkframe
```

ZIP을 직접 내려받아 압축을 풀고 앱을 응용 프로그램 폴더로 옮기는 방식도 지원합니다. 모든 배포 파일에 SHA-256 파일을 함께 제공합니다.

## 실행

macOS 13 이상과 Apple Command Line Tools가 필요합니다. 기본 빌드는 빌드한 Mac의 아키텍처를 대상으로 합니다. `./build.sh --universal`로 Apple Silicon과 Intel 실행 파일을 함께 만들 수 있습니다. Intel 코드는 교차 컴파일로 생성하며 실제 Intel 하드웨어에서 실행 검증은 별도로 필요합니다.

```sh
./build.sh
open build/TalkFrame.app
```

1. **이미지 선택…**으로 PNG, JPEG, HEIC, TIFF, WebP 중 파일을 고릅니다. 운영체제가 해당 형식을 디코딩할 수 있어야 합니다.
2. **전체 표시**, **영역 채우기**, **직접 선택** 중 하나를 선택합니다. 직접 선택에서는 박스를 이동하거나 모서리를 드래그해 사진의 원하는 부분을 지정합니다. **광고 비율 고정**을 켜면 카카오톡에서 실제로 표시 중인 광고 화면의 가로·세로 크기에 맞춘 프레임이 제공됩니다. **선택 영역으로 꽉 채우기**를 켜면 자른 영역으로 여백 없이 채웁니다(비율이 달라지면 가장자리가 더 잘릴 수 있습니다). 박스 밖을 드래그하면 새 영역을 그릴 수 있고, 슬라이더로도 조절할 수 있습니다. **선택 완료** 후 미리보기를 확인합니다.
3. **이미지 적용**을 누릅니다. 첫 적용 시 macOS 관리자 승인과 사용자 인증서 신뢰 승인이 필요합니다. 비밀번호는 macOS 창에 입력합니다.
4. **카카오톡 다시 열기…**를 누르거나 카카오톡을 직접 종료하고 다시 실행합니다.
5. 이후 이미지를 바꾸고 적용하면 표시 중인 HTML이 약 2초 간격으로 변경을 확인합니다. 카카오톡 웹뷰에서 이 요청이 제한되는 경우 카카오톡을 다시 열어 주세요.

앱을 종료해도 로컬 이미지 서버는 계속 실행됩니다. 자동 업데이트와 로그인 상태 확인 앱은 구현하지 않았습니다. 원상복구하려면 앱의 **원래 설정으로 복구…**를 사용한 다음 카카오톡을 다시 엽니다. 앱만 삭제하면 hosts 설정과 서버가 남으므로 먼저 복구해 주세요.

## 작동 방식

```text
카카오톡 → https://serv.ds.kakao.com/sdk/banner
           ↓ /etc/hosts
           127.84.11.2:443의 로컬 HTTPS 서버
           ↓
           선택한 이미지를 포함한 광고 JSON/HTML
```

광고 영역의 크기는 유지합니다. HTML에 JPEG 이미지를 포함하고 `ReadyToListen` 메시지에 `AdLoaded(result: true)`를 응답합니다. 실제 광고 서버에 요청을 전달하지 않으며 카카오톡 앱 파일, 대화 데이터, 카카오톡 설정은 수정하지 않습니다. 광고 응답 형식과 메시지 프로토콜은 [KleanTalk의 공개 구현](https://github.com/showmeyourway-sketch/KleanTalk)을 조사한 내용을 참고했습니다. KleanTalk의 앱이나 서버를 실행하는 구조는 아닙니다.

첫 HTML에 이미지가 포함되어 있어 별도 이미지 요청 없이 표시할 수 있습니다. 표시 후에는 `/talkframe/state`에서 버전을 확인하고 변경 시 `/talkframe/image`를 읽습니다. 두 경로는 설치별 임의 토큰을 검사합니다. 광고 JSON 응답에는 외부 웹 페이지가 내용을 읽을 수 있는 CORS 허용 헤더를 붙이지 않습니다. 로컬 사용자에 대한 접근 통제 수단은 아니며, 같은 Mac에서 직접 HTTPS 요청을 보내는 사용자는 광고 응답에 포함된 이미지를 읽을 수 있습니다.

이미지는 최대 1600px로 축소하고 투명 영역은 흰색으로 합성한 뒤 JPEG로 변환합니다. 원본 메타데이터는 전달하지 않습니다. 현재 정지 이미지 한 장과 사각형 영역 선택을 지원합니다. 직접 선택한 영역은 잘라낸 JPEG로 전달하며, 전체 표시 또는 꽉 채우기를 고를 수 있습니다. 광고 비율은 HTML의 `window.innerWidth/innerHeight`를 토큰으로 보호된 로컬 상태 요청에 포함하여 측정합니다. 측정값은 서버 메모리에만 저장하며 최근 15초 이내 값만 사용합니다. 창 크기 변경은 다음 폴링에 반영됩니다. 카카오톡을 실행한 상태에서 편집 화면을 열면 실측 비율이 감지되며 고정 프레임도 갱신됩니다. GIF 애니메이션과 슬라이드쇼는 지원하지 않습니다. 원본의 변환 사본과 선택 좌표는 사용자 폴더의 `editor.json`에 보관해 다시 편집할 수 있습니다. 기존 0.2.x 이하에서 업데이트하는 경우 **이미지 적용**을 누르면 서버 실행 파일을 업데이트하며 관리자 승인이 한 번 필요합니다. 그다음 카카오톡을 다시 열어 새 HTML을 받아야 자동 비율 감지가 시작됩니다. 측정 전에는 임의의 4:1 값을 실측값으로 간주하지 않고 감지 대기 상태를 표시합니다. 단순히 선택 영역을 꽉 채우는 기능은 실측 비율이 없어도 사용할 수 있습니다.

## 변경되는 시스템 항목

| 항목 | 위치 / 용도 |
|---|---|
| hosts | `/etc/hosts`의 `# >>> TalkFrame` ~ `# <<< TalkFrame` 블록. `serv.ds.kakao.com`만 IPv4 로컬 서버로 연결하고 IPv6는 차단합니다. |
| 초기 hosts 백업 | `/etc/hosts.talkframe.backup`. 복구 시 전체 백업을 덮어쓰지 않고 관리 블록만 제거하며, 백업은 보관합니다. |
| 서버·인증서 | `/Library/Application Support/TalkFrame/` |
| 이미지 설정 | 위 폴더의 `Content/banner.json`. 설치한 사용자가 쓰고 `nobody` 그룹이 읽습니다. |
| 시스템 서비스 | `/Library/LaunchDaemons/local.talkframe.server.plist` |
| 루프백 주소 | `lo0`의 `127.84.11.2` |
| 인증서 신뢰 | 현재 사용자, `serv.ds.kakao.com`의 SSL 서버 인증 용도로 한정 |
| 선택 이미지 사본 | `~/Library/Application Support/TalkFrame/draft.json`. 복구 후에도 보관합니다. |

인증서는 해당 도메인용 자체 서명 일반 인증서(`CA:FALSE`, 365일)입니다. 개인 키는 root 전용 파일이며 서버는 키를 메모리에 올리고 포트를 준비한 뒤 보조 그룹을 비우고 `nobody`로 권한을 낮춥니다. `127.84.11.2`에서만 요청을 받으며 외부 광고 서버로 프록시하지 않습니다.

hosts는 Mac 전체에 영향을 줍니다. 다른 앱의 같은 광고 도메인 요청도 로컬 서버로 연결됩니다. 해당 도메인을 이미 사용하는 hosts 규칙이 있으면 설치를 중단합니다. 인증서 승인 취소나 설치 오류 후에는 다시 적용하거나 복구 기능을 사용해 주세요. 인증서가 만료되면 복구 후 다시 적용하여 새 인증서를 생성할 수 있습니다.

## 개발 및 검증

```sh
./build.sh
zsh scripts/test.sh
# 배포 파일 준비
./build.sh --universal
zsh scripts/package.sh       # universal ZIP과 SHA-256
zsh scripts/make-pkg.sh      # PKG 설치 파일과 SHA-256
python3 scripts/update-cask.py  # ZIP 체크섬으로 Cask 갱신
```

테스트는 임시 테스트 인증서와 `127.0.0.1`의 임의 고포트를 사용합니다. 관리자 권한, hosts 변경, 인증서 신뢰 등록은 하지 않습니다. 이미지 축소/잘못된 파일, 선택 영역의 픽셀 위치·크기와 좌표 저장, 편집 드래그 범위, 인증서 검증을 거친 HTTPS 광고 응답, 원본 이미지 전달, 설정 교체 반영, JavaScript 로딩 신호/변경 루프, 토큰 검사, 잘못된 설정 복구를 확인합니다. Python 3와 Node.js가 필요합니다.

```text
Sources/App/          이미지 선택, SwiftUI 화면, 설치 및 복구 제어
Sources/Shared/       이미지 설정과 광고 HTML/JSON 생성
Sources/Server/       루프백 HTTPS 서버
scripts/install.sh    관리자 설치 및 hosts 연결
scripts/uninstall.sh  관리 블록과 서비스 복구
Tests/                이미지 변환, HTTPS 통합, JavaScript 검증
```

현재는 초기 프로토타입입니다. 테스트의 가짜 웹뷰 객체는 실제 카카오톡 웹뷰와 다르므로 **실제 카카오톡의 광고 수용과 실시간 이미지 교체는 설치 후 별도 확인이 필요합니다.** 광고 서버 규격이나 카카오톡의 인증서 정책이 바뀌면 동작하지 않을 수 있습니다. 앱은 로컬 ad-hoc 서명이며 Apple 공증은 받지 않았습니다.

## 앱 아이콘

말풍선 안에 산과 해가 있는 사진을 넣은 아이콘입니다. `Resources/AppIcon.svg`에 벡터 원본을, `Resources/AppIcon.png`와 `Resources/AppIcon.icns`에 배포용 파일을 보관합니다. `scripts/draw-icon.swift`와 `scripts/make-icon.sh`가 해상도별 PNG 및 ICNS를 생성하며 앱 빌드에 포함됩니다.

## 릴리스 업데이트

`Resources/Info.plist`의 버전을 갱신하고 위 순서대로 universal 빌드, ZIP, PKG, Cask를 생성합니다. 소스 코드와 Cask를 커밋한 후 같은 버전의 GitHub Release에 ZIP·PKG·각 SHA-256 파일을 첨부합니다. URL과 체크섬이 버전별로 고정되므로 이미 공개한 버전의 ZIP을 교체하는 대신 새 버전을 배포해 주세요.
