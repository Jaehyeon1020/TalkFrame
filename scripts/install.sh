#!/bin/zsh
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[[ $EUID -eq 0 && $# -eq 3 ]] || { print -u2 "관리자 권한 및 설치 인자 3개가 필요합니다."; exit 1; }
BINARY=$1
DRAFT=$2
OWNER=$3
[[ $OWNER == <-> && $OWNER -ne 0 && -x $BINARY && -f $DRAFT ]] || exit 1
DIR="/Library/Application Support/TalkFrame"
LABEL=local.talkframe.server
PLIST=/Library/LaunchDaemons/$LABEL.plist
HOST=serv.ds.kakao.com
ADDR=127.84.11.2
BEGIN='# >>> TalkFrame'
END='# <<< TalkFrame'

# Abort before changes if another ad tool or manual rule already owns this hostname.
awk '
  /^# >>> TalkFrame$/ { inside=1; next }
  /^# <<< TalkFrame$/ { inside=0; next }
  !inside && $1 !~ /^#/ { for(i=2;i<=NF;i++) { if($i ~ /^#/) break; if($i=="serv.ds.kakao.com") exit 1 } }
' /etc/hosts || { print -u2 "다른 hosts 규칙이 serv.ds.kakao.com을 사용 중입니다. 기존 광고 도구의 설정을 먼저 해제해 주세요."; exit 1; }
# The privileged directory must never be a link or writable by regular users.
for ITEM in "$DIR" "$DIR/Content" "$DIR/server" "$DIR/cert.pem" "$DIR/cert.der" "$DIR/key.der" "$PLIST"; do
  [[ ! -L $ITEM ]] || { print -u2 "설치 경로가 심볼릭 링크입니다: $ITEM"; exit 1; }
done
if [[ -d $DIR ]]; then
  [[ $(stat -f %u "$DIR") -eq 0 ]] || { print -u2 "설치 폴더의 소유자가 올바르지 않습니다."; exit 1; }
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
umask 077
mkdir -p "$DIR"
chown root:wheel "$DIR"
chmod 755 "$DIR"
mkdir -p "$DIR/Content"
chown "$OWNER":nobody "$DIR/Content"
chmod 750 "$DIR/Content"
# Validate and stage the complete user configuration before touching the running service.
"$BINARY" --validate "$DRAFT"
install -o "$OWNER" -g nobody -m 640 "$DRAFT" "$TMP/banner.json"
if [[ ! -f $DIR/cert.pem || ! -f $DIR/key.der ]] || ! openssl x509 -in "$DIR/cert.pem" -noout -checkend 2592000 >/dev/null 2>&1; then
  cat > "$TMP/certificate.cnf" <<'CNF'
[req]
distinguished_name=subject
x509_extensions=extensions
prompt=no
[subject]
CN=serv.ds.kakao.com
[extensions]
subjectAltName=DNS:serv.ds.kakao.com
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
CNF
  openssl genrsa -out "$TMP/key.pem" 2048 2>/dev/null
  openssl req -new -x509 -sha256 -days 365 -key "$TMP/key.pem" -config "$TMP/certificate.cnf" -out "$TMP/cert.pem"
  openssl rsa -in "$TMP/key.pem" -outform DER -out "$TMP/key.der" 2>/dev/null
  openssl x509 -in "$TMP/cert.pem" -outform DER -out "$TMP/cert.der"
  install -o root -g wheel -m 600 "$TMP/key.der" "$DIR/key.der"
  install -o root -g wheel -m 644 "$TMP/cert.pem" "$DIR/cert.pem"
  install -o root -g wheel -m 644 "$TMP/cert.der" "$DIR/cert.der"
fi
launchctl bootout system/$LABEL 2>/dev/null || true
install -o root -g wheel -m 755 "$BINARY" "$DIR/server"
# Replace the directory entry, rather than following a user-created link inside Content.
mv -f "$TMP/banner.json" "$DIR/Content/banner.json"
cat > "$TMP/service.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.talkframe.server</string>
<key>ProgramArguments</key><array>
<string>/Library/Application Support/TalkFrame/server</string>
<string>/Library/Application Support/TalkFrame/cert.der</string>
<string>/Library/Application Support/TalkFrame/key.der</string>
<string>/Library/Application Support/TalkFrame/Content/banner.json</string>
</array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>10</integer>
</dict></plist>
PLIST
install -o root -g wheel -m 644 "$TMP/service.plist" "$PLIST"
launchctl bootstrap system "$PLIST"
READY=false
for ATTEMPT in {1..12}; do
  if curl --silent --fail --noproxy '*' --connect-timeout 1 --max-time 2 --cacert "$DIR/cert.pem" \
    --resolve "$HOST:443:$ADDR" "https://$HOST/talkframe/health" > "$TMP/health.json"; then
    READY=true
    break
  fi
  sleep 0.5
done
[[ $READY == true ]] || { print -u2 "로컬 서버가 준비되지 않았습니다. hosts 연결은 변경하지 않았습니다. 앱에서 복구하거나 다시 적용해 주세요."; exit 1; }
# Only redirect real requests after a verified HTTPS response from the new server.
[[ -f /etc/hosts.talkframe.backup ]] || cp -p /etc/hosts /etc/hosts.talkframe.backup
awk '
  /^# >>> TalkFrame$/ { inside=1; next }
  /^# <<< TalkFrame$/ { inside=0; next }
  !inside { print }
' /etc/hosts > "$TMP/hosts"
printf '\n%s\n%s %s\n:: %s\n%s\n' "$BEGIN" "$ADDR" "$HOST" "$HOST" "$END" >> "$TMP/hosts"
cat "$TMP/hosts" > /etc/hosts
dscacheutil -flushcache
killall mDNSResponder 2>/dev/null || true
print "설치 완료"
