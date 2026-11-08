import AppKit
import ImageIO
import UniformTypeIdentifiers
import SwiftUI

@main
struct ImageCheck {
    @MainActor static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("source.png")
        let image = NSImage(size: NSSize(width: 2400, height: 600))
        image.lockFocus()
        NSGradient(starting: .systemIndigo, ending: .systemTeal)!.draw(in: NSRect(x: 0, y: 0, width: 2400, height: 600), angle: 0)
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: source)
        let jpeg = try Model.prepareImage(source)
        let converted = CGImageSourceCreateWithData(jpeg as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(converted, 0, nil) as! [CFString: Any]
        precondition(properties[kCGImagePropertyPixelWidth] as! Int == 1600)
        precondition(properties[kCGImagePropertyPixelHeight] as! Int == 400)
        precondition(properties[kCGImagePropertyGPSDictionary] == nil)
        let banner = Banner(accessToken: UUID().uuidString, revision: UUID().uuidString, imageBase64: jpeg.base64EncodedString(), fit: .contain)
        try JSONEncoder().encode(banner).write(to: folder.appendingPathComponent("banner.json"))
        let bad = folder.appendingPathComponent("bad.png")
        try Data("not an image".utf8).write(to: bad)
        do { _ = try Model.prepareImage(bad); fatalError("Invalid image accepted") }
        catch { print("PASS image downsampling, metadata stripping, invalid file rejection") }

        // Four known pixel quadrants catch both incorrect crop bounds and inverted Y coordinates.
        var pixels = [UInt8]()
        for y in 0..<80 {
            for x in 0..<100 {
                let color: [UInt8] = y < 40 ? (x < 50 ? [255, 0, 0, 255] : [0, 255, 0, 255])
                                            : (x < 50 ? [0, 0, 255, 255] : [255, 255, 0, 255])
                pixels.append(contentsOf: color)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let quadrants = CGImage(width: 100, height: 80, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: 400, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let png = NSBitmapImageRep(cgImage: quadrants).representation(using: .png, properties: [:])!
        for selection in [
            CropSelection(x: 0, y: 0, width: 0.5, height: 0.5),
            CropSelection(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        ] {
            let cropped = try ImageCrop.jpeg(png, selection: selection)
            let bitmap = NSBitmapImageRep(data: cropped)!
            precondition(bitmap.pixelsWide == 50 && bitmap.pixelsHigh == 40)
            let pixel = bitmap.colorAt(x: 20, y: 20)!.usingColorSpace(.sRGB)!
            let originalPixel = NSBitmapImageRep(data: png)!.colorAt(x: Int(selection.x * 100) + 20, y: Int(selection.y * 80) + 20)!.usingColorSpace(.sRGB)!
            // Compare in the same managed color space; system display profiles may transform primaries.
            precondition(abs(pixel.redComponent - originalPixel.redComponent) < 0.03 &&
                         abs(pixel.greenComponent - originalPixel.greenComponent) < 0.03 &&
                         abs(pixel.blueComponent - originalPixel.blueComponent) < 0.03)
            try cropped.write(to: folder.appendingPathComponent("cropped.jpg"))
        }
        do {
            _ = try ImageCrop.jpeg(png, selection: CropSelection(x: -0.2, y: 0, width: 1, height: 1))
            fatalError("Invalid crop accepted")
        } catch {}
        let settings = EditorSettings(sourceBase64: jpeg.base64EncodedString(), mode: .custom,
                                      selection: CropSelection(x: 0.2, y: 0.1, width: 0.5, height: 0.7))
        let restored = try JSONDecoder().decode(EditorSettings.self, from: JSONEncoder().encode(settings))
        precondition(restored.selection == settings.selection && restored.mode == .custom)
        precondition(Data(base64Encoded: restored.sourceBase64) == jpeg)

        let editor = CropEditorState(selection: settings.selection)
        let bounds = CGRect(x: 50, y: 20, width: 200, height: 100)
        editor.move(by: CGSize(width: 10000, height: -10000), in: bounds)
        precondition(editor.selection.isValid && editor.selection.x == 0.5 && editor.selection.y == 0)
        editor.dragStart = nil
        editor.resize(corner: 0, to: CGPoint(x: -500, y: -500), in: bounds)
        precondition(editor.selection.isValid && editor.selection.x == 0 && editor.selection.y == 0)
        editor.dragStart = nil
        editor.draw(from: CGPoint(x: 250, y: 120), to: CGPoint(x: -1, y: -1), in: bounds)
        precondition(editor.selection == .full)
        editor.setAspect(viewport: CGSize(width: 517, height: 89), imageSize: CGSize(width: 300, height: 400))
        let target = (517.0 / 89.0) / (300.0 / 400.0)
        func verifyLocked() {
            precondition(editor.selection.isValid)
            precondition(abs(editor.selection.width / editor.selection.height - target) < 0.000001)
        }
        verifyLocked()
        editor.resize(corner: 3, to: CGPoint(x: 10000, y: 10000), in: bounds)
        verifyLocked()
        editor.dragStart = nil
        editor.draw(from: CGPoint(x: 200, y: 90), to: CGPoint(x: 60, y: 25), in: bounds)
        verifyLocked()
        editor.adjust(\.width, to: 0.95); verifyLocked()
        editor.adjust(\.height, to: 0.9); verifyLocked()
        editor.adjust(\.x, to: 1); verifyLocked()
        editor.lockToAd = false
        editor.draw(from: CGPoint(x: 50, y: 20), to: CGPoint(x: 250, y: 120), in: bounds)
        precondition(editor.selection == .full)
        setenv("TALKFRAME_PREVIEW_IMAGE", folder.appendingPathComponent("banner.json").path, 1)
        let model = Model()
        model.mode = .custom; model.cropFill = true
        precondition(model.fillsPreview)
        model.cropFill = false
        precondition(!model.fillsPreview)
        model.mode = .cover
        precondition(model.fillsPreview)
        unsetenv("TALKFRAME_PREVIEW_IMAGE")
        print("PASS measured aspect lock across resize/draw/sliders, free crop, custom fill toggle")
        print("PASS crop pixel position and dimensions, invalid bounds, editor persistence, drag limits")

        if ProcessInfo.processInfo.environment["TALKFRAME_RENDER_EDITOR"] == "1" {
            _ = NSApplication.shared
            let view = NSHostingView(rootView: CropEditor(image: NSImage(data: jpeg)!, selection: settings.selection, viewport: CGSize(width: 517, height: 89),
                                                         onSave: { _ in }, onCancel: {}))
            view.setFrameSize(view.fittingSize)
            let window = NSWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            let snapshot = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: snapshot)
            try snapshot.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("crop-editor.png"))
            print("PASS editor render")
        }
    }
}
