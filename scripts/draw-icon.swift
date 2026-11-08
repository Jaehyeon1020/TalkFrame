import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in sizes {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(size) / 512, y: CGFloat(size) / 512)
    func fill(_ path: NSBezierPath, _ color: NSColor) { color.setFill(); path.fill() }
    fill(NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 448, height: 448), xRadius: 104, yRadius: 104),
         NSColor(srgbRed: 0.384, green: 0.318, blue: 0.808, alpha: 1))
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 145, y: 166)); tail.line(to: NSPoint(x: 132, y: 113))
    tail.line(to: NSPoint(x: 207, y: 157)); tail.close()
    fill(tail, .white)
    fill(NSBezierPath(roundedRect: NSRect(x: 104, y: 151, width: 304, height: 224), xRadius: 52, yRadius: 52), .white)
    let picture = NSBezierPath(roundedRect: NSRect(x: 139, y: 188, width: 234, height: 150), xRadius: 20, yRadius: 20)
    fill(picture, NSColor(srgbRed: 0.91, green: 0.90, blue: 1, alpha: 1))
    NSGraphicsContext.saveGraphicsState()
    picture.addClip()
    let mountain = NSBezierPath()
    mountain.move(to: NSPoint(x: 139, y: 188)); mountain.line(to: NSPoint(x: 139, y: 218))
    mountain.line(to: NSPoint(x: 212, y: 287)); mountain.line(to: NSPoint(x: 266, y: 232))
    mountain.line(to: NSPoint(x: 303, y: 270)); mountain.line(to: NSPoint(x: 373, y: 212))
    mountain.line(to: NSPoint(x: 373, y: 188)); mountain.close()
    fill(mountain, NSColor(srgbRed: 0.20, green: 0.69, blue: 0.60, alpha: 1))
    fill(NSBezierPath(ovalIn: NSRect(x: 300, y: 289, width: 29, height: 29)),
         NSColor(srgbRed: 1, green: 0.73, blue: 0.28, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: directory.appendingPathComponent("render-\(size).png"))
}
