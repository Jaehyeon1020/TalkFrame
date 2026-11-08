import SwiftUI
import AppKit

@MainActor
final class CropEditorState: ObservableObject {
    @Published var selection: CropSelection
    @Published var lockToAd = true
    @Published var normalizedAspect: Double?
    var dragStart: CropSelection?

    func setAspect(viewport: CGSize?, imageSize: CGSize) {
        guard let viewport, viewport.width > 1, viewport.height > 1,
              imageSize.width > 0, imageSize.height > 0 else { normalizedAspect = nil; return }
        normalizedAspect = (viewport.width / viewport.height) / (imageSize.width / imageSize.height)
        if lockToAd { fitSelection() }
    }

    func fitSelection(reset: Bool = false) {
        guard let ratio = normalizedAspect, ratio > 0 else { return }
        let start = reset ? CropSelection.full : selection
        let width = min(start.width, start.height * ratio, 1, ratio)
        let height = width / ratio
        selection = CropSelection(x: min(max(0, start.x + (start.width - width) / 2), 1 - width),
                                  y: min(max(0, start.y + (start.height - height) / 2), 1 - height),
                                  width: width, height: height)
    }

    private func constrained(anchor: CGPoint, location: CGPoint, left: Bool, top: Bool, ratio: Double) -> CropSelection {
        let maxWidth = min(left ? anchor.x : 1 - anchor.x, (top ? anchor.y : 1 - anchor.y) * ratio)
        let requested = max(abs(location.x - anchor.x), abs(location.y - anchor.y) * ratio)
        let width = min(maxWidth, max(min(0.005, maxWidth), requested))
        let height = width / ratio
        return CropSelection(x: left ? anchor.x - width : anchor.x,
                             y: top ? anchor.y - height : anchor.y, width: width, height: height)
    }
    init(selection: CropSelection) { self.selection = selection }

    func draw(from start: CGPoint, to end: CGPoint, in bounds: CGRect) {
        let a = point(start, in: bounds), b = point(end, in: bounds)
        if lockToAd, let ratio = normalizedAspect {
            let next = constrained(anchor: a, location: b, left: b.x < a.x, top: b.y < a.y, ratio: ratio)
            if next.isValid { selection = next }
            return
        }
        let width = max(0.01, abs(a.x - b.x)), height = max(0.01, abs(a.y - b.y))
        selection = CropSelection(x: min(min(a.x, b.x), 1 - width),
                                  y: min(min(a.y, b.y), 1 - height), width: width, height: height)
    }

    func move(by translation: CGSize, in bounds: CGRect) {
        let start = dragStart ?? selection
        dragStart = start
        selection.x = min(max(0, start.x + translation.width / bounds.width), 1 - start.width)
        selection.y = min(max(0, start.y + translation.height / bounds.height), 1 - start.height)
    }

    func resize(corner: Int, to location: CGPoint, in bounds: CGRect) {
        let start = dragStart ?? selection
        dragStart = start
        let p = point(location, in: bounds)
        let left = corner == 0 || corner == 2
        let top = corner == 0 || corner == 1
        if lockToAd, let ratio = normalizedAspect {
            let anchor = CGPoint(x: left ? start.x + start.width : start.x,
                                 y: top ? start.y + start.height : start.y)
            let next = constrained(anchor: anchor, location: p, left: left, top: top, ratio: ratio)
            if next.isValid { selection = next }
            return
        }
        let x1 = left ? min(p.x, start.x + start.width - 0.01) : start.x
        let y1 = top ? min(p.y, start.y + start.height - 0.01) : start.y
        let x2 = left ? start.x + start.width : max(p.x, start.x + 0.01)
        let y2 = top ? start.y + start.height : max(p.y, start.y + 0.01)
        selection = CropSelection(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }

    func adjust(_ key: WritableKeyPath<CropSelection, Double>, to value: Double) {
        if lockToAd, let ratio = normalizedAspect {
            if key == \.x { selection.x = min(max(0, value), 1 - selection.width) }
            else if key == \.y { selection.y = min(max(0, value), 1 - selection.height) }
            else {
                let desired = key == \.height ? value * ratio : value
                let width = min(max(0.000001, desired), 1 - selection.x, (1 - selection.y) * ratio)
                selection.width = width; selection.height = width / ratio
            }
            return
        }
        var next = selection
        next[keyPath: key] = value
        next.x = min(max(0, next.x), 0.99)
        next.y = min(max(0, next.y), 0.99)
        next.width = min(max(0.01, next.width), 1 - next.x)
        next.height = min(max(0.01, next.height), 1 - next.y)
        selection = next
    }

    private func point(_ location: CGPoint, in bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max((location.x - bounds.minX) / bounds.width, 0), 1),
                y: min(max((location.y - bounds.minY) / bounds.height, 0), 1))
    }
}

