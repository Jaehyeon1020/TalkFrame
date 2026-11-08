#!/bin/zsh
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[[ $EUID -eq 0 ]] || exit 1
DIR="/Library/Application Support/TalkFrame"
LABEL=local.talkframe.server
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
# Remove our routing first, so a stopped server cannot leave KakaoTalk routed to a dead endpoint.
awk '
  /^# >>> TalkFrame$/ { inside=1; next }
  /^# <<< TalkFrame$/ { inside=0; next }
  !inside { print }
' /etc/hosts > "$TMP"
cat "$TMP" > /etc/hosts
dscacheutil -flushcache
killall mDNSResponder 2>/dev/null || true
launchctl bootout system/$LABEL 2>/dev/null || true
rm -f /Library/LaunchDaemons/$LABEL.plist
[[ ! -L $DIR ]] || { print -u2 "예상하지 못한 설치 경로입니다."; exit 1; }
rm -rf "$DIR"
/sbin/ifconfig lo0 -alias 127.84.11.2 2>/dev/null || true
print "원래 광고 연결로 복구했습니다."
