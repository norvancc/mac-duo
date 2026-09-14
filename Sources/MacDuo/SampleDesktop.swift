import AppKit

/// A local, generated calibration desktop. No screen permission is needed to
/// inspect the perspective grid or try settings in the preview.
@MainActor
enum SampleDesktop {
    static let image: CGImage = make()

    private static func make() -> CGImage {
        let width = 1440, height = 936
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        NSGradient(colors: [NSColor(red: 0.045, green: 0.065, blue: 0.13, alpha: 1),
                            NSColor(red: 0.24, green: 0.31, blue: 0.65, alpha: 1),
                            NSColor(red: 0.52, green: 0.55, blue: 0.79, alpha: 1)])!.draw(in: rect, angle: 34)
        for i in 0..<7 {
            let path = NSBezierPath()
            let y = Double(i) * 135 - 270
            path.move(to: .init(x: -100, y: y))
            path.curve(to: .init(x: 1600, y: y + 300), controlPoint1: .init(x: 530, y: y + 1050),
                       controlPoint2: .init(x: 960, y: y - 620))
            path.lineWidth = 80
            NSColor.white.withAlphaComponent(0.035 + Double(i) * 0.009).setStroke()
            path.stroke()
        }
        func text(_ string: String, _ x: Double, _ y: Double, _ size: Double,
                  _ color: NSColor = .white, weight: NSFont.Weight = .regular) {
            (string as NSString).draw(at: .init(x: x, y: y), withAttributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        }
        NSColor.black.withAlphaComponent(0.14).setFill()
        NSRect(x: 0, y: 906, width: width, height: 30).fill()
        text("●   Finder     File     Edit     View     Go     Window     Help", 24, 913, 13, weight: .medium)
        text("100%     Wi-Fi     Mon  9:41", 1194, 913, 13)
        text("A little perspective.", 124, 656, 67, weight: .semibold)
        text("Same desktop. A new point of view.", 129, 613, 25, .white.withAlphaComponent(0.72))
        let window = NSRect(x: 670, y: 218, width: 632, height: 335)
        NSColor(red: 0.075, green: 0.092, blue: 0.16, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: window, xRadius: 18, yRadius: 18).fill()
        for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 692 + i * 23, y: 522, width: 12, height: 12)).fill()
        }
        text("FIELD NOTES", 704, 466, 13, .white.withAlphaComponent(0.45), weight: .semibold)
        text("Stay in the moment.", 704, 415, 32, weight: .medium)
        text("An idea can move with you.", 704, 371, 20, .white.withAlphaComponent(0.7))
        for (i, w) in [440, 390, 454, 260].enumerated() {
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: NSRect(x: 706, y: 335 - i * 23, width: w, height: 7), xRadius: 3, yRadius: 3).fill()
        }
        let dock = NSRect(x: 466, y: 22, width: 508, height: 78)
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: dock, xRadius: 23, yRadius: 23).fill()
        for (i, color) in [NSColor.systemBlue, .systemIndigo, .systemOrange, .systemPink, .systemTeal, .systemPurple, .systemGray].enumerated() {
            let icon = NSRect(x: 482 + i * 70, y: 35, width: 53, height: 53)
            color.setFill()
            NSBezierPath(roundedRect: icon, xRadius: 13, yRadius: 13).fill()
            text(["F", "S", "N", "M", "P", "A", "⚙"][i], icon.minX + 16, icon.minY + 10, 27, weight: .medium)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
}