struct CropEditor: View {
    let image: NSImage
    let viewport: CGSize?
    let onSave: (CropSelection) -> Void
    let onCancel: () -> Void
    @StateObject private var editor: CropEditorState

    init(image: NSImage, selection: CropSelection, viewport: CGSize? = nil,
         onSave: @escaping (CropSelection) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.viewport = viewport
        self.onSave = onSave
        self.onCancel = onCancel
        _editor = StateObject(wrappedValue: CropEditorState(selection: selection))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("광고에 표시할 부분 선택").font(.title2.weight(.semibold))
            Text("박스를 옮기거나 모서리를 드래그해 조절하세요. 박스 밖을 드래그하면 새로 선택합니다.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Toggle("광고 비율 고정", isOn: $editor.lockToAd)
                    .disabled(viewport == nil)
                    .onChange(of: editor.lockToAd) { locked in if locked { editor.fitSelection() } }
                Spacer()
                if let viewport {
                    Text("광고 영역 \(Int(viewport.width)) × \(Int(viewport.height)) · \(String(format: "%.2f", viewport.width / viewport.height)):1")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("크기 감지 대기 중 · 서버 업데이트 후 카카오톡을 다시 열어 주세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geometry in
                let bounds = imageBounds(in: geometry.size)
                let selected = editor.selection.rect(in: bounds)
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.9)
                    Image(nsImage: image).resizable()
                        .frame(width: bounds.width, height: bounds.height)
                        .position(x: bounds.midX, y: bounds.midY)
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("crop"))
                            .onChanged { value in editor.draw(from: value.startLocation, to: value.location, in: bounds) })
                    Path { path in
                        path.addRect(bounds); path.addRect(selected)
                    }
                    .fill(.black.opacity(0.58), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                    Rectangle().fill(.clear)
                        .overlay(Rectangle().strokeBorder(.white, lineWidth: 2))
                        .frame(width: selected.width, height: selected.height)
                        .contentShape(Rectangle())
                        .position(x: selected.midX, y: selected.midY)
                        .gesture(DragGesture(coordinateSpace: .named("crop"))
                            .onChanged { value in editor.move(by: value.translation, in: bounds) }
                            .onEnded { _ in editor.dragStart = nil })
                    ForEach(0..<4) { corner in
                        Circle().fill(.white)
                            .frame(width: 12, height: 12)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                            .position(x: corner == 0 || corner == 2 ? selected.minX : selected.maxX,
                                      y: corner < 2 ? selected.minY : selected.maxY)
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("crop"))
                                .onChanged { value in editor.resize(corner: corner, to: value.location, in: bounds) }
                                .onEnded { _ in editor.dragStart = nil })
                            .accessibilityHidden(true)
                    }
                }
                .coordinateSpace(name: "crop")
                .clipped()
            }
            .frame(height: 310)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Native sliders provide the same controls to keyboard and VoiceOver users.
            HStack(spacing: 20) {
                VStack(spacing: 8) {
                    adjustment("가로 위치", key: \.x, range: 0...max(0.001, 1 - editor.selection.width))
                    adjustment("세로 위치", key: \.y, range: 0...max(0.001, 1 - editor.selection.height))
                }
                VStack(spacing: 8) {
                    adjustment("선택 너비", key: \.width, range: 0.000001...max(0.000001, 1 - editor.selection.x))
                    adjustment("선택 높이", key: \.height, range: 0.000001...max(0.000001, 1 - editor.selection.y))
                }
            }
            HStack {
                Button("사진 전체") { editor.lockToAd = false; editor.selection = .full }
                Button("광고 비율로 맞추기") { editor.lockToAd = true; editor.fitSelection(reset: true) }.disabled(viewport == nil)
                Spacer()
                Button("취소", action: onCancel).keyboardShortcut(.cancelAction)
                Button("선택 완료") { onSave(editor.selection) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .interactiveDismissDisabled()
        .onAppear { editor.setAspect(viewport: viewport, imageSize: image.size) }
        .onChange(of: viewport) { value in editor.setAspect(viewport: value, imageSize: image.size) }
    }

    private func adjustment(_ title: String, key: WritableKeyPath<CropSelection, Double>,
                            range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 56, alignment: .leading)
            Slider(value: Binding(get: { editor.selection[keyPath: key] },
                                  set: { editor.adjust(key, to: $0) }), in: range)
                .accessibilityLabel(title)
            Text("\(Int((editor.selection[keyPath: key] * 100).rounded()))%")
                .font(.caption.monospacedDigit()).frame(width: 35, alignment: .trailing)
        }
    }

    private func imageBounds(in size: CGSize) -> CGRect {
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let width = image.size.width * scale, height = image.size.height * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
}
