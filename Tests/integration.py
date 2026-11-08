#!/usr/bin/env python3
"""Isolated HTTPS checks. No hosts changes, trust registration, or administrator access."""
import base64
import json
import os
from pathlib import Path
import socket
import ssl
import subprocess
import sys
import time
import uuid

root = Path(__file__).resolve().parents[1]
folder = Path(sys.argv[1]).resolve()
server = root / "build/TalkFrame.app/Contents/Resources/TalkFrameServer"
config = folder / "banner.json"
cnf = folder / "certificate.cnf"
cnf.write_text("""[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=serv.ds.kakao.com
[ext]
subjectAltName=DNS:serv.ds.kakao.com
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
""")
def command(*args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

command("/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "1",
        "-config", str(cnf), "-keyout", str(folder/"key.pem"), "-out", str(folder/"cert.pem"))
command("/usr/bin/openssl", "rsa", "-in", str(folder/"key.pem"), "-outform", "DER", "-out", str(folder/"key.der"))
command("/usr/bin/openssl", "x509", "-in", str(folder/"cert.pem"), "-outform", "DER", "-out", str(folder/"cert.der"))
context = ssl.create_default_context(cafile=str(folder/"cert.pem"))
with socket.socket() as probe:
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
log = open(folder/"server.log", "w")
process = subprocess.Popen([str(server), str(folder/"cert.der"), str(folder/"key.der"), str(config), "127.0.0.1", str(port)], stdout=log, stderr=log)
def request(path, method="GET"):
    with socket.create_connection(("127.0.0.1", port), timeout=5) as raw:
        with context.wrap_socket(raw, server_hostname="serv.ds.kakao.com") as connection:
            connection.sendall(f"{method} {path} HTTP/1.1\r\nHost: serv.ds.kakao.com\r\nConnection: close\r\n\r\n".encode())
            response = b""
            while chunk := connection.recv(65536):
                response += chunk
    header, body = response.split(b"\r\n\r\n", 1)
    assert int(dict(line.split(b": ", 1) for line in header.split(b"\r\n")[1:])[b"Content-Length"]) == len(body)
    return int(header.split()[1]), header, body

try:
    for attempt in range(100):
        if process.poll() is not None:
            raise RuntimeError((folder/"server.log").read_text())
        try:
            status, _, _ = request("/talkframe/health")
            if status == 200: break
        except (OSError, ValueError): time.sleep(0.1)
    else: raise RuntimeError("Server did not start")
    original = json.loads(config.read_text())
    token = original["accessToken"]
    status, headers, body = request("/sdk/banner?test=1")
    payload = json.loads(body)
    assert status == 200 and b"X-TalkFrame: 1" in headers
    assert b"Access-Control-Allow-Origin" not in headers
    assert request("/talkframe/image")[0] == 403
    assert request("/talkframe/state?key=wrong")[0] == 403
    assert payload["status"] == "OK" and len(payload["ads"]) == 1
    html = payload["ads"][0]["content"]
    assert original["imageBase64"] in html and "ReadyToListen" in html and "AdLoaded" in html
    assert "https://serv.ds.kakao.com/talkframe/state" in html
    assert request("/talkframe/image?key=" + token)[2] == base64.b64decode(original["imageBase64"])
    assert request("/talkframe/state?key=" + token)[0] == 200
    request("/talkframe/state?key=" + token + "&w=517&h=89")
    measured = json.loads(request("/talkframe/health")[2])
    assert measured["viewportReporting"] and measured["viewport"] == {"width": 517, "height": 89}
    assert request("/talkframe/state?key=wrong&w=900&h=50")[0] == 403
    request("/talkframe/state?key=" + token + "&w=0&h=NaN")
    assert json.loads(request("/talkframe/health")[2])["viewport"] == measured["viewport"]
    request("/talkframe/state?key=" + token + "&w=641&h=81")
    assert json.loads(request("/talkframe/health")[2])["viewport"] == {"width": 641, "height": 81}
    print("PASS viewport reporting, resized viewport, invalid and unauthorized measurements")
    print("PASS verified TLS, ad envelope, embedded image, state and image endpoints")

    # Exercise the JavaScript bridge and update loop with browser objects, without external traffic.
    html_path = folder/"banner.html"
    html_path.write_text(html)
    subprocess.run(["node", str(root/"Tests/bridge.cjs"), str(html_path)], check=True)

    cropped_image = (folder / "cropped.jpg").read_bytes()
    updated = {**original, "revision": str(uuid.uuid4()), "fit": "cover", "imageBase64": base64.b64encode(cropped_image).decode()}
    temporary = folder/"next.json"
    temporary.write_text(json.dumps(updated))
    os.replace(temporary, config)
    state = json.loads(request("/talkframe/state?key=" + token)[2])
    assert state["revision"] == updated["revision"] and state["fit"] == "cover"
    assert updated["imageBase64"] in json.loads(request("/sdk/banner")[2])["ads"][0]["content"]
    assert request("/talkframe/image?key=" + token)[2] == cropped_image
    assert request("/talkframe/feedback")[0] == 204
    assert request("/elsewhere")[0] == 204
    assert request("/sdk/banner", "POST")[0] == 405
    assert request("/sdk/banner-other")[0] == 204
    print("PASS atomic image/config reload, fit update, feedback and unsupported request handling")
    temporary.write_text('{"invalid":true}')
    os.replace(temporary, config)
    assert request("/sdk/banner")[0] == 503
    temporary.write_text(json.dumps(original))
    os.replace(temporary, config)
    assert request("/sdk/banner")[0] == 200
    print("PASS corrupt configuration fails closed and recovers after replacement")
finally:
    process.terminate()
    process.wait(timeout=5)
    log.close()
