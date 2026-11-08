import Foundation
import Network
import Security
import Darwin

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// All mutable server state is confined to the main dispatch queue.
final class ImageServer {
    let configuration: String
    var cached: Banner?
    var modified: Date?
    var connections = 0
    var viewport: [String: Int]?
    var viewportUpdated = Date.distantPast
    init(configuration: String) { self.configuration = configuration }

    func banner() throws -> Banner {
        let date = try FileManager.default.attributesOfItem(atPath: configuration)[.modificationDate] as? Date
        if cached == nil || date != modified {
            cached = try Banner.load(configuration)
            modified = date
        }
        return cached!
    }

    func response(_ request: String) -> Data {
        let parts = request.components(separatedBy: "\r\n")[0].split(separator: " ")
        guard parts.count == 3, parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0",
              let url = URLComponents(string: String(parts[1])), url.host == nil else {
            return http("400 Bad Request")
        }
        guard parts[0] == "GET" else { return http("405 Method Not Allowed") }
        do {
            switch url.path {
            case "/talkframe/health":
                let current = try banner()
                let body = try JSONSerialization.data(withJSONObject: [
                    "ok": true, "revision": current.revision, "viewportReporting": true,
                    "viewport": Date().timeIntervalSince(viewportUpdated) < 15 ? (viewport as Any? ?? NSNull()) : NSNull()
                ])
                return http("200 OK", type: "application/json", body: body)
            case "/talkframe/state":
                let current = try banner()
                guard url.queryItems?.first(where: { $0.name == "key" })?.value == current.accessToken else { return http("403 Forbidden") }
                if let widthText = url.queryItems?.first(where: { $0.name == "w" })?.value,
                   let heightText = url.queryItems?.first(where: { $0.name == "h" })?.value,
                   let width = Int(widthText), let height = Int(heightText),
                   (2...16384).contains(width), (2...8192).contains(height) {
                    viewport = ["width": width, "height": height]
                    viewportUpdated = Date()
                }
                let body = try JSONSerialization.data(withJSONObject: ["revision": current.revision, "fit": current.fit.rawValue])
                return http("200 OK", type: "application/json", body: body, cors: true)
            case "/talkframe/image":
                let current = try banner()
                guard url.queryItems?.first(where: { $0.name == "key" })?.value == current.accessToken else { return http("403 Forbidden") }
                return http("200 OK", type: "image/jpeg", body: current.imageData!, cors: true)
            case "/sdk/banner":
                return http("200 OK", type: "application/json", body: try banner().adResponse())
            default:
                return http("204 No Content")
            }
        } catch {
            return http("503 Service Unavailable")
        }
    }

    private func http(_ status: String, type: String = "text/plain", body: Data = Data(), cors: Bool = false) -> Data {
        let access = cors ? "Access-Control-Allow-Origin: *\r\n" : ""
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\(access)X-TalkFrame: 1\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    func accept(_ connection: NWConnection) {
        guard connections < 32 else { connection.cancel(); return }
        connections += 1
        var finished = false
        let finish = {
            guard !finished else { return }
            finished = true
            self.connections -= 1
            connection.cancel()
        }
        let timeout = DispatchWorkItem(block: finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)
        connection.stateUpdateHandler = { state in
            if case .failed = state { timeout.cancel(); finish() }
            if case .cancelled = state { timeout.cancel(); finish() }
        }
        connection.start(queue: .main)
        var buffer = Data()
        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, done, error in
                guard !finished else { return }
                if let data { buffer.append(data) }
                guard buffer.count <= 16384 else { timeout.cancel(); finish(); return }
                if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let response = self.response(String(decoding: buffer[..<end.lowerBound], as: UTF8.self))
                    connection.send(content: response, completion: .contentProcessed { _ in timeout.cancel(); finish() })
                } else if done || error != nil { timeout.cancel(); finish() }
                else { receive() }
            }
        }
        receive()
    }
}

let args = CommandLine.arguments
if args.count == 3 && args[1] == "--validate" {
    do { _ = try Banner.load(args[2]); exit(0) } catch { fail(error.localizedDescription) }
}
guard args.count == 4 || args.count == 6 else {
    fail("usage: TalkFrameServer cert.der key.der banner.json [127.x.x.x port]")
}
let host = args.count == 6 ? args[4] : TalkFrame.address
guard host.hasPrefix("127."), host.split(separator: ".").count == 4,
      let port = NWEndpoint.Port(args.count == 6 ? args[5] : "443") else { fail("루프백 주소와 올바른 포트만 허용합니다.") }
guard let certData = FileManager.default.contents(atPath: args[1]),
      let keyData = FileManager.default.contents(atPath: args[2]),
      let cert = SecCertificateCreateWithData(nil, certData as CFData),
      let key = SecKeyCreateWithData(keyData as CFData, [
        kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate
      ] as CFDictionary, nil),
      let identity = SecIdentityCreate(nil, cert, key),
      let tlsIdentity = sec_identity_create(identity) else { fail("인증서 또는 개인 키를 불러올 수 없습니다.") }

if getuid() == 0 && host != "127.0.0.1" {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
    process.arguments = ["lo0", "alias", host, "netmask", "255.255.255.255", "up"]
    do { try process.run(); process.waitUntilExit() } catch { fail(error.localizedDescription) }
    guard process.terminationStatus == 0 else { fail("루프백 주소를 준비할 수 없습니다.") }
}
let tls = NWProtocolTLS.Options()
sec_protocol_options_set_local_identity(tls.securityProtocolOptions, tlsIdentity)
sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: port)
parameters.allowLocalEndpointReuse = true
let listener: NWListener
do { listener = try NWListener(using: parameters) } catch { fail(error.localizedDescription) }
let server = ImageServer(configuration: args[3])
listener.newConnectionHandler = server.accept
listener.stateUpdateHandler = { state in
    switch state {
    case .ready:
        if getuid() == 0 {
            guard setgroups(0, nil) == 0, setgid(UInt32(bitPattern: -2)) == 0,
                  setuid(UInt32(bitPattern: -2)) == 0 else { fail("서버 권한을 낮출 수 없습니다.") }
        }
        do { _ = try server.banner() } catch { fail("이미지 설정을 읽을 수 없습니다: \(error.localizedDescription)") }
        print("TalkFrame ready \(host):\(port.rawValue), uid=\(getuid())")
        fflush(stdout)
    case .failed(let error): fail(error.localizedDescription)
    default: break
    }
}
listener.start(queue: .main)
dispatchMain()
