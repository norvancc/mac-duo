import AppKit
let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let plate = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
    NSGradient(colors: [NSColor(red: 0.075, green: 0.085, blue: 0.16, alpha: 1),
                        NSColor(red: 0.20, green: 0.24, blue: 0.42, alpha: 1)])!.draw(in: plate, angle: 70)
    let shape = NSBezierPath()
    shape.move(to: NSPoint(x: 236, y: 692))
    shape.line(to: NSPoint(x: 788, y: 692))
    shape.line(to: NSPoint(x: 868, y: 324))
    shape.line(to: NSPoint(x: 156, y: 324))
    shape.close()
    NSGradient(colors: [NSColor(red: 0.27, green: 0.34, blue: 0.75, alpha: 1),
                        NSColor(red: 0.72, green: 0.78, blue: 1, alpha: 1)])!.draw(in: shape, angle: 80)
    NSColor.white.withAlphaComponent(0.7).setStroke()
    shape.lineWidth = 9
    shape.lineJoinStyle = .round
    shape.stroke()
    let hinge = NSBezierPath()
    hinge.move(to: NSPoint(x: 204, y: 240)); hinge.line(to: NSPoint(x: 820, y: 240))
    hinge.lineCapStyle = .round; hinge.lineWidth = 14
    NSColor(red: 0.64, green: 0.71, blue: 1, alpha: 0.6).setStroke()
    hinge.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    if size <= 512 { try data.write(to: URL(fileURLWithPath: "\(folder)/icon_\(size)x\(size).png")) }
    if size >= 32 { try data.write(to: URL(fileURLWithPath: "\(folder)/icon_\(size / 2)x\(size / 2)@2x.png")) }
}
