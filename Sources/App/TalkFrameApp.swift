import SwiftUI
import AppKit

@main
struct TalkFrameApp: App {
    @StateObject private var model = Model()
    var body: some Scene {
        WindowGroup("톡프레임") {
            ContentView(model: model)
                .frame(width: 600)
                .fixedSize(horizontal: true, vertical: true)
        }
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

struct ContentView: View {
    @ObservedObject var model: Model
    @Environment(\.colorScheme) private var colorScheme

    private var modeDescription: String {
        switch model.mode {
        case .contain: return "사진 전체를 보여 줍니다. 남는 부분은 배경색으로 채웁니다."
        case .cover: return "영역을 가득 채웁니다. 이미지의 가장자리가 잘릴 수 있습니다."
        case .custom: return model.cropFill ? "선택한 영역으로 빈틈없이 채웁니다. 비율이 다르면 가장자리가 일부 잘릴 수 있습니다." : "선택한 부분 전체를 보여 줍니다. 비율이 다르면 여백이 생길 수 있습니다."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("작은 자리, 나만의 이미지").font(.system(size: 23, weight: .semibold))
                    Text("카카오톡 하단 광고 자리를 좋아하는 사진으로 바꿔 보세요.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("광고 영역 미리보기").font(.headline)
                    Spacer()
                    Label(model.status, systemImage: model.status == "연결 확인됨" ? "checkmark.circle" : "circle.dotted")
                        .font(.caption).foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    ZStack {
                        Color(nsColor: colorScheme == .dark ? .init(white: 0.133, alpha: 1) : .white)
                        if let image = model.previewImage {
                            Image(nsImage: image).resizable()
                                .aspectRatio(contentMode: model.fillsPreview ? .fill : .fit)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                                .accessibilityLabel("선택한 이미지의 광고 영역 미리보기")
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.plus").font(.system(size: 28))
                                Text("이 자리에 나만의 이미지가 표시됩니다").font(.callout)
                            }.foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: model.adSize.map { max(30, min(180, 544 * $0.height / $0.width)) } ?? 132)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.10)))
                Text("실제 광고 영역의 가로세로 비율은 카카오톡 창 크기에 따라 달라집니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.filename).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Text(model.dirty ? "아직 적용하지 않은 변경 사항이 있습니다." : "선택한 이미지는 이 Mac에만 저장됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("이미지 선택…", action: model.chooseImage)
                    .keyboardShortcut("o")
            }

            Picker("이미지 맞춤", selection: $model.mode) {
                ForEach(PresentationMode.allCases) { fit in Text(fit.title).tag(fit) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("이미지 맞춤 방식")
            Text(modeDescription)
                .font(.caption).foregroundStyle(.secondary).padding(.top, -14)

            if model.mode == .custom {
                Toggle("선택 영역으로 꽉 채우기", isOn: $model.cropFill)
                Button("선택 영역 편집…", action: model.editCrop)
                    .disabled(model.image == nil)
            }

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("처음 적용할 때 macOS 관리자 승인과 인증서 신뢰 승인이 필요합니다.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                if model.serverNeedsUpdate {
                    Text("광고 크기 자동 감지를 사용하려면 이미지 적용을 눌러 서버를 업데이트한 뒤 카카오톡을 다시 열어 주세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(model.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.red)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                if model.installed {
                    Button("원래 설정으로 복구…") { model.confirmRestore = true }
                    Button("연결 확인") { Task { await model.check() } }
                }
                Spacer(minLength: 0)
                if model.busy { ProgressView().controlSize(.small).accessibilityLabel("처리 중") }
                Button("이미지 적용", action: model.apply)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.image == nil)
            }
            if model.installed {
                Button("카카오톡 다시 열기…") { model.confirmRestart = true }
                    .font(.caption)
            }
        }
        .padding(28)
        .tint(Color(red: 0.36, green: 0.29, blue: 0.75))
        .disabled(model.busy)
        .sheet(isPresented: $model.showCropEditor) {
            if let image = model.image {
                CropEditor(image: image, selection: model.selection, viewport: model.adSize,
                           onSave: model.finishCrop, onCancel: model.cancelCrop)
                    .task {
                        while !Task.isCancelled {
                            await model.check()
                            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { break }
                        }
                    }
            } else {
                VStack(spacing: 16) {
                    Text("이미지를 먼저 선택해 주세요.")
                    Button("닫기", action: model.cancelCrop)
                }.padding(32)
            }
        }
        .alert("원래 광고 연결로 복구할까요?", isPresented: $model.confirmRestore) {
            Button("취소", role: .cancel) {}
            Button("복구", role: .destructive, action: model.restore)
        } message: {
            Text("로컬 서버와 광고 주소 설정, 인증서 신뢰를 제거합니다. 선택한 이미지는 앱에 보관됩니다.")
        }
        .alert("카카오톡을 종료하고 다시 열까요?", isPresented: $model.confirmRestart) {
            Button("취소", role: .cancel) {}
            Button("다시 열기", action: model.restartKakaoTalk)
        } message: { Text("작성 중인 내용을 확인해 주세요. 설정이 새로 열린 카카오톡에 반영됩니다.") }
    }
}
