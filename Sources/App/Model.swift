import AppKit
import SwiftUI
import Security
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class Model: ObservableObject {
    @Published var image: NSImage?
    @Published var previewImage: NSImage?
    @Published var adSize: CGSize?
    @Published var cropFill = true { didSet { if !loading { dirty = true } } }
    var fillsPreview: Bool { mode == .cover || (mode == .custom && cropFill) }
    var serverNeedsUpdate: Bool {
        guard installed, let bundled = Bundle.main.path(forResource: "TalkFrameServer", ofType: nil),
              let new = FileManager.default.contents(atPath: bundled),
              let old = FileManager.default.contents(atPath: TalkFrame.directory + "/server") else { return installed }
        return new != old
    }
    @Published var mode: PresentationMode = .contain {
        didSet {
            guard !loading, mode != oldValue else { return }
            let previousDirty = dirty
            dirty = true
            refreshPreview()
            if mode == .custom {
                modeBeforeEditor = oldValue
                dirtyBeforeEditor = previousDirty
                showCropEditor = true
            }
        }
    }
    @Published var selection = CropSelection.full
    @Published var showCropEditor = false
    private var loading = true
    private var modeBeforeEditor: PresentationMode = .contain
    private var dirtyBeforeEditor = false
    private var outputFit: ImageFit { fillsPreview ? .cover : .contain }
    private var editorURL: URL { draftURL.deletingLastPathComponent().appendingPathComponent("editor.json") }
    @Published var filename = "이미지를 선택해 주세요"
    @Published var busy = false
    @Published var installed = FileManager.default.fileExists(atPath: TalkFrame.directory + "/server")
    @Published var status = "적용 전"
    @Published var message = "이미지를 고르면 아래에서 미리 볼 수 있습니다."
    @Published var error: String?
    @Published var dirty = false
    @Published var confirmRestore = false
    @Published var confirmRestart = false
    private var jpeg: Data?
    private var appliedRevision: String?
    private var accessToken = UUID().uuidString
    private let draftURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/TalkFrame/draft.json")

    init() {
        // Preview-only launch never changes the user's saved image or system settings.
        if let path = ProcessInfo.processInfo.environment["TALKFRAME_PREVIEW_IMAGE"],
           let banner = try? Banner.load(path), let data = banner.imageData {
            jpeg = data; image = NSImage(data: data); mode = banner.fit == .cover ? .cover : .contain
            selection = .bannerDefault(imageSize: image?.size ?? .zero)
            filename = "미리보기 이미지"; dirty = true
            loading = false; refreshPreview()
            return
        }
        if let banner = try? Banner.load(draftURL.path), let data = banner.imageData {
            accessToken = banner.accessToken
            jpeg = data; image = NSImage(data: data); mode = banner.fit == .cover ? .cover : .contain
            selection = .bannerDefault(imageSize: image?.size ?? .zero)
            filename = "저장된 이미지"
        }
        if let saved = try? Data(contentsOf: editorURL), saved.count <= 4_100_000,
           let editor = try? JSONDecoder().decode(EditorSettings.self, from: saved),
           editor.selection.isValid, let data = Data(base64Encoded: editor.sourceBase64),
           data.count <= 3_000_000, let restored = NSImage(data: data) {
            jpeg = data; image = restored; mode = editor.mode; selection = editor.selection
            cropFill = editor.cropFill ?? false
        }
        loading = false
        refreshPreview()
        if let current = try? Banner.load(TalkFrame.runtime) {
            accessToken = current.accessToken
            appliedRevision = current.revision
            dirty = current.imageBase64 != (try? outputData())?.base64EncodedString() || current.fit != outputFit
        } else { dirty = jpeg != nil }
        Task { await check() }
    }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "이미지 선택"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Self.prepareImage(url)
            jpeg = data; image = NSImage(data: data); filename = url.lastPathComponent
            selection = .bannerDefault(imageSize: image?.size ?? .zero)
            refreshPreview()
            dirty = true
            if mode == .custom { editCrop() }
            dirty = true; error = nil
            message = "미리보기를 확인하고 ‘이미지 적용’을 눌러 주세요."
        } catch { self.error = error.localizedDescription }
    }

    func editCrop() {
        guard image != nil else { return }
        modeBeforeEditor = mode; dirtyBeforeEditor = dirty
        showCropEditor = true
    }

    func finishCrop(_ value: CropSelection) {
        guard value.isValid else { return }
        selection = value; showCropEditor = false; dirty = true
        refreshPreview()
    }

    func cancelCrop() {
        showCropEditor = false
        mode = modeBeforeEditor
        dirty = dirtyBeforeEditor
    }

    private func outputData() throws -> Data {
        guard let jpeg else { throw Self.failure("이미지를 먼저 선택해 주세요.") }
        return mode == .custom ? try ImageCrop.jpeg(jpeg, selection: selection) : jpeg
    }

    private func refreshPreview() {
        guard jpeg != nil else { previewImage = nil; return }
        do { previewImage = NSImage(data: try outputData()) }
        catch { previewImage = image; self.error = error.localizedDescription }
    }

    static func prepareImage(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 40_000_000,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 100_000_000,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary),
              let context = CGContext(data: nil, width: thumbnail.width, height: thumbnail.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw failure("이미지를 읽을 수 없습니다. 40MB 이하의 일반 이미지 파일을 선택해 주세요.")
        }
        // Flatten transparency and discard original metadata, including camera location.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        let output = NSMutableData()
        guard let flat = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw failure("이미지 변환에 실패했습니다.")
        }
        CGImageDestinationAddImage(destination, flat, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 3_000_000 else {
            throw failure("변환한 이미지가 너무 큽니다. 더 작은 이미지를 선택해 주세요.")
        }
        return output as Data
    }

    private static func failure(_ description: String) -> NSError {
        NSError(domain: "TalkFrame", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }

    private func write(_ banner: Banner, to url: URL) throws {
        try banner.validate()
        try JSONEncoder().encode(banner).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
    }

    func apply() {
        guard let jpeg, !busy else { return }
        busy = true; error = nil; status = "적용 중"
        let upgradingServer = serverNeedsUpdate
        Task {
            let oldCertificate = FileManager.default.contents(atPath: TalkFrame.certificate)
            do {
                let banner = Banner(accessToken: accessToken, revision: UUID().uuidString,
                                    imageBase64: try outputData().base64EncodedString(), fit: outputFit)
                try FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let editor = EditorSettings(sourceBase64: jpeg.base64EncodedString(), mode: mode, selection: selection, cropFill: cropFill)
                try JSONEncoder().encode(editor).write(to: editorURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: editorURL.path)
                try write(banner, to: draftURL)
                // First installation or a missing runtime folder needs administrator setup.
                if !installed || serverNeedsUpdate || !FileManager.default.isWritableFile(atPath: URL(fileURLWithPath: TalkFrame.runtime).deletingLastPathComponent().path) {
                    try await runAdmin(script: "install", arguments: [
                        Bundle.main.path(forResource: "TalkFrameServer", ofType: nil) ?? "",
                        draftURL.path, String(getuid())
                    ])
                    installed = true
                } else {
                    try write(banner, to: URL(fileURLWithPath: TalkFrame.runtime))
                }
                guard let certData = FileManager.default.contents(atPath: TalkFrame.certificate),
                      let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
                    throw Self.failure("설치된 인증서를 읽을 수 없습니다. 설정 복구 후 다시 적용해 주세요.")
                }
                var trust: CFArray?
                if SecTrustSettingsCopyTrustSettings(certificate, .user, &trust) != errSecSuccess {
                    let setting: [String: Any] = [
                        kSecTrustSettingsPolicy as String: SecPolicyCreateSSL(true, TalkFrame.host as CFString),
                        kSecTrustSettingsPolicyString as String: TalkFrame.host,
                        kSecTrustSettingsResult as String: SecTrustSettingsResult.trustRoot.rawValue
                    ]
                    let result = SecTrustSettingsSetTrustSettings(certificate, .user, [setting] as CFArray)
                    guard result == errSecSuccess else {
                        throw Self.failure("인증서 신뢰가 완료되지 않았습니다 (\(result)). 이미지 적용을 다시 누르거나 원래 설정으로 복구해 주세요.")
                    }
                }
                if let oldCertificate, oldCertificate != certData { try Self.removeTrust(oldCertificate) }
                appliedRevision = banner.revision
                dirty = false
                await check()
                if status == "연결 확인됨" {
                    message = upgradingServer
                        ? "서버 업데이트를 마쳤습니다. 카카오톡을 다시 연 뒤 선택 영역 편집을 열면 실제 광고 비율이 자동 감지됩니다."
                        : "이미지를 저장했습니다. 처음 적용하셨다면 카카오톡을 다시 열어 주세요. 이후 변경은 표시 중인 이미지에 약 2초 안에 반영됩니다."
                }
            } catch {
                installed = FileManager.default.fileExists(atPath: TalkFrame.directory + "/server")
                self.error = error.localizedDescription
                status = "확인 필요"
            }
            busy = false
        }
    }

    func check() async {
        guard installed else { status = "적용 전"; return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(from: URL(string: "https://\(TalkFrame.host)/talkframe/health")!)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.value(forHTTPHeaderField: "X-TalkFrame") == "1",
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["ok"] as? Bool == true,
                  appliedRevision == nil || json["revision"] as? String == appliedRevision else {
                throw Self.failure("선택한 이미지의 로컬 서버 응답을 확인하지 못했습니다.")
            }
            if let viewport = json["viewport"] as? [String: Int],
               let width = viewport["width"], let height = viewport["height"],
               width > 1, height > 1 {
                adSize = CGSize(width: width, height: height)
            } else { adSize = nil }
            status = "연결 확인됨"
        } catch {
            status = "연결 확인 필요"
            message = "로컬 서버 연결을 확인하지 못했습니다. 최초 인증서 승인을 마친 뒤 다시 확인하거나, 원래 설정으로 복구 후 적용해 주세요."
        }
    }

    private static func removeTrust(_ data: Data) throws {
        guard let cert = SecCertificateCreateWithData(nil, data as CFData) else { return }
        var settings: CFArray?
        guard SecTrustSettingsCopyTrustSettings(cert, .user, &settings) == errSecSuccess else { return }
        let result = SecTrustSettingsRemoveTrustSettings(cert, .user)
        guard result == errSecSuccess else { throw failure("사용자 인증서 신뢰 제거에 실패했습니다 (\(result)).") }
    }

    func restore() {
        guard !busy else { return }
        busy = true; error = nil
        let cert = FileManager.default.contents(atPath: TalkFrame.certificate)
        Task {
            do {
                try await runAdmin(script: "uninstall", arguments: [])
                installed = false; appliedRevision = nil
                if let cert { try Self.removeTrust(cert) }
                status = "적용 전"; dirty = jpeg != nil
                message = "원래 광고 연결로 복구했습니다. 카카오톡을 다시 열면 반영됩니다. 고른 이미지는 앱에 보관됩니다."
            } catch {
                installed = FileManager.default.fileExists(atPath: TalkFrame.directory + "/server")
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func runAdmin(script: String, arguments: [String]) async throws {
        guard let path = Bundle.main.path(forResource: script, ofType: "sh") else {
            throw Self.failure("설치 스크립트를 찾을 수 없습니다.")
        }
        func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = (["/bin/zsh", path] + arguments).map(shellQuote).joined(separator: " ")
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(literal)\" with administrator privileges"
        let result: (Int32, String) = await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardOutput = pipe; process.standardError = pipe
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return (process.terminationStatus, String(decoding: data, as: UTF8.self))
            } catch { return (1, error.localizedDescription) }
        }.value
        guard result.0 == 0 else { throw Self.failure(result.1.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    func restartKakaoTalk() {
        guard !busy else { return }
        Task {
            busy = true
            defer { busy = false }
            let bundleID = "com.kakao.KakaoTalkMac"
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                guard app.terminate() else { error = "카카오톡을 직접 종료한 뒤 다시 열어 주세요."; return }
                for _ in 0..<50 {
                    if app.isTerminated { break }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                guard app.isTerminated else { error = "카카오톡 종료를 기다리고 있습니다. 직접 다시 열어 주세요."; return }
            }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                do { _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
                catch { self.error = error.localizedDescription }
            } else { error = "카카오톡 앱을 찾을 수 없습니다." }
        }
    }
}
